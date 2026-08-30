class_name ShipSimulation
extends Node

signal hull_depleted
signal docking_state_changed(state: StringName, contact_id: int)
signal docking_completed(contact_id: int)
signal docking_cancelled(contact_id: int)
signal undocking_completed(contact_id: int)
signal module_disabled(room_id: StringName, piece_index: int, ionized: bool)
signal module_detached(piece_key: String, condition: Dictionary, world_position: Vector2, initial_velocity: Vector2)

const CAPITAL_SHIP_INSTANCE_SCENE := preload("res://scenes/ships/capital_ship_instance.tscn")
const SHIP_RESOURCE_ANALYZER := preload("res://scripts/ship_builder_analyzer.gd")
const GRID_GEOMETRY := preload("res://scripts/grid_geometry.gd")
const GRID_INVENTORY_CATALOG := preload("res://scripts/grid_inventory_catalog.gd")
const ROOM_STAFFING_RULES := preload("res://scripts/room_staffing_rules.gd")
const STARTING_CARGO_COLUMNS := 10
const STARTING_CARGO_ROWS := 3

enum TargetingDoctrine {
	WEAPONS_FREE,
	CENTER_MASS,
	MANUAL,
}

@export_category("Ship Layout")
@export var ship_layout: Resource
@export_node_path("RigidBody2D") var physics_body_path: NodePath
## Editor-authored durability, penetration resistance, and atmosphere rules for this hull.
@export var structural_material: Resource
## Editor-authored door motion, safety interlock, and visual settings.
@export var door_definition: Resource

@export_category("Run Inventory")
## Finite loose grid pieces carried into station drydocks. Forge development mode ignores these counts.
@export var starting_grid_piece_inventory: Dictionary = {}

@export_category("Capital Ship Handling")
@export_range(10.0, 250.0, 5.0) var maximum_speed := 48.0
@export_range(1.0, 100.0, 1.0) var acceleration := 3.0
@export_range(1.0, 150.0, 1.0) var braking_acceleration := 7.0
@export_range(0.0, 40.0, 0.25) var lateral_stabilization_acceleration := 8.0
@export_range(1.0, 180.0, 1.0) var turn_speed_degrees := 10.0
@export_range(0.5, 90.0, 0.5) var turn_acceleration_degrees := 8.0
@export_range(0.1, 8.0, 0.1) var steering_response := 1.8
## Forward power retained during broad helm turns so ordinary course changes
## become moving arcs instead of rotate-then-accelerate maneuvers.
@export_range(0.0, 1.0, 0.05) var turn_under_power_throttle := 0.45
## Only targets almost directly behind the ship are allowed to reduce forward
## power all the way to zero for a near in-place reversal.
@export_range(90.0, 180.0, 1.0) var in_place_turn_threshold_degrees := 165.0
@export_range(1.0, 50.0, 1.0) var arrival_radius := 8.0
## Fraction of propulsion output available from healthy thrusters when a reactor/engine room exists but is unmanned.
@export_range(0.0, 1.0, 0.05) var unmanned_engine_propulsion_factor := 0.45
## Emergency thrust available to an unmanned thruster that directly touches a healthy engine/reactor grid.
@export_range(0.0, 1.0, 0.05) var adjacent_unmanned_thruster_factor := 0.25
## Temporary fallback for older test layouts that do not yet include a reactor/engine room.
@export_range(0.0, 1.0, 0.05) var no_engine_propulsion_fallback := 0.65
## Small built-in maneuvering jets keep a damaged or poorly configured hull
## controllable, while installed directional thrusters remain dramatically
## stronger and compound normally.
@export_range(0.0, 0.3, 0.01) var heading_lock_emergency_rcs_factor := 0.08
## Minimum operating level for basic ship rooms when the power grid is offline.
@export_range(0.0, 1.0, 0.05) var basic_room_unpowered_output_factor := 0.35
## Minimum generation level for a healthy reactor/engine room before crew bonuses are applied.
@export_range(0.0, 1.0, 0.05) var unmanned_power_generation_factor := 0.45

@export_category("Layered Damage")
## Once a compartment is already disabled, hits through it hurt ship health more.
@export_range(1.0, 5.0, 0.1) var disabled_section_damage_multiplier := 1.6
## Additional punishment a disabled section must absorb before an outer wall catastrophically opens.
@export_range(1.0, 10.0, 0.25) var breach_overdamage_health_multiplier := 1.5
## Detachable extensions must first lose their full local durability and then
## absorb this many additional health-bars before the mount shears free.
@export_range(1.0, 10.0, 0.25) var extension_detachment_overdamage_multiplier := 2.0

@export_category("Route Plotting")
## Approximate distance between hidden navigation points generated along a bent route segment.
@export_range(4.0, 50.0, 1.0) var curved_route_point_spacing := 16.0
## Maximum number of navigation points generated for one curved segment.
@export_range(4, 64, 1) var maximum_curve_subdivisions := 32
## Distance at which the helm begins steering toward the next hidden curve point. Larger values produce broader, smoother turns.
@export_range(8.0, 100.0, 1.0) var route_lookahead_radius := 28.0
## Portion of a direct course used as its initial forward tangent. This makes
## right-click destinations begin in the ship's current direction before
## bending cleanly toward the target.
@export_range(0.1, 0.8, 0.05) var automatic_course_handle_ratio := 0.45
## Lowest commanded speed while tightening an automatic final-approach turn.
## The helm may brake to this value when the destination lies inside the
## ship's current turning circle.
@export_range(1.0, 20.0, 1.0) var course_capture_speed_floor := 6.0
## Safety margin applied to the theoretical interception speed. Values below
## one make the helm slow early enough to avoid visually circular approaches.
@export_range(0.25, 1.0, 0.05) var course_capture_turn_margin := 0.55
## Beyond this heading error the helm stops following the forward tangent and
## commits directly to a reversal turn.
@export_range(90.0, 170.0, 5.0) var course_capture_reversal_degrees := 115.0
## How often the navigator refreshes the physical trajectory forecast shown
## on the tactical display.
@export_range(0.05, 1.0, 0.05) var trajectory_prediction_refresh_seconds := 0.15
## Fixed simulation step used by the course predictor.
@export_range(0.025, 0.25, 0.025) var trajectory_prediction_step_seconds := 0.075
## Maximum future travel time represented by the course line.
@export_range(10.0, 120.0, 5.0) var trajectory_prediction_horizon_seconds := 90.0
## Time between visible samples on the predicted course.
@export_range(0.1, 1.0, 0.05) var trajectory_prediction_sample_seconds := 0.25

@export_category("Docking Computer")
## Distance outside the final berth where the ship stops and aligns before translating sideways into the clamp.
@export_range(40.0, 300.0, 5.0) var docking_alignment_distance := 140.0
## Extra clearance used by the automatically generated path around a station.
@export_range(20.0, 240.0, 5.0) var docking_route_clearance := 90.0
## Average visual speed of the single continuous autopilot maneuver into a berth.
@export_range(8.0, 60.0, 1.0) var docking_approach_speed := 20.0
## Portion of the berth distance used by the entry and arrival curve handles.
@export_range(0.15, 0.6, 0.05) var docking_curve_handle_ratio := 0.35
## Maximum speed of legacy precision docking translations.
@export_range(2.0, 40.0, 1.0) var docking_final_speed := 18.0
## Position tolerance at which the docking computer engages the berth lock.
@export_range(0.25, 5.0, 0.25) var docking_lock_distance := 1.0
## Rotation tolerance at which the final translation may begin.
@export_range(0.25, 5.0, 0.25) var docking_alignment_degrees := 1.0
## Distance the berth mechanism quickly pushes the ship before returning helm control.
@export_range(30.0, 160.0, 5.0) var undocking_clearance_distance := 75.0
## Duration of the protected clamp-release push.
@export_range(0.25, 1.5, 0.05) var undocking_clearance_duration := 0.55

@export_category("Shield System")
@export var shield_installed := true
@export var shield_enabled := true
@export_range(0.0, 10000.0, 5.0) var maximum_shield := 100.0
@export_range(0.0, 100.0, 0.1) var shield_regeneration_per_second := 1.5
## Capacity projected by each occupied directional shield grid cell.
@export_range(5.0, 1000.0, 5.0) var shield_capacity_per_cell := 60.0
@export_range(5.0, 250.0, 5.0) var omni_shield_capacity_per_bank := 20.0

var ship_position := Vector2.ZERO
var ship_rotation := 0.0
var previous_ship_position := Vector2.ZERO
var previous_ship_rotation := 0.0
var velocity := Vector2.ZERO
var destination := Vector2.ZERO
var has_destination := false
var destination_binding: Dictionary = {}
## Remaining committed waypoints after the ship's current destination.
var route_waypoints: Array[Vector2] = []
var route_waypoint_bindings: Array[Dictionary] = []
## A normal right-click course is continuously replotted from the ship's real
## pose. The visible line and the helm therefore describe the same remaining
## maneuver instead of preserving an ideal curve the physical ship has already
## drifted away from.
var automatic_course_active := false
var automatic_course_goal := Vector2.ZERO
var automatic_course_binding: Dictionary = {}
## A course ordered while clamped is retained through the short berth-clearance
## translation. Further course orders during release replace this one.
var post_undock_course_active := false
var post_undock_course_goal := Vector2.ZERO
var post_undock_course_binding: Dictionary = {}
var predicted_automatic_course: Array[Vector2] = []
var trajectory_prediction_refresh_remaining := 0.0
## Waypoints being plotted while Shift is held. They do not affect movement until committed.
var pending_route_waypoints: Array[Vector2] = []
var pending_route_bindings: Array[Dictionary] = []
## Quadratic curve handles keyed by the index of the segment's ending waypoint.
var pending_route_curve_controls: Dictionary = {}
var is_plotting_route := false
var course_preview_active := false
var course_preview_point := Vector2.ZERO
var course_preview_binding: Dictionary = {}
var course_preview_heading_lock := false
var heading_lock_course_active := false
var heading_lock_rotation := 0.0
var current_shield := 0.0
var shield_bank_maximums: Dictionary = {}
var shield_bank_currents: Dictionary = {}
var shield_bank_rooms: Dictionary = {}
var manual_heading_active := false
var manual_heading_target := Vector2.ZERO
var controller_translation_input := Vector2.ZERO
var controller_turn_input := 0.0
var controller_helm_active := false
var controller_coasting := false
var targeting_doctrine := TargetingDoctrine.WEAPONS_FREE
var manual_weapon_ids: Array[StringName] = []
var manual_target_enemy_id := -1
var manual_target_room_id: StringName = &""

var rooms: Array[Dictionary] = []
var power_network_cache: Dictionary = {}
var power_network_cache_frame := -1
var maximum_ship_health := 0.0
var current_ship_health := 0.0
var room_breach_overdamage: Dictionary = {}
## Local damage and disruption belong to physical pieces, not combined rooms.
## Keys include the room id and authored footprint, so grouped mounts remain
## independently targetable and operational.
var module_damage: Dictionary = {}
var module_ion_disable_remaining: Dictionary = {}
var physics_body: RigidBody2D
var structural_state: ShipStructuralState
var capital_ship_instance: Node
var is_destroyed := false
var hull_depletion_reported := false
var docking_state: StringName = &"IDLE"
var docking_contact_id := -1
var docking_station_body: RigidBody2D
var docking_final_position := Vector2.ZERO
var docking_final_rotation := 0.0
var docking_port_outward := Vector2.ZERO
var docking_release_position := Vector2.ZERO
var docking_curve_start := Vector2.ZERO
var docking_curve_control_a := Vector2.ZERO
var docking_curve_control_b := Vector2.ZERO
var docking_curve_progress := 0.0
var docking_curve_duration := 1.0
var docking_curve_velocity := Vector2.ZERO
var undocking_start_position := Vector2.ZERO
var undocking_progress := 0.0
var grid_piece_inventory: Dictionary = {}
var grid_piece_instances: Array[Dictionary] = []
var next_grid_piece_instance_id := 1


func _ready() -> void:
	add_to_group("ship_simulation")
	if ship_layout != null and ship_layout.has_method("ensure_quarter_lattice"):
		ship_layout.call("ensure_quarter_lattice")
	if ship_layout != null and ship_layout.has_method("capture_core_frame"):
		ship_layout.call("capture_core_frame")
	# Every sortie begins permissively. The player may still change doctrine after launch.
	targeting_doctrine = TargetingDoctrine.WEAPONS_FREE
	manual_weapon_ids.clear()
	manual_target_enemy_id = -1
	manual_target_room_id = &""
	_initialize_grid_piece_inventory()
	physics_body = get_node_or_null(physics_body_path) as RigidBody2D
	_initialize_capital_ship_instance()
	_initialize_rooms_from_layout()
	_initialize_ship_health()
	_initialize_directional_shields()


func _physics_process(delta: float) -> void:
	_update_module_disable_timers(delta)
	previous_ship_position = ship_position
	previous_ship_rotation = ship_rotation
	_pull_physics_state()
	_refresh_bound_course_points()
	_refresh_automatic_course_navigation()
	_update_automatic_course_prediction(delta)
	_update_shield(delta)
	if structural_state != null:
		structural_state.update_atmosphere(delta)

	if _update_docking_sequence(delta):
		return
	if controller_helm_active:
		_update_controller_helm(delta)
		return

	if not has_destination:
		if manual_heading_active:
			var heading_direction := ship_position.direction_to(manual_heading_target)
			var heading_rotation := Vector2.UP.angle_to(heading_direction)
			var heading_difference := angle_difference(ship_rotation, heading_rotation)
			var heading_angular_velocity := clampf(
				heading_difference * steering_response,
				-deg_to_rad(turn_speed_degrees),
				deg_to_rad(turn_speed_degrees)
			)
			if is_instance_valid(physics_body):
				_command_physics_propulsion(0.0, 0.25, heading_angular_velocity)
			else:
				ship_rotation = rotate_toward(ship_rotation, heading_rotation, deg_to_rad(turn_speed_degrees) * delta)
			return
		if is_instance_valid(physics_body):
			if controller_coasting:
				physics_body.call("set_coast_command")
			else:
				_command_physics_propulsion(0.0, 1.0, 0.0)
		else:
			if not controller_coasting:
				var idle_profile := get_propulsion_command_profile()
				velocity = velocity.move_toward(Vector2.ZERO, float(idle_profile["braking_acceleration"]) * delta)
			ship_position += velocity * delta
		return

	var to_destination := destination - ship_position
	var distance_to_destination := to_destination.length()
	var waypoint_capture_radius := route_lookahead_radius
	if docking_state == &"APPROACH":
		# Docking curves contain closely spaced hidden samples. A capture radius
		# that grows modestly with speed prevents a capital ship from circling a
		# sample it has already flown past.
		waypoint_capture_radius = maxf(
			route_lookahead_radius,
			velocity.length() * 1.35
		)
	while (
		not route_waypoints.is_empty()
		and (
			distance_to_destination <= waypoint_capture_radius
			or _route_point_has_been_passed(destination, route_waypoints[0])
		)
	):
		destination = route_waypoints.pop_front()
		destination_binding = route_waypoint_bindings.pop_front() if not route_waypoint_bindings.is_empty() else {}
		to_destination = destination - ship_position
		distance_to_destination = to_destination.length()
	var final_destination := destination
	if automatic_course_active:
		final_destination = _resolved_binding_position(
			automatic_course_binding,
			automatic_course_goal
		)
	if heading_lock_course_active:
		_update_heading_lock_course(final_destination, distance_to_destination, delta)
		return
	var desired_direction := (
		ship_position.direction_to(manual_heading_target)
		if manual_heading_active
		else to_destination.normalized()
	)
	var forward := Vector2.UP.rotated(ship_rotation)
	if automatic_course_active and not manual_heading_active:
		var final_direction := ship_position.direction_to(final_destination)
		if (
			not final_direction.is_zero_approx()
			and absf(forward.angle_to(final_direction))
			>= deg_to_rad(course_capture_reversal_degrees)
		):
			desired_direction = final_direction
	var desired_rotation := Vector2.UP.angle_to(desired_direction)
	var rotation_difference := angle_difference(ship_rotation, desired_rotation)
	var desired_angular_velocity := clampf(
		rotation_difference * steering_response,
		-deg_to_rad(turn_speed_degrees),
		deg_to_rad(turn_speed_degrees)
	)
	if not is_instance_valid(physics_body):
		ship_rotation = rotate_toward(
			ship_rotation,
			desired_rotation,
			deg_to_rad(turn_speed_degrees) * delta
		)

	var heading_alignment := forward.dot(desired_direction)
	var heading_error := absf(rotation_difference)
	var alignment_throttle := clampf((heading_alignment + 0.15) / 1.15, 0.0, 1.0)
	var in_place_threshold := deg_to_rad(in_place_turn_threshold_degrees)
	var turn_power_scale := 1.0 - smoothstep(in_place_threshold, PI, heading_error)
	var turning_throttle_floor := turn_under_power_throttle * turn_power_scale
	var thrust_alignment := maxf(alignment_throttle, turning_throttle_floor)
	var has_more_route := not route_waypoints.is_empty()
	var propulsion_profile := get_propulsion_command_profile()
	var effective_braking := float(propulsion_profile["braking_acceleration"])
	var braking_distance := distance_to_destination
	if automatic_course_active:
		braking_distance = ship_position.distance_to(final_destination)
	var stopping_speed := (
		maximum_speed
		if has_more_route and not automatic_course_active
		else sqrt(
			2.0
			* effective_braking
			* maxf(braking_distance - arrival_radius, 0.0)
		)
	)
	var desired_speed := minf(maximum_speed, stopping_speed)
	if automatic_course_active:
		desired_speed = _turn_limited_capture_speed(
			ship_position,
			ship_rotation,
			final_destination,
			desired_speed
		)
	elif docking_state == &"APPROACH":
		# Authored docking splines must obey the same turning-circle limit as a
		# normal helm order. Without this the ship can overshoot a curve sample
		# and settle into a permanent orbit around it.
		desired_speed = _turn_limited_capture_speed(
			ship_position,
			ship_rotation,
			destination,
			desired_speed
		)
	if is_instance_valid(physics_body):
		var forward_speed := velocity.dot(forward)
		var forward_throttle := thrust_alignment if forward_speed < desired_speed else 0.0
		var brake_reference_speed := (
			desired_speed
			if automatic_course_active
			else stopping_speed
		)
		var brake_throttle := (
			1.0
			if absf(forward_speed) > brake_reference_speed + 0.5
			else 0.0
		)
		if heading_error > PI * 0.5 and absf(forward_speed) > maximum_speed * 0.7:
			brake_throttle = maxf(brake_throttle, 0.15)
		_command_physics_propulsion(forward_throttle, brake_throttle, desired_angular_velocity, propulsion_profile)
	else:
		var desired_velocity := forward * desired_speed * thrust_alignment
		var velocity_change_rate := float(propulsion_profile["forward_acceleration"])
		if desired_velocity.length() < velocity.length():
			velocity_change_rate = effective_braking
		velocity = velocity.move_toward(desired_velocity, velocity_change_rate * delta)
		ship_position += velocity * delta

	if distance_to_destination <= arrival_radius and velocity.length() <= 2.0:
		velocity = Vector2.ZERO
		has_destination = false
		heading_lock_course_active = false
		destination_binding.clear()
		automatic_course_active = false
		automatic_course_binding.clear()
		predicted_automatic_course.clear()
		if is_instance_valid(physics_body):
			_command_physics_propulsion(0.0, 1.0, 0.0)


func _update_heading_lock_course(
	final_destination: Vector2,
	distance_to_destination: float,
	delta: float
) -> void:
	var to_destination := final_destination - ship_position
	var profile := get_propulsion_command_profile()
	var desired_angular_velocity := clampf(
		angle_difference(ship_rotation, heading_lock_rotation) * steering_response,
		-deg_to_rad(turn_speed_degrees),
		deg_to_rad(turn_speed_degrees)
	)
	if to_destination.length_squared() <= 0.001:
		to_destination = Vector2.UP.rotated(heading_lock_rotation)
	var travel_direction := to_destination.normalized()
	var local_travel_direction := travel_direction.rotated(-ship_rotation)
	var local_braking_direction := -local_travel_direction
	if velocity.length_squared() > 0.01:
		local_braking_direction = -velocity.normalized().rotated(-ship_rotation)
	var effective_braking := maxf(
		_translation_acceleration_for_local_direction(profile, local_braking_direction),
		0.1
	)
	var stopping_speed := sqrt(
		2.0
		* effective_braking
		* maxf(distance_to_destination - arrival_radius, 0.0)
	)
	var desired_speed := minf(maximum_speed, stopping_speed)
	var desired_velocity := travel_direction * desired_speed
	if is_instance_valid(physics_body):
		_command_physics_translation(
			desired_velocity,
			desired_angular_velocity,
			profile,
			-local_travel_direction
		)
	else:
		var velocity_error := desired_velocity - velocity
		var local_velocity_error := velocity_error.rotated(-ship_rotation)
		var available_acceleration := _translation_acceleration_for_local_direction(
			profile,
			local_velocity_error.normalized()
		)
		velocity = velocity.move_toward(
			desired_velocity,
			available_acceleration * delta
		)
		ship_position += velocity * delta
		ship_rotation = rotate_toward(
			ship_rotation,
			heading_lock_rotation,
			deg_to_rad(turn_speed_degrees) * delta
		)
	if distance_to_destination <= arrival_radius and velocity.length() <= 2.0:
		velocity = Vector2.ZERO
		has_destination = false
		heading_lock_course_active = false
		destination_binding.clear()
		if is_instance_valid(physics_body):
			_command_physics_propulsion(0.0, 1.0, 0.0)


func _translation_acceleration_for_local_direction(
	profile: Dictionary,
	local_direction: Vector2
) -> float:
	if local_direction.is_zero_approx():
		return 0.0
	var direction := local_direction.normalized()
	var horizontal := (
		float(profile["translation_starboard_acceleration"])
		if direction.x >= 0.0
		else float(profile["translation_port_acceleration"])
	)
	var vertical := (
		float(profile["translation_reverse_acceleration"])
		if direction.y >= 0.0
		else float(profile["translation_forward_acceleration"])
	)
	return absf(direction.x) * horizontal + absf(direction.y) * vertical


func _route_point_has_been_passed(
	current_point: Vector2,
	next_point: Vector2
) -> bool:
	var outgoing_segment := next_point - current_point
	if outgoing_segment.length_squared() <= 0.001:
		return true
	# Once the ship crosses the plane through the current sample, perpendicular
	# to the outgoing path, steering back toward that sample would only create
	# a loop. Advance the pure-pursuit target along the route instead.
	return (ship_position - current_point).dot(outgoing_segment) >= 0.0


func set_course(world_destination: Vector2, target_binding: Dictionary = {}) -> void:
	controller_coasting = false
	if docking_state in [&"DOCKED", &"UNDOCK"]:
		post_undock_course_active = true
		post_undock_course_goal = world_destination
		post_undock_course_binding = target_binding.duplicate(true)
		if docking_state == &"DOCKED" and not begin_undocking():
			post_undock_course_active = false
			post_undock_course_binding.clear()
		return
	if not _cancel_docking_approach_for_manual_course():
		return
	route_waypoints.clear()
	route_waypoint_bindings.clear()
	pending_route_waypoints.clear()
	pending_route_bindings.clear()
	is_plotting_route = false
	course_preview_active = false
	course_preview_heading_lock = false
	heading_lock_course_active = false
	automatic_course_active = true
	automatic_course_goal = world_destination
	automatic_course_binding = target_binding.duplicate(true)
	trajectory_prediction_refresh_remaining = 0.0
	_refresh_automatic_course_navigation()
	has_destination = true


## Shows a temporary course marker while right click is held. The real course is not committed until release.
func begin_course_preview(
	world_destination: Vector2,
	target_binding: Dictionary = {},
	preserve_heading := false
) -> void:
	if not _cancel_docking_approach_for_manual_course():
		return
	course_preview_active = true
	course_preview_point = world_destination
	course_preview_binding = target_binding.duplicate(true)
	course_preview_heading_lock = preserve_heading


func update_course_preview(world_destination: Vector2, target_binding: Dictionary = {}) -> void:
	if not course_preview_active:
		return
	course_preview_point = world_destination
	course_preview_binding = target_binding.duplicate(true)


func commit_course_preview() -> void:
	if not course_preview_active:
		return
	var chosen_destination := course_preview_point
	var chosen_binding := course_preview_binding.duplicate(true)
	var preserve_heading := course_preview_heading_lock
	course_preview_active = false
	course_preview_binding.clear()
	course_preview_heading_lock = false
	if preserve_heading:
		set_heading_lock_course(chosen_destination, chosen_binding)
	else:
		set_course(chosen_destination, chosen_binding)


func cancel_course_preview() -> void:
	course_preview_active = false
	course_preview_binding.clear()
	course_preview_heading_lock = false


func set_heading_lock_course(world_destination: Vector2, target_binding: Dictionary = {}) -> void:
	controller_coasting = false
	if not _cancel_docking_approach_for_manual_course():
		return
	route_waypoints.clear()
	route_waypoint_bindings.clear()
	pending_route_waypoints.clear()
	pending_route_bindings.clear()
	pending_route_curve_controls.clear()
	is_plotting_route = false
	course_preview_active = false
	course_preview_binding.clear()
	course_preview_heading_lock = false
	automatic_course_active = false
	automatic_course_binding.clear()
	predicted_automatic_course.clear()
	destination = world_destination
	destination_binding = target_binding.duplicate(true)
	heading_lock_rotation = ship_rotation
	heading_lock_course_active = true
	has_destination = true


## Temporarily overrides course-facing while right click is held. Normal capital-ship turn physics still apply.
func set_manual_heading_target(world_target: Vector2) -> void:
	if docking_state != &"IDLE":
		return
	controller_coasting = false
	manual_heading_target = world_target
	manual_heading_active = true


func clear_manual_heading() -> void:
	manual_heading_active = false


func set_controller_helm_input(translation_input: Vector2, turn_input: float) -> void:
	var next_translation := translation_input.limit_length(1.0)
	var next_turn := clampf(turn_input, -1.0, 1.0)
	var next_active := next_translation.length_squared() > 0.0001 or absf(next_turn) > 0.001
	if next_active:
		controller_coasting = false
	elif controller_helm_active:
		controller_coasting = true
	if next_active and not controller_helm_active:
		_cancel_active_course_for_controller()
	controller_translation_input = next_translation
	controller_turn_input = next_turn
	controller_helm_active = next_active


func controller_hold_position() -> void:
	_cancel_active_course_for_controller()
	controller_translation_input = Vector2.ZERO
	controller_turn_input = 0.0
	controller_helm_active = false
	controller_coasting = false
	velocity = Vector2.ZERO
	if is_instance_valid(physics_body):
		physics_body.linear_velocity = Vector2.ZERO
		physics_body.angular_velocity = 0.0
		_command_physics_propulsion(0.0, 1.0, 0.0)


func _cancel_active_course_for_controller() -> void:
	if not _cancel_docking_approach_for_manual_course():
		return
	has_destination = false
	destination_binding.clear()
	route_waypoints.clear()
	route_waypoint_bindings.clear()
	automatic_course_active = false
	automatic_course_binding.clear()
	predicted_automatic_course.clear()
	pending_route_waypoints.clear()
	pending_route_bindings.clear()
	pending_route_curve_controls.clear()
	is_plotting_route = false
	course_preview_active = false
	course_preview_binding.clear()
	heading_lock_course_active = false
	manual_heading_active = false


func _cancel_docking_approach_for_manual_course() -> bool:
	if docking_state == &"IDLE":
		return true
	if docking_state not in [&"APPROACH", &"ALIGN", &"FINAL"]:
		return false
	var cancelled_contact_id := docking_contact_id
	has_destination = false
	heading_lock_course_active = false
	destination_binding.clear()
	route_waypoints.clear()
	route_waypoint_bindings.clear()
	automatic_course_active = false
	automatic_course_binding.clear()
	predicted_automatic_course.clear()
	pending_route_waypoints.clear()
	pending_route_bindings.clear()
	pending_route_curve_controls.clear()
	is_plotting_route = false
	docking_state = &"IDLE"
	docking_contact_id = -1
	docking_station_body = null
	docking_port_outward = Vector2.ZERO
	docking_curve_progress = 0.0
	if is_instance_valid(physics_body):
		physics_body.freeze = false
		physics_body.sleeping = false
		physics_body.linear_velocity = docking_curve_velocity
		physics_body.angular_velocity = 0.0
	docking_state_changed.emit(docking_state, cancelled_contact_id)
	docking_cancelled.emit(cancelled_contact_id)
	return true


## Starts a route plan. Any active destination and queued route are copied first,
## allowing Shift-waypoints to extend a normal right-click course as one chain.
func begin_route_plotting() -> void:
	if not _cancel_docking_approach_for_manual_course():
		return
	course_preview_active = false
	course_preview_binding.clear()
	course_preview_heading_lock = false
	pending_route_waypoints = get_active_route_points()
	pending_route_bindings.clear()
	if has_destination:
		pending_route_bindings.append(destination_binding.duplicate(true))
		for binding: Dictionary in route_waypoint_bindings:
			pending_route_bindings.append(binding.duplicate(true))
	pending_route_curve_controls.clear()
	is_plotting_route = true


## Adds one waypoint to the route currently being plotted.
func add_plotted_waypoint(world_waypoint: Vector2, target_binding: Dictionary = {}) -> void:
	if not is_plotting_route:
		begin_route_plotting()
	pending_route_waypoints.append(world_waypoint)
	pending_route_bindings.append(target_binding.duplicate(true))


## Bends the newest route segment toward this world-space control point.
func set_last_route_curve_control(world_control_point: Vector2) -> void:
	if pending_route_waypoints.size() < 2:
		return
	pending_route_curve_controls[pending_route_waypoints.size() - 1] = world_control_point


## Replaces the active course with the plotted route and begins following it.
func commit_plotted_route() -> void:
	if not is_plotting_route:
		return
	is_plotting_route = false
	if pending_route_waypoints.is_empty():
		return
	controller_coasting = false
	var route_data := _build_pending_route_navigation()
	automatic_course_active = false
	automatic_course_binding.clear()
	predicted_automatic_course.clear()
	route_waypoints = route_data["points"]
	route_waypoint_bindings = route_data["bindings"]
	pending_route_waypoints.clear()
	pending_route_bindings.clear()
	pending_route_curve_controls.clear()
	destination = route_waypoints.pop_front()
	destination_binding = route_waypoint_bindings.pop_front() if not route_waypoint_bindings.is_empty() else {}
	has_destination = true


## Discards an unfinished route without changing the ship's active course.
func cancel_plotted_route() -> void:
	pending_route_waypoints.clear()
	pending_route_bindings.clear()
	pending_route_curve_controls.clear()
	is_plotting_route = false


func get_active_route_points() -> Array[Vector2]:
	var points: Array[Vector2] = []
	if has_destination:
		points.append(destination)
		points.append_array(route_waypoints)
	return points


## The tactical course line uses a physical forecast for normal helm orders.
## Authored multi-point and docking routes retain their explicit geometry.
func get_display_route_points() -> Array[Vector2]:
	if automatic_course_active and not predicted_automatic_course.is_empty():
		return predicted_automatic_course.duplicate()
	return get_active_route_points()


func _refresh_automatic_course_navigation() -> void:
	if not automatic_course_active:
		return
	var navigation := _build_automatic_turn_navigation(
		automatic_course_goal,
		automatic_course_binding
	)
	var refreshed_points: Array[Vector2] = navigation["points"]
	var refreshed_bindings: Array[Dictionary] = navigation["bindings"]
	if refreshed_points.is_empty():
		destination = _resolved_binding_position(
			automatic_course_binding,
			automatic_course_goal
		)
		destination_binding = automatic_course_binding.duplicate(true)
		route_waypoints.clear()
		route_waypoint_bindings.clear()
		return
	destination = refreshed_points.pop_front()
	destination_binding = (
		refreshed_bindings.pop_front()
		if not refreshed_bindings.is_empty()
		else {}
	)
	route_waypoints = refreshed_points
	route_waypoint_bindings = refreshed_bindings


func _update_automatic_course_prediction(delta: float) -> void:
	if not automatic_course_active or not has_destination:
		predicted_automatic_course.clear()
		trajectory_prediction_refresh_remaining = 0.0
		return
	trajectory_prediction_refresh_remaining -= delta
	if trajectory_prediction_refresh_remaining > 0.0:
		return
	trajectory_prediction_refresh_remaining = trajectory_prediction_refresh_seconds
	predicted_automatic_course = _predict_automatic_course_trajectory()


func _predict_automatic_course_trajectory() -> Array[Vector2]:
	var forecast: Array[Vector2] = []
	var predicted_position := ship_position
	var predicted_rotation := ship_rotation
	var predicted_velocity := velocity
	var predicted_angular_velocity := (
		physics_body.angular_velocity
		if is_instance_valid(physics_body)
		else 0.0
	)
	var final_destination := _resolved_binding_position(
		automatic_course_binding,
		automatic_course_goal
	)
	var propulsion_profile := get_propulsion_command_profile()
	var forward_acceleration := float(propulsion_profile["forward_acceleration"])
	var effective_braking := float(propulsion_profile["braking_acceleration"])
	var angular_acceleration_limit := float(propulsion_profile["angular_acceleration"])
	var lateral_acceleration_limit := float(propulsion_profile["lateral_acceleration"])
	var prediction_step := maxf(trajectory_prediction_step_seconds, 0.001)
	var maximum_steps := ceili(
		trajectory_prediction_horizon_seconds / prediction_step
	)
	var sample_elapsed := 0.0

	var flight_assist := _physics_body_bool(&"flight_assist_enabled", true)
	var lateral_velocity_damping := _physics_body_float(&"lateral_velocity_damping", 8.0)
	var turning_lateral_velocity_damping := _physics_body_float(
		&"turning_lateral_velocity_damping",
		5.0
	)
	var idle_forward_velocity_damping := _physics_body_float(
		&"idle_forward_velocity_damping",
		1.4
	)
	var angular_velocity_damping := _physics_body_float(
		&"angular_velocity_damping",
		7.0
	)
	var lateral_stabilization_response := _physics_body_float(
		&"lateral_stabilization_response",
		4.0
	)
	var forward_drag_response := _physics_body_float(
		&"forward_drag_response",
		0.35
	)
	var turn_slide_drag_response := _physics_body_float(
		&"turn_slide_drag_response",
		2.0
	)
	var angular_velocity_response := _physics_body_float(
		&"angular_velocity_response",
		2.5
	)

	for _step_index: int in range(maximum_steps):
		var remaining_distance := predicted_position.distance_to(final_destination)
		if remaining_distance <= arrival_radius and predicted_velocity.length() <= 2.0:
			forecast.append(final_destination)
			break

		var steering_target := _automatic_steering_target_for_pose(
			predicted_position,
			predicted_rotation,
			final_destination
		)
		var desired_direction := predicted_position.direction_to(steering_target)
		if desired_direction.is_zero_approx():
			desired_direction = predicted_position.direction_to(final_destination)
		if desired_direction.is_zero_approx():
			desired_direction = Vector2.UP.rotated(predicted_rotation)
		var forward := Vector2.UP.rotated(predicted_rotation)
		var final_direction := predicted_position.direction_to(
			final_destination
		)
		if (
			not final_direction.is_zero_approx()
			and absf(forward.angle_to(final_direction))
			>= deg_to_rad(course_capture_reversal_degrees)
		):
			desired_direction = final_direction
		var desired_rotation := Vector2.UP.angle_to(desired_direction)
		var rotation_difference := angle_difference(
			predicted_rotation,
			desired_rotation
		)
		var desired_angular_velocity := clampf(
			rotation_difference * steering_response,
			-deg_to_rad(turn_speed_degrees),
			deg_to_rad(turn_speed_degrees)
		)
		var starboard := forward.orthogonal()
		var heading_alignment := forward.dot(desired_direction)
		var heading_error := absf(rotation_difference)
		var alignment_throttle := clampf(
			(heading_alignment + 0.15) / 1.15,
			0.0,
			1.0
		)
		var in_place_threshold := deg_to_rad(
			in_place_turn_threshold_degrees
		)
		var turn_power_scale := 1.0 - smoothstep(
			in_place_threshold,
			PI,
			heading_error
		)
		var thrust_alignment := maxf(
			alignment_throttle,
			turn_under_power_throttle * turn_power_scale
		)
		var stopping_speed := sqrt(
			2.0
			* effective_braking
			* maxf(remaining_distance - arrival_radius, 0.0)
		)
		var desired_speed := minf(maximum_speed, stopping_speed)
		desired_speed = _turn_limited_capture_speed(
			predicted_position,
			predicted_rotation,
			final_destination,
			desired_speed
		)
		var forward_speed := predicted_velocity.dot(forward)
		var forward_throttle := (
			thrust_alignment
			if forward_speed < desired_speed
			else 0.0
		)
		var brake_throttle := (
			1.0
			if absf(forward_speed) > desired_speed + 0.5
			else 0.0
		)
		if (
			heading_error > PI * 0.5
			and absf(forward_speed) > maximum_speed * 0.7
		):
			brake_throttle = maxf(brake_throttle, 0.15)

		var lateral_speed := predicted_velocity.dot(starboard)
		if flight_assist:
			var lateral_damping := lateral_velocity_damping
			if absf(desired_angular_velocity) > 0.001:
				var turn_amount := minf(
					absf(desired_angular_velocity) / deg_to_rad(20.0),
					1.0
				)
				lateral_damping += (
					turning_lateral_velocity_damping * turn_amount
				)
			if lateral_damping > 0.0 and absf(lateral_speed) > 0.001:
				var lateral_keep := exp(-lateral_damping * prediction_step)
				predicted_velocity += (
					starboard
					* (lateral_speed * lateral_keep - lateral_speed)
				)
			if (
				forward_throttle <= 0.01
				and idle_forward_velocity_damping > 0.0
				and absf(forward_speed) > 0.001
			):
				var forward_keep := exp(
					-idle_forward_velocity_damping * prediction_step
				)
				predicted_velocity += (
					forward
					* (forward_speed * forward_keep - forward_speed)
				)
			if angular_velocity_damping > 0.0:
				var angular_keep := exp(
					-angular_velocity_damping * prediction_step
				)
				predicted_angular_velocity = (
					desired_angular_velocity
					+ (
						predicted_angular_velocity
						- desired_angular_velocity
					)
					* angular_keep
				)

		forward_speed = predicted_velocity.dot(forward)
		lateral_speed = predicted_velocity.dot(starboard)
		if forward_throttle > 0.0:
			predicted_velocity += (
				forward
				* forward_acceleration
				* forward_throttle
				* prediction_step
			)
		if (
			brake_throttle > 0.0
			and absf(forward_speed) > 0.001
		):
			predicted_velocity += (
				-forward * signf(forward_speed)
				* effective_braking
				* brake_throttle
				* prediction_step
			)
		var lateral_acceleration := clampf(
			-lateral_speed * lateral_stabilization_response,
			-lateral_acceleration_limit,
			lateral_acceleration_limit
		)
		predicted_velocity += (
			starboard * lateral_acceleration * prediction_step
		)
		if forward_throttle <= 0.01 and absf(forward_speed) > 0.001:
			predicted_velocity += (
				forward
				* -forward_speed
				* forward_drag_response
				* prediction_step
			)
		if (
			absf(lateral_speed) > 0.001
			and absf(desired_angular_velocity) > 0.001
		):
			var turn_slide_drag := minf(
				absf(desired_angular_velocity) / deg_to_rad(20.0),
				1.0
			)
			predicted_velocity += (
				starboard
				* -lateral_speed
				* turn_slide_drag_response
				* turn_slide_drag
				* prediction_step
			)
		var angular_velocity_error := (
			desired_angular_velocity - predicted_angular_velocity
		)
		var predicted_angular_acceleration := clampf(
			angular_velocity_error * angular_velocity_response,
			-angular_acceleration_limit,
			angular_acceleration_limit
		)
		predicted_angular_velocity += (
			predicted_angular_acceleration * prediction_step
		)
		predicted_position += predicted_velocity * prediction_step
		predicted_rotation += predicted_angular_velocity * prediction_step

		sample_elapsed += prediction_step
		if sample_elapsed >= trajectory_prediction_sample_seconds:
			forecast.append(predicted_position)
			sample_elapsed = 0.0
	return forecast


func _automatic_steering_target_for_pose(
	start_position: Vector2,
	start_rotation: float,
	final_destination: Vector2
) -> Vector2:
	var distance := start_position.distance_to(final_destination)
	if distance <= maxf(arrival_radius, 0.001):
		return final_destination
	var control := _automatic_curve_control_for_pose(
		start_position,
		start_rotation,
		final_destination
	)
	var estimated_length := (
		start_position.distance_to(control)
		+ control.distance_to(final_destination)
	)
	var subdivisions := clampi(
		ceili(estimated_length / curved_route_point_spacing),
		4,
		maximum_curve_subdivisions
	)
	for step: int in range(1, subdivisions + 1):
		var weight := float(step) / float(subdivisions)
		var point := _quadratic_bezier(
			start_position,
			control,
			final_destination,
			weight
		)
		if start_position.distance_to(point) > route_lookahead_radius:
			return point
	return final_destination


func _turn_limited_capture_speed(
	current_position: Vector2,
	current_rotation: float,
	final_destination: Vector2,
	unrestricted_speed: float
) -> float:
	var displacement := final_destination - current_position
	var distance := displacement.length()
	if distance <= 0.001:
		return 0.0
	var forward := Vector2.UP.rotated(current_rotation)
	var final_direction := displacement / distance
	var final_heading_error := absf(forward.angle_to(final_direction))
	var turn_demand := maxf(
		absf(sin(final_heading_error)),
		smoothstep(PI * 0.5, PI, final_heading_error)
	)
	if turn_demand <= 0.08:
		return unrestricted_speed
	# Pure-pursuit geometry: curvature needed to intercept a point is
	# approximately 2*sin(error)/distance. Limiting speed to turn-rate /
	# curvature guarantees the destination will eventually fall outside the
	# ship's turning circle instead of becoming the center of an orbit.
	var maximum_turn_rate := deg_to_rad(turn_speed_degrees)
	var intercept_speed := (
		maximum_turn_rate
		* distance
		/ maxf(2.0 * turn_demand, 0.001)
		* course_capture_turn_margin
	)
	return minf(
		unrestricted_speed,
		maxf(course_capture_speed_floor, intercept_speed)
	)


func _physics_body_float(property_name: StringName, fallback: float) -> float:
	if not is_instance_valid(physics_body):
		return fallback
	var value: Variant = physics_body.get(property_name)
	return float(value) if value != null else fallback


func _physics_body_bool(property_name: StringName, fallback: bool) -> bool:
	if not is_instance_valid(physics_body):
		return fallback
	var value: Variant = physics_body.get(property_name)
	return bool(value) if value != null else fallback


func get_course_preview_navigation_points() -> Array[Vector2]:
	if not course_preview_active:
		return []
	return _build_automatic_turn_navigation(
		course_preview_point,
		course_preview_binding
	)["points"]


## Returns the smooth visual/navigation path generated from the currently plotted waypoint anchors.
func get_pending_route_navigation_points() -> Array[Vector2]:
	return _build_pending_route_navigation()["points"]


func get_pending_route_anchor_points() -> Array[Vector2]:
	var anchors: Array[Vector2] = []
	for index: int in range(pending_route_waypoints.size()):
		anchors.append(_resolved_binding_position(_pending_binding(index), pending_route_waypoints[index]))
	return anchors


func get_pending_route_marker_points() -> Array[Vector2]:
	var markers: Array[Vector2] = []
	for index: int in range(pending_route_waypoints.size()):
		var binding := _pending_binding(index)
		if _binding_has_object_destination(binding):
			continue
		markers.append(_resolved_binding_position(binding, pending_route_waypoints[index]))
	return markers


func course_preview_has_object_destination() -> bool:
	return course_preview_active and _binding_has_object_destination(course_preview_binding)


func active_route_ends_at_object_destination() -> bool:
	if not has_destination:
		return false
	var final_binding := route_waypoint_bindings[-1] if not route_waypoint_bindings.is_empty() else destination_binding
	return _binding_has_object_destination(final_binding)


func pending_route_ends_at_object_destination() -> bool:
	return (
		not pending_route_bindings.is_empty()
		and _binding_has_object_destination(pending_route_bindings[-1])
	)


func _binding_has_object_destination(binding: Dictionary) -> bool:
	if binding.is_empty():
		return false
	match String(binding.get("kind", "")):
		"grid_pickup":
			return true
		"route_sample":
			var weight := clampf(float(binding.get("weight", 0.0)), 0.0, 1.0)
			if weight >= 0.999:
				return _binding_has_object_destination(binding.get("end_binding", {}))
			if weight <= 0.001:
				return _binding_has_object_destination(binding.get("start_binding", {}))
			return (
				_binding_has_object_destination(binding.get("start_binding", {}))
				or _binding_has_object_destination(binding.get("end_binding", {}))
			)
	return false


func _build_pending_route_navigation() -> Dictionary:
	var navigation_points: Array[Vector2] = []
	var navigation_bindings: Array[Dictionary] = []
	if pending_route_waypoints.is_empty():
		return {"points": navigation_points, "bindings": navigation_bindings}
	var anchors := get_pending_route_anchor_points()
	var curve_points: Array[Vector2] = [ship_position]
	curve_points.append_array(anchors)
	for end_index: int in range(anchors.size()):
		var segment_start := curve_points[end_index]
		var segment_end := curve_points[end_index + 1]
		var start_binding := _pending_binding(end_index - 1)
		var end_binding := _pending_binding(end_index)
		if pending_route_curve_controls.has(end_index):
			var control: Vector2 = pending_route_curve_controls[end_index]
			var estimated_length := segment_start.distance_to(control) + control.distance_to(segment_end)
			var subdivisions := clampi(ceili(estimated_length / curved_route_point_spacing), 4, maximum_curve_subdivisions)
			for step: int in range(1, subdivisions + 1):
				var t := float(step) / float(subdivisions)
				var point := _quadratic_bezier(segment_start, control, segment_end, t)
				navigation_points.append(point)
				navigation_bindings.append(_route_sample_binding(
					point,
					segment_start,
					segment_end,
					start_binding,
					end_binding,
					t
				))
		else:
			var previous := curve_points[maxi(end_index - 1, 0)]
			var following := curve_points[mini(end_index + 2, curve_points.size() - 1)]
			var estimated_length := segment_start.distance_to(segment_end)
			var subdivisions := clampi(ceili(estimated_length / curved_route_point_spacing), 4, maximum_curve_subdivisions)
			for step: int in range(1, subdivisions + 1):
				var t := float(step) / float(subdivisions)
				var point := _catmull_rom(previous, segment_start, segment_end, following, t)
				navigation_points.append(point)
				navigation_bindings.append(_route_sample_binding(
					point,
					segment_start,
					segment_end,
					start_binding,
					end_binding,
					t
				))
	return {"points": navigation_points, "bindings": navigation_bindings}


func _build_automatic_turn_navigation(
	world_destination: Vector2,
	target_binding: Dictionary = {}
) -> Dictionary:
	var navigation_points: Array[Vector2] = []
	var navigation_bindings: Array[Dictionary] = []
	var resolved_destination := _resolved_binding_position(target_binding, world_destination)
	var displacement := resolved_destination - ship_position
	var distance := displacement.length()
	if distance <= maxf(arrival_radius, 0.001):
		navigation_points.append(resolved_destination)
		navigation_bindings.append(target_binding.duplicate(true))
		return {"points": navigation_points, "bindings": navigation_bindings}

	var control := _automatic_curve_control_for_pose(
		ship_position,
		ship_rotation,
		resolved_destination
	)

	var estimated_length := ship_position.distance_to(control) + control.distance_to(resolved_destination)
	var subdivisions := clampi(
		ceili(estimated_length / curved_route_point_spacing),
		4,
		maximum_curve_subdivisions
	)
	for step: int in range(1, subdivisions + 1):
		var weight := float(step) / float(subdivisions)
		var point := _quadratic_bezier(
			ship_position,
			control,
			resolved_destination,
			weight
		)
		navigation_points.append(point)
		navigation_bindings.append(_route_sample_binding(
			point,
			ship_position,
			resolved_destination,
			{},
			target_binding,
			weight
		))
	return {"points": navigation_points, "bindings": navigation_bindings}


func _automatic_curve_control_for_pose(
	start_position: Vector2,
	start_rotation: float,
	final_destination: Vector2
) -> Vector2:
	var displacement := final_destination - start_position
	var distance := displacement.length()
	if distance <= 0.001:
		return start_position
	var forward := Vector2.UP.rotated(start_rotation)
	var target_direction := displacement / distance
	var signed_heading_error := forward.angle_to(target_direction)
	var heading_error_ratio := clampf(
		absf(signed_heading_error) / PI,
		0.0,
		1.0
	)
	var handle_length := distance * lerpf(
		automatic_course_handle_ratio * 0.5,
		automatic_course_handle_ratio,
		smoothstep(0.0, 1.0, heading_error_ratio)
	)
	var control := start_position + forward * handle_length
	if heading_error_ratio > 0.82:
		var turn_side := signf(signed_heading_error)
		if is_zero_approx(turn_side):
			turn_side = 1.0
		control += (
			forward.orthogonal()
			* turn_side
			* handle_length
			* 0.38
		)
	return control


func _quadratic_bezier(start: Vector2, control: Vector2, finish: Vector2, weight: float) -> Vector2:
	var inverse := 1.0 - weight
	return inverse * inverse * start + 2.0 * inverse * weight * control + weight * weight * finish


func _catmull_rom(previous: Vector2, start: Vector2, finish: Vector2, following: Vector2, weight: float) -> Vector2:
	var weight_squared := weight * weight
	var weight_cubed := weight_squared * weight
	return 0.5 * (
		2.0 * start
		+ (-previous + finish) * weight
		+ (2.0 * previous - 5.0 * start + 4.0 * finish - following) * weight_squared
		+ (-previous + 3.0 * start - 3.0 * finish + following) * weight_cubed
	)


func _pending_binding(index: int) -> Dictionary:
	if index < 0 or index >= pending_route_bindings.size():
		return {}
	return pending_route_bindings[index]


func _route_sample_binding(
	base_position: Vector2,
	start_position: Vector2,
	end_position: Vector2,
	start_binding: Dictionary,
	end_binding: Dictionary,
	weight: float
) -> Dictionary:
	if start_binding.is_empty() and end_binding.is_empty():
		return {}
	return {
		"kind": "route_sample",
		"base_position": base_position,
		"start_position": start_position,
		"end_position": end_position,
		"start_binding": start_binding.duplicate(true),
		"end_binding": end_binding.duplicate(true),
		"weight": weight,
	}


func _refresh_bound_course_points() -> void:
	if has_destination:
		var active_points: Array[Vector2] = [destination]
		active_points.append_array(route_waypoints)
		var active_bindings: Array[Dictionary] = [destination_binding]
		active_bindings.append_array(route_waypoint_bindings)
		var valid_points: Array[Vector2] = []
		var valid_bindings: Array[Dictionary] = []
		for index: int in range(active_points.size()):
			var binding := active_bindings[index] if index < active_bindings.size() else {}
			var resolved := _resolve_binding(binding, active_points[index])
			if not bool(resolved["valid"]):
				continue
			valid_points.append(resolved["position"])
			valid_bindings.append(binding)
		if valid_points.is_empty():
			has_destination = false
			heading_lock_course_active = false
			destination = ship_position
			destination_binding.clear()
			route_waypoints.clear()
			route_waypoint_bindings.clear()
			automatic_course_active = false
			automatic_course_binding.clear()
		else:
			destination = valid_points.pop_front()
			destination_binding = valid_bindings.pop_front()
			route_waypoints = valid_points
			route_waypoint_bindings = valid_bindings
	for index: int in range(pending_route_bindings.size()):
		if pending_route_bindings[index].is_empty():
			continue
		var resolved_pending := _resolve_binding(pending_route_bindings[index], pending_route_waypoints[index])
		pending_route_waypoints[index] = resolved_pending["position"]
		if not bool(resolved_pending["valid"]):
			pending_route_bindings[index].clear()
	if course_preview_active and not course_preview_binding.is_empty():
		var resolved_preview := _resolve_binding(course_preview_binding, course_preview_point)
		course_preview_point = resolved_preview["position"]
		if not bool(resolved_preview["valid"]):
			course_preview_binding.clear()


func _resolved_binding_position(binding: Dictionary, fallback: Vector2) -> Vector2:
	return _resolve_binding(binding, fallback)["position"]


func _resolve_binding(binding: Dictionary, fallback: Vector2) -> Dictionary:
	if binding.is_empty():
		return {"valid": true, "position": fallback}
	var kind := String(binding.get("kind", ""))
	if kind == "route_sample":
		var weight := clampf(float(binding.get("weight", 0.0)), 0.0, 1.0)
		var position: Vector2 = binding.get("base_position", fallback)
		var start_binding: Dictionary = binding.get("start_binding", {})
		var end_binding: Dictionary = binding.get("end_binding", {})
		if weight < 0.999 and not start_binding.is_empty():
			var start_position: Vector2 = binding.get("start_position", position)
			var resolved_start := _resolve_binding(start_binding, start_position)
			if not bool(resolved_start["valid"]):
				return {"valid": false, "position": fallback}
			position += (Vector2(resolved_start["position"]) - start_position) * (1.0 - weight)
		if weight > 0.001 and not end_binding.is_empty():
			var end_position: Vector2 = binding.get("end_position", position)
			var resolved_end := _resolve_binding(end_binding, end_position)
			if not bool(resolved_end["valid"]):
				return {"valid": false, "position": fallback}
			position += (Vector2(resolved_end["position"]) - end_position) * weight
		return {"valid": true, "position": position}
	if kind != "grid_pickup":
		return {"valid": false, "position": fallback}
	var combat := get_tree().get_first_node_in_group("combat_simulation")
	if not is_instance_valid(combat) or not combat.has_method("get_grid_pickup_transform"):
		return {"valid": false, "position": fallback}
	var pickup_transform: Dictionary = combat.call("get_grid_pickup_transform", int(binding.get("id", -1)))
	if pickup_transform.is_empty():
		return {"valid": false, "position": fallback}
	var local_offset: Vector2 = binding.get("local_offset", Vector2.ZERO)
	return {
		"valid": true,
		"position": Vector2(pickup_transform["position"]) + local_offset.rotated(float(pickup_transform["rotation"])),
	}


func get_active_grid_pickup_destination_ids() -> PackedInt32Array:
	var ids: Dictionary = {}
	if course_preview_active:
		_collect_grid_pickup_binding_ids(course_preview_binding, ids)
	for binding: Dictionary in pending_route_bindings:
		_collect_grid_pickup_binding_ids(binding, ids)
	if has_destination:
		_collect_grid_pickup_binding_ids(destination_binding, ids)
		for binding: Dictionary in route_waypoint_bindings:
			_collect_grid_pickup_binding_ids(binding, ids)
	var result := PackedInt32Array()
	for id_value: Variant in ids.keys():
		result.append(int(id_value))
	return result


func _collect_grid_pickup_binding_ids(binding: Dictionary, ids: Dictionary) -> void:
	if binding.is_empty():
		return
	match String(binding.get("kind", "")):
		"grid_pickup":
			var pickup_id := int(binding.get("id", -1))
			if pickup_id >= 0:
				ids[pickup_id] = true
		"route_sample":
			_collect_grid_pickup_binding_ids(binding.get("start_binding", {}), ids)
			_collect_grid_pickup_binding_ids(binding.get("end_binding", {}), ids)


## The player's docking socket is always the exposed starboard hull cell nearest
## the ship's vertical center. The returned position is in ship-local pixels.
func get_starboard_docking_connector() -> Dictionary:
	if ship_layout == null:
		return {}
	var occupied := GRID_GEOMETRY.layout_cells(ship_layout)
	if occupied.is_empty():
		return {}
	var bounds: Rect2i = ship_layout.call("get_occupied_bounds")
	var geometry_size := GRID_GEOMETRY.grid_pixel_size(ship_layout, bounds, 20.0)
	var hull_center_y := geometry_size.y * 0.5
	var best_cell := Vector2i.ZERO
	var best_center := Vector2.ZERO
	var best_middle_distance := INF
	var best_right_edge := -INF
	for cell_value: Variant in occupied.keys():
		var cell: Vector2i = cell_value
		if GRID_GEOMETRY.face_contact_strength(ship_layout, cell, Vector2i.RIGHT, occupied) >= 0.999:
			continue
		var cell_rect := GRID_GEOMETRY.cell_rect(ship_layout, cell, bounds, 20.0)
		var middle_distance := absf(cell_rect.get_center().y - hull_center_y)
		var right_edge := cell_rect.end.x
		if middle_distance < best_middle_distance or (
			is_equal_approx(middle_distance, best_middle_distance) and right_edge > best_right_edge
		):
			best_cell = cell
			best_center = cell_rect.get_center() - geometry_size * 0.5
			best_middle_distance = middle_distance
			best_right_edge = right_edge
	if best_middle_distance == INF:
		return {}
	return {
		"cell": best_cell,
		"local_position": best_center + Vector2.RIGHT * 10.0,
		"local_direction": Vector2.RIGHT,
	}


func begin_docking_sequence(plan: Dictionary) -> bool:
	if plan.is_empty() or docking_state != &"IDLE":
		return false
	controller_coasting = false
	post_undock_course_active = false
	post_undock_course_binding.clear()
	docking_contact_id = int(plan.get("contact_id", -1))
	docking_station_body = plan.get("station_body") as RigidBody2D
	docking_final_position = plan.get("final_position", ship_position)
	docking_final_rotation = float(plan.get("final_rotation", ship_rotation))
	docking_port_outward = plan.get("port_outward", Vector2.ZERO)
	manual_heading_active = false
	heading_lock_course_active = false
	course_preview_active = false
	course_preview_heading_lock = false
	course_preview_binding.clear()
	pending_route_waypoints.clear()
	pending_route_bindings.clear()
	pending_route_curve_controls.clear()
	is_plotting_route = false
	automatic_course_active = false
	automatic_course_binding.clear()
	predicted_automatic_course.clear()
	route_waypoints.clear()
	route_waypoint_bindings.clear()
	destination = docking_final_position
	destination_binding.clear()
	has_destination = true
	_prepare_smooth_docking_curve()
	docking_state = &"APPROACH"
	docking_state_changed.emit(docking_state, docking_contact_id)
	return true


func _update_docking_sequence(delta: float) -> bool:
	if docking_state == &"IDLE":
		return false
	if docking_state == &"APPROACH":
		_update_smooth_docking_approach(delta)
		return true
	if docking_state == &"ALIGN":
		var rotation_error := angle_difference(ship_rotation, docking_final_rotation)
		var desired_angular_velocity := clampf(
			rotation_error * steering_response,
			-deg_to_rad(turn_speed_degrees),
			deg_to_rad(turn_speed_degrees)
		)
		if is_instance_valid(physics_body):
			_command_physics_propulsion(0.0, 1.0, desired_angular_velocity)
		else:
			velocity = velocity.move_toward(Vector2.ZERO, braking_acceleration * delta)
			ship_rotation = rotate_toward(
				ship_rotation,
				docking_final_rotation,
				deg_to_rad(turn_speed_degrees) * delta
			)
		if absf(rad_to_deg(rotation_error)) <= docking_alignment_degrees and velocity.length() <= 1.0:
			docking_state = &"FINAL"
			docking_state_changed.emit(docking_state, docking_contact_id)
		return true
	if docking_state == &"FINAL":
		_update_final_docking_translation(delta)
		return true
	if docking_state == &"UNDOCK":
		_update_undocking_translation(delta)
		return true
	if docking_state == &"DOCKED":
		if is_instance_valid(physics_body):
			physics_body.linear_velocity = Vector2.ZERO
			physics_body.angular_velocity = 0.0
		return true
	return false


func _prepare_smooth_docking_curve() -> void:
	docking_curve_start = ship_position
	docking_curve_progress = 0.0
	docking_curve_velocity = velocity
	var berth_distance := docking_curve_start.distance_to(docking_final_position)
	var start_forward := Vector2.UP.rotated(ship_rotation)
	var final_forward := Vector2.UP.rotated(docking_final_rotation)
	var base_handle := clampf(
		berth_distance * docking_curve_handle_ratio,
		70.0,
		420.0
	)
	var arrival_handle := minf(
		base_handle,
		maxf(55.0, berth_distance * 0.28)
	)
	docking_curve_control_a = docking_curve_start + start_forward * base_handle
	docking_curve_control_b = docking_final_position - final_forward * arrival_handle
	var estimated_length := _estimate_docking_curve_length()
	docking_curve_duration = clampf(
		estimated_length / maxf(docking_approach_speed, 1.0),
		2.5,
		45.0
	)
	if is_instance_valid(physics_body):
		physics_body.linear_velocity = Vector2.ZERO
		physics_body.angular_velocity = 0.0
		physics_body.freeze_mode = RigidBody2D.FREEZE_MODE_KINEMATIC
		physics_body.freeze = true


func _update_smooth_docking_approach(delta: float) -> void:
	var previous_position := ship_position
	docking_curve_progress = minf(
		docking_curve_progress + delta / maxf(docking_curve_duration, 0.001),
		1.0
	)
	var eased_progress := smoothstep(0.0, 1.0, docking_curve_progress)
	ship_position = _docking_curve_point(eased_progress)
	var tangent := _docking_curve_tangent(eased_progress)
	if not tangent.is_zero_approx():
		ship_rotation = Vector2.UP.angle_to(tangent)
	docking_curve_velocity = (
		(ship_position - previous_position) / delta
		if delta > 0.0001
		else Vector2.ZERO
	)
	velocity = docking_curve_velocity
	if is_instance_valid(physics_body):
		var braking_phase := smoothstep(0.78, 1.0, docking_curve_progress)
		_command_physics_propulsion(
			0.58 * (1.0 - braking_phase),
			braking_phase,
			0.0
		)
		physics_body.global_position = ship_position
		physics_body.global_rotation = ship_rotation
		physics_body.linear_velocity = Vector2.ZERO
		physics_body.angular_velocity = 0.0
	if docking_curve_progress >= 1.0:
		_lock_to_docking_berth()


func _docking_curve_point(weight: float) -> Vector2:
	var inverse := 1.0 - weight
	return (
		docking_curve_start * inverse * inverse * inverse
		+ docking_curve_control_a * 3.0 * inverse * inverse * weight
		+ docking_curve_control_b * 3.0 * inverse * weight * weight
		+ docking_final_position * weight * weight * weight
	)


func _docking_curve_tangent(weight: float) -> Vector2:
	var inverse := 1.0 - weight
	return (
		(docking_curve_control_a - docking_curve_start) * 3.0 * inverse * inverse
		+ (docking_curve_control_b - docking_curve_control_a) * 6.0 * inverse * weight
		+ (docking_final_position - docking_curve_control_b) * 3.0 * weight * weight
	).normalized()


func _estimate_docking_curve_length() -> float:
	var length := 0.0
	var previous := docking_curve_start
	for sample_index: int in range(1, 17):
		var sample := _docking_curve_point(float(sample_index) / 16.0)
		length += previous.distance_to(sample)
		previous = sample
	return length


func _update_final_docking_translation(delta: float) -> void:
	var to_berth := docking_final_position - ship_position
	var distance := to_berth.length()
	if distance <= docking_lock_distance:
		_lock_to_docking_berth()
		return
	var precision_speed := minf(
		docking_final_speed,
		sqrt(2.0 * maxf(braking_acceleration, 1.0) * distance)
	)
	var precision_velocity := to_berth.normalized() * precision_speed
	if is_instance_valid(physics_body):
		physics_body.freeze = false
		physics_body.linear_velocity = precision_velocity
		physics_body.angular_velocity = 0.0
		physics_body.global_rotation = rotate_toward(
			physics_body.global_rotation,
			docking_final_rotation,
			deg_to_rad(turn_speed_degrees) * delta
		)
	else:
		velocity = precision_velocity
		ship_position += velocity * delta
		ship_rotation = rotate_toward(
			ship_rotation,
			docking_final_rotation,
			deg_to_rad(turn_speed_degrees) * delta
		)


func _lock_to_docking_berth() -> void:
	has_destination = false
	heading_lock_course_active = false
	destination_binding.clear()
	route_waypoints.clear()
	route_waypoint_bindings.clear()
	automatic_course_active = false
	automatic_course_binding.clear()
	velocity = Vector2.ZERO
	ship_position = docking_final_position
	ship_rotation = docking_final_rotation
	if is_instance_valid(physics_body):
		_command_physics_propulsion(0.0, 0.0, 0.0)
		physics_body.linear_velocity = Vector2.ZERO
		physics_body.angular_velocity = 0.0
		physics_body.global_position = docking_final_position
		physics_body.global_rotation = docking_final_rotation
		physics_body.freeze_mode = RigidBody2D.FREEZE_MODE_STATIC
		physics_body.freeze = true
	docking_state = &"DOCKED"
	docking_state_changed.emit(docking_state, docking_contact_id)
	docking_completed.emit(docking_contact_id)


func begin_undocking() -> bool:
	if docking_state != &"DOCKED" or docking_port_outward.is_zero_approx():
		return false
	undocking_start_position = ship_position
	docking_release_position = (
		undocking_start_position
		+ docking_port_outward.normalized() * undocking_clearance_distance
	)
	undocking_progress = 0.0
	if is_instance_valid(physics_body):
		physics_body.freeze_mode = RigidBody2D.FREEZE_MODE_KINEMATIC
		physics_body.freeze = true
		physics_body.sleeping = false
		physics_body.linear_velocity = Vector2.ZERO
		physics_body.angular_velocity = 0.0
	velocity = Vector2.ZERO
	docking_state = &"UNDOCK"
	docking_state_changed.emit(docking_state, docking_contact_id)
	return true


func _update_undocking_translation(delta: float) -> void:
	var previous_position := ship_position
	undocking_progress = minf(
		undocking_progress + delta / maxf(undocking_clearance_duration, 0.001),
		1.0
	)
	var eased_progress := smoothstep(0.0, 1.0, undocking_progress)
	ship_position = undocking_start_position.lerp(
		docking_release_position,
		eased_progress
	)
	velocity = (
		(ship_position - previous_position) / delta
		if delta > 0.0001
		else Vector2.ZERO
	)
	if is_instance_valid(physics_body):
		physics_body.global_position = ship_position
		physics_body.global_rotation = ship_rotation
		physics_body.linear_velocity = Vector2.ZERO
		physics_body.angular_velocity = 0.0
	if undocking_progress >= 1.0:
		var released_contact_id := docking_contact_id
		ship_position = docking_release_position
		velocity = Vector2.ZERO
		if is_instance_valid(physics_body):
			physics_body.global_position = docking_release_position
			physics_body.freeze = false
			physics_body.sleeping = false
			physics_body.linear_velocity = Vector2.ZERO
			physics_body.angular_velocity = 0.0
		docking_state = &"IDLE"
		docking_contact_id = -1
		docking_station_body = null
		docking_port_outward = Vector2.ZERO
		docking_state_changed.emit(docking_state, released_contact_id)
		undocking_completed.emit(released_contact_id)
		if post_undock_course_active:
			var queued_goal := post_undock_course_goal
			var queued_binding := post_undock_course_binding.duplicate(true)
			post_undock_course_active = false
			post_undock_course_binding.clear()
			set_course(queued_goal, queued_binding)
		return


func get_grid_piece_inventory() -> Dictionary:
	return grid_piece_inventory


func get_grid_piece_instances() -> Array[Dictionary]:
	return grid_piece_instances.duplicate(true)


func get_grid_piece_instance(instance_id: int) -> Dictionary:
	for item: Dictionary in grid_piece_instances:
		if int(item.get("instance_id", 0)) == instance_id:
			return item.duplicate(true)
	return {}


func reset_for_sector_entry(
	entry_position: Vector2 = Vector2.ZERO,
	entry_rotation: float = 0.0
) -> void:
	controller_coasting = false
	has_destination = false
	heading_lock_course_active = false
	destination = entry_position
	destination_binding.clear()
	route_waypoints.clear()
	route_waypoint_bindings.clear()
	pending_route_waypoints.clear()
	pending_route_bindings.clear()
	pending_route_curve_controls.clear()
	course_preview_active = false
	course_preview_binding.clear()
	course_preview_heading_lock = false
	is_plotting_route = false
	manual_heading_active = false
	docking_state = &"IDLE"
	docking_contact_id = -1
	docking_station_body = null
	docking_port_outward = Vector2.ZERO
	ship_position = entry_position
	previous_ship_position = entry_position
	ship_rotation = entry_rotation
	previous_ship_rotation = entry_rotation
	velocity = Vector2.ZERO
	if is_instance_valid(physics_body):
		physics_body.freeze = false
		physics_body.sleeping = false
		physics_body.global_position = entry_position
		physics_body.global_rotation = entry_rotation
		physics_body.linear_velocity = Vector2.ZERO
		physics_body.angular_velocity = 0.0


func get_grid_piece_count(room_type: String) -> int:
	return maxi(int(grid_piece_inventory.get(room_type, 0)), 0)


func consume_grid_piece(room_type: String, instance_id: int = 0) -> bool:
	for index: int in range(grid_piece_instances.size()):
		var item: Dictionary = grid_piece_instances[index]
		if String(item.get("inventory_key", "")) != room_type:
			continue
		if instance_id > 0 and int(item.get("instance_id", 0)) != instance_id:
			continue
		grid_piece_instances.remove_at(index)
		_sync_grid_piece_inventory_counts()
		return true
	return false


func add_grid_piece(room_type: String, amount: int = 1, condition: Dictionary = {}) -> Array[int]:
	var added_ids: Array[int] = []
	if room_type.is_empty() or amount <= 0:
		return added_ids
	for item_index: int in range(amount):
		var requested_position := Vector2i(condition.get("inventory_position", Vector2i(-1, -1)))
		var inventory_position := _find_grid_piece_inventory_position(room_type, requested_position)
		if inventory_position == Vector2i(-1, -1):
			break
		var maximum_health := maxf(float(condition.get("maximum_health", 100.0)), 1.0)
		var item := {
			"instance_id": next_grid_piece_instance_id,
			"inventory_key": room_type,
			"maximum_health": maximum_health,
			"current_health": clampf(float(condition.get("current_health", maximum_health)), 0.0, maximum_health),
			"disabled": bool(condition.get("disabled", false)),
			"breached": bool(condition.get("breached", false)),
			"inventory_position": inventory_position,
		}
		grid_piece_instances.append(item)
		added_ids.append(next_grid_piece_instance_id)
		next_grid_piece_instance_id += 1
	_sync_grid_piece_inventory_counts()
	return added_ids


func can_store_grid_piece(room_type: String) -> bool:
	return _find_grid_piece_inventory_position(room_type) != Vector2i(-1, -1)


func _find_grid_piece_inventory_position(room_type: String, requested_position: Vector2i = Vector2i(-1, -1)) -> Vector2i:
	var occupied := {}
	for item: Dictionary in grid_piece_instances:
		var item_key := String(item.get("inventory_key", ""))
		var item_footprint := _inventory_piece_footprint(item_key)
		var item_position := Vector2i(item.get("inventory_position", Vector2i(-1, -1)))
		if not _inventory_position_fits(item_position, item_footprint, occupied):
			item_position = _first_open_inventory_position(item_footprint, occupied)
		if item_position == Vector2i(-1, -1):
			continue
		_mark_inventory_footprint(occupied, item_position, item_footprint)
	var footprint := _inventory_piece_footprint(room_type)
	if _inventory_position_fits(requested_position, footprint, occupied):
		return requested_position
	return _first_open_inventory_position(footprint, occupied)


func _inventory_piece_footprint(room_type: String) -> Vector2i:
	var descriptor: Dictionary = GRID_INVENTORY_CATALOG.describe(ship_layout, room_type)
	var raw := Vector2i(descriptor.get("footprint", Vector2i.ONE))
	return Vector2i(clampi(raw.x, 1, STARTING_CARGO_COLUMNS), clampi(raw.y, 1, STARTING_CARGO_ROWS))


func _first_open_inventory_position(footprint: Vector2i, occupied: Dictionary) -> Vector2i:
	for row: int in range(STARTING_CARGO_ROWS - footprint.y + 1):
		for column: int in range(STARTING_CARGO_COLUMNS - footprint.x + 1):
			var candidate := Vector2i(column, row)
			if _inventory_position_fits(candidate, footprint, occupied):
				return candidate
	return Vector2i(-1, -1)


func _inventory_position_fits(position: Vector2i, footprint: Vector2i, occupied: Dictionary) -> bool:
	if position.x < 0 or position.y < 0:
		return false
	if position.x + footprint.x > STARTING_CARGO_COLUMNS or position.y + footprint.y > STARTING_CARGO_ROWS:
		return false
	for y: int in range(position.y, position.y + footprint.y):
		for x: int in range(position.x, position.x + footprint.x):
			if occupied.has(Vector2i(x, y)):
				return false
	return true


func _mark_inventory_footprint(occupied: Dictionary, position: Vector2i, footprint: Vector2i) -> void:
	for y: int in range(position.y, position.y + footprint.y):
		for x: int in range(position.x, position.x + footprint.x):
			occupied[Vector2i(x, y)] = true


func update_grid_piece_condition(instance_id: int, changes: Dictionary) -> bool:
	for item: Dictionary in grid_piece_instances:
		if int(item.get("instance_id", 0)) != instance_id:
			continue
		for key: Variant in changes:
			if key in ["maximum_health", "current_health", "disabled", "breached", "inventory_position"]:
				item[key] = changes[key]
		return true
	return false


func clear_grid_piece_inventory() -> void:
	grid_piece_instances.clear()
	grid_piece_inventory.clear()


func _initialize_grid_piece_inventory() -> void:
	grid_piece_instances.clear()
	grid_piece_inventory.clear()
	next_grid_piece_instance_id = 1
	var inventory_keys := starting_grid_piece_inventory.keys()
	inventory_keys.sort()
	for key_value: Variant in inventory_keys:
		add_grid_piece(String(key_value), maxi(int(starting_grid_piece_inventory[key_value]), 0))


func _sync_grid_piece_inventory_counts() -> void:
	grid_piece_inventory.clear()
	for item: Dictionary in grid_piece_instances:
		var inventory_key := String(item.get("inventory_key", ""))
		if inventory_key.is_empty():
			continue
		grid_piece_inventory[inventory_key] = int(grid_piece_inventory.get(inventory_key, 0)) + 1


func set_shield_enabled(is_enabled: bool) -> void:
	shield_enabled = shield_installed and is_enabled


func apply_shield_damage(amount: float, impact_world_direction: Vector2 = Vector2.ZERO) -> float:
	if not is_shield_active():
		return maxf(amount, 0.0)
	var bank := _shield_bank_for_world_direction(impact_world_direction)
	if bank < 0 or not _shield_bank_is_online(bank):
		return maxf(amount, 0.0)
	var bank_current := float(shield_bank_currents.get(bank, 0.0))
	var absorbed_damage := minf(bank_current, maxf(amount, 0.0))
	shield_bank_currents[bank] = bank_current - absorbed_damage
	_sync_shield_totals()
	return maxf(amount - absorbed_damage, 0.0)


func get_shield_percentage() -> float:
	if maximum_shield <= 0.0:
		return 0.0
	return 100.0 * current_shield / maximum_shield


func is_shield_active() -> bool:
	return not is_destroyed and shield_installed and shield_enabled and maximum_shield > 0.0


## Applies one weapon hit as a single transaction. Shields consume only the
## amount they actually contain; every remaining point continues into hull.
func apply_combat_damage(
	amount: float,
	target_room_id: StringName = &"",
	impact_world_direction: Vector2 = Vector2.ZERO,
	shield_effectiveness: float = 1.0,
	hull_effectiveness: float = 1.0,
	system_effectiveness: float = 1.0,
	breach_effectiveness: float = 1.0,
	impact_cell: Vector2i = Vector2i(2147483647, 2147483647),
	ion_disruption_seconds: float = 0.0
) -> Dictionary:
	var incoming_damage := maxf(amount, 0.0)
	var shield_bank := _shield_bank_for_world_direction(impact_world_direction)
	var shield_scale := maxf(shield_effectiveness, 0.0)
	var remaining_base_damage := incoming_damage
	var absorbed_damage := 0.0
	if shield_scale > 0.0:
		var scaled_shield_damage := incoming_damage * shield_scale
		var remaining_scaled_damage := apply_shield_damage(scaled_shield_damage, impact_world_direction)
		absorbed_damage = scaled_shield_damage - remaining_scaled_damage
		remaining_base_damage = incoming_damage * (
			remaining_scaled_damage / maxf(scaled_shield_damage, 0.001)
		)
	var hull_report := _apply_layered_hull_damage(
		remaining_base_damage,
		target_room_id,
		hull_effectiveness,
		system_effectiveness,
		breach_effectiveness,
		impact_cell,
		impact_world_direction,
		ion_disruption_seconds
	)
	return {
		"incoming": incoming_damage,
		"shield_absorbed": absorbed_damage,
		"shield_bank": shield_bank,
		"hull_damage": hull_report["ship_damage"],
		"local_damage": hull_report["local_damage"],
		"section_disabled": hull_report["section_disabled"],
		"vulnerability_multiplier": hull_report["vulnerability_multiplier"],
		"breach_progress": hull_report["breach_progress"],
		"breached": hull_report["breached"],
		"module_detached": hull_report.get("module_detached", false),
		"ion_disabled": hull_report.get("ion_disabled", false),
		"unapplied": 0.0,
		"destroyed": is_hull_depleted(),
	}


## Sector hazards attack the whole vessel rather than drilling repeatedly into
## one compartment. Shields still protect the exposed facing, but spillover
## reduces ship health without manufacturing commonplace hull breaches.
func apply_environmental_damage(
	amount: float,
	impact_world_direction: Vector2 = Vector2.ZERO,
	bypass_shields: bool = false
) -> Dictionary:
	var incoming_damage := maxf(amount, 0.0)
	if incoming_damage <= 0.0 or is_destroyed:
		return {
			"incoming": incoming_damage,
			"shield_absorbed": 0.0,
			"hull_damage": 0.0,
			"destroyed": is_hull_depleted(),
		}
	var remaining_damage := incoming_damage
	if not bypass_shields:
		remaining_damage = apply_shield_damage(incoming_damage, impact_world_direction)
	var absorbed_damage := incoming_damage - remaining_damage
	var hull_damage := minf(current_ship_health, remaining_damage)
	current_ship_health = maxf(current_ship_health - hull_damage, 0.0)
	_report_hull_depletion_if_needed()
	return {
		"incoming": incoming_damage,
		"shield_absorbed": absorbed_damage,
		"hull_damage": hull_damage,
		"destroyed": is_hull_depleted(),
	}


func _apply_layered_hull_damage(
	amount: float,
	target_room_id: StringName,
	hull_effectiveness: float = 1.0,
	system_effectiveness: float = 1.0,
	breach_effectiveness: float = 1.0,
	impact_cell: Vector2i = Vector2i(2147483647, 2147483647),
	impact_world_direction: Vector2 = Vector2.ZERO,
	ion_disruption_seconds: float = 0.0
) -> Dictionary:
	var incoming := maxf(amount, 0.0)
	var target := get_room_data(target_room_id)
	if target.is_empty() and not rooms.is_empty():
		target = rooms[0]
		target_room_id = target["id"]
	var target_definition := _layout_room_definition(target_room_id)
	var target_piece_index := _target_piece_index(target_definition, impact_cell, impact_world_direction)
	var piece_key := _module_piece_key(target_definition, target_piece_index)
	var was_disabled := not piece_key.is_empty() and is_module_piece_disabled(target_room_id, target_piece_index)
	var vulnerability := disabled_section_damage_multiplier if was_disabled else 1.0
	var ship_damage := minf(
		current_ship_health,
		incoming * maxf(hull_effectiveness, 0.0) * vulnerability
	)
	current_ship_health = maxf(current_ship_health - ship_damage, 0.0)
	var local_damage := 0.0
	var breached := false
	var breach_progress := 0.0
	var detached := false
	var ion_disabled := false
	if not target.is_empty():
		var system_damage := incoming * maxf(system_effectiveness, 0.0)
		local_damage = minf(float(target["current_health"]), system_damage)
		target["current_health"] = maxf(float(target["current_health"]) - system_damage, 0.0)
		if not piece_key.is_empty():
			var previous_piece_damage := float(module_damage.get(piece_key, 0.0))
			module_damage[piece_key] = previous_piece_damage + system_damage
			var piece_maximum := _module_piece_maximum_health(target_definition)
			var now_disabled := float(module_damage[piece_key]) >= piece_maximum
			if now_disabled and not was_disabled:
				module_disabled.emit(target_room_id, target_piece_index, false)
			if ion_disruption_seconds > 0.0:
				module_ion_disable_remaining[piece_key] = maxf(
					float(module_ion_disable_remaining.get(piece_key, 0.0)),
					ion_disruption_seconds
				)
				ion_disabled = true
				module_disabled.emit(target_room_id, target_piece_index, true)
			if now_disabled and not _module_piece_is_core(target_definition, target_piece_index):
				var detachment_threshold := piece_maximum * (1.0 + extension_detachment_overdamage_multiplier)
				breach_progress = clampf(float(module_damage[piece_key]) / maxf(detachment_threshold, 0.001), 0.0, 1.0)
				if float(module_damage[piece_key]) >= detachment_threshold:
					detached = _detach_extension_piece(target_definition, target_piece_index, impact_world_direction)
		if was_disabled and incoming > 0.0 and _module_piece_is_core(target_definition, target_piece_index):
			var accumulated := (
				float(room_breach_overdamage.get(target_room_id, 0.0))
				+ incoming * maxf(breach_effectiveness, 0.0)
			)
			room_breach_overdamage[target_room_id] = accumulated
			var threshold := float(target["maximum_health"]) * breach_overdamage_health_multiplier
			breach_progress = clampf(accumulated / maxf(threshold, 0.001), 0.0, 1.0)
			if accumulated >= threshold and structural_state != null and structural_state.get_room_outer_breach_length(target_room_id) <= 0.0:
				breached = _breach_room_outer_wall(target_room_id)
	_report_hull_depletion_if_needed()
	return {
		"ship_damage": ship_damage,
		"local_damage": local_damage,
		"section_disabled": not target.is_empty() and float(target["current_health"]) <= 0.001,
		"vulnerability_multiplier": vulnerability,
		"breach_progress": breach_progress,
		"breached": breached,
		"module_detached": detached,
		"ion_disabled": ion_disabled,
	}


func _breach_room_outer_wall(room_id: StringName) -> bool:
	var chosen_key := ""
	var chosen_length := 0.0
	for wall_value: Variant in structural_state.walls.values():
		var wall: Dictionary = wall_value
		var cells: Array = wall["cells"]
		if not bool(wall["outer"]) or bool(wall["breached"]) or cells.is_empty():
			continue
		if StringName(structural_state.cell_rooms.get(cells[0], &"")) != room_id:
			continue
		var length := Vector2(wall["start"]).distance_to(Vector2(wall["end"]))
		if length > chosen_length:
			chosen_length = length
			chosen_key = String(wall["key"])
	if chosen_key.is_empty():
		return false
	structural_state.breach_wall(chosen_key)
	return true


func _layout_room_definition(room_id: StringName) -> Resource:
	if ship_layout == null:
		return null
	for definition: Resource in ship_layout.get("rooms"):
		if StringName(definition.get("room_id")) == room_id:
			return definition
	return null


func _target_piece_index(room: Resource, impact_cell: Vector2i, impact_world_direction: Vector2) -> int:
	if room == null:
		return -1
	var rects: Array[Rect2i] = room.get("grid_rects")
	if rects.is_empty():
		return -1
	for index: int in range(rects.size()):
		if rects[index].has_point(impact_cell):
			return index
	if impact_world_direction.is_zero_approx():
		return 0
	var local_direction := impact_world_direction.normalized().rotated(-ship_rotation)
	var best_index := 0
	var best_projection := -INF
	for index: int in range(rects.size()):
		var projection := Vector2(rects[index].get_center()).dot(local_direction)
		if projection > best_projection:
			best_projection = projection
			best_index = index
	return best_index


func _module_piece_key(room: Resource, piece_index: int) -> String:
	if room == null:
		return ""
	var rects: Array[Rect2i] = room.get("grid_rects")
	if piece_index < 0 or piece_index >= rects.size():
		return ""
	var rect := rects[piece_index]
	return "%s|%d,%d,%d,%d" % [
		String(room.get("room_id")),
		rect.position.x,
		rect.position.y,
		rect.size.x,
		rect.size.y,
	]


func _module_piece_maximum_health(room: Resource) -> float:
	if room == null:
		return 1.0
	var rects: Array[Rect2i] = room.get("grid_rects")
	var maximum_health := ROOM_STAFFING_RULES.effective_maximum_health(
		room,
		float(room.get("maximum_health"))
	)
	return maxf(maximum_health / float(maxi(rects.size(), 1)), 1.0)


func _module_piece_is_core(room: Resource, piece_index: int) -> bool:
	if room == null or ship_layout == null or not ship_layout.has_method("rect_contains_core"):
		return true
	var rects: Array[Rect2i] = room.get("grid_rects")
	if piece_index < 0 or piece_index >= rects.size():
		return true
	return bool(ship_layout.call("rect_contains_core", rects[piece_index]))


func is_module_piece_disabled(room_id: StringName, piece_index: int) -> bool:
	var room := _layout_room_definition(room_id)
	var key := _module_piece_key(room, piece_index)
	if key.is_empty():
		return true
	return (
		float(module_damage.get(key, 0.0)) >= _module_piece_maximum_health(room)
		or float(module_ion_disable_remaining.get(key, 0.0)) > 0.001
	)


func get_module_piece_status(room_id: StringName, piece_index: int) -> Dictionary:
	var room := _layout_room_definition(room_id)
	var key := _module_piece_key(room, piece_index)
	if key.is_empty():
		return {}
	var maximum := _module_piece_maximum_health(room)
	var damage := float(module_damage.get(key, 0.0))
	return {
		"core": _module_piece_is_core(room, piece_index),
		"damage": damage,
		"maximum_health": maximum,
		"health_ratio": clampf(1.0 - damage / maxf(maximum, 0.001), 0.0, 1.0),
		"ion_seconds": float(module_ion_disable_remaining.get(key, 0.0)),
		"disabled": is_module_piece_disabled(room_id, piece_index),
		"detachment_progress": clampf(
			damage / maxf(maximum * (1.0 + extension_detachment_overdamage_multiplier), 0.001),
			0.0,
			1.0
		),
	}


func _room_module_operational_factor(room_id: StringName) -> float:
	var room := _layout_room_definition(room_id)
	if room == null:
		return 0.0
	var rects: Array[Rect2i] = room.get("grid_rects")
	if rects.is_empty():
		return 0.0
	var online := 0
	for index: int in range(rects.size()):
		if not is_module_piece_disabled(room_id, index):
			online += 1
	return float(online) / float(rects.size())


func _update_module_disable_timers(delta: float) -> void:
	if module_ion_disable_remaining.is_empty():
		return
	for key_value: Variant in module_ion_disable_remaining.keys().duplicate():
		var key := String(key_value)
		var remaining := maxf(float(module_ion_disable_remaining[key]) - delta, 0.0)
		if remaining <= 0.001:
			module_ion_disable_remaining.erase(key)
		else:
			module_ion_disable_remaining[key] = remaining


func _detach_extension_piece(room: Resource, piece_index: int, impact_world_direction: Vector2) -> bool:
	if room == null or _module_piece_is_core(room, piece_index):
		return false
	var detached_records: Array[Dictionary] = []
	var primary := _remove_layout_piece(room, piece_index, impact_world_direction)
	if primary.is_empty():
		return false
	detached_records.append(primary)
	# If the sheared mount was a structural bridge, every extension no longer
	# connected to a permanent core cell leaves with it as a physical cluster.
	while true:
		var orphan := _first_orphan_extension_piece()
		if orphan.is_empty():
			break
		var orphan_record := _remove_layout_piece(
			orphan["room"],
			int(orphan["piece_index"]),
			impact_world_direction
		)
		if orphan_record.is_empty():
			break
		detached_records.append(orphan_record)
	ship_layout.call("prune_unused_cell_offsets")
	_refresh_module_damage_keys()
	refresh_rooms_from_layout()
	for record: Dictionary in detached_records:
		module_detached.emit(
			String(record["piece_key"]),
			record["condition"],
			Vector2(record["world_position"]),
			Vector2(record["velocity"])
		)
	return true


func _remove_layout_piece(room: Resource, piece_index: int, impact_world_direction: Vector2) -> Dictionary:
	var rects: Array[Rect2i] = room.get("grid_rects")
	if piece_index < 0 or piece_index >= rects.size():
		return {}
	var removed_rect := rects[piece_index]
	var old_count := maxi(rects.size(), 1)
	var piece_maximum := _module_piece_maximum_health(room)
	var old_key := _module_piece_key(room, piece_index)
	var representative_cell := removed_rect.position + Vector2i(
		maxi(floori(float(removed_rect.size.x - 1) * 0.5), 0),
		maxi(floori(float(removed_rect.size.y - 1) * 0.5), 0)
	)
	var world_position := ship_position
	if is_instance_valid(physics_body) and physics_body.has_method("get_world_point_for_cell"):
		world_position = physics_body.call("get_world_point_for_cell", representative_cell)
	var outward := impact_world_direction.normalized()
	if outward.is_zero_approx():
		outward = ship_position.direction_to(world_position)
	if outward.is_zero_approx():
		outward = Vector2.UP.rotated(ship_rotation)
	var piece_inventory_key := _inventory_key_for_layout_piece(room)
	var facings: Array = room.get("module_mount_facings")
	var fire_modes: Array = room.get("weapon_fire_modes")
	rects.remove_at(piece_index)
	if piece_index < facings.size():
		facings.remove_at(piece_index)
	if piece_index < fire_modes.size():
		fire_modes.remove_at(piece_index)
	room.set("grid_rects", rects)
	room.set("module_mount_facings", facings)
	room.set("weapon_fire_modes", fire_modes)
	room.set("installed_piece_count", maxi(rects.size(), 1))
	room.set("maximum_health", maxf(float(room.get("maximum_health")) - piece_maximum, 1.0))
	room.set("minimum_crew", maxi(roundi(float(room.get("minimum_crew")) * float(old_count - 1) / float(old_count)), 0))
	room.set("optimal_crew", maxi(roundi(float(room.get("optimal_crew")) * float(old_count - 1) / float(old_count)), 0))
	if rects.is_empty():
		var definitions: Array = ship_layout.get("rooms")
		definitions.erase(room)
		ship_layout.set("rooms", definitions)
	module_damage.erase(old_key)
	module_ion_disable_remaining.erase(old_key)
	return {
		"piece_key": piece_inventory_key,
		"condition": {
			"maximum_health": piece_maximum,
			"current_health": 0.0,
			"disabled": true,
			"breached": false,
		},
		"world_position": world_position,
		"velocity": velocity + outward * 42.0,
	}


func _inventory_key_for_layout_piece(room: Resource) -> String:
	var room_type := String(room.get("type_name"))
	var recipe: Resource = room.get("module_recipe")
	if room_type == "WEAPONS" and recipe != null:
		return "WEAPON:%s" % String(recipe.get("module_id"))
	return room_type


func _first_orphan_extension_piece() -> Dictionary:
	var occupied: Dictionary = {}
	for definition: Resource in ship_layout.get("rooms"):
		for rect: Rect2i in definition.get("grid_rects"):
			for y: int in range(rect.position.y, rect.end.y):
				for x: int in range(rect.position.x, rect.end.x):
					occupied[Vector2i(x, y)] = true
	var reachable: Dictionary = {}
	var pending: Array[Vector2i] = []
	for core_cell: Vector2i in ship_layout.get("core_frame_cells"):
		if occupied.has(core_cell):
			reachable[core_cell] = true
			pending.append(core_cell)
	while not pending.is_empty():
		var cell: Vector2i = pending.pop_front()
		for direction: Vector2i in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
			var neighbor: Vector2i = cell + direction
			if occupied.has(neighbor) and not reachable.has(neighbor):
				reachable[neighbor] = true
				pending.append(neighbor)
	for definition: Resource in ship_layout.get("rooms"):
		var rects: Array[Rect2i] = definition.get("grid_rects")
		for index: int in range(rects.size()):
			if _module_piece_is_core(definition, index):
				continue
			var connected := false
			for y: int in range(rects[index].position.y, rects[index].end.y):
				for x: int in range(rects[index].position.x, rects[index].end.x):
					if reachable.has(Vector2i(x, y)):
						connected = true
						break
				if connected:
					break
			if not connected:
				return {"room": definition, "piece_index": index}
	return {}


func _refresh_module_damage_keys() -> void:
	var valid: Dictionary = {}
	for definition: Resource in ship_layout.get("rooms"):
		var rects: Array[Rect2i] = definition.get("grid_rects")
		for index: int in range(rects.size()):
			valid[_module_piece_key(definition, index)] = true
	for key_value: Variant in module_damage.keys().duplicate():
		if not valid.has(String(key_value)):
			module_damage.erase(key_value)
	for key_value: Variant in module_ion_disable_remaining.keys().duplicate():
		if not valid.has(String(key_value)):
			module_ion_disable_remaining.erase(key_value)


## Compatibility entry point for collision and scripted hull damage.
func apply_hull_damage(amount: float, target_room_id: StringName = &"") -> float:
	if amount <= 0.0 or rooms.is_empty() or is_destroyed:
		return 0.0
	return float(_apply_layered_hull_damage(amount, target_room_id)["ship_damage"])


func is_hull_depleted() -> bool:
	return current_ship_health <= 0.001


func get_current_hull_integrity() -> float:
	return current_ship_health


func _report_hull_depletion_if_needed() -> void:
	if hull_depletion_reported or not is_hull_depleted():
		return
	hull_depletion_reported = true
	hull_depleted.emit()


func mark_destroyed() -> void:
	if is_destroyed:
		return
	is_destroyed = true
	controller_coasting = false
	current_shield = 0.0
	shield_enabled = false
	has_destination = false
	heading_lock_course_active = false
	destination_binding.clear()
	manual_heading_active = false
	route_waypoints.clear()
	route_waypoint_bindings.clear()
	automatic_course_active = false
	automatic_course_binding.clear()
	pending_route_waypoints.clear()
	pending_route_bindings.clear()
	course_preview_active = false
	course_preview_binding.clear()
	course_preview_heading_lock = false
	velocity = Vector2.ZERO
	set_physics_process(false)


func apply_room_damage(room_id: StringName, amount: float) -> void:
	for room: Dictionary in rooms:
		if room["id"] == room_id:
			room["current_health"] = maxf(float(room["current_health"]) - maxf(amount, 0.0), 0.0)
			_report_hull_depletion_if_needed()
			return


func apply_center_mass_damage(amount: float) -> void:
	if amount <= 0.0 or rooms.is_empty():
		return
	var target_room_id: StringName = rooms[0]["id"]
	for room: Dictionary in rooms:
		if room["type_name"] == "UNASSIGNED" and float(room["current_health"]) > 0.0:
			target_room_id = room["id"]
			break
	apply_room_damage(target_room_id, amount)


func repair_room(room_id: StringName, amount: float) -> void:
	var repair_remaining := maxf(amount, 0.0)
	var definition := _layout_room_definition(room_id)
	if definition != null and repair_remaining > 0.0:
		var rects: Array[Rect2i] = definition.get("grid_rects")
		for index: int in range(rects.size()):
			var key := _module_piece_key(definition, index)
			var damaged := float(module_damage.get(key, 0.0))
			if damaged <= 0.0:
				continue
			var repaired := minf(damaged, repair_remaining)
			module_damage[key] = damaged - repaired
			repair_remaining -= repaired
			if float(module_damage[key]) <= 0.001:
				module_damage.erase(key)
			if repair_remaining <= 0.001:
				break
	for room: Dictionary in rooms:
		if room["id"] == room_id:
			room["current_health"] = minf(
				float(room["current_health"]) + maxf(amount, 0.0),
				float(room["maximum_health"])
			)
			if float(room["current_health"]) > 0.001:
				room_breach_overdamage[room_id] = 0.0
			return


func get_room_health_percentage(room_id: StringName) -> float:
	for room: Dictionary in rooms:
		if room["id"] == room_id:
			var maximum_health: float = room["maximum_health"]
			if maximum_health <= 0.0:
				return 0.0
			return 100.0 * float(room["current_health"]) / maximum_health
	return 0.0


func get_room_data(room_id: StringName) -> Dictionary:
	for room: Dictionary in rooms:
		if room["id"] == room_id:
			return room
	return {}


func get_room_type_name(room_id: StringName) -> String:
	var room := get_room_data(room_id)
	if room.is_empty():
		return "UNKNOWN"
	return room["type_name"]


func get_room_efficiency(room_id: StringName) -> float:
	for room: Dictionary in rooms:
		if room["id"] == room_id:
			if not room["produces_output"]:
				return 0.0
			var type_name := String(room["type_name"])
			var health_factor := get_room_health_percentage(room_id) / 100.0
			var module_factor := _room_module_operational_factor(room_id)
			if module_factor <= 0.0:
				return 0.0
			var group_bonus := get_room_group_bonus(room_id)
			var manning_efficiency := 0.0
			var crew := get_tree().get_first_node_in_group("crew_simulation")
			if is_instance_valid(crew):
				manning_efficiency = crew.call("get_room_manning_efficiency", room_id)
			if type_name == "PROPULSION":
				var staffed_output := health_factor * manning_efficiency * get_engine_power_factor()
				var auxiliary_output := health_factor * get_adjacent_engine_health_factor(room_id) * adjacent_unmanned_thruster_factor
				return clampf(maxf(staffed_output, auxiliary_output) * group_bonus * module_factor, 0.0, 1.3)
			if _room_type_generates_power(type_name):
				var baseline := health_factor * unmanned_power_generation_factor
				return clampf(maxf(baseline, health_factor * manning_efficiency) * group_bonus * module_factor, 0.0, 1.3)
			return health_factor * manning_efficiency * get_room_power_factor(room_id) * group_bonus * module_factor
	return 0.0


func get_weapon_mount_efficiency(room_id: StringName, mount_index: int) -> float:
	var layout_room: Resource = null
	if ship_layout != null:
		for candidate: Resource in ship_layout.get("rooms"):
			if candidate.get("room_id") == room_id:
				layout_room = candidate
				break
	if layout_room == null or String(layout_room.get("type_name")) != "WEAPONS":
		return get_room_efficiency(room_id)
	var room_data := get_room_data(room_id)
	if room_data.is_empty() or not bool(room_data.get("produces_output", false)):
		return 0.0
	var mount_count := maxi(int(layout_room.get("installed_piece_count")), 1)
	if mount_index < 0 or mount_index >= mount_count:
		return 0.0
	var operating_crew := 0
	var crew := get_tree().get_first_node_in_group("crew_simulation")
	if is_instance_valid(crew):
		operating_crew = int(crew.call("get_room_staffing", room_id))
	var staffing_factor := 1.0
	if not ROOM_STAFFING_RULES.is_unmanned_exterior_module(layout_room):
		staffing_factor = calculate_weapon_mount_staffing_factor(
			operating_crew,
			int(layout_room.get("minimum_crew")),
			int(layout_room.get("optimal_crew")),
			mount_index,
			mount_count
		)
	if staffing_factor <= 0.0:
		return 0.0
	if is_module_piece_disabled(room_id, mount_index):
		return 0.0
	var health_factor := get_room_health_percentage(room_id) / 100.0
	return health_factor * staffing_factor * get_room_power_factor(room_id) * get_room_group_bonus(room_id)


static func calculate_weapon_mount_staffing_factor(
	operating_crew: int,
	total_minimum: int,
	total_optimal: int,
	mount_index: int,
	mount_count: int
) -> float:
	mount_count = maxi(mount_count, 1)
	var minimum_per_mount := maxi(ceili(float(maxi(total_minimum, 0)) / float(mount_count)), 1)
	var optimal_per_mount := maxi(ceili(float(maxi(total_optimal, total_minimum)) / float(mount_count)), minimum_per_mount)
	var crew_for_mount := clampi(operating_crew - mount_index * optimal_per_mount, 0, optimal_per_mount)
	if crew_for_mount < minimum_per_mount:
		return 0.0
	if optimal_per_mount <= minimum_per_mount:
		return 1.0
	return lerpf(
		float(minimum_per_mount) / float(optimal_per_mount),
		1.0,
		float(crew_for_mount - minimum_per_mount) / float(optimal_per_mount - minimum_per_mount)
	)


func get_room_group_bonus(room_id: StringName) -> float:
	if ship_layout == null:
		return 1.0
	for layout_room: Resource in ship_layout.get("rooms"):
		if layout_room.get("room_id") != room_id:
			continue
		var piece_count := maxi(int(layout_room.get("installed_piece_count")), 1)
		# Shared utilities and command paths reward compact banks without making a
		# large battery strictly dominate several independent rooms.
		return 1.0 + minf(float(piece_count - 1) * 0.06, 0.30)
	return 1.0


func get_room_power_factor(room_id: StringName) -> float:
	var type_name := get_room_type_name(room_id)
	if _room_type_generates_power(type_name):
		return 1.0
	var report := _get_local_power_network_report()
	var power_factor := float(report.get("room_factors", {}).get(room_id, 0.0))
	if room_type_has_basic_unpowered_operation(type_name):
		return maxf(power_factor, basic_room_unpowered_output_factor)
	return power_factor


func get_power_grid_factor() -> float:
	if ship_layout == null:
		return 0.0
	var report := _get_local_power_network_report()
	var total_demand := 0.0
	var powered_demand := 0.0
	for network: Dictionary in report.get("networks", []):
		var demand := float(network.get("demand", 0.0))
		total_demand += demand
		powered_demand += demand * float(network.get("factor", 0.0))
	total_demand += float(report.get("uncovered_demand", 0.0))
	if total_demand <= 0.0:
		return 1.0
	return clampf(powered_demand / total_demand, 0.0, 1.0)


func get_power_network_report() -> Dictionary:
	return _get_local_power_network_report().duplicate(true)


func _get_local_power_network_report() -> Dictionary:
	var frame := Engine.get_process_frames()
	if power_network_cache_frame == frame and not power_network_cache.is_empty():
		return power_network_cache
	var generator_factors: Dictionary = {}
	for room: Dictionary in rooms:
		if not _room_type_generates_power(String(room["type_name"])):
			continue
		var room_id: StringName = room["id"]
		var health_factor := get_room_health_percentage(room_id) / 100.0
		var module_factor := _room_module_operational_factor(room_id)
		var manning := 0.0
		var crew := get_tree().get_first_node_in_group("crew_simulation")
		if is_instance_valid(crew):
			manning = float(crew.call("get_room_manning_efficiency", room_id))
		var output := 0.0
		if bool(room["produces_output"]):
			output = health_factor * maxf(unmanned_power_generation_factor, manning) * module_factor
		generator_factors[room_id] = clampf(output, 0.0, 1.3)
	power_network_cache = SHIP_RESOURCE_ANALYZER.power_network_report(ship_layout, generator_factors)
	power_network_cache_frame = frame
	return power_network_cache


func room_type_has_basic_unpowered_operation(type_name: String) -> bool:
	return type_name in ["COMMAND", "BRIDGE", "PROPULSION", "CREW", "CREW_QUARTERS"]


func _room_type_generates_power(type_name: String) -> bool:
	return type_name in ["POWER", "REACTOR", "ENGINE"]


func get_room_type_efficiency(type_name: String) -> float:
	var total := 0.0
	var count := 0
	for room: Dictionary in rooms:
		if String(room["type_name"]) == type_name and bool(room["produces_output"]):
			total += get_room_efficiency(room["id"])
			count += 1
	return total / float(count) if count > 0 else 1.0


func get_room_type_health_factor(type_name: String) -> float:
	var total := 0.0
	var count := 0
	for room: Dictionary in rooms:
		if String(room["type_name"]) == type_name and bool(room["produces_output"]):
			total += get_room_health_percentage(room["id"]) / 100.0
			count += 1
	return total / float(count) if count > 0 else 0.0


func get_engine_power_factor() -> float:
	var power_health := get_room_type_health_factor("POWER")
	if power_health <= 0.0:
		return no_engine_propulsion_fallback
	var manned_power := get_power_grid_factor()
	var baseline := power_health * unmanned_engine_propulsion_factor
	return clampf(maxf(baseline, manned_power), 0.0, 1.0)


func has_adjacent_engine_grid(room_id: StringName) -> bool:
	return get_adjacent_engine_health_factor(room_id) > 0.0


func get_adjacent_engine_health_factor(room_id: StringName) -> float:
	if ship_layout == null:
		return 0.0
	var source_cells := _layout_room_cells(room_id)
	if source_cells.is_empty():
		return 0.0
	var best_health := 0.0
	for definition: Resource in ship_layout.get("rooms"):
		var engine_type := String(definition.get("type_name"))
		if engine_type not in ["POWER", "REACTOR", "ENGINE"]:
			continue
		var engine_cells := _definition_cells(definition)
		if not _cell_sets_share_edge(source_cells, engine_cells):
			continue
		var engine_id: StringName = definition.get("room_id")
		best_health = maxf(best_health, get_room_health_percentage(engine_id) / 100.0)
	return clampf(best_health, 0.0, 1.0)


func get_unmanned_propulsion_baseline(room_id: StringName) -> float:
	if get_room_type_name(room_id) != "PROPULSION":
		return 0.0
	var health_factor := get_room_health_percentage(room_id) / 100.0
	return clampf(health_factor * get_adjacent_engine_health_factor(room_id) * adjacent_unmanned_thruster_factor, 0.0, 1.0)


func get_propulsion_output_factor() -> float:
	return clampf(get_room_type_efficiency("PROPULSION"), 0.0, 1.0)


## Returns additive thrust available through each ship-local exhaust direction.
## One fully effective cell contributes 1.0 to its bank; aligned cells stack.
func get_directional_propulsion_output() -> Dictionary:
	var banks := {
		"bow": 0.0,
		"starboard": 0.0,
		"aft": 0.0,
		"port": 0.0,
		"total": 0.0,
	}
	if ship_layout == null:
		return banks
	for definition: Resource in ship_layout.get("rooms"):
		if String(definition.get("type_name")) != "PROPULSION":
			continue
		var room_id: StringName = definition.get("room_id")
		var efficiency := get_room_efficiency(room_id)
		var rects: Array[Rect2i] = definition.get("grid_rects")
		var mount_facings: Array = definition.get("module_mount_facings")
		var mount_count := maxi(int(definition.get("installed_piece_count")), 1)
		# Connected thrusters share a room, but remain independent hardware.
		# Preserve every mount's exhaust direction when building the flight model.
		if mount_count > 1 and rects.size() >= mount_count:
			for mount_index: int in range(mount_count):
				if is_module_piece_disabled(room_id, mount_index):
					continue
				var rect := rects[mount_index]
				var mount_cells := maxi(rect.size.x * rect.size.y, 1)
				var facing := (
					posmod(int(mount_facings[mount_index]), 4)
					if mount_index < mount_facings.size()
					else posmod(GRID_GEOMETRY.resolved_module_facing(ship_layout, definition), 4)
				)
				_add_directional_propulsion_output(banks, facing, float(mount_cells) * efficiency)
		else:
			if is_module_piece_disabled(room_id, 0):
				continue
			var cell_count := _definition_cell_count(definition)
			var facing := posmod(GRID_GEOMETRY.resolved_module_facing(ship_layout, definition), 4)
			_add_directional_propulsion_output(banks, facing, float(cell_count) * efficiency)
	return banks


func _add_directional_propulsion_output(banks: Dictionary, facing: int, output: float) -> void:
	match posmod(facing, 4):
		0:
			banks["bow"] = float(banks["bow"]) + output
		1:
			banks["starboard"] = float(banks["starboard"]) + output
		2:
			banks["aft"] = float(banks["aft"]) + output
		3:
			banks["port"] = float(banks["port"]) + output
	banks["total"] = float(banks["total"]) + output


## Converts directional bank strength into the movement axes used by the helm.
## A single healthy aft thruster preserves the original handling baseline.
func get_propulsion_command_profile() -> Dictionary:
	var banks := get_directional_propulsion_output()
	var aft_output := float(banks["aft"])
	var bow_output := float(banks["bow"])
	var port_output := float(banks["port"])
	var starboard_output := float(banks["starboard"])
	var side_output := port_output + starboard_output
	var baseline_control := clampf(float(banks["total"]), 0.0, 1.0)
	var emergency_output := baseline_control * heading_lock_emergency_rcs_factor
	var braking_output := maxf(baseline_control, bow_output + aft_output * 0.35)
	var maneuver_output := maxf(baseline_control, side_output + (aft_output + bow_output) * 0.25)
	return {
		"banks": banks,
		"forward_acceleration": acceleration * aft_output,
		"translation_forward_acceleration": acceleration * maxf(aft_output, emergency_output),
		"translation_reverse_acceleration": acceleration * maxf(bow_output, emergency_output),
		"translation_starboard_acceleration": acceleration * maxf(port_output, emergency_output),
		"translation_port_acceleration": acceleration * maxf(starboard_output, emergency_output),
		"braking_acceleration": braking_acceleration * braking_output,
		"angular_acceleration": deg_to_rad(turn_acceleration_degrees) * maneuver_output,
		"lateral_acceleration": lateral_stabilization_acceleration * maneuver_output,
	}


func _update_controller_helm(delta: float) -> void:
	var profile := get_propulsion_command_profile()
	var forward := Vector2.UP.rotated(ship_rotation)
	var starboard := Vector2.RIGHT.rotated(ship_rotation)
	var target_world_velocity := (
		starboard * controller_translation_input.x
		+ forward * controller_translation_input.y
	) * maximum_speed
	var desired_angular_velocity := controller_turn_input * deg_to_rad(turn_speed_degrees)
	if is_instance_valid(physics_body):
		var forward_speed := physics_body.linear_velocity.dot(forward)
		var controller_brake := maxf(-controller_translation_input.y, 0.0)
		if controller_brake > 0.001 and forward_speed > 0.5:
			physics_body.call(
				"set_controller_brake_command",
				controller_brake,
				desired_angular_velocity,
				float(profile["braking_acceleration"]),
				float(profile["angular_acceleration"])
			)
			return
		var heading_alignment := (
			absf(controller_translation_input.y)
			* (1.0 - absf(controller_translation_input.x))
		)
		_command_physics_translation(
			target_world_velocity,
			desired_angular_velocity,
			profile,
			Vector2(-controller_translation_input.x, controller_translation_input.y),
			heading_alignment
		)
		return
	var fallback_forward_speed := velocity.dot(forward)
	var fallback_brake := maxf(-controller_translation_input.y, 0.0)
	if fallback_brake > 0.001 and fallback_forward_speed > 0.5:
		var braking_step := float(profile["braking_acceleration"]) * fallback_brake * delta
		velocity -= forward * minf(fallback_forward_speed, braking_step)
		ship_position += velocity * delta
		ship_rotation += desired_angular_velocity * delta
		return
	var fallback_acceleration := float(profile["forward_acceleration"])
	velocity = velocity.move_toward(target_world_velocity, fallback_acceleration * delta)
	ship_position += velocity * delta
	ship_rotation += desired_angular_velocity * delta


func _layout_room_cells(room_id: StringName) -> Dictionary:
	if ship_layout == null:
		return {}
	for definition: Resource in ship_layout.get("rooms"):
		if StringName(definition.get("room_id")) == room_id:
			return _definition_cells(definition)
	return {}


func _definition_cells(definition: Resource) -> Dictionary:
	var cells: Dictionary = {}
	for rect: Rect2i in definition.get("grid_rects"):
		for y: int in range(rect.position.y, rect.end.y):
			for x: int in range(rect.position.x, rect.end.x):
				cells[Vector2i(x, y)] = true
	return cells


func _cell_sets_share_edge(first: Dictionary, second: Dictionary) -> bool:
	const CARDINAL_DIRECTIONS: Array[Vector2i] = [
		Vector2i.LEFT,
		Vector2i.RIGHT,
		Vector2i.UP,
		Vector2i.DOWN,
	]
	for cell_value: Variant in first.keys():
		var cell: Vector2i = cell_value
		for direction: Vector2i in CARDINAL_DIRECTIONS:
			if second.has(cell + direction):
				return true
	return false


func get_hull_percentage() -> float:
	if maximum_ship_health <= 0.0:
		return 0.0
	return 100.0 * current_ship_health / maximum_ship_health


func refresh_rooms_from_layout() -> void:
	# A live refit can change generators and consumers while the scene tree is
	# paused. In that state the process-frame counter does not advance, so the
	# frame-scoped power report must be invalidated explicitly before anything
	# queries the rebuilt layout.
	power_network_cache.clear()
	power_network_cache_frame = -1
	var previous_health_ratio := current_ship_health / maximum_ship_health if maximum_ship_health > 0.0 else 1.0
	_initialize_rooms_from_layout()
	_initialize_ship_health(previous_health_ratio)
	_initialize_directional_shields()
	hull_depletion_reported = false
	_initialize_structural_state(true)
	if is_instance_valid(capital_ship_instance):
		capital_ship_instance.set("layout", ship_layout)
		capital_ship_instance.set("structural_state", structural_state)
	var crew := get_tree().get_first_node_in_group("crew_simulation")
	if is_instance_valid(crew) and crew.has_method("refresh_work_slots"):
		crew.call("refresh_work_slots", ship_layout)
	if is_instance_valid(physics_body) and physics_body.has_method("configure_layout"):
		physics_body.call("configure_layout", ship_layout)


func _initialize_rooms_from_layout() -> void:
	var previous_health: Dictionary = {}
	for existing_room: Dictionary in rooms:
		previous_health[existing_room["id"]] = existing_room["current_health"]
	rooms.clear()
	if ship_layout == null:
		push_error("ShipSimulation requires a ship layout resource.")
		return

	var room_definitions: Array = ship_layout.get("rooms")
	for definition: Resource in room_definitions:
		var maximum_health := ROOM_STAFFING_RULES.effective_maximum_health(
			definition,
			float(definition.get("maximum_health"))
		)
		var room_id: StringName = definition.get("room_id")
		rooms.append({
			"id": room_id,
			"name": definition.get("display_name"),
			"type_name": definition.get("type_name"),
			"effect_label": definition.get("effect_label"),
			"description": definition.get("description"),
			"maximum_health": maximum_health,
			"current_health": minf(float(previous_health.get(room_id, maximum_health)), maximum_health),
			"produces_output": definition.get("produces_output"),
			"contributes_to_hull": definition.get("contributes_to_hull"),
			"weapon_definition": definition.get("weapon_definition"),
			"storage_role": definition.get("storage_role"),
			"storage_capacity_per_cell": definition.get("storage_capacity_per_cell"),
			"storage_cell_count": _definition_cell_count(definition),
		})
	_sync_runtime_room_health_from_modules()


func _sync_runtime_room_health_from_modules() -> void:
	if module_damage.is_empty():
		return
	for room: Dictionary in rooms:
		var definition := _layout_room_definition(room["id"])
		if definition == null:
			continue
		var total_piece_damage := 0.0
		var has_piece_damage := false
		var rects: Array[Rect2i] = definition.get("grid_rects")
		for index: int in range(rects.size()):
			var key := _module_piece_key(definition, index)
			if module_damage.has(key):
				has_piece_damage = true
				total_piece_damage += float(module_damage[key])
		if has_piece_damage:
			room["current_health"] = maxf(float(room["maximum_health"]) - total_piece_damage, 0.0)


func _initialize_ship_health(preserved_ratio: float = 1.0) -> void:
	maximum_ship_health = 0.0
	for room: Dictionary in rooms:
		if bool(room["contributes_to_hull"]):
			maximum_ship_health += float(room["maximum_health"])
	current_ship_health = maximum_ship_health * clampf(preserved_ratio, 0.0, 1.0)
	var valid_room_ids: Dictionary = {}
	for room: Dictionary in rooms:
		valid_room_ids[room["id"]] = true
	for room_id_value: Variant in room_breach_overdamage.keys():
		if not valid_room_ids.has(room_id_value):
			room_breach_overdamage.erase(room_id_value)


func _definition_cell_count(definition: Resource) -> int:
	var count := 0
	for rect: Rect2i in definition.get("grid_rects"):
		count += rect.size.x * rect.size.y
	return maxi(ceili(float(count) / 4.0), 1)


func room_provides_capability(type_name: String, capability: String) -> bool:
	match capability:
		"DAMAGE_CONTROL", "ENVIRONMENTAL_GEAR":
			return type_name == "WORKSHOP"
		"MEDICAL_CARE", "CASUALTY_RESPONSE":
			return type_name in ["MEDICAL", "MED_BAY"]
		"SECURITY_RESPONSE":
			return type_name == "SECURITY"
		"FLIGHT_SERVICE":
			return type_name == "HANGAR"
	return false


func get_capability_providers(capability: String) -> Array[Dictionary]:
	var providers: Array[Dictionary] = []
	for room: Dictionary in rooms:
		if not room_provides_capability(String(room["type_name"]), capability):
			continue
		var status := get_room_capability_status(room["id"])
		status["capability"] = capability
		providers.append(status)
	providers.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if bool(a["online"]) != bool(b["online"]):
			return bool(a["online"])
		return String(a["name"]) < String(b["name"])
	)
	return providers


func get_room_capability_status(room_id: StringName) -> Dictionary:
	var room := get_room_data(room_id)
	if room.is_empty():
		return {}
	var health_ratio := float(room["current_health"]) / maxf(float(room["maximum_health"]), 0.001)
	var pressure := structural_state.get_room_pressure(room_id) if structural_state != null else 1.0
	var power_factor := get_room_power_factor(room_id)
	var crew := get_tree().get_first_node_in_group("crew_simulation")
	var present_staff := int(crew.call("get_room_staffing", room_id)) if is_instance_valid(crew) else 0
	var reason := "READY"
	if health_ratio <= 0.25:
		reason = "HEAVY DAMAGE"
	elif pressure <= 0.2:
		reason = "NO SAFE ACCESS"
	elif power_factor <= 0.2:
		reason = "NO POWER"
	elif present_staff < 1:
		reason = "NO BAY CREW"
	var online := reason == "READY"
	var raw_channels := int(room.get("storage_cell_count", 1))
	var channels := maxi(floori(float(raw_channels) * health_ratio * power_factor), 1) if online else 0
	return {
		"id": room_id,
		"name": room["name"],
		"type_name": room["type_name"],
		"online": online,
		"reason": reason,
		"channels": channels,
		"health_ratio": health_ratio,
		"pressure": pressure,
		"power_factor": power_factor,
		"staff": present_staff,
	}


func get_capability_summary(capability: String) -> Dictionary:
	var providers := get_capability_providers(capability)
	var online := 0
	var channels := 0
	for provider: Dictionary in providers:
		if bool(provider["online"]):
			online += 1
			channels += int(provider["channels"])
	return {
		"capability": capability,
		"installed": providers.size(),
		"online": online,
		"channels": channels,
		"providers": providers,
	}


func set_targeting_doctrine(new_doctrine: TargetingDoctrine) -> void:
	targeting_doctrine = new_doctrine
	if targeting_doctrine == TargetingDoctrine.MANUAL and manual_weapon_ids.is_empty():
		select_all_weapons()


func _initialize_capital_ship_instance() -> void:
	if ship_layout == null or structural_material == null:
		return
	capital_ship_instance = CAPITAL_SHIP_INSTANCE_SCENE.instantiate()
	add_child(capital_ship_instance)
	capital_ship_instance.call(
		"configure",
		0,
		CombatSimulation.ProjectileFaction.PLAYER,
		ship_layout,
		null,
		0,
		structural_material,
		door_definition,
		false
	)
	structural_state = capital_ship_instance.get("structural_state") as ShipStructuralState
	if is_instance_valid(physics_body):
		capital_ship_instance.call("adopt_physics_body", physics_body, ship_position, ship_rotation)
		physics_body.linear_velocity = velocity


func _initialize_structural_state(force_rebuild: bool = false) -> void:
	if ship_layout == null or structural_material == null:
		return
	if structural_state != null:
		if force_rebuild:
			structural_state.reconfigure_preserving_state(ship_layout, structural_material, door_definition)
		if is_instance_valid(physics_body):
			physics_body.set_meta("structural_state", structural_state)
		return
	structural_state = ShipStructuralState.new()
	structural_state.configure(ship_layout, structural_material, door_definition)
	if is_instance_valid(physics_body):
		physics_body.set_meta("structural_state", structural_state)


func _pull_physics_state() -> void:
	if not is_instance_valid(physics_body):
		return
	ship_position = physics_body.global_position
	ship_rotation = physics_body.global_rotation
	velocity = physics_body.linear_velocity


func _command_physics_propulsion(
	forward_throttle: float,
	brake_throttle: float,
	desired_angular_velocity: float,
	supplied_profile: Dictionary = {}
) -> void:
	if not is_instance_valid(physics_body):
		return
	var profile := supplied_profile if not supplied_profile.is_empty() else get_propulsion_command_profile()
	physics_body.call(
		"set_propulsion_command",
		forward_throttle,
		brake_throttle,
		desired_angular_velocity,
		float(profile["forward_acceleration"]),
		float(profile["braking_acceleration"]),
		float(profile["angular_acceleration"]),
		float(profile["lateral_acceleration"])
	)


func _command_physics_translation(
	target_world_velocity: Vector2,
	desired_angular_velocity: float,
	profile: Dictionary,
	local_exhaust_direction: Vector2,
	heading_alignment: float = 0.0
) -> void:
	if not is_instance_valid(physics_body):
		return
	physics_body.call(
		"set_translation_command",
		target_world_velocity,
		desired_angular_velocity,
		float(profile["angular_acceleration"]),
		float(profile["lateral_acceleration"]),
		float(profile["translation_port_acceleration"]),
		float(profile["translation_starboard_acceleration"]),
		float(profile["translation_forward_acceleration"]),
		float(profile["translation_reverse_acceleration"]),
		local_exhaust_direction,
		heading_alignment
	)


func select_all_weapons() -> void:
	manual_weapon_ids.clear()
	for room: Resource in ship_layout.get("rooms"):
		if room.get("type_name") == "WEAPONS" and room.get("weapon_definition") != null:
			manual_weapon_ids.append(room.get("room_id"))


func toggle_manual_weapon(room_id: StringName) -> void:
	if manual_weapon_ids.has(room_id):
		manual_weapon_ids.erase(room_id)
	else:
		manual_weapon_ids.append(room_id)


func set_manual_target(enemy_id: int, room_id: StringName) -> void:
	manual_target_enemy_id = enemy_id
	manual_target_room_id = room_id


func clear_manual_target() -> void:
	manual_target_enemy_id = -1
	manual_target_room_id = &""


func _update_shield(delta: float) -> void:
	if not shield_installed or shield_bank_maximums.is_empty():
		current_shield = 0.0
		maximum_shield = 0.0
		return
	if shield_enabled:
		for bank_value: Variant in shield_bank_maximums.keys():
			var bank := int(bank_value)
			if not _shield_bank_is_online(bank):
				continue
			var bank_efficiency := _shield_bank_efficiency(bank)
			shield_bank_currents[bank] = minf(
				float(shield_bank_maximums[bank]),
				float(shield_bank_currents.get(bank, 0.0)) + shield_regeneration_per_second * bank_efficiency * delta
			)
	_sync_shield_totals()


func _initialize_directional_shields() -> void:
	var previous_ratios: Dictionary = {}
	for bank_value: Variant in shield_bank_maximums.keys():
		var bank := int(bank_value)
		previous_ratios[bank] = float(shield_bank_currents.get(bank, 0.0)) / maxf(float(shield_bank_maximums[bank]), 0.001)
	shield_bank_maximums.clear()
	shield_bank_currents.clear()
	shield_bank_rooms.clear()
	if ship_layout == null or not shield_installed:
		_sync_shield_totals()
		return
	for definition: Resource in ship_layout.get("rooms"):
		if String(definition.get("type_name")) != "SHIELDS":
			continue
		# A full-size shield with no installed facing is an intentionally weak
		# omnidirectional generator. Directional pieces retain the stronger,
		# exposed-edge behavior below.
		var room_facing := int(definition.get("module_facing_quarters"))
		var mount_facings: Array = definition.get("module_mount_facings")
		if room_facing < 0 and mount_facings.is_empty():
			for bank: int in range(4):
				shield_bank_maximums[bank] = float(shield_bank_maximums.get(bank, 0.0)) + omni_shield_capacity_per_bank
				var omni_rooms: Array = shield_bank_rooms.get(bank, [])
				if not omni_rooms.has(definition.get("room_id")):
					omni_rooms.append(definition.get("room_id"))
				shield_bank_rooms[bank] = omni_rooms
			continue
		for shield_piece: Resource in _directional_shield_piece_views(definition):
			var exposed := GridGeometry.room_exposed_quarters(ship_layout, shield_piece)
			var facing := GridGeometry.resolved_module_facing(ship_layout, shield_piece)
			if exposed.is_empty() or not exposed.has(facing):
				continue
			var capacity := float(_definition_cell_count(shield_piece)) * shield_capacity_per_cell
			shield_bank_maximums[facing] = float(shield_bank_maximums.get(facing, 0.0)) + capacity
			var bank_rooms: Array = shield_bank_rooms.get(facing, [])
			if not bank_rooms.has(definition.get("room_id")):
				bank_rooms.append(definition.get("room_id"))
			shield_bank_rooms[facing] = bank_rooms
	for bank_value: Variant in shield_bank_maximums.keys():
		var bank := int(bank_value)
		var ratio := float(previous_ratios.get(bank, 1.0))
		shield_bank_currents[bank] = float(shield_bank_maximums[bank]) * ratio
	_sync_shield_totals()


func _directional_shield_piece_views(room: Resource) -> Array[Resource]:
	var rects: Array[Rect2i] = room.get("grid_rects")
	var views: Array[Resource] = []
	if maxi(int(room.get("installed_piece_count")), 1) <= 1 or rects.size() <= 1:
		views.append(room)
		return views
	var facings: Array = room.get("module_mount_facings")
	for index: int in range(rects.size()):
		var view := room.duplicate(false)
		var one_rect: Array[Rect2i] = [rects[index]]
		var facing := int(room.get("module_facing_quarters"))
		if index < facings.size():
			facing = int(facings[index])
		view.set("grid_rects", one_rect)
		view.set("module_facing_quarters", facing)
		view.set("module_mount_facings", [facing])
		view.set("installed_piece_count", 1)
		views.append(view)
	return views


func _shield_bank_for_world_direction(world_direction: Vector2) -> int:
	if world_direction.is_zero_approx():
		var strongest := -1
		var strongest_charge := 0.0
		for bank_value: Variant in shield_bank_currents.keys():
			var bank := int(bank_value)
			if _shield_bank_is_online(bank) and float(shield_bank_currents[bank]) > strongest_charge:
				strongest = bank
				strongest_charge = float(shield_bank_currents[bank])
		return strongest
	var local_direction := world_direction.normalized().rotated(-ship_rotation)
	var quarter := roundi(Vector2.UP.angle_to(local_direction) / (PI * 0.5))
	return posmod(quarter, 4)


func _shield_bank_efficiency(bank: int) -> float:
	var room_ids: Array = shield_bank_rooms.get(bank, [])
	var total := 0.0
	for room_id_value: Variant in room_ids:
		total += get_room_efficiency(StringName(room_id_value))
	return total / float(room_ids.size()) if not room_ids.is_empty() else 0.0


func _shield_bank_is_online(bank: int) -> bool:
	return float(shield_bank_maximums.get(bank, 0.0)) > 0.0 and _shield_bank_efficiency(bank) > 0.0


func _sync_shield_totals() -> void:
	maximum_shield = 0.0
	current_shield = 0.0
	for maximum_value: Variant in shield_bank_maximums.values():
		maximum_shield += float(maximum_value)
	for current_value: Variant in shield_bank_currents.values():
		current_shield += float(current_value)
	current_shield = clampf(current_shield, 0.0, maximum_shield)


func get_shield_bank_report() -> Dictionary:
	var report: Dictionary = {}
	for bank: int in range(4):
		var maximum := float(shield_bank_maximums.get(bank, 0.0))
		report[bank] = {
			"current": float(shield_bank_currents.get(bank, 0.0)),
			"maximum": maximum,
			"ratio": float(shield_bank_currents.get(bank, 0.0)) / maximum if maximum > 0.0 else 0.0,
			"online": _shield_bank_is_online(bank),
			"rooms": shield_bank_rooms.get(bank, []),
		}
	return report
