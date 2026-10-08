class_name PhysicsShipBody
extends RigidBody2D

const GRID_GEOMETRY := preload("res://scripts/grid_geometry.gd")

signal ship_collision_detected(ship: RigidBody2D, other_body: RigidBody2D, point: Vector2, relative_velocity: Vector2)

@export_category("Hull Collision")
@export var ship_layout: Resource
@export_range(4.0, 100.0, 1.0) var tactical_cell_size := 10.0
@export_range(0.1, 100.0, 0.5) var mass_per_hull_cell := 2.0
@export_range(0.0, 1.0, 0.05) var hull_bounce := 0.15
@export_range(0.0, 1.0, 0.05) var hull_friction := 0.35
@export var merge_hull_collision_shapes := true
@export_range(0.25, 8.0, 0.25) var angular_velocity_response := 2.5
@export_range(0.1, 12.0, 0.1) var lateral_stabilization_response := 4.0
@export_range(0.0, 8.0, 0.1) var forward_drag_response := 0.35
@export_range(0.0, 10.0, 0.1) var turn_slide_drag_response := 2.0
@export_category("Flight Assist")
@export var flight_assist_enabled := true
@export_range(0.0, 20.0, 0.1) var lateral_velocity_damping := 8.0
@export_range(0.0, 20.0, 0.1) var turning_lateral_velocity_damping := 5.0
@export_range(0.0, 12.0, 0.1) var idle_forward_velocity_damping := 1.4
## Gentle all-axis slowdown while controller thrust is released. This avoids both
## endless drift and the much stronger normal flight-assist parking-brake feel.
@export_range(0.0, 4.0, 0.05) var coast_velocity_damping := 0.35
## While the controller primarily commands forward/reverse thrust, bend lateral
## slip toward the aimed heading without overriding deliberate strafe input.
@export_range(0.1, 6.0, 0.1) var controller_heading_alignment_response := 1.6
@export_range(0.0, 1.0, 0.05) var controller_heading_alignment_strength := 0.65
@export_range(0.0, 20.0, 0.1) var angular_velocity_damping := 7.0
@export_range(0.1, 8.0, 0.1) var translation_velocity_response := 2.2

var occupied_cells: Dictionary = {}
var cell_room_ids: Dictionary = {}
var commanded_forward_throttle := 0.0
var commanded_brake_throttle := 0.0
var commanded_angular_velocity := 0.0
var commanded_acceleration := 0.0
var commanded_braking_acceleration := 0.0
var commanded_angular_acceleration := 0.0
var commanded_lateral_acceleration := 0.0
var commanded_translation_active := false
var commanded_coasting := false
var commanded_translation_velocity := Vector2.ZERO
var commanded_translation_negative_x_acceleration := 0.0
var commanded_translation_positive_x_acceleration := 0.0
var commanded_translation_negative_y_acceleration := 0.0
var commanded_translation_positive_y_acceleration := 0.0
var commanded_translation_exhaust := Vector2.ZERO
var commanded_heading_alignment := 0.0


func _ready() -> void:
	add_to_group("physics_ships")
	contact_monitor = true
	max_contacts_reported = 32
	rebuild_hull_collision()


func configure_layout(layout: Resource) -> void:
	ship_layout = layout
	if ship_layout != null and ship_layout.has_method("ensure_quarter_lattice"):
		ship_layout.call("ensure_quarter_lattice")
	if is_inside_tree():
		rebuild_hull_collision()


func rebuild_hull_collision() -> void:
	for child: Node in get_children():
		if child.has_meta("generated_hull_collision"):
			child.queue_free()
	occupied_cells.clear()
	cell_room_ids.clear()
	if ship_layout == null:
		push_error("PhysicsShipBody requires a ship layout resource.")
		return

	var bounds: Rect2i = ship_layout.call("get_occupied_bounds")
	for room: Resource in ship_layout.get("rooms"):
		var rects: Array[Rect2i] = room.get("grid_rects")
		for grid_rect: Rect2i in rects:
			for y: int in range(grid_rect.position.y, grid_rect.end.y):
				for x: int in range(grid_rect.position.x, grid_rect.end.x):
					var cell := Vector2i(x, y)
					occupied_cells[cell] = true
					cell_room_ids[cell] = room.get("room_id")

	if merge_hull_collision_shapes:
		_build_merged_hull_collisions(bounds)
	else:
		_build_cell_hull_collisions(bounds)

	mass = maxf(float(occupied_cells.size()) * mass_per_hull_cell, 0.1)
	var hull_physics_material := PhysicsMaterial.new()
	hull_physics_material.bounce = hull_bounce
	hull_physics_material.friction = hull_friction
	physics_material_override = hull_physics_material


func _build_cell_hull_collisions(bounds: Rect2i) -> void:
	var geometry_size := GRID_GEOMETRY.grid_pixel_size(ship_layout, bounds, tactical_cell_size)
	for cell_value: Variant in occupied_cells.keys():
		var cell: Vector2i = cell_value
		var cell_rect := GRID_GEOMETRY.cell_rect(ship_layout, cell, bounds, tactical_cell_size)
		_add_hull_collision(cell_rect.get_center() - geometry_size * 0.5, cell_rect.size, "HullCell_%d_%d" % [cell.x, cell.y])


func _build_merged_hull_collisions(bounds: Rect2i) -> void:
	var geometry_size := GRID_GEOMETRY.grid_pixel_size(ship_layout, bounds, tactical_cell_size)
	for y: int in range(bounds.position.y, bounds.end.y):
		var run_start := INVALID_CELL()
		var previous_cell := INVALID_CELL()
		var previous_offset := Vector2(INF, INF)
		for x: int in range(bounds.position.x, bounds.end.x + 1):
			var cell := Vector2i(x, y)
			var occupied := occupied_cells.has(cell)
			var offset := GRID_GEOMETRY.cell_offset(ship_layout, cell) if occupied else Vector2(INF, INF)
			var continues_run := occupied and run_start != INVALID_CELL() and previous_cell.x == x - 1 and previous_offset == offset
			if occupied and run_start == INVALID_CELL():
				run_start = cell
				previous_cell = cell
				previous_offset = offset
			elif continues_run:
				previous_cell = cell
			else:
				if run_start != INVALID_CELL():
					_add_hull_collision_run(run_start, previous_cell, bounds, geometry_size)
				run_start = cell if occupied else INVALID_CELL()
				previous_cell = cell if occupied else INVALID_CELL()
				previous_offset = offset


func _add_hull_collision_run(start_cell: Vector2i, end_cell: Vector2i, bounds: Rect2i, geometry_size: Vector2) -> void:
	var start_rect := GRID_GEOMETRY.cell_rect(ship_layout, start_cell, bounds, tactical_cell_size)
	var end_rect := GRID_GEOMETRY.cell_rect(ship_layout, end_cell, bounds, tactical_cell_size)
	var run_rect := start_rect.merge(end_rect)
	_add_hull_collision(run_rect.get_center() - geometry_size * 0.5, run_rect.size, "HullRun_%d_%d_%d" % [start_cell.y, start_cell.x, end_cell.x])


func _add_hull_collision(local_center: Vector2, shape_size: Vector2, collision_name: String) -> void:
	var shape := RectangleShape2D.new()
	shape.size = shape_size
	var collision := CollisionShape2D.new()
	collision.name = collision_name
	collision.shape = shape
	collision.position = local_center
	collision.set_meta("generated_hull_collision", true)
	add_child(collision)


func INVALID_CELL() -> Vector2i:
	return Vector2i(2147483647, 2147483647)


func has_hull_cell(cell: Vector2i) -> bool:
	return occupied_cells.has(cell)


func get_hull_cell_count() -> int:
	return occupied_cells.size()


## Conservative radius enclosing the generated grid hull, used by autonomous collision avoidance.
func get_hull_bounding_radius() -> float:
	if ship_layout == null or occupied_cells.is_empty():
		return tactical_cell_size
	var bounds: Rect2i = ship_layout.call("get_occupied_bounds")
	var geometry_size := GRID_GEOMETRY.grid_pixel_size(ship_layout, bounds, tactical_cell_size)
	var radius := 0.0
	for cell_value: Variant in occupied_cells.keys():
		var cell: Vector2i = cell_value
		var center := GRID_GEOMETRY.cell_rect(ship_layout, cell, bounds, tactical_cell_size).get_center() - geometry_size * 0.5
		radius = maxf(radius, center.length() + tactical_cell_size * 0.72)
	return radius


func get_room_id_nearest_world_point(world_point: Vector2) -> StringName:
	var nearest_cell := get_cell_nearest_world_point(world_point)
	return cell_room_ids.get(nearest_cell, &"") if nearest_cell != Vector2i(2147483647, 2147483647) else &""


func get_cell_nearest_world_point(world_point: Vector2) -> Vector2i:
	if ship_layout == null or occupied_cells.is_empty():
		return Vector2i(2147483647, 2147483647)
	var bounds: Rect2i = ship_layout.call("get_occupied_bounds")
	var local_point := to_local(world_point)
	var geometry_size := GRID_GEOMETRY.grid_pixel_size(ship_layout, bounds, tactical_cell_size)
	var nearest_cell := Vector2i.ZERO
	var nearest_distance := INF
	for cell_value: Variant in occupied_cells.keys():
		var cell: Vector2i = cell_value
		var cell_center := GRID_GEOMETRY.cell_rect(ship_layout, cell, bounds, tactical_cell_size).get_center() - geometry_size * 0.5
		var distance := local_point.distance_squared_to(cell_center)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest_cell = cell
	return nearest_cell


func get_world_point_for_cell(cell: Vector2i) -> Vector2:
	if ship_layout == null or not occupied_cells.has(cell):
		return global_position
	var bounds: Rect2i = ship_layout.call("get_occupied_bounds")
	var geometry_size := GRID_GEOMETRY.grid_pixel_size(ship_layout, bounds, tactical_cell_size)
	var local_center := GRID_GEOMETRY.cell_rect(ship_layout, cell, bounds, tactical_cell_size).get_center() - geometry_size * 0.5
	return to_global(local_center)


func set_propulsion_command(
	forward_throttle: float,
	brake_throttle: float,
	target_angular_velocity: float,
	linear_acceleration: float,
	braking_acceleration: float,
	angular_acceleration: float,
	lateral_acceleration: float
) -> void:
	commanded_translation_active = false
	commanded_coasting = false
	commanded_heading_alignment = 0.0
	commanded_translation_velocity = Vector2.ZERO
	commanded_translation_exhaust = Vector2.ZERO
	commanded_forward_throttle = clampf(forward_throttle, 0.0, 1.0)
	commanded_brake_throttle = clampf(brake_throttle, 0.0, 1.0)
	commanded_angular_velocity = target_angular_velocity
	commanded_acceleration = maxf(linear_acceleration, 0.0)
	commanded_braking_acceleration = maxf(braking_acceleration, 0.0)
	commanded_angular_acceleration = maxf(angular_acceleration, 0.0)
	commanded_lateral_acceleration = maxf(lateral_acceleration, 0.0)


func set_translation_command(
	target_world_velocity: Vector2,
	target_angular_velocity: float,
	angular_acceleration: float,
	lateral_acceleration: float,
	negative_x_acceleration: float,
	positive_x_acceleration: float,
	negative_y_acceleration: float,
	positive_y_acceleration: float,
	local_exhaust_direction: Vector2,
	heading_alignment: float = 0.0
) -> void:
	commanded_translation_active = true
	commanded_coasting = false
	commanded_heading_alignment = clampf(heading_alignment, 0.0, 1.0)
	commanded_translation_velocity = target_world_velocity
	commanded_translation_exhaust = local_exhaust_direction.limit_length(1.0)
	commanded_forward_throttle = 0.0
	commanded_brake_throttle = 0.0
	commanded_angular_velocity = target_angular_velocity
	commanded_angular_acceleration = maxf(angular_acceleration, 0.0)
	commanded_lateral_acceleration = maxf(lateral_acceleration, 0.0)
	commanded_translation_negative_x_acceleration = maxf(negative_x_acceleration, 0.0)
	commanded_translation_positive_x_acceleration = maxf(positive_x_acceleration, 0.0)
	commanded_translation_negative_y_acceleration = maxf(negative_y_acceleration, 0.0)
	commanded_translation_positive_y_acceleration = maxf(positive_y_acceleration, 0.0)


func set_coast_command() -> void:
	commanded_translation_active = false
	commanded_coasting = true
	commanded_heading_alignment = 0.0
	commanded_translation_velocity = Vector2.ZERO
	commanded_translation_exhaust = Vector2.ZERO
	commanded_forward_throttle = 0.0
	commanded_brake_throttle = 0.0
	commanded_angular_velocity = 0.0


func set_controller_brake_command(
	brake_throttle: float,
	target_angular_velocity: float,
	braking_acceleration: float,
	angular_acceleration: float
) -> void:
	# Controller braking keeps the gentle coast decay but avoids the much stronger
	# idle flight-assist damping. Stick depth controls the added braking force.
	commanded_translation_active = false
	commanded_coasting = true
	commanded_heading_alignment = 0.0
	commanded_translation_velocity = Vector2.ZERO
	commanded_translation_exhaust = Vector2.ZERO
	commanded_forward_throttle = 0.0
	commanded_brake_throttle = clampf(brake_throttle, 0.0, 1.0)
	commanded_angular_velocity = target_angular_velocity
	commanded_braking_acceleration = maxf(braking_acceleration, 0.0)
	commanded_angular_acceleration = maxf(angular_acceleration, 0.0)


func get_propulsion_visual_command() -> Dictionary:
	return {
		"forward": commanded_forward_throttle,
		"brake": commanded_brake_throttle,
		"turn": clampf(commanded_angular_velocity / deg_to_rad(12.0), -1.0, 1.0),
		"translation_exhaust": commanded_translation_exhaust if commanded_translation_active else Vector2.ZERO,
	}


func _integrate_forces(state: PhysicsDirectBodyState2D) -> void:
	var forward := Vector2.UP.rotated(state.transform.get_rotation())
	var starboard := forward.orthogonal()
	var forward_speed := state.linear_velocity.dot(forward)
	var lateral_speed := state.linear_velocity.dot(starboard)
	if flight_assist_enabled and not commanded_translation_active:
		_apply_flight_assist(
			state,
			forward,
			starboard,
			forward_speed,
			lateral_speed,
			not commanded_coasting
		)
		forward_speed = state.linear_velocity.dot(forward)
		lateral_speed = state.linear_velocity.dot(starboard)
	if commanded_coasting and coast_velocity_damping > 0.0:
		state.linear_velocity *= exp(-coast_velocity_damping * state.step)
		forward_speed = state.linear_velocity.dot(forward)
		lateral_speed = state.linear_velocity.dot(starboard)
	if commanded_translation_active:
		var velocity_error_local := (
			commanded_translation_velocity - state.linear_velocity
		).rotated(-state.transform.get_rotation())
		var requested_local_acceleration := velocity_error_local * translation_velocity_response
		requested_local_acceleration.x = clampf(
			requested_local_acceleration.x,
			-commanded_translation_negative_x_acceleration,
			commanded_translation_positive_x_acceleration
		)
		requested_local_acceleration.y = clampf(
			requested_local_acceleration.y,
			-commanded_translation_negative_y_acceleration,
			commanded_translation_positive_y_acceleration
		)
		commanded_translation_exhaust = (
			-requested_local_acceleration.normalized()
			if requested_local_acceleration.length_squared() > 0.0001
			else Vector2.ZERO
		)
		state.apply_central_force(
			requested_local_acceleration.rotated(state.transform.get_rotation()) * mass
		)
		if commanded_heading_alignment > 0.001:
			var desired_lateral_speed := commanded_translation_velocity.dot(starboard)
			var lateral_velocity_error := desired_lateral_speed - lateral_speed
			var alignment_acceleration_limit := (
				commanded_lateral_acceleration
				* controller_heading_alignment_strength
				* commanded_heading_alignment
			)
			var alignment_acceleration := clampf(
				lateral_velocity_error * controller_heading_alignment_response,
				-alignment_acceleration_limit,
				alignment_acceleration_limit
			)
			state.apply_central_force(starboard * mass * alignment_acceleration)
	elif commanded_forward_throttle > 0.0:
		state.apply_central_force(forward * mass * commanded_acceleration * commanded_forward_throttle)
	if not commanded_translation_active and commanded_brake_throttle > 0.0 and absf(forward_speed) > 0.001:
		# Main-engine braking regulates longitudinal motion only. Projectile hits
		# to the flank create lateral velocity, which belongs to flight assist;
		# treating total velocity as forward overspeed allowed side fire to pin
		# the ship in place by holding its main brakes on.
		state.apply_central_force(
			-forward * signf(forward_speed)
			* mass
			* commanded_braking_acceleration
			* commanded_brake_throttle
		)
	if not commanded_translation_active:
		var lateral_acceleration := clampf(
			-lateral_speed * lateral_stabilization_response,
			-commanded_lateral_acceleration,
			commanded_lateral_acceleration
		)
		state.apply_central_force(starboard * mass * lateral_acceleration)
	if not commanded_translation_active and not commanded_coasting and absf(forward_speed) > 0.001 and commanded_forward_throttle <= 0.01:
		state.apply_central_force(forward * mass * -forward_speed * forward_drag_response)
	if not commanded_translation_active and absf(lateral_speed) > 0.001 and absf(commanded_angular_velocity) > 0.001:
		var turn_slide_drag := minf(
			absf(commanded_angular_velocity) / deg_to_rad(20.0),
			1.0
		)
		state.apply_central_force(
			starboard
			* mass
			* -lateral_speed
			* turn_slide_drag_response
			* turn_slide_drag
		)
	var angular_velocity_error := commanded_angular_velocity - state.angular_velocity
	var desired_angular_acceleration := clampf(
		angular_velocity_error * angular_velocity_response,
		-commanded_angular_acceleration,
		commanded_angular_acceleration
	)
	if state.inverse_inertia > 0.0:
		state.apply_torque(desired_angular_acceleration / state.inverse_inertia)
	for contact_index: int in range(state.get_contact_count()):
		var other_body := state.get_contact_collider_object(contact_index) as RigidBody2D
		if not is_instance_valid(other_body):
			continue
		if not other_body.is_in_group("physics_ships") and not other_body.is_in_group("sector_obstacles"):
			continue
		# DirectBodyState reports the contact in this body's local coordinates.
		# Combat damage routing expects a world point; passing the local value made
		# impacts far from the origin select an unrelated edge module.
		var point := to_global(state.get_contact_local_position(contact_index))
		var other_velocity := state.get_contact_collider_velocity_at_position(contact_index)
		call_deferred(
			"_emit_ship_collision",
			other_body,
			point,
			state.linear_velocity - other_velocity
		)
		break


func _apply_flight_assist(
	state: PhysicsDirectBodyState2D,
	forward: Vector2,
	starboard: Vector2,
	forward_speed: float,
	lateral_speed: float,
	apply_linear_damping: bool = true
) -> void:
	var step := state.step
	var lateral_damping := lateral_velocity_damping
	if absf(commanded_angular_velocity) > 0.001:
		var turn_amount := minf(absf(commanded_angular_velocity) / deg_to_rad(20.0), 1.0)
		lateral_damping += turning_lateral_velocity_damping * turn_amount
	if apply_linear_damping and lateral_damping > 0.0 and absf(lateral_speed) > 0.001:
		var lateral_keep := exp(-lateral_damping * step)
		state.linear_velocity += starboard * (lateral_speed * lateral_keep - lateral_speed)

	if apply_linear_damping and commanded_forward_throttle <= 0.01 and idle_forward_velocity_damping > 0.0 and absf(forward_speed) > 0.001:
		var forward_keep := exp(-idle_forward_velocity_damping * step)
		state.linear_velocity += forward * (forward_speed * forward_keep - forward_speed)

	if angular_velocity_damping > 0.0:
		var angular_keep := exp(-angular_velocity_damping * step)
		var target_angular_velocity := commanded_angular_velocity
		state.angular_velocity = target_angular_velocity + (state.angular_velocity - target_angular_velocity) * angular_keep


func _emit_ship_collision(other_body: RigidBody2D, point: Vector2, relative_velocity: Vector2) -> void:
	ship_collision_detected.emit(self, other_body, point, relative_velocity)
