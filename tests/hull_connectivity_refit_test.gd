extends SceneTree

const BUILDER_SCREEN := preload("res://scripts/ship_builder_screen.gd")
const SHIP_LAYOUT := preload("res://scripts/resources/ship_layout_resource.gd")
const ROOM_LAYOUT := preload("res://scripts/resources/room_layout_data.gd")


func _init() -> void:
	var builder := BUILDER_SCREEN.new()
	var layout := SHIP_LAYOUT.new()
	layout.set("lattice_version", 2)
	var left := _room(&"left", Vector2i(0, 0))
	var link := _room(&"link", Vector2i(1, 0))
	var right := _room(&"right", Vector2i(2, 0))
	var connected_rooms: Array[Resource] = [left, link, right]
	layout.set("rooms", connected_rooms)
	builder.set("source_layout", layout)
	if not bool(builder.call("_builder_hull_is_connected")):
		push_error("HULL CONNECTIVITY REFIT TEST // FAIL // intact chain reported disconnected")
		quit(1)
		return
	var severed_rooms: Array[Resource] = [left, right]
	layout.set("rooms", severed_rooms)
	if bool(builder.call("_builder_hull_is_connected")):
		push_error("HULL CONNECTIVITY REFIT TEST // FAIL // severed hull reported connected")
		quit(1)
		return
	print("HULL CONNECTIVITY REFIT TEST // PASS // STRUCTURAL LINKS ARE PROTECTED")
	quit(0)


func _room(room_id: StringName, cell: Vector2i) -> Resource:
	var room := ROOM_LAYOUT.new()
	room.set("room_id", room_id)
	var rects: Array[Rect2i] = [Rect2i(cell, Vector2i.ONE)]
	room.set("grid_rects", rects)
	return room
