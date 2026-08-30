extends SceneTree

const LAYOUT_SCRIPT := preload("res://scripts/resources/ship_layout_resource.gd")
const ROOM_SCRIPT := preload("res://scripts/resources/room_layout_data.gd")
const STRUCTURAL_MATERIAL := preload("res://resources/default_structural_material.tres")
const DOOR_DEFINITION := preload("res://resources/default_door_definition.tres")
const GRID_GEOMETRY := preload("res://scripts/grid_geometry.gd")
const LEGACY_STARTER := preload("res://resources/ship_designs/barebones_starter.tres")
const BUILDER_SCRIPT := preload("res://scripts/ship_builder_screen.gd")
const BUILDER_ANALYZER := preload("res://scripts/ship_builder_analyzer.gd")
const LIGHT_BALLISTIC := preload("res://resources/module_recipes/light_ballistic_mount.tres")
const SETTLEMENT_GRID := preload("res://scripts/settlement_grid.gd")


func _initialize() -> void:
	var failures := PackedStringArray()
	var legacy_layout: Resource = LEGACY_STARTER.duplicate(true)
	if int(legacy_layout.get("lattice_version")) < 2:
		var legacy_bounds: Rect2i = legacy_layout.call("get_occupied_bounds")
		var legacy_pixels := GRID_GEOMETRY.grid_pixel_size(legacy_layout, legacy_bounds, 20.0)
		legacy_layout.call("ensure_quarter_lattice")
		var migrated_bounds: Rect2i = legacy_layout.call("get_occupied_bounds")
		var migrated_pixels := GRID_GEOMETRY.grid_pixel_size(legacy_layout, migrated_bounds, 10.0)
		if not legacy_pixels.is_equal_approx(migrated_pixels):
			failures.append("legacy hull changed physical size during lattice migration")
	if int(legacy_layout.get("lattice_version")) != 2:
		failures.append("legacy hull did not record quarter-lattice migration")
	var builder: Object = BUILDER_SCRIPT.new()
	if builder.call("_inventory_piece_footprint", "SHIELDS", null, null) != Vector2i.ONE:
		failures.append("directional shield was not classified as quarter-grid")
	if builder.call("_inventory_piece_footprint", "MEDICAL", null, null) != Vector2i(1, 2):
		failures.append("medical room was not classified as long half-grid")
	if builder.call("_inventory_piece_footprint", "WEAPONS", null, LIGHT_BALLISTIC) != Vector2i.ONE:
		failures.append("light ballistic mount was not classified as quarter-grid")
	builder.free()
	var layout: Resource = LAYOUT_SCRIPT.new()
	layout.set("lattice_version", 2)
	layout.set("columns", 8)
	layout.set("rows", 8)
	var full_room := _room(&"full", "CREW_QUARTERS", Rect2i(2, 2, 2, 2))
	var quarter_weapon := _room(&"quarter", "WEAPONS", Rect2i(4, 2, 1, 1))
	var long_medical := _room(&"medical", "MEDICAL", Rect2i(4, 3, 1, 2))
	var test_rooms: Array[Resource] = [full_room, quarter_weapon, long_medical]
	layout.set("rooms", test_rooms)
	var irregular_quarters := _room(&"irregular_quarters", "CREW_QUARTERS", Rect2i(3, 1, 1, 1))
	var irregular_rects: Array[Rect2i] = [Rect2i(3, 1, 1, 1), Rect2i(1, 2, 3, 1)]
	irregular_quarters.set("grid_rects", irregular_rects)
	var gauge_layout: Resource = LAYOUT_SCRIPT.new()
	gauge_layout.set("lattice_version", 2)
	gauge_layout.set("columns", 6)
	gauge_layout.set("rows", 6)
	var gauge_rooms: Array[Resource] = [irregular_quarters]
	gauge_layout.set("rooms", gauge_rooms)
	var gauge_grid: Control = SETTLEMENT_GRID.new()
	gauge_grid.set("ship_layout", gauge_layout)
	var gauge_anchor: Vector2 = gauge_grid.call("_crew_reinforcement_gauge_anchor", irregular_quarters)
	var anchor_is_contained := false
	for gauge_rect: Rect2i in irregular_rects:
		if (gauge_grid.call("_get_grid_rect", gauge_rect) as Rect2).has_point(gauge_anchor):
			anchor_is_contained = true
			break
	if not anchor_is_contained:
		failures.append("crew reinforcement gauge escaped an irregular merged room")
	gauge_grid.free()
	if layout.call("can_place_footprint", Vector2i(5, 2), Vector2i.ONE) != true:
		failures.append("open quarter-grid position was rejected")
	if layout.call("can_place_footprint", Vector2i(3, 2), Vector2i.ONE) != false:
		failures.append("overlapping quarter-grid position was accepted")
	var structure := ShipStructuralState.new()
	structure.configure(layout, STRUCTURAL_MATERIAL, DOOR_DEFINITION)
	if structure.get_door_between_cells(Vector2i(3, 2), Vector2i(4, 2)).is_empty():
		failures.append("quarter weapon has no crew-access door")
	if structure.get_door_between_cells(Vector2i(3, 3), Vector2i(4, 3)).is_empty():
		failures.append("long medical room has no crew-access door")
	if not _route_exists(structure, Vector2i(2, 2), Vector2i(4, 4)):
		failures.append("crew route does not reach the long medical room")
	# Removing a module can turn the same geometric edge from an internal
	# bulkhead into exposed hull. That new hull must not inherit the deleted
	# room edge's damage state merely because its coordinate key is unchanged.
	var refit_layout: Resource = LAYOUT_SCRIPT.new()
	refit_layout.set("lattice_version", 2)
	refit_layout.set("columns", 6)
	refit_layout.set("rows", 6)
	var refit_core := _room(&"refit_core", "CREW_QUARTERS", Rect2i(2, 2, 1, 1))
	var removed_weapon := _room(&"removed_weapon", "WEAPONS", Rect2i(3, 2, 1, 1))
	var refit_rooms: Array[Resource] = [refit_core, removed_weapon]
	refit_layout.set("rooms", refit_rooms)
	var refit_structure := ShipStructuralState.new()
	refit_structure.configure(refit_layout, STRUCTURAL_MATERIAL, DOOR_DEFINITION)
	var converted_wall_key := ""
	for wall_key_value: Variant in refit_structure.walls.keys():
		var wall_key := String(wall_key_value)
		var wall: Dictionary = refit_structure.walls[wall_key]
		if not bool(wall["outer"]) and (wall["cells"] as Array).has(Vector2i(2, 2)) and (wall["cells"] as Array).has(Vector2i(3, 2)):
			converted_wall_key = wall_key
			refit_structure.damage_wall(wall_key, float(wall["maximum"]) * 0.75)
			break
	refit_rooms = [refit_core]
	refit_layout.set("rooms", refit_rooms)
	refit_structure.reconfigure_preserving_state(refit_layout, STRUCTURAL_MATERIAL, DOOR_DEFINITION)
	if converted_wall_key.is_empty() or not refit_structure.walls.has(converted_wall_key):
		failures.append("refit topology regression could not locate converted hull wall")
	else:
		var converted_wall: Dictionary = refit_structure.walls[converted_wall_key]
		if not bool(converted_wall["outer"]) or not is_equal_approx(float(converted_wall["current"]), float(converted_wall["maximum"])):
			failures.append("new outer hull inherited stale damage from a removed weapon bulkhead")
	var bow_layout: Resource = LAYOUT_SCRIPT.new()
	bow_layout.set("lattice_version", 2)
	bow_layout.set("build_origin", Vector2i.ZERO)
	bow_layout.set("columns", 10)
	bow_layout.set("rows", 10)
	var bridge := _room(&"bridge", "COMMAND", Rect2i(3, 3, 2, 2))
	bridge.set("display_name", "BRIDGE")
	bridge.set("module_facing_quarters", 0)
	var bow_rooms: Array[Resource] = [bridge]
	bow_layout.set("rooms", bow_rooms)
	var bridge_spans: Array[Rect2i] = GRID_GEOMETRY.exterior_face_spans(bridge, GRID_GEOMETRY.layout_cells(bow_layout), bow_layout)
	if bridge_spans != [Rect2i(3, 3, 2, 1)]:
		failures.append("solid 2x2 bridge was split into quarter-cell exterior profiles")
	var blocked_bow: Dictionary = bow_layout.call("evaluate_cell_exterior_clearance", "POWER", Vector2i(3, 2), Vector2.ZERO, Vector2i(2, 1))
	if bool(blocked_bow.get("valid", true)):
		failures.append("module placement was allowed across the bridge bow")
	var clear_aft: Dictionary = bow_layout.call("evaluate_cell_exterior_clearance", "POWER", Vector2i(3, 5), Vector2.ZERO, Vector2i(2, 1))
	if not bool(clear_aft.get("valid", false)):
		failures.append("bridge bow clearance incorrectly blocked an aft placement")
	var firing_layout: Resource = LAYOUT_SCRIPT.new()
	firing_layout.set("lattice_version", 2)
	firing_layout.set("columns", 8)
	firing_layout.set("rows", 8)
	var edge_weapon := _room(&"edge_weapon", "WEAPONS", Rect2i(1, 0, 1, 1))
	var lower_hull := _room(&"lower_hull", "CREW_QUARTERS", Rect2i(0, 1, 3, 2))
	var firing_rooms: Array[Resource] = [edge_weapon, lower_hull]
	firing_layout.set("rooms", firing_rooms)
	var right_clearance: Vector2 = GRID_GEOMETRY.weapon_face_clearance_degrees(
		firing_layout, edge_weapon, 1, 45.0
	)
	if right_clearance.x > -44.0:
		failures.append("clear upper weapon traverse was incorrectly clipped")
	if right_clearance.y >= 40.0 or right_clearance.y <= 15.0:
		failures.append("lower hull did not clip the weapon traverse to its clear tangent")
	var battery_layout: Resource = LAYOUT_SCRIPT.new()
	battery_layout.set("lattice_version", 2)
	battery_layout.set("columns", 8)
	battery_layout.set("rows", 8)
	var port_mount := _room(&"port_mount", "WEAPONS", Rect2i(2, 2, 1, 1))
	var starboard_mount := _room(&"starboard_mount", "WEAPONS", Rect2i(3, 2, 1, 1))
	for mount: Resource in [port_mount, starboard_mount]:
		mount.set("module_recipe", LIGHT_BALLISTIC)
		mount.set("weapon_definition", LIGHT_BALLISTIC.get("payload_resource"))
		mount.set("module_facing_quarters", 0)
		mount.set("module_mount_facings", [0])
	var battery_rooms: Array[Resource] = [port_mount, starboard_mount]
	battery_layout.set("rooms", battery_rooms)
	var merge_builder: Object = BUILDER_SCRIPT.new()
	merge_builder.set("source_layout", battery_layout)
	merge_builder.call("_builder_merge_all_touching_like_rooms")
	var separate_rooms: Array = battery_layout.get("rooms")
	if separate_rooms.size() != 2:
		failures.append("touching quarter-grid weapons were incorrectly combined")
	else:
		var first_mount: Resource = separate_rooms[0]
		var second_mount: Resource = separate_rooms[1]
		if first_mount.get("room_id") == second_mount.get("room_id"):
			failures.append("touching weapons did not retain independent room identities")
		for mount: Resource in separate_rooms:
			if int(mount.get("installed_piece_count")) != 1 or (mount.get("grid_rects") as Array).size() != 1:
				failures.append("an independent weapon room contains more than one installed mount")
		var battery_stats: Dictionary = BUILDER_ANALYZER.analyze(battery_layout)
		if int(battery_stats["weapon_count"]) != 2:
			failures.append("separate touching weapons are not both counted")
		if not is_equal_approx(float(battery_stats["energy_demand"]), float(LIGHT_BALLISTIC.get("power_draw")) * 2.0):
			failures.append("separate touching weapons did not retain independent power draw")
	merge_builder.free()
	if not failures.is_empty():
		for failure: String in failures:
			push_error("QUARTER-LATTICE TEST // %s" % failure)
		quit(1)
		return
	print("QUARTER-LATTICE TEST // PASS // FULL 2x2 // QUARTER 1x1 // LONG 1x2 // %d DOORS" % structure.doors.size())
	quit()


func _room(room_id: StringName, type_name: String, rect: Rect2i) -> Resource:
	var room: Resource = ROOM_SCRIPT.new()
	room.set("room_id", room_id)
	room.set("display_name", type_name)
	room.set("type_name", type_name)
	var rects: Array[Rect2i] = [rect]
	room.set("grid_rects", rects)
	room.set("build_footprint_lattice", rect.size)
	return room


func _route_exists(structure: ShipStructuralState, start: Vector2i, goal: Vector2i) -> bool:
	var frontier: Array[Vector2i] = [start]
	var visited := {start: true}
	while not frontier.is_empty():
		var current: Vector2i = frontier.pop_front()
		if current == goal:
			return true
		for direction: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var neighbor := current + direction
			if visited.has(neighbor) or not structure.cell_rooms.has(neighbor):
				continue
			var current_room: StringName = structure.cell_rooms[current]
			var neighbor_room: StringName = structure.cell_rooms[neighbor]
			if current_room != neighbor_room and structure.get_door_between_cells(current, neighbor).is_empty():
				continue
			visited[neighbor] = true
			frontier.append(neighbor)
	return false
