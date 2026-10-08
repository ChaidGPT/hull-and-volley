extends SceneTree

const RANDOMIZER := preload("res://scripts/starting_ship_randomizer.gd")
const TERMINAL := preload("res://scripts/starting_ship_terminal.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failures := PackedStringArray()
	var randomizer := RANDOMIZER.new() as StartingShipRandomizer
	var rounds: Array[Dictionary] = randomizer.generate_draft_rounds(8675309)
	_check(rounds.size() == 3, "opening did not create three salvage rounds", failures)
	for round_data: Dictionary in rounds:
		var options: Array = round_data.get("options", [])
		_check(options.size() == 2, "a salvage round did not offer exactly two choices", failures)
		var keys: Dictionary = {}
		for option_value: Variant in options:
			var option := option_value as Dictionary
			var key := String(option.get("inventory_key", ""))
			keys[key] = true
			_check(not key.is_empty(), "draft option omitted its inventory key", failures)
			_check(option.get("preview_layout") is Resource, "%s omitted a visual preview layout" % key, failures)
			_check(option.get("descriptor") is Dictionary, "%s omitted its grid requirements" % key, failures)
		_check(keys.size() == options.size(), "a salvage round offered the same grid twice", failures)

	var host := Control.new()
	root.add_child(host)
	var terminal := TERMINAL.new() as StartingShipTerminal
	host.add_child(terminal)
	terminal.open_terminal(rounds)
	await process_frame
	await process_frame
	_check(terminal.visible, "salvage terminal did not open", failures)
	_check(paused, "salvage terminal did not pause gameplay", failures)
	var first_round_previews := terminal.find_children("*", "ShipBuilderPreview", true, false)
	_check(first_round_previews.size() == 2, "first round did not show two visual grid choices", failures)
	for preview_node: Node in first_round_previews:
		var preview := preview_node as ShipBuilderPreview
		var deck_visual := preview.get_node_or_null("AuthoredDeckVisual") as Control
		_check(is_instance_valid(deck_visual), "draft choice fell back to blueprint shorthand", failures)
		if is_instance_valid(deck_visual):
			_check(deck_visual.scale.x > 3.0, "authored choice artwork remained too small", failures)
			_check(not deck_visual.find_children("WeaponMount_*", "Node2D", true, false).is_empty(), "weapon choice omitted its authored mount visual", failures)

	for round_data: Dictionary in rounds:
		var options: Array = round_data.get("options", [])
		terminal.call("_select_draft_option", options[0])
		await process_frame
	var drafted_keys: Array = terminal.get("drafted_inventory_keys")
	_check(drafted_keys.size() == 3, "terminal did not retain one grid from every round", failures)
	var manifest_buttons := terminal.find_children("*", "Button", true, false)
	var found_assembly_action := false
	for button_node: Node in manifest_buttons:
		var button := button_node as Button
		found_assembly_action = found_assembly_action or button.text.contains("OPEN ASSEMBLY BAY")
	_check(found_assembly_action, "completed draft did not offer the assembly bay", failures)

	await terminal.close_terminal()
	_check(not terminal.visible and not paused, "salvage terminal did not restore gameplay state", failures)
	if not failures.is_empty():
		for failure: String in failures:
			push_error("STARTING SHIP DRAFT TEST // FAIL // %s" % failure)
		quit(1)
		return
	print("STARTING SHIP DRAFT TEST // PASS // THREE VISUAL SALVAGE CHOICES")
	quit(0)


func _check(condition: bool, message: String, failures: PackedStringArray) -> void:
	if not condition:
		failures.append(message)
