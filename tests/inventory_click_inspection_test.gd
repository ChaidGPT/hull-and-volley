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
	var controller := main.get("parts_locker_refit_controller") as ShipBuilderScreen
	var piece: ForgeInventoryPiece
	if locker != null:
		for child: Node in locker.get_children():
			if child is ForgeInventoryPiece:
				piece = child as ForgeInventoryPiece
				break
	if locker != null and piece == null:
		piece = ForgeInventoryPiece.new()
		piece.configure("TEST_GRID", "TEST GRID", Color(0.2, 0.8, 0.7), Vector2i(2, 2), 0, 1, "TEST_GRID", null, 9001, {}, 1)
		piece.selected.connect(Callable(main, "_on_parts_locker_piece_selected"))
		locker.add_child(piece)
		await process_frame
	_check(piece != null, "parts locker did not expose a loose grid piece", failures)
	_check(controller != null, "parts locker did not create its refit controller", failures)

	if piece != null and controller != null:
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = true
		piece.call("_gui_input", click)
		await process_frame
		_check(
			not bool(controller.call("has_embedded_inventory_piece_armed")),
			"a normal inventory click still armed hull placement",
			failures
		)
		_check(
			int(controller.get("inspected_inventory_piece_id")) == piece.get_instance_id(),
			"a normal inventory click did not select the grid for inspection",
			failures
		)
		var dossier := controller.get("dossier_panel") as Control
		var readout := controller.get("stat_label") as RichTextLabel
		_check(dossier != null and dossier.visible, "inventory inspection did not open its cargo profile", failures)
		_check(
			readout != null and "DRAG TO THE HULL TO INSTALL" in readout.text,
			"inventory inspection did not explain the drag-to-install gesture",
			failures
		)

		controller.call(
			"begin_embedded_inventory_piece_pickup",
			String(piece.get("room_type")),
			piece.get_instance_id()
		)
		_check(
			bool(controller.call("has_embedded_inventory_piece_armed")),
			"the explicit controller pickup action did not arm placement",
			failures
		)
		controller.call("cancel_embedded_inventory_piece")

	if failures.is_empty():
		print("INVENTORY CLICK INSPECTION TEST // PASS // CLICK INSPECTS, PICKUP INSTALLS")
		quit(0)
		return
	for failure: String in failures:
		push_error("INVENTORY CLICK INSPECTION TEST // FAIL // %s" % failure)
	quit(1)


func _check(condition: bool, message: String, failures: PackedStringArray) -> void:
	if not condition:
		failures.append(message)
