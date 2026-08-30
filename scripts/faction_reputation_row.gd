class_name FactionReputationRow
extends Control

var report: Dictionary = {}
var hovered := false


func _ready() -> void:
	custom_minimum_size = Vector2(0.0, 64.0)
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	mouse_entered.connect(func() -> void:
		hovered = true
		queue_redraw()
	)
	mouse_exited.connect(func() -> void:
		hovered = false
		queue_redraw()
	)


func set_report(new_report: Dictionary) -> void:
	report = new_report
	tooltip_text = "%s\n\nSHIP SIGNATURE\n%s" % [
		String(report.get("description", "")),
		String(report.get("ship_design_language", "")),
	]
	queue_redraw()


func _draw() -> void:
	if report.is_empty():
		return
	var live: Color = report.get("signal_color", Color(0.5, 0.9, 0.85))
	var background := Color(0.006, 0.025, 0.028, 0.94)
	if hovered:
		background = background.lerp(Color(live.r, live.g, live.b, 0.2), 0.32)
	draw_rect(Rect2(Vector2.ZERO, size), background, true)
	draw_line(Vector2(0.0, size.y - 1.0), Vector2(size.x, size.y - 1.0), Color(live.r, live.g, live.b, 0.34), 1.0)

	draw_rect(Rect2(8.0, 8.0, 42.0, 42.0), Color(live.r, live.g, live.b, 0.13), true)
	draw_rect(Rect2(8.0, 8.0, 42.0, 42.0), live, false, 1.5)
	draw_string(
		ThemeDB.fallback_font,
		Vector2(8.0, 38.0),
		String(report.get("insignia_glyph", "◇")),
		HORIZONTAL_ALIGNMENT_CENTER,
		42.0,
		24,
		live
	)
	draw_string(
		ThemeDB.fallback_font,
		Vector2(61.0, 22.0),
		String(report.get("display_name", "UNKNOWN")).to_upper(),
		HORIZONTAL_ALIGNMENT_LEFT,
		size.x - 170.0,
		12,
		Color(0.78, 0.98, 0.92, 1.0)
	)
	draw_string(
		ThemeDB.fallback_font,
		Vector2(size.x - 106.0, 22.0),
		String(report.get("standing", "NEUTRAL")),
		HORIZONTAL_ALIGNMENT_RIGHT,
		96.0,
		11,
		live
	)

	var reputation := float(report.get("reputation", 0.0))
	var lit_position := roundi(remap(reputation, -100.0, 100.0, 0.0, 10.0))
	for index: int in range(11):
		var center := Vector2(67.0 + index * 20.0, 42.0)
		var diamond := PackedVector2Array([
			center + Vector2(0.0, -5.0),
			center + Vector2(7.0, 0.0),
			center + Vector2(0.0, 5.0),
			center + Vector2(-7.0, 0.0),
		])
		var segment := Color(0.16, 0.25, 0.25, 0.72)
		if index == lit_position:
			segment = live
		elif (index < 5 and index >= lit_position) or (index > 5 and index <= lit_position):
			segment = Color(live.r, live.g, live.b, 0.42)
		draw_colored_polygon(diamond, segment)
	var neutral_center := Vector2(67.0 + 5.0 * 20.0, 42.0)
	draw_circle(neutral_center, 2.0, Color(0.9, 0.9, 0.72, 0.9), true)
