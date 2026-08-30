extends SceneTree

const LAYOUT_SCRIPT := preload("res://scripts/resources/ship_layout_resource.gd")
const ROOM_SCRIPT := preload("res://scripts/resources/room_layout_data.gd")
const TACTICAL_VISUAL := preload("res://scripts/tactical_ship_visual.gd")
const BUILDER_SCRIPT := preload("res://scripts/ship_builder_screen.gd")
const EXPLOSIVE_CANNON := preload("res://resources/weapons/longshot_cannon.tres")


func _init() -> void:
	var failures := PackedStringArray()
	var layout: Resource = LAYOUT_SCRIPT.new()
	layout.set("lattice_version", 2)
	layout.set("columns", 6)
	layout.set("rows", 6)
	var core: Resource = ROOM_SCRIPT.new()
	core.set("room_id", &"core")
	core.set("type_name", "CREW_QUARTERS")
	var core_rects: Array[Rect2i] = [Rect2i(1, 1, 1, 3)]
	core.set("grid_rects", core_rects)
	var weapons: Resource = ROOM_SCRIPT.new()
	weapons.set("room_id", &"battery")
	weapons.set("type_name", "WEAPONS")
	var weapon_rects: Array[Rect2i] = [
		Rect2i(2, 1, 1, 1),
		Rect2i(2, 2, 1, 1),
		Rect2i(2, 3, 1, 1),
	]
	weapons.set("grid_rects", weapon_rects)
	weapons.set("installed_piece_count", 3)
	weapons.set("module_facing_quarters", 1)
	var right_facings: Array[int] = [1, 1, 1]
	weapons.set("module_mount_facings", right_facings)
	weapons.set("weapon_definition", EXPLOSIVE_CANNON)
	var rooms: Array[Resource] = [core, weapons]
	layout.set("rooms", rooms)

	var visual: Control = TACTICAL_VISUAL.new()
	visual.set("ship_layout", layout)
	visual.call("_update_size_from_layout")
	var mounts: Array = visual.call("_module_piece_views", weapons)
	_check(mounts.size() == 3, "merged battery did not preserve three hardpoints", failures)
	var centers: Dictionary = {}
	for mount_value: Variant in mounts:
		var mount := mount_value as Resource
		var center: Vector2 = visual.call("_resource_room_center", mount)
		centers[center] = true
		var cells: Dictionary = visual.call("_build_room_cells", mount)
		var direction: Vector2 = visual.call("_module_facing_direction", mount, cells, visual.call("_all_occupied_cells"))
		_check(direction.is_equal_approx(Vector2.RIGHT), "hardpoint direction diverged from its stored mount vector", failures)
	_check(centers.size() == 3, "merged hardpoints collapsed onto one tactical marker", failures)
	var middle_mount: Resource = mounts[1]
	var clear_starboard: Dictionary = layout.call("evaluate_room_facing_clearance", middle_mount, 1)
	var blocked_bow: Dictionary = layout.call("evaluate_room_facing_clearance", middle_mount, 0)
	_check(bool(clear_starboard.get("valid", false)), "mount treated its own combined room as a starboard blocker", failures)
	_check(not bool(blocked_bow.get("valid", true)), "adjacent sibling mount failed to block the bow firing lane", failures)

	var builder: Object = BUILDER_SCRIPT.new()
	builder.call("_set_room_mount_facing_at_cell", weapons, Vector2i(2, 2), 0)
	var facings: Array = weapons.get("module_mount_facings")
	_check(facings == [1, 0, 1], "direction control changed the room fallback instead of the clicked hardpoint", failures)

	builder.free()
	visual.free()
	if not failures.is_empty():
		for failure: String in failures:
			push_error("MERGED WEAPON VISUAL TEST // FAIL // %s" % failure)
		quit(1)
		return
	print("MERGED WEAPON VISUAL TEST // PASS // 3 DISTINCT MOUNTS + PER-MOUNT FACING + CLEARANCE")
	quit(0)


func _check(condition: bool, message: String, failures: PackedStringArray) -> void:
	if not condition:
		failures.append(message)
