extends SceneTree

const LAYOUT_SCRIPT := preload("res://scripts/resources/ship_layout_resource.gd")
const ROOM_SCRIPT := preload("res://scripts/resources/room_layout_data.gd")
const ANALYZER := preload("res://scripts/ship_builder_analyzer.gd")


func _initialize() -> void:
	var failures := PackedStringArray()
	var layout: Resource = LAYOUT_SCRIPT.new()
	layout.set("lattice_version", 2)
	layout.set("columns", 20)
	layout.set("rows", 8)
	var reactor_a := _room(&"reactor_a", "REACTOR", Rect2i(0, 2, 2, 2))
	var near_weapon := _room(&"near_weapon", "WEAPONS", Rect2i(5, 2, 1, 1))
	var far_weapon := _room(&"far_weapon", "WEAPONS", Rect2i(7, 2, 1, 1))
	var rooms: Array[Resource] = [reactor_a, near_weapon, far_weapon]
	layout.set("rooms", rooms)
	var report := ANALYZER.power_network_report(layout)
	if not is_equal_approx(float(report["room_factors"].get(&"near_weapon", -1.0)), 1.0):
		failures.append("consumer at the reactor field edge was not powered")
	if not is_equal_approx(float(report["room_factors"].get(&"far_weapon", -1.0)), 0.0):
		failures.append("consumer outside the reactor field received power")
	var far_status := ANALYZER.evaluate_power_placement(
		layout, "WEAPONS", Vector2i(12, 2), Vector2i.ONE
	)
	if bool(far_status.get("valid", true)) or bool(far_status.get("covered", true)):
		failures.append("blueprint accepted a weapon outside every reactor field")

	# The second reactor's field overlaps the first, so their capacity and
	# consumers become one pooled local network.
	var reactor_b := _room(&"reactor_b", "REACTOR", Rect2i(8, 2, 2, 2))
	rooms.append(reactor_b)
	layout.set("rooms", rooms)
	report = ANALYZER.power_network_report(layout)
	if (report["networks"] as Array).size() != 1:
		failures.append("overlapping reactor fields did not merge")
	if not is_equal_approx(float(report["room_factors"].get(&"far_weapon", 0.0)), 1.0):
		failures.append("overlapping reactor network did not power its consumer")
	if not is_equal_approx(float((report["networks"] as Array)[0]["capacity"]), 8.0):
		failures.append("overlapping reactor capacity did not pool")

	# A destroyed/offline reactor contributes no local capacity at runtime.
	report = ANALYZER.power_network_report(layout, {&"reactor_a": 0.0, &"reactor_b": 0.0})
	if float(report["room_factors"].get(&"near_weapon", 1.0)) > 0.001:
		failures.append("offline reactors continued powering consumers")

	if failures.is_empty():
		print("LOCAL_POWER_NETWORK_TEST_PASS")
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	quit(1)


func _room(room_id: StringName, room_type: String, rect: Rect2i) -> Resource:
	var room: Resource = ROOM_SCRIPT.new()
	room.set("room_id", room_id)
	room.set("display_name", room_type)
	room.set("type_name", room_type)
	var rects: Array[Rect2i] = [rect]
	room.set("grid_rects", rects)
	room.set("installed_piece_count", 1)
	return room
