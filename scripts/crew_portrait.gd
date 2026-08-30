@tool
class_name CrewPortrait
extends Control

@export_category("Portrait Frame")
## Dark display color behind the crew silhouette.
@export var background_color := Color(0.025, 0.055, 0.07, 1.0)
## Primary holographic frame and silhouette color.
@export var accent_color := Color(0.3, 0.9, 0.9, 1.0)
## Dim secondary line color used by scanlines and inner framing.
@export var secondary_color := Color(0.12, 0.36, 0.42, 0.9)
## Width of the angular outer frame.
@export_range(1.0, 6.0, 0.5) var frame_width := 2.0
## Opacity of horizontal display scanlines.
@export_range(0.0, 1.0, 0.05) var scanline_opacity := 0.16

@export_category("Crew Identity")
## Stable seed used to vary head, shoulders, and small identification marks.
@export var portrait_seed := 1:
	set(value):
		portrait_seed = value
		queue_redraw()
## Current health percentage; low health adds warning coloration.
@export_range(0.0, 100.0, 1.0) var health_percentage := 100.0:
	set(value):
		health_percentage = value
		queue_redraw()
## Current morale percentage, used by the small status lamp.
@export_range(0.0, 100.0, 1.0) var morale_percentage := 75.0:
	set(value):
		morale_percentage = value
		queue_redraw()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	queue_redraw()


func configure(member_id: int, crew_accent: Color, health: float, morale: float) -> void:
	portrait_seed = member_id
	accent_color = crew_accent
	health_percentage = health
	morale_percentage = morale
	queue_redraw()


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	if rect.size.x < 4.0 or rect.size.y < 4.0:
		return
	var cut := minf(rect.size.x, rect.size.y) * 0.13
	var frame := PackedVector2Array([
		Vector2(cut, 1.0), Vector2(rect.end.x - 1.0, 1.0),
		Vector2(rect.end.x - 1.0, rect.end.y - cut), Vector2(rect.end.x - cut, rect.end.y - 1.0),
		Vector2(1.0, rect.end.y - 1.0), Vector2(1.0, cut), Vector2(cut, 1.0),
	])
	draw_colored_polygon(PackedVector2Array([Vector2(cut, 2), Vector2(rect.end.x - 2, 2), Vector2(rect.end.x - 2, rect.end.y - cut), Vector2(rect.end.x - cut, rect.end.y - 2), Vector2(2, rect.end.y - 2), Vector2(2, cut)]), background_color)
	draw_polyline(frame, accent_color if health_percentage > 25.0 else Color(1.0, 0.2, 0.14), frame_width, false)
	draw_line(Vector2(cut + 2.0, 5.0), Vector2(rect.end.x - 5.0, 5.0), secondary_color, 1.0)
	for y: float in range(9, int(rect.size.y - 4.0), 5):
		draw_line(Vector2(4.0, y), Vector2(rect.size.x - 4.0, y), Color(secondary_color, scanline_opacity), 1.0)
	var variation := float(abs(portrait_seed * 37) % 7) / 7.0
	var center_x := rect.size.x * (0.49 + (variation - 0.5) * 0.06)
	var head_center := Vector2(center_x, rect.size.y * 0.38)
	var head_radius := minf(rect.size.x, rect.size.y) * (0.14 + variation * 0.018)
	var silhouette := Color(accent_color, 0.72)
	draw_circle(head_center, head_radius + 2.0, Color(accent_color, 0.18))
	draw_circle(head_center, head_radius, silhouette)
	var shoulder_y := rect.size.y * 0.77
	var shoulder_half := rect.size.x * (0.27 + variation * 0.035)
	var neck_half := head_radius * 0.46
	draw_colored_polygon(PackedVector2Array([
		head_center + Vector2(-neck_half, head_radius * 0.7),
		Vector2(center_x - shoulder_half, shoulder_y),
		Vector2(center_x - shoulder_half * 1.08, rect.size.y - 5.0),
		Vector2(center_x + shoulder_half * 1.08, rect.size.y - 5.0),
		Vector2(center_x + shoulder_half, shoulder_y),
		head_center + Vector2(neck_half, head_radius * 0.7),
	]), silhouette)
	var morale_normalized := clampf(morale_percentage / 100.0, 0.0, 1.0)
	var lamp_color := Color(0.92, 0.18, 0.12).lerp(Color(0.95, 0.68, 0.16), morale_normalized * 2.0) if morale_normalized < 0.5 else Color(0.95, 0.68, 0.16).lerp(Color(0.25, 0.9, 0.46), (morale_normalized - 0.5) * 2.0)
	draw_circle(Vector2(rect.size.x - 7.0, 8.0), 2.5, lamp_color)
	draw_string(ThemeDB.fallback_font, Vector2(5.0, rect.size.y - 5.0), "%02d" % (abs(portrait_seed) % 100), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 8, Color(accent_color, 0.75))
