extends SceneTree


func _init() -> void:
	var failures := PackedStringArray()
	var vertical_span := Rect2(Vector2(100.0, 40.0), Vector2(20.0, 80.0))
	var right_profile := GridGeometry.exterior_edge_profile(vertical_span, "PROPULSION", 1)
	var left_profile := GridGeometry.exterior_edge_profile(vertical_span, "PROPULSION", 3)
	_check_side_profile(right_profile, vertical_span, true, failures)
	_check_side_profile(left_profile, vertical_span, false, failures)

	var horizontal_span := Rect2(Vector2(40.0, 100.0), Vector2(80.0, 20.0))
	var aft_profile := GridGeometry.exterior_edge_profile(horizontal_span, "PROPULSION", 2)
	if aft_profile.is_empty() or not aft_profile[0].is_equal_approx(horizontal_span.end):
		failures.append("Aft profile no longer begins at the correct hull corner.")

	if failures.is_empty():
		print("EXTERIOR PROFILE TEST • PASS • CARDINAL SPANS KEEP TRUE DEPTH")
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	quit(1)


func _check_side_profile(profile: PackedVector2Array, rect: Rect2, faces_right: bool, failures: PackedStringArray) -> void:
	if profile.is_empty():
		failures.append("Side-facing propulsion profile was empty.")
		return
	var minimum_y := INF
	var maximum_y := -INF
	var minimum_x := INF
	var maximum_x := -INF
	for point: Vector2 in profile:
		minimum_y = minf(minimum_y, point.y)
		maximum_y = maxf(maximum_y, point.y)
		minimum_x = minf(minimum_x, point.x)
		maximum_x = maxf(maximum_x, point.x)
	if not is_equal_approx(minimum_y, rect.position.y) or not is_equal_approx(maximum_y, rect.end.y):
		failures.append("Side profile did not cover the complete vertical hull face.")
	var projection_depth := maximum_x - rect.end.x if faces_right else rect.position.x - minimum_x
	if projection_depth > rect.size.x * 0.25:
		failures.append("Side profile projection depth incorrectly scaled from room height.")
