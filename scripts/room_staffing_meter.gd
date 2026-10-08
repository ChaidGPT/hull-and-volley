class_name RoomStaffingMeter
extends Control

const CREW_REQUIREMENT_DISPLAY := preload("res://scripts/crew_requirement_display.gd")

signal fill_requested

var minimum_crew := 0
var optimal_crew := 0
var assigned_crew := 0
var present_crew := 0
var operating_crew := 0
var can_fill := false
var eventual_crew_available := true
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


func set_staffing_state(minimum: int, optimal: int, assigned: int, present: int, operating: int, fill_available: bool, future_capacity_sufficient: bool = true) -> void:
	minimum_crew = maxi(minimum, 0)
	optimal_crew = maxi(optimal, minimum_crew)
	assigned_crew = maxi(assigned, 0)
	present_crew = maxi(present, 0)
	operating_crew = maxi(operating, 0)
	can_fill = fill_available and assigned_crew < optimal_crew
	eventual_crew_available = future_capacity_sufficient
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
	lines.append(CREW_REQUIREMENT_DISPLAY.plain_text(optimal_crew, operating_crew, eventual_crew_available))
	if not state_parts.is_empty():
		lines.append(" • ".join(state_parts))
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
	var urgency := operating_crew < optimal_crew and not eventual_crew_available
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

	if optimal_crew > 0:
		CREW_REQUIREMENT_DISPLAY.draw_status(
			self,
			Vector2(24.0, 39.0),
			optimal_crew,
			operating_crew,
			eventual_crew_available,
			18.0
		)
		draw_string(
			ThemeDB.fallback_font,
			Vector2(47.0, 43.0),
			"%d / %d MANNED" % [mini(operating_crew, optimal_crew), optimal_crew],
			HORIZONTAL_ALIGNMENT_LEFT,
			-1.0,
			10,
			frame_color
		)
	else:
		draw_string(ThemeDB.fallback_font, Vector2(9.0, 42.0), "NO CREW STATIONS", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, EMPTY.lightened(0.5))


func _state_caption() -> String:
	if optimal_crew <= 0:
		return "AUTOMATED"
	if operating_crew >= optimal_crew:
		return "FULL WATCH"
	if not eventual_crew_available:
		return "BERTH SHORTAGE"
	if operating_crew < optimal_crew:
		return "CREW PENDING"
	return "READY"
