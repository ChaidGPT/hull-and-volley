class_name ProjectileVisual
extends Node2D

## Projectile trails are authored at full length, but a new shot cannot already
## have a trail extending behind its muzzle. Reveal each trail only as the shell
## physically travels away from its authored socket.
var authored_trail_points: Dictionary = {}


func _ready() -> void:
	_capture_authored_trails()


func _capture_authored_trails() -> void:
	if not authored_trail_points.is_empty():
		return
	for child: Node in find_children("*", "Line2D", true, false):
		var trail := child as Line2D
		if bool(trail.get_meta("grows_from_muzzle", false)):
			authored_trail_points[trail] = trail.points


func set_travel_distance(distance: float) -> void:
	_capture_authored_trails()
	var revealed := maxf(distance, 0.0)
	for trail_value: Variant in authored_trail_points.keys():
		var trail := trail_value as Line2D
		if not is_instance_valid(trail):
			continue
		var source: PackedVector2Array = authored_trail_points[trail]
		var points := PackedVector2Array()
		for source_point: Vector2 in source:
			points.append(Vector2(maxf(source_point.x, -revealed), source_point.y))
		trail.points = points
		trail.visible = points.size() >= 2 and not points[0].is_equal_approx(points[points.size() - 1])
