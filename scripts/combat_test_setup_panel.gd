class_name CombatTestSetupPanel
extends Control

signal scenario_requested(configuration: Dictionary)
signal asteroid_field_requested(target_count: int)
signal clear_requested
signal closed

const ASTEROID_TARGET_COUNT := 40

const FACTIONS: Array[Dictionary] = [
	{"id": &"UNITED_SYSTEMS", "name": "UNITED SYSTEMS", "combat_faction": 1, "color": Color(0.28, 0.88, 1.0)},
	{"id": &"CHARTERED_COMBINE", "name": "CHARTERED COMBINE", "combat_faction": 2, "color": Color(1.0, 0.68, 0.22)},
	{"id": &"FREE_SYSTEMS", "name": "FREE SYSTEMS", "combat_faction": 3, "color": Color(0.78, 0.42, 1.0)},
]

var faction_controls: Array[Dictionary] = []
var ship_blueprints: Array[Dictionary] = []
var station_blueprints: Array[Dictionary] = []
var environment_selector: OptionButton
var neutral_station_selector: OptionButton
var neutral_station_hostile_player: CheckButton
var neutral_station_hostile_npcs: CheckButton
var status_label: Label
var previous_pause_state := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_interface()
	visible = false


func _build_interface() -> void:
	var shade := ColorRect.new()
	shade.color = Color(0.005, 0.012, 0.016, 0.9)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(shade)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.offset_left = 24.0
	center.offset_top = 24.0
	center.offset_right = -24.0
	center.offset_bottom = -24.0
	add_child(center)

	var frame := PanelContainer.new()
	frame.custom_minimum_size = Vector2(1080.0, 640.0)
	frame.add_theme_stylebox_override("panel", _panel_style(Color(0.12, 0.95, 0.86), Color(0.006, 0.025, 0.026, 0.98), 2))
	center.add_child(frame)
	var margin := MarginContainer.new()
	for side: String in ["left", "right"]:
		margin.add_theme_constant_override("margin_%s" % side, 22)
	for side: String in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, 18)
	frame.add_child(margin)

	var root_box := VBoxContainer.new()
	root_box.add_theme_constant_override("separation", 10)
	margin.add_child(root_box)
	var title := Label.new()
	title.text = "COMBAT TESTING • SCENARIO CONTROL"
	title.add_theme_color_override("font_color", Color(0.68, 1.0, 0.95))
	title.add_theme_font_size_override("font_size", 23)
	root_box.add_child(title)
	var intro := Label.new()
	intro.text = "Build each faction's roster, assign optional station support, then choose the battlespace. Neutral stations remain uninvolved until attacked."
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.add_theme_color_override("font_color", Color(0.48, 0.78, 0.76))
	intro.add_theme_font_size_override("font_size", 12)
	root_box.add_child(intro)

	var environment_row := HBoxContainer.new()
	environment_row.add_theme_constant_override("separation", 12)
	root_box.add_child(environment_row)
	var environment_label := Label.new()
	environment_label.text = "BATTLESPACE"
	environment_label.custom_minimum_size.x = 150.0
	environment_label.add_theme_color_override("font_color", Color(0.35, 0.72, 0.7))
	environment_row.add_child(environment_label)
	environment_selector = OptionButton.new()
	environment_selector.custom_minimum_size = Vector2(270.0, 36.0)
	environment_selector.add_item("CLEAR SPACE")
	environment_selector.set_item_metadata(0, &"CLEAR_SPACE")
	environment_selector.add_item("ASTEROID FIELD")
	environment_selector.set_item_metadata(1, &"ASTEROID_FIELD")
	environment_row.add_child(environment_selector)

	var roster_scroll := ScrollContainer.new()
	roster_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	roster_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root_box.add_child(roster_scroll)
	var faction_list := VBoxContainer.new()
	faction_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	faction_list.add_theme_constant_override("separation", 8)
	roster_scroll.add_child(faction_list)
	for faction: Dictionary in FACTIONS:
		_build_faction_card(faction_list, faction)

	var neutral_row := HBoxContainer.new()
	neutral_row.add_theme_constant_override("separation", 12)
	root_box.add_child(neutral_row)
	var neutral_label := Label.new()
	neutral_label.text = "NEUTRAL INSTALLATION"
	neutral_label.custom_minimum_size.x = 210.0
	neutral_label.add_theme_color_override("font_color", Color(0.62, 0.72, 0.7))
	neutral_row.add_child(neutral_label)
	neutral_station_selector = OptionButton.new()
	neutral_station_selector.custom_minimum_size = Vector2(340.0, 36.0)
	neutral_row.add_child(neutral_station_selector)
	neutral_station_hostile_player = CheckButton.new()
	neutral_station_hostile_player.text = "VS PLAYER"
	neutral_row.add_child(neutral_station_hostile_player)
	neutral_station_hostile_npcs = CheckButton.new()
	neutral_station_hostile_npcs.text = "VS NPC TEAMS"
	neutral_row.add_child(neutral_station_hostile_npcs)

	status_label = Label.new()
	status_label.text = "RANGE CLEAR • AWAITING SCENARIO"
	status_label.add_theme_color_override("font_color", Color(0.22, 0.95, 0.84))
	status_label.add_theme_font_size_override("font_size", 12)
	root_box.add_child(status_label)
	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_END
	actions.add_theme_constant_override("separation", 10)
	root_box.add_child(actions)
	var range_button := _action_button("AUTOMATIC-FIRE RANGE", Color(0.78, 0.48, 1.0))
	range_button.tooltip_text = "Deploy 40 destructible asteroid targets for testing Linked and Sentry fire."
	range_button.pressed.connect(_request_asteroid_field)
	actions.add_child(range_button)
	var clear_button := _action_button("CLEAR RANGE", Color(1.0, 0.38, 0.28))
	clear_button.pressed.connect(_request_clear)
	actions.add_child(clear_button)
	var close_button := _action_button("RETURN TO FLIGHT", Color(0.42, 0.76, 0.76))
	close_button.pressed.connect(close_panel)
	actions.add_child(close_button)
	var deploy_button := _action_button("DEPLOY SCENARIO >", Color(1.0, 0.72, 0.2))
	deploy_button.pressed.connect(_request_scenario)
	actions.add_child(deploy_button)


func _build_faction_card(parent: VBoxContainer, faction: Dictionary) -> void:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _panel_style(faction["color"].darkened(0.5), Color(0.008, 0.035, 0.035, 0.92), 1))
	parent.add_child(card)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 5)
	card.add_child(content)
	var header := HBoxContainer.new()
	content.add_child(header)
	var faction_label := Label.new()
	faction_label.text = String(faction["name"])
	faction_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	faction_label.add_theme_color_override("font_color", faction["color"])
	faction_label.add_theme_font_size_override("font_size", 15)
	header.add_child(faction_label)
	var team_label := Label.new()
	team_label.text = "TEAM"
	team_label.add_theme_color_override("font_color", Color(0.48, 0.78, 0.76))
	team_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_child(team_label)
	var team_selector := OptionButton.new()
	team_selector.custom_minimum_size = Vector2(125.0, 30.0)
	for team_number: int in range(1, 4):
		team_selector.add_item("TEAM %s" % String.chr(64 + team_number))
		team_selector.set_item_metadata(team_selector.item_count - 1, team_number)
	team_selector.select(clampi(int(faction.get("combat_faction", 1)) - 1, 0, 2))
	header.add_child(team_selector)
	var hostile := CheckButton.new()
	hostile.text = "FLEET VS PLAYER"
	header.add_child(hostile)
	var roster_list := VBoxContainer.new()
	roster_list.add_theme_constant_override("separation", 4)
	content.add_child(roster_list)
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 8)
	content.add_child(footer)
	var add_ship := Button.new()
	add_ship.text = "+ ADD SHIP TYPE"
	add_ship.custom_minimum_size = Vector2(160.0, 30.0)
	footer.add_child(add_ship)
	var station_row := HBoxContainer.new()
	station_row.add_theme_constant_override("separation", 8)
	content.add_child(station_row)
	var station_label := Label.new()
	station_label.text = "STATION"
	station_label.add_theme_color_override("font_color", Color(0.48, 0.78, 0.76))
	station_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	station_row.add_child(station_label)
	var station_selector := OptionButton.new()
	station_selector.custom_minimum_size = Vector2(310.0, 32.0)
	station_selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	station_row.add_child(station_selector)
	var station_hostile_player := CheckButton.new()
	station_hostile_player.text = "VS PLAYER"
	station_row.add_child(station_hostile_player)
	var station_hostile_npcs := CheckButton.new()
	station_hostile_npcs.text = "VS NPC TEAMS"
	station_hostile_npcs.button_pressed = true
	station_row.add_child(station_hostile_npcs)
	var entry := {
		"faction": faction, "team_selector": team_selector, "hostile": hostile,
		"roster_list": roster_list, "roster_rows": [], "station_selector": station_selector,
		"station_hostile_player": station_hostile_player,
		"station_hostile_npcs": station_hostile_npcs,
	}
	faction_controls.append(entry)
	add_ship.pressed.connect(_add_roster_row.bind(entry))


func _add_roster_row(entry: Dictionary, selected_path: String = "", count_value: int = 1) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	(entry["roster_list"] as VBoxContainer).add_child(row)
	var selector := OptionButton.new()
	selector.custom_minimum_size = Vector2(410.0, 32.0)
	selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_populate_blueprint_selector(selector, ship_blueprints, false, selected_path)
	row.add_child(selector)
	var count := SpinBox.new()
	count.custom_minimum_size = Vector2(90.0, 32.0)
	count.min_value = 1.0
	count.max_value = 12.0
	count.step = 1.0
	count.value = clampi(count_value, 1, 12)
	count.allow_greater = false
	count.allow_lesser = false
	row.add_child(count)
	var remove := Button.new()
	remove.text = "REMOVE"
	remove.custom_minimum_size = Vector2(95.0, 32.0)
	remove.add_theme_color_override("font_color", Color(1.0, 0.42, 0.32))
	row.add_child(remove)
	var row_data := {"control": row, "selector": selector, "count": count}
	(entry["roster_rows"] as Array).append(row_data)
	remove.pressed.connect(_remove_roster_row.bind(entry, row_data))


func _remove_roster_row(entry: Dictionary, row_data: Dictionary) -> void:
	(entry["roster_rows"] as Array).erase(row_data)
	var row := row_data.get("control") as Control
	if is_instance_valid(row):
		row.queue_free()


func open_panel(blueprints: Array[Dictionary]) -> void:
	ship_blueprints.clear()
	station_blueprints.clear()
	for blueprint: Dictionary in blueprints:
		if String(blueprint.get("kind", "SHIP")).to_upper() == "STATION":
			station_blueprints.append(blueprint)
		else:
			ship_blueprints.append(blueprint)
	for entry: Dictionary in faction_controls:
		var rows := entry["roster_rows"] as Array
		if rows.is_empty():
			_add_roster_row(entry)
		else:
			for row_data: Dictionary in rows:
				var selector := row_data["selector"] as OptionButton
				var selected_path := String(selector.get_selected_metadata()) if selector.item_count > 0 else ""
				_populate_blueprint_selector(selector, ship_blueprints, false, selected_path)
		_populate_blueprint_selector(entry["station_selector"] as OptionButton, station_blueprints, true)
	_populate_blueprint_selector(neutral_station_selector, station_blueprints, true)
	previous_pause_state = get_tree().paused
	visible = true
	get_tree().paused = true
	if not faction_controls.is_empty():
		var first_rows := faction_controls[0]["roster_rows"] as Array
		if not first_rows.is_empty():
			(first_rows[0]["selector"] as OptionButton).grab_focus()


func _populate_blueprint_selector(selector: OptionButton, blueprints: Array[Dictionary], include_none: bool, selected_path: String = "") -> void:
	selector.clear()
	if include_none:
		selector.add_item("NONE")
		selector.set_item_metadata(0, "")
	for blueprint: Dictionary in blueprints:
		selector.add_item(String(blueprint.get("name", "UNNAMED DESIGN")))
		var item_index := selector.item_count - 1
		var path := String(blueprint.get("path", ""))
		selector.set_item_metadata(item_index, path)
		if not selected_path.is_empty() and path == selected_path:
			selector.select(item_index)
	selector.disabled = selector.item_count == 0


func close_panel() -> void:
	if not visible:
		return
	visible = false
	get_tree().paused = previous_pause_state
	closed.emit()


func set_status(message: String) -> void:
	if is_instance_valid(status_label):
		status_label.text = message


func _request_scenario() -> void:
	var groups: Array[Dictionary] = []
	for entry: Dictionary in faction_controls:
		var faction: Dictionary = entry["faction"]
		var ships: Array[Dictionary] = []
		for row_data: Dictionary in entry["roster_rows"]:
			var selector := row_data["selector"] as OptionButton
			if selector.item_count == 0:
				continue
			ships.append({"blueprint_path": selector.get_selected_metadata(), "ship_name": selector.get_item_text(selector.selected), "count": int((row_data["count"] as SpinBox).value)})
		var station_selector := entry["station_selector"] as OptionButton
		groups.append({
			"faction_id": faction["id"], "faction_name": faction["name"],
			"combat_team": int((entry["team_selector"] as OptionButton).get_selected_metadata()),
			"color": faction["color"],
			"ships": ships,
			"station_blueprint_path": station_selector.get_selected_metadata() if station_selector.item_count > 0 else "",
			"station_name": station_selector.get_item_text(station_selector.selected) if station_selector.item_count > 0 else "",
			"fleet_hostile_to_player": (entry["hostile"] as CheckButton).button_pressed,
			"station_hostile_to_player": (entry["station_hostile_player"] as CheckButton).button_pressed,
			"station_hostile_to_npcs": (entry["station_hostile_npcs"] as CheckButton).button_pressed,
		})
	var neutral_path := String(neutral_station_selector.get_selected_metadata()) if neutral_station_selector.item_count > 0 else ""
	scenario_requested.emit({
		"environment": environment_selector.get_selected_metadata(),
		"factions": groups,
		"neutral_station": {
			"blueprint_path": neutral_path,
			"station_name": neutral_station_selector.get_item_text(neutral_station_selector.selected) if not neutral_path.is_empty() else "",
			"hostile_to_player": neutral_station_hostile_player.button_pressed,
			"hostile_to_npcs": neutral_station_hostile_npcs.button_pressed,
		},
	})
	close_panel()


func _request_clear() -> void:
	clear_requested.emit()
	set_status("RANGE CLEAR • AWAITING SCENARIO")


func _request_asteroid_field() -> void:
	asteroid_field_requested.emit(ASTEROID_TARGET_COUNT)
	close_panel()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close_panel()
		get_viewport().set_input_as_handled()


func _action_button(text: String, accent: Color) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(170.0, 42.0)
	button.add_theme_color_override("font_color", accent)
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_color_override("font_focus_color", Color.WHITE)
	button.add_theme_stylebox_override("normal", _panel_style(accent.darkened(0.35), Color(0.01, 0.035, 0.035, 0.98), 1))
	button.add_theme_stylebox_override("hover", _panel_style(accent, Color(0.025, 0.09, 0.085, 0.98), 2))
	button.add_theme_stylebox_override("focus", _panel_style(accent, Color(0.025, 0.09, 0.085, 0.98), 2))
	return button


func _panel_style(border: Color, fill: Color, width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(width)
	style.corner_radius_top_left = 3
	style.corner_radius_top_right = 3
	style.corner_radius_bottom_left = 3
	style.corner_radius_bottom_right = 3
	style.content_margin_left = 10.0
	style.content_margin_top = 7.0
	style.content_margin_right = 10.0
	style.content_margin_bottom = 7.0
	return style
