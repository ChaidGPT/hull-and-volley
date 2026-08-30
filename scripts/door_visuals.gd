class_name DoorVisuals
extends RefCounted

## Universal authored ship-door renderer. Door simulation remains owned by
## ShipStructuralState; this helper only turns its openness into an art frame.
const DOOR_TEXTURE: Texture2D = preload("res://assets/sprites/interiors/ship_doors.png")
const FRAME_SIZE := Vector2(48.0, 32.0)
const FRAME_COUNT := 4


static func draw_door(
	canvas: CanvasItem,
	start: Vector2,
	finish: Vector2,
	openness: float,
	locked: bool = false
) -> void:
	var span := finish - start
	var door_width := span.length()
	if door_width <= 0.001:
		return

	var frame_index := clampi(
		int(round(clampf(openness, 0.0, 1.0) * float(FRAME_COUNT - 1))),
		0,
		FRAME_COUNT - 1
	)
	var source_rect := Rect2(
		Vector2(float(frame_index) * FRAME_SIZE.x, 0.0),
		FRAME_SIZE
	)
	var tint := Color(1.0, 0.55, 0.46) if locked else Color.WHITE

	# The art's horizontal axis is the doorway threshold. Scaling from the
	# simulated threshold width keeps the same source usable in every ship view.
	canvas.draw_set_transform(
		(start + finish) * 0.5,
		span.angle(),
		Vector2.ONE * (door_width / FRAME_SIZE.x)
	)
	canvas.draw_texture_rect_region(
		DOOR_TEXTURE,
		Rect2(-FRAME_SIZE * 0.5, FRAME_SIZE),
		source_rect,
		tint
	)
	canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


static func is_transitioning(structure: ShipStructuralState) -> bool:
	if structure == null:
		return false
	for door_value: Variant in structure.doors.values():
		var openness := float((door_value as Dictionary).get("openness", 0.0))
		if openness > 0.001 and openness < 0.999:
			return true
	return false
