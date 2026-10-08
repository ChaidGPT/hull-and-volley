extends Control

const EXPLICIT_GROUP_ROOM_TYPES := ["WEAPONS", "PROPULSION", "HANGAR", "SHIELDS"]
const INVALID_CELL := Vector2i(2147483647, 2147483647)
const GRID_GEOMETRY := preload("res://scripts/grid_geometry.gd")
const SHIP_RESOURCE_ANALYZER := preload("res://scripts/ship_builder_analyzer.gd")
const POWER_REQUIREMENT_DISPLAY := preload("res://scripts/power_requirement_display.gd")
const CREW_REQUIREMENT_DISPLAY := preload("res://scripts/crew_requirement_display.gd")
const GRID_TYPE_CATEGORIES := {
	"CREW": ["COMMAND", "CREW_QUARTERS", "MESS_HALL", "MEDICAL"],
	"ENGINEERING": ["PROPULSION", "POWER", "SHIELDS", "WORKSHOP"],
	"COMBAT": ["WEAPONS", "SECURITY"],
	"LOGISTICS": ["UNASSIGNED", "HANGAR", "DOCKING", "SENSOR"],
}
const FIRE_MODE_LINKED := 0
const FIRE_MODE_TRIGGER := 1
const FIRE_MODE_SENTRY := 2

@export_category("Hangar Launch Validation")
## Empty distance required beyond a hangar edge before that deployment direction may be selected.
@export_range(0.5, 8.0, 0.25) var hangar_launch_clearance_cells := 2.5
## Width of the tested launch corridor in grid-cell units.
@export_range(0.2, 1.5, 0.05) var hangar_launch_corridor_width := 0.65

@export_category("Structural Damage Lab")
## Durability removed by the LIGHT test action.
@export_range(1.0, 500.0, 1.0) var test_light_wall_damage := 15.0
## Durability removed by the HEAVY test action.
@export_range(1.0, 1000.0, 1.0) var test_heavy_wall_damage := 45.0
## Penetration energy sent through the selected wall and every wall behind it.
@export_range(1.0, 10000.0, 5.0) var test_penetration_energy := 240.0
## Fraction of test wall damage also applied to each compartment touching that wall.
@export_range(0.0, 2.0, 0.05) var test_wall_to_room_damage := 0.5

@onready var settlement_grid: Control = %SettlementGrid
@onready var selected_room_name: Label = %SelectedRoomName
@onready var selected_room_type: Label = %SelectedRoomType
@onready var selected_room_status_lamp: Label = %SelectedRoomStatusLamp
@onready var selected_room_status_text: Label = %SelectedRoomStatusText
@onready var selected_room_health: Label = %SelectedRoomHealth
@onready var selected_room_output: Label = %SelectedRoomOutput
@onready var selected_room_crew: Label = %SelectedRoomCrew
@onready var selected_room_oxygen: Label = %SelectedRoomOxygen
@onready var selected_room_oxygen_bar: ProgressBar = %SelectedRoomOxygenBar
@onready var selected_room_health_bar: ProgressBar = %SelectedRoomHealthBar
@onready var selected_room_panel: PanelContainer = %SelectedRoomPanel
@onready var system_detail_button: Button = %SystemDetailButton
@onready var system_detail_panel: PanelContainer = %SystemDetailPanel
@onready var close_system_detail_button: Button = %CloseSystemDetailButton
@onready var system_detail_room_name: Label = %SystemDetailRoomName
@onready var system_detail_status: Label = %SystemDetailStatus
@onready var system_detail_output: Label = %SystemDetailOutput
@onready var system_detail_crew: Label = %SystemDetailCrew
@onready var system_detail_action: Label = %SystemDetailAction
@onready var editor_panel: PanelContainer = %EditorPanel
@onready var editor_button: Button = %EditorButton
@onready var editor_room_type: OptionButton = %EditorRoomType
@onready var add_tool_button: Button = %AddToolButton
@onready var delete_tool_button: Button = %DeleteToolButton
@onready var group_tool_button: Button = %GroupToolButton
@onready var group_instruction: Label = %GroupInstruction
@onready var group_actions: HBoxContainer = %GroupActions
@onready var recipe_section: VBoxContainer = %RecipeSection
@onready var recipe_selector: OptionButton = %RecipeSelector
@onready var recipe_stats: Label = %RecipeStats
@onready var facing_controls: HBoxContainer = %FacingControls
@onready var facing_buttons := {
	0: %FacingForwardButton,
	1: %FacingStarboardButton,
	2: %FacingRearButton,
	3: %FacingPortButton,
}
@onready var editor_status: Label = %EditorStatus
@onready var zoom_controller: Node = %ZoomController
@onready var grid_status: Label = %GridStatus
@onready var deck_power_meter: Control = %DeckPowerMeter
@onready var deck_crew_meter: Control = %DeckCrewMeter
@onready var room_callout: Control = %RoomCallout
@onready var weapon_configuration: VBoxContainer = %WeaponConfiguration
@onready var weapon_readout: PanelContainer = %WeaponReadout
@onready var weapon_readout_label: Label = %WeaponReadoutLabel
@onready var weapon_type_selector: OptionButton = %WeaponTypeSelector
@onready var weapon_stats: Label = %WeaponStats
@onready var fire_directive_title: Label = %FireDirectiveTitle
@onready var linked_fire_button: Button = %LinkedFireButton
@onready var trigger_fire_button: Button = %TriggerFireButton
@onready var sentry_fire_button: Button = %SentryFireButton
@onready var hangar_facing_configuration: VBoxContainer = %HangarFacingConfiguration
@onready var hangar_facing_hint: Label = %HangarFacingHint
@onready var hangar_facing_readout: PanelContainer = %HangarFacingReadout
@onready var hangar_facing_readout_label: Label = %HangarFacingReadoutLabel
@onready var hangar_facing_buttons: GridContainer = %HangarFacingButtons
@onready var selected_hangar_facing_buttons := {
	0: %Forward,
	1: %Starboard,
	2: %Rear,
	3: %Port,
}
@onready var category_section: PanelContainer = %CategorySection
@onready var type_section: PanelContainer = %TypeSection
@onready var add_section: PanelContainer = %AddSection
@onready var occupied_section: PanelContainer = %OccupiedSection
@onready var grid_type_category_label: Label = %GridTypeCategoryLabel
@onready var grid_type_buttons: VBoxContainer = %GridTypeButtons
@onready var confirm_add_button: Button = %ConfirmAddButton
@onready var damage_lab_button: Button = %DamageLabButton
@onready var damage_lab_panel: PanelContainer = %DamageLabPanel
@onready var damage_lab_status: Label = %DamageLabStatus
@onready var staffing_configuration: VBoxContainer = %StaffingConfiguration
@onready var room_staffing_meter: Control = %RoomStaffingMeter
@onready var assigned_crew_list: VBoxContainer = %AssignedCrewList
@onready var no_assigned_crew_label: Label = %NoAssignedCrewLabel
@onready var auto_assign_crew_button: Button = %AutoAssignCrewButton
@onready var open_dispatch_button: Button = %OpenDispatchButton
@onready var manual_dispatch_panel: PanelContainer = %ManualDispatchPanel
@onready var staffing_crew_selector: OptionButton = %CrewSelector
@onready var assign_crew_button: Button = %AssignCrewButton
@onready var manual_staffing_row: HBoxContainer = %ManualRow
@onready var close_dispatch_button: Button = %CloseDispatchButton
@onready var crew_action_panel: PanelContainer = %CrewActionPanel
@onready var crew_action_name: Label = %CrewActionName
@onready var crew_action_status: Label = %CrewActionStatus
@onready var crew_action_morale_bar: ProgressBar = %CrewActionMoraleBar
@onready var damage_control_status: Label = %DamageControlStatus
@onready var damage_control_status_button: Button = %DamageControlStatusButton
@onready var damage_control_panel: PanelContainer = %DamageControlPanel
@onready var order_room_repair_button: Button = %OrderRoomRepairButton
@onready var order_breach_repair_button: Button = %OrderBreachRepairButton

var simulation
var selected_room_id: StringName = &""
var editor_mode := false
var editor_tool := "add"
var hovered_room_name := ""
var hovered_room_anchor := Vector2.ZERO
var group_selected_cells: Dictionary = {}
var pending_editor_cell := INVALID_CELL
var pending_editor_offset := Vector2.ZERO
var pending_room_type := ""
var damage_lab_mode := false
var selected_structural_wall := ""
var damage_lab_message := ""
var staffing_crew_ids: Array[int] = []
var staffing_roster_signature := ""
var staffing_display_signature := ""
var action_crew_id := 0
var auto_assign_needed_systems_button: Button


func _ready() -> void:
	simulation = get_tree().get_first_node_in_group("ship_simulation")
	settlement_grid.connect("room_selected", _on_room_selected)
	settlement_grid.connect("editor_cell_clicked", _on_editor_cell_clicked)
	settlement_grid.connect("room_hovered", _on_room_hovered)
	settlement_grid.connect("room_hover_exited", _on_room_hover_exited)
	settlement_grid.connect("empty_space_selected", _on_empty_space_selected)
	settlement_grid.connect("structural_wall_selected", _on_structural_wall_selected)
	editor_button.toggled.connect(_on_editor_mode_toggled)
	damage_lab_button.toggled.connect(_on_damage_lab_toggled)
	%LightDamageButton.pressed.connect(_damage_selected_wall.bind(test_light_wall_damage))
	%HeavyDamageButton.pressed.connect(_damage_selected_wall.bind(test_heavy_wall_damage))
	%BreachWallButton.pressed.connect(_breach_selected_wall)
	%PenetrationTestButton.pressed.connect(_fire_test_penetrator)
	%RepairWallButton.pressed.connect(_repair_selected_wall)
	%RestoreAtmosphereButton.pressed.connect(_restore_test_atmosphere)
	system_detail_button.pressed.connect(_open_system_detail_panel)
	close_system_detail_button.pressed.connect(func() -> void: system_detail_panel.call("power_off"))
	auto_assign_crew_button.pressed.connect(_cycle_selected_room_staffing_priority)
	open_dispatch_button.pressed.connect(_open_manual_dispatch_panel)
	close_dispatch_button.pressed.connect(func() -> void: manual_dispatch_panel.call("power_off"))
	assign_crew_button.pressed.connect(_manually_assign_selected_room)
	staffing_crew_selector.item_selected.connect(_on_staffing_crew_selected)
	%ManualPickCrewButton.pressed.connect(_select_action_crew_in_picker)
	%UnassignRoomCrewButton.pressed.connect(_unassign_action_crew)
	%CloseCrewActionButton.pressed.connect(func() -> void: crew_action_panel.call("power_off"))
	order_room_repair_button.pressed.connect(_order_selected_room_repair)
	order_breach_repair_button.pressed.connect(_order_selected_breach_repairs)
	damage_control_status_button.pressed.connect(_open_damage_control_status)
	_apply_command_button_style(auto_assign_crew_button, Color(1.0, 0.62, 0.18, 1.0), true)
	_apply_command_button_style(open_dispatch_button, Color(0.25, 0.92, 0.82, 1.0))
	_apply_command_button_style(assign_crew_button, Color(1.0, 0.62, 0.18, 1.0), true)
	settlement_grid.call("set_weapon_envelopes_outside_editor", true)
	assigned_crew_list.visible = false
	open_dispatch_button.visible = false
	selected_room_crew.visible = false
	add_tool_button.pressed.connect(_set_editor_tool.bind("add"))
	delete_tool_button.pressed.connect(_set_editor_tool.bind("delete"))
	group_tool_button.pressed.connect(_set_editor_tool.bind("group"))
	%CombineButton.pressed.connect(_combine_selected_cells)
	%SplitButton.pressed.connect(_split_selected_groups)
	%ClearGroupSelectionButton.pressed.connect(_clear_group_selection)
	%FinishGroupingButton.pressed.connect(_finish_grouping)
	%InstallRecipeButton.pressed.connect(_install_selected_recipe)
	recipe_selector.item_selected.connect(_on_recipe_selected)
	%FacingForwardButton.pressed.connect(_set_selected_group_facing.bind(0))
	%FacingStarboardButton.pressed.connect(_set_selected_group_facing.bind(1))
	%FacingRearButton.pressed.connect(_set_selected_group_facing.bind(2))
	%FacingPortButton.pressed.connect(_set_selected_group_facing.bind(3))
	%SaveLayoutButton.pressed.connect(_save_layout)
	weapon_type_selector.item_selected.connect(_on_weapon_type_selected)
	linked_fire_button.pressed.connect(_set_selected_weapon_fire_mode.bind(FIRE_MODE_LINKED))
	trigger_fire_button.pressed.connect(_set_selected_weapon_fire_mode.bind(FIRE_MODE_TRIGGER))
	sentry_fire_button.pressed.connect(_set_selected_weapon_fire_mode.bind(FIRE_MODE_SENTRY))
	_apply_command_button_style(linked_fire_button, Color(0.24, 0.95, 0.86, 1.0))
	_apply_command_button_style(trigger_fire_button, Color(1.0, 0.64, 0.2, 1.0))
	_apply_command_button_style(sentry_fire_button, Color(0.72, 0.42, 1.0, 1.0))
	for facing_value: Variant in selected_hangar_facing_buttons.keys():
		(selected_hangar_facing_buttons[facing_value] as Button).pressed.connect(_set_selected_hangar_facing.bind(int(facing_value)))
	%CrewCategoryButton.pressed.connect(_on_grid_category_selected.bind("CREW"))
	%EngineeringCategoryButton.pressed.connect(_on_grid_category_selected.bind("ENGINEERING"))
	%CombatCategoryButton.pressed.connect(_on_grid_category_selected.bind("COMBAT"))
	%LogisticsCategoryButton.pressed.connect(_on_grid_category_selected.bind("LOGISTICS"))
	confirm_add_button.pressed.connect(_confirm_add_pending_cell)
	%DeleteSelectedCellButton.pressed.connect(_delete_pending_cell)
	%GroupSelectedCellButton.pressed.connect(_group_pending_cell)
	_populate_room_types()
	_populate_weapon_types()
	_set_editor_tool("add")
	selected_room_panel.call("power_off", true)
	editor_panel.call("power_off", true)
	category_section.call("power_off", true)
	type_section.call("power_off", true)
	add_section.call("power_off", true)
	occupied_section.call("power_off", true)
	damage_lab_panel.call("power_off", true)
	crew_action_panel.call("power_off", true)
	damage_control_panel.call("power_off", true)
	manual_dispatch_panel.call("power_off", true)
	system_detail_panel.call("power_off", true)


func _process(_delta: float) -> void:
	_update_selected_room_panel()
	_update_system_detail_panel()
	_update_room_status_indicators()
	_update_arcade_resource_meters()
	_update_damage_lab_panel()
	settlement_grid.queue_redraw()
	var layout: Resource = settlement_grid.get("ship_layout")
	var bounds: Rect2i = layout.call("get_occupied_bounds")
	var build_bounds: Rect2i = layout.call("get_build_bounds")
	var offset_cells: Dictionary = {}
	for cell: Vector2i in layout.get("offset_cells"):
		offset_cells[cell] = true
	for cell: Vector2i in layout.get("vertical_offset_cells"):
		offset_cells[cell] = true
	var offset_count: int = offset_cells.size()
	grid_status.text = "HULL %dx%d • BUILD ENVELOPE %dx%d • %d OFFSET CELLS" % [bounds.size.x, bounds.size.y, build_bounds.size.x, build_bounds.size.y, offset_count]
	if not hovered_room_name.is_empty() and not editor_mode:
		var global_anchor: Vector2 = settlement_grid.get_global_transform() * hovered_room_anchor
		var callout_anchor: Vector2 = room_callout.get_global_transform().affine_inverse() * global_anchor
		room_callout.call("show_room", hovered_room_name, callout_anchor)


func _update_arcade_resource_meters() -> void:
	var layout: Resource = settlement_grid.get("ship_layout")
	if layout == null:
		return
	var stats: Dictionary = SHIP_RESOURCE_ANALYZER.analyze(layout)
	var report: Dictionary = simulation.get_power_network_report() if is_instance_valid(simulation) and simulation.has_method("get_power_network_report") else SHIP_RESOURCE_ANALYZER.power_network_report(layout)
	deck_power_meter.call(
		"set_power_coverage_state",
		int(report.get("reactor_field_count", stats.get("reactor_field_count", 0))),
		int(report.get("powered_room_count", stats.get("powered_room_count", 0))),
		int(report.get("underpowered_room_count", stats.get("underpowered_room_count", 0))),
		float(report.get("active_reactor_fields", stats.get("reactor_field_count", 0)))
	)
	var crew_state := _live_crew_meter_state()
	var crew := get_tree().get_first_node_in_group("crew_simulation")
	var missing_stations := int(crew.call("get_unfilled_minimum_stations")) if is_instance_valid(crew) else 0
	var crew_capacity := int(stats["crew_capacity"])
	deck_crew_meter.call(
		"set_crew_state",
		int(crew_state["working"]),
		int(crew_state["available"]),
		int(crew_state["injured"]),
		missing_stations,
		0,
		"live",
		crew_capacity,
		int(crew_state["security"]),
		int(crew_state["labor"])
	)
	if is_instance_valid(crew) and crew.has_method("get_reinforcement_status"):
		deck_crew_meter.call("set_reinforcement_state", crew.call("get_reinforcement_status"))


func _live_crew_meter_state() -> Dictionary:
	var state := {"working": 0, "available": 0, "injured": 0, "security": 0, "labor": 0}
	var crew := get_tree().get_first_node_in_group("crew_simulation")
	if not is_instance_valid(crew):
		return state
	for member: Dictionary in crew.crew_members:
		if bool(member.get("dead", false)) or bool(member.get("ejected", false)):
			continue
		var maximum_health := maxf(float(member.get("maximum_health", 1.0)), 1.0)
		var is_injured := (
			bool(member.get("incapacitated", false))
			or bool(member.get("seeking_medical", false))
			or float(member.get("health", maximum_health)) < maximum_health - 0.001
		)
		if is_injured:
			state["injured"] = int(state["injured"]) + 1
		elif String(member.get("reserve_role", "")) == "SECURITY":
			state["security"] = int(state["security"]) + 1
		elif String(member.get("reserve_role", "")) == "LABOR":
			state["labor"] = int(state["labor"]) + 1
		elif StringName(member.get("assigned_room_id", &"")) != &"" or int(member.get("active_job_id", 0)) > 0:
			state["working"] = int(state["working"]) + 1
		else:
			state["available"] = int(state["available"]) + 1
	return state


func _ship_has_full_crew_capacity() -> bool:
	var layout: Resource = settlement_grid.get("ship_layout") if is_instance_valid(settlement_grid) else null
	if layout == null:
		return false
	var stats := SHIP_RESOURCE_ANALYZER.analyze(layout)
	return int(stats.get("crew_capacity", 0)) >= int(stats.get("optimal_crew", 0))


func _on_room_selected(room_id: StringName) -> void:
	var should_power_on_panel := selected_room_id != room_id or not selected_room_panel.visible
	selected_room_id = room_id
	staffing_roster_signature = ""
	staffing_display_signature = "__FORCE__"
	crew_action_panel.call("power_off", true)
	damage_control_panel.call("power_off")
	manual_dispatch_panel.call("power_off")
	system_detail_panel.call("power_off")
	_update_selected_room_panel()
	if should_power_on_panel:
		selected_room_panel.call("power_on_from", get_viewport().get_mouse_position())


func _on_empty_space_selected() -> void:
	if selected_room_panel.visible:
		_play_menu_sound("play_cancel")
	selected_room_id = &""
	settlement_grid.call("clear_room_selection")
	selected_room_panel.call("power_off")
	crew_action_panel.call("power_off")
	damage_control_panel.call("power_off")
	manual_dispatch_panel.call("power_off")
	system_detail_panel.call("power_off")


func _open_damage_control_status() -> void:
	if selected_room_id == &"" or not damage_control_status_button.visible:
		return
	system_detail_panel.call("power_off")
	damage_control_panel.call("power_on_from", damage_control_status_button.get_global_rect().get_center())


func _open_system_detail_panel() -> void:
	if selected_room_id == &"" or system_detail_button.disabled:
		return
	damage_control_panel.call("power_off")
	manual_dispatch_panel.call("power_off")
	system_detail_panel.call("power_on_from", system_detail_button.get_global_rect().get_center())
	_update_system_detail_panel()


func _on_room_hovered(room_name: String, anchor_local: Vector2) -> void:
	hovered_room_name = room_name
	hovered_room_anchor = anchor_local


func _on_room_hover_exited() -> void:
	hovered_room_name = ""
	room_callout.call("hide_room")


func _on_editor_mode_toggled(is_enabled: bool) -> void:
	if is_enabled and damage_lab_mode:
		damage_lab_button.set_pressed_no_signal(false)
		_set_damage_lab_mode(false)
	editor_mode = is_enabled
	settlement_grid.call("set_editor_mode", is_enabled)
	editor_button.text = "EXIT EDITOR" if is_enabled else "OPEN SHIP EDITOR"
	editor_status.text = "CLICK A CELL TO EDIT" if is_enabled else ""
	if is_enabled:
		_set_editor_tool("add")
		selected_room_panel.call("power_off")
		editor_panel.call("power_off", true)
		category_section.call("power_off", true)
		type_section.call("power_off", true)
		add_section.call("power_off", true)
		occupied_section.call("power_off", true)
		_on_room_hover_exited()
	else:
		_play_menu_sound("play_cancel")
		editor_panel.call("power_off")
		category_section.call("power_off")
		type_section.call("power_off")
		add_section.call("power_off")
		occupied_section.call("power_off")
		pending_editor_cell = INVALID_CELL
		pending_editor_offset = Vector2.ZERO
		_clear_group_selection()


func _on_damage_lab_toggled(is_enabled: bool) -> void:
	if is_enabled and editor_mode:
		editor_button.set_pressed_no_signal(false)
		_on_editor_mode_toggled(false)
	_set_damage_lab_mode(is_enabled)


func toggle_dev_ship_editor() -> void:
	var enable := not editor_mode
	editor_button.set_pressed_no_signal(enable)
	_on_editor_mode_toggled(enable)


func toggle_dev_structural_test() -> void:
	var enable := not damage_lab_mode
	damage_lab_button.set_pressed_no_signal(enable)
	_on_damage_lab_toggled(enable)


func _set_damage_lab_mode(is_enabled: bool) -> void:
	damage_lab_mode = is_enabled
	selected_structural_wall = ""
	damage_lab_message = ""
	settlement_grid.call("set_damage_lab_mode", is_enabled)
	damage_lab_button.text = "EXIT STRUCTURAL TEST" if is_enabled else "STRUCTURAL TEST"
	selected_room_panel.call("power_off")
	damage_lab_panel.call("power_off")
	if is_enabled:
		_on_room_hover_exited()
	else:
		_play_menu_sound("play_cancel")


func _on_structural_wall_selected(wall_key: String) -> void:
	selected_structural_wall = wall_key
	damage_lab_message = ""
	damage_lab_panel.call("power_on_from", get_viewport().get_mouse_position())
	_update_damage_lab_panel()


func _player_structural_state() -> ShipStructuralState:
	var combat := get_tree().get_first_node_in_group("combat_simulation")
	if not is_instance_valid(combat):
		return null
	return combat.call("get_structural_state", 0, 0)


func _update_damage_lab_panel() -> void:
	if not damage_lab_mode or selected_structural_wall.is_empty():
		return
	var structure := _player_structural_state()
	if structure == null or not structure.walls.has(selected_structural_wall):
		damage_lab_status.text = "WALL DATA UNAVAILABLE"
		return
	var wall: Dictionary = structure.walls[selected_structural_wall]
	var wall_kind := "OUTER HULL" if bool(wall["outer"]) else "INTERNAL BULKHEAD"
	var condition := "BREACHED" if bool(wall["breached"]) else "%d / %d" % [roundi(float(wall["current"])), roundi(float(wall["maximum"]))]
	damage_lab_status.text = "%s • %s" % [wall_kind, condition]
	if not damage_lab_message.is_empty():
		damage_lab_status.text += "\n" + damage_lab_message


func _damage_selected_wall(amount: float) -> void:
	var structure := _player_structural_state()
	if structure == null or selected_structural_wall.is_empty():
		return
	var wall: Dictionary = structure.walls[selected_structural_wall]
	var applied := minf(float(wall["current"]), amount)
	structure.damage_wall(selected_structural_wall, amount)
	_apply_structural_test_room_damage(structure, selected_structural_wall, applied)
	damage_lab_message = "APPLIED %d STRUCTURAL DAMAGE" % roundi(amount)
	_play_menu_sound("play_execute")
	_update_damage_lab_panel()


func _breach_selected_wall() -> void:
	var structure := _player_structural_state()
	if structure == null or selected_structural_wall.is_empty():
		return
	var wall: Dictionary = structure.walls[selected_structural_wall]
	var applied := float(wall["current"])
	structure.breach_wall(selected_structural_wall)
	_apply_structural_test_room_damage(structure, selected_structural_wall, applied)
	damage_lab_message = "WALL OPEN TO VACUUM"
	_play_menu_sound("play_execute")
	_update_damage_lab_panel()


func _fire_test_penetrator() -> void:
	var structure := _player_structural_state()
	if structure == null or selected_structural_wall.is_empty():
		return
	var result: Dictionary = structure.trace_from_wall(selected_structural_wall, test_penetration_energy, 20.0)
	var hits: Array = result["hits"]
	for hit: Dictionary in hits:
		_apply_structural_test_room_damage(structure, String(hit["key"]), float(hit["damage"]))
	damage_lab_message = "PENETRATOR CONTACTED %d WALL SEGMENTS" % hits.size()
	_play_menu_sound("play_execute")
	_update_damage_lab_panel()


func _apply_structural_test_room_damage(structure: ShipStructuralState, wall_key: String, wall_damage: float) -> void:
	if wall_damage <= 0.0 or not structure.walls.has(wall_key) or not is_instance_valid(simulation):
		return
	var wall: Dictionary = structure.walls[wall_key]
	var room_ids: Array[StringName] = []
	for cell_value: Variant in wall["cells"]:
		var room_id: StringName = structure.cell_rooms.get(cell_value, &"")
		if room_id != &"" and not room_ids.has(room_id):
			room_ids.append(room_id)
	if room_ids.is_empty():
		return
	var shared_damage := wall_damage * test_wall_to_room_damage / float(room_ids.size())
	for room_id: StringName in room_ids:
		simulation.apply_room_damage(room_id, shared_damage)


func _repair_selected_wall() -> void:
	var structure := _player_structural_state()
	if structure == null or selected_structural_wall.is_empty():
		return
	structure.repair_wall(selected_structural_wall)
	damage_lab_message = "WALL SEALED AND RESTORED"
	_play_menu_sound("play_execute")
	_update_damage_lab_panel()


func _restore_test_atmosphere() -> void:
	var structure := _player_structural_state()
	if structure == null:
		return
	structure.restore_atmosphere()
	damage_lab_message = "ATMOSPHERE RESTORED; OPEN BREACHES WILL VENT AGAIN"
	_play_menu_sound("play_execute")
	_update_damage_lab_panel()


func _set_editor_tool(tool_name: String) -> void:
	editor_tool = tool_name
	add_tool_button.button_pressed = tool_name == "add"
	delete_tool_button.button_pressed = tool_name == "delete"
	group_tool_button.button_pressed = tool_name == "group"
	var is_group_tool := tool_name == "group"
	_set_submenu_visible(group_instruction, is_group_tool)
	_set_submenu_visible(group_actions, is_group_tool)
	_set_submenu_visible(facing_controls, is_group_tool)
	_set_submenu_visible(recipe_section, is_group_tool)
	editor_room_type.disabled = is_group_tool
	settlement_grid.call("set_editor_selection_mode", is_group_tool)
	if not is_group_tool:
		_clear_group_selection()
	else:
		_update_recipe_options()
	if editor_mode:
		match tool_name:
			"add":
				editor_status.text = "ADD: CLICK A CELL"
			"delete":
				editor_status.text = "DELETE: CLICK A CELL"
			_:
				editor_status.text = "GROUP: SELECT CONNECTED CELLS"


func _set_submenu_visible(control: Control, should_show: bool) -> void:
	if not should_show:
		control.visible = false
		control.scale = Vector2.ONE
		control.modulate = Color.WHITE
		return
	control.visible = true
	control.pivot_offset = control.size * 0.5
	control.scale = Vector2(0.0, 0.04)
	control.modulate = Color(1.3, 1.5, 1.5, 1.0)
	var tween := create_tween()
	tween.tween_property(control, "scale:x", 1.0, 0.08)
	tween.tween_property(control, "scale:y", 1.0, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(control, "modulate", Color.WHITE, 0.12)


func _on_editor_cell_clicked(cell: Vector2i) -> void:
	if not editor_mode:
		return
	editor_panel.call("power_on_from", get_viewport().get_mouse_position())
	if editor_tool == "group":
		_toggle_group_cell(cell)
		return
	pending_editor_cell = cell
	pending_editor_offset = settlement_grid.call("get_pending_placement_offset")
	pending_room_type = ""
	var source := get_viewport().get_mouse_position()
	if _room_at_cell(cell) == null:
		editor_tool = "add"
		occupied_section.call("power_off")
		type_section.call("power_off", true)
		add_section.call("power_off", true)
		category_section.call("power_on_from", source)
		editor_status.text = "EMPTY CELL %s SELECTED • CHOOSE A CATEGORY" % cell
	else:
		category_section.call("power_off")
		type_section.call("power_off", true)
		add_section.call("power_off", true)
		occupied_section.call("power_on_from", source)
		editor_status.text = "OCCUPIED CELL %s SELECTED" % cell


func _on_grid_category_selected(category: String) -> void:
	for child: Node in grid_type_buttons.get_children():
		child.queue_free()
	grid_type_category_label.text = "%s GRID TYPES" % category
	var available_types: Array = GRID_TYPE_CATEGORIES.get(category, [])
	var definitions: Array = settlement_grid.get("ship_layout").get("room_types")
	for room_type_value: Variant in available_types:
		var room_type := String(room_type_value)
		var is_available := false
		for definition: Resource in definitions:
			if String(definition.get("type_name")) == room_type:
				is_available = true
				break
		if not is_available:
			continue
		var button := Button.new()
		button.text = _room_type_palette_name(room_type)
		button.custom_minimum_size.y = 30.0
		button.pressed.connect(_on_responsive_grid_type_selected.bind(room_type, button.text))
		grid_type_buttons.add_child(button)
	add_section.call("power_off", true)
	type_section.call("power_on_from", get_viewport().get_mouse_position())


func _on_responsive_grid_type_selected(room_type: String, display_name: String) -> void:
	pending_room_type = room_type
	confirm_add_button.text = "ADD %s" % display_name
	add_section.call("power_on_from", get_viewport().get_mouse_position())
	editor_status.text = "%s SELECTED • CONFIRM TO BUILD" % display_name


func _confirm_add_pending_cell() -> void:
	if pending_editor_cell == INVALID_CELL or pending_room_type.is_empty():
		return
	editor_tool = "add"
	_apply_editor_cell(pending_editor_cell)
	_play_menu_sound("play_execute")
	category_section.call("power_off")
	type_section.call("power_off")
	add_section.call("power_off")


func _delete_pending_cell() -> void:
	if pending_editor_cell == INVALID_CELL:
		return
	editor_tool = "delete"
	_apply_editor_cell(pending_editor_cell)
	_play_menu_sound("play_execute")
	occupied_section.call("power_off")


func _group_pending_cell() -> void:
	if pending_editor_cell == INVALID_CELL:
		return
	var selected_cell := pending_editor_cell
	_set_editor_tool("group")
	_toggle_group_cell(selected_cell)
	occupied_section.call("power_off")


func _finish_grouping() -> void:
	_play_menu_sound("play_execute")
	_clear_group_selection()
	_set_editor_tool("add")
	pending_editor_cell = INVALID_CELL
	pending_editor_offset = Vector2.ZERO
	editor_status.text = "CLICK A CELL TO CONTINUE EDITING"


func _apply_editor_cell(cell: Vector2i) -> void:
	var layout: Resource = settlement_grid.get("ship_layout")
	var was_occupied: bool = _room_at_cell(cell) != null
	var existing_offset: Vector2 = layout.call("get_cell_offset", cell)
	_remove_cell_from_all_rooms(cell)
	if editor_tool == "add" and not pending_room_type.is_empty():
		# The selected preview is a cell-and-offset pair. Never read the live hover
		# offset here: the cursor has moved to the confirmation UI by this point.
		var placement_offset: Vector2 = pending_editor_offset
		if was_occupied:
			placement_offset = existing_offset
		layout.call("set_cell_offset", cell, placement_offset)
		var room_type := pending_room_type
		selected_room_id = _add_cell_to_room_type(room_type, cell)
		editor_status.text = "ASSIGNED CELL %s TO %s" % [cell, _room_type_palette_name(room_type)]
	else:
		settlement_grid.get("ship_layout").call("prune_unused_cell_offsets")
		editor_status.text = "CLEARED CELL %s" % cell
	var new_bounds: Rect2i = layout.call("get_occupied_bounds")
	editor_status.text += "HULL %dx%d INSIDE %dx%d ENVELOPE" % [new_bounds.size.x, new_bounds.size.y, int(layout.get("columns")), int(layout.get("rows"))]
	settlement_grid.call("refresh_layout")
	zoom_controller.call("refresh_content")
	simulation.refresh_rooms_from_layout()
	pending_editor_cell = INVALID_CELL
	pending_editor_offset = Vector2.ZERO
	pending_room_type = ""


func _populate_room_types() -> void:
	editor_room_type.clear()
	editor_room_type.add_item("CHOOSE GRID TYPE...")
	editor_room_type.set_item_disabled(0, true)
	var definitions: Array = settlement_grid.get("ship_layout").get("room_types")
	for definition: Resource in definitions:
		editor_room_type.add_item(_room_type_palette_name(definition.get("type_name")))
		editor_room_type.set_item_metadata(
			editor_room_type.item_count - 1,
			definition.get("type_name")
		)
	editor_room_type.select(0)


func _room_type_palette_name(room_type: String) -> String:
	match room_type:
		"COMMAND":
			return "BRIDGE"
		"PROPULSION":
			return "THRUSTERS"
		"WEAPONS":
			return "SHIP WEAPONS"
		"UNASSIGNED":
			return "UNASSIGNED COMPARTMENT"
		"CREW_QUARTERS":
			return "CREW QUARTERS"
		"SECURITY":
			return "SECURITY"
		"SHIELDS":
			return "SHIELD GENERATOR"
		"POWER":
			return "REACTOR"
		"MEDICAL":
			return "MEDICAL BAY"
		"MESS_HALL":
			return "MESS HALL"
		"WORKSHOP":
			return "ENGINEERING BAY"
		"CARGO":
			return "CARGO HOLD"
		"SUPPLY_STORAGE":
			return "SUPPLY STORAGE"
		"HANGAR":
			return "HANGAR"
	return room_type


func _remove_cell_from_all_rooms(cell: Vector2i) -> void:
	var definitions: Array = settlement_grid.get("ship_layout").get("rooms")
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
	_prune_empty_room_instances()


func _add_cell_to_room_type(room_type: String, cell: Vector2i) -> StringName:
	var layout: Resource = settlement_grid.get("ship_layout")
	var definitions: Array = layout.get("rooms")
	var neighboring_rooms: Array[Resource] = []
	if not EXPLICIT_GROUP_ROOM_TYPES.has(room_type):
		for definition: Resource in definitions:
			if definition.get("type_name") == room_type and _room_touches_cell(definition, cell):
				neighboring_rooms.append(definition)

	var target_room: Resource
	if neighboring_rooms.is_empty():
		target_room = _create_room_instance(room_type)
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
	layout.set("rooms", definitions)
	return target_room.get("room_id")


func _create_room_instance(room_type: String) -> Resource:
	var layout: Resource = settlement_grid.get("ship_layout")
	var templates: Array = layout.get("room_types")
	var template: Resource
	for candidate: Resource in templates:
		if candidate.get("type_name") == room_type:
			template = candidate
			break

	var room_script := preload("res://scripts/resources/room_layout_data.gd")
	var room: Resource = room_script.new()
	room.set("room_id", StringName("%s_%d" % [room_type.to_snake_case(), Time.get_ticks_usec()]))
	room.set("display_name", _new_room_display_name(room_type))
	room.set("type_name", room_type)
	room.set("effect_label", template.get("effect_label"))
	room.set("description", template.get("description"))
	room.set("grid_label", template.get("grid_label"))
	var empty_rects: Array[Rect2i] = []
	room.set("grid_rects", empty_rects)
	room.set("color", template.get("color"))
	room.set("maximum_health", template.get("maximum_health"))
	room.set("produces_output", template.get("produces_output"))
	room.set("contributes_to_hull", template.get("contributes_to_hull"))
	room.set("weapon_definition", template.get("weapon_definition"))
	return room


func _toggle_group_cell(cell: Vector2i) -> void:
	var room := _room_at_cell(cell)
	if room == null:
		editor_status.text = "GROUP: SELECT OCCUPIED MODULE CELLS"
		return
	if not EXPLICIT_GROUP_ROOM_TYPES.has(String(room.get("type_name"))):
		editor_status.text = "GROUPING IS ENABLED FOR WEAPONS, THRUSTERS, AND HANGARS"
		return
	if group_selected_cells.has(cell):
		group_selected_cells.erase(cell)
	else:
		group_selected_cells[cell] = true
	settlement_grid.call("set_group_selection", group_selected_cells)
	_update_recipe_options()
	editor_status.text = "GROUP: %d CELL%s SELECTED" % [
		group_selected_cells.size(),
		"" if group_selected_cells.size() == 1 else "S",
	]


func _clear_group_selection() -> void:
	group_selected_cells.clear()
	if is_instance_valid(settlement_grid):
		settlement_grid.call("set_group_selection", group_selected_cells)
	if editor_mode and editor_tool == "group":
		editor_status.text = "GROUP: SELECT CONNECTED CELLS"
	_update_recipe_options()


func _combine_selected_cells() -> void:
	if group_selected_cells.size() < 2:
		editor_status.text = "COMBINE REQUIRES AT LEAST 2 CELLS"
		return
	if not _selected_cells_are_connected():
		editor_status.text = "COMBINE BLOCKED: CELLS MUST SHARE EDGES"
		return
	var selected_rooms: Array[Resource] = []
	var selected_room_ids: Dictionary = {}
	var room_type := ""
	for cell_value: Variant in group_selected_cells.keys():
		var cell: Vector2i = cell_value
		var room := _room_at_cell(cell)
		if room == null:
			editor_status.text = "COMBINE BLOCKED: EMPTY CELL IN SELECTION"
			return
		if room_type.is_empty():
			room_type = room.get("type_name")
		elif room.get("type_name") != room_type:
			editor_status.text = "COMBINE BLOCKED: ALL CELLS MUST SHARE A MODULE TYPE"
			return
		var instance_key := room.get_instance_id()
		if not selected_room_ids.has(instance_key):
			selected_room_ids[instance_key] = true
			selected_rooms.append(room)
	for room: Resource in selected_rooms:
		for room_cell_value: Variant in _resource_room_cells(room).keys():
			if not group_selected_cells.has(room_cell_value):
				editor_status.text = "COMBINE BLOCKED: SPLIT EXISTING GROUPS BEFORE PARTIAL REGROUPING"
				return

	var target_room := selected_rooms[0]
	var combined_rects: Array[Rect2i] = []
	for cell_value: Variant in group_selected_cells.keys():
		combined_rects.append(Rect2i(cell_value, Vector2i.ONE))
	var shared_weapon: Resource = selected_rooms[0].get("weapon_definition")
	var combined_health := 0.0
	for room: Resource in selected_rooms:
		combined_health += float(room.get("maximum_health"))
		if room.get("weapon_definition") != shared_weapon:
			shared_weapon = null
	target_room.set("grid_rects", combined_rects)
	target_room.set("maximum_health", combined_health)
	target_room.set("weapon_definition", shared_weapon)
	target_room.set("module_recipe", null)
	target_room.set("module_facing_quarters", -1)
	var definitions: Array = settlement_grid.get("ship_layout").get("rooms")
	for index: int in range(1, selected_rooms.size()):
		definitions.erase(selected_rooms[index])
	settlement_grid.get("ship_layout").set("rooms", definitions)
	selected_room_id = target_room.get("room_id")
	var combined_count := group_selected_cells.size()
	_refresh_after_group_edit()
	settlement_grid.call("set_group_selection", group_selected_cells)
	_update_recipe_options()
	editor_status.text = "COMBINED %d CELLS INTO ONE %s FOOTPRINT" % [combined_count, room_type]


func _split_selected_groups() -> void:
	if group_selected_cells.is_empty():
		editor_status.text = "SPLIT: SELECT A CELL FROM A GROUPED FOOTPRINT"
		return
	var rooms_to_split: Array[Resource] = []
	var room_ids: Dictionary = {}
	for cell_value: Variant in group_selected_cells.keys():
		var room := _room_at_cell(cell_value)
		if room == null or _resource_room_cells(room).size() <= 1:
			continue
		if not room_ids.has(room.get_instance_id()):
			room_ids[room.get_instance_id()] = true
			rooms_to_split.append(room)
	if rooms_to_split.is_empty():
		editor_status.text = "SPLIT: NO GROUPED FOOTPRINT SELECTED"
		return
	var definitions: Array = settlement_grid.get("ship_layout").get("rooms")
	var split_cell_count := 0
	for source_room: Resource in rooms_to_split:
		var source_cells := _resource_room_cells(source_room)
		var health_per_cell := float(source_room.get("maximum_health")) / maxf(float(source_cells.size()), 1.0)
		definitions.erase(source_room)
		for cell_value: Variant in source_cells.keys():
			var cell: Vector2i = cell_value
			var new_room := source_room.duplicate(false) as Resource
			new_room.set("room_id", StringName("%s_%d" % [String(source_room.get("type_name")).to_snake_case(), Time.get_ticks_usec() + split_cell_count]))
			var cell_rects: Array[Rect2i] = [Rect2i(cell, Vector2i.ONE)]
			new_room.set("grid_rects", cell_rects)
			new_room.set("maximum_health", health_per_cell)
			new_room.set("module_recipe", null)
			new_room.set("module_facing_quarters", -1)
			definitions.append(new_room)
			selected_room_id = new_room.get("room_id")
			split_cell_count += 1
	settlement_grid.get("ship_layout").set("rooms", definitions)
	_clear_group_selection()
	_refresh_after_group_edit()
	editor_status.text = "SPLIT FOOTPRINT INTO %d INDEPENDENT CELLS" % split_cell_count


func _selected_cells_are_connected() -> bool:
	if group_selected_cells.is_empty():
		return false
	var unvisited := group_selected_cells.duplicate()
	var start_cell: Vector2i = unvisited.keys()[0]
	var pending: Array[Vector2i] = [start_cell]
	unvisited.erase(pending[0])
	while not pending.is_empty():
		var cell: Vector2i = pending.pop_back()
		var layout: Resource = settlement_grid.get("ship_layout")
		for connection: Dictionary in layout.call("get_touching_cells", cell, false):
			var neighbor: Vector2i = connection["cell"]
			if unvisited.has(neighbor):
				unvisited.erase(neighbor)
				pending.append(neighbor)
	return unvisited.is_empty()


func _room_at_cell(cell: Vector2i) -> Resource:
	var definitions: Array = settlement_grid.get("ship_layout").get("rooms")
	for room: Resource in definitions:
		if _resource_room_cells(room).has(cell):
			return room
	return null


func _resource_room_cells(room: Resource) -> Dictionary:
	var cells: Dictionary = {}
	var rects: Array[Rect2i] = room.get("grid_rects")
	for grid_rect: Rect2i in rects:
		for y: int in range(grid_rect.position.y, grid_rect.end.y):
			for x: int in range(grid_rect.position.x, grid_rect.end.x):
				cells[Vector2i(x, y)] = true
	return cells


func _refresh_after_group_edit() -> void:
	settlement_grid.call("refresh_layout")
	zoom_controller.call("refresh_content")
	simulation.refresh_rooms_from_layout()
	_update_recipe_options()


func _update_recipe_options() -> void:
	if not is_instance_valid(recipe_selector):
		return
	recipe_selector.clear()
	var selected_room := _complete_selected_room()
	_update_facing_controls(selected_room)
	if selected_room == null:
		recipe_stats.text = "SELECT EVERY CELL OF ONE COMPLETE MODULE FOOTPRINT"
		%InstallRecipeButton.disabled = true
		return
	var matches := _matching_recipes_for_room(selected_room)
	for match: Dictionary in matches:
		var recipe: Resource = match["recipe"]
		var option_name := "%s  [%s]" % [
			recipe.get("display_name"),
			_rotation_name(match["facing_quarters"]),
		]
		if match["mirrored"]:
			option_name += " [MIRRORED]"
		recipe_selector.add_item(option_name)
		recipe_selector.set_item_metadata(recipe_selector.item_count - 1, match)
	if matches.is_empty():
		recipe_stats.text = "NO RECIPE MATCHES THIS SHAPE, ORIENTATION, AND HULL EXPOSURE"
		%InstallRecipeButton.disabled = true
		return
	%InstallRecipeButton.disabled = false
	recipe_selector.select(0)
	_on_recipe_selected(0)


func _complete_selected_room() -> Resource:
	if group_selected_cells.is_empty():
		return null
	var first_cell: Vector2i = group_selected_cells.keys()[0]
	var room := _room_at_cell(first_cell)
	if room == null:
		return null
	var room_cells := _resource_room_cells(room)
	if room_cells.size() != group_selected_cells.size():
		return null
	for cell_value: Variant in room_cells.keys():
		if not group_selected_cells.has(cell_value):
			return null
	return room


func _matching_recipes_for_room(room: Resource) -> Array[Dictionary]:
	var matches: Array[Dictionary] = []
	var room_cells := _resource_room_cells(room)
	var normalized_room_cells := _normalized_cell_array(room_cells)
	var anchor: Vector2i = _minimum_cell(room_cells)
	var recipes: Array = settlement_grid.get("ship_layout").get("module_recipes")
	for recipe: Resource in recipes:
		if not recipe.call("supports_grid_type", String(room.get("type_name"))):
			continue
		var adjacency_result: Dictionary = settlement_grid.get("ship_layout").call("evaluate_module_recipe", room, recipe)
		if not adjacency_result["valid"]:
			continue
		var footprint: Resource = recipe.get("footprint")
		if footprint == null or int(footprint.call("cell_count")) != room_cells.size():
			continue
		var mirror_options: Array[bool] = [false]
		if footprint.get("allow_mirroring"):
			mirror_options.append(true)
		var rotation_count := 4 if footprint.get("allow_quarter_turn_rotation") else 1
		var seen_orientations: Dictionary = {}
		for mirrored: bool in mirror_options:
			for rotation_quarters: int in range(rotation_count):
				var footprint_cells: Array = footprint.call("transformed_cells", rotation_quarters, mirrored)
				if not _cell_arrays_equal(normalized_room_cells, footprint_cells):
					continue
				var facing_options: Array[int] = [0, 1, 2, 3]
				var chosen_facing := int(room.get("module_facing_quarters"))
				if chosen_facing >= 0:
					facing_options = [chosen_facing]
				for facing_quarters: int in facing_options:
					if not _footprint_exposure_matches(footprint, room_cells, anchor, rotation_quarters, mirrored, facing_quarters):
						continue
					var orientation_key := "%s:%d:%s" % [str(footprint_cells), facing_quarters, mirrored]
					var required_edges: Array = footprint.get("required_edges")
					if not required_edges.is_empty():
						orientation_key += ":%d" % rotation_quarters
					if seen_orientations.has(orientation_key):
						continue
					seen_orientations[orientation_key] = true
					matches.append({
						"recipe": recipe,
						"rotation_quarters": rotation_quarters,
						"facing_quarters": facing_quarters,
						"mirrored": mirrored,
					})
	return matches


func _footprint_exposure_matches(
	footprint: Resource,
	room_cells: Dictionary,
	anchor: Vector2i,
	rotation_quarters: int,
	mirrored: bool,
	facing_quarters: int
) -> bool:
	var hull_cells: Dictionary = {}
	var layout: Resource = settlement_grid.get("ship_layout")
	var definitions: Array = layout.get("rooms")
	for definition: Resource in definitions:
		hull_cells.merge(_resource_room_cells(definition), true)
	var open_edge_count := 0
	for cell_value: Variant in room_cells.keys():
		var cell: Vector2i = cell_value
		for direction: Vector2i in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
			if GRID_GEOMETRY.face_contact_strength(layout, cell, direction, hull_cells) < 0.999:
				open_edge_count += 1
	if open_edge_count < int(footprint.get("minimum_open_edges")):
		return false
	if footprint.get("require_forward_exposure"):
		var forward_direction := _rotation_direction(facing_quarters)
		var forward_exposed_cells := 0
		for cell_value: Variant in room_cells.keys():
			var cell: Vector2i = cell_value
			if GRID_GEOMETRY.face_contact_strength(layout, cell, forward_direction, hull_cells) < 0.999:
				forward_exposed_cells += 1
		if forward_exposed_cells < int(footprint.get("minimum_forward_exposed_cells")):
			return false
	var requirements: Array = footprint.call("transformed_edge_requirements", facing_quarters, mirrored)
	for requirement: Dictionary in requirements:
		var cell: Vector2i = anchor + (requirement["cell"] as Vector2i)
		var direction: Vector2i = requirement["direction"]
		var faces_open_space := GRID_GEOMETRY.face_contact_strength(layout, cell, direction, hull_cells) < 0.999
		if bool(requirement["must_face_open_space"]) != faces_open_space:
			return false
	return true


func _rotation_direction(rotation_quarters: int) -> Vector2i:
	match posmod(rotation_quarters, 4):
		1:
			return Vector2i.RIGHT
		2:
			return Vector2i.DOWN
		3:
			return Vector2i.LEFT
		_:
			return Vector2i.UP


func _rotation_name(rotation_quarters: int) -> String:
	match posmod(rotation_quarters, 4):
		1:
			return "STARBOARD"
		2:
			return "REAR"
		3:
			return "PORT"
		_:
			return "FORWARD"


func _normalized_cell_array(cells: Dictionary) -> Array[Vector2i]:
	var minimum := _minimum_cell(cells)
	var normalized: Array[Vector2i] = []
	for cell_value: Variant in cells.keys():
		normalized.append((cell_value as Vector2i) - minimum)
	normalized.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y < b.y or (a.y == b.y and a.x < b.x))
	return normalized


func _minimum_cell(cells: Dictionary) -> Vector2i:
	var minimum: Vector2i = cells.keys()[0]
	for cell_value: Variant in cells.keys():
		var cell: Vector2i = cell_value
		minimum.x = mini(minimum.x, cell.x)
		minimum.y = mini(minimum.y, cell.y)
	return minimum


func _cell_arrays_equal(first: Array, second: Array) -> bool:
	if first.size() != second.size():
		return false
	for index: int in range(first.size()):
		if first[index] != second[index]:
			return false
	return true


func _update_facing_controls(room: Resource) -> void:
	var has_complete_room := room != null
	var current_facing := int(room.get("module_facing_quarters")) if has_complete_room else -1
	for facing_value: Variant in facing_buttons.keys():
		var facing: int = facing_value
		var button := facing_buttons[facing] as Button
		button.disabled = not has_complete_room or (String(room.get("type_name")) == "HANGAR" and not _room_facing_is_exposed(room, facing))
		button.button_pressed = facing == current_facing


func _set_selected_group_facing(facing_quarters: int) -> void:
	var room := _complete_selected_room()
	if room == null:
		editor_status.text = "FACING: SELECT EVERY CELL OF ONE COMPLETE FOOTPRINT"
		return
	if String(room.get("type_name")) == "HANGAR" and not _room_facing_is_exposed(room, facing_quarters):
		editor_status.text = "HANGAR FACING BLOCKED: LAUNCH EDGE MUST OPEN DIRECTLY INTO SPACE"
		return
	_apply_room_facing(room, facing_quarters)


func _set_selected_hangar_facing(facing_quarters: int) -> void:
	if not editor_mode:
		_update_selected_room_panel()
		return
	var room := _get_layout_room(selected_room_id)
	if room == null or String(room.get("type_name")) != "HANGAR":
		return
	_apply_room_facing(room, facing_quarters)


func _apply_room_facing(room: Resource, facing_quarters: int) -> void:
	if String(room.get("type_name")) == "HANGAR" and not _room_facing_is_exposed(room, facing_quarters):
		editor_status.text = "HANGAR FACING BLOCKED: LAUNCH EDGE MUST OPEN DIRECTLY INTO SPACE"
		return
	var installed_recipe: Resource = room.get("module_recipe")
	room.set("module_facing_quarters", posmod(facing_quarters, 4))
	if installed_recipe != null:
		var recipe_still_valid := false
		for match: Dictionary in _matching_recipes_for_room(room):
			if match["recipe"] == installed_recipe:
				room.set("module_rotation_quarters", match["rotation_quarters"])
				room.set("module_mirrored", match["mirrored"])
				recipe_still_valid = true
				break
		if not recipe_still_valid:
			room.set("module_recipe", null)
			room.set("weapon_definition", null)
			room.set("display_name", "%s FOOTPRINT" % _module_type_display_name(room.get("type_name")))
			editor_status.text = "FACING CHANGED TO %s • PREVIOUS RECIPE NO LONGER FITS" % _rotation_name(facing_quarters)
		else:
			editor_status.text = "FACING CHANGED TO %s" % _rotation_name(facing_quarters)
	else:
		editor_status.text = "FACING CHANGED TO %s" % _rotation_name(facing_quarters)
	settlement_grid.queue_redraw()
	simulation.refresh_rooms_from_layout()
	_update_recipe_options()
	_update_selected_hangar_facing_controls(room)


func _update_selected_hangar_facing_controls(room: Resource) -> void:
	var current_facing := int(room.get("module_facing_quarters"))
	var controls_visible := editor_mode
	hangar_facing_hint.visible = controls_visible
	hangar_facing_buttons.visible = controls_visible
	hangar_facing_readout.visible = not controls_visible
	if not controls_visible:
		var facing_label := _rotation_name(current_facing) if current_facing >= 0 else "UNSET"
		hangar_facing_readout_label.text = "LAUNCH VECTOR • %s\nREFIT IN SHIP EDITOR TO CHANGE" % facing_label
	for facing_value: Variant in selected_hangar_facing_buttons.keys():
		var facing: int = facing_value
		var button := selected_hangar_facing_buttons[facing] as Button
		button.disabled = not _room_facing_is_exposed(room, facing)
		button.button_pressed = facing == current_facing


func _room_facing_is_exposed(room: Resource, facing_quarters: int) -> bool:
	var layout: Resource = settlement_grid.get("ship_layout")
	var hull_cells: Dictionary = {}
	for definition: Resource in layout.get("rooms"):
		hull_cells.merge(_resource_room_cells(definition), true)
	var room_cells := _resource_room_cells(room)
	var wanted_normal := Vector2(_rotation_direction(facing_quarters))
	var bounds: Rect2i = layout.call("get_occupied_bounds")
	for segment: Dictionary in GRID_GEOMETRY.boundary_segments(layout, hull_cells, bounds, 1.0):
		if not room_cells.has(segment["cell"]) or not Vector2(segment["normal"]).is_equal_approx(wanted_normal):
			continue
		var mouth := (segment["start"] as Vector2).lerp(segment["end"], 0.5)
		var corridor_center := mouth + wanted_normal * hangar_launch_clearance_cells * 0.5
		var corridor_size := Vector2(hangar_launch_corridor_width, hangar_launch_clearance_cells)
		if absf(wanted_normal.x) > 0.0:
			corridor_size = Vector2(hangar_launch_clearance_cells, hangar_launch_corridor_width)
		var corridor := Rect2(corridor_center - corridor_size * 0.5, corridor_size).grow(-0.01)
		var is_clear := true
		for hull_cell_value: Variant in hull_cells.keys():
			var hull_cell: Vector2i = hull_cell_value
			if room_cells.has(hull_cell):
				continue
			var hull_rect := GRID_GEOMETRY.cell_rect(layout, hull_cell, bounds, 1.0)
			var overlap := corridor.intersection(hull_rect)
			if overlap.size.x > 0.001 and overlap.size.y > 0.001:
				is_clear = false
				break
		if is_clear:
			return true
	return false


func _on_recipe_selected(index: int) -> void:
	if index < 0 or index >= recipe_selector.item_count:
		return
	var match: Dictionary = recipe_selector.get_item_metadata(index)
	var recipe: Resource = match["recipe"]
	var required_fields := int(recipe.get("required_reactor_fields"))
	if required_fields <= 0 and float(recipe.get("power_draw")) > 0.0:
		required_fields = maxi(ceili(float(recipe.get("power_draw"))), 1)
	recipe_stats.text = "%s\nPOWER LINKS %s • CREW %d/%d • HEALTH %d\nFACING %s • SHAPE ROTATION %d DEG%s" % [
		recipe.get("description"),
		POWER_REQUIREMENT_DISPLAY.plain_text(required_fields, 0.0),
		int(recipe.get("minimum_crew")),
		int(recipe.get("optimal_crew")),
		roundi(recipe.get("maximum_health")),
		_rotation_name(match["facing_quarters"]),
		int(match["rotation_quarters"]) * 90,
		"MIRRORED" if match["mirrored"] else "",
	]
	var costs: PackedStringArray = recipe.call("formatted_construction_costs")
	if not costs.is_empty():
		recipe_stats.text += "\nCOST: %s" % "".join(costs)
	var payload: Resource = recipe.get("payload_resource")
	if int(recipe.get("family")) == 8 and payload != null:
		recipe_stats.text += "\nCRAFT CAPACITY %d • LAUNCH LANES %d • REPAIR %.1f/s\nROLES: %s" % [
			int(payload.get("craft_capacity")),
			int(payload.get("simultaneous_launches")),
			float(payload.get("repair_per_second")),
			", ".join(payload.get("allowed_craft_roles")),
		]


func _install_selected_recipe() -> void:
	var room := _complete_selected_room()
	if room == null or recipe_selector.selected < 0:
		editor_status.text = "INSTALL BLOCKED: SELECT A COMPLETE MATCHING FOOTPRINT"
		return
	var match: Dictionary = recipe_selector.get_item_metadata(recipe_selector.selected)
	var recipe: Resource = match["recipe"]
	room.set("module_recipe", recipe)
	room.set("module_rotation_quarters", match["rotation_quarters"])
	room.set("module_facing_quarters", match["facing_quarters"])
	room.set("module_mirrored", match["mirrored"])
	room.set("display_name", recipe.get("display_name"))
	room.set("maximum_health", recipe.get("maximum_health"))
	var payload: Resource = recipe.get("payload_resource")
	if payload != null and String(room.get("type_name")) == "WEAPONS":
		var installed_payload := payload.duplicate(true)
		for modifier: Resource in recipe.get("stat_modifiers"):
			var stat_id := String(modifier.get("stat_id"))
			if not stat_id.begins_with("weapon_"):
				continue
			var property_name := stat_id.trim_prefix("weapon_")
			var current_value: Variant = installed_payload.get(property_name)
			if current_value is float or current_value is int:
				installed_payload.set(
					property_name,
					modifier.call("apply_to", float(current_value), _resource_room_cells(room).size())
				)
		room.set("weapon_definition", installed_payload)
	_refresh_after_group_edit()
	editor_status.text = "INSTALLED %s" % recipe.get("display_name")
	_play_menu_sound("play_execute")


func _play_menu_sound(method_name: StringName) -> void:
	var menu_audio := get_tree().get_first_node_in_group("menu_audio")
	if is_instance_valid(menu_audio):
		menu_audio.call(method_name)


func _build_needed_systems_staffing_button() -> void:
	if auto_assign_needed_systems_button != null:
		return
	auto_assign_needed_systems_button = Button.new()
	auto_assign_needed_systems_button.name = "AutoAssignNeededSystemsButton"
	auto_assign_needed_systems_button.text = ">> MAN ALL CRITICAL SYSTEMS"
	auto_assign_needed_systems_button.tooltip_text = "CLICK • FILL CRITICAL STATIONS"
	auto_assign_needed_systems_button.focus_mode = Control.FOCUS_NONE
	auto_assign_needed_systems_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	auto_assign_needed_systems_button.pressed.connect(_auto_assign_needed_systems)
	auto_assign_needed_systems_button.add_theme_font_size_override("font_size", 13)
	_apply_command_button_style(auto_assign_needed_systems_button, Color(1.0, 0.36, 0.16, 1.0), true)
	var parent := auto_assign_crew_button.get_parent()
	parent.add_child(auto_assign_needed_systems_button)


func _populate_weapon_types() -> void:
	weapon_type_selector.clear()
	var weapon_definitions: Array = settlement_grid.get("ship_layout").get("weapon_types")
	for weapon: Resource in weapon_definitions:
		var required_cells: int = weapon.get("required_mount_cells")
		var item_name: String = weapon.get("display_name")
		if required_cells > 1:
			item_name += "  [%d CELLS]" % required_cells
		weapon_type_selector.add_item(item_name)
		weapon_type_selector.set_item_metadata(weapon_type_selector.item_count - 1, weapon)


func _on_weapon_type_selected(index: int) -> void:
	if not editor_mode:
		_update_selected_room_panel()
		return
	var room_definition := _get_layout_room(selected_room_id)
	if room_definition == null or room_definition.get("type_name") != "WEAPONS":
		return
	if room_definition.get("module_recipe") != null:
		weapon_stats.text = "THIS FOOTPRINT IS CONTROLLED BY THE %s RECIPE\nUSE SHIP EDITOR > GROUP TO CHANGE IT" % room_definition.get("module_recipe").get("display_name")
		_update_selected_room_panel()
		return
	var weapon: Resource = weapon_type_selector.get_item_metadata(index)
	var available_cells := _room_cell_count(room_definition)
	var required_cells: int = weapon.get("required_mount_cells")
	if available_cells < required_cells:
		weapon_stats.text = "INSTALLATION BLOCKED\n%s REQUIRES %d CONNECTED WEAPON CELLS • ROOM HAS %d" % [
			weapon.get("display_name"),
			required_cells,
			available_cells,
		]
		var installed_weapon: Resource = room_definition.get("weapon_definition")
		for installed_index: int in range(weapon_type_selector.item_count):
			if weapon_type_selector.get_item_metadata(installed_index) == installed_weapon:
				weapon_type_selector.select(installed_index)
				break
		return
	room_definition.set("weapon_definition", weapon)
	simulation.refresh_rooms_from_layout()
	_update_selected_room_panel()


func _set_selected_weapon_fire_mode(fire_mode: int) -> void:
	var room := _get_layout_room(selected_room_id)
	if room == null or String(room.get("type_name")) != "WEAPONS":
		return
	var mount_index := _selected_weapon_mount_index(room)
	if room.has_method("set_weapon_fire_mode"):
		room.call("set_weapon_fire_mode", mount_index, fire_mode)
	else:
		var modes: Array[int] = []
		for mode_value: Variant in room.get("weapon_fire_modes"):
			modes.append(clampi(int(mode_value), FIRE_MODE_LINKED, FIRE_MODE_SENTRY))
		while modes.size() < maxi(int(room.get("installed_piece_count")), 1):
			modes.append(FIRE_MODE_LINKED)
		modes[mount_index] = clampi(fire_mode, FIRE_MODE_LINKED, FIRE_MODE_SENTRY)
		room.set("weapon_fire_modes", modes)
	var layout: Resource = settlement_grid.get("ship_layout")
	if layout != null:
		layout.emit_changed()
	_play_menu_sound("play_execute")
	_update_selected_room_panel()


func _selected_weapon_mount_index(room: Resource) -> int:
	var selected_cell := INVALID_CELL
	if settlement_grid.has_method("get_selected_room_cell"):
		selected_cell = settlement_grid.call("get_selected_room_cell")
	var rects: Array[Rect2i] = room.get("grid_rects")
	for index: int in range(rects.size()):
		if rects[index].has_point(selected_cell):
			return index
	return 0


func _weapon_fire_mode(room: Resource, mount_index: int) -> int:
	if room.has_method("get_weapon_fire_mode"):
		return int(room.call("get_weapon_fire_mode", mount_index))
	var modes: Array = room.get("weapon_fire_modes")
	if mount_index >= 0 and mount_index < modes.size():
		return clampi(int(modes[mount_index]), FIRE_MODE_LINKED, FIRE_MODE_SENTRY)
	return FIRE_MODE_LINKED


func _room_cell_count(room_definition: Resource) -> int:
	var cells: Dictionary = {}
	var rects: Array[Rect2i] = room_definition.get("grid_rects")
	for grid_rect: Rect2i in rects:
		for y: int in range(grid_rect.position.y, grid_rect.end.y):
			for x: int in range(grid_rect.position.x, grid_rect.end.x):
				cells[Vector2i(x, y)] = true
	var unvisited := cells.duplicate()
	var largest_connected_group := 0
	while not unvisited.is_empty():
		var start_cell: Vector2i = unvisited.keys()[0]
		var pending: Array[Vector2i] = [start_cell]
		unvisited.erase(start_cell)
		var connected_count := 0
		while not pending.is_empty():
			var cell: Vector2i = pending.pop_back()
			connected_count += 1
			for direction: Vector2i in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
				var neighbor: Vector2i = cell + direction
				if unvisited.has(neighbor):
					unvisited.erase(neighbor)
					pending.append(neighbor)
		largest_connected_group = maxi(largest_connected_group, connected_count)
	return largest_connected_group


func _get_layout_room(room_id: StringName) -> Resource:
	var definitions: Array = settlement_grid.get("ship_layout").get("rooms")
	for definition: Resource in definitions:
		if definition.get("room_id") == room_id:
			return definition
	return null


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
		"CREW_QUARTERS":
			return "CREW QUARTERS"
		"SECURITY":
			return "SECURITY"
		"SHIELDS":
			return "SHIELD GENERATOR"
		"POWER":
			return "REACTOR"
		"MEDICAL":
			return "MEDICAL BAY"
		"MESS_HALL":
			return "MESS HALL"
		"WORKSHOP":
			return "ENGINEERING BAY"
		"CARGO":
			return "CARGO HOLD"
		"SUPPLY_STORAGE":
			return "SUPPLY STORAGE"
		"HANGAR":
			return "HANGAR"
	return "%s ROOM" % room_type


func _module_type_display_name(room_type: String) -> String:
	match room_type:
		"PROPULSION":
			return "THRUSTER"
		"WEAPONS":
			return "WEAPON"
	return room_type


func _room_touches_cell(room: Resource, cell: Vector2i) -> bool:
	var layout: Resource = settlement_grid.get("ship_layout")
	var neighbors: Array[Dictionary] = layout.call("get_touching_cells", cell, false)
	var rects: Array[Rect2i] = room.get("grid_rects")
	for rect: Rect2i in rects:
		for connection: Dictionary in neighbors:
			if rect.has_point(connection["cell"]):
				return true
	return false


func _prune_empty_room_instances() -> void:
	var layout: Resource = settlement_grid.get("ship_layout")
	var definitions: Array = layout.get("rooms")
	for index: int in range(definitions.size() - 1, -1, -1):
		if (definitions[index] as Resource).get("grid_rects").is_empty():
			definitions.remove_at(index)
	layout.set("rooms", definitions)


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


func _save_layout() -> void:
	var layout: Resource = settlement_grid.get("ship_layout")
	var save_error := ResourceSaver.save(layout, layout.resource_path)
	if save_error == OK:
		editor_status.text = "LAYOUT SAVED"
	else:
		editor_status.text = "SAVE FAILED: ERROR %d" % save_error


func _update_room_staffing_controls(crew: Node, requirements: Vector2i, assigned_count: int) -> void:
	staffing_configuration.visible = requirements.y > 0
	if not staffing_configuration.visible:
		return
	var present_count: int = crew.call("get_room_present_count", selected_room_id)
	var operating_count: int = crew.call("get_room_staffing", selected_room_id)
	var layout: Resource = settlement_grid.get("ship_layout")
	var ship_stats := SHIP_RESOURCE_ANALYZER.analyze(layout)
	var future_capacity_sufficient := int(ship_stats.get("crew_capacity", 0)) >= int(ship_stats.get("optimal_crew", 0))
	room_staffing_meter.call(
		"set_staffing_state",
		requirements.x,
		requirements.y,
		assigned_count,
		present_count,
		operating_count,
		false,
		future_capacity_sufficient
	)
	var priority_label := String(crew.call("get_room_staffing_priority_label", selected_room_id))
	auto_assign_crew_button.visible = true
	auto_assign_crew_button.disabled = false
	var priority_color := Color(0.24, 0.92, 0.82, 1.0)
	match priority_label:
		"PRIORITY":
			priority_color = Color(1.0, 0.66, 0.18, 1.0)
			auto_assign_crew_button.text = "CREW NET • PRIORITY HOLD  >"
			auto_assign_crew_button.tooltip_text = "CREW HELD HERE FIRST\nCLICK • STAND DOWN"
		"STANDBY":
			priority_color = Color(0.9, 0.32, 0.2, 1.0)
			auto_assign_crew_button.text = "CREW NET • STAND DOWN  >"
			auto_assign_crew_button.tooltip_text = "NO AUTOMATIC CREW\nCLICK • AUTO-ROUTE"
		_:
			auto_assign_crew_button.text = "CREW NET • AUTO-ROUTE  >"
			auto_assign_crew_button.tooltip_text = "CREW BALANCED AUTOMATICALLY\nCLICK • PRIORITY HOLD"
	_apply_command_button_style(auto_assign_crew_button, priority_color, true)


func _cycle_selected_room_staffing_priority() -> void:
	var crew := get_tree().get_first_node_in_group("crew_simulation")
	if not is_instance_valid(crew) or selected_room_id == &"":
		return
	crew.call("cycle_room_staffing_priority", selected_room_id)
	_play_menu_sound("play_execute")
	_update_selected_room_panel()


func _open_manual_dispatch_panel() -> void:
	if selected_room_id == &"" or open_dispatch_button.disabled:
		return
	manual_dispatch_panel.call("power_on_from", open_dispatch_button.get_global_rect().get_center())


func _on_staffing_crew_selected(_index: int) -> void:
	_update_manual_assign_button_state()


func _update_manual_assign_button_state() -> void:
	var index := staffing_crew_selector.selected
	assign_crew_button.disabled = index <= 0 or index >= staffing_crew_ids.size() or staffing_crew_ids[index] <= 0


func _create_assigned_crew_row(crew: Node, member: Dictionary) -> Control:
	var row := PanelContainer.new()
	row.custom_minimum_size = Vector2(0, 52)
	var row_style := StyleBoxFlat.new()
	row_style.bg_color = Color(0.035, 0.05, 0.052, 0.88)
	row_style.border_width_left = 2
	row_style.border_width_bottom = 1
	row_style.border_color = Color(0.18, 0.52, 0.48, 0.72)
	row_style.content_margin_left = 5.0
	row_style.content_margin_top = 5.0
	row_style.content_margin_right = 6.0
	row_style.content_margin_bottom = 5.0
	row.add_theme_stylebox_override("panel", row_style)

	var content := HBoxContainer.new()
	content.add_theme_constant_override("separation", 7)
	row.add_child(content)

	var health_percentage := 100.0 * float(member.get("health", 0.0)) / maxf(float(member.get("maximum_health", 1.0)), 0.001)
	var portrait_scene: PackedScene = member.get("portrait_scene")
	if portrait_scene != null:
		var portrait := portrait_scene.instantiate() as Control
		portrait.custom_minimum_size = Vector2(38, 38)
		portrait.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var portrait_color: Color = crew.crew_definition.get("base_color")
		portrait.call("configure", int(member["id"]), portrait_color.lightened(float(member.get("color_shift", 0.0))), health_percentage, float(member.get("morale", 0.0)))
		portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content.add_child(portrait)

	var text_stack := VBoxContainer.new()
	text_stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_stack.add_theme_constant_override("separation", 1)
	content.add_child(text_stack)

	var station_state := _crew_station_state_label(member)
	var name_label := Label.new()
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.add_theme_color_override("font_color", Color(0.78, 0.96, 0.9, 1.0))
	name_label.add_theme_font_size_override("font_size", 12)
	name_label.clip_text = true
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.text = "%s • %s" % [String(member["name"]), station_state]
	text_stack.add_child(name_label)

	var vitals_label := Label.new()
	vitals_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vitals_label.add_theme_color_override("font_color", Color(0.48, 0.72, 0.68, 1.0))
	vitals_label.add_theme_font_size_override("font_size", 9)
	vitals_label.clip_text = true
	vitals_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	vitals_label.text = "HP %03d%% • MORALE %03d%%" % [roundi(health_percentage), roundi(float(member.get("morale", 0.0)))]
	text_stack.add_child(vitals_label)

	var click_target := Button.new()
	click_target.flat = true
	click_target.text = ""
	click_target.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	click_target.tooltip_text = "CLICK • OPEN CREW ACTIONS"
	click_target.mouse_entered.connect(_set_assigned_crew_row_hovered.bind(row, row_style, true))
	click_target.mouse_exited.connect(_set_assigned_crew_row_hovered.bind(row, row_style, false))
	click_target.pressed.connect(_open_assigned_crew_actions.bind(int(member["id"]), click_target))
	row.add_child(click_target)
	return row


func _crew_station_state_label(member: Dictionary) -> String:
	if int(member.get("active_job_id", 0)) > 0:
		return "DAMAGE CONTROL"
	if bool(member.get("evacuating", false)):
		return "EVACUATING"
	if bool(member.get("at_assignment", false)):
		return "AT STATION"
	return String(member.get("state", "REPORTING"))


func _set_assigned_crew_row_hovered(row: PanelContainer, row_style: StyleBoxFlat, is_hovered: bool) -> void:
	if not is_instance_valid(row):
		return
	row_style.bg_color = Color(0.045, 0.09, 0.088, 0.96) if is_hovered else Color(0.035, 0.05, 0.052, 0.88)
	row_style.border_color = Color(0.42, 1.0, 0.86, 0.95) if is_hovered else Color(0.18, 0.52, 0.48, 0.72)
	row.add_theme_stylebox_override("panel", row_style)


func _auto_assign_selected_room() -> void:
	var crew := get_tree().get_first_node_in_group("crew_simulation")
	if not is_instance_valid(crew) or selected_room_id == &"":
		return
	var assigned: int = crew.call("auto_assign_room", selected_room_id)
	staffing_roster_signature = ""
	staffing_display_signature = "__FORCE__"
	if assigned <= 0:
		no_assigned_crew_label.visible = true
		no_assigned_crew_label.text = "NO UNASSIGNED CREW AVAILABLE"
		_play_menu_sound("play_cancel")
	else:
		_play_menu_sound("play_execute")
	_update_selected_room_panel()


func _apply_command_button_style(button: Button, accent: Color, primary: bool = false) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(accent, 0.1 if not primary else 0.16)
	normal.border_width_left = 3 if primary else 1
	normal.border_width_top = 1
	normal.border_width_right = 1
	normal.border_width_bottom = 1
	normal.border_color = Color(accent, 0.72)
	normal.corner_radius_top_right = 3
	normal.corner_radius_bottom_left = 3
	normal.content_margin_top = 8.0 if primary else 6.0
	normal.content_margin_bottom = 8.0 if primary else 6.0
	normal.content_margin_left = 8.0
	normal.content_margin_right = 8.0
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(accent, 0.3)
	hover.border_color = accent.lightened(0.25)
	hover.expand_margin_left = 2.0
	hover.expand_margin_right = 2.0
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(accent, 0.5)
	pressed.border_color = Color.WHITE
	var disabled := normal.duplicate() as StyleBoxFlat
	disabled.bg_color = Color(0.04, 0.055, 0.052, 0.78)
	disabled.border_color = Color(0.22, 0.28, 0.27, 0.6)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("disabled", disabled)
	button.add_theme_color_override("font_color", accent.lightened(0.2))
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_color_override("font_pressed_color", Color(0.02, 0.04, 0.035, 1.0))
	button.add_theme_color_override("font_disabled_color", Color(0.32, 0.4, 0.38, 0.75))
	button.add_theme_font_size_override("font_size", 14 if primary else 12)
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND


func _auto_assign_needed_systems() -> void:
	var crew := get_tree().get_first_node_in_group("crew_simulation")
	if not is_instance_valid(crew):
		return
	var assigned: int = crew.call("auto_assign_priority_rooms")
	staffing_roster_signature = ""
	staffing_display_signature = "__FORCE__"
	if assigned > 0:
		_play_menu_sound("play_execute")
	else:
		_play_menu_sound("play_cancel")
		no_assigned_crew_label.visible = true
		no_assigned_crew_label.text = "NO OPEN PRIORITY STATIONS OR UNASSIGNED CREW"
	_update_selected_room_panel()


func _manually_assign_selected_room() -> void:
	var crew := get_tree().get_first_node_in_group("crew_simulation")
	var index := staffing_crew_selector.selected
	if not is_instance_valid(crew) or selected_room_id == &"" or index <= 0 or index >= staffing_crew_ids.size():
		return
	var succeeded: bool = crew.call("assign_crew_to_room", staffing_crew_ids[index], selected_room_id)
	staffing_roster_signature = ""
	staffing_display_signature = "__FORCE__"
	if not succeeded:
		no_assigned_crew_label.visible = true
		no_assigned_crew_label.text = "ASSIGNMENT FAILED • NO OPEN SLOT OR ROUTE"
	else:
		manual_dispatch_panel.call("power_off")


func _open_assigned_crew_actions(crew_id: int, source_button: Button) -> void:
	var crew := get_tree().get_first_node_in_group("crew_simulation")
	if not is_instance_valid(crew):
		return
	var member: Dictionary = crew.call("get_member", crew_id)
	if member.is_empty():
		return
	action_crew_id = crew_id
	crew_action_name.text = String(member["name"])
	var health_percentage := 100.0 * float(member["health"]) / maxf(float(member["maximum_health"]), 0.001)
	crew_action_status.text = "STATUS • %s\nHEALTH • %d%%" % [
		"AT STATION" if bool(member["at_assignment"]) else String(member["state"]),
		roundi(health_percentage),
	]
	_set_crew_action_morale(float(member["morale"]))
	crew_action_panel.call("power_on_from", source_button.get_global_rect().get_center())


func _set_crew_action_morale(morale: float) -> void:
	var normalized := clampf(morale / 100.0, 0.0, 1.0)
	var low := Color(0.88, 0.16, 0.12, 1.0)
	var middle := Color(0.95, 0.68, 0.16, 1.0)
	var high := Color(0.25, 0.82, 0.4, 1.0)
	var fill := StyleBoxFlat.new()
	fill.bg_color = low.lerp(middle, normalized * 2.0) if normalized < 0.5 else middle.lerp(high, (normalized - 0.5) * 2.0)
	var background := StyleBoxFlat.new()
	background.bg_color = Color(0.025, 0.035, 0.04, 0.95)
	background.border_width_left = 1
	background.border_width_top = 1
	background.border_width_right = 1
	background.border_width_bottom = 1
	background.border_color = Color(0.24, 0.28, 0.3, 1.0)
	crew_action_morale_bar.add_theme_stylebox_override("background", background)
	crew_action_morale_bar.add_theme_stylebox_override("fill", fill)
	crew_action_morale_bar.value = morale


func _unassign_action_crew() -> void:
	var crew := get_tree().get_first_node_in_group("crew_simulation")
	if not is_instance_valid(crew) or action_crew_id <= 0:
		return
	crew.call("unassign_crew", action_crew_id)
	staffing_roster_signature = ""
	staffing_display_signature = "__FORCE__"
	crew_action_panel.call("power_off")


func _select_action_crew_in_picker() -> void:
	for index: int in range(staffing_crew_ids.size()):
		if staffing_crew_ids[index] == action_crew_id:
			staffing_crew_selector.select(index)
			break
	crew_action_panel.call("power_off")


func _update_damage_control_readout(crew: Node, room: Dictionary) -> void:
	var jobs: Array[Dictionary] = crew.call("get_jobs_for_room", selected_room_id)
	var structure := _player_structural_state()
	var damaged_walls := 0
	if structure != null:
		for wall_value: Variant in structure.walls.values():
			var wall: Dictionary = wall_value
			if float(wall["current"]) >= float(wall["maximum"]):
				continue
			for cell_value: Variant in wall["cells"]:
				if StringName(structure.cell_rooms.get(cell_value, &"")) == selected_room_id:
					damaged_walls += 1
					break
	var room_damaged := float(room["current_health"]) < float(room["maximum_health"]) - 0.001
	var atmosphere_issue := false
	if structure != null:
		atmosphere_issue = structure.get_room_pressure(selected_room_id) < 0.65 or structure.get_room_outer_breach_length(selected_room_id) > 0.0
	var room_job_active := false
	var wall_job_active := false
	if jobs.is_empty():
		damage_control_status.text = "COMPARTMENT NOMINAL" if not room_damaged and damaged_walls == 0 else "DAMAGE DETECTED • AWAITING ORDERS"
	else:
		var lines: PackedStringArray = []
		for job: Dictionary in jobs:
			var job_type := String(job["type"])
			room_job_active = room_job_active or job_type == "ROOM"
			wall_job_active = wall_job_active or job_type == "WALL"
			var assigned_names: PackedStringArray = []
			for crew_id: Variant in job["assigned_crew"]:
				var member: Dictionary = crew.call("get_member", int(crew_id))
				if not member.is_empty():
					assigned_names.append(String(member["name"]))
			var crew_text := ", ".join(assigned_names) if not assigned_names.is_empty() else "NO CREW"
			lines.append("%s • %s • %d%% • %s" % [job_type, String(job["state"]), roundi(float(job["progress"]) * 100.0), crew_text])
		damage_control_status.text = "\n".join(lines)
	order_room_repair_button.disabled = not room_damaged or room_job_active
	order_breach_repair_button.disabled = damaged_walls == 0 or wall_job_active
	var has_issue := room_damaged or damaged_walls > 0 or atmosphere_issue or not jobs.is_empty()
	damage_control_status_button.visible = has_issue
	if has_issue:
		var alert_count := int(room_damaged) + damaged_walls + int(atmosphere_issue)
		damage_control_status_button.text = "⚠ STATUS • %d ALERT%s" % [alert_count, "" if alert_count == 1 else "S"]
	else:
		damage_control_status_button.text = "STATUS • NOMINAL"
		if damage_control_panel.visible:
			damage_control_panel.call("power_off")


func _update_system_detail_panel() -> void:
	if not is_instance_valid(simulation):
		return
	var room: Dictionary = simulation.get_room_data(selected_room_id)
	if room.is_empty():
		system_detail_button.visible = false
		if system_detail_panel.visible:
			system_detail_panel.call("power_off")
		return
	var room_type: String = simulation.get_room_type_name(selected_room_id)
	system_detail_button.visible = false
	system_detail_button.disabled = true
	if not system_detail_panel.visible:
		return

	var crew := get_tree().get_first_node_in_group("crew_simulation")
	var structure := _player_structural_state()
	var output_efficiency: float = simulation.get_room_efficiency(selected_room_id)
	var operation_status: Dictionary = {}
	if is_instance_valid(crew):
		operation_status = crew.call("get_room_operational_status", selected_room_id)
	var pressure := 1.0
	var breach_length := 0.0
	if structure != null:
		pressure = structure.get_room_pressure(selected_room_id)
		breach_length = structure.get_room_outer_breach_length(selected_room_id)

	var status_lines := _system_status_lines(room, operation_status, output_efficiency, pressure, breach_length)
	system_detail_room_name.text = String(room["name"])
	system_detail_status.text = "STATUS • %s" % status_lines[0]
	if status_lines.size() > 1:
		system_detail_status.text += "\nCAUSE • %s" % status_lines[1]
	system_detail_output.text = _system_output_detail_text(room, output_efficiency, pressure, breach_length)
	system_detail_crew.text = _system_crew_detail_text(crew)
	system_detail_action.text = "ACTION • %s" % _system_action_hint(status_lines[0], status_lines[1] if status_lines.size() > 1 else "")


func _system_status_lines(room: Dictionary, operation_status: Dictionary, output_efficiency: float, pressure: float, breach_length: float) -> PackedStringArray:
	var lines: PackedStringArray = []
	var room_damaged := float(room["current_health"]) < float(room["maximum_health"]) - 0.001
	if breach_length > 0.0:
		lines.append("BREACH")
		lines.append("HULL OPEN TO SPACE")
	elif pressure < 0.35:
		lines.append("NO AIR")
		lines.append("COMPARTMENT PRESSURE CRITICAL")
	elif room_damaged:
		lines.append("DAMAGED")
		lines.append("STRUCTURE BELOW NOMINAL")
	elif not operation_status.is_empty() and String(operation_status.get("state", "NOMINAL")) != "NOMINAL":
		lines.append(String(operation_status.get("state", "CHECK")))
		lines.append(String(operation_status.get("reason", "SYSTEM DEGRADED")))
	elif output_efficiency < 0.995:
		lines.append("DEGRADED")
		lines.append("OUTPUT BELOW EXPECTED")
	else:
		lines.append("NOMINAL")
		lines.append("ALL LOCAL CONDITIONS GREEN")
	return lines


func _system_output_detail_text(room: Dictionary, output_efficiency: float, pressure: float, breach_length: float) -> String:
	return "%s • %03d%%\nSTRUCTURE • %03d / %03d\nATMOSPHERE • %03d%% • BREACH %.1f" % [
		String(room["effect_label"]),
		roundi(output_efficiency * 100.0),
		roundi(float(room["current_health"])),
		roundi(float(room["maximum_health"])),
		roundi(pressure * 100.0),
		breach_length,
	]


func _system_crew_detail_text(crew: Node) -> String:
	if not is_instance_valid(crew):
		return "CREW • SIMULATION OFFLINE"
	var requirements: Vector2i = crew.call("get_room_manning_requirements", selected_room_id)
	var assigned_members: Array[Dictionary] = crew.call("get_assigned_members", selected_room_id)
	var operating := 0
	var present := 0
	var en_route := 0
	var names: PackedStringArray = []
	for member: Dictionary in assigned_members:
		if bool(member.get("at_assignment", false)):
			present += 1
		else:
			en_route += 1
		if _crew_station_state_label(member) == "AT STATION":
			operating += 1
		names.append("%s:%s" % [String(member["name"]), _crew_station_state_label(member)])
	var crew_line := "CREW STATIONS • %s" % CREW_REQUIREMENT_DISPLAY.plain_text(requirements.y, operating, _ship_has_full_crew_capacity())
	crew_line += "\nMOVEMENT TRACE • %d PRESENT • %d EN ROUTE" % [present, en_route]
	if names.is_empty():
		return crew_line + "\nASSIGNED • NONE"
	return crew_line + "\nASSIGNED • %s" % "  |  ".join(names)


func _system_action_hint(status: String, cause: String) -> String:
	match status:
		"NOMINAL":
			return "MONITOR"
		"BREACH":
			return "OPEN STATUS AND SEAL WALLS"
		"NO AIR":
			return "EVACUATE OR RESTORE ATMOSPHERE"
		"DAMAGED":
			return "OPEN STATUS AND REPAIR ROOM"
		"UNMANNED", "DEGRADED":
			return "FILL OPEN STATIONS"
		"AUXILIARY":
			return "FILL STATIONS FOR FULL THRUST"
		"CREW EN ROUTE":
			return "WAIT FOR CREW TO ARRIVE"
		_:
			if cause.contains("CREW"):
				return "CHECK STAFFING"
			return "INSPECT RELATED SUBSYSTEM"


func _update_room_status_indicators() -> void:
	if not is_instance_valid(simulation):
		settlement_grid.call("set_room_status_indicators", {})
		return
	var layout: Resource = settlement_grid.get("ship_layout")
	if layout == null:
		settlement_grid.call("set_room_status_indicators", {})
		return
	var crew := get_tree().get_first_node_in_group("crew_simulation")
	var structure := _player_structural_state()
	var indicators: Dictionary = {}
	for room_definition: Resource in layout.get("rooms"):
		var room_id: StringName = room_definition.get("room_id")
		var room: Dictionary = simulation.get_room_data(room_id)
		if room.is_empty():
			continue
		var output_efficiency: float = simulation.get_room_efficiency(room_id)
		var operation_status: Dictionary = {}
		if is_instance_valid(crew):
			operation_status = crew.call("get_room_operational_status", room_id)
		var pressure := 1.0
		var breach_length := 0.0
		if structure != null:
			pressure = structure.get_room_pressure(room_id)
			breach_length = structure.get_room_outer_breach_length(room_id)
		var crew_en_route := false
		var repair_active := false
		if is_instance_valid(crew):
			crew_en_route = _room_has_crew_en_route(crew, room_id)
			repair_active = _room_has_active_repair_job(crew, room_id)
		indicators[room_id] = {
			"state": _room_indicator_state(room, operation_status, output_efficiency, pressure, breach_length, repair_active),
			"crew_en_route": crew_en_route,
		}
	settlement_grid.call("set_room_status_indicators", indicators)


func _room_indicator_state(room: Dictionary, operation_status: Dictionary, output_efficiency: float, pressure: float, breach_length: float, repair_active: bool) -> String:
	var room_damaged := float(room["current_health"]) < float(room["maximum_health"]) - 0.001
	if breach_length > 0.0:
		return "BREACH"
	if float(room["current_health"]) <= 0.001:
		return "SYSTEM DOWN"
	if pressure < 0.35:
		return "NO AIR"
	if repair_active:
		return "REPAIRING"
	if room_damaged:
		return "DAMAGED"
	if not operation_status.is_empty() and String(operation_status.get("state", "NOMINAL")) != "NOMINAL":
		return String(operation_status.get("state", "DEGRADED"))
	if output_efficiency < 0.995:
		return "DEGRADED"
	return "NOMINAL"


func _room_indicator_cause(state: String, operation_status: Dictionary) -> String:
	match state:
		"BREACH":
			return "The compartment hull is open to space."
		"NO AIR":
			return "Compartment pressure is critically low."
		"REPAIRING":
			return "Damage-control crew are actively repairing this compartment."
		"DAMAGED":
			return "Compartment structure is below nominal."
		"SYSTEM DOWN":
			return "The compartment has been disabled. Further hits here inflict amplified ship damage and may cause a catastrophic breach."
		"NOMINAL":
			return "All local operating conditions are nominal."
		_:
			var reason := String(operation_status.get("reason", "")).strip_edges()
			if not reason.is_empty():
				return "Output is degraded: %s." % reason
			return "System output is below nominal."


func _room_has_crew_en_route(crew: Node, room_id: StringName) -> bool:
	var assigned_members: Array[Dictionary] = crew.call("get_assigned_members", room_id)
	for member: Dictionary in assigned_members:
		if not bool(member.get("at_assignment", false)) and int(member.get("active_job_id", 0)) <= 0 and not bool(member.get("evacuating", false)):
			return true
	return false


func _room_has_active_repair_job(crew: Node, room_id: StringName) -> bool:
	var jobs: Array[Dictionary] = crew.call("get_jobs_for_room", room_id)
	for job: Dictionary in jobs:
		var state := String(job.get("state", ""))
		if state != "COMPLETE":
			return true
	return false


func _order_selected_room_repair() -> void:
	var crew := get_tree().get_first_node_in_group("crew_simulation")
	if is_instance_valid(crew) and selected_room_id != &"" and int(crew.call("request_room_repair", selected_room_id)) > 0:
		_play_menu_sound("play_execute")


func _order_selected_breach_repairs() -> void:
	var crew := get_tree().get_first_node_in_group("crew_simulation")
	if is_instance_valid(crew) and selected_room_id != &"" and int(crew.call("request_room_breach_repairs", selected_room_id)) > 0:
		_play_menu_sound("play_execute")


func _update_selected_room_panel() -> void:
	if not is_instance_valid(simulation):
		return

	var room: Dictionary = simulation.get_room_data(selected_room_id)
	if room.is_empty():
		return

	var health_percentage: float = simulation.get_room_health_percentage(selected_room_id)
	selected_room_name.text = room["name"]
	selected_room_type.text = "TYPE • %s" % simulation.get_room_type_name(selected_room_id)
	selected_room_health.text = "STRUCTURE • %03d / %03d  (%03d%%)" % [
		roundi(room["current_health"]),
		roundi(room["maximum_health"]),
		roundi(health_percentage),
	]
	selected_room_health.visible = health_percentage < 99.5

	var output_efficiency: float = simulation.get_room_efficiency(selected_room_id)
	selected_room_health_bar.value = output_efficiency * 100.0
	selected_room_health_bar.tooltip_text = "%d%% OUTPUT" % roundi(output_efficiency * 100.0)
	var selected_type: String = simulation.get_room_type_name(selected_room_id)
	var crew := get_tree().get_first_node_in_group("crew_simulation")
	var operation_status: Dictionary = {}
	if is_instance_valid(crew):
		operation_status = crew.call("get_room_operational_status", selected_room_id)
	if selected_type == "CREW_QUARTERS" and is_instance_valid(crew) and crew.has_method("get_reinforcement_status"):
		var reinforcement: Dictionary = crew.call("get_reinforcement_status")
		if bool(reinforcement.get("active", false)):
			var remaining: float = float(reinforcement.get("remaining", 0.0))
			var duration: float = maxf(float(reinforcement.get("duration", 1.0)), 0.001)
			var cycle_progress: float = clampf(1.0 - remaining / duration, 0.0, 1.0)
			selected_room_output.text = "%s x%d • %02d SEC" % [
				String(reinforcement.get("mode", "REINFORCEMENT")),
				int(reinforcement.get("sources", 1)),
				ceili(remaining),
			]
			selected_room_health_bar.max_value = 100.0
			selected_room_health_bar.value = cycle_progress * 100.0
			selected_room_health_bar.tooltip_text = "CREW FORMING • %d%%" % roundi(cycle_progress * 100.0)
		else:
			selected_room_output.text = "BERTHS READY • CREW AT CAPACITY"
			selected_room_health_bar.max_value = 100.0
			selected_room_health_bar.value = 100.0
			selected_room_health_bar.tooltip_text = "REINFORCEMENT CYCLE STANDBY"
	elif selected_type == "WORKSHOP":
		var capability: Dictionary = simulation.get_room_capability_status(selected_room_id)
		selected_room_output.text = "DAMAGE CONTROL • %s • %d OUTFIT" % [
			String(capability.get("reason", "OFFLINE")),
			int(capability.get("channels", 0)),
		]
		selected_room_health_bar.max_value = 100.0
		selected_room_health_bar.value = 100.0 if bool(capability.get("online", false)) else 0.0
		selected_room_health_bar.tooltip_text = "READINESS • HULL + POWER + AIR + CREW + ACCESS"
	elif selected_type in ["SUPPLY_STORAGE", "CARGO"]:
		selected_room_output.text = "LEGACY COMPARTMENT • NO ITEM STORAGE"
	elif selected_type == "UNASSIGNED":
		selected_room_output.text = "SYSTEM OUTPUT • NONE"
	else:
		selected_room_output.text = "%s • %03d%%" % [
			room["effect_label"],
			roundi(output_efficiency * 100.0),
		]
	var pressure := 1.0
	var breach_length := 0.0
	var structure := _player_structural_state()
	if structure != null:
		pressure = structure.get_room_pressure(selected_room_id)
		breach_length = structure.get_room_outer_breach_length(selected_room_id)
		var large_breach := breach_length >= float(structure.material.get("large_breach_length"))
		var atmosphere_state := "DECOMPRESSION HAZARD" if large_breach else ("VENTING" if breach_length > 0.0 else ("VACUUM" if pressure <= 0.02 else "SEALED"))
		selected_room_oxygen.text = "ATMOSPHERE • %03d%% • %s" % [roundi(pressure * 100.0), atmosphere_state]
		selected_room_oxygen_bar.value = pressure * 100.0
		var atmosphere_issue := pressure < 0.995 or breach_length > 0.0
		selected_room_oxygen.visible = atmosphere_issue
		selected_room_oxygen_bar.visible = atmosphere_issue
	if is_instance_valid(crew):
		var requirements: Vector2i = crew.call("get_room_manning_requirements", selected_room_id)
		var assigned: int = crew.call("get_room_assigned_count", selected_room_id)
		var present: int = crew.call("get_room_present_count", selected_room_id)
		var operating: int = crew.call("get_room_staffing", selected_room_id)
		selected_room_crew.text = "CREW STATIONS • %s" % CREW_REQUIREMENT_DISPLAY.plain_text(requirements.y, operating, _ship_has_full_crew_capacity())
		_update_room_staffing_controls(crew, requirements, assigned)
		_update_damage_control_readout(crew, room)
	else:
		selected_room_crew.text = "CREW • OFFLINE"
		staffing_configuration.visible = false
	var repair_active := is_instance_valid(crew) and _room_has_active_repair_job(crew, selected_room_id)
	var indicator_state := _room_indicator_state(room, operation_status, output_efficiency, pressure, breach_length, repair_active)
	var indicator_cause := _room_indicator_cause(indicator_state, operation_status)
	selected_room_status_lamp.add_theme_color_override("font_color", settlement_grid.call("status_color_for_state", indicator_state))
	selected_room_status_lamp.tooltip_text = "%s\nCTRL • SHOW DIAGNOSTICS + LINKS" % indicator_cause
	selected_room_status_text.text = indicator_state
	selected_room_status_text.tooltip_text = selected_room_status_lamp.tooltip_text
	var room_definition := _get_layout_room(selected_room_id)
	hangar_facing_configuration.visible = editor_mode and room_definition != null and String(room_definition.get("type_name")) == "HANGAR"
	if hangar_facing_configuration.visible:
		_update_selected_hangar_facing_controls(room_definition)
	weapon_configuration.visible = simulation.get_room_type_name(selected_room_id) == "WEAPONS"
	if weapon_configuration.visible:
		var weapon: Resource = room["weapon_definition"]
		var refit_controls_visible := editor_mode
		weapon_type_selector.visible = refit_controls_visible
		weapon_readout.visible = not refit_controls_visible
		weapon_type_selector.disabled = not refit_controls_visible or (room_definition != null and room_definition.get("module_recipe") != null)
		var mount_index := _selected_weapon_mount_index(room_definition)
		var mount_count := maxi(int(room_definition.get("installed_piece_count")), 1)
		var fire_mode := _weapon_fire_mode(room_definition, mount_index)
		fire_directive_title.text = "FIRE DIRECTIVE • HARDPOINT %d OF %d" % [mount_index + 1, mount_count]
		linked_fire_button.button_pressed = fire_mode == FIRE_MODE_LINKED
		trigger_fire_button.button_pressed = fire_mode == FIRE_MODE_TRIGGER
		sentry_fire_button.button_pressed = fire_mode == FIRE_MODE_SENTRY
		if weapon == null:
			weapon_readout_label.text = "NO WEAPON INSTALLED"
			weapon_stats.text = "FIRE CONTROL • OFFLINE\nREFIT IN SHIP EDITOR TO INSTALL"
			return
		for index: int in range(weapon_type_selector.item_count):
			if weapon_type_selector.get_item_metadata(index) == weapon:
				weapon_type_selector.select(index)
				break
		weapon_readout_label.text = "%s\n%s • %s DAMAGE" % [
			String(weapon.get("display_name")),
			String(weapon.get("weapon_family")),
			String(weapon.get("damage_type")),
		]
		weapon_stats.text = "%s • %s DAMAGE\nRANGE %d • DAMAGE %d\nARC +/- %d DEG • RELOAD %.2fs\nMOUNT %d/%d CONNECTED CELLS" % [
			weapon.get("weapon_family"),
			weapon.get("damage_type"),
			roundi(weapon.get("maximum_range")),
			roundi(weapon.get("damage")),
			roundi(weapon.get("traverse_degrees")),
			float(weapon.get("reload_seconds")),
			_room_cell_count(_get_layout_room(selected_room_id)),
			int(weapon.get("required_mount_cells")),
		]
