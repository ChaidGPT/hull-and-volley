extends Node

signal camera_manipulated

@export_category("View Zoom")
@export var target_path: NodePath
@export var zoom_label_path: NodePath
@export var zoom_label_prefix := "ZOOM"
@export_range(0.1, 1.0, 0.05) var minimum_zoom := 0.5
@export_range(1.0, 5.0, 0.1) var maximum_zoom := 2.0
@export_range(1.01, 1.5, 0.01) var zoom_step := 1.15
@export var allow_panning := true
@export var zoom_around_pointer := true
@export var keep_labels_screen_sized := true
@export var manage_label_opacity := true
@export_range(0.0, 2.0, 0.05) var label_fade_start_zoom := 0.0
@export_range(0.0, 2.0, 0.05) var label_hidden_zoom := 0.0

@onready var view: Control = get_parent()
@onready var target: Control = get_node(target_path)
@onready var zoom_label: Label = get_node_or_null(zoom_label_path)

var zoom_level := 1.0
var is_drag_panning := false


func _ready() -> void:
	call_deferred("_apply_zoom")


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			if not allow_panning:
				return
			if event.pressed and _is_mouse_inside_view():
				is_drag_panning = true
				camera_manipulated.emit()
				get_viewport().set_input_as_handled()
			elif not event.pressed and is_drag_panning:
				is_drag_panning = false
				camera_manipulated.emit()
				get_viewport().set_input_as_handled()
			return

		if not event.pressed or not _is_mouse_inside_view():
			return

		var requested_zoom := zoom_level
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			requested_zoom *= zoom_step
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			requested_zoom /= zoom_step
		else:
			return

		var old_zoom := zoom_level
		zoom_level = clampf(requested_zoom, minimum_zoom, maximum_zoom)
		if zoom_around_pointer:
			var target_parent := target.get_parent() as Control
			var mouse_in_parent: Vector2 = target_parent.get_local_mouse_position()
			var pivot_from_mouse: Vector2 = mouse_in_parent - target.position - target.pivot_offset
			target.position += pivot_from_mouse * (1.0 - zoom_level / old_zoom)
		_apply_zoom()
		camera_manipulated.emit()
		get_viewport().set_input_as_handled()

	elif event is InputEventMouseMotion and is_drag_panning:
		target.position += event.relative
		camera_manipulated.emit()
		get_viewport().set_input_as_handled()


func _apply_zoom() -> void:
	target.pivot_offset = target.size * 0.5
	target.scale = Vector2.ONE * zoom_level
	if keep_labels_screen_sized:
		var label_alpha := 1.0
		if label_fade_start_zoom > label_hidden_zoom:
			label_alpha = smoothstep(label_hidden_zoom, label_fade_start_zoom, zoom_level)
		for node: Node in target.find_children("*", "Label", true, false):
			var label := node as Label
			label.pivot_offset = label.size * 0.5
			label.scale = Vector2.ONE / zoom_level
			if manage_label_opacity:
				label.modulate.a = label_alpha
	target.queue_redraw()
	if is_instance_valid(zoom_label):
		zoom_label.text = "%s • %.2fx" % [zoom_label_prefix, zoom_level]


func refresh_content() -> void:
	_apply_zoom()


func set_zoom_level(value: float) -> void:
	zoom_level = clampf(value, minimum_zoom, maximum_zoom)
	_apply_zoom()


func set_zoom_level_around_view_center(value: float) -> void:
	var previous_zoom := zoom_level
	zoom_level = clampf(value, minimum_zoom, maximum_zoom)
	if is_equal_approx(zoom_level, previous_zoom):
		return
	var target_parent := target.get_parent() as Control
	var view_center_global := view.get_global_transform_with_canvas() * (view.size * 0.5)
	var view_center_in_parent := target_parent.get_global_transform_with_canvas().affine_inverse() * view_center_global
	var pivot_from_center := view_center_in_parent - target.position - target.pivot_offset
	target.position += pivot_from_center * (1.0 - zoom_level / previous_zoom)
	_apply_zoom()
	camera_manipulated.emit()


func _is_mouse_inside_view() -> bool:
	return Rect2(Vector2.ZERO, view.size).has_point(view.get_local_mouse_position())
