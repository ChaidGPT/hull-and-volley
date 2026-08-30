extends Control

const BANK_LABELS := ["BOW", "STBD", "AFT", "PORT"]
var bank_report: Dictionary = {}


func set_banks(report: Dictionary) -> void:
	bank_report = report
	var lines: PackedStringArray = []
	for bank: int in range(4):
		var data: Dictionary = bank_report.get(bank, {})
		var maximum := roundi(float(data.get("maximum", 0.0)))
		if maximum <= 0:
			continue
		lines.append("%s  %d%%" % [
			BANK_LABELS[bank],
			roundi(float(data.get("ratio", 0.0)) * 100.0),
		])
	if lines.is_empty():
		tooltip_text = ""
		remove_meta(&"_crt_terminal_tooltip")
	else:
		tooltip_text = "\n".join(lines)
	queue_redraw()


func _draw() -> void:
	var center := size * 0.5
	var ship_half_width := 8.0
	var ship_half_height := 10.0
	var ship_points := PackedVector2Array([
		center + Vector2(0.0, -ship_half_height - 2.0),
		center + Vector2(ship_half_width, -ship_half_height * 0.35),
		center + Vector2(ship_half_width, ship_half_height),
		center + Vector2(2.5, ship_half_height - 1.5),
		center + Vector2(0.0, ship_half_height + 1.5),
		center + Vector2(-2.5, ship_half_height - 1.5),
		center + Vector2(-ship_half_width, ship_half_height),
		center + Vector2(-ship_half_width, -ship_half_height * 0.35),
	])
	draw_colored_polygon(ship_points, Color(0.055, 0.16, 0.18, 0.96))
	var closed_ship_points := ship_points.duplicate()
	closed_ship_points.append(ship_points[0])
	draw_polyline(closed_ship_points, Color(0.42, 0.82, 0.84, 0.9), 1.25, true)
	draw_line(center + Vector2(0.0, -6.0), center + Vector2(0.0, 7.0), Color(0.2, 0.52, 0.56, 0.8), 1.0)

	var horizontal_size := Vector2(30.0, 5.0)
	var vertical_size := Vector2(5.0, 24.0)
	var bank_rects: Array[Rect2] = [
		Rect2(center + Vector2(-horizontal_size.x * 0.5, -ship_half_height - 8.0), horizontal_size),
		Rect2(center + Vector2(ship_half_width + 4.0, -vertical_size.y * 0.5), vertical_size),
		Rect2(center + Vector2(-horizontal_size.x * 0.5, ship_half_height + 3.0), horizontal_size),
		Rect2(center + Vector2(-ship_half_width - 9.0, -vertical_size.y * 0.5), vertical_size),
	]
	for bank: int in range(4):
		var rect := bank_rects[bank]
		var data: Dictionary = bank_report.get(bank, {})
		var maximum := float(data.get("maximum", 0.0))
		var ratio := clampf(float(data.get("ratio", 0.0)), 0.0, 1.0)
		var online := bool(data.get("online", false))
		var edge := Color(0.12, 0.48, 0.54, 0.92) if maximum > 0.0 else Color(0.1, 0.18, 0.2, 0.56)
		var fill := _shield_fill_color(ratio) if online else Color(0.18, 0.25, 0.27, 0.58)
		draw_rect(rect, Color(0.008, 0.025, 0.032, 0.96), true)
		if ratio > 0.0:
			var fill_rect := rect.grow(-1.0)
			if bank in [0, 2]:
				fill_rect.size.x *= ratio
				if bank == 2:
					fill_rect.position.x = rect.end.x - 1.0 - fill_rect.size.x
			else:
				fill_rect.size.y *= ratio
				fill_rect.position.y = rect.end.y - 1.0 - fill_rect.size.y
			draw_rect(fill_rect, fill, true)
		draw_rect(rect, edge, false, 1.0)
		if maximum > 0.0:
			var contact_point := _bank_contact_point(center, bank, ship_half_width, ship_half_height)
			draw_line(contact_point, rect.get_center(), Color(edge, 0.54), 1.0, true)


func _shield_fill_color(ratio: float) -> Color:
	if ratio <= 0.25:
		return Color(1.0, 0.28, 0.16, 0.98)
	if ratio <= 0.55:
		return Color(1.0, 0.68, 0.18, 0.98)
	return Color(0.18, 0.86, 0.96, 0.98)


func _bank_contact_point(center: Vector2, bank: int, half_width: float, half_height: float) -> Vector2:
	match bank:
		0:
			return center + Vector2(0.0, -half_height - 2.0)
		1:
			return center + Vector2(half_width, 0.0)
		2:
			return center + Vector2(0.0, half_height + 1.0)
		_:
			return center + Vector2(-half_width, 0.0)
