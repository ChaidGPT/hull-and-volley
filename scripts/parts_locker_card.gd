class_name PartsLockerCard
extends Control

var room_type := ""
var display_name := ""
var piece_color := Color(0.12, 0.56, 0.52, 1.0)
var quantity := 0
var glyph := ""
var hovered := false
var hover_time := 0.0


func _ready() -> void:
	custom_minimum_size = Vector2(94, 78)
	mouse_default_cursor_shape = Control.CURSOR_ARROW if room_type.is_empty() else Control.CURSOR_POINTING_HAND
	mouse_entered.connect(_set_hovered.bind(true))
	mouse_exited.connect(_set_hovered.bind(false))
	set_process(false)


func _process(delta: float) -> void:
	if not hovered:
		return
	hover_time += delta
	queue_redraw()


func configure(type_name: String, label: String, color: Color, count: int, tile_glyph: String = "") -> void:
	room_type = type_name
	display_name = label
	piece_color = color
	quantity = maxi(count, 0)
	glyph = tile_glyph
	tooltip_text = (
		"%s\n%d LOOSE GRID%s\nAVAILABLE AT STATION DRYDOCK"
		% [display_name.to_upper(), quantity, "" if quantity == 1 else "S"]
	)
	queue_redraw()


func configure_empty() -> void:
	room_type = ""
	display_name = "EMPTY BAY"
	piece_color = Color(0.12, 0.24, 0.24, 0.55)
	quantity = 0
	mouse_default_cursor_shape = Control.CURSOR_ARROW
	tooltip_text = "EMPTY SALVAGE BERTH"
	queue_redraw()


func _set_hovered(is_hovered: bool) -> void:
	hovered = is_hovered
	set_process(hovered)
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if room_type.is_empty():
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		hover_time += 0.6
		queue_redraw()


func _draw() -> void:
	var card_rect := Rect2(Vector2.ONE, size - Vector2(2.0, 2.0))
	var fill := Color(0.006, 0.026, 0.028, 0.98)
	var edge := Color(0.08, 0.34, 0.34, 0.9)
	if hovered and not room_type.is_empty():
		fill = Color(0.012, 0.07, 0.068, 0.99)
		edge = piece_color.lightened(0.35)
		draw_rect(card_rect.grow(3.0), Color(edge, 0.09), true)
	draw_rect(card_rect, fill, true)
	draw_rect(card_rect, edge, false, 1.5)

	var tile_rect := Rect2(Vector2(7.0, 8.0), Vector2(34.0, 34.0))
	if room_type.is_empty():
		draw_rect(tile_rect, Color(0.02, 0.045, 0.046, 0.72), true)
		draw_rect(tile_rect, edge, false, 1.0)
		draw_line(tile_rect.position + Vector2(8.0, 17.0), tile_rect.end - Vector2(8.0, 17.0), edge, 1.0)
	else:
		draw_rect(tile_rect.grow(3.0), Color(piece_color, 0.12), true)
		draw_rect(tile_rect, Color(piece_color, 0.78), true)
		draw_rect(tile_rect, piece_color.lightened(0.4), false, 2.0)
		var notch := 6.0
		draw_line(tile_rect.position, tile_rect.position + Vector2(notch, 0.0), Color.WHITE, 1.0)
		draw_line(tile_rect.position, tile_rect.position + Vector2(0.0, notch), Color.WHITE, 1.0)
		if not glyph.is_empty():
			draw_string(
				ThemeDB.fallback_font,
				tile_rect.position + Vector2(0.0, 24.0),
				glyph,
				HORIZONTAL_ALIGNMENT_CENTER,
				tile_rect.size.x,
				16,
				Color(0.96, 1.0, 0.98)
			)

	var count_color := Color(0.94, 1.0, 0.92, 1.0) if quantity > 0 else Color(0.28, 0.42, 0.42, 1.0)
	draw_string(
		ThemeDB.fallback_font,
		Vector2(49.0, 31.0),
		"x%d" % quantity,
		HORIZONTAL_ALIGNMENT_LEFT,
		38.0,
		17,
		count_color
	)
	draw_string(
		ThemeDB.fallback_font,
		Vector2(7.0, 61.0),
		display_name.to_upper(),
		HORIZONTAL_ALIGNMENT_LEFT,
		size.x - 14.0,
		9,
		Color(0.7, 0.94, 0.87, 1.0) if not room_type.is_empty() else Color(0.25, 0.43, 0.42, 1.0)
	)
	if hovered and not room_type.is_empty():
		var scan_y := 4.0 + fmod(hover_time * 42.0, maxf(size.y - 8.0, 1.0))
		draw_line(
			Vector2(4.0, scan_y),
			Vector2(size.x - 4.0, scan_y),
			Color(piece_color.lightened(0.45), 0.22),
			1.0
		)
