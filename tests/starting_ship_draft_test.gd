extends SceneTree

const RANDOMIZER := preload("res://scripts/starting_ship_randomizer.gd")
const TERMINAL := preload("res://scripts/starting_ship_terminal.gd")
const ANALYZER := preload("res://scripts/ship_builder_analyzer.gd")
const GRID_GEOMETRY := preload("res://scripts/grid_geometry.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failures := PackedStringArray()
	var randomizer: StartingShipRandomizer = RANDOMIZER.new() as StartingShipRandomizer
	var candidates: Array[Dictionary] = randomizer.generate_candidates(3, 8675309)
	_check(candidates.size() == 3, "randomizer did not create three starter hulls", failures)
	var archetypes: Dictionary = {}
	for candidate: Dictionary in candidates:
		var layout: Resource = candidate.get("layout")
		_check(layout != null, "candidate did not contain a real ship layout", failures)
		if layout == null:
			continue
		archetypes[candidate.get("archetype", "")] = true
		var counts: Dictionary = {}
		for room: Resource in layout.get("rooms"):
			var room_type := String(room.get("type_name"))
			counts[room_type] = int(counts.get(room_type, 0)) + 1
		for required_type: String in ["COMMAND", "CREW_QUARTERS", "POWER", "PROPULSION"]:
			_check(int(counts.get(required_type, 0)) >= 1, "%s starter omitted %s" % [candidate.get("name", "candidate"), required_type], failures)
		_check(_is_connected(layout), "%s starter hull was not physically connected" % candidate.get("name", "candidate"), failures)
		var stats: Dictionary = ANALYZER.analyze(layout, Vector2i(6, 8))
		_check(float(stats.get("energy_capacity", 0.0)) >= float(stats.get("energy_demand", 0.0)), "%s starter exceeded its reactor capacity" % candidate.get("name", "candidate"), failures)
		_check(int(stats.get("crew_capacity", 0)) >= int(stats.get("optimal_crew", 0)), "%s starter exceeded its crew capacity" % candidate.get("name", "candidate"), failures)
	_check(archetypes.size() == 3, "starter draft did not contain three distinct archetypes", failures)

	var host := Control.new()
	root.add_child(host)
	var terminal: StartingShipTerminal = TERMINAL.new() as StartingShipTerminal
	host.add_child(terminal)
	# Production opens the terminal in the same input frame in which it is
	# instantiated. Keep this immediate to guard against deferred CRT init races.
	terminal.open_terminal(candidates)
	await process_frame
	_check(terminal.visible, "starter terminal did not open", failures)
	_check(paused, "starter terminal did not pause gameplay", failures)
	var crt_frame: CrtContextPanel = terminal.get("frame")
	_check(crt_frame.visible and crt_frame.scale.x > 0.0, "starter CRT frame vanished after immediate open", failures)
	var choice_buttons := terminal.find_children("*", "Button", true, false)
	var candidate_card_count := 0
	for button_node: Node in choice_buttons:
		var candidate_button := button_node as Button
		if candidate_button.tooltip_text.begins_with("OPEN BLUEPRINT DOSSIER"):
			candidate_card_count += 1
	_check(candidate_card_count == 3, "candidate hulls were not exposed as three whole-card controls", failures)
	terminal.call("_show_focus", 0)
	await process_frame
	var title: Label = terminal.get("header_title")
	_check(title.text.contains(String(candidates[0].get("name", ""))), "focused blueprint did not identify the selected hull", failures)
	var focused_buttons := terminal.find_children("*", "Button", true, false)
	var clear_choose_action := false
	var clear_compare_action := false
	for button_node: Node in focused_buttons:
		var focused_button := button_node as Button
		clear_choose_action = clear_choose_action or focused_button.text.begins_with("CHOOSE ")
		clear_compare_action = clear_compare_action or focused_button.text.contains("COMPARE ALL THREE SHIPS")
	_check(clear_choose_action, "focused hull did not present a clear choose-this-ship action", failures)
	_check(clear_compare_action, "focused hull did not present a clear return-to-comparison action", failures)
	var previews := terminal.find_children("*", "ShipBuilderPreview", true, false)
	_check(not previews.is_empty(), "focused hull omitted its interactive blueprint", failures)
	if not previews.is_empty():
		var focused_preview := previews[0] as ShipBuilderPreview
		var first_room: Resource = (candidates[0].get("layout") as Resource).get("rooms")[0]
		_check(not String(focused_preview.call("_room_tooltip", first_room)).is_empty(), "blueprint rooms did not produce shipnet tooltip data", failures)
	await terminal.close_terminal()
	_check(not terminal.visible, "starter terminal did not close", failures)
	_check(not paused, "starter terminal did not restore gameplay pause state", failures)

	if not failures.is_empty():
		for failure: String in failures:
			push_error("STARTING SHIP DRAFT TEST // FAIL // %s" % failure)
		quit(1)
		return
	print("STARTING SHIP DRAFT TEST // PASS // 3 VALID HULLS + CRT INSPECTION FLOW")
	quit(0)


func _is_connected(layout: Resource) -> bool:
	var occupied := GRID_GEOMETRY.layout_cells(layout)
	if occupied.is_empty():
		return false
	var frontier: Array[Vector2i] = [occupied.keys()[0]]
	var visited: Dictionary = {frontier[0]: true}
	while not frontier.is_empty():
		var cell: Vector2i = frontier.pop_back()
		for direction: Vector2i in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
			var neighbor: Vector2i = cell + direction
			if occupied.has(neighbor) and not visited.has(neighbor):
				visited[neighbor] = true
				frontier.append(neighbor)
	return visited.size() == occupied.size()


func _check(condition: bool, message: String, failures: PackedStringArray) -> void:
	if not condition:
		failures.append(message)
