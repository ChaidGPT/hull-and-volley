extends SceneTree

const LAYOUT_SCRIPT := preload("res://scripts/resources/ship_layout_resource.gd")
const ROOM_SCRIPT := preload("res://scripts/resources/room_layout_data.gd")
const GRID_GEOMETRY := preload("res://scripts/grid_geometry.gd")


func _initialize() -> void:
	var layout: Resource = LAYOUT_SCRIPT.new()
	layout.set("lattice_version", 2)
	layout.set("columns", 40)
	layout.set("rows", 30)
	var rooms: Array[Resource] = []
	for y: int in range(0, 30, 2):
		for x: int in range(0, 40, 2):
			var room: Resource = ROOM_SCRIPT.new()
			room.set("room_id", StringName("room_%d_%d" % [x, y]))
			room.set("type_name", "UNASSIGNED")
			var rects: Array[Rect2i] = [Rect2i(x, y, 2, 2)]
			room.set("grid_rects", rects)
			rooms.append(room)
	layout.set("rooms", rooms)
	var occupied := GRID_GEOMETRY.layout_cells(layout)
	var started := Time.get_ticks_usec()
	var segment_count := 0
	for index: int in range(500):
		segment_count += GRID_GEOMETRY.boundary_segments(layout, occupied, Rect2i(0, 0, 40, 30), 10.0).size()
	var elapsed_ms := float(Time.get_ticks_usec() - started) / 1000.0
	if elapsed_ms > 750.0:
		push_error("QUARTER-LATTICE PERFORMANCE // boundary lookup took %.1f ms" % elapsed_ms)
		quit(1)
		return
	print("QUARTER-LATTICE PERFORMANCE // PASS // 1200 CELLS // 500 PASSES // %.1f MS // %d SEGMENTS" % [elapsed_ms, segment_count])
	quit()
