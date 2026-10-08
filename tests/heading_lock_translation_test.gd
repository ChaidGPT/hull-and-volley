extends SceneTree

const SHIP_SIMULATION := preload("res://scripts/ship_simulation.gd")
const PHYSICS_SHIP_BODY := preload("res://scripts/physics_ship_body.gd")
const SHIP_LAYOUT := preload("res://scripts/resources/ship_layout_resource.gd")
const ROOM_LAYOUT := preload("res://scripts/resources/room_layout_data.gd")


class TranslationTestShip extends ShipSimulation:
	var test_profile := {
		"banks": {},
		"forward_acceleration": 3.0,
		"translation_forward_acceleration": 3.0,
		"translation_reverse_acceleration": 1.0,
		"translation_starboard_acceleration": 7.0,
		"translation_port_acceleration": 0.7,
		"braking_acceleration": 4.0,
		"angular_acceleration": deg_to_rad(20.0),
		"lateral_acceleration": 7.0,
	}

	func get_propulsion_command_profile() -> Dictionary:
		return test_profile


class DirectionalBankTestShip extends ShipSimulation:
	func get_room_efficiency(_room_id: StringName) -> float:
		return 1.0


func _init() -> void:
	var failures := PackedStringArray()
	var starboard_ship := TranslationTestShip.new()
	starboard_ship.ship_rotation = 0.0
	starboard_ship.previous_ship_rotation = 0.0
	starboard_ship.set_heading_lock_course(Vector2(300.0, 0.0))
	for index: int in range(20):
		starboard_ship._physics_process(0.1)
	_check(starboard_ship.ship_position.x > 1.0, "side bank did not translate the ship", failures)
	_check(absf(starboard_ship.ship_position.y) < 0.01, "translation wandered off its commanded axis", failures)
	_check(absf(starboard_ship.ship_rotation) < 0.001, "heading lock rotated the hull", failures)
	_check(starboard_ship.heading_lock_course_active, "heading lock dropped before arrival", failures)

	var port_ship := TranslationTestShip.new()
	port_ship.ship_rotation = 0.0
	port_ship.previous_ship_rotation = 0.0
	port_ship.set_heading_lock_course(Vector2(-300.0, 0.0))
	for index: int in range(20):
		port_ship._physics_process(0.1)
	_check(
		starboard_ship.ship_position.x > absf(port_ship.ship_position.x) * 2.0,
		"stronger directional bank did not compound translation",
		failures
	)

	var physics_body := PHYSICS_SHIP_BODY.new() as PhysicsShipBody
	physics_body.set_translation_command(
		Vector2(12.0, 0.0),
		0.0,
		1.0,
		1.0,
		7.0,
		3.0,
		1.0,
		1.0,
		Vector2.LEFT
	)
	var visual_command: Dictionary = physics_body.get_propulsion_visual_command()
	var exhaust: Vector2 = visual_command.get("translation_exhaust", Vector2.ZERO)
	_check(
		exhaust.is_equal_approx(Vector2.LEFT),
		"translation did not expose the firing thruster bank to visuals",
		failures
	)

	var bank_ship := DirectionalBankTestShip.new()
	var bank_layout := SHIP_LAYOUT.new() as ShipLayoutResource
	bank_layout.lattice_version = 2
	var combined_thrusters := ROOM_LAYOUT.new() as RoomLayoutData
	combined_thrusters.room_id = &"combined_thrusters"
	combined_thrusters.type_name = "PROPULSION"
	combined_thrusters.installed_piece_count = 3
	combined_thrusters.grid_rects = [
		Rect2i(Vector2i(0, 0), Vector2i(1, 1)),
		Rect2i(Vector2i(1, 0), Vector2i(1, 1)),
		Rect2i(Vector2i(2, 0), Vector2i(1, 1)),
	]
	combined_thrusters.module_mount_facings = [3, 2, 1]
	bank_layout.rooms = [combined_thrusters]
	bank_ship.ship_layout = bank_layout
	var banks: Dictionary = bank_ship.get_directional_propulsion_output()
	_check(is_equal_approx(float(banks["port"]), 1.0), "combined room lost its port-facing thruster", failures)
	_check(is_equal_approx(float(banks["aft"]), 1.0), "combined room lost its aft-facing thruster", failures)
	_check(is_equal_approx(float(banks["starboard"]), 1.0), "combined room lost its starboard-facing thruster", failures)
	var bank_profile := bank_ship.get_propulsion_command_profile()
	_check(
		is_equal_approx(float(bank_profile["translation_starboard_acceleration"]), bank_ship.acceleration),
		"port exhaust did not create starboard translation",
		failures
	)
	_check(
		is_equal_approx(float(bank_profile["translation_port_acceleration"]), bank_ship.acceleration),
		"starboard exhaust did not create port translation",
		failures
	)

	physics_body.free()
	bank_ship.free()
	port_ship.free()
	starboard_ship.free()
	if not failures.is_empty():
		for failure: String in failures:
			push_error("HEADING LOCK TEST • FAIL • %s" % failure)
		quit(1)
		return
	print("HEADING LOCK TEST • PASS • DIRECTIONAL STRAFE + FIXED FACING")
	quit(0)


func _check(condition: bool, message: String, failures: PackedStringArray) -> void:
	if not condition:
		failures.append(message)
