extends SceneTree

const PHYSICS_SHIP_BODY := preload("res://scripts/physics_ship_body.gd")
const SHIP_LAYOUT := preload("res://scripts/resources/ship_layout_resource.gd")
const ROOM_LAYOUT := preload("res://scripts/resources/room_layout_data.gd")


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var failures := PackedStringArray()
	var layout := SHIP_LAYOUT.new() as ShipLayoutResource
	layout.lattice_version = 2
	var hull := ROOM_LAYOUT.new() as RoomLayoutData
	hull.room_id = &"test_hull"
	hull.grid_rects = [Rect2i(Vector2i.ZERO, Vector2i(2, 2))]
	layout.rooms = [hull]

	var body := PHYSICS_SHIP_BODY.new() as PhysicsShipBody
	body.gravity_scale = 0.0
	body.can_sleep = false
	body.configure_layout(layout)
	root.add_child(body)
	await physics_frame
	body.set_translation_command(
		Vector2(20.0, 0.0),
		0.0,
		1.0,
		0.0,
		7.0,
		0.0,
		0.0,
		Vector2.LEFT
	)
	for _frame: int in range(30):
		await physics_frame
	if body.global_position.x <= 0.25:
		failures.append("real physics body did not translate under a side-bank command")
	if absf(body.global_position.y) > 0.05:
		failures.append("real physics body wandered off the commanded translation axis")
	if absf(body.rotation) > 0.001:
		failures.append("translation command rotated the real physics hull")

	body.queue_free()
	if not failures.is_empty():
		for failure: String in failures:
			push_error("PHYSICS TRANSLATION TEST - FAIL - %s" % failure)
		quit(1)
		return
	print("PHYSICS TRANSLATION TEST - PASS - SIDE BANK MOVES RIGID BODY")
	quit(0)
