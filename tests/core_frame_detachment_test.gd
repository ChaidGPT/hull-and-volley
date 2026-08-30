extends SceneTree


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failures := PackedStringArray()
	var layout := ShipLayoutResource.new()
	layout.lattice_version = 2
	layout.unlimited_build_space = true
	layout.build_origin = Vector2i.ZERO
	layout.columns = 2
	layout.rows = 2

	var core := _room(&"bridge", "BRIDGE", Rect2i(Vector2i.ZERO, Vector2i(2, 2)), 100.0)
	layout.rooms = [core]
	layout.capture_core_frame()
	var extension := _room(&"weapon_extension", "WEAPONS", Rect2i(Vector2i(2, 0), Vector2i(1, 1)), 30.0)
	layout.rooms.append(extension)

	_check(layout.is_core_rect(core.grid_rects[0]), "starting footprint was not captured as permanent core", failures)
	_check(not layout.rect_contains_core(extension.grid_rects[0]), "later extension was incorrectly promoted into the core", failures)
	_check(layout.can_place_footprint(Vector2i(500, -300), Vector2i(2, 2)), "unlimited workbench still rejects distant coordinates", failures)
	_check(layout.get_build_bounds().has_point(Vector2i(2, 0)), "dynamic workbench bounds do not follow the hull", failures)

	var ship := ShipSimulation.new()
	ship.ship_layout = layout
	ship.shield_installed = false
	ship.extension_detachment_overdamage_multiplier = 2.0
	root.add_child(ship)
	await process_frame
	var detached_events: Array[Dictionary] = []
	ship.module_detached.connect(func(_piece_key: String, _condition: Dictionary, _position: Vector2, _velocity: Vector2) -> void:
		detached_events.append({"piece_key": _piece_key})
	)

	ship.apply_combat_damage(30.0, &"weapon_extension", Vector2.RIGHT, 0.0, 0.0, 1.0, 1.0, Vector2i(2, 0))
	_check(ship.is_module_piece_disabled(&"weapon_extension", 0), "extension did not enter disabled state at local durability limit", failures)
	_check(_has_room(layout, &"weapon_extension"), "extension detached before catastrophic overdamage", failures)
	ship.apply_combat_damage(60.0, &"weapon_extension", Vector2.RIGHT, 0.0, 0.0, 1.0, 1.0, Vector2i(2, 0))
	_check(not _has_room(layout, &"weapon_extension"), "extension remained attached after catastrophic overdamage", failures)
	_check(_has_room(layout, &"bridge"), "core frame was removed with its extension", failures)
	_check(detached_events.size() == 1, "detachment did not emit exactly one physical salvage event", failures)

	ship.apply_combat_damage(300.0, &"bridge", Vector2.UP, 0.0, 0.0, 1.0, 1.0, Vector2i(0, 0))
	_check(_has_room(layout, &"bridge"), "core module was allowed to detach", failures)
	ship.apply_combat_damage(0.0, &"bridge", Vector2.UP, 0.0, 0.0, 0.0, 0.0, Vector2i(0, 0), 2.0)
	var ion_status: Dictionary = ship.get_module_piece_status(&"bridge", 0)
	_check(float(ion_status.get("ion_seconds", 0.0)) > 1.9, "ion disruption did not disable the struck module", failures)
	ship.call("_update_module_disable_timers", 2.1)
	ion_status = ship.get_module_piece_status(&"bridge", 0)
	_check(float(ion_status.get("ion_seconds", 0.0)) <= 0.001, "ion disruption did not recover after its duration", failures)

	ship.queue_free()
	if failures.is_empty():
		print("CORE FRAME DETACHMENT TEST PASS")
		quit(0)
	else:
		for failure: String in failures:
			push_error(failure)
		quit(1)


func _room(id: StringName, type_name: String, rect: Rect2i, health: float) -> RoomLayoutData:
	var room := RoomLayoutData.new()
	room.room_id = id
	room.display_name = type_name
	room.type_name = type_name
	room.grid_rects = [rect]
	room.maximum_health = health
	room.minimum_crew = 0
	room.optimal_crew = 0
	return room


func _has_room(layout: ShipLayoutResource, room_id: StringName) -> bool:
	for room: Resource in layout.rooms:
		if StringName(room.get("room_id")) == room_id:
			return true
	return false


func _check(condition: bool, message: String, failures: PackedStringArray) -> void:
	if not condition:
		failures.append(message)
