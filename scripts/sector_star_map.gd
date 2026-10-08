class_name SectorStarMap
extends Control

signal destination_selected(destination: GeneratedSector)

const ROUTE_Y := [72.0, 190.0, 308.0]
const NODE_RADIUS := 15.0
const FIRST_COLUMN_X := 115.0
const JOURNEY_SPACING := 190.0
const ACTIVE_BRANCH_SPAN := 430.0

var routes: Array[Resource] = []
var current_sector: GeneratedSector
var journey_sectors: Array[Resource] = []
var journey_route_slots := PackedInt32Array()
var hovered_route := -1
var animation_clock := 0.0
var star_points := PackedVector2Array()
var map_offset_x := 0.0
var drag_active := false
var drag_moved := false
var drag_last_x := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	clip_contents = true
	custom_minimum_size = Vector2(830.0, 380.0)
	_seed_star_field()
	set_process(true)


func set_map_data(
	new_routes: Array[Resource],
	origin: GeneratedSector = null,
	history: Array[Resource] = [],
	history_slots: PackedInt32Array = PackedInt32Array()
) -> void:
	routes = new_routes.duplicate()
	current_sector = origin
	journey_sectors = history.duplicate()
	journey_route_slots = history_slots.duplicate()
	hovered_route = -1
	_focus_active_routes()
	call_deferred("_focus_active_routes")
	queue_redraw()


func _process(delta: float) -> void:
	animation_clock += delta
	if visible:
		queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		if drag_active:
			var delta_x := motion.position.x - drag_last_x
			drag_last_x = motion.position.x
			if absf(delta_x) > 0.5:
				drag_moved = true
				map_offset_x = clampf(map_offset_x + delta_x, _minimum_map_offset(), 0.0)
				hovered_route = -1
				queue_redraw()
				mouse_default_cursor_shape = Control.CURSOR_DRAG
			return
		var new_hover := _route_at(motion.position)
		if new_hover != hovered_route:
			hovered_route = new_hover
			queue_redraw()
	if event is InputEventMouseButton:
		var click := event as InputEventMouseButton
		if click.button_index == MOUSE_BUTTON_WHEEL_UP and click.pressed:
			map_offset_x = clampf(map_offset_x + 80.0, _minimum_map_offset(), 0.0)
			queue_redraw()
			accept_event()
			return
		if click.button_index == MOUSE_BUTTON_WHEEL_DOWN and click.pressed:
			map_offset_x = clampf(map_offset_x - 80.0, _minimum_map_offset(), 0.0)
			queue_redraw()
			accept_event()
			return
		if click.button_index == MOUSE_BUTTON_LEFT:
			if click.pressed:
				drag_active = true
				drag_moved = false
				drag_last_x = click.position.x
				accept_event()
			else:
				drag_active = false
				mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if hovered_route >= 0 else Control.CURSOR_ARROW
				if not drag_moved:
					var index := _route_at(click.position)
					if index >= 0 and index < routes.size():
						var route := routes[index] as GeneratedSector
						if route != null:
							destination_selected.emit(route)
				accept_event()
	if event is InputEventMouseMotion and hovered_route < 0:
		mouse_default_cursor_shape = Control.CURSOR_ARROW
	else:
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT:
		hovered_route = -1
		mouse_default_cursor_shape = Control.CURSOR_ARROW
		queue_redraw()


func _draw() -> void:
	_draw_chart_background()
	draw_set_transform(Vector2(map_offset_x, 0.0))
	_draw_journey()
	var origin_position := _current_origin_position()
	for index: int in range(mini(routes.size(), 3)):
		var route := routes[index] as GeneratedSector
		if route == null:
			continue
		var center := Vector2(_active_route_x(), ROUTE_Y[index])
		_draw_branch(origin_position, center, route, index)
		_draw_sector_decoration(center, route, index == hovered_route)
	draw_set_transform(Vector2.ZERO)
	if hovered_route >= 0 and hovered_route < routes.size():
		var route := routes[hovered_route] as GeneratedSector
		if route != null:
			_draw_intelligence_card(route, hovered_route)
	else:
		_draw_idle_prompt()
	_draw_scroll_position()


func _draw_chart_background() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.002, 0.02, 0.028, 0.82))
	for point: Vector2 in star_points:
		var pulse := 0.28 + sin(animation_clock * 0.7 + point.x * 0.07) * 0.1
		draw_circle(point, 0.75, Color(0.36, 0.78, 0.82, pulse))
	draw_line(Vector2(45.0, 43.0), Vector2(785.0, 43.0), Color(0.1, 0.42, 0.44, 0.24), 1.0)
	draw_string(ThemeDB.fallback_font, Vector2(45.0, 33.0), "LOCAL SECTOR", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 9, Color(0.32, 0.63, 0.62))
	draw_string(ThemeDB.fallback_font, Vector2(706.0, 33.0), "NEXT JUMP", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 9, Color(0.72, 0.61, 0.32))


func _draw_journey() -> void:
	var opening_position := Vector2(FIRST_COLUMN_X, 190.0)
	_draw_origin(opening_position, journey_sectors.is_empty())
	var previous := opening_position
	for index: int in range(journey_sectors.size()):
		var sector := journey_sectors[index] as GeneratedSector
		if sector == null:
			continue
		var slot := journey_route_slots[index] if index < journey_route_slots.size() else 1
		var point := Vector2(FIRST_COLUMN_X + JOURNEY_SPACING * float(index + 1), ROUTE_Y[clampi(slot, 0, 2)])
		_draw_journey_connection(previous, point, sector.signal_color)
		_draw_history_sector(point, sector, index == journey_sectors.size() - 1)
		previous = point


func _draw_origin(origin_position: Vector2, is_current: bool) -> void:
	var cyan := Color(0.22, 0.92, 0.84)
	draw_circle(origin_position, 22.0, Color(0.01, 0.12, 0.13, 0.9))
	draw_arc(origin_position, 22.0, 0.0, TAU, 32, Color(cyan.r, cyan.g, cyan.b, 0.5), 1.0)
	draw_arc(origin_position, 16.0, -PI * 0.25, PI * 1.5, 24, cyan, 2.0)
	draw_circle(origin_position, 6.0 + sin(animation_clock * 2.0) * 0.75, Color(0.65, 1.0, 0.9))
	draw_line(origin_position + Vector2(-31.0, 0.0), origin_position + Vector2(-41.0, 0.0), cyan, 1.0)
	draw_string(ThemeDB.fallback_font, origin_position + Vector2(-71.0, 37.0), "OPENING SECTOR", HORIZONTAL_ALIGNMENT_CENTER, 143.0, 10, Color(0.68, 1.0, 0.93))
	if is_current:
		draw_string(ThemeDB.fallback_font, origin_position + Vector2(-71.0, 52.0), "CURRENT POSITION", HORIZONTAL_ALIGNMENT_CENTER, 143.0, 8, Color(0.28, 0.72, 0.67))


func _draw_history_sector(center: Vector2, sector: GeneratedSector, is_current: bool) -> void:
	var color := sector.signal_color
	draw_circle(center, 12.0, Color(0.008, 0.055, 0.065, 0.96))
	draw_arc(center, 12.0, 0.0, TAU, 24, color, 1.0)
	draw_circle(center, 4.0, _faction_color(sector))
	if is_current:
		draw_arc(center, 20.0, animation_clock, animation_clock + PI * 1.35, 26, Color(0.55, 1.0, 0.88), 2.0)
		draw_string(ThemeDB.fallback_font, center + Vector2(-72.0, 34.0), sector.display_name.to_upper(), HORIZONTAL_ALIGNMENT_CENTER, 144.0, 10, Color(0.72, 1.0, 0.94))
		draw_string(ThemeDB.fallback_font, center + Vector2(-72.0, 48.0), "CURRENT POSITION", HORIZONTAL_ALIGNMENT_CENTER, 144.0, 8, Color(0.3, 0.8, 0.7))


func _draw_journey_connection(start: Vector2, finish: Vector2, color: Color) -> void:
	var controls := PackedVector2Array()
	for step: int in range(20):
		var t := float(step) / 19.0
		var eased := t * t * (3.0 - 2.0 * t)
		controls.append(start.lerp(finish, eased))
	for segment: int in range(controls.size() - 1):
		draw_line(controls[segment], controls[segment + 1], Color(color.r, color.g, color.b, 0.42), 1.5, true)


func _draw_branch(origin: Vector2, destination: Vector2, route: GeneratedSector, index: int) -> void:
	var start := origin + Vector2(22.0, 0.0)
	var finish := destination - Vector2(NODE_RADIUS + 8.0, 0.0)
	var control_a := origin + Vector2(ACTIVE_BRANCH_SPAN * 0.36, 0.0)
	var control_b := destination - Vector2(ACTIVE_BRANCH_SPAN * 0.36, 0.0)
	var points := PackedVector2Array()
	for step: int in range(25):
		var t := float(step) / 24.0
		var inv := 1.0 - t
		points.append(
			start * inv * inv * inv
			+ control_a * 3.0 * inv * inv * t
			+ control_b * 3.0 * inv * t * t
			+ finish * t * t * t
		)
	var line_color := Color(route.signal_color.r, route.signal_color.g, route.signal_color.b, 0.23 if index != hovered_route else 0.78)
	for segment: int in range(points.size() - 1):
		if segment % 3 != 2:
			draw_line(points[segment], points[segment + 1], line_color, 1.2 if index != hovered_route else 2.0, true)


func _draw_sector_decoration(center: Vector2, route: GeneratedSector, hovered: bool) -> void:
	var color := route.signal_color
	var pulse := 1.0 + (0.08 * sin(animation_clock * 3.0) if hovered else 0.0)
	var radius := NODE_RADIUS * pulse
	_draw_environment_field(center, route, radius)
	draw_circle(center, radius + 7.0, Color(color.r, color.g, color.b, 0.05 if not hovered else 0.12))
	draw_arc(center, radius + 7.0, 0.0, TAU, 32, Color(color.r, color.g, color.b, 0.22 if not hovered else 0.72), 1.0)
	draw_circle(center, radius, Color(0.008, 0.055, 0.065, 0.96))
	draw_arc(center, radius, 0.0, TAU, 24, color, 2.0 if hovered else 1.0)
	draw_circle(center, 5.0, _faction_color(route))
	_draw_environment_tick(center, route, color)

	# Tiny rank tabs preserve the military-decoration language without dominating the chart.
	var danger_rank := clampi(ceili(float(route.danger_rating) / 20.0), 1, 5)
	var rank_start := center + Vector2(-15.0, radius + 13.0)
	for rank: int in range(5):
		var rank_color := Color(1.0, 0.34, 0.16) if rank < danger_rank else Color(0.13, 0.24, 0.25)
		draw_rect(Rect2(rank_start + Vector2(rank * 7.0, 0.0), Vector2(4.0, 2.0)), rank_color)
	draw_string(ThemeDB.fallback_font, center + Vector2(28.0, 4.0), "%02d" % (routes.find(route) + 1), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 9, Color(color.r, color.g, color.b, 0.65))
	if hovered:
		_draw_corner_brackets(center, radius + 13.0, color)
		draw_string(ThemeDB.fallback_font, center + Vector2(28.0, -10.0), route.display_name.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, 130.0, 10, Color(0.82, 1.0, 0.95))


func _draw_environment_field(center: Vector2, route: GeneratedSector, radius: float) -> void:
	var environment := String(route.environment_type)
	var color := Color(route.signal_color.r, route.signal_color.g, route.signal_color.b, 0.1)
	if environment in ["ASTEROID_BELT", "ASTEROID_FIELD", "SCATTERED_ASTEROIDS"]:
		var object_count := 9 if environment == "ASTEROID_BELT" else (6 if environment == "ASTEROID_FIELD" else 4)
		for index: int in range(object_count):
			var angle := float(index) * 2.39 + animation_clock * (0.08 + float(index % 3) * 0.02)
			var distance := radius + 11.0 + float((index * 13) % (19 if environment == "ASTEROID_BELT" else 11))
			var point := center + Vector2.from_angle(angle) * distance
			draw_circle(point, 1.0 + float(index % 2), color)
	elif environment == "FLEET_ANCHORAGE":
		for index: int in range(3):
			var offset := Vector2(-30.0 + index * 18.0, -27.0 + sin(animation_clock + index) * 2.0)
			draw_line(center + offset, center + offset + Vector2(6.0, 2.0), color, 1.0)
	elif environment == "BATTLEFIELD":
		for index: int in range(4):
			var angle := float(index) * 0.91
			var offset := Vector2.from_angle(angle) * (radius + 17.0)
			draw_line(center + offset - Vector2(3.0, 1.0), center + offset + Vector2(3.0, 1.0), color, 1.0)
	elif environment == "PLANETOID_SETTLEMENT":
		draw_arc(center, radius + 15.0, 0.0, TAU, 40, color, 1.0)


func _draw_environment_tick(center: Vector2, route: GeneratedSector, color: Color) -> void:
	var environment := String(route.environment_type)
	if environment == "ASTEROID_BELT":
		draw_circle(center + Vector2(-4.0, -4.0), 2.0, color)
		draw_circle(center + Vector2(4.0, 2.0), 1.5, color)
	elif environment == "ASTEROID_FIELD":
		draw_circle(center, 5.5, Color(color.r, color.g, color.b, 0.18))
		draw_circle(center + Vector2(-3.0, 1.0), 1.6, color)
		draw_circle(center + Vector2(3.0, -2.0), 1.2, color)
	elif environment == "SCATTERED_ASTEROIDS":
		draw_circle(center + Vector2(-4.0, -3.0), 1.4, color)
		draw_circle(center + Vector2(4.0, 3.0), 1.2, color)
	elif environment == "FLEET_ANCHORAGE":
		draw_line(center + Vector2(-6.0, 0.0), center + Vector2(6.0, 0.0), color, 1.0)
		draw_line(center + Vector2(2.0, -3.0), center + Vector2(6.0, 0.0), color, 1.0)
		draw_line(center + Vector2(2.0, 3.0), center + Vector2(6.0, 0.0), color, 1.0)
	elif environment == "BATTLEFIELD":
		draw_line(center + Vector2(-5.0, -5.0), center + Vector2(5.0, 5.0), color, 1.5)
		draw_line(center + Vector2(5.0, -5.0), center + Vector2(-5.0, 5.0), color, 1.5)
	elif environment == "PLANETOID_SETTLEMENT":
		draw_arc(center, 6.0, 0.0, TAU, 16, color, 1.0)


func _draw_intelligence_card(route: GeneratedSector, index: int) -> void:
	var center := Vector2(385.0, 190.0)
	var card_rect := Rect2(center - Vector2(112.0, 80.0), Vector2(224.0, 160.0))
	draw_rect(card_rect, Color(0.004, 0.045, 0.05, 0.97))
	draw_rect(card_rect, Color(route.signal_color.r, route.signal_color.g, route.signal_color.b, 0.8), false, 2.0)
	draw_string(ThemeDB.fallback_font, card_rect.position + Vector2(13.0, 20.0), "VECTOR %02d • LIVE INTEL" % (index + 1), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 10, Color(1.0, 0.7, 0.23))
	draw_string(ThemeDB.fallback_font, card_rect.position + Vector2(13.0, 42.0), route.display_name.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, 198.0, 15, route.signal_color)
	draw_multiline_string(ThemeDB.fallback_font, card_rect.position + Vector2(13.0, 63.0), route.intel_summary, HORIZONTAL_ALIGNMENT_LEFT, 198.0, 11, 13, Color(0.68, 0.92, 0.87))
	var intel_y := card_rect.position.y + 112.0
	var shown := mini(route.intel_lines.size(), 2)
	for intel_index: int in range(shown):
		draw_string(ThemeDB.fallback_font, Vector2(card_rect.position.x + 13.0, intel_y + intel_index * 15.0), "› %s" % route.intel_lines[intel_index], HORIZONTAL_ALIGNMENT_LEFT, 198.0, 10, Color(0.86, 0.9, 0.72))
	draw_string(ThemeDB.fallback_font, card_rect.position + Vector2(13.0, 151.0), "CLICK DECORATION TO COMMIT >", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 9, Color(0.35, 1.0, 0.8))


func _draw_idle_prompt() -> void:
	draw_string(ThemeDB.fallback_font, Vector2(250.0, 354.0), "DRAG OR SCROLL TO REVIEW JOURNEY • HOVER A JUMP POINT FOR INTELLIGENCE", HORIZONTAL_ALIGNMENT_CENTER, 380.0, 9, Color(0.3, 0.62, 0.61))


func _draw_corner_brackets(center: Vector2, radius: float, color: Color) -> void:
	var corners := [
		Vector2(-radius, -radius), Vector2(radius, -radius),
		Vector2(radius, radius), Vector2(-radius, radius),
	]
	for index: int in range(4):
		var point: Vector2 = center + corners[index]
		var horizontal_sign := 1.0 if index in [0, 3] else -1.0
		var vertical_sign := 1.0 if index in [0, 1] else -1.0
		draw_line(point, point + Vector2(horizontal_sign * 10.0, 0.0), color, 2.0)
		draw_line(point, point + Vector2(0.0, vertical_sign * 10.0), color, 2.0)


func _faction_color(route: GeneratedSector) -> Color:
	for faction: String in route.faction_signals:
		var upper := faction.to_upper()
		if "USC" in upper or "UDC" in upper or "UNITED" in upper:
			return Color(0.16, 0.68, 1.0)
		if "FSR" in upper or "REBEL" in upper:
			return Color(1.0, 0.27, 0.19)
		if "COMBINE" in upper or "CORP" in upper:
			return Color(1.0, 0.68, 0.16)
	return Color(0.28, 0.86, 0.7)


func _route_at(mouse_position: Vector2) -> int:
	var world_mouse := mouse_position - Vector2(map_offset_x, 0.0)
	for index: int in range(mini(routes.size(), 3)):
		if world_mouse.distance_to(Vector2(_active_route_x(), ROUTE_Y[index])) <= NODE_RADIUS + 20.0:
			return index
	return -1


func _current_origin_position() -> Vector2:
	if journey_sectors.is_empty():
		return Vector2(FIRST_COLUMN_X, 190.0)
	var last_index := journey_sectors.size() - 1
	var slot := journey_route_slots[last_index] if last_index < journey_route_slots.size() else 1
	return Vector2(FIRST_COLUMN_X + JOURNEY_SPACING * float(journey_sectors.size()), ROUTE_Y[clampi(slot, 0, 2)])


func _active_route_x() -> float:
	return _current_origin_position().x + ACTIVE_BRANCH_SPAN


func _content_width() -> float:
	return _active_route_x() + 120.0


func _minimum_map_offset() -> float:
	var viewport_width := maxf(size.x, custom_minimum_size.x)
	return minf(0.0, viewport_width - _content_width() - 20.0)


func _focus_active_routes() -> void:
	var desired_right_edge := _active_route_x() + 120.0
	var viewport_width := maxf(size.x, custom_minimum_size.x)
	map_offset_x = clampf(viewport_width - desired_right_edge - 20.0, _minimum_map_offset(), 0.0)
	queue_redraw()


func _draw_scroll_position() -> void:
	var minimum := _minimum_map_offset()
	if minimum >= -1.0:
		return
	var track := Rect2(Vector2(60.0, size.y - 10.0), Vector2(size.x - 120.0, 2.0))
	draw_rect(track, Color(0.08, 0.28, 0.3, 0.42))
	var visible_fraction := clampf(size.x / _content_width(), 0.12, 1.0)
	var thumb_width := track.size.x * visible_fraction
	var travel := track.size.x - thumb_width
	var progress := clampf((-map_offset_x) / maxf(-minimum, 1.0), 0.0, 1.0)
	draw_rect(Rect2(track.position + Vector2(progress * travel, -1.0), Vector2(thumb_width, 4.0)), Color(0.22, 0.84, 0.78, 0.72))


func _seed_star_field() -> void:
	var random := RandomNumberGenerator.new()
	random.seed = 771923
	star_points.clear()
	for _index: int in range(74):
		star_points.append(Vector2(random.randf_range(12.0, 818.0), random.randf_range(12.0, 368.0)))
