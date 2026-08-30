@tool
class_name RoomLayoutObstacle
extends Polygon2D

## An exact solid-furniture footprint authored directly in the room scene.
## Select this node and use Godot's polygon edit tool to move/add/delete points.


func _ready() -> void:
	if polygon.size() < 3:
		polygon = PackedVector2Array([
			Vector2(-16.0, -16.0),
			Vector2(16.0, -16.0),
			Vector2(16.0, 16.0),
			Vector2(-16.0, 16.0),
		])
	if color.a <= 0.0:
		color = Color(1.0, 0.24, 0.16, 0.18)
