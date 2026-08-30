class_name StartingShipTerminal
extends Control

signal ship_engaged(candidate: Dictionary)
signal cancelled

const CRT_PANEL := preload("res://scripts/crt_context_panel.gd")
const SHIP_PREVIEW := preload("res://scripts/ship_builder_preview.gd")

const CYAN := Color(0.34, 1.0, 0.91, 1.0)
const DIM_CYAN := Color(0.18, 0.55, 0.52, 1.0)
const AMBER := Color(1.0, 0.62, 0.18, 1.0)
const MAGENTA := Color(0.88, 0.38, 1.0, 1.0)
const INK := Color(0.006, 0.02, 0.025, 0.98)

var candidates: Array[Dictionary] = []
var previous_pause_state := false
var frame: CrtContextPanel
var body: MarginContainer
var header_title: Label
var header_status: Label
var close_button: Button


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_interface()
	visible = false


func open_terminal(generated_candidates: Array[Dictionary]) -> void:
	candidates = generated_candidates
	previous_pause_state = get_tree().paused
	get_tree().paused = true
	visible = true
	_show_choices()
	frame.call("power_on_from", get_viewport_rect().size * Vector2(0.88, 0.16))


func close_terminal() -> void:
	if not visible:
		return
	frame.call("power_off")
	await get_tree().create_timer(0.25, true).timeout
	visible = false
	get_tree().paused = previous_pause_state


func _build_interface() -> void:
	var backdrop := ColorRect.new()
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0.0, 0.01, 0.015, 1.0)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(backdrop)

	frame = CRT_PANEL.new() as CrtContextPanel
	frame.name = "StarterAcquisitionTerminal"
	frame.process_mode = Node.PROCESS_MODE_ALWAYS
	# This terminal is hidden by its full-screen host, so the CRT frame itself
	# must begin initialized. Otherwise CrtContextPanel's deferred startup can
	# hide it one frame after open_terminal() has already powered it on.
	frame.begin_powered_off = false
	frame.anchor_left = 0.055
	frame.anchor_top = 0.055
	frame.anchor_right = 0.945
	frame.anchor_bottom = 0.945
	frame.add_theme_stylebox_override("panel", _panel_style(CYAN, INK, 2))
	add_child(frame)

	var frame_margin := MarginContainer.new()
	frame_margin.add_theme_constant_override("margin_left", 22)
	frame_margin.add_theme_constant_override("margin_top", 16)
	frame_margin.add_theme_constant_override("margin_right", 22)
	frame_margin.add_theme_constant_override("margin_bottom", 16)
	frame.add_child(frame_margin)

	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 12)
	frame_margin.add_child(stack)

	var header := HBoxContainer.new()
	header.custom_minimum_size.y = 58.0
	stack.add_child(header)
	var title_stack := VBoxContainer.new()
	title_stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title_stack)
	header_title = _make_label("HANGAR THEFT PROTOCOL • AVAILABLE HULLS", 23, CYAN)
	title_stack.add_child(header_title)
	header_status = _make_label("FACILITY LOCKDOWN ACTIVE • THREE TRANSPONDERS REMAIN UNCLAIMED", 10, AMBER)
	title_stack.add_child(header_status)
	close_button = _make_button("EXIT TO CURRENT GAME  >", CYAN)
	close_button.custom_minimum_size = Vector2(190, 46)
	close_button.pressed.connect(_cancel_terminal)
	header.add_child(close_button)

	var divider := HSeparator.new()
	divider.add_theme_color_override("separator", DIM_CYAN)
	stack.add_child(divider)

	body = MarginContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stack.add_child(body)

	var footer := HBoxContainer.new()
	footer.custom_minimum_size.y = 20.0
	stack.add_child(footer)
	var footer_left := _make_label("CAPTAIN'S AUTHORITY ACCEPTED • HANGAR CAMERAS LOOPED", 9, DIM_CYAN)
	footer_left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(footer_left)
	footer.add_child(_make_label("SELECTION IS PROVISIONAL UNTIL DRIVE ENGAGEMENT", 9, AMBER))


func _show_choices() -> void:
	header_title.text = "HANGAR THEFT PROTOCOL • AVAILABLE HULLS"
	header_status.text = "FACILITY LOCKDOWN ACTIVE • SELECT ONE ESCAPE PLATFORM"
	close_button.text = "EXIT TO CURRENT GAME  >"
	_clear_body()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	body.add_child(row)
	for index: int in range(candidates.size()):
		row.add_child(_build_candidate_card(index))


func _build_candidate_card(index: int) -> Control:
	var candidate: Dictionary = candidates[index]
	var accent: Color = [CYAN, AMBER, MAGENTA][index % 3]
	var card := Button.new()
	card.text = ""
	card.focus_mode = Control.FOCUS_NONE
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	card.tooltip_text = "OPEN BLUEPRINT DOSSIER • %s" % String(candidate.get("name", "UNNAMED"))
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("normal", _panel_style(accent, Color(0.008, 0.03, 0.034, 0.94), 1))
	card.add_theme_stylebox_override("hover", _panel_style(Color.WHITE, Color(accent, 0.13), 2))
	card.add_theme_stylebox_override("pressed", _panel_style(accent.lightened(0.25), Color(accent, 0.22), 2))
	card.pressed.connect(func() -> void: Callable(self, "_show_focus").call_deferred(index))
	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 10)
	card.add_child(margin)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 6)
	margin.add_child(stack)

	var serial := _make_label("◆ %s • %s" % [candidate.get("serial", "HX"), candidate.get("archetype", "HULL")], 9, accent)
	stack.add_child(serial)
	stack.add_child(_make_label(String(candidate.get("name", "UNNAMED")), 20, Color.WHITE))
	stack.add_child(_make_label(String(candidate.get("role", "ESCAPE HULL")), 10, accent))

	var preview: ShipBuilderPreview = SHIP_PREVIEW.new() as ShipBuilderPreview
	preview.custom_minimum_size = Vector2(0, 260)
	preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview.set_layout(candidate.get("layout"), Vector2i(6, 8))
	stack.add_child(preview)

	_add_power_meter(stack, candidate.get("stats", {}), accent)
	_add_crew_meter(stack, candidate.get("stats", {}), accent)
	var stats: Dictionary = candidate.get("stats", {})
	stack.add_child(_make_label(
		"WEAPONS %d • THRUST %d" % [int(stats.get("weapon_count", 0)), roundi(float(stats.get("thrust_rating", 0.0)))],
		10,
		Color(0.68, 0.84, 0.8)
	))
	var prompt := _make_label("HOVER TO SCAN • CLICK TO INSPECT", 9, accent)
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stack.add_child(prompt)
	_make_children_input_transparent(margin)
	return card


func _show_focus(index: int) -> void:
	if index < 0 or index >= candidates.size():
		return
	var candidate: Dictionary = candidates[index]
	var accent: Color = [CYAN, AMBER, MAGENTA][index % 3]
	header_title.text = "%s • BLUEPRINT INTERCEPT" % String(candidate.get("name", "UNNAMED"))
	header_status.text = "%s • CLAMPS ARMED • DRIVE CORE COLD" % String(candidate.get("serial", "HX"))
	close_button.text = "EXIT TO CURRENT GAME  >"
	_clear_body()

	var split := HBoxContainer.new()
	split.add_theme_constant_override("separation", 18)
	body.add_child(split)
	var preview_panel := PanelContainer.new()
	preview_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview_panel.add_theme_stylebox_override("panel", _panel_style(accent, Color(0.005, 0.02, 0.024, 0.9), 1))
	split.add_child(preview_panel)
	var preview: ShipBuilderPreview = SHIP_PREVIEW.new() as ShipBuilderPreview
	preview.custom_minimum_size = Vector2(620, 460)
	preview.room_tooltips_enabled = true
	preview.mouse_default_cursor_shape = Control.CURSOR_HELP
	preview.set_layout(candidate.get("layout"), Vector2i(6, 8))
	preview_panel.add_child(preview)

	var dossier := PanelContainer.new()
	dossier.custom_minimum_size.x = 350.0
	dossier.add_theme_stylebox_override("panel", _panel_style(accent, Color(0.012, 0.035, 0.038, 0.96), 1))
	split.add_child(dossier)
	var dossier_margin := MarginContainer.new()
	for side: String in ["left", "top", "right", "bottom"]:
		dossier_margin.add_theme_constant_override("margin_%s" % side, 14)
	dossier.add_child(dossier_margin)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 9)
	dossier_margin.add_child(stack)
	stack.add_child(_make_label(String(candidate.get("name", "UNNAMED")), 24, accent))
	stack.add_child(_make_label(String(candidate.get("role", "ESCAPE HULL")), 11, AMBER))
	var description := _make_label(String(candidate.get("flavor", "")), 11, Color(0.72, 0.88, 0.84))
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stack.add_child(description)
	stack.add_child(HSeparator.new())
	_add_power_meter(stack, candidate.get("stats", {}), accent)
	_add_crew_meter(stack, candidate.get("stats", {}), accent)
	var stats: Dictionary = candidate.get("stats", {})
	stack.add_child(_make_label("WEAPON MOUNTS • %d" % int(stats.get("weapon_count", 0)), 11, Color.WHITE))
	stack.add_child(_make_label("DRIVE RATING • %d" % roundi(float(stats.get("thrust_rating", 0.0))), 11, Color.WHITE))
	stack.add_child(_make_label("HULL FOOTPRINT • %d CELLS" % int(stats.get("occupied_cells", 0)), 11, Color.WHITE))
	stack.add_child(_make_label("HULL TRAITS", 10, AMBER))
	for trait_name: String in candidate.get("traits", PackedStringArray()):
		stack.add_child(_make_label("  ◆  %s" % trait_name, 10, accent))
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stack.add_child(spacer)
	var engage := _make_button("CHOOSE %s AS STARTING SHIP  >" % String(candidate.get("name", "THIS HULL")), AMBER)
	engage.custom_minimum_size.y = 52.0
	engage.pressed.connect(func() -> void: _engage_candidate(index))
	stack.add_child(engage)
	var back := _make_button("<  COMPARE ALL THREE SHIPS", accent)
	back.custom_minimum_size.y = 36.0
	back.pressed.connect(func() -> void: Callable(self, "_show_choices").call_deferred())
	stack.add_child(back)


func _engage_candidate(index: int) -> void:
	if index < 0 or index >= candidates.size():
		return
	var candidate := candidates[index]
	print("STARTER SHIP SELECTED • %s • %s" % [candidate.get("name", "UNNAMED"), candidate.get("archetype", "UNKNOWN")])
	await close_terminal()
	ship_engaged.emit(candidate)


func _cancel_terminal() -> void:
	await close_terminal()
	cancelled.emit()


func _add_power_meter(parent: Container, stats: Dictionary, accent: Color) -> void:
	var capacity := maxi(roundi(float(stats.get("energy_capacity", 0.0))), 1)
	var demand := clampi(roundi(float(stats.get("energy_demand", 0.0))), 0, capacity)
	parent.add_child(_make_label("POWER FIELD • %d OPEN" % (capacity - demand), 9, accent))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 3)
	parent.add_child(row)
	for index: int in range(capacity):
		var cell := ColorRect.new()
		cell.custom_minimum_size = Vector2(22, 10)
		cell.color = AMBER if index < demand else Color(accent, 0.8)
		row.add_child(cell)


func _add_crew_meter(parent: Container, stats: Dictionary, accent: Color) -> void:
	var capacity := maxi(int(stats.get("crew_capacity", 0)), 1)
	var required := clampi(int(stats.get("optimal_crew", 0)), 0, capacity)
	parent.add_child(_make_label("CREW BERTHS • %d RESERVE" % (capacity - required), 9, accent))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	parent.add_child(row)
	for index: int in range(capacity):
		var crew_mark := ColorRect.new()
		crew_mark.custom_minimum_size = Vector2(7, 14)
		crew_mark.color = AMBER if index < required else Color(accent, 0.88)
		row.add_child(crew_mark)


func _clear_body() -> void:
	for child: Node in body.get_children():
		body.remove_child(child)
		child.queue_free()


func _make_label(text_value: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text_value
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


func _make_button(text_value: String, accent: Color) -> Button:
	var button := Button.new()
	button.text = text_value
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.add_theme_font_size_override("font_size", 11)
	button.add_theme_color_override("font_color", accent)
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_stylebox_override("normal", _panel_style(Color(accent, 0.48), Color(0.018, 0.035, 0.04, 0.94), 1))
	button.add_theme_stylebox_override("hover", _panel_style(accent, Color(accent, 0.14), 2))
	button.add_theme_stylebox_override("pressed", _panel_style(Color.WHITE, Color(accent, 0.22), 2))
	return button


func _make_children_input_transparent(root_control: Control) -> void:
	root_control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child: Node in root_control.get_children():
		if child is Control:
			_make_children_input_transparent(child as Control)


func _panel_style(border: Color, background: Color, width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(width)
	style.corner_radius_top_left = 2
	style.corner_radius_top_right = 2
	style.corner_radius_bottom_left = 2
	style.corner_radius_bottom_right = 9
	style.content_margin_left = 10.0
	style.content_margin_top = 7.0
	style.content_margin_right = 10.0
	style.content_margin_bottom = 7.0
	return style
