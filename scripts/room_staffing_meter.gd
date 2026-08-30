class_name RoomStaffingMeter
extends Control

signal fill_requested

var minimum_crew := 0
var optimal_crew := 0
var assigned_crew := 0
var present_crew := 0
var operating_crew := 0
var can_fill := false
var pointer_inside := false
var pulse_time := 0.0
var command_flash := 0.0

const BACKGROUND := Color(0.012, 0.038, 0.038, 0.98)
const FRAME := Color(0.18, 0.56, 0.5, 0.9)
const OPERATING := Color(0.28, 1.0, 0.68, 1.0)
const PRESENT := Color(0.24, 0.88, 1.0, 1.0)
const EN_ROUTE := Color(1.0, 0.76, 0.2, 1.0)
const EMPTY := Color(0.14, 0.24, 0.23, 0.9)
const REQUIRED := Color(1.0, 0.34, 0.18, 0.95)


func _ready() -> void:
	custom_minimum_size = Vector2(0.0, 62.0)
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	queue_redraw()


func _process(delta: float) -> void:
	pulse_time += delta
	command_flash = maxf(command_flash - delta * 4.0, 0.0)
	queue_redraw()
	if not pointer_inside and command_flash <= 0.0 and assigned_crew >= optimal_crew:
		set_process(false)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		command_flash = 1.0
		set_process(true)
		queue_redraw()
		if can_fill:
			fill_requested.emit()
		accept_event()


func set_staffing_state(minimum: int, optimal: int, assigned: int, present: int, operating: int, fill_available: bool) -> void:
	minimum_crew = maxi(minimum, 0)
	optimal_crew = maxi(optimal, minimum_crew)
	assigned_crew = maxi(assigned, 0)
	present_crew = maxi(present, 0)
	operating_crew = maxi(operating, 0)
	can_fill = fill_available and assigned_crew < optimal_crew
	var en_route := maxi(assigned_crew - present_crew, 0)
	var open_slots := maxi(optimal_crew - assigned_crew, 0)
	var state_parts: PackedStringArray = []
	if operating_crew > 0:
		state_parts.append("%d OPERATING" % operating_crew)
	if en_route > 0:
		state_parts.append("%d EN ROUTE" % en_route)
	if open_slots > 0:
		state_parts.append("%d OPEN" % open_slots)
	var lines: PackedStringArray = []
	if optimal_crew <= 0:
		lines.append("NO CREW REQUIRED")
	elif not state_parts.is_empty():
		lines.append("".join(state_parts))
	if can_fill:
		lines.append("CLICK • FILL OPEN STATIONS")
	tooltip_text = "\n".join(lines)
	set_process(pointer_inside or command_flash > 0.0 or open_slots > 0)
	queue_redraw()


func _on_mouse_entered() -> void:
	pointer_inside = true
	set_process(true)
	queue_redraw()


func _on_mouse_exited() -> void:
	pointer_inside = false
	queue_redraw()


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	var urgency := assigned_crew < minimum_crew
	var pulse := (sin(pulse_time * 5.0) + 1.0) * 0.5 if urgency else 0.0
	var frame_color := REQUIRED.lerp(Color(1.0, 0.7, 0.2, 1.0), pulse * 0.35) if urgency else FRAME
	if pointer_inside:
		frame_color = frame_color.lerp(Color(0.35, 1.0, 0.82, 1.0), 0.55)
	if command_flash > 0.0:
		frame_color = frame_color.lerp(Color.WHITE, command_flash * 0.65)
	draw_rect(rect, BACKGROUND.lightened(0.035 if pointer_inside else 0.0), true)
	draw_rect(rect.grow(-0.5), frame_color, false, 1.5 if pointer_inside else 1.0)
	draw_line(Vector2(8.0, 18.0), Vector2(size.x - 8.0, 18.0), Color(frame_color, 0.4), 1.0)

	var heading := "BATTLE STATIONS"
	var heading_color := REQUIRED if urgency else Color(0.52, 0.9, 0.82, 1.0)
	draw_string(ThemeDB.fallback_font, Vector2(9.0, 13.0), heading, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, heading_color)
	var prompt := "CLICK: FILL" if can_fill and pointer_inside else _state_caption()
	draw_string(ThemeDB.fallback_font, Vector2(size.x - 121.0, 13.0), prompt, HORIZONTAL_ALIGNMENT_RIGHT, 112.0, 9, frame_color)

	var slots := maxi(optimal_crew, 1)
	var gap := 5.0
	var available_width := maxf(size.x - 18.0, 20.0)
	var slot_width := minf(34.0, (available_width - gap * float(slots - 1)) / float(slots))
	var total_width := slot_width * float(slots) + gap * float(slots - 1)
	var start_x := 9.0 + maxf((available_width - total_width) * 0.5, 0.0)
	for index: int in range(slots):
		var slot_rect := Rect2(Vector2(start_x + float(index) * (slot_width + gap), 27.0), Vector2(slot_width, 24.0))
		var fill := EMPTY
		var edge := Color(0.2, 0.38, 0.36, 0.9)
		if index < operating_crew:
			fill = OPERATING
			edge = OPERATING.lightened(0.2)
		elif index < present_crew:
			fill = PRESENT
			edge = PRESENT.lightened(0.16)
		elif index < assigned_crew:
			fill = Color(EN_ROUTE, 0.72)
			edge = EN_ROUTE
		elif index < minimum_crew:
			fill = Color(REQUIRED, 0.08 + pulse * 0.1)
			edge = Color(REQUIRED, 0.7 + pulse * 0.25)
		if pointer_inside and slot_rect.grow(2.0).has_point(get_local_mouse_position()):
			fill = fill.lightened(0.18)
			edge = edge.lightened(0.24)
			draw_rect(slot_rect.grow(3.0), Color(edge, 0.13), true)
		draw_rect(slot_rect, fill, true)
		draw_rect(slot_rect, edge, false, 1.5)
		var center := slot_rect.get_center()
		draw_circle(center + Vector2(0.0, -3.0), 3.0, edge)
		draw_rect(Rect2(center + Vector2(-3.5, 1.0), Vector2(7.0, 7.0)), edge, index < assigned_crew)


func _state_caption() -> String:
	if optimal_crew <= 0:
		return "AUTOMATED"
	if assigned_crew < minimum_crew:
		return "CREW NEEDED"
	if operating_crew < assigned_crew:
		return "CREW MOVING"
	if assigned_crew < optimal_crew:
		return "PARTIAL"
	return "READY"
