extends Control

const GRID_GEOMETRY := preload("res://scripts/grid_geometry.gd")

@export_category("Shield Impact Style")
## Bright color used for the small ring that flashes at the exact point of impact.
@export var impact_color := Color(0.38, 0.94, 1.0, 1.0)
## Color of the energy wave as it travels across the ship's shield surface.
@export var wave_color := Color(0.18, 0.7, 0.84, 0.85)
## Total time, in seconds, that one shield impact remains visible.
@export_range(0.1, 2.0, 0.05) var impact_lifetime := 0.75
## How quickly the ripple travels away from the impact point, measured in tactical pixels per second.
@export_range(10.0, 300.0, 5.0) var wave_speed := 115.0
## Thickness of the traveling wave band. Larger values illuminate more of the shield at once.
@export_range(2.0, 30.0, 1.0) var wave_band_width := 10.0
## Width of the crisp line drawn along the hull while the shield wave passes it.
@export_range(1.0, 8.0, 0.5) var wave_line_width := 3.0
## Starting radius of the circular flash shown at the projectile's impact point.
@export_range(2.0, 16.0, 1.0) var impact_marker_radius := 6.0
## Visual distance between the physical hull and a shielded projectile impact. This does not change collision geometry.
@export_range(0.0, 12.0, 0.5) var impact_standoff := 5.0
## Distance the standing shield field floats beyond the physical hull.
@export_range(1.0, 12.0, 0.5) var field_standoff := 4.0
## How deeply each directional bank bows away from the protected hull side.
@export_range(0.05, 0.4, 0.01) var field_curve_depth_ratio := 0.18
## Distance each projected bank reaches beyond the first and last protected hull edge.
@export_range(0.0, 20.0, 0.5) var field_endpoint_extension := 6.0
## Width of the persistent directional field line.
@export_range(1.0, 6.0, 0.5) var field_line_width := 2.0

var shield_ratio := 0.0
var shield_active := false
var ship_layout: Resource
var grid_origin := Vector2.ZERO
var cell_size := 20.0
var active_impacts: Array[Dictionary] = []
var bank_report: Dictionary = {}
var bank_visual_signature := 0


func _ready() -> void:
	set_process(false)


func _process(delta: float) -> void:
	for index: int in range(active_impacts.size() - 1, -1, -1):
		active_impacts[index]["age"] = float(active_impacts[index]["age"]) + delta
		if float(active_impacts[index]["age"]) >= impact_lifetime:
			active_impacts.remove_at(index)
	set_process(not active_impacts.is_empty())
	queue_redraw()


func set_hull_geometry(layout: Resource, origin: Vector2, new_cell_size: float) -> void:
	if ship_layout == layout and grid_origin == origin and is_equal_approx(cell_size, new_cell_size):
		return
	ship_layout = layout
	grid_origin = origin
	cell_size = new_cell_size
	queue_redraw()


func set_shield_state(current_shield: float, maximum_shield: float, is_active: bool) -> void:
	var next_active := is_active and maximum_shield > 0.0 and current_shield > 0.0
	var next_ratio := clampf(current_shield / maximum_shield, 0.0, 1.0) if maximum_shield > 0.0 else 0.0
	if shield_active == next_active and is_equal_approx(shield_ratio, next_ratio):
		return
	shield_active = next_active
	shield_ratio = next_ratio
	bank_report.clear()
	for bank: int in range(4):
		bank_report[bank] = {
			"current": current_shield,
			"maximum": maximum_shield,
			"ratio": next_ratio,
			"online": next_active,
		}
	queue_redraw()


func set_shield_banks(report: Dictionary, is_active: bool = true) -> void:
	var total_current := 0.0
	var total_maximum := 0.0
	for bank_value: Variant in report.values():
		var bank: Dictionary = bank_value
		total_current += float(bank.get("current", 0.0))
		total_maximum += float(bank.get("maximum", 0.0))
	var next_active := is_active and total_current > 0.0 and total_maximum > 0.0
	var next_ratio := clampf(total_current / total_maximum, 0.0, 1.0) if total_maximum > 0.0 else 0.0
	var next_signature := hash(next_active)
	for bank: int in range(4):
		var data: Dictionary = report.get(bank, {})
		next_signature = hash([
			next_signature,
			float(data.get("maximum", 0.0)) > 0.0,
			bool(data.get("online", false)),
			roundi(float(data.get("ratio", 0.0)) * 100.0),
		])
	if next_signature == bank_visual_signature:
		return
	bank_visual_signature = next_signature
	bank_report = report.duplicate(true)
	shield_active = next_active
	shield_ratio = next_ratio
	queue_redraw()


func show_impact(local_point: Vector2, local_normal: Vector2, strength: float = 1.0) -> void:
	if not shield_active:
		return
	active_impacts.append({
		"point": local_point,
		"normal": local_normal.normalized(),
		"strength": clampf(strength, 0.25, 1.0),
		"age": 0.0,
	})
	set_process(true)
	queue_redraw()


func _draw() -> void:
	if not shield_active or ship_layout == null:
		return

	var hull_cells := _all_occupied_cells()
	_draw_standing_fields(hull_cells)
	for impact: Dictionary in active_impacts:
		_draw_impact_wave(hull_cells, impact)


func _draw_standing_fields(hull_cells: Dictionary) -> void:
	for bank: int in range(4):
		var data: Dictionary = bank_report.get(bank, {})
		var maximum := float(data.get("maximum", 0.0))
		var current := float(data.get("current", 0.0))
		var online := bool(data.get("online", false))
		if not online or maximum <= 0.0 or current <= 0.0:
			continue
		var arc_points := _shield_arc_points(hull_cells, bank)
		if arc_points.size() < 2:
			continue
		var ratio := clampf(float(data.get("ratio", current / maximum)), 0.0, 1.0)
		var field_color := wave_color.lerp(impact_color, 0.3 + ratio * 0.35)
		field_color.a = 0.24 + ratio * 0.48
		draw_polyline(arc_points, Color(field_color, field_color.a * 0.2), field_line_width + 4.0, false)
		draw_polyline(arc_points, field_color, field_line_width, false)


func _shield_arc_points(hull_cells: Dictionary, bank: int) -> PackedVector2Array:
	var normal := _normal_for_bank(bank)
	var tangent := Vector2(-normal.y, normal.x)
	var tangent_min := INF
	var tangent_max := -INF
	var outer_projection := -INF
	var found_side := false
	var bounds: Rect2i = ship_layout.call("get_occupied_bounds")
	for segment: Dictionary in GRID_GEOMETRY.boundary_segments(ship_layout, hull_cells, bounds, cell_size, grid_origin):
		var segment_normal: Vector2 = segment.get("normal", Vector2.ZERO)
		if _bank_for_normal(segment_normal) != bank:
			continue
		found_side = true
		for point: Vector2 in [Vector2(segment["start"]), Vector2(segment["end"])]:
			tangent_min = minf(tangent_min, point.dot(tangent))
			tangent_max = maxf(tangent_max, point.dot(tangent))
			outer_projection = maxf(outer_projection, point.dot(normal))
	if not found_side:
		return PackedVector2Array()

	tangent_min -= field_endpoint_extension
	tangent_max += field_endpoint_extension
	var span := tangent_max - tangent_min
	var field_projection := outer_projection + field_standoff
	var start := tangent * tangent_min + normal * field_projection
	var finish := tangent * tangent_max + normal * field_projection
	var control := tangent * ((tangent_min + tangent_max) * 0.5) + normal * (field_projection + clampf(span * field_curve_depth_ratio, 8.0, 34.0))
	var points := PackedVector2Array()
	var sample_count := clampi(ceili(span / 5.0), 12, 32)
	for index: int in range(sample_count + 1):
		var t := float(index) / float(sample_count)
		var inverse := 1.0 - t
		var point := inverse * inverse * start + 2.0 * inverse * t * control + t * t * finish
		point += normal * _impact_reverberation(point, normal, bank)
		points.append(point)
	return points


func _impact_reverberation(midpoint: Vector2, normal: Vector2, bank: int) -> float:
	var displacement := 0.0
	for impact: Dictionary in active_impacts:
		if _bank_for_normal(Vector2(impact.get("normal", Vector2.ZERO))) != bank:
			continue
		var age := float(impact.get("age", 0.0))
		var life := 1.0 - clampf(age / impact_lifetime, 0.0, 1.0)
		var distance := midpoint.distance_to(Vector2(impact.get("point", midpoint)))
		displacement += sin(age * 48.0 - distance * 0.16) * life * float(impact.get("strength", 1.0)) * 3.0
	return displacement


func _bank_for_normal(normal: Vector2) -> int:
	if absf(normal.x) > absf(normal.y):
		return 1 if normal.x > 0.0 else 3
	return 2 if normal.y > 0.0 else 0


func _normal_for_bank(bank: int) -> Vector2:
	match bank:
		0:
			return Vector2.UP
		1:
			return Vector2.RIGHT
		2:
			return Vector2.DOWN
		_:
			return Vector2.LEFT


func _draw_impact_wave(hull_cells: Dictionary, impact: Dictionary) -> void:
	var age := float(impact["age"])
	var life_ratio := clampf(age / impact_lifetime, 0.0, 1.0)
	var strength := float(impact["strength"])
	var center: Vector2 = impact["point"]
	var radius := age * wave_speed
	var fade := (1.0 - life_ratio) * strength
	var bounds: Rect2i = ship_layout.call("get_occupied_bounds")
	for segment: Dictionary in GRID_GEOMETRY.boundary_segments(ship_layout, hull_cells, bounds, cell_size, grid_origin):
		_draw_wave_edge(segment["start"], segment["end"], true, center, radius, fade)
	var marker_color := impact_color
	marker_color.a *= fade
	var marker_radius := impact_marker_radius + age * 12.0
	draw_arc(center, marker_radius, 0.0, TAU, 20, marker_color, maxf(wave_line_width - 1.0, 1.0), false)


func _draw_wave_edge(start: Vector2, finish: Vector2, exposed: bool, center: Vector2, radius: float, fade: float) -> void:
	if not exposed:
		return
	var midpoint := (start + finish) * 0.5
	var distance_from_impact := midpoint.distance_to(center)
	var band_strength := 1.0 - clampf(absf(distance_from_impact - radius) / wave_band_width, 0.0, 1.0)
	if band_strength <= 0.0:
		return
	var color := wave_color
	color.a *= fade * band_strength
	draw_line(start, finish, color, wave_line_width, false)


func _all_occupied_cells() -> Dictionary:
	var occupied_cells: Dictionary = {}
	var rooms: Array = ship_layout.get("rooms")
	for room: Resource in rooms:
		var rects: Array[Rect2i] = room.get("grid_rects")
		for grid_rect: Rect2i in rects:
			for y: int in range(grid_rect.position.y, grid_rect.end.y):
				for x: int in range(grid_rect.position.x, grid_rect.end.x):
					occupied_cells[Vector2i(x, y)] = true
	return occupied_cells


func _draw_boundary(occupied_cells: Dictionary, color: Color, width: float) -> void:
	for cell_value: Variant in occupied_cells.keys():
		var cell: Vector2i = cell_value
		var cell_rect := _get_cell_rect(cell)
		if not occupied_cells.has(cell + Vector2i.UP):
			draw_line(cell_rect.position, Vector2(cell_rect.end.x, cell_rect.position.y), color, width)
		if not occupied_cells.has(cell + Vector2i.DOWN):
			draw_line(Vector2(cell_rect.position.x, cell_rect.end.y), cell_rect.end, color, width)
		if not occupied_cells.has(cell + Vector2i.LEFT):
			draw_line(cell_rect.position, Vector2(cell_rect.position.x, cell_rect.end.y), color, width)
		if not occupied_cells.has(cell + Vector2i.RIGHT):
			draw_line(Vector2(cell_rect.end.x, cell_rect.position.y), cell_rect.end, color, width)


func _get_cell_rect(cell: Vector2i) -> Rect2:
	var bounds: Rect2i = ship_layout.call("get_occupied_bounds")
	return GRID_GEOMETRY.cell_rect(ship_layout, cell, bounds, cell_size, grid_origin)
