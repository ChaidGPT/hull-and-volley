extends SceneTree

const COMBAT_SIMULATION := preload("res://scripts/combat_simulation.gd")
const PHYSICS_PROJECTILE := preload("res://scenes/physics_projectile.tscn")
const STARTING_LAYOUT := preload("res://resources/starting_ship_layout.tres")


func _init() -> void:
	var combat: CombatSimulation = COMBAT_SIMULATION.new()
	root.add_child(combat)
	var body := RigidBody2D.new()
	root.add_child(body)
	body.global_position = Vector2(140.0, -80.0)
	body.linear_velocity = Vector2(18.0, 7.0)
	var enemy := {
		"id": 77,
		"hull": 0.0,
		"maximum_hull": 100.0,
		"position": body.global_position,
		"previous_position": body.global_position,
		"rotation": body.global_rotation,
		"previous_rotation": body.global_rotation,
		"velocity": body.linear_velocity,
		"physics_body": body,
		"layout": STARTING_LAYOUT,
		"combat_active": true,
		"player_targetable": true,
		"stationary": false,
	}
	var requested_effects: Array[Vector2] = []
	combat.impact_effect_requested.connect(
		func(_collider: RigidBody2D, point: Vector2, _normal: Vector2, _color: Color, _scene: PackedScene) -> void:
			requested_effects.append(point)
	)
	combat.call("_begin_enemy_destruction", enemy)
	_assert(bool(enemy.get("destruction_active", false)), "destroyed ship should enter a staged state")
	_assert(not bool(enemy.get("combat_active", true)), "doomed ship should stop fighting")
	_assert(body.linear_velocity == Vector2(18.0, 7.0), "doomed ship should retain its drift velocity")
	var finished := bool(combat.call("_update_enemy_destruction", enemy, 0.05))
	_assert(not finished, "destruction should not finish on its opening burst")
	_assert(requested_effects.size() == 1, "opening localized explosion should be requested")
	finished = bool(combat.call("_update_enemy_destruction", enemy, 10.0))
	_assert(finished, "destruction should finish after its authored delay")

	# A normal pool reset remains safe and verifies the corrected cleanup path is
	# parsed and callable on the actual projectile scene.
	var projectile := PHYSICS_PROJECTILE.instantiate() as PhysicsProjectile
	root.add_child(projectile)
	projectile.prepare_for_pool()

	projectile.free()
	body.free()
	combat.free()
	print("STAGED SHIP DESTRUCTION TEST // PASS")
	quit(0)


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error("STAGED SHIP DESTRUCTION TEST // FAIL // %s" % message)
	quit(1)
