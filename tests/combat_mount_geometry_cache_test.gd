extends SceneTree

const COMBAT_SIMULATION := preload("res://scripts/combat_simulation.gd")
const WEAPON_BLUEPRINT := preload("res://resources/ship_designs/small_ship_2.tres")


func _init() -> void:
	var combat: Node = COMBAT_SIMULATION.new()
	var mounts: Array[Resource] = []
	for room: Resource in WEAPON_BLUEPRINT.get("rooms"):
		if String(room.get("type_name")) != "WEAPONS":
			continue
		for mount_index: int in range(int(combat.call("_weapon_mount_count", room))):
			mounts.append(combat.call("_weapon_mount_room", room, mount_index))
	_assert(not mounts.is_empty(), "station fixture needs weapon mounts")

	for mount: Resource in mounts:
		combat.call("_get_mount_data", WEAPON_BLUEPRINT, mount, Vector2.ZERO, 0.0)
	var warmed_count := int(combat.get("mount_geometry_cache").size())
	_assert(warmed_count == mounts.size(), "every station mount should have one cached geometry record")

	var started := Time.get_ticks_usec()
	for pass_index: int in range(250):
		var rotation := float(pass_index) * 0.013
		for mount: Resource in mounts:
			combat.call("_get_mount_data", WEAPON_BLUEPRINT, mount, Vector2(240.0, -80.0), rotation)
	var elapsed_ms := float(Time.get_ticks_usec() - started) / 1000.0
	_assert(int(combat.get("mount_geometry_cache").size()) == warmed_count, "moving ships must reuse static hull geometry")
	print("COMBAT MOUNT CACHE TEST // PASS // %d MOUNTS // 250 POSES IN %.2f MS" % [mounts.size(), elapsed_ms])
	combat.free()
	quit(0)


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error("COMBAT MOUNT CACHE TEST // FAIL // %s" % message)
	quit(1)
