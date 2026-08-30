class_name ControllerMenuCursor
extends Control

var pulse_time := 0.0
var held_piece_active := false
var held_piece_color := Color.WHITE
var held_piece_footprint := Vector2i.ONE
var held_piece_glyph := ""


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(30.0, 30.0)
	size = custom_minimum_size
	set_process(true)


func _process(delta: float) -> void:
	pulse_time += delta
	queue_redraw()


func _draw() -> void:
	var glow := 0.78 + sin(pulse_time * 5.0) * 0.16
	var color := Color(0.28, 1.0, 0.88, glow)
	var shadow := Color(0.01, 0.12, 0.13, 0.9)
	var center := size * 0.5
	if held_piece_active:
		var preview_size := Vector2(held_piece_footprint) * 13.0
		var preview_rect := Rect2(center - preview_size * 0.5, preview_size)
		draw_rect(preview_rect.grow(3.0), Color(0.0, 0.08, 0.08, 0.82), true)
		draw_rect(preview_rect, Color(held_piece_color, 0.82), true)
		draw_rect(preview_rect, held_piece_color.lightened(0.32), false, 2.0)
		draw_string(
			ThemeDB.fallback_font,
			Vector2(preview_rect.position.x, center.y + 5.0),
			held_piece_glyph,
			HORIZONTAL_ALIGNMENT_CENTER,
			preview_rect.size.x,
			13
		)
	var radius := 10.0
	var arm := 5.0
	for offset: Vector2 in [Vector2(-radius, -radius), Vector2(radius, -radius), Vector2(radius, radius), Vector2(-radius, radius)]:
		var horizontal_sign := 1.0 if offset.x < 0.0 else -1.0
		var vertical_sign := 1.0 if offset.y < 0.0 else -1.0
		var corner := center + offset
		draw_line(corner + Vector2(1.0, 1.0), corner + Vector2(horizontal_sign * arm, 1.0), shadow, 3.0)
		draw_line(corner + Vector2(1.0, 1.0), corner + Vector2(1.0, vertical_sign * arm), shadow, 3.0)
		draw_line(corner, corner + Vector2(horizontal_sign * arm, 0.0), color, 2.0)
		draw_line(corner, corner + Vector2(0.0, vertical_sign * arm), color, 2.0)
	draw_circle(center + Vector2(1.0, 1.0), 3.0, shadow)
	draw_circle(center, 2.0, Color(0.78, 1.0, 0.94, 1.0))


func hold_piece(piece_color: Color, footprint: Vector2i, glyph: String) -> void:
	held_piece_active = true
	held_piece_color = piece_color
	held_piece_footprint = Vector2i(maxi(footprint.x, 1), maxi(footprint.y, 1))
	held_piece_glyph = glyph.left(1).to_upper()
	queue_redraw()


func release_piece() -> void:
	held_piece_active = false
	queue_redraw()
