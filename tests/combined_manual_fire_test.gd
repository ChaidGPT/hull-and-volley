extends SceneTree

const COMBAT_SIMULATION := preload("res://scripts/combat_simulation.gd")
const SHIP_LAYOUT_RESOURCE := preload("res://scripts/resources/ship_layout_resource.gd")
const ROOM_LAYOUT_DATA := preload("res://scripts/resources/room_layout_data.gd")
const LONGSHOT_CANNON := preload("res://resources/weapons/longshot_cannon.tres")


class TestPlayer:
	extends Node

	var ship_layout: Resource
	var ship_position := Vector2.ZERO
	var ship_rotation := 0.0
	var velocity := Vector2.ZERO
	var physics_body: RigidBody2D


	func get_weapon_mount_efficiency(_room_id: StringName, _mount_index: int) -> float:
		return 1.0


func _initialize() -> void:
	var physics_world := Node2D.new()
	root.add_child(physics_world)
	physics_world.add_to_group("physics_world")

	var layout: Resource = SHIP_LAYOUT_RESOURCE.new()
	layout.set("lattice_version", 2)
	layout.set("columns", 8)
	layout.set("rows", 8)

	# Two independently installed 2x2 cannons share one combined room. Keep the
	# old/stale installed count deliberately: physical grid pieces are the source
	# of truth for mounts after like rooms combine.
	var cannons: Resource = ROOM_LAYOUT_DATA.new()
	cannons.set("room_id", &"combined_explosive_cannons")
	cannons.set("display_name", "EXPLOSIVE CANNON BATTERY")
	cannons.set("type_name", "WEAPONS")
	var cannon_rects: Array[Rect2i] = [
		Rect2i(Vector2i(2, 2), Vector2i(2, 2)),
		Rect2i(Vector2i(2, 4), Vector2i(2, 2)),
	]
	cannons.set("grid_rects", cannon_rects)
	cannons.set("installed_piece_count", 1)
	cannons.set("module_facing_quarters", 1)
	cannons.set("module_mount_facings", [1, 1])
	cannons.set("weapon_definition", LONGSHOT_CANNON)
	var rooms: Array[Resource] = [cannons]
	layout.set("rooms", rooms)

	var player := TestPlayer.new()
	player.ship_layout = layout
	player.physics_body = RigidBody2D.new()
	player.physics_body.set_meta("ship_id", 0)
	physics_world.add_child(player.physics_body)
	root.add_child(player)

	var combat := COMBAT_SIMULATION.new()
	root.add_child(combat)
	await process_frame
	var fired_count: int = combat.fire_direct_volley(player, Vector2.RIGHT)
	var opening_projectiles: Array = combat.get("projectiles")
	_assert(opening_projectiles.size() == 1, "bow cannon begins the ripple volley immediately")
	_assert(
		StringName(combat.call("get_weapon_operation_state", 0, 0, &"combined_explosive_cannons", 0).get("state", &"")) == &"FIRING",
		"bow cannon did not enter reload when its shot left the muzzle"
	)
	_assert(
		StringName(combat.call("get_weapon_operation_state", 0, 0, &"combined_explosive_cannons", 1).get("state", &"")) != &"FIRING",
		"stern cannon entered reload before its queued shot fired"
	)
	_assert(
		combat.fire_direct_volley(player, Vector2.RIGHT) == 0,
		"a repeated trigger press double-booked the active battery"
	)
	combat.set("manual_fire_clock", float(combat.get("manual_fire_clock")) + 0.2)
	combat.call("_update_manual_fire_sequence")
	var projectiles: Array = combat.get("projectiles")

	_assert(fired_count == 2, "two staffed touching cannons scheduled %d shots" % fired_count)
	_assert(projectiles.size() == 2, "volley created %d projectile records" % projectiles.size())
	if projectiles.size() < 2:
		return
	var first_position := Vector2(projectiles[0]["position"])
	var second_position := Vector2(projectiles[1]["position"])
	_assert(not first_position.is_equal_approx(second_position), "both cannon shots used one shared muzzle")
	_assert(first_position.y < second_position.y, "manual battery did not ripple from bow to stern")
	_assert(
		StringName(combat.call("get_weapon_operation_state", 0, 0, &"combined_explosive_cannons", 0).get("state", &"")) == &"FIRING",
		"first cannon did not enter its own reload state"
	)
	_assert(
		StringName(combat.call("get_weapon_operation_state", 0, 0, &"combined_explosive_cannons", 1).get("state", &"")) == &"FIRING",
		"second cannon did not enter its own reload state"
	)

	print("COMBINED MANUAL FIRE TEST - PASS - TWO MOUNTS, TWO MUZZLES, TWO RELOADS")
	quit(0)


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error("COMBINED MANUAL FIRE TEST - FAIL - %s" % message)
	quit(1)
