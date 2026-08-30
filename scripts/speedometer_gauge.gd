class_name SpeedometerGauge
extends Control

var current_speed := 0.0
var maximum_speed := 1.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_redraw()


func set_speed(speed: float, speed_limit: float) -> void:
	current_speed = maxf(speed, 0.0)
	maximum_speed = maxf(speed_limit, 0.001)
	queue_redraw()


func _draw() -> void:
	var center := Vector2(size.x * 0.5, size.y - 12.0)
	var radius := minf(size.x * 0.39, size.y - 25.0)
	var ratio := clampf(current_speed / maximum_speed, 0.0, 1.0)
	var start_angle := PI
	var end_angle := TAU
	var needle_angle := lerpf(start_angle, end_angle, ratio)
	var dim_color := Color(0.12, 0.2, 0.24, 1.0)
	var bright_color := _speed_color(ratio).lightened(0.2)

	draw_arc(center, radius, start_angle, end_angle, 28, dim_color, 4.0, true)
	if ratio > 0.001:
		var active_segments := maxi(1, ceili(ratio * 24.0))
		for segment_index: int in range(active_segments):
			var segment_start_ratio := float(segment_index) / 24.0
			var segment_end_ratio := minf(float(segment_index + 1) / 24.0, ratio)
			draw_arc(
				center,
				radius,
				lerpf(start_angle, end_angle, segment_start_ratio),
				lerpf(start_angle, end_angle, segment_end_ratio),
				3,
				_speed_color(segment_end_ratio),
				4.0,
				true
			)

	for tick_index: int in range(9):
		var tick_ratio := float(tick_index) / 8.0
		var tick_angle := lerpf(start_angle, end_angle, tick_ratio)
		var direction := Vector2.from_angle(tick_angle)
		var tick_length := 7.0 if tick_index % 2 == 0 else 4.0
		var tick_color := _speed_color(tick_ratio).lightened(0.12) if tick_ratio <= ratio else Color(0.3, 0.42, 0.45, 1.0)
		draw_line(
			center + direction * (radius - tick_length),
			center + direction * (radius + 1.0),
			tick_color,
			1.5,
			true
		)

	var needle_direction := Vector2.from_angle(needle_angle)
	draw_line(center, center + needle_direction * (radius - 7.0), bright_color, 2.0, true)
	draw_circle(center, 3.0, bright_color)

	var font := ThemeDB.fallback_font
	var label_font_size := 9
	var value_font_size := 11
	var label := "SPEED"
	var value := "%.1f" % current_speed
	var label_size := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, label_font_size)
	var value_size := font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, value_font_size)
	draw_string(
		font,
		Vector2(center.x - label_size.x * 0.5, 10.0),
		label,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		label_font_size,
		Color(0.66, 0.45, 0.22, 1.0)
	)
	draw_string(
		font,
		Vector2(center.x - value_size.x * 0.5, size.y - 1.0),
		value,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		value_font_size,
		bright_color
	)


func _speed_color(ratio: float) -> Color:
	var low_speed := Color(0.18, 0.82, 0.72, 1.0)
	var cruise_speed := Color(0.96, 0.72, 0.2, 1.0)
	var maximum_speed_color := Color(1.0, 0.25, 0.12, 1.0)
	if ratio <= 0.65:
		return low_speed.lerp(cruise_speed, ratio / 0.65)
	return cruise_speed.lerp(maximum_speed_color, (ratio - 0.65) / 0.35)
