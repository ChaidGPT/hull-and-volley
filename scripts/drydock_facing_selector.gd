class_name DrydockFacingSelector
extends Control

signal facing_selected(facing_quarters: int)
signal facing_blocked(facing_quarters: int)

const DIRECTIONS := [Vector2.UP, Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT]
const DIRECTION_NAMES := ["BOW", "STARBOARD", "AFT", "PORT"]

var current_facing := -1
var hovered_facing := -1
var pulse_time := 0.0
var available_facings := [true, true, true, true]


func _ready() -> void:
	custom_minimum_size = Vector2(94.0, 70.0)
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	tooltip_text = "ROTATE MOUNT"
	mouse_exited.connect(func() -> void:
		hovered_facing = -1
		queue_redraw()
	)
	set_process(true)


func _process(delta: float) -> void:
	pulse_time += delta
	if hovered_facing >= 0 or current_facing >= 0:
		queue_redraw()


func set_current_facing(facing_quarters: int) -> void:
	current_facing = posmod(facing_quarters, 4) if facing_quarters >= 0 else -1
	queue_redraw()


func set_available_facings(facings: Array) -> void:
	for facing: int in range(4):
		available_facings[facing] = facing < facings.size() and bool(facings[facing])
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		hovered_facing = _facing_at_position((event as InputEventMouseMotion).position)
		tooltip_text = (
			"FACE %s" % DIRECTION_NAMES[hovered_facing]
			if hovered_facing >= 0
			else "ROTATE MOUNT"
		)
		queue_redraw()
	elif event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed:
			var facing := _facing_at_position(mouse_event.position)
			if facing >= 0:
				if available_facings[facing]:
					current_facing = facing
					facing_selected.emit(facing)
				else:
					facing_blocked.emit(facing)
				accept_event()
				queue_redraw()


func _facing_at_position(point: Vector2) -> int:
	var center := size * 0.5
	var best := -1
	var best_distance := 17.0
	for facing: int in range(4):
		var anchor: Vector2 = center + DIRECTIONS[facing] * Vector2(31.0, 22.0)
		var distance: float = point.distance_to(anchor)
		if distance < best_distance:
			best_distance = distance
			best = facing
	return best


func _draw() -> void:
	var center := size * 0.5
	var idle := Color(0.14, 0.42, 0.42, 0.82)
	var live := Color(0.22, 1.0, 0.88, 0.98)
	var active := Color(1.0, 0.62, 0.18, 1.0)
	var locked := Color(0.72, 0.18, 0.12, 0.78)
	draw_line(center - Vector2(22.0, 0.0), center + Vector2(22.0, 0.0), Color(idle, 0.34), 1.0)
	draw_line(center - Vector2(0.0, 17.0), center + Vector2(0.0, 17.0), Color(idle, 0.34), 1.0)
	var hull := PackedVector2Array([
		center + Vector2(0.0, -9.0),
		center + Vector2(5.0, -4.0),
		center + Vector2(5.0, 8.0),
		center + Vector2(-5.0, 8.0),
		center + Vector2(-5.0, -4.0),
	])
	draw_colored_polygon(hull, Color(0.04, 0.16, 0.16, 0.96))
	draw_polyline(hull + PackedVector2Array([hull[0]]), live, 1.5, true)
	for facing: int in range(4):
		var direction: Vector2 = DIRECTIONS[facing]
		var anchor: Vector2 = center + direction * Vector2(31.0, 22.0)
		var is_current: bool = facing == current_facing
		var is_hovered: bool = facing == hovered_facing
		var is_available: bool = available_facings[facing]
		var color: Color = locked if not is_available else active if is_current else live if is_hovered else idle
		var glow: float = 0.12
		if is_current:
			glow = 0.2 + (sin(pulse_time * 5.0) + 1.0) * 0.055
		elif is_hovered:
			glow = 0.18
		draw_circle(anchor, 12.0, Color(color, glow))
		var side: Vector2 = direction.orthogonal()
		var tip: Vector2 = anchor + direction * 6.0
		var rear: Vector2 = anchor - direction * 4.0
		var wedge := PackedVector2Array([tip, rear + side * 5.0, rear - side * 5.0])
		draw_colored_polygon(wedge, Color(color, 0.82 if is_current or is_hovered else 0.26))
		draw_polyline(wedge + PackedVector2Array([wedge[0]]), color, 1.5, true)
