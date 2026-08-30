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

	var start_button := main.get_node_or_null("%ForgeStartRunButton") as Button
	_check(start_button != null, "Forge menu omitted START RUN", failures)
	main.call("_start_escape_run")
	await process_frame
	var prologue: RunPrologueTerminal = main.get("run_prologue_terminal")
	_check(is_instance_valid(prologue) and prologue.visible, "prologue did not open", failures)
	_check(paused, "prologue did not pause the world", failures)

	prologue.call("_confirm")
	await process_frame
	var run_state: RunState = main.get("run_state")
	var starter_terminal: StartingShipTerminal = main.get("starting_ship_terminal")
	_check(run_state.run_active, "confirming the escape did not start run pressure", failures)
	_check(is_instance_valid(starter_terminal) and starter_terminal.visible, "prologue did not hand off to hangar choice", failures)
	var candidates: Array[Dictionary] = starter_terminal.candidates
	_check(candidates.size() == 3, "hangar did not produce three escape hulls", failures)
	if candidates.size() == 3:
		starter_terminal.call("_engage_candidate", 0)
		await create_timer(0.45, true).timeout
		await process_frame
		var ship := get_first_node_in_group("ship_simulation")
		_check(is_instance_valid(ship), "run lost the player ship", failures)
		_check(main.get("pending_jump_destination") != null, "chosen ship did not commit the opening jump", failures)
		_check(String((main.get("selected_starter_candidate") as Dictionary).get("name", "")).length() > 0, "starter selection was not retained", failures)
		var inventory: Dictionary = ship.call("get_grid_piece_inventory")
		_check(inventory.is_empty(), "fresh escape hull inherited dev inventory", failures)

	if not failures.is_empty():
		for failure: String in failures:
			push_error("RUN START FLOW TEST // FAIL // %s" % failure)
		quit(1)
		return
	print("RUN START FLOW TEST // PASS // PROLOGUE -> THREE HULLS -> OPENING JUMP")
	quit(0)


func _check(condition: bool, message: String, failures: PackedStringArray) -> void:
	if not condition:
		failures.append(message)
