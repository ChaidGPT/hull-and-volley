class_name SectorSimulation
extends Node

signal sector_started(sector_id: StringName)
signal objective_changed(objective_id: StringName, completed: bool)
signal sector_completed
signal jump_lock_changed(is_locked: bool)
signal hazard_state_changed(state: Dictionary)
signal safe_radius_changed(radius: float)

@export_category("Sector")
@export var sector_id: StringName = &"FRINGE_01"
@export var sector_center := Vector2.ZERO
## The calm navigable pocket measured from the sector center.
@export_range(500.0, 5000.0, 50.0) var starting_safe_radius := 2100.0
## The jump route stays locked until all required sector objectives are complete.
@export var jump_locked := true
## The current opening sector is a departure sandbox until authored victory objectives arrive.
@export var opening_sector_departure_ready := true

@export_category("Outer Ion Storm")
@export var hazard_enabled := true
## Distance inside the safe pocket at which proximity warnings begin.
@export_range(50.0, 1000.0, 25.0) var warning_distance := 350.0
## Distance into the storm required to reach maximum exposure.
@export_range(100.0, 2000.0, 25.0) var full_exposure_depth := 700.0
## Damage begins immediately after crossing the storm front.
@export_range(0.0, 100.0, 0.5) var minimum_damage_per_second := 8.0
@export_range(1.0, 250.0, 1.0) var maximum_damage_per_second := 34.0
## Environmental damage is applied in short pulses so feedback remains readable.
@export_range(0.05, 1.0, 0.05) var damage_tick_interval := 0.25

@export_category("Encroachment")
## Kept off for the first sector pass. Call start_encroachment() when sector pressure should begin.
@export var encroachment_enabled := false
@export_range(0.0, 600.0, 1.0) var encroachment_delay := 90.0
@export_range(0.0, 100.0, 0.25) var encroachment_units_per_second := 6.0
@export_range(300.0, 5000.0, 50.0) var minimum_safe_radius := 650.0

var current_safe_radius := 0.0
var objectives: Dictionary = {}
var elapsed_time := 0.0
var damage_tick_remaining := 0.0
var last_hazard_state: Dictionary = {}
var ship_simulation: Node


func _ready() -> void:
	add_to_group("sector_simulation")
	current_safe_radius = starting_safe_radius
	ship_simulation = get_tree().get_first_node_in_group("ship_simulation")
	sector_started.emit(sector_id)
	set_physics_process(true)
	if opening_sector_departure_ready:
		call_deferred("_configure_opening_sector_objectives")


func _physics_process(delta: float) -> void:
	elapsed_time += delta
	if (
		encroachment_enabled
		and elapsed_time >= encroachment_delay
		and current_safe_radius > minimum_safe_radius
	):
		current_safe_radius = maxf(
			minimum_safe_radius,
			current_safe_radius - encroachment_units_per_second * delta
		)
		safe_radius_changed.emit(current_safe_radius)

	if not is_instance_valid(ship_simulation):
		ship_simulation = get_tree().get_first_node_in_group("ship_simulation")
	if not is_instance_valid(ship_simulation):
		return

	var state := get_hazard_state(Vector2(ship_simulation.get("ship_position")))
	if _hazard_state_materially_changed(state):
		last_hazard_state = state
		hazard_state_changed.emit(state)

	damage_tick_remaining -= delta
	if not bool(state["inside_hazard"]) or damage_tick_remaining > 0.0:
		return
	damage_tick_remaining = damage_tick_interval
	if bool(ship_simulation.get("is_destroyed")):
		return
	var damage := float(state["damage_per_second"]) * damage_tick_interval
	var outward: Vector2 = sector_center.direction_to(Vector2(ship_simulation.get("ship_position")))
	if ship_simulation.has_method("apply_environmental_damage"):
		ship_simulation.call("apply_environmental_damage", damage, outward)


func get_hazard_state(world_position: Vector2) -> Dictionary:
	var distance := world_position.distance_to(sector_center)
	var signed_distance := distance - current_safe_radius
	var inside_hazard := hazard_enabled and signed_distance > 0.0
	var exposure := 0.0
	var damage_rate := 0.0
	if inside_hazard:
		exposure = clampf(signed_distance / maxf(full_exposure_depth, 1.0), 0.0, 1.0)
		damage_rate = lerpf(
			minimum_damage_per_second,
			maximum_damage_per_second,
			pow(exposure, 1.35)
		)
	var warning_level := 0.0
	if hazard_enabled:
		warning_level = clampf(
			(signed_distance + warning_distance) / maxf(warning_distance, 1.0),
			0.0,
			1.0
		)
	return {
		"sector_id": sector_id,
		"distance": distance,
		"signed_distance": signed_distance,
		"safe_radius": current_safe_radius,
		"inside_hazard": inside_hazard,
		"exposure": exposure,
		"warning_level": warning_level,
		"damage_per_second": damage_rate,
		"encroaching": encroachment_enabled and elapsed_time >= encroachment_delay,
	}


func start_encroachment(delay: float = -1.0) -> void:
	if delay >= 0.0:
		encroachment_delay = delay
		elapsed_time = 0.0
	encroachment_enabled = true


func stop_encroachment() -> void:
	encroachment_enabled = false


func configure_generated_sector(sector: GeneratedSector) -> void:
	if sector == null:
		return
	sector_id = sector.sector_id
	sector_center = Vector2.ZERO
	starting_safe_radius = sector.safe_radius
	current_safe_radius = starting_safe_radius
	hazard_enabled = sector.hazard_enabled
	jump_locked = true
	opening_sector_departure_ready = false
	objectives.clear()
	elapsed_time = 0.0
	damage_tick_remaining = 0.0
	last_hazard_state.clear()
	encroachment_enabled = sector.sector_tags.has("ENCROACHING_STORM")
	sector_started.emit(sector_id)
	jump_lock_changed.emit(true)
	safe_radius_changed.emit(current_safe_radius)


func _configure_opening_sector_objectives() -> void:
	if not opening_sector_departure_ready:
		return
	register_objective(&"RECOVER_GRID", "Recover one loose grid piece")
	register_objective(&"ARM_PROVING_TARGET", "Arm a proving target")
	_set_jump_locked(true)
	var combat_simulation := get_tree().get_first_node_in_group("combat_simulation")
	if not is_instance_valid(combat_simulation):
		return
	if combat_simulation.has_signal("grid_pickup_collected"):
		combat_simulation.connect("grid_pickup_collected", _on_opening_grid_recovered)
	if combat_simulation.has_signal("training_target_armed"):
		combat_simulation.connect("training_target_armed", _on_opening_target_armed)


func _on_opening_grid_recovered(
	_room_type: String,
	_display_name: String,
	_world_position: Vector2
) -> void:
	complete_objective(&"RECOVER_GRID")


func _on_opening_target_armed(_target_id: int) -> void:
	complete_objective(&"ARM_PROVING_TARGET")


func register_objective(
	objective_id: StringName,
	display_name: String,
	required: bool = true
) -> void:
	if objective_id.is_empty():
		return
	objectives[objective_id] = {
		"display_name": display_name,
		"required": required,
		"completed": false,
	}


func complete_objective(objective_id: StringName) -> void:
	if not objectives.has(objective_id):
		return
	var objective: Dictionary = objectives[objective_id]
	if bool(objective["completed"]):
		return
	objective["completed"] = true
	objective_changed.emit(objective_id, true)
	if are_required_objectives_complete():
		_set_jump_locked(false)
		sector_completed.emit()


func are_required_objectives_complete() -> bool:
	var has_required := false
	for objective_value: Variant in objectives.values():
		var objective: Dictionary = objective_value
		if not bool(objective["required"]):
			continue
		has_required = true
		if not bool(objective["completed"]):
			return false
	return has_required


func _set_jump_locked(is_locked: bool) -> void:
	if jump_locked == is_locked:
		return
	jump_locked = is_locked
	jump_lock_changed.emit(jump_locked)


func _hazard_state_materially_changed(state: Dictionary) -> bool:
	if last_hazard_state.is_empty():
		return true
	if bool(last_hazard_state["inside_hazard"]) != bool(state["inside_hazard"]):
		return true
	if absf(float(last_hazard_state["warning_level"]) - float(state["warning_level"])) >= 0.02:
		return true
	if absf(float(last_hazard_state["exposure"]) - float(state["exposure"])) >= 0.02:
		return true
	return absf(float(last_hazard_state["safe_radius"]) - float(state["safe_radius"])) >= 1.0
