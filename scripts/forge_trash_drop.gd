class_name ForgeTrashDrop
extends Control

signal grid_discarded(room_type: String, room_id: StringName, cell: Vector2i)

var drag_hovered := false


func _ready() -> void:
	custom_minimum_size = Vector2(88, 34)
	tooltip_text = "DISPOSAL CHUTE\nDROPPED PARTS ARE DESTROYED"
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	var accepted := data is Dictionary and String(data.get("kind", "")) == "installed_grid_piece"
	if drag_hovered != accepted:
		drag_hovered = accepted
		queue_redraw()
	return accepted


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	drag_hovered = false
	queue_redraw()
	grid_discarded.emit(
		String(data.get("room_type", "UNASSIGNED")),
		StringName(data.get("room_id", &"")),
		data.get("cell", Vector2i.ZERO)
	)


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END and drag_hovered:
		drag_hovered = false
		queue_redraw()


func _draw() -> void:
	var edge := Color(1.0, 0.34, 0.18, 1.0) if drag_hovered else Color(0.72, 0.28, 0.18, 0.9)
	var fill := Color(0.24, 0.035, 0.02, 0.96) if drag_hovered else Color(0.055, 0.018, 0.016, 0.94)
	draw_rect(Rect2(Vector2.ONE, size - Vector2(2, 2)), fill, true)
	draw_rect(Rect2(Vector2.ONE, size - Vector2(2, 2)), edge, false, 2.0)
	var icon_center := Vector2(18, size.y * 0.5 + 1)
	draw_rect(Rect2(icon_center + Vector2(-6, -6), Vector2(12, 12)), edge, false, 1.5)
	draw_line(icon_center + Vector2(-8, -9), icon_center + Vector2(8, -9), edge, 1.5)
	draw_line(icon_center + Vector2(-4, -12), icon_center + Vector2(4, -12), edge, 1.5)
	draw_string(
		ThemeDB.fallback_font,
		Vector2(30, size.y * 0.5 + 4),
		"DISCARD",
		HORIZONTAL_ALIGNMENT_LEFT,
		54,
		9,
		edge
	)
