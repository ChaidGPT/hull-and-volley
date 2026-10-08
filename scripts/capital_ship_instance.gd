class_name CapitalShipInstance
extends Node

const DEFAULT_PHYSICS_SHIP_SCENE := preload("res://scenes/physics_ship_body.tscn")
const SHIP_BUILDER_ANALYZER := preload("res://scripts/ship_builder_analyzer.gd")
const ROOM_STAFFING_RULES := preload("res://scripts/room_staffing_rules.gd")

var ship_id := -1
var faction := 0
var definition: Resource
var layout: Resource
var display_name := "CAPITAL SHIP"
var tactical_tint := Color(1.0, 0.68, 0.68, 1.0)
var tactical_interest_room_types := PackedStringArray(["DOCKING", "WEAPONS", "HANGAR"])
var station_service_tags := PackedStringArray()
var political_faction_id: StringName = &"UNAFFILIATED"
var dialogue_profile: Resource
var stationary := false
var combat_active := true
var maximum_shield := 100.0
var maximum_hull := 100.0
var behavior := 0
var crew_capacity := 0
var minimum_crew := 0
var optimal_crew := 0
var room_power_factors: Dictionary = {}
var structural_state: ShipStructuralState
var physics_body: RigidBody2D


func configure(
		new_ship_id: int,
		new_faction: int,
		new_layout: Resource,
		new_definition: Resource,
		default_behavior: int,
		default_structural_material: Resource,
		default_door_definition: Resource,
		force_stationary: bool = false
) -> void:
	ship_id = new_ship_id
	faction = new_faction
	layout = new_layout
	definition = new_definition
	if layout != null and layout.has_method("ensure_quarter_lattice"):
		layout.call("ensure_quarter_lattice")
	_apply_blueprint_stats()
	if definition != null:
		display_name = String(definition.get("display_name"))
		tactical_tint = definition.get("tactical_tint")
		tactical_interest_room_types = definition.get("tactical_interest_room_types")
		station_service_tags = definition.get("station_service_tags")
		political_faction_id = StringName(definition.get("faction_id"))
		dialogue_profile = definition.get("dialogue_profile") as Resource
		stationary = force_stationary or bool(definition.get("stationary_world_object"))
		combat_active = bool(definition.get("participates_in_combat"))
		behavior = int(definition.get("default_behavior"))
	else:
		display_name = "PLAYER-SHIP COPY"
		stationary = force_stationary
		combat_active = true
		behavior = default_behavior
	structural_state = ShipStructuralState.new()
	structural_state.configure(layout, default_structural_material, default_door_definition)


func _apply_blueprint_stats() -> void:
	if layout == null:
		return
	var stats: Dictionary = SHIP_BUILDER_ANALYZER.analyze(layout)
	maximum_shield = float(stats.get("shield_capacity", 0.0))
	crew_capacity = int(stats.get("crew_capacity", 0))
	minimum_crew = int(stats.get("minimum_crew", 0))
	optimal_crew = int(stats.get("optimal_crew", 0))
	room_power_factors = stats.get("room_power_factors", {}) as Dictionary
	maximum_hull = 0.0
	for room: Resource in layout.get("rooms"):
		maximum_hull += ROOM_STAFFING_RULES.effective_maximum_health(
			room,
			float(room.get("maximum_health"))
		)
	maximum_hull = maxf(maximum_hull, 1.0)


func spawn_physics_body(physics_parent: Node, world_position: Vector2, world_rotation: float) -> RigidBody2D:
	physics_body = DEFAULT_PHYSICS_SHIP_SCENE.instantiate() as RigidBody2D
	physics_body.call("configure_layout", layout)
	physics_body.set_meta("structural_state", structural_state)
	physics_body.set_meta("ship_faction", faction)
	physics_body.set_meta("ship_id", ship_id)
	if is_instance_valid(physics_parent):
		physics_parent.add_child(physics_body)
	physics_body.global_position = world_position
	physics_body.global_rotation = world_rotation
	if stationary:
		physics_body.freeze_mode = RigidBody2D.FREEZE_MODE_STATIC
		physics_body.freeze = true
		physics_body.contact_monitor = false
		physics_body.max_contacts_reported = 0
	return physics_body


func adopt_physics_body(existing_body: RigidBody2D, world_position: Vector2, world_rotation: float) -> void:
	physics_body = existing_body
	if not is_instance_valid(physics_body):
		return
	if physics_body.has_method("configure_layout"):
		physics_body.call("configure_layout", layout)
	physics_body.set_meta("structural_state", structural_state)
	physics_body.set_meta("ship_faction", faction)
	physics_body.set_meta("ship_id", ship_id)
	physics_body.global_position = world_position
	physics_body.global_rotation = world_rotation
	if stationary:
		physics_body.freeze_mode = RigidBody2D.FREEZE_MODE_STATIC
		physics_body.freeze = true
		physics_body.contact_monitor = false
		physics_body.max_contacts_reported = 0


func create_tactical_visual(default_visual_scene: PackedScene) -> Control:
	var visual := default_visual_scene.instantiate() as Control
	if visual.has_method("set_ship_layout"):
		visual.call("set_ship_layout", layout)
	if visual.has_method("set_low_detail_mode"):
		visual.call("set_low_detail_mode", not combat_active)
	if visual.has_method("set_tactical_interest_room_types"):
		visual.call("set_tactical_interest_room_types", tactical_interest_room_types)
	visual.modulate = tactical_tint
	return visual


func make_combat_record(world_position: Vector2, world_rotation: float) -> Dictionary:
	return {
		"id": ship_id,
		"instance": self,
		"position": world_position,
		"previous_position": world_position,
		"rotation": world_rotation,
		"previous_rotation": world_rotation,
		"velocity": Vector2.ZERO,
		"behavior": behavior,
		"stationary": stationary,
		"combat_active": combat_active,
		"player_targetable": combat_active,
		"neutral_contact": not combat_active,
		"transponder_online": true,
		"shield": maximum_shield,
		"maximum_shield": maximum_shield,
		"hull": maximum_hull,
		"maximum_hull": maximum_hull,
		"layout": layout,
		"structural_state": structural_state,
		"display_name": display_name,
		"tactical_tint": tactical_tint,
		"tactical_interest_room_types": tactical_interest_room_types,
		"station_service_tags": station_service_tags,
		"faction_id": political_faction_id,
		"dialogue_profile": dialogue_profile,
		"room_damage": {},
		"crew_capacity": crew_capacity,
		"crew_count": crew_capacity,
		"healthy_crew_count": crew_capacity,
		"minimum_crew": minimum_crew,
		"optimal_crew": optimal_crew,
		"fully_staffed": crew_capacity >= optimal_crew,
		"room_power_factors": room_power_factors,
		"station_operational": true,
		"weapon_cooldowns": {},
		"physics_body": physics_body,
	}


func destroy() -> void:
	if is_instance_valid(physics_body):
		physics_body.queue_free()
	queue_free()
