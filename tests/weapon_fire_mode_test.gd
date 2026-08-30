extends SceneTree

const ROOM_DATA := preload("res://scripts/resources/room_layout_data.gd")
const COMBAT_SIMULATION := preload("res://scripts/combat_simulation.gd")


func _init() -> void:
	var room: Resource = ROOM_DATA.new()
	room.set("type_name", "WEAPONS")
	room.set("installed_piece_count", 3)
	room.set("grid_rects", [
		Rect2i(Vector2i(0, 0), Vector2i.ONE),
		Rect2i(Vector2i(1, 0), Vector2i.ONE),
		Rect2i(Vector2i(2, 0), Vector2i.ONE),
	])
	room.call("set_weapon_fire_mode", 0, 0) # LINKED
	room.call("set_weapon_fire_mode", 1, 1) # TRIGGER
	room.call("set_weapon_fire_mode", 2, 2) # SENTRY

	var combat: Node = COMBAT_SIMULATION.new()
	combat.call("set_player_direct_fire_active", false)
	_assert(bool(combat.call("_weapon_mount_uses_automatic_fire", room, 0)), "LINKED should use automatic fire outside manual control")
	_assert(not bool(combat.call("_weapon_mount_uses_automatic_fire", room, 1)), "TRIGGER must never use automatic fire")
	_assert(bool(combat.call("_weapon_mount_uses_automatic_fire", room, 2)), "SENTRY should use automatic fire")

	combat.call("set_player_direct_fire_active", true)
	_assert(not bool(combat.call("_weapon_mount_uses_automatic_fire", room, 0)), "LINKED should hold automatic fire during manual control")
	_assert(not bool(combat.call("_weapon_mount_uses_automatic_fire", room, 1)), "TRIGGER should remain held for the player")
	_assert(bool(combat.call("_weapon_mount_uses_automatic_fire", room, 2)), "SENTRY should remain autonomous during manual control")
	_assert(bool(combat.call("_weapon_mount_accepts_manual_fire", room, 0)), "LINKED should accept the player trigger")
	_assert(bool(combat.call("_weapon_mount_accepts_manual_fire", room, 1)), "TRIGGER should accept the player trigger")
	_assert(not bool(combat.call("_weapon_mount_accepts_manual_fire", room, 2)), "SENTRY must ignore the player trigger")

	combat.free()
	print("WEAPON FIRE MODE TEST // PASS // LINKED + TRIGGER + SENTRY")
	quit(0)


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error("WEAPON FIRE MODE TEST // FAIL // %s" % message)
	quit(1)
