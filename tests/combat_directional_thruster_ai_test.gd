extends SceneTree

const COMBAT_SIMULATION := preload("res://scripts/combat_simulation.gd")
const PHYSICS_SHIP_BODY := preload("res://scripts/physics_ship_body.gd")


func _init() -> void:
	var failures := PackedStringArray()
	var combat := COMBAT_SIMULATION.new() as CombatSimulation
	var conventional_layout := load("res://resources/ship_designs/small_ship.tres") as Resource
	var strafe_layout := load("res://resources/ship_designs/small_ship_2.tres") as Resource
	var conventional_profile: Dictionary = combat.call("_enemy_propulsion_profile", conventional_layout)
	var strafe_profile: Dictionary = combat.call("_enemy_propulsion_profile", strafe_layout)

	_check(
		not bool(conventional_profile.get("has_lateral_translation", false)),
		"aft-thrust-only Small Ship was incorrectly granted lateral translation",
		failures
	)
	_check(
		bool(strafe_profile.get("has_lateral_translation", false)),
		"Small Ship 2 side thrusters were not recognized by the combat helm",
		failures
	)
	_check(
		float(strafe_profile.get("translation_port_acceleration", 0.0)) > 0.0,
		"Small Ship 2 cannot strafe port",
		failures
	)
	_check(
		float(strafe_profile.get("translation_starboard_acceleration", 0.0)) > 0.0,
		"Small Ship 2 cannot strafe starboard",
		failures
	)
	var target_direction := Vector2.RIGHT
	var orbit_direction := Vector2.DOWN
	var facing_target_rotation := Vector2.UP.angle_to(target_direction)
	var conventional_choice: Vector2 = combat.call(
		"_best_supported_combat_direction",
		orbit_direction,
		facing_target_rotation,
		conventional_profile,
		target_direction,
		orbit_direction
	)
	var strafe_choice: Vector2 = combat.call(
		"_best_supported_combat_direction",
		orbit_direction,
		facing_target_rotation,
		strafe_profile,
		target_direction,
		orbit_direction
	)
	_check(
		conventional_choice.dot(target_direction) > conventional_choice.dot(orbit_direction),
		"aft-thrust-only hull did not adapt its maneuver to usable thrust",
		failures
	)
	_check(
		strafe_choice.dot(orbit_direction) > 0.9,
		"side-thrust-capable hull discarded a valid strafing maneuver",
		failures
	)
	var observed_modes := {}
	var maneuver_enemy := _test_enemy(strafe_layout, null)
	maneuver_enemy["id"] = 41
	maneuver_enemy["combat_personality"]["strafe_preference"] = 0.52
	for cycle: int in range(12):
		maneuver_enemy["combat_maneuver_cycle"] = cycle
		observed_modes[combat.call("_choose_combat_maneuver", maneuver_enemy, false)] = true
	_check(
		observed_modes.size() > 1,
		"lateral thrusters locked the ship into one permanent combat style",
		failures
	)

	var strafe_body := PHYSICS_SHIP_BODY.new() as PhysicsShipBody
	var strafe_enemy := _test_enemy(strafe_layout, strafe_body)
	var target := {"position": Vector2(360.0, 0.0)}
	combat.call("_update_enemy_movement", strafe_enemy, target["position"], 0.1, target)
	_check(
		strafe_body.commanded_translation_active,
		"combat helm did not select translation control for a strafe-capable ship",
		failures
	)

	var conventional_body := PHYSICS_SHIP_BODY.new() as PhysicsShipBody
	var conventional_enemy := _test_enemy(conventional_layout, conventional_body)
	combat.call("_update_enemy_movement", conventional_enemy, target["position"], 0.1, target)
	_check(
		not conventional_body.commanded_translation_active,
		"conventional ship stopped using turn-then-drive control",
		failures
	)

	strafe_body.free()
	conventional_body.free()
	combat.free()
	if not failures.is_empty():
		for failure: String in failures:
			push_error("COMBAT DIRECTIONAL THRUSTER AI TEST • FAIL • %s" % failure)
		quit(1)
		return
	print("COMBAT DIRECTIONAL THRUSTER AI TEST • PASS • BLUEPRINT-AWARE STRAFING")
	quit(0)


func _test_enemy(layout: Resource, physics_body: PhysicsShipBody) -> Dictionary:
	return {
		"physics_body": physics_body,
		"stationary": false,
		"position": Vector2.ZERO,
		"rotation": 0.0,
		"velocity": Vector2.ZERO,
		"layout": layout,
		"combat_test_ship": true,
		"hull": 100.0,
		"maximum_hull": 100.0,
		"combat_personality": {
			"aggression": 1.0,
			"range_factor": 0.72,
			"orbit_sign": 1.0,
			"courage": 0.2,
			"decision_interval": 0.65,
		},
	}


func _check(condition: bool, message: String, failures: PackedStringArray) -> void:
	if not condition:
		failures.append(message)
