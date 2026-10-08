extends SceneTree

const COMBAT_SIMULATION := preload("res://scripts/combat_simulation.gd")

class FakePlayer extends Node:
	var ship_position := Vector2.ZERO
	var physics_body: RigidBody2D
	var is_destroyed := false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var world := Node2D.new()
	root.add_child(world)
	var physics_world := Node2D.new()
	physics_world.add_to_group("physics_world")
	world.add_child(physics_world)
	var combat := COMBAT_SIMULATION.new()
	world.add_child(combat)
	var player := FakePlayer.new()
	player.physics_body = RigidBody2D.new()
	physics_world.add_child(player.physics_body)
	world.add_child(player)
	await process_frame

	var layout := load("res://resources/ship_designs/morrow_proving_yard.tres") as Resource
	var faction_station_id := int(combat.call(
		"spawn_combat_test_ship", layout, &"UNITED_SYSTEMS", 1,
		Vector2(-500.0, 0.0), 0.0, "UNITED SYSTEMS • MORROW", Color.CYAN, false, false
	))
	var faction_station: Dictionary = combat.call("_enemy_by_id", faction_station_id)
	_assert(bool(faction_station.get("stationary", false)), "faction station must spawn as a fixed installation")
	_assert(bool(faction_station.get("combat_test_ship", false)), "faction station must participate in its side's combat roster")
	_assert(bool(faction_station.get("combat_active", false)), "faction station defenses must begin active")
	_assert(not bool(faction_station.get("combat_test_engage_npcs", true)), "station NPC engagement order must remain independent")
	var opponent_layout := load("res://resources/ship_designs/small_ship.tres") as Resource
	var opponent_id := int(combat.call(
		"spawn_combat_test_ship", opponent_layout, &"CHARTERED_COMBINE", 2,
		Vector2(0.0, 300.0), 0.0, "COMBINE TEST SHIP", Color.ORANGE, false
	))
	_assert((combat.call("_combat_target_for_enemy", faction_station, player) as Dictionary).is_empty(), "station with NPC hostility disabled must hold fire against rival teams")
	faction_station["combat_test_engage_npcs"] = true
	var station_target: Dictionary = combat.call("_combat_target_for_enemy", faction_station, player)
	_assert(int(station_target.get("enemy_id", -1)) == opponent_id, "station with NPC hostility enabled must engage a rival team")

	var neutral_id := int(combat.call("spawn_combat_test_neutral_station", layout, Vector2(500.0, 0.0), 0.0, "NEUTRAL MORROW"))
	var neutral: Dictionary = combat.call("_enemy_by_id", neutral_id)
	_assert(bool(neutral.get("combat_test_neutral_station", false)), "neutral station needs an explicit neutral test identity")
	_assert(not bool(combat.call("_enemy_should_defend", neutral)), "neutral station must hold fire before provocation")
	combat.call("_apply_damage_to_enemy", neutral, {
		"damage": 5.0, "shield_damage_multiplier": 1.0,
		"hull_damage_multiplier": 1.0, "system_damage_multiplier": 1.0,
		"faction": 2,
	})
	_assert(int(neutral.get("aggressor_combat_faction", -1)) == 2, "neutral station must remember the attacking faction")
	_assert(bool(combat.call("_enemy_should_defend", neutral)), "provoked neutral station must activate its defenses")
	_assert(not bool(neutral.get("hostile_to_player", false)), "a faction-provoked neutral station must not blame the player")

	world.queue_free()
	print("COMBAT TEST STATION ALLEGIANCE TEST // PASS")
	quit(0)


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error("COMBAT TEST STATION ALLEGIANCE TEST // FAIL // %s" % message)
	quit(1)
