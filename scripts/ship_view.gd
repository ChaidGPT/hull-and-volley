extends Control

signal station_drydock_requested

const WORLD_ORIGIN := Vector2(5000, 5000)
const ENEMY_VISUAL_SCENE := preload("res://scenes/enemy_ship_visual.tscn")
const GRID_PICKUP_VISUAL := preload("res://scripts/forge_inventory_piece.gd")
const FLIGHT_DESTINATION_INDICATOR := preload("res://scripts/flight_destination_indicator.gd")
const SECTOR_HAZARD_HUD := preload("res://scripts/sector_hazard_hud.gd")
const COMMUNICATION_PANEL := preload("res://scripts/communication_panel.gd")
const GRID_GEOMETRY := preload("res://scripts/grid_geometry.gd")
const TACTICAL_SHIP_VISUAL_SCRIPT := preload("res://scripts/tactical_ship_visual.gd")
const IMPACT_SPRITE_BURST_SCENE := preload("res://scenes/projectiles/impact_sprite_burst.tscn")

const FIRE_MODE_LINKED := 0
const FIRE_MODE_TRIGGER := 1
const FIRE_MODE_SENTRY := 2

@export_category("Automatic Camera Follow")
@export_range(0.5, 10.0, 0.25) var follow_delay := 3.0
@export_range(0.25, 8.0, 0.25) var recenter_speed := 1.75

@export_category("Ship Labels")
@export_range(0.5, 12.0, 0.5) var label_fade_speed := 5.0
@export_range(0.0, 2.0, 0.05) var label_fade_start_zoom := 0.8
@export_range(0.0, 2.0, 0.05) var label_hidden_zoom := 0.45

@export_category("Unified Command / Deck Camera")
## At close range the tactical silhouette resolves into its live deck plan.
@export_range(1.0, 3.0, 0.05) var deck_detail_zoom := 2.0
## Width of the cross-fade between the exterior command silhouette and live deck.
@export_range(0.05, 1.0, 0.05) var deck_detail_blend_width := 0.35
## Deck framing stays fixed until the ship reaches this inset viewport boundary.
@export_range(0.0, 0.45, 0.01) var deck_camera_leash_margin := 0.15
## Exponential zoom response at full right-stick deflection.
@export_range(0.25, 3.0, 0.05) var controller_zoom_speed := 1.25

@export_category("Direct Fire")
@export var direct_fire_ready_color := Color(0.25, 1.0, 0.84, 0.9)
@export var direct_fire_reloading_color := Color(1.0, 0.68, 0.18, 0.78)
@export var direct_fire_blocked_color := Color(1.0, 0.24, 0.18, 0.42)
@export var direct_fire_disabled_color := Color(0.38, 0.42, 0.45, 0.32)

@export_category("Context Panel CRT Transition")
## Time for the bright horizontal CRT line to expand across the panel when opening.
@export_range(0.02, 0.5, 0.01) var crt_horizontal_time := 0.1
## Time for the CRT image to expand vertically after the horizontal line appears.
@export_range(0.02, 0.5, 0.01) var crt_vertical_time := 0.14
## Thin vertical scale used for the old television power-on line.
@export_range(0.01, 0.2, 0.01) var crt_line_scale := 0.04

@onready var world: Control = %World
@onready var starfield: Control = %Starfield
@onready var ship_visual: Control = %PlaceholderShip
@onready var shield_visual: Control = %ShieldVisual
@onready var zoom_controller: Node = %ZoomController
@onready var weapons_free_button: Button = %WeaponsFreeButton
@onready var center_mass_button: Button = %CenterMassButton
@onready var manual_button: Button = %ManualButton
@onready var manual_status: Label = %ManualStatus
@onready var manual_target_line: Line2D = %ManualTargetLine
@onready var targeting_panel: PanelContainer = %TargetingPanel
@onready var contact_panel_title: Label = %ContactPanelTitle
@onready var contact_name: Label = %ContactName
@onready var contact_status: Label = %ContactStatus
@onready var combat_contact_actions: VBoxContainer = %CombatContactActions
@onready var contact_target_toggle: Button = %ContactTargetToggle
@onready var safe_contact_actions: VBoxContainer = %SafeContactActions
@onready var safe_contact_action_title: Label = %SafeContactActionTitle
@onready var safe_contact_action: Button = %SafeContactAction
@onready var safe_contact_feedback: Label = %SafeContactFeedback
@onready var docked_panel: PanelContainer = %DockedPanel
@onready var docked_contact_name: Label = %DockedContactName
@onready var close_docked_panel_button: Button = %CloseDockedPanelButton
@onready var station_drydock_button: Button = %StationDrydockButton
@onready var station_repair_button: Button = %StationRepairButton
@onready var station_market_button: Button = %StationMarketButton
@onready var station_crew_button: Button = %StationCrewButton
@onready var station_service_status: Label = %StationServiceStatus
@onready var release_clamps_button: Button = %ReleaseClampsButton
@onready var dev_menu_toggle: Button = %DevMenuToggle
@onready var dev_menu: PanelContainer = %DevMenu
@onready var enemy_behavior_selector: OptionButton = %EnemyBehaviorSelector
@onready var enemy_count_label: Label = %EnemyCountLabel
@onready var sample_ship_selector: OptionButton = %SampleShipSelector

var simulation
var combat_simulation
var sector_simulation
var reputation_simulation
var dialogue_simulation
var quest_simulation
var sector_hazard_hud: Control
var communication_panel: CommunicationPanel
var docking_annunciator: PanelContainer
var docking_annunciator_lamp: ColorRect
var docking_annunciator_label: Label
var enemy_shield_bank_weight_cache: Dictionary = {}
var docking_annunciator_blink_tween: Tween
var docking_annunciator_intro_tween: Tween
var open_communications_button: Button
var safe_training_action: Button
var combat_training_action: Button
var communication_contact: Dictionary = {}
var communication_pause_was_active := false
var camera_idle_time := 0.0
var camera_following := true
var ship_labels: Array[Label] = []
var ship_label_alpha := 0.0
var enemy_visuals: Dictionary = {}
var projectile_visuals: Dictionary = {}
var fragment_visuals: Dictionary = {}
var fighter_visuals: Dictionary = {}
var grid_pickup_visuals: Dictionary = {}
var is_bending_route_segment := false
var route_drag_armed := false
var route_drag_start := Vector2.ZERO
var rotation_drag_armed := false
var rotation_dragging := false
var rotation_drag_start := Vector2.ZERO
var translation_preview_armed := false
var selected_tactical_ship_id := -1
var context_panel_tween: Tween
var context_panel_source_global := Vector2.ZERO
var contact_channel_states: Dictionary = {}
var direct_fire_active := false
var direct_fire_lines: Array[Line2D] = []
const CONTROLLER_STICK_DEADZONE := 0.22
const CONTROLLER_TRIGGER_THRESHOLD := 0.35
var controller_aim_direction := Vector2.UP
var controller_aim_active := false
var controller_fire_was_pressed := false
var controller_hold_was_pressed := false
var controller_recenter_was_pressed := false
var controller_menu_active := false
var controller_translation_indicator_input := Vector2.ZERO
var controller_translation_indicator_alpha := 0.0
var controller_translation_indicator: Node2D
var controller_aim_indicator_alpha := 0.0
var controller_aim_indicator: Node2D
var deck_detail_visual: Control
var deck_detail_mix := 0.0
var selected_compartment_id: StringName = &""
var compartment_actions: VBoxContainer
var compartment_integrity_bar: ProgressBar
var compartment_output_bar: ProgressBar
var compartment_atmosphere: Label
var compartment_crew: Label
var compartment_staffing_button: Button
var compartment_repair_button: Button
var compartment_weapon_modes: HBoxContainer
var compartment_fire_buttons: Array[Button] = []


func _ready() -> void:
	add_to_group("ship_view")
	simulation = get_tree().get_first_node_in_group("ship_simulation")
	combat_simulation = get_tree().get_first_node_in_group("combat_simulation")
	sector_simulation = get_tree().get_first_node_in_group("sector_simulation")
	reputation_simulation = get_tree().get_first_node_in_group("reputation_simulation")
	dialogue_simulation = get_tree().get_first_node_in_group("dialogue_simulation")
	quest_simulation = get_tree().get_first_node_in_group("quest_simulation")
	if not is_instance_valid(simulation):
		push_error("Ship view could not find the persistent ship simulation.")
		return
	_rebuild_ship_label_cache()
	zoom_controller.connect("camera_manipulated", _on_camera_manipulated)
	weapons_free_button.pressed.connect(_set_targeting_doctrine.bind(0))
	center_mass_button.pressed.connect(_set_targeting_doctrine.bind(1))
	manual_button.pressed.connect(_set_targeting_doctrine.bind(2))
	contact_target_toggle.toggled.connect(_on_contact_target_toggled)
	safe_contact_action.pressed.connect(_on_safe_contact_action_pressed)
	_create_communication_interface()
	close_docked_panel_button.pressed.connect(_on_close_docked_panel_pressed)
	station_drydock_button.pressed.connect(_on_station_drydock_pressed)
	station_repair_button.pressed.connect(_on_unavailable_station_service_pressed.bind("REPAIR YARD"))
	station_market_button.pressed.connect(_on_unavailable_station_service_pressed.bind("NIGHT MARKET"))
	station_crew_button.pressed.connect(_on_unavailable_station_service_pressed.bind("CREW EXCHANGE"))
	release_clamps_button.pressed.connect(_on_release_clamps_pressed)
	simulation.connect("docking_completed", _on_docking_completed)
	simulation.connect("docking_cancelled", _on_docking_cancelled)
	simulation.connect("undocking_completed", _on_undocking_completed)
	simulation.connect("docking_state_changed", _on_docking_state_changed)
	_set_targeting_doctrine(simulation.targeting_doctrine)
	dev_menu_toggle.toggled.connect(_on_dev_menu_toggled)
	%SpawnEnemyButton.pressed.connect(_spawn_enemy)
	%SpawnSampleShipButton.pressed.connect(_spawn_sample_enemy)
	%ClearEnemiesButton.pressed.connect(_clear_enemies)
	enemy_behavior_selector.item_selected.connect(_on_enemy_behavior_selected)
	_populate_enemy_behaviors()
	_populate_sample_ships()
	if is_instance_valid(combat_simulation):
		combat_simulation.connect("shield_impact_detected", _on_shield_impact_detected)
		combat_simulation.connect("impact_effect_requested", _on_impact_effect_requested)
		combat_simulation.connect("player_ship_destroyed", _on_player_ship_destroyed)
	ship_visual.visible = not bool(simulation.get("is_destroyed"))
	_create_deck_detail_visual()
	_create_compartment_interface()
	_create_sector_hazard_hud()
	_create_docking_annunciator()
	_create_controller_translation_indicator()
	call_deferred("_center_camera_on_ship")
	call_deferred("_initialize_context_panel")


func refresh_player_ship_layout(layout: Resource) -> void:
	if layout == null or not is_instance_valid(ship_visual):
		return
	if ship_visual.has_method("set_ship_layout"):
		ship_visual.call("set_ship_layout", layout)
	if is_instance_valid(deck_detail_visual) and deck_detail_visual.has_method("set_ship_layout"):
		deck_detail_visual.call("set_ship_layout", layout)
	# Refit can change the visual bounds while both layers are sharing a cross-fade.
	# Recenter both pivots together so rotation cannot pull the tactical silhouette
	# away from the live deck representation.
	ship_visual.pivot_offset = ship_visual.size * 0.5
	if is_instance_valid(deck_detail_visual):
		deck_detail_visual.pivot_offset = deck_detail_visual.size * 0.5
		_sync_deck_detail_transform()
	_rebuild_ship_label_cache()


func prepare_for_display() -> void:
	if not is_instance_valid(simulation) or not is_instance_valid(ship_visual):
		return
	ship_visual.pivot_offset = ship_visual.size * 0.5
	ship_visual.position = (
		WORLD_ORIGIN
		+ simulation.ship_position
		- ship_visual.pivot_offset
	)
	ship_visual.rotation = simulation.ship_rotation
	_sync_deck_detail_transform()
	world.pivot_offset = WORLD_ORIGIN
	world.position = size * 0.5 - WORLD_ORIGIN - simulation.ship_position
	starfield.call("reset_camera_position", world.position)


func _rebuild_ship_label_cache() -> void:
	ship_labels.clear()
	if not is_instance_valid(ship_visual):
		return
	for node: Node in ship_visual.find_children("*", "Label", true, false):
		var label := node as Label
		if not is_instance_valid(label):
			continue
		label.modulate.a = ship_label_alpha
		ship_labels.append(label)


func _initialize_context_panel() -> void:
	targeting_panel.pivot_offset = targeting_panel.size * 0.5
	targeting_panel.visible = false
	targeting_panel.scale = Vector2.ZERO


func _create_deck_detail_visual() -> void:
	if is_instance_valid(deck_detail_visual) or not is_instance_valid(ship_visual):
		return
	deck_detail_visual = TACTICAL_SHIP_VISUAL_SCRIPT.new() as Control
	deck_detail_visual.name = "LiveDeckDetail"
	deck_detail_visual.mouse_filter = Control.MOUSE_FILTER_IGNORE
	deck_detail_visual.set("ship_layout", simulation.get("ship_layout"))
	world.add_child(deck_detail_visual)
	world.move_child(deck_detail_visual, ship_visual.get_index() + 1)
	deck_detail_visual.call("set_deck_detail_visible", true)
	deck_detail_visual.call("set_simulation_identity", 0, 0)
	deck_detail_visual.add_to_group("player_weapon_muzzle_provider")
	deck_detail_visual.modulate.a = 0.0
	deck_detail_visual.process_mode = Node.PROCESS_MODE_DISABLED
	_sync_deck_detail_transform()


func _sync_deck_detail_transform() -> void:
	if not is_instance_valid(deck_detail_visual) or not is_instance_valid(ship_visual):
		return
	deck_detail_visual.position = ship_visual.position
	deck_detail_visual.rotation = ship_visual.rotation
	deck_detail_visual.pivot_offset = deck_detail_visual.size * 0.5


func _create_compartment_interface() -> void:
	if is_instance_valid(compartment_actions):
		return
	var content := targeting_panel.get_node("Margin/Content") as VBoxContainer
	compartment_actions = VBoxContainer.new()
	compartment_actions.name = "CompartmentActions"
	compartment_actions.visible = false
	compartment_actions.add_theme_constant_override("separation", 5)
	content.add_child(compartment_actions)

	compartment_integrity_bar = _new_compartment_bar(Color(0.36, 0.86, 0.58))
	compartment_integrity_bar.tooltip_text = "COMPARTMENT STRUCTURE"
	compartment_actions.add_child(compartment_integrity_bar)
	compartment_output_bar = _new_compartment_bar(Color(0.24, 0.92, 0.94))
	compartment_output_bar.tooltip_text = "SYSTEM OUTPUT"
	compartment_actions.add_child(compartment_output_bar)

	compartment_atmosphere = _new_compartment_label(Color(0.45, 0.9, 0.95))
	compartment_actions.add_child(compartment_atmosphere)
	compartment_crew = _new_compartment_label(Color(0.5, 1.0, 0.78))
	compartment_actions.add_child(compartment_crew)

	var orders := HBoxContainer.new()
	orders.add_theme_constant_override("separation", 5)
	compartment_actions.add_child(orders)
	compartment_staffing_button = Button.new()
	compartment_staffing_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	compartment_staffing_button.custom_minimum_size.y = 27.0
	compartment_staffing_button.add_theme_font_size_override("font_size", 10)
	compartment_staffing_button.pressed.connect(_on_compartment_staffing_pressed)
	orders.add_child(compartment_staffing_button)
	compartment_repair_button = Button.new()
	compartment_repair_button.text = "REPAIR >"
	compartment_repair_button.custom_minimum_size = Vector2(82.0, 27.0)
	compartment_repair_button.add_theme_font_size_override("font_size", 10)
	compartment_repair_button.pressed.connect(_on_compartment_repair_pressed)
	orders.add_child(compartment_repair_button)

	compartment_weapon_modes = HBoxContainer.new()
	compartment_weapon_modes.add_theme_constant_override("separation", 4)
	compartment_actions.add_child(compartment_weapon_modes)
	for mode_data: Dictionary in [
		{"label": "LINKED", "mode": FIRE_MODE_LINKED},
		{"label": "TRIGGER", "mode": FIRE_MODE_TRIGGER},
		{"label": "SENTRY", "mode": FIRE_MODE_SENTRY},
	]:
		var button := Button.new()
		button.text = String(mode_data["label"])
		button.toggle_mode = true
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size.y = 25.0
		button.add_theme_font_size_override("font_size", 9)
		button.pressed.connect(_on_compartment_fire_mode_pressed.bind(int(mode_data["mode"])))
		compartment_weapon_modes.add_child(button)
		compartment_fire_buttons.append(button)


func _new_compartment_bar(fill_color: Color) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.custom_minimum_size.y = 9.0
	bar.show_percentage = false
	var background := StyleBoxFlat.new()
	background.bg_color = Color(0.015, 0.055, 0.06, 0.95)
	background.border_color = Color(0.12, 0.48, 0.48, 0.8)
	background.set_border_width_all(1)
	var fill := StyleBoxFlat.new()
	fill.bg_color = fill_color
	bar.add_theme_stylebox_override("background", background)
	bar.add_theme_stylebox_override("fill", fill)
	return bar


func _new_compartment_label(color: Color) -> Label:
	var label := Label.new()
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_size_override("font_size", 9)
	label.clip_text = true
	return label


func _select_tactical_ship(ship_id: int, source_global_position: Vector2 = Vector2.INF) -> void:
	# The command ship is already represented by the entire command interface.
	# Only foreign contacts receive the generic tactical readout.
	if ship_id == 0:
		_clear_tactical_selection()
		return
	selected_compartment_id = &""
	if selected_tactical_ship_id == ship_id and targeting_panel.visible:
		return
	selected_tactical_ship_id = ship_id
	if source_global_position == Vector2.INF:
		source_global_position = get_viewport().get_mouse_position()
	context_panel_source_global = source_global_position
	_update_contact_panel()
	_set_context_panel_open(true)


func _select_compartment(room: Resource, source_global_position: Vector2 = Vector2.INF) -> void:
	if room == null:
		return
	var room_id: StringName = room.get("room_id")
	if room_id == &"":
		return
	var should_power_on := selected_compartment_id != room_id or not targeting_panel.visible
	selected_tactical_ship_id = -1
	selected_compartment_id = room_id
	if source_global_position == Vector2.INF:
		source_global_position = get_viewport().get_mouse_position()
	context_panel_source_global = source_global_position
	_update_compartment_panel()
	if should_power_on:
		_set_context_panel_open(true)


func _clear_tactical_selection() -> void:
	if selected_tactical_ship_id == -1 and selected_compartment_id == &"" and not targeting_panel.visible:
		return
	selected_tactical_ship_id = -1
	selected_compartment_id = &""
	_set_context_panel_open(false)


func _update_contact_panel() -> void:
	if selected_compartment_id != &"":
		_update_compartment_panel()
		return
	if selected_tactical_ship_id < 0 or not is_instance_valid(targeting_panel):
		return
	_set_compartment_action_mode(false)
	_set_context_panel_height(false)
	contact_name.remove_theme_color_override("font_color")
	if not is_instance_valid(combat_simulation):
		_set_contact_action_mode(false, false)
		contact_panel_title.text = "CONTACT LINK"
		contact_name.text = "UNKNOWN CONTACT"
		contact_status.text = "TACTICAL LINK UNAVAILABLE"
		return
	var contact: Dictionary = combat_simulation.call("get_tactical_contact", selected_tactical_ship_id)
	if contact.is_empty():
		_set_contact_action_mode(false, false)
		contact_panel_title.text = "CONTACT LINK"
		contact_name.text = "CONTACT LOST"
		contact_status.text = "NO ACTIVE TRANSPONDER"
		return
	var is_hostile := bool(contact.get("combat_active", true)) or bool(contact.get("defense_alert", false))
	var is_training_target := bool(contact.get("training_target", false))
	var is_authorized := bool(contact.get("player_targetable", is_hostile))
	var is_station := bool(contact.get("stationary", false)) or not PackedStringArray(contact.get("station_service_tags", PackedStringArray())).is_empty()
	var faction_id := StringName(contact.get("faction_id", &"UNAFFILIATED"))
	var faction_report: Dictionary = {}
	if is_instance_valid(reputation_simulation):
		faction_report = reputation_simulation.call("get_faction_report", faction_id)
	var faction_name := String(faction_report.get("short_name", "INDEPENDENT"))
	var faction_standing := String(faction_report.get("standing", "NEUTRAL"))
	if not faction_report.is_empty():
		contact_name.add_theme_color_override(
			"font_color",
			Color(faction_report.get("signal_color", Color(0.65, 0.95, 0.9)))
		)
	var shield_percent := 0
	var hull_percent := 0
	if float(contact.get("maximum_shield", 0.0)) > 0.0:
		shield_percent = roundi(100.0 * float(contact.get("shield", 0.0)) / float(contact.get("maximum_shield", 1.0)))
	if float(contact.get("maximum_hull", 0.0)) > 0.0:
		hull_percent = roundi(100.0 * float(contact.get("hull", 0.0)) / float(contact.get("maximum_hull", 1.0)))
	contact_name.text = String(contact.get("display_name", "TACTICAL CONTACT")).to_upper()
	if is_hostile:
		_set_contact_action_mode(true, false, is_training_target)
		contact_panel_title.text = "%s TRANSPONDER" % faction_name
		contact_status.text = "%s  •  %s  •  CONTACT HOSTILE • SHIELD %03d%% • HULL %03d%%" % [
			faction_name,
			faction_standing,
			shield_percent,
			hull_percent,
		]
		contact_target_toggle.set_pressed_no_signal(is_authorized)
		if is_training_target:
			contact_panel_title.text = "PROVING RANGE LINK"
			contact_status.text = "TRAINING TARGET ARMED • MOVEMENT LIVE • WEAPONS LIVE"
	else:
		_set_contact_action_mode(false, true, is_training_target)
		contact_panel_title.text = "%s STATION LINK" % faction_name if is_station else "%s TRANSPONDER" % faction_name
		contact_status.text = "%s  •  %s • SHIELD %03d%% • HULL %03d%%" % [
			faction_name,
			faction_standing,
			shield_percent,
			hull_percent,
		]
		_configure_safe_contact_action(is_station, is_training_target)
		if is_training_target:
			contact_panel_title.text = "PROVING RANGE LINK"
			contact_status.text = "TRAINING TARGET SAFE • DRIVE LOCKED • WEAPONS COLD"


func _update_compartment_panel() -> void:
	if selected_compartment_id == &"" or not is_instance_valid(simulation):
		return
	var room: Dictionary = simulation.call("get_room_data", selected_compartment_id)
	if room.is_empty():
		_clear_tactical_selection()
		return
	_set_contact_action_mode(false, false)
	_set_compartment_action_mode(true)
	_set_context_panel_height(true)
	contact_name.remove_theme_color_override("font_color")
	contact_panel_title.text = "COMPARTMENT LINK"
	contact_name.text = String(room.get("name", "SHIP SYSTEM")).to_upper()
	var health := float(simulation.call("get_room_health_percentage", selected_compartment_id))
	var efficiency := float(simulation.call("get_room_efficiency", selected_compartment_id))
	var state := "NOMINAL"
	if health <= 0.5:
		state = "OFFLINE"
	elif health < 70.0 or (bool(room.get("produces_output", false)) and efficiency < 0.5):
		state = "DEGRADED"
	contact_status.text = "%s  •  %s" % [
		String(simulation.call("get_room_type_name", selected_compartment_id)).replace("_", " "),
		state,
	]
	compartment_integrity_bar.value = health
	compartment_integrity_bar.tooltip_text = "STRUCTURE  %d%%" % roundi(health)
	compartment_output_bar.visible = bool(room.get("produces_output", false))
	compartment_output_bar.value = efficiency * 100.0
	compartment_output_bar.tooltip_text = "SYSTEM OUTPUT  %d%%" % roundi(efficiency * 100.0)

	var pressure := 1.0
	if is_instance_valid(combat_simulation):
		var structure: Variant = combat_simulation.call("get_structural_state", 0, 0)
		if structure != null and structure.has_method("get_room_pressure"):
			pressure = float(structure.call("get_room_pressure", selected_compartment_id))
	compartment_atmosphere.text = "ATMOSPHERE  %03d%%  %s" % [
		roundi(pressure * 100.0),
		"SEALED" if pressure >= 0.995 else ("VENTING" if pressure > 0.02 else "VACUUM"),
	]

	var crew := get_tree().get_first_node_in_group("crew_simulation")
	if is_instance_valid(crew):
		var requirements: Vector2i = crew.call("get_room_manning_requirements", selected_compartment_id)
		var operating := int(crew.call("get_room_staffing", selected_compartment_id))
		var present := int(crew.call("get_room_present_count", selected_compartment_id))
		compartment_crew.text = "CREW  %d OPERATING  •  %d PRESENT  •  %d OPTIMAL" % [
			operating, present, requirements.y,
		]
		compartment_staffing_button.text = "CREW NET  •  %s" % String(
			crew.call("get_room_staffing_priority_label", selected_compartment_id)
		).to_upper()
		compartment_staffing_button.disabled = false
	else:
		compartment_crew.text = "CREW NET  OFFLINE"
		compartment_staffing_button.text = "CREW NET  OFFLINE"
		compartment_staffing_button.disabled = true
	compartment_repair_button.visible = health < 99.5
	compartment_weapon_modes.visible = String(room.get("type_name", "")) == "WEAPONS"
	if compartment_weapon_modes.visible:
		var room_definition := _player_layout_room(selected_compartment_id)
		var fire_mode := FIRE_MODE_LINKED
		if room_definition != null and room_definition.has_method("get_weapon_fire_mode"):
			fire_mode = int(room_definition.call("get_weapon_fire_mode", 0))
		for index: int in range(compartment_fire_buttons.size()):
			compartment_fire_buttons[index].set_pressed_no_signal(index == fire_mode)


func _set_compartment_action_mode(is_visible: bool) -> void:
	if is_instance_valid(compartment_actions):
		compartment_actions.visible = is_visible


func _set_context_panel_height(is_compartment: bool) -> void:
	var desired_bottom := 300.0 if is_compartment else 176.0
	if not is_equal_approx(targeting_panel.offset_bottom, desired_bottom):
		targeting_panel.offset_bottom = desired_bottom
		targeting_panel.pivot_offset = targeting_panel.size * 0.5


func _player_layout_room(room_id: StringName) -> Resource:
	var layout: Resource = simulation.get("ship_layout")
	if layout == null:
		return null
	for room: Resource in layout.get("rooms"):
		if StringName(room.get("room_id")) == room_id:
			return room
	return null


func _on_compartment_staffing_pressed() -> void:
	var crew := get_tree().get_first_node_in_group("crew_simulation")
	if is_instance_valid(crew) and selected_compartment_id != &"":
		crew.call("cycle_room_staffing_priority", selected_compartment_id)
		_update_compartment_panel()


func _on_compartment_repair_pressed() -> void:
	var crew := get_tree().get_first_node_in_group("crew_simulation")
	if is_instance_valid(crew) and selected_compartment_id != &"":
		crew.call("request_room_repair", selected_compartment_id)
		_update_compartment_panel()


func _on_compartment_fire_mode_pressed(fire_mode: int) -> void:
	var room := _player_layout_room(selected_compartment_id)
	if room == null or String(room.get("type_name")) != "WEAPONS":
		return
	var mount_count := maxi(int(room.get("installed_piece_count")), 1)
	for mount_index: int in range(mount_count):
		if room.has_method("set_weapon_fire_mode"):
			room.call("set_weapon_fire_mode", mount_index, fire_mode)
	var layout: Resource = simulation.get("ship_layout")
	if layout != null:
		layout.emit_changed()
	_update_compartment_panel()


func _set_contact_action_mode(
	show_combat: bool,
	show_safe: bool,
	show_training: bool = false
) -> void:
	combat_contact_actions.visible = show_combat
	safe_contact_actions.visible = show_safe
	contact_target_toggle.visible = false
	if is_instance_valid(safe_training_action):
		var show_safe_training := show_safe and show_training
		if safe_training_action.visible != show_safe_training:
			safe_training_action.visible = show_safe_training
	if is_instance_valid(combat_training_action):
		var show_combat_training := show_combat and show_training
		if combat_training_action.visible != show_combat_training:
			combat_training_action.visible = show_combat_training


func _configure_safe_contact_action(is_station: bool, is_training_target: bool = false) -> void:
	var docking_for_contact := (
		int(simulation.get("docking_contact_id")) == selected_tactical_ship_id
		and StringName(simulation.get("docking_state")) != &"IDLE"
	)
	var docking_state := StringName(simulation.get("docking_state")) if docking_for_contact else &"IDLE"
	safe_contact_action.disabled = docking_for_contact and docking_state != &"DOCKED"
	safe_contact_action.visible = is_station and not is_training_target
	if is_instance_valid(open_communications_button):
		open_communications_button.visible = not is_training_target
		open_communications_button.disabled = false
		open_communications_button.text = "OPEN COMMS >"
	if is_station:
		safe_contact_action_title.text = "CONTACT CHANNELS"
		safe_contact_action.tooltip_text = "Open a channel with station traffic control."
		match docking_state:
			&"APPROACH":
				safe_contact_action.text = "DOCKING AUTOPILOT ACTIVE"
				safe_contact_feedback.text = "SAFE APPROACH CORRIDOR"
			&"ALIGN":
				safe_contact_action.text = "DOCKING AUTOPILOT ACTIVE"
				safe_contact_feedback.text = "ALIGNING STARBOARD CONNECTOR"
			&"FINAL":
				safe_contact_action.text = "DOCKING AUTOPILOT ACTIVE"
				safe_contact_feedback.text = "FINAL BERTHING MANEUVER"
			&"DOCKED":
				safe_contact_action.text = "OPEN STATION SERVICES >"
				safe_contact_feedback.text = "BERTH LOCKED • HARDLINE CONNECTED"
			_:
				safe_contact_action.text = "REQUEST DOCKING CLEARANCE >"
				safe_contact_feedback.text = "CHANNEL READY"
	else:
		safe_contact_action_title.text = "COMMUNICATIONS"
		safe_contact_feedback.text = "VOICE AND CONTRACT DATA AVAILABLE AT RANGE"
	if is_training_target:
		safe_contact_action_title.text = "SIMULATION CONTROL"
		safe_contact_feedback.text = "TARGET INTERLOCK SAFE • NO RETURN FIRE"


func _on_safe_contact_action_pressed() -> void:
	if selected_tactical_ship_id <= 0 or not is_instance_valid(combat_simulation):
		return
	var contact: Dictionary = combat_simulation.call("get_tactical_contact", selected_tactical_ship_id)
	if contact.is_empty() or bool(contact.get("combat_active", true)) or bool(contact.get("defense_alert", false)):
		return
	if (
		StringName(simulation.get("docking_state")) == &"DOCKED"
		and int(simulation.get("docking_contact_id")) == selected_tactical_ship_id
	):
		_show_station_services(selected_tactical_ship_id)
		return
	var is_station := bool(contact.get("stationary", false)) or not PackedStringArray(contact.get("station_service_tags", PackedStringArray())).is_empty()
	if is_station:
		var result: Dictionary = combat_simulation.call(
			"request_docking_clearance",
			selected_tactical_ship_id,
			simulation
		)
		if not bool(result.get("ok", false)):
			safe_contact_feedback.text = String(result.get("message", "CLEARANCE DENIED"))
			return
		if not bool(simulation.call("begin_docking_sequence", result)):
			safe_contact_feedback.text = "DOCKING COMPUTER BUSY"
			return
		_update_contact_panel()
		return
	_open_communications_channel()


func _create_communication_interface() -> void:
	var menu_audio := get_tree().get_first_node_in_group("menu_audio")
	if is_instance_valid(menu_audio):
		menu_audio.process_mode = Node.PROCESS_MODE_ALWAYS
	open_communications_button = Button.new()
	open_communications_button.name = "OpenCommunicationsButton"
	open_communications_button.custom_minimum_size = Vector2(0.0, 28.0)
	open_communications_button.text = "OPEN COMMS >"
	open_communications_button.tooltip_text = "Open a long-range voice and contract channel. Physical services still require docking."
	open_communications_button.add_theme_color_override("font_color", Color(0.62, 0.94, 1.0))
	open_communications_button.add_theme_font_size_override("font_size", 10)
	open_communications_button.pressed.connect(_open_communications_channel)
	safe_contact_actions.add_child(open_communications_button)
	safe_contact_actions.move_child(open_communications_button, 1)
	safe_training_action = Button.new()
	safe_training_action.name = "SafeTrainingAction"
	safe_training_action.text = ">> ARM TRAINING TARGET"
	safe_training_action.tooltip_text = "Enable movement, weapons, and return fire for this proving target."
	safe_training_action.add_theme_color_override("font_color", Color(1.0, 0.7, 0.22))
	safe_training_action.add_theme_font_size_override("font_size", 11)
	safe_training_action.visible = false
	safe_training_action.pressed.connect(_toggle_selected_training_target.bind(true))
	safe_contact_actions.add_child(safe_training_action)
	safe_contact_actions.move_child(safe_training_action, 1)
	combat_training_action = Button.new()
	combat_training_action.name = "CombatTrainingAction"
	combat_training_action.text = ">> DISARM + RESET TARGET"
	combat_training_action.tooltip_text = "Return this proving target to an inert, fully repaired state."
	combat_training_action.add_theme_color_override("font_color", Color(0.45, 1.0, 0.82))
	combat_training_action.add_theme_font_size_override("font_size", 11)
	combat_training_action.visible = false
	combat_training_action.pressed.connect(_toggle_selected_training_target.bind(false))
	combat_contact_actions.add_child(combat_training_action)
	communication_panel = COMMUNICATION_PANEL.new() as CommunicationPanel
	communication_panel.z_index = 120
	communication_panel.response_selected.connect(_on_communication_response_selected)
	communication_panel.channel_closed.connect(_close_communications_channel)
	add_child(communication_panel)


func _toggle_selected_training_target(is_aggressive: bool) -> void:
	if selected_tactical_ship_id <= 0 or not is_instance_valid(combat_simulation):
		return
	if not bool(combat_simulation.call(
		"set_training_target_aggression",
		selected_tactical_ship_id,
		is_aggressive
	)):
		return
	if is_aggressive:
		simulation.call("set_manual_target", selected_tactical_ship_id, &"")
	_update_contact_panel()


func _open_communications_channel() -> void:
	if selected_tactical_ship_id <= 0 or not is_instance_valid(combat_simulation):
		return
	var contact: Dictionary = combat_simulation.call("get_tactical_contact", selected_tactical_ship_id)
	if contact.is_empty() or bool(contact.get("defense_alert", false)):
		safe_contact_feedback.text = "NO RESPONSE • CHANNEL REFUSED"
		return
	if not is_instance_valid(dialogue_simulation) or not is_instance_valid(communication_panel):
		safe_contact_feedback.text = "COMMUNICATIONS BUS OFFLINE"
		return
	communication_contact = contact
	var view: Dictionary = dialogue_simulation.call("begin_conversation", communication_contact)
	communication_pause_was_active = get_tree().paused
	get_tree().paused = true
	communication_panel.show_view(view)
	_set_context_panel_open(false)
	var menu_audio := get_tree().get_first_node_in_group("menu_audio")
	if is_instance_valid(menu_audio):
		menu_audio.call("play_open")


func _on_communication_response_selected(response_id: StringName) -> void:
	if communication_contact.is_empty() or not is_instance_valid(dialogue_simulation):
		return
	var view: Dictionary = dialogue_simulation.call(
		"choose_response",
		communication_contact,
		response_id
	)
	communication_panel.show_view(view)
	var menu_audio := get_tree().get_first_node_in_group("menu_audio")
	if is_instance_valid(menu_audio):
		menu_audio.call("play_execute")


func _close_communications_channel() -> void:
	if is_instance_valid(communication_panel):
		communication_panel.close_channel()
	communication_contact.clear()
	get_tree().paused = communication_pause_was_active
	var menu_audio := get_tree().get_first_node_in_group("menu_audio")
	if is_instance_valid(menu_audio):
		menu_audio.call("play_close")


func _exit_tree() -> void:
	if not communication_contact.is_empty() and is_instance_valid(get_tree()):
		get_tree().paused = communication_pause_was_active


func _on_docking_completed(contact_id: int) -> void:
	_set_docking_annunciator_active(false)
	_show_station_services(contact_id)


func _show_station_services(contact_id: int) -> void:
	var contact: Dictionary = combat_simulation.call("get_tactical_contact", contact_id)
	docked_contact_name.text = String(contact.get("display_name", "STATION")).to_upper()
	station_service_status.text = "SELECT A NEON SERVICE CHANNEL"
	_clear_tactical_selection()
	docked_panel.visible = true
	var menu_audio := get_tree().get_first_node_in_group("menu_audio")
	if is_instance_valid(menu_audio):
		menu_audio.call("play_open")


func _on_close_docked_panel_pressed() -> void:
	docked_panel.visible = false
	var menu_audio := get_tree().get_first_node_in_group("menu_audio")
	if is_instance_valid(menu_audio):
		menu_audio.call("play_close")


func _on_station_drydock_pressed() -> void:
	station_service_status.text = "DRYDOCK HARDLINE OPEN • TRANSFERRING CARGO MANIFEST"
	station_drydock_requested.emit()


func _on_unavailable_station_service_pressed(service_name: String) -> void:
	station_service_status.text = "%s • SHUTTERED THIS SHIFT" % service_name
	var menu_audio := get_tree().get_first_node_in_group("menu_audio")
	if is_instance_valid(menu_audio):
		menu_audio.call("play_cancel")


func _on_release_clamps_pressed() -> void:
	if not bool(simulation.call("begin_undocking")):
		station_service_status.text = "CLAMP RELEASE INTERLOCK DENIED"
		return
	docked_panel.visible = false
	var menu_audio := get_tree().get_first_node_in_group("menu_audio")
	if is_instance_valid(menu_audio):
		menu_audio.call("play_execute")


func _on_undocking_completed(contact_id: int) -> void:
	if is_instance_valid(combat_simulation):
		combat_simulation.call("complete_undocking", contact_id, simulation.physics_body)


func _on_docking_cancelled(contact_id: int) -> void:
	_set_docking_annunciator_active(false)
	if is_instance_valid(combat_simulation):
		combat_simulation.call("complete_undocking", contact_id, simulation.physics_body)
	if selected_tactical_ship_id == contact_id:
		_update_contact_panel()


func _on_docking_state_changed(state: StringName, _contact_id: int) -> void:
	_set_docking_annunciator_active(state in [&"APPROACH", &"ALIGN", &"FINAL"])


func _on_contact_target_toggled(is_enabled: bool) -> void:
	if selected_tactical_ship_id <= 0 or not is_instance_valid(combat_simulation):
		return
	combat_simulation.call("set_enemy_player_targetable", selected_tactical_ship_id, is_enabled)
	_update_contact_panel()


func _set_context_panel_open(is_open: bool) -> void:
	if not is_open and not targeting_panel.visible:
		return
	if is_instance_valid(context_panel_tween):
		context_panel_tween.kill()
	targeting_panel.pivot_offset = _context_source_to_panel_pivot(context_panel_source_global)
	if is_open:
		var menu_audio := get_tree().get_first_node_in_group("menu_audio")
		if is_instance_valid(menu_audio):
			menu_audio.call("play_open")
		context_panel_tween = create_tween()
		context_panel_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		targeting_panel.visible = true
		targeting_panel.scale = Vector2(0.0, crt_line_scale)
		targeting_panel.modulate = Color(1.35, 1.55, 1.55, 1.0)
		context_panel_tween.tween_property(targeting_panel, "scale:x", 1.0, crt_horizontal_time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		context_panel_tween.tween_property(targeting_panel, "scale:y", 1.0, crt_vertical_time).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		context_panel_tween.parallel().tween_property(targeting_panel, "modulate", Color.WHITE, crt_vertical_time)
	else:
		var menu_audio := get_tree().get_first_node_in_group("menu_audio")
		if is_instance_valid(menu_audio):
			menu_audio.call("play_cancel")
		context_panel_tween = create_tween()
		context_panel_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		context_panel_tween.tween_property(targeting_panel, "scale:y", crt_line_scale, crt_vertical_time * 0.75).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		context_panel_tween.parallel().tween_property(targeting_panel, "modulate", Color(1.3, 1.5, 1.5, 1.0), crt_vertical_time * 0.75)
		context_panel_tween.tween_property(targeting_panel, "scale:x", 0.0, crt_horizontal_time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		context_panel_tween.tween_callback(func() -> void:
			targeting_panel.visible = false
			targeting_panel.modulate = Color.WHITE
		)


func _context_source_to_panel_pivot(global_position: Vector2) -> Vector2:
	var canvas_parent := targeting_panel.get_parent() as CanvasItem
	if canvas_parent == null:
		return targeting_panel.size * 0.5
	return canvas_parent.get_global_transform_with_canvas().affine_inverse() * global_position - targeting_panel.position


func _on_shield_impact_detected(collider: RigidBody2D, point: Vector2, normal: Vector2, strength: float) -> void:
	var faction := int(collider.get_meta("ship_faction", -1))
	var target_visual: Control
	if faction == 0:
		target_visual = ship_visual
	else:
		target_visual = enemy_visuals.get(int(collider.get_meta("ship_id", -1))) as Control
	if not is_instance_valid(target_visual):
		return
	var target_shield := target_visual.get_node_or_null("ShieldVisual") as Control
	if not is_instance_valid(target_shield):
		return
	var canvas_point := WORLD_ORIGIN + point
	var local_point := target_shield.get_global_transform_with_canvas().affine_inverse() * canvas_point
	var local_normal := normal.rotated(-target_visual.rotation)
	target_shield.call("show_impact", local_point, local_normal, strength)


func _on_impact_effect_requested(
	_collider: RigidBody2D,
	point: Vector2,
	normal: Vector2,
	impact_color: Color,
	impact_scene: PackedScene
) -> void:
	if not is_instance_valid(world):
		return
	var effect_scene := impact_scene if impact_scene != null else IMPACT_SPRITE_BURST_SCENE
	var effect := effect_scene.instantiate() as Node2D
	world.add_child(effect)
	effect.position = WORLD_ORIGIN + point
	effect.call("configure", normal, impact_color, 1.0)


func _on_player_ship_destroyed(_world_position: Vector2) -> void:
	ship_visual.visible = false
	if is_instance_valid(deck_detail_visual):
		deck_detail_visual.visible = false
	manual_target_line.visible = false
	_clear_tactical_selection()


func _process(delta: float) -> void:
	if not is_instance_valid(simulation):
		return
	_update_controller_input(delta)
	if is_instance_valid(combat_simulation):
		combat_simulation.call("set_tactical_audio_zoom", float(zoom_controller.get("zoom_level")))

	var interpolation := Engine.get_physics_interpolation_fraction()
	var rendered_position: Vector2 = simulation.previous_ship_position.lerp(
		simulation.ship_position,
		interpolation
	)
	var rendered_rotation: float = lerp_angle(
		simulation.previous_ship_rotation,
		simulation.ship_rotation,
		interpolation
	)
	_update_controller_translation_indicator(delta, rendered_rotation)
	_update_controller_aim_indicator(delta)
	ship_visual.position = WORLD_ORIGIN + rendered_position - ship_visual.pivot_offset
	ship_visual.rotation = rendered_rotation
	ship_visual.call("set_simulation_identity", 0, 0)
	var command_zoom := float(zoom_controller.get("zoom_level"))
	var blend_half := deck_detail_blend_width * 0.5
	deck_detail_mix = smoothstep(
		deck_detail_zoom - blend_half,
		deck_detail_zoom + blend_half,
		command_zoom
	)
	if ship_visual.has_method("set_deck_detail_visible"):
		# The command silhouette participates only in the transition. Once room art
		# is fully readable it must disappear completely; otherwise its solid hull
		# shows through authored transparent apertures and adds a second gray rim.
		ship_visual.call("set_deck_detail_visible", false)
	ship_visual.modulate.a = 1.0 - deck_detail_mix
	if is_instance_valid(deck_detail_visual):
		var deck_layer_active := ship_visual.visible and deck_detail_mix > 0.001
		deck_detail_visual.visible = deck_layer_active
		deck_detail_visual.process_mode = (
			Node.PROCESS_MODE_INHERIT if deck_layer_active else Node.PROCESS_MODE_DISABLED
		)
		deck_detail_visual.modulate.a = deck_detail_mix
		deck_detail_visual.call("set_simulation_identity", 0, 0)
		_sync_deck_detail_transform()
	if selected_compartment_id != &"" and deck_detail_mix < 0.45:
		_clear_tactical_selection()
	_apply_propulsion_visual_command(ship_visual, simulation.physics_body)
	_apply_propulsion_visual_command(deck_detail_visual, simulation.physics_body)
	_update_ship_label_visibility(delta)
	_update_camera_follow(rendered_position, delta)
	starfield.call("update_camera_position", world.position)
	world.queue_redraw()
	if is_instance_valid(sector_hazard_hud) and is_instance_valid(sector_simulation):
		sector_hazard_hud.call(
			"set_hazard_state",
			sector_simulation.call("get_hazard_state", simulation.ship_position)
		)

	_update_shield_visual()
	_sync_enemy_visuals()
	_sync_fighter_visuals()
	_sync_projectile_visuals()
	_sync_fragment_visuals()
	_sync_grid_pickup_visuals()
	_sync_flight_destination_indicators()
	_update_manual_targeting_display()
	_update_direct_fire_display()
	_update_contact_panel()


func _create_sector_hazard_hud() -> void:
	if is_instance_valid(sector_hazard_hud):
		return
	sector_hazard_hud = SECTOR_HAZARD_HUD.new()
	sector_hazard_hud.name = "SectorHazardHud"
	sector_hazard_hud.set_anchors_preset(Control.PRESET_CENTER_TOP)
	sector_hazard_hud.position = Vector2(-150.0, 12.0)
	sector_hazard_hud.size = Vector2(300.0, 36.0)
	add_child(sector_hazard_hud)
	move_child(sector_hazard_hud, get_child_count() - 1)


func _create_docking_annunciator() -> void:
	if is_instance_valid(docking_annunciator):
		return
	docking_annunciator = PanelContainer.new()
	docking_annunciator.name = "DockingAnnunciator"
	docking_annunciator.mouse_filter = Control.MOUSE_FILTER_IGNORE
	docking_annunciator.z_index = 220
	docking_annunciator.set_anchors_preset(Control.PRESET_CENTER_TOP)
	docking_annunciator.position = Vector2(-136.0, 52.0)
	docking_annunciator.size = Vector2(272.0, 34.0)
	docking_annunciator.visible = false

	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.018, 0.025, 0.026, 0.72)
	docking_annunciator.add_theme_stylebox_override("panel", panel_style)

	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 11)
	margin.add_theme_constant_override("margin_right", 11)
	margin.add_theme_constant_override("margin_top", 5)
	margin.add_theme_constant_override("margin_bottom", 5)
	docking_annunciator.add_child(margin)

	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 9)
	margin.add_child(row)

	docking_annunciator_lamp = ColorRect.new()
	docking_annunciator_lamp.custom_minimum_size = Vector2(8.0, 8.0)
	docking_annunciator_lamp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	docking_annunciator_lamp.color = Color(1.0, 0.57, 0.1)
	row.add_child(docking_annunciator_lamp)

	docking_annunciator_label = Label.new()
	docking_annunciator_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	docking_annunciator_label.text = "DOCKING SEQUENCE • ACTIVE"
	docking_annunciator_label.add_theme_font_size_override("font_size", 12)
	docking_annunciator_label.add_theme_color_override(
		"font_color",
		Color(1.0, 0.72, 0.28)
	)
	row.add_child(docking_annunciator_label)

	add_child(docking_annunciator)
	move_child(docking_annunciator, get_child_count() - 1)


func _set_docking_annunciator_active(is_active: bool) -> void:
	if not is_instance_valid(docking_annunciator):
		return
	if is_instance_valid(docking_annunciator_blink_tween):
		docking_annunciator_blink_tween.kill()
	if is_instance_valid(docking_annunciator_intro_tween):
		docking_annunciator_intro_tween.kill()
	if not is_active:
		docking_annunciator.visible = false
		return
	docking_annunciator.visible = true
	docking_annunciator.modulate = Color.WHITE
	docking_annunciator.scale = Vector2.ONE
	docking_annunciator.pivot_offset = docking_annunciator.size * 0.5
	docking_annunciator_lamp.modulate = Color.WHITE
	docking_annunciator_label.visible_ratio = 0.0

	docking_annunciator_intro_tween = create_tween()
	docking_annunciator_intro_tween.tween_property(
		docking_annunciator_label,
		"visible_ratio",
		1.0,
		0.78
	).set_trans(Tween.TRANS_LINEAR)

	docking_annunciator_blink_tween = create_tween().set_loops()
	docking_annunciator_blink_tween.tween_property(
		docking_annunciator_lamp,
		"modulate:a",
		0.12,
		0.28
	).set_trans(Tween.TRANS_QUAD)
	docking_annunciator_blink_tween.tween_property(
		docking_annunciator_lamp,
		"modulate:a",
		1.0,
		0.12
	).set_trans(Tween.TRANS_QUAD)
	docking_annunciator_blink_tween.tween_interval(0.32)


func _sync_grid_pickup_visuals() -> void:
	if not is_instance_valid(combat_simulation):
		return
	var active_ids: Dictionary = {}
	var interpolation := Engine.get_physics_interpolation_fraction()
	for pickup: Dictionary in combat_simulation.grid_pickups:
		var pickup_id := int(pickup["id"])
		active_ids[pickup_id] = true
		if not grid_pickup_visuals.has(pickup_id):
			var visual: Control = GRID_PICKUP_VISUAL.new()
			visual.mouse_filter = Control.MOUSE_FILTER_IGNORE
			visual.call(
				"configure",
				String(pickup["room_type"]),
				String(pickup["display_name"]),
				pickup["color"],
				pickup.get("footprint", Vector2i.ONE),
				0,
				0,
				String(pickup.get("inventory_key", pickup["room_type"])),
				pickup.get("module_recipe")
			)
			visual.set("drag_ghost", true)
			# The ghost draws with a four-pixel field around it. A 28px control
			# therefore produces a 20px colored grid: exactly one tactical hull cell.
			visual.custom_minimum_size = Vector2(28, 28)
			visual.size = visual.custom_minimum_size
			visual.pivot_offset = visual.size * 0.5
			world.add_child(visual)
			grid_pickup_visuals[pickup_id] = visual
		var pickup_visual := grid_pickup_visuals[pickup_id] as Control
		var previous_position: Vector2 = pickup["previous_position"]
		var current_position: Vector2 = pickup["position"]
		pickup_visual.position = (
			WORLD_ORIGIN
			+ previous_position.lerp(current_position, interpolation)
			- pickup_visual.pivot_offset
		)
		pickup_visual.rotation = lerp_angle(
			float(pickup["previous_rotation"]),
			float(pickup["rotation"]),
			interpolation
		)
		pickup_visual.modulate = (
			Color(1.28, 1.28, 1.08, 1.0)
			if bool(pickup.get("magnetized", false))
			else Color.WHITE
		)
	for pickup_id_value: Variant in grid_pickup_visuals.keys().duplicate():
		if active_ids.has(pickup_id_value):
			continue
		(grid_pickup_visuals[pickup_id_value] as Control).queue_free()
		grid_pickup_visuals.erase(pickup_id_value)


func _sync_flight_destination_indicators() -> void:
	var targeted_pickups: Dictionary = {}
	for pickup_id: int in simulation.call("get_active_grid_pickup_destination_ids"):
		targeted_pickups[pickup_id] = true
	var quest_pickups: Dictionary = {}
	if is_instance_valid(quest_simulation):
		for pickup_id: int in quest_simulation.call("get_active_objective_pickup_ids"):
			quest_pickups[pickup_id] = true
	for pickup_id_value: Variant in grid_pickup_visuals.keys():
		var pickup_id := int(pickup_id_value)
		var is_route_target := targeted_pickups.has(pickup_id)
		var is_quest_target := quest_pickups.has(pickup_id)
		_set_flight_destination_indicator(
			grid_pickup_visuals[pickup_id_value] as Control,
			is_route_target or is_quest_target,
			Color(0.28, 1.0, 0.88, 0.9) if is_route_target else Color(1.0, 0.6, 0.18, 0.96)
		)
	var docking_state := StringName(simulation.get("docking_state"))
	var docking_contact := int(simulation.get("docking_contact_id"))
	var station_is_destination := docking_state in [&"APPROACH", &"ALIGN", &"FINAL"]
	for enemy_id_value: Variant in enemy_visuals.keys():
		_set_flight_destination_indicator(
			enemy_visuals[enemy_id_value] as Control,
			station_is_destination and int(enemy_id_value) == docking_contact
		)


func _set_flight_destination_indicator(
	target_visual: Control,
	is_active: bool,
	indicator_color: Color = Color(0.28, 1.0, 0.88, 0.9)
) -> void:
	if not is_instance_valid(target_visual):
		return
	var indicator := target_visual.get_node_or_null("FlightDestinationIndicator") as Control
	if not is_active:
		if indicator != null:
			indicator.visible = false
		return
	if indicator == null:
		indicator = FLIGHT_DESTINATION_INDICATOR.new() as Control
		indicator.name = "FlightDestinationIndicator"
		target_visual.add_child(indicator)
		indicator.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	indicator.set("bracket_color", indicator_color)
	indicator.visible = true


func _input(event: InputEvent) -> void:
	if event is InputEventKey:
		if event.keycode == KEY_F and not event.echo:
			_set_direct_fire_active(event.pressed)
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_SHIFT and not event.pressed and simulation.is_plotting_route:
			is_bending_route_segment = false
			simulation.commit_plotted_route()
			get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseMotion:
		var mouse_motion := event as InputEventMouseMotion
		if route_drag_armed and mouse_motion.shift_pressed and (mouse_motion.button_mask & MOUSE_BUTTON_MASK_RIGHT) != 0:
			if route_drag_start.distance_to(mouse_motion.position) >= 4.0:
				is_bending_route_segment = true
		if is_bending_route_segment:
			_update_route_curve_from_mouse()
			get_viewport().set_input_as_handled()
			return
		if rotation_drag_armed and not mouse_motion.shift_pressed and (mouse_motion.button_mask & MOUSE_BUTTON_MASK_RIGHT) != 0:
			_update_course_preview_from_mouse()
			if not translation_preview_armed and rotation_drag_start.distance_to(mouse_motion.position) >= 5.0:
				rotation_dragging = true
			if rotation_dragging:
				_update_manual_ship_heading()
				get_viewport().set_input_as_handled()
				return
	if not event is InputEventMouseButton:
		return
	if event.button_index == MOUSE_BUTTON_RIGHT and not event.pressed:
		if is_instance_valid(simulation) and simulation.course_preview_active:
			_update_course_preview_from_mouse()
			simulation.commit_course_preview()
		is_bending_route_segment = false
		route_drag_armed = false
		rotation_drag_armed = false
		rotation_dragging = false
		translation_preview_armed = false
		simulation.clear_manual_heading()
		get_viewport().set_input_as_handled()
		return
	var hovered_control := get_viewport().gui_get_hovered_control()
	if hovered_control != null and hovered_control != self and hovered_control != world:
		return
	if not event.pressed:
		return
	if direct_fire_active and event.button_index == MOUSE_BUTTON_LEFT:
		if Rect2(Vector2.ZERO, size).has_point(get_local_mouse_position()):
			combat_simulation.call(
				"fire_direct_volley",
				simulation,
				_direct_fire_aim_direction()
			)
			get_viewport().set_input_as_handled()
		return
	if event.button_index == MOUSE_BUTTON_RIGHT and simulation.targeting_doctrine == 2:
		simulation.clear_manual_target()
		get_viewport().set_input_as_handled()
		return
	if event.button_index != MOUSE_BUTTON_LEFT and event.button_index != MOUSE_BUTTON_RIGHT:
		return
	if not Rect2(Vector2.ZERO, size).has_point(get_local_mouse_position()):
		return
	if targeting_panel.visible and targeting_panel.get_global_rect().has_point(get_viewport().get_mouse_position()):
		return
	if dev_menu_toggle.visible and dev_menu_toggle.get_global_rect().has_point(get_viewport().get_mouse_position()):
		return
	if dev_menu.visible and dev_menu.get_global_rect().has_point(get_viewport().get_mouse_position()):
		return
	if event.button_index == MOUSE_BUTTON_LEFT and simulation.targeting_doctrine == 2 and _handle_manual_targeting_click():
		get_viewport().set_input_as_handled()
		return
	for visual_value: Variant in enemy_visuals.values():
		var enemy_visual := visual_value as Control
		if _visual_contains_tactical_point(enemy_visual):
			if event.button_index == MOUSE_BUTTON_LEFT:
				for enemy_id_value: Variant in enemy_visuals.keys():
					if enemy_visuals[enemy_id_value] == enemy_visual:
						_select_tactical_ship(int(enemy_id_value))
						break
			get_viewport().set_input_as_handled()
			return
	if Rect2(Vector2.ZERO, ship_visual.size).has_point(ship_visual.get_local_mouse_position()):
		if event.button_index == MOUSE_BUTTON_LEFT:
			var player_room: Resource = ship_visual.call(
				"get_room_at_local_position",
				ship_visual.get_local_mouse_position()
			)
			if deck_detail_mix >= 0.45 and player_room != null:
				_select_compartment(player_room)
			else:
				_clear_tactical_selection()
		get_viewport().set_input_as_handled()
		return
	if not is_instance_valid(simulation):
		return

	var clicked_world_position := world.get_local_mouse_position()
	if not Rect2(Vector2.ZERO, world.size).has_point(clicked_world_position):
		return

	if event.button_index == MOUSE_BUTTON_LEFT:
		_clear_tactical_selection()
		get_viewport().set_input_as_handled()
		return
	var course_point := clicked_world_position - WORLD_ORIGIN
	var target_binding := _grid_pickup_binding_at_course_point(course_point)
	if event.shift_pressed:
		simulation.add_plotted_waypoint(course_point, target_binding)
		route_drag_armed = simulation.pending_route_waypoints.size() >= 2
		route_drag_start = event.position
	else:
		translation_preview_armed = event.alt_pressed
		simulation.begin_course_preview(course_point, target_binding, translation_preview_armed)
		rotation_drag_armed = true
		rotation_drag_start = event.position
	get_viewport().set_input_as_handled()


func _visual_contains_tactical_point(visual: Control) -> bool:
	var local_point := visual.get_local_mouse_position()
	if visual.has_method("contains_tactical_point"):
		return bool(visual.call("contains_tactical_point", local_point))
	return Rect2(Vector2.ZERO, visual.size).has_point(local_point)


func _update_route_curve_from_mouse() -> void:
	var mouse_in_world := world.get_local_mouse_position()
	if Rect2(Vector2.ZERO, world.size).has_point(mouse_in_world):
		simulation.set_last_route_curve_control(mouse_in_world - WORLD_ORIGIN)


func _update_course_preview_from_mouse() -> void:
	var mouse_in_world := world.get_local_mouse_position()
	if Rect2(Vector2.ZERO, world.size).has_point(mouse_in_world):
		var course_point := mouse_in_world - WORLD_ORIGIN
		simulation.update_course_preview(course_point, _grid_pickup_binding_at_course_point(course_point))


func _grid_pickup_binding_at_course_point(course_point: Vector2) -> Dictionary:
	if not is_instance_valid(combat_simulation):
		return {}
	for pickup_id_value: Variant in grid_pickup_visuals.keys():
		var visual := grid_pickup_visuals[pickup_id_value] as Control
		if not is_instance_valid(visual) or not _visual_contains_tactical_point(visual):
			continue
		var pickup_transform: Dictionary = combat_simulation.call("get_grid_pickup_transform", int(pickup_id_value))
		if pickup_transform.is_empty():
			continue
		var pickup_position: Vector2 = pickup_transform["position"]
		var pickup_rotation := float(pickup_transform["rotation"])
		return {
			"kind": "grid_pickup",
			"id": int(pickup_id_value),
			"local_offset": (course_point - pickup_position).rotated(-pickup_rotation),
		}
	return {}


func _update_manual_ship_heading() -> void:
	var mouse_in_world := world.get_local_mouse_position()
	if Rect2(Vector2.ZERO, world.size).has_point(mouse_in_world):
		simulation.set_manual_heading_target(mouse_in_world - WORLD_ORIGIN)


func _center_camera_on_ship() -> void:
	ship_visual.pivot_offset = ship_visual.size * 0.5
	world.pivot_offset = WORLD_ORIGIN
	world.position = size * 0.5 - WORLD_ORIGIN - simulation.ship_position
	starfield.call("reset_camera_position", world.position)


func _on_camera_manipulated() -> void:
	camera_idle_time = 0.0
	camera_following = false


func _set_targeting_doctrine(doctrine: int) -> void:
	simulation.set_targeting_doctrine(doctrine)
	weapons_free_button.button_pressed = doctrine == 0
	center_mass_button.button_pressed = doctrine == 1
	manual_button.button_pressed = doctrine == 2
	manual_status.visible = doctrine == 2
	manual_target_line.visible = doctrine == 2 and simulation.manual_target_enemy_id >= 0


func _handle_manual_targeting_click() -> bool:
	var player_room: Resource = ship_visual.call("get_room_at_local_position", ship_visual.get_local_mouse_position())
	if player_room != null:
		if deck_detail_mix >= 0.45:
			_select_compartment(player_room)
		else:
			_clear_tactical_selection()
		if player_room.get("type_name") == "WEAPONS" and player_room.get("weapon_definition") != null:
			simulation.toggle_manual_weapon(player_room.get("room_id"))
		return true
	for enemy_id_value: Variant in enemy_visuals.keys():
		var enemy_id: int = enemy_id_value
		var enemy_visual := enemy_visuals[enemy_id] as Control
		var enemy_room: Resource = enemy_visual.call("get_room_at_local_position", enemy_visual.get_local_mouse_position())
		if enemy_room != null:
			_select_tactical_ship(enemy_id)
			simulation.set_manual_target(enemy_id, enemy_room.get("room_id"))
			return true
	return false


func _update_manual_targeting_display() -> void:
	var is_manual: bool = simulation.targeting_doctrine == 2
	manual_status.visible = is_manual
	manual_target_line.visible = false
	var no_rooms: Array[StringName] = []
	var selected_weapons: Array[StringName] = simulation.manual_weapon_ids if is_manual else no_rooms
	ship_visual.call("set_manual_highlights", selected_weapons, &"")
	if is_instance_valid(deck_detail_visual):
		deck_detail_visual.call("set_manual_highlights", selected_weapons, &"")
	var hovered_enemy_id := -1
	var hovered_room_id: StringName = &""
	for enemy_id_value: Variant in enemy_visuals.keys():
		var enemy_id: int = enemy_id_value
		var enemy_visual := enemy_visuals[enemy_id] as Control
		var hovered_room: Resource = enemy_visual.call("get_room_at_local_position", enemy_visual.get_local_mouse_position())
		if hovered_room != null:
			hovered_enemy_id = enemy_id
			hovered_room_id = hovered_room.get("room_id")
		var target_id: StringName = simulation.manual_target_room_id if is_manual and enemy_id == simulation.manual_target_enemy_id else &""
		var hover_id: StringName = hovered_room_id if is_manual and enemy_id == hovered_enemy_id else &""
		enemy_visual.call("set_manual_highlights", no_rooms, target_id, hover_id)
	if not is_manual:
		return
	manual_status.text = combat_simulation.get_manual_target_status(simulation)
	var target_visual := enemy_visuals.get(simulation.manual_target_enemy_id) as Control
	if is_instance_valid(target_visual):
		manual_target_line.visible = true
		var target_local: Vector2 = target_visual.call("get_room_local_center", simulation.manual_target_room_id)
		manual_target_line.points = PackedVector2Array([
			WORLD_ORIGIN + simulation.ship_position,
			target_visual.get_transform() * target_local,
		])


func _set_direct_fire_active(is_active: bool) -> void:
	if direct_fire_active == is_active:
		return
	direct_fire_active = is_active
	_sync_direct_fire_mode()


func _direct_fire_controls_active() -> bool:
	return direct_fire_active or controller_aim_active


func _sync_direct_fire_mode() -> void:
	var is_active := _direct_fire_controls_active()
	if is_instance_valid(combat_simulation):
		combat_simulation.call("set_player_direct_fire_active", is_active)
	if not is_active:
		_clear_direct_fire_lines()
		if is_instance_valid(ship_visual) and ship_visual.has_method("set_direct_fire_states"):
			ship_visual.call("set_direct_fire_states", {})
		if is_instance_valid(deck_detail_visual) and deck_detail_visual.has_method("set_direct_fire_states"):
			deck_detail_visual.call("set_direct_fire_states", {})


func _direct_fire_target_world_position() -> Vector2:
	return world.get_local_mouse_position() - WORLD_ORIGIN


func _direct_fire_aim_direction() -> Vector2:
	if controller_aim_active:
		return controller_aim_direction
	var to_cursor: Vector2 = _direct_fire_target_world_position() - Vector2(simulation.ship_position)
	return to_cursor.normalized() if not to_cursor.is_zero_approx() else Vector2.UP.rotated(simulation.ship_rotation)


func _controller_device() -> int:
	var devices := Input.get_connected_joypads()
	return int(devices[0]) if not devices.is_empty() else -1


func _controller_stick(device: int, x_axis: JoyAxis, y_axis: JoyAxis) -> Vector2:
	var value := Vector2(Input.get_joy_axis(device, x_axis), Input.get_joy_axis(device, y_axis))
	var magnitude := value.length()
	if magnitude <= CONTROLLER_STICK_DEADZONE:
		return Vector2.ZERO
	var scaled := (magnitude - CONTROLLER_STICK_DEADZONE) / (1.0 - CONTROLLER_STICK_DEADZONE)
	return value.normalized() * clampf(scaled, 0.0, 1.0)


func set_controller_menu_active(is_active: bool) -> void:
	controller_menu_active = is_active
	if not is_active or not is_instance_valid(simulation):
		return
	controller_translation_indicator_input = Vector2.ZERO
	controller_aim_active = false
	_sync_direct_fire_mode()
	simulation.call("set_controller_helm_input", Vector2.ZERO, 0.0)


func _update_controller_input(delta: float) -> void:
	var device := _controller_device()
	if device < 0:
		controller_translation_indicator_input = Vector2.ZERO
		if controller_aim_active:
			controller_aim_active = false
			_sync_direct_fire_mode()
		simulation.call("set_controller_helm_input", Vector2.ZERO, 0.0)
		controller_fire_was_pressed = false
		controller_hold_was_pressed = false
		controller_recenter_was_pressed = false
		return
	if controller_menu_active:
		controller_translation_indicator_input = Vector2.ZERO
		if controller_aim_active:
			controller_aim_active = false
			_sync_direct_fire_mode()
		simulation.call("set_controller_helm_input", Vector2.ZERO, 0.0)
		controller_fire_was_pressed = Input.get_joy_axis(device, JOY_AXIS_TRIGGER_RIGHT) > CONTROLLER_TRIGGER_THRESHOLD
		controller_hold_was_pressed = Input.is_joy_button_pressed(device, JOY_BUTTON_LEFT_STICK)
		controller_recenter_was_pressed = Input.is_joy_button_pressed(device, JOY_BUTTON_RIGHT_STICK)
		return

	var translation_stick := _controller_stick(device, JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y)
	# Godot reports stick-up as negative Y; helm-forward is positive Y.
	var translation := Vector2(translation_stick.x, -translation_stick.y)
	controller_translation_indicator_input = translation
	var turn := 0.0
	if Input.is_joy_button_pressed(device, JOY_BUTTON_RIGHT_SHOULDER):
		turn += 1.0
	if Input.is_joy_button_pressed(device, JOY_BUTTON_LEFT_SHOULDER):
		turn -= 1.0
	simulation.call("set_controller_helm_input", translation, turn)

	var manual_aim_held := Input.get_joy_axis(device, JOY_AXIS_TRIGGER_LEFT) > CONTROLLER_TRIGGER_THRESHOLD
	var aim := _controller_stick(device, JOY_AXIS_RIGHT_X, JOY_AXIS_RIGHT_Y)
	var was_aiming := controller_aim_active
	controller_aim_active = manual_aim_held
	if controller_aim_active and not aim.is_zero_approx():
		controller_aim_direction = aim.normalized()
	if was_aiming != controller_aim_active:
		_sync_direct_fire_mode()
	if not controller_aim_active and absf(aim.y) > 0.001:
		var current_zoom := float(zoom_controller.get("zoom_level"))
		var requested_zoom := current_zoom * exp(-aim.y * controller_zoom_speed * delta)
		zoom_controller.call("set_zoom_level", requested_zoom)

	var fire_pressed := Input.get_joy_axis(device, JOY_AXIS_TRIGGER_RIGHT) > CONTROLLER_TRIGGER_THRESHOLD
	if manual_aim_held and fire_pressed and not controller_fire_was_pressed and controller_aim_active and is_instance_valid(combat_simulation):
		combat_simulation.call("fire_direct_volley", simulation, controller_aim_direction)
	controller_fire_was_pressed = fire_pressed

	var hold_pressed := Input.is_joy_button_pressed(device, JOY_BUTTON_LEFT_STICK)
	if hold_pressed and not controller_hold_was_pressed:
		simulation.call("controller_hold_position")
	controller_hold_was_pressed = hold_pressed

	var recenter_pressed := Input.is_joy_button_pressed(device, JOY_BUTTON_RIGHT_STICK)
	if recenter_pressed and not controller_recenter_was_pressed and not controller_aim_active:
		_center_camera_on_ship()
	controller_recenter_was_pressed = recenter_pressed


func _create_controller_translation_indicator() -> void:
	if is_instance_valid(controller_translation_indicator):
		return
	controller_translation_indicator = _new_controller_chevron(
		"ControllerMovementIndicator",
		Color(0.42, 1.0, 0.94, 0.96),
		Color(0.05, 0.9, 1.0, 0.2)
	)
	controller_aim_indicator = _new_controller_chevron(
		"ControllerAimIndicator",
		Color(1.0, 0.66, 0.2, 0.98),
		Color(1.0, 0.3, 0.05, 0.22)
	)


func _new_controller_chevron(
	indicator_name: String,
	chevron_color: Color,
	glow_color: Color
) -> Node2D:
	var indicator := Node2D.new()
	indicator.name = indicator_name
	indicator.z_index = 100
	indicator.visible = false
	add_child(indicator)
	var points := PackedVector2Array([
		Vector2(-8.0, -6.0),
		Vector2.ZERO,
		Vector2(-8.0, 6.0),
	])
	var glow := Line2D.new()
	glow.name = "Glow"
	glow.points = points
	glow.width = 7.0
	glow.default_color = glow_color
	glow.joint_mode = Line2D.LINE_JOINT_ROUND
	glow.begin_cap_mode = Line2D.LINE_CAP_ROUND
	glow.end_cap_mode = Line2D.LINE_CAP_ROUND
	glow.antialiased = true
	indicator.add_child(glow)
	var chevron := Line2D.new()
	chevron.name = "Chevron"
	chevron.points = points
	chevron.width = 2.0
	chevron.default_color = chevron_color
	chevron.joint_mode = Line2D.LINE_JOINT_ROUND
	chevron.begin_cap_mode = Line2D.LINE_CAP_ROUND
	chevron.end_cap_mode = Line2D.LINE_CAP_ROUND
	chevron.antialiased = true
	indicator.add_child(chevron)
	return indicator


func _update_controller_translation_indicator(delta: float, rendered_rotation: float) -> void:
	if not is_instance_valid(controller_translation_indicator):
		return
	var magnitude := controller_translation_indicator_input.length()
	var target_alpha := smoothstep(0.0, 0.55, magnitude)
	controller_translation_indicator_alpha = move_toward(
		controller_translation_indicator_alpha,
		target_alpha,
		delta * (9.0 if target_alpha > controller_translation_indicator_alpha else 6.0)
	)
	controller_translation_indicator.visible = controller_translation_indicator_alpha > 0.01
	if not controller_translation_indicator.visible:
		return
	if magnitude > 0.001:
		var ship_local_direction := Vector2(
			controller_translation_indicator_input.x,
			-controller_translation_indicator_input.y
		).normalized()
		var screen_direction := ship_local_direction.rotated(rendered_rotation)
		var zoom_scale := absf(world.scale.x)
		var ship_screen_extent := maxf(ship_visual.size.x, ship_visual.size.y) * 0.5 * zoom_scale
		var maximum_radius := minf(size.x, size.y) * 0.38
		var indicator_radius := clampf(ship_screen_extent + 16.0, 48.0, maximum_radius)
		controller_translation_indicator.position = size * 0.5 + screen_direction * indicator_radius
		controller_translation_indicator.rotation = screen_direction.angle()
	controller_translation_indicator.modulate.a = controller_translation_indicator_alpha


func _update_controller_aim_indicator(delta: float) -> void:
	if not is_instance_valid(controller_aim_indicator):
		return
	var target_alpha := 1.0 if controller_aim_active else 0.0
	controller_aim_indicator_alpha = move_toward(
		controller_aim_indicator_alpha,
		target_alpha,
		delta * (10.0 if controller_aim_active else 7.0)
	)
	controller_aim_indicator.visible = controller_aim_indicator_alpha > 0.01
	if not controller_aim_indicator.visible:
		return
	var screen_direction := controller_aim_direction.normalized()
	if screen_direction.is_zero_approx():
		screen_direction = Vector2.UP
	var zoom_scale := absf(world.scale.x)
	var ship_screen_extent := maxf(ship_visual.size.x, ship_visual.size.y) * 0.5 * zoom_scale
	var maximum_radius := minf(size.x, size.y) * 0.42
	var indicator_radius := clampf(ship_screen_extent + 30.0, 62.0, maximum_radius)
	controller_aim_indicator.position = size * 0.5 + screen_direction * indicator_radius
	controller_aim_indicator.rotation = screen_direction.angle()
	controller_aim_indicator.modulate.a = controller_aim_indicator_alpha


func _direct_fire_battery_direction(aim_direction: Vector2) -> Vector2:
	var ship_rotation := float(simulation.ship_rotation)
	var local_aim := aim_direction.rotated(-ship_rotation)
	var local_battery := Vector2.ZERO
	if absf(local_aim.x) >= absf(local_aim.y):
		local_battery = Vector2.RIGHT if local_aim.x >= 0.0 else Vector2.LEFT
	else:
		local_battery = Vector2.DOWN if local_aim.y >= 0.0 else Vector2.UP
	return local_battery.rotated(ship_rotation)


func _update_direct_fire_display() -> void:
	if (
		not _direct_fire_controls_active()
		or not is_instance_valid(combat_simulation)
		or not is_instance_valid(simulation)
	):
		_clear_direct_fire_lines()
		if is_instance_valid(ship_visual) and ship_visual.has_method("set_direct_fire_states"):
			ship_visual.call("set_direct_fire_states", {})
		if is_instance_valid(deck_detail_visual) and deck_detail_visual.has_method("set_direct_fire_states"):
			deck_detail_visual.call("set_direct_fire_states", {})
		return
	var aim_direction := _direct_fire_aim_direction()
	var solution: Array = combat_simulation.call(
		"get_direct_fire_solution",
		simulation,
		aim_direction
	)
	# The cursor selects a hull-side battery. Two rails leave the extreme ends of
	# that entire hull side, showing the broadside corridor without implying that
	# every individual barrel shares one pinpoint trajectory.
	while direct_fire_lines.size() < 2:
		var line := Line2D.new()
		line.name = "DirectFireBearingLine"
		line.width = 1.5
		line.antialiased = false
		line.z_index = 180
		line.begin_cap_mode = Line2D.LINE_CAP_BOX
		line.end_cap_mode = Line2D.LINE_CAP_BOX
		world.add_child(line)
		direct_fire_lines.append(line)
	while direct_fire_lines.size() > 2:
		var removed_line: Line2D = direct_fire_lines.pop_back()
		removed_line.queue_free()
	var indicator_color := direct_fire_blocked_color
	var battery_states: Dictionary = {}
	var battery_count := 0
	var ready_count := 0
	for weapon_solution: Dictionary in solution:
		# Every manual-capable authored mount tracks the cursor, even when its hull
		# side is not the battery currently selected to fire. The mount visual clamps
		# this desired bearing to its own physical traverse limits.
		var room_id: StringName = weapon_solution.get("room_id", &"")
		var mount_index := int(weapon_solution.get("mount_index", 0))
		var mount_aim_direction: Vector2 = weapon_solution.get("aim_direction", aim_direction)
		var local_aim_direction := mount_aim_direction.rotated(-float(simulation.ship_rotation))
		battery_states["%s#%d" % [String(room_id), mount_index]] = {
			"status": StringName(weapon_solution["status"]),
			"local_aim_direction": local_aim_direction,
		}
		if not bool(weapon_solution.get("battery_member", false)):
			continue
		battery_count += 1
		match StringName(weapon_solution["status"]):
			&"READY":
				ready_count += 1
			&"RELOADING":
				indicator_color = direct_fire_reloading_color
			&"DISABLED":
				if indicator_color == direct_fire_blocked_color:
					indicator_color = direct_fire_disabled_color
	if battery_count > 0 and ready_count == battery_count:
		indicator_color = direct_fire_ready_color
	elif ready_count > 0:
		indicator_color = direct_fire_reloading_color
	if ship_visual.has_method("set_direct_fire_states"):
		ship_visual.call("set_direct_fire_states", battery_states)
	if is_instance_valid(deck_detail_visual) and deck_detail_visual.has_method("set_direct_fire_states"):
		deck_detail_visual.call("set_direct_fire_states", battery_states)
	var camera_zoom := maxf(float(zoom_controller.get("zoom_level")), 0.01)
	var origin: Vector2 = WORLD_ORIGIN + Vector2(simulation.ship_position)
	var battery_direction := _direct_fire_battery_direction(aim_direction)
	var local_battery := battery_direction.rotated(-float(simulation.ship_rotation))
	var local_extremes := PackedVector2Array()
	if ship_visual.has_method("get_hull_side_extremes"):
		local_extremes = ship_visual.call("get_hull_side_extremes", local_battery)
	if local_extremes.size() < 2:
		var local_center := ship_visual.size * 0.5
		var local_tangent := local_battery.rotated(PI * 0.5)
		var along_extent := absf(local_battery.x) * local_center.x + absf(local_battery.y) * local_center.y
		var across_extent := absf(local_tangent.x) * local_center.x + absf(local_tangent.y) * local_center.y
		var side_center := local_center + local_battery * along_extent
		local_extremes = PackedVector2Array([
			side_center - local_tangent * across_extent,
			side_center + local_tangent * across_extent,
		])
	var ship_rotation := float(simulation.ship_rotation)
	var first_origin := origin + (local_extremes[0] - ship_visual.pivot_offset).rotated(ship_rotation)
	var second_origin := origin + (local_extremes[1] - ship_visual.pivot_offset).rotated(ship_rotation)
	var cone_length := 72.0 / camera_zoom
	var cone_half_angle := deg_to_rad(24.0)
	var left_direction := battery_direction.rotated(-cone_half_angle)
	var right_direction := battery_direction.rotated(cone_half_angle)
	direct_fire_lines[0].points = PackedVector2Array([first_origin, first_origin + left_direction * cone_length])
	direct_fire_lines[1].points = PackedVector2Array([second_origin, second_origin + right_direction * cone_length])
	for line: Line2D in direct_fire_lines:
		line.width = 1.5 / camera_zoom
		line.default_color = indicator_color


func _clear_direct_fire_lines() -> void:
	for line: Line2D in direct_fire_lines:
		if is_instance_valid(line):
			line.queue_free()
	direct_fire_lines.clear()


func _on_dev_menu_toggled(is_open: bool) -> void:
	dev_menu.visible = is_open
	dev_menu_toggle.text = "DEV TOOLS <" if is_open else "DEV TOOLS >"


func _populate_enemy_behaviors() -> void:
	enemy_behavior_selector.clear()
	for behavior_name: String in ["HOLD POSITION", "APPROACH PLAYER", "ORBIT PLAYER", "RETREAT"]:
		enemy_behavior_selector.add_item(behavior_name)
	enemy_behavior_selector.select(combat_simulation.default_behavior)


func _populate_sample_ships() -> void:
	sample_ship_selector.clear()
	for definition: Resource in combat_simulation.sample_ship_definitions:
		sample_ship_selector.add_item(String(definition.get("display_name")))


func _spawn_sample_enemy() -> void:
	combat_simulation.spawn_sample_enemy(sample_ship_selector.selected)
	_sync_enemy_visuals()


func _spawn_enemy() -> void:
	combat_simulation.spawn_enemy()
	_sync_enemy_visuals()


func _clear_enemies() -> void:
	combat_simulation.clear_enemies()
	_sync_enemy_visuals()


func _on_enemy_behavior_selected(index: int) -> void:
	combat_simulation.set_all_enemy_behavior(index)


func _sync_enemy_visuals() -> void:
	if not is_instance_valid(combat_simulation):
		return
	var active_enemy_ids: Dictionary = {}
	var interpolation := Engine.get_physics_interpolation_fraction()
	for enemy: Dictionary in combat_simulation.enemies:
		var enemy_id: int = enemy["id"]
		active_enemy_ids[enemy_id] = true
		if not enemy_visuals.has(enemy_id):
			var ship_instance := enemy.get("instance") as Node
			var new_visual: Control
			if is_instance_valid(ship_instance) and ship_instance.has_method("create_tactical_visual"):
				new_visual = ship_instance.call("create_tactical_visual", ENEMY_VISUAL_SCENE)
			else:
				var exterior_scene: PackedScene = enemy.get("tactical_exterior_scene", null)
				var visual_scene: PackedScene = exterior_scene if exterior_scene != null else ENEMY_VISUAL_SCENE
				new_visual = visual_scene.instantiate() as Control
				new_visual.call("set_ship_layout", enemy.get("layout", simulation.ship_layout))
				new_visual.modulate = enemy.get("tactical_tint", Color(1.0, 0.68, 0.68, 1.0))
			var is_combat_active := bool(enemy.get("combat_active", true))
			if new_visual.has_method("set_low_detail_mode"):
				new_visual.call("set_low_detail_mode", not is_combat_active)
			if new_visual.has_method("set_tactical_interest_room_types"):
				new_visual.call("set_tactical_interest_room_types", enemy.get("tactical_interest_room_types", PackedStringArray(["DOCKING", "WEAPONS", "HANGAR"])))
			world.add_child(new_visual)
			new_visual.pivot_offset = new_visual.size * 0.5
			var new_shield := new_visual.get_node_or_null("ShieldVisual")
			if new_shield != null:
				new_shield.visible = is_combat_active
			enemy_visuals[enemy_id] = new_visual
		var visual := enemy_visuals[enemy_id] as Control
		var rendered_position: Vector2 = (enemy["previous_position"] as Vector2).lerp(enemy["position"], interpolation)
		var rendered_rotation: float = lerp_angle(enemy["previous_rotation"], enemy["rotation"], interpolation)
		visual.position = WORLD_ORIGIN + rendered_position - visual.pivot_offset
		visual.rotation = rendered_rotation
		visual.call("set_simulation_identity", 1, enemy_id)
		_apply_propulsion_visual_command(visual, enemy.get("physics_body") as RigidBody2D)
		var enemy_shield := visual.get_node_or_null("ShieldVisual")
		if enemy_shield != null and bool(enemy.get("combat_active", true)):
			enemy_shield.call(
				"set_shield_banks",
				_enemy_shield_bank_report(enemy),
				float(enemy.get("shield", 0.0)) > 0.0
			)

	for enemy_id: Variant in enemy_visuals.keys().duplicate():
		if not active_enemy_ids.has(enemy_id):
			(enemy_visuals[enemy_id] as Control).queue_free()
			enemy_visuals.erase(enemy_id)
			if selected_tactical_ship_id == int(enemy_id):
				_clear_tactical_selection()
	enemy_count_label.text = "ACTIVE ENEMIES • %d" % combat_simulation.enemies.size()


func _apply_propulsion_visual_command(visual: Control, physics_body_value: Variant) -> void:
	if not is_instance_valid(visual) or not visual.has_method("set_propulsion_visual_command"):
		return
	if is_instance_valid(physics_body_value) and physics_body_value is RigidBody2D and physics_body_value.has_method("get_propulsion_visual_command"):
		var physics_body := physics_body_value as RigidBody2D
		visual.call("set_propulsion_visual_command", physics_body.call("get_propulsion_visual_command"))
	else:
		visual.call("clear_propulsion_visual_command")


func _sync_projectile_visuals() -> void:
	if not is_instance_valid(combat_simulation):
		return
	var active_projectile_ids: Dictionary = {}
	var interpolation := Engine.get_physics_interpolation_fraction()
	for projectile: Dictionary in combat_simulation.projectiles:
		# The impact and debris own the contact frame. Do not leave the spent shell
		# frozen against the hull during the simulation's short bookkeeping linger.
		if bool(projectile.get("impacted", false)):
			continue
		var projectile_id: int = projectile["id"]
		active_projectile_ids[projectile_id] = true
		if not projectile_visuals.has(projectile_id):
			var visual_scene: PackedScene = projectile["visual_scene"]
			if visual_scene == null:
				continue
			var new_visual: Node2D = visual_scene.instantiate()
			world.add_child(new_visual)
			projectile_visuals[projectile_id] = new_visual
		if not projectile_visuals.has(projectile_id):
			continue
		var visual := projectile_visuals[projectile_id] as Node2D
		var previous_position: Vector2 = projectile["previous_position"]
		var current_position: Vector2 = projectile["position"]
		var velocity: Vector2 = projectile["velocity"]
		visual.position = WORLD_ORIGIN + previous_position.lerp(current_position, interpolation)
		visual.rotation = velocity.angle()
		if visual.has_method("set_travel_distance"):
			visual.call("set_travel_distance", float(projectile.get("travelled_distance", 0.0)))

	for projectile_id: Variant in projectile_visuals.keys().duplicate():
		if not active_projectile_ids.has(projectile_id):
			(projectile_visuals[projectile_id] as Node2D).queue_free()
			projectile_visuals.erase(projectile_id)


func _sync_fighter_visuals() -> void:
	if not is_instance_valid(combat_simulation):
		return
	var active_ids: Dictionary = {}
	var interpolation := Engine.get_physics_interpolation_fraction()
	for fighter: Dictionary in combat_simulation.fighters:
		var fighter_id: int = int(fighter["id"])
		active_ids[fighter_id] = true
		if not fighter_visuals.has(fighter_id):
			var behavior: Resource = fighter["behavior"]
			var visual_scene: PackedScene = behavior.get("visual_scene")
			if visual_scene == null:
				continue
			var new_visual := visual_scene.instantiate() as Node2D
			world.add_child(new_visual)
			var configured_scale: float = float(behavior.get("visual_scale"))
			new_visual.scale = Vector2.ONE * configured_scale
			fighter_visuals[fighter_id] = new_visual
		if not fighter_visuals.has(fighter_id):
			continue
		var visual := fighter_visuals[fighter_id] as Node2D
		var previous_position: Vector2 = fighter["previous_position"]
		var current_position: Vector2 = fighter["position"]
		visual.position = WORLD_ORIGIN + previous_position.lerp(current_position, interpolation)
		visual.rotation = lerp_angle(float(fighter["previous_rotation"]), float(fighter["rotation"]), interpolation)
		if visual.has_method("set_thrust_visual"):
			visual.call("set_thrust_visual", 1.0 if previous_position.distance_to(current_position) > 0.1 else 0.0)
	for fighter_id_value: Variant in fighter_visuals.keys().duplicate():
		if not active_ids.has(fighter_id_value):
			(fighter_visuals[fighter_id_value] as Node2D).queue_free()
			fighter_visuals.erase(fighter_id_value)


func _sync_fragment_visuals() -> void:
	if not is_instance_valid(combat_simulation):
		return
	var active_fragment_ids: Dictionary = {}
	var interpolation := Engine.get_physics_interpolation_fraction()
	for fragment: Dictionary in combat_simulation.impact_fragments:
		var fragment_id: int = fragment["id"]
		active_fragment_ids[fragment_id] = true
		if not fragment_visuals.has(fragment_id):
			var line := Line2D.new()
			var half_length := float(fragment["length"]) * 0.5
			line.points = PackedVector2Array([Vector2(-half_length, 0.0), Vector2(half_length, 0.0)]) if bool(fragment.get("tumbling", false)) else PackedVector2Array([Vector2.ZERO, Vector2(-float(fragment["length"]), 0.0)])
			line.width = fragment["width"]
			line.default_color = fragment["color"]
			line.begin_cap_mode = Line2D.LINE_CAP_ROUND
			line.end_cap_mode = Line2D.LINE_CAP_ROUND
			world.add_child(line)
			fragment_visuals[fragment_id] = line
		var visual := fragment_visuals[fragment_id] as Line2D
		var previous_position: Vector2 = fragment["previous_position"]
		var current_position: Vector2 = fragment["position"]
		var velocity: Vector2 = fragment["velocity"]
		visual.position = WORLD_ORIGIN + previous_position.lerp(current_position, interpolation)
		if bool(fragment.get("tumbling", false)):
			visual.rotation = lerp_angle(float(fragment["previous_rotation"]), float(fragment["rotation"]), interpolation)
		elif velocity.length_squared() > 0.01:
			visual.rotation = velocity.angle()
		var lifetime_ratio := float(fragment["remaining_lifetime"]) / maxf(float(fragment["maximum_lifetime"]), 0.001)
		visual.modulate.a = smoothstep(0.0, 0.35, lifetime_ratio)
	for fragment_id: Variant in fragment_visuals.keys().duplicate():
		if not active_fragment_ids.has(fragment_id):
			(fragment_visuals[fragment_id] as Line2D).queue_free()
			fragment_visuals.erase(fragment_id)


func _update_camera_follow(rendered_ship_position: Vector2, _delta: float) -> void:
	var ship_world_point := WORLD_ORIGIN + rendered_ship_position
	world.position = (
		size * 0.5
		- world.pivot_offset
		- (ship_world_point - world.pivot_offset) * world.scale
	)


func _apply_deck_camera_leash(rendered_ship_position: Vector2) -> void:
	var ship_world_point := WORLD_ORIGIN + rendered_ship_position
	var ship_screen_point := world.get_transform() * ship_world_point
	var viewport_margin := size * deck_camera_leash_margin
	var minimum_screen_point := viewport_margin
	var maximum_screen_point := size - viewport_margin
	var leashed_screen_point := ship_screen_point.clamp(minimum_screen_point, maximum_screen_point)
	world.position += leashed_screen_point - ship_screen_point

func _update_ship_label_visibility(delta: float) -> void:
	var mouse_over_ship := Rect2(Vector2.ZERO, ship_visual.size).has_point(
		ship_visual.get_local_mouse_position()
	)
	var zoom_level: float = zoom_controller.get("zoom_level")
	var zoom_visibility := smoothstep(label_hidden_zoom, label_fade_start_zoom, zoom_level)
	var desired_alpha := zoom_visibility if mouse_over_ship else 0.0
	ship_label_alpha = move_toward(ship_label_alpha, desired_alpha, label_fade_speed * delta)

	for index: int in range(ship_labels.size() - 1, -1, -1):
		var label := ship_labels[index]
		if not is_instance_valid(label):
			ship_labels.remove_at(index)
			continue
		label.modulate.a = ship_label_alpha


func _update_shield_visual() -> void:
	var shield_active: bool = simulation.is_shield_active()
	shield_visual.call(
		"set_shield_banks",
		simulation.call("get_shield_bank_report"),
		shield_active
	)


func _enemy_shield_bank_report(enemy: Dictionary) -> Dictionary:
	var report: Dictionary = {}
	var layout := enemy.get("layout") as Resource
	var maximum := float(enemy.get("maximum_shield", 0.0))
	var current := float(enemy.get("shield", 0.0))
	if layout == null or maximum <= 0.0:
		return report
	var layout_key := layout.get_instance_id()
	var weights: Dictionary = enemy_shield_bank_weight_cache.get(layout_key, {})
	if weights.is_empty():
		weights = _shield_bank_weights_for_layout(layout)
		enemy_shield_bank_weight_cache[layout_key] = weights
	var total_weight := 0.0
	for weight_value: Variant in weights.values():
		total_weight += float(weight_value)
	var ratio := clampf(current / maximum, 0.0, 1.0)
	for bank_value: Variant in weights.keys():
		var bank := int(bank_value)
		var bank_maximum := maximum * float(weights[bank]) / maxf(total_weight, 0.001)
		report[bank] = {
			"current": bank_maximum * ratio,
			"maximum": bank_maximum,
			"ratio": ratio,
			"online": current > 0.0,
		}
	return report


func _shield_bank_weights_for_layout(layout: Resource) -> Dictionary:
	var weights: Dictionary = {}
	for room: Resource in layout.get("rooms"):
		if String(room.get("type_name")) != "SHIELDS":
			continue
		var rects: Array[Rect2i] = room.get("grid_rects")
		var facings: Array = room.get("module_mount_facings")
		for index: int in range(rects.size()):
			var view := room.duplicate(false)
			var one_rect: Array[Rect2i] = [rects[index]]
			view.set("grid_rects", one_rect)
			var facing := int(room.get("module_facing_quarters"))
			if index < facings.size():
				facing = int(facings[index])
			view.set("module_facing_quarters", facing)
			var resolved := GRID_GEOMETRY.resolved_module_facing(layout, view)
			var exposed := GRID_GEOMETRY.room_exposed_quarters(layout, view)
			if not exposed.has(resolved):
				continue
			weights[resolved] = float(weights.get(resolved, 0.0)) + float(rects[index].size.x * rects[index].size.y)
	if weights.is_empty():
		for bank: int in range(4):
			weights[bank] = 1.0
	return weights
