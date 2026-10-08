extends SceneTree

const PANEL_SCRIPT := preload("res://scripts/combat_test_setup_panel.gd")
const MAIN_SCRIPT := preload("res://scripts/main.gd")

var captured_configuration: Dictionary = {}


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var main := MAIN_SCRIPT.new()
	var catalog: Array[Dictionary] = main.call("_combat_test_blueprints")
	main.free()
	var panel := PANEL_SCRIPT.new()
	root.add_child(panel)
	await process_frame
	panel.open_panel(catalog)
	_assert(panel.ship_blueprints.size() >= 2, "scenario builder needs multiple saved ship choices")
	_assert(panel.station_blueprints.size() >= 2, "scenario builder needs saved station choices")

	var first_faction: Dictionary = panel.faction_controls[0]
	panel.call("_add_roster_row", first_faction, "res://resources/ship_designs/small_ship_2.tres", 3)
	_assert((first_faction["roster_rows"] as Array).size() == 2, "a faction must accept multiple ship-type rows")
	_select_path(first_faction["station_selector"] as OptionButton, "res://resources/ship_designs/morrow_proving_yard.tres")
	(first_faction["team_selector"] as OptionButton).select(1)
	(first_faction["station_hostile_player"] as CheckButton).button_pressed = true
	(first_faction["station_hostile_npcs"] as CheckButton).button_pressed = false
	_select_path(panel.neutral_station_selector, "res://resources/ship_designs/salvage_outpost.tres")
	panel.environment_selector.select(1)
	panel.scenario_requested.connect(_capture_configuration)
	panel.call("_request_scenario")
	_assert(StringName(captured_configuration.get("environment", &"")) == &"ASTEROID_FIELD", "selected environment must enter the scenario configuration")
	var factions: Array = captured_configuration.get("factions", [])
	_assert((factions[0].get("ships", []) as Array).size() == 2, "faction configuration must retain both roster entries")
	_assert(int(factions[0].get("combat_team", -1)) == 2, "faction team assignment must enter the scenario configuration")
	_assert(not String(factions[0].get("station_blueprint_path", "")).is_empty(), "faction station must be retained separately from ships")
	_assert(bool(factions[0].get("station_hostile_to_player", false)), "station player hostility must be independent")
	_assert(not bool(factions[0].get("station_hostile_to_npcs", true)), "station NPC hostility must be independent")
	_assert(not String((captured_configuration.get("neutral_station", {}) as Dictionary).get("blueprint_path", "")).is_empty(), "neutral station selection must be retained")
	panel.queue_free()
	print("COMBAT TEST SCENARIO BUILDER TEST // PASS")
	quit(0)


func _capture_configuration(configuration: Dictionary) -> void:
	captured_configuration = configuration


func _select_path(selector: OptionButton, path: String) -> void:
	for item_index: int in range(selector.item_count):
		if String(selector.get_item_metadata(item_index)) == path:
			selector.select(item_index)
			return
	_assert(false, "selector is missing expected path: %s" % path)


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error("COMBAT TEST SCENARIO BUILDER TEST // FAIL // %s" % message)
	quit(1)
