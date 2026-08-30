class_name SectorJumpTerminal
extends Control

signal destination_selected(destination: GeneratedSector)

var route_button: Button
var terminal_panel: PanelContainer
var star_map: SectorStarMap
var routes: Array[Resource] = []
var pause_was_active := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_route_button()
	_build_terminal()


func present_routes(new_routes: Array[Resource]) -> void:
	routes = new_routes.duplicate()
	var origin: GeneratedSector
	var run_state := get_tree().get_first_node_in_group("run_state") as RunState
	if run_state != null:
		origin = run_state.current_sector
		star_map.set_map_data(routes, origin, run_state.journey_sectors, run_state.journey_route_slots)
	else:
		star_map.set_map_data(routes, origin)
	route_button.text = "JUMP SOLUTIONS • %d >" % routes.size()
	route_button.visible = not routes.is_empty()


func clear_routes() -> void:
	routes.clear()
	route_button.visible = false
	terminal_panel.visible = false


func open_terminal() -> void:
	if routes.is_empty():
		return
	pause_was_active = get_tree().paused
	get_tree().paused = true
	terminal_panel.visible = true
	terminal_panel.modulate = Color(0.7, 1.45, 1.38, 0.0)
	terminal_panel.scale = Vector2(1.0, 0.08)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(terminal_panel, "modulate", Color.WHITE, 0.16)
	tween.tween_property(terminal_panel, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func close_terminal() -> void:
	terminal_panel.visible = false
	get_tree().paused = pause_was_active


func release_jump_pause() -> void:
	get_tree().paused = pause_was_active


func _build_route_button() -> void:
	route_button = Button.new()
	route_button.name = "JumpRoutesButton"
	route_button.text = "JUMP SOLUTIONS >"
	route_button.visible = false
	route_button.mouse_filter = Control.MOUSE_FILTER_STOP
	route_button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	route_button.position = Vector2(-360.0, 74.0)
	route_button.size = Vector2(220.0, 38.0)
	route_button.add_theme_font_size_override("font_size", 12)
	route_button.add_theme_color_override("font_color", Color(1.0, 0.76, 0.25))
	route_button.add_theme_color_override("font_hover_color", Color(1.0, 0.95, 0.65))
	route_button.add_theme_stylebox_override("normal", _panel_style(Color(0.38, 0.21, 0.02, 0.94), Color(1.0, 0.58, 0.08), 1))
	route_button.add_theme_stylebox_override("hover", _panel_style(Color(0.24, 0.15, 0.02, 0.98), Color(1.0, 0.86, 0.28), 2))
	route_button.pressed.connect(open_terminal)
	add_child(route_button)


func _build_terminal() -> void:
	var blackout := ColorRect.new()
	blackout.color = Color(0.0, 0.012, 0.018, 0.86)
	blackout.mouse_filter = Control.MOUSE_FILTER_STOP
	blackout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	terminal_panel = PanelContainer.new()
	terminal_panel.name = "JumpTerminal"
	terminal_panel.visible = false
	terminal_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	terminal_panel.set_anchors_preset(Control.PRESET_CENTER)
	terminal_panel.position = Vector2(-445.0, -255.0)
	terminal_panel.size = Vector2(930.0, 560.0)
	terminal_panel.pivot_offset = terminal_panel.size * 0.5
	terminal_panel.add_theme_stylebox_override(
		"panel",
		_panel_style(Color(0.004, 0.035, 0.04, 0.985), Color(0.12, 0.92, 0.84), 2)
	)
	add_child(terminal_panel)
	terminal_panel.add_child(blackout)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_bottom", 16)
	terminal_panel.add_child(margin)

	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 12)
	margin.add_child(stack)

	var command_row := HBoxContainer.new()
	stack.add_child(command_row)
	var title_stack := VBoxContainer.new()
	title_stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	command_row.add_child(title_stack)
	var title := Label.new()
	title.text = "ASTROGATION • BRANCHING STAR MAP"
	title.add_theme_font_size_override("font_size", 23)
	title.add_theme_color_override("font_color", Color(0.64, 1.0, 0.94))
	title_stack.add_child(title)
	var subtitle := Label.new()
	subtitle.text = "SECTOR CLEARANCE VERIFIED. PLOT THE NEXT LIGHT-SPEED JUMP."
	subtitle.add_theme_font_size_override("font_size", 11)
	subtitle.add_theme_color_override("font_color", Color(0.3, 0.76, 0.72))
	title_stack.add_child(subtitle)
	var close := Button.new()
	close.text = "RETURN TO TACTICAL >"
	close.custom_minimum_size = Vector2(180.0, 42.0)
	close.add_theme_color_override("font_color", Color(0.62, 0.92, 0.88))
	close.add_theme_stylebox_override("normal", _panel_style(Color(0.02, 0.08, 0.08), Color(0.14, 0.48, 0.46), 1))
	close.add_theme_stylebox_override("hover", _panel_style(Color(0.03, 0.15, 0.14), Color(0.35, 1.0, 0.9), 2))
	close.pressed.connect(close_terminal)
	command_row.add_child(close)

	var divider := HSeparator.new()
	divider.add_theme_color_override("separator", Color(0.12, 0.7, 0.66, 0.7))
	stack.add_child(divider)

	star_map = SectorStarMap.new()
	star_map.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	star_map.size_flags_vertical = Control.SIZE_EXPAND_FILL
	star_map.destination_selected.connect(_select_route)
	stack.add_child(star_map)

	var footer := Label.new()
	footer.text = "HALO: SECTOR TYPE • CORE: FACTION SIGNAL • RANK TABS: THREAT • DRIVE COMMIT IS FINAL"
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	footer.add_theme_font_size_override("font_size", 10)
	footer.add_theme_color_override("font_color", Color(0.42, 0.62, 0.6))
	stack.add_child(footer)


func _select_route(route: GeneratedSector) -> void:
	route.set_meta("route_slot", maxi(routes.find(route), 0))
	terminal_panel.visible = false
	destination_selected.emit(route)


func _panel_style(background: Color, border: Color, width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(width)
	style.corner_radius_top_left = 3
	style.corner_radius_top_right = 3
	style.corner_radius_bottom_left = 3
	style.corner_radius_bottom_right = 3
	style.content_margin_left = 12.0
	style.content_margin_top = 10.0
	style.content_margin_right = 12.0
	style.content_margin_bottom = 10.0
	return style
