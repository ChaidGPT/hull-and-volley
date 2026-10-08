class_name ShipBuilderPreview
extends Control

const GRID_GEOMETRY := preload("res://scripts/grid_geometry.gd")
const SHIP_ANALYZER := preload("res://scripts/ship_builder_analyzer.gd")
const ROOM_STAFFING_RULES := preload("res://scripts/room_staffing_rules.gd")
const POWER_REQUIREMENT_DISPLAY := preload("res://scripts/power_requirement_display.gd")
const TACTICAL_SHIP_VISUAL := preload("res://scripts/tactical_ship_visual.gd")

@export var grid_color := Color(0.12, 0.36, 0.38, 0.45)
@export var envelope_color := Color(0.22, 0.9, 0.9, 0.95)
@export var hull_edge_color := Color(0.62, 0.76, 0.74, 1.0)
@export var empty_cell_color := Color(0.02, 0.05, 0.055, 0.45)
@export var room_tooltips_enabled := false

var ship_layout: Resource
var preview_size := Vector2i.ZERO
var tooltip_bounds := Rect2i()
var tooltip_cell_size := 0.0
var tooltip_origin := Vector2.ZERO
var hovered_room: Resource
var callout_alpha := 0.0
var callout_target_alpha := 0.0
var authored_visual_mode := false
var authored_deck_visual: Control


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP if room_tooltips_enabled else Control.MOUSE_FILTER_IGNORE
	if room_tooltips_enabled:
		mouse_exited.connect(_clear_room_tooltip)
		set_process(true)
	else:
		set_process(false)


func _process(delta: float) -> void:
	if not room_tooltips_enabled:
		return
	var next_alpha := move_toward(callout_alpha, callout_target_alpha, delta * 8.0)
	if not is_equal_approx(next_alpha, callout_alpha):
		callout_alpha = next_alpha
		queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if not room_tooltips_enabled or not event is InputEventMouseMotion:
		return
	var room := _room_at_position((event as InputEventMouseMotion).position)
	if room != hovered_room:
		hovered_room = room
		callout_target_alpha = 1.0 if room != null else 0.0
		queue_redraw()
	# This preview uses an anchored deck-style callout instead of the floating
	# SHIPNET tooltip terminal.
	set_meta(&"_crt_terminal_tooltip", "")
	tooltip_text = ""


func _clear_room_tooltip() -> void:
	hovered_room = null
	callout_target_alpha = 0.0
	set_meta(&"_crt_terminal_tooltip", "")
	tooltip_text = ""
	queue_redraw()


func set_layout(layout: Resource, size: Vector2i) -> void:
	authored_visual_mode = false
	if is_instance_valid(authored_deck_visual):
		authored_deck_visual.queue_free()
		authored_deck_visual = null
	ship_layout = layout
	preview_size = size
	queue_redraw()


## Shows the exact authored deck/module artwork used by the live ship instead
## of the compact blueprint shorthand. Choice cards use this close inspection
## mode so weapon barrels, room skins, and quarter-grid overlays are legible.
func set_authored_layout(layout: Resource) -> void:
	authored_visual_mode = true
	ship_layout = layout
	preview_size = Vector2i.ZERO
	clip_contents = true
	if not is_instance_valid(authored_deck_visual):
		authored_deck_visual = TACTICAL_SHIP_VISUAL.new() as Control
		authored_deck_visual.name = "AuthoredDeckVisual"
		authored_deck_visual.mouse_filter = Control.MOUSE_FILTER_IGNORE
		authored_deck_visual.set("blueprint_preview_mode", true)
		authored_deck_visual.set("tactical_hull_only_mode", false)
		authored_deck_visual.set("ship_layout", ship_layout)
		authored_deck_visual.process_mode = Node.PROCESS_MODE_DISABLED
		add_child(authored_deck_visual)
	elif authored_deck_visual.is_inside_tree():
		authored_deck_visual.call("set_ship_layout", ship_layout)
	else:
		authored_deck_visual.set("ship_layout", ship_layout)
	call_deferred("_sync_authored_deck_visual")
	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and authored_visual_mode:
		call_deferred("_sync_authored_deck_visual")


func _sync_authored_deck_visual() -> void:
	if not authored_visual_mode or not is_instance_valid(authored_deck_visual) or ship_layout == null:
		return
	var occupied: Rect2i = ship_layout.call("get_occupied_bounds", false)
	if occupied.size.x <= 0 or occupied.size.y <= 0 or size.x <= 1.0 or size.y <= 1.0:
		return
	# TacticalShipVisual renders at ten pixels per quarter-grid cell. Reserve
	# room for barrels/nozzles outside the hull, then scale the authored object
	# until it dominates the inspection viewport.
	var hull_pixels := Vector2(occupied.size) * 10.0
	var exterior_allowance := Vector2(26.0, 26.0)
	var available := Vector2(maxf(size.x - 24.0, 1.0), maxf(size.y - 24.0, 1.0))
	var fit_scale := minf(
		available.x / maxf(hull_pixels.x + exterior_allowance.x, 1.0),
		available.y / maxf(hull_pixels.y + exterior_allowance.y, 1.0)
	)
	fit_scale = clampf(fit_scale, 1.0, 12.0)
	authored_deck_visual.scale = Vector2.ONE * fit_scale
	var authored_hull_center := Vector2(10.0, 22.0) + hull_pixels * 0.5
	authored_deck_visual.position = size * 0.5 - authored_hull_center * fit_scale


func _draw() -> void:
	if ship_layout == null and preview_size == Vector2i.ZERO:
		return
	if authored_visual_mode:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.003, 0.014, 0.018, 0.96), true)
		draw_rect(Rect2(Vector2.ONE, size - Vector2.ONE * 2.0), Color(0.12, 0.72, 0.7, 0.42), false, 1.0)
		return
	var build_origin := Vector2i.ZERO
	var build_size := preview_size
	if ship_layout != null:
		if bool(ship_layout.get("unlimited_build_space")) and ship_layout.has_method("get_build_bounds"):
			var dynamic_bounds: Rect2i = ship_layout.call("get_build_bounds")
			build_origin = dynamic_bounds.position
			build_size = dynamic_bounds.size
		else:
			build_origin = ship_layout.get("build_origin")
			if build_size == Vector2i.ZERO:
				build_size = Vector2i(int(ship_layout.get("columns")), int(ship_layout.get("rows")))
	var bounds := Rect2i(build_origin, build_size)
	var padding := 18.0
	var horizontal_profile_allowance := 0.0
	var vertical_profile_allowance := 0.0
	if ship_layout != null:
		for room: Resource in ship_layout.get("rooms"):
			if (room.get("grid_rects") as Array).is_empty() or not GRID_GEOMETRY.has_exterior_profile(String(room.get("type_name"))):
				continue
			if String(room.get("type_name")) == "HANGAR":
				continue
			var facing_quarters := GRID_GEOMETRY.exterior_facing_quarters(room)
			if facing_quarters % 2 == 0:
				vertical_profile_allowance = 0.76
			else:
				horizontal_profile_allowance = 0.76
	var cell_size := minf(
		(size.x - padding * 2.0) / maxf(float(bounds.size.x) + horizontal_profile_allowance, 1.0),
		(size.y - padding * 2.0) / maxf(float(bounds.size.y) + vertical_profile_allowance, 1.0)
	)
	var grid_pixel := Vector2(bounds.size) * cell_size
	var origin := (size - grid_pixel) * 0.5
	tooltip_bounds = bounds
	tooltip_cell_size = cell_size
	tooltip_origin = origin
	var hull_cells: Dictionary = {}
	if ship_layout != null:
		for room: Resource in ship_layout.get("rooms"):
			for room_rect: Rect2i in room.get("grid_rects"):
				for room_y: int in range(room_rect.position.y, room_rect.end.y):
					for room_x: int in range(room_rect.position.x, room_rect.end.x):
						hull_cells[Vector2i(room_x, room_y)] = true
	var replaced_edges := (
		GRID_GEOMETRY.exterior_replaced_edge_keys(ship_layout.get("rooms"), hull_cells, ship_layout)
		if ship_layout != null
		else {}
	)
	draw_rect(Rect2(origin, grid_pixel), Color(0.005, 0.018, 0.02, 0.92), true)
	for y: int in range(bounds.position.y, bounds.end.y):
		for x: int in range(bounds.position.x, bounds.end.x):
			var cell := Vector2i(x, y)
			var rect := Rect2(origin + (Vector2(cell - bounds.position) * cell_size), Vector2(cell_size, cell_size))
			draw_rect(rect.grow(-1.0), empty_cell_color, true)
			draw_rect(rect, grid_color, false, 1.0)
	if ship_layout != null:
		for room: Resource in ship_layout.get("rooms"):
			var color: Color = room.get("color")
			var room_cells: Dictionary = {}
			for rect: Rect2i in room.get("grid_rects"):
				for y: int in range(rect.position.y, rect.end.y):
					for x: int in range(rect.position.x, rect.end.x):
						var cell := Vector2i(x, y)
						if not bounds.has_point(cell):
							continue
						room_cells[cell] = true
						var offset := GRID_GEOMETRY.cell_offset(ship_layout, cell) * cell_size
						var local_rect := Rect2(origin + (Vector2(cell - bounds.position) * cell_size) + offset, Vector2(cell_size, cell_size))
						draw_rect(local_rect, color.darkened(0.08), true)
			for segment: Dictionary in GRID_GEOMETRY.boundary_segments(ship_layout, room_cells, bounds, cell_size, origin):
				if replaced_edges.has(GRID_GEOMETRY.exterior_edge_key(segment["cell"], segment["normal"])):
					continue
				draw_line(segment["start"], segment["end"], hull_edge_color, 1.0, true)
	draw_rect(Rect2(origin, grid_pixel), envelope_color, false, 2.0)
	if ship_layout != null:
		for room: Resource in ship_layout.get("rooms"):
			var room_type := String(room.get("type_name"))
			if not GRID_GEOMETRY.has_exterior_profile(room_type):
				continue
			var facing_quarters := GRID_GEOMETRY.exterior_facing_quarters(room)
			var fill_color: Color = Color(room.get("color")).darkened(0.08)
			for exterior_span: Rect2i in GRID_GEOMETRY.exterior_face_spans(room, hull_cells, ship_layout):
				if not bounds.encloses(exterior_span):
					continue
				var offset := GRID_GEOMETRY.cell_offset(ship_layout, exterior_span.position) * cell_size
				var local_rect := Rect2(
					origin + (Vector2(exterior_span.position - bounds.position) * cell_size) + offset,
					Vector2(exterior_span.size) * cell_size
				)
				var polygon := GRID_GEOMETRY.exterior_cell_polygon(local_rect, room_type, facing_quarters)
				var profile := GRID_GEOMETRY.exterior_edge_profile(local_rect, room_type, facing_quarters)
				var aperture := GRID_GEOMETRY.exterior_aperture_polygon(local_rect, room_type, facing_quarters)
				if polygon.size() < 3 or profile.size() < 2:
					continue
				draw_colored_polygon(polygon, fill_color)
				if aperture.size() >= 3:
					draw_colored_polygon(aperture, Color(0.006, 0.025, 0.03, 1.0))
				draw_polyline(profile, hull_edge_color, 1.0, true)
				if room_type == "HANGAR":
					draw_polyline(profile, Color(0.2, 0.92, 0.88, 0.95), 1.0, true)
		# Finish with the same continuous outer stroke used by ordinary hull
		# sections so profile fills cannot create inset shoulders at their joins.
		for segment: Dictionary in GRID_GEOMETRY.boundary_segments(ship_layout, hull_cells, bounds, cell_size, origin):
			if replaced_edges.has(GRID_GEOMETRY.exterior_edge_key(segment["cell"], segment["normal"])):
				continue
			draw_line(segment["start"], segment["end"], hull_edge_color, 1.0, true)
		for room: Resource in ship_layout.get("rooms"):
			var room_type := String(room.get("type_name"))
			if room_type not in ["WEAPONS", "SHIELDS"]:
				continue
			var cells := GRID_GEOMETRY.room_cells(room)
			if cells.is_empty():
				continue
			var center := Vector2.ZERO
			for cell: Vector2i in cells:
				center += origin + (Vector2(cell - bounds.position) + Vector2(0.5, 0.5)) * cell_size
			center /= float(cells.size())
			if room_type == "WEAPONS":
				var weapon: Resource = room.get("weapon_definition")
				var traverse := maxf(float(weapon.get("traverse_degrees")), 8.0) if weapon != null else 8.0
				var family := String(weapon.get("weapon_family")) if weapon != null else "CANNON"
				var weapon_color := Color(weapon.get("visual_color")) if weapon != null else Color(0.95, 0.58, 0.22)
				for quarter: int in GRID_GEOMETRY.weapon_coverage_quarters(ship_layout, room, weapon):
					var direction := Vector2.UP.rotated(float(quarter) * PI * 0.5)
					draw_arc(center, cell_size * 0.68, direction.angle() - deg_to_rad(traverse), direction.angle() + deg_to_rad(traverse), 12, Color(0.35, 1.0, 0.82, 0.88), 1.5, true)
					_draw_preview_weapon_mount(center, direction, family, weapon_color, cell_size)
			else:
				var facing := GRID_GEOMETRY.resolved_module_facing(ship_layout, room)
				var exposed := GRID_GEOMETRY.room_exposed_quarters(ship_layout, room)
				if exposed.has(facing):
					var direction := Vector2.UP.rotated(float(facing) * PI * 0.5)
					draw_arc(center, cell_size * 0.78, direction.angle() - PI * 0.34, direction.angle() + PI * 0.34, 16, Color(0.2, 0.85, 1.0, 0.9), 2.0, true)
	_draw_room_callout()


func _draw_room_callout() -> void:
	if hovered_room == null or callout_alpha <= 0.001 or tooltip_cell_size <= 0.0:
		return
	var room_rect := Rect2()
	var has_rect := false
	for cell: Vector2i in GRID_GEOMETRY.room_cells(hovered_room):
		var cell_rect := GRID_GEOMETRY.cell_rect(ship_layout, cell, tooltip_bounds, tooltip_cell_size, tooltip_origin)
		room_rect = room_rect.merge(cell_rect) if has_rect else cell_rect
		has_rect = true
	if not has_rect:
		return
	var anchor := room_rect.get_center()
	var line_direction := -1.0 if anchor.x <= size.x * 0.5 else 1.0
	var diagonal_length := clampf(tooltip_cell_size * 0.38, 14.0, 24.0)
	var horizontal_length := clampf(size.x * 0.13, 70.0, 108.0)
	var elbow := anchor + Vector2(line_direction * diagonal_length, -diagonal_length)
	var line_end := elbow + Vector2(line_direction * horizontal_length, 0.0)
	var line_color := Color(0.65, 0.94, 0.91, 0.94 * callout_alpha)
	var accent := Color(0.95, 0.72, 0.3, 0.95 * callout_alpha)
	draw_circle(anchor, 3.2, Color(0.01, 0.03, 0.035, callout_alpha), true)
	draw_circle(anchor, 4.2, line_color, false, 1.25, true)
	draw_line(anchor + Vector2(line_direction * 4.0, -4.0), elbow, line_color, 1.25, true)
	draw_line(elbow, line_end, line_color, 1.25, true)
	draw_line(elbow, elbow + Vector2(line_direction * 14.0, 0.0), accent, 2.5, true)
	var room_name := String(hovered_room.get("display_name")).strip_edges().to_upper()
	if room_name.is_empty():
		room_name = String(hovered_room.get("type_name")).replace("_", " ").to_upper()
	var font := get_theme_default_font()
	var font_size := 12
	var text_size := font.get_string_size(room_name, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size)
	var text_position := Vector2(line_end.x + 7.0, line_end.y - 7.0)
	if line_direction < 0.0:
		text_position.x = line_end.x - text_size.x - 7.0
	draw_string(font, text_position + Vector2(1.0, 1.0), room_name, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, Color(0.0, 0.0, 0.0, 0.9 * callout_alpha))
	draw_string(font, text_position, room_name, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, line_color)


func _room_at_position(local_position: Vector2) -> Resource:
	if ship_layout == null or tooltip_cell_size <= 0.0:
		return null
	for room: Resource in ship_layout.get("rooms"):
		for cell: Vector2i in GRID_GEOMETRY.room_cells(room):
			if GRID_GEOMETRY.cell_rect(ship_layout, cell, tooltip_bounds, tooltip_cell_size, tooltip_origin).has_point(local_position):
				return room
	return null


func _room_tooltip(room: Resource) -> String:
	if room == null:
		return ""
	var room_name := String(room.get("display_name")).strip_edges()
	var room_type := String(room.get("type_name")).strip_edges()
	var effect := String(room.get("effect_label")).strip_edges()
	var cell_count := GRID_GEOMETRY.room_cells(room).size()
	var power := SHIP_ANALYZER.room_power_delta(room_type, cell_count, room)
	var lines := PackedStringArray([
		room_name if not room_name.is_empty() else room_type.replace("_", " "),
		"%s GRID • %d CELL%s" % [room_type.replace("_", " "), cell_count, "S" if cell_count != 1 else ""],
	])
	if not effect.is_empty():
		lines.append(effect)
	if power.x > 0.0:
		lines.append("REACTOR FIELD • UNLIMITED LOCAL POWER")
	elif power.y > 0.0:
		var required := maxi(roundi(power.y), 1)
		var supplied := 0.0
		if ship_layout != null:
			var report := SHIP_ANALYZER.power_network_report(ship_layout)
			var room_id: StringName = room.get("room_id")
			required = int((report.get("room_requirements", {}) as Dictionary).get(room_id, required))
			supplied = float((report.get("room_coverage", {}) as Dictionary).get(room_id, 0.0))
		lines.append("POWER LINKS • %s" % POWER_REQUIREMENT_DISPLAY.plain_text(required, supplied))
	var optimal_crew := int(room.get("optimal_crew"))
	var minimum_crew := int(room.get("minimum_crew"))
	var recipe: Resource = room.get("module_recipe")
	if recipe != null:
		minimum_crew = maxi(minimum_crew, int(recipe.get("minimum_crew")))
		optimal_crew = maxi(optimal_crew, int(recipe.get("optimal_crew")))
	optimal_crew = ROOM_STAFFING_RULES.effective_requirements(room, minimum_crew, optimal_crew).y
	if optimal_crew > 0:
		lines.append("BATTLE STATIONS • %d CREW" % optimal_crew)
	return "\n".join(lines)


func _draw_preview_weapon_mount(
	center: Vector2,
	direction: Vector2,
	family: String,
	color: Color,
	cell_size: float
) -> void:
	var side := direction.orthogonal()
	var length := cell_size * 0.5
	var spacing := cell_size * 0.11
	match family:
		"BALLISTIC":
			draw_circle(center, cell_size * 0.14, Color(0.01, 0.04, 0.045), true)
			draw_circle(center, cell_size * 0.14, color, false, 1.5)
			draw_line(center + side * spacing, center + direction * length + side * spacing, color, 2.0, true)
			draw_line(center - side * spacing, center + direction * length - side * spacing, color, 2.0, true)
		"LASER":
			var diamond := PackedVector2Array([
				center - direction * cell_size * 0.15,
				center + side * cell_size * 0.15,
				center + direction * cell_size * 0.15,
				center - side * cell_size * 0.15,
				center - direction * cell_size * 0.15,
			])
			draw_colored_polygon(diamond, Color(color, 0.35))
			draw_polyline(diamond, color, 1.5, true)
			draw_line(center, center + direction * length, color.lightened(0.25), 1.5, true)
		"ENERGY":
			draw_circle(center, cell_size * 0.17, Color(color, 0.25), true)
			draw_circle(center, cell_size * 0.17, color, false, 1.5)
			draw_line(center + side * spacing, center + direction * length, color, 2.0, true)
			draw_line(center - side * spacing, center + direction * length, color, 2.0, true)
		"MISSILE":
			for offset: float in [-spacing, 0.0, spacing]:
				draw_line(center + side * offset, center + direction * length + side * offset, color, 2.0, true)
		_:
			draw_rect(Rect2(center - Vector2.ONE * cell_size * 0.13, Vector2.ONE * cell_size * 0.26), Color(color, 0.4), true)
			draw_line(center, center + direction * cell_size * 0.62, color, 3.0, true)
