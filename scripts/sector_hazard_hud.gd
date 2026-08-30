class_name SectorHazardHud
extends Control

var hazard_state: Dictionary = {}
var pulse := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(300.0, 36.0)
	visible = false


func _process(delta: float) -> void:
	pulse = fmod(pulse + delta * 4.0, TAU)
	if visible:
		queue_redraw()


func set_hazard_state(state: Dictionary) -> void:
	hazard_state = state
	visible = (
		not state.is_empty()
		and (
			bool(state.get("inside_hazard", false))
			or float(state.get("warning_level", 0.0)) >= 0.25
		)
	)
	queue_redraw()


func _draw() -> void:
	if hazard_state.is_empty():
		return
	var inside := bool(hazard_state.get("inside_hazard", false))
	var warning := float(hazard_state.get("warning_level", 0.0))
	var live := Color(1.0, 0.22, 0.48, 0.95) if inside else Color(1.0, 0.66, 0.18, 0.88)
	var glow := live
	glow.a = (0.07 + 0.06 * sin(pulse)) * (1.0 if inside else warning)
	var alert_rect := Rect2(5.0, 5.0, size.x - 10.0, 26.0)
	draw_rect(alert_rect, Color(0.018, 0.008, 0.028, 0.86), true)
	draw_rect(alert_rect, glow, true)

	# Open-ended terminal brackets keep this feeling like an urgent projected
	# message instead of another permanent HUD panel.
	var bracket_length := 12.0
	draw_line(alert_rect.position, alert_rect.position + Vector2(bracket_length, 0.0), live, 2.0)
	draw_line(alert_rect.position, alert_rect.position + Vector2(0.0, alert_rect.size.y), live, 2.0)
	var right_top := Vector2(alert_rect.end.x, alert_rect.position.y)
	var right_bottom := alert_rect.end
	draw_line(right_top, right_top - Vector2(bracket_length, 0.0), live, 2.0)
	draw_line(right_top, right_bottom, live, 2.0)

	var title := "DANGER • INSIDE ION STORM" if inside else "CAUTION • ION STORM PROXIMITY"
	draw_string(
		ThemeDB.fallback_font,
		Vector2(14.0, 23.0),
		title,
		HORIZONTAL_ALIGNMENT_CENTER,
		size.x - 28.0,
		12,
		live
	)
