class_name FlightDestinationIndicator
extends Control

@export var bracket_color := Color(0.28, 1.0, 0.88, 0.9)
@export var corner_margin := 5.0
@export var arm_length := 8.0
@export var line_width := 1.2
@export var pulse_speed := 2.4

var pulse_time := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 100
	set_process(true)


func _process(delta: float) -> void:
	pulse_time += delta
	queue_redraw()


func _draw() -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return
	var canvas_scale := get_global_transform_with_canvas().get_scale()
	var camera_zoom := maxf((absf(canvas_scale.x) + absf(canvas_scale.y)) * 0.5, 0.001)
	var margin := corner_margin / camera_zoom
	var arm := arm_length / camera_zoom
	var width := line_width / camera_zoom
	var rect := Rect2(Vector2.ZERO, size).grow(margin)
	var pulse := 0.78 + (sin(pulse_time * pulse_speed) + 1.0) * 0.08
	var color := bracket_color
	color.a *= pulse
	for corner_data: Array in [
		[rect.position, Vector2.RIGHT, Vector2.DOWN],
		[Vector2(rect.end.x, rect.position.y), Vector2.LEFT, Vector2.DOWN],
		[rect.end, Vector2.LEFT, Vector2.UP],
		[Vector2(rect.position.x, rect.end.y), Vector2.RIGHT, Vector2.UP],
	]:
		var corner: Vector2 = corner_data[0]
		var horizontal: Vector2 = corner_data[1]
		var vertical: Vector2 = corner_data[2]
		draw_line(corner, corner + horizontal * arm, color, width, false)
		draw_line(corner, corner + vertical * arm, color, width, false)
