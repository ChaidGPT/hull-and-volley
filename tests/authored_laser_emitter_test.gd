extends SceneTree

const LASER := preload("res://resources/weapons/laser_emitter.tres")
const LASER_TEXTURE := preload("res://assets/sprites/weapons/authored/laser_emitter_mount.png")
const COMBAT_SIMULATION := preload("res://scripts/combat_simulation.gd")
const SHIP_LAYOUT := preload("res://scripts/resources/ship_layout_resource.gd")
const ROOM_LAYOUT := preload("res://scripts/resources/room_layout_data.gd")


func _init() -> void:
	var failures := PackedStringArray()
	_check(LASER_TEXTURE.get_width() == 32, "laser art must keep the shared two-tile width", failures)
	_check(LASER_TEXTURE.get_height() == 64, "laser art must keep the shared four-tile mount canvas", failures)
	var mount_scene := LASER.get("mount_visual_scene") as PackedScene
	_check(mount_scene != null, "laser emitter must provide a reusable mount scene", failures)
	if mount_scene != null:
		var mount := mount_scene.instantiate() as Node2D
		_check(mount.get_node_or_null("Sprite") is Sprite2D, "laser mount must own its sprite", failures)
		_check(mount.get_node_or_null("TurretBase") is Marker2D, "laser mount must expose the shared round-base pivot", failures)
		_check(mount.get_node_or_null("Muzzle") is Marker2D, "laser mount must own its muzzle", failures)
		_check(mount.get_node_or_null("AnimationPlayer") is AnimationPlayer, "laser mount must be animation-ready", failures)
		_check(Vector2(mount.call("get_authored_muzzle_offset")).is_equal_approx(Vector2(0.0, 4.3125)), "laser muzzle must resolve to the visible barrel tip", failures)
		mount.call("set_installed_facing_quarters", 0)
		_check(Vector2(mount.call("get_authored_muzzle_offset")).rotated(float(mount.rotation)).is_equal_approx(Vector2(0.0, -4.3125)), "north-facing laser must rotate its muzzle with its sprite", failures)
		var installed_rotation := float(mount.rotation)
		mount.call("aim_toward_parent_direction", Vector2(1.0, -1.0).normalized())
		var traverse_offset := absf(angle_difference(installed_rotation, float(mount.rotation)))
		_check(traverse_offset > 0.01, "laser sprite must visibly traverse toward an aim bearing", failures)
		_check(traverse_offset <= deg_to_rad(float(LASER.get("traverse_degrees"))) + 0.001, "laser sprite traverse must respect its authored arc", failures)
		mount.free()

	var room: Resource = ROOM_LAYOUT.new()
	room.set("room_id", &"authored_laser_test")
	room.set("type_name", "WEAPONS")
	var laser_rects: Array[Rect2i] = [Rect2i(0, 0, 2, 2)]
	room.set("grid_rects", laser_rects)
	room.set("module_facing_quarters", 1)
	room.set("weapon_definition", LASER)
	var layout: Resource = SHIP_LAYOUT.new()
	layout.set("lattice_version", 2)
	layout.set("rooms", [room])
	var combat: Node = COMBAT_SIMULATION.new()
	var mount_data: Dictionary = combat.call("_get_mount_data", layout, room, Vector2.ZERO, 0.0)
	var expected_offset := Vector2(4.3125, 0.0)
	var actual_offset_value: Variant = mount_data.get("muzzle_offset", Vector2.INF)
	var actual_offset := actual_offset_value as Vector2 if actual_offset_value is Vector2 else Vector2.INF
	var mount_position: Vector2 = mount_data.get("position", Vector2.INF)
	var spawn_position: Vector2 = combat.call("_projectile_spawn_position", mount_data, Vector2.RIGHT)
	_check(actual_offset.is_equal_approx(expected_offset), "east-facing combat mount must use the laser scene's muzzle", failures)
	_check(spawn_position.is_equal_approx(mount_position + expected_offset), "projectile center must begin exactly at the laser muzzle", failures)
	combat.free()

	if not failures.is_empty():
		for failure: String in failures:
			push_error("AUTHORED LASER EMITTER TEST - FAIL - %s" % failure)
		quit(1)
		return
	print("AUTHORED LASER EMITTER TEST - PASS - SPRITE AND MUZZLE SHARE THE CANNON CONTRACT")
	quit(0)


func _check(condition: bool, message: String, failures: PackedStringArray) -> void:
	if not condition:
		failures.append(message)
