extends Control

const VIEW_SCENES := {
	"Ship": preload("res://scenes/views/ship_view.tscn"),
	"Settlement": preload("res://scenes/views/settlement_view.tscn"),
	"Crew": preload("res://scenes/views/crew_view.tscn"),
}
const SHIP_BUILDER_SCREEN := preload("res://scenes/ship_builder_screen.tscn")
const FORGE_INVENTORY_GRID := preload("res://scripts/forge_inventory_grid.gd")
const FORGE_INVENTORY_PIECE := preload("res://scripts/forge_inventory_piece.gd")
const SETTLEMENT_GRID := preload("res://scripts/settlement_grid.gd")
const GRID_INVENTORY_CATALOG := preload("res://scripts/grid_inventory_catalog.gd")
const POWER_REQUIREMENT_DISPLAY := preload("res://scripts/power_requirement_display.gd")
const CREW_REQUIREMENT_DISPLAY := preload("res://scripts/crew_requirement_display.gd")
const FACTION_REPUTATION_ROW := preload("res://scripts/faction_reputation_row.gd")
const CONTRACT_TERMINAL_PANEL := preload("res://scripts/contract_terminal_panel.gd")
const RUN_STATE_SCRIPT := preload("res://scripts/run_state.gd")
const JUMP_DIRECTOR_SCRIPT := preload("res://scripts/jump_director.gd")
const SECTOR_JUMP_TERMINAL_SCRIPT := preload("res://scripts/sector_jump_terminal.gd")
const LIGHTSPEED_TRANSITION_SCRIPT := preload("res://scripts/lightspeed_transition.gd")
const STARTING_SHIP_RANDOMIZER_SCRIPT := preload("res://scripts/starting_ship_randomizer.gd")
const STARTING_SHIP_TERMINAL_SCRIPT := preload("res://scripts/starting_ship_terminal.gd")
const RUN_PROLOGUE_TERMINAL_SCRIPT := preload("res://scripts/run_prologue_terminal.gd")
const CONTROLLER_MENU_CURSOR := preload("res://scripts/controller_menu_cursor.gd")
const COMBAT_TEST_SETUP_PANEL := preload("res://scripts/combat_test_setup_panel.gd")
const ESCAPE_KEEL_BLUEPRINT := preload("res://resources/ship_designs/barebones_starter.tres")
const COMBAT_TEST_BLUEPRINT_DIRECTORY := "res://resources/ship_designs"
const COMBAT_TEST_FALLBACK_BLUEPRINT_PATH := "res://resources/starting_ship_layout.tres"

const FORGE_TAB_PEEK_WIDTH := 22.0
const FORGE_TAB_RIGHT_MARGIN := 0.0
const FORGE_TAB_SLIDE_SECONDS := 0.22
const CONTROLLER_MENU_SCROLL_DEADZONE := 0.24
const CONTROLLER_MENU_SCROLL_SPEED := 420.0
const CONTROLLER_CURSOR_DEADZONE := 0.18
const CONTROLLER_CURSOR_SPEED := 760.0
const CONTROLLER_CURSOR_DEVICE := 127
const CONTROLLER_CURSOR_MARGIN := 8.0

const VIEW_DEPTH := {
	"Ship": 0,
	"Settlement": 1,
	"Crew": 2,
}

@export_category("View Transition")
@export_range(0.1, 1.5, 0.05) var transition_duration := 0.4
@export var transition_sound: AudioStream

@onready var content_host: MarginContainer = %ContentHost
@onready var current_view_label: Label = %CurrentViewLabel
@onready var shield_bar: Control = %ShieldBar
@onready var shield_value: Label = %ShieldValue
@onready var hull_bar: ProgressBar = %HullBar
@onready var hull_value: Label = %HullValue
@onready var speed_gauge: Control = %SpeedGauge
@onready var mode_selector: PanelContainer = %ModeSelector
@onready var mode_selector_light: Panel = %ModeSelectorLight
@onready var mode_selector_layer: Control = %ModeSelectorLayer
@onready var transition_audio: AudioStreamPlayer = %TransitionAudio
@onready var forge_toggle: Button = %ForgeToggle
@onready var forge_panel: PanelContainer = %ForgePanel
@onready var forge_enemy_behavior: OptionButton = %ForgeEnemyBehavior
@onready var forge_blueprint_contact: OptionButton = %ForgeBlueprintContact
@onready var forge_status: Label = %ForgeStatus
@onready var forge_active_indicator: Button = %ForgeActiveIndicator
@onready var forge_ship_editor_button: Button = %ForgeShipEditorButton
@onready var forge_structural_test_button: Button = %ForgeStructuralTestButton
@onready var logistics_toggle: Button = %LogisticsToggle
@onready var logistics_overview_panel: PanelContainer = %LogisticsOverviewPanel
@onready var logistics_overview_status: Label = %LogisticsOverviewStatus
@onready var logistics_manifest_panel: PanelContainer = %LogisticsManifestPanel
@onready var logistics_manifest_title: Label = %LogisticsManifestTitle
@onready var logistics_manifest_summary: Label = %LogisticsManifestSummary
@onready var logistics_manifest_list: GridContainer = %LogisticsManifestList
@onready var logistics_detail_panel: PanelContainer = %LogisticsDetailPanel
@onready var logistics_detail_title: Label = %LogisticsDetailTitle
@onready var logistics_detail_meta: Label = %LogisticsDetailMeta
@onready var logistics_detail_icon: TextureRect = %LogisticsDetailIcon
@onready var logistics_detail_glyph: Label = %LogisticsDetailGlyph
@onready var logistics_detail_text: Label = %LogisticsDetailText
@onready var mode_buttons := {
	"Ship": %ShipButton,
	"Settlement": %SettlementButton,
	"Crew": %CrewButton,
}

var current_view: Control
var current_view_name := ""
var is_transitioning := false
var tactical_zoom_level := 1.0
var active_logistics_role := "ENGINEERING"
var mode_light_tween: Tween
var generated_inventory_icons: Dictionary = {}
var ship_builder_screen: ShipBuilderScreen
var parts_locker_grid: Container
var parts_locker_workbench: Control
var parts_locker_workbench_status: Label
var parts_locker_refit_controller: ShipBuilderScreen
var parts_locker_refit_layout: Resource
var parts_locker_refit_context: VBoxContainer
var parts_locker_resource_host: Control
var parts_locker_signature := ""
var parts_locker_initialized := false
var diplomacy_toggle: Button
var diplomacy_panel: CrtContextPanel
var diplomacy_rows: VBoxContainer
var contract_toggle: Button
var contract_panel: ContractTerminalPanel
var run_state: RunState
var jump_director: JumpDirector
var sector_jump_terminal: SectorJumpTerminal
var lightspeed_transition: LightspeedTransition
var pending_jump_destination: GeneratedSector
var pending_combat_test_jump := false
var combat_testing_active := false
var combat_test_panel: CombatTestSetupPanel
var combat_test_panel_layer: CanvasLayer
var forge_tab_tween: Tween
var forge_tab_hovered := false
var starting_ship_terminal: StartingShipTerminal
var starting_ship_terminal_layer: CanvasLayer
var selected_starter_candidate: Dictionary = {}
var run_prologue_terminal: RunPrologueTerminal
var run_prologue_layer: CanvasLayer
var run_start_pending := false
var escape_assembly_pending := false
var pursuit_alert_layer: CanvasLayer
var pursuit_alert: Label
var controller_menu_cursor: Control
var controller_cursor_position := Vector2.ZERO
var controller_cursor_active := false
var controller_cursor_warp_deadline := 0
var controller_held_inventory_piece: Control
var controller_forge_chord_latched := false


func _ready() -> void:
	_initialize_sector_jump_loop()
	for view_name: String in mode_buttons:
		mode_buttons[view_name].pressed.connect(_show_view.bind(view_name))
	# The former Deck view now lives inside the command camera.  Keep its scene
	# available for developer laboratories, but remove it from flight navigation.
	mode_buttons["Settlement"].visible = false
	mode_buttons["Crew"].visible = false
	mode_selector_layer.custom_minimum_size.x = 102.0
	mode_selector.visible = false
	forge_toggle.toggled.connect(_on_forge_toggled)
	forge_toggle.mouse_entered.connect(_on_forge_tab_mouse_entered)
	forge_toggle.mouse_exited.connect(_on_forge_tab_mouse_exited)
	resized.connect(_refresh_forge_tab_position)
	forge_active_indicator.pressed.connect(_deactivate_active_forge_tool)
	forge_ship_editor_button.pressed.connect(_toggle_settlement_dev_tool.bind("editor"))
	forge_structural_test_button.pressed.connect(_toggle_settlement_dev_tool.bind("structure"))
	logistics_toggle.toggled.connect(_on_logistics_toggled)
	%LogisticsSuppliesButton.pressed.connect(_open_logistics_manifest.bind("ENGINEERING"))
	%LogisticsCargoButton.pressed.connect(_open_logistics_manifest.bind("CREW_SUPPORT"))
	%LogisticsManifestBackButton.pressed.connect(_close_logistics_manifest)
	%LogisticsDetailBackButton.pressed.connect(func() -> void: logistics_detail_panel.call("power_off"))
	%ForgeSpawnCopyButton.pressed.connect(_forge_spawn_copy)
	%ForgeSpawnBlueprintContactButton.pressed.connect(_forge_spawn_blueprint_contact)
	%ForgeClearEnemiesButton.pressed.connect(_forge_clear_enemies)
	%ForgeSpawnGridPickupButton.pressed.connect(_forge_spawn_grid_pickup)
	%ForgeMaxCrewButton.pressed.connect(_forge_max_crew)
	%ForgeStarterDraftButton.pressed.connect(_open_starter_ship_draft)
	%ForgeStartRunButton.pressed.connect(_start_escape_run)
	forge_enemy_behavior.item_selected.connect(_forge_set_enemy_behavior)
	_configure_parts_locker_panel()
	_create_diplomacy_terminal()
	_create_contract_terminal()
	_create_controller_menu_cursor()
	_populate_forge()
	_add_forge_ship_builder_button()
	_add_forge_combat_testing_button()
	forge_panel.call("power_off", true)
	call_deferred("_refresh_forge_tab_position")
	logistics_overview_panel.call("power_off", true)
	logistics_manifest_panel.call("power_off", true)
	logistics_detail_panel.call("power_off", true)
	_show_view("Ship")


func _initialize_sector_jump_loop() -> void:
	run_state = RUN_STATE_SCRIPT.new() as RunState
	run_state.name = "RunState"
	add_child(run_state)
	run_state.pursuit_trace_changed.connect(_on_pursuit_trace_changed)
	run_state.pursuit_stage_changed.connect(_on_pursuit_stage_changed)
	_create_pursuit_alert()

	jump_director = JUMP_DIRECTOR_SCRIPT.new() as JumpDirector
	jump_director.name = "JumpDirector"
	add_child(jump_director)

	sector_jump_terminal = SECTOR_JUMP_TERMINAL_SCRIPT.new() as SectorJumpTerminal
	sector_jump_terminal.name = "SectorJumpTerminal"
	add_child(sector_jump_terminal)
	sector_jump_terminal.destination_selected.connect(_on_jump_destination_selected)

	lightspeed_transition = LIGHTSPEED_TRANSITION_SCRIPT.new() as LightspeedTransition
	lightspeed_transition.name = "LightspeedTransition"
	add_child(lightspeed_transition)
	lightspeed_transition.jump_midpoint.connect(_on_lightspeed_midpoint)
	lightspeed_transition.jump_completed.connect(_on_lightspeed_completed)

	var sector := get_tree().get_first_node_in_group("sector_simulation")
	if is_instance_valid(sector):
		sector.sector_completed.connect(_on_sector_completed)
	var combat := get_tree().get_first_node_in_group("combat_simulation")
	if is_instance_valid(combat) and combat.has_signal("player_weapon_fired"):
		combat.connect("player_weapon_fired", _on_player_weapon_fired)


func _on_sector_completed() -> void:
	if not is_instance_valid(jump_director) or not is_instance_valid(sector_jump_terminal):
		return
	sector_jump_terminal.present_routes(jump_director.generate_jump_routes())


func _on_jump_destination_selected(destination: GeneratedSector) -> void:
	if destination == null or pending_jump_destination != null:
		return
	pending_jump_destination = destination
	combat_testing_active = false
	sector_jump_terminal.clear_routes()
	jump_director.commit_destination(destination)
	_play_transition_sound()
	var ship := get_tree().get_first_node_in_group("ship_simulation")
	var tactical_ship_visual: CanvasItem
	if is_instance_valid(current_view) and current_view.is_in_group("ship_view"):
		tactical_ship_visual = current_view.call("get_jump_transition_visual") as CanvasItem
	lightspeed_transition.begin_jump(destination, ship, tactical_ship_visual, current_view)


func _on_lightspeed_midpoint() -> void:
	if pending_jump_destination == null:
		return
	var sector := get_tree().get_first_node_in_group("sector_simulation")
	var population := get_tree().get_first_node_in_group("sector_population")
	var ship := get_tree().get_first_node_in_group("ship_simulation")
	var combat := get_tree().get_first_node_in_group("combat_simulation")
	if pending_combat_test_jump:
		if is_instance_valid(combat):
			combat.call("clear_enemies")
		if is_instance_valid(population):
			population.call("clear_sector_population")
	else:
		run_state.advance_to_sector(pending_jump_destination)
	if is_instance_valid(sector):
		sector.call("configure_generated_sector", pending_jump_destination)
		if not pending_combat_test_jump:
			_on_pursuit_stage_changed(run_state.pursuit_stage, run_state.get_pursuit_report())
	if is_instance_valid(population) and not pending_combat_test_jump:
		population.call("populate_generated_sector", pending_jump_destination)
	if is_instance_valid(ship):
		ship.call(
			"reset_for_sector_entry",
			pending_jump_destination.entry_position,
			pending_jump_destination.entry_rotation
		)
	if is_instance_valid(current_view) and current_view.is_in_group("ship_view"):
		current_view.call_deferred("_center_camera_on_ship")


func _on_lightspeed_completed() -> void:
	var should_open_combat_test := pending_combat_test_jump
	if pending_combat_test_jump:
		combat_testing_active = true
		pending_combat_test_jump = false
	pending_jump_destination = null
	if is_instance_valid(sector_jump_terminal):
		sector_jump_terminal.release_jump_pause()
	if should_open_combat_test:
		_open_combat_test_setup()


func _create_pursuit_alert() -> void:
	pursuit_alert_layer = CanvasLayer.new()
	pursuit_alert_layer.name = "PursuitAlertLayer"
	pursuit_alert_layer.layer = 80
	add_child(pursuit_alert_layer)
	pursuit_alert = Label.new()
	pursuit_alert.process_mode = Node.PROCESS_MODE_ALWAYS
	pursuit_alert.anchor_left = 0.5
	pursuit_alert.anchor_top = 0.0
	pursuit_alert.anchor_right = 0.5
	pursuit_alert.anchor_bottom = 0.0
	pursuit_alert.offset_left = -210.0
	pursuit_alert.offset_top = 172.0
	pursuit_alert.offset_right = 210.0
	pursuit_alert.offset_bottom = 198.0
	pursuit_alert.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pursuit_alert.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pursuit_alert.add_theme_font_size_override("font_size", 11)
	pursuit_alert.visible = false
	pursuit_alert_layer.add_child(pursuit_alert)


func _on_pursuit_trace_changed(report: Dictionary) -> void:
	if not is_instance_valid(pursuit_alert):
		return
	var active := bool(report.get("active", false))
	pursuit_alert.visible = active
	if not active:
		return
	var stage := int(report.get("stage", 0))
	var trace := roundi(float(report.get("trace", 0.0)))
	var color := Color(0.4, 0.82, 0.75)
	if stage == 1:
		color = Color(1.0, 0.72, 0.28)
	elif stage == 2:
		color = Color(1.0, 0.48, 0.2)
	elif stage >= 3:
		color = Color(1.0, 0.2, 0.16)
	pursuit_alert.add_theme_color_override("font_color", color)
	pursuit_alert.text = "SECURITY TRACE • %s • %02d%%" % [
		String(report.get("stage_name", "SIGNAL QUIET")),
		trace,
	]


func _on_pursuit_stage_changed(stage: int, _report: Dictionary) -> void:
	var sector := get_tree().get_first_node_in_group("sector_simulation")
	if not is_instance_valid(sector):
		return
	if stage == 3 and sector.has_method("start_encroachment"):
		sector.call("start_encroachment", 20.0)
	elif stage >= 4 and sector.has_method("start_encroachment"):
		sector.call("start_encroachment", 0.0)


func _on_player_weapon_fired(trace_noise: float) -> void:
	if is_instance_valid(run_state) and not combat_testing_active:
		run_state.add_pursuit_trace(trace_noise, &"WEAPONS_FIRE")


func _process(_delta: float) -> void:
	var combat := get_tree().get_first_node_in_group("combat_simulation")
	if is_instance_valid(combat):
		forge_status.text = "TRACKED CONTACTS • %d" % combat.enemies.size()
	_update_command_status()
	_sync_forge_tool_indicators()
	if logistics_overview_panel.visible:
		_refresh_logistics_overview()
	_update_controller_menu_cursor(_delta)
	_update_controller_menu_scroll(_delta)


func _input(event: InputEvent) -> void:
	if is_instance_valid(current_view):
		var wheel := current_view.get_node_or_null("WeaponsHUD")
		if wheel != null and wheel.call("handle_input", event):
			get_viewport().set_input_as_handled()
			return
	if event is InputEventMouseMotion:
		var mouse_motion := event as InputEventMouseMotion
		var is_controller_warp := (
			controller_cursor_active
			and Time.get_ticks_msec() <= controller_cursor_warp_deadline
		)
		if is_controller_warp:
			return
		if mouse_motion.device != CONTROLLER_CURSOR_DEVICE and not mouse_motion.relative.is_zero_approx():
			_deactivate_controller_menu_cursor()
		return
	if not event is InputEventJoypadButton:
		return
	var button_event := event as InputEventJoypadButton
	if button_event.button_index in [JOY_BUTTON_BACK, JOY_BUTTON_START]:
		var device := button_event.device
		var back_pressed := Input.is_joy_button_pressed(device, JOY_BUTTON_BACK)
		var start_pressed := Input.is_joy_button_pressed(device, JOY_BUTTON_START)
		if button_event.pressed and back_pressed and start_pressed and not controller_forge_chord_latched:
			controller_forge_chord_latched = true
			_toggle_controller_forge()
		if not back_pressed and not start_pressed:
			controller_forge_chord_latched = false
		get_viewport().set_input_as_handled()
		return
	if not button_event.pressed:
		return
	if button_event.button_index == JOY_BUTTON_B:
		if _close_open_forge_option_popup():
			get_viewport().set_input_as_handled()
			return
		if _handle_controller_back():
			get_viewport().set_input_as_handled()
		return
	if _controller_primary_panel_open():
		if forge_toggle.button_pressed and _forge_option_popup_visible():
			# Let Godot's native popup consume D-pad/A while an OptionButton is
			# expanded. B is handled above so it closes only that popup first.
			return
		match button_event.button_index:
			JOY_BUTTON_LEFT_SHOULDER:
				if _controller_panel_index() < 3:
					_cycle_controller_panel(-1)
				else:
					return
			JOY_BUTTON_RIGHT_SHOULDER:
				if _controller_panel_index() < 3:
					_cycle_controller_panel(1)
				else:
					return
			JOY_BUTTON_A:
				_activate_controller_menu_cursor()
				_controller_cursor_accept()
			JOY_BUTTON_DPAD_LEFT:
				_snap_controller_cursor(Vector2.LEFT)
			JOY_BUTTON_DPAD_RIGHT:
				_snap_controller_cursor(Vector2.RIGHT)
			JOY_BUTTON_DPAD_UP:
				_snap_controller_cursor(Vector2.UP)
			JOY_BUTTON_DPAD_DOWN:
				_snap_controller_cursor(Vector2.DOWN)
			_:
				return
		get_viewport().set_input_as_handled()
		return
	match button_event.button_index:
		JOY_BUTTON_DPAD_LEFT:
			_open_controller_panel(0)
		JOY_BUTTON_DPAD_UP:
			_open_controller_panel(1)
		JOY_BUTTON_DPAD_RIGHT:
			_open_controller_panel(2)
		_:
			return
	get_viewport().set_input_as_handled()


func _update_command_status() -> void:
	var ship := get_tree().get_first_node_in_group("ship_simulation")
	if not is_instance_valid(ship):
		shield_bar.call("set_banks", {})
		shield_value.text = "---"
		hull_bar.value = 0.0
		hull_value.text = "---"
		speed_gauge.call("set_speed", 0.0, 1.0)
		return
	var shield_percent := float(ship.call("get_shield_percentage"))
	var hull_percent := float(ship.call("get_hull_percentage"))
	var speed := (ship.get("velocity") as Vector2).length()
	var maximum_speed := maxf(float(ship.get("maximum_speed")), 0.001)
	var shield_bank_report: Dictionary = ship.call("get_shield_bank_report")
	var installed_shield_capacity := 0.0
	for bank_data_variant: Variant in shield_bank_report.values():
		var bank_data: Dictionary = bank_data_variant
		installed_shield_capacity += float(bank_data.get("maximum", 0.0))
	shield_bar.call("set_banks", shield_bank_report)
	hull_bar.value = clampf(hull_percent, 0.0, 100.0)
	shield_value.text = "OFF" if installed_shield_capacity <= 0.0 else "%03d%%" % roundi(shield_percent)
	hull_value.text = "%03d%%" % roundi(hull_percent)
	speed_gauge.call("set_speed", speed, maximum_speed)


func _on_logistics_toggled(is_open: bool) -> void:
	logistics_toggle.text = "PARTS LOCKER <" if is_open else "PARTS LOCKER >"
	if is_open:
		if is_instance_valid(contract_toggle) and contract_toggle.button_pressed:
			contract_toggle.set_pressed_no_signal(false)
			_on_contracts_toggled(false)
		if is_instance_valid(diplomacy_toggle) and diplomacy_toggle.button_pressed:
			diplomacy_toggle.set_pressed_no_signal(false)
			_on_diplomacy_toggled(false)
		if forge_toggle.button_pressed:
			forge_toggle.set_pressed_no_signal(false)
			_on_forge_toggled(false)
		_refresh_logistics_overview()
		logistics_overview_panel.call("power_on_from", logistics_toggle.get_global_rect().get_center())
		call_deferred("_fit_parts_locker_after_open")
	else:
		logistics_detail_panel.call("power_off")
		logistics_manifest_panel.call("power_off")
		logistics_overview_panel.call("power_off")
		_release_controller_menu_focus()
	_sync_controller_menu_mode()


func _fit_parts_locker_after_open() -> void:
	# The panel and its CRT reveal both settle one frame after the toggle. Fit
	# against that final viewport so the ship never opens half outside the bench.
	await get_tree().process_frame
	if is_instance_valid(parts_locker_workbench) and logistics_overview_panel.visible:
		parts_locker_workbench.call("fit_editor_view_to_hull")


func _create_diplomacy_terminal() -> void:
	var overlay := get_node("LogisticsOverlay") as CanvasLayer
	diplomacy_toggle = Button.new()
	diplomacy_toggle.name = "DiplomacyToggle"
	diplomacy_toggle.position = Vector2(140.0, 74.0)
	diplomacy_toggle.size = Vector2(148.0, 30.0)
	diplomacy_toggle.toggle_mode = true
	diplomacy_toggle.text = "DIPLOMATIC >"
	diplomacy_toggle.tooltip_text = "CLICK • OPEN RUN FACTION TRAFFIC"
	diplomacy_toggle.add_theme_font_size_override("font_size", 11)
	diplomacy_toggle.add_theme_color_override("font_color", Color(0.78, 0.56, 1.0, 1.0))
	diplomacy_toggle.add_theme_color_override("font_hover_color", Color(0.94, 0.82, 1.0, 1.0))
	var button_style := StyleBoxFlat.new()
	button_style.bg_color = Color(0.025, 0.012, 0.035, 0.94)
	button_style.border_color = Color(0.52, 0.24, 0.68, 0.82)
	button_style.border_width_bottom = 1
	button_style.corner_radius_bottom_right = 5
	diplomacy_toggle.add_theme_stylebox_override("normal", button_style)
	var button_hover := button_style.duplicate() as StyleBoxFlat
	button_hover.bg_color = Color(0.11, 0.025, 0.14, 0.98)
	button_hover.border_color = Color(0.85, 0.48, 1.0, 1.0)
	diplomacy_toggle.add_theme_stylebox_override("hover", button_hover)
	diplomacy_toggle.add_theme_stylebox_override("pressed", button_hover)
	overlay.add_child(diplomacy_toggle)
	diplomacy_toggle.toggled.connect(_on_diplomacy_toggled)

	diplomacy_panel = CrtContextPanel.new()
	diplomacy_panel.name = "DiplomacyPanel"
	diplomacy_panel.position = Vector2(140.0, 110.0)
	diplomacy_panel.size = Vector2(470.0, 285.0)
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.004, 0.016, 0.022, 0.98)
	panel_style.border_color = Color(0.5, 0.24, 0.68, 0.9)
	panel_style.border_width_left = 1
	panel_style.border_width_top = 1
	panel_style.border_width_right = 1
	panel_style.border_width_bottom = 1
	panel_style.corner_radius_top_left = 3
	panel_style.corner_radius_bottom_right = 12
	panel_style.shadow_color = Color(0.55, 0.12, 0.75, 0.2)
	panel_style.shadow_size = 8
	diplomacy_panel.add_theme_stylebox_override("panel", panel_style)
	overlay.add_child(diplomacy_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 10)
	diplomacy_panel.add_child(margin)
	var controls := VBoxContainer.new()
	controls.add_theme_constant_override("separation", 5)
	margin.add_child(controls)
	var title := Label.new()
	title.text = "DIPLOMATIC TRAFFIC"
	title.add_theme_color_override("font_color", Color(0.85, 0.64, 1.0, 1.0))
	title.add_theme_font_size_override("font_size", 17)
	controls.add_child(title)
	var subtitle := Label.new()
	subtitle.text = "RUN STANDING • REPORTED ACTIONS ALTER THE SIGNAL"
	subtitle.add_theme_color_override("font_color", Color(0.48, 0.4, 0.58, 1.0))
	subtitle.add_theme_font_size_override("font_size", 9)
	controls.add_child(subtitle)
	diplomacy_rows = VBoxContainer.new()
	diplomacy_rows.size_flags_vertical = Control.SIZE_EXPAND_FILL
	diplomacy_rows.add_theme_constant_override("separation", 2)
	controls.add_child(diplomacy_rows)

	var reputation := get_tree().get_first_node_in_group("reputation_simulation")
	if is_instance_valid(reputation):
		reputation.connect("reputation_changed", func(_faction_id: StringName, _old: float, _new: float, _reason: String) -> void:
			_refresh_diplomacy_terminal()
		)
		reputation.connect("run_reputation_reset", _refresh_diplomacy_terminal)
	_refresh_diplomacy_terminal()
	diplomacy_panel.call("power_off", true)


func _on_diplomacy_toggled(is_open: bool) -> void:
	diplomacy_toggle.text = "DIPLOMATIC <" if is_open else "DIPLOMATIC >"
	if is_open:
		if is_instance_valid(contract_toggle) and contract_toggle.button_pressed:
			contract_toggle.set_pressed_no_signal(false)
			_on_contracts_toggled(false)
		if logistics_toggle.button_pressed:
			logistics_toggle.set_pressed_no_signal(false)
			_on_logistics_toggled(false)
		if forge_toggle.button_pressed:
			forge_toggle.set_pressed_no_signal(false)
			_on_forge_toggled(false)
		_refresh_diplomacy_terminal()
		diplomacy_panel.call("power_on_from", diplomacy_toggle.get_global_rect().get_center())
	else:
		diplomacy_panel.call("power_off")
		_release_controller_menu_focus()
	_sync_controller_menu_mode()


func _create_contract_terminal() -> void:
	var overlay := get_node("LogisticsOverlay") as CanvasLayer
	contract_toggle = Button.new()
	contract_toggle.name = "ContractToggle"
	contract_toggle.position = Vector2(296.0, 74.0)
	contract_toggle.size = Vector2(138.0, 30.0)
	contract_toggle.toggle_mode = true
	contract_toggle.text = "CONTRACTS >"
	contract_toggle.tooltip_text = "CLICK • OPEN ACTIVE CONTRACT TELEMETRY"
	contract_toggle.add_theme_font_size_override("font_size", 11)
	contract_toggle.add_theme_color_override("font_color", Color(1.0, 0.64, 0.24))
	contract_toggle.add_theme_color_override("font_hover_color", Color(1.0, 0.86, 0.48))
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.035, 0.022, 0.008, 0.94)
	normal.border_color = Color(0.65, 0.32, 0.08, 0.82)
	normal.border_width_bottom = 1
	normal.corner_radius_bottom_right = 5
	contract_toggle.add_theme_stylebox_override("normal", normal)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.16, 0.065, 0.01, 0.98)
	hover.border_color = Color(1.0, 0.57, 0.16, 1.0)
	contract_toggle.add_theme_stylebox_override("hover", hover)
	contract_toggle.add_theme_stylebox_override("pressed", hover)
	overlay.add_child(contract_toggle)
	contract_toggle.toggled.connect(_on_contracts_toggled)
	contract_panel = CONTRACT_TERMINAL_PANEL.new() as ContractTerminalPanel
	contract_panel.name = "ContractPanel"
	contract_panel.position = Vector2(296.0, 110.0)
	contract_panel.size = Vector2(470.0, 310.0)
	contract_panel.plot_course_requested.connect(_plot_contract_course)
	overlay.add_child(contract_panel)
	var quests := get_tree().get_first_node_in_group("quest_simulation")
	if is_instance_valid(quests):
		quests.connect("quest_changed", func(_quest_id: StringName, _report: Dictionary) -> void:
			if is_instance_valid(contract_panel):
				contract_panel.refresh_contracts()
		)
		quests.connect("run_quests_reset", func() -> void:
			if is_instance_valid(contract_panel):
				contract_panel.refresh_contracts()
		)
	contract_panel.refresh_contracts()
	contract_panel.call("power_off", true)


func _on_contracts_toggled(is_open: bool) -> void:
	contract_toggle.text = "CONTRACTS <" if is_open else "CONTRACTS >"
	if is_open:
		if logistics_toggle.button_pressed:
			logistics_toggle.set_pressed_no_signal(false)
			_on_logistics_toggled(false)
		if is_instance_valid(diplomacy_toggle) and diplomacy_toggle.button_pressed:
			diplomacy_toggle.set_pressed_no_signal(false)
			_on_diplomacy_toggled(false)
		if forge_toggle.button_pressed:
			forge_toggle.set_pressed_no_signal(false)
			_on_forge_toggled(false)
		contract_panel.refresh_contracts()
		contract_panel.call("power_on_from", contract_toggle.get_global_rect().get_center())
	else:
		contract_panel.call("power_off")
		_release_controller_menu_focus()
	_sync_controller_menu_mode()


func _controller_primary_panel_open() -> bool:
	return (
		logistics_toggle.button_pressed
		or (is_instance_valid(diplomacy_toggle) and diplomacy_toggle.button_pressed)
		or (is_instance_valid(contract_toggle) and contract_toggle.button_pressed)
		or forge_toggle.button_pressed
	)


func _controller_panel_index() -> int:
	if logistics_toggle.button_pressed:
		return 0
	if is_instance_valid(diplomacy_toggle) and diplomacy_toggle.button_pressed:
		return 1
	if is_instance_valid(contract_toggle) and contract_toggle.button_pressed:
		return 2
	if forge_toggle.button_pressed:
		return 3
	return -1


func _open_controller_panel(panel_index: int) -> void:
	_release_controller_menu_focus()
	match wrapi(panel_index, 0, 3):
		0:
			logistics_toggle.set_pressed_no_signal(true)
			_on_logistics_toggled(true)
		1:
			diplomacy_toggle.set_pressed_no_signal(true)
			_on_diplomacy_toggled(true)
		2:
			contract_toggle.set_pressed_no_signal(true)
			_on_contracts_toggled(true)
	call_deferred("_prepare_controller_cursor_for_panel")


func _cycle_controller_panel(direction: int) -> void:
	var current_index := _controller_panel_index()
	if current_index < 0 or current_index >= 3:
		return
	_open_controller_panel(current_index + direction)


func _toggle_controller_forge() -> void:
	var is_opening := not forge_toggle.button_pressed
	forge_toggle.set_pressed_no_signal(is_opening)
	_on_forge_toggled(is_opening)
	if is_opening:
		call_deferred("_prepare_controller_cursor_for_panel")


func _handle_controller_back() -> bool:
	if is_instance_valid(controller_held_inventory_piece):
		_cancel_controller_held_inventory_piece()
		return true
	if logistics_toggle.button_pressed:
		if logistics_detail_panel.visible:
			logistics_detail_panel.call("power_off")
			_release_controller_menu_focus()
			call_deferred("_clamp_controller_cursor_to_panel")
			return true
		if logistics_manifest_panel.visible:
			_close_logistics_manifest()
			_release_controller_menu_focus()
			call_deferred("_clamp_controller_cursor_to_panel")
			return true
		logistics_toggle.set_pressed_no_signal(false)
		_on_logistics_toggled(false)
		return true
	if is_instance_valid(diplomacy_toggle) and diplomacy_toggle.button_pressed:
		diplomacy_toggle.set_pressed_no_signal(false)
		_on_diplomacy_toggled(false)
		return true
	if is_instance_valid(contract_toggle) and contract_toggle.button_pressed:
		contract_toggle.set_pressed_no_signal(false)
		_on_contracts_toggled(false)
		return true
	if forge_toggle.button_pressed:
		forge_toggle.set_pressed_no_signal(false)
		_on_forge_toggled(false)
		_release_controller_menu_focus()
		return true
	return false


func _sync_controller_menu_mode() -> void:
	var ship_view := get_tree().get_first_node_in_group("ship_view")
	if is_instance_valid(ship_view) and ship_view.has_method("set_controller_menu_active"):
		ship_view.call("set_controller_menu_active", _controller_primary_panel_open())
	if not _controller_primary_panel_open():
		_deactivate_controller_menu_cursor()


func _release_controller_menu_focus() -> void:
	var focus_owner := get_viewport().gui_get_focus_owner()
	if is_instance_valid(focus_owner):
		focus_owner.release_focus()


func _active_controller_panel() -> Control:
	match _controller_panel_index():
		0:
			if logistics_detail_panel.visible:
				return logistics_detail_panel
			if logistics_manifest_panel.visible:
				return logistics_manifest_panel
			return logistics_overview_panel
		1:
			return diplomacy_panel
		2:
			return contract_panel
		3:
			return forge_panel
	return null


func _focus_active_controller_panel() -> void:
	var panel := _active_controller_panel()
	if not is_instance_valid(panel) or not panel.visible:
		return
	var controls := panel.find_children("*", "Control", true, false)
	for control_value: Node in controls:
		var control := control_value as Control
		if control != null and control.is_visible_in_tree() and control.focus_mode != Control.FOCUS_NONE:
			control.grab_focus()
			return


func _create_controller_menu_cursor() -> void:
	var cursor_layer := CanvasLayer.new()
	cursor_layer.name = "ControllerMenuCursorLayer"
	cursor_layer.layer = 100
	add_child(cursor_layer)
	controller_menu_cursor = CONTROLLER_MENU_CURSOR.new() as Control
	controller_menu_cursor.name = "ControllerMenuCursor"
	controller_menu_cursor.visible = false
	cursor_layer.add_child(controller_menu_cursor)


func _prepare_controller_cursor_for_panel() -> void:
	var panel := _active_controller_panel()
	if not is_instance_valid(panel) or not panel.visible:
		return
	controller_cursor_position = panel.get_global_rect().get_center()
	_activate_controller_menu_cursor()
	_snap_controller_cursor(Vector2.DOWN, true)


func _activate_controller_menu_cursor() -> void:
	if not _controller_primary_panel_open() or not is_instance_valid(controller_menu_cursor):
		return
	if not controller_cursor_active:
		var panel := _active_controller_panel()
		if is_instance_valid(panel):
			controller_cursor_position = panel.get_global_rect().get_center()
	controller_cursor_active = true
	controller_menu_cursor.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	_release_controller_menu_focus()
	_clamp_controller_cursor_to_panel()
	_position_controller_cursor()


func _deactivate_controller_menu_cursor() -> void:
	if not controller_cursor_active:
		return
	controller_cursor_active = false
	if is_instance_valid(controller_held_inventory_piece):
		_cancel_controller_held_inventory_piece()
	if is_instance_valid(controller_menu_cursor):
		controller_menu_cursor.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _update_controller_menu_cursor(delta: float) -> void:
	if not _controller_primary_panel_open():
		return
	var devices := Input.get_connected_joypads()
	if devices.is_empty():
		return
	var device := int(devices[0])
	var stick := Vector2(
		Input.get_joy_axis(device, JOY_AXIS_LEFT_X),
		Input.get_joy_axis(device, JOY_AXIS_LEFT_Y)
	)
	if stick.length() <= CONTROLLER_CURSOR_DEADZONE:
		return
	_activate_controller_menu_cursor()
	var strength := inverse_lerp(CONTROLLER_CURSOR_DEADZONE, 1.0, minf(stick.length(), 1.0))
	controller_cursor_position += stick.normalized() * strength * CONTROLLER_CURSOR_SPEED * delta
	_clamp_controller_cursor_to_panel()
	_position_controller_cursor()
	_warp_mouse_to_controller_cursor()
	_update_controller_held_piece_hover()


func _clamp_controller_cursor_to_panel() -> void:
	var panel := _active_controller_panel()
	if not is_instance_valid(panel):
		return
	var bounds := panel.get_global_rect().grow(-CONTROLLER_CURSOR_MARGIN)
	if bounds.size.x <= 0.0 or bounds.size.y <= 0.0:
		return
	controller_cursor_position = Vector2(
		clampf(controller_cursor_position.x, bounds.position.x, bounds.end.x),
		clampf(controller_cursor_position.y, bounds.position.y, bounds.end.y)
	)
	_position_controller_cursor()


func _position_controller_cursor() -> void:
	if is_instance_valid(controller_menu_cursor):
		controller_menu_cursor.position = controller_cursor_position - controller_menu_cursor.size * 0.5


func _send_controller_cursor_click() -> void:
	_warp_mouse_to_controller_cursor()
	for is_pressed: bool in [true, false]:
		var click := InputEventMouseButton.new()
		click.device = CONTROLLER_CURSOR_DEVICE
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = is_pressed
		click.position = controller_cursor_position
		click.global_position = controller_cursor_position
		click.button_mask = MOUSE_BUTTON_MASK_LEFT if is_pressed else 0
		Input.parse_input_event(click)
	call_deferred("_release_controller_menu_focus")


func _controller_cursor_accept() -> void:
	if _controller_panel_index() == 0:
		if is_instance_valid(controller_held_inventory_piece):
			if (
				is_instance_valid(parts_locker_workbench)
				and parts_locker_workbench.get_global_rect().has_point(controller_cursor_position)
				and parts_locker_workbench.has_method("controller_place_armed_piece_at_global_position")
			):
				parts_locker_workbench.call(
					"controller_place_armed_piece_at_global_position",
					controller_cursor_position
				)
				if (
					not is_instance_valid(parts_locker_refit_controller)
					or not bool(parts_locker_refit_controller.call("has_embedded_inventory_piece_armed"))
				):
					_finish_controller_held_inventory_piece()
				return
			return
		var inventory_piece := _controller_inventory_piece_at_cursor()
		if is_instance_valid(inventory_piece):
			_begin_controller_inventory_pickup(inventory_piece)
			return
	_send_controller_cursor_click()


func _controller_inventory_piece_at_cursor() -> Control:
	if not is_instance_valid(parts_locker_grid):
		return null
	for child: Node in parts_locker_grid.get_children():
		var piece := child as Control
		if (
			piece != null
			and piece.is_visible_in_tree()
			and piece.get_global_rect().has_point(controller_cursor_position)
			and piece is ForgeInventoryPiece
		):
			return piece
	return null


func _begin_controller_inventory_pickup(piece: Control) -> void:
	if not is_instance_valid(parts_locker_refit_controller):
		return
	parts_locker_refit_controller.call(
		"begin_embedded_inventory_piece_pickup",
		String(piece.get("room_type")),
		piece.get_instance_id()
	)
	if not bool(parts_locker_refit_controller.call("has_embedded_inventory_piece_armed")):
		return
	controller_held_inventory_piece = piece
	piece.modulate.a = 0.24
	if is_instance_valid(controller_menu_cursor):
		controller_menu_cursor.call(
			"hold_piece",
			Color(piece.get("piece_color")),
			Vector2i(piece.get("footprint")),
			String(piece.get("display_name"))
		)
	_update_controller_held_piece_hover()


func _update_controller_held_piece_hover() -> void:
	if (
		is_instance_valid(controller_held_inventory_piece)
		and is_instance_valid(parts_locker_workbench)
		and parts_locker_workbench.has_method("controller_hover_armed_piece_at_global_position")
	):
		parts_locker_workbench.call(
			"controller_hover_armed_piece_at_global_position",
			controller_cursor_position
		)


func _finish_controller_held_inventory_piece() -> void:
	if is_instance_valid(controller_held_inventory_piece):
		controller_held_inventory_piece.modulate = Color.WHITE
	controller_held_inventory_piece = null
	if is_instance_valid(controller_menu_cursor):
		controller_menu_cursor.call("release_piece")


func _cancel_controller_held_inventory_piece() -> void:
	if is_instance_valid(parts_locker_refit_controller):
		parts_locker_refit_controller.call("cancel_embedded_inventory_piece")
	_finish_controller_held_inventory_piece()


func _snap_controller_cursor(direction: Vector2, allow_any := false) -> void:
	_activate_controller_menu_cursor()
	var candidates := _controller_cursor_targets()
	if candidates.is_empty():
		return
	var best_position := controller_cursor_position
	var best_score := INF
	for candidate: Control in candidates:
		var candidate_position := candidate.get_global_rect().get_center()
		var offset := candidate_position - controller_cursor_position
		if offset.length_squared() < 4.0:
			continue
		var along := offset.dot(direction)
		if not allow_any and along <= 1.0:
			continue
		var sideways := absf(offset.cross(direction))
		var score := offset.length() if allow_any else along + sideways * 2.4
		if score < best_score:
			best_score = score
			best_position = candidate_position
	if best_score < INF:
		controller_cursor_position = best_position
		_clamp_controller_cursor_to_panel()
		_warp_mouse_to_controller_cursor()


func _warp_mouse_to_controller_cursor() -> void:
	# Windows can report the OS warp in physical-window coordinates while this
	# Control uses stretched viewport coordinates. Treat the short post-warp
	# motion window as controller-owned instead of comparing those two spaces.
	controller_cursor_warp_deadline = Time.get_ticks_msec() + 80
	Input.warp_mouse(controller_cursor_position)


func _controller_cursor_targets() -> Array[Control]:
	var panel := _active_controller_panel()
	var targets: Array[Control] = []
	if not is_instance_valid(panel):
		return targets
	for node: Node in panel.find_children("*", "Control", true, false):
		var control := node as Control
		if control == null or not control.is_visible_in_tree() or control.mouse_filter == Control.MOUSE_FILTER_IGNORE:
			continue
		if control is BaseButton or control is ForgeInventoryPiece:
			targets.append(control)
	if is_instance_valid(parts_locker_workbench) and parts_locker_workbench.is_visible_in_tree():
		targets.append(parts_locker_workbench)
	return targets


func _update_controller_menu_scroll(delta: float) -> void:
	if not _controller_primary_panel_open():
		return
	var devices := Input.get_connected_joypads()
	if devices.is_empty():
		return
	var axis := Input.get_joy_axis(int(devices[0]), JOY_AXIS_RIGHT_Y)
	if absf(axis) <= CONTROLLER_MENU_SCROLL_DEADZONE:
		return
	var panel := _active_controller_panel()
	if not is_instance_valid(panel):
		return
	var scrolls := panel.find_children("*", "ScrollContainer", true, false)
	for scroll_value: Node in scrolls:
		var scroll := scroll_value as ScrollContainer
		if scroll != null and scroll.is_visible_in_tree():
			scroll.scroll_vertical += roundi(axis * CONTROLLER_MENU_SCROLL_SPEED * delta)
			return


func _plot_contract_course(pickup_id: int) -> void:
	var combat := get_tree().get_first_node_in_group("combat_simulation")
	var ship := get_tree().get_first_node_in_group("ship_simulation")
	if not is_instance_valid(combat) or not is_instance_valid(ship):
		contract_panel.set_terminal_status("NAVIGATION LINK OFFLINE")
		return
	var transform: Dictionary = combat.call("get_grid_pickup_transform", pickup_id)
	if transform.is_empty():
		contract_panel.set_terminal_status("SALVAGE BEACON LOST")
		return
	ship.call(
		"set_course",
		Vector2(transform.get("position", Vector2.ZERO)),
		{
			"kind": "grid_pickup",
			"id": pickup_id,
			"local_offset": Vector2.ZERO,
		}
	)
	contract_panel.set_terminal_status("COURSE LOCKED • SALVAGE BEACON")
	contract_toggle.set_pressed_no_signal(false)
	_on_contracts_toggled(false)


func _refresh_diplomacy_terminal() -> void:
	if not is_instance_valid(diplomacy_rows):
		return
	for child: Node in diplomacy_rows.get_children():
		child.queue_free()
	var reputation := get_tree().get_first_node_in_group("reputation_simulation")
	if not is_instance_valid(reputation):
		return
	for report: Dictionary in reputation.call("get_all_faction_reports"):
		var row: Control = FACTION_REPUTATION_ROW.new()
		row.call("set_report", report)
		diplomacy_rows.add_child(row)


func _configure_parts_locker_panel() -> void:
	logistics_toggle.text = "PARTS LOCKER >"
	logistics_toggle.tooltip_text = "CLICK • OPEN RECOVERED GRID INVENTORY"
	# The locker is a contained in-flight console. Anchor it between the command
	# header and footer so child minimum sizes can never push it off-screen.
	logistics_overview_panel.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	logistics_overview_panel.offset_left = 20.0
	logistics_overview_panel.offset_top = 110.0
	logistics_overview_panel.offset_right = 535.0
	logistics_overview_panel.offset_bottom = -46.0
	logistics_overview_panel.clip_contents = true
	var controls := logistics_overview_panel.get_node("Margin/Controls") as VBoxContainer
	var title := controls.get_node("Title") as Label
	var subtitle := controls.get_node("Subtitle") as Label
	title.text = "PARTS LOCKER"
	subtitle.visible = false
	logistics_overview_status.visible = false
	%LogisticsSuppliesButton.visible = false
	%LogisticsCargoButton.visible = false

	var workbench_frame := PanelContainer.new()
	workbench_frame.name = "HullWorkbench"
	workbench_frame.custom_minimum_size = Vector2(0.0, 286.0)
	workbench_frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	workbench_frame.clip_contents = true
	var workbench_style := StyleBoxFlat.new()
	workbench_style.bg_color = Color(0.004, 0.025, 0.028, 0.96)
	workbench_style.border_color = Color(0.12, 0.56, 0.52, 0.9)
	workbench_style.border_width_left = 1
	workbench_style.border_width_top = 1
	workbench_style.border_width_right = 1
	workbench_style.border_width_bottom = 1
	workbench_style.corner_radius_top_left = 8
	workbench_frame.add_theme_stylebox_override("panel", workbench_style)
	controls.add_child(workbench_frame)
	var workbench_stack := VBoxContainer.new()
	workbench_stack.add_theme_constant_override("separation", 2)
	workbench_frame.add_child(workbench_stack)
	var workbench_header := HBoxContainer.new()
	workbench_header.custom_minimum_size.y = 28.0
	workbench_header.add_theme_constant_override("separation", 8)
	workbench_stack.add_child(workbench_header)
	var workbench_title := Label.new()
	workbench_title.text = "HULL WORKBENCH"
	workbench_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	workbench_title.add_theme_font_size_override("font_size", 13)
	workbench_title.add_theme_color_override("font_color", Color(0.48, 1.0, 0.88, 1.0))
	workbench_header.add_child(workbench_title)
	parts_locker_workbench_status = Label.new()
	parts_locker_workbench_status.visible = false
	parts_locker_resource_host = HBoxContainer.new()
	parts_locker_resource_host.name = "RefitResourceRail"
	parts_locker_resource_host.custom_minimum_size.y = 52.0
	parts_locker_resource_host.add_theme_constant_override("separation", 6)
	workbench_stack.add_child(parts_locker_resource_host)
	var workbench_body := HBoxContainer.new()
	workbench_body.add_theme_constant_override("separation", 6)
	workbench_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	workbench_stack.add_child(workbench_body)
	var ship := get_tree().get_first_node_in_group("ship_simulation")
	parts_locker_workbench = SETTLEMENT_GRID.new() as Control
	parts_locker_workbench.name = "ActiveHullWorkbench"
	parts_locker_workbench.custom_minimum_size = Vector2(274.0, 184.0)
	parts_locker_workbench.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parts_locker_workbench.size_flags_vertical = Control.SIZE_EXPAND_FILL
	if is_instance_valid(ship):
		parts_locker_workbench.set("ship_layout", ship.ship_layout)
	parts_locker_workbench.call("set_editor_mode", true)
	parts_locker_workbench.call("set_editor_viewport_constrained", true)
	workbench_body.add_child(parts_locker_workbench)
	# The selected-part console can contain tall controls (direction gimbal,
	# weapon doctrine, etc.).  Keep that content inside a fixed viewport so its
	# calculated minimum height cannot stretch the entire CanvasLayer past the
	# bottom of the game window.
	var refit_context_viewport := Control.new()
	refit_context_viewport.name = "RefitContextViewport"
	# A selected part is a working console, not a narrow tooltip.  Reserve enough
	# width for its name, resource lamps, output gauge, and facing control to read
	# as one deliberate instrument panel.
	refit_context_viewport.custom_minimum_size = Vector2(176.0, 184.0)
	refit_context_viewport.size_flags_horizontal = Control.SIZE_SHRINK_END
	refit_context_viewport.size_flags_vertical = Control.SIZE_EXPAND_FILL
	refit_context_viewport.clip_contents = true
	workbench_body.add_child(refit_context_viewport)
	parts_locker_refit_context = VBoxContainer.new()
	parts_locker_refit_context.name = "RefitContext"
	parts_locker_refit_context.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	refit_context_viewport.add_child(parts_locker_refit_context)

	var locker_frame := PanelContainer.new()
	locker_frame.name = "PartsLockerFrame"
	locker_frame.custom_minimum_size = Vector2(294.0, 98.0)
	locker_frame.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	locker_frame.size_flags_vertical = Control.SIZE_SHRINK_END
	var frame_style := StyleBoxFlat.new()
	frame_style.bg_color = Color(0.003, 0.018, 0.02, 0.98)
	frame_style.border_color = Color(0.08, 0.42, 0.4, 0.9)
	frame_style.border_width_left = 1
	frame_style.border_width_top = 1
	frame_style.border_width_right = 1
	frame_style.border_width_bottom = 1
	frame_style.corner_radius_top_left = 2
	frame_style.corner_radius_bottom_right = 10
	locker_frame.add_theme_stylebox_override("panel", frame_style)
	controls.add_child(locker_frame)

	var locker_margin := MarginContainer.new()
	locker_margin.add_theme_constant_override("margin_left", 6)
	locker_margin.add_theme_constant_override("margin_top", 6)
	locker_margin.add_theme_constant_override("margin_right", 6)
	locker_margin.add_theme_constant_override("margin_bottom", 6)
	locker_frame.add_child(locker_margin)
	var locker_scroll := ScrollContainer.new()
	locker_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	locker_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	locker_margin.add_child(locker_scroll)
	parts_locker_grid = FORGE_INVENTORY_GRID.new() as Container
	parts_locker_grid.name = "SharedGridInventory"
	parts_locker_grid.set("manual_layout", true)
	parts_locker_grid.call("set_capacity_rows", 3, true)
	parts_locker_grid.connect("piece_position_changed", _on_inventory_piece_position_changed)
	locker_scroll.add_child(parts_locker_grid)
	if is_instance_valid(ship):
		parts_locker_refit_controller = SHIP_BUILDER_SCREEN.instantiate() as ShipBuilderScreen
		parts_locker_refit_controller.name = "InlineRefitController"
		add_child(parts_locker_refit_controller)
		parts_locker_refit_controller.embedded_status_changed.connect(_on_inline_refit_status_changed)
		parts_locker_refit_layout = ship.ship_layout
		parts_locker_refit_controller.configure_embedded_refit(
			ship.ship_layout,
			ship,
			parts_locker_grid,
			parts_locker_workbench,
			parts_locker_refit_context,
			parts_locker_resource_host
		)
		parts_locker_workbench.call_deferred("fit_editor_view_to_hull")
	logistics_manifest_panel.visible = false
	logistics_detail_panel.visible = false
	_refresh_parts_locker()


func _refresh_logistics_overview() -> void:
	if is_instance_valid(parts_locker_workbench):
		parts_locker_workbench.queue_redraw()
	_refresh_parts_locker()


func _refresh_parts_locker() -> void:
	var ship := get_tree().get_first_node_in_group("ship_simulation")
	if not is_instance_valid(ship):
		logistics_overview_status.text = "LOCKER LINK OFFLINE"
		return
	var refit_locked := _field_refit_has_active_threats()
	if is_instance_valid(parts_locker_refit_controller):
		parts_locker_refit_controller.set_embedded_refit_locked(refit_locked)
	if is_instance_valid(parts_locker_workbench) and parts_locker_refit_layout != ship.ship_layout:
		parts_locker_refit_layout = ship.ship_layout
		parts_locker_refit_controller.configure_embedded_refit(
			ship.ship_layout,
			ship,
			parts_locker_grid,
			parts_locker_workbench,
			parts_locker_refit_context,
			parts_locker_resource_host
		)
		parts_locker_workbench.call_deferred("fit_editor_view_to_hull")
	if is_instance_valid(parts_locker_refit_controller):
		parts_locker_refit_controller.refresh_embedded_resource_meters()
	var inventory: Dictionary = ship.call("get_grid_piece_inventory")
	var keys := inventory.keys()
	keys.sort()
	var signature_parts: PackedStringArray = []
	var inventory_instances: Array[Dictionary] = []
	if ship.has_method("get_grid_piece_instances"):
		inventory_instances = ship.call("get_grid_piece_instances")
	for item: Dictionary in inventory_instances:
		signature_parts.append("%d:%s:%s:%s" % [
			int(item.get("instance_id", 0)),
			String(item.get("inventory_key", "")),
			str(item.get("current_health", 100.0)),
			str(item.get("breached", false)),
		])
	if inventory_instances.is_empty():
		for key_value: Variant in keys:
			signature_parts.append("%s:%d" % [String(key_value), int(inventory[key_value])])
	var signature := "|".join(signature_parts)
	if parts_locker_initialized and signature == parts_locker_signature:
		return
	parts_locker_signature = signature
	parts_locker_initialized = true
	for child: Node in parts_locker_grid.get_children():
		child.free()

	var pieces: Array[Dictionary] = []
	var total_grids := 0
	var pattern_count := 0
	if not inventory_instances.is_empty():
		var patterns := {}
		for inventory_instance: Dictionary in inventory_instances:
			var inventory_key := String(inventory_instance.get("inventory_key", ""))
			if inventory_key.is_empty():
				continue
			var descriptor: Dictionary = GRID_INVENTORY_CATALOG.describe(ship.ship_layout, inventory_key)
			descriptor["inventory_instance"] = inventory_instance
			pieces.append(descriptor)
			patterns[inventory_key] = true
		total_grids = pieces.size()
		pattern_count = patterns.size()
	else:
		for key_value: Variant in keys:
			var inventory_key := String(key_value)
			var count := maxi(int(inventory[key_value]), 0)
			if count <= 0:
				continue
			total_grids += count
			pattern_count += 1
			var descriptor: Dictionary = GRID_INVENTORY_CATALOG.describe(ship.ship_layout, inventory_key)
			for piece_index: int in range(count):
				pieces.append(descriptor)
	pieces.sort_custom(func(first: Dictionary, second: Dictionary) -> bool:
		return String(first["display_name"]) < String(second["display_name"])
	)
	for descriptor: Dictionary in pieces:
		var piece: Control = FORGE_INVENTORY_PIECE.new()
		piece.call(
			"configure",
			descriptor["room_type"],
			descriptor["display_name"],
			descriptor["color"],
			descriptor["footprint"],
			descriptor["power_capacity"],
			descriptor["power_draw"],
			descriptor["inventory_key"],
			descriptor["recipe"],
			int((descriptor.get("inventory_instance", {}) as Dictionary).get("instance_id", 0)),
			descriptor.get("inventory_instance", {}),
			int(descriptor.get("crew_required", 0))
		)
		piece.set("drag_enabled", true)
		piece.connect("selected", _on_parts_locker_piece_selected)
		var power_capacity := int(descriptor["power_capacity"])
		var power_draw := int(descriptor["power_draw"])
		var power_hint := "PROJECTS A REACTOR FIELD" if power_capacity > 0 else (
			"REQUIRES %d REACTOR FIELD%s" % [power_draw, "" if power_draw == 1 else "S"] if power_draw > 0 else "NO REACTOR LINK REQUIRED"
		)
		var crew_required := int(descriptor.get("crew_required", 0))
		var crew_hint := "CREW COMPLEMENT • %d" % crew_required if crew_required > 0 else "NO CREW STATIONS REQUIRED"
		piece.tooltip_text = "%s • %s\n%s\n%s\nDRAG • REARRANGE CARGO" % [
			String(descriptor["display_name"]).to_upper(),
			GRID_INVENTORY_CATALOG.footprint_label(descriptor["footprint"]),
			power_hint,
			crew_hint,
		]
		parts_locker_grid.add_child(piece)
	logistics_overview_status.text = "%d LOOSE GRID%s • %d PATTERN%s" % [
		total_grids,
		"" if total_grids == 1 else "S",
		pattern_count,
		"" if pattern_count == 1 else "S",
	]


func _on_parts_locker_piece_selected(room_type: String, source_instance_id: int) -> void:
	if is_instance_valid(parts_locker_refit_controller):
		parts_locker_refit_controller.select_embedded_inventory_piece(room_type, source_instance_id)


func _on_inline_refit_status_changed(message: String, is_error: bool) -> void:
	if not is_instance_valid(parts_locker_workbench_status):
		return
	parts_locker_workbench_status.text = message.to_upper()
	parts_locker_workbench_status.add_theme_color_override(
		"font_color",
		Color(1.0, 0.38, 0.2, 1.0) if is_error else Color(0.42, 1.0, 0.84, 1.0)
	)


func _on_inventory_piece_position_changed(inventory_instance_id: int, inventory_position: Vector2i) -> void:
	var ship := get_tree().get_first_node_in_group("ship_simulation")
	if not is_instance_valid(ship) or not ship.has_method("update_grid_piece_condition"):
		return
	ship.call("update_grid_piece_condition", inventory_instance_id, {"inventory_position": inventory_position})


func _on_parts_locker_workbench_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_open_field_refit()


func _open_field_refit() -> void:
	var ship := get_tree().get_first_node_in_group("ship_simulation")
	if not is_instance_valid(ship):
		return
	if _field_refit_has_active_threats():
		parts_locker_workbench_status.text = "REFIT INTERLOCK\nHOSTILE FIRE DETECTED"
		parts_locker_workbench_status.add_theme_color_override("font_color", Color(1.0, 0.36, 0.18, 1.0))
		return
	parts_locker_workbench_status.text = "FIELD REFIT READY\nCARGO LINK CONNECTED"
	parts_locker_workbench_status.add_theme_color_override("font_color", Color(0.58, 0.82, 0.76, 1.0))
	if logistics_toggle.button_pressed:
		logistics_toggle.set_pressed_no_signal(false)
		_on_logistics_toggled(false)
	if ship_builder_screen == null:
		ship_builder_screen = SHIP_BUILDER_SCREEN.instantiate() as ShipBuilderScreen
		add_child(ship_builder_screen)
		ship_builder_screen.grid_editor_requested.connect(_open_deck_grid_editor_from_shipyard)
	ship_builder_screen.open_for_layout(
		ship.ship_layout,
		"STATION",
		ship.call("get_grid_piece_inventory"),
		ship
	)


func _field_refit_has_active_threats() -> bool:
	var combat := get_node_or_null("CombatSimulation")
	if not is_instance_valid(combat):
		return false
	var contacts: Variant = combat.get("enemies")
	if not contacts is Array:
		return false
	for contact_value: Variant in contacts:
		if not contact_value is Dictionary:
			continue
		var contact: Dictionary = contact_value
		if float(contact.get("hull", 0.0)) > 0.0 and (
			bool(contact.get("combat_active", false))
			or bool(contact.get("defense_alert", false))
		):
			return true
	return false


func _open_logistics_manifest(capability_group: String) -> void:
	active_logistics_role = capability_group
	logistics_detail_panel.call("power_off")
	_populate_logistics_manifest()
	var source: Button = %LogisticsSuppliesButton if capability_group == "ENGINEERING" else %LogisticsCargoButton
	logistics_manifest_panel.call("power_on_from", source.get_global_rect().get_center())


func _populate_logistics_manifest() -> void:
	for child: Node in logistics_manifest_list.get_children():
		child.free()
	var ship := get_tree().get_first_node_in_group("ship_simulation")
	if not is_instance_valid(ship):
		return
	var capabilities: Array = ["DAMAGE_CONTROL"] if active_logistics_role == "ENGINEERING" else ["MEDICAL_CARE", "SECURITY_RESPONSE", "FLIGHT_SERVICE"]
	logistics_manifest_title.text = "ENGINEERING SERVICES" if active_logistics_role == "ENGINEERING" else "CREW SERVICES"
	var installed := 0
	var online := 0
	for capability: String in capabilities:
		var summary: Dictionary = ship.call("get_capability_summary", capability)
		installed += int(summary["installed"])
		online += int(summary["online"])
	logistics_manifest_summary.text = "%d INSTALLED • %d ONLINE" % [installed, online]
	if installed <= 0:
		var empty_label := Label.new()
		empty_label.text = "NO SERVICE GRID INSTALLED"
		empty_label.modulate = Color(0.48, 0.62, 0.6, 1.0)
		logistics_manifest_list.add_child(empty_label)
		return
	for capability: String in capabilities:
		for provider: Dictionary in ship.call("get_capability_providers", capability):
			logistics_manifest_list.add_child(_create_capability_card(provider, capability))


func _create_capability_card(provider: Dictionary, capability: String) -> Button:
	var card := Button.new()
	card.custom_minimum_size = Vector2(112, 124)
	card.text = "%s\n\n%s\n%d CHANNEL%s" % [
		_capability_glyph(capability),
		String(provider["reason"]),
		int(provider["channels"]),
		"" if int(provider["channels"]) == 1 else "S",
	]
	var readiness_parts: PackedStringArray = []
	var hull_percent := roundi(float(provider["health_ratio"]) * 100.0)
	var air_percent := roundi(float(provider["pressure"]) * 100.0)
	var power_percent := roundi(float(provider["power_factor"]) * 100.0)
	if hull_percent < 100:
		readiness_parts.append("HULL %d%%" % hull_percent)
	if air_percent < 100:
		readiness_parts.append("AIR %d%%" % air_percent)
	if power_percent < 100:
		readiness_parts.append("POWER %d%%" % power_percent)
	if int(provider["staff"]) <= 0:
		readiness_parts.append("NO CREW PRESENT")
	if readiness_parts.is_empty():
		readiness_parts.append("READY")
	readiness_parts.append("CLICK • INSPECT")
	card.tooltip_text = "".join(readiness_parts)
	card.add_theme_color_override("font_color", Color(0.48, 1.0, 0.84, 1.0) if bool(provider["online"]) else Color(1.0, 0.42, 0.24, 1.0))
	card.add_theme_font_size_override("font_size", 10)
	card.pressed.connect(_open_capability_provider_detail.bind(provider, capability, card))
	return card


func _open_capability_provider_detail(provider: Dictionary, capability: String, source: Button) -> void:
	logistics_detail_title.text = String(provider["name"])
	logistics_detail_meta.text = "%s • %s" % [_capability_label(capability), String(provider["reason"])]
	logistics_detail_icon.texture = null
	logistics_detail_glyph.visible = true
	logistics_detail_glyph.text = _capability_glyph(capability)
	logistics_detail_text.text = "SERVICE NODE\n\n%s\n\nREADINESS\nHull integrity • %d%%\nAtmosphere • %d%%\nPower feed • %d%%\nBay crew • %d\nOutfitting channels • %d\n\nCrew must physically reach this compartment before responding." % [
		"Repair tools and environmental gear" if capability == "DAMAGE_CONTROL" else _capability_label(capability).capitalize(),
		roundi(float(provider["health_ratio"]) * 100.0),
		roundi(float(provider["pressure"]) * 100.0),
		roundi(float(provider["power_factor"]) * 100.0),
		int(provider["staff"]),
		int(provider["channels"]),
	]
	logistics_detail_panel.call("power_on_from", source.get_global_rect().get_center())


func _capability_label(capability: String) -> String:
	match capability:
		"DAMAGE_CONTROL":
			return "DAMAGE CONTROL"
		"MEDICAL_CARE":
			return "MEDICAL CARE"
		"SECURITY_RESPONSE":
			return "SECURITY RESPONSE"
		"FLIGHT_SERVICE":
			return "FLIGHT SERVICE"
	return capability.replace("_", " ")


func _capability_glyph(capability: String) -> String:
	match capability:
		"DAMAGE_CONTROL":
			return "ENG"
		"MEDICAL_CARE":
			return "MED"
		"SECURITY_RESPONSE":
			return "SEC"
		"FLIGHT_SERVICE":
			return "FLT"
	return "SYS"


func _open_logistics_item_detail(stack: Dictionary, source: Button) -> void:
	var definition: Resource = stack["definition"]
	var quantity := int(stack["quantity"])
	var reserved := int(stack["reserved"])
	var ship := get_tree().get_first_node_in_group("ship_simulation")
	logistics_detail_title.text = String(definition.get("display_name"))
	logistics_detail_meta.text = "%s REGISTER • %s" % [
		active_logistics_role,
		String(definition.get("item_id")).to_upper(),
	]
	logistics_detail_icon.texture = _inventory_icon(definition, active_logistics_role, 72)
	var has_custom_icon := definition.get("icon") != null
	logistics_detail_glyph.visible = not has_custom_icon
	logistics_detail_glyph.text = _inventory_glyph(definition)
	var lines := PackedStringArray([
		"ITEM RECORD",
		"%s" % String(definition.get("description")),
		"------------------------------",
		"QUANTITY • %d" % quantity,
		"AVAILABLE • %d" % maxi(quantity - reserved, 0),
		"RESERVED • %d" % reserved,
		"VOLUME • %.2f EACH • %.2f TOTAL" % [float(definition.get("volume_per_unit")), quantity * float(definition.get("volume_per_unit"))],
		"",
		"STORAGE MAP",
	])
	var locations: Array[Dictionary] = ship.call("get_storage_locations", active_logistics_role) if is_instance_valid(ship) else []
	if locations.is_empty():
		lines.append("NO VALID STORAGE ROOM • ITEM INACCESSIBLE")
	else:
		for location: Dictionary in locations:
			lines.append("%s • %d CAP • HULL %d%% • AIR %d%% • %s" % [
				String(location["name"]), roundi(float(location["capacity"])), roundi(float(location["health_ratio"]) * 100.0),
				roundi(float(location["pressure"]) * 100.0), "ACCESSIBLE" if bool(location["accessible"]) else "OFFLINE",
			])
	logistics_detail_text.text = "\n".join(lines)
	logistics_detail_panel.call("power_on_from", source.get_global_rect().get_center())


func _create_inventory_card(stack: Dictionary) -> Control:
	var definition: Resource = stack["definition"]
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(112, 124)
	card.pivot_offset = Vector2(56, 62)
	var card_style := StyleBoxFlat.new()
	card_style.bg_color = Color(0.025, 0.045, 0.046, 0.96)
	card_style.border_width_left = 1
	card_style.border_width_top = 1
	card_style.border_width_right = 1
	card_style.border_width_bottom = 1
	card_style.border_color = Color(0.09, 0.32, 0.32, 1.0)
	card_style.corner_radius_top_left = 2
	card_style.corner_radius_bottom_right = 8
	card.add_theme_stylebox_override("panel", card_style)
	card.tooltip_text = _inventory_stack_tooltip(stack)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 6)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_right", 6)
	margin.add_theme_constant_override("margin_bottom", 6)
	card.add_child(margin)

	var stack_box := VBoxContainer.new()
	stack_box.add_theme_constant_override("separation", 4)
	margin.add_child(stack_box)

	var icon_stack := Control.new()
	icon_stack.custom_minimum_size = Vector2(88, 58)
	stack_box.add_child(icon_stack)

	var icon_frame := PanelContainer.new()
	icon_frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var icon_style := StyleBoxFlat.new()
	icon_style.bg_color = Color(0.015, 0.04, 0.044, 1.0)
	icon_style.border_width_left = 1
	icon_style.border_width_top = 1
	icon_style.border_width_right = 1
	icon_style.border_width_bottom = 1
	icon_style.border_color = Color(0.2, 0.74, 0.68, 1.0)
	icon_style.corner_radius_top_left = 2
	icon_style.corner_radius_bottom_right = 7
	icon_frame.add_theme_stylebox_override("panel", icon_style)
	icon_stack.add_child(icon_frame)

	var icon := TextureRect.new()
	icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	icon.offset_left = 6
	icon.offset_top = 6
	icon.offset_right = -6
	icon.offset_bottom = -6
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture = _inventory_icon(definition, active_logistics_role)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_stack.add_child(icon)

	var quantity_badge := Label.new()
	quantity_badge.anchor_left = 1.0
	quantity_badge.anchor_top = 1.0
	quantity_badge.anchor_right = 1.0
	quantity_badge.anchor_bottom = 1.0
	quantity_badge.offset_left = -42
	quantity_badge.offset_top = -20
	quantity_badge.offset_right = -3
	quantity_badge.offset_bottom = -3
	quantity_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	quantity_badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	quantity_badge.add_theme_color_override("font_color", Color(0.95, 1.0, 0.92, 1.0))
	quantity_badge.add_theme_font_size_override("font_size", 12)
	quantity_badge.text = "x%d" % int(stack["quantity"])
	quantity_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_stack.add_child(quantity_badge)

	var name_label := Label.new()
	name_label.custom_minimum_size = Vector2(0, 40)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.add_theme_color_override("font_color", Color(0.78, 0.96, 0.9, 1.0))
	name_label.add_theme_font_size_override("font_size", 10)
	name_label.text = _inventory_card_title(String(definition.get("display_name")))
	stack_box.add_child(name_label)

	var click_target := Button.new()
	click_target.flat = true
	click_target.text = ""
	click_target.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	click_target.tooltip_text = card.tooltip_text
	click_target.mouse_entered.connect(_set_inventory_card_hovered.bind(card, card_style, icon_style, true))
	click_target.mouse_exited.connect(_set_inventory_card_hovered.bind(card, card_style, icon_style, false))
	click_target.pressed.connect(_open_logistics_item_detail.bind(stack, click_target))
	card.add_child(click_target)
	return card


func _set_inventory_card_hovered(card: PanelContainer, card_style: StyleBoxFlat, icon_style: StyleBoxFlat, is_hovered: bool) -> void:
	if not is_instance_valid(card):
		return
	if is_hovered:
		card_style.bg_color = Color(0.035, 0.09, 0.088, 0.98)
		card_style.border_color = Color(0.42, 1.0, 0.88, 1.0)
		card_style.shadow_color = Color(0.1, 0.95, 0.85, 0.35)
		card_style.shadow_size = 8
		icon_style.border_color = Color(0.7, 1.0, 0.92, 1.0)
		icon_style.bg_color = Color(0.025, 0.08, 0.078, 1.0)
	else:
		card_style.bg_color = Color(0.025, 0.045, 0.046, 0.96)
		card_style.border_color = Color(0.09, 0.32, 0.32, 1.0)
		card_style.shadow_color = Color(0, 0, 0, 0)
		card_style.shadow_size = 0
		icon_style.border_color = Color(0.2, 0.74, 0.68, 1.0)
		icon_style.bg_color = Color(0.015, 0.04, 0.044, 1.0)
	card.add_theme_stylebox_override("panel", card_style)
	var tween := create_tween().set_parallel(true)
	tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(card, "scale", Vector2(1.04, 1.04) if is_hovered else Vector2.ONE, 0.12)
	tween.tween_property(card, "modulate", Color(1.08, 1.14, 1.1, 1.0) if is_hovered else Color.WHITE, 0.12)


func _inventory_stack_tooltip(stack: Dictionary) -> String:
	var definition: Resource = stack["definition"]
	var reserved := int(stack["reserved"])
	var lines: PackedStringArray = []
	var description := String(definition.get("description")).strip_edges()
	if not description.is_empty():
		lines.append(description)
	if reserved > 0:
		lines.append("%d RESERVED" % reserved)
	lines.append("CLICK • INSPECT")
	return "\n".join(lines)


func _inventory_card_title(display_name: String) -> String:
	var words := display_name.split(" ", false)
	if words.is_empty():
		return "UNKNOWN ITEM"
	var lines: PackedStringArray = []
	var current_line := ""
	for raw_word: String in words:
		var word := raw_word.to_upper()
		if current_line.is_empty():
			current_line = word
		elif current_line.length() + 1 + word.length() <= 12:
			current_line += " " + word
		else:
			lines.append(current_line)
			current_line = word
			if lines.size() >= 2:
				break
	if lines.size() < 2 and not current_line.is_empty():
		lines.append(current_line)
	if lines.size() > 2:
		lines.resize(2)
	if lines.is_empty():
		return display_name.left(12).to_upper()
	return "\n".join(lines)


func _inventory_glyph(definition: Resource) -> String:
	var display_name := String(definition.get("display_name"))
	var words := display_name.split(" ", false)
	if words.is_empty():
		return "ITM"
	if words.size() == 1:
		return String(words[0]).left(3).to_upper()
	return "%s%s" % [String(words[0]).left(1).to_upper(), String(words[1]).left(2).to_upper()]


func _inventory_icon(definition: Resource, storage_role: String, size: int = 54) -> Texture2D:
	var custom_icon: Texture2D = definition.get("icon")
	if custom_icon != null:
		return custom_icon
	var key := "%s:%s:%d" % [String(definition.get("item_id")), storage_role, size]
	if generated_inventory_icons.has(key):
		return generated_inventory_icons[key]
	var image := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	var base_color := Color(0.08, 0.35, 0.32, 1.0) if storage_role == "SUPPLY" else Color(0.36, 0.22, 0.08, 1.0)
	var edge_color := Color(0.42, 1.0, 0.88, 1.0) if storage_role == "SUPPLY" else Color(1.0, 0.62, 0.24, 1.0)
	var dark_color := Color(0.015, 0.035, 0.04, 1.0)
	for y: int in range(size):
		for x: int in range(size):
			var is_edge := x < 3 or y < 3 or x >= size - 3 or y >= size - 3
			var is_inner_edge := x == 8 or y == 8 or x == size - 9 or y == size - 9
			var diagonal := absf(float(x - y)) < 1.5 or absf(float((size - x) - y)) < 1.5
			var color := dark_color
			if is_edge:
				color = edge_color
			elif is_inner_edge:
				color = edge_color.darkened(0.25)
			elif diagonal and x > 10 and x < size - 10 and y > 10 and y < size - 10:
				color = base_color.lightened(0.18)
			else:
				color = base_color.darkened(float(y) / float(size) * 0.22)
			image.set_pixel(x, y, color)
	var texture := ImageTexture.create_from_image(image)
	generated_inventory_icons[key] = texture
	return texture


func _close_logistics_manifest() -> void:
	logistics_detail_panel.call("power_off")
	logistics_manifest_panel.call("power_off")


func _on_forge_toggled(is_open: bool) -> void:
	forge_toggle.text = "FORGE • CLOSE" if is_open else "FORGE >"
	_slide_forge_tab(true)
	if is_open:
		if is_instance_valid(contract_toggle) and contract_toggle.button_pressed:
			contract_toggle.set_pressed_no_signal(false)
			_on_contracts_toggled(false)
		if is_instance_valid(diplomacy_toggle) and diplomacy_toggle.button_pressed:
			diplomacy_toggle.set_pressed_no_signal(false)
			_on_diplomacy_toggled(false)
		if logistics_toggle.button_pressed:
			logistics_toggle.set_pressed_no_signal(false)
			_on_logistics_toggled(false)
		forge_panel.call("power_on_from", forge_toggle.get_global_rect().get_center())
	else:
		forge_panel.call("power_off")
		if not forge_tab_hovered:
			_slide_forge_tab(false)
	_sync_controller_menu_mode()


func _forge_option_popup_visible() -> bool:
	if not forge_toggle.button_pressed:
		return false
	for node: Node in forge_panel.find_children("*", "OptionButton", true, false):
		var option := node as OptionButton
		if option != null and option.get_popup().visible:
			return true
	return false


func _close_open_forge_option_popup() -> bool:
	if not forge_toggle.button_pressed:
		return false
	for node: Node in forge_panel.find_children("*", "OptionButton", true, false):
		var option := node as OptionButton
		if option != null and option.get_popup().visible:
			option.get_popup().hide()
			return true
	return false


func _on_forge_tab_mouse_entered() -> void:
	forge_tab_hovered = true
	_slide_forge_tab(true)


func _on_forge_tab_mouse_exited() -> void:
	forge_tab_hovered = false
	if not forge_toggle.button_pressed:
		_slide_forge_tab(false)


func _refresh_forge_tab_position() -> void:
	if not is_instance_valid(forge_toggle) or forge_toggle.size.x <= 0.0:
		return
	forge_toggle.position.x = _forge_tab_x(forge_tab_hovered or forge_toggle.button_pressed)


func _slide_forge_tab(reveal: bool) -> void:
	if not is_instance_valid(forge_toggle) or forge_toggle.size.x <= 0.0:
		return
	if forge_tab_tween != null and forge_tab_tween.is_valid():
		forge_tab_tween.kill()
	forge_tab_tween = create_tween()
	forge_tab_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	forge_tab_tween.tween_property(forge_toggle, "position:x", _forge_tab_x(reveal), FORGE_TAB_SLIDE_SECONDS)


func _forge_tab_x(revealed: bool) -> float:
	var viewport_width := get_viewport_rect().size.x
	if revealed:
		return viewport_width - FORGE_TAB_RIGHT_MARGIN - forge_toggle.size.x
	return viewport_width - FORGE_TAB_PEEK_WIDTH


func _populate_forge() -> void:
	var combat := get_tree().get_first_node_in_group("combat_simulation")
	if not is_instance_valid(combat):
		return
	forge_enemy_behavior.clear()
	for behavior_name: String in ["ANCHOR VECTOR", "INTERCEPT COMMAND", "CIRCULAR ATTACK", "BREAK CONTACT"]:
		forge_enemy_behavior.add_item(behavior_name)
	forge_enemy_behavior.select(combat.default_behavior)
	forge_blueprint_contact.clear()
	for definition: Resource in combat.ship_contact_definitions:
		forge_blueprint_contact.add_item(String(definition.get("display_name")))


func _add_forge_ship_builder_button() -> void:
	if forge_panel.has_node("Margin/Controls/ForgeShipBuilderButton"):
		return
	var controls := forge_panel.get_node_or_null("Margin/Controls") as VBoxContainer
	if controls == null:
		return
	var button := Button.new()
	button.name = "ForgeShipBuilderButton"
	button.text = "> DRYDOCK FABRICATOR"
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.tooltip_text = "CLICK • OPEN SHIPYARD"
	button.add_theme_font_size_override("font_size", 12)
	button.add_theme_stylebox_override("normal", forge_ship_editor_button.get_theme_stylebox("normal"))
	button.add_theme_stylebox_override("hover", forge_ship_editor_button.get_theme_stylebox("hover"))
	button.pressed.connect(_open_ship_builder)
	controls.add_child(button)
	if is_instance_valid(forge_structural_test_button):
		controls.move_child(button, forge_structural_test_button.get_index() + 1)


func _add_forge_combat_testing_button() -> void:
	if forge_panel.has_node("Margin/Controls/ForgeCombatTestingButton"):
		return
	var controls := forge_panel.get_node_or_null("Margin/Controls") as VBoxContainer
	if controls == null:
		return
	var button := Button.new()
	button.name = "ForgeCombatTestingButton"
	button.text = "> COMBAT TESTING SECTOR"
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.tooltip_text = "JUMP TO AN EMPTY LIVE-FIRE RANGE"
	button.add_theme_font_size_override("font_size", 12)
	button.add_theme_color_override("font_color", Color(1.0, 0.72, 0.2))
	button.add_theme_stylebox_override("normal", forge_ship_editor_button.get_theme_stylebox("normal"))
	button.add_theme_stylebox_override("hover", forge_ship_editor_button.get_theme_stylebox("hover"))
	button.add_theme_stylebox_override("focus", forge_ship_editor_button.get_theme_stylebox("hover"))
	button.pressed.connect(_enter_combat_testing)
	controls.add_child(button)
	var builder_button := controls.get_node_or_null("ForgeShipBuilderButton") as Button
	if is_instance_valid(builder_button):
		controls.move_child(button, builder_button.get_index() + 1)


func _enter_combat_testing() -> void:
	if pending_jump_destination != null:
		return
	if forge_toggle.button_pressed:
		forge_toggle.set_pressed_no_signal(false)
		_on_forge_toggled(false)
	if combat_testing_active:
		_open_combat_test_setup()
		return
	var destination := GeneratedSector.new()
	destination.sector_id = &"COMBAT_TESTING"
	destination.display_name = "FORGE COMBAT RANGE"
	destination.archetype_id = &"COMBAT_TEST"
	destination.environment_type = &"OPEN_SPACE"
	destination.sector_tags = PackedStringArray(["COMBAT_TEST", "EMPTY_SECTOR"])
	destination.faction_signals = PackedStringArray()
	destination.modifier_ids = PackedStringArray()
	destination.safe_radius = 2100.0
	destination.hazard_enabled = true
	destination.signal_color = Color(1.0, 0.68, 0.18)
	pending_combat_test_jump = true
	pending_jump_destination = destination
	if is_instance_valid(sector_jump_terminal):
		sector_jump_terminal.clear_routes()
	_play_transition_sound()
	var ship := get_tree().get_first_node_in_group("ship_simulation")
	var tactical_ship_visual: CanvasItem
	if is_instance_valid(current_view) and current_view.is_in_group("ship_view"):
		tactical_ship_visual = current_view.call("get_jump_transition_visual") as CanvasItem
	lightspeed_transition.begin_jump(destination, ship, tactical_ship_visual, current_view)


func _open_combat_test_setup() -> void:
	if combat_test_panel == null:
		combat_test_panel_layer = CanvasLayer.new()
		combat_test_panel_layer.name = "CombatTestSetupLayer"
		combat_test_panel_layer.layer = 240
		add_child(combat_test_panel_layer)
		combat_test_panel = COMBAT_TEST_SETUP_PANEL.new() as CombatTestSetupPanel
		combat_test_panel.name = "CombatTestSetupPanel"
		combat_test_panel.scenario_requested.connect(_deploy_combat_test_scenario)
		combat_test_panel.asteroid_field_requested.connect(_deploy_combat_test_asteroid_field)
		combat_test_panel.clear_requested.connect(_clear_combat_test_scenario)
		combat_test_panel_layer.add_child(combat_test_panel)
	combat_test_panel.open_panel(_combat_test_blueprints())


func _combat_test_blueprints() -> Array[Dictionary]:
	var blueprints: Array[Dictionary] = []
	var directory := DirAccess.open(COMBAT_TEST_BLUEPRINT_DIRECTORY)
	if directory != null:
		var files: PackedStringArray = []
		directory.list_dir_begin()
		var file_name := directory.get_next()
		while not file_name.is_empty():
			if not directory.current_is_dir() and file_name.get_extension().to_lower() == "tres":
				files.append(file_name)
			file_name = directory.get_next()
		directory.list_dir_end()
		files.sort()
		for saved_file: String in files:
			var path := "%s/%s" % [COMBAT_TEST_BLUEPRINT_DIRECTORY, saved_file]
			var layout := ResourceLoader.load(path) as Resource
			if layout == null:
				continue
			var display_name := String(layout.get("design_name")).strip_edges()
			if display_name.is_empty():
				display_name = saved_file.get_basename().capitalize()
			blueprints.append({
				"name": display_name,
				"path": path,
				"kind": String(layout.get("vessel_kind")).to_upper() if not String(layout.get("vessel_kind")).is_empty() else "SHIP",
			})
	if blueprints.is_empty() and ResourceLoader.exists(COMBAT_TEST_FALLBACK_BLUEPRINT_PATH):
		blueprints.append({
			"name": "BAREBONES STARTER",
			"path": COMBAT_TEST_FALLBACK_BLUEPRINT_PATH,
			"kind": "SHIP",
		})
	return blueprints


func _clear_combat_test_scenario() -> void:
	var combat := get_tree().get_first_node_in_group("combat_simulation")
	if is_instance_valid(combat):
		combat.call("clear_enemies")
	var population := get_tree().get_first_node_in_group("sector_population")
	if is_instance_valid(population):
		population.call("clear_combat_test_target_field")
		population.call("clear_combat_test_environment")


func _deploy_combat_test_asteroid_field(target_count: int) -> void:
	var combat := get_tree().get_first_node_in_group("combat_simulation")
	var population := get_tree().get_first_node_in_group("sector_population")
	if not is_instance_valid(combat) or not is_instance_valid(population):
		return
	combat.call("clear_enemies")
	population.call("clear_combat_test_environment")
	var deployed_count := int(population.call("spawn_combat_test_target_field", target_count))
	forge_status.text = "AUTOMATIC-FIRE RANGE • %d ASTEROID TARGETS DEPLOYED" % deployed_count


func _deploy_combat_test_scenario(configuration: Dictionary) -> void:
	var combat := get_tree().get_first_node_in_group("combat_simulation")
	if not is_instance_valid(combat):
		return
	combat.call("clear_enemies")
	var population := get_tree().get_first_node_in_group("sector_population")
	if is_instance_valid(population):
		population.call("clear_combat_test_target_field")
		population.call("clear_combat_test_environment")
		population.call("spawn_combat_test_environment", StringName(configuration.get("environment", &"CLEAR_SPACE")))
	var formation_centers: Array[Vector2] = [
		Vector2(-760.0, -430.0),
		Vector2(760.0, -430.0),
		Vector2(0.0, 820.0),
	]
	var player_ship := get_tree().get_first_node_in_group("ship_simulation")
	var scenario_origin := Vector2(player_ship.get("ship_position")) if is_instance_valid(player_ship) else Vector2.ZERO
	var total_spawned := 0
	var station_count := 0
	var groups: Array = configuration.get("factions", [])
	for group_index: int in range(groups.size()):
		var group: Dictionary = groups[group_index]
		var center_offset := formation_centers[group_index % formation_centers.size()]
		var center := scenario_origin + center_offset
		var tangent := center_offset.normalized().orthogonal()
		var combat_team := int(group.get("combat_team", group_index + 1))
		var station_path := String(group.get("station_blueprint_path", ""))
		if ResourceLoader.exists(station_path):
			var station_layout := load(station_path) as Resource
			if station_layout != null:
				combat.call(
					"spawn_combat_test_ship", station_layout,
					StringName(group.get("faction_id", &"UNAFFILIATED")), combat_team,
					center, Vector2.UP.angle_to((-center_offset).normalized()),
					"%s • %s" % [group.get("faction_name", "TEST GROUP"), group.get("station_name", "STATION")],
					Color(group.get("color", Color.WHITE)), bool(group.get("station_hostile_to_player", false)),
					bool(group.get("station_hostile_to_npcs", true))
				)
				station_count += 1
		var roster: Array = group.get("ships", [])
		var total_group_ships := 0
		for roster_entry: Dictionary in roster:
			total_group_ships += clampi(int(roster_entry.get("count", 0)), 0, 12)
		var deployed_in_group := 0
		for roster_entry: Dictionary in roster:
			var ship_count := clampi(int(roster_entry.get("count", 0)), 0, 12)
			var blueprint_path := String(roster_entry.get("blueprint_path", ""))
			if ship_count <= 0 or not ResourceLoader.exists(blueprint_path):
				continue
			var layout := load(blueprint_path) as Resource
			if layout == null:
				continue
			for ship_index: int in range(ship_count):
				var offset := (float(deployed_in_group) - float(total_group_ships - 1) * 0.5) * 150.0
				var spawn_position := center + (-center_offset).normalized() * 230.0 + tangent * offset
				var facing := Vector2.UP.angle_to((scenario_origin - spawn_position).normalized())
				deployed_in_group += 1
				combat.call(
					"spawn_combat_test_ship", layout,
					StringName(group.get("faction_id", &"UNAFFILIATED")), combat_team,
					spawn_position, facing,
					"%s • %s %02d" % [group.get("faction_name", "TEST GROUP"), roster_entry.get("ship_name", "SHIP"), ship_index + 1],
					Color(group.get("color", Color.WHITE)), bool(group.get("fleet_hostile_to_player", false)), true
				)
				total_spawned += 1
	var neutral_station: Dictionary = configuration.get("neutral_station", {})
	var neutral_path := String(neutral_station.get("blueprint_path", ""))
	if ResourceLoader.exists(neutral_path):
		var neutral_layout := load(neutral_path) as Resource
		if neutral_layout != null:
			combat.call(
				"spawn_combat_test_neutral_station", neutral_layout,
				scenario_origin + Vector2(0.0, -760.0), 0.0,
				String(neutral_station.get("station_name", "NEUTRAL STATION")),
				bool(neutral_station.get("hostile_to_player", false)),
				bool(neutral_station.get("hostile_to_npcs", false))
			)
			station_count += 1
	forge_status.text = "COMBAT RANGE • %d SHIPS • %d STATIONS • %s" % [total_spawned, station_count, String(configuration.get("environment", &"CLEAR_SPACE")).replace("_", " ")]


func _open_ship_builder() -> void:
	var ship := get_tree().get_first_node_in_group("ship_simulation")
	if not is_instance_valid(ship):
		return
	if ship_builder_screen == null:
		ship_builder_screen = SHIP_BUILDER_SCREEN.instantiate() as ShipBuilderScreen
		add_child(ship_builder_screen)
		ship_builder_screen.grid_editor_requested.connect(_open_deck_grid_editor_from_shipyard)
	if forge_toggle.button_pressed:
		forge_toggle.set_pressed_no_signal(false)
		_on_forge_toggled(false)
	ship_builder_screen.open_for_layout(ship.ship_layout, "FORGE")


func _start_escape_run() -> void:
	run_start_pending = true
	if run_prologue_terminal == null:
		run_prologue_layer = CanvasLayer.new()
		run_prologue_layer.name = "RunPrologueLayer"
		run_prologue_layer.layer = 230
		add_child(run_prologue_layer)
		run_prologue_terminal = RUN_PROLOGUE_TERMINAL_SCRIPT.new() as RunPrologueTerminal
		run_prologue_terminal.name = "RunPrologueTerminal"
		run_prologue_terminal.escape_confirmed.connect(_on_escape_prologue_confirmed)
		run_prologue_terminal.cancelled.connect(_on_escape_run_cancelled)
		run_prologue_layer.add_child(run_prologue_terminal)
	if forge_toggle.button_pressed:
		forge_toggle.set_pressed_no_signal(false)
		_on_forge_toggled(false)
		forge_panel.call("power_off", true)
	run_prologue_terminal.open_terminal()


func _on_escape_prologue_confirmed() -> void:
	_open_starter_ship_draft()


func _on_escape_run_cancelled() -> void:
	run_start_pending = false
	forge_status.text = "RUN SETUP • ABORTED"


func _open_starter_ship_draft() -> void:
	if starting_ship_terminal == null:
		starting_ship_terminal_layer = CanvasLayer.new()
		starting_ship_terminal_layer.name = "StartingShipTerminalLayer"
		starting_ship_terminal_layer.layer = 220
		add_child(starting_ship_terminal_layer)
		starting_ship_terminal = STARTING_SHIP_TERMINAL_SCRIPT.new() as StartingShipTerminal
		starting_ship_terminal.name = "StartingShipTerminal"
		starting_ship_terminal.ship_engaged.connect(_on_starter_ship_engaged)
		starting_ship_terminal.cancelled.connect(_on_starter_ship_draft_cancelled)
		starting_ship_terminal_layer.add_child(starting_ship_terminal)
	var randomizer := STARTING_SHIP_RANDOMIZER_SCRIPT.new() as StartingShipRandomizer
	var draft_rounds: Array[Dictionary] = randomizer.generate_draft_rounds()
	if forge_toggle.button_pressed:
		forge_toggle.set_pressed_no_signal(false)
		_on_forge_toggled(false)
		# The starter terminal pauses the tree as soon as it opens. Finish the
		# Forge shutdown immediately so its CRT collapse cannot freeze onscreen.
		forge_panel.call("power_off", true)
	starting_ship_terminal.open_terminal(draft_rounds)


func _on_starter_ship_draft_cancelled() -> void:
	if run_start_pending:
		run_start_pending = false
		if is_instance_valid(run_state):
			run_state.run_active = false
			_on_pursuit_trace_changed(run_state.get_pursuit_report())
	forge_status.text = "HANGAR ACQUISITION • ABORTED"


func _on_starter_ship_engaged(candidate: Dictionary) -> void:
	selected_starter_candidate = candidate
	var ship_name := String(candidate.get("name", "UNNAMED HULL"))
	var role := String(candidate.get("role", "ESCAPE PLATFORM"))
	forge_status.text = "STARTER LOCKED • %s" % ship_name
	print("ESCAPE HULL ACQUIRED • %s • %s" % [ship_name, role])
	if not run_start_pending:
		_show_starter_selection_message(ship_name, role)
		return
	_apply_starter_candidate(candidate)
	_open_escape_assembly()


func _apply_starter_candidate(candidate: Dictionary) -> void:
	var ship := get_tree().get_first_node_in_group("ship_simulation")
	if not is_instance_valid(ship):
		push_error("Starter draft could not be applied: missing ship simulation.")
		return
	var fresh_layout := ESCAPE_KEEL_BLUEPRINT.duplicate(true) as Resource
	var bridge_template: Resource
	for template: Resource in fresh_layout.get("room_types"):
		if String(template.get("type_name")) in ["COMMAND", "BRIDGE"]:
			bridge_template = template
			break
	if bridge_template == null:
		push_error("Starter draft could not be applied: bridge template missing.")
		return
	var bridge := bridge_template.duplicate(true) as Resource
	bridge.set("room_id", &"escape_keel_bridge")
	bridge.set("display_name", "ESCAPE BRIDGE")
	bridge.set("grid_rects", [Rect2i(Vector2i(4, 4), Vector2i(2, 2))])
	bridge.set("build_footprint_lattice", Vector2i(2, 2))
	bridge.set("installed_piece_count", 1)
	fresh_layout.set("design_name", "IMPOUND ESCAPE HULL")
	fresh_layout.set("lattice_version", 2)
	fresh_layout.set("build_origin", Vector2i.ZERO)
	fresh_layout.set("columns", 10)
	fresh_layout.set("rows", 12)
	fresh_layout.set("unlimited_build_space", true)
	var keel_rooms: Array[Resource] = [bridge]
	fresh_layout.set("rooms", keel_rooms)
	ship.set("ship_layout", fresh_layout)
	if fresh_layout.has_method("capture_core_frame"):
		fresh_layout.call("capture_core_frame", true)
	if ship.has_method("clear_grid_piece_inventory"):
		ship.call("clear_grid_piece_inventory")
	var starting_inventory: Array[String] = ["CREW_QUARTERS", "POWER", "PROPULSION", "WEAPON:light_ballistic_mount", "WEAPON:light_ballistic_mount"]
	for key_value: Variant in candidate.get("draft_inventory", []):
		var inventory_key := String(key_value)
		if not inventory_key.is_empty():
			starting_inventory.append(inventory_key)
	for inventory_key: String in starting_inventory:
		ship.call("add_grid_piece", inventory_key, 1)
	ship.call("refresh_rooms_from_layout")
	refresh_active_layout_views()
	parts_locker_signature = ""


func _open_escape_assembly() -> void:
	var ship := get_tree().get_first_node_in_group("ship_simulation")
	if not is_instance_valid(ship):
		return
	if ship_builder_screen == null:
		ship_builder_screen = SHIP_BUILDER_SCREEN.instantiate() as ShipBuilderScreen
		add_child(ship_builder_screen)
		ship_builder_screen.grid_editor_requested.connect(_open_deck_grid_editor_from_shipyard)
	if not ship_builder_screen.closed.is_connected(_on_escape_assembly_closed):
		ship_builder_screen.closed.connect(_on_escape_assembly_closed)
	escape_assembly_pending = true
	ship_builder_screen.open_for_layout(
		ship.ship_layout,
		"ESCAPE",
		ship.call("get_grid_piece_inventory"),
		ship
	)


func _on_escape_assembly_closed() -> void:
	if not escape_assembly_pending:
		return
	escape_assembly_pending = false
	run_start_pending = false
	var ship := get_tree().get_first_node_in_group("ship_simulation")
	if is_instance_valid(ship):
		ship.call("refresh_rooms_from_layout")
	var crew := get_tree().get_first_node_in_group("crew_simulation")
	if is_instance_valid(crew) and crew.has_method("reset_crew_for_new_run"):
		crew.call("reset_crew_for_new_run", 8)
	if is_instance_valid(run_state):
		run_state.begin_new_run()
	refresh_active_layout_views()
	parts_locker_signature = ""
	_begin_opening_sector_jump()


func _begin_opening_sector_jump() -> void:
	if not is_instance_valid(jump_director) or not is_instance_valid(lightspeed_transition):
		return
	var destination := jump_director.generate_opening_sector()
	pending_jump_destination = destination
	jump_director.commit_destination(destination)
	_play_transition_sound()
	var ship := get_tree().get_first_node_in_group("ship_simulation")
	var tactical_ship_visual: CanvasItem
	if is_instance_valid(current_view) and current_view.is_in_group("ship_view"):
		tactical_ship_visual = current_view.call("get_jump_transition_visual") as CanvasItem
	lightspeed_transition.begin_jump(destination, ship, tactical_ship_visual, current_view)
	_show_starter_selection_message(
		String(selected_starter_candidate.get("name", "ESCAPE HULL")),
		"CLAMPS RELEASED • LIGHT-SPEED VECTOR COMMITTED"
	)


func _show_starter_selection_message(ship_name: String, role: String) -> void:
	var message := Label.new()
	message.process_mode = Node.PROCESS_MODE_ALWAYS
	message.z_index = 500
	message.mouse_filter = Control.MOUSE_FILTER_IGNORE
	message.anchor_left = 0.5
	message.anchor_top = 0.12
	message.anchor_right = 0.5
	message.anchor_bottom = 0.12
	message.offset_left = -250.0
	message.offset_top = 0.0
	message.offset_right = 250.0
	message.offset_bottom = 46.0
	message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	message.add_theme_font_size_override("font_size", 13)
	message.add_theme_color_override("font_color", Color(1.0, 0.68, 0.24, 1.0))
	message.add_theme_stylebox_override("normal", _starter_message_style())
	message.text = "ESCAPE HULL ACQUIRED • %s\n%s" % [ship_name, role]
	add_child(message)
	message.modulate = Color(1.0, 0.72, 0.35, 0.0)
	message.position.y -= 10.0
	var tween := create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(message, "modulate", Color.WHITE, 0.16)
	tween.parallel().tween_property(message, "position:y", message.position.y + 10.0, 0.2).set_trans(Tween.TRANS_BACK)
	tween.tween_interval(1.8)
	tween.tween_property(message, "modulate:a", 0.0, 0.3)
	tween.tween_callback(message.queue_free)


func _starter_message_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.025, 0.012, 0.035, 0.94)
	style.border_width_bottom = 2
	style.border_color = Color(1.0, 0.46, 0.18, 0.92)
	style.corner_radius_bottom_right = 8
	return style


func _open_station_ship_builder() -> void:
	var ship := get_tree().get_first_node_in_group("ship_simulation")
	if not is_instance_valid(ship) or StringName(ship.get("docking_state")) != &"DOCKED":
		return
	if ship_builder_screen == null:
		ship_builder_screen = SHIP_BUILDER_SCREEN.instantiate() as ShipBuilderScreen
		add_child(ship_builder_screen)
		ship_builder_screen.grid_editor_requested.connect(_open_deck_grid_editor_from_shipyard)
	ship_builder_screen.open_for_layout(
		ship.ship_layout,
		"STATION",
		ship.call("get_grid_piece_inventory"),
		ship
	)


func _open_deck_grid_editor_from_shipyard() -> void:
	if ship_builder_screen != null and ship_builder_screen.visible:
		await ship_builder_screen.close()
	await _activate_settlement_grid_editor()


func _activate_settlement_grid_editor() -> void:
	if current_view_name != "Settlement":
		_show_view("Settlement")
		while is_transitioning:
			await get_tree().process_frame
		await get_tree().process_frame
	if not is_instance_valid(current_view):
		return
	if bool(current_view.get("damage_lab_mode")):
		current_view.call("_on_damage_lab_toggled", false)
	if not bool(current_view.get("editor_mode")):
		current_view.call("_on_editor_mode_toggled", true)
	_sync_forge_tool_indicators()


func _toggle_settlement_dev_tool(tool_name: String) -> void:
	if current_view_name != "Settlement":
		_show_view("Settlement")
		while is_transitioning:
			await get_tree().process_frame
		await get_tree().process_frame
	if not is_instance_valid(current_view):
		return
	if tool_name == "editor":
		current_view.call("toggle_dev_ship_editor")
	else:
		current_view.call("toggle_dev_structural_test")
	_sync_forge_tool_indicators()
	forge_toggle.set_pressed_no_signal(false)
	_on_forge_toggled(false)


func _deactivate_active_forge_tool() -> void:
	if current_view_name != "Settlement" or not is_instance_valid(current_view):
		return
	if bool(current_view.get("editor_mode")):
		current_view.call("toggle_dev_ship_editor")
	elif bool(current_view.get("damage_lab_mode")):
		current_view.call("toggle_dev_structural_test")
	_sync_forge_tool_indicators()


func _sync_forge_tool_indicators() -> void:
	var editor_active := false
	var structure_active := false
	if current_view_name == "Settlement" and is_instance_valid(current_view):
		editor_active = bool(current_view.get("editor_mode"))
		structure_active = bool(current_view.get("damage_lab_mode"))
	forge_ship_editor_button.set_pressed_no_signal(editor_active)
	forge_structural_test_button.set_pressed_no_signal(structure_active)
	forge_ship_editor_button.text = "> HULL GRID • ENGAGED" if editor_active else "> HULL GRID • STANDBY"
	forge_structural_test_button.text = "> DAMAGE LAB • ENGAGED" if structure_active else "> DAMAGE LAB • STANDBY"
	forge_active_indicator.visible = editor_active or structure_active
	if editor_active:
		forge_active_indicator.text = "HULL GRID • ENGAGED"
	elif structure_active:
		forge_active_indicator.text = "DAMAGE LAB • ENGAGED"
	forge_toggle.text = "FORGE • CLOSE" if forge_toggle.button_pressed else ("FORGE [LIVE] >" if editor_active or structure_active else "FORGE >")


func _forge_spawn_copy() -> void:
	var combat := get_tree().get_first_node_in_group("combat_simulation")
	if is_instance_valid(combat):
		combat.spawn_enemy()


func _forge_spawn_blueprint_contact() -> void:
	var combat := get_tree().get_first_node_in_group("combat_simulation")
	if is_instance_valid(combat) and forge_blueprint_contact.item_count > 0:
		combat.spawn_blueprint_contact(forge_blueprint_contact.selected)


func _forge_clear_enemies() -> void:
	var combat := get_tree().get_first_node_in_group("combat_simulation")
	if is_instance_valid(combat):
		combat.clear_enemies()


func _forge_spawn_grid_pickup() -> void:
	var combat := get_tree().get_first_node_in_group("combat_simulation")
	if not is_instance_valid(combat):
		return
	var pickup_id := int(combat.call("spawn_random_grid_pickup"))
	forge_status.text = (
		"GRID SALVAGE EJECTED • ID %d" % pickup_id
		if pickup_id >= 0
		else "GRID SALVAGE FAILED"
	)


func _forge_max_crew() -> void:
	var crew := get_tree().get_first_node_in_group("crew_simulation")
	if not is_instance_valid(crew) or not crew.has_method("fill_crew_to_capacity"):
		forge_status.text = "CREW MUSTER • SYSTEM OFFLINE"
		return
	var spawned := int(crew.call("fill_crew_to_capacity"))
	forge_status.text = (
		"CREW MUSTER • %d ARRIVED" % spawned
		if spawned > 0
		else "CREW MUSTER • BERTHS ALREADY FULL"
	)


func _forge_set_enemy_behavior(index: int) -> void:
	var combat := get_tree().get_first_node_in_group("combat_simulation")
	if is_instance_valid(combat):
		combat.set_all_enemy_behavior(index)


func _unhandled_key_input(event: InputEvent) -> void:
	if not event.is_pressed() or event.is_echo():
		return

	match event.keycode:
		KEY_1:
			_show_view("Ship")


## Reserved entry point for future captain-disembark gameplay.
## The Crew view remains intact, but is not part of normal ship command navigation.
func enter_captain_disembark_mode() -> void:
	mode_selector_layer.custom_minimum_size.x = 198.0
	mode_buttons["Crew"].visible = true
	mode_selector.visible = true
	_show_view("Crew")


func leave_captain_disembark_mode() -> void:
	mode_buttons["Crew"].visible = false
	mode_selector_layer.custom_minimum_size.x = 102.0
	_show_view("Ship")
	mode_selector.visible = false


func _show_view(view_name: String) -> void:
	if not VIEW_SCENES.has(view_name) or view_name == current_view_name or is_transitioning:
		return

	if not is_instance_valid(current_view):
		_add_view(view_name)
		return

	is_transitioning = true
	_set_navigation_enabled(false)
	_play_transition_sound()
	if current_view_name == "Ship":
		var outgoing_zoom_controller := current_view.get_node_or_null("%ZoomController")
		if is_instance_valid(outgoing_zoom_controller):
			tactical_zoom_level = float(outgoing_zoom_controller.get("zoom_level"))

	var zooming_in: bool = int(VIEW_DEPTH[view_name]) > int(VIEW_DEPTH[current_view_name])
	var outgoing_scale := Vector2(1.14, 1.14) if zooming_in else Vector2(0.86, 0.86)
	current_view.pivot_offset = current_view.size * 0.5

	var outgoing_tween := create_tween().set_parallel(true)
	outgoing_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	outgoing_tween.tween_property(current_view, "scale", outgoing_scale, transition_duration * 0.5)
	outgoing_tween.tween_property(current_view, "modulate", Color(1, 1, 1, 0), transition_duration * 0.5)
	await outgoing_tween.finished

	content_host.remove_child(current_view)
	current_view.queue_free()
	_add_view(view_name)
	await get_tree().process_frame

	current_view.pivot_offset = current_view.size * 0.5
	current_view.scale = Vector2(0.86, 0.86) if zooming_in else Vector2(1.14, 1.14)
	current_view.modulate = Color(1, 1, 1, 0)

	var incoming_tween := create_tween().set_parallel(true)
	incoming_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	incoming_tween.tween_property(current_view, "scale", Vector2.ONE, transition_duration * 0.5)
	incoming_tween.tween_property(current_view, "modulate", Color.WHITE, transition_duration * 0.5)
	await incoming_tween.finished

	is_transitioning = false
	_set_navigation_enabled(true)


func _add_view(view_name: String) -> void:
	current_view_name = view_name

	current_view = VIEW_SCENES[view_name].instantiate()
	content_host.add_child(current_view)
	if view_name == "Ship":
		current_view.add_child(preload("res://scripts/weapons_hud.gd").new())
	if view_name == "Ship" and current_view.has_signal("station_drydock_requested"):
		current_view.connect("station_drydock_requested", _open_station_ship_builder)
	current_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	refresh_active_layout_views()
	if view_name == "Ship":
		var incoming_zoom_controller := current_view.get_node_or_null("%ZoomController")
		if (
			is_instance_valid(incoming_zoom_controller)
			and incoming_zoom_controller.has_method("set_zoom_level")
		):
			incoming_zoom_controller.call("set_zoom_level", tactical_zoom_level)
	if current_view.has_method("prepare_for_display"):
		current_view.call("prepare_for_display")

	var view_label: String = {
		"Ship": "COMMAND VIEW",
		"Settlement": "DECK VIEW",
		"Crew": "CREW VIEW",
	}.get(view_name, "VIEW")
	current_view_label.text = view_label
	for button_name: String in mode_buttons:
		mode_buttons[button_name].button_pressed = button_name == view_name
	await get_tree().process_frame
	_slide_mode_light_to(view_name, transition_duration * 0.42)


func refresh_active_layout_views() -> void:
	var ship := get_tree().get_first_node_in_group("ship_simulation")
	if not is_instance_valid(ship) or not is_instance_valid(current_view):
		return
	var layout: Resource = ship.get("ship_layout")
	if layout == null:
		return
	if current_view.has_method("refresh_player_ship_layout"):
		current_view.call("refresh_player_ship_layout", layout)
	else:
		var tactical_visual := current_view.get_node_or_null("%PlaceholderShip")
		if tactical_visual != null and tactical_visual.has_method("set_ship_layout"):
			tactical_visual.call("set_ship_layout", layout)
	var settlement_grid := current_view.get_node_or_null("%SettlementGrid")
	if settlement_grid != null:
		settlement_grid.set("ship_layout", layout)
		if settlement_grid.has_method("refresh_layout"):
			settlement_grid.call("refresh_layout")
	var crew_world := current_view.get_node_or_null("%World")
	if crew_world != null and crew_world.get("ship_layout") != null:
		crew_world.set("ship_layout", layout)
		if crew_world.has_method("_update_size_from_layout"):
			crew_world.call("_update_size_from_layout")
		crew_world.queue_redraw()


func _slide_mode_light_to(view_name: String, duration: float = 0.16) -> void:
	if not mode_buttons.has(view_name) or not is_instance_valid(mode_selector_light):
		return
	var target_button: Button = mode_buttons[view_name]
	if not is_instance_valid(target_button):
		return
	var target_position := target_button.position
	var target_size := target_button.size
	if target_size.x <= 0.0 or target_size.y <= 0.0:
		target_size = target_button.custom_minimum_size
	if mode_light_tween != null and mode_light_tween.is_valid():
		mode_light_tween.kill()
	if duration <= 0.0:
		mode_selector_light.position = target_position
		mode_selector_light.size = target_size
		return
	mode_light_tween = create_tween().set_parallel(true)
	mode_light_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	mode_light_tween.tween_property(mode_selector_light, "position", target_position, duration)
	mode_light_tween.tween_property(mode_selector_light, "size", target_size, duration)


func _set_navigation_enabled(is_enabled: bool) -> void:
	for button: Button in mode_buttons.values():
		button.disabled = not is_enabled


func _play_transition_sound() -> void:
	if transition_sound == null:
		return

	transition_audio.stream = transition_sound
	transition_audio.play()
