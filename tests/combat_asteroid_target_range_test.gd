extends SceneTree

const COMBAT_SIMULATION := preload("res://scripts/combat_simulation.gd")
const SECTOR_POPULATION := preload("res://scripts/sector_population.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var world := Node2D.new()
	root.add_child(world)
	var physics_world := Node2D.new()
	physics_world.name = "PhysicsWorld"
	physics_world.add_to_group("physics_world")
	world.add_child(physics_world)

	var combat: Node = COMBAT_SIMULATION.new()
	world.add_child(combat)
	var population: Node = SECTOR_POPULATION.new()
	population.set("populate_opening_sector", false)
	world.add_child(population)
	await process_frame
	var environment_count := int(population.call("spawn_combat_test_environment", &"ASTEROID_FIELD"))
	_assert(environment_count == 24, "Combat environment should deploy its physical navigation field")
	_assert(combat.call("_player_automatic_target_candidates").is_empty(), "Environment asteroids must not masquerade as hostile range targets")
	population.call("clear_combat_test_environment")
	await process_frame

	var spawned := int(population.call("spawn_combat_test_target_field", 40))
	_assert(spawned >= 30, "The massive range should produce a dense physical target field")
	var targets: Array[Dictionary] = combat.call("_player_automatic_target_candidates")
	_assert(targets.size() == spawned, "Every range asteroid should enter automatic weapon targeting")
	_assert(not combat.call("_nearest_enemy", Vector2.ZERO, targets).is_empty(), "Automatic weapons should acquire a range asteroid")

	var first_body := targets[0].get("physics_body") as RigidBody2D
	_assert(is_instance_valid(first_body), "Target records should retain their physical asteroid")
	first_body.call("apply_projectile_damage", 1000.0)
	await process_frame
	await process_frame
	var remaining: Array[Dictionary] = combat.call("_player_automatic_target_candidates")
	_assert(remaining.size() == spawned - 1, "Destroyed asteroids should immediately leave the target pool")

	population.call("clear_combat_test_target_field")
	await process_frame
	_assert(combat.call("_player_automatic_target_candidates").is_empty(), "Clearing the range should remove every asteroid target")
	world.queue_free()
	print("COMBAT ASTEROID TARGET RANGE TEST // PASS // %d TARGETS" % spawned)
	quit(0)


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error("COMBAT ASTEROID TARGET RANGE TEST // FAIL // %s" % message)
	quit(1)
