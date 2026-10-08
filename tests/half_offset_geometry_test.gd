extends SceneTree

const GRID_GEOMETRY := preload("res://scripts/grid_geometry.gd")
const SHIP_LAYOUT := preload("res://scripts/resources/ship_layout_resource.gd")
const ROOM_LAYOUT := preload("res://scripts/resources/room_layout_data.gd")
const STRUCTURAL_MATERIAL := preload("res://resources/default_structural_material.tres")
const DOOR_DEFINITION := preload("res://resources/default_door_definition.tres")


func _initialize() -> void:
	var layout: Resource = _make_offset_fixture()
	var failures := PackedStringArray()
	if (layout.get("offset_cells") as Array).is_empty():
		failures.append("fixture has no horizontal half-offset cells")
	if (layout.get("vertical_offset_cells") as Array).is_empty():
		failures.append("fixture has no vertical half-offset cells")
	var structure := ShipStructuralState.new()
	structure.configure(layout, STRUCTURAL_MATERIAL, DOOR_DEFINITION)
	var occupied := GRID_GEOMETRY.layout_cells(layout)
	var checked_pairs: Dictionary = {}
	var physical_connections := 0
	for cell_value: Variant in occupied.keys():
		var cell := cell_value as Vector2i
		for connection: Dictionary in GRID_GEOMETRY.touching_neighbors(layout, cell):
			var neighbor: Vector2i = connection["cell"]
			if not occupied.has(neighbor):
				continue
			var pair := [cell, neighbor]
			pair.sort()
			var pair_key := "%s|%s" % [pair[0], pair[1]]
			if checked_pairs.has(pair_key):
				continue
			checked_pairs[pair_key] = true
			physical_connections += 1
			var first_room: StringName = structure.cell_rooms.get(cell, &"")
			var second_room: StringName = structure.cell_rooms.get(neighbor, &"")
			if first_room != second_room and not _rooms_have_door(structure, first_room, second_room):
				failures.append("missing door across staggered connection %s -> %s" % [cell, neighbor])
	if physical_connections <= 0:
		failures.append("fixture produced no physical shared-edge connections")
	for door_value: Variant in structure.doors.values():
		var door: Dictionary = door_value
		var door_id := String(door.get("id", ""))
		var door_cells: Array = door.get("cells", [])
		if door_cells.size() < 2:
			continue
		var first_cell: Vector2i = door_cells[0]
		var second_cell: Vector2i = door_cells[1]
		var first_approach := structure.get_door_approach_point(door_id, first_cell, 0.14)
		var second_approach := structure.get_door_approach_point(door_id, second_cell, 0.14)
		var center := structure.get_door_center(door_id)
		var first_crossing := structure.constrain_crew_motion(first_approach, center, first_cell, second_cell, 0.08, door_id)
		var second_crossing := structure.constrain_crew_motion(second_approach, center, second_cell, first_cell, 0.08, door_id)
		if first_crossing.is_equal_approx(first_approach):
			failures.append("door aperture blocks crossing from %s through %s" % [first_cell, door_id])
		if second_crossing.is_equal_approx(second_approach):
			failures.append("door aperture blocks crossing from %s through %s" % [second_cell, door_id])
	if not failures.is_empty():
		for failure: String in failures:
			push_error("HALF-OFFSET TEST // %s" % failure)
		quit(1)
		return
	print("HALF-OFFSET TEST // PASS // %d PHYSICAL CONNECTIONS // %d DOORS" % [physical_connections, structure.doors.size()])
	quit()


func _make_offset_fixture() -> Resource:
	# Explicit legacy geometry keeps this regression independent of player saves.
	# Each shifted cell shares partial edges with two separate neighboring rooms.
	var layout := SHIP_LAYOUT.new()
	layout.lattice_version = 1
	layout.offset_cells = [Vector2i(0, 1)]
	layout.vertical_offset_cells = [Vector2i(5, 0)]
	var cells: Array[Vector2i] = [
		Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1),
		Vector2i(4, 0), Vector2i(4, 1), Vector2i(5, 0),
	]
	for index: int in range(cells.size()):
		var room := ROOM_LAYOUT.new()
		room.room_id = StringName("offset_room_%d" % index)
		room.type_name = "CREW_QUARTERS"
		room.grid_rects = [Rect2i(cells[index], Vector2i.ONE)]
		layout.rooms.append(room)
	return layout


func _rooms_have_door(structure: ShipStructuralState, first_room: StringName, second_room: StringName) -> bool:
	for door_value: Variant in structure.doors.values():
		var door: Dictionary = door_value
		var door_cells: Array = door.get("cells", [])
		if door_cells.size() < 2:
			continue
		var door_first: StringName = structure.cell_rooms.get(door_cells[0], &"")
		var door_second: StringName = structure.cell_rooms.get(door_cells[1], &"")
		if (door_first == first_room and door_second == second_room) or (door_first == second_room and door_second == first_room):
			return true
	return false
