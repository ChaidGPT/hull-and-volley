extends SceneTree

const CREW_SIMULATION := preload("res://scripts/crew_simulation.gd")
const LAYOUT_SCRIPT := preload("res://scripts/resources/ship_layout_resource.gd")
const ROOM_SCRIPT := preload("res://scripts/resources/room_layout_data.gd")
const CREW_VISUAL := preload("res://resources/default_crew_visual.tres")
const LASER_EMITTER := preload("res://resources/weapons/laser_emitter.tres")


func _initialize() -> void:
	var layout: Resource = LAYOUT_SCRIPT.new()
	layout.set("lattice_version", 2)
	layout.set("columns", 4)
	layout.set("rows", 4)
	var weapon_room: Resource = ROOM_SCRIPT.new()
	weapon_room.set("room_id", &"narrow_casemate")
	weapon_room.set("type_name", "WEAPONS")
	var weapon_rects: Array[Rect2i] = [Rect2i(1, 1, 2, 2)]
	weapon_room.set("grid_rects", weapon_rects)
	weapon_room.set("module_facing_quarters", 2)
	var weapon_facings: Array[int] = [2]
	weapon_room.set("module_mount_facings", weapon_facings)
	weapon_room.set("weapon_definition", LASER_EMITTER)
	var rooms: Array[Resource] = [weapon_room]
	layout.set("rooms", rooms)

	var crew: Node = CREW_SIMULATION.new()
	crew.set("crew_definition", CREW_VISUAL)
	crew.call("_build_work_slots", layout)
	var obstacles: Array = crew.get("furniture_obstacles")
	var work_slots: Array = crew.get("work_slots")
	if obstacles.size() < 2:
		_fail("narrow casemate did not register gun and aperture blockers (found %d)" % obstacles.size())
		crew.free()
		return
	if work_slots.is_empty():
		_fail("narrow casemate did not create an accessible authored work station")
		crew.free()
		return
	for slot_value: Variant in work_slots:
		var slot: Dictionary = slot_value
		if _blocked(Vector2(slot.get("position", Vector2.ZERO)), obstacles):
			_fail("work slot was placed inside the gun or open aperture")
			crew.free()
			return
		if not bool(slot.get("authored_weapon_station", false)):
			_fail("narrow casemate retained a generic, potentially unreachable work slot")
			crew.free()
			return
	for slot_value: Variant in crew.get("ambient_slots"):
		var slot: Dictionary = slot_value
		if StringName(slot.get("room_id", &"")) == &"narrow_casemate":
			_fail("narrow casemate retained an ambient parking destination")
			crew.free()
			return
		if _blocked(Vector2(slot.get("position", Vector2.ZERO)), obstacles):
			_fail("ambient slot was placed inside the gun or open aperture")
			crew.free()
			return

	crew.free()
	print("NARROW WEAPON ROOM NAVIGATION TEST - PASS - GUN + SPACE APERTURE ARE NON-WALKABLE")
	quit(0)


func _blocked(point: Vector2, obstacles: Array) -> bool:
	for obstacle_value: Variant in obstacles:
		var obstacle: Rect2 = obstacle_value
		if obstacle.has_point(point):
			return true
	return false


func _fail(message: String) -> void:
	push_error("NARROW WEAPON ROOM NAVIGATION TEST - FAIL - %s" % message)
	quit(1)
