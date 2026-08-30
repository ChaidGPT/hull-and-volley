@tool
class_name ShipLayoutResource
extends Resource

const ADJACENCY_EVALUATOR := preload("res://scripts/grid_adjacency_evaluator.gd")
const GRID_GEOMETRY := preload("res://scripts/grid_geometry.gd")
const CLEAR_FACING_ROOM_TYPES := ["COMMAND", "BRIDGE", "PROPULSION", "HANGAR", "WEAPONS", "SHIELDS"]

@export_category("Design Identity")
## Friendly blueprint name used by the Shipyard creator and sample ship authoring tools.
@export var design_name := "Unnamed Hull"
## Broad construction class. Existing blueprints remain ships by default.
@export_enum("SHIP", "STATION") var vessel_kind := "SHIP"

@export_category("Build Envelope")
## Current construction-coordinate density. Version 2 uses a consistent
## 2x2 lattice inside every original full-size grid cell.
@export_range(1, 2, 1) var lattice_version := 1
## Individual occupied cells shifted half a grid space horizontally. Players may mix regular and offset cells freely.
@export var offset_cells: Array[Vector2i] = []
## Individual occupied cells shifted half a grid space vertically.
@export var vertical_offset_cells: Array[Vector2i] = []
## Top-left logical coordinate of the finite construction area available to the player.
@export var build_origin := Vector2i.ZERO
## Number of buildable columns currently unlocked. Progression may increase this value.
@export_range(1, 64, 1) var columns := 6
## Number of buildable rows currently unlocked. Progression may increase this value.
@export_range(1, 128, 1) var rows := 12
## During the current prototype the hull workbench has no hard construction
## boundary. The displayed lattice follows the occupied hull, but placement is
## valid at any coordinate that satisfies overlap and attachment rules.
@export var unlimited_build_space := true
## The cells present when a run ship is commissioned. This permanent keel is
## independent of room grouping, so later-combined rooms may contain both core
## and detachable extension pieces without losing their identity.
@export var core_frame_cells: Array[Vector2i] = []
@export var core_frame_initialized := false
@export var room_types: Array[Resource] = []
@export var weapon_types: Array[Resource] = []
@export var module_recipes: Array[Resource] = []
## Catalog of commodities that recipes, inventories, salvage, and trade may reference.
@export var resource_catalog: Resource
@export var rooms: Array[Resource] = []


## Converts a legacy whole/half-offset layout to the quarter-module lattice.
## Each old cell becomes 2x2 lattice cells, preserving its exact physical size
## and any authored half-cell displacement. The operation is idempotent.
func ensure_quarter_lattice() -> void:
	if lattice_version >= 2:
		return
	for room: Resource in rooms:
		var migrated_rects: Array[Rect2i] = []
		for old_rect: Rect2i in room.get("grid_rects"):
			for y: int in range(old_rect.position.y, old_rect.end.y):
				for x: int in range(old_rect.position.x, old_rect.end.x):
					var old_cell := Vector2i(x, y)
					var old_offset := get_cell_offset(old_cell)
					var lattice_origin := old_cell * 2 + Vector2i(roundi(old_offset.x * 2.0), roundi(old_offset.y * 2.0))
					migrated_rects.append(Rect2i(lattice_origin, Vector2i(2, 2)))
		room.set("grid_rects", migrated_rects)
		if "build_footprint_lattice" in room:
			room.set("build_footprint_lattice", Vector2i(2, 2))
	build_origin *= 2
	columns *= 2
	rows *= 2
	if not core_frame_cells.is_empty():
		var migrated_core: Array[Vector2i] = []
		for old_core_cell: Vector2i in core_frame_cells:
			var origin := old_core_cell * 2
			for y: int in range(2):
				for x: int in range(2):
					migrated_core.append(origin + Vector2i(x, y))
		core_frame_cells = migrated_core
	offset_cells.clear()
	vertical_offset_cells.clear()
	lattice_version = 2
	emit_changed()


func get_build_bounds() -> Rect2i:
	if unlimited_build_space:
		var occupied := get_occupied_bounds(false)
		if occupied.size.x > 0 and occupied.size.y > 0:
			const DISPLAY_MARGIN := 4
			return occupied.grow(DISPLAY_MARGIN)
	return Rect2i(build_origin, Vector2i(columns, rows))


func is_cell_buildable(cell: Vector2i) -> bool:
	if unlimited_build_space:
		return true
	return get_build_bounds().has_point(cell)


func is_cell_offset(cell: Vector2i) -> bool:
	return offset_cells.has(cell) or vertical_offset_cells.has(cell)


func get_cell_offset(cell: Vector2i) -> Vector2:
	return Vector2(0.5 if offset_cells.has(cell) else 0.0, 0.5 if vertical_offset_cells.has(cell) else 0.0)


## Sets one cell's optional half-grid horizontal offset.
func set_cell_offset(cell: Vector2i, offset: Vector2) -> void:
	offset_cells.erase(cell)
	vertical_offset_cells.erase(cell)
	if offset.x >= 0.25:
		offset_cells.append(cell)
	if offset.y >= 0.25:
		vertical_offset_cells.append(cell)
	emit_changed()


## Removes offset records for cells that no longer contain hull.
func prune_unused_cell_offsets() -> void:
	var occupied: Dictionary = {}
	for room: Resource in rooms:
		for rect: Rect2i in room.get("grid_rects"):
			for y: int in range(rect.position.y, rect.end.y):
				for x: int in range(rect.position.x, rect.end.x):
					occupied[Vector2i(x, y)] = true
	for index: int in range(offset_cells.size() - 1, -1, -1):
		if not occupied.has(offset_cells[index]):
			offset_cells.remove_at(index)
	for index: int in range(vertical_offset_cells.size() - 1, -1, -1):
		if not occupied.has(vertical_offset_cells[index]):
			vertical_offset_cells.remove_at(index)


## Checks whether a regular or half-offset cell would physically overlap the existing hull.
func can_place_cell(cell: Vector2i, offset: Vector2) -> bool:
	return can_place_footprint(cell, Vector2i.ONE, offset)


## Checks a rectangular module footprint on the unified lattice.
func can_place_footprint(cell: Vector2i, footprint: Vector2i, offset: Vector2 = Vector2.ZERO) -> bool:
	if footprint.x < 1 or footprint.y < 1:
		return false
	var candidate_bounds := Rect2i(cell, footprint)
	if not unlimited_build_space:
		var build_bounds := get_build_bounds()
		if not build_bounds.encloses(candidate_bounds):
			return false
		if not is_cell_buildable(cell):
			return false
	var candidate := Rect2(Vector2(cell) + offset, Vector2(footprint))
	for room: Resource in rooms:
		for rect: Rect2i in room.get("grid_rects"):
			for y: int in range(rect.position.y, rect.end.y):
				for x: int in range(rect.position.x, rect.end.x):
					var occupied_cell := Vector2i(x, y)
					var existing := GRID_GEOMETRY.logical_cell_rect(occupied_cell, get_cell_offset(occupied_cell))
					var overlap := candidate.intersection(existing)
					if overlap.size.x > 0.001 and overlap.size.y > 0.001:
						return false
	return true


## Protects physical exhaust and launch lanes. These exterior faces must remain
## open until the player deliberately rotates the affected compartment.
func evaluate_cell_exterior_clearance(
	room_type: String,
	cell: Vector2i,
	placement_offset: Vector2 = Vector2.ZERO,
	footprint: Vector2i = Vector2i.ONE
) -> Dictionary:
	var candidate_rect := Rect2(Vector2(cell) + placement_offset, Vector2(footprint))
	for room: Resource in rooms:
		if not String(room.get("type_name")) in CLEAR_FACING_ROOM_TYPES:
			continue
		var direction := GRID_GEOMETRY.quarter_direction(GRID_GEOMETRY.exterior_facing_quarters(room))
		for source_cell: Vector2i in GRID_GEOMETRY.room_cells(room):
			var source_rect := GRID_GEOMETRY.logical_cell_rect(source_cell, get_cell_offset(source_cell))
			if _rect_touches_face(source_rect, candidate_rect, direction):
				return {
					"valid": false,
					"message": "%s BLOCKED • ROTATE %s FIRST" % [
						_facing_lane_name(String(room.get("type_name"))),
						String(room.get("display_name")).to_upper(),
					],
					"blocker": room,
				}
	if room_type in CLEAR_FACING_ROOM_TYPES:
		var facing := _default_facing_for_room_type(room_type)
		if room_type in ["WEAPONS", "SHIELDS"]:
			var open_facing := _first_open_facing(cell, placement_offset, facing, footprint)
			if open_facing < 0:
				return {
					"valid": false,
					"message": "%s REQUIRES AN EXPOSED HULL EDGE" % (
						"SHIELD EMITTER" if room_type == "SHIELDS" else "WEAPON MOUNT"
					),
					"blocker": null,
					"facing": -1,
				}
			return {"valid": true, "message": "", "blocker": null, "facing": open_facing}
		var target_room := _room_touching_candidate_face(candidate_rect, GRID_GEOMETRY.quarter_direction(facing))
		if target_room != null:
			return {
				"valid": false,
				"message": "%s MUST FACE OPEN SPACE • %s BLOCKS THE LANE" % [
					_facing_system_name(room_type),
					String(target_room.get("display_name")).to_upper(),
				],
				"blocker": target_room,
				"facing": facing,
			}
		return {"valid": true, "message": "", "blocker": null, "facing": facing}
	return {"valid": true, "message": "", "blocker": null, "facing": -1}


func evaluate_room_facing_clearance(room: Resource, facing_quarters: int) -> Dictionary:
	if room == null or not String(room.get("type_name")) in CLEAR_FACING_ROOM_TYPES:
		return {"valid": true, "message": "", "blocker": null}
	var room_cells: Array[Vector2i] = GRID_GEOMETRY.room_cells(room)
	var own_cells: Dictionary = {}
	for own_cell: Vector2i in room_cells:
		own_cells[own_cell] = true
	var direction := GRID_GEOMETRY.quarter_direction(facing_quarters)
	for source_cell: Vector2i in room_cells:
		var source_rect := GRID_GEOMETRY.logical_cell_rect(source_cell, get_cell_offset(source_cell))
		# `room` may be a one-mount proxy duplicated from a combined compartment.
		# Comparing only the Resource instance made the real parent room block the
		# proxy with its own cells on every side. Ignore this mount's footprint,
		# while still allowing sibling mounts in the same room to block the lane.
		var target_room := _room_touching_candidate_face(source_rect, direction, null, own_cells)
		if target_room != null:
			return {
				"valid": false,
				"message": "%s BLOCKED BY %s • CLEAR THE LANE BEFORE ROTATING" % [
					_facing_lane_name(String(room.get("type_name"))),
					String(target_room.get("display_name")).to_upper(),
				],
				"blocker": target_room,
			}
	return {"valid": true, "message": "", "blocker": null}


func _first_open_facing(cell: Vector2i, placement_offset: Vector2, preferred_facing: int, footprint: Vector2i = Vector2i.ONE) -> int:
	var candidate_rect := Rect2(Vector2(cell) + placement_offset, Vector2(footprint))
	for offset: int in range(4):
		var facing := posmod(preferred_facing + offset, 4)
		if _candidate_face_contact_strength(candidate_rect, GRID_GEOMETRY.quarter_direction(facing)) < 0.999:
			return facing
	return -1


func _facing_system_name(room_type: String) -> String:
	match room_type:
		"PROPULSION":
			return "THRUSTER"
		"HANGAR":
			return "HANGAR"
		"WEAPONS":
			return "WEAPON"
		"SHIELDS":
			return "SHIELD EMITTER"
		"COMMAND", "BRIDGE":
			return "BRIDGE BOW"
		_:
			return "MODULE"


func _facing_lane_name(room_type: String) -> String:
	match room_type:
		"PROPULSION":
			return "EXHAUST"
		"HANGAR":
			return "LAUNCH BAY"
		"WEAPONS":
			return "FIRING ARC"
		"SHIELDS":
			return "SHIELD EMITTER LANE"
		"COMMAND", "BRIDGE":
			return "BRIDGE BOW"
		_:
			return "MODULE LANE"


func _default_facing_for_room_type(room_type: String) -> int:
	for template: Resource in room_types:
		if String(template.get("type_name")) != room_type:
			continue
		var authored_facing := int(template.get("module_facing_quarters"))
		if authored_facing >= 0:
			return posmod(authored_facing, 4)
	return 2 if room_type == "PROPULSION" else 0


func _room_at_cell(cell: Vector2i) -> Resource:
	for room: Resource in rooms:
		for room_cell: Vector2i in GRID_GEOMETRY.room_cells(room):
			if room_cell == cell:
				return room
	return null


func _room_touching_candidate_face(
	source_rect: Rect2,
	direction: Vector2i,
	ignored_room: Resource = null,
	ignored_cells: Dictionary = {}
) -> Resource:
	for room: Resource in rooms:
		if room == ignored_room:
			continue
		for room_cell: Vector2i in GRID_GEOMETRY.room_cells(room):
			if ignored_cells.has(room_cell):
				continue
			var target_rect := GRID_GEOMETRY.logical_cell_rect(room_cell, get_cell_offset(room_cell))
			if _rect_touches_face(source_rect, target_rect, direction):
				return room
	return null


func _candidate_face_contact_strength(source_rect: Rect2, direction: Vector2i, ignored_room: Resource = null) -> float:
	var total := 0.0
	for room: Resource in rooms:
		if room == ignored_room:
			continue
		for room_cell: Vector2i in GRID_GEOMETRY.room_cells(room):
			var target_rect := GRID_GEOMETRY.logical_cell_rect(room_cell, get_cell_offset(room_cell))
			if not _rect_touches_face(source_rect, target_rect, direction):
				continue
			if direction.x != 0:
				total += maxf(0.0, minf(source_rect.end.y, target_rect.end.y) - maxf(source_rect.position.y, target_rect.position.y))
			else:
				total += maxf(0.0, minf(source_rect.end.x, target_rect.end.x) - maxf(source_rect.position.x, target_rect.position.x))
	var face_length := source_rect.size.y if direction.x != 0 else source_rect.size.x
	return clampf(total / maxf(face_length, 0.001), 0.0, 1.0)


func _rect_touches_face(source_rect: Rect2, target_rect: Rect2, direction: Vector2i) -> bool:
	if direction == Vector2i.RIGHT and not is_equal_approx(source_rect.end.x, target_rect.position.x):
		return false
	if direction == Vector2i.LEFT and not is_equal_approx(source_rect.position.x, target_rect.end.x):
		return false
	if direction == Vector2i.DOWN and not is_equal_approx(source_rect.end.y, target_rect.position.y):
		return false
	if direction == Vector2i.UP and not is_equal_approx(source_rect.position.y, target_rect.end.y):
		return false
	if direction.x != 0:
		return minf(source_rect.end.y, target_rect.end.y) - maxf(source_rect.position.y, target_rect.position.y) > 0.001
	return minf(source_rect.end.x, target_rect.end.x) - maxf(source_rect.position.x, target_rect.position.x) > 0.001


## Changes the unlocked construction envelope without altering the hull. Returns false if shrinking would cut off occupied cells.
func set_build_envelope(new_origin: Vector2i, new_size: Vector2i) -> bool:
	if new_size.x < 1 or new_size.y < 1:
		return false
	var proposed: Rect2i = Rect2i(new_origin, new_size)
	for room: Resource in rooms:
		for rect: Rect2i in room.get("grid_rects"):
			for y: int in range(rect.position.y, rect.end.y):
				for x: int in range(rect.position.x, rect.end.x):
					if not proposed.has_point(Vector2i(x, y)):
						return false
	build_origin = new_origin
	columns = new_size.x
	rows = new_size.y
	emit_changed()
	return true


## Progression-friendly helper that grows the envelope equally around its existing center where possible.
func expand_build_envelope(extra_columns: int, extra_rows: int) -> void:
	var left: int = floori(maxi(extra_columns, 0) * 0.5)
	var top: int = floori(maxi(extra_rows, 0) * 0.5)
	build_origin -= Vector2i(left, top)
	columns += maxi(extra_columns, 0)
	rows += maxi(extra_rows, 0)
	emit_changed()


func get_touching_cells(cell: Vector2i, include_diagonals: bool = false) -> Array[Dictionary]:
	return GRID_GEOMETRY.touching_neighbors(self, cell, include_diagonals)


func get_occupied_bounds(fallback_to_build_bounds: bool = true) -> Rect2i:
	var has_cells: bool = false
	var minimum: Vector2i = Vector2i.ZERO
	var maximum: Vector2i = Vector2i.ZERO
	for room: Resource in rooms:
		var rects: Array[Rect2i] = room.get("grid_rects")
		for grid_rect: Rect2i in rects:
			if grid_rect.size.x <= 0 or grid_rect.size.y <= 0:
				continue
			if not has_cells:
				minimum = grid_rect.position
				maximum = grid_rect.end
				has_cells = true
			else:
				minimum.x = mini(minimum.x, grid_rect.position.x)
				minimum.y = mini(minimum.y, grid_rect.position.y)
				maximum.x = maxi(maximum.x, grid_rect.end.x)
				maximum.y = maxi(maximum.y, grid_rect.end.y)
	if not has_cells:
		return Rect2i(build_origin, Vector2i(columns, rows)) if fallback_to_build_bounds else Rect2i()
	return Rect2i(minimum, maximum - minimum)


## Locks the currently occupied footprint as the run's permanent keel. Calling
## this again is harmless unless a new run explicitly requests a fresh frame.
func capture_core_frame(force: bool = false) -> void:
	if core_frame_initialized and not force:
		return
	core_frame_cells.clear()
	for room: Resource in rooms:
		for rect: Rect2i in room.get("grid_rects"):
			for y: int in range(rect.position.y, rect.end.y):
				for x: int in range(rect.position.x, rect.end.x):
					core_frame_cells.append(Vector2i(x, y))
	core_frame_initialized = true
	emit_changed()


func is_core_cell(cell: Vector2i) -> bool:
	return core_frame_cells.has(cell)


func is_core_rect(rect: Rect2i) -> bool:
	if rect.size.x <= 0 or rect.size.y <= 0:
		return false
	for y: int in range(rect.position.y, rect.end.y):
		for x: int in range(rect.position.x, rect.end.x):
			if not is_core_cell(Vector2i(x, y)):
				return false
	return true


func rect_contains_core(rect: Rect2i) -> bool:
	for y: int in range(rect.position.y, rect.end.y):
		for x: int in range(rect.position.x, rect.end.x):
			if is_core_cell(Vector2i(x, y)):
				return true
	return false


## Returns all edge-touching sections and, when requested, corner-touching sections for the supplied section.
func get_section_connections(section: Resource, include_diagonals: bool = false) -> Array[Dictionary]:
	return ADJACENCY_EVALUATOR.get_connections(self, section, include_diagonals)


## Checks whether this base grid type may be installed at the supplied cell. This is construction eligibility only, not power or staffing.
func evaluate_grid_type_placement(room_type: String, cell: Vector2i, placement_offset: Vector2 = Vector2.ZERO, footprint: Vector2i = Vector2i.ONE) -> Dictionary:
	return ADJACENCY_EVALUATOR.evaluate_grid_type_placement(self, room_type, cell, placement_offset, footprint)


## Checks only module unlock requirements. Basic grid placement is deliberately always permitted.
func evaluate_module_recipe(section: Resource, recipe: Resource) -> Dictionary:
	return ADJACENCY_EVALUATOR.evaluate_recipe(self, section, recipe)


## Resolves every currently active base-grid and installed-module adjacency effect in the ship.
func collect_adjacency_effects() -> Array[Dictionary]:
	return ADJACENCY_EVALUATOR.collect_layout_effects(self)
