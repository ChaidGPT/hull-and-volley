extends SceneTree

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var main := preload("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	var ship := get_first_node_in_group("ship_simulation")
	var combat := get_first_node_in_group("combat_simulation")
	var hud: Control = main.current_view.get_node("WeaponsHUD")
	assert(not hud.visible, "Wheel should be hidden during flight")
	var room := preload("res://scripts/resources/room_layout_data.gd").new()
	room.room_id = &"hud_test_battery"
	room.type_name = "WEAPONS"
	room.weapon_definition = preload("res://resources/weapons/longshot_cannon.tres")
	room.installed_piece_count = 50
	for index: int in range(50):
		room.grid_rects.append(Rect2i(index * 2, 12, 2, 2))
		room.module_mount_facings.append(index % 4)
	var layout: Resource = ship.ship_layout
	var old_rooms: Array = layout.get("rooms").duplicate()
	layout.get("rooms").clear()
	layout.get("rooms").append(room)
	var prior_scale := Engine.time_scale
	var event := InputEventKey.new()
	event.keycode = KEY_R
	event.pressed = true
	main.call("_input", event)
	assert(hud.opened and hud.visible, "R must open the wheel")
	assert(is_equal_approx(Engine.time_scale, prior_scale * 0.15), "Wheel should slow time")
	assert(main.current_view.controller_menu_active, "Wheel must suppress helm input")
	assert(hud.entries.size() == 50, "Every mount must be represented")
	assert(hud.visible_entries.size() == 4, "Large batteries must use direction selection")
	hud.selected = "group:0"
	hud.call("_accept")
	assert(hud.expanded_direction == 0 and hud.visible_entries.size() == 12, "Direction should expand to a readable page")
	hud.call("_change_page", 1)
	assert(hud.visible_entries.size() == 1, "Thirteenth forward weapon must be reachable")
	hud.call("_change_page", -1)
	var first: Dictionary = hud.visible_entries[0]
	var icon_point: Vector2 = hud.center + Vector2.from_angle(first.angle) * hud.radius
	hud.call("_point_at", icon_point)
	assert(hud.selected == first.key, "Hover must show the pointed weapon")
	assert(room.get_weapon_fire_mode(first.mount_index) == 0, "Hover must not change mode")
	hud.call("_accept")
	assert(room.get_weapon_fire_mode(first.mount_index) == 1, "Selected mount mode was not changed")
	assert(room.get_weapon_fire_mode(1) == 0, "Neighboring mount mode was changed")
	hud.call("_accept")
	assert(room.get_weapon_fire_mode(first.mount_index) == 2, "Cycle must advance to Sentry")
	hud.call("_accept")
	assert(room.get_weapon_fire_mode(first.mount_index) == 0, "Cycle must wrap to Linked")
	hud.call("_accept")
	assert(not combat.call("_weapon_mount_uses_automatic_fire", room, first.mount_index), "Trigger mount must not autofire")
	combat.player_weapon_cooldowns[first.key] = 2.0
	combat.call("_mark_weapon_fired", 0, 0, room.room_id, first.mount_index, 4.0)
	hud.call("_refresh")
	assert(is_equal_approx(hud.call("_selected_entry").progress, 0.5), "Wheel must follow actual cooldown")
	assert(hud.call("_weapon_texture", room.weapon_definition) != null, "Actual turret art missing")
	for i: int in range(1, hud.entries.size()):
		assert(not combat.weapon_firing_order_before(hud.entries[i], hud.entries[i-1]), "Wheel differs from volley order")
	hud.call("_back")
	assert(hud.expanded_direction == -1 and hud.opened, "B should return to four directions")
	event.pressed = false
	main.call("_input", event)
	assert(not hud.opened and not hud.visible, "Release must close the wheel")
	assert(is_equal_approx(Engine.time_scale, prior_scale), "Closing must restore time")
	assert(not main.current_view.controller_menu_active, "Closing must release helm input")
	hud.call("open_wheel")
	layout.get("rooms").clear()
	hud.call("_refresh")
	assert(hud.entries.is_empty(), "Removed weapons must not remain selectable")
	hud.call("_notification", Control.NOTIFICATION_APPLICATION_FOCUS_OUT)
	assert(not hud.opened and is_equal_approx(Engine.time_scale, prior_scale), "Focus loss must restore flight")
	layout.get("rooms").assign(old_rooms)
	var button := InputEventJoypadButton.new()
	button.button_index = JOY_BUTTON_LEFT_STICK
	button.pressed = true
	main.call("_input", button)
	assert(hud.opened, "Left-stick click must open the controller wheel")
	button.pressed = false
	main.call("_input", button)
	assert(not hud.opened, "Releasing left-stick click must close the wheel")
	assert(is_equal_approx(Engine.time_scale, prior_scale), "Stick release must restore time")
	assert(not main.current_view.controller_menu_active, "Stick release must restore helm input")
	button.pressed = true
	main.call("_input", button)
	button.button_index = JOY_BUTTON_B
	main.call("_input", button)
	assert(not hud.opened, "B must close the top-level controller wheel")
	assert(is_equal_approx(Engine.time_scale, prior_scale), "Controller close must restore time")
	main.queue_free()
	await process_frame
	print("WEAPON WHEEL TEST // PASS // 50 MOUNTS, PAGING, MODES, COOLDOWN, INPUT, TIME RESTORATION")
	quit(0)
