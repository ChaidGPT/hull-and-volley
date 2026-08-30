class_name ShipStructuralState
extends RefCounted

const ROOM_STAFFING_RULES := preload("res://scripts/room_staffing_rules.gd")

const GRID_GEOMETRY := preload("res://scripts/grid_geometry.gd")
const BRIDGE_ROOM_LAYOUT := preload("res://scenes/room_layouts/standard/bridge_room_layout.tscn")
const THRUSTER_ROOM_LAYOUT := preload("res://scenes/room_layouts/standard/thruster_room_layout.tscn")

var layout: Resource
var material: Resource
var door_definition: Resource
var walls: Dictionary = {}
var cell_walls: Dictionary = {}
var doors: Dictionary = {}
var cell_pressure: Dictionary = {}
var cell_rooms: Dictionary = {}
var room_resources: Dictionary = {}
var cell_room_piece_indices: Dictionary = {}
var room_door_rules: Dictionary = {}


func configure(ship_layout: Resource, structural_material: Resource, shared_door_definition: Resource = null) -> void:
	layout = ship_layout
	if layout != null and layout.has_method("ensure_quarter_lattice"):
		layout.call("ensure_quarter_lattice")
	material = structural_material
	door_definition = shared_door_definition
	_build_structure()


func reconfigure_preserving_state(ship_layout: Resource, structural_material: Resource, shared_door_definition: Resource = null) -> void:
	var previous_wall_state: Dictionary = {}
	for key_value: Variant in walls.keys():
		var key := String(key_value)
		var wall: Dictionary = walls[key]
		previous_wall_state[key] = {
			"current": wall.get("current", wall.get("maximum", 0.0)),
			"breached": wall.get("breached", false),
			"topology": _wall_topology_signature(wall),
		}
	var previous_pressure := cell_pressure.duplicate()
	var previous_door_state: Dictionary = {}
	for key_value: Variant in doors.keys():
		var key := String(key_value)
		var door: Dictionary = doors[key]
		previous_door_state[key] = {
			"locked": door.get("locked", false),
			"requested_open": door.get("requested_open", false),
			"openness": door.get("openness", 0.0),
		}
	configure(ship_layout, structural_material, shared_door_definition)
	for key_value: Variant in walls.keys():
		var key := String(key_value)
		if not previous_wall_state.has(key):
			continue
		var wall: Dictionary = walls[key]
		var state: Dictionary = previous_wall_state[key]
		# A refit can leave an edge at the same coordinates while changing what
		# that edge *is* (for example, an internal weapon-room bulkhead becoming
		# exposed hull after the weapon is removed). Never carry damage across
		# that topology change or deleted modules leave ghost-colored hull scars.
		if String(state.get("topology", "")) != _wall_topology_signature(wall):
			continue
		wall["current"] = clampf(float(state["current"]), 0.0, float(wall["maximum"]))
		wall["breached"] = bool(state["breached"]) or float(wall["current"]) <= 0.0
	for cell_value: Variant in cell_pressure.keys():
		if previous_pressure.has(cell_value):
			cell_pressure[cell_value] = float(previous_pressure[cell_value])
	for key_value: Variant in doors.keys():
		var key := String(key_value)
		if not previous_door_state.has(key):
			continue
		var door: Dictionary = doors[key]
		var state: Dictionary = previous_door_state[key]
		door["locked"] = bool(state["locked"])
		door["requested_open"] = bool(state["requested_open"])
		door["openness"] = clampf(float(state["openness"]), 0.0, 1.0)


func _wall_topology_signature(wall: Dictionary) -> String:
	var room_ids: Array[String] = []
	for cell_value: Variant in wall.get("cells", []):
		var room_id := String(cell_rooms.get(cell_value, &""))
		if not room_ids.has(room_id):
			room_ids.append(room_id)
	room_ids.sort()
	return "%s|%s" % ["OUTER" if bool(wall.get("outer", false)) else "INNER", ",".join(room_ids)]


func _build_structure() -> void:
	walls.clear()
	cell_walls.clear()
	doors.clear()
	cell_pressure.clear()
	cell_rooms.clear()
	room_resources.clear()
	cell_room_piece_indices.clear()
	room_door_rules.clear()
	if layout == null or material == null:
		return
	for room: Resource in layout.get("rooms"):
		var room_id := String(room.get("room_id"))
		room_resources[room_id] = room
		_cache_room_door_rule(room)
		var room_rects: Array[Rect2i] = room.get("grid_rects")
		for piece_index: int in range(room_rects.size()):
			var rect: Rect2i = room_rects[piece_index]
			for y: int in range(rect.position.y, rect.end.y):
				for x: int in range(rect.position.x, rect.end.x):
					var cell := Vector2i(x, y)
					cell_rooms[cell] = room.get("room_id")
					cell_room_piece_indices[cell] = piece_index
					cell_pressure[cell] = 1.0
	var segment_sides: Dictionary = {}
	for cell_value: Variant in cell_rooms.keys():
		var cell: Vector2i = cell_value
		var rect := GRID_GEOMETRY.logical_cell_rect(cell, GRID_GEOMETRY.cell_offset(layout, cell))
		_register_split_edge(segment_sides, rect.position, Vector2(rect.end.x, rect.position.y), cell)
		_register_split_edge(segment_sides, Vector2(rect.end.x, rect.position.y), rect.end, cell)
		_register_split_edge(segment_sides, rect.end, Vector2(rect.position.x, rect.end.y), cell)
		_register_split_edge(segment_sides, Vector2(rect.position.x, rect.end.y), rect.position, cell)
	for key_value: Variant in segment_sides.keys():
		var key := String(key_value)
		var entry: Dictionary = segment_sides[key]
		var adjacent: Array = entry["cells"]
		if adjacent.size() > 1 and cell_rooms.get(adjacent[0]) == cell_rooms.get(adjacent[1]):
			continue
		var outer := adjacent.size() == 1
		var length: float = (entry["start"] as Vector2).distance_to(entry["end"])
		var full_durability := float(material.get("outer_hull_durability")) if outer else float(material.get("internal_bulkhead_durability"))
		var maximum := full_durability * length
		walls[key] = {
			"key": key,
			"start": entry["start"],
			"end": entry["end"],
			"cells": adjacent,
			"outer": outer,
			"maximum": maximum,
			"current": maximum,
			"breached": false,
		}
		for cell_value: Variant in adjacent:
			var cell: Vector2i = cell_value
			if not cell_walls.has(cell):
				cell_walls[cell] = []
			(cell_walls[cell] as Array).append(key)
	_build_doors()


func _cache_room_door_rule(room: Resource) -> void:
	var room_type := String(room.get("type_name"))
	if room_door_rules.has(room_type):
		return
	var room_scene: PackedScene = null
	match room_type:
		"COMMAND", "BRIDGE":
			room_scene = BRIDGE_ROOM_LAYOUT
		"PROPULSION":
			room_scene = THRUSTER_ROOM_LAYOUT
	if room_scene == null:
		room_door_rules[room_type] = {
			"forbidden_edges": 0,
			"source_rotation_quarters": 0,
		}
		return
	var authored := room_scene.instantiate() as RoomCrewLayout
	if authored == null:
		return
	room_door_rules[room_type] = {
		"forbidden_edges": authored.forbidden_door_edges,
		"source_rotation_quarters": authored.source_rotation_quarters,
	}
	authored.free()


func _room_forbids_door_on_boundary(room_id: String, from_cell: Vector2i, to_cell: Vector2i) -> bool:
	var room := room_resources.get(room_id) as Resource
	if room == null:
		return false
	# Quarter-scale exterior hardware is serviced from outside and has no
	# traversable interior. Its attachment remains a solid structural boundary.
	if ROOM_STAFFING_RULES.is_unmanned_exterior_module(room):
		return true
	var rule: Dictionary = room_door_rules.get(String(room.get("type_name")), {})
	var forbidden_edges := int(rule.get("forbidden_edges", 0))
	if forbidden_edges == 0:
		return false
	var from_center := GRID_GEOMETRY.logical_cell_rect(
		from_cell,
		GRID_GEOMETRY.cell_offset(layout, from_cell)
	).get_center()
	var to_center := GRID_GEOMETRY.logical_cell_rect(
		to_cell,
		GRID_GEOMETRY.cell_offset(layout, to_cell)
	).get_center()
	var delta := to_center - from_center
	var live_edge := 0
	if absf(delta.x) > absf(delta.y):
		live_edge = 1 if delta.x > 0.0 else 3
	else:
		live_edge = 2 if delta.y > 0.0 else 0
	var piece_index := int(cell_room_piece_indices.get(from_cell, 0))
	var facing := int(room.get("module_facing_quarters"))
	var mount_facings: Array = room.get("module_mount_facings")
	if piece_index >= 0 and piece_index < mount_facings.size():
		facing = int(mount_facings[piece_index])
	facing = posmod(maxi(facing, 0), 4)
	var total_rotation := posmod(facing + int(rule.get("source_rotation_quarters", 0)), 4)
	var source_edge := posmod(live_edge - total_rotation, 4)
	return (forbidden_edges & (1 << source_edge)) != 0


func _build_doors() -> void:
	if door_definition == null:
		return
	var boundary_groups: Dictionary = {}
	for wall_value: Variant in walls.values():
		var wall: Dictionary = wall_value
		var cells: Array = wall["cells"]
		if bool(wall["outer"]) or cells.size() < 2:
			continue
		var first_room := String(cell_rooms.get(cells[0], &""))
		var second_room := String(cell_rooms.get(cells[1], &""))
		if first_room == second_room:
			continue
		if _room_forbids_door_on_boundary(first_room, cells[0], cells[1]) \
			or _room_forbids_door_on_boundary(second_room, cells[1], cells[0]):
			continue
		var room_pair := [first_room, second_room]
		room_pair.sort()
		var start: Vector2 = wall["start"]
		var finish: Vector2 = wall["end"]
		var vertical := is_equal_approx(start.x, finish.x)
		var fixed := start.x if vertical else start.y
		var group_key := "%s|%s|%s|%.3f" % [room_pair[0], room_pair[1], "V" if vertical else "H", fixed]
		if not boundary_groups.has(group_key):
			boundary_groups[group_key] = []
		(boundary_groups[group_key] as Array).append(wall)
	for group_key_value: Variant in boundary_groups.keys():
		var candidates: Array = boundary_groups[group_key_value]
		candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			var a_start: Vector2 = a["start"]
			var b_start: Vector2 = b["start"]
			return (a_start.y if is_equal_approx(a_start.x, Vector2(a["end"]).x) else a_start.x) < (b_start.y if is_equal_approx(b_start.x, Vector2(b["end"]).x) else b_start.x)
		)
		var runs: Array[Array] = []
		var current_run: Array = []
		var previous_end := -INF
		for wall_value: Variant in candidates:
			var wall: Dictionary = wall_value
			var start: Vector2 = wall["start"]
			var finish: Vector2 = wall["end"]
			var segment_start := minf(start.x, finish.x) if not is_equal_approx(start.x, finish.x) else minf(start.y, finish.y)
			var segment_end := maxf(start.x, finish.x) if not is_equal_approx(start.x, finish.x) else maxf(start.y, finish.y)
			if not current_run.is_empty() and segment_start > previous_end + 0.001:
				runs.append(current_run)
				current_run = []
			current_run.append(wall)
			previous_end = segment_end
		if not current_run.is_empty():
			runs.append(current_run)
		for run_index: int in range(runs.size()):
			var run: Array = runs[run_index]
			var chosen: Dictionary = run[floori(float(run.size()) * 0.5)]
			var chosen_start: Vector2 = chosen["start"]
			var chosen_finish: Vector2 = chosen["end"]
			var vertical := is_equal_approx(chosen_start.x, chosen_finish.x)
			var minimum_axis := INF
			var maximum_axis := -INF
			for segment_value: Variant in run:
				var segment: Dictionary = segment_value
				var segment_start: Vector2 = segment["start"]
				var segment_finish: Vector2 = segment["end"]
				minimum_axis = minf(minimum_axis, minf(segment_start.y, segment_finish.y) if vertical else minf(segment_start.x, segment_finish.x))
				maximum_axis = maxf(maximum_axis, maxf(segment_start.y, segment_finish.y) if vertical else maxf(segment_start.x, segment_finish.x))
			var fixed_axis := chosen_start.x if vertical else chosen_start.y
			var center := Vector2(fixed_axis, (minimum_axis + maximum_axis) * 0.5) if vertical else Vector2((minimum_axis + maximum_axis) * 0.5, fixed_axis)
			var tangent := Vector2.DOWN if vertical else Vector2.RIGHT
			var half_width := float(door_definition.get("edge_width_fraction")) * 0.5
			var door_start := center - tangent * half_width
			var door_end := center + tangent * half_width
			# Structural edges are split into half-cell wall segments. A centered
			# doorway can straddle the seam between two of those segments, so the
			# complete aperture must be passable while a crew member crosses it.
			# Keeping only the arbitrarily chosen center segment leaves the other
			# half of the visible doorway solid and traps crew at the threshold.
			var aperture_wall_keys: Array[String] = []
			var aperture_min := minf(door_start.y, door_end.y) if vertical else minf(door_start.x, door_end.x)
			var aperture_max := maxf(door_start.y, door_end.y) if vertical else maxf(door_start.x, door_end.x)
			for segment_value: Variant in run:
				var segment: Dictionary = segment_value
				var segment_start := Vector2(segment["start"])
				var segment_end := Vector2(segment["end"])
				var segment_min := minf(segment_start.y, segment_end.y) if vertical else minf(segment_start.x, segment_end.x)
				var segment_max := maxf(segment_start.y, segment_end.y) if vertical else maxf(segment_start.x, segment_end.x)
				if segment_max > aperture_min + 0.0001 and segment_min < aperture_max - 0.0001:
					aperture_wall_keys.append(String(segment["key"]))
			if aperture_wall_keys.is_empty():
				aperture_wall_keys.append(String(chosen["key"]))
			var door_id := "%s#%d" % [String(group_key_value), run_index]
			doors[door_id] = {
				"id": door_id,
				"wall_key": chosen["key"],
				"wall_keys": aperture_wall_keys,
				"start": door_start,
				"end": door_end,
				"cells": (chosen["cells"] as Array).duplicate(),
				"locked": false,
				"pressure_interlocked": false,
				"hazard_override": false,
				"requested_open": false,
				"openness": 0.0,
			}


func _register_split_edge(registry: Dictionary, start: Vector2, finish: Vector2, cell: Vector2i) -> void:
	var length := start.distance_to(finish)
	var pieces := maxi(1, ceili(length / 0.5))
	for index: int in range(pieces):
		var a := start.lerp(finish, float(index) / float(pieces))
		var b := start.lerp(finish, float(index + 1) / float(pieces))
		var key := _segment_key(a, b)
		if not registry.has(key):
			registry[key] = {"start": a, "end": b, "cells": []}
		var cells: Array = registry[key]["cells"]
		if not cells.has(cell):
			cells.append(cell)


func _segment_key(first: Vector2, second: Vector2) -> String:
	var a := Vector2i(roundi(first.x * 1000.0), roundi(first.y * 1000.0))
	var b := Vector2i(roundi(second.x * 1000.0), roundi(second.y * 1000.0))
	if a.x > b.x or (a.x == b.x and a.y > b.y):
		var swap := a
		a = b
		b = swap
	return "%d,%d:%d,%d" % [a.x, a.y, b.x, b.y]


func trace_penetration(local_entry: Vector2, local_direction: Vector2, energy: float, tactical_cell_size: float) -> Dictionary:
	var hits: Array[Dictionary] = []
	if energy <= 0.0 or local_direction.is_zero_approx():
		return {"remaining_energy": energy, "hits": hits}
	var bounds: Rect2i = layout.call("get_occupied_bounds")
	var geometry_size := GRID_GEOMETRY.grid_pixel_size(layout, bounds, tactical_cell_size)
	var ray_end := local_entry + local_direction.normalized() * geometry_size.length() * 2.0
	for wall_value: Variant in walls.values():
		var wall: Dictionary = wall_value
		var start := _logical_to_local(wall["start"], bounds, geometry_size, tactical_cell_size)
		var finish := _logical_to_local(wall["end"], bounds, geometry_size, tactical_cell_size)
		var intersection: Variant = Geometry2D.segment_intersects_segment(local_entry - local_direction.normalized() * 2.0, ray_end, start, finish)
		if intersection != null:
			hits.append({"wall": wall, "point": intersection, "distance": local_entry.distance_to(intersection)})
	hits.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["distance"]) < float(b["distance"]))
	var resolved: Array[Dictionary] = []
	for hit: Dictionary in hits:
		if energy <= 0.0:
			break
		var wall: Dictionary = hit["wall"]
		var before := float(wall["current"])
		var applied := minf(before, energy)
		wall["current"] = maxf(before - applied, 0.0)
		wall["breached"] = float(wall["current"]) <= 0.0
		energy = maxf(energy - applied * float(material.get("penetration_resistance")), 0.0)
		resolved.append({"key": wall["key"], "point": hit["point"], "damage": applied, "breached": wall["breached"]})
		if not bool(wall["breached"]):
			break
	return {"remaining_energy": energy, "hits": resolved}


func _logical_to_local(point: Vector2, bounds: Rect2i, geometry_size: Vector2, cell_size: float) -> Vector2:
	return (point - Vector2(bounds.position)) * cell_size - geometry_size * 0.5


func update_atmosphere(delta: float) -> void:
	if material == null:
		return
	var vent_rate := float(material.get("breach_vent_rate")) * delta
	_update_doors(delta)
	for wall_value: Variant in walls.values():
		var wall: Dictionary = wall_value
		if not bool(wall["breached"]):
			continue
		var cells: Array = wall["cells"]
		if bool(wall["outer"]) and not cells.is_empty():
			cell_pressure[cells[0]] = maxf(float(cell_pressure.get(cells[0], 1.0)) - vent_rate, 0.0)
		elif cells.size() >= 2:
			_equalize_cells(cells[0], cells[1], delta)
	for door_value: Variant in doors.values():
		var door: Dictionary = door_value
		if float(door["openness"]) > 0.01:
			var cells: Array = door["cells"]
			_equalize_cells(cells[0], cells[1], delta * float(door["openness"]))
	# Cells belonging to one room are openly connected even though no wall exists between them.
	for first_value: Variant in cell_rooms.keys():
		var first: Vector2i = first_value
		for direction: Vector2i in [Vector2i.RIGHT, Vector2i.DOWN]:
			var second := first + direction
			if cell_rooms.has(second) and cell_rooms.get(first) == cell_rooms.get(second):
				_equalize_cells(first, second, delta)


func has_active_atmosphere_events() -> bool:
	for wall_value: Variant in walls.values():
		if bool((wall_value as Dictionary).get("breached", false)):
			return true
	for door_value: Variant in doors.values():
		var door: Dictionary = door_value
		if bool(door.get("requested_open", false)) or float(door.get("openness", 0.0)) > 0.001:
			return true
	return false


func _equalize_cells(first: Vector2i, second: Vector2i, delta: float) -> void:
	var first_pressure := float(cell_pressure.get(first, 1.0))
	var second_pressure := float(cell_pressure.get(second, 1.0))
	var transfer := (first_pressure - second_pressure) * minf(float(material.get("equalization_rate")) * delta, 0.5)
	cell_pressure[first] = first_pressure - transfer
	cell_pressure[second] = second_pressure + transfer


func get_cell_pressure(cell: Vector2i) -> float:
	return float(cell_pressure.get(cell, 1.0))


func get_room_pressure(room_id: StringName) -> float:
	var total := 0.0
	var count := 0
	for cell_value: Variant in cell_rooms.keys():
		if StringName(cell_rooms[cell_value]) == room_id:
			total += get_cell_pressure(cell_value)
			count += 1
	return total / float(count) if count > 0 else 0.0


func get_room_outer_breach_length(room_id: StringName) -> float:
	var total := 0.0
	for wall_value: Variant in walls.values():
		var wall: Dictionary = wall_value
		if not bool(wall["outer"]) or not bool(wall["breached"]):
			continue
		var cells: Array = wall["cells"]
		if not cells.is_empty() and StringName(cell_rooms.get(cells[0], &"")) == room_id:
			total += Vector2(wall["start"]).distance_to(Vector2(wall["end"]))
	return total


func get_decompression_force(logical_position: Vector2, room_id: StringName) -> Vector2:
	if material == null:
		return Vector2.ZERO
	var breach_length := get_room_outer_breach_length(room_id)
	var threshold := float(material.get("large_breach_length"))
	if breach_length < threshold:
		return Vector2.ZERO
	var radius := float(material.get("decompression_pull_radius"))
	var force := Vector2.ZERO
	for wall_value: Variant in walls.values():
		var wall: Dictionary = wall_value
		if not bool(wall["outer"]) or not bool(wall["breached"]):
			continue
		var cells: Array = wall["cells"]
		if cells.is_empty() or StringName(cell_rooms.get(cells[0], &"")) != room_id:
			continue
		var breach_center := (Vector2(wall["start"]) + Vector2(wall["end"])) * 0.5
		var distance := logical_position.distance_to(breach_center)
		if distance > radius or distance <= 0.001:
			continue
		var pressure := get_cell_pressure(cells[0])
		var falloff := 1.0 - distance / radius
		var opening_scale := clampf(breach_length / maxf(threshold, 0.01), 1.0, 3.0)
		force += logical_position.direction_to(breach_center) * float(material.get("decompression_pull_strength")) * pressure * falloff * opening_scale
	return force


func contains_logical_position(logical_position: Vector2) -> bool:
	for cell_value: Variant in cell_rooms.keys():
		var cell: Vector2i = cell_value
		if GRID_GEOMETRY.logical_cell_rect(cell, GRID_GEOMETRY.cell_offset(layout, cell)).has_point(logical_position):
			return true
	return false


## Tests a complete local crew leg against the ship's actual wall network.
## Furniture steering cannot rely only on rectangle corners: an otherwise
## attractive corner may sit beyond an exterior wall or across a closed room
## boundary, causing the collision sweep to reject every movement frame.
func is_crew_segment_clear(previous: Vector2, desired: Vector2, clearance: float, passable_door_id: String = "") -> bool:
	if not contains_logical_position(desired):
		return false
	var ignored_wall_keys := _door_aperture_wall_keys(passable_door_id)
	for wall_value: Variant in walls.values():
		var wall: Dictionary = wall_value
		if ignored_wall_keys.has(String(wall.get("key", ""))):
			continue
		var wall_start := Vector2(wall["start"])
		var wall_end := Vector2(wall["end"])
		if Geometry2D.segment_intersects_segment(previous, desired, wall_start, wall_end) != null:
			return false
		if _closest_point_on_segment(desired, wall_start, wall_end).distance_squared_to(desired) < clearance * clearance:
			return false
	return true


func _update_doors(delta: float) -> void:
	if door_definition == null:
		return
	for door_value: Variant in doors.values():
		var door: Dictionary = door_value
		var cells: Array = door["cells"]
		var pressure_difference := absf(get_cell_pressure(cells[0]) - get_cell_pressure(cells[1]))
		door["pressure_interlocked"] = bool(door_definition.get("automatic_pressure_interlock")) and pressure_difference > float(door_definition.get("safe_pressure_difference"))
		var wall: Dictionary = walls.get(door["wall_key"], {})
		var destroyed := not wall.is_empty() and bool(wall["breached"])
		var may_open := not bool(door["locked"]) and (not bool(door["pressure_interlocked"]) or bool(door.get("hazard_override", false)))
		var target := 1.0 if destroyed or (bool(door["requested_open"]) and may_open) else 0.0
		var speed := 1.0 / maxf(float(door_definition.get("travel_time")), 0.01)
		door["openness"] = move_toward(float(door["openness"]), target, speed * delta)


func request_door_open(door_id: String, should_open: bool) -> bool:
	if not doors.has(door_id):
		return false
	var door: Dictionary = doors[door_id]
	if should_open and (bool(door["locked"]) or bool(door["pressure_interlocked"])):
		return false
	door["requested_open"] = should_open
	return true


func request_hazard_door_override(door_id: String, should_open: bool) -> bool:
	if not doors.has(door_id):
		return false
	var door: Dictionary = doors[door_id]
	if should_open and bool(door["locked"]):
		return false
	door["hazard_override"] = should_open
	door["requested_open"] = should_open
	return true


func set_door_locked(door_id: String, should_lock: bool) -> void:
	if not doors.has(door_id):
		return
	var door: Dictionary = doors[door_id]
	door["locked"] = should_lock
	if should_lock:
		door["requested_open"] = false


func can_traverse_door(door_id: String) -> bool:
	if not doors.has(door_id):
		return false
	var door: Dictionary = doors[door_id]
	return float(door["openness"]) >= 0.85 and not bool(door["locked"])


func get_door_between_cells(first: Vector2i, second: Vector2i) -> String:
	for door_value: Variant in doors.values():
		var door: Dictionary = door_value
		var cells: Array = door["cells"]
		if cells.has(first) and cells.has(second):
			return String(door["id"])
	return ""


func get_door_center(door_id: String) -> Vector2:
	if not doors.has(door_id):
		return Vector2.ZERO
	var door: Dictionary = doors[door_id]
	return (Vector2(door["start"]) + Vector2(door["end"])) * 0.5


## Returns a point directly in front of a doorway on the requested cell's
## side. Using the door normal (rather than direction-to-center) prevents a
## crew member from diagonally shaving across the wall jamb at offset rooms.
func get_door_approach_point(door_id: String, cell: Vector2i, clearance: float) -> Vector2:
	if not doors.has(door_id):
		return GRID_GEOMETRY.logical_cell_rect(cell, GRID_GEOMETRY.cell_offset(layout, cell)).get_center()
	var door: Dictionary = doors[door_id]
	var center := (Vector2(door["start"]) + Vector2(door["end"])) * 0.5
	var tangent := Vector2(door["end"]) - Vector2(door["start"])
	var normal := tangent.orthogonal().normalized()
	var cell_center := GRID_GEOMETRY.logical_cell_rect(cell, GRID_GEOMETRY.cell_offset(layout, cell)).get_center()
	if normal.dot(cell_center - center) < 0.0:
		normal = -normal
	return center + normal * maxf(clearance, 0.01)


## Sweeps a point-sized crew body between two navigation samples, then keeps
## its center a small distance from nearby solid wall segments. The active
## doorway wall is ignored only while the crew member is actually crossing it.
func constrain_crew_motion(
	previous: Vector2,
	desired: Vector2,
	current_cell: Vector2i,
	next_cell: Vector2i,
	clearance: float,
	passable_door_id: String = ""
) -> Vector2:
	var resolved := desired
	var ignored_wall_keys := _door_aperture_wall_keys(passable_door_id)
	var nearby_wall_keys: Dictionary = {}
	for cell: Vector2i in [current_cell, next_cell]:
		for wall_key_value: Variant in cell_walls.get(cell, []):
			nearby_wall_keys[String(wall_key_value)] = true
	for wall_key_value: Variant in nearby_wall_keys.keys():
		var wall_key := String(wall_key_value)
		if not walls.has(wall_key):
			continue
		var wall: Dictionary = walls[wall_key]
		if ignored_wall_keys.has(String(wall.get("key", ""))):
			continue
		var wall_start := Vector2(wall["start"])
		var wall_end := Vector2(wall["end"])
		if Geometry2D.segment_intersects_segment(previous, resolved, wall_start, wall_end) != null:
			return previous
		var closest := _closest_point_on_segment(resolved, wall_start, wall_end)
		var separation := resolved - closest
		if separation.length_squared() >= clearance * clearance:
			continue
		var push_direction := separation.normalized()
		if push_direction.is_zero_approx():
			var current_center := GRID_GEOMETRY.logical_cell_rect(current_cell, GRID_GEOMETRY.cell_offset(layout, current_cell)).get_center()
			push_direction = (current_center - closest).normalized()
		if not push_direction.is_zero_approx():
			resolved = closest + push_direction * clearance
	return resolved


func _door_aperture_wall_keys(door_id: String) -> Dictionary:
	var result: Dictionary = {}
	if door_id.is_empty() or not doors.has(door_id):
		return result
	var door: Dictionary = doors[door_id]
	var stored_keys: Variant = door.get("wall_keys", [])
	if stored_keys is Array:
		for wall_key_value: Variant in stored_keys:
			var wall_key := String(wall_key_value)
			if not wall_key.is_empty():
				result[wall_key] = true
	# Compatibility with structures serialized/generated before multi-segment
	# apertures were introduced.
	if result.is_empty():
		var legacy_key := String(door.get("wall_key", ""))
		if not legacy_key.is_empty():
			result[legacy_key] = true
	return result


func _closest_point_on_segment(point: Vector2, start: Vector2, finish: Vector2) -> Vector2:
	var segment := finish - start
	var length_squared := segment.length_squared()
	if length_squared <= 0.000001:
		return start
	var amount := clampf((point - start).dot(segment) / length_squared, 0.0, 1.0)
	return start + segment * amount


func damage_wall(wall_key: String, amount: float) -> void:
	if not walls.has(wall_key):
		return
	var wall: Dictionary = walls[wall_key]
	wall["current"] = maxf(float(wall["current"]) - maxf(amount, 0.0), 0.0)
	wall["breached"] = float(wall["current"]) <= 0.0


func breach_wall(wall_key: String) -> void:
	if walls.has(wall_key):
		damage_wall(wall_key, float(walls[wall_key]["maximum"]))


func repair_wall(wall_key: String) -> void:
	if not walls.has(wall_key):
		return
	var wall: Dictionary = walls[wall_key]
	wall["current"] = wall["maximum"]
	wall["breached"] = false


func repair_wall_amount(wall_key: String, amount: float) -> void:
	if not walls.has(wall_key):
		return
	var wall: Dictionary = walls[wall_key]
	wall["current"] = minf(float(wall["current"]) + maxf(amount, 0.0), float(wall["maximum"]))
	wall["breached"] = float(wall["current"]) <= 0.0


func restore_atmosphere() -> void:
	for cell: Variant in cell_pressure.keys():
		cell_pressure[cell] = 1.0


func trace_from_wall(wall_key: String, energy: float, tactical_cell_size: float) -> Dictionary:
	if not walls.has(wall_key):
		return {"remaining_energy": energy, "hits": []}
	var wall: Dictionary = walls[wall_key]
	var cells: Array = wall["cells"]
	if cells.is_empty():
		return {"remaining_energy": energy, "hits": []}
	var midpoint: Vector2 = (Vector2(wall["start"]) + Vector2(wall["end"])) * 0.5
	var first_cell: Vector2i = cells[0]
	var cell_center := GRID_GEOMETRY.logical_cell_rect(first_cell, GRID_GEOMETRY.cell_offset(layout, first_cell)).get_center()
	var inward := (cell_center - midpoint).normalized()
	if inward.is_zero_approx():
		inward = (Vector2(wall["end"]) - Vector2(wall["start"])).orthogonal().normalized()
	var bounds: Rect2i = layout.call("get_occupied_bounds")
	var geometry_size := GRID_GEOMETRY.grid_pixel_size(layout, bounds, tactical_cell_size)
	var entry := _logical_to_local(midpoint, bounds, geometry_size, tactical_cell_size) - inward * 3.0
	return trace_penetration(entry, inward, energy, tactical_cell_size)
