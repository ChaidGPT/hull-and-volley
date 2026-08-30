extends Control

@export_category("Station Silhouette")
## Main station hull fill color.
@export var hull_fill_color := Color(0.055, 0.075, 0.08, 0.94)
## Darker inner structure color.
@export var inner_hull_color := Color(0.08, 0.13, 0.14, 0.88)
## Steel-colored outer hull line.
@export var outer_hull_color := Color(0.48, 0.55, 0.56, 0.95)
## Cyan tactical glow used for active exterior infrastructure.
@export var tactical_glow_color := Color(0.24, 0.95, 1.0, 0.85)
## Orange docking clamp color.
@export var docking_color := Color(0.95, 0.58, 0.18, 0.9)
## Hangar bay color.
@export var hangar_color := Color(0.18, 0.78, 0.86, 0.84)
## Fighter marker color shown inside hangar bays.
@export var fighter_marker_color := Color(0.72, 0.96, 0.92, 0.95)

@export_category("Shape")
## Overall radius of the circular station core.
@export_range(120.0, 260.0, 2.0) var core_radius := 188.0
## Width of each capital docking arm.
@export_range(28.0, 90.0, 2.0) var docking_arm_width := 58.0
## Length of each capital docking arm.
@export_range(45.0, 140.0, 2.0) var docking_arm_length := 92.0
## Size of each fighter hangar module.
@export var hangar_size := Vector2(54.0, 36.0)

var ship_layout: Resource
var tactical_interest_room_types := PackedStringArray(["DOCKING", "WEAPONS", "HANGAR"])


func _ready() -> void:
	custom_minimum_size = Vector2(520, 544)
	size = custom_minimum_size
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_redraw()


func set_ship_layout(layout: Resource) -> void:
	ship_layout = layout


func set_low_detail_mode(_is_enabled: bool) -> void:
	pass


func set_tactical_interest_room_types(room_types: PackedStringArray) -> void:
	tactical_interest_room_types = room_types


func set_simulation_identity(_faction: int, _ship_id: int) -> void:
	pass


func set_manual_highlights(_selected_rooms: Array[StringName], _targeted_room: StringName = &"", _hovered_room: StringName = &"") -> void:
	pass


func get_room_at_local_position(_local_position: Vector2) -> Resource:
	return null


func get_room_local_center(_room_id: StringName) -> Vector2:
	return size * 0.5


func contains_tactical_point(local_position: Vector2) -> bool:
	var center := size * 0.5
	if local_position.distance_to(center) <= core_radius + 4.0:
		return true
	for direction: Vector2 in [Vector2.UP, Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT]:
		if _point_in_docking_arm(local_position, center, direction):
			return true
	for direction: Vector2 in [
		Vector2(-0.68, -0.68).normalized(),
		Vector2(0.68, -0.68).normalized(),
		Vector2(0.68, 0.68).normalized(),
		Vector2(-0.68, 0.68).normalized(),
	]:
		if _point_in_hangar_bay(local_position, center, direction):
			return true
	return false


func _draw() -> void:
	var center := size * 0.5
	_draw_station_core(center)
	_draw_docking_arm(center, Vector2.UP)
	_draw_docking_arm(center, Vector2.RIGHT)
	_draw_docking_arm(center, Vector2.DOWN)
	_draw_docking_arm(center, Vector2.LEFT)
	_draw_hangar_bay(center, Vector2(-0.68, -0.68).normalized(), 0)
	_draw_hangar_bay(center, Vector2(0.68, -0.68).normalized(), 1)
	_draw_hangar_bay(center, Vector2(0.68, 0.68).normalized(), 2)
	_draw_hangar_bay(center, Vector2(-0.68, 0.68).normalized(), 3)
	_draw_sensor_ticks(center)


func _draw_station_core(center: Vector2) -> void:
	draw_circle(center, core_radius, hull_fill_color)
	draw_circle(center, core_radius * 0.67, inner_hull_color)
	draw_arc(center, core_radius, 0.0, TAU, 96, Color(0.28, 0.86, 0.92, 0.18), 7.0, true)
	draw_arc(center, core_radius, 0.0, TAU, 96, outer_hull_color, 3.0, true)
	draw_arc(center, core_radius * 0.78, 0.0, TAU, 88, Color(0.34, 0.58, 0.6, 0.42), 2.0, true)
	draw_arc(center, core_radius * 0.46, 0.0, TAU, 72, Color(0.22, 0.42, 0.46, 0.36), 1.5, true)
	draw_line(center + Vector2(-core_radius * 0.52, 0.0), center + Vector2(core_radius * 0.52, 0.0), Color(0.24, 0.56, 0.6, 0.18), 1.0, true)
	draw_line(center + Vector2(0.0, -core_radius * 0.52), center + Vector2(0.0, core_radius * 0.52), Color(0.24, 0.56, 0.6, 0.18), 1.0, true)


func _draw_docking_arm(center: Vector2, direction: Vector2) -> void:
	if not tactical_interest_room_types.has("DOCKING"):
		return
	var side := direction.orthogonal()
	var inner := center + direction * (core_radius * 0.64)
	var outer := center + direction * (core_radius + docking_arm_length)
	var half_width := docking_arm_width * 0.5
	var points := PackedVector2Array([
		inner - side * half_width,
		inner + side * half_width,
		outer + side * half_width,
		outer - side * half_width,
	])
	draw_colored_polygon(points, Color(0.19, 0.17, 0.11, 0.88))
	draw_polyline(_closed_points(points), outer_hull_color, 2.4, true)
	var clamp_center := outer - direction * 16.0
	draw_line(clamp_center - side * (half_width - 7.0), clamp_center + side * (half_width - 7.0), docking_color, 4.0, true)
	draw_line(outer - direction * 4.0, outer + direction * 15.0, tactical_glow_color, 1.4, true)
	draw_line(outer - side * 10.0, outer + side * 10.0, tactical_glow_color, 1.2, true)


func _draw_hangar_bay(center: Vector2, direction: Vector2, index: int) -> void:
	if not tactical_interest_room_types.has("HANGAR"):
		return
	var side := direction.orthogonal()
	var bay_center := center + direction * (core_radius * 0.82)
	var half_forward := hangar_size.x * 0.5
	var half_side := hangar_size.y * 0.5
	var points := PackedVector2Array([
		bay_center - direction * half_forward - side * half_side,
		bay_center - direction * half_forward + side * half_side,
		bay_center + direction * half_forward + side * half_side,
		bay_center + direction * half_forward - side * half_side,
	])
	draw_colored_polygon(points, Color(0.05, 0.22, 0.24, 0.92))
	draw_polyline(_closed_points(points), hangar_color, 2.0, true)
	var mouth := bay_center + direction * half_forward
	draw_line(mouth - side * (half_side - 3.0), mouth + side * (half_side - 3.0), tactical_glow_color, 2.5, true)
	_draw_tiny_fighter(bay_center - side * 8.0, direction, 0.78 + float(index % 2) * 0.12)
	_draw_tiny_fighter(bay_center + side * 8.0, direction, 0.66 + float(index % 2) * 0.1)


func _draw_tiny_fighter(center: Vector2, direction: Vector2, alpha: float) -> void:
	var side := direction.orthogonal()
	var nose := center + direction * 6.0
	var rear_left := center - direction * 4.5 - side * 4.0
	var rear_right := center - direction * 4.5 + side * 4.0
	draw_polyline(PackedVector2Array([nose, rear_left, center - direction * 1.0, rear_right, nose]), Color(fighter_marker_color, alpha), 1.2, true)


func _draw_sensor_ticks(center: Vector2) -> void:
	for index: int in range(16):
		var angle := float(index) / 16.0 * TAU
		var direction := Vector2.RIGHT.rotated(angle)
		var start := center + direction * (core_radius + 8.0)
		var finish := center + direction * (core_radius + (18.0 if index % 4 == 0 else 13.0))
		draw_line(start, finish, Color(0.2, 0.78, 0.86, 0.32), 1.0, true)


func _point_in_docking_arm(point: Vector2, center: Vector2, direction: Vector2) -> bool:
	var side := direction.orthogonal()
	var rel := point - center
	var forward_distance := rel.dot(direction)
	var side_distance := absf(rel.dot(side))
	return forward_distance >= core_radius * 0.64 and forward_distance <= core_radius + docking_arm_length + 8.0 and side_distance <= docking_arm_width * 0.5 + 5.0


func _point_in_hangar_bay(point: Vector2, center: Vector2, direction: Vector2) -> bool:
	var side := direction.orthogonal()
	var bay_center := center + direction * (core_radius * 0.82)
	var rel := point - bay_center
	return absf(rel.dot(direction)) <= hangar_size.x * 0.5 + 5.0 and absf(rel.dot(side)) <= hangar_size.y * 0.5 + 5.0


func _closed_points(points: PackedVector2Array) -> PackedVector2Array:
	var closed := PackedVector2Array(points)
	if not closed.is_empty():
		closed.append(closed[0])
	return closed
