class_name ModuleEdgeRequirement
extends Resource

enum EdgeDirection {
	FORWARD,
	STARBOARD,
	REAR,
	PORT,
}

@export var cell_offset := Vector2i.ZERO
@export var direction := EdgeDirection.FORWARD
@export var must_face_open_space := true


func direction_vector() -> Vector2i:
	match direction:
		EdgeDirection.STARBOARD:
			return Vector2i.RIGHT
		EdgeDirection.REAR:
			return Vector2i.DOWN
		EdgeDirection.PORT:
			return Vector2i.LEFT
		_:
			return Vector2i.UP
