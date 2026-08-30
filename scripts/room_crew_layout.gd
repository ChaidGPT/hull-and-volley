@tool
class_name RoomCrewLayout
extends Node2D

## Authoring canvas used by all regular 160x160 room overlays.
@export var source_size := Vector2(160.0, 160.0):
	set(value):
		source_size = value
		queue_redraw()

## Some room art is authored facing a different direction than the room's
## gameplay-facing value. Thrusters, for example, use a south-facing source.
@export_range(0, 3, 1) var source_rotation_quarters := 0

## Edges which are structural dead ends in the authored source orientation.
## These are stronger than "no door currently placed": ship topology must never
## cut a doorway through them. Quarter order is North, East, South, West.
@export_flags("North", "East", "South", "West") var forbidden_door_edges := 0


func forbids_source_door(edge_quarters: int) -> bool:
	return (forbidden_door_edges & (1 << posmod(edge_quarters, 4))) != 0


func _ready() -> void:
	queue_redraw()


func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	var bounds := Rect2(-source_size * 0.5, source_size)
	draw_rect(bounds, Color(0.2, 1.0, 0.88, 0.55), false, 1.0)
	draw_line(Vector2(bounds.position.x, 0.0), Vector2(bounds.end.x, 0.0), Color(0.2, 1.0, 0.88, 0.16), 1.0)
	draw_line(Vector2(0.0, bounds.position.y), Vector2(0.0, bounds.end.y), Color(0.2, 1.0, 0.88, 0.16), 1.0)


func markers_under(group_name: StringName) -> Array[Marker2D]:
	var result: Array[Marker2D] = []
	var group := get_node_or_null(NodePath(String(group_name)))
	if group == null:
		return result
	for child: Node in group.get_children():
		if child is Marker2D:
			result.append(child as Marker2D)
	return result


func obstacles() -> Array[RoomLayoutObstacle]:
	var result: Array[RoomLayoutObstacle] = []
	var group := get_node_or_null(^"Obstacles")
	if group == null:
		return result
	for child: Node in group.get_children():
		if child is RoomLayoutObstacle:
			result.append(child as RoomLayoutObstacle)
	return result


func normalized_position(local_position: Vector2) -> Vector2:
	if source_size.x <= 0.0 or source_size.y <= 0.0:
		return Vector2(0.5, 0.5)
	return local_position / source_size + Vector2(0.5, 0.5)


func normalized_size(local_size: Vector2) -> Vector2:
	if source_size.x <= 0.0 or source_size.y <= 0.0:
		return Vector2.ZERO
	return local_size / source_size
