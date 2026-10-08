extends SceneTree

const MAIN_SCENE := preload("res://scenes/main.tscn")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failures := PackedStringArray()
	var main := MAIN_SCENE.instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	main.call("_refresh_parts_locker")
	await process_frame
	var locker := main.get("parts_locker_grid") as Container
	var workbench := main.get("parts_locker_workbench") as Control
	var refit_controller := main.get("parts_locker_refit_controller") as ShipBuilderScreen
	var locker_panel := main.get_node("%LogisticsOverviewPanel") as Control
	_check(locker != null, "parts locker did not create an inventory grid", failures)
	_check(locker is ForgeInventoryGrid, "parts locker is not using the blueprint inventory component", failures)
	_check(workbench != null and workbench.get_script() == preload("res://scripts/settlement_grid.gd"), "parts locker still uses a passive hull preview instead of the live editor", failures)
	_check(refit_controller != null and bool(refit_controller.get("embedded_refit_mode")), "parts locker did not bind the drydock controller inline", failures)
	_check(locker != null and int(locker.get("capacity_rows")) == 3, "parts locker does not expose the full three-row starting hold", failures)
	_check(locker != null and bool(locker.get("bounded_capacity")), "parts locker starting hold is still unbounded", failures)
	_check(locker != null and is_equal_approx(locker.custom_minimum_size.y, 84.0), "parts locker grid is not exactly three cargo rows tall", failures)
	_check(workbench != null and workbench.custom_minimum_size.x <= 340.0, "parts locker workbench still consumes the tactical viewport", failures)
	var locker_frame := main.find_child("PartsLockerFrame", true, false) as Control
	_check(locker_frame != null and locker_frame.size_flags_horizontal == Control.SIZE_SHRINK_CENTER, "cargo case is not centered beneath the workbench", failures)
	_check(main.get("parts_locker_resource_host") != null, "inline refit is missing its power and crew rail", failures)
	if locker_panel != null:
		locker_panel.visible = true
		await process_frame
		var viewport_size := root.get_visible_rect().size
		var panel_rect := locker_panel.get_global_rect()
		_check(panel_rect.end.y <= viewport_size.y + 0.5, "parts locker extends below the game viewport", failures)
		_check(panel_rect.size.x <= 520.0, "parts locker became too wide for simultaneous flight", failures)
		_check(locker != null and locker.get_global_rect().end.y <= panel_rect.end.y + 0.5, "cargo grid is clipped below the locker frame", failures)
	var settlement_button := main.get_node("%SettlementButton") as Button
	_check(settlement_button != null and not settlement_button.visible, "obsolete Deck tab is still present in flight navigation", failures)
	var ship_view := main.get("current_view") as Control
	var tactical_visual := ship_view.get_node_or_null("%PlaceholderShip") as Control if ship_view != null else null
	var tactical_zoom := ship_view.get_node_or_null("%ZoomController") if ship_view != null else null
	var live_deck_visual := ship_view.get_node_or_null("World/LiveDeckDetail") as Control if ship_view != null else null
	var live_shield_visual := ship_view.get("shield_visual") as Control if ship_view != null else null
	_check(tactical_visual != null and tactical_visual.has_method("set_deck_detail_visible"), "tactical ship cannot resolve into its deck plan", failures)
	_check(live_deck_visual != null, "unified command view is missing its authored ship layer", failures)
	_check(live_shield_visual != null and live_shield_visual.get_parent() == live_deck_visual, "active shield field is still attached to the hidden tactical silhouette", failures)
	if tactical_visual != null and tactical_zoom != null:
		tactical_zoom.call("set_zoom_level", 2.5)
		ship_view.call("_process", 0.016)
		_check(live_deck_visual != null and live_deck_visual.visible and live_deck_visual.modulate.a > 0.99, "close tactical zoom does not reveal deck detail", failures)
		_check(live_deck_visual != null and float(live_deck_visual.get("crew_detail_alpha")) > 0.99, "crew do not resolve at close tactical zoom", failures)
		var player_layout: Resource = main.get_node("ShipSimulation").get("ship_layout")
		var first_room: Resource = player_layout.get("rooms")[0] if player_layout != null and not player_layout.get("rooms").is_empty() else null
		if first_room != null:
			ship_view.call("_select_compartment", first_room)
			await process_frame
			var compartment_actions := ship_view.find_child("CompartmentActions", true, false) as Control
			_check(compartment_actions != null and compartment_actions.visible, "close-up ship click cannot open the compartment CRT", failures)
			_check(StringName(ship_view.get("selected_compartment_id")) == StringName(first_room.get("room_id")), "compartment CRT did not retain the clicked room", failures)
		tactical_zoom.call("set_zoom_level", float(ship_view.get("deck_detail_zoom")))
		ship_view.call("_process", 0.016)
		_check(float(ship_view.get("deck_detail_mix")) > 0.0 and float(ship_view.get("deck_detail_mix")) < 1.0, "close-range interaction detail does not blend smoothly", failures)
		tactical_zoom.call("set_zoom_level", 1.0)
		ship_view.call("_process", 0.016)
		_check(live_deck_visual != null and live_deck_visual.visible and live_deck_visual.modulate.a > 0.99, "authored ship visuals disappear at tactical zoom", failures)
		_check(live_deck_visual != null and float(live_deck_visual.get("crew_detail_alpha")) < 0.01, "crew remain fully rendered at distant tactical zoom", failures)
		_check(tactical_visual.modulate.a < 0.01, "legacy tactical silhouette is still painted over the authored ship", failures)
		_check(StringName(ship_view.get("selected_compartment_id")) == &"", "compartment CRT remains open after returning to tactical zoom", failures)
		ship_view.call("_select_tactical_ship", 0)
		await create_timer(0.35).timeout
		var self_contact_panel := ship_view.get_node_or_null("%TargetingPanel") as Control
		_check(self_contact_panel != null and not self_contact_panel.visible, "player ship still opens the redundant generic contact panel", failures)
		_check(float((tactical_visual.get("tactical_module_seam_color") as Color).a) > 0.0, "tactical hull module seams are invisible", failures)
	var refit_context := main.get("parts_locker_refit_context") as Control
	var facing_selector := refit_controller.get("builder_facing_actions") as Control if refit_controller != null else null
	var dossier := refit_controller.get("dossier_panel") as Control if refit_controller != null else null
	_check(refit_context != null and refit_context.custom_minimum_size.x <= 132.0, "selected-grid rail still reserves too much width", failures)
	_check(facing_selector != null and facing_selector.custom_minimum_size.x <= 94.0 and facing_selector.custom_minimum_size.y <= 70.0, "direction selector is still using the labelled wide layout", failures)
	_check(dossier != null and dossier.size_flags_horizontal == Control.SIZE_SHRINK_END, "selected-grid dossier still stretches across spare workbench space", failures)
	_check(not _contains_button_text(main, "OPEN REFIT DECK >"), "parts locker still requires the redundant refit-deck button", failures)
	if workbench != null:
		(main.get("logistics_overview_panel") as Control).visible = true
		await process_frame
		workbench.call("fit_editor_view_to_hull")
		var occupied_bounds: Rect2i = (workbench.get("ship_layout") as Resource).call("get_occupied_bounds", false)
		var occupied_content_rect := workbench.call("_get_grid_rect", occupied_bounds) as Rect2
		var occupied_screen_center := Vector2(workbench.get("editor_view_pan")) + occupied_content_rect.get_center() * float(workbench.get("editor_view_zoom"))
		_check(occupied_screen_center.distance_to(workbench.size * 0.5) <= 1.5, "opening hull fit does not center the actual ship", failures)
		var fitted_hull_height := occupied_content_rect.size.y * float(workbench.get("editor_view_zoom"))
		_check(fitted_hull_height >= workbench.size.y * 0.5, "opening hull fit still renders a small ship too far away", failures)
		var initial_zoom := float(workbench.get("editor_view_zoom"))
		var zoom_event := InputEventMouseButton.new()
		zoom_event.button_index = MOUSE_BUTTON_WHEEL_UP
		zoom_event.pressed = true
		zoom_event.position = workbench.get_global_rect().get_center()
		workbench.call("_input", zoom_event)
		_check(float(workbench.get("editor_view_zoom")) > initial_zoom, "mouse wheel does not zoom the embedded workbench", failures)
		workbench.call("adjust_editor_zoom", 10.0)
		var pan_before := Vector2(workbench.get("editor_view_pan"))
		var pan_press := InputEventMouseButton.new()
		pan_press.button_index = MOUSE_BUTTON_MIDDLE
		pan_press.pressed = true
		pan_press.position = workbench.size * 0.5
		workbench.call("_gui_input", pan_press)
		# The tactical HUD refreshes the locker every frame; that refresh must not
		# cancel a held camera drag between press and motion events.
		main.call("_refresh_parts_locker")
		var pan_motion := InputEventMouseMotion.new()
		pan_motion.position = workbench.size * 0.5 - Vector2(24.0, 12.0)
		pan_motion.relative = Vector2(-24.0, -12.0)
		pan_motion.button_mask = MOUSE_BUTTON_MASK_MIDDLE
		workbench.call("_gui_input", pan_motion)
		_check(not Vector2(workbench.get("editor_view_pan")).is_equal_approx(pan_before), "middle-mouse drag does not pan the embedded workbench", failures)
		var left_pan_before := Vector2(workbench.get("editor_view_pan"))
		var left_press := InputEventMouseButton.new()
		left_press.button_index = MOUSE_BUTTON_LEFT
		left_press.pressed = true
		left_press.position = Vector2(8.0, 8.0)
		workbench.call("_gui_input", left_press)
		var left_motion := InputEventMouseMotion.new()
		left_motion.position = Vector2(-14.0, -6.0)
		left_motion.relative = Vector2(-22.0, -14.0)
		left_motion.button_mask = MOUSE_BUTTON_MASK_LEFT
		workbench.call("_gui_input", left_motion)
		var left_release := InputEventMouseButton.new()
		left_release.button_index = MOUSE_BUTTON_LEFT
		left_release.pressed = false
		left_release.position = left_motion.position
		workbench.call("_gui_input", left_release)
		_check(not Vector2(workbench.get("editor_view_pan")).is_equal_approx(left_pan_before), "empty-space left drag still draws a selection instead of panning", failures)
		workbench.set("editor_view_panning", false)
		workbench.set("editor_view_pan_with_left", false)
		var workbench_layout := workbench.get("ship_layout") as Resource
		var workbench_rooms: Array = workbench_layout.get("rooms") if workbench_layout != null else []
		if not workbench_rooms.is_empty():
			# The commissioned starting footprint is now the permanent frame. Add a
			# genuine refit extension before exercising the lift/return interaction.
			workbench_layout.call("capture_core_frame", true)
			var core_rects: Array = workbench_rooms[0].get("grid_rects")
			if not core_rects.is_empty():
				var core_rect: Rect2i = core_rects[0]
				var core_content := (workbench.call("_get_grid_rect", core_rect) as Rect2).get_center()
				workbench.call("_begin_installed_piece_drag", workbench_rooms[0], core_rect.position, core_content, core_content)
				_check((workbench.get("installed_drag_data") as Dictionary).is_empty(), "permanent core frame can still be lifted", failures)
			var extension := RoomLayoutData.new()
			extension.room_id = &"inventory_test_extension"
			extension.display_name = "TEST EXTENSION"
			extension.type_name = "UNASSIGNED"
			var occupied: Rect2i = workbench_layout.call("get_occupied_bounds")
			extension.grid_rects = [Rect2i(Vector2i(occupied.end.x, occupied.position.y), Vector2i.ONE)]
			extension.installed_piece_count = 1
			workbench_layout.get("rooms").append(extension)
			workbench_rooms = workbench_layout.get("rooms")
			var first_rects: Array = extension.get("grid_rects")
			if not first_rects.is_empty():
				var first_rect: Rect2i = first_rects[0]
				var source_content := (workbench.call("_get_grid_rect", first_rect) as Rect2).get_center()
				workbench.call("_begin_installed_piece_drag", extension, first_rect.position, source_content + Vector2(18.0, 12.0), source_content)
				var installed_drag: Dictionary = workbench.get("installed_drag_data")
				_check(not installed_drag.is_empty(), "placed hull piece never enters a lifted drag state", failures)
				_check(installed_drag.has("source_rect"), "lifted hull piece does not retain its physical source footprint", failures)
				_check(Vector2(workbench.get("installed_drag_pointer_position")) != Vector2.INF, "lifted hull piece is not attached to the cursor", failures)
				workbench.call("_return_installed_piece_to_source")
				_check(bool(workbench.get("installed_drag_returning")), "released hull piece does not begin its return flight", failures)
				_check(not (workbench.get("installed_drag_data") as Dictionary).is_empty(), "source phase socket vanishes before the returning piece arrives", failures)
				await create_timer(0.24).timeout
				_check((workbench.get("installed_drag_data") as Dictionary).is_empty(), "returned hull piece remains detached after reaching its source", failures)
				_check(not bool(workbench.get("installed_drag_returning")), "hull piece remains in returning state after rematerializing", failures)
	var ship := get_first_node_in_group("ship_simulation")
	var expected_count := 0
	if is_instance_valid(ship):
		for count: Variant in (ship.call("get_grid_piece_inventory") as Dictionary).values():
			expected_count += maxi(int(count), 0)
	var actual_count := 0
	if locker != null:
		for child: Node in locker.get_children():
			if child is ForgeInventoryPiece:
				actual_count += 1
				_check(bool(child.get("drag_enabled")), "tactical locker piece could not be rearranged", failures)
	_check(actual_count == expected_count, "parts locker did not render one physical brick per stored grid", failures)
	if locker != null:
		var locker_pieces: Array[Control] = []
		for child: Node in locker.get_children():
			if child is ForgeInventoryPiece:
				locker_pieces.append(child as Control)
		if locker_pieces.size() >= 2:
			await process_frame
			var neighbor_slot := Vector2i(locker_pieces[1].get("inventory_position"))
			locker.call("begin_piece_drag", locker_pieces[0])
			await process_frame
			_check(Vector2i(locker_pieces[1].get("inventory_position")) == neighbor_slot, "picking up cargo automatically repacked neighboring grids", failures)
			locker.call("restore_catalog_piece", locker_pieces[0].get_instance_id())
	var scooch_grid := ForgeInventoryGrid.new()
	scooch_grid.manual_layout = true
	scooch_grid.set_capacity_rows(3, true)
	root.add_child(scooch_grid)
	var wide_piece := ForgeInventoryPiece.new()
	wide_piece.configure("TEST_WIDE", "TEST WIDE", Color.WHITE, Vector2i(3, 1), 0, 0, "TEST_WIDE", null, 91001, {"inventory_position": Vector2i(0, 0)})
	var blocker_piece := ForgeInventoryPiece.new()
	blocker_piece.configure("TEST_BLOCKER", "TEST BLOCKER", Color.WHITE, Vector2i(1, 1), 0, 0, "TEST_BLOCKER", null, 91002, {"inventory_position": Vector2i(4, 0)})
	scooch_grid.add_child(wide_piece)
	scooch_grid.add_child(blocker_piece)
	await process_frame
	scooch_grid.call("begin_piece_drag", wide_piece)
	scooch_grid.call("_layout_manual_inventory")
	_check(not wide_piece.visible, "inventory sort put the held piece back into its source cells", failures)
	var scooch_data := {
		"kind": "forge_grid_piece",
		"source_instance_id": wide_piece.get_instance_id(),
		"footprint": Vector2i(3, 1),
		"grab_offset": Vector2.ZERO,
	}
	_check(bool(scooch_grid.call("_can_drop_data", Vector2(ForgeInventoryGrid.CELL_SIZE, 0.0), scooch_data)), "held piece could not scooch one cell into its own vacated footprint", failures)
	_check(not bool(scooch_grid.call("_can_drop_data", Vector2(ForgeInventoryGrid.CELL_SIZE * 2.0, 0.0), scooch_data)), "held piece was allowed to overlap another cargo brick", failures)
	scooch_grid.call("_drop_data", Vector2(ForgeInventoryGrid.CELL_SIZE, 0.0), scooch_data)
	_check(Vector2i(wide_piece.inventory_position) == Vector2i(1, 0), "one-cell cargo move did not commit to the new slot", failures)
	_check(wide_piece.visible, "cargo brick stayed hidden after a valid overlapping move", failures)
	scooch_grid.queue_free()
	if is_instance_valid(ship):
		var added_ids: Array = ship.call("add_grid_piece", "TEST_UNSTACKED", 2)
		_check(added_ids.size() == 2, "adding two like grids did not create two cargo objects", failures)
		if added_ids.size() == 2:
			_check(int(added_ids[0]) != int(added_ids[1]), "like grids were assigned the same inventory identity", failures)
			ship.call("update_grid_piece_condition", int(added_ids[0]), {"current_health": 25.0})
			var first_item: Dictionary = ship.call("get_grid_piece_instance", int(added_ids[0]))
			var second_item: Dictionary = ship.call("get_grid_piece_instance", int(added_ids[1]))
			_check(is_equal_approx(float(first_item.get("current_health", 0.0)), 25.0), "first grid did not retain its own condition", failures)
			_check(is_equal_approx(float(second_item.get("current_health", 0.0)), 100.0), "damage leaked between identical inventory grids", failures)
			_check(bool(ship.call("consume_grid_piece", "TEST_UNSTACKED", int(added_ids[1]))), "exact grid could not be removed from cargo", failures)
			_check(not (ship.call("get_grid_piece_instance", int(added_ids[0])) as Dictionary).is_empty(), "removing one like grid removed its neighbor", failures)
			_check((ship.call("get_grid_piece_instance", int(added_ids[1])) as Dictionary).is_empty(), "selected grid identity remained after removal", failures)
			ship.call("consume_grid_piece", "TEST_UNSTACKED", int(added_ids[0]))
		ship.call("clear_grid_piece_inventory")
		var capacity_fill: Array = ship.call("add_grid_piece", "SHIELDS", 31)
		_check(capacity_fill.size() == 30, "starting cargo case accepted more than its 10 by 3 cells", failures)
		_check(not bool(ship.call("can_store_grid_piece", "SHIELDS")), "full starting cargo case still reports open space", failures)
	if not failures.is_empty():
		for failure: String in failures:
			push_error("SHARED GRID INVENTORY TEST // FAIL // %s" % failure)
		quit(1)
		return
	print("SHARED GRID INVENTORY TEST // PASS // TACTICAL + BLUEPRINT USE ONE COMPONENT")
	quit(0)


func _check(condition: bool, message: String, failures: PackedStringArray) -> void:
	if not condition:
		failures.append(message)


func _contains_button_text(node: Node, target_text: String) -> bool:
	if node is Button and (node as Button).text == target_text:
		return true
	for child: Node in node.get_children():
		if _contains_button_text(child, target_text):
			return true
	return false
