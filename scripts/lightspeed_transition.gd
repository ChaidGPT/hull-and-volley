class_name LightspeedTransition
extends Control

signal jump_midpoint
signal jump_completed

var progress := 0.0:
	set(value):
		progress = value
		_update_status_text()
		queue_redraw()

var destination_name := ""
var status_label: Label
var aligned_ship: Node
var aligned_visual: CanvasItem
var target_ship_rotation := 0.0
var target_visual_rotation := 0.0
var visual_rest_position := Vector2.ZERO


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	z_index = 1000
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	status_label = Label.new()
	status_label.set_anchors_preset(Control.PRESET_CENTER)
	status_label.position = Vector2(-260.0, 128.0)
	status_label.size = Vector2(520.0, 48.0)
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.add_theme_font_size_override("font_size", 14)
	status_label.add_theme_color_override("font_color", Color(0.72, 1.0, 0.96))
	add_child(status_label)


func begin_jump(destination: GeneratedSector, ship: Node = null, ship_visual: CanvasItem = null) -> void:
	if visible or destination == null:
		return
	destination_name = destination.display_name.to_upper()
	aligned_ship = ship
	aligned_visual = ship_visual
	status_label.text = "VECTOR ALIGNMENT • ROTATING SHIP"
	progress = 0.0
	visible = true
	modulate = Color.WHITE

	var ship_rotation := 0.0
	if is_instance_valid(aligned_ship):
		ship_rotation = float(aligned_ship.get("ship_rotation"))
		target_ship_rotation = ship_rotation + angle_difference(ship_rotation, 0.0)
	var visual_rotation := 0.0
	if is_instance_valid(aligned_visual):
		visual_rotation = aligned_visual.rotation
		target_visual_rotation = visual_rotation + angle_difference(visual_rotation, 0.0)
		visual_rest_position = aligned_visual.position

	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "progress", 0.16, 0.58).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	if is_instance_valid(aligned_ship):
		tween.tween_property(aligned_ship, "ship_rotation", target_ship_rotation, 0.58).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
		tween.tween_property(aligned_ship, "previous_ship_rotation", target_ship_rotation, 0.58).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	if is_instance_valid(aligned_visual):
		tween.tween_property(aligned_visual, "rotation", target_visual_rotation, 0.58).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	tween.set_parallel(false)
	tween.tween_callback(_lock_alignment)
	tween.tween_interval(0.12)
	tween.set_parallel(true)
	tween.tween_property(self, "progress", 0.5, 0.76).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_IN)
	if is_instance_valid(aligned_visual):
		tween.tween_property(
			aligned_visual,
			"position",
			visual_rest_position + Vector2(0.0, -62.0),
			0.76
		).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_IN)
	tween.set_parallel(false)
	tween.tween_callback(jump_midpoint.emit)
	tween.tween_callback(_stage_arrival_visual)
	tween.tween_interval(0.1)
	tween.set_parallel(true)
	tween.tween_property(self, "progress", 1.0, 0.92).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	if is_instance_valid(aligned_visual):
		tween.tween_property(aligned_visual, "position", visual_rest_position, 0.7).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tween.tween_property(aligned_visual, "modulate", Color.WHITE, 0.42).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.set_parallel(false)
	tween.tween_callback(_finish_jump)


func _lock_alignment() -> void:
	if is_instance_valid(aligned_ship):
		aligned_ship.set("ship_rotation", 0.0)
		aligned_ship.set("previous_ship_rotation", 0.0)
		if aligned_ship.get("velocity") is Vector2:
			aligned_ship.set("velocity", Vector2.ZERO)
	if is_instance_valid(aligned_visual):
		aligned_visual.rotation = 0.0


func _stage_arrival_visual() -> void:
	if not is_instance_valid(aligned_visual):
		return
	aligned_visual.position = visual_rest_position + Vector2(0.0, 48.0)
	aligned_visual.modulate = Color(0.72, 0.9, 1.0, 0.68)


func _finish_jump() -> void:
	if is_instance_valid(aligned_visual):
		aligned_visual.position = visual_rest_position
		aligned_visual.rotation = 0.0
		aligned_visual.modulate = Color.WHITE
	visible = false
	progress = 0.0
	aligned_ship = null
	aligned_visual = null
	jump_completed.emit()


func _draw() -> void:
	if not visible:
		return
	var center := size * 0.5
	var warp_strength := _warp_strength()
	var blackout_alpha := smoothstep(0.14, 0.38, progress) * (1.0 - smoothstep(0.72, 1.0, progress))
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.0, 0.012, 0.022, blackout_alpha * 0.88))

	if progress < 0.17:
		_draw_alignment_lanes(center)
	else:
		_draw_vertical_starfield(center, warp_strength)

	var flash := clampf(1.0 - absf(progress - 0.5) / 0.045, 0.0, 1.0)
	if flash > 0.0:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.72, 0.96, 1.0, flash * 0.88))
		draw_rect(Rect2(Vector2(center.x - 42.0, 0.0), Vector2(84.0, size.y)), Color(1.0, 1.0, 1.0, flash * 0.34))


func _warp_strength() -> float:
	if progress <= 0.5:
		return smoothstep(0.16, 0.48, progress)
	return 1.0 - smoothstep(0.58, 0.96, progress)


func _draw_alignment_lanes(center: Vector2) -> void:
	var alignment := smoothstep(0.0, 0.16, progress)
	var color := Color(0.24, 0.95, 0.9, 0.18 + alignment * 0.32)
	var lane_half_width := lerpf(130.0, 62.0, alignment)
	draw_line(Vector2(center.x - lane_half_width, size.y), Vector2(center.x - 28.0, center.y - 120.0), color, 1.5, true)
	draw_line(Vector2(center.x + lane_half_width, size.y), Vector2(center.x + 28.0, center.y - 120.0), color, 1.5, true)
	for index: int in range(6):
		var y := lerpf(size.y - 40.0, center.y - 90.0, float(index) / 5.0)
		var width := lerpf(lane_half_width, 30.0, float(index) / 5.0)
		draw_line(Vector2(center.x - width, y), Vector2(center.x - width + 10.0, y), color, 1.0)
		draw_line(Vector2(center.x + width, y), Vector2(center.x + width - 10.0, y), color, 1.0)


func _draw_vertical_starfield(center: Vector2, warp_strength: float) -> void:
	var travel_offset := progress * size.y * (2.4 + warp_strength * 7.0)
	var streak_length := lerpf(2.0, size.y * 0.46, pow(warp_strength, 1.8))
	for index: int in range(112):
		var x_weight := fmod(float(index * 73 + 19), 113.0) / 113.0
		var base_y := fmod(float(index * 137 + 41), maxf(size.y, 1.0))
		var x := x_weight * size.x
		if absf(x - center.x) < 54.0:
			x += 112.0 if x < center.x else -112.0
		var speed_band := 0.52 + fmod(float(index * 31), 47.0) / 94.0
		var head_y := fmod(base_y + travel_offset * speed_band, size.y + streak_length) - streak_length
		var tail_y := head_y + streak_length * speed_band
		var brightness := 0.2 + warp_strength * 0.72
		var star_color := Color(
			0.58 + x_weight * 0.18,
			0.84 + x_weight * 0.14,
			1.0,
			brightness
		)
		draw_line(Vector2(x, head_y), Vector2(x, tail_y), star_color, 0.8 + warp_strength * 1.7, true)

	# A narrow, clear forward corridor keeps the real player ship readable beneath the effect.
	var corridor_alpha := warp_strength * 0.26
	draw_line(Vector2(center.x - 58.0, size.y), Vector2(center.x - 30.0, 0.0), Color(0.2, 0.9, 1.0, corridor_alpha), 1.0)
	draw_line(Vector2(center.x + 58.0, size.y), Vector2(center.x + 30.0, 0.0), Color(0.2, 0.9, 1.0, corridor_alpha), 1.0)


func _update_status_text() -> void:
	if not is_instance_valid(status_label):
		return
	if progress < 0.16:
		status_label.text = "VECTOR ALIGNMENT • ROTATING SHIP"
	elif progress < 0.28:
		status_label.text = "LIGHT-SPEED DRIVE • CHARGING"
	elif progress < 0.5:
		status_label.text = "LIGHT-SPEED DRIVE • ACCELERATING"
	elif progress < 0.62:
		status_label.text = "LIGHT-SPEED TRANSIT • %s" % destination_name
	elif progress < 0.9:
		status_label.text = "DECELERATING • DESTINATION SIGNAL ACQUIRED"
	else:
		status_label.text = "SECTOR RESOLUTION • %s" % destination_name
