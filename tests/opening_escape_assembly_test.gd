extends SceneTree

const MAIN_SCENE := preload("res://scenes/main.tscn")
const RANDOMIZER := preload("res://scripts/starting_ship_randomizer.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failures := PackedStringArray()
	var main := MAIN_SCENE.instantiate()
	root.add_child(main)
	await process_frame
	await process_frame

	var randomizer := RANDOMIZER.new() as StartingShipRandomizer
	var rounds: Array[Dictionary] = randomizer.generate_draft_rounds(424242)
	var drafted: Array[String] = []
	for round_data: Dictionary in rounds:
		var options: Array = round_data.get("options", [])
		drafted.append(String((options[0] as Dictionary).get("inventory_key", "")))
	var package := {
		"name": "TEST ESCAPE HULL",
		"role": "ASSEMBLY TEST",
		"draft_inventory": drafted,
	}
	main.call("_apply_starter_candidate", package)
	var ship := get_first_node_in_group("ship_simulation")
	_check(is_instance_valid(ship), "starter draft did not retain a ship simulation", failures)
	if is_instance_valid(ship):
		var layout := ship.get("ship_layout") as Resource
		var installed_types: Array[String] = []
		for room: Resource in layout.get("rooms"):
			installed_types.append(String(room.get("type_name")))
		_check(installed_types == ["COMMAND"], "escape assembly did not begin from a bridge-only keel: %s" % str(installed_types), failures)
		var inventory: Dictionary = ship.call("get_grid_piece_inventory")
		_check(int(inventory.get("WEAPON:light_ballistic_mount", 0)) == 2, "starter did not receive two light ballistic turrets", failures)
		for required_key: String in ["CREW_QUARTERS", "POWER", "PROPULSION"]:
			_check(int(inventory.get(required_key, 0)) >= 1, "guaranteed %s grid was missing" % required_key, failures)
		for drafted_key: String in drafted:
			_check(int(inventory.get(drafted_key, 0)) >= drafted.count(drafted_key), "drafted %s grid was missing" % drafted_key, failures)

	main.set("run_start_pending", true)
	main.call("_open_escape_assembly")
	await process_frame
	var builder := main.get("ship_builder_screen") as ShipBuilderScreen
	_check(is_instance_valid(builder) and builder.visible, "escape assembly bay did not open", failures)
	if is_instance_valid(builder):
		_check(String(builder.get("inventory_mode")) == "ESCAPE", "assembly bay did not use finite escape inventory", failures)
		_check(String(builder.get("current_context")) == "edit", "assembly bay did not open directly on the build grid", failures)
		_check(String(builder.get("close_terminal_button").text).contains("BEGIN RUN"), "assembly bay did not present launch as its completion action", failures)
		# Construction order must not make unpowered exterior hardware impossible
		# to mount. Install a connected reactor down-hull, then place a quarter-grid
		# shield outside its radius; it should mount offline instead of being rejected.
		_drop_inventory_piece(builder, "CREW_QUARTERS", Vector2i(4, 6))
		await process_frame
		_drop_inventory_piece(builder, "POWER", Vector2i(4, 8))
		await process_frame
		_drop_inventory_piece(builder, "SHIELDS", Vector2i(3, 4))
		await process_frame
		var shield_installed := false
		for room: Resource in (ship.get("ship_layout") as Resource).get("rooms"):
			shield_installed = shield_installed or String(room.get("type_name")) == "SHIELDS"
		_check(shield_installed, "unpowered quarter-grid shield was rejected from a legal exterior mount", failures)
		_check(
			String(builder.get("builder_status_label").text).contains("INSTALLED OFFLINE"),
			"unpowered shield placement did not explain its offline state",
			failures
		)
	var run_state := get_first_node_in_group("run_state") as RunState
	_check(is_instance_valid(run_state) and not run_state.run_active, "run clock started before ship assembly launched", failures)

	main.set("escape_assembly_pending", false)
	if is_instance_valid(builder):
		await builder.close()
	if not failures.is_empty():
		for failure: String in failures:
			push_error("OPENING ESCAPE ASSEMBLY TEST // FAIL // %s" % failure)
		quit(1)
		return
	print("OPENING ESCAPE ASSEMBLY TEST // PASS // FIXED KEEL + FINITE DRAFT INVENTORY")
	quit(0)


func _check(condition: bool, message: String, failures: PackedStringArray) -> void:
	if not condition:
		failures.append(message)


func _drop_inventory_piece(builder: ShipBuilderScreen, room_type: String, cell: Vector2i) -> void:
	var inventory_grid := builder.get("forge_inventory_grid") as Control
	if inventory_grid == null:
		return
	for child: Node in inventory_grid.get_children():
		if "room_type" in child and String(child.get("room_type")) == room_type:
			builder.call("_on_forge_inventory_piece_dropped", room_type, cell, child.get_instance_id())
			return
