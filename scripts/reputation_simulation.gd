class_name ReputationSimulation
extends Node

signal reputation_changed(faction_id: StringName, old_value: float, new_value: float, reason: String)
signal standing_changed(faction_id: StringName, old_standing: StringName, new_standing: StringName)
signal incident_reported(incident: Dictionary)
signal run_reputation_reset

@export_category("Run Factions")
@export var faction_definitions: Array[Resource] = []
## How strongly an incident with one faction affects its allies and enemies.
@export_range(0.0, 1.0, 0.05) var diplomatic_spillover_factor := 0.35
@export_range(0, 100, 1) var maximum_incident_history := 40

var reputations: Dictionary = {}
var factions_by_id: Dictionary = {}
var incident_history: Array[Dictionary] = []


func _ready() -> void:
	add_to_group("reputation_simulation")
	_index_factions()
	reset_for_new_run()


func reset_for_new_run() -> void:
	reputations.clear()
	incident_history.clear()
	for faction_id: StringName in factions_by_id:
		var definition: Resource = factions_by_id[faction_id]
		reputations[faction_id] = clampf(float(definition.get("starting_reputation")), -100.0, 100.0)
	run_reputation_reset.emit()


func get_faction_definition(faction_id: StringName) -> Resource:
	return factions_by_id.get(faction_id)


func get_reputation(faction_id: StringName) -> float:
	return float(reputations.get(faction_id, 0.0))


func get_standing(faction_id: StringName) -> StringName:
	var value := get_reputation(faction_id)
	if value <= -60.0:
		return &"HUNTED"
	if value <= -25.0:
		return &"HOSTILE"
	if value < -5.0:
		return &"SUSPICIOUS"
	if value < 25.0:
		return &"NEUTRAL"
	if value < 60.0:
		return &"FAVORED"
	return &"ALLIED"


func get_faction_report(faction_id: StringName) -> Dictionary:
	var definition := get_faction_definition(faction_id)
	if definition == null:
		return {}
	return {
		"faction_id": faction_id,
		"display_name": String(definition.get("display_name")),
		"short_name": String(definition.get("short_name")),
		"description": String(definition.get("description")),
		"signal_color": Color(definition.get("signal_color")),
		"insignia_glyph": String(definition.get("insignia_glyph")),
		"ship_design_language": String(definition.get("ship_design_language")),
		"favored_grid_types": PackedStringArray(definition.get("favored_grid_types")),
		"reputation": get_reputation(faction_id),
		"standing": get_standing(faction_id),
	}


func get_all_faction_reports() -> Array[Dictionary]:
	var reports: Array[Dictionary] = []
	for definition: Resource in faction_definitions:
		if definition == null:
			continue
		var report := get_faction_report(StringName(definition.get("faction_id")))
		if not report.is_empty():
			reports.append(report)
	return reports


func report_incident(
	action_id: StringName,
	target_faction_id: StringName,
	world_position: Vector2,
	witnessed: bool,
	subject_name: String = "",
	source_contact_id: int = -1
) -> Dictionary:
	var direct_change := _incident_reputation_value(action_id)
	var incident := {
		"action_id": action_id,
		"target_faction_id": target_faction_id,
		"world_position": world_position,
		"witnessed": witnessed,
		"subject_name": subject_name,
		"source_contact_id": source_contact_id,
		"direct_change": direct_change if witnessed else 0.0,
		"standing_changes": {},
		"timestamp_msec": Time.get_ticks_msec(),
	}
	if witnessed and factions_by_id.has(target_faction_id) and not is_zero_approx(direct_change):
		var changes: Dictionary = incident["standing_changes"]
		changes[target_faction_id] = _apply_change(
			target_faction_id,
			direct_change,
			_incident_reason(action_id, subject_name)
		)
		var target_definition: Resource = factions_by_id[target_faction_id]
		var relations: Dictionary = target_definition.get("diplomatic_relations")
		for related_id_value: Variant in relations:
			var related_id := StringName(related_id_value)
			if related_id == target_faction_id or not factions_by_id.has(related_id):
				continue
			var relation := clampf(float(relations[related_id_value]), -1.0, 1.0)
			var spillover := direct_change * relation * diplomatic_spillover_factor
			if absf(spillover) < 0.1:
				continue
			changes[related_id] = _apply_change(
				related_id,
				spillover,
				"%s • DIPLOMATIC ECHO" % _incident_reason(action_id, subject_name)
			)
	incident_history.push_front(incident)
	if incident_history.size() > maximum_incident_history:
		incident_history.resize(maximum_incident_history)
	incident_reported.emit(incident)
	return incident


func adjust_reputation(
	faction_id: StringName,
	amount: float,
	reason: String,
	witnessed: bool = true
) -> float:
	if not witnessed:
		return get_reputation(faction_id)
	return float(_apply_change(faction_id, amount, reason).get("new_value", get_reputation(faction_id)))


func _apply_change(faction_id: StringName, amount: float, reason: String) -> Dictionary:
	if not factions_by_id.has(faction_id):
		return {}
	var old_value := get_reputation(faction_id)
	var old_standing := get_standing(faction_id)
	var new_value := clampf(old_value + amount, -100.0, 100.0)
	reputations[faction_id] = new_value
	var new_standing := get_standing(faction_id)
	if not is_equal_approx(old_value, new_value):
		reputation_changed.emit(faction_id, old_value, new_value, reason)
	if old_standing != new_standing:
		standing_changed.emit(faction_id, old_standing, new_standing)
	return {
		"old_value": old_value,
		"new_value": new_value,
		"old_standing": old_standing,
		"new_standing": new_standing,
	}


func _incident_reputation_value(action_id: StringName) -> float:
	match action_id:
		&"TRADE":
			return 2.0
		&"CONTRACT_COMPLETED":
			return 8.0
		&"RESCUE":
			return 14.0
		&"DEFENDED":
			return 18.0
		&"SMUGGLING_AID":
			return 10.0
		&"ASSAULT":
			return -18.0
		&"THEFT":
			return -12.0
		&"SHIP_DESTROYED":
			return -32.0
		&"STATION_DESTROYED":
			return -55.0
	return 0.0


func _incident_reason(action_id: StringName, subject_name: String) -> String:
	var readable := String(action_id).replace("_", " ")
	if subject_name.is_empty():
		return readable
	return "%s • %s" % [readable, subject_name.to_upper()]


func _index_factions() -> void:
	factions_by_id.clear()
	for definition: Resource in faction_definitions:
		if definition == null:
			continue
		var faction_id := StringName(definition.get("faction_id"))
		if faction_id.is_empty():
			continue
		factions_by_id[faction_id] = definition
