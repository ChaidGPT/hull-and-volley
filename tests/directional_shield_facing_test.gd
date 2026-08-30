extends SceneTree

const LAYOUT_SCRIPT := preload("res://scripts/resources/ship_layout_resource.gd")
const ROOM_SCRIPT := preload("res://scripts/resources/room_layout_data.gd")
const SHIP_SIMULATION := preload("res://scripts/ship_simulation.gd")
const SETTLEMENT_GRID := preload("res://scripts/settlement_grid.gd")
const BUILDER_SCRIPT := preload("res://scripts/ship_builder_screen.gd")


func _init() -> void:
	var failures := PackedStringArray()
	var layout: Resource = LAYOUT_SCRIPT.new()
	layout.set("lattice_version", 2)
	layout.set("columns", 6)
	layout.set("rows", 6)

	var core: Resource = ROOM_SCRIPT.new()
	core.set("room_id", &"core")
	core.set("type_name", "CREW_QUARTERS")
	var core_rects: Array[Rect2i] = [Rect2i(1, 1, 1, 2)]
	core.set("grid_rects", core_rects)

	var shields: Resource = ROOM_SCRIPT.new()
	shields.set("room_id", &"shield_bank")
	shields.set("display_name", "Directional Shield")
	shields.set("type_name", "SHIELDS")
	var shield_rects: Array[Rect2i] = [Rect2i(2, 1, 1, 1), Rect2i(2, 2, 1, 1)]
	shields.set("grid_rects", shield_rects)
	shields.set("installed_piece_count", 2)
	shields.set("module_facing_quarters", 1)
	var shield_facings: Array[int] = [1, 1]
	shields.set("module_mount_facings", shield_facings)
	var rooms: Array[Resource] = [core, shields]
	layout.set("rooms", rooms)

	var grid: Control = SETTLEMENT_GRID.new()
	grid.set("ship_layout", layout)
	_check(
		bool(grid.call("_pointer_hits_module_hardware", Vector2i(2, 1), Vector2.ZERO)),
		"shield tile was not selectable as directional hardware",
		failures
	)

	var simulation: Node = SHIP_SIMULATION.new()
	var pieces: Array = simulation.call("_directional_shield_piece_views", shields)
	_check(pieces.size() == 2, "combined shield bank collapsed into one emitter", failures)

	var builder: Object = BUILDER_SCRIPT.new()
	builder.call("_set_room_mount_facing_at_cell", shields, Vector2i(2, 2), 0)
	var updated_facings: Array = shields.get("module_mount_facings")
	_check(updated_facings == [1, 0], "direction control changed more than the selected shield emitter", failures)

	var right_clearance: Dictionary = layout.call("evaluate_room_facing_clearance", pieces[0], 1)
	var left_clearance: Dictionary = layout.call("evaluate_room_facing_clearance", pieces[0], 3)
	_check(bool(right_clearance.get("valid", false)), "exposed starboard shield facing was rejected", failures)
	_check(not bool(left_clearance.get("valid", true)), "shield emitter was allowed to point through the hull", failures)

	builder.free()
	simulation.free()
	grid.free()
	if not failures.is_empty():
		for failure: String in failures:
			push_error("DIRECTIONAL SHIELD TEST // FAIL // %s" % failure)
		quit(1)
		return
	print("DIRECTIONAL SHIELD TEST // PASS // PER-PIECE FACING + EXPOSED-HULL CLEARANCE")
	quit(0)


func _check(condition: bool, message: String, failures: PackedStringArray) -> void:
	if not condition:
		failures.append(message)
