extends Control

@export_category("Monitor Backdrop")
## Turns the shipboard monitor texture on/off without removing the node.
@export var effect_enabled := true
## Overall strength of the monitor treatment. Keep this low if text starts feeling busy.
@export_range(0.05, 3.0, 0.05) var master_intensity := 1.35
## Distance between horizontal phosphor/scan bands.
@export_range(2.0, 16.0, 0.5) var scanline_spacing := 5.0
## How visible the scan bands are. Kept low because this sits behind UI text.
@export_range(0.0, 0.35, 0.01) var scanline_opacity := 0.115
## Very subtle moving shimmer, like an active display rather than a static overlay.
@export_range(0.0, 2.0, 0.01) var shimmer_speed := 0.22
## Strength of the edge darkening.
@export_range(0.0, 0.7, 0.01) var vignette_strength := 0.22
## Soft central screen glow.
@export_range(0.0, 0.25, 0.01) var center_glow_strength := 0.075
## Faint vertical phosphor columns. Low values keep it from feeling like VHS.
@export_range(0.0, 0.2, 0.01) var phosphor_column_opacity := 0.05
## Distance between faint vertical phosphor columns.
@export_range(16.0, 96.0, 1.0) var phosphor_column_spacing := 42.0

var _time := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(true)


func _process(delta: float) -> void:
	if not effect_enabled:
		return
	_time += delta
	queue_redraw()


func _draw() -> void:
	if not effect_enabled:
		return
	var rect := get_rect()
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return

	_draw_center_glow(rect.size)
	_draw_phosphor_columns(rect.size)
	_draw_scanlines(rect.size)
	_draw_vignette(rect.size)


func _draw_scanlines(screen_size: Vector2) -> void:
	var phase := fposmod(_time * shimmer_speed * scanline_spacing, scanline_spacing)
	var line_color := Color(0.26, 0.9, 0.82, scanline_opacity * master_intensity)
	var y := -phase
	while y < screen_size.y:
		draw_line(Vector2(0.0, y), Vector2(screen_size.x, y), line_color, 1.0, false)
		y += scanline_spacing


func _draw_phosphor_columns(screen_size: Vector2) -> void:
	if phosphor_column_opacity <= 0.0:
		return
	var column_color := Color(0.12, 0.45, 0.48, phosphor_column_opacity * master_intensity)
	var x := phosphor_column_spacing * 0.5
	while x < screen_size.x:
		draw_line(Vector2(x, 0.0), Vector2(x, screen_size.y), column_color, 1.0, false)
		x += phosphor_column_spacing


func _draw_center_glow(screen_size: Vector2) -> void:
	if center_glow_strength <= 0.0:
		return
	var center := screen_size * 0.5
	var radius := maxf(screen_size.x, screen_size.y) * 0.64
	var steps := 14
	for index: int in range(steps, 0, -1):
		var weight := float(index) / float(steps)
		var alpha := center_glow_strength * master_intensity * weight * weight * 0.18
		draw_circle(center, radius * weight, Color(0.08, 0.5, 0.48, alpha))


func _draw_vignette(screen_size: Vector2) -> void:
	if vignette_strength <= 0.0:
		return
	var edge_color := Color(0.0, 0.0, 0.0, vignette_strength)
	var band := minf(screen_size.x, screen_size.y) * 0.14
	for index: int in range(8):
		var weight := float(index + 1) / 8.0
		var alpha := vignette_strength * master_intensity * weight * 0.12
		var color := Color(edge_color.r, edge_color.g, edge_color.b, alpha)
		var inset := band * (1.0 - weight)
		draw_rect(Rect2(0.0, 0.0, screen_size.x, inset), color)
		draw_rect(Rect2(0.0, screen_size.y - inset, screen_size.x, inset), color)
		draw_rect(Rect2(0.0, 0.0, inset, screen_size.y), color)
		draw_rect(Rect2(screen_size.x - inset, 0.0, inset, screen_size.y), color)
