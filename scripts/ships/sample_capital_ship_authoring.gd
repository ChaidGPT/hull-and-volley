@tool
class_name SampleCapitalShipAuthoring
extends Node2D

const GRID_GEOMETRY := preload("res://scripts/grid_geometry.gd")

@export_category("Sample Ship")
## Definition consumed by the combat dev spawner.
@export var definition: Resource:
	set(value):
		definition = value
		queue_redraw()
## Size of one construction grid in the editor preview.
@export_range(8.0, 128.0, 1.0) var preview_cell_size := 42.0
## Steel-colored exposed hull outline.
@export var hull_color := Color(0.55, 0.68, 0.7, 1.0)
## Width of the exposed hull preview line.
@export_range(1.0, 12.0, 0.5) var hull_width := 3.0


func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		queue_redraw()


func _draw() -> void:
	if definition == null:
		_draw_missing_definition()
		return
	var layout: Resource = definition.get("ship_layout")
	if layout == null or not layout.has_method("get_occupied_bounds"):
		_draw_missing_definition()
		return
	var bounds: Rect2i = layout.call("get_occupied_bounds")
	var geometry_size := GRID_GEOMETRY.grid_pixel_size(layout, bounds, preview_cell_size)
	var origin := -geometry_size * 0.5
	var occupied: Dictionary = {}
	for room: Resource in layout.get("rooms"):
		for rect: Rect2i in room.get("grid_rects"):
			for y: int in range(rect.position.y, rect.end.y):
				for x: int in range(rect.position.x, rect.end.x):
					var cell := Vector2i(x, y)
					occupied[cell] = true
					var cell_rect := GRID_GEOMETRY.cell_rect(layout, cell, bounds, preview_cell_size, origin)
					draw_rect(cell_rect.grow(-1.0), room.get("color"), true)
	for segment: Dictionary in GRID_GEOMETRY.boundary_segments(layout, occupied, bounds, preview_cell_size, origin):
		draw_line(segment["start"], segment["end"], hull_color, hull_width, true)
	draw_string(ThemeDB.fallback_font, Vector2(-geometry_size.x * 0.5, -geometry_size.y * 0.5 - 18.0), String(definition.get("display_name")), HORIZONTAL_ALIGNMENT_CENTER, geometry_size.x, 14, Color(0.55, 0.9, 0.92))


func _draw_missing_definition() -> void:
	draw_rect(Rect2(-120, -45, 240, 90), Color(0.08, 0.11, 0.13), true)
	draw_rect(Rect2(-120, -45, 240, 90), Color(0.3, 0.75, 0.78), false, 2.0)
	draw_string(ThemeDB.fallback_font, Vector2(-110, 5), "ASSIGN A SAMPLE SHIP DEFINITION", HORIZONTAL_ALIGNMENT_CENTER, 220, 13, Color(0.5, 0.85, 0.88))
