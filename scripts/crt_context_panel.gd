class_name CrtContextPanel
extends PanelContainer

@export_category("CRT Power Transition")
## Horizontal line expansion time when powering the panel on or off.
@export_range(0.02, 0.5, 0.01) var horizontal_time := 0.1
## Vertical image expansion time after the CRT line appears.
@export_range(0.02, 0.5, 0.01) var vertical_time := 0.14
## Thin vertical scale used for the bright television power line.
@export_range(0.01, 0.2, 0.01) var line_scale := 0.04
## Tint used during the brief CRT power flash.
@export var flash_color := Color(1.3, 1.5, 1.5, 1.0)
## Context panels normally begin hidden until the player selects something.
@export var begin_powered_off := true

@export_category("CRT Screen Background")
## Draws subtle monitor texture inside this menu only, behind text and controls.
@export var screen_effect_enabled := true
## Overall strength of this menu's screen texture.
@export_range(0.0, 3.0, 0.05) var screen_effect_intensity := 1.0
## Distance between faint horizontal scan bands.
@export_range(2.0, 16.0, 0.5) var screen_scanline_spacing := 5.0
## Scanline strength. This draws behind the menu contents to preserve clarity.
@export_range(0.0, 0.4, 0.01) var screen_scanline_opacity := 0.105
## Faint vertical phosphor columns.
@export_range(0.0, 0.2, 0.01) var screen_phosphor_opacity := 0.045
## Distance between vertical phosphor columns.
@export_range(12.0, 96.0, 1.0) var screen_phosphor_spacing := 38.0
## Gentle moving shimmer so open menus feel like active displays.
@export_range(0.0, 2.0, 0.01) var screen_shimmer_speed := 0.18
## Edge darkening inside the menu screen.
@export_range(0.0, 0.7, 0.01) var screen_vignette_strength := 0.18
## Soft center glow inside the menu screen.
@export_range(0.0, 0.25, 0.01) var screen_center_glow := 0.055

var active_tween: Tween
var source_global_position := Vector2.ZERO
var is_powering_off := false
var screen_time := 0.0


func _ready() -> void:
	set_process(true)
	call_deferred("_initialize_crt_panel")


func _process(delta: float) -> void:
	if not visible or not screen_effect_enabled:
		return
	screen_time += delta
	queue_redraw()


func _draw() -> void:
	if not screen_effect_enabled:
		return
	var screen_size := size
	if screen_size.x <= 0.0 or screen_size.y <= 0.0:
		return
	_draw_screen_center_glow(screen_size)
	_draw_screen_phosphor_columns(screen_size)
	_draw_screen_scanlines(screen_size)
	_draw_screen_vignette(screen_size)


func _initialize_crt_panel() -> void:
	pivot_offset = size * 0.5
	if begin_powered_off:
		visible = false
		scale = Vector2.ZERO


func power_on() -> void:
	power_on_from(get_global_rect().get_center())


## Powers the panel on as though it is unfolding from a clicked screen position.
func power_on_from(global_position: Vector2) -> void:
	_stop_active_tween()
	is_powering_off = false
	var menu_audio := get_tree().get_first_node_in_group("menu_audio")
	if is_instance_valid(menu_audio):
		menu_audio.call("play_open")
	source_global_position = global_position
	pivot_offset = _global_source_to_pivot(global_position)
	visible = true
	scale = Vector2(0.0, line_scale)
	modulate = flash_color
	active_tween = create_tween()
	active_tween.tween_property(self, "scale:x", 1.0, horizontal_time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	active_tween.tween_property(self, "scale:y", 1.0, vertical_time).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	active_tween.parallel().tween_property(self, "modulate", Color.WHITE, vertical_time)


func power_off(immediate: bool = false) -> void:
	# Live status panels may request closure every frame after their condition clears.
	# Let the first CRT collapse finish instead of continually restarting its tween.
	if is_powering_off and not immediate:
		return
	_stop_active_tween()
	if immediate or not visible:
		is_powering_off = false
		visible = false
		scale = Vector2.ZERO
		modulate = Color.WHITE
		return
	var menu_audio := get_tree().get_first_node_in_group("menu_audio")
	if is_instance_valid(menu_audio):
		menu_audio.call("play_close")
	is_powering_off = true
	pivot_offset = _global_source_to_pivot(source_global_position)
	active_tween = create_tween()
	active_tween.tween_property(self, "scale:y", line_scale, vertical_time * 0.75).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	active_tween.parallel().tween_property(self, "modulate", flash_color, vertical_time * 0.75)
	active_tween.tween_property(self, "scale:x", 0.0, horizontal_time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	active_tween.tween_callback(func() -> void:
		visible = false
		modulate = Color.WHITE
		is_powering_off = false
	)


func _stop_active_tween() -> void:
	if is_instance_valid(active_tween):
		active_tween.kill()


func _global_source_to_pivot(global_position: Vector2) -> Vector2:
	var canvas_parent := get_parent() as CanvasItem
	if canvas_parent == null:
		# Direct children of a CanvasLayer use viewport coordinates.
		if get_parent() is CanvasLayer:
			return global_position - position
		return size * 0.5
	return canvas_parent.get_global_transform_with_canvas().affine_inverse() * global_position - position


func _draw_screen_scanlines(screen_size: Vector2) -> void:
	if screen_scanline_opacity <= 0.0:
		return
	var phase := fposmod(screen_time * screen_shimmer_speed * screen_scanline_spacing, screen_scanline_spacing)
	var line_color := Color(0.22, 0.95, 0.84, screen_scanline_opacity * screen_effect_intensity)
	var y := -phase
	while y < screen_size.y:
		draw_line(Vector2(0.0, y), Vector2(screen_size.x, y), line_color, 1.0, false)
		y += screen_scanline_spacing


func _draw_screen_phosphor_columns(screen_size: Vector2) -> void:
	if screen_phosphor_opacity <= 0.0:
		return
	var column_color := Color(0.12, 0.52, 0.5, screen_phosphor_opacity * screen_effect_intensity)
	var x := screen_phosphor_spacing * 0.5
	while x < screen_size.x:
		draw_line(Vector2(x, 0.0), Vector2(x, screen_size.y), column_color, 1.0, false)
		x += screen_phosphor_spacing


func _draw_screen_center_glow(screen_size: Vector2) -> void:
	if screen_center_glow <= 0.0:
		return
	var center := screen_size * 0.5
	var radius := maxf(screen_size.x, screen_size.y) * 0.62
	for index: int in range(12, 0, -1):
		var weight := float(index) / 12.0
		var alpha := screen_center_glow * screen_effect_intensity * weight * weight * 0.17
		draw_circle(center, radius * weight, Color(0.06, 0.55, 0.46, alpha))


func _draw_screen_vignette(screen_size: Vector2) -> void:
	if screen_vignette_strength <= 0.0:
		return
	var band := minf(screen_size.x, screen_size.y) * 0.16
	for index: int in range(8):
		var weight := float(index + 1) / 8.0
		var alpha := screen_vignette_strength * screen_effect_intensity * weight * 0.12
		var color := Color(0.0, 0.0, 0.0, alpha)
		var inset := band * (1.0 - weight)
		draw_rect(Rect2(0.0, 0.0, screen_size.x, inset), color)
		draw_rect(Rect2(0.0, screen_size.y - inset, screen_size.x, inset), color)
		draw_rect(Rect2(0.0, 0.0, inset, screen_size.y), color)
		draw_rect(Rect2(screen_size.x - inset, 0.0, inset, screen_size.y), color)
