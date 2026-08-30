extends SceneTree

const COMBAT_SIMULATION := preload("res://scripts/combat_simulation.gd")
const SHIP_LAYOUT := preload("res://scripts/resources/ship_layout_resource.gd")
const ROOM_LAYOUT := preload("res://scripts/resources/room_layout_data.gd")
const EXPLOSIVE_CANNON := preload("res://resources/weapons/longshot_cannon.tres")
const CANNON_TEXTURE := preload("res://assets/sprites/weapons/authored/explosive_cannon_mount.png")
const LONGSHOT_PROJECTILE := preload("res://scenes/projectiles/longshot_projectile.tscn")
const GRID_GEOMETRY := preload("res://scripts/grid_geometry.gd")
const WEAPON_MOUNT_SOCKET := preload("res://scripts/weapon_mount_socket.gd")


func _init() -> void:
	var failures := PackedStringArray()
	_check(CANNON_TEXTURE.get_width() == 48, "authored cannon must be three 16px tiles wide", failures)
	_check(CANNON_TEXTURE.get_height() == 96, "authored cannon must be six 16px tiles long", failures)
	var mount_scene := EXPLOSIVE_CANNON.get("mount_visual_scene") as PackedScene
	_check(mount_scene != null, "explosive cannon must provide a reusable mount scene", failures)
	var scene_muzzle_offset := Vector2.ZERO
	if mount_scene != null:
		var mount_visual := mount_scene.instantiate() as Node2D
		_check(mount_visual.get_node_or_null("Muzzle") is Marker2D, "mount scene must own a Muzzle marker", failures)
		_check(mount_visual.get_node_or_null("TurretBase") is Marker2D, "mount scene must expose the center of its round turret base", failures)
		_check(mount_visual.get_node_or_null("Sprite") is Sprite2D, "mount scene must own its cannon sprite", failures)
		_check(mount_visual.get_node_or_null("AnimationPlayer") is AnimationPlayer, "mount scene must be ready for authored firing animations", failures)
		scene_muzzle_offset = Vector2(mount_visual.call("get_authored_muzzle_offset"))
		_check(scene_muzzle_offset.is_equal_approx(Vector2(0.0, 9.0)), "scene muzzle marker must resolve to the new barrel's exact bottom-center tip", failures)
		mount_visual.call("set_installed_facing_quarters", 0)
		_check(Vector2(mount_visual.call("get_authored_muzzle_offset")).rotated(float(mount_visual.rotation)).is_equal_approx(-scene_muzzle_offset), "north-facing mount must rotate its marker to the visible barrel tip", failures)
		mount_visual.free()

	var room: Resource = ROOM_LAYOUT.new()
	room.set("room_id", &"authored_cannon_test")
	room.set("type_name", "WEAPONS")
	var cannon_rects: Array[Rect2i] = [Rect2i(0, 0, 2, 2)]
	room.set("grid_rects", cannon_rects)
	room.set("module_facing_quarters", 2)
	room.set("weapon_definition", EXPLOSIVE_CANNON)
	var layout: Resource = SHIP_LAYOUT.new()
	layout.set("lattice_version", 2)
	layout.set("rooms", [room])

	var combat: Node = COMBAT_SIMULATION.new()
	var mount: Dictionary = combat.call("_get_mount_data", layout, room, Vector2.ZERO, 0.0)
	var bounds: Rect2i = layout.call("get_occupied_bounds")
	var geometry_size: Vector2 = GRID_GEOMETRY.grid_pixel_size(layout, bounds, 10.0)
	var rendered_room := GRID_GEOMETRY.cell_rect(layout, Vector2i.ZERO, bounds, 10.0)
	rendered_room.size = Vector2(20.0, 20.0)
	var expected_socket := WEAPON_MOUNT_SOCKET.standard_room_socket_position(rendered_room, 2) - geometry_size * 0.5
	_check(Vector2(mount.get("position", Vector2.INF)).is_equal_approx(expected_socket), "cannon pivot must sit at the room socket", failures)
	_check(Vector2(mount.get("muzzle_offset", Vector2.INF)).is_equal_approx(scene_muzzle_offset), "mount must preserve the authored muzzle offset", failures)
	_check(is_equal_approx(float(mount.get("muzzle_clearance", 0.0)), scene_muzzle_offset.length()), "muzzle clearance must match the authored socket-to-tip distance", failures)
	var spawn: Vector2 = combat.call("_projectile_spawn_position", mount, Vector2.RIGHT)
	_check(spawn.is_equal_approx(expected_socket + scene_muzzle_offset), "south-facing projectile must begin at the authored barrel tip", failures)
	_check(not spawn.is_equal_approx(expected_socket + Vector2.RIGHT * scene_muzzle_offset.length()), "aim must not slide the projectile origin away from the visible muzzle", failures)
	_check(Vector2(mount.get("muzzle_position", Vector2.INF)).is_equal_approx(spawn), "mount must carry the scene muzzle as one authoritative world-space socket", failures)
	var automatic_mount: Dictionary = combat.call("_resolve_firing_mount", mount, spawn + Vector2(0.0, 100.0), EXPLOSIVE_CANNON)
	_check(not automatic_mount.is_empty(), "automatic fire must resolve the authored cannon", failures)
	_check(Vector2(combat.call("_projectile_spawn_position", automatic_mount, Vector2.DOWN)).is_equal_approx(spawn), "automatic target resolution must not lose or move the scene muzzle", failures)
	var manual_mount: Dictionary = combat.call("_resolve_firing_mount_for_bearing", mount, Vector2.DOWN, Vector2(0.05, 1.0), EXPLOSIVE_CANNON)
	_check(not manual_mount.is_empty(), "manual fire must resolve the authored cannon", failures)
	_check(Vector2(combat.call("_projectile_spawn_position", manual_mount, Vector2.DOWN)).is_equal_approx(spawn), "manual battery resolution must not lose or move the scene muzzle", failures)

	var rotated_mount: Dictionary = combat.call("_get_mount_data", layout, room, Vector2(73.0, -19.0), PI * 0.5)
	var rotated_spawn: Vector2 = combat.call("_projectile_spawn_position", rotated_mount, Vector2.UP)
	var expected_rotated_socket := Vector2(73.0, -19.0) + expected_socket.rotated(PI * 0.5)
	_check(rotated_spawn.is_equal_approx(expected_rotated_socket + scene_muzzle_offset.rotated(PI * 0.5)), "ship rotation must rotate the muzzle socket with the visible cannon", failures)

	# Reproduce a real refit layout: the cannon begins on a half-offset cell,
	# while other occupied cells expand the ship bounds.  The renderer anchors
	# the full cannon room to that first cell; combat must not average the mount
	# back toward the unshifted cells in the room.
	var staggered_room: Resource = ROOM_LAYOUT.new()
	staggered_room.set("room_id", &"staggered_cannon_test")
	staggered_room.set("type_name", "WEAPONS")
	var staggered_rects: Array[Rect2i] = [Rect2i(3, 1, 2, 2)]
	staggered_room.set("grid_rects", staggered_rects)
	staggered_room.set("module_facing_quarters", 0)
	staggered_room.set("weapon_definition", EXPLOSIVE_CANNON)
	var ballast_room: Resource = ROOM_LAYOUT.new()
	ballast_room.set("room_id", &"ballast")
	ballast_room.set("type_name", "UNASSIGNED")
	var ballast_rects: Array[Rect2i] = [Rect2i(-2, -1, 2, 2)]
	ballast_room.set("grid_rects", ballast_rects)
	var staggered_layout: Resource = SHIP_LAYOUT.new()
	staggered_layout.set("lattice_version", 2)
	staggered_layout.set("rooms", [staggered_room, ballast_room])
	staggered_layout.call("set_cell_offset", Vector2i(3, 1), Vector2(0.5, 0.5))
	var staggered_bounds: Rect2i = staggered_layout.call("get_occupied_bounds")
	var staggered_geometry_size: Vector2 = GRID_GEOMETRY.grid_pixel_size(staggered_layout, staggered_bounds, 10.0)
	var rendered_piece := GRID_GEOMETRY.cell_rect(staggered_layout, Vector2i(3, 1), staggered_bounds, 10.0)
	rendered_piece.size = Vector2(20.0, 20.0)
	var expected_staggered_socket := WEAPON_MOUNT_SOCKET.standard_room_socket_position(rendered_piece, 0) - staggered_geometry_size * 0.5
	var staggered_mount: Dictionary = combat.call("_get_mount_data", staggered_layout, staggered_room, Vector2.ZERO, 0.0)
	var staggered_spawn: Vector2 = combat.call("_projectile_spawn_position", staggered_mount, Vector2.LEFT)
	_check(Vector2(staggered_mount.get("position", Vector2.INF)).is_equal_approx(expected_staggered_socket), "staggered cannon pivot must match the rendered piece rectangle", failures)
	_check(staggered_spawn.is_equal_approx(expected_staggered_socket - scene_muzzle_offset), "staggered cannon projectile must begin at its visible north-facing muzzle", failures)

	var projectile_visual := LONGSHOT_PROJECTILE.instantiate() as Node2D
	root.add_child(projectile_visual)
	var trail := projectile_visual.get_node_or_null("Trail") as Line2D
	if trail != null:
		projectile_visual.call("set_travel_distance", 0.0)
		_check(not trail.visible, "a newly spawned shell cannot begin with a full trail behind the muzzle", failures)
		projectile_visual.call("set_travel_distance", 8.0)
		_check(trail.visible and trail.points[0].x >= -8.01, "trail may only extend across distance the shell has actually travelled", failures)
		projectile_visual.call("set_travel_distance", 40.0)
		_check(trail.points[0].is_equal_approx(Vector2(-28.0, 0.0)), "full authored trail returns after sufficient travel", failures)
	projectile_visual.queue_free()
	combat.free()

	if not failures.is_empty():
		for failure: String in failures:
			push_error("AUTHORED EXPLOSIVE CANNON TEST - FAIL - %s" % failure)
		quit(1)
		return
	print("AUTHORED EXPLOSIVE CANNON TEST - PASS - SOCKET AND MUZZLE ARE LOCKED TO ART")
	quit(0)


func _check(condition: bool, message: String, failures: PackedStringArray) -> void:
	if not condition:
		failures.append(message)
