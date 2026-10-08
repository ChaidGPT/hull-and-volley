class_name ShipBuilderScreen
extends CanvasLayer

signal embedded_status_changed(message: String, is_error: bool)

signal closed
signal grid_editor_requested

const ShipBuilderAnalyzer := preload("res://scripts/ship_builder_analyzer.gd")
const ShipBuilderPreviewSceneScript := preload("res://scripts/ship_builder_preview.gd")
const SettlementGridScript := preload("res://scripts/settlement_grid.gd")
const ForgeInventoryPieceScript := preload("res://scripts/forge_inventory_piece.gd")
const ForgeInventoryGridScript := preload("res://scripts/forge_inventory_grid.gd")
const GridInventoryCatalogScript := preload("res://scripts/grid_inventory_catalog.gd")
const ForgeTrashDropScript := preload("res://scripts/forge_trash_drop.gd")
const ArcadeResourceMeterScript := preload("res://scripts/arcade_resource_meter.gd")
const DrydockFacingSelectorScript := preload("res://scripts/drydock_facing_selector.gd")
const GRID_GEOMETRY := preload("res://scripts/grid_geometry.gd")
const ROOM_STAFFING_RULES := preload("res://scripts/room_staffing_rules.gd")
const POWER_REQUIREMENT_DISPLAY := preload("res://scripts/power_requirement_display.gd")
const CREW_REQUIREMENT_DISPLAY := preload("res://scripts/crew_requirement_display.gd")
const BLUEPRINT_DIRECTORY := "res://resources/ship_designs"
const EXPLICIT_GROUP_ROOM_TYPES := ["WEAPONS", "PROPULSION", "HANGAR", "SHIELDS"]
const REQUIRED_SHIP_SYSTEMS := [
	{"label": "BRIDGE", "types": ["COMMAND", "BRIDGE"]},
	{"label": "REACTOR", "types": ["POWER", "REACTOR", "ENGINE"]},
	{"label": "CREW QUARTERS", "types": ["CREW", "CREW_QUARTERS"]},
	{"label": "THRUSTER", "types": ["PROPULSION", "THRUSTER"]},
]
const INVALID_CELL := Vector2i(2147483647, 2147483647)
const QUARTER_CELLS_PER_FULL_GRID := 2

@export var envelope_presets: Array[Vector2i] = [
	Vector2i(3, 3),
	Vector2i(5, 5),
	Vector2i(7, 7),
	Vector2i(9, 9),
	Vector2i(12, 12),
	Vector2i(16, 16),
]
@export var open_sound_method := "play_open"
@export var close_sound_method := "play_close"
@export var execute_sound_method := "play_execute"
@export var denied_sound_method := "play_builder_denied"
@export var install_sound_method := "play_grid_install"

var source_layout: Resource
var selected_size := Vector2i.ZERO
var selected_new_vessel_kind := "SHIP"
var new_vessel_kind_buttons: Dictionary = {}
var root_panel: PanelContainer
var new_design_name_field: LineEdit
var new_size_options: VBoxContainer
var design_name_field: LineEdit
var design_selector: OptionButton
var blueprint_catalog_panel: PanelContainer
var open_catalog_button: Button
var blueprint_selection_label: Label
var blueprint_card_grid: GridContainer
var blueprint_cards: Array[PanelContainer] = []
var selected_blueprint_path := ""
var selected_blueprint_layout: Resource
var size_options: VBoxContainer
var command_section: PanelContainer
var new_section: PanelContainer
var new_confirm_section: PanelContainer
var save_section: PanelContainer
var load_section: PanelContainer
var load_actions_section: PanelContainer
var edit_blueprint_button: Button
var play_blueprint_button: Button
var delete_blueprint_button: Button
var envelope_section: PanelContainer
var status_label: Label
var shipyard_notice_label: Label
var new_frame_summary_label: Label
var builder_status_label: Label
var builder_view_actions: HBoxContainer
var builder_tool_row: HBoxContainer
var builder_add_header: Button
var builder_type_buttons: VBoxContainer
var forge_inventory_grid: Container
var builder_resource_panel: PanelContainer
var builder_power_meter: Control
var builder_crew_meter: Control
var builder_scroll: ScrollContainer
var builder_group_header: Button
var builder_group_actions: HBoxContainer
var builder_combine_button: Button
var builder_split_button: Button
var builder_clear_selection_button: Button
var builder_facing_actions: Control
var builder_delete_actions: HBoxContainer
var inventory_header_label: Label
var builder_last_selected_cell := INVALID_CELL
var builder_specific_mount_selected := false
var builder_pending_add_cell := INVALID_CELL
var builder_pending_add_offset := Vector2.ZERO
var builder_pending_delete_cell := INVALID_CELL
var stat_label: RichTextLabel
var dossier_panel: PanelContainer
var preview: ShipBuilderPreview
var builder_grid: Control
var previous_tree_pause := false
var action_buttons: Array[Button] = []
var current_context := ""
var builder_tool := ""
var builder_room_type := ""
var builder_inventory_key := ""
var builder_module_recipe: Resource
var builder_group_selection: Dictionary = {}
var hovered_frame_size := Vector2i.ZERO
var forge_armed_piece_id := 0
var inspected_inventory_piece_id := 0
var inspected_inventory_room_type := ""
var forge_inventory_initialized := false
var builder_resource_signature := ""
var builder_resource_stats_cache: Dictionary = {}
var inventory_mode := "FORGE"
var owned_grid_inventory: Dictionary = {}
var owned_grid_instances: Array[Dictionary] = []
var inventory_owner: Node
var shipyard_title_label: Label
var shipyard_subtitle_label: Label
var save_title_label: Label
var save_blueprint_button: Button
var back_from_edit_button: Button
var close_terminal_button: Button
var builder_alert_panel: PanelContainer
var builder_alert_title: Label
var builder_alert_detail: Label
var builder_alert_tween: Tween
var embedded_refit_mode := false
var embedded_refit_locked := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 90
	visible = false
	_build_interface()


func _process(_delta: float) -> void:
	if visible and current_context == "edit":
		_refresh_builder_resource_meters()


func open_for_layout(
	layout: Resource,
	requested_inventory_mode := "FORGE",
	grid_inventory: Dictionary = {},
	requested_inventory_owner: Node = null
) -> void:
	embedded_refit_mode = false
	embedded_refit_locked = false
	source_layout = layout
	_invalidate_builder_resource_stats()
	if source_layout != null and source_layout.has_method("ensure_quarter_lattice"):
		source_layout.call("ensure_quarter_lattice")
	# Every installed grid piece owns its own systems compartment. Older saved
	# hulls may still contain the former linked-room representation, so normalize
	# them as soon as they enter either drydock terminal.
	_builder_separate_all_installed_pieces()
	_normalize_unmanned_exterior_modules()
	inventory_mode = requested_inventory_mode.to_upper()
	if forge_inventory_grid != null:
		forge_inventory_grid.set("manual_layout", _uses_owned_inventory())
	owned_grid_inventory = grid_inventory
	inventory_owner = requested_inventory_owner
	owned_grid_instances.clear()
	if (
		_uses_owned_inventory()
		and is_instance_valid(inventory_owner)
		and inventory_owner.has_method("get_grid_piece_instances")
	):
		owned_grid_instances = inventory_owner.call("get_grid_piece_instances")
	forge_inventory_initialized = false
	forge_armed_piece_id = 0
	if inventory_header_label != null:
		inventory_header_label.text = (
			"CARGO GRID INVENTORY • DRAG TO BLUEPRINT"
			if _uses_owned_inventory()
			else "MODULE INVENTORY • UNLIMITED FORGE CATALOG"
		)
	if source_layout != null:
		selected_size = Vector2i(int(source_layout.get("columns")), int(source_layout.get("rows")))
		if design_name_field != null:
			design_name_field.text = _layout_display_name(source_layout)
	_refresh_blueprint_archive()
	_populate_size_selector()
	_populate_new_size_selector()
	_populate_forge_inventory()
	_configure_inventory_mode_interface()
	_show_shipyard_context("edit" if _uses_owned_inventory() else "", false)
	_refresh_display()
	previous_tree_pause = get_tree().paused
	get_tree().paused = true
	visible = true
	if builder_alert_tween != null and builder_alert_tween.is_valid():
		builder_alert_tween.kill()
	if is_instance_valid(builder_alert_panel):
		builder_alert_panel.visible = false
	root_panel.scale = Vector2(0.0, 0.04)
	root_panel.modulate = Color(1.25, 1.45, 1.45, 1.0)
	_play_menu_sound(open_sound_method)
	var tween := create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(root_panel, "scale:x", 1.0, 0.11).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(root_panel, "scale:y", 1.0, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(root_panel, "modulate", Color.WHITE, 0.16)


func configure_embedded_refit(
	layout: Resource,
	requested_inventory_owner: Node,
	external_inventory_grid: Container,
	external_builder_grid: Control,
	external_context_host: Container = null,
	external_resource_host: Container = null
) -> void:
	embedded_refit_mode = true
	source_layout = layout
	_invalidate_builder_resource_stats()
	inventory_mode = "STATION"
	inventory_owner = requested_inventory_owner
	forge_inventory_grid = external_inventory_grid
	builder_grid = external_builder_grid
	owned_grid_inventory = (
		inventory_owner.call("get_grid_piece_inventory")
		if is_instance_valid(inventory_owner) and inventory_owner.has_method("get_grid_piece_inventory")
		else {}
	)
	owned_grid_instances = (
		inventory_owner.call("get_grid_piece_instances")
		if is_instance_valid(inventory_owner) and inventory_owner.has_method("get_grid_piece_instances")
		else []
	)
	forge_inventory_initialized = true
	forge_armed_piece_id = 0
	builder_room_type = ""
	builder_inventory_key = ""
	builder_module_recipe = null
	builder_tool = ""
	current_context = "edit"
	if source_layout != null:
		if source_layout.has_method("ensure_quarter_lattice"):
			source_layout.call("ensure_quarter_lattice")
		_normalize_unmanned_exterior_modules()
		selected_size = Vector2i(int(source_layout.get("columns")), int(source_layout.get("rows")))
	if builder_grid != null:
		builder_grid.set("ship_layout", source_layout)
		builder_grid.set("planned_staffing_display", false)
		_connect_embedded_builder_grid()
		builder_grid.call("set_editor_mode", true)
		builder_grid.call("set_free_blueprint_placement", false)
		if builder_grid.has_method("set_core_frame_edit_locked"):
			builder_grid.call("set_core_frame_edit_locked", true)
		if builder_grid.has_method("set_editor_edit_locked"):
			builder_grid.call("set_editor_edit_locked", embedded_refit_locked)
		builder_grid.call("refresh_layout")
		builder_grid.call_deferred("fit_editor_view")
	if forge_inventory_grid != null:
		forge_inventory_grid.set("manual_layout", true)
		var returned_callback := Callable(self, "_on_installed_piece_returned")
		if forge_inventory_grid.has_signal("installed_piece_returned") and not forge_inventory_grid.is_connected("installed_piece_returned", returned_callback):
			forge_inventory_grid.connect("installed_piece_returned", returned_callback)
	if external_context_host != null and dossier_panel != null and dossier_panel.get_parent() != external_context_host:
		dossier_panel.reparent(external_context_host)
		# The full-screen terminal docks this card with right-edge anchors. Clear
		# that old geometry when the same card becomes the compact side dossier.
		dossier_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
		dossier_panel.position = Vector2.ZERO
		dossier_panel.size = Vector2(176.0, 0.0)
		dossier_panel.custom_minimum_size = Vector2(176.0, 0.0)
		dossier_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		dossier_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	if external_resource_host != null and builder_resource_panel != null and builder_resource_panel.get_parent() != external_resource_host:
		builder_resource_panel.reparent(external_resource_host)
		builder_resource_panel.custom_minimum_size = Vector2(0.0, 38.0)
		builder_resource_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		builder_resource_panel.size_flags_vertical = Control.SIZE_FILL
		# The live workbench explains power spatially on the hull and selected
		# room. Keep only the genuinely ship-wide crew roster in this rail.
		builder_power_meter.visible = false
		builder_crew_meter.custom_minimum_size = Vector2(150.0, 38.0)
	_refresh_display()


func refresh_embedded_resource_meters() -> void:
	if embedded_refit_mode:
		_refresh_builder_resource_meters()


func set_embedded_refit_locked(is_locked: bool) -> void:
	if embedded_refit_locked == is_locked:
		return
	embedded_refit_locked = is_locked
	if embedded_refit_mode and builder_grid != null:
		# Keep the editor camera alive during combat.  The interlock blocks hull
		# mutation, not the captain's ability to inspect, pan, or zoom the ship.
		builder_grid.call("set_editor_mode", true)
		if builder_grid.has_method("set_editor_edit_locked"):
			builder_grid.call("set_editor_edit_locked", is_locked)
		builder_grid.mouse_default_cursor_shape = Control.CURSOR_ARROW


func select_embedded_inventory_piece(room_type: String, source_instance_id: int) -> void:
	if not embedded_refit_mode:
		return
	_inspect_forge_inventory_piece(room_type, source_instance_id)


func begin_embedded_inventory_piece_pickup(room_type: String, source_instance_id: int) -> void:
	if not embedded_refit_mode:
		return
	if embedded_refit_locked:
		_set_builder_status("REFIT INTERLOCK • HOSTILE FIRE DETECTED")
		return
	_arm_forge_inventory_piece(room_type, source_instance_id)


func has_embedded_inventory_piece_armed() -> bool:
	return embedded_refit_mode and forge_armed_piece_id > 0 and not builder_room_type.is_empty()


func cancel_embedded_inventory_piece() -> void:
	if not embedded_refit_mode or forge_armed_piece_id <= 0:
		return
	forge_armed_piece_id = 0
	builder_room_type = ""
	builder_inventory_key = ""
	builder_module_recipe = null
	if builder_grid != null:
		builder_grid.call("set_inventory_piece_armed", false)
	_set_builder_tool("")
	_set_builder_status("GRID PIECE RETURNED TO PARTS LOCKER")
	_refresh_display()


func _connect_embedded_builder_grid() -> void:
	var signal_map := {
		"editor_cell_activated": Callable(self, "_on_builder_grid_cell_activated"),
		"editor_cells_dragged": Callable(self, "_on_builder_grid_cells_dragged"),
		"empty_space_selected": Callable(self, "_on_builder_grid_empty_space_selected"),
		"forge_inventory_piece_dropped": Callable(self, "_on_forge_inventory_piece_dropped"),
		"forge_inventory_piece_rejected": Callable(self, "_on_forge_inventory_piece_rejected"),
		"installed_piece_relocated": Callable(self, "_on_installed_piece_relocated"),
	}
	for signal_name: String in signal_map:
		var callback: Callable = signal_map[signal_name]
		if builder_grid.has_signal(signal_name) and not builder_grid.is_connected(signal_name, callback):
			builder_grid.connect(signal_name, callback)


func close() -> void:
	if not visible:
		return
	if blueprint_catalog_panel != null:
		blueprint_catalog_panel.visible = false
	_play_menu_sound(close_sound_method)
	var tween := create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(root_panel, "scale:y", 0.04, 0.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.parallel().tween_property(root_panel, "modulate", Color(1.25, 1.45, 1.45, 1.0), 0.1)
	tween.tween_property(root_panel, "scale:x", 0.0, 0.08).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await tween.finished
	visible = false
	get_tree().paused = previous_tree_pause
	closed.emit()


func _configure_inventory_mode_interface() -> void:
	var is_station_drydock := inventory_mode == "STATION"
	var is_escape_assembly := inventory_mode == "ESCAPE"
	var uses_owned_inventory := _uses_owned_inventory()
	if shipyard_title_label != null:
		shipyard_title_label.text = (
			"IMPOUND ASSEMBLY BAY • BUILD YOUR ESCAPE HULL"
			if is_escape_assembly
			else ("DRYDOCK • %s" % _layout_display_name(source_layout).to_upper() if is_station_drydock else "SHIPYARD COMMAND")
		)
	if shipyard_subtitle_label != null:
		shipyard_subtitle_label.text = (
			"Attach the stolen grids to the bridge keel. Launch begins when every required system is installed."
			if is_escape_assembly
			else ("Active vessel on clamps. Refit the hull directly." if is_station_drydock else "Paused drydock terminal. Choose a work order to arm the console.")
		)
	if shipyard_notice_label != null and uses_owned_inventory:
		shipyard_notice_label.text = "DRAG GRID TO HULL • ROTATE DIRECTIONAL SYSTEMS • KEEP THE FRAME CONNECTED" if is_escape_assembly else "LIFT FROM HULL • RETURN TO LOCKER • DISCARD AT CHUTE"
	if save_section != null:
		var section_title := save_section.get_node_or_null("Margin/Body") as VBoxContainer
		if section_title != null and section_title.get_child_count() > 0:
			(section_title.get_child(0) as Label).text = "STOLEN GRID MANIFEST" if is_escape_assembly else ("PARTS LOCKER" if is_station_drydock else "HULL ARCHIVE")
	if save_title_label != null:
		save_title_label.visible = not uses_owned_inventory
	if design_name_field != null:
		design_name_field.visible = not uses_owned_inventory
	if save_blueprint_button != null:
		save_blueprint_button.visible = not is_escape_assembly
		save_blueprint_button.text = "SAVE HULL PATTERN" if is_station_drydock else "ARCHIVE BLUEPRINT"
		save_blueprint_button.tooltip_text = "CLICK • SAVE CURRENT HULL AS BLUEPRINT" if is_station_drydock else "CLICK • SAVE BLUEPRINT"
		save_blueprint_button.custom_minimum_size.y = 28 if is_station_drydock else 34
		if is_station_drydock and save_blueprint_button.get_parent() != null:
			save_blueprint_button.get_parent().move_child(
				save_blueprint_button,
				save_blueprint_button.get_parent().get_child_count() - 1
			)
	if back_from_edit_button != null:
		back_from_edit_button.visible = not uses_owned_inventory
	if builder_resource_panel != null:
		builder_resource_panel.visible = current_context == "edit" and source_layout != null
	if builder_scroll != null:
		builder_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		builder_scroll.vertical_scroll_mode = (
			ScrollContainer.SCROLL_MODE_DISABLED
			if uses_owned_inventory
			else ScrollContainer.SCROLL_MODE_AUTO
		)
		builder_scroll.custom_minimum_size.y = 0 if is_station_drydock else 280
	if builder_view_actions != null:
		builder_view_actions.visible = not uses_owned_inventory
	if builder_status_label != null and uses_owned_inventory:
		builder_status_label.text = "ASSEMBLE REQUIRED SYSTEMS • OPTIONAL GRIDS MAY REMAIN IN CARGO" if is_escape_assembly else "DRAG LOCKER → HULL • HULL → LOCKER OR CHUTE"
	if inventory_header_label != null:
		inventory_header_label.text = "STOLEN GRIDS • DRAG TO KEEL" if is_escape_assembly else ("STOWED PARTS • DROP HERE" if is_station_drydock else "FORGE CATALOG • UNLIMITED")
	if close_terminal_button != null:
		close_terminal_button.text = "BREAK CLAMPS • BEGIN RUN  >" if is_escape_assembly else ("RETURN TO STATION  >" if is_station_drydock else "CLOSE TERMINAL  >")
		close_terminal_button.tooltip_text = "LAUNCH THE ASSEMBLED ESCAPE HULL" if is_escape_assembly else ("LEAVE DRYDOCK EDITOR" if is_station_drydock else "CLOSE SHIPYARD TERMINAL")
	if preview != null and uses_owned_inventory:
		_dock_shipyard_child(preview, 0.0, 0.0, 1.0, 1.0, 340.0, 0.0, -8.0, 0.0)
	if builder_grid != null and uses_owned_inventory:
		_dock_shipyard_child(builder_grid, 0.0, 0.0, 1.0, 1.0, 340.0, 0.0, -8.0, 0.0)
	if dossier_panel != null:
		dossier_panel.visible = false
		_dock_shipyard_child(dossier_panel, 1.0, 0.0, 1.0, 0.0, -346.0, 0.0, -8.0, 390.0)


func _build_interface() -> void:
	var shade := ColorRect.new()
	shade.name = "PauseShade"
	shade.color = Color(0.0, 0.0, 0.0, 0.72)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)

	root_panel = PanelContainer.new()
	root_panel.name = "ShipBuilderPanel"
	root_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root_panel.offset_left = 58
	root_panel.offset_top = 54
	root_panel.offset_right = -58
	root_panel.offset_bottom = -48
	root_panel.pivot_offset = Vector2(600, 340)
	root_panel.clip_contents = true
	root_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.015, 0.036, 0.04, 0.98), Color(0.28, 0.92, 0.88, 1.0)))
	add_child(root_panel)
	_build_builder_alert()

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_bottom", 16)
	root_panel.add_child(margin)

	var columns := VBoxContainer.new()
	columns.add_theme_constant_override("separation", 12)
	margin.add_child(columns)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	columns.add_child(header)

	var title_stack := VBoxContainer.new()
	title_stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title_stack)
	shipyard_title_label = Label.new()
	shipyard_title_label.text = "SHIPYARD COMMAND"
	shipyard_title_label.add_theme_font_size_override("font_size", 22)
	shipyard_title_label.add_theme_color_override("font_color", Color(0.72, 1.0, 0.94, 1.0))
	title_stack.add_child(shipyard_title_label)
	shipyard_subtitle_label = Label.new()
	shipyard_subtitle_label.text = "Paused drydock terminal. Choose a work order to arm the console."
	shipyard_subtitle_label.add_theme_font_size_override("font_size", 10)
	shipyard_subtitle_label.add_theme_color_override("font_color", Color(0.44, 0.75, 0.72, 1.0))
	title_stack.add_child(shipyard_subtitle_label)

	shipyard_notice_label = Label.new()
	shipyard_notice_label.text = "CONSOLE READY"
	shipyard_notice_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	shipyard_notice_label.add_theme_font_size_override("font_size", 10)
	shipyard_notice_label.add_theme_color_override("font_color", Color(0.28, 1.0, 0.88, 0.95))
	title_stack.add_child(shipyard_notice_label)

	close_terminal_button = Button.new()
	close_terminal_button.text = "CLOSE TERMINAL  >"
	close_terminal_button.custom_minimum_size = Vector2(154, 38)
	close_terminal_button.tooltip_text = "CLOSE SHIPYARD TERMINAL"
	close_terminal_button.pressed.connect(_request_close)
	_style_button(close_terminal_button)
	header.add_child(close_terminal_button)

	var body := Control.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.clip_contents = true
	columns.add_child(body)

	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(320, 0)
	left.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	left.add_theme_constant_override("separation", 10)
	body.add_child(left)
	_dock_shipyard_child(left, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 330.0, 0.0)

	var command_panel := _make_terminal_section("SHIPYARD COMMAND")
	command_section = command_panel
	left.add_child(command_panel)
	var command := _terminal_section_body(command_panel)

	var command_title := Label.new()
	command_title.text = "Select a shipyard station."
	command_title.add_theme_font_size_override("font_size", 9)
	command_title.add_theme_color_override("font_color", Color(0.46, 0.78, 0.74, 1.0))
	command.add_child(command_title)

	var new_button := Button.new()
	new_button.text = "NEW VESSEL"
	new_button.tooltip_text = "CLICK • CUT NEW FRAME"
	new_button.pressed.connect(_show_shipyard_context.bind("new_size"))
	_style_button(new_button)
	command.add_child(new_button)

	var edit_mode_button := Button.new()
	edit_mode_button.text = "EDIT CURRENT SHIP >"
	edit_mode_button.tooltip_text = "CLICK • EDIT ACTIVE HULL"
	edit_mode_button.pressed.connect(_show_shipyard_context.bind("edit"))
	_style_button(edit_mode_button)
	command.add_child(edit_mode_button)

	var load_mode_button := Button.new()
	load_mode_button.text = "LOAD BLUEPRINT >"
	load_mode_button.tooltip_text = "CLICK • OPEN BLUEPRINT ARCHIVE"
	load_mode_button.pressed.connect(_show_shipyard_context.bind("load"))
	_style_button(load_mode_button)
	command.add_child(load_mode_button)

	status_label = Label.new()
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.add_theme_font_size_override("font_size", 10)
	status_label.add_theme_color_override("font_color", Color(0.62, 0.8, 0.75, 1.0))
	status_label.text = "SHIPYARD READY"
	command.add_child(status_label)

	new_section = _make_terminal_section("NEW VESSEL")
	left.add_child(new_section)
	var new_body := _terminal_section_body(new_section)

	var new_title := Label.new()
	new_title.text = "Choose a vessel class, then select its drydock frame."
	new_title.add_theme_font_size_override("font_size", 9)
	new_title.add_theme_color_override("font_color", Color(0.46, 0.78, 0.74, 1.0))
	new_body.add_child(new_title)

	var class_label := Label.new()
	class_label.text = "VESSEL CLASS"
	class_label.add_theme_font_size_override("font_size", 9)
	class_label.add_theme_color_override("font_color", Color(1.0, 0.68, 0.18, 1.0))
	new_body.add_child(class_label)

	var class_row := HBoxContainer.new()
	class_row.add_theme_constant_override("separation", 4)
	new_body.add_child(class_row)
	for kind_value: Variant in ["SHIP", "STATION"]:
		var kind := String(kind_value)
		var kind_button := Button.new()
		kind_button.text = kind
		kind_button.toggle_mode = true
		kind_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		kind_button.set_pressed_no_signal(kind == selected_new_vessel_kind)
		kind_button.tooltip_text = "CLICK • AUTHOR %s FRAME" % kind
		kind_button.pressed.connect(_select_new_vessel_kind.bind(kind))
		_style_button(kind_button)
		class_row.add_child(kind_button)
		new_vessel_kind_buttons[kind] = kind_button

	new_size_options = VBoxContainer.new()
	new_size_options.add_theme_constant_override("separation", 4)
	new_body.add_child(new_size_options)

	var back_from_new_size_button := Button.new()
	back_from_new_size_button.text = "BACK"
	back_from_new_size_button.tooltip_text = "CLICK • BACK"
	back_from_new_size_button.pressed.connect(_show_shipyard_context.bind(""))
	_style_button(back_from_new_size_button)
	new_body.add_child(back_from_new_size_button)

	new_confirm_section = _make_terminal_section("AUTHORIZE HULL")
	left.add_child(new_confirm_section)
	var new_confirm_body := _terminal_section_body(new_confirm_section)

	var new_confirm_title := Label.new()
	new_confirm_title.text = "Name the vessel and authorize the empty frame."
	new_confirm_title.add_theme_font_size_override("font_size", 9)
	new_confirm_title.add_theme_color_override("font_color", Color(0.46, 0.78, 0.74, 1.0))
	new_confirm_body.add_child(new_confirm_title)

	new_frame_summary_label = Label.new()
	new_frame_summary_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	new_frame_summary_label.add_theme_font_size_override("font_size", 10)
	new_frame_summary_label.add_theme_color_override("font_color", Color(0.72, 1.0, 0.94, 1.0))
	new_confirm_body.add_child(new_frame_summary_label)

	new_design_name_field = LineEdit.new()
	new_design_name_field.placeholder_text = "NEW VESSEL NAME..."
	new_design_name_field.tooltip_text = "TYPE • HULL NAME"
	_style_line_edit(new_design_name_field)
	new_confirm_body.add_child(new_design_name_field)

	var confirm_new_button := Button.new()
	confirm_new_button.text = "CREATE AND EDIT HULL"
	confirm_new_button.tooltip_text = "CLICK • CREATE EMPTY HULL"
	confirm_new_button.pressed.connect(_new_ship_design)
	_style_button(confirm_new_button)
	new_confirm_body.add_child(confirm_new_button)

	var back_from_new_button := Button.new()
	back_from_new_button.text = "BACK"
	back_from_new_button.tooltip_text = "CLICK • BACK"
	back_from_new_button.pressed.connect(_show_shipyard_context.bind("new_size"))
	_style_button(back_from_new_button)
	new_confirm_body.add_child(back_from_new_button)

	save_section = _make_terminal_section("HULL ARCHIVE")
	left.add_child(save_section)
	var save_body := _terminal_section_body(save_section)

	save_title_label = Label.new()
	save_title_label.text = "Register the active hull as a reusable design."
	save_title_label.add_theme_font_size_override("font_size", 9)
	save_title_label.add_theme_color_override("font_color", Color(0.46, 0.78, 0.74, 1.0))
	save_body.add_child(save_title_label)

	design_name_field = LineEdit.new()
	design_name_field.placeholder_text = "DESIGN NAME..."
	design_name_field.tooltip_text = "TYPE • BLUEPRINT NAME"
	_style_line_edit(design_name_field)
	save_body.add_child(design_name_field)

	save_blueprint_button = Button.new()
	save_blueprint_button.text = "ARCHIVE BLUEPRINT"
	save_blueprint_button.tooltip_text = "CLICK • SAVE BLUEPRINT"
	save_blueprint_button.pressed.connect(_save_active_design)
	_style_button(save_blueprint_button)
	save_body.add_child(save_blueprint_button)

	builder_scroll = ScrollContainer.new()
	builder_scroll.custom_minimum_size = Vector2(0, 280)
	builder_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	save_body.add_child(builder_scroll)
	var builder_body := VBoxContainer.new()
	builder_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	builder_body.add_theme_constant_override("separation", 7)
	builder_scroll.add_child(builder_body)

	builder_status_label = Label.new()
	builder_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	builder_status_label.text = "Drydock grid armed. Choose a tool, then click cells in the center bay."
	builder_status_label.add_theme_font_size_override("font_size", 10)
	builder_status_label.add_theme_color_override("font_color", Color(0.72, 1.0, 0.94, 1.0))
	builder_body.add_child(builder_status_label)

	builder_resource_panel = PanelContainer.new()
	builder_resource_panel.name = "BuilderResourceRail"
	builder_resource_panel.z_index = 20
	builder_resource_panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	body.add_child(builder_resource_panel)
	# Ship-wide readiness is a centered HUD strip. Keeping it fixed-width gives
	# the catalog and the right-side dossier permanent, non-overlapping lanes.
	_dock_shipyard_child(builder_resource_panel, 0.5, 0.0, 0.5, 0.0, -184.0, 0.0, 184.0, 38.0)
	var resource_margin := MarginContainer.new()
	builder_resource_panel.add_child(resource_margin)
	var resource_stack := HBoxContainer.new()
	resource_stack.add_theme_constant_override("separation", 6)
	resource_margin.add_child(resource_stack)
	builder_power_meter = ArcadeResourceMeterScript.new() as Control
	builder_power_meter.set("compact_hud", true)
	builder_power_meter.custom_minimum_size = Vector2(180, 38)
	builder_power_meter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	resource_stack.add_child(builder_power_meter)
	builder_crew_meter = ArcadeResourceMeterScript.new() as Control
	builder_crew_meter.set("meter_kind", 1)
	builder_crew_meter.set("compact_hud", true)
	builder_crew_meter.custom_minimum_size = Vector2(180, 38)
	builder_crew_meter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	resource_stack.add_child(builder_crew_meter)

	var inventory_header_row := HBoxContainer.new()
	inventory_header_row.add_theme_constant_override("separation", 6)
	builder_body.add_child(inventory_header_row)
	inventory_header_label = Label.new()
	inventory_header_label.text = "FORGE CATALOG • UNLIMITED"
	inventory_header_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inventory_header_label.add_theme_font_size_override("font_size", 10)
	inventory_header_label.add_theme_color_override("font_color", Color(1.0, 0.68, 0.28, 1.0))
	inventory_header_row.add_child(inventory_header_label)
	var trash_drop: Control = ForgeTrashDropScript.new()
	trash_drop.connect("grid_discarded", _on_installed_piece_discarded)
	inventory_header_row.add_child(trash_drop)
	var inventory_panel := PanelContainer.new()
	inventory_panel.custom_minimum_size.y = 82
	inventory_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.004, 0.025, 0.025, 0.92), Color(0.1, 0.5, 0.46, 0.9)))
	builder_body.add_child(inventory_panel)
	var inventory_margin := MarginContainer.new()
	inventory_margin.add_theme_constant_override("margin_left", 5)
	inventory_margin.add_theme_constant_override("margin_top", 5)
	inventory_margin.add_theme_constant_override("margin_right", 5)
	inventory_margin.add_theme_constant_override("margin_bottom", 5)
	inventory_panel.add_child(inventory_margin)
	forge_inventory_grid = ForgeInventoryGridScript.new() as Container
	forge_inventory_grid.connect("installed_piece_returned", _on_installed_piece_returned)
	forge_inventory_grid.connect("piece_position_changed", _on_inventory_piece_position_changed)
	inventory_margin.add_child(forge_inventory_grid)

	builder_view_actions = HBoxContainer.new()
	builder_view_actions.add_theme_constant_override("separation", 5)
	builder_body.add_child(builder_view_actions)
	var zoom_out_button := Button.new()
	zoom_out_button.text = "VIEW -"
	zoom_out_button.tooltip_text = "CLICK • ZOOM OUT"
	zoom_out_button.pressed.connect(_adjust_builder_zoom.bind(1.0 / 1.18))
	_style_compact_button(zoom_out_button)
	builder_view_actions.add_child(zoom_out_button)
	var center_view_button := Button.new()
	center_view_button.text = "CENTER"
	center_view_button.tooltip_text = "CLICK • CENTER HULL"
	center_view_button.pressed.connect(_fit_builder_view)
	_style_compact_button(center_view_button)
	builder_view_actions.add_child(center_view_button)
	var zoom_in_button := Button.new()
	zoom_in_button.text = "VIEW +"
	zoom_in_button.tooltip_text = "CLICK • ZOOM IN"
	zoom_in_button.pressed.connect(_adjust_builder_zoom.bind(1.18))
	_style_compact_button(zoom_in_button)
	builder_view_actions.add_child(zoom_in_button)

	builder_tool_row = HBoxContainer.new()
	builder_tool_row.add_theme_constant_override("separation", 5)
	builder_body.add_child(builder_tool_row)
	for tool_name: String in ["ADD", "DELETE", "GROUP"]:
		var tool_button := Button.new()
		tool_button.text = tool_name
		tool_button.tooltip_text = "CLICK • %s TOOL" % tool_name.to_upper()
		tool_button.pressed.connect(_set_builder_tool.bind(tool_name.to_lower()))
		_style_compact_button(tool_button)
		tool_button.custom_minimum_size = Vector2(92, 30)
		builder_tool_row.add_child(tool_button)

	builder_add_header = Button.new()
	builder_add_header.text = "CELL TYPE >"
	builder_add_header.tooltip_text = "CLICK • OPEN GRID CATALOG"
	builder_add_header.pressed.connect(_set_builder_tool.bind("add"))
	_style_compact_button(builder_add_header)
	builder_body.add_child(builder_add_header)

	builder_type_buttons = VBoxContainer.new()
	builder_type_buttons.add_theme_constant_override("separation", 4)
	builder_body.add_child(builder_type_buttons)

	builder_group_header = Button.new()
	builder_group_header.text = "GROUP OPERATIONS >"
	builder_group_header.tooltip_text = "CLICK • GROUP CONTROLS"
	builder_group_header.pressed.connect(_set_builder_tool.bind("group"))
	_style_compact_button(builder_group_header)
	builder_body.add_child(builder_group_header)

	builder_group_actions = HBoxContainer.new()
	builder_group_actions.add_theme_constant_override("separation", 5)
	builder_body.add_child(builder_group_actions)
	for action_name: String in ["CLEAR"]:
		var action_button := Button.new()
		action_button.text = action_name
		action_button.custom_minimum_size = Vector2(92, 30)
		match action_name:
			"COMBINE":
				action_button.pressed.connect(_combine_builder_selection)
			"SPLIT":
				action_button.pressed.connect(_split_builder_selection)
			_:
				action_button.pressed.connect(_clear_builder_group_selection)
		_style_compact_button(action_button)
		builder_group_actions.add_child(action_button)
		match action_name:
			"COMBINE":
				builder_combine_button = action_button
			"SPLIT":
				builder_split_button = action_button
			_:
				builder_clear_selection_button = action_button

	builder_delete_actions = HBoxContainer.new()
	builder_delete_actions.add_theme_constant_override("separation", 5)
	builder_body.add_child(builder_delete_actions)
	var clear_cell_button := Button.new()
	clear_cell_button.text = "CLEAR CELL"
	clear_cell_button.tooltip_text = "CLICK • REMOVE CELL"
	clear_cell_button.pressed.connect(_confirm_builder_delete_cell)
	_style_compact_button(clear_cell_button)
	builder_delete_actions.add_child(clear_cell_button)
	var cancel_delete_button := Button.new()
	cancel_delete_button.text = "CANCEL"
	cancel_delete_button.tooltip_text = "CLICK • CANCEL"
	cancel_delete_button.pressed.connect(_cancel_builder_context)
	_style_compact_button(cancel_delete_button)
	builder_delete_actions.add_child(cancel_delete_button)

	back_from_edit_button = Button.new()
	back_from_edit_button.text = "RETURN TO COMMAND <"
	back_from_edit_button.tooltip_text = "CLICK • RETURN TO SHIPYARD COMMAND"
	back_from_edit_button.pressed.connect(_return_to_shipyard_command)
	_style_button(back_from_edit_button)
	save_body.add_child(back_from_edit_button)

	load_section = _make_terminal_section("LOAD BLUEPRINT")
	left.add_child(load_section)
	var load_body := _terminal_section_body(load_section)

	var archive_title := Label.new()
	archive_title.text = "Local shipyard design archive. Open the catalog, choose a hull card, then commit it."
	archive_title.add_theme_font_size_override("font_size", 9)
	archive_title.add_theme_color_override("font_color", Color(0.46, 0.78, 0.74, 1.0))
	load_body.add_child(archive_title)

	open_catalog_button = Button.new()
	open_catalog_button.text = "OPEN BLUEPRINT CATALOG"
	open_catalog_button.tooltip_text = "CLICK • OPEN ARCHIVE"
	open_catalog_button.pressed.connect(_open_blueprint_catalog)
	_style_button(open_catalog_button)
	load_body.add_child(open_catalog_button)

	blueprint_selection_label = Label.new()
	blueprint_selection_label.text = "No blueprint selected."
	blueprint_selection_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	blueprint_selection_label.add_theme_font_size_override("font_size", 10)
	blueprint_selection_label.add_theme_color_override("font_color", Color(0.58, 0.9, 0.84, 1.0))
	load_body.add_child(blueprint_selection_label)

	load_actions_section = _make_terminal_section("SELECTED HULL")
	load_body.add_child(load_actions_section)
	var load_actions := _terminal_section_body(load_actions_section)

	edit_blueprint_button = Button.new()
	edit_blueprint_button.text = "EDIT BLUEPRINT"
	edit_blueprint_button.tooltip_text = "CLICK • LOAD + EDIT"
	edit_blueprint_button.pressed.connect(_load_selected_design)
	_style_button(edit_blueprint_button)
	load_actions.add_child(edit_blueprint_button)

	play_blueprint_button = Button.new()
	play_blueprint_button.text = "PLAY AS THIS SHIP"
	play_blueprint_button.tooltip_text = "CLICK • LOAD + LAUNCH"
	play_blueprint_button.pressed.connect(_play_selected_design)
	_style_button(play_blueprint_button)
	load_actions.add_child(play_blueprint_button)

	delete_blueprint_button = Button.new()
	delete_blueprint_button.text = "DELETE BLUEPRINT"
	delete_blueprint_button.tooltip_text = "CLICK • DELETE BLUEPRINT"
	delete_blueprint_button.pressed.connect(_delete_selected_design)
	_style_button(delete_blueprint_button)
	load_actions.add_child(delete_blueprint_button)

	var back_from_load_button := Button.new()
	back_from_load_button.text = "BACK"
	back_from_load_button.tooltip_text = "CLICK • BACK"
	back_from_load_button.pressed.connect(_show_shipyard_context.bind(""))
	_style_button(back_from_load_button)
	load_body.add_child(back_from_load_button)

	envelope_section = _make_terminal_section("CONSTRUCTION ENVELOPE")
	left.add_child(envelope_section)
	var envelope := _terminal_section_body(envelope_section)

	var envelope_note := Label.new()
	envelope_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	envelope_note.text = "Envelope controls are handled during new hull setup. Use the grid editor for room placement, grouping, and facing."
	envelope_note.add_theme_font_size_override("font_size", 10)
	envelope_note.add_theme_color_override("font_color", Color(0.46, 0.78, 0.74, 1.0))
	envelope.add_child(envelope_note)

	_show_shipyard_context("", false)

	preview = ShipBuilderPreview.new()
	preview.custom_minimum_size = Vector2(430, 430)
	preview.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(preview)
	_dock_shipyard_child(preview, 0.5, 0.0, 0.5, 1.0, -215.0, 0.0, 215.0, 0.0)

	dossier_panel = PanelContainer.new()
	dossier_panel.name = "DossierPanel"
	dossier_panel.visible = false
	dossier_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.005, 0.03, 0.028, 0.9), Color(0.28, 0.96, 0.88, 0.95), 2))
	body.add_child(dossier_panel)
	_dock_shipyard_child(dossier_panel, 1.0, 0.0, 1.0, 0.0, -346.0, 0.0, -8.0, 390.0)
	var stat_margin := MarginContainer.new()
	stat_margin.add_theme_constant_override("margin_left", 10)
	stat_margin.add_theme_constant_override("margin_top", 10)
	stat_margin.add_theme_constant_override("margin_right", 10)
	stat_margin.add_theme_constant_override("margin_bottom", 10)
	dossier_panel.add_child(stat_margin)

	var dossier_stack := VBoxContainer.new()
	dossier_stack.add_theme_constant_override("separation", 8)
	stat_margin.add_child(dossier_stack)

	stat_label = RichTextLabel.new()
	stat_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stat_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stat_label.bbcode_enabled = true
	stat_label.fit_content = false
	stat_label.scroll_active = false
	stat_label.clip_contents = true
	stat_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stat_label.add_theme_font_size_override("normal_font_size", 10)
	stat_label.add_theme_font_size_override("bold_font_size", 11)
	stat_label.add_theme_color_override("default_color", Color(0.67, 0.86, 0.8, 1.0))
	dossier_stack.add_child(stat_label)

	# Direction is a property of the selected physical mount, so its control
	# belongs with that mount's dossier rather than among inventory operations.
	builder_facing_actions = DrydockFacingSelectorScript.new() as Control
	builder_facing_actions.custom_minimum_size = Vector2(94, 70)
	builder_facing_actions.connect("facing_selected", _set_builder_facing)
	builder_facing_actions.connect("facing_blocked", _on_builder_facing_blocked)
	dossier_stack.add_child(builder_facing_actions)

	_build_blueprint_catalog_panel()
	_populate_builder_type_buttons()
	_populate_forge_inventory()
	_set_builder_tool("")


func _populate_size_selector() -> void:
	_populate_size_options_for(size_options, false)


func _dock_shipyard_child(control: Control, left_anchor: float, top_anchor: float, right_anchor: float, bottom_anchor: float, left_offset: float, top_offset: float, right_offset: float, bottom_offset: float) -> void:
	control.anchor_left = left_anchor
	control.anchor_top = top_anchor
	control.anchor_right = right_anchor
	control.anchor_bottom = bottom_anchor
	control.offset_left = left_offset
	control.offset_top = top_offset
	control.offset_right = right_offset
	control.offset_bottom = bottom_offset


func _populate_builder_type_buttons() -> void:
	if builder_type_buttons == null:
		return
	for child: Node in builder_type_buttons.get_children():
		child.queue_free()
	if _uses_owned_inventory():
		_add_builder_category_label("CARGO CONTROL")
		var cargo_instruction := Label.new()
		cargo_instruction.text = "DRAG AN OWNED GRID\nFROM THE INVENTORY."
		cargo_instruction.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		cargo_instruction.add_theme_font_size_override("font_size", 9)
		cargo_instruction.add_theme_color_override("font_color", Color(0.48, 0.9, 0.86, 1.0))
		builder_type_buttons.add_child(cargo_instruction)
		return
	var categories: Array[Dictionary] = [
		{"title": "COMMAND", "types": ["COMMAND", "UNASSIGNED"]},
		{"title": "ENGINEERING", "types": ["POWER", "PROPULSION", "SHIELDS", "WORKSHOP"]},
		{"title": "TACTICAL", "types": ["WEAPONS", "HANGAR"]},
		{"title": "CREW SERVICES", "types": ["CREW_QUARTERS", "MEDICAL", "SECURITY"]},
	]
	for category: Dictionary in categories:
		_add_builder_category_label(String(category["title"]))
		for room_type: String in category["types"]:
			var button := Button.new()
			var requirement_status := _builder_grid_type_requirement_status(room_type, builder_pending_add_cell)
			var has_warning := not bool(requirement_status["valid"])
			var is_locked := has_warning and inventory_mode != "FORGE"
			var label := _room_type_palette_name(room_type)
			button.text = label.to_upper()
			if room_type == builder_room_type:
				button.text = "%s   ARMED" % label.to_upper()
			if is_locked:
				button.text = "%s   LOCKED" % label.to_upper()
				button.tooltip_text = "LOCKED • %s" % " ".join(requirement_status["details"])
			elif has_warning:
				button.text = "%s   ⚠" % label.to_upper()
				button.tooltip_text = "PLACEABLE WITH WARNING • %s" % " ".join(requirement_status["details"])
			else:
				button.tooltip_text = "CLICK • INSTALL %s" % label.to_upper()
			button.disabled = is_locked
			button.pressed.connect(_set_builder_room_type.bind(room_type))
			_style_compact_button(button)
			if room_type == builder_room_type and not is_locked:
				button.add_theme_stylebox_override("normal", _button_style(Color(0.86, 0.63, 0.25, 0.96), Color(1.0, 0.86, 0.32, 1.0)))
				button.add_theme_color_override("font_color", Color(0.08, 0.025, 0.0, 1.0))
			builder_type_buttons.add_child(button)


func _add_builder_category_label(title_text: String) -> void:
	var label := Label.new()
	label.text = title_text
	label.add_theme_font_size_override("font_size", 9)
	label.add_theme_color_override("font_color", Color(1.0, 0.68, 0.28, 0.98))
	builder_type_buttons.add_child(label)


func _populate_forge_inventory() -> void:
	if forge_inventory_grid == null or source_layout == null:
		return
	if forge_inventory_initialized:
		return
	for child: Node in forge_inventory_grid.get_children():
		child.queue_free()
	if _uses_owned_inventory():
		if not owned_grid_instances.is_empty():
			owned_grid_instances.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
				var first_key := String(a.get("inventory_key", ""))
				var second_key := String(b.get("inventory_key", ""))
				return first_key < second_key or (
					first_key == second_key
					and int(a.get("instance_id", 0)) < int(b.get("instance_id", 0))
				)
			)
			for inventory_instance: Dictionary in owned_grid_instances:
				var inventory_key := String(inventory_instance.get("inventory_key", ""))
				var recipe := _inventory_recipe_for_key(inventory_key)
				var room_type := "WEAPONS" if recipe != null else inventory_key
				_add_forge_inventory_piece(room_type, null, inventory_key, recipe, inventory_instance)
		else:
			var inventory_keys := owned_grid_inventory.keys()
			inventory_keys.sort()
			for key_value: Variant in inventory_keys:
				var inventory_key := String(key_value)
				var piece_count := maxi(int(owned_grid_inventory.get(inventory_key, 0)), 0)
				var recipe := _inventory_recipe_for_key(inventory_key)
				var room_type := "WEAPONS" if recipe != null else inventory_key
				for piece_index: int in range(piece_count):
					_add_forge_inventory_piece(room_type, null, inventory_key, recipe)
	else:
		var templates: Array = (source_layout.get("room_types") as Array).duplicate()
		templates.sort_custom(func(a: Resource, b: Resource) -> bool:
			return _room_type_palette_name(String(a.get("type_name"))) < _room_type_palette_name(String(b.get("type_name")))
		)
		for template: Resource in templates:
			var room_type := String(template.get("type_name"))
			if room_type != "WEAPONS":
				_add_forge_inventory_piece(room_type, template)
		for recipe: Resource in source_layout.get("module_recipes"):
			if (
				recipe != null
				and int(recipe.get("family")) == ModuleRecipeDefinition.ModuleFamily.WEAPON
			):
				_add_forge_inventory_piece(
					"WEAPONS",
					null,
					_weapon_inventory_key(recipe),
					recipe
				)
	forge_inventory_initialized = true


func _add_forge_inventory_piece(
	room_type: String,
	supplied_template: Resource = null,
	inventory_key: String = "",
	recipe: Resource = null,
	inventory_instance: Dictionary = {}
) -> Control:
	if forge_inventory_grid == null or source_layout == null:
		return null
	var template := supplied_template
	if template == null:
		for candidate: Resource in source_layout.get("room_types") as Array:
			if String(candidate.get("type_name")) == room_type:
				template = candidate
				break
	if template == null:
		return null
	var resolved_key := inventory_key if not inventory_key.is_empty() else room_type
	var piece_name := (
		String(recipe.get("display_name"))
		if recipe != null
		else _room_type_palette_name(room_type)
	)
	var piece_color: Color = _inventory_category_color(room_type)
	var piece_footprint := _inventory_piece_footprint(room_type, template, recipe)
	var power_delta := ShipBuilderAnalyzer.room_power_delta(room_type, 1, template)
	if recipe != null:
		var recipe_requirement := int(recipe.get("required_reactor_fields"))
		if recipe_requirement <= 0 and float(recipe.get("power_draw")) > 0.0:
			recipe_requirement = maxi(ceili(float(recipe.get("power_draw"))), 1)
		power_delta = Vector2(0.0, float(recipe_requirement))
	var piece_minimum_crew := int(template.get("minimum_crew"))
	var piece_optimal_crew := int(template.get("optimal_crew"))
	if recipe != null:
		piece_minimum_crew = maxi(piece_minimum_crew, int(recipe.get("minimum_crew")))
		piece_optimal_crew = maxi(piece_optimal_crew, int(recipe.get("optimal_crew")))
	piece_optimal_crew = ROOM_STAFFING_RULES.effective_requirements(template, piece_minimum_crew, piece_optimal_crew).y
	var piece: Control = ForgeInventoryPieceScript.new()
	piece.call(
		"configure",
		room_type,
		piece_name,
		piece_color,
		piece_footprint,
		roundi(power_delta.x),
		roundi(power_delta.y),
		resolved_key,
		recipe,
		int(inventory_instance.get("instance_id", 0)),
		inventory_instance,
		piece_optimal_crew
	)
	var power_hint := "PROJECTS A REACTOR FIELD" if power_delta.x > 0.0 else (
		"REQUIRES %d REACTOR FIELD%s" % [roundi(power_delta.y), "" if roundi(power_delta.y) == 1 else "S"] if power_delta.y > 0.0 else "NO REACTOR LINK REQUIRED"
	)
	var crew_hint := "CREW COMPLEMENT • %d" % piece_optimal_crew if piece_optimal_crew > 0 else "NO CREW STATIONS REQUIRED"
	piece.tooltip_text = "%s\n%s\n%s\nDRAG TO INSTALL" % [
		"%s • %s" % [piece_name.to_upper(), _inventory_footprint_label(piece_footprint)],
		power_hint,
		crew_hint,
	]
	piece.connect("selected", _select_forge_inventory_piece)
	forge_inventory_grid.add_child(piece)
	for sibling: Node in forge_inventory_grid.get_children():
		if sibling == piece or not "room_type" in sibling:
			continue
		if String(sibling.get("display_name")) > piece_name:
			forge_inventory_grid.move_child(piece, sibling.get_index())
			break
	return piece


func _inventory_category_color(room_type: String) -> Color:
	return GridInventoryCatalogScript.category_color(room_type)


func _inventory_piece_footprint(room_type: String, template: Resource, recipe: Resource) -> Vector2i:
	return GridInventoryCatalogScript.footprint(room_type, template, recipe)


func _inventory_footprint_label(footprint: Vector2i) -> String:
	return GridInventoryCatalogScript.footprint_label(footprint)


func _select_forge_inventory_piece(room_type: String, source_instance_id: int) -> void:
	_inspect_forge_inventory_piece(room_type, source_instance_id)


func _inspect_forge_inventory_piece(room_type: String, source_instance_id: int) -> void:
	var selected_piece := _inventory_piece_by_id(source_instance_id, room_type)
	if selected_piece == null:
		return
	# A tap is an inspection gesture. Installation is deliberately reserved for
	# an actual drag (or the controller's explicit pickup action).
	forge_armed_piece_id = 0
	builder_room_type = ""
	builder_inventory_key = ""
	builder_module_recipe = null
	_set_builder_tool("")
	inspected_inventory_piece_id = source_instance_id
	inspected_inventory_room_type = room_type
	if builder_grid != null:
		builder_grid.call("set_inventory_piece_armed", false)
		builder_grid.call("clear_room_selection")
	_set_builder_status(
		"%s SELECTED • DRAG FROM THE CATALOG TO INSTALL"
		% String(selected_piece.get("display_name")).to_upper()
	)
	_refresh_display()


func _arm_forge_inventory_piece(room_type: String, source_instance_id: int) -> void:
	builder_room_type = room_type
	forge_armed_piece_id = source_instance_id
	var selected_piece := _inventory_piece_by_id(source_instance_id, room_type)
	if selected_piece == null:
		forge_armed_piece_id = 0
		builder_room_type = ""
		return
	inspected_inventory_piece_id = source_instance_id
	inspected_inventory_room_type = room_type
	builder_inventory_key = (
		String(selected_piece.get("inventory_key"))
		if selected_piece != null
		else room_type
	)
	builder_module_recipe = (
		selected_piece.get("module_recipe") as Resource
		if selected_piece != null
		else null
	)
	_set_builder_tool("add")
	var selected_footprint := (
		Vector2i(selected_piece.get("footprint"))
		if selected_piece != null
		else Vector2i(2, 2)
	)
	if builder_grid != null:
		builder_grid.call("set_inventory_piece_armed", true, true, room_type, selected_footprint)
	var empty_frame := source_layout != null and (source_layout.get("rooms") as Array).is_empty()
	if empty_frame and room_type in ["POWER", "REACTOR", "ENGINE"]:
		_set_builder_status(
			"%s ARMED • PLACE ON THE CENTER KEEL SOCKET"
			% _room_type_palette_name(room_type).to_upper()
		)
	elif empty_frame:
		_set_builder_status("EMPTY FRAME • INSTALL A REACTOR ON THE CENTER KEEL SOCKET FIRST")
	else:
		_set_builder_status(
			"%s ARMED • PLACE INSIDE A REACTOR FIELD"
			% _room_type_palette_name(room_type).to_upper()
		)
	_refresh_display()


func _weapon_inventory_key(recipe: Resource) -> String:
	return "WEAPON:%s" % String(recipe.get("module_id"))


func _inventory_recipe_for_key(inventory_key: String) -> Resource:
	return GridInventoryCatalogScript.recipe_for_key(source_layout, inventory_key)


func _populate_new_size_selector() -> void:
	_populate_size_options_for(new_size_options, true)


func _build_blueprint_catalog_panel() -> void:
	blueprint_catalog_panel = _make_terminal_section("BLUEPRINT CATALOG")
	blueprint_catalog_panel.name = "BlueprintCatalogPanel"
	blueprint_catalog_panel.visible = false
	blueprint_catalog_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	blueprint_catalog_panel.anchor_left = 0.18
	blueprint_catalog_panel.anchor_top = 0.22
	blueprint_catalog_panel.anchor_right = 0.68
	blueprint_catalog_panel.anchor_bottom = 0.82
	blueprint_catalog_panel.offset_left = 0.0
	blueprint_catalog_panel.offset_top = 0.0
	blueprint_catalog_panel.offset_right = 0.0
	blueprint_catalog_panel.offset_bottom = 0.0
	add_child(blueprint_catalog_panel)

	var body := _terminal_section_body(blueprint_catalog_panel)
	var note := Label.new()
	note.text = "Choose a stored hull card. The center drydock preview updates before anything is committed."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_font_size_override("font_size", 10)
	note.add_theme_color_override("font_color", Color(0.46, 0.78, 0.74, 1.0))
	body.add_child(note)

	var archive_scroll := ScrollContainer.new()
	archive_scroll.custom_minimum_size = Vector2(0, 300)
	archive_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	archive_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(archive_scroll)

	blueprint_card_grid = GridContainer.new()
	blueprint_card_grid.columns = 3
	blueprint_card_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	blueprint_card_grid.add_theme_constant_override("h_separation", 10)
	blueprint_card_grid.add_theme_constant_override("v_separation", 10)
	archive_scroll.add_child(blueprint_card_grid)

	var close_catalog_button := Button.new()
	close_catalog_button.text = "BACK"
	close_catalog_button.tooltip_text = "CLICK • CLOSE"
	close_catalog_button.pressed.connect(_close_blueprint_catalog)
	_style_button(close_catalog_button)
	body.add_child(close_catalog_button)


func _populate_size_options_for(container: VBoxContainer, is_new_ship: bool) -> void:
	if container == null:
		return
	for child: Node in container.get_children():
		child.queue_free()
	var sizes := envelope_presets.duplicate()
	var selected_full_size := _full_grid_size(selected_size)
	if selected_full_size != Vector2i.ZERO and not sizes.has(selected_full_size):
		sizes.append(selected_full_size)
	sizes.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.x * a.y < b.x * b.y)
	for index: int in range(sizes.size()):
		var size_value: Vector2i = sizes[index]
		var button := Button.new()
		button.text = "%dx%d FULL GRID   %d ROOMS" % [size_value.x, size_value.y, size_value.x * size_value.y]
		button.tooltip_text = "CLICK • %dx%d FULL-ROOM FRAME" % [size_value.x, size_value.y]
		button.mouse_entered.connect(_preview_frame_size.bind(size_value))
		button.mouse_exited.connect(_clear_frame_size_preview.bind(size_value))
		button.pressed.connect(_select_size_option.bind(size_value, is_new_ship))
		_style_size_option_button(button, size_value == selected_full_size)
		button.custom_minimum_size.y = 28
		container.add_child(button)


func _lattice_size(full_grid_size: Vector2i) -> Vector2i:
	return Vector2i(
		maxi(full_grid_size.x, 1) * QUARTER_CELLS_PER_FULL_GRID,
		maxi(full_grid_size.y, 1) * QUARTER_CELLS_PER_FULL_GRID
	)


func _full_grid_size(lattice_size: Vector2i) -> Vector2i:
	if lattice_size == Vector2i.ZERO:
		return Vector2i.ZERO
	return Vector2i(
		ceili(float(lattice_size.x) / float(QUARTER_CELLS_PER_FULL_GRID)),
		ceili(float(lattice_size.y) / float(QUARTER_CELLS_PER_FULL_GRID))
	)


func _on_size_selected(index: int) -> void:
	_select_size_option(Vector2i.ZERO, false)


func _on_new_size_selected(index: int) -> void:
	_select_size_option(Vector2i.ZERO, true)


func _select_size_option(size_value: Vector2i, is_new_ship: bool) -> void:
	if size_value != Vector2i.ZERO:
		selected_size = _lattice_size(size_value)
	hovered_frame_size = Vector2i.ZERO
	_populate_size_selector()
	_populate_new_size_selector()
	_play_menu_sound(open_sound_method)
	_refresh_display()
	if is_new_ship:
		_show_shipyard_context("new_confirm")
	else:
		var full_size := _full_grid_size(selected_size)
		status_label.text = "Build envelope preview armed - %dx%d full rooms" % [full_size.x, full_size.y]


func _select_new_vessel_kind(kind: String) -> void:
	var normalized := kind.to_upper()
	if normalized != "SHIP" and normalized != "STATION":
		normalized = "SHIP"
	selected_new_vessel_kind = normalized
	for key: Variant in new_vessel_kind_buttons.keys():
		var button := new_vessel_kind_buttons.get(key) as Button
		if button != null:
			button.set_pressed_no_signal(String(key) == normalized)
	_update_new_frame_summary()
	_play_menu_sound(open_sound_method)


func _preview_frame_size(size_value: Vector2i) -> void:
	if current_context != "new_size" and current_context != "new_confirm":
		return
	hovered_frame_size = _lattice_size(size_value)
	if shipyard_notice_label != null:
		shipyard_notice_label.text = "FRAME SCAN   %dx%d FULL ROOMS   %d PIECES" % [size_value.x, size_value.y, size_value.x * size_value.y]
		shipyard_notice_label.add_theme_color_override("font_color", Color(0.28, 1.0, 0.88, 0.98))
	_refresh_display()


func _clear_frame_size_preview(size_value: Vector2i) -> void:
	if hovered_frame_size != _lattice_size(size_value):
		return
	hovered_frame_size = Vector2i.ZERO
	if current_context == "new_size":
		_announce_shipyard("NEW HULL CHANNEL   FRAME SELECTION")
	elif current_context == "new_confirm":
		_announce_shipyard("NEW HULL CHANNEL   AUTHORIZE FRAME")
	_refresh_display()


func _show_shipyard_context(context: String, play_sound := true) -> void:
	var previous_context := current_context
	hovered_frame_size = Vector2i.ZERO
	current_context = context
	var animate := play_sound and previous_context != context
	for section: PanelContainer in [command_section, new_section, new_confirm_section, save_section, load_section, envelope_section]:
		if section != null and not _section_matches_context(section, context):
			_hide_section(section, animate)
	_set_section_active(command_section, context == "", animate)
	_set_section_active(new_section, context == "new_size", animate)
	_set_section_active(new_confirm_section, context == "new_confirm", animate)
	_set_section_active(save_section, context == "edit", animate)
	_set_section_active(load_section, context == "load", animate)
	_set_section_active(envelope_section, false, animate)
	if context != "load":
		_close_blueprint_catalog(false)
	if play_sound:
		_play_menu_sound(open_sound_method)
	match context:
		"new_size":
			_populate_new_size_selector()
			if new_design_name_field != null and new_design_name_field.text.strip_edges().is_empty():
				new_design_name_field.text = "%s %d" % ["New Station" if selected_new_vessel_kind == "STATION" else "New Hull", Time.get_ticks_msec()]
			status_label.text = "New vessel station online. Choose a drydock frame."
			_announce_shipyard("NEW HULL CHANNEL   FRAME SELECTION")
		"new_confirm":
			if new_design_name_field != null and new_design_name_field.text.strip_edges().is_empty():
				new_design_name_field.text = "%s %d" % ["New Station" if selected_new_vessel_kind == "STATION" else "New Hull", Time.get_ticks_msec()]
			_update_new_frame_summary()
			status_label.text = "Frame selected. Name the vessel and authorize construction."
			_announce_shipyard("NEW HULL CHANNEL   AUTHORIZE FRAME")
		"edit":
			status_label.text = "Drydock editor online. Build directly on the center grid."
			builder_tool = ""
			builder_room_type = ""
			builder_last_selected_cell = INVALID_CELL
			_clear_builder_group_selection()
			if builder_grid != null:
				builder_grid.call("set_editor_focus_cell", INVALID_CELL, Vector2.ZERO)
			_populate_builder_type_buttons()
			_set_builder_tool("")
			_announce_shipyard("DRYDOCK EDITOR   CLICK A CELL")
		"load":
			_refresh_blueprint_archive()
			_open_blueprint_catalog()
			status_label.text = "Blueprint archive online. Select a stored hull design."
			_announce_shipyard("BLUEPRINT ARCHIVE   SELECT A HULL CARD")
		_:
			status_label.text = "Shipyard standing by. No hull is connected to the terminal yet."
			_announce_shipyard("SHIPYARD STANDBY")
	_refresh_display()


func _update_new_frame_summary() -> void:
	if new_frame_summary_label == null:
		return
	var lattice_size := selected_size if selected_size != Vector2i.ZERO else Vector2i(6, 6)
	var size_value := _full_grid_size(lattice_size)
	new_frame_summary_label.text = "Vessel class: %s\nSelected frame: %d x %d full rooms\nInternal lattice: %d x %d quarter cells\nBuild capacity: %d full grid pieces\nHull state: empty drydock frame" % [
		selected_new_vessel_kind,
		size_value.x,
		size_value.y,
		lattice_size.x,
		lattice_size.y,
		size_value.x * size_value.y,
	]


func _refresh_blueprint_archive() -> void:
	if blueprint_card_grid == null:
		return
	_ensure_blueprint_directory()
	for child: Node in blueprint_card_grid.get_children():
		child.queue_free()
	blueprint_cards.clear()
	var directory := DirAccess.open(BLUEPRINT_DIRECTORY)
	if directory == null:
		selected_blueprint_path = ""
		selected_blueprint_layout = null
		_add_blueprint_empty_notice("NO BLUEPRINT ARCHIVE FOUND")
		_update_blueprint_selection_readout()
		return
	var files: PackedStringArray = []
	directory.list_dir_begin()
	var file_name := directory.get_next()
	while not file_name.is_empty():
		if not directory.current_is_dir() and file_name.get_extension().to_lower() == "tres":
			files.append(file_name)
		file_name = directory.get_next()
	directory.list_dir_end()
	files.sort()
	if files.is_empty():
		selected_blueprint_path = ""
		selected_blueprint_layout = null
		_add_blueprint_empty_notice("NO SAVED BLUEPRINTS")
		_update_blueprint_selection_readout()
		return
	var still_has_selection := false
	for file: String in files:
		var path := "%s/%s" % [BLUEPRINT_DIRECTORY, file]
		var layout := ResourceLoader.load(path)
		var display_name := file.get_basename().capitalize()
		if layout != null:
			display_name = _layout_display_name(layout)
		_add_blueprint_card(display_name, path, layout)
		if path == selected_blueprint_path:
			still_has_selection = true
			selected_blueprint_layout = layout
	if not still_has_selection:
		selected_blueprint_path = ""
		selected_blueprint_layout = null
	_update_blueprint_selection_readout()


func _add_blueprint_empty_notice(text: String) -> void:
	var notice := Label.new()
	notice.text = text
	notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	notice.add_theme_font_size_override("font_size", 10)
	notice.add_theme_color_override("font_color", Color(0.72, 1.0, 0.94, 0.85))
	blueprint_card_grid.add_child(notice)


func _add_blueprint_card(display_name: String, path: String, layout: Resource) -> void:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(166, 174)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.tooltip_text = "CLICK • SELECT"
	card.set_meta("blueprint_path", path)
	card.set_meta("blueprint_layout", layout)
	blueprint_card_grid.add_child(card)
	blueprint_cards.append(card)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	card.add_child(margin)

	var stack := VBoxContainer.new()
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_theme_constant_override("separation", 5)
	margin.add_child(stack)

	var name_label := Label.new()
	name_label.text = display_name.to_upper()
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.clip_text = true
	name_label.custom_minimum_size = Vector2(0, 30)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_label.add_theme_font_size_override("font_size", 10)
	name_label.add_theme_color_override("font_color", Color(1.0, 0.76, 0.28, 1.0))
	stack.add_child(name_label)

	var mini_preview := ShipBuilderPreview.new()
	mini_preview.custom_minimum_size = Vector2(128, 76)
	mini_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var preview_size := Vector2i(6, 6)
	if layout != null:
		preview_size = Vector2i(int(layout.get("columns")), int(layout.get("rows")))
	mini_preview.set_layout(layout, preview_size)
	stack.add_child(mini_preview)

	var meta_label := Label.new()
	meta_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	meta_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	meta_label.add_theme_font_size_override("font_size", 8)
	meta_label.add_theme_color_override("font_color", Color(0.46, 0.78, 0.74, 0.95))
	if layout != null:
		var full_frame := _full_grid_size(Vector2i(int(layout.get("columns")), int(layout.get("rows"))))
		meta_label.text = "%dx%d FULL-ROOM FRAME" % [full_frame.x, full_frame.y]
	else:
		meta_label.text = "UNREADABLE"
	stack.add_child(meta_label)

	var click_target := Button.new()
	click_target.flat = true
	click_target.text = ""
	click_target.tooltip_text = card.tooltip_text
	click_target.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	click_target.mouse_entered.connect(_set_blueprint_card_hovered.bind(card, true))
	click_target.mouse_exited.connect(_set_blueprint_card_hovered.bind(card, false))
	click_target.pressed.connect(_select_blueprint_card.bind(path, layout))
	card.add_child(click_target)
	_update_blueprint_card_style(card)


func _save_active_design() -> void:
	if source_layout == null:
		status_label.text = "NO ACTIVE SHIP LAYOUT TO SAVE"
		return
	_ensure_blueprint_directory()
	var design_name := design_name_field.text.strip_edges()
	if design_name.is_empty():
		design_name = _layout_display_name(source_layout)
	if design_name.is_empty():
		design_name = "Unnamed Hull"
	source_layout.set("design_name", design_name)
	var save_path := "%s/%s.tres" % [BLUEPRINT_DIRECTORY, _safe_file_stem(design_name)]
	var layout_copy := source_layout.duplicate(true)
	layout_copy.resource_path = ""
	layout_copy.set("design_name", design_name)
	var error := ResourceSaver.save(layout_copy, save_path)
	if error != OK:
		status_label.text = "Save failed. Error code %d" % error
		_announce_shipyard("SAVE FAILED   ERROR %d" % error, true)
		return
	status_label.text = "Blueprint saved to %s" % save_path
	_set_builder_status("Blueprint saved. Active design remains open in the drydock.")
	_announce_shipyard("BLUEPRINT SAVED   %s" % design_name.to_upper())
	_play_menu_sound(execute_sound_method)
	_refresh_blueprint_archive()
	_select_blueprint_path(save_path)
	_refresh_display()


func _select_blueprint_card(path: String, layout: Resource) -> void:
	selected_blueprint_path = path
	selected_blueprint_layout = layout
	if selected_blueprint_layout == null and not path.is_empty():
		selected_blueprint_layout = ResourceLoader.load(path)
	for card: PanelContainer in blueprint_cards:
		_update_blueprint_card_style(card)
	if selected_blueprint_layout != null:
		selected_size = Vector2i(int(selected_blueprint_layout.get("columns")), int(selected_blueprint_layout.get("rows")))
		status_label.text = "Blueprint selected: %s" % _layout_display_name(selected_blueprint_layout)
		_announce_shipyard("BLUEPRINT CARD LOCKED   %s" % _layout_display_name(selected_blueprint_layout).to_upper())
	else:
		status_label.text = "Blueprint selected."
		_announce_shipyard("BLUEPRINT CARD LOCKED")
	_update_blueprint_selection_readout()
	_close_blueprint_catalog(false)
	_play_menu_sound(open_sound_method)
	_pulse_control(preview, Color(0.8, 1.28, 1.18, 1.0), 1.025)
	_refresh_display()


func _new_ship_design() -> void:
	var base_layout := source_layout
	if base_layout == null:
		var ship := get_tree().get_first_node_in_group("ship_simulation")
		if is_instance_valid(ship):
			base_layout = ship.get("ship_layout")
	if base_layout == null:
		status_label.text = "New ship blocked. No shipyard template is available."
		_announce_shipyard("NEW HULL BLOCKED   TEMPLATE MISSING", true)
		return
	var new_layout: Resource = base_layout.duplicate(true)
	new_layout.resource_path = ""
	var design_name := new_design_name_field.text.strip_edges() if new_design_name_field != null else ""
	if design_name.is_empty() or design_name == _layout_display_name(base_layout):
		design_name = "%s %d" % ["New Station" if selected_new_vessel_kind == "STATION" else "New Hull", Time.get_ticks_msec()]
	var empty_rooms: Array[Resource] = []
	var empty_offset_cells: Array[Vector2i] = []
	var empty_vertical_offset_cells: Array[Vector2i] = []
	new_layout.set("design_name", design_name)
	new_layout.set("vessel_kind", selected_new_vessel_kind)
	new_layout.set("rooms", empty_rooms)
	new_layout.set("offset_cells", empty_offset_cells)
	new_layout.set("vertical_offset_cells", empty_vertical_offset_cells)
	new_layout.set("build_origin", Vector2i.ZERO)
	new_layout.set("columns", maxi(selected_size.x, 1))
	new_layout.set("rows", maxi(selected_size.y, 1))
	source_layout = new_layout
	_invalidate_builder_resource_stats()
	if design_name_field != null:
		design_name_field.text = design_name
	if new_design_name_field != null:
		new_design_name_field.text = design_name
	_apply_layout_to_active_ship(source_layout)
	var full_size := _full_grid_size(selected_size)
	status_label.text = "New active hull created. Empty %dx%d full-room construction envelope." % [full_size.x, full_size.y]
	_announce_shipyard("NEW HULL ONLINE   %s" % design_name.to_upper())
	_play_menu_sound(execute_sound_method)
	_populate_size_selector()
	_refresh_display()
	_show_shipyard_context("edit")


func _load_selected_design() -> void:
	if not _load_selected_blueprint_as_active():
		return
	status_label.text = "Blueprint ready for editing: %s" % _layout_display_name(source_layout).to_upper()
	_announce_shipyard("BLUEPRINT LOADED FOR EDIT   %s" % _layout_display_name(source_layout).to_upper())
	_show_shipyard_context("edit")


func _play_selected_design() -> void:
	if not _load_selected_blueprint_as_active():
		return
	status_label.text = "Player ship switched to %s." % _layout_display_name(source_layout).to_upper()
	_announce_shipyard("PLAYER VESSEL SWITCHED   %s" % _layout_display_name(source_layout).to_upper())
	close()


func _delete_selected_design() -> void:
	var path := _selected_blueprint_path()
	if path.is_empty():
		status_label.text = "No blueprint selected for deletion."
		_announce_shipyard("DELETE BLOCKED   NO BLUEPRINT SELECTED", true)
		return
	var display_name := _layout_display_name(selected_blueprint_layout) if selected_blueprint_layout != null else path.get_file().get_basename().capitalize()
	var absolute_path := ProjectSettings.globalize_path(path)
	var error := DirAccess.remove_absolute(absolute_path)
	if error != OK:
		status_label.text = "Delete failed. Error code %d" % error
		_announce_shipyard("DELETE FAILED   ERROR %d" % error, true)
		return
	_play_menu_sound(execute_sound_method)
	status_label.text = "Blueprint deleted: %s" % display_name
	_announce_shipyard("BLUEPRINT DELETED   %s" % display_name.to_upper())
	selected_blueprint_path = ""
	selected_blueprint_layout = null
	_refresh_blueprint_archive()
	_refresh_display()


func _selected_blueprint_path() -> String:
	return selected_blueprint_path


func _load_selected_blueprint_as_active() -> bool:
	var path := _selected_blueprint_path()
	if path.is_empty():
		status_label.text = "No blueprint selected."
		_announce_shipyard("LOAD BLOCKED   NO BLUEPRINT SELECTED", true)
		return false
	var loaded := selected_blueprint_layout
	if loaded == null:
		loaded = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE)
	if loaded == null:
		status_label.text = "Load failed. Blueprint file was not found."
		_announce_shipyard("LOAD FAILED   BLUEPRINT NOT FOUND", true)
		return false
	source_layout = loaded
	_invalidate_builder_resource_stats()
	if design_name_field != null:
		design_name_field.text = _layout_display_name(source_layout)
	selected_size = Vector2i(int(source_layout.get("columns")), int(source_layout.get("rows")))
	_apply_layout_to_active_ship(source_layout)
	_play_menu_sound(execute_sound_method)
	_announce_shipyard("ACTIVE HULL CONNECTED   %s" % _layout_display_name(source_layout).to_upper())
	_populate_size_selector()
	_refresh_display()
	return true


func _apply_layout_to_active_ship(layout: Resource) -> void:
	if layout == null:
		return
	var ship := get_tree().get_first_node_in_group("ship_simulation")
	if is_instance_valid(ship):
		ship.set("ship_layout", layout)
		ship.call("refresh_rooms_from_layout")
	var main_scene := get_tree().current_scene
	if is_instance_valid(main_scene) and main_scene.has_method("refresh_active_layout_views"):
		main_scene.call("refresh_active_layout_views")


func _apply_selected_envelope() -> void:
	if source_layout == null:
		status_label.text = "NO ACTIVE SHIP LAYOUT"
		return
	var current_origin: Vector2i = source_layout.get("build_origin")
	var current_size := Vector2i(int(source_layout.get("columns")), int(source_layout.get("rows")))
	var delta := selected_size - current_size
	var proposed_origin := current_origin - Vector2i(floori(float(delta.x) * 0.5), floori(float(delta.y) * 0.5))
	if not bool(source_layout.call("set_build_envelope", proposed_origin, selected_size)):
		status_label.text = "Envelope rejected. Existing hull cells would be cut off."
		_announce_shipyard("ENVELOPE REJECTED   HULL WOULD BE CUT", true)
		return
	_apply_layout_to_active_ship(source_layout)
	var full_size := _full_grid_size(selected_size)
	status_label.text = "ACTIVE SHIP ENVELOPE SET TO %dx%d FULL ROOMS" % [full_size.x, full_size.y]
	_announce_shipyard("BUILD ENVELOPE UPDATED   %dx%d FULL ROOMS" % [full_size.x, full_size.y])
	_play_menu_sound(execute_sound_method)
	_refresh_display()


func _request_grid_editor() -> void:
	if not _validate_required_ship_systems():
		return
	_capture_current_core_frame()
	_play_menu_sound(execute_sound_method)
	grid_editor_requested.emit()


func _request_close() -> void:
	if current_context == "edit" and not _validate_required_ship_systems():
		return
	if current_context == "edit":
		_capture_current_core_frame()
	close()


func _return_to_shipyard_command() -> void:
	if not _validate_required_ship_systems():
		return
	_capture_current_core_frame()
	_show_shipyard_context("")


func _validate_required_ship_systems() -> bool:
	if source_layout == null or String(source_layout.get("vessel_kind")) == "STATION":
		return true
	var installed_types: Dictionary = {}
	for room: Resource in source_layout.get("rooms"):
		var rects: Array[Rect2i] = room.get("grid_rects")
		if not rects.is_empty():
			installed_types[String(room.get("type_name")).to_upper()] = true
	var missing: PackedStringArray = []
	for requirement: Dictionary in REQUIRED_SHIP_SYSTEMS:
		var found := false
		for type_name: String in requirement["types"]:
			if installed_types.has(type_name):
				found = true
				break
		if not found:
			missing.append(String(requirement["label"]))
	if missing.is_empty():
		return true
	_set_builder_status("LAUNCH INTERLOCK • REQUIRED SYSTEMS MISSING: %s" % ", ".join(missing))
	_play_menu_sound(denied_sound_method)
	_pulse_builder_console()
	return false


func _capture_current_core_frame() -> void:
	# The paused Forge can recommission a redesigned keel. Live station refits
	# must not turn every newly attached cargo piece into permanent core framing.
	if inventory_mode != "STATION" and source_layout != null and source_layout.has_method("capture_core_frame"):
		source_layout.call("capture_core_frame", true)


func _ensure_builder_grid() -> void:
	if source_layout == null:
		return
	if builder_grid == null:
		builder_grid = SettlementGridScript.new() as Control
		builder_grid.custom_minimum_size = Vector2(430, 430)
		builder_grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		builder_grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
		builder_grid.set("ship_layout", source_layout)
		builder_grid.set("planned_staffing_display", true)
		builder_grid.call("set_editor_mode", true)
		builder_grid.call("set_free_blueprint_placement", inventory_mode == "FORGE")
		if builder_grid.has_method("set_core_frame_edit_locked"):
			builder_grid.call("set_core_frame_edit_locked", _uses_owned_inventory())
		if builder_grid.has_signal("editor_cell_activated"):
			builder_grid.connect("editor_cell_activated", _on_builder_grid_cell_activated)
		if builder_grid.has_signal("editor_cells_dragged"):
			builder_grid.connect("editor_cells_dragged", _on_builder_grid_cells_dragged)
		if builder_grid.has_signal("empty_space_selected"):
			builder_grid.connect("empty_space_selected", _on_builder_grid_empty_space_selected)
		if builder_grid.has_signal("forge_inventory_piece_dropped"):
			builder_grid.connect("forge_inventory_piece_dropped", _on_forge_inventory_piece_dropped)
		if builder_grid.has_signal("forge_inventory_piece_rejected"):
			builder_grid.connect("forge_inventory_piece_rejected", _on_forge_inventory_piece_rejected)
		if builder_grid.has_signal("installed_piece_relocated"):
			builder_grid.connect("installed_piece_relocated", _on_installed_piece_relocated)
		preview.get_parent().add_child(builder_grid)
		preview.get_parent().move_child(builder_grid, preview.get_index())
		_dock_shipyard_child(builder_grid, 0.5, 0.0, 0.5, 1.0, -215.0, 0.0, 215.0, 0.0)
	else:
		builder_grid.set("ship_layout", source_layout)
		builder_grid.call("set_editor_mode", true)
		builder_grid.call("set_free_blueprint_placement", inventory_mode == "FORGE")
		if builder_grid.has_method("set_core_frame_edit_locked"):
			builder_grid.call("set_core_frame_edit_locked", _uses_owned_inventory())
		if embedded_refit_mode:
			builder_grid.call("set_editor_mode", not embedded_refit_locked)
			builder_grid.call("refresh_layout")
			return
		_dock_shipyard_child(builder_grid, 0.5, 0.0, 0.5, 1.0, -215.0, 0.0, 215.0, 0.0)
		builder_grid.call("refresh_layout")
	if _uses_owned_inventory():
		_dock_shipyard_child(builder_grid, 0.0, 0.0, 1.0, 1.0, 340.0, 0.0, -8.0, 0.0)


func _show_builder_grid(is_builder_visible: bool) -> void:
	# The grid is refreshed explicitly when the layout changes. Ordinary dossier
	# and status updates must not rebuild it again while it is already visible.
	if is_builder_visible and (builder_grid == null or not builder_grid.visible):
		_ensure_builder_grid()
	if builder_grid != null:
		var was_visible := builder_grid.visible
		builder_grid.visible = is_builder_visible
		if is_builder_visible and not was_visible:
			builder_grid.call_deferred("fit_editor_view")
	if builder_view_actions != null:
		builder_view_actions.visible = is_builder_visible and not _uses_owned_inventory()
	if preview != null:
		preview.visible = not is_builder_visible


func _adjust_builder_zoom(factor: float) -> void:
	if builder_grid == null:
		return
	builder_grid.call("adjust_editor_zoom", factor)
	_set_builder_status("Drydock camera zoom adjusted.")
	_play_menu_sound(open_sound_method)


func _fit_builder_view() -> void:
	if builder_grid == null:
		return
	builder_grid.call("fit_editor_view")
	_set_builder_status("Drydock camera centered on authorized build frame.")
	_play_menu_sound(open_sound_method)


func _set_builder_tool(tool_name: String) -> void:
	builder_tool = tool_name
	if builder_tool_row != null:
		builder_tool_row.visible = false
	if builder_grid != null:
		builder_grid.call("set_editor_selection_mode", tool_name == "group")
	if tool_name != "group":
		_clear_builder_group_selection()
		builder_last_selected_cell = INVALID_CELL
		builder_specific_mount_selected = false
	if builder_type_buttons != null:
		builder_type_buttons.visible = false
	if builder_group_actions != null:
		builder_group_actions.visible = false
	if builder_facing_actions != null:
		builder_facing_actions.visible = false
	if builder_delete_actions != null:
		builder_delete_actions.visible = false
	if builder_add_header != null:
		builder_add_header.visible = false
	if builder_group_header != null:
		builder_group_header.visible = false
	match tool_name:
		"add":
			_set_builder_status("Install channel open. Choose a cell type before placing hull systems.")
		"delete":
			_set_builder_status("Clearance channel open. Confirm removal or cancel.")
		"group":
			_set_builder_status("Compartment channel online. Direction, grouping, and clearance controls appear when valid.")
		_:
			_set_builder_status("Drydock standby. Click an empty cell to install, an occupied cell to inspect, or drag occupied cells to group.")
	_refresh_builder_context_controls()


func _set_builder_room_type(room_type: String) -> void:
	builder_room_type = room_type
	_populate_builder_type_buttons()
	if builder_pending_add_cell != INVALID_CELL:
		var installed_cell := builder_pending_add_cell
		var installed_type := room_type
		if _builder_add_cell(builder_pending_add_cell):
			builder_pending_add_cell = INVALID_CELL
			builder_pending_add_offset = Vector2.ZERO
			if builder_grid != null:
				builder_grid.call("set_editor_focus_cell", INVALID_CELL, Vector2.ZERO)
			builder_room_type = ""
			_populate_builder_type_buttons()
			_set_builder_tool("")
			_set_builder_status("%s installed at cell %s." % [_room_type_palette_name(installed_type), installed_cell])
			_pulse_builder_grid()
	else:
		_set_builder_tool("add")
		_set_builder_status("%s selected. Click an open drydock cell to install it." % _room_type_palette_name(room_type))
		_play_menu_sound(open_sound_method)
		_pulse_builder_console()


func _on_builder_grid_cell_activated(cell: Vector2i, button_index: int) -> void:
	if source_layout == null:
		return
	inspected_inventory_piece_id = 0
	inspected_inventory_room_type = ""
	builder_last_selected_cell = cell
	builder_specific_mount_selected = (
		button_index == MOUSE_BUTTON_LEFT
		and builder_grid != null
		and bool(builder_grid.call("was_last_editor_click_on_hardware"))
	)
	var room := _builder_room_at_cell(cell)
	if button_index == MOUSE_BUTTON_RIGHT:
		if room == null:
			_set_builder_status("No hull cell at %s to clear." % cell)
			return
		_open_builder_delete_context(cell, room)
		return
	if room == null:
		if builder_grid != null:
			builder_grid.call("clear_room_selection")
		if (
			_uses_owned_inventory()
			and not builder_room_type.is_empty()
			and _inventory_piece_by_id(forge_armed_piece_id, builder_room_type) != null
		):
			builder_pending_add_cell = cell
			builder_pending_add_offset = builder_grid.call("get_pending_placement_offset") if builder_grid != null else Vector2.ZERO
			if _builder_add_cell(cell):
				builder_pending_add_cell = INVALID_CELL
				builder_pending_add_offset = Vector2.ZERO
				builder_room_type = ""
				if builder_grid != null:
					builder_grid.call("set_inventory_piece_armed", false)
					builder_grid.call("set_editor_focus_cell", INVALID_CELL, Vector2.ZERO)
				_set_builder_tool("")
				_set_builder_status("GRID LOCKED • INSTALLATION COMPLETE")
				_pulse_builder_grid()
			return
		_open_builder_add_context(cell)
	else:
		_open_builder_room_context(cell, room)


func _on_builder_grid_empty_space_selected() -> void:
	inspected_inventory_piece_id = 0
	inspected_inventory_room_type = ""
	builder_last_selected_cell = INVALID_CELL
	builder_specific_mount_selected = false
	builder_pending_add_cell = INVALID_CELL
	builder_pending_add_offset = Vector2.ZERO
	builder_pending_delete_cell = INVALID_CELL
	builder_group_selection.clear()
	if builder_grid != null:
		builder_grid.call("clear_room_selection")
		builder_grid.call("set_group_selection", builder_group_selection)
		builder_grid.call("set_editor_focus_cell", INVALID_CELL, Vector2.ZERO)
	_set_builder_tool("")
	_set_builder_status("Fire-control focus released. Select a hull grid to inspect it.")
	_refresh_display()


func _on_forge_inventory_piece_dropped(room_type: String, cell: Vector2i, source_instance_id: int) -> void:
	if embedded_refit_mode and embedded_refit_locked:
		_set_builder_status("REFIT INTERLOCK • HOSTILE FIRE DETECTED")
		_return_inventory_drag(source_instance_id)
		return
	if source_layout == null:
		_return_inventory_drag(source_instance_id)
		return
	if _builder_room_at_cell(cell) != null:
		_set_builder_status("INSTALLATION DENIED • TARGET CELL OCCUPIED")
		_play_menu_sound(denied_sound_method)
		_pulse_builder_console()
		_return_inventory_drag(source_instance_id)
		return
	builder_room_type = room_type
	forge_armed_piece_id = source_instance_id
	inspected_inventory_piece_id = 0
	inspected_inventory_room_type = ""
	var dragged_piece := _inventory_piece_by_id(source_instance_id, room_type)
	if dragged_piece != null:
		builder_inventory_key = String(dragged_piece.get("inventory_key"))
		builder_module_recipe = dragged_piece.get("module_recipe") as Resource
	builder_pending_add_cell = cell
	builder_pending_add_offset = builder_grid.call("get_pending_placement_offset") if builder_grid != null else Vector2.ZERO
	if _builder_add_cell(cell):
		# Keep readiness warnings produced by the placement transaction visible;
		# replacing them with the generic transfer receipt hides why a newly
		# installed grid is dark.
		if builder_status_label == null or not builder_status_label.text.begins_with("PLACED WITH WARNINGS"):
			_set_builder_status("%s transferred from inventory and installed at %s." % [_room_type_palette_name(room_type), cell])
		builder_room_type = ""
		builder_inventory_key = ""
		builder_module_recipe = null
		if builder_grid != null:
			builder_grid.call("set_inventory_piece_armed", false)
		_pulse_builder_grid()
		if not _uses_owned_inventory() and forge_inventory_grid != null:
			forge_inventory_grid.call("restore_catalog_piece", source_instance_id)
	else:
		_return_inventory_drag(source_instance_id)


func _on_forge_inventory_piece_rejected(reason: String, source_instance_id: int) -> void:
	_set_builder_status("INSTALLATION DENIED • %s" % reason)
	_play_menu_sound(denied_sound_method)
	_pulse_builder_console()
	_return_inventory_drag(source_instance_id)


func _on_installed_piece_relocated(
	room_type: String,
	room_id: StringName,
	source_cell: Vector2i,
	target_cell: Vector2i
) -> void:
	if embedded_refit_mode and embedded_refit_locked:
		_set_builder_status("REFIT INTERLOCK • HOSTILE FIRE DETECTED")
		return
	if source_layout == null or target_cell == INVALID_CELL:
		return
	var source_room := _builder_room_by_id(room_id)
	if source_room == null:
		source_room = _builder_room_at_cell(source_cell)
	if source_room == null:
		_set_builder_status("RELOCATION ABORTED • GRID LINK LOST")
		return
	var source_offset: Vector2 = source_layout.call("get_cell_offset", source_cell)
	var target_offset: Vector2 = builder_grid.call("get_pending_placement_offset") if builder_grid != null else Vector2.ZERO
	if source_cell == target_cell and source_offset == target_offset:
		_set_builder_status("GRID REMAINS LOCKED AT %s" % source_cell)
		return

	# Keep relocation atomic. A rejected destination restores the combined room
	# exactly as it was before the player picked up this physical piece.
	var room_snapshot: Array[Resource] = []
	for room_value: Variant in source_layout.get("rooms"):
		room_snapshot.append((room_value as Resource).duplicate(true))
	var horizontal_offsets: Array[Vector2i] = source_layout.get("offset_cells").duplicate()
	var vertical_offsets: Array[Vector2i] = source_layout.get("vertical_offset_cells").duplicate()
	var moving_piece := _builder_extract_piece_at_cell(source_room, source_cell)
	if moving_piece == source_room:
		var source_definitions: Array = source_layout.get("rooms")
		source_definitions.erase(source_room)
		source_layout.set("rooms", source_definitions)
	var moving_rects: Array[Rect2i] = moving_piece.get("grid_rects")
	var footprint := moving_rects[0].size if not moving_rects.is_empty() else Vector2i.ONE
	var denial := ""
	var readiness_warning := ""
	var facing_changed := false
	if not bool(source_layout.call("is_cell_buildable", target_cell)):
		denial = "DESTINATION OUTSIDE HULL WORK ENVELOPE"
	elif not bool(source_layout.call("can_place_footprint", target_cell, footprint, target_offset)):
		denial = "DESTINATION OVERLAPS EXISTING HULL"
	else:
		var relocated_rects: Array[Rect2i] = [Rect2i(target_cell, footprint)]
		moving_piece.set("grid_rects", relocated_rects)
		# Facing-clearance queries read offsets from the layout. Keep this
		# provisional edit silent: emitting `changed` while the piece is detached
		# lets live refit observers rebuild from the half-finished transaction.
		_set_layout_cell_offset_silent(target_cell, target_offset)
		if inventory_mode != "FORGE" and not _relocated_piece_touches_existing_hull(target_cell, footprint, target_offset):
			denial = "GRID MUST SHARE A HULL EDGE"
		elif EXPLICIT_GROUP_ROOM_TYPES.has(room_type) and source_layout.has_method("evaluate_room_facing_clearance"):
			var saved_facing := posmod(int(moving_piece.get("module_facing_quarters")), 4)
			var resolved_facing := -1
			# Preserve the authored vector when possible. If the module has crossed
			# the hull, rotate it to the nearest legal exterior face instead of
			# silently snapping the entire grid back to its old position.
			for facing_step: int in range(4):
				var candidate_facing := posmod(saved_facing + facing_step, 4)
				var facing_clearance: Dictionary = source_layout.call(
					"evaluate_room_facing_clearance",
					moving_piece,
					candidate_facing
				)
				if bool(facing_clearance.get("valid", true)):
					resolved_facing = candidate_facing
					break
			if resolved_facing < 0:
				denial = "NO EXPOSED FIRING OR EXHAUST LANE"
			else:
				facing_changed = resolved_facing != saved_facing
				moving_piece.set("module_facing_quarters", resolved_facing)
				moving_piece.set("module_mount_facings", [resolved_facing])
		if denial.is_empty():
			var power_status := ShipBuilderAnalyzer.evaluate_power_placement(
				source_layout,
				room_type,
				target_cell,
				footprint,
				moving_piece
			)
			if not bool(power_status.get("valid", true)):
				# Power is an operating state, not a structural mounting rule. A
				# grid may be installed dark and brought online later by moving or
				# adding a reactor. Hull attachment and exterior clearance remain
				# hard interlocks above.
				readiness_warning = String(power_status.get("message", "LOCAL POWER LINK UNAVAILABLE"))
	if not denial.is_empty():
		_restore_relocation_snapshot(room_snapshot, horizontal_offsets, vertical_offsets)
		_set_builder_status("RELOCATION DENIED • %s" % denial)
		_play_menu_sound(denied_sound_method)
		_pulse_builder_console()
		return

	var target_definitions: Array = source_layout.get("rooms")
	target_definitions.append(moving_piece)
	source_layout.set("rooms", target_definitions)
	if _requires_connected_live_hull() and not _builder_hull_is_connected():
		_restore_relocation_snapshot(room_snapshot, horizontal_offsets, vertical_offsets)
		_set_builder_status("RELOCATION DENIED • MOVE WOULD SEVER THE HULL")
		_play_menu_sound(denied_sound_method)
		_pulse_builder_console()
		return
	# Keep the resource mutation silent here as well. The explicit refresh below
	# updates every live consumer after the whole transaction is committed;
	# Resource.changed observers can otherwise re-enter the embedded workbench
	# before its controller has finished updating its selection state.
	_set_layout_cell_offset_silent(target_cell, target_offset)
	source_layout.call("prune_unused_cell_offsets")
	var relocated_room := moving_piece
	builder_last_selected_cell = target_cell
	builder_specific_mount_selected = false
	builder_group_selection.clear()
	for room_cell: Variant in _builder_room_cells(relocated_room).keys():
		builder_group_selection[room_cell] = true
	if builder_grid != null:
		builder_grid.call("select_room", relocated_room.get("room_id"), INVALID_CELL)
		builder_grid.call("set_group_selection", builder_group_selection)
	_set_builder_tool("group")
	if not readiness_warning.is_empty():
		_set_builder_status("%s RELOCATED • INSTALLED OFFLINE • %s" % [
			_room_type_palette_name(room_type).to_upper(),
			readiness_warning,
		])
	else:
		_set_builder_status(
			"%s RELOCATED • AUTO-VECTOR LOCKED" % _room_type_palette_name(room_type).to_upper()
			if facing_changed
			else "%s RELOCATED • HULL LINK SECURED" % _room_type_palette_name(room_type).to_upper()
		)
	_refresh_builder_after_edit()
	_play_menu_sound(install_sound_method)
	_pulse_builder_grid()


func _set_layout_cell_offset_silent(cell: Vector2i, offset: Vector2) -> void:
	var horizontal_offsets: Array[Vector2i] = source_layout.get("offset_cells")
	var vertical_offsets: Array[Vector2i] = source_layout.get("vertical_offset_cells")
	horizontal_offsets.erase(cell)
	vertical_offsets.erase(cell)
	if offset.x >= 0.25:
		horizontal_offsets.append(cell)
	if offset.y >= 0.25:
		vertical_offsets.append(cell)
	source_layout.set("offset_cells", horizontal_offsets)
	source_layout.set("vertical_offset_cells", vertical_offsets)


func _relocated_piece_touches_existing_hull(
	target_cell: Vector2i,
	footprint: Vector2i,
	target_offset: Vector2
) -> bool:
	var candidate := Rect2(Vector2(target_cell) + target_offset, Vector2(footprint))
	for room_value: Variant in source_layout.get("rooms"):
		var room := room_value as Resource
		for cell_value: Variant in _builder_room_cells(room).keys():
			var cell: Vector2i = cell_value
			var existing := Rect2(Vector2(cell) + Vector2(source_layout.call("get_cell_offset", cell)), Vector2.ONE)
			var vertical_touch := (
				is_equal_approx(candidate.end.x, existing.position.x)
				or is_equal_approx(existing.end.x, candidate.position.x)
			) and minf(candidate.end.y, existing.end.y) - maxf(candidate.position.y, existing.position.y) > 0.001
			var horizontal_touch := (
				is_equal_approx(candidate.end.y, existing.position.y)
				or is_equal_approx(existing.end.y, candidate.position.y)
			) and minf(candidate.end.x, existing.end.x) - maxf(candidate.position.x, existing.position.x) > 0.001
			if vertical_touch or horizontal_touch:
				return true
	return false


func _restore_relocation_snapshot(
	rooms: Array[Resource],
	horizontal_offsets: Array[Vector2i],
	vertical_offsets: Array[Vector2i]
) -> void:
	source_layout.set("rooms", rooms)
	source_layout.set("offset_cells", horizontal_offsets)
	source_layout.set("vertical_offset_cells", vertical_offsets)
	_refresh_builder_after_edit()


func _return_inventory_drag(source_instance_id: int) -> void:
	if forge_inventory_grid != null:
		forge_inventory_grid.call("return_piece", source_instance_id, get_viewport().get_mouse_position())
	forge_armed_piece_id = 0
	builder_room_type = ""
	builder_inventory_key = ""
	builder_module_recipe = null
	if builder_grid != null:
		builder_grid.call("set_inventory_piece_armed", false)


func _on_builder_grid_cells_dragged(cells: Array[Vector2i]) -> void:
	builder_pending_add_cell = INVALID_CELL
	builder_pending_add_offset = Vector2.ZERO
	builder_pending_delete_cell = INVALID_CELL
	builder_last_selected_cell = INVALID_CELL
	builder_specific_mount_selected = false
	builder_group_selection.clear()
	if builder_grid != null:
		builder_grid.call("clear_room_selection")
		builder_grid.call("set_editor_focus_cell", INVALID_CELL, Vector2.ZERO)
		builder_grid.call("set_inventory_piece_armed", false)
	for cell: Vector2i in cells:
		if _builder_room_at_cell(cell) != null:
			builder_group_selection[cell] = true
	if builder_grid != null:
		builder_grid.call("set_group_selection", builder_group_selection)
	if builder_group_selection.is_empty():
		_set_builder_tool("")
		_set_builder_status("Drag selection found no occupied hull cells.")
		_play_menu_sound(close_sound_method)
		return
	builder_tool = "group"
	_set_builder_tool("group")
	if _builder_selection_can_merge():
		if builder_group_actions != null:
			builder_group_actions.visible = true
		_set_builder_status("Compatible module selection. Merge controls are online.")
	else:
		_set_builder_status(_builder_selection_summary())
	_refresh_builder_context_controls()
	_play_menu_sound(open_sound_method)
	_pulse_builder_grid()


func _open_builder_add_context(cell: Vector2i) -> void:
	builder_pending_add_cell = cell
	builder_pending_add_offset = Vector2.ZERO
	if builder_grid != null:
		builder_pending_add_offset = builder_grid.call("get_pending_placement_offset")
	builder_pending_delete_cell = INVALID_CELL
	builder_room_type = ""
	builder_group_selection.clear()
	if builder_grid != null:
		builder_grid.call("set_group_selection", builder_group_selection)
		builder_grid.call("set_editor_focus_cell", builder_pending_add_cell, builder_pending_add_offset)
	_set_builder_tool("add")
	_populate_builder_type_buttons()
	if _uses_owned_inventory():
		_set_builder_status("Empty drydock cell %s selected. Drag an owned cargo grid here." % cell)
	else:
		_set_builder_status("Empty drydock cell %s selected. Choose a room system to install." % cell)
	_refresh_display()
	_play_menu_sound(open_sound_method)
	_pulse_builder_console()


func _open_builder_room_context(cell: Vector2i, room: Resource) -> void:
	builder_pending_add_cell = INVALID_CELL
	builder_pending_add_offset = Vector2.ZERO
	builder_pending_delete_cell = cell
	builder_group_selection.clear()
	# A module may occupy several quarter-lattice cells, but it remains one
	# physical grid piece. Normal selection always arms its complete footprint.
	for room_cell: Variant in _builder_room_cells(room).keys():
		builder_group_selection[room_cell] = true
	if builder_grid != null:
		# Preserve which physical mount inside a combined room was clicked. The
		# whole room remains selected. Only a click on the hardware itself arms its
		# individual vector controls; a click on the shared room body selects every
		# mount and therefore displays every targeting envelope.
		builder_grid.call("select_room", room.get("room_id"), cell if builder_specific_mount_selected else INVALID_CELL)
		builder_grid.call("set_group_selection", builder_group_selection)
		builder_grid.call("set_editor_focus_cell", INVALID_CELL, Vector2.ZERO)
	_set_builder_tool("group")
	_set_builder_status(_builder_room_summary(room))
	_refresh_builder_context_controls()
	_refresh_display()
	_play_menu_sound(open_sound_method)
	_pulse_builder_grid()


func _open_builder_delete_context(cell: Vector2i, room: Resource) -> void:
	if _builder_cell_is_core(cell):
		_set_builder_status("CORE FRAME LOCKED • PERMANENT KEEL CANNOT BE CLEARED")
		_play_menu_sound(denied_sound_method)
		_pulse_builder_console()
		return
	builder_pending_add_cell = INVALID_CELL
	builder_pending_add_offset = Vector2.ZERO
	builder_pending_delete_cell = cell
	builder_group_selection.clear()
	if builder_grid != null:
		builder_grid.call("select_room", room.get("room_id"))
		builder_grid.call("set_group_selection", builder_group_selection)
		builder_grid.call("set_editor_focus_cell", INVALID_CELL, Vector2.ZERO)
	_set_builder_tool("delete")
	if builder_delete_actions != null:
		builder_delete_actions.visible = true
	_set_builder_status("Clear %s cell %s from this hull?" % [_room_type_palette_name(String(room.get("type_name"))), cell])
	_refresh_display()
	_play_menu_sound(open_sound_method)
	_pulse_builder_console()


func _confirm_builder_delete_cell() -> void:
	if builder_pending_delete_cell == INVALID_CELL:
		_set_builder_status("No cell is queued for clearance.")
		return
	var cell := builder_pending_delete_cell
	builder_pending_delete_cell = INVALID_CELL
	_builder_delete_cell(cell)
	_set_builder_tool("")
	_play_menu_sound(execute_sound_method)
	_pulse_builder_grid()


func _cancel_builder_context() -> void:
	builder_pending_add_cell = INVALID_CELL
	builder_pending_add_offset = Vector2.ZERO
	builder_pending_delete_cell = INVALID_CELL
	builder_room_type = ""
	builder_inventory_key = ""
	builder_module_recipe = null
	inspected_inventory_piece_id = 0
	inspected_inventory_room_type = ""
	_clear_builder_group_selection()
	if builder_grid != null:
		builder_grid.call("set_editor_focus_cell", INVALID_CELL, Vector2.ZERO)
		builder_grid.call("set_inventory_piece_armed", false)
	_populate_builder_type_buttons()
	_set_builder_tool("")
	_refresh_display()
	_play_menu_sound(close_sound_method)
	_pulse_builder_console()


func _refresh_builder_context_controls() -> void:
	# The selected cell identifies the physical mount whose vector controls are
	# shown, even when the click landed on the grid body instead of its tiny
	# hardware glyph. Hardware hits still isolate that mount's targeting envelope;
	# body hits retain the useful all-ranges view for a combined room.
	# Merge/split controls belong only to an explicit multi-piece selection.
	var has_group_selection := (
		builder_tool == "group"
		and builder_group_selection.size() > 1
		and builder_last_selected_cell == INVALID_CELL
	)
	var can_merge := has_group_selection and _builder_selection_can_merge()
	var can_split := has_group_selection and _builder_selection_can_split()
	if builder_group_actions != null:
		builder_group_actions.visible = has_group_selection
	if builder_combine_button != null:
		builder_combine_button.visible = can_merge
		builder_combine_button.disabled = not can_merge
	if builder_split_button != null:
		builder_split_button.visible = can_split
		builder_split_button.disabled = not can_split
	if builder_clear_selection_button != null:
		builder_clear_selection_button.visible = has_group_selection
		builder_clear_selection_button.disabled = not has_group_selection
	var facing_room: Resource = null
	if builder_tool == "group":
		facing_room = _builder_complete_selected_room()
		if facing_room == null and builder_last_selected_cell != INVALID_CELL:
			facing_room = _builder_room_at_cell(builder_last_selected_cell)
	var supports_facing := (
		facing_room != null
		and EXPLICIT_GROUP_ROOM_TYPES.has(String(facing_room.get("type_name")))
	)
	if builder_facing_actions != null:
		builder_facing_actions.visible = builder_tool == "group" and supports_facing
		if supports_facing:
			var facing_subject := _builder_mount_view_at_cell(facing_room, builder_last_selected_cell)
			var available_facings := _builder_available_facings(facing_subject)
			builder_facing_actions.call("set_available_facings", available_facings)
			var current_facing := int(facing_subject.get("module_facing_quarters"))
			if current_facing < 0 or not bool(available_facings[posmod(current_facing, 4)]):
				current_facing = available_facings.find(true)
				if current_facing >= 0:
					_set_room_mount_facing_at_cell(facing_room, builder_last_selected_cell, current_facing)
			builder_facing_actions.call("set_current_facing", current_facing)
	if builder_delete_actions != null:
		builder_delete_actions.visible = builder_pending_delete_cell != INVALID_CELL and builder_tool == "delete"
	if builder_tool == "group" and supports_facing:
		var facing_rects: Array[Rect2i] = facing_room.get("grid_rects")
		var facing_mount_index := _builder_mount_index_at_cell(facing_room, builder_last_selected_cell)
		if facing_rects.size() > 1 and facing_mount_index >= 0:
			_set_builder_status(
				"%s • MOUNT %d OF %d SELECTED"
				% [String(facing_room.get("display_name")).to_upper(), facing_mount_index + 1, facing_rects.size()]
			)
		else:
			_set_builder_status(
				"%s SELECTED" % String(facing_room.get("display_name")).to_upper()
				if _uses_owned_inventory()
				else "%s selected. Direction and grouping controls are online." % _room_type_palette_name(String(facing_room.get("type_name")))
			)


func _on_builder_grid_cell_clicked(cell: Vector2i) -> void:
	if source_layout == null:
		return
	builder_last_selected_cell = cell
	match builder_tool:
		"delete":
			_builder_delete_cell(cell)
		"group":
			_toggle_builder_group_cell(cell)
		"add":
			_builder_add_cell(cell)
		_:
			_set_builder_status("Choose Add, Delete, or Module before touching the drydock grid.")


func _builder_add_cell(cell: Vector2i) -> bool:
	if builder_room_type.is_empty():
		_set_builder_status("Choose a cell type before installing a hull section.")
		_play_menu_sound(denied_sound_method)
		return false
	if _uses_owned_inventory() and _inventory_piece_by_id(forge_armed_piece_id, builder_room_type) == null:
		_set_builder_status("INSTALLATION DENIED • THAT GRID IS NOT IN CARGO")
		_play_menu_sound(denied_sound_method)
		return false
	if not bool(source_layout.call("is_cell_buildable", cell)):
		_set_builder_status("Cell is outside the authorized drydock frame.")
		_play_menu_sound(denied_sound_method)
		return false
	var proposed_offset := Vector2.ZERO
	var piece_footprint := _armed_inventory_footprint()
	var placement_warnings := PackedStringArray()
	if cell == builder_pending_add_cell:
		proposed_offset = builder_pending_add_offset
	elif builder_grid != null:
		proposed_offset = builder_grid.call("get_pending_placement_offset")
	var placement_facing := -1
	if source_layout.has_method("evaluate_cell_exterior_clearance"):
		var clearance: Dictionary = source_layout.call("evaluate_cell_exterior_clearance", builder_room_type, cell, proposed_offset, piece_footprint)
		if not bool(clearance["valid"]):
			_set_builder_status(String(clearance["message"]))
			_play_menu_sound(denied_sound_method)
			_pulse_builder_console()
			return false
		placement_facing = int(clearance.get("facing", -1))
	var requirement_status := _builder_grid_type_requirement_status(builder_room_type, cell)
	if not bool(requirement_status["valid"]):
		if inventory_mode == "FORGE":
			placement_warnings.append_array(requirement_status["details"])
		else:
			_set_builder_status("%s locked. %s" % [_room_type_palette_name(builder_room_type), " ".join(requirement_status["details"])])
			_play_menu_sound(denied_sound_method)
			_populate_builder_type_buttons()
			return false
	var was_occupied := _builder_room_at_cell(cell) != null
	var power_status := _builder_power_placement_status(builder_room_type, cell, piece_footprint)
	if not bool(power_status["valid"]):
		var denial_message := String(power_status["message"])
		# Unpowered hardware is legal construction. It remains visibly dark and
		# non-operational until a reactor field reaches it, allowing players to
		# assemble in any order and add exterior systems before power expansion.
		placement_warnings.append("INSTALLED OFFLINE • %s" % denial_message)
	var existing_offset: Vector2 = source_layout.call("get_cell_offset", cell)
	var placement_offset := Vector2.ZERO
	if cell == builder_pending_add_cell:
		placement_offset = builder_pending_add_offset
	if builder_grid != null:
		if cell != builder_pending_add_cell:
			placement_offset = builder_grid.call("get_pending_placement_offset")
	_builder_remove_cell_from_all_rooms(cell)
	if was_occupied:
		placement_offset = existing_offset
	if not was_occupied and not bool(source_layout.call("can_place_footprint", cell, piece_footprint, placement_offset)):
		_set_builder_status("Placement blocked. That cell overlaps existing hull.")
		_play_menu_sound(denied_sound_method)
		_refresh_builder_after_edit()
		return false
	source_layout.call("set_cell_offset", cell, placement_offset)
	var room_id := _builder_add_piece_to_room_type(builder_room_type, cell, piece_footprint)
	var installed_room := _builder_room_at_cell(cell)
	if installed_room != null and builder_module_recipe != null:
		_apply_inventory_recipe_to_room(installed_room, builder_module_recipe)
	_configure_unmanned_exterior_module(installed_room)
	if placement_facing >= 0:
		if installed_room != null:
			installed_room.set("module_facing_quarters", placement_facing)
	if installed_room != null:
		installed_room.set("installed_piece_count", 1)
		installed_room.set("module_mount_facings", [int(installed_room.get("module_facing_quarters"))])
		installed_room.set("weapon_fire_modes", [0])
		room_id = installed_room.get("room_id")
	var installed_room_type := builder_room_type
	if _uses_owned_inventory():
		_consume_station_inventory_piece(
			builder_inventory_key if not builder_inventory_key.is_empty() else installed_room_type,
			installed_room_type,
			forge_armed_piece_id
		)
	forge_armed_piece_id = 0
	builder_inventory_key = ""
	builder_module_recipe = null
	var readiness_warnings := _builder_readiness_warnings()
	for warning: String in readiness_warnings:
		if not placement_warnings.has(warning):
			placement_warnings.append(warning)
	if placement_warnings.is_empty():
		_set_builder_status("Cell %s assigned to %s • BLUEPRINT READY" % [cell, _room_type_palette_name(builder_room_type)])
	else:
		_set_builder_status("PLACED WITH WARNINGS • %s" % " • ".join(placement_warnings))
	if builder_grid != null:
		builder_grid.call("select_room", room_id)
	_refresh_builder_after_edit()
	_play_menu_sound(install_sound_method)
	return true


func _armed_inventory_footprint() -> Vector2i:
	var piece := _inventory_piece_by_id(forge_armed_piece_id, builder_room_type)
	if piece != null:
		return Vector2i(piece.get("footprint"))
	return _inventory_piece_footprint(builder_room_type, _builder_room_type_template(builder_room_type), builder_module_recipe)


func _builder_add_piece_to_room_type(room_type: String, cell: Vector2i, footprint: Vector2i) -> StringName:
	var definitions: Array = source_layout.get("rooms")
	var room := _create_builder_room_instance(room_type)
	var footprint_rects: Array[Rect2i] = [Rect2i(cell, footprint)]
	room.set("grid_rects", footprint_rects)
	room.set("build_footprint_lattice", footprint)
	definitions.append(room)
	source_layout.set("rooms", definitions)
	return room.get("room_id")


func _builder_merge_touching_like_rooms(seed_room: Resource) -> Resource:
	# Compatibility entry point for old tools. Matching modules deliberately
	# remain separate so each owns staffing, damage, facing, and cooldown state.
	return seed_room


func _builder_merge_all_touching_like_rooms() -> void:
	# Compatibility alias: old callers now migrate linked compartments in the
	# opposite direction instead of recreating them.
	_builder_separate_all_installed_pieces()


func _builder_separate_all_installed_pieces() -> void:
	if source_layout == null:
		return
	var original_definitions: Array = source_layout.get("rooms")
	var separated_definitions: Array[Resource] = []
	var used_ids: Dictionary = {}
	for room_value: Variant in original_definitions:
		var known_room := room_value as Resource
		if known_room != null:
			used_ids[String(known_room.get("room_id"))] = true
	for room_value: Variant in original_definitions:
		var source_room := room_value as Resource
		if source_room == null:
			continue
		var rects: Array[Rect2i] = source_room.get("grid_rects")
		if rects.is_empty():
			separated_definitions.append(source_room)
			continue
		# Multi-rectangle footprints can be a single deliberately shaped module.
		# The retired auto-linker is the code which raised this count above one,
		# so only those legacy linked compartments should be migrated apart.
		if int(source_room.get("installed_piece_count")) <= 1:
			source_room.set("installed_piece_count", 1)
			separated_definitions.append(source_room)
			continue
		var piece_count := rects.size()
		var facings := _room_piece_facings(source_room, piece_count)
		var fire_modes := _room_piece_fire_modes(source_room, piece_count)
		var total_health := float(source_room.get("maximum_health"))
		var total_minimum := int(source_room.get("minimum_crew"))
		var total_optimal := int(source_room.get("optimal_crew"))
		var recipe: Resource = source_room.get("module_recipe")
		for piece_index: int in range(piece_count):
			var piece_room := source_room if piece_index == 0 else source_room.duplicate(true) as Resource
			var piece_rects: Array[Rect2i] = [rects[piece_index]]
			piece_room.set("grid_rects", piece_rects)
			piece_room.set("build_footprint_lattice", rects[piece_index].size)
			piece_room.set("installed_piece_count", 1)
			piece_room.set("module_facing_quarters", facings[piece_index])
			piece_room.set("module_mount_facings", [facings[piece_index]])
			piece_room.set("weapon_fire_modes", [fire_modes[piece_index]])
			piece_room.set("module_recipe", recipe)
			if recipe != null:
				piece_room.set("maximum_health", float(recipe.get("maximum_health")))
				piece_room.set("minimum_crew", int(recipe.get("minimum_crew")))
				piece_room.set("optimal_crew", int(recipe.get("optimal_crew")))
			else:
				piece_room.set("maximum_health", maxf(total_health / float(piece_count), 1.0))
				piece_room.set("minimum_crew", maxi(roundi(float(total_minimum) / float(piece_count)), 0))
				piece_room.set("optimal_crew", maxi(roundi(float(total_optimal) / float(piece_count)), 0))
			if piece_index > 0:
				piece_room.set("room_id", _next_separate_room_id(source_room, piece_index, used_ids))
			separated_definitions.append(piece_room)
	source_layout.set("rooms", separated_definitions)


func _next_separate_room_id(source_room: Resource, piece_index: int, used_ids: Dictionary) -> StringName:
	var base := String(source_room.get("room_id"))
	if base.is_empty():
		base = String(source_room.get("type_name")).to_snake_case()
	var suffix := piece_index + 1
	var candidate := "%s_%d" % [base, suffix]
	while used_ids.has(candidate):
		suffix += 1
		candidate = "%s_%d" % [base, suffix]
	used_ids[candidate] = true
	return StringName(candidate)


func _rooms_can_auto_combine(_first: Resource, _second: Resource) -> bool:
	# Rooms can touch and share traversable doors without sharing their system
	# identity. No module types auto-combine anymore.
	return false


func _same_module_resource(first: Resource, second: Resource) -> bool:
	if first == second:
		return true
	if first == null or second == null:
		return false
	if not first.resource_path.is_empty() or not second.resource_path.is_empty():
		return first.resource_path == second.resource_path
	# Payload resources are duplicated on installation, so compare their stable
	# authored identity when no resource path survives the duplicate.
	for property_name: String in ["display_name", "weapon_family"]:
		var first_value: Variant = first.get(property_name)
		var second_value: Variant = second.get(property_name)
		if first_value != null or second_value != null:
			return first_value == second_value
	return false


func _builder_rooms_share_wall(first: Resource, second: Resource) -> bool:
	var second_cells := _builder_room_cells(second)
	for cell_value: Variant in _builder_room_cells(first).keys():
		var cell: Vector2i = cell_value
		for direction: Vector2i in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
			if second_cells.has(cell + direction):
				return true
	return false


func _merge_room_piece_data(target: Resource, source: Resource) -> void:
	var target_rects: Array[Rect2i] = target.get("grid_rects")
	var source_rects: Array[Rect2i] = source.get("grid_rects")
	var target_facings := _room_piece_facings(target, target_rects.size())
	var source_facings := _room_piece_facings(source, source_rects.size())
	var target_fire_modes := _room_piece_fire_modes(target, target_rects.size())
	var source_fire_modes := _room_piece_fire_modes(source, source_rects.size())
	for rect: Rect2i in source_rects:
		target_rects.append(rect)
	for facing: int in source_facings:
		target_facings.append(facing)
	for fire_mode: int in source_fire_modes:
		target_fire_modes.append(fire_mode)
	target.set("grid_rects", target_rects)
	target.set("module_mount_facings", target_facings)
	target.set("weapon_fire_modes", target_fire_modes)
	target.set("installed_piece_count", maxi(int(target.get("installed_piece_count")), 1) + maxi(int(source.get("installed_piece_count")), 1))
	target.set("maximum_health", float(target.get("maximum_health")) + float(source.get("maximum_health")))
	# Keep one shared compartment identity, but require the personnel that all of
	# its installed systems would have needed separately.
	target.set("minimum_crew", int(target.get("minimum_crew")) + int(source.get("minimum_crew")))
	target.set("optimal_crew", int(target.get("optimal_crew")) + int(source.get("optimal_crew")))


func _room_piece_facings(room: Resource, piece_count: int) -> Array[int]:
	var facings: Array[int] = []
	var stored: Array = room.get("module_mount_facings")
	for facing_value: Variant in stored:
		facings.append(int(facing_value))
	while facings.size() < piece_count:
		facings.append(int(room.get("module_facing_quarters")))
	if facings.size() > piece_count:
		facings.resize(piece_count)
	return facings


func _room_piece_fire_modes(room: Resource, piece_count: int) -> Array[int]:
	var fire_modes: Array[int] = []
	var stored: Array = room.get("weapon_fire_modes")
	for mode_value: Variant in stored:
		fire_modes.append(clampi(int(mode_value), 0, 2))
	while fire_modes.size() < piece_count:
		fire_modes.append(0)
	if fire_modes.size() > piece_count:
		fire_modes.resize(piece_count)
	return fire_modes


func _consume_forge_inventory_piece(piece: Control) -> void:
	if forge_inventory_grid != null:
		forge_inventory_grid.call("commit_piece_drag", piece.get_instance_id())
	piece.queue_free()


func _inventory_piece_by_id(source_instance_id: int, expected_room_type: String) -> Control:
	if source_instance_id <= 0 or forge_inventory_grid == null:
		return null
	for child: Node in forge_inventory_grid.get_children():
		if child.get_instance_id() != source_instance_id:
			continue
		if not "room_type" in child or String(child.get("room_type")) != expected_room_type:
			return null
		return child as Control
	return null


func _consume_station_inventory_piece(
	inventory_key: String,
	room_type: String,
	source_instance_id: int
) -> void:
	var piece := _inventory_piece_by_id(source_instance_id, room_type)
	if piece == null:
		return
	if is_instance_valid(inventory_owner) and inventory_owner.has_method("consume_grid_piece"):
		var inventory_instance_id := int(piece.get("inventory_instance_id"))
		if not bool(inventory_owner.call("consume_grid_piece", inventory_key, inventory_instance_id)):
			_set_builder_status("CARGO LINK LOST • GRID PIECE IS NO LONGER AVAILABLE")
			return
		owned_grid_inventory = inventory_owner.call("get_grid_piece_inventory")
		if inventory_owner.has_method("get_grid_piece_instances"):
			owned_grid_instances = inventory_owner.call("get_grid_piece_instances")
	else:
		var count := maxi(int(owned_grid_inventory.get(inventory_key, 0)), 0)
		owned_grid_inventory[inventory_key] = maxi(count - 1, 0)
	_consume_forge_inventory_piece(piece)


func _on_inventory_piece_position_changed(inventory_instance_id: int, inventory_position: Vector2i) -> void:
	if not is_instance_valid(inventory_owner) or not inventory_owner.has_method("update_grid_piece_condition"):
		return
	inventory_owner.call("update_grid_piece_condition", inventory_instance_id, {"inventory_position": inventory_position})


func _on_installed_piece_returned(room_type: String, room_id: StringName, cell: Vector2i, cursor_position: Vector2) -> void:
	if forge_inventory_grid == null:
		return
	if embedded_refit_mode and embedded_refit_locked:
		_set_builder_status("REFIT INTERLOCK â€¢ HOSTILE FIRE DETECTED")
		return
	if _builder_cell_is_core(cell):
		_set_builder_status("CORE FRAME LOCKED • PERMANENT KEEL CANNOT ENTER CARGO")
		_play_menu_sound(denied_sound_method)
		_pulse_builder_console()
		return
	var returned_room := _builder_room_by_id(room_id)
	if returned_room == null:
		returned_room = _builder_room_at_cell(cell)
	if returned_room == null:
		return
	var room_snapshot: Array[Resource] = []
	for room_value: Variant in source_layout.get("rooms"):
		room_snapshot.append((room_value as Resource).duplicate(true))
	var horizontal_offsets: Array[Vector2i] = source_layout.get("offset_cells").duplicate()
	var vertical_offsets: Array[Vector2i] = source_layout.get("vertical_offset_cells").duplicate()
	var returned_piece_room := _builder_extract_piece_at_cell(returned_room, cell)
	var returned_recipe: Resource = returned_piece_room.get("module_recipe")
	var inventory_key := (
		_weapon_inventory_key(returned_recipe)
		if returned_recipe != null and int(returned_recipe.get("family")) == ModuleRecipeDefinition.ModuleFamily.WEAPON
		else room_type
	)
	if returned_piece_room == returned_room:
		_builder_remove_room(returned_room)
	else:
		source_layout.call("prune_unused_cell_offsets")
	if _requires_connected_live_hull() and not _builder_hull_is_connected():
		_restore_relocation_snapshot(room_snapshot, horizontal_offsets, vertical_offsets)
		_set_builder_status("REMOVAL DENIED • GRID IS A STRUCTURAL LINK")
		_play_menu_sound(denied_sound_method)
		_pulse_builder_console()
		return
	if _uses_owned_inventory():
		var returned_instance: Dictionary = {}
		if is_instance_valid(inventory_owner) and inventory_owner.has_method("add_grid_piece"):
			var added_ids: Variant = inventory_owner.call("add_grid_piece", inventory_key, 1)
			owned_grid_inventory = inventory_owner.call("get_grid_piece_inventory")
			if inventory_owner.has_method("get_grid_piece_instances"):
				owned_grid_instances = inventory_owner.call("get_grid_piece_instances")
			if added_ids is Array and not (added_ids as Array).is_empty() and inventory_owner.has_method("get_grid_piece_instance"):
				returned_instance = inventory_owner.call("get_grid_piece_instance", int((added_ids as Array)[0]))
		else:
			owned_grid_inventory[inventory_key] = maxi(int(owned_grid_inventory.get(inventory_key, 0)), 0) + 1
		var returned_piece := _add_forge_inventory_piece(
			room_type,
			null,
			inventory_key,
			returned_recipe,
			returned_instance
		)
		if returned_piece != null:
			forge_inventory_grid.call("receive_new_piece", returned_piece, cursor_position)
		_set_builder_status("%s secured in the parts locker." % _room_type_palette_name(room_type))
	else:
		_set_builder_status("%s removed from blueprint. Forge catalog supply remains unlimited." % _room_type_palette_name(room_type))
	if returned_piece_room != returned_room:
		_clear_builder_group_selection()
		_refresh_builder_after_edit()
	_play_menu_sound(execute_sound_method)


func _builder_cell_is_core(cell: Vector2i) -> bool:
	return (
		_uses_owned_inventory()
		and source_layout != null
		and source_layout.has_method("is_core_cell")
		and bool(source_layout.call("is_core_cell", cell))
	)


func _apply_inventory_recipe_to_room(room: Resource, recipe: Resource) -> void:
	room.set("module_recipe", recipe)
	room.set("maximum_health", float(recipe.get("maximum_health")))
	room.set("minimum_crew", int(recipe.get("minimum_crew")))
	room.set("optimal_crew", int(recipe.get("optimal_crew")))
	var payload: Resource = recipe.get("payload_resource")
	if payload != null:
		room.set("weapon_definition", payload.duplicate(true))
		room.set("display_name", String(recipe.get("display_name")))


func _normalize_unmanned_exterior_modules() -> void:
	if source_layout == null:
		return
	for room: Resource in source_layout.get("rooms"):
		_configure_unmanned_exterior_module(room)


func _configure_unmanned_exterior_module(room: Resource) -> void:
	if room == null or not ROOM_STAFFING_RULES.is_unmanned_exterior_module(room):
		return
	room.set("minimum_crew", 0)
	room.set("optimal_crew", 0)
	room.set(
		"maximum_health",
		ROOM_STAFFING_RULES.effective_maximum_health(room, float(room.get("maximum_health")))
	)
	if String(room.get("type_name")).to_upper() in ["SHIELD", "SHIELDS"]:
		room.set("display_name", "DIRECTIONAL SHIELD ARRAY")
		room.set("effect_label", "DIRECTIONAL SHIELD CAPACITY / REGEN")
		room.set(
			"description",
			"An exposed automated shield array protecting one hull direction. It requires no crew, but its exterior housing is easily damaged."
		)
	else:
		var recipe: Resource = room.get("module_recipe")
		if recipe != null:
			room.set("description", String(recipe.get("description")))


func _on_installed_piece_discarded(room_type: String, room_id: StringName, cell: Vector2i) -> void:
	if _builder_cell_is_core(cell):
		_set_builder_status("CORE FRAME LOCKED • PERMANENT KEEL CANNOT BE DISCARDED")
		_play_menu_sound(denied_sound_method)
		_pulse_builder_console()
		return
	var discarded_room := _builder_room_by_id(room_id)
	if discarded_room == null:
		discarded_room = _builder_room_at_cell(cell)
	if discarded_room == null:
		return
	var room_snapshot: Array[Resource] = []
	for room_value: Variant in source_layout.get("rooms"):
		room_snapshot.append((room_value as Resource).duplicate(true))
	var horizontal_offsets: Array[Vector2i] = source_layout.get("offset_cells").duplicate()
	var vertical_offsets: Array[Vector2i] = source_layout.get("vertical_offset_cells").duplicate()
	var discarded_piece_room := _builder_extract_piece_at_cell(discarded_room, cell)
	if discarded_piece_room == discarded_room:
		_builder_remove_room(discarded_room)
	else:
		source_layout.call("prune_unused_cell_offsets")
		_clear_builder_group_selection()
		_refresh_builder_after_edit()
	if _requires_connected_live_hull() and not _builder_hull_is_connected():
		_restore_relocation_snapshot(room_snapshot, horizontal_offsets, vertical_offsets)
		_set_builder_status("DISPOSAL DENIED • GRID IS A STRUCTURAL LINK")
		_play_menu_sound(denied_sound_method)
		_pulse_builder_console()
		return
	_set_builder_status("DISPOSAL CHUTE • %s grid vented from the refit plan." % _room_type_palette_name(room_type))
	_play_menu_sound(close_sound_method)
	_pulse_builder_console()


func _builder_extract_piece_at_cell(room: Resource, cell: Vector2i) -> Resource:
	var rects: Array[Rect2i] = room.get("grid_rects")
	if rects.size() <= 1:
		return room
	var piece_index := -1
	for index: int in range(rects.size()):
		if rects[index].has_point(cell):
			piece_index = index
			break
	if piece_index < 0:
		return room
	var facings := _room_piece_facings(room, rects.size())
	var fire_modes := _room_piece_fire_modes(room, rects.size())
	var detached := room.duplicate(false)
	var detached_rects: Array[Rect2i] = [rects[piece_index]]
	var detached_facing := facings[piece_index]
	detached.set("grid_rects", detached_rects)
	detached.set("module_mount_facings", [detached_facing])
	detached.set("weapon_fire_modes", [fire_modes[piece_index]])
	detached.set("module_facing_quarters", detached_facing)
	detached.set("installed_piece_count", 1)
	detached.set("maximum_health", float(room.get("maximum_health")) / float(rects.size()))
	detached.set("minimum_crew", _piece_crew_share(room, "minimum_crew", rects.size()))
	detached.set("optimal_crew", _piece_crew_share(room, "optimal_crew", rects.size()))

	rects.remove_at(piece_index)
	facings.remove_at(piece_index)
	fire_modes.remove_at(piece_index)
	room.set("grid_rects", rects)
	room.set("module_mount_facings", facings)
	room.set("weapon_fire_modes", fire_modes)
	room.set("installed_piece_count", rects.size())
	room.set("maximum_health", maxf(float(room.get("maximum_health")) - float(detached.get("maximum_health")), 1.0))
	room.set("minimum_crew", maxi(int(room.get("minimum_crew")) - int(detached.get("minimum_crew")), 0))
	room.set("optimal_crew", maxi(int(room.get("optimal_crew")) - int(detached.get("optimal_crew")), 0))
	_builder_split_disconnected_room(room)
	return detached


func _piece_crew_share(room: Resource, property_name: String, piece_count: int) -> int:
	var recipe: Resource = room.get("module_recipe")
	if recipe != null:
		return int(recipe.get(property_name))
	return maxi(roundi(float(room.get(property_name)) / float(maxi(piece_count, 1))), 0)


func _builder_split_disconnected_room(room: Resource) -> void:
	var rects: Array[Rect2i] = room.get("grid_rects")
	if rects.size() <= 1:
		return
	var facings := _room_piece_facings(room, rects.size())
	var fire_modes := _room_piece_fire_modes(room, rects.size())
	var unvisited: Array[int] = []
	for index: int in range(rects.size()):
		unvisited.append(index)
	var components: Array[Array] = []
	while not unvisited.is_empty():
		var component: Array = []
		var pending: Array[int] = [unvisited.pop_front()]
		while not pending.is_empty():
			var current: int = pending.pop_front()
			component.append(current)
			for candidate: int in unvisited.duplicate():
				if _rects_share_wall(rects[current], rects[candidate]):
					unvisited.erase(candidate)
					pending.append(candidate)
		components.append(component)
	if components.size() <= 1:
		return
	var definitions: Array = source_layout.get("rooms")
	var total_health := float(room.get("maximum_health"))
	var total_minimum := int(room.get("minimum_crew"))
	var total_optimal := int(room.get("optimal_crew"))
	for component_index: int in range(components.size()):
		var component: Array = components[component_index]
		var component_room := room if component_index == 0 else room.duplicate(false)
		var component_rects: Array[Rect2i] = []
		var component_facings: Array[int] = []
		var component_fire_modes: Array[int] = []
		for rect_index: int in component:
			component_rects.append(rects[rect_index])
			component_facings.append(facings[rect_index])
			component_fire_modes.append(fire_modes[rect_index])
		component_room.set("grid_rects", component_rects)
		component_room.set("module_mount_facings", component_facings)
		component_room.set("weapon_fire_modes", component_fire_modes)
		component_room.set("installed_piece_count", component_rects.size())
		var share := float(component_rects.size()) / float(rects.size())
		component_room.set("maximum_health", maxf(total_health * share, 1.0))
		component_room.set("minimum_crew", maxi(roundi(float(total_minimum) * share), 0))
		component_room.set("optimal_crew", maxi(roundi(float(total_optimal) * share), 0))
		if component_index > 0:
			component_room.set("room_id", StringName("%s_%d" % [String(room.get("type_name")).to_snake_case(), Time.get_ticks_usec() + component_index]))
			definitions.append(component_room)
	source_layout.set("rooms", definitions)


func _rects_share_wall(first: Rect2i, second: Rect2i) -> bool:
	for y: int in range(first.position.y, first.end.y):
		for x: int in range(first.position.x, first.end.x):
			var cell := Vector2i(x, y)
			for direction: Vector2i in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
				if second.has_point(cell + direction):
					return true
	return false


func _builder_remove_room(room: Resource) -> void:
	if source_layout == null or room == null:
		return
	var definitions: Array = source_layout.get("rooms")
	definitions.erase(room)
	source_layout.set("rooms", definitions)
	source_layout.call("prune_unused_cell_offsets")
	_clear_builder_group_selection()
	_refresh_builder_after_edit()


func _builder_delete_cell(cell: Vector2i) -> void:
	if _builder_room_at_cell(cell) == null:
		_set_builder_status("No hull section found at %s." % cell)
		return
	_builder_remove_cell_from_all_rooms(cell)
	source_layout.call("prune_unused_cell_offsets")
	_clear_builder_group_selection()
	_set_builder_status("Cell %s cleared from the hull." % cell)
	_refresh_builder_after_edit()


func _toggle_builder_group_cell(cell: Vector2i) -> void:
	var room := _builder_room_at_cell(cell)
	if room == null:
		_clear_builder_group_selection()
		_set_builder_status("Group tool needs occupied hull cells.")
		return
	if not EXPLICIT_GROUP_ROOM_TYPES.has(String(room.get("type_name"))):
		_clear_builder_group_selection()
		_set_builder_status("Grouping is enabled for weapons, thrusters, and hangars.")
		return
	# A second group-tool click changes intent from hardware inspection to an
	# explicit room-link selection.
	builder_last_selected_cell = INVALID_CELL
	builder_specific_mount_selected = false
	if builder_grid != null:
		builder_grid.call("clear_room_selection")
	if builder_group_selection.has(cell):
		builder_group_selection.erase(cell)
	else:
		builder_group_selection[cell] = true
	if builder_grid != null:
		builder_grid.call("set_group_selection", builder_group_selection)
		builder_grid.call("set_editor_focus_cell", INVALID_CELL, Vector2.ZERO)
	_set_builder_status("Group selection: %d cell%s." % [builder_group_selection.size(), "" if builder_group_selection.size() == 1 else "s"])
	_refresh_builder_context_controls()


func _combine_builder_selection() -> void:
	_set_builder_status("COMPARTMENT LINK DISABLED • EACH GRID OPERATES INDEPENDENTLY")
	_play_menu_sound(denied_sound_method)
	_pulse_builder_console()


func _split_builder_selection() -> void:
	var rooms_to_split: Array[Resource] = []
	var room_ids: Dictionary = {}
	for cell_value: Variant in builder_group_selection.keys():
		var room := _builder_room_at_cell(cell_value)
		if room == null or _builder_room_cells(room).size() <= 1:
			continue
		if not room_ids.has(room.get_instance_id()):
			room_ids[room.get_instance_id()] = true
			rooms_to_split.append(room)
	if rooms_to_split.is_empty():
		_set_builder_status("Select a grouped footprint to split.")
		return
	var split_room_ids: Dictionary = {}
	for room: Resource in rooms_to_split:
		split_room_ids[room.get_instance_id()] = true
	var original_definitions: Array = source_layout.get("rooms")
	var definitions: Array[Resource] = []
	for definition: Resource in original_definitions:
		if not split_room_ids.has(definition.get_instance_id()):
			definitions.append(definition)
	var split_count := 0
	var split_cells: Dictionary = {}
	for source_room: Resource in rooms_to_split:
		var source_cells := _builder_room_cells(source_room)
		var health_per_cell := float(source_room.get("maximum_health")) / maxf(float(source_cells.size()), 1.0)
		for cell_value: Variant in source_cells.keys():
			var new_room := _duplicate_builder_room_as_single_cell(source_room, cell_value, health_per_cell, split_count)
			definitions.append(new_room)
			split_cells[cell_value] = true
			split_count += 1
	source_layout.set("rooms", definitions)
	builder_tool = "group"
	builder_pending_delete_cell = INVALID_CELL
	builder_group_selection = split_cells
	builder_last_selected_cell = INVALID_CELL
	if source_layout.has_method("prune_unused_cell_offsets"):
		source_layout.call("prune_unused_cell_offsets")
	source_layout.emit_changed()
	_refresh_builder_after_edit()
	if builder_grid != null:
		builder_grid.call("set_editor_selection_mode", true)
		builder_grid.call("set_group_selection", builder_group_selection)
		builder_grid.call("set_editor_focus_cell", INVALID_CELL, Vector2.ZERO)
	_refresh_builder_context_controls()
	_refresh_display()
	var resulting_rooms := _builder_selected_room_count()
	if resulting_rooms == split_count:
		_set_builder_status("Split footprint into %d independent cells. Selection remains active for review or re-merge." % split_count)
	else:
		_set_builder_status("Split refreshed %d cells. Review selection before re-merge." % split_count)
	_play_menu_sound(execute_sound_method)
	_pulse_builder_grid()


func _duplicate_builder_room_as_single_cell(source_room: Resource, cell: Vector2i, health_per_cell: float, suffix: int) -> Resource:
	var room_script := preload("res://scripts/resources/room_layout_data.gd")
	var new_room: Resource = room_script.new()
	new_room.set("room_id", StringName("%s_%d" % [String(source_room.get("type_name")).to_snake_case(), Time.get_ticks_usec() + suffix]))
	new_room.set("display_name", source_room.get("display_name"))
	new_room.set("type_name", source_room.get("type_name"))
	new_room.set("effect_label", source_room.get("effect_label"))
	new_room.set("description", source_room.get("description"))
	new_room.set("grid_label", source_room.get("grid_label"))
	var single_rects: Array[Rect2i] = [Rect2i(cell, Vector2i.ONE)]
	new_room.set("grid_rects", single_rects)
	new_room.set("color", source_room.get("color"))
	new_room.set("maximum_health", health_per_cell)
	new_room.set("produces_output", source_room.get("produces_output"))
	new_room.set("contributes_to_hull", source_room.get("contributes_to_hull"))
	new_room.set("storage_role", source_room.get("storage_role"))
	new_room.set("storage_capacity_per_cell", source_room.get("storage_capacity_per_cell"))
	new_room.set("minimum_crew", source_room.get("minimum_crew"))
	new_room.set("optimal_crew", source_room.get("optimal_crew"))
	new_room.set("build_requirements", source_room.get("build_requirements"))
	new_room.set("adjacency_effects", source_room.get("adjacency_effects"))
	new_room.set("weapon_definition", source_room.get("weapon_definition"))
	new_room.set("module_recipe", null)
	new_room.set("module_rotation_quarters", source_room.get("module_rotation_quarters"))
	new_room.set("module_facing_quarters", source_room.get("module_facing_quarters"))
	new_room.set("module_mirrored", source_room.get("module_mirrored"))
	return new_room


func _builder_selected_room_count() -> int:
	var room_ids: Dictionary = {}
	for cell_value: Variant in builder_group_selection.keys():
		var room := _builder_room_at_cell(cell_value)
		if room != null:
			room_ids[room.get_instance_id()] = true
	return room_ids.size()


func _set_builder_facing(facing_quarters: int) -> void:
	var room := _builder_complete_selected_room()
	if room == null and builder_last_selected_cell != INVALID_CELL:
		room = _builder_room_at_cell(builder_last_selected_cell)
	if room == null:
		_set_builder_status("Select a module cell or complete group before setting direction.")
		return
	var facing_subject := _builder_mount_view_at_cell(room, builder_last_selected_cell)
	if source_layout.has_method("evaluate_room_facing_clearance"):
		var clearance: Dictionary = source_layout.call("evaluate_room_facing_clearance", facing_subject, facing_quarters)
		if not bool(clearance["valid"]):
			_set_builder_status(String(clearance["message"]))
			if builder_facing_actions != null:
				builder_facing_actions.call("set_current_facing", int(facing_subject.get("module_facing_quarters")))
			_play_menu_sound(denied_sound_method)
			_pulse_builder_console()
			return
	_set_room_mount_facing_at_cell(room, builder_last_selected_cell, facing_quarters)
	if builder_facing_actions != null:
		builder_facing_actions.call("set_current_facing", facing_quarters)
	_set_builder_status("%s VECTOR LOCKED" % String(room.get("display_name")).to_upper())
	_refresh_builder_after_edit()
	_play_menu_sound(execute_sound_method)
	_pulse_builder_grid()


func _on_builder_facing_blocked(facing_quarters: int) -> void:
	var room := _builder_complete_selected_room()
	if room == null and builder_last_selected_cell != INVALID_CELL:
		room = _builder_room_at_cell(builder_last_selected_cell)
	var message := "VECTOR BLOCKED • MODULE MUST FACE AN EXPOSED HULL EDGE"
	if room != null and source_layout != null and source_layout.has_method("evaluate_room_facing_clearance"):
		var facing_subject := _builder_mount_view_at_cell(room, builder_last_selected_cell)
		var clearance: Dictionary = source_layout.call("evaluate_room_facing_clearance", facing_subject, facing_quarters)
		message = String(clearance.get("message", message))
	_set_builder_status(message)
	_play_menu_sound(denied_sound_method)
	_pulse_builder_console()


func _builder_available_facings(room: Resource) -> Array:
	var availability := [true, true, true, true]
	if room == null or source_layout == null or not source_layout.has_method("evaluate_room_facing_clearance"):
		return availability
	for facing: int in range(4):
		var clearance: Dictionary = source_layout.call("evaluate_room_facing_clearance", room, facing)
		availability[facing] = bool(clearance.get("valid", true))
	return availability


func _builder_mount_index_at_cell(room: Resource, cell: Vector2i) -> int:
	if room == null:
		return -1
	var rects: Array[Rect2i] = room.get("grid_rects")
	for index: int in range(rects.size()):
		if rects[index].has_point(cell):
			return index
	return -1


func _builder_mount_view_at_cell(room: Resource, cell: Vector2i) -> Resource:
	var mount_index := _builder_mount_index_at_cell(room, cell)
	var rects: Array[Rect2i] = room.get("grid_rects")
	if mount_index < 0 or rects.size() <= 1:
		return room
	var view := room.duplicate(false)
	var one_rect: Array[Rect2i] = [rects[mount_index]]
	var facings := _room_piece_facings(room, rects.size())
	view.set("grid_rects", one_rect)
	view.set("module_facing_quarters", facings[mount_index])
	view.set("module_mount_facings", [facings[mount_index]])
	view.set("installed_piece_count", 1)
	return view


func _set_room_mount_facing_at_cell(room: Resource, cell: Vector2i, facing_quarters: int) -> void:
	var rects: Array[Rect2i] = room.get("grid_rects")
	var mount_index := _builder_mount_index_at_cell(room, cell)
	if mount_index < 0 or rects.size() <= 1:
		room.set("module_facing_quarters", facing_quarters)
		room.set("module_mount_facings", [facing_quarters])
		return
	var facings := _room_piece_facings(room, rects.size())
	facings[mount_index] = facing_quarters
	room.set("module_mount_facings", facings)
	# Keep the legacy fallback coherent when every hardpoint shares one vector.
	var all_match := true
	for stored_facing: int in facings:
		if stored_facing != facing_quarters:
			all_match = false
			break
	if all_match:
		room.set("module_facing_quarters", facing_quarters)


func _clear_builder_group_selection() -> void:
	builder_group_selection.clear()
	if builder_grid != null:
		builder_grid.call("set_group_selection", builder_group_selection)
	_refresh_builder_context_controls()


func _set_builder_status(message: String) -> void:
	if embedded_refit_mode:
		embedded_status_changed.emit(message, _builder_message_is_error(message))
	if _builder_message_is_error(message):
		_show_builder_alert(message)
		return
	if builder_status_label != null:
		builder_status_label.text = message
		_pulse_control(builder_status_label, Color(0.78, 1.25, 1.12, 1.0), 1.04)
	if shipyard_notice_label != null and current_context == "edit":
		shipyard_notice_label.text = (
			"HARDLINE • %s" % message.get_slice(" • ", 0).strip_edges().to_upper()
			if _uses_owned_inventory()
			else "DRYDOCK   %s" % message.to_upper()
		)
		shipyard_notice_label.add_theme_color_override("font_color", Color(0.28, 1.0, 0.88, 0.95))


func _announce_shipyard(message: String, is_warning := false) -> void:
	if is_warning:
		_show_builder_alert(message)
		return
	if shipyard_notice_label == null:
		return
	shipyard_notice_label.text = message
	var color := Color(1.0, 0.62, 0.28, 1.0) if is_warning else Color(0.28, 1.0, 0.88, 0.98)
	shipyard_notice_label.add_theme_color_override("font_color", color)
	_pulse_control(shipyard_notice_label, Color(1.0, 0.86, 0.42, 1.0) if is_warning else Color(0.72, 1.35, 1.22, 1.0), 1.035)


func _build_builder_alert() -> void:
	builder_alert_panel = PanelContainer.new()
	builder_alert_panel.name = "DrydockInterlockAlert"
	builder_alert_panel.z_index = 400
	builder_alert_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	builder_alert_panel.anchor_left = 0.5
	builder_alert_panel.anchor_top = 0.0
	builder_alert_panel.anchor_right = 0.5
	builder_alert_panel.anchor_bottom = 0.0
	builder_alert_panel.offset_left = -280.0
	builder_alert_panel.offset_top = 88.0
	builder_alert_panel.offset_right = 280.0
	builder_alert_panel.offset_bottom = 166.0
	builder_alert_panel.add_theme_stylebox_override(
		"panel",
		_panel_style(
			Color(0.065, 0.025, 0.012, 0.98),
			Color(1.0, 0.34, 0.12, 1.0),
			2
		)
	)
	builder_alert_panel.visible = false
	add_child(builder_alert_panel)

	var alert_margin := MarginContainer.new()
	alert_margin.add_theme_constant_override("margin_left", 16)
	alert_margin.add_theme_constant_override("margin_top", 9)
	alert_margin.add_theme_constant_override("margin_right", 16)
	alert_margin.add_theme_constant_override("margin_bottom", 9)
	builder_alert_panel.add_child(alert_margin)

	var alert_stack := VBoxContainer.new()
	alert_stack.add_theme_constant_override("separation", 4)
	alert_margin.add_child(alert_stack)

	builder_alert_title = Label.new()
	builder_alert_title.add_theme_font_size_override("font_size", 13)
	builder_alert_title.add_theme_color_override("font_color", Color(1.0, 0.36, 0.16, 1.0))
	alert_stack.add_child(builder_alert_title)

	builder_alert_detail = Label.new()
	builder_alert_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	builder_alert_detail.add_theme_font_size_override("font_size", 10)
	builder_alert_detail.add_theme_color_override("font_color", Color(1.0, 0.78, 0.4, 1.0))
	alert_stack.add_child(builder_alert_detail)


func _show_builder_alert(message: String) -> void:
	if not is_instance_valid(builder_alert_panel):
		return
	var message_parts := message.split(" • ", false)
	builder_alert_title.text = message_parts[0].strip_edges().to_upper()
	var details: PackedStringArray = []
	for part_index: int in range(1, message_parts.size()):
		var detail := message_parts[part_index].strip_edges()
		if not detail.is_empty():
			details.append(detail.to_upper())
	builder_alert_detail.text = "  ◆  ".join(details)
	builder_alert_detail.visible = not details.is_empty()
	if builder_alert_tween != null and builder_alert_tween.is_valid():
		builder_alert_tween.kill()
	builder_alert_panel.visible = true
	builder_alert_panel.pivot_offset = builder_alert_panel.size * 0.5
	builder_alert_panel.scale = Vector2(0.92, 0.68)
	builder_alert_panel.modulate = Color(1.25, 0.82, 0.48, 0.0)
	builder_alert_tween = create_tween()
	builder_alert_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	builder_alert_tween.tween_property(
		builder_alert_panel,
		"scale",
		Vector2.ONE,
		0.13
	).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	builder_alert_tween.parallel().tween_property(
		builder_alert_panel,
		"modulate",
		Color.WHITE,
		0.09
	)
	builder_alert_tween.tween_interval(1.65)
	builder_alert_tween.tween_property(
		builder_alert_panel,
		"modulate",
		Color(1.0, 0.55, 0.25, 0.0),
		0.22
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	builder_alert_tween.tween_callback(builder_alert_panel.hide)


func _builder_message_is_error(message: String) -> bool:
	var upper := message.to_upper()
	for warning_term: String in [
		"DENIED",
		"BLOCKED",
		"FAILED",
		"LOST",
		"NOT IN CARGO",
		"OUTSIDE THE AUTHORIZED",
		"NO HULL",
		"NO CELL",
		"NO ACTIVE",
		"NO BLUEPRINT",
		"FOUND NO",
		"NEEDS ",
		"REQUIRES ",
		"MUST ",
		"SELECT AT LEAST",
		"CHOOSE A ",
		"IS QUEUED",
		"INTERLOCK",
	]:
		if upper.contains(warning_term):
			return true
	return false


func _pulse_builder_console() -> void:
	_pulse_control(save_section, Color(0.78, 1.18, 1.1, 1.0), 1.015)


func _pulse_builder_grid() -> void:
	_pulse_control(builder_grid, Color(0.8, 1.28, 1.18, 1.0), 1.035)


func _pulse_control(control: Control, flash_color: Color, peak_scale: float) -> void:
	if not is_instance_valid(control):
		return
	control.pivot_offset = control.size * 0.5
	var tween := create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(control, "scale", Vector2.ONE * peak_scale, 0.055).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(control, "modulate", flash_color, 0.055)
	tween.tween_property(control, "scale", Vector2.ONE, 0.11).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(control, "modulate", Color.WHITE, 0.11)


func _refresh_builder_after_edit() -> void:
	_invalidate_builder_resource_stats()
	if builder_grid != null:
		builder_grid.call("refresh_layout")
	_apply_layout_to_active_ship(source_layout)
	_refresh_display()


func _refresh_builder_resource_meters() -> void:
	if builder_resource_panel == null:
		return
	var should_show := current_context == "edit" and source_layout != null
	builder_resource_panel.visible = should_show
	if not should_show:
		builder_resource_signature = ""
		return
	if builder_resource_stats_cache.is_empty():
		builder_resource_stats_cache = ShipBuilderAnalyzer.analyze(source_layout, selected_size)
	var stats: Dictionary = builder_resource_stats_cache
	var preview_capacity := 0.0
	var preview_demand := 0.0
	var preview_crew_required := 0
	var preview_crew_capacity := 0
	var drag_data: Variant = get_viewport().gui_get_drag_data()
	if drag_data is Dictionary:
		var kind := String(drag_data.get("kind", ""))
		var room_type := String(drag_data.get("room_type", ""))
		var cell_count := 1
		if kind == "forge_grid_piece":
			var footprint: Vector2i = drag_data.get("footprint", Vector2i.ONE)
			cell_count = maxi(footprint.x * footprint.y, 1)
			var addition := _builder_resource_delta(room_type, cell_count)
			preview_capacity = float(addition.x)
			preview_demand = float(addition.y)
			preview_crew_required = _builder_room_type_minimum_crew(room_type)
			if room_type in ["CREW", "CREW_QUARTERS"]:
				preview_crew_capacity = cell_count * ShipBuilderAnalyzer.CREW_CAPACITY_PER_QUARTERS_CELL
		elif kind == "installed_grid_piece":
			var room := _builder_room_at_cell(drag_data.get("cell", Vector2i.ZERO))
			if room != null:
				cell_count = maxi(_builder_room_cells(room).size(), 1)
				var removal := _builder_resource_delta(String(room.get("type_name")), cell_count, room)
				preview_capacity = -float(removal.x)
				preview_demand = -float(removal.y)
				preview_crew_required = -_builder_room_minimum_crew(room)
				if String(room.get("type_name")) in ["CREW", "CREW_QUARTERS"]:
					preview_crew_capacity = -cell_count * ShipBuilderAnalyzer.CREW_CAPACITY_PER_QUARTERS_CELL
	elif _uses_owned_inventory() and not builder_room_type.is_empty() and forge_armed_piece_id > 0:
		var addition := _builder_resource_delta(builder_room_type, 1)
		preview_capacity = float(addition.x)
		preview_demand = float(addition.y)
		preview_crew_required = _builder_room_type_minimum_crew(builder_room_type)
		if builder_room_type in ["CREW", "CREW_QUARTERS"]:
			preview_crew_capacity = ShipBuilderAnalyzer.CREW_CAPACITY_PER_QUARTERS_CELL
	var crew_counts := _builder_live_crew_counts()
	if inventory_mode == "FORGE":
		crew_counts = {"total": 0, "injured": 0}
	var healthy_crew := maxi(int(crew_counts["total"]) - int(crew_counts["injured"]), 0)
	var base_required := int(stats["minimum_crew"])
	var final_required := maxi(base_required + preview_crew_required, 0)
	var final_crew_capacity := maxi(int(stats["crew_capacity"]) + preview_crew_capacity, 0)
	var working := 0
	var available := healthy_crew
	var preview_reserved := maxi(preview_crew_required, 0)
	var missing := maxi(final_required - healthy_crew, 0)
	var signature := "%s|%s|%s|%s|%s|%s|%s|%s|%s|%s" % [
		stats["energy_capacity"],
		stats["energy_demand"],
		preview_capacity,
		preview_demand,
		working,
		available,
		crew_counts["injured"],
		missing,
		preview_reserved,
		final_crew_capacity,
	]
	if signature == builder_resource_signature:
		return
	builder_resource_signature = signature
	builder_power_meter.call(
		"set_power_coverage_state",
		int(stats.get("reactor_field_count", 0)),
		int(stats.get("powered_room_count", 0)),
		int(stats.get("underpowered_room_count", 0)),
		float(stats.get("reactor_field_count", 0)),
		roundi(preview_capacity),
		roundi(maxf(preview_demand, 0.0))
	)
	builder_crew_meter.call(
		"set_crew_state",
		working,
		available,
		int(crew_counts["injured"]),
		missing,
		preview_reserved,
		"blueprint",
		final_crew_capacity
	)


func _invalidate_builder_resource_stats() -> void:
	builder_resource_stats_cache.clear()
	builder_resource_signature = ""


func _builder_resource_delta(room_type: String, cell_count: int, room: Resource = null) -> Vector2:
	if room == null:
		var armed_piece := _inventory_piece_by_id(forge_armed_piece_id, room_type)
		if armed_piece != null:
			return Vector2(
				float(armed_piece.get("power_capacity")),
				float(armed_piece.get("power_draw"))
			)
		if builder_module_recipe != null:
			return Vector2(
				0.0,
				float(builder_module_recipe.get("power_draw")) * maxf(float(cell_count), 1.0)
			)
	var power_room := room if room != null else _builder_room_type_template(room_type)
	return ShipBuilderAnalyzer.room_power_delta(room_type, cell_count, power_room)


func _builder_power_placement_status(
	room_type: String,
	cell: Vector2i,
	footprint := Vector2i(2, 2)
) -> Dictionary:
	var existing := _builder_room_at_cell(cell)
	var template := _builder_room_type_template(room_type)
	if builder_module_recipe != null:
		template = template.duplicate(true) if template != null else RoomLayoutData.new()
		template.set("module_recipe", builder_module_recipe)
	return ShipBuilderAnalyzer.evaluate_power_placement(
		source_layout,
		room_type,
		cell,
		Vector2i(footprint),
		template,
		existing
	)


func _builder_readiness_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if source_layout == null or inventory_mode != "FORGE":
		return warnings
	var stats := ShipBuilderAnalyzer.analyze(source_layout, selected_size)
	var missing_links := float(stats.get("missing_reactor_links", 0.0))
	var underpowered_rooms := int(stats.get("underpowered_room_count", 0))
	if underpowered_rooms > 0:
		warnings.append("REACTOR COVERAGE LOW • %d ROOM%s • %d FIELD LINK%s MISSING" % [
			underpowered_rooms,
			"" if underpowered_rooms == 1 else "S",
			ceili(missing_links),
			"" if ceili(missing_links) == 1 else "S",
		])
	var crew_capacity := int(stats.get("crew_capacity", 0))
	var minimum_crew := int(stats.get("minimum_crew", 0))
	var optimal_crew := maxi(int(stats.get("optimal_crew", 0)), minimum_crew)
	if crew_capacity < minimum_crew:
		warnings.append("NOT ENOUGH CREW QUARTERS • MINIMUM WATCH %d • MAX CREW %d" % [minimum_crew, crew_capacity])
	elif crew_capacity < optimal_crew:
		warnings.append("OPTIMAL WATCH UNAVAILABLE • %d CREW NEEDED • MAX CREW %d" % [optimal_crew, crew_capacity])
	if not _builder_hull_is_connected():
		warnings.append("HULL HAS DISCONNECTED SECTIONS")
	return warnings


func _builder_room_type_minimum_crew(room_type: String) -> int:
	if builder_module_recipe != null and room_type == "WEAPONS":
		return int(builder_module_recipe.get("minimum_crew"))
	var template := _builder_room_type_template(room_type)
	return _builder_room_minimum_crew(template) if template != null else 0


func _builder_room_minimum_crew(room: Resource) -> int:
	if room == null:
		return 0
	if String(room.get("type_name")) in ["UNASSIGNED", "CREW", "CREW_QUARTERS", "MESS_HALL", "SUPPLY_STORAGE", "CARGO"]:
		return 0
	var required := int(room.get("minimum_crew"))
	var recipe: Resource = room.get("module_recipe")
	if recipe != null:
		required = maxi(required, int(recipe.get("minimum_crew")))
	return ROOM_STAFFING_RULES.effective_requirements(room, required, int(room.get("optimal_crew"))).x


func _builder_room_optimal_crew(room: Resource) -> int:
	if room == null:
		return 0
	if String(room.get("type_name")) in ["UNASSIGNED", "CREW", "CREW_QUARTERS", "MESS_HALL", "SUPPLY_STORAGE", "CARGO"]:
		return 0
	var minimum := int(room.get("minimum_crew"))
	var optimal := int(room.get("optimal_crew"))
	var recipe: Resource = room.get("module_recipe")
	if recipe != null:
		minimum = maxi(minimum, int(recipe.get("minimum_crew")))
		optimal = maxi(optimal, int(recipe.get("optimal_crew")))
	return ROOM_STAFFING_RULES.effective_requirements(room, minimum, optimal).y


func _builder_live_crew_counts() -> Dictionary:
	var counts := {"total": 0, "injured": 0}
	var crew := get_tree().get_first_node_in_group("crew_simulation")
	if not is_instance_valid(crew):
		return counts
	for member: Dictionary in crew.crew_members:
		if bool(member.get("dead", false)) or bool(member.get("ejected", false)):
			continue
		counts["total"] = int(counts["total"]) + 1
		var maximum_health := maxf(float(member.get("maximum_health", 1.0)), 1.0)
		if (
			bool(member.get("incapacitated", false))
			or bool(member.get("seeking_medical", false))
			or float(member.get("health", maximum_health)) < maximum_health - 0.001
		):
			counts["injured"] = int(counts["injured"]) + 1
	return counts


func _refresh_display() -> void:
	if preview == null or stat_label == null:
		return
	_refresh_builder_resource_meters()
	if dossier_panel != null:
		dossier_panel.visible = false
	match current_context:
		"":
			_show_builder_grid(false)
			var idle_size := selected_size if selected_size != Vector2i.ZERO else Vector2i(6, 6)
			if source_layout != null:
				idle_size = Vector2i(int(source_layout.get("columns")), int(source_layout.get("rows")))
				preview.set_layout(source_layout, idle_size)
			else:
				preview.set_layout(null, idle_size)
			stat_label.text = ""
			return
		"new_size", "new_confirm":
			_show_builder_grid(false)
			var new_size := hovered_frame_size if hovered_frame_size != Vector2i.ZERO else selected_size
			if new_size == Vector2i.ZERO:
				new_size = Vector2i(6, 6)
			preview.set_layout(null, new_size)
			stat_label.text = ""
			return
		"load":
			_show_builder_grid(false)
			var load_size := selected_size if selected_size != Vector2i.ZERO else Vector2i(6, 6)
			if selected_blueprint_layout != null:
				load_size = Vector2i(int(selected_blueprint_layout.get("columns")), int(selected_blueprint_layout.get("rows")))
				preview.set_layout(selected_blueprint_layout, load_size)
			else:
				preview.set_layout(null, load_size)
			stat_label.text = ""
			return
	if source_layout == null:
		_show_builder_grid(false)
		preview.set_layout(null, Vector2i(6, 6))
		stat_label.text = "[color=#ff9966]No active hull connected.[/color]"
		return
	_show_builder_grid(current_context == "edit")
	if current_context != "edit":
		preview.set_layout(source_layout, selected_size)
	if _uses_owned_inventory() and current_context == "edit":
		if inspected_inventory_piece_id > 0:
			var station_inventory_piece := _inventory_piece_by_id(
				inspected_inventory_piece_id,
				inspected_inventory_room_type
			)
			if station_inventory_piece != null:
				dossier_panel.visible = true
				stat_label.text = _format_inventory_piece_card(station_inventory_piece)
				return
			inspected_inventory_piece_id = 0
			inspected_inventory_room_type = ""
		if builder_tool == "group" and builder_group_selection.size() > 1 and builder_last_selected_cell == INVALID_CELL:
			dossier_panel.visible = true
			stat_label.text = _format_group_selection_card()
			return
		if builder_last_selected_cell != INVALID_CELL:
			var station_selected_room := _builder_room_at_cell(builder_last_selected_cell)
			if station_selected_room != null:
				dossier_panel.visible = true
				stat_label.text = _format_station_room_card(station_selected_room)
				return
		stat_label.text = ""
		return
	if current_context == "edit" and inspected_inventory_piece_id > 0:
		var forge_inventory_piece := _inventory_piece_by_id(
			inspected_inventory_piece_id,
			inspected_inventory_room_type
		)
		if forge_inventory_piece != null:
			dossier_panel.visible = true
			stat_label.text = _format_inventory_piece_card(forge_inventory_piece)
			return
		inspected_inventory_piece_id = 0
		inspected_inventory_room_type = ""
	if current_context == "edit" and builder_tool == "group" and builder_group_selection.size() > 1 and builder_last_selected_cell == INVALID_CELL:
		dossier_panel.visible = true
		stat_label.text = _format_group_selection_card()
		return
	if current_context == "edit" and builder_last_selected_cell != INVALID_CELL:
		var selected_room := _builder_room_at_cell(builder_last_selected_cell)
		if selected_room != null:
			dossier_panel.visible = true
			stat_label.text = _format_station_room_card(selected_room)
			return
	stat_label.text = ""


func _format_inventory_piece_card(piece: Control) -> String:
	var display_name := String(piece.get("display_name")).to_upper()
	var footprint := Vector2i(piece.get("footprint"))
	var power_capacity := maxi(int(piece.get("power_capacity")), 0)
	var power_required := maxi(int(piece.get("power_draw")), 0)
	var crew_required := maxi(int(piece.get("crew_required")), 0)
	var lines := PackedStringArray([
		"[color=#315f5b][font_size=8]◆  CARGO PROFILE[/font_size][/color]",
		"[color=#f2a83d][font_size=14][outline_size=2][outline_color=#241407]%s[/outline_color][/outline_size][/font_size][/color]" % display_name,
		"[color=#315f5b]━━━━━━━━━━━━[/color]",
		"[color=#6a9d96]FRAME[/color]  [color=#bffcf2]%s[/color]" % _inventory_footprint_label(footprint),
	])
	if power_capacity > 0:
		lines.append("[color=#fff12c]ϟ[/color]  PROJECTS %d REACTOR FIELD%s" % [
			power_capacity,
			"" if power_capacity == 1 else "S",
		])
	elif power_required > 0:
		lines.append(POWER_REQUIREMENT_DISPLAY.bbcode(power_required, float(power_required)))
	if crew_required > 0:
		lines.append(CREW_REQUIREMENT_DISPLAY.status_bbcode(crew_required, crew_required, true))
	lines.append("")
	lines.append("[color=#72fff0]DRAG TO THE HULL TO INSTALL[/color]")
	return "\n".join(lines)


func _format_station_room_card(room: Resource) -> String:
	var display_room := room
	if builder_last_selected_cell != INVALID_CELL:
		var selected_mount := _builder_mount_view_at_cell(room, builder_last_selected_cell)
		if selected_mount != null:
			display_room = selected_mount
	var room_type := String(display_room.get("type_name"))
	var minimum_crew := _builder_room_minimum_crew(room)
	var optimal_crew := _builder_room_optimal_crew(room)
	var piece_count := maxi(int(display_room.get("installed_piece_count")), 1)
	var power_delta := ShipBuilderAnalyzer.room_power_delta(room_type, piece_count, display_room)
	var display_name := String(display_room.get("display_name")).to_upper()
	var name_size := 13 if display_name.length() > 12 else 15
	var lines: PackedStringArray = [
		"[color=#315f5b][font_size=8]◆  GRID LINK[/font_size][/color]",
		"[color=#f2a83d][font_size=%d][outline_size=2][outline_color=#241407]%s[/outline_color][/outline_size][/font_size][/color]" % [name_size, display_name],
		"[color=#315f5b]━━━━━━━━━━━━[/color]",
	]
	var field := _selected_room_power_field(room)
	if power_delta.x > 0.0:
		var field_count := int(field.get("field_count", roundi(power_delta.x)))
		var supported := int((field.get("room_ids", []) as Array).size()) - int((field.get("generator_ids", []) as Array).size())
		var missing := float(field.get("missing_links", 0.0))
		lines.append("")
		lines.append("[color=#6a9d96]LOCAL FIELD[/color]")
		lines.append(_compact_power_pips(field_count, field_count))
		lines.append("[color=#72fff0]%d[/color] REACTOR FIELD%s  [color=#f2a83d]%d[/color] ROOMS COVERED" % [
			field_count, "" if field_count == 1 else "S", maxi(supported, 0),
		])
		if missing > 0.001:
			lines.append("[color=#ff4b2b]%d FIELD LINKS MISSING[/color]" % ceili(missing))
	elif power_delta.y > 0.0:
		var report := ShipBuilderAnalyzer.power_network_report(source_layout)
		var room_id: StringName = room.get("room_id")
		var power_required := int((report.get("room_requirements", {}) as Dictionary).get(room_id, maxi(ceili(power_delta.y), 1)))
		var power_supplied := clampf(float((report.get("room_coverage", {}) as Dictionary).get(room_id, 0.0)), 0.0, float(power_required))
		lines.append("")
		lines.append(POWER_REQUIREMENT_DISPLAY.bbcode(power_required, power_supplied) + _crew_requirement_icons(room, optimal_crew))
	elif optimal_crew > 0:
		lines.append("")
		lines.append(_crew_requirement_icons(room, optimal_crew).strip_edges())
	lines.append_array(_room_performance_instruments(display_room))
	return "\n".join(lines)


func _room_performance_instruments(room: Resource) -> PackedStringArray:
	var lines := PackedStringArray()
	if room == null:
		return lines
	var room_type := String(room.get("type_name"))
	var cell_count := maxi(_builder_room_cells(room).size(), 1)
	if room_type == "PROPULSION":
		var thrust := float(cell_count) * 12.0
		lines.append("")
		lines.append(_visual_stat_track("»", thrust, 48.0, "#f2a83d", "%d" % roundi(thrust)))
	elif room_type == "WEAPONS":
		var weapon: Resource = room.get("weapon_definition")
		if weapon != null:
			var base_damage := float(weapon.get("damage"))
			var hull_damage := base_damage * float(weapon.get("hull_damage_multiplier"))
			var shield_damage := base_damage * float(weapon.get("shield_damage_multiplier"))
			var reload := float(weapon.get("reload_seconds"))
			lines.append("")
			lines.append(_visual_stat_track("◷", reload, 10.0, "#f2a83d", "%.1fs" % reload))
			lines.append(_visual_stat_track("◆", hull_damage, 60.0, "#ff7040", "%d" % roundi(hull_damage)))
			lines.append(_visual_stat_track("⬡", shield_damage, 60.0, "#46dfff", "%d" % roundi(shield_damage)))
	return lines


func _visual_stat_track(icon: String, value: float, scale_max: float, color: String, value_text: String) -> String:
	const SEGMENTS := 6
	var lit_segments := clampi(ceili(clampf(value / maxf(scale_max, 0.001), 0.0, 1.0) * SEGMENTS), 1, SEGMENTS)
	var track := ""
	for index: int in range(SEGMENTS):
		track += "[color=%s]▰[/color]" % (color if index < lit_segments else "#183331")
	return "[font_size=12][color=%s]%s[/color][/font_size] %s  [color=%s]%s[/color]" % [
		color, icon, track, color, value_text,
	]


func _selected_room_power_field(room: Resource) -> Dictionary:
	if source_layout == null or room == null:
		return {}
	var room_id: StringName = room.get("room_id")
	var report := ShipBuilderAnalyzer.power_network_report(source_layout)
	for network_value: Variant in report.get("networks", []):
		var network := network_value as Dictionary
		if (network.get("room_ids", []) as Array).has(room_id):
			return network
	return {"factor": float((report.get("room_factors", {}) as Dictionary).get(room_id, 0.0))}


func _compact_power_pips(capacity: float, demand: float) -> String:
	var total := maxi(roundi(capacity), 1)
	var used := clampi(roundi(demand), 0, total)
	var result := ""
	for index: int in range(total):
		result += "[color=%s]■[/color]" % ("#f2a83d" if index < used else "#174f4d")
	return result


func _crew_requirement_icons(room: Resource, required: int) -> String:
	if required <= 0:
		return ""
	var operating := 0
	var crew := get_tree().get_first_node_in_group("crew_simulation")
	if inventory_mode != "FORGE" and is_instance_valid(crew) and crew.has_method("get_room_staffing"):
		operating = int(crew.call("get_room_staffing", StringName(room.get("room_id"))))
	var eventual_crew_available := true
	if source_layout != null:
		var stats := ShipBuilderAnalyzer.analyze(source_layout, selected_size)
		eventual_crew_available = int(stats.get("crew_capacity", 0)) >= int(stats.get("optimal_crew", 0))
	if not embedded_refit_mode and eventual_crew_available:
		operating = required
	return "    " + CREW_REQUIREMENT_DISPLAY.status_bbcode(required, mini(operating, required), eventual_crew_available)


func _format_idle_terminal() -> String:
	return "\n".join([
		_instrument_header("DRYDOCK CONSOLE", "no hull on the clamps"),
		_status_chip("BAY", false) + "  waiting for work order",
		"",
		_instrument_section("AVAILABLE STATIONS"),
		_status_chip("NEW", true) + "  cut a clean build frame",
		_status_chip("EDIT", true) + "  connect current vessel",
		_status_chip("LOAD", true) + "  pull a stored blueprint",
		"",
		"[color=#46fff0]Choose a command card. The preview bay wakes once a hull is linked.[/color]",
	])


func _format_connected_terminal(stats: Dictionary) -> String:
	var size_value := _full_grid_size(Vector2i(stats["build_size"]))
	var hull_size: Vector2i = stats["hull_size"]
	var reactor_fields := int(stats.get("reactor_field_count", 0))
	var powered_rooms := int(stats.get("powered_room_count", 0))
	var underpowered_rooms := int(stats.get("underpowered_room_count", 0))
	var room_counts := _format_counts(stats["room_counts"])
	var shield_capacity := float(stats["shield_capacity"])
	var shield_regen := float(stats["shield_regen"])
	var thrust_rating := float(stats["thrust_rating"])
	var weapon_count := int(stats["weapon_count"])
	var hangar_capacity := int(stats["hangar_capacity"])
	var current_crew := int(_builder_live_crew_counts().get("total", 0))
	return "\n".join([
		_instrument_header("VESSEL STATUS", "drydock link active"),
		_status_chip("FRAME", true) + "  %dx%d full-room bay • %dx%d quarter-cell hull • %d cells" % [size_value.x, size_value.y, hull_size.x, hull_size.y, int(stats["occupied_cells"])],
		"",
		_instrument_section("SHIP LOAD"),
		_meter_line("Power coverage", float(powered_rooms), maxf(float(powered_rooms + underpowered_rooms), 1.0), "%d reactor fields   %d rooms low" % [reactor_fields, underpowered_rooms]),
		_meter_line("Personnel register", float(current_crew), maxf(float(stats["crew_capacity"]), 1.0), "CURRENT CREW %d   MAX CREW %d" % [current_crew, int(stats["crew_capacity"])]),
		"",
		_instrument_section("COMBAT SYSTEMS"),
		_meter_line("Shield bank", shield_capacity, 100.0, "%d reserve   %.1f/sec" % [roundi(shield_capacity), shield_regen]),
		_meter_line("Drive wake", thrust_rating, 48.0, "%d thrust   %d turn" % [roundi(thrust_rating), roundi(float(stats["maneuver_rating"]))]),
		_meter_line("Gunline", float(weapon_count), 8.0, "%d mounts   %d volley" % [weapon_count, roundi(float(stats["weapon_alpha"]))]),
		"",
		_instrument_section("SUPPORT"),
		"%s  %s  %s  %s" % [
			_status_chip("HGR %d" % hangar_capacity, hangar_capacity > 0),
			_status_chip("ENG %d" % int(stats["damage_control_channels"]), int(stats["damage_control_channels"]) > 0),
			_status_chip("MED %d" % int(stats["medical_channels"]), int(stats["medical_channels"]) > 0),
			_status_chip("SEC %d" % int(stats["security_channels"]), int(stats["security_channels"]) > 0),
		],
		"",
		"[color=#6a9d96]COMPARTMENTS[/color]  %s" % room_counts,
	])
	return "\n".join([
		"[color=#72fff0][font_size=18]ACTIVE HULL LINK[/font_size][/color]",
		"[color=#345d58]::::::::::::::::::::::::::::[/color]",
		"",
		"[color=#f2a83d]Vessel Signal[/color]",
		"[font_size=14]%s[/font_size]" % _layout_display_name(source_layout),
		"Current command ship is mirrored in the drydock bay.",
		"",
		"[color=#f2a83d]Frame Lock[/color]",
		"Build envelope  %d x %d full rooms" % [size_value.x, size_value.y],
		"Hull footprint   %d x %d occupied field" % [hull_size.x, hull_size.y],
		"",
		"[color=#f2a83d]Live Readouts[/color]",
		"Current Crew     %d" % current_crew,
		"Max Crew         %d" % int(stats["crew_capacity"]),
		"Power coverage   %d fields • %d rooms low" % [reactor_fields, underpowered_rooms],
		"Shield reserve   %d" % roundi(float(stats["shield_capacity"])),
		"Drive rating     %d" % roundi(float(stats["thrust_rating"])),
		"Weapon mounts    %d" % int(stats["weapon_count"]),
		"",
		"[color=#46fff0]Choose Edit Current Ship to bring the grid online, or start a new hull from Shipyard Command.[/color]",
	])


func _format_new_hull_terminal(size_value: Vector2i) -> String:
	size_value = _full_grid_size(size_value)
	var title := "FRAME PREVIEW" if hovered_frame_size != Vector2i.ZERO else "NEW HULL FRAME"
	var state_line := "Hover scan only - click a frame to lock it." if hovered_frame_size != Vector2i.ZERO else "No existing ship systems are connected to this channel."
	return "\n".join([
		_instrument_header(title, "empty frame authorization"),
		_status_chip("FRAME", hovered_frame_size != Vector2i.ZERO or selected_size != Vector2i.ZERO) + "  %d x %d full-room bay" % [size_value.x, size_value.y],
		"",
		_instrument_section("BUILD VOLUME"),
		_meter_line("Authorized grid", float(size_value.x * size_value.y), 256.0, "%d full grid pieces" % (size_value.x * size_value.y), 14),
		_signal_line("Starting mass", "Empty hull frame", true),
		"",
		_instrument_section("NEXT COMMAND"),
		_status_chip("NAME", true) + "  tag the hull card",
		_status_chip("SIZE", true) + "  choose a frame",
		_status_chip("CREATE", true) + "  open the grid editor",
		"",
		"[color=#46fff0]%s[/color]" % state_line,
	])
	return "\n".join([
		"[color=#72fff0][font_size=18]%s[/font_size][/color]" % title,
		"",
		"[color=#f2a83d]Drydock Envelope[/color]",
		"Frame size: %d x %d full rooms" % [size_value.x, size_value.y],
		"Build capacity: %d full grid pieces" % (size_value.x * size_value.y),
		"Initial hull mass: empty",
		"",
		"[color=#f2a83d]Next Step[/color]",
		"Name the design, choose a frame size, then create the clean hull.",
		"",
		"[color=#46fff0]%s[/color]" % state_line,
	])


func _format_archive_terminal() -> String:
	if selected_blueprint_layout != null:
		var stats := ShipBuilderAnalyzer.analyze(
			selected_blueprint_layout,
			Vector2i(int(selected_blueprint_layout.get("columns")), int(selected_blueprint_layout.get("rows")))
		)
		var reactor_fields := int(stats.get("reactor_field_count", 0))
		var powered_rooms := int(stats.get("powered_room_count", 0))
		var underpowered_rooms := int(stats.get("underpowered_room_count", 0))
		var archive_size: Vector2i = stats["build_size"]
		var archive_full_size := _full_grid_size(archive_size)
		return "\n".join([
			_instrument_header("BLUEPRINT LOCK", _layout_display_name(selected_blueprint_layout)),
			_status_chip("PREVIEW", true) + "  hull card loaded in center bay",
			"",
			_instrument_section("HULL CARD"),
			_meter_line("Frame", float(int(stats["occupied_cells"])), float(maxi(archive_size.x * archive_size.y, 1)), "%dx%d full-room bay   %d quarter cells occupied" % [
				archive_full_size.x,
				archive_full_size.y,
				int(stats["occupied_cells"]),
			], 12),
			_meter_line("Personnel register", 0.0, maxf(float(stats["crew_capacity"]), 1.0), "CURRENT CREW 0   MAX CREW %d" % int(stats["crew_capacity"])),
			_meter_line("Power coverage", float(powered_rooms), maxf(float(powered_rooms + underpowered_rooms), 1.0), "%d reactor fields   %d rooms low" % [reactor_fields, underpowered_rooms]),
			_meter_line("Weapon mounts", float(stats["weapon_count"]), 8.0, "%d hardpoints" % int(stats["weapon_count"])),
			"",
			_instrument_section("COMMIT OPTIONS"),
			_status_chip("EDIT", true) + "  open this card in the builder",
			_status_chip("PLAY", true) + "  make this the command ship",
			_status_chip("DELETE", true) + "  purge saved card",
		])
		return "\n".join([
			"[color=#72fff0][font_size=14]BLUEPRINT SELECTED[/font_size][/color]",
			"[color=#345d58]────────────────────────[/color]",
			"[color=#f2a83d]%s[/color]" % _layout_display_name(selected_blueprint_layout),
			"Frame  %dx%d   occupied %d" % [
				int(selected_blueprint_layout.get("columns")),
				int(selected_blueprint_layout.get("rows")),
				int(stats["occupied_cells"]),
			],
			"Current Crew  0",
			"Max Crew      %d" % int(stats["crew_capacity"]),
			"Power coverage  %d fields • %d rooms low" % [reactor_fields, underpowered_rooms],
			"Weapons  %d mounts" % int(stats["weapon_count"]),
			"Services  ENG %d   MED %d   SEC %d   Craft %d" % [
				int(stats["damage_control_channels"]),
				int(stats["medical_channels"]),
				int(stats["security_channels"]),
				int(stats["hangar_capacity"]),
			],
			"",
			"[color=#46fff0]Choose Edit or Play to commit this hull.[/color]",
		])
	return "\n".join([
		_instrument_header("BLUEPRINT ARCHIVE", "local shipyard index"),
		_status_chip("CATALOG", true) + "  choose a saved hull card",
		"",
		_instrument_section("PREVIEW BAY"),
		_signal_line("Protocol", "Hull cards preview before commit.", true),
		"",
		"[color=#46fff0]No blueprint selected.[/color]",
	])


func _builder_room_at_cell(cell: Vector2i) -> Resource:
	if source_layout == null:
		return null
	var definitions: Array = source_layout.get("rooms")
	for room: Resource in definitions:
		if _builder_room_cells(room).has(cell):
			return room
	return null


func _builder_room_by_id(room_id: StringName) -> Resource:
	if source_layout == null or room_id == &"":
		return null
	for room: Resource in source_layout.get("rooms"):
		if StringName(room.get("room_id")) == room_id:
			return room
	return null


func _builder_room_cells(room: Resource) -> Dictionary:
	var cells: Dictionary = {}
	if room == null:
		return cells
	var rects: Array[Rect2i] = room.get("grid_rects")
	for grid_rect: Rect2i in rects:
		for y: int in range(grid_rect.position.y, grid_rect.end.y):
			for x: int in range(grid_rect.position.x, grid_rect.end.x):
				cells[Vector2i(x, y)] = true
	return cells


func _requires_connected_live_hull() -> bool:
	return embedded_refit_mode or _uses_owned_inventory()


func _uses_owned_inventory() -> bool:
	return inventory_mode in ["STATION", "ESCAPE"]


func _builder_hull_is_connected() -> bool:
	if source_layout == null:
		return true
	var occupied: Dictionary = {}
	for room_value: Variant in source_layout.get("rooms"):
		occupied.merge(_builder_room_cells(room_value as Resource), true)
	if occupied.size() <= 1:
		return true
	var unvisited := occupied.duplicate()
	var pending: Array[Vector2i] = [Vector2i(unvisited.keys()[0])]
	unvisited.erase(pending[0])
	while not pending.is_empty():
		var cell: Vector2i = pending.pop_back()
		for connection: Dictionary in source_layout.call("get_touching_cells", cell, false):
			var neighbor := Vector2i(connection.get("cell", INVALID_CELL))
			if unvisited.has(neighbor):
				unvisited.erase(neighbor)
				pending.append(neighbor)
	return unvisited.is_empty()


func _builder_remove_cell_from_all_rooms(cell: Vector2i) -> void:
	if source_layout == null:
		return
	var definitions: Array = source_layout.get("rooms")
	for definition: Resource in definitions:
		var original_rects: Array[Rect2i] = definition.get("grid_rects")
		var updated_rects: Array[Rect2i] = []
		for grid_rect: Rect2i in original_rects:
			if grid_rect.has_point(cell):
				updated_rects.append_array(_subtract_cell(grid_rect, cell))
			else:
				updated_rects.append(grid_rect)
		definition.set("grid_rects", updated_rects)
		if updated_rects.size() != original_rects.size():
			definition.set("module_recipe", null)
	_prune_empty_builder_rooms()


func _builder_add_cell_to_room_type(room_type: String, cell: Vector2i) -> StringName:
	var definitions: Array = source_layout.get("rooms")
	var neighboring_rooms: Array[Resource] = []
	if not EXPLICIT_GROUP_ROOM_TYPES.has(room_type):
		for definition: Resource in definitions:
			if String(definition.get("type_name")) == room_type and _builder_room_touches_cell(definition, cell):
				neighboring_rooms.append(definition)
	var target_room: Resource
	if neighboring_rooms.is_empty():
		target_room = _create_builder_room_instance(room_type)
		definitions.append(target_room)
	else:
		target_room = neighboring_rooms[0]
	var target_rects: Array[Rect2i] = target_room.get("grid_rects").duplicate()
	target_rects.append(Rect2i(cell, Vector2i.ONE))
	for index: int in range(1, neighboring_rooms.size()):
		var merged_room := neighboring_rooms[index]
		target_rects.append_array(merged_room.get("grid_rects"))
		definitions.erase(merged_room)
	target_room.set("grid_rects", target_rects)
	source_layout.set("rooms", definitions)
	return target_room.get("room_id")


func _builder_room_touches_cell(room: Resource, cell: Vector2i) -> bool:
	var neighbors: Array[Dictionary] = source_layout.call("get_touching_cells", cell, false)
	var rects: Array[Rect2i] = room.get("grid_rects")
	for rect: Rect2i in rects:
		for connection: Dictionary in neighbors:
			if rect.has_point(connection["cell"]):
				return true
	return false


func _builder_grid_type_requirement_status(room_type: String, cell: Vector2i) -> Dictionary:
	if source_layout == null or cell == INVALID_CELL:
		return {"valid": true, "unmet_requirements": PackedStringArray(), "details": PackedStringArray()}
	if not source_layout.has_method("evaluate_grid_type_placement"):
		return {"valid": true, "unmet_requirements": PackedStringArray(), "details": PackedStringArray()}
	var placement_offset := Vector2.ZERO
	if _builder_room_at_cell(cell) != null:
		placement_offset = source_layout.call("get_cell_offset", cell)
	elif cell == builder_pending_add_cell:
		placement_offset = builder_pending_add_offset
	elif builder_grid != null:
		placement_offset = builder_grid.call("get_pending_placement_offset")
	return source_layout.call("evaluate_grid_type_placement", room_type, cell, placement_offset, _armed_inventory_footprint())


func _create_builder_room_instance(room_type: String) -> Resource:
	var templates: Array = source_layout.get("room_types")
	var template: Resource
	for candidate: Resource in templates:
		if String(candidate.get("type_name")) == room_type:
			template = candidate
			break
	var room_script := preload("res://scripts/resources/room_layout_data.gd")
	var room: Resource = room_script.new()
	room.set("room_id", StringName("%s_%d" % [room_type.to_snake_case(), Time.get_ticks_usec()]))
	room.set("display_name", _new_room_display_name(room_type))
	room.set("type_name", room_type)
	if template != null:
		room.set("effect_label", template.get("effect_label"))
		room.set("description", template.get("description"))
		room.set("grid_label", template.get("grid_label"))
		room.set("color", template.get("color"))
		room.set("maximum_health", template.get("maximum_health"))
		room.set("produces_output", template.get("produces_output"))
		room.set("contributes_to_hull", template.get("contributes_to_hull"))
		room.set("build_requirements", template.get("build_requirements"))
		room.set("weapon_definition", template.get("weapon_definition"))
		room.set("module_facing_quarters", template.get("module_facing_quarters"))
		room.set("module_rotation_quarters", template.get("module_rotation_quarters"))
		room.set("module_mirrored", template.get("module_mirrored"))
	room.set("grid_rects", [])
	return room


func _prune_empty_builder_rooms() -> void:
	if source_layout == null:
		return
	var definitions: Array = source_layout.get("rooms")
	for index: int in range(definitions.size() - 1, -1, -1):
		if (definitions[index] as Resource).get("grid_rects").is_empty():
			definitions.remove_at(index)
	source_layout.set("rooms", definitions)


func _builder_selected_cells_are_connected() -> bool:
	if builder_group_selection.is_empty() or source_layout == null:
		return false
	var unvisited := builder_group_selection.duplicate()
	var start_cell: Vector2i = unvisited.keys()[0]
	var pending: Array[Vector2i] = [start_cell]
	unvisited.erase(start_cell)
	while not pending.is_empty():
		var cell: Vector2i = pending.pop_back()
		for connection: Dictionary in source_layout.call("get_touching_cells", cell, false):
			var neighbor: Vector2i = connection["cell"]
			if unvisited.has(neighbor):
				unvisited.erase(neighbor)
				pending.append(neighbor)
	return unvisited.is_empty()


func _builder_complete_selected_room() -> Resource:
	if builder_group_selection.is_empty():
		return null
	var first_cell: Vector2i = builder_group_selection.keys()[0]
	var room := _builder_room_at_cell(first_cell)
	if room == null:
		return null
	var room_cells := _builder_room_cells(room)
	if room_cells.size() != builder_group_selection.size():
		return null
	for cell_value: Variant in room_cells.keys():
		if not builder_group_selection.has(cell_value):
			return null
	return room


func _builder_selection_can_merge() -> bool:
	if builder_group_selection.size() < 2:
		return false
	if not _builder_selected_cells_are_connected():
		return false
	var room_type := ""
	for cell_value: Variant in builder_group_selection.keys():
		var room := _builder_room_at_cell(cell_value)
		if room == null:
			return false
		var type_name := String(room.get("type_name"))
		if not EXPLICIT_GROUP_ROOM_TYPES.has(type_name):
			return false
		if room_type.is_empty():
			room_type = type_name
		elif type_name != room_type:
			return false
	return true


func _builder_selection_can_split() -> bool:
	if builder_group_selection.is_empty():
		return false
	var room_ids: Dictionary = {}
	for cell_value: Variant in builder_group_selection.keys():
		var room := _builder_room_at_cell(cell_value)
		if room == null:
			continue
		if _builder_room_cells(room).size() > 1:
			room_ids[room.get_instance_id()] = true
	return not room_ids.is_empty()


func _builder_selection_summary() -> String:
	if builder_group_selection.is_empty():
		return "No hull cells selected."
	var counts: Dictionary = {}
	for cell_value: Variant in builder_group_selection.keys():
		var room := _builder_room_at_cell(cell_value)
		if room == null:
			continue
		var label := _room_type_palette_name(String(room.get("type_name")))
		counts[label] = int(counts.get(label, 0)) + 1
	var parts: PackedStringArray = []
	for key: Variant in counts.keys():
		parts.append("%s ×%d" % [String(key), int(counts[key])])
	if _builder_selection_can_merge():
		return "Compatible selection: %s. Merge controls online." % "   ".join(parts)
	return "Selection scan: %s. Merge unavailable; cells must touch and share one module type." % "   ".join(parts)


func _builder_room_summary(room: Resource) -> String:
	if room == null:
		return "No compartment selected."
	var cells := _builder_room_cells(room)
	var type_name := String(room.get("type_name"))
	var facing := int(room.get("module_facing_quarters"))
	var facing_text := _rotation_name(facing) if facing >= 0 else "auto"
	var lines: PackedStringArray = [
		"%s selected." % _room_type_palette_name(type_name),
		"Footprint: %d cell%s." % [cells.size(), "" if cells.size() == 1 else "s"],
	]
	if EXPLICIT_GROUP_ROOM_TYPES.has(type_name):
		lines.append("Facing: %s. Direction controls available." % facing_text)
		if type_name in ["WEAPONS", "SHIELDS"]:
			var exposed_faces := GRID_GEOMETRY.room_exposed_quarters(source_layout, room)
			lines.append("Hull exposure: %d face%s%s." % [
				exposed_faces.size(),
				"" if exposed_faces.size() == 1 else "s",
				" — BLOCKED" if exposed_faces.is_empty() else "",
			])
	else:
		lines.append("No directional controls for this compartment type.")
	return " ".join(lines)


func _subtract_cell(grid_rect: Rect2i, cell: Vector2i) -> Array[Rect2i]:
	var pieces: Array[Rect2i] = []
	var top_height := cell.y - grid_rect.position.y
	if top_height > 0:
		pieces.append(Rect2i(grid_rect.position, Vector2i(grid_rect.size.x, top_height)))
	var bottom_y := cell.y + 1
	var bottom_height := grid_rect.end.y - bottom_y
	if bottom_height > 0:
		pieces.append(Rect2i(Vector2i(grid_rect.position.x, bottom_y), Vector2i(grid_rect.size.x, bottom_height)))
	var left_width := cell.x - grid_rect.position.x
	if left_width > 0:
		pieces.append(Rect2i(Vector2i(grid_rect.position.x, cell.y), Vector2i(left_width, 1)))
	var right_x := cell.x + 1
	var right_width := grid_rect.end.x - right_x
	if right_width > 0:
		pieces.append(Rect2i(Vector2i(right_x, cell.y), Vector2i(right_width, 1)))
	return pieces


func _room_type_palette_name(room_type: String) -> String:
	return GridInventoryCatalogScript.palette_name(room_type)


func _new_room_display_name(room_type: String) -> String:
	match room_type:
		"COMMAND":
			return "BRIDGE"
		"PROPULSION":
			return "THRUSTER SECTION"
		"WEAPONS":
			return "WEAPON SECTION"
		"UNASSIGNED":
			return "UNASSIGNED COMPARTMENT"
		"SHIELDS":
			return "DIRECTIONAL SHIELD ARRAY"
		"POWER":
			return "REACTOR"
		"HANGAR":
			return "HANGAR"
	return _room_type_palette_name(room_type).to_upper()


func _rotation_name(rotation_quarters: int) -> String:
	match posmod(rotation_quarters, 4):
		1:
			return "starboard"
		2:
			return "aft"
		3:
			return "port"
		_:
			return "bow"


func _format_stats(stats: Dictionary) -> String:
	var size_value := _full_grid_size(Vector2i(stats["build_size"]))
	var hull_size: Vector2i = stats["hull_size"]
	var weapon_families := _format_counts(stats["weapon_families"])
	var room_counts := _format_counts(stats["room_counts"])
	var reactor_fields := int(stats.get("reactor_field_count", 0))
	var powered_rooms := int(stats.get("powered_room_count", 0))
	var underpowered_rooms := int(stats.get("underpowered_room_count", 0))
	var current_crew := int(_builder_live_crew_counts().get("total", 0))
	return "\n".join([
		_instrument_header("ACTIVE HULL LINK", _layout_display_name(source_layout)),
		_status_chip("MIRROR", true) + "  command ship linked",
		"",
		_instrument_section("FRAME LOCK"),
		_meter_line("Envelope", float(size_value.x * size_value.y), float(size_value.x * size_value.y), "%d x %d full rooms" % [size_value.x, size_value.y]),
		"[color=#6a9d96]Hull footprint[/color]  %d x %d occupied field" % [hull_size.x, hull_size.y],
		"",
		_instrument_section("LIVE SHIP PULSE"),
		_meter_line("Personnel register", float(current_crew), maxf(float(stats["crew_capacity"]), 1.0), "CURRENT CREW %d   MAX CREW %d" % [current_crew, int(stats["crew_capacity"])]),
		_meter_line("Power coverage", float(powered_rooms), maxf(float(powered_rooms + underpowered_rooms), 1.0), "%d reactor fields   %d rooms low" % [reactor_fields, underpowered_rooms]),
		_meter_line("Shield reserve", float(stats["shield_capacity"]), 100.0, "%d banked" % roundi(float(stats["shield_capacity"]))),
		_meter_line("Drive rating", float(stats["thrust_rating"]), 48.0, "%d thrust" % roundi(float(stats["thrust_rating"]))),
		_meter_line("Weapon mounts", float(stats["weapon_count"]), 8.0, "%d linked" % int(stats["weapon_count"])),
		"",
		"[color=#46fff0]Open Edit to work the grid.[/color]",
	])
	return "\n".join([
		"[color=#72fff0][font_size=14]VESSEL DOSSIER[/font_size][/color]",
		"[color=#345d58]────────────────────────[/color]",
		"[color=#f2a83d]FRAME[/color]  %d×%d envelope   %d occupied" % [size_value.x, size_value.y, int(stats["occupied_cells"])],
		"Footprint   %d×%d hull cells" % [hull_size.x, hull_size.y],
		"",
		"[color=#f2a83d]PERSONNEL REGISTER[/color]   CURRENT CREW %d   MAX CREW %d" % [current_crew, int(stats["crew_capacity"])],
		"[color=#f2a83d]POWER[/color]  %d reactor fields   %d rooms covered   %d low" % [reactor_fields, powered_rooms, underpowered_rooms],
		"[color=#f2a83d]SHIELD[/color] reserve %d   regen %.1f/s" % [roundi(float(stats["shield_capacity"])), float(stats["shield_regen"])],
		"[color=#f2a83d]DRIVE[/color]  thrust %d   maneuver %d" % [roundi(float(stats["thrust_rating"])), roundi(float(stats["maneuver_rating"]))],
		"",
		"[color=#f2a83d]WEAPONS[/color] mounts %d   volley %d" % [int(stats["weapon_count"]), roundi(float(stats["weapon_alpha"]))],
		"Sustained %.1f/s   reach %d" % [float(stats["weapon_dps"]), roundi(float(stats["weapon_range"]))],
		"Families   %s" % weapon_families,
		"",
		"[color=#f2a83d]SERVICES[/color] engineering %d   medical %d   security %d   craft %d" % [
			int(stats["damage_control_channels"]),
			int(stats["medical_channels"]),
			int(stats["security_channels"]),
			int(stats["hangar_capacity"]),
		],
		"",
		"[color=#f2a83d]COMPARTMENTS[/color]",
		room_counts,
	])


func _format_selected_room_scan(room: Resource) -> String:
	return _format_selected_room_card(room)
	var room_type := String(room.get("type_name"))
	var cell_count := _builder_room_cells(room).size()
	var recipe: Resource = room.get("module_recipe")
	var minimum_crew := int(room.get("minimum_crew"))
	var optimal_crew := int(room.get("optimal_crew"))
	if recipe != null:
		minimum_crew = maxi(minimum_crew, int(recipe.get("minimum_crew")))
		optimal_crew = maxi(optimal_crew, int(recipe.get("optimal_crew")))
	var staffing := ROOM_STAFFING_RULES.effective_requirements(room, minimum_crew, optimal_crew)
	minimum_crew = staffing.x
	optimal_crew = staffing.y
	var lines: PackedStringArray = [
		"[color=#72fff0][font_size=14]COMPARTMENT SCAN[/font_size][/color]",
		"[color=#345d58]────────────────────────[/color]",
		"[color=#f2a83d]%s[/color]" % String(room.get("display_name")).to_upper(),
		"%s grid" % _room_type_palette_name(room_type),
		"",
		"[color=#f2a83d]FOOTPRINT[/color]",
		"%d occupied cell%s" % [cell_count, "" if cell_count == 1 else "s"],
		"Facing: %s" % (_rotation_name(int(room.get("module_facing_quarters"))) if int(room.get("module_facing_quarters")) >= 0 else "auto"),
		"Structure: %d integrity" % roundi(float(room.get("maximum_health"))),
		"",
		"[color=#f2a83d]CREW STATIONS[/color]",
		"Minimum watch: %d" % minimum_crew,
		"Optimal watch: %d" % maxi(optimal_crew, minimum_crew),
		"",
		"[color=#f2a83d]POWER PROFILE[/color]",
		_room_power_profile(room, cell_count),
	]
	var scan_output_lines := _room_output_profile(room, cell_count)
	if not scan_output_lines.is_empty():
		lines.append("")
		lines.append("[color=#f2a83d]SYSTEM OUTPUT[/color]")
		lines.append_array(scan_output_lines)
	var requirement_lines := _room_build_requirement_lines(room)
	if not requirement_lines.is_empty():
		lines.append("")
		lines.append("[color=#f2a83d]BUILD ACCESS[/color]")
		lines.append_array(requirement_lines)
	var connection_lines := _room_connection_lines(room)
	if not connection_lines.is_empty():
		lines.append("")
		lines.append("[color=#f2a83d]LOCAL CONTACTS[/color]")
		lines.append_array(connection_lines)
	var effect_lines := _room_adjacency_effect_lines(room)
	if not effect_lines.is_empty():
		lines.append("")
		lines.append("[color=#f2a83d]GRID INFLUENCE[/color]")
		lines.append_array(effect_lines)
	if recipe != null:
		lines.append("")
		lines.append("[color=#f2a83d]INSTALLED MODULE[/color]")
		lines.append(String(recipe.get("display_name")))
		var costs: PackedStringArray = recipe.call("formatted_construction_costs")
		if not costs.is_empty():
			lines.append("Build cost: %s" % ", ".join(costs))
	return "\n".join(lines)


func _format_selected_room_card(room: Resource) -> String:
	var room_type := String(room.get("type_name"))
	var cell_count := _builder_room_cells(room).size()
	var recipe: Resource = room.get("module_recipe")
	var minimum_crew := int(room.get("minimum_crew"))
	var optimal_crew := int(room.get("optimal_crew"))
	if recipe != null:
		minimum_crew = maxi(minimum_crew, int(recipe.get("minimum_crew")))
		optimal_crew = maxi(optimal_crew, int(recipe.get("optimal_crew")))
	var staffing := ROOM_STAFFING_RULES.effective_requirements(room, minimum_crew, optimal_crew)
	minimum_crew = staffing.x
	optimal_crew = staffing.y
	var facing_quarters := int(room.get("module_facing_quarters"))
	var facing_name := _rotation_name(facing_quarters) if facing_quarters >= 0 else "AUTO"
	var structure_rating := roundi(float(room.get("maximum_health")))
	var crew_capacity := maxi(optimal_crew, minimum_crew)
	var crew_operating := 0
	var crew := get_tree().get_first_node_in_group("crew_simulation")
	if inventory_mode != "FORGE" and is_instance_valid(crew) and crew.has_method("get_room_staffing"):
		crew_operating = int(crew.call("get_room_staffing", StringName(room.get("room_id"))))
	var ship_stats := ShipBuilderAnalyzer.analyze(source_layout, selected_size) if source_layout != null else {}
	var eventual_crew_available := int(ship_stats.get("crew_capacity", 0)) >= int(ship_stats.get("optimal_crew", 0))
	if not embedded_refit_mode and eventual_crew_available:
		crew_operating = crew_capacity
	var has_direction := EXPLICIT_GROUP_ROOM_TYPES.has(room_type)
	var power_profile := _room_power_profile(room, cell_count)
	var requirement_lines := _room_build_requirement_lines(room)
	var connection_lines := _room_connection_lines(room)
	var effect_lines := _room_adjacency_effect_lines(room)
	var room_title := String(room.get("display_name")).to_upper()
	var room_family := _room_type_palette_name(room_type).to_upper()
	var live_output_lines := _room_output_profile(room, cell_count)
	var room_status := "VECTOR LOCKED" if has_direction else "PASSIVE MODULE"
	var install_clearance := "OPEN INSTALL" if requirement_lines.is_empty() or requirement_lines[0].contains("Open install") else "CHECK REQUIRED"
	var live_lines: PackedStringArray = [
		_instrument_header("COMPARTMENT LINK", "live room card"),
		_status_chip(room_family, true) + "  [color=#f2a83d][font_size=13]%s[/font_size][/color]" % room_title,
		_status_chip("FACING", has_direction) + "  %s" % facing_name,
		_status_chip("BUILD", install_clearance == "OPEN INSTALL") + "  %s" % install_clearance,
		"",
		_instrument_section("ROOM SILHOUETTE"),
		_meter_line("Footprint", float(cell_count), float(maxi(cell_count, 1)), "%d cell%s" % [cell_count, "" if cell_count == 1 else "s"], 10),
		_meter_line("Hull integrity", float(structure_rating), float(maxi(structure_rating, 1)), "%d structure" % structure_rating, 12),
		"[color=#6a9d96]Module state[/color]  %s" % room_status,
		"",
		_instrument_section("CREW JACKS"),
		_meter_line("Watch floor", float(minimum_crew), float(maxi(crew_capacity, 1)), "%d crew required" % minimum_crew, 10),
		_meter_line("Full station", float(crew_capacity), float(maxi(crew_capacity, 1)), "%d crew optimal" % crew_capacity, 10),
		CREW_REQUIREMENT_DISPLAY.status_bbcode(crew_capacity, crew_operating, eventual_crew_available) + "  [color=#6a9d96]%s[/color]" % CREW_REQUIREMENT_DISPLAY.plain_text(crew_capacity, crew_operating, eventual_crew_available),
		"",
		_instrument_section("POWER FIELD"),
		_signal_line("Feed", power_profile, not power_profile.begins_with("No active")),
	]
	if room_type in ["WEAPONS", "SHIELDS"]:
		var exposed_faces := GRID_GEOMETRY.room_exposed_quarters(source_layout, room)
		var coverage_count := exposed_faces.size()
		if room_type == "WEAPONS":
			coverage_count = GRID_GEOMETRY.weapon_coverage_quarters(source_layout, room, room.get("weapon_definition")).size()
		live_lines.append("")
		live_lines.append(_instrument_section("EXTERNAL APERTURE"))
		live_lines.append(_signal_line("Hull faces", "%d exposed" % exposed_faces.size(), not exposed_faces.is_empty()))
		live_lines.append(_signal_line("Coverage", "%d active arc%s" % [coverage_count, "" if coverage_count == 1 else "s"], coverage_count > 0))
		if exposed_faces.is_empty():
			live_lines.append("[color=#ff4b2b]BLOCKED • MOVE MODULE TO AN OUTER HULL EDGE[/color]")
	if not live_output_lines.is_empty():
		live_lines.append("")
		live_lines.append(_instrument_section("SYSTEM PAYOFF"))
		for output_line: String in live_output_lines:
			live_lines.append(_signal_line("Output", output_line, true))
	if not connection_lines.is_empty():
		live_lines.append("")
		live_lines.append(_instrument_section("CONTACT MAP"))
		live_lines.append_array(_compartment_contact_map(room))
	if not effect_lines.is_empty():
		live_lines.append("")
		live_lines.append(_instrument_section("GRID INFLUENCE"))
		for effect_line: String in effect_lines:
			live_lines.append(_signal_line("Influence", effect_line, not effect_line.begins_with("No ")))
	if recipe != null:
		live_lines.append("")
		live_lines.append(_instrument_section("INSTALLED HARDWARE"))
		live_lines.append(_status_chip("MOUNTED", true) + "  %s" % String(recipe.get("display_name")))
		var costs: PackedStringArray = recipe.call("formatted_construction_costs")
		if not costs.is_empty():
			live_lines.append("[color=#6a9d96]Fabrication[/color]  %s" % ", ".join(costs))
	live_lines.append("")
	live_lines.append("[color=#46fff0]Select another cell to retune.[/color]")
	return "\n".join(live_lines)
	var lines: PackedStringArray = [
		"[color=#72fff0][font_size=15]DIAGNOSTIC SCAN[/font_size][/color]",
		"[color=#1f5e57]SCANLINE ===================[/color]",
		"%s  [color=#f2a83d][font_size=13]%s[/font_size][/color]" % [
			_diagnostic_chip("LINKED", true),
			String(room.get("display_name")).to_upper(),
		],
		"[color=#7ffff4]%s NODE[/color]   %s" % [
			_room_type_palette_name(room_type).to_upper(),
			_diagnostic_chip("DIRECTIONAL" if has_direction else "PASSIVE", has_direction),
		],
		"",
		_diagnostic_section("FRAME MATRIX"),
		_scan_row("Hull footprint", float(cell_count), float(maxi(cell_count, 1)), "%d cell%s" % [cell_count, "" if cell_count == 1 else "s"], 10),
		_scan_row("Structure", float(structure_rating), float(maxi(structure_rating, 1)), "%d integrity" % structure_rating, 12),
		_signal_row("Facing vector", facing_name, has_direction),
		"",
		_diagnostic_section("CREW SOCKETS"),
		_scan_row("Minimum watch", float(minimum_crew), float(maxi(crew_capacity, 1)), "%d required" % minimum_crew, 10),
		_scan_row("Optimal watch", float(crew_capacity), float(maxi(crew_capacity, 1)), "%d ideal" % crew_capacity, 10),
		"",
		_diagnostic_section("POWER TRACE"),
		_signal_row("Power profile", power_profile, not power_profile.begins_with("No active")),
	]
	var output_lines := _room_output_profile(room, cell_count)
	if not output_lines.is_empty():
		lines.append("")
		lines.append(_diagnostic_section("SYSTEM RESPONSE"))
		for output_line: String in output_lines:
			lines.append(_signal_row("Output", output_line, true))
	if not requirement_lines.is_empty():
		lines.append("")
		lines.append(_diagnostic_section("INSTALL CLEARANCE"))
		for requirement_line: String in requirement_lines:
			lines.append(_requirement_scan_row(requirement_line))
	if not connection_lines.is_empty():
		lines.append("")
		lines.append(_diagnostic_section("ADJACENT CONTACTS"))
		for connection_line: String in connection_lines:
			lines.append(_signal_row("Edge contact", connection_line, not connection_line.begins_with("No ")))
	if not effect_lines.is_empty():
		lines.append("")
		lines.append(_diagnostic_section("GRID INFLUENCE"))
		for effect_line: String in effect_lines:
			lines.append(_signal_row("Influence", effect_line, not effect_line.begins_with("No ")))
	if recipe != null:
		lines.append("")
		lines.append(_diagnostic_section("INSTALLED HARDWARE"))
		lines.append(_signal_row("Module", String(recipe.get("display_name")), true))
		var costs: PackedStringArray = recipe.call("formatted_construction_costs")
		if not costs.is_empty():
			lines.append(_signal_row("Fabrication", ", ".join(costs), true))
	lines.append("")
	lines.append("[color=#46fff0]Live scan. Select another cell to retune.[/color]")
	return "\n".join(lines)


func _format_group_selection_card() -> String:
	var counts: Dictionary = {}
	var room_count := 0
	var room_ids: Dictionary = {}
	for cell_value: Variant in builder_group_selection.keys():
		var room := _builder_room_at_cell(cell_value)
		if room == null:
			continue
		var type_label := _room_type_palette_name(String(room.get("type_name")))
		counts[type_label] = int(counts.get(type_label, 0)) + 1
		var room_key := room.get_instance_id()
		if not room_ids.has(room_key):
			room_ids[room_key] = true
			room_count += 1
	var type_lines := PackedStringArray()
	for key: Variant in counts.keys():
		type_lines.append(_signal_row(String(key), "x%d contact%s" % [int(counts[key]), "" if int(counts[key]) == 1 else "s"], true))
	if type_lines.is_empty():
		type_lines.append(_signal_row("Cell families", "No occupied hull cells in selection", false))
	var can_merge := _builder_selection_can_merge()
	var can_split := _builder_selection_can_split()
	var merge_reason := "Cells touch by edges and share a compatible module type." if can_merge else _builder_merge_block_reason()
	var sweep_lines: PackedStringArray = [
		_instrument_header("CONTACT SWEEP", "drag-selection channel"),
		_status_chip("MERGE", can_merge) + "  %s" % ("ready" if can_merge else "locked"),
		_status_chip("SPLIT", can_split) + "  %s" % ("ready" if can_split else "standby"),
		"",
		_instrument_section("SELECTION GHOST"),
		_meter_line("Cells held", float(builder_group_selection.size()), float(maxi(builder_group_selection.size(), 1)), "%d selected" % builder_group_selection.size(), 10),
		_meter_line("Room links", float(room_count), float(maxi(builder_group_selection.size(), 1)), "%d compartments" % room_count, 10),
		"",
		_instrument_section("FAMILY RETURN"),
	]
	sweep_lines.append_array(type_lines)
	sweep_lines.append("")
	sweep_lines.append(_instrument_section("LINK DECISION"))
	sweep_lines.append(_signal_line("Merge report", merge_reason, can_merge))
	sweep_lines.append(_signal_line("Split report", "Grouped module can separate into single-cell compartments." if can_split else "No grouped module in selection.", can_split))
	sweep_lines.append("")
	sweep_lines.append("[color=#46fff0]Drag cells to sweep. Clear drops signal.[/color]")
	return "\n".join(sweep_lines)
	var lines: PackedStringArray = [
		"[color=#72fff0][font_size=15]SELECTION DIAGNOSTIC[/font_size][/color]",
		"[color=#1f5e57]CONTACT SWEEP ===============[/color]",
		_diagnostic_section("DRYDOCK CONTACTS"),
		_scan_row("Selected cells", float(builder_group_selection.size()), float(maxi(builder_group_selection.size(), 1)), "%d locked" % builder_group_selection.size(), 10),
		_scan_row("Compartments", float(room_count), float(maxi(builder_group_selection.size(), 1)), "%d detected" % room_count, 10),
		"",
		_diagnostic_section("CELL FAMILIES"),
	]
	lines.append_array(type_lines)
	lines.append("")
	lines.append(_diagnostic_section("MODULE CHANNELS"))
	lines.append(_signal_row("Merge channel", "AVAILABLE" if can_merge else "LOCKED", can_merge))
	lines.append(_signal_row("Split channel", "AVAILABLE" if can_split else "STANDBY", can_split))
	lines.append("")
	lines.append(_diagnostic_section("MERGE ANALYSIS"))
	lines.append(_signal_row("Report", merge_reason, can_merge))
	lines.append("")
	lines.append("[color=#46fff0]Drag occupied cells to retune the sweep. Clear returns the console to standby.[/color]")
	return "\n".join(lines)


func _builder_merge_block_reason() -> String:
	if builder_group_selection.size() < 2:
		return "Select at least two occupied cells."
	if not _builder_selected_cells_are_connected():
		return "Selected cells must touch by edges."
	var room_type := ""
	for cell_value: Variant in builder_group_selection.keys():
		var room := _builder_room_at_cell(cell_value)
		if room == null:
			return "Selection includes empty hull space."
		var type_name := String(room.get("type_name"))
		if not EXPLICIT_GROUP_ROOM_TYPES.has(type_name):
			return "%s cells cannot currently form explicit modules." % _room_type_palette_name(type_name)
		if room_type.is_empty():
			room_type = type_name
		elif type_name != room_type:
			return "Selected cells must share one module family."
	return "Selection is not eligible for merge."


func _scan_bar(current: float, maximum: float, blocks: int) -> String:
	var safe_maximum := maxf(maximum, 0.001)
	var filled := clampi(roundi((current / safe_maximum) * float(blocks)), 0, blocks)
	var empty := maxi(blocks - filled, 0)
	return "[color=#56ffb0]%s[/color][color=#143b36]%s[/color]" % [
		_repeat_glyph("█", filled),
		_repeat_glyph("░", empty),
	]


func _repeat_glyph(glyph: String, count: int) -> String:
	var pieces := PackedStringArray()
	for index: int in range(maxi(count, 0)):
		pieces.append(glyph)
	return "".join(pieces)


func _ascii_scan_bar(current: float, maximum: float, blocks: int) -> String:
	var safe_maximum := maxf(maximum, 0.001)
	var filled := clampi(roundi((current / safe_maximum) * float(blocks)), 0, blocks)
	var empty := maxi(blocks - filled, 0)
	return "[color=#56ffb0]%s[/color][color=#143b36]%s[/color]" % [
		_repeat_glyph("|", filled),
		_repeat_glyph(".", empty),
	]


func _scan_row(label: String, current: float, maximum: float, value_text: String, blocks := 10) -> String:
	var safe_maximum := maxf(maximum, 0.001)
	var percent := clampf(current / safe_maximum, 0.0, 1.0)
	var color := "#56ffb0"
	if percent < 0.34:
		color = "#ff6b4a"
	elif percent < 0.67:
		color = "#f2a83d"
	return "[color=#6a9d96]%s[/color]\n  [%s] [color=%s]%03d%%[/color]  [color=#ffffff]%s[/color]" % [
		label.to_upper(),
		_ascii_scan_bar(current, safe_maximum, blocks),
		color,
		roundi(percent * 100.0),
		value_text,
	]


func _signal_row(label: String, value_text: String, online: bool) -> String:
	return "%s [color=#6a9d96]%s[/color]\n  [color=#ffffff]%s[/color]" % [
		_diagnostic_chip("ONLINE" if online else "NO LINK", online),
		label.to_upper(),
		value_text,
	]


func _requirement_scan_row(requirement_line: String) -> String:
	var online := requirement_line.contains("ONLINE") or requirement_line.contains("Open install")
	var clean_line := requirement_line
	clean_line = clean_line.replace("[color=#56ffb0]ONLINE[/color]", "ONLINE")
	clean_line = clean_line.replace("[color=#ff9966]LOCKED[/color]", "LOCKED")
	return _signal_row("Build access", clean_line, online)


func _diagnostic_chip(label: String, online: bool) -> String:
	var color := "#56ffb0" if online else "#ff9966"
	return "[color=%s][ %s ][/color]" % [color, label]


func _diagnostic_section(title: String) -> String:
	return "[color=#1f5e57]-- %s --[/color]" % title


func _instrument_header(title: String, subtitle: String = "") -> String:
	var lines: PackedStringArray = [
		"[color=#72fff0][font_size=16]%s[/font_size][/color]" % title,
		"[color=#1f5e57]SIGNAL =====================[/color]",
	]
	if not subtitle.strip_edges().is_empty():
		lines.append("[color=#46fff0]%s[/color]" % subtitle)
	return "\n".join(lines)


func _instrument_section(title: String) -> String:
	return "[color=#f2a83d]%s[/color]\n[color=#1f5e57]------------------------[/color]" % title


func _status_chip(label: String, online: bool) -> String:
	var color := "#56ffb0" if online else "#ff9966"
	var fill := "LIVE" if online else "WAIT"
	return "[color=%s][%s:%s][/color]" % [color, fill, label]


func _meter_line(label: String, current: float, maximum: float, value_text: String, blocks := 12) -> String:
	var safe_maximum := maxf(absf(maximum), 0.001)
	var ratio := clampf(current / safe_maximum, 0.0, 1.0)
	var color := "#56ffb0"
	if ratio < 0.25:
		color = "#ff6b4a"
	elif ratio < 0.6:
		color = "#f2a83d"
	return "[color=#6a9d96]%s[/color]\n  %s  [color=%s]%s[/color]" % [
		label,
		_ascii_scan_bar(current, safe_maximum, blocks),
		color,
		value_text,
	]


func _signal_line(label: String, value_text: String, online: bool) -> String:
	return "%s  [color=#6a9d96]%s[/color]\n  [color=#ffffff]%s[/color]" % [
		_status_chip(label.to_upper(), online),
		label,
		value_text,
	]


func _compartment_contact_map(room: Resource) -> PackedStringArray:
	var lines: PackedStringArray = []
	if source_layout == null:
		lines.append(_signal_line("Contact", "No drydock link", false))
		return lines
	var counts: Dictionary = {}
	var total_edges := 0
	for connection: Dictionary in source_layout.call("get_section_connections", room, false):
		var neighbor: Resource = connection["section"]
		var label := _room_type_palette_name(String(neighbor.get("type_name")))
		counts[label] = int(counts.get(label, 0)) + int(connection.get("shared_edges", 1))
		total_edges += int(connection.get("shared_edges", 1))
	if counts.is_empty():
		lines.append(_signal_line("Edge contact", "Isolated compartment skin", false))
		return lines
	lines.append(_meter_line("Shared edges", float(total_edges), 8.0, "%d wall contact%s" % [total_edges, "" if total_edges == 1 else "s"], 8))
	for key: Variant in counts.keys():
		lines.append(_status_chip(String(key).to_upper(), true) + "  %s x%d" % [String(key), int(counts[key])])
	return lines


func _room_power_profile(room: Resource, cell_count: int) -> String:
	var delta := ShipBuilderAnalyzer.room_power_delta(String(room.get("type_name")), cell_count, room)
	if delta.x > 0.0:
		return "POWER • REACTOR FIELD SOURCE"
	if delta.y > 0.0:
		var required := maxi(roundi(delta.y), 1)
		var supplied := 0.0
		if source_layout != null:
			var report := ShipBuilderAnalyzer.power_network_report(source_layout)
			var room_id: StringName = room.get("room_id")
			required = int((report.get("room_requirements", {}) as Dictionary).get(room_id, required))
			supplied = float((report.get("room_coverage", {}) as Dictionary).get(room_id, 0.0))
		return "%s  [color=#6a9d96]%s[/color]" % [
			POWER_REQUIREMENT_DISPLAY.bbcode(required, supplied),
			POWER_REQUIREMENT_DISPLAY.plain_text(required, supplied),
		]
	return "POWER • PASSIVE"


func _room_output_profile(room: Resource, cell_count: int) -> PackedStringArray:
	var lines: PackedStringArray = []
	match String(room.get("type_name")):
		"CREW", "CREW_QUARTERS":
			lines.append("Living capacity: %d crew" % (cell_count * ShipBuilderAnalyzer.CREW_CAPACITY_PER_QUARTERS_CELL))
		"REACTOR", "POWER", "ENGINE":
			lines.append("Power coverage: unlimited inside reactor radius")
		"SHIELDS":
			lines.append("Shield reserve: %d" % roundi(float(cell_count) * 55.0))
			lines.append("Shield recovery: %.1f per second" % (float(cell_count) * 0.75))
		"PROPULSION":
			lines.append("Thrust rating: %d" % roundi(float(cell_count) * 12.0))
		"WEAPONS":
			var weapon: Resource = room.get("weapon_definition")
			if weapon != null:
				lines.append("Weapon: %s" % String(weapon.get("display_name")))
				lines.append("Damage: %d   Reload: %.1fs" % [roundi(float(weapon.get("damage"))), float(weapon.get("reload_seconds"))])
				lines.append("Range: %d" % roundi(float(weapon.get("maximum_range"))))
			else:
				lines.append("Unconfigured hardpoint")
		"HANGAR":
			lines.append("Craft capacity: %d" % (cell_count * 4))
		"WORKSHOP":
			lines.append("Damage-control outfitting: %d simultaneous crews" % cell_count)
			lines.append("Provides repair tools and environmental gear")
		"MEDICAL":
			lines.append("Medical treatment channels: %d" % cell_count)
		"SECURITY":
			lines.append("Security response channels: %d" % cell_count)
		"SUPPLY_STORAGE", "CARGO":
			lines.append("Legacy grid: counted ship inventory is retired")
	return lines


func _room_build_requirement_lines(room: Resource) -> PackedStringArray:
	var lines: PackedStringArray = []
	var template := _builder_room_type_template(String(room.get("type_name")))
	if template == null:
		return lines
	var requirements: Array = template.get("build_requirements")
	if requirements.is_empty():
		lines.append("Open install")
		return lines
	for requirement: Resource in requirements:
		if requirement == null:
			continue
		var status: Dictionary = source_layout.call("evaluate_grid_type_placement", String(room.get("type_name")), _first_builder_room_cell(room))
		var prefix := "[color=#56ffb0]ONLINE[/color]" if bool(status["valid"]) else "[color=#ff9966]LOCKED[/color]"
		lines.append("%s  %s" % [prefix, requirement.call("requirement_summary")])
	return lines


func _room_connection_lines(room: Resource) -> PackedStringArray:
	var lines: PackedStringArray = []
	if source_layout == null:
		return lines
	var counts: Dictionary = {}
	for connection: Dictionary in source_layout.call("get_section_connections", room, false):
		var neighbor: Resource = connection["section"]
		var label := _room_type_palette_name(String(neighbor.get("type_name")))
		counts[label] = int(counts.get(label, 0)) + 1
	if counts.is_empty():
		lines.append("No edge contacts")
		return lines
	for key: Variant in counts.keys():
		lines.append("%s x%d" % [String(key), int(counts[key])])
	return lines


func _room_adjacency_effect_lines(room: Resource) -> PackedStringArray:
	var lines: PackedStringArray = []
	if source_layout == null or not source_layout.has_method("collect_adjacency_effects"):
		return lines
	for entry: Dictionary in source_layout.call("collect_adjacency_effects"):
		var source: Resource = entry["source"]
		var target: Resource = entry["target"]
		if source != room and target != room:
			continue
		var effect: Resource = entry["effect"]
		var direction := "receives from" if target == room else "projects to"
		var other: Resource = source if target == room else target
		lines.append("%s %s %s  x%.1f" % [
			String(effect.get("display_name")),
			direction,
			_room_type_palette_name(String(other.get("type_name"))),
			float(entry["stacks"]),
		])
	if lines.is_empty():
		lines.append("No active grid influence")
	return lines


func _builder_room_type_template(room_type: String) -> Resource:
	if source_layout == null:
		return null
	for template: Resource in source_layout.get("room_types"):
		if String(template.get("type_name")) == room_type:
			return template
	return null


func _first_builder_room_cell(room: Resource) -> Vector2i:
	for cell_value: Variant in _builder_room_cells(room).keys():
		return cell_value
	return INVALID_CELL


func _weapon_energy_estimate_for_scan(weapon: Resource) -> float:
	match String(weapon.get("weapon_family")):
		"LASER":
			return 18.0
		"ENERGY":
			return 26.0
		"MISSILE":
			return 8.0
		"BALLISTIC":
			return 10.0
		_:
			return 12.0


func _format_counts(counts: Dictionary) -> String:
	if counts.is_empty():
		return "NONE"
	var parts: PackedStringArray = []
	for key: Variant in counts.keys():
		parts.append("%s ×%d" % [_room_type_palette_name(String(key)), int(counts[key])])
	return "   ".join(parts)


func _layout_display_name(layout: Resource) -> String:
	if layout == null:
		return ""
	var design_name := String(layout.get("design_name")).strip_edges()
	if not design_name.is_empty():
		return design_name
	if not layout.resource_path.is_empty():
		return layout.resource_path.get_file().get_basename().capitalize()
	return "Unnamed Hull"


func _safe_file_stem(raw_name: String) -> String:
	var result := raw_name.strip_edges().to_lower()
	var safe := PackedStringArray()
	for index: int in range(result.length()):
		var character := result[index]
		var is_letter := character >= "a" and character <= "z"
		var is_number := character >= "0" and character <= "9"
		if is_letter or is_number:
			safe.append(character)
		elif character == " " or character == "-" or character == "_":
			safe.append("_")
	var stem := "".join(safe)
	while stem.contains("__"):
		stem = stem.replace("__", "_")
	stem = stem.trim_prefix("_").trim_suffix("_")
	return stem if not stem.is_empty() else "unnamed_hull"


func _ensure_blueprint_directory() -> void:
	if DirAccess.dir_exists_absolute(BLUEPRINT_DIRECTORY):
		return
	var root := DirAccess.open("res://")
	if root != null:
		root.make_dir_recursive("resources/ship_designs")


func _select_blueprint_path(path: String) -> void:
	selected_blueprint_path = path
	selected_blueprint_layout = ResourceLoader.load(path) if not path.is_empty() else null
	for card: PanelContainer in blueprint_cards:
		_update_blueprint_card_style(card)
	_update_blueprint_selection_readout()


func _update_blueprint_selection_readout() -> void:
	var display_name := "No blueprint selected."
	var button_name := "OPEN BLUEPRINT CATALOG"
	if selected_blueprint_layout != null:
		var layout_name := _layout_display_name(selected_blueprint_layout)
		display_name = "Selected Blueprint: %s" % layout_name
		button_name = "BLUEPRINT: %s" % layout_name.to_upper()
	elif not selected_blueprint_path.is_empty():
		var file_name := selected_blueprint_path.get_file().get_basename().capitalize()
		display_name = "Selected Blueprint: %s" % file_name
		button_name = "BLUEPRINT: %s" % file_name.to_upper()
	if blueprint_selection_label != null:
		blueprint_selection_label.text = display_name
	if open_catalog_button != null:
		open_catalog_button.text = button_name
	var has_selection := selected_blueprint_layout != null or not selected_blueprint_path.is_empty()
	if load_actions_section != null:
		var was_visible := load_actions_section.visible
		load_actions_section.visible = has_selection
		if has_selection and not was_visible:
			_pulse_control(load_actions_section, Color(0.75, 1.35, 1.22, 1.0), 1.02)
	for button: Button in [edit_blueprint_button, play_blueprint_button, delete_blueprint_button]:
		if button != null:
			button.disabled = not has_selection


func _open_blueprint_catalog() -> void:
	if blueprint_catalog_panel == null:
		return
	_refresh_blueprint_archive()
	blueprint_catalog_panel.visible = true
	blueprint_catalog_panel.pivot_offset = blueprint_catalog_panel.size * 0.5
	blueprint_catalog_panel.scale = Vector2(0.06, 0.14)
	blueprint_catalog_panel.modulate = Color(0.72, 1.35, 1.22, 0.8)
	_play_menu_sound(open_sound_method)
	var tween := create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(blueprint_catalog_panel, "scale:x", 1.0, 0.09).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(blueprint_catalog_panel, "scale:y", 1.0, 0.13).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(blueprint_catalog_panel, "modulate", Color.WHITE, 0.13)


func _close_blueprint_catalog(play_sound := true) -> void:
	if blueprint_catalog_panel == null or not blueprint_catalog_panel.visible:
		return
	if play_sound:
		_play_menu_sound(close_sound_method)
	var tween := create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(blueprint_catalog_panel, "scale:y", 0.08, 0.07).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.parallel().tween_property(blueprint_catalog_panel, "modulate:a", 0.0, 0.07)
	tween.finished.connect(func() -> void:
		if is_instance_valid(blueprint_catalog_panel):
			blueprint_catalog_panel.visible = false
			blueprint_catalog_panel.scale = Vector2.ONE
			blueprint_catalog_panel.modulate = Color.WHITE
	)


func _section_matches_context(section: PanelContainer, context: String) -> bool:
	return (
		(section == command_section and context == "")
		or (section == new_section and context == "new_size")
		or (section == new_confirm_section and context == "new_confirm")
		or (section == save_section and context == "edit")
		or (section == load_section and context == "load")
	)


func _hide_section(section: PanelContainer, animate: bool) -> void:
	if section == null or not section.visible:
		return
	# These sections live inside a VBoxContainer. If an outgoing section animates
	# while still visible, the container briefly lays out both old and new menus,
	# which creates a shove/jump during console transitions.
	section.visible = false
	section.position.x = 0.0
	section.scale = Vector2.ONE
	section.modulate = Color.WHITE


func _set_section_active(section: PanelContainer, is_active: bool, animate: bool) -> void:
	if section == null:
		return
	if not is_active:
		if not animate:
			section.visible = false
		return
	section.visible = true
	if not animate:
		section.scale = Vector2.ONE
		section.modulate = Color.WHITE
		return
	section.pivot_offset = section.size * 0.5
	section.scale = Vector2(0.04, 0.12)
	section.modulate = Color(0.75, 1.4, 1.25, 0.72)
	var original_position := section.position
	section.position.x += 22.0
	var tween := create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(section, "position:x", original_position.x, 0.09).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(section, "scale:x", 1.0, 0.08).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(section, "scale:y", 1.0, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(section, "modulate", Color.WHITE, 0.12)


func _make_terminal_section(title_text: String) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _panel_style(Color(0.005, 0.03, 0.028, 0.7), Color(0.1, 0.72, 0.66, 0.85)))
	var margin := MarginContainer.new()
	margin.name = "Margin"
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	panel.add_child(margin)
	var stack := VBoxContainer.new()
	stack.name = "Body"
	stack.add_theme_constant_override("separation", 7)
	margin.add_child(stack)
	var title := Label.new()
	title.text = title_text
	title.add_theme_font_size_override("font_size", 12)
	title.add_theme_color_override("font_color", Color(0.7, 1.0, 0.94, 1.0))
	stack.add_child(title)
	return panel


func _terminal_section_body(section: PanelContainer) -> VBoxContainer:
	return section.get_node("Margin/Body") as VBoxContainer


func _style_button(button: Button) -> void:
	action_buttons.append(button)
	button.custom_minimum_size.y = 34
	button.add_theme_font_size_override("font_size", 12)
	button.add_theme_color_override("font_color", Color(0.82, 1.0, 0.95, 1.0))
	button.add_theme_color_override("font_hover_color", Color(0.95, 1.0, 0.75, 1.0))
	button.add_theme_color_override("font_pressed_color", Color(0.1, 0.03, 0.0, 1.0))
	button.add_theme_stylebox_override("normal", _button_style(Color(0.015, 0.07, 0.065, 0.92), Color(0.08, 0.45, 0.42, 0.9)))
	button.add_theme_stylebox_override("hover", _button_style(Color(0.02, 0.13, 0.12, 0.96), Color(0.25, 1.0, 0.88, 1.0)))
	button.add_theme_stylebox_override("pressed", _button_style(Color(0.85, 0.62, 0.24, 0.95), Color(1.0, 0.88, 0.32, 1.0)))
	button.add_theme_stylebox_override("disabled", _button_style(Color(0.02, 0.025, 0.025, 0.58), Color(0.12, 0.18, 0.17, 0.65)))


func _style_compact_button(button: Button) -> void:
	_style_button(button)
	button.custom_minimum_size.y = 28
	button.add_theme_font_size_override("font_size", 10)


func _style_size_option_button(button: Button, is_selected: bool) -> void:
	_style_button(button)
	if not is_selected:
		return
	button.add_theme_color_override("font_color", Color(0.08, 0.025, 0.0, 1.0))
	button.add_theme_color_override("font_hover_color", Color(0.08, 0.025, 0.0, 1.0))
	button.add_theme_stylebox_override("normal", _button_style(Color(0.86, 0.63, 0.25, 0.96), Color(1.0, 0.86, 0.32, 1.0)))
	button.add_theme_stylebox_override("hover", _button_style(Color(0.98, 0.76, 0.32, 1.0), Color(1.0, 0.95, 0.48, 1.0)))


func _update_blueprint_card_style(card: PanelContainer) -> void:
	if card == null:
		return
	var is_selected := String(card.get_meta("blueprint_path", "")) == selected_blueprint_path and not selected_blueprint_path.is_empty()
	var fill := Color(0.008, 0.045, 0.042, 0.92)
	var edge := Color(0.08, 0.45, 0.42, 0.9)
	if is_selected:
		fill = Color(0.03, 0.16, 0.145, 0.98)
		edge = Color(0.3, 1.0, 0.9, 1.0)
	card.add_theme_stylebox_override("panel", _button_style(fill, edge))


func _set_blueprint_card_hovered(card: PanelContainer, is_hovered: bool) -> void:
	if not is_instance_valid(card):
		return
	var is_selected := String(card.get_meta("blueprint_path", "")) == selected_blueprint_path and not selected_blueprint_path.is_empty()
	if is_hovered:
		card.add_theme_stylebox_override("panel", _button_style(Color(0.02, 0.13, 0.12, 0.96), Color(0.58, 1.0, 0.92, 1.0)))
	else:
		_update_blueprint_card_style(card)
	var target_scale := Vector2(1.035, 1.035) if is_hovered else Vector2.ONE
	if is_selected and not is_hovered:
		target_scale = Vector2.ONE
	var tween := create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(card, "scale", target_scale, 0.1).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _style_line_edit(field: LineEdit) -> void:
	field.custom_minimum_size.y = 34
	field.add_theme_font_size_override("font_size", 12)
	field.add_theme_color_override("font_color", Color(0.82, 1.0, 0.95, 1.0))
	field.add_theme_color_override("font_placeholder_color", Color(0.36, 0.58, 0.55, 0.9))
	field.add_theme_stylebox_override("normal", _button_style(Color(0.01, 0.055, 0.052, 0.92), Color(0.1, 0.56, 0.52, 0.85)))
	field.add_theme_stylebox_override("focus", _button_style(Color(0.015, 0.09, 0.08, 0.98), Color(0.38, 1.0, 0.9, 1.0)))


func _button_style(fill: Color, edge: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = edge
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = 2
	style.corner_radius_bottom_right = 8
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 5
	style.content_margin_bottom = 5
	return style


func _panel_style(fill: Color, edge: Color, border_width: int = 1) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = edge
	style.border_width_left = border_width
	style.border_width_top = border_width
	style.border_width_right = border_width
	style.border_width_bottom = border_width
	style.corner_radius_top_left = 3
	style.corner_radius_bottom_right = 10
	style.shadow_color = Color(edge.r, edge.g, edge.b, 0.22)
	style.shadow_size = 10
	return style


func _play_menu_sound(method_name: String) -> void:
	var menu_audio := get_tree().get_first_node_in_group("menu_audio")
	if is_instance_valid(menu_audio) and menu_audio.has_method(method_name):
		menu_audio.call(method_name)
