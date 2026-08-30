class_name ArcadeResourceMeter
extends Control

const POWER_ICON := preload("res://assets/sprites/ui/icons/power.png")
const POWER_DARK_ICON := preload("res://assets/sprites/ui/icons/power_dark.png")
const POWER_ALERT_ICON := preload("res://assets/sprites/ui/icons/power_alert.png")
const CREW_ICON := preload("res://assets/sprites/ui/icons/crew.png")
const CREW_DARK_ICON := preload("res://assets/sprites/ui/icons/crew_dark.png")
const CREW_ALERT_ICON := preload("res://assets/sprites/ui/icons/crew_alert.png")

enum MeterKind {
	POWER,
	CREW,
}

@export var meter_kind := MeterKind.POWER
@export var power_cell_units := 1.0
@export_range(6, 24, 1) var maximum_power_cells := 20

var power_capacity := 0.0
var power_online_capacity := 0.0
var power_used := 0.0
var preview_capacity_delta := 0.0
var preview_demand_delta := 0.0

var crew_working := 0
var crew_available := 0
var crew_injured := 0
var crew_missing := 0
var crew_preview := 0
var crew_capacity := -1
var crew_security := 0
var crew_labor := 0
var pointer_inside := false
var pointer_local := Vector2.ZERO
var hover_phase := 0.0
var interaction_flash := 0.0
var summary_tooltip := ""
var crew_context := "live"
var hover_regions: Array[Dictionary] = []
var reinforcement_active := false
var reinforcement_remaining := 0.0
var reinforcement_duration := 1.0
var reinforcement_sources := 0
var reinforcement_mode := ""

const PANEL_COLOR := Color(0.006, 0.028, 0.03, 0.96)
const FRAME_COLOR := Color(0.12, 0.42, 0.4, 0.92)
const POWER_USED_COLOR := Color(0.24, 0.94, 1.0, 0.96)
const POWER_OPEN_COLOR := Color(0.08, 0.24, 0.24, 0.9)
const AVAILABLE_COLOR := Color(0.32, 1.0, 0.62, 0.96)
const RESERVE_COLOR := Color(1.0, 0.72, 0.24, 0.98)
const INJURED_COLOR := Color(1.0, 0.68, 0.22, 0.98)
const DANGER_COLOR := Color(1.0, 0.24, 0.16, 0.96)
const PREVIEW_COLOR := Color(1.0, 0.78, 0.24, 0.98)


func _ready() -> void:
	custom_minimum_size.y = maxf(custom_minimum_size.y, 54.0)
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	mouse_entered.connect(_on_pointer_entered)
	mouse_exited.connect(_on_pointer_exited)
	set_process(false)
	queue_redraw()


func _process(delta: float) -> void:
	hover_phase += delta
	interaction_flash = maxf(interaction_flash - delta * 4.5, 0.0)
	if pointer_inside:
		pointer_local = get_local_mouse_position()
		_update_context_tooltip()
	queue_redraw()
	if not pointer_inside and interaction_flash <= 0.0 and not reinforcement_active:
		set_process(false)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		interaction_flash = 1.0
		set_process(true)
		queue_redraw()
		accept_event()


func _on_pointer_entered() -> void:
	pointer_inside = true
	pointer_local = get_local_mouse_position()
	set_process(true)
	queue_redraw()


func _on_pointer_exited() -> void:
	pointer_inside = false
	queue_redraw()


func set_power_state(capacity: float, used: float, online_capacity: float = -1.0, capacity_preview: float = 0.0, demand_preview: float = 0.0) -> void:
	power_capacity = maxf(capacity, 0.0)
	power_used = maxf(used, 0.0)
	power_online_capacity = power_capacity if online_capacity < 0.0 else clampf(online_capacity, 0.0, power_capacity)
	preview_capacity_delta = capacity_preview
	preview_demand_delta = demand_preview
	var open_power := power_online_capacity - power_used
	var lines: PackedStringArray = [
		"%d COMMITTED • %d OPEN" % [
			roundi(power_used),
			roundi(maxf(open_power, 0.0)),
		],
	]
	if power_used > power_online_capacity:
		lines.append("⚠ %d POWER DEFICIT" % roundi(power_used - power_online_capacity))
	if not is_zero_approx(preview_capacity_delta):
		lines.append("INSTALL • %+.0f POWER" % preview_capacity_delta)
	if not is_zero_approx(preview_demand_delta):
		lines.append("INSTALL • %.0f POWER NEEDED" % preview_demand_delta)
	summary_tooltip = "\n".join(lines)
	tooltip_text = summary_tooltip
	queue_redraw()


func set_crew_state(working: int, available: int, injured: int, missing: int = 0, preview: int = 0, context: String = "live", capacity: int = -1, security: int = 0, labor: int = 0) -> void:
	crew_working = maxi(working, 0)
	crew_available = maxi(available, 0)
	crew_injured = maxi(injured, 0)
	crew_missing = maxi(missing, 0)
	crew_preview = maxi(preview, 0)
	crew_capacity = capacity
	crew_security = maxi(security, 0)
	crew_labor = maxi(labor, 0)
	crew_context = context
	var total := crew_working + crew_available + crew_injured + crew_security + crew_labor
	var lines: PackedStringArray = []
	var duty_parts: PackedStringArray = []
	if context == "blueprint":
		if crew_working > 0:
			duty_parts.append("%d REQUIRED" % crew_working)
		if crew_available > 0:
			duty_parts.append("%d READY" % crew_available)
	else:
		if crew_working > 0:
			duty_parts.append("%d ON DUTY" % crew_working)
		if crew_security > 0:
			duty_parts.append("%d SECURITY" % crew_security)
		if crew_labor > 0:
			duty_parts.append("%d LABOR" % crew_labor)
		if crew_available > 0:
			duty_parts.append("%d READY" % crew_available)
	if not duty_parts.is_empty():
		lines.append("".join(duty_parts))
	if crew_capacity >= 0:
		var open_berths := maxi(crew_capacity - total, 0)
		if open_berths > 0:
			lines.append("%d OPEN BERTH%s" % [open_berths, "" if open_berths == 1 else "S"])
		if total > crew_capacity:
			lines.append("⚠ %d OVER CAPACITY" % (total - crew_capacity))
	if crew_injured > 0:
		lines.append("⚠ %d INJURED" % crew_injured)
	if crew_missing > 0:
		lines.append("⚠ %d STATIONS UNFILLED" % crew_missing)
	if crew_preview > 0:
		lines.append("INSTALL • %d CREW COMMITTED" % crew_preview)
	if lines.is_empty():
		lines.append("NO CREW ABOARD")
	summary_tooltip = "\n".join(lines)
	tooltip_text = summary_tooltip
	queue_redraw()


func set_reinforcement_state(status: Dictionary) -> void:
	reinforcement_active = not status.is_empty() and bool(status.get("active", false))
	if not reinforcement_active:
		reinforcement_remaining = 0.0
		reinforcement_sources = 0
		reinforcement_mode = ""
		return
	reinforcement_remaining = float(status.get("remaining", 0.0))
	reinforcement_duration = maxf(float(status.get("duration", 1.0)), 0.001)
	reinforcement_sources = int(status.get("sources", 0))
	reinforcement_mode = String(status.get("mode", "REINFORCEMENT"))
	var reinforcement_line := "%s • %02d SEC • %d QUARTERS ONLINE" % [reinforcement_mode, ceili(reinforcement_remaining), reinforcement_sources]
	summary_tooltip = "%s\n%s" % [summary_tooltip, reinforcement_line]
	tooltip_text = summary_tooltip
	set_process(true)
	queue_redraw()


func _draw() -> void:
	hover_regions.clear()
	var panel_rect := Rect2(Vector2.ZERO, size)
	var active_strength := 1.0 if pointer_inside else interaction_flash
	var panel_color := PANEL_COLOR.lightened(0.055 * active_strength)
	var frame_color := FRAME_COLOR.lerp(Color(0.32, 1.0, 0.9, 1.0), 0.55 * active_strength)
	if interaction_flash > 0.0:
		frame_color = frame_color.lerp(PREVIEW_COLOR, interaction_flash * 0.65)
	draw_rect(panel_rect, panel_color, true)
	if active_strength > 0.0:
		draw_rect(panel_rect.grow(2.0), Color(frame_color, 0.09 + active_strength * 0.09), true)
	draw_rect(panel_rect.grow(-0.5), frame_color, false, 1.0 + active_strength)
	if active_strength > 0.0:
		draw_rect(panel_rect.grow(-3.0), Color(frame_color, 0.22), false, 1.0)
		_draw_interaction_brackets(panel_rect.grow(-2.0), frame_color)
	if meter_kind == MeterKind.CREW:
		_draw_crew_meter()
	else:
		_draw_power_meter()
	if pointer_inside:
		var scan_y := fmod(hover_phase * 31.0, maxf(size.y - 6.0, 1.0)) + 3.0
		draw_line(Vector2(4.0, scan_y), Vector2(size.x - 4.0, scan_y), Color(0.42, 1.0, 0.9, 0.13), 1.0)


func _draw_interaction_brackets(rect: Rect2, color: Color) -> void:
	var length := 8.0
	var width := 2.0
	draw_line(rect.position, rect.position + Vector2(length, 0.0), color, width)
	draw_line(rect.position, rect.position + Vector2(0.0, length), color, width)
	draw_line(Vector2(rect.end.x, rect.position.y), Vector2(rect.end.x - length, rect.position.y), color, width)
	draw_line(Vector2(rect.end.x, rect.position.y), Vector2(rect.end.x, rect.position.y + length), color, width)
	draw_line(Vector2(rect.position.x, rect.end.y), Vector2(rect.position.x + length, rect.end.y), color, width)
	draw_line(Vector2(rect.position.x, rect.end.y), Vector2(rect.position.x, rect.end.y - length), color, width)
	draw_line(rect.end, rect.end - Vector2(length, 0.0), color, width)
	draw_line(rect.end, rect.end - Vector2(0.0, length), color, width)


func _draw_power_meter() -> void:
	_draw_power_icon(Vector2(13.0, 11.0))
	draw_string(ThemeDB.fallback_font, Vector2(25.0, 13.0), "POWER FIELD", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.5, 0.88, 0.84, 0.9))
	_add_hover_region(Rect2(Vector2(5.0, 2.0), Vector2(88.0, 16.0)), summary_tooltip)
	var final_capacity := maxf(power_capacity + preview_capacity_delta, 0.0)
	var display_capacity := maxf(maxf(power_capacity, final_capacity), power_cell_units)
	var cell_units := maxf(power_cell_units, ceilf(display_capacity / float(maximum_power_cells)))
	var cell_count := clampi(ceili(display_capacity / cell_units), 1, maximum_power_cells)
	var start := Vector2(9.0, 21.0)
	var available_width := maxf(size.x - 18.0, 20.0)
	var gap := 3.0
	var cell_width := minf(16.0, (available_width - gap * float(cell_count - 1)) / float(cell_count))
	var total_width := cell_width * float(cell_count) + gap * float(cell_count - 1)
	start.x += maxf((available_width - total_width) * 0.5, 0.0)
	var preview_used_end := power_used + maxf(preview_demand_delta, 0.0)
	for index: int in range(cell_count):
		var unit_center := (float(index) + 0.5) * cell_units
		var rect := Rect2(start + Vector2(float(index) * (cell_width + gap), 0.0), Vector2(cell_width, 23.0))
		var fill := POWER_OPEN_COLOR
		var edge := Color(0.18, 0.56, 0.54, 0.9)
		if unit_center <= power_used:
			fill = POWER_USED_COLOR
			edge = POWER_USED_COLOR.lightened(0.25)
		elif preview_demand_delta > 0.0 and unit_center <= preview_used_end:
			fill = Color(PREVIEW_COLOR, 0.82)
			edge = PREVIEW_COLOR
		elif unit_center <= power_online_capacity:
			fill = POWER_OPEN_COLOR
			edge = Color(0.24, 0.75, 0.72, 0.92)
		elif unit_center <= power_capacity:
			fill = Color(DANGER_COLOR, 0.14)
			edge = Color(DANGER_COLOR, 0.52)
		elif unit_center <= final_capacity:
			fill = Color(PREVIEW_COLOR, 0.14)
			edge = PREVIEW_COLOR
		else:
			fill = Color(0.025, 0.055, 0.055, 0.7)
			edge = Color(0.1, 0.24, 0.23, 0.62)
		var cell_number := index + 1
		var cell_tooltip := "POWER CELL %02d • UNAVAILABLE\nNO REACTOR CAPACITY ASSIGNED" % cell_number
		if unit_center <= power_used:
			cell_tooltip = "POWER CELL %02d • COMMITTED\nRESERVED BY ACTIVE SHIP SYSTEMS" % cell_number
		elif preview_demand_delta > 0.0 and unit_center <= preview_used_end:
			cell_tooltip = "POWER CELL %02d • INSTALL PREVIEW\nPROPOSED GRID WILL COMMIT THIS UNIT" % cell_number
		elif unit_center <= power_online_capacity:
			cell_tooltip = "POWER CELL %02d • AVAILABLE\nREADY FOR ANOTHER GRID SYSTEM" % cell_number
		elif unit_center <= power_capacity:
			cell_tooltip = "POWER CELL %02d • OFFLINE\nCAPACITY EXISTS BUT THE REACTOR IS DOWN" % cell_number
		elif unit_center <= final_capacity:
			cell_tooltip = "POWER CELL %02d • INSTALL PREVIEW\nPROPOSED GRID ADDS THIS CAPACITY" % cell_number
		_add_hover_region(rect.grow(2.0), cell_tooltip)
		var cell_focused := pointer_inside and rect.grow(2.0).has_point(pointer_local)
		if pointer_inside:
			fill = fill.lightened(0.04)
			edge = edge.lightened(0.1)
		if cell_focused:
			fill = fill.lightened(0.2)
			edge = edge.lightened(0.28)
			draw_rect(rect.grow(4.0), Color(edge, 0.16), true)
			draw_rect(rect.grow(2.0), Color(edge, 0.22), false, 1.0)
		draw_rect(rect, fill, true)
		draw_rect(rect, edge, false, 1.5)
		draw_line(rect.position + Vector2(3.0, 4.0), rect.position + Vector2(rect.size.x - 3.0, 4.0), Color(edge, 0.55), 1.0)
		if unit_center > power_online_capacity and unit_center <= power_capacity:
			draw_line(rect.position + Vector2(2.0, rect.size.y - 2.0), rect.end - Vector2(2.0, rect.size.y - 2.0), Color(DANGER_COLOR, 0.55), 1.0)
	if power_used + maxf(preview_demand_delta, 0.0) > maxf(power_online_capacity + maxf(preview_capacity_delta, 0.0), 0.0):
		draw_line(Vector2(7.0, size.y - 4.0), Vector2(size.x - 7.0, size.y - 4.0), DANGER_COLOR, 2.0)


func _draw_crew_meter() -> void:
	var header_icon_point := Vector2(13.0, 10.0)
	_draw_crew_icon(header_icon_point, Color(0.48, 0.9, 0.84, 0.9), false, pointer_inside and pointer_local.distance_to(header_icon_point) < 8.0)
	draw_string(ThemeDB.fallback_font, Vector2(25.0, 13.0), "CREW ROSTER", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.5, 0.88, 0.84, 0.9))
	_add_hover_region(Rect2(Vector2(5.0, 1.0), Vector2(88.0, 17.0)), summary_tooltip)
	var states: Array[Dictionary] = []
	_append_crew_states(states, crew_working, POWER_USED_COLOR, false, "working")
	_append_crew_states(states, crew_security + crew_labor, RESERVE_COLOR, false, "reserve")
	_append_crew_states(states, crew_available, AVAILABLE_COLOR, false, "available")
	_append_crew_states(states, crew_injured, INJURED_COLOR, false, "injured")
	var current_crew := crew_working + crew_available + crew_injured + crew_security + crew_labor
	if crew_capacity >= 0:
		_append_crew_states(states, maxi(crew_capacity - current_crew, 0), Color(0.18, 0.42, 0.38, 0.8), true, "berth")
	if reinforcement_active:
		var forming_remaining := reinforcement_sources
		for state: Dictionary in states:
			if forming_remaining > 0 and String(state.get("kind", "")) == "berth":
				state["kind"] = "forming"
				state["color"] = AVAILABLE_COLOR.lerp(PREVIEW_COLOR, 0.25)
				forming_remaining -= 1
	_append_crew_states(states, crew_preview, PREVIEW_COLOR, true, "preview")
	_append_crew_states(states, crew_missing, DANGER_COLOR, true, "missing")
	if states.is_empty():
		states.append({"color": Color(0.15, 0.3, 0.29, 0.75), "outline": true, "kind": "empty"})
	var icon_spacing := 15.0
	var icons_per_row := maxi(floori((size.x - 18.0) / icon_spacing), 1)
	var rows := ceili(float(states.size()) / float(icons_per_row))
	var start_y := 27.0 if rows <= 1 else 22.0
	for index: int in range(states.size()):
		var row := floori(float(index) / float(icons_per_row))
		var column := index % icons_per_row
		var row_count := mini(icons_per_row, states.size() - row * icons_per_row)
		var row_width := float(row_count - 1) * icon_spacing
		var start_x := size.x * 0.5 - row_width * 0.5
		var point := Vector2(start_x + float(column) * icon_spacing, start_y + float(row) * 16.0)
		var state: Dictionary = states[index]
		var icon_focused := pointer_inside and pointer_local.distance_to(point) < 7.5
		_draw_crew_icon(point, state["color"], bool(state["outline"]), icon_focused)
		if String(state.get("kind", "")) == "forming":
			var progress := clampf(1.0 - reinforcement_remaining / reinforcement_duration, 0.0, 1.0)
			var pulse := 0.62 + sin(hover_phase * 6.0) * 0.22
			draw_circle(point + Vector2(0.0, 1.0), 7.2, Color(AVAILABLE_COLOR, 0.08 * pulse))
			draw_arc(point + Vector2(0.0, 1.0), 7.0, -PI * 0.5, -PI * 0.5 + TAU * progress, 18, Color(AVAILABLE_COLOR, pulse), 1.5)
		_add_hover_region(Rect2(point - Vector2(6.5, 7.5), Vector2(13.0, 15.0)), _crew_state_tooltip(String(state["kind"])))


func _append_crew_states(states: Array[Dictionary], count: int, color: Color, outline: bool, kind: String) -> void:
	for _index: int in range(count):
		states.append({"color": color, "outline": outline, "kind": kind})


func _crew_state_tooltip(kind: String) -> String:
	match kind:
		"working":
			return (
				"CREW SIGNAL • REQUIRED STAFF\nTHIS BERTH IS COMMITTED BY THE CURRENT DESIGN"
				if crew_context == "blueprint"
				else "CREW SIGNAL • ON DUTY\nCURRENTLY OPERATING A SHIP SYSTEM"
			)
		"reserve":
			return "CREW SIGNAL • RESERVE\nAVAILABLE FOR SECURITY, LABOR, OR DAMAGE CONTROL"
		"available":
			return "CREW SIGNAL • AVAILABLE\nHEALTHY CREW MEMBER WITH NO REQUIRED STATION"
		"injured":
			return "CREW SIGNAL • INJURED\nUNAVAILABLE UNTIL TREATED BY A MEDICAL SYSTEM"
		"berth":
			return "CREW BERTH • OPEN\nCREW QUARTERS WILL BEGIN A REINFORCEMENT CYCLE WHEN NEEDED"
		"forming":
			return "%s • %d CREW FORMING\n%02d SEC REMAINING • PARALLEL BERTH CYCLE" % [reinforcement_mode, reinforcement_sources, ceili(reinforcement_remaining)]
		"preview":
			return "CREW SIGNAL • INSTALL PREVIEW\nPROPOSED GRID WILL COMMIT THIS CREW MEMBER"
		"missing":
			return "CREW SIGNAL • STATION UNFILLED\nSHIP DESIGN REQUIRES MORE HEALTHY CREW"
		_:
			return "CREW ROSTER • NO CREW ABOARD"


func _add_hover_region(rect: Rect2, text: String) -> void:
	if not text.is_empty():
		hover_regions.append({"rect": rect, "text": text})


func _update_context_tooltip() -> void:
	var next_tooltip := summary_tooltip
	for region: Dictionary in hover_regions:
		var region_rect: Rect2 = region["rect"]
		if region_rect.has_point(pointer_local):
			next_tooltip = String(region["text"])
			break
	tooltip_text = next_tooltip


func _draw_power_icon(center: Vector2) -> void:
	var texture := POWER_ICON
	if power_used > power_online_capacity + 0.001:
		texture = POWER_ALERT_ICON
	elif power_online_capacity <= 0.001:
		texture = POWER_DARK_ICON
	_draw_authored_icon(texture, center)


func _draw_crew_icon(center: Vector2, color: Color, outline: bool, focused: bool = false) -> void:
	var texture := CREW_ICON
	if color.is_equal_approx(DANGER_COLOR) or color.is_equal_approx(INJURED_COLOR):
		texture = CREW_ALERT_ICON
	elif outline:
		texture = CREW_DARK_ICON
	var icon_rect := Rect2((center - Vector2(8.0, 8.0)).round(), Vector2(16.0, 16.0))
	if pointer_inside:
		draw_rect(icon_rect.grow(1.0), Color(color, 0.09), true)
	if focused:
		draw_circle(center + Vector2(0.0, 1.0), 8.0, Color(color, 0.16))
		draw_arc(center + Vector2(0.0, 1.0), 7.0, 0.0, TAU, 16, color.lightened(0.3), 1.2)
	draw_texture_rect(texture, icon_rect, false)


func _draw_authored_icon(texture: Texture2D, center: Vector2) -> void:
	if texture == null:
		return
	draw_texture_rect(texture, Rect2((center - Vector2(8.0, 8.0)).round(), Vector2(16.0, 16.0)), false)
