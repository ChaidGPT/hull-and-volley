class_name LightspeedTransition
extends Control

signal jump_midpoint
signal jump_completed

const ALIGNMENT_END := 0.18
const STREAKS_BEGIN := 0.34
const SECTOR_CROSSING := 0.52

var progress := 0.0:
	set(value):
		progress = value
		_update_status_text()
		_apply_background_motion()
		queue_redraw()

var background_offset := 0.0:
	set(value):
		background_offset = value
		_apply_background_motion()

var thrust_strength := 0.0:
	set(value):
		thrust_strength = clampf(value, 0.0, 1.0)
		_apply_thrust_visual()

var destination_name := ""
var status_label: Label
var aligned_ship: Node
var aligned_visual: CanvasItem
var tactical_view: Node
var target_ship_rotation := 0.0
var target_visual_rotation := 0.0
var visual_rest_position := Vector2.ZERO
var visual_rest_modulate := Color.WHITE


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


func begin_jump(
	destination: GeneratedSector,
	ship: Node = null,
	ship_visual: CanvasItem = null,
	ship_view: Node = null
) -> void:
	if visible or destination == null:
		return
	destination_name = destination.display_name.to_upper()
	aligned_ship = ship
	aligned_visual = ship_visual
	tactical_view = ship_view
	status_label.text = "VECTOR ALIGNMENT • ROTATING SHIP"
	progress = 0.0
	background_offset = 0.0
	thrust_strength = 0.0
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
		visual_rest_modulate = aligned_visual.modulate

	# First the ship alone settles onto its upward jump vector.
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "progress", ALIGNMENT_END, 0.62).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	if is_instance_valid(aligned_ship):
		tween.tween_property(aligned_ship, "ship_rotation", target_ship_rotation, 0.62).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
		tween.tween_property(aligned_ship, "previous_ship_rotation", target_ship_rotation, 0.62).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	if is_instance_valid(aligned_visual):
		tween.tween_property(aligned_visual, "rotation", target_visual_rotation, 0.62).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	tween.set_parallel(false)
	tween.tween_callback(_lock_alignment)

	# Then the engines light and the actual tactical backdrop begins falling away.
	tween.set_parallel(true)
	tween.tween_property(self, "progress", STREAKS_BEGIN, 0.48).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_IN)
	tween.tween_property(self, "thrust_strength", 1.0, 0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "background_offset", 180.0, 0.48).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_IN)
	tween.set_parallel(false)

	# Long lines arrive only after visible acceleration has been established.
	tween.set_parallel(true)
	tween.tween_property(self, "progress", SECTOR_CROSSING, 0.56).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_IN)
	tween.tween_property(self, "background_offset", 820.0, 0.56).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_IN)
	tween.set_parallel(false)
	tween.tween_callback(jump_midpoint.emit)
	tween.tween_callback(_stage_arrival_visual)
	tween.tween_interval(0.06)

	# The destination inherits forward motion, then coasts while the ship rises to rest.
	tween.set_parallel(true)
	tween.tween_property(self, "progress", 1.0, 1.02).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "background_offset", 390.0, 1.02).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "thrust_strength", 0.0, 0.7).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	if is_instance_valid(aligned_visual):
		tween.tween_property(aligned_visual, "position", visual_rest_position, 0.82).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tween.tween_property(aligned_visual, "modulate", visual_rest_modulate, 0.48).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
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
	# The midpoint flash hides the reset so the new sector can inherit the motion.
	if is_instance_valid(tactical_view) and tactical_view.has_method("prepare_for_display"):
		tactical_view.call("prepare_for_display")
	if is_instance_valid(aligned_visual):
		# Sector entry resets the simulation to its new origin. Capture that new
		# visual home before applying the arrival offset so long jumps cannot land
		# the ship at its previous sector coordinates.
		visual_rest_position = aligned_visual.position
	background_offset = 0.0
	if not is_instance_valid(aligned_visual):
		return
	aligned_visual.position = visual_rest_position + Vector2(0.0, 72.0)
	aligned_visual.modulate = Color(0.72, 0.9, 1.0, visual_rest_modulate.a * 0.72)


func _finish_jump() -> void:
	thrust_strength = 0.0
	background_offset = 0.0
	if is_instance_valid(tactical_view) and tactical_view.has_method("clear_jump_background_motion"):
		tactical_view.call("clear_jump_background_motion")
	if is_instance_valid(aligned_visual):
		if aligned_visual.has_method("clear_propulsion_visual_command"):
			aligned_visual.call("clear_propulsion_visual_command")
		aligned_visual.position = visual_rest_position
		aligned_visual.rotation = 0.0
		aligned_visual.modulate = visual_rest_modulate
	visible = false
	progress = 0.0
	aligned_ship = null
	aligned_visual = null
	tactical_view = null
	jump_completed.emit()


func _apply_background_motion() -> void:
	if not is_instance_valid(tactical_view) or not tactical_view.has_method("set_jump_background_motion"):
		return
	tactical_view.call("set_jump_background_motion", background_offset, _streak_strength())


func _apply_thrust_visual() -> void:
	if not is_instance_valid(aligned_visual) or not aligned_visual.has_method("set_propulsion_visual_command"):
		return
	aligned_visual.call("set_propulsion_visual_command", {
		"forward": thrust_strength,
		"brake": 0.0,
		"turn": 0.0,
		"translation_exhaust": Vector2.ZERO,
	})


func _draw() -> void:
	if not visible:
		return
	var center := size * 0.5
	var streak_strength := _streak_strength()
	var blackout_in := smoothstep(0.28, 0.48, progress)
	var blackout_out := 1.0 - smoothstep(0.7, 1.0, progress)
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.0, 0.012, 0.022, blackout_in * blackout_out * 0.58))

	if streak_strength > 0.001:
		_draw_vertical_starfield(center, streak_strength)

	var flash := clampf(1.0 - absf(progress - SECTOR_CROSSING) / 0.045, 0.0, 1.0)
	if flash > 0.0:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.72, 0.96, 1.0, flash * 0.88))
		draw_rect(Rect2(Vector2(center.x - 42.0, 0.0), Vector2(84.0, size.y)), Color(1.0, 1.0, 1.0, flash * 0.34))


func _streak_strength() -> float:
	if progress < STREAKS_BEGIN:
		return 0.0
	if progress <= SECTOR_CROSSING:
		return smoothstep(STREAKS_BEGIN, 0.49, progress)
	return 1.0 - smoothstep(0.64, 0.94, progress)


func _draw_vertical_starfield(center: Vector2, streak_strength: float) -> void:
	var travel_offset := progress * size.y * (1.8 + streak_strength * 6.5)
	var streak_length := lerpf(4.0, size.y * 0.46, pow(streak_strength, 1.7))
	for index: int in range(112):
		var x_weight := fmod(float(index * 73 + 19), 113.0) / 113.0
		var base_y := fmod(float(index * 137 + 41), maxf(size.y, 1.0))
		var x := x_weight * size.x
		if absf(x - center.x) < 54.0:
			x += 112.0 if x < center.x else -112.0
		var speed_band := 0.52 + fmod(float(index * 31), 47.0) / 94.0
		var head_y := fmod(base_y + travel_offset * speed_band, size.y + streak_length) - streak_length
		var tail_y := head_y + streak_length * speed_band
		var brightness := 0.2 + streak_strength * 0.72
		var star_color := Color(0.58 + x_weight * 0.18, 0.84 + x_weight * 0.14, 1.0, brightness)
		draw_line(Vector2(x, head_y), Vector2(x, tail_y), star_color, 0.8 + streak_strength * 1.7, true)

	var corridor_alpha := streak_strength * 0.26
	draw_line(Vector2(center.x - 58.0, size.y), Vector2(center.x - 30.0, 0.0), Color(0.2, 0.9, 1.0, corridor_alpha), 1.0)
	draw_line(Vector2(center.x + 58.0, size.y), Vector2(center.x + 30.0, 0.0), Color(0.2, 0.9, 1.0, corridor_alpha), 1.0)


func _update_status_text() -> void:
	if not is_instance_valid(status_label):
		return
	if progress < ALIGNMENT_END:
		status_label.text = "VECTOR ALIGNMENT • ROTATING SHIP"
	elif progress < STREAKS_BEGIN:
		status_label.text = "MAIN THRUST • ACCELERATING"
	elif progress < SECTOR_CROSSING:
		status_label.text = "LIGHT-SPEED CORRIDOR • FORMING"
	elif progress < 0.68:
		status_label.text = "LIGHT-SPEED TRANSIT • %s" % destination_name
	elif progress < 0.92:
		status_label.text = "DECELERATING • DESTINATION SIGNAL ACQUIRED"
	else:
		status_label.text = "SECTOR RESOLUTION • %s" % destination_name
