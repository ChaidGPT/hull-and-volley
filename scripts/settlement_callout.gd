extends Control

@export_range(60.0, 180.0, 5.0) var line_length := 105.0
@export_range(10.0, 50.0, 2.0) var diagonal_length := 24.0
@export_range(1.0, 12.0, 0.5) var fade_speed := 7.0

@onready var room_label: Label = %RoomLabel

var anchor_position := Vector2.ZERO
var line_direction := 1.0
var target_alpha := 0.0
var current_alpha := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	room_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	modulate.a = 0.0


func _process(delta: float) -> void:
	current_alpha = move_toward(current_alpha, target_alpha, fade_speed * delta)
	modulate.a = current_alpha
	queue_redraw()


func show_room(room_name: String, new_anchor_position: Vector2) -> void:
	anchor_position = new_anchor_position
	line_direction = -1.0 if anchor_position.x < size.x * 0.5 else 1.0
	room_label.text = room_name
	_update_label_position()
	target_alpha = 1.0


func hide_room() -> void:
	target_alpha = 0.0


func _draw() -> void:
	if current_alpha <= 0.001:
		return

	var color := Color(0.65, 0.88, 0.88, 0.92)
	var elbow := anchor_position + Vector2(line_direction * diagonal_length, -diagonal_length)
	var line_end := elbow + Vector2(line_direction * line_length, 0)
	draw_circle(anchor_position, 3.5, Color(0.04, 0.07, 0.08), true)
	draw_circle(anchor_position, 4.5, color, false, 1.5)
	draw_line(anchor_position + Vector2(line_direction * 4.0, -4.0), elbow, color, 1.5)
	draw_line(elbow, line_end, color, 1.5)
	draw_line(elbow, elbow + Vector2(line_direction * 16.0, 0), Color(0.95, 0.72, 0.3, 0.95), 3.0)


func _update_label_position() -> void:
	var elbow := anchor_position + Vector2(line_direction * diagonal_length, -diagonal_length)
	var line_end := elbow + Vector2(line_direction * line_length, 0)
	room_label.size = Vector2(180, 24)
	room_label.position.y = line_end.y - 22.0
	if line_direction > 0.0:
		room_label.position.x = line_end.x + 8.0
		room_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	else:
		room_label.position.x = line_end.x - room_label.size.x - 8.0
		room_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
