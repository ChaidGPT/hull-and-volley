extends SceneTree

const CREW_SIMULATION := preload("res://scripts/crew_simulation.gd")
const TEST_LAYOUT := preload("res://resources/ship_designs/barebones_starter.tres")


func _initialize() -> void:
	var crew: Node = CREW_SIMULATION.new()
	var obstacles: Array = crew.get("furniture_obstacles")
	obstacles.append(Rect2(Vector2(-0.35, -0.05), Vector2(0.70, 0.55)))

	var approaching_member := {"resting": false}
	var start := Vector2(0.0, -0.55)
	var target := Vector2(0.0, 0.75)
	var desired := start.move_toward(target, 0.10)
	var first_step: Vector2 = crew.call("_steer_around_furniture", approaching_member, start, desired, target)
	_assert(first_step.distance_to(start) > 0.001, "crew did not begin a furniture detour")
	_assert(approaching_member.has("furniture_waypoint"), "crew did not retain a stable furniture waypoint")
	var waypoint: Vector2 = approaching_member["furniture_waypoint"]
	var second_step: Vector2 = crew.call("_steer_around_furniture", approaching_member, first_step, first_step.move_toward(target, 0.10), target)
	_assert(second_step.distance_to(waypoint) < first_step.distance_to(waypoint), "crew abandoned its furniture detour")
	crew.call("_prepare_furniture_navigation_leg", approaching_member, "4:engine_door:0")
	_assert(not approaching_member.has("furniture_waypoint"), "stale furniture detour survived a navigation-leg change")
	approaching_member["furniture_waypoint"] = waypoint
	crew.call("_prepare_furniture_navigation_leg", approaching_member, "4:engine_door:0")
	_assert(approaching_member.has("furniture_waypoint"), "stable navigation leg discarded its active detour")
	crew.call("_prepare_furniture_navigation_leg", approaching_member, "4:engine_door:1")
	_assert(not approaching_member.has("furniture_waypoint"), "door-stage change retained a wall-pinning detour")

	var embedded_member := {"resting": false}
	var embedded := Vector2.ZERO
	var escape_step: Vector2 = crew.call("_steer_around_furniture", embedded_member, embedded, embedded.move_toward(target, 0.10), target)
	_assert(escape_step.distance_to(embedded) > 0.001, "embedded crew could not escape furniture")

	# A casemate can sit directly behind a room's doorway. Once the member clears
	# the jamb, the added landing leg must commit to a side aisle around it.
	obstacles.clear()
	obstacles.append(Rect2(Vector2(0.34, 1.34), Vector2(0.32, 0.44)))
	var doorway_member := {"resting": false}
	var landing := Vector2(0.5, 1.16)
	var room_target := Vector2(0.5, 1.88)
	var landing_step: Vector2 = crew.call("_steer_around_furniture", doorway_member, landing, landing.move_toward(room_target, 0.10), room_target)
	_assert(landing_step.distance_to(landing) > 0.001, "crew did not leave the far-side door landing")
	_assert(doorway_member.has("furniture_waypoint"), "door landing did not create a cannon detour")
	var landing_waypoint: Vector2 = doorway_member["furniture_waypoint"]
	_assert(absf(landing_waypoint.x - 0.5) > 0.10, "door landing did not choose a side aisle around the cannon")

	# A body that is still moving sideways can nevertheless be permanently
	# pinned against a jamb. The watchdog must judge progress toward the target,
	# not merely whether the body's velocity reached exactly zero.
	var stalled_member := {"position": Vector2.ZERO}
	var navigation_target := Vector2(1.0, 0.0)
	var detected_stall := false
	for sample_index: int in range(8):
		var sideways_shuffle := Vector2(0.0, float(sample_index % 2) * 0.01)
		stalled_member["position"] = sideways_shuffle
		detected_stall = bool(crew.call("_navigation_progress_stalled", stalled_member, sideways_shuffle, navigation_target, 0.10))
	_assert(detected_stall, "sideways doorway shuffle was not recognized as a navigation stall")
	crew.call("_reset_navigation_progress", stalled_member, navigation_target, 1.0)
	_assert(not bool(crew.call("_navigation_progress_stalled", stalled_member, Vector2(0.1, 0.0), navigation_target, 0.10)), "forward progress incorrectly triggered recovery")

	# A room slot authored before its furniture overlay must not remain a valid
	# destination after that overlay places a solid prop over the same point.
	# This was the recurring source of crew visibly walking into a mount and
	# shuffling there forever.
	obstacles.clear()
	# Keep the prop tightly centered: the crew clearance padding still covers the
	# old center slot, while the deliberately authored side slot stays usable.
	obstacles.append(Rect2(Vector2(0.46, 0.46), Vector2(0.08, 0.08)))
	crew.set("rest_slots", [{"cell": Vector2i.ZERO, "position": Vector2(0.50, 0.50)}])
	crew.set("work_slots", [{"cell": Vector2i.ZERO, "position": Vector2(0.20, 0.50)}])
	var safe_point: Vector2 = crew.call("_safe_cell_navigation_point", TEST_LAYOUT, Vector2i.ZERO)
	_assert(not bool(crew.call("_position_blocked_by_furniture", safe_point)), "safe navigation point remained inside furniture")
	_assert(safe_point.is_equal_approx(Vector2(0.20, 0.50)), "safe navigation did not fall back to the clear work position")

	crew.free()
	print("CREW FURNITURE NAVIGATION TEST - PASS - STABLE DETOUR + DOOR LANDING + PROGRESS WATCHDOG + SAFE SLOT")
	quit(0)


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error("CREW FURNITURE NAVIGATION TEST - FAIL - %s" % message)
	quit(1)
