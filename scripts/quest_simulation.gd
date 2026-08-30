class_name QuestSimulation
extends Node

signal quest_changed(quest_id: StringName, report: Dictionary)
signal quest_completed(quest_id: StringName, report: Dictionary)
signal run_quests_reset

@export var quest_definitions: Array[Resource] = []

var definitions_by_id: Dictionary = {}
var quest_states: Dictionary = {}


func _ready() -> void:
	add_to_group("quest_simulation")
	_index_definitions()
	reset_for_new_run()
	call_deferred("_connect_world_events")


func reset_for_new_run() -> void:
	quest_states.clear()
	run_quests_reset.emit()


func get_definition(quest_id: StringName) -> Resource:
	return definitions_by_id.get(quest_id)


func get_state(quest_id: StringName) -> StringName:
	return StringName(quest_states.get(quest_id, {}).get("state", &"AVAILABLE"))


func get_report(quest_id: StringName) -> Dictionary:
	var definition := get_definition(quest_id)
	if definition == null:
		return {}
	var state: Dictionary = quest_states.get(quest_id, {})
	return {
		"quest_id": quest_id,
		"display_name": String(definition.get("display_name")),
		"summary": String(definition.get("summary")),
		"objective_label": String(definition.get("objective_label")),
		"objective_count": int(definition.get("objective_count")),
		"progress": int(state.get("progress", 0)),
		"state": StringName(state.get("state", &"AVAILABLE")),
		"giver_contact_id": int(state.get("giver_contact_id", -1)),
		"giver_name": String(state.get("giver_name", "")),
		"objective_pickup_id": int(state.get("objective_pickup_id", -1)),
		"reward_label": String(definition.get("reward_label")),
		"reputation_reward": float(definition.get("reputation_reward")),
		"reward_faction_id": StringName(definition.get("reward_faction_id")),
	}


func get_contact_quest_report(quest: Resource, contact_id: int) -> Dictionary:
	if quest == null:
		return {}
	var report := get_report(StringName(quest.get("quest_id")))
	if report.is_empty():
		return {}
	var giver_id := int(report.get("giver_contact_id", -1))
	if giver_id >= 0 and giver_id != contact_id:
		return {}
	return report


func accept_quest(quest: Resource, giver_contact_id: int, giver_name: String) -> Dictionary:
	if quest == null:
		return {}
	var quest_id := StringName(quest.get("quest_id"))
	if quest_id.is_empty() or get_state(quest_id) != &"AVAILABLE":
		return get_report(quest_id)
	quest_states[quest_id] = {
		"state": &"ACTIVE",
		"progress": 0,
		"giver_contact_id": giver_contact_id,
		"giver_name": giver_name,
		"objective_pickup_id": -1,
	}
	_spawn_contract_objective(quest_id)
	var report := get_report(quest_id)
	quest_changed.emit(quest_id, report)
	return report


func record_event(event_id: StringName, target_id: StringName = &"", amount: int = 1) -> void:
	for quest_id_value: Variant in quest_states.keys():
		var quest_id := StringName(quest_id_value)
		var state: Dictionary = quest_states[quest_id]
		if StringName(state.get("state", &"")) != &"ACTIVE":
			continue
		var definition := get_definition(quest_id)
		if definition == null or StringName(definition.get("objective_event")) != event_id:
			continue
		var required_target := StringName(definition.get("objective_target"))
		if not required_target.is_empty() and required_target != target_id:
			continue
		state["progress"] = mini(
			int(state.get("progress", 0)) + maxi(amount, 0),
			int(definition.get("objective_count"))
		)
		if int(state["progress"]) >= int(definition.get("objective_count")):
			state["state"] = &"READY"
		quest_states[quest_id] = state
		quest_changed.emit(quest_id, get_report(quest_id))


func turn_in_quest(quest_id: StringName, contact_id: int) -> Dictionary:
	if get_state(quest_id) != &"READY":
		return get_report(quest_id)
	var state: Dictionary = quest_states.get(quest_id, {})
	if int(state.get("giver_contact_id", -1)) != contact_id:
		return get_report(quest_id)
	state["state"] = &"COMPLETED"
	quest_states[quest_id] = state
	var definition := get_definition(quest_id)
	var reputation := get_tree().get_first_node_in_group("reputation_simulation")
	if is_instance_valid(reputation) and definition != null:
		reputation.call(
			"adjust_reputation",
			StringName(definition.get("reward_faction_id")),
			float(definition.get("reputation_reward")),
			"CONTRACT COMPLETED • %s" % String(definition.get("display_name")),
			true
		)
	var report := get_report(quest_id)
	quest_changed.emit(quest_id, report)
	quest_completed.emit(quest_id, report)
	return report


func get_active_objective_pickup_ids() -> PackedInt32Array:
	var result := PackedInt32Array()
	for quest_id_value: Variant in quest_states:
		var state: Dictionary = quest_states[quest_id_value]
		if StringName(state.get("state", &"")) != &"ACTIVE":
			continue
		var pickup_id := int(state.get("objective_pickup_id", -1))
		if pickup_id >= 0:
			result.append(pickup_id)
	return result


func get_open_quest_reports() -> Array[Dictionary]:
	var reports: Array[Dictionary] = []
	for quest_id_value: Variant in quest_states:
		var quest_id := StringName(quest_id_value)
		if get_state(quest_id) in [&"ACTIVE", &"READY"]:
			reports.append(get_report(quest_id))
	return reports


func _connect_world_events() -> void:
	var combat := get_tree().get_first_node_in_group("combat_simulation")
	if is_instance_valid(combat) and not combat.is_connected("grid_pickup_collected", _on_grid_pickup_collected):
		combat.connect("grid_pickup_collected", _on_grid_pickup_collected)


func _spawn_contract_objective(quest_id: StringName) -> void:
	var definition := get_definition(quest_id)
	var state: Dictionary = quest_states.get(quest_id, {})
	var pickup_type := StringName(definition.get("spawned_pickup_room_type")) if definition != null else &""
	if pickup_type.is_empty():
		return
	var combat := get_tree().get_first_node_in_group("combat_simulation")
	var player := get_tree().get_first_node_in_group("ship_simulation")
	if not is_instance_valid(combat) or not is_instance_valid(player):
		return
	var giver_contact: Dictionary = combat.call(
		"get_tactical_contact",
		int(state.get("giver_contact_id", -1))
	)
	var origin := Vector2(giver_contact.get("position", player.get("ship_position")))
	var seed_angle := fposmod(float(abs(int(state.get("giver_contact_id", 1)) * 97)), 360.0)
	var outward := Vector2.RIGHT.rotated(deg_to_rad(seed_angle))
	var distance := float(definition.get("spawned_pickup_distance"))
	var spawn_position := origin + outward * distance
	var pickup_id := int(combat.call(
		"spawn_grid_pickup",
		String(pickup_type),
		spawn_position,
		outward.rotated(PI * 0.5) * 4.0
	))
	if pickup_id < 0:
		for template: Resource in player.ship_layout.get("room_types"):
			var fallback_type := String(template.get("type_name"))
			if fallback_type in ["COMMAND", "CREW", "CREW_QUARTERS", "CARGO", "SUPPLY_STORAGE"]:
				continue
			pickup_id = int(combat.call(
				"spawn_grid_pickup",
				fallback_type,
				spawn_position,
				outward.rotated(PI * 0.5) * 4.0
			))
			if pickup_id >= 0:
				break
	state["objective_pickup_id"] = pickup_id
	quest_states[quest_id] = state


func _on_grid_pickup_collected(room_type: String, _display_name: String, _world_position: Vector2) -> void:
	record_event(&"COLLECT_GRID", StringName(room_type.to_upper()), 1)


func _index_definitions() -> void:
	definitions_by_id.clear()
	for definition: Resource in quest_definitions:
		if definition == null:
			continue
		var quest_id := StringName(definition.get("quest_id"))
		if not quest_id.is_empty():
			definitions_by_id[quest_id] = definition
