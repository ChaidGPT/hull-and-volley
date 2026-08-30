@tool
class_name FighterVisual
extends Node2D

@export_category("Editable Vector Hull")
## Hull vertices in local pixels. Edit these values or move the Line2D points directly in the 2D editor.
@export var hull_points := PackedVector2Array([
	Vector2(0, -18),
	Vector2(14, 14),
	Vector2(0, 7),
	Vector2(-14, 14),
	Vector2(0, -18),
])
## Crisp outline color of the fighter silhouette.
@export var hull_color := Color(0.78, 0.9, 0.9, 1.0)
## Subtle interior color. Set alpha to zero for a classic outline-only Asteroids look.
@export var hull_fill_color := Color(0.06, 0.1, 0.11, 0.5)
## Width of the vector hull outline in pixels.
@export_range(0.5, 8.0, 0.25) var hull_line_width := 1.5

@export_category("Cockpit")
## Show or hide the small cockpit chevron independently from the hull.
@export var cockpit_visible := true
@export var cockpit_color := Color(0.3, 0.9, 1.0, 0.85)

@export_category("Thruster")
## Current visual thrust amount from zero to one. Future fighter movement can drive this value.
@export_range(0.0, 1.0, 0.05) var thrust_amount := 0.0
@export var thruster_color := Color(1.0, 0.58, 0.2, 0.95)
## Maximum length of the engine flame in local pixels.
@export_range(2.0, 30.0, 1.0) var maximum_flame_length := 12.0

@export_category("Editor Preview")
## Continuously synchronizes exported values into child vector nodes while editing this scene.
@export var live_editor_preview := true


func _ready() -> void:
	_apply_visual_settings()


func _process(_delta: float) -> void:
	if Engine.is_editor_hint() and live_editor_preview:
		_apply_visual_settings()


func set_thrust_visual(amount: float) -> void:
	thrust_amount = clampf(amount, 0.0, 1.0)
	_apply_visual_settings()


func _apply_visual_settings() -> void:
	var fill := get_node_or_null("HullFill") as Polygon2D
	var outline := get_node_or_null("HullOutline") as Line2D
	var cockpit := get_node_or_null("Cockpit") as Line2D
	var plume := get_node_or_null("ThrusterPlume") as Line2D
	if fill != null:
		var fill_points := hull_points.duplicate()
		if fill_points.size() > 1 and fill_points[0] == fill_points[-1]:
			fill_points.resize(fill_points.size() - 1)
		fill.polygon = fill_points
		fill.color = hull_fill_color
	if outline != null:
		outline.points = hull_points
		outline.width = hull_line_width
		outline.default_color = hull_color
	if cockpit != null:
		cockpit.visible = cockpit_visible
		cockpit.default_color = cockpit_color
	if plume != null:
		plume.visible = thrust_amount > 0.01
		plume.default_color = thruster_color
		plume.points = PackedVector2Array([
			Vector2(-4, 11),
			Vector2(0, 11 + maximum_flame_length * thrust_amount),
			Vector2(4, 11),
		])

