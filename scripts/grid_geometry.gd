class_name GridGeometry
extends RefCounted


static func cell_offset(layout: Resource, cell: Vector2i) -> Vector2:
	var offset: Vector2 = layout.call("get_cell_offset", cell)
	return offset


static func logical_cell_rect(cell: Vector2i, offset: Vector2) -> Rect2:
	return Rect2(Vector2(cell) + offset, Vector2.ONE)


static func cell_rect(layout: Resource, cell: Vector2i, bounds: Rect2i, cell_size: float, origin: Vector2 = Vector2.ZERO) -> Rect2:
	return Rect2(
		origin + (Vector2(cell - bounds.position) + cell_offset(layout, cell)) * cell_size,
		Vector2.ONE * cell_size
	)


static func grid_pixel_size(layout: Resource, bounds: Rect2i, cell_size: float) -> Vector2:
	var extra_size := Vector2.ZERO
	for y: int in range(bounds.position.y, bounds.end.y):
		for x: int in range(bounds.position.x, bounds.end.x):
			var offset := cell_offset(layout, Vector2i(x, y))
			extra_size.x = maxf(extra_size.x, offset.x)
			extra_size.y = maxf(extra_size.y, offset.y)
	return (Vector2(bounds.size) + extra_size) * cell_size


static func has_exterior_profile(room_type: String) -> bool:
	return room_type in ["COMMAND", "BRIDGE", "PROPULSION", "HANGAR"]


static func exterior_facing_quarters(room: Resource) -> int:
	var explicit_facing := int(room.get("module_facing_quarters"))
	if explicit_facing >= 0:
		return posmod(explicit_facing, 4)
	return 2 if String(room.get("type_name")) == "PROPULSION" else 0


static func quarter_direction(quarters: int) -> Vector2i:
	var direction := Vector2.UP.rotated(float(posmod(quarters, 4)) * PI * 0.5)
	return Vector2i(roundi(direction.x), roundi(direction.y))


static func layout_cells(layout: Resource) -> Dictionary:
	var occupied: Dictionary = {}
	if layout == null:
		return occupied
	for room: Resource in layout.get("rooms"):
		for rect: Rect2i in room.get("grid_rects"):
			for y: int in range(rect.position.y, rect.end.y):
				for x: int in range(rect.position.x, rect.end.x):
					occupied[Vector2i(x, y)] = true
	return occupied


static func room_cells(room: Resource) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	if room == null:
		return cells
	for rect: Rect2i in room.get("grid_rects"):
		for y: int in range(rect.position.y, rect.end.y):
			for x: int in range(rect.position.x, rect.end.x):
				cells.append(Vector2i(x, y))
	return cells


## Cardinal hull faces through which this module can physically fire, launch,
## or project a field. A one-cell corner mount naturally returns two or three
## faces while an internal mount returns none.
static func room_exposed_quarters(layout: Resource, room: Resource) -> Array[int]:
	var exposed: Array[int] = []
	var occupied := layout_cells(layout)
	for cell: Vector2i in room_cells(room):
		for quarter: int in range(4):
			if face_contact_strength(layout, cell, quarter_direction(quarter), occupied) < 0.999 and not exposed.has(quarter):
				exposed.append(quarter)
	exposed.sort()
	return exposed


static func resolved_module_facing(layout: Resource, room: Resource) -> int:
	var explicit := int(room.get("module_facing_quarters"))
	if explicit >= 0:
		return posmod(explicit, 4)
	var exposed := room_exposed_quarters(layout, room)
	if exposed.is_empty():
		return 0
	var bounds: Rect2i = layout.call("get_occupied_bounds")
	var hull_center := Vector2(bounds.position) + grid_pixel_size(layout, bounds, 1.0) * 0.5
	var module_center := Vector2.ZERO
	var cells := room_cells(room)
	for cell: Vector2i in cells:
		module_center += logical_cell_rect(cell, cell_offset(layout, cell)).get_center()
	module_center /= maxf(float(cells.size()), 1.0)
	var outward := (module_center - hull_center).normalized()
	var best := exposed[0]
	var best_score := -INF
	for quarter: int in exposed:
		var score := Vector2(quarter_direction(quarter)).dot(outward)
		if score > best_score:
			best_score = score
			best = quarter
	return best


static func weapon_coverage_quarters(layout: Resource, room: Resource, weapon: Resource) -> Array[int]:
	var exposed := room_exposed_quarters(layout, room)
	if weapon == null or exposed.is_empty():
		var no_coverage: Array[int] = []
		return no_coverage
	if bool(weapon.get("uses_exposed_hull_edges")):
		return exposed
	var facing := resolved_module_facing(layout, room)
	var coverage: Array[int] = []
	if exposed.has(facing):
		coverage.append(facing)
	return coverage


## Returns the safe negative/positive traverse offsets, in degrees, for one
## exposed weapon face. Immediate exposure alone is insufficient: a wider room
## elsewhere on the hull may still protrude across the muzzle's firing arc.
static func weapon_face_clearance_degrees(
	layout: Resource,
	room: Resource,
	quarter: int,
	desired_half_degrees: float
) -> Vector2:
	var desired := clampf(desired_half_degrees, 0.0, 89.0)
	if desired <= 0.0:
		return Vector2.ZERO
	var origin: Variant = _weapon_face_origin(layout, room, quarter)
	var facing := Vector2(quarter_direction(quarter))
	if origin == null or not _weapon_ray_is_clear(layout, room, origin, facing):
		return Vector2.ZERO
	return Vector2(
		-_clear_traverse_side(layout, room, origin, facing, desired, -1.0),
		_clear_traverse_side(layout, room, origin, facing, desired, 1.0)
	)


static func weapon_face_center_is_clear(layout: Resource, room: Resource, quarter: int) -> bool:
	var origin: Variant = _weapon_face_origin(layout, room, quarter)
	if origin == null:
		return false
	return _weapon_ray_is_clear(layout, room, origin, Vector2(quarter_direction(quarter)))


static func _clear_traverse_side(
	layout: Resource,
	room: Resource,
	origin: Vector2,
	facing: Vector2,
	desired_degrees: float,
	sign_value: float
) -> float:
	var desired_direction := facing.rotated(deg_to_rad(desired_degrees * sign_value))
	if _weapon_ray_is_clear(layout, room, origin, desired_direction):
		return desired_degrees
	var low := 0.0
	var high := desired_degrees
	# A short binary search gives sub-degree tangency without sampling an entire
	# arc every combat frame.
	for iteration: int in range(8):
		var probe := (low + high) * 0.5
		var direction := facing.rotated(deg_to_rad(probe * sign_value))
		if _weapon_ray_is_clear(layout, room, origin, direction):
			low = probe
		else:
			high = probe
	return maxf(low - 0.35, 0.0)


static func _weapon_face_origin(layout: Resource, room: Resource, quarter: int) -> Variant:
	var direction := quarter_direction(quarter)
	var occupied := layout_cells(layout)
	var edge_centers: Array[Vector2] = []
	for cell: Vector2i in room_cells(room):
		if face_contact_strength(layout, cell, direction, occupied) >= 0.999:
			continue
		var rect := logical_cell_rect(cell, cell_offset(layout, cell))
		edge_centers.append(rect.get_center() + Vector2(direction) * 0.5)
	if edge_centers.is_empty():
		return null
	var origin := Vector2.ZERO
	for edge_center: Vector2 in edge_centers:
		origin += edge_center
	return origin / float(edge_centers.size()) + Vector2(direction) * 0.015


static func _weapon_ray_is_clear(
	layout: Resource,
	room: Resource,
	origin: Vector2,
	direction: Vector2
) -> bool:
	if direction.is_zero_approx():
		return false
	direction = direction.normalized()
	var source_cells := {}
	for source_cell: Vector2i in room_cells(room):
		source_cells[source_cell] = true
	var bounds: Rect2i = layout.call("get_occupied_bounds")
	var maximum_distance := maxf(Vector2(bounds.size).length() * 2.0 + 4.0, 8.0)
	for blocker: Resource in layout.get("rooms"):
		if blocker == room:
			continue
		for blocker_cell: Vector2i in room_cells(blocker):
			if source_cells.has(blocker_cell):
				continue
			var blocker_rect := logical_cell_rect(blocker_cell, cell_offset(layout, blocker_cell)).grow(-0.025)
			if _ray_intersects_rect(origin, direction, blocker_rect, maximum_distance):
				return false
	return true


static func _ray_intersects_rect(origin: Vector2, direction: Vector2, rect: Rect2, maximum_distance: float) -> bool:
	var near_time := 0.0
	var far_time := maximum_distance
	for axis: int in range(2):
		var origin_axis := origin[axis]
		var direction_axis := direction[axis]
		var minimum_axis := rect.position[axis]
		var maximum_axis := rect.end[axis]
		if absf(direction_axis) <= 0.00001:
			if origin_axis < minimum_axis or origin_axis > maximum_axis:
				return false
			continue
		var first_time := (minimum_axis - origin_axis) / direction_axis
		var second_time := (maximum_axis - origin_axis) / direction_axis
		if first_time > second_time:
			var swap := first_time
			first_time = second_time
			second_time = swap
		near_time = maxf(near_time, first_time)
		far_time = minf(far_time, second_time)
		if near_time > far_time:
			return false
	return far_time >= maxf(near_time, 0.0)


static func exterior_profile_is_exposed(room: Resource, cell: Vector2i, hull_cells: Dictionary, layout: Resource = null) -> bool:
	var room_type := String(room.get("type_name"))
	if not has_exterior_profile(room_type):
		return false
	if room_type in ["COMMAND", "BRIDGE"] and room_type != "BRIDGE" and not String(room.get("display_name")).to_upper().contains("BRIDGE"):
		return false
	if layout == null:
		return not hull_cells.has(cell + quarter_direction(exterior_facing_quarters(room)))
	return face_contact_strength(layout, cell, quarter_direction(exterior_facing_quarters(room)), hull_cells) < 0.999


## Returns contiguous exposed portions of a room's business-facing edge.
## The construction lattice may divide one module into several cells, but its
## bridge nose, exhaust crown, or hangar mouth must be authored once per span.
static func exterior_face_spans(room: Resource, hull_cells: Dictionary, layout: Resource = null) -> Array[Rect2i]:
	var spans: Array[Rect2i] = []
	if room == null or not has_exterior_profile(String(room.get("type_name"))):
		return spans
	var exposed: Dictionary = {}
	for cell: Vector2i in room_cells(room):
		if exterior_profile_is_exposed(room, cell, hull_cells, layout):
			exposed[cell] = true
	var direction := quarter_direction(exterior_facing_quarters(room))
	var tangent := Vector2i.RIGHT if direction.y != 0 else Vector2i.DOWN
	while not exposed.is_empty():
		var start: Vector2i = exposed.keys()[0]
		var first := start
		while exposed.has(first - tangent):
			first -= tangent
		var last := first
		exposed.erase(last)
		while exposed.has(last + tangent):
			last += tangent
			exposed.erase(last)
		if tangent.x != 0:
			spans.append(Rect2i(first, Vector2i(last.x - first.x + 1, 1)))
		else:
			spans.append(Rect2i(first, Vector2i(1, last.y - first.y + 1)))
	return spans


## Straight cell boundaries on these faces are replaced by authored exterior
## profiles. Renderers use this map so the hull is one path, not two overlays.
static func exterior_replaced_edge_keys(rooms: Array, hull_cells: Dictionary, layout: Resource = null) -> Dictionary:
	var replaced: Dictionary = {}
	for room: Resource in rooms:
		if not has_exterior_profile(String(room.get("type_name"))):
			continue
		var facing := exterior_facing_quarters(room)
		for cell: Vector2i in room_cells(room):
			if exterior_profile_is_exposed(room, cell, hull_cells, layout):
				replaced[Vector3i(cell.x, cell.y, facing)] = true
	return replaced


static func exterior_edge_key(cell: Vector2i, normal: Vector2) -> Vector3i:
	var direction := Vector2i(roundi(normal.x), roundi(normal.y))
	var facing := 0
	if direction == Vector2i.RIGHT:
		facing = 1
	elif direction == Vector2i.DOWN:
		facing = 2
	elif direction == Vector2i.LEFT:
		facing = 3
	return Vector3i(cell.x, cell.y, facing)


static func exterior_cell_polygon(rect: Rect2, room_type: String, facing_quarters: int) -> PackedVector2Array:
	var normalized_points: Array[Vector2] = []
	if room_type in ["COMMAND", "BRIDGE"]:
		normalized_points = [
			Vector2(0.0, 1.0),
			Vector2(0.0, 0.0),
			Vector2(0.5, -0.38),
			Vector2(1.0, 0.0),
			Vector2(1.0, 1.0),
		]
	elif room_type == "PROPULSION":
		normalized_points = [
			Vector2(0.0, 1.0),
			Vector2(0.0, 0.0),
			Vector2(0.16, 0.0),
			Vector2(0.16, -0.18),
			Vector2(0.36, -0.18),
			Vector2(0.36, 0.0),
			Vector2(0.64, 0.0),
			Vector2(0.64, -0.18),
			Vector2(0.84, -0.18),
			Vector2(0.84, 0.0),
			Vector2(1.0, 0.0),
			Vector2(1.0, 1.0),
		]
	elif room_type == "HANGAR":
		normalized_points = [
			Vector2(0.0, 1.0),
			Vector2(0.0, 0.0),
			Vector2(1.0, 0.0),
			Vector2(1.0, 1.0),
		]
	else:
		return PackedVector2Array()
	return _transform_normalized_profile(normalized_points, rect, facing_quarters)


static func exterior_edge_profile(rect: Rect2, room_type: String, facing_quarters: int) -> PackedVector2Array:
	var normalized_points: Array[Vector2] = []
	if room_type in ["COMMAND", "BRIDGE"]:
		normalized_points = [Vector2(0.0, 0.0), Vector2(0.5, -0.38), Vector2(1.0, 0.0)]
	elif room_type == "PROPULSION":
		normalized_points = [
			Vector2(0.0, 0.0),
			Vector2(0.16, 0.0),
			Vector2(0.16, -0.18),
			Vector2(0.36, -0.18),
			Vector2(0.36, 0.0),
			Vector2(0.64, 0.0),
			Vector2(0.64, -0.18),
			Vector2(0.84, -0.18),
			Vector2(0.84, 0.0),
			Vector2(1.0, 0.0),
		]
	elif room_type == "HANGAR":
		normalized_points = [
			Vector2(0.0, 0.0),
			Vector2(0.16, 0.0),
			Vector2(0.3, 0.2),
			Vector2(0.7, 0.2),
			Vector2(0.84, 0.0),
			Vector2(1.0, 0.0),
		]
	else:
		return PackedVector2Array()
	return _transform_normalized_profile(normalized_points, rect, facing_quarters)


static func exterior_aperture_polygon(rect: Rect2, room_type: String, facing_quarters: int) -> PackedVector2Array:
	if room_type != "HANGAR":
		return PackedVector2Array()
	var normalized_points: Array[Vector2] = [
		Vector2(0.16, -0.02),
		Vector2(0.84, -0.02),
		Vector2(0.7, 0.2),
		Vector2(0.3, 0.2),
	]
	return _transform_normalized_profile(normalized_points, rect, facing_quarters)


static func _transform_normalized_profile(points: Array[Vector2], rect: Rect2, facing_quarters: int) -> PackedVector2Array:
	var transformed := PackedVector2Array()
	# Profiles are authored as an UP-facing edge: X travels along the hull face
	# and Y travels inward (negative Y therefore projects outside the hull). A
	# simple rotation of a non-square span swaps neither of those dimensions,
	# making side-facing profiles use the full room height as their projection
	# depth. Build a cardinal face-local basis instead so tangent length and hull
	# depth remain correct for every orientation.
	var face_origin := rect.position
	var tangent := Vector2.RIGHT * rect.size.x
	var inward := Vector2.DOWN * rect.size.y
	match posmod(facing_quarters, 4):
		1:
			face_origin = Vector2(rect.end.x, rect.position.y)
			tangent = Vector2.DOWN * rect.size.y
			inward = Vector2.LEFT * rect.size.x
		2:
			face_origin = rect.end
			tangent = Vector2.LEFT * rect.size.x
			inward = Vector2.UP * rect.size.y
		3:
			face_origin = Vector2(rect.position.x, rect.end.y)
			tangent = Vector2.UP * rect.size.y
			inward = Vector2.RIGHT * rect.size.x
	for point: Vector2 in points:
		transformed.append(face_origin + tangent * point.x + inward * point.y)
	return transformed


static func cell_at_position(layout: Resource, local_position: Vector2, bounds: Rect2i, cell_size: float, origin: Vector2 = Vector2.ZERO, placement_offset: int = -1) -> Vector2i:
	for y: int in range(bounds.position.y, bounds.end.y):
		var relative: Vector2 = (local_position - origin) / cell_size
		var forced_offset := Vector2(0.5, 0.0) if placement_offset == 1 else Vector2.ZERO
		var x: int = floori(relative.x - forced_offset.x) + bounds.position.x
		var candidate: Vector2i = Vector2i(x, y)
		var candidate_rect := cell_rect(layout, candidate, bounds, cell_size, origin)
		if placement_offset >= 0:
			candidate_rect.position = origin + (Vector2(candidate - bounds.position) + forced_offset) * cell_size
		if bounds.has_point(candidate) and candidate_rect.has_point(local_position):
			return candidate
	return Vector2i(2147483647, 2147483647)


static func contact_strength(layout: Resource, first: Vector2i, second: Vector2i) -> float:
	if first == second:
		return 0.0
	if _uses_uniform_quarter_lattice(layout):
		return 1.0 if abs(first.x - second.x) + abs(first.y - second.y) == 1 else 0.0
	var a: Rect2 = logical_cell_rect(first, cell_offset(layout, first))
	var b: Rect2 = logical_cell_rect(second, cell_offset(layout, second))
	if is_equal_approx(a.end.x, b.position.x) or is_equal_approx(b.end.x, a.position.x):
		return maxf(0.0, minf(a.end.y, b.end.y) - maxf(a.position.y, b.position.y))
	if is_equal_approx(a.end.y, b.position.y) or is_equal_approx(b.end.y, a.position.y):
		return maxf(0.0, minf(a.end.x, b.end.x) - maxf(a.position.x, b.position.x))
	return 0.0


static func face_contact_strength(layout: Resource, cell: Vector2i, direction: Vector2i, occupied_cells: Dictionary = {}) -> float:
	var occupied := occupied_cells if not occupied_cells.is_empty() else layout_cells(layout)
	if _uses_uniform_quarter_lattice(layout):
		return 1.0 if occupied.has(cell + direction) else 0.0
	var source := logical_cell_rect(cell, cell_offset(layout, cell))
	var total := 0.0
	for other_value: Variant in occupied.keys():
		var other := other_value as Vector2i
		if other == cell:
			continue
		var target := logical_cell_rect(other, cell_offset(layout, other))
		if direction == Vector2i.RIGHT and is_equal_approx(source.end.x, target.position.x):
			total += maxf(0.0, minf(source.end.y, target.end.y) - maxf(source.position.y, target.position.y))
		elif direction == Vector2i.LEFT and is_equal_approx(source.position.x, target.end.x):
			total += maxf(0.0, minf(source.end.y, target.end.y) - maxf(source.position.y, target.position.y))
		elif direction == Vector2i.DOWN and is_equal_approx(source.end.y, target.position.y):
			total += maxf(0.0, minf(source.end.x, target.end.x) - maxf(source.position.x, target.position.x))
		elif direction == Vector2i.UP and is_equal_approx(source.position.y, target.end.y):
			total += maxf(0.0, minf(source.end.x, target.end.x) - maxf(source.position.x, target.position.x))
	return minf(total, 1.0)


static func touching_neighbors(layout: Resource, cell: Vector2i, include_diagonals: bool = false) -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	if _uses_uniform_quarter_lattice(layout):
		for direction: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			results.append({"cell": cell + direction, "strength": 1.0, "diagonal": false})
		if include_diagonals:
			for diagonal: Vector2i in [Vector2i(-1, -1), Vector2i(1, -1), Vector2i(1, 1), Vector2i(-1, 1)]:
				results.append({"cell": cell + diagonal, "strength": 0.0, "diagonal": true})
		return results
	for y: int in range(cell.y - 1, cell.y + 2):
		for x: int in range(cell.x - 1, cell.x + 2):
			var other: Vector2i = Vector2i(x, y)
			if other == cell:
				continue
			var strength: float = contact_strength(layout, cell, other)
			if strength > 0.0:
				results.append({"cell": other, "strength": strength, "diagonal": false})
			elif include_diagonals and abs(x - cell.x) == 1 and abs(y - cell.y) == 1:
				results.append({"cell": other, "strength": 0.0, "diagonal": true})
	return results


static func boundary_segments(layout: Resource, occupied_cells: Dictionary, bounds: Rect2i, cell_size: float, origin: Vector2 = Vector2.ZERO) -> Array[Dictionary]:
	if _uses_uniform_quarter_lattice(layout):
		return _uniform_boundary_segments(occupied_cells, bounds, cell_size, origin)
	var segments: Array[Dictionary] = []
	for cell_value: Variant in occupied_cells.keys():
		var cell: Vector2i = cell_value
		var rect: Rect2 = cell_rect(layout, cell, bounds, cell_size, origin)
		_append_exposed_horizontal(segments, occupied_cells, layout, cell, rect, true)
		_append_exposed_horizontal(segments, occupied_cells, layout, cell, rect, false)
		_append_exposed_vertical(segments, occupied_cells, layout, cell, rect, true)
		_append_exposed_vertical(segments, occupied_cells, layout, cell, rect, false)
	return segments


static func _uniform_boundary_segments(occupied_cells: Dictionary, bounds: Rect2i, cell_size: float, origin: Vector2) -> Array[Dictionary]:
	var segments: Array[Dictionary] = []
	for cell_value: Variant in occupied_cells.keys():
		var cell: Vector2i = cell_value
		var position := origin + Vector2(cell - bounds.position) * cell_size
		var end := position + Vector2.ONE * cell_size
		if not occupied_cells.has(cell + Vector2i.UP):
			segments.append({"cell": cell, "start": position, "end": Vector2(end.x, position.y), "normal": Vector2.UP})
		if not occupied_cells.has(cell + Vector2i.DOWN):
			segments.append({"cell": cell, "start": Vector2(position.x, end.y), "end": end, "normal": Vector2.DOWN})
		if not occupied_cells.has(cell + Vector2i.LEFT):
			segments.append({"cell": cell, "start": position, "end": Vector2(position.x, end.y), "normal": Vector2.LEFT})
		if not occupied_cells.has(cell + Vector2i.RIGHT):
			segments.append({"cell": cell, "start": Vector2(end.x, position.y), "end": end, "normal": Vector2.RIGHT})
	return segments


static func _uses_uniform_quarter_lattice(layout: Resource) -> bool:
	return layout != null and int(layout.get("lattice_version")) >= 2


static func _append_exposed_horizontal(segments: Array[Dictionary], occupied: Dictionary, layout: Resource, cell: Vector2i, rect: Rect2, top: bool) -> void:
	var y: float = rect.position.y if top else rect.end.y
	var intervals: Array[Vector2] = [Vector2(rect.position.x, rect.end.x)]
	for entry: Dictionary in touching_neighbors(layout, cell):
		var other: Vector2i = entry["cell"]
		if not occupied.has(other) or (top and other.y >= cell.y) or (not top and other.y <= cell.y):
			continue
		var other_rect: Rect2 = cell_rect(layout, other, Rect2i(Vector2i.ZERO, Vector2i.ONE), rect.size.x)
		var own_rect: Rect2 = cell_rect(layout, cell, Rect2i(Vector2i.ZERO, Vector2i.ONE), rect.size.x)
		var shift: Vector2 = rect.position - own_rect.position
		intervals = _subtract_interval(intervals, other_rect.position.x + shift.x, other_rect.end.x + shift.x)
	for interval: Vector2 in intervals:
		segments.append({"cell": cell, "start": Vector2(interval.x, y), "end": Vector2(interval.y, y), "normal": Vector2.UP if top else Vector2.DOWN})


static func _append_exposed_vertical(segments: Array[Dictionary], occupied: Dictionary, layout: Resource, cell: Vector2i, rect: Rect2, left: bool) -> void:
	var x: float = rect.position.x if left else rect.end.x
	var intervals: Array[Vector2] = [Vector2(rect.position.y, rect.end.y)]
	for entry: Dictionary in touching_neighbors(layout, cell):
		var other: Vector2i = entry["cell"]
		if not occupied.has(other) or (left and other.x >= cell.x) or (not left and other.x <= cell.x):
			continue
		var other_rect: Rect2 = cell_rect(layout, other, Rect2i(Vector2i.ZERO, Vector2i.ONE), rect.size.x)
		var own_rect: Rect2 = cell_rect(layout, cell, Rect2i(Vector2i.ZERO, Vector2i.ONE), rect.size.x)
		var shift: Vector2 = rect.position - own_rect.position
		intervals = _subtract_interval(intervals, other_rect.position.y + shift.y, other_rect.end.y + shift.y)
	for interval: Vector2 in intervals:
		segments.append({"cell": cell, "start": Vector2(x, interval.x), "end": Vector2(x, interval.y), "normal": Vector2.LEFT if left else Vector2.RIGHT})


static func _subtract_interval(intervals: Array[Vector2], cut_start: float, cut_end: float) -> Array[Vector2]:
	var result: Array[Vector2] = []
	for interval: Vector2 in intervals:
		if cut_end <= interval.x or cut_start >= interval.y:
			result.append(interval)
			continue
		if cut_start > interval.x:
			result.append(Vector2(interval.x, minf(cut_start, interval.y)))
		if cut_end < interval.y:
			result.append(Vector2(maxf(cut_end, interval.x), interval.y))
	return result
