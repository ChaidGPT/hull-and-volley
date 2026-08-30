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
	var powered_rooms: Dictionary = {}
	var staffed_rooms: Dictionary = {}


	func get_weapon_mount_efficiency(room_id: StringName, mount_index: int) -> float:
		if mount_index != 0:
			return 0.0
		return 1.0 if bool(powered_rooms.get(room_id, false)) and int(staffed_rooms.get(room_id, 0)) >= 2 else 0.0


func _initialize() -> void:
	var physics_world := Node2D.new()
	root.add_child(physics_world)
	physics_world.add_to_group("physics_world")

	var layout: Resource = SHIP_LAYOUT_RESOURCE.new()
	layout.set("lattice_version", 2)
	layout.set("columns", 10)
	layout.set("rows", 10)
	var bow_cannon := _weapon_room(&"port_bow_cannon", Rect2i(Vector2i(2, 2), Vector2i(2, 2)))
	var stern_cannon := _weapon_room(&"port_stern_cannon", Rect2i(Vector2i(2, 4), Vector2i(2, 2)))
	var rooms: Array[Resource] = [bow_cannon, stern_cannon]
	layout.set("rooms", rooms)

	var player := TestPlayer.new()
	player.ship_layout = layout
	player.powered_rooms = {&"port_bow_cannon": true, &"port_stern_cannon": true}
	player.staffed_rooms = {&"port_bow_cannon": 2, &"port_stern_cannon": 2}
	player.physics_body = RigidBody2D.new()
	player.physics_body.set_meta("ship_id", 0)
	physics_world.add_child(player.physics_body)
	root.add_child(player)

	var combat := COMBAT_SIMULATION.new()
	root.add_child(combat)
	await process_frame

	var scheduled := combat.fire_direct_volley(player, Vector2.LEFT)
	_assert(scheduled == 2, "two powered and staffed side cannons scheduled %d shots" % scheduled)
	_assert((combat.get("projectiles") as Array).size() == 1, "the first cannon did not begin the ripple immediately")
	_assert((combat.get("pending_manual_fire") as Array).size() == 1, "the second independent cannon was not queued")
	combat.set("manual_fire_clock", float(combat.get("manual_fire_clock")) + 0.2)
	combat.call("_update_manual_fire_sequence")
	var projectiles: Array = combat.get("projectiles")
	_assert(projectiles.size() == 2, "the two independent rooms created %d projectiles" % projectiles.size())
	_assert(
		StringName(combat.call("get_weapon_operation_state", 0, 0, &"port_bow_cannon", 0).get("state", &"")) == &"FIRING",
		"the bow cannon did not enter its own reload"
	)
	_assert(
		StringName(combat.call("get_weapon_operation_state", 0, 0, &"port_stern_cannon", 0).get("state", &"")) == &"FIRING",
		"the stern cannon did not enter its own reload"
	)
	_assert(
		combat.fire_direct_volley(player, Vector2.LEFT) == 0,
		"the independent cannon cooldowns did not block a duplicate volley"
	)

	print("SEPARATE SIDE WEAPON FIRE TEST - PASS - TWO ROOMS, TWO SHOTS, TWO RELOADS")
	quit(0)


func _weapon_room(room_id: StringName, rect: Rect2i) -> Resource:
	var room: Resource = ROOM_LAYOUT_DATA.new()
	room.set("room_id", room_id)
	room.set("display_name", "EXPLOSIVE CANNON MOUNT")
	room.set("type_name", "WEAPONS")
	var rects: Array[Rect2i] = [rect]
	room.set("grid_rects", rects)
	room.set("installed_piece_count", 1)
	room.set("module_facing_quarters", 3)
	room.set("module_mount_facings", [3])
	room.set("minimum_crew", 2)
	room.set("optimal_crew", 2)
	room.set("weapon_definition", LONGSHOT_CANNON)
	return room


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error("SEPARATE SIDE WEAPON FIRE TEST - FAIL - %s" % message)
	quit(1)
