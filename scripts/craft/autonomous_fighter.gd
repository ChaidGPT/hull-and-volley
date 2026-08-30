class_name AutonomousFighter
extends RigidBody2D

signal fire_requested(fighter: AutonomousFighter, target_position: Vector2)
signal recovery_requested(fighter: AutonomousFighter)
signal destroyed_in_combat(fighter: AutonomousFighter, world_position: Vector2)

enum FlightState { LAUNCHING, PURSUIT, ATTACK_RUN, BREAKAWAY, REPOSITION, RETURNING, DOCKING }

var behavior: Resource
var carrier: RigidBody2D
var target: RigidBody2D
var capital_target: RigidBody2D
var operating_radius := 500.0
var faction := 0
var flight_state := FlightState.LAUNCHING
var launch_timer := 0.0
var fire_timer := 0.0
var launch_heading := Vector2.UP
var carrier_collision_ignored := true
var current_hull := 1.0
var maneuver_timer := 0.0
var committed_heading := Vector2.UP
var reposition_side := 1.0
var speed_factor := 1.0
var acceleration_factor := 1.0
var timing_factor := 1.0
var commit_delay := 0.0
var rng := RandomNumberGenerator.new()
var hangar_local_position := Vector2.ZERO
var hangar_local_direction := Vector2.UP
var guidance_direction := Vector2.UP
var target_lock_timer := 0.0
var avoidance_urgency := 0.0
var avoidance_correction := Vector2.ZERO


func configure(profile: Resource, carrier_body: RigidBody2D, target_body: RigidBody2D, radius: float, craft_faction: int, hangar_world_position: Vector2, hangar_world_direction: Vector2) -> void:
	behavior = profile
	carrier = carrier_body
	target = target_body
	capital_target = target_body
	operating_radius = radius
	faction = craft_faction
	launch_timer = float(behavior.get("launch_clearance_time"))
	launch_heading = Vector2.UP.rotated(global_rotation)
	guidance_direction = launch_heading
	hangar_local_position = carrier.to_local(hangar_world_position)
	hangar_local_direction = hangar_world_direction.rotated(-carrier.global_rotation).normalized()
	current_hull = float(behavior.get("maximum_hull"))
	rng.randomize()
	var variation: float = float(behavior.get("behavior_variation"))
	speed_factor = rng.randf_range(1.0 - variation, 1.0 + variation)
	acceleration_factor = rng.randf_range(1.0 - variation, 1.0 + variation)
	timing_factor = rng.randf_range(1.0 - variation, 1.0 + variation)
	reposition_side = -1.0 if rng.randf() < 0.5 else 1.0
	commit_delay = rng.randf_range(0.0, float(behavior.get("maximum_commit_delay")))
	target_lock_timer = rng.randf_range(0.0, float(behavior.get("target_lock_seconds")))
	var collision_shape := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if collision_shape != null and collision_shape.shape is CircleShape2D:
		collision_shape.shape = collision_shape.shape.duplicate()
		(collision_shape.shape as CircleShape2D).radius = float(behavior.get("collision_radius"))
	set_meta("ship_faction", faction)
	set_meta("is_fighter", true)


func _physics_process(delta: float) -> void:
	if behavior == null:
		return
	if not is_instance_valid(carrier):
		queue_free()
		return
	fire_timer = maxf(fire_timer - delta, 0.0)
	launch_timer = maxf(launch_timer - delta, 0.0)
	maneuver_timer = maxf(maneuver_timer - delta, 0.0)
	commit_delay = maxf(commit_delay - delta, 0.0)
	target_lock_timer = maxf(target_lock_timer - delta, 0.0)
	if flight_state == FlightState.LAUNCHING:
		_fly_launch_corridor(delta)
		if launch_timer <= 0.0 and _has_cleared_carrier_hull():
			flight_state = FlightState.PURSUIT
			if carrier_collision_ignored and is_instance_valid(carrier):
				remove_collision_exception_with(carrier)
				carrier_collision_ignored = false
		return
	if global_position.distance_to(carrier.global_position) > operating_radius:
		flight_state = FlightState.RETURNING
	if flight_state == FlightState.RETURNING:
		_update_return_approach(delta)
		return
	if flight_state == FlightState.DOCKING:
		_update_docking(delta)
		return
	match flight_state:
		FlightState.PURSUIT:
			_update_pursuit(delta)
		FlightState.ATTACK_RUN:
			_update_attack_run(delta)
		FlightState.BREAKAWAY:
			_fly_committed_heading(delta)
			if maneuver_timer <= 0.0:
				flight_state = FlightState.REPOSITION
				maneuver_timer = float(behavior.get("reposition_timeout"))
		FlightState.REPOSITION:
			_update_reposition(delta)


func _update_pursuit(delta: float) -> void:
	_select_priority_target()
	if not is_instance_valid(target):
		flight_state = FlightState.RETURNING
		return
	if not bool(target.get_meta("is_fighter", false)) and global_position.distance_to(target.global_position) <= _capital_safe_distance(target):
		_begin_capital_avoidance()
		return
	var predicted_target := target.global_position + target.linear_velocity * float(behavior.get("intercept_lead_seconds"))
	var target_direction := global_position.direction_to(predicted_target)
	var forward := Vector2.UP.rotated(global_rotation)
	var alignment := absf(angle_difference(forward.angle(), target_direction.angle()))
	var distance := global_position.distance_to(target.global_position)
	if commit_delay <= 0.0 and distance <= float(behavior.get("attack_run_entry_distance")) * speed_factor and alignment <= deg_to_rad(float(behavior.get("attack_run_entry_degrees"))):
		committed_heading = target_direction
		flight_state = FlightState.ATTACK_RUN
		maneuver_timer = float(behavior.get("attack_run_duration")) * timing_factor
		return
	_steer_toward(predicted_target, delta)


func _update_attack_run(delta: float) -> void:
	if not is_instance_valid(target):
		_begin_breakaway()
		return
	if not bool(target.get_meta("is_fighter", false)) and global_position.distance_to(target.global_position) <= _capital_safe_distance(target):
		_begin_capital_avoidance()
		return
	_fly_committed_heading(delta)
	_try_fire()
	var target_is_behind := (target.global_position - global_position).dot(committed_heading) < 0.0
	if maneuver_timer <= 0.0 or target_is_behind:
		_begin_breakaway()


func _begin_breakaway() -> void:
	flight_state = FlightState.BREAKAWAY
	maneuver_timer = float(behavior.get("breakaway_duration")) * timing_factor


func _begin_capital_avoidance() -> void:
	var away := target.global_position.direction_to(global_position)
	if away.is_zero_approx():
		away = Vector2.UP.rotated(global_rotation)
	var tangent := away.orthogonal() * reposition_side
	committed_heading = (away * 0.65 + tangent).normalized()
	_begin_breakaway()


func _capital_safe_distance(capital_ship: RigidBody2D) -> float:
	var hull_radius := 0.0
	if capital_ship.has_method("get_hull_bounding_radius"):
		hull_radius = float(capital_ship.call("get_hull_bounding_radius"))
	return maxf(
		float(behavior.get("capital_breakaway_distance")),
		hull_radius + float(behavior.get("capital_safety_margin"))
	)


func _update_reposition(delta: float) -> void:
	_select_priority_target()
	if not is_instance_valid(target):
		flight_state = FlightState.RETURNING
		return
	var away := target.global_position.direction_to(global_position)
	if away.is_zero_approx():
		away = committed_heading
	var reposition_distance: float = float(behavior.get("reposition_distance"))
	var destination := target.global_position + (away + away.orthogonal() * reposition_side * 0.55).normalized() * reposition_distance
	_steer_toward(destination, delta)
	if global_position.distance_to(target.global_position) >= reposition_distance * 0.9 or maneuver_timer <= 0.0:
		flight_state = FlightState.PURSUIT
		commit_delay = rng.randf_range(0.0, float(behavior.get("maximum_commit_delay")))
		reposition_side = -1.0 if rng.randf() < 0.5 else 1.0


func _fly_committed_heading(delta: float) -> void:
	_apply_inertial_steering(committed_heading, delta)


func _update_return_approach(delta: float) -> void:
	var hangar_position := _hangar_world_position()
	var hangar_direction := _hangar_world_direction()
	var approach_point := hangar_position + hangar_direction * float(behavior.get("docking_approach_distance"))
	_steer_toward(approach_point, delta)
	if global_position.distance_to(approach_point) <= float(behavior.get("docking_approach_radius")):
		flight_state = FlightState.DOCKING
		if not carrier_collision_ignored:
			add_collision_exception_with(carrier)
			carrier_collision_ignored = true


func _update_docking(delta: float) -> void:
	var hangar_position := _hangar_world_position()
	var inward_target := hangar_position - _hangar_world_direction() * 8.0
	_steer_toward(inward_target, delta, false)
	if global_position.distance_to(hangar_position) <= float(behavior.get("docking_capture_distance")):
		recovery_requested.emit(self)


func _hangar_world_position() -> Vector2:
	return carrier.to_global(hangar_local_position)


func _hangar_world_direction() -> Vector2:
	return hangar_local_direction.rotated(carrier.global_rotation).normalized()


func _fly_launch_corridor(delta: float) -> void:
	# No combat steering is allowed until the fighter has physically cleared the bay.
	var inherited_velocity := carrier.linear_velocity if is_instance_valid(carrier) else Vector2.ZERO
	var desired_velocity := inherited_velocity + launch_heading * float(behavior.get("launch_speed"))
	linear_velocity = linear_velocity.move_toward(desired_velocity, float(behavior.get("acceleration")) * delta)
	global_rotation = Vector2.UP.angle_to(launch_heading)


func _has_cleared_carrier_hull() -> bool:
	if not is_instance_valid(carrier):
		return true
	var hangar_position := _hangar_world_position()
	var clearance_progress := (global_position - hangar_position).dot(launch_heading.normalized())
	var minimum_clearance := maxf(float(behavior.get("collision_radius")) * 4.0, 12.0)
	if clearance_progress < minimum_clearance:
		return false
	var space_state := get_world_2d().direct_space_state
	var query := PhysicsPointQueryParameters2D.new()
	query.position = global_position
	query.collide_with_areas = false
	query.collide_with_bodies = true
	query.collision_mask = carrier.collision_layer
	for hit: Dictionary in space_state.intersect_point(query, 16):
		if hit.get("collider") == carrier:
			return false
	return true


func _steer_toward(destination: Vector2, delta: float, avoid_obstacles: bool = true) -> void:
	var offset := destination - global_position
	if offset.length() > 3.0:
		_apply_inertial_steering(offset.normalized(), delta, avoid_obstacles)


func _apply_inertial_steering(desired_direction: Vector2, delta: float, avoid_obstacles: bool = true) -> void:
	if desired_direction.is_zero_approx():
		return
	var adjusted_direction := _apply_obstacle_avoidance(desired_direction) if avoid_obstacles else desired_direction
	if not avoid_obstacles:
		avoidance_urgency = 0.0
		avoidance_correction = Vector2.ZERO
	var guidance_turn_speed := lerpf(
		float(behavior.get("guidance_turn_degrees")),
		float(behavior.get("turn_speed_degrees")) * 1.8,
		avoidance_urgency
	)
	var guidance_angle := rotate_toward(
		guidance_direction.angle(),
		adjusted_direction.angle(),
		deg_to_rad(guidance_turn_speed) * delta
	)
	guidance_direction = Vector2.RIGHT.rotated(guidance_angle)
	var desired_rotation := Vector2.UP.angle_to(guidance_direction)
	global_rotation = rotate_toward(global_rotation, desired_rotation, deg_to_rad(float(behavior.get("turn_speed_degrees"))) * delta)
	var forward := Vector2.UP.rotated(global_rotation)
	var alignment := clampf(forward.dot(guidance_direction), -1.0, 1.0)
	var throttle := clampf((alignment + 0.25) / 1.25, float(behavior.get("minimum_turn_throttle")), 1.0)
	var acceleration: float = float(behavior.get("acceleration")) * acceleration_factor
	linear_velocity += forward * acceleration * throttle * delta
	if avoidance_urgency > 0.0 and not avoidance_correction.is_zero_approx():
		linear_velocity += avoidance_correction * acceleration * float(behavior.get("emergency_avoidance_thrust")) * avoidance_urgency * delta
	# Preserve momentum while gradually correcting lateral slip instead of replacing velocity.
	var lateral := forward.orthogonal()
	var lateral_speed := linear_velocity.dot(lateral)
	var lateral_keep := exp(-float(behavior.get("lateral_damping")) * delta)
	linear_velocity += lateral * (lateral_speed * lateral_keep - lateral_speed)
	linear_velocity *= exp(-float(behavior.get("flight_drag")) * delta)
	var maximum_speed: float = float(behavior.get("maximum_speed")) * speed_factor
	if linear_velocity.length() > maximum_speed:
		linear_velocity = linear_velocity.normalized() * maximum_speed


func _apply_obstacle_avoidance(desired_direction: Vector2) -> Vector2:
	var space_state := get_world_2d().direct_space_state
	var forward := Vector2.UP.rotated(global_rotation)
	var movement_direction := linear_velocity.normalized() if linear_velocity.length() > 8.0 else forward
	var lookahead: float = float(behavior.get("avoidance_lookahead")) + linear_velocity.length() * 0.75
	var whisker_angle := deg_to_rad(float(behavior.get("avoidance_whisker_degrees")))
	var correction := Vector2.ZERO
	var strongest_urgency := 0.0
	var ray_directions: Array[Vector2] = [
		movement_direction,
		movement_direction.rotated(-whisker_angle),
		movement_direction.rotated(whisker_angle),
		forward.rotated(-whisker_angle * 0.7),
		forward.rotated(whisker_angle * 0.7),
	]
	for ray_direction: Vector2 in ray_directions:
		var query := PhysicsRayQueryParameters2D.create(global_position, global_position + ray_direction * lookahead, 1)
		query.exclude = [get_rid()]
		var hit := space_state.intersect_ray(query)
		if hit.is_empty():
			continue
		var hit_distance := global_position.distance_to(hit["position"])
		var urgency := 1.0 - clampf(hit_distance / lookahead, 0.0, 1.0)
		urgency = urgency * urgency
		strongest_urgency = maxf(strongest_urgency, urgency)
		var normal: Vector2 = hit["normal"]
		var tangent := normal.orthogonal() * reposition_side
		correction += (normal + tangent * 0.65) * maxf(urgency, 0.15)
	avoidance_urgency = strongest_urgency
	if correction.is_zero_approx():
		avoidance_correction = Vector2.ZERO
		return desired_direction
	avoidance_correction = correction.normalized()
	return (desired_direction + avoidance_correction * float(behavior.get("avoidance_strength")) * maxf(avoidance_urgency, 0.35)).normalized()


func _select_priority_target() -> void:
	if is_instance_valid(target) and target_lock_timer > 0.0:
		return
	var nearest_fighter: RigidBody2D
	var nearest_distance := INF
	for fighter_value: Variant in get_tree().get_nodes_in_group("autonomous_fighters"):
		var fighter := fighter_value as RigidBody2D
		if not is_instance_valid(fighter) or fighter == self or int(fighter.get_meta("ship_faction", -1)) == faction:
			continue
		if carrier.global_position.distance_to(fighter.global_position) > operating_radius:
			continue
		var distance := global_position.distance_squared_to(fighter.global_position)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest_fighter = fighter
	if is_instance_valid(nearest_fighter):
		target = nearest_fighter
	elif is_instance_valid(capital_target):
		target = capital_target
	else:
		target = null
	target_lock_timer = float(behavior.get("target_lock_seconds")) * timing_factor


func _try_fire() -> void:
	if fire_timer > 0.0 or not is_instance_valid(target):
		return
	var weapon: Resource = behavior.get("weapon")
	if weapon == null:
		return
	if global_position.distance_to(target.global_position) > float(weapon.get("maximum_range")):
		return
	var forward := Vector2.UP.rotated(global_rotation)
	var target_direction := global_position.direction_to(target.global_position)
	var alignment_error := absf(angle_difference(forward.angle(), target_direction.angle()))
	if alignment_error > deg_to_rad(float(behavior.get("firing_alignment_degrees"))):
		return
	fire_timer = float(weapon.get("reload_seconds")) + float(behavior.get("firing_interval_bonus"))
	fire_requested.emit(self, target.global_position)


func apply_damage(amount: float) -> void:
	current_hull = maxf(current_hull - amount, 0.0)
	if current_hull <= 0.0:
		destroyed_in_combat.emit(self, global_position)
		queue_free()
