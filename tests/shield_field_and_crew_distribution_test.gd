extends SceneTree

const LAYOUT_SCRIPT := preload("res://scripts/resources/ship_layout_resource.gd")
const ROOM_SCRIPT := preload("res://scripts/resources/room_layout_data.gd")
const GRID_GEOMETRY := preload("res://scripts/grid_geometry.gd")
const SHIELD_VISUAL := preload("res://scripts/shield_visual.gd")
const CREW_SIMULATION := preload("res://scripts/crew_simulation.gd")
const SHIP_BUILDER_ANALYZER := preload("res://scripts/ship_builder_analyzer.gd")


func _init() -> void:
	var failures := PackedStringArray()
	var layout: Resource = LAYOUT_SCRIPT.new()
	layout.set("lattice_version", 2)
	layout.set("columns", 4)
	layout.set("rows", 4)
	var room: Resource = ROOM_SCRIPT.new()
	room.set("room_id", &"combined_battery")
	room.set("type_name", "WEAPONS")
	var rects: Array[Rect2i] = [Rect2i(1, 1, 1, 1), Rect2i(1, 2, 1, 1)]
	room.set("grid_rects", rects)
	var rooms: Array[Resource] = [room]
	layout.set("rooms", rooms)

	var occupied := GRID_GEOMETRY.layout_cells(layout)
	var right_edges := 0
	for segment: Dictionary in GRID_GEOMETRY.boundary_segments(layout, occupied, layout.call("get_occupied_bounds"), 20.0):
		if Vector2(segment.get("normal", Vector2.ZERO)) == Vector2.RIGHT:
			right_edges += 1
	_check(right_edges == 2, "starboard shield field did not span the complete two-cell side", failures)

	var shield: Control = SHIELD_VISUAL.new()
	shield.call("set_hull_geometry", layout, Vector2.ZERO, 20.0)
	shield.call("set_shield_banks", {1: {"current": 20.0, "maximum": 20.0, "ratio": 1.0, "online": true}}, true)
	_check(bool(shield.get("shield_active")), "charged directional bank did not activate its field", failures)
	var arc: PackedVector2Array = shield.call("_shield_arc_points", occupied, 1)
	_check(arc.size() >= 3, "directional bank did not create a continuous projected arc", failures)
	if arc.size() >= 3:
		var midpoint: Vector2 = arc[arc.size() / 2]
		_check(midpoint.x > arc[0].x and midpoint.x > arc[arc.size() - 1].x, "directional field did not bow outward from the hull", failures)
		_check(absf(arc[arc.size() - 1].y - arc[0].y) > 40.0, "directional field did not span the complete protected side", failures)
	shield.call("set_shield_banks", {1: {"current": 0.0, "maximum": 20.0, "ratio": 0.0, "online": true}}, true)
	_check(not bool(shield.get("shield_active")), "depleted directional bank left its field visible", failures)

	var crew: Node = CREW_SIMULATION.new()
	_check(int(crew.get("crew_capacity_per_quarters_cell")) == 8, "Crew Quarters runtime capacity was not raised to eight", failures)
	_check(int(SHIP_BUILDER_ANALYZER.CREW_CAPACITY_PER_QUARTERS_CELL) == 8, "drydock Crew Quarters capacity was not raised to eight", failures)
	var slots: Array[Dictionary] = [
		{"room_id": &"combined_battery", "cell": Vector2i(1, 1), "slot_index": 0, "piece_index": 0, "position": Vector2(1.0, 1.0)},
		{"room_id": &"combined_battery", "cell": Vector2i(1, 1), "slot_index": 1, "piece_index": 0, "position": Vector2(1.1, 1.0)},
		{"room_id": &"combined_battery", "cell": Vector2i(1, 2), "slot_index": 0, "piece_index": 1, "position": Vector2(1.0, 2.0)},
		{"room_id": &"combined_battery", "cell": Vector2i(1, 2), "slot_index": 1, "piece_index": 1, "position": Vector2(1.1, 2.0)},
	]
	crew.set("work_slots", slots)
	var first_member := {
		"id": 1,
		"assigned_room_id": &"combined_battery",
		"target_slot": slots[0],
		"position": slots[0]["position"],
		"path": [],
		"ejected": false,
	}
	var members: Array[Dictionary] = [first_member]
	crew.set("crew_members", members)
	var next_slot: Dictionary = crew.call("_balanced_open_room_slot", slots, {crew.call("_slot_key", slots[0]): true}, &"combined_battery", 2)
	_check(int(next_slot.get("piece_index", -1)) == 1, "combined-room staffing bunched into the first physical piece", failures)

	crew.free()
	shield.free()
	if not failures.is_empty():
		for failure: String in failures:
			push_error("SHIELD FIELD / CREW DISTRIBUTION TEST // FAIL // %s" % failure)
		quit(1)
		return
	print("SHIELD FIELD / CREW DISTRIBUTION TEST // PASS // FULL-SIDE BANK + DEPLETION + BALANCED STATIONS")
	quit(0)


func _check(condition: bool, message: String, failures: PackedStringArray) -> void:
	if not condition:
		failures.append(message)
