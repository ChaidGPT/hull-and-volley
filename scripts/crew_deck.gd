extends Control

const CELL_SIZE := 256
const CANVAS_PADDING := Vector2(320, 320)
const GRID_GEOMETRY := preload("res://scripts/grid_geometry.gd")
const DOOR_VISUALS := preload("res://scripts/door_visuals.gd")
const CREW_ANIMATION_RANGES := {
	"Idle": Vector2i(0, 1),
	"Walk": Vector2i(2, 11),
	"Pistol_idle": Vector2i(24, 25),
	"Die": Vector2i(36, 37),
}
const CREW_FRAME_DURATION_MS := 100

@export var ship_layout: Resource
var combat_overlay: CloseCombatOverlay
var selected_crew_id := 0

@export_category("Grid Indicators")
@export var hull_edge_indicator_color := Color(1.0, 0.58, 0.18, 0.95)
@export_range(2.0, 30.0, 1.0) var hull_edge_indicator_width := 14.0
@export var module_facing_indicator_color := Color(0.2, 0.95, 1.0, 0.95)
@export_range(2.0, 30.0, 1.0) var module_facing_indicator_width := 12.0
@export_range(30.0, 220.0, 5.0) var module_facing_arrow_length := 105.0

@export_category("Status Indicators")
## Crew dot color when a crew member is actively operating a station.
@export var crew_working_color := Color(0.35, 1.0, 0.72, 0.96)
## Crew dot color when a crew member is traveling to an assigned room.
@export var crew_en_route_color := Color(1.0, 0.86, 0.28, 0.96)
## Crew dot color when a crew member is doing damage-control work.
@export var crew_repair_color := Color(1.0, 0.6, 0.2, 0.96)
## Crew dot color when a crew member is evacuating or badly hurt.
@export var crew_danger_color := Color(1.0, 0.22, 0.18, 0.96)
## Crew dot color when a crew member is blocked or waiting.
@export var crew_blocked_color := Color(0.46, 0.52, 0.52, 0.86)

@export_category("Breach Atmosphere Effect")
## Color of atmosphere particles escaping through breached outer hull walls.
@export var breach_jet_color := Color(0.5, 0.9, 1.0, 0.74)
## Number of animated atmosphere motes drawn at each active breach.
@export_range(1, 24, 1) var breach_jet_particles := 10
## Distance in pixels traveled by venting atmosphere in the close Crew view.
@export_range(20.0, 500.0, 5.0) var breach_jet_length := 190.0
## Half-angle of the turbulent atmosphere fan escaping a breach.
@export_range(0.0, 1.2, 0.05) var breach_jet_spread := 0.52


func _ready() -> void:
	if ship_layout == null:
		push_error("CrewDeck requires a ship layout resource.")
		return
	_update_size_from_layout()
	combat_overlay = CloseCombatOverlay.new()
	combat_overlay.name = "CloseCombatOverlay"
	add_child(combat_overlay)
	combat_overlay.configure(self, ship_layout, CANVAS_PADDING, CELL_SIZE)
	queue_redraw()


func _process(_delta: float) -> void:
	if DOOR_VISUALS.is_transitioning(_get_player_structure()):
		queue_redraw()


func get_room_at_local_position(local_position: Vector2) -> Resource:
	for room: Resource in _rooms():
		for cell_value: Variant in _room_cells(room).keys():
			if _get_grid_rect(Rect2i(cell_value, Vector2i.ONE)).has_point(local_position):
				return room
	return null


func _draw() -> void:
	var grid_size := Vector2(_columns() * CELL_SIZE, _rows() * CELL_SIZE)
	var hull_cells := _all_occupied_cells()
	var drawing_zoom := maxf(absf(scale.x), 0.01)
	var room_font_size := maxi(8, int(round(30.0 / drawing_zoom)))
	var weapon_font_size := maxi(7, int(round(20.0 / drawing_zoom)))
	var orientation_font_size := maxi(7, int(round(24.0 / drawing_zoom)))

	draw_rect(Rect2(Vector2.ZERO, size), Color(0.012, 0.015, 0.018), true)
	for hull_cell_value: Variant in hull_cells.keys():
		var hull_cell: Vector2i = hull_cell_value
		draw_rect(_get_grid_rect(Rect2i(hull_cell, Vector2i.ONE)), Color(0.04, 0.055, 0.06), true)

	for room: Resource in _rooms():
		for cell_value: Variant in _room_cells(room).keys():
			var cell: Vector2i = cell_value
			draw_rect(_get_grid_rect(Rect2i(cell, Vector2i.ONE)), room.get("color"), true)

	for room: Resource in _rooms():
		_draw_room_boundary(room, Color(0.55, 0.64, 0.62, 0.72), 10.0, hull_cells)
		if String(room.get("type_name")) == "HANGAR":
			_draw_docked_fighters(room)
		if String(room.get("type_name")) == "WEAPONS":
			_draw_weapon_operation(room, hull_cells)
	_draw_profiled_hull_boundary(hull_cells, Color(0.32, 0.4, 0.42), 18.0)
	_draw_special_exterior_profiles(hull_cells, Color(0.32, 0.4, 0.42), 18.0)
	_draw_profiled_hull_boundary(hull_cells, Color(0.32, 0.4, 0.42), 18.0)
	_draw_hull_edge_indicators(hull_cells)
	for room: Resource in _rooms():
		var type_name := String(room.get("type_name"))
		if type_name != "PROPULSION" and (type_name in ["WEAPONS", "HANGAR", "DOCKING"] or room.get("module_recipe") != null):
			_draw_module_facing_indicator(room, hull_cells)

	_draw_simulated_doors()

	for room: Resource in _rooms():
		var grid_label: String = room.get("grid_label")
		var room_rects := _room_rects(room)
		if room_rects.is_empty():
			continue
		if not grid_label.is_empty():
			for cells: Rect2i in room_rects:
				_draw_centered_label(_get_grid_rect(cells), grid_label, weapon_font_size)
		else:
			_draw_centered_label(
				_get_grid_rect(_largest_rect(room_rects)),
				room.get("display_name"),
				room_font_size
			)

	_draw_pressure_and_structural_damage()
	_draw_work_slots_and_crew()


func _draw_work_slots_and_crew() -> void:
	var crew := get_tree().get_first_node_in_group("crew_simulation")
	if not is_instance_valid(crew) or crew.crew_definition == null:
		return
	for slot: Dictionary in crew.work_slots:
		var point := _logical_to_canvas(slot["position"])
		draw_circle(point, 8.0, Color(0.55, 0.78, 0.72, 0.24), false, 2.0)
	for member: Dictionary in crew.crew_members:
		if bool(member.get("ejected", false)) or int(member.get("carried_by", 0)) > 0:
			continue
		var point := _logical_to_canvas(member["position"])
		var base_color: Color = crew.crew_definition.get("base_color")
		var dot_color := _crew_state_color(member, base_color).lightened(float(member["color_shift"]) * 0.35)
		var radius := float(crew.crew_definition.get("dot_radius"))
		var outline_width := float(crew.crew_definition.get("outline_width"))
		var is_selected := int(member["id"]) == selected_crew_id
		var has_sprite := crew.crew_definition.get("sprite_sheet") != null
		if not has_sprite:
			draw_circle(point, radius + outline_width + 3.0, Color(0.015, 0.025, 0.03, 0.95))
			draw_circle(point, radius + outline_width * 0.55, _crew_state_ring_color(member, dot_color), false, maxf(outline_width, 2.0))
		var heading: Vector2 = member.get("facing_direction", Vector2.UP)
		if not _draw_crew_sprite(member, point, heading, crew.crew_definition):
			draw_circle(point, radius, dot_color)
		if is_selected:
			draw_arc(point, radius + 12.0, 0.0, TAU, 24, crew.crew_definition.get("selection_color"), 5.0, true)
	var captain: Dictionary = crew.get("captain_member")
	if not captain.is_empty():
		var captain_point := _logical_to_canvas(captain.get("position", Vector2.ZERO))
		var captain_heading: Vector2 = captain.get("facing_direction", Vector2.UP)
		var captain_color := Color(0.16, 0.78, 1.0, 0.95)
		draw_arc(captain_point, 12.0, 0.0, TAU, 20, captain_color, 3.0, true)
		draw_line(captain_point + Vector2(-9.0, 13.0), captain_point + Vector2(0.0, 18.0), captain_color, 3.0, true)
		draw_line(captain_point + Vector2(0.0, 18.0), captain_point + Vector2(9.0, 13.0), captain_color, 3.0, true)
		_draw_crew_sprite(captain, captain_point, captain_heading, crew.crew_definition)
	for job: Dictionary in crew.damage_control_jobs:
		var target: Dictionary = job["target"]
		var point := _logical_to_canvas(target["position"])
		var color := Color(1.0, 0.58, 0.18, 0.95) if String(job["state"]) != "REPAIRING" else Color(0.28, 1.0, 0.72, 0.95)
		draw_circle(point, 24.0, Color(0.02, 0.035, 0.04, 0.9))
		draw_line(point + Vector2(-12, -12), point + Vector2(12, 12), color, 6.0, true)
		draw_line(point + Vector2(12, -12), point + Vector2(-12, 12), color, 6.0, true)
		draw_arc(point, 34.0, -PI * 0.5, -PI * 0.5 + TAU * float(job["progress"]), 24, color, 5.0, true)


func _draw_crew_sprite(member: Dictionary, point: Vector2, heading: Vector2, definition: Resource) -> bool:
	var sprite_sheet: Texture2D = definition.get("sprite_sheet")
	if sprite_sheet == null:
		return false
	var frame_size: Vector2i = definition.get("sprite_frame_size")
	if frame_size.x <= 0 or frame_size.y <= 0:
		return false
	var animation_name := _crew_animation_name(member)
	var frame_range: Vector2i = CREW_ANIMATION_RANGES.get(animation_name, CREW_ANIMATION_RANGES["Idle"])
	var frame_count := frame_range.y - frame_range.x + 1
	var phase_ms := int(member.get("id", 0)) * 37
	var frame_offset := int((Time.get_ticks_msec() + phase_ms) / CREW_FRAME_DURATION_MS) % frame_count
	if animation_name == "Die":
		frame_offset = mini(int(float(member.get("incapacitated_seconds", 0.0)) * 1000.0 / CREW_FRAME_DURATION_MS), frame_count - 1)
	var frame_index := frame_range.x + frame_offset
	var source_rect := Rect2(Vector2(frame_index * frame_size.x, 0), Vector2(frame_size))
	var draw_size := Vector2(frame_size) * float(definition.get("sprite_scale"))
	# The Aseprite character is authored facing up (-Y). Vector2.angle()
	# measures from right (+X), so rotate the sheet's forward axis by 90 degrees
	# before aligning it with the crew member's travel heading.
	var rotation := heading.angle() + PI * 0.5 if not heading.is_zero_approx() else 0.0
	draw_set_transform(point, rotation)
	draw_texture_rect_region(sprite_sheet, Rect2(-draw_size * 0.5, draw_size), source_rect)
	draw_set_transform(Vector2.ZERO, 0.0)
	return true


func _crew_animation_name(member: Dictionary) -> String:
	var state := String(member.get("state", ""))
	if bool(member.get("incapacitated", false)) or bool(member.get("dead", false)):
		return "Die"
	if state == "MOVING":
		return "Walk"
	var is_repairing := int(member.get("active_job_id", 0)) > 0 and bool(member.get("at_job", false))
	var is_working := bool(member.get("at_assignment", false)) or state in ["WORKING", "MANNING"]
	if is_repairing or is_working:
		return "Pistol_idle"
	return "Idle"


func _crew_state_color(member: Dictionary, base_color: Color) -> Color:
	var state := String(member.get("state", ""))
	if bool(member.get("evacuating", false)) or float(member.get("health", 100.0)) <= 25.0:
		return crew_danger_color
	if int(member.get("active_job_id", 0)) > 0:
		return crew_repair_color
	if state.contains("WAIT"):
		return crew_blocked_color
	var assigned_room_id: StringName = member.get("assigned_room_id", &"")
	if not bool(member.get("at_assignment", false)) and assigned_room_id != &"":
		return crew_en_route_color
	if bool(member.get("at_assignment", false)):
		return crew_working_color
	return base_color


func _crew_state_ring_color(member: Dictionary, dot_color: Color) -> Color:
	if bool(member.get("evacuating", false)) or float(member.get("health", 100.0)) <= 25.0:
		return Color(1.0, 0.1, 0.08, 0.95)
	if int(member.get("active_job_id", 0)) > 0:
		return Color(1.0, 0.58, 0.18, 0.92)
	var assigned_room_id: StringName = member.get("assigned_room_id", &"")
	if not bool(member.get("at_assignment", false)) and assigned_room_id != &"":
		return Color(1.0, 0.82, 0.22, 0.88)
	return Color(dot_color, 0.72)


func _logical_to_canvas(logical_position: Vector2) -> Vector2:
	return CANVAS_PADDING + (logical_position - Vector2(_bounds().position)) * CELL_SIZE


func _cell_logical_center(cell: Vector2i) -> Vector2:
	return GRID_GEOMETRY.logical_cell_rect(cell, GRID_GEOMETRY.cell_offset(ship_layout, cell)).get_center()


func get_crew_at_local_position(local_position: Vector2) -> int:
	var crew := get_tree().get_first_node_in_group("crew_simulation")
	if not is_instance_valid(crew) or crew.crew_definition == null:
		return 0
	var pick_radius := float(crew.crew_definition.get("dot_radius")) + 14.0
	var closest_id := 0
	var closest_distance := pick_radius
	for member: Dictionary in crew.crew_members:
		var distance := local_position.distance_to(_logical_to_canvas(member["position"]))
		if distance < closest_distance:
			closest_distance = distance
			closest_id = int(member["id"])
	return closest_id


func set_selected_crew(crew_id: int) -> void:
	selected_crew_id = crew_id
	queue_redraw()


func get_crew_canvas_position(crew_id: int) -> Vector2:
	var crew := get_tree().get_first_node_in_group("crew_simulation")
	if not is_instance_valid(crew):
		return Vector2.ZERO
	var member: Dictionary = crew.call("get_member", crew_id)
	return _logical_to_canvas(member["position"]) if not member.is_empty() else Vector2.ZERO


func _draw_pressure_and_structural_damage() -> void:
	var combat := get_tree().get_first_node_in_group("combat_simulation")
	if not is_instance_valid(combat):
		return
	var structure: ShipStructuralState = combat.call("get_structural_state", 0, 0)
	if structure == null or structure.material == null:
		return
	for cell_value: Variant in structure.cell_pressure.keys():
		var cell: Vector2i = cell_value
		var pressure := structure.get_cell_pressure(cell)
		if pressure < 0.99:
			var cell_rect := _get_grid_rect(Rect2i(cell, Vector2i.ONE)).grow(-10.0)
			draw_rect(cell_rect, Color(0.025, 0.16, 0.24, (1.0 - pressure) * 0.56), true)
			if pressure < 0.12:
				draw_string(ThemeDB.fallback_font, cell_rect.get_center() + Vector2(-72.0, 8.0), "VACUUM", HORIZONTAL_ALIGNMENT_CENTER, 144.0, 22, Color(0.45, 0.9, 1.0, 0.8))
	var bounds := _bounds()
	for wall_value: Variant in structure.walls.values():
		var wall: Dictionary = wall_value
		var start := CANVAS_PADDING + (Vector2(wall["start"]) - Vector2(bounds.position)) * CELL_SIZE
		var finish := CANVAS_PADDING + (Vector2(wall["end"]) - Vector2(bounds.position)) * CELL_SIZE
		if bool(wall["breached"]):
			draw_line(start, finish, Color(0.008, 0.012, 0.015), 24.0, false)
			draw_circle(start, 10.0, structure.material.get("breach_marker_color"))
			draw_circle(finish, 10.0, structure.material.get("breach_marker_color"))
			if bool(wall["outer"]):
				_draw_breach_atmosphere_jet(wall, start, finish, structure)
		else:
			var health: float = float(wall["current"]) / maxf(float(wall["maximum"]), 0.001)
			if health < 0.999:
				var color: Color = structure.material.get("damaged_wall_color").lerp(structure.material.get("healthy_wall_color"), health)
				draw_line(start, finish, color, 18.0, false)


func _draw_breach_atmosphere_jet(wall: Dictionary, start: Vector2, finish: Vector2, structure: ShipStructuralState) -> void:
	var cells: Array = wall["cells"]
	if cells.is_empty():
		return
	var pressure := structure.get_cell_pressure(cells[0])
	if pressure <= 0.01:
		return
	var mouth := start.lerp(finish, 0.5)
	var cell_center := _get_grid_rect(Rect2i(cells[0], Vector2i.ONE)).get_center()
	var outward := cell_center.direction_to(mouth)
	var phase := Time.get_ticks_msec() * 0.001
	for index: int in range(breach_jet_particles):
		var speed := 0.6 + fposmod(sin(float(index) * 41.73) * 9182.31, 1.0) * 0.9
		var progress := fposmod(phase * speed + float(index) / breach_jet_particles, 1.0)
		var spread_seed := sin(float(index) * 12.9898 + 4.21)
		var particle_direction := outward.rotated(spread_seed * breach_jet_spread)
		var tangent := particle_direction.orthogonal()
		var curl := sin(phase * (3.5 + speed) + index * 2.37) * breach_jet_length * 0.14 * progress * progress
		var travel := breach_jet_length * progress * (0.68 + speed * 0.3)
		var point := mouth + particle_direction * travel + tangent * curl
		var alpha := breach_jet_color.a * pressure * (1.0 - progress) * (0.52 + speed * 0.32)
		var color := Color(breach_jet_color, alpha)
		var streak := particle_direction * (10.0 + speed * 15.0) * (1.0 - progress)
		draw_line(point - streak, point, color, maxf(2.0, 5.5 - progress * 2.5), true)
		if index % 3 == 0:
			draw_circle(point, 7.5 - progress * 4.0, color)


func _draw_docked_fighters(room: Resource) -> void:
	var combat := get_tree().get_first_node_in_group("combat_simulation")
	if not is_instance_valid(combat):
		return
	var craft: Array[Dictionary] = combat.call("get_hangar_craft", 0, 0, room.get("room_id"), true)
	var center := _room_visual_bounds(room).get_center()
	var offsets := [Vector2(-52.0, -52.0), Vector2(52.0, -52.0), Vector2(-52.0, 52.0), Vector2(52.0, 52.0)]
	for index: int in range(mini(craft.size(), offsets.size())):
		var point: Vector2 = center + offsets[index]
		draw_colored_polygon(PackedVector2Array([point + Vector2(0, -34), point + Vector2(27, 28), point, point + Vector2(-27, 28)]), Color(0.72, 0.94, 0.92, 0.95))
		draw_polyline(PackedVector2Array([point + Vector2(0, -34), point + Vector2(27, 28), point, point + Vector2(-27, 28), point + Vector2(0, -34)]), Color(0.15, 0.45, 0.48), 5.0)


func _draw_weapon_operation(room: Resource, hull_cells: Dictionary) -> void:
	var combat := get_tree().get_first_node_in_group("combat_simulation")
	if not is_instance_valid(combat):
		return
	var state: Dictionary = combat.call("get_weapon_operation_state", 0, 0, room.get("room_id"))
	var center := _room_visual_bounds(room).get_center()
	var direction := _module_facing_direction(room, _room_cells(room), hull_cells)
	if String(state["state"]) == "FIRING":
		var muzzle := center + direction * 105.0
		draw_colored_polygon(PackedVector2Array([muzzle, muzzle + direction.rotated(-0.35) * 95.0, muzzle + direction * 145.0, muzzle + direction.rotated(0.35) * 95.0]), Color(1.0, 0.75, 0.2, 0.95))
	elif String(state["state"]) == "RELOADING":
		var total := maxf(float(state["reload_total"]), 0.001)
		var progress := 1.0 - float(state["reload_remaining"]) / total
		draw_arc(center, 68.0, -PI * 0.5, -PI * 0.5 + TAU * progress, 24, Color(0.95, 0.58, 0.22, 0.9), 10.0)


func _room_visual_bounds(room: Resource) -> Rect2:
	var result := Rect2()
	var first := true
	for rect: Rect2i in _room_rects(room):
		var pixel_rect := _get_grid_rect(rect)
		result = pixel_rect if first else result.merge(pixel_rect)
		first = false
	return result


func _draw_centered_label(room_rect: Rect2, text: String, font_size: int) -> void:
	var baseline_y := room_rect.position.y + room_rect.size.y * 0.5 + font_size * 0.35
	draw_string(
		ThemeDB.fallback_font,
		Vector2(room_rect.position.x + 24.0, baseline_y),
		text,
		HORIZONTAL_ALIGNMENT_CENTER,
		room_rect.size.x - 48.0,
		font_size,
		Color(0.78, 0.84, 0.8)
	)


func _draw_weapon_mount(room: Resource, cells: Rect2i, room_rect: Rect2) -> void:
	var direction := Vector2.UP
	var bounds := _bounds()
	if cells.position.y == bounds.position.y:
		direction = Vector2.UP
	elif cells.position.x == bounds.position.x:
		direction = Vector2.LEFT
	elif cells.position.x == bounds.end.x - 1:
		direction = Vector2.RIGHT
	var weapon: Resource = room.get("weapon_definition")
	var traverse := 0.0
	var weapon_color := Color(0.86, 0.58, 0.25)
	var family := "CANNON"
	if weapon != null:
		traverse = weapon.get("traverse_degrees")
		weapon_color = weapon.get("visual_color")
		family = String(weapon.get("weapon_family"))

	var turret_center := room_rect.get_center()
	draw_circle(turret_center, 42.0, Color(0.16, 0.19, 0.2), true)
	draw_circle(turret_center, 42.0, weapon_color, false, 8.0)
	var side := direction.orthogonal()
	match family:
		"BALLISTIC":
			for offset: float in [-15.0, 15.0]:
				draw_line(turret_center + side * offset, turret_center + direction * 92.0 + side * offset, weapon_color, 14.0)
				draw_line(turret_center + side * offset, turret_center + direction * 92.0 + side * offset, Color(0.08, 0.1, 0.1), 5.0)
		"LASER":
			var emitter := PackedVector2Array([
				turret_center - direction * 36.0,
				turret_center + side * 36.0,
				turret_center + direction * 36.0,
				turret_center - side * 36.0,
			])
			draw_colored_polygon(emitter, Color(weapon_color, 0.32))
			draw_polyline(emitter + PackedVector2Array([emitter[0]]), weapon_color, 7.0)
			draw_line(turret_center + direction * 22.0, turret_center + direction * 118.0, weapon_color.lightened(0.25), 11.0)
		"ENERGY":
			draw_circle(turret_center, 25.0, Color(weapon_color, 0.3), true)
			draw_circle(turret_center, 18.0, weapon_color.lightened(0.3), false, 7.0)
			draw_line(turret_center + side * 24.0, turret_center + direction * 100.0 + side * 11.0, weapon_color, 13.0)
			draw_line(turret_center - side * 24.0, turret_center + direction * 100.0 - side * 11.0, weapon_color, 13.0)
		"MISSILE":
			for offset: float in [-25.0, 0.0, 25.0]:
				var tube := turret_center + side * offset
				draw_line(tube - direction * 22.0, tube + direction * 76.0, weapon_color, 17.0)
				draw_circle(tube + direction * 76.0, 8.0, weapon_color.lightened(0.3), true)
		_:
			var barrel_start := turret_center + direction * 34.0
			var barrel_end := turret_center + direction * (88.0 if traverse > 0.0 else 132.0)
			draw_line(barrel_start, barrel_end, weapon_color, 18.0)
			draw_line(barrel_start, barrel_end, Color(0.18, 0.14, 0.1), 8.0)
	if traverse > 0.0:
		var facing_angle := direction.angle()
		draw_arc(turret_center, 78.0, facing_angle - deg_to_rad(traverse), facing_angle + deg_to_rad(traverse), 24, Color(weapon_color, 0.55), 5.0)


func _draw_simulated_doors() -> void:
	var structure := _get_player_structure()
	if structure == null or structure.door_definition == null:
		return
	var bounds := _bounds()
	for door_value: Variant in structure.doors.values():
		var door: Dictionary = door_value
		var start := CANVAS_PADDING + (Vector2(door["start"]) - Vector2(bounds.position)) * CELL_SIZE
		var finish := CANVAS_PADDING + (Vector2(door["end"]) - Vector2(bounds.position)) * CELL_SIZE
		DOOR_VISUALS.draw_door(
			self,
			start,
			finish,
			float(door["openness"]),
			bool(door["locked"]) or bool(door["pressure_interlocked"])
		)


func _get_player_structure() -> ShipStructuralState:
	var combat := get_tree().get_first_node_in_group("combat_simulation")
	return combat.call("get_structural_state", 0, 0) if is_instance_valid(combat) else null


func get_door_at_local_position(local_position: Vector2) -> String:
	var structure := _get_player_structure()
	if structure == null:
		return ""
	var bounds := _bounds()
	var closest_id := ""
	var closest_distance := 28.0
	for door_value: Variant in structure.doors.values():
		var door: Dictionary = door_value
		var start := CANVAS_PADDING + (Vector2(door["start"]) - Vector2(bounds.position)) * CELL_SIZE
		var finish := CANVAS_PADDING + (Vector2(door["end"]) - Vector2(bounds.position)) * CELL_SIZE
		var distance := local_position.distance_to(Geometry2D.get_closest_point_to_segment(local_position, start, finish))
		if distance < closest_distance:
			closest_distance = distance
			closest_id = String(door["id"])
	return closest_id


func _largest_rect(rects: Array[Rect2i]) -> Rect2i:
	var largest := rects[0]
	for candidate: Rect2i in rects:
		if candidate.get_area() > largest.get_area():
			largest = candidate
	return largest


func _room_cells(room: Resource) -> Dictionary:
	var occupied_cells: Dictionary = {}
	for grid_rect: Rect2i in _room_rects(room):
		for y: int in range(grid_rect.position.y, grid_rect.end.y):
			for x: int in range(grid_rect.position.x, grid_rect.end.x):
				occupied_cells[Vector2i(x, y)] = true
	return occupied_cells


func _all_occupied_cells() -> Dictionary:
	var occupied_cells: Dictionary = {}
	for room: Resource in _rooms():
		occupied_cells.merge(_room_cells(room), true)
	return occupied_cells


func _draw_room_boundary(room: Resource, color: Color, width: float, hull_cells: Dictionary = {}) -> void:
	var hull := hull_cells if not hull_cells.is_empty() else _all_occupied_cells()
	var replaced := GRID_GEOMETRY.exterior_replaced_edge_keys(_rooms(), hull, ship_layout)
	for segment: Dictionary in GRID_GEOMETRY.boundary_segments(ship_layout, _room_cells(room), _bounds(), CELL_SIZE, CANVAS_PADDING):
		if replaced.has(GRID_GEOMETRY.exterior_edge_key(segment["cell"], segment["normal"])):
			continue
		draw_line(segment["start"], segment["end"], color, width)
	if GRID_GEOMETRY.has_exterior_profile(String(room.get("type_name"))):
		var facing := GRID_GEOMETRY.exterior_facing_quarters(room)
		for exterior_span: Rect2i in GRID_GEOMETRY.exterior_face_spans(room, hull, ship_layout):
			var profile := GRID_GEOMETRY.exterior_edge_profile(_get_grid_rect(exterior_span), String(room.get("type_name")), facing)
			if profile.size() >= 2:
				draw_polyline(profile, color, width, false)


func _draw_cell_set_boundary(occupied_cells: Dictionary, color: Color, width: float) -> void:
	for segment: Dictionary in GRID_GEOMETRY.boundary_segments(ship_layout, occupied_cells, _bounds(), CELL_SIZE, CANVAS_PADDING):
		draw_line(segment["start"], segment["end"], color, width)


func _draw_profiled_hull_boundary(hull_cells: Dictionary, color: Color, width: float) -> void:
	var replaced := GRID_GEOMETRY.exterior_replaced_edge_keys(_rooms(), hull_cells, ship_layout)
	for segment: Dictionary in GRID_GEOMETRY.boundary_segments(ship_layout, hull_cells, _bounds(), CELL_SIZE, CANVAS_PADDING):
		if replaced.has(GRID_GEOMETRY.exterior_edge_key(segment["cell"], segment["normal"])):
			continue
		draw_line(segment["start"], segment["end"], color, width)


func _draw_special_exterior_profiles(hull_cells: Dictionary, outline_color: Color, outline_width: float) -> void:
	for room: Resource in _rooms():
		var room_type := String(room.get("type_name"))
		if not GRID_GEOMETRY.has_exterior_profile(room_type):
			continue
		var facing_quarters := GRID_GEOMETRY.exterior_facing_quarters(room)
		var fill_color: Color = room.get("color")
		for exterior_span: Rect2i in GRID_GEOMETRY.exterior_face_spans(room, hull_cells, ship_layout):
			var rect := _get_grid_rect(exterior_span)
			var polygon := GRID_GEOMETRY.exterior_cell_polygon(rect, room_type, facing_quarters)
			var profile := GRID_GEOMETRY.exterior_edge_profile(rect, room_type, facing_quarters)
			var aperture := GRID_GEOMETRY.exterior_aperture_polygon(rect, room_type, facing_quarters)
			if polygon.size() < 3 or profile.size() < 2:
				continue
			draw_colored_polygon(polygon, fill_color)
			if aperture.size() >= 3:
				draw_colored_polygon(aperture, Color(0.006, 0.025, 0.03, 1.0))
			draw_polyline(profile, outline_color, outline_width, false)
			if room_type == "HANGAR":
				draw_polyline(profile, Color(0.2, 0.92, 0.88, 0.95), maxf(outline_width * 0.42, 1.0), false)


func _draw_hull_edge_indicators(hull_cells: Dictionary) -> void:
	for segment: Dictionary in GRID_GEOMETRY.boundary_segments(ship_layout, hull_cells, _bounds(), CELL_SIZE, CANVAS_PADDING):
		_draw_hull_edge_segment(segment["start"], segment["end"], -Vector2(segment["normal"]))


func _draw_hull_edge_segment(start: Vector2, finish: Vector2, inward: Vector2) -> void:
	draw_line(start, finish, hull_edge_indicator_color, hull_edge_indicator_width, true)
	var midpoint := start.lerp(finish, 0.5)
	draw_line(midpoint, midpoint + inward * 34.0, hull_edge_indicator_color, maxf(hull_edge_indicator_width - 3.0, 2.0), true)


func _draw_module_facing_indicator(room: Resource, hull_cells: Dictionary) -> void:
	var room_cells := _room_cells(room)
	if room_cells.is_empty():
		return
	var direction := _module_facing_direction(room, room_cells, hull_cells)
	var center := Vector2.ZERO
	for cell_value: Variant in room_cells.keys():
		center += _get_grid_rect(Rect2i(cell_value, Vector2i.ONE)).get_center()
	center /= float(room_cells.size())
	var arrow_tip := center + direction * module_facing_arrow_length * 0.68
	var arrow_start := center - direction * module_facing_arrow_length * 0.28
	draw_circle(center, 22.0, Color(0.03, 0.08, 0.09, 0.9), true)
	draw_line(arrow_start, arrow_tip, module_facing_indicator_color, module_facing_indicator_width, true)
	var side := direction.orthogonal()
	var arrow_back := arrow_tip - direction * 38.0
	draw_line(arrow_tip, arrow_back + side * 26.0, module_facing_indicator_color, module_facing_indicator_width, true)
	draw_line(arrow_tip, arrow_back - side * 26.0, module_facing_indicator_color, module_facing_indicator_width, true)

func _module_facing_direction(room: Resource, room_cells: Dictionary, hull_cells: Dictionary) -> Vector2:
	var explicit_facing := int(room.get("module_facing_quarters"))
	if explicit_facing >= 0:
		return Vector2.UP.rotated(float(explicit_facing) * PI * 0.5)
	var hull_bounds := _bounds()
	var hull_center := Vector2(hull_bounds.position) + GRID_GEOMETRY.grid_pixel_size(ship_layout, hull_bounds, 1.0) * 0.5
	var module_center := Vector2.ZERO
	for cell_value: Variant in room_cells.keys():
		var module_cell := cell_value as Vector2i
		module_center += GRID_GEOMETRY.logical_cell_rect(module_cell, GRID_GEOMETRY.cell_offset(ship_layout, module_cell)).get_center()
	module_center /= float(room_cells.size())
	var outward_bias := (module_center - hull_center).normalized()
	var best_direction := Vector2i.UP
	var best_score := -INF
	for direction: Vector2i in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
		var exposed_count := 0
		for cell_value: Variant in room_cells.keys():
			var exposed_cell := cell_value as Vector2i
			if GRID_GEOMETRY.face_contact_strength(ship_layout, exposed_cell, direction, hull_cells) < 0.999:
				exposed_count += 1
		var score := float(exposed_count) * 100.0 + Vector2(direction).dot(outward_bias)
		if score > best_score:
			best_score = score
			best_direction = direction
	return Vector2(best_direction)


func _get_grid_rect(cells: Rect2i) -> Rect2:
	var rect := GRID_GEOMETRY.cell_rect(ship_layout, cells.position, _bounds(), CELL_SIZE, CANVAS_PADDING)
	rect.size = Vector2(cells.size) * CELL_SIZE
	return rect


func _update_size_from_layout() -> void:
	var grid_size := GRID_GEOMETRY.grid_pixel_size(ship_layout, _bounds(), CELL_SIZE)
	custom_minimum_size = CANVAS_PADDING * 2.0 + grid_size
	size = custom_minimum_size


func _bounds() -> Rect2i:
	return ship_layout.call("get_occupied_bounds")


func _rooms() -> Array:
	return ship_layout.get("rooms")


func _room_rects(room: Resource) -> Array[Rect2i]:
	return room.get("grid_rects")


func _columns() -> int:
	return _bounds().size.x


func _rows() -> int:
	return _bounds().size.y
