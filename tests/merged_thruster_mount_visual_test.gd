extends SceneTree

const LAYOUT_SCRIPT := preload("res://scripts/resources/ship_layout_resource.gd")
const ROOM_SCRIPT := preload("res://scripts/resources/room_layout_data.gd")
const TACTICAL_VISUAL := preload("res://scripts/tactical_ship_visual.gd")
const BUILDER_SCRIPT := preload("res://scripts/ship_builder_screen.gd")


func _init() -> void:
	var failures := PackedStringArray()
	var layout: Resource = LAYOUT_SCRIPT.new()
	layout.set("lattice_version", 2)
	layout.set("columns", 8)
	layout.set("rows", 6)

	var core: Resource = ROOM_SCRIPT.new()
	core.set("room_id", &"core")
	core.set("type_name", "REACTOR")
	var core_rects: Array[Rect2i] = [Rect2i(1, 1, 6, 2)]
	core.set("grid_rects", core_rects)

	var thrusters: Resource = ROOM_SCRIPT.new()
	thrusters.set("room_id", &"aft_bank")
	thrusters.set("type_name", "PROPULSION")
	var thruster_rects: Array[Rect2i] = [
		Rect2i(1, 3, 2, 2),
		Rect2i(3, 3, 2, 2),
		Rect2i(5, 3, 2, 2),
	]
	thrusters.set("grid_rects", thruster_rects)
	thrusters.set("installed_piece_count", 3)
	thrusters.set("module_facing_quarters", 2)
	var aft_facings: Array[int] = [2, 2, 2]
	thrusters.set("module_mount_facings", aft_facings)
	var rooms: Array[Resource] = [core, thrusters]
	layout.set("rooms", rooms)

	var visual: Control = TACTICAL_VISUAL.new()
	visual.set("ship_layout", layout)
	visual.call("_update_size_from_layout")
	var mounts: Array = visual.call("_module_piece_views", thrusters)
	_check(mounts.size() == 3, "merged propulsion room did not preserve three nozzles", failures)
	var centers: Dictionary = {}
	for mount_value: Variant in mounts:
		var mount := mount_value as Resource
		var center: Vector2 = visual.call("_resource_room_center", mount)
		centers[center] = true
		var cells: Dictionary = visual.call("_build_room_cells", mount)
		var direction: Vector2 = visual.call("_module_facing_direction", mount, cells, visual.call("_all_occupied_cells"))
		_check(direction.is_equal_approx(Vector2.DOWN), "nozzle direction diverged from its stored mount vector", failures)
	_check(centers.size() == 3, "merged thrusters collapsed onto one exhaust point", failures)
	var middle_mount: Resource = mounts[1]
	var clear_aft: Dictionary = layout.call("evaluate_room_facing_clearance", middle_mount, 2)
	var blocked_port: Dictionary = layout.call("evaluate_room_facing_clearance", middle_mount, 3)
	_check(bool(clear_aft.get("valid", false)), "thruster treated its own combined room as an aft blocker", failures)
	_check(not bool(blocked_port.get("valid", true)), "adjacent sibling thruster failed to block the port exhaust lane", failures)

	# The same per-mount control path is shared by weapons and propulsion. Verify
	# that changing the middle hardware leaves its connected neighbors untouched.
	var builder: Object = BUILDER_SCRIPT.new()
	builder.call("_set_room_mount_facing_at_cell", thrusters, Vector2i(3, 3), 3)
	var facings: Array = thrusters.get("module_mount_facings")
	_check(facings == [2, 3, 2], "direction control changed the combined room instead of the clicked mount", failures)

	builder.free()
	visual.free()
	if not failures.is_empty():
		for failure: String in failures:
			push_error("MERGED THRUSTER VISUAL TEST // FAIL // %s" % failure)
		quit(1)
		return
	print("MERGED THRUSTER VISUAL TEST // PASS // 3 DISTINCT NOZZLES + PER-MOUNT FACING + CLEARANCE")
	quit(0)


func _check(condition: bool, message: String, failures: PackedStringArray) -> void:
	if not condition:
		failures.append(message)
