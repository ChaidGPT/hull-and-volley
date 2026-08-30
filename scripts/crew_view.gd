extends Control

@export_category("Camera Panning")
@export_range(100.0, 1600.0, 25.0) var pan_speed := 650.0

@export_category("Camera Zoom")
@export_range(0.2, 1.0, 0.05) var minimum_zoom := 0.4
@export_range(1.0, 4.0, 0.1) var maximum_zoom := 2.0
@export_range(1.01, 1.5, 0.01) var zoom_step := 1.15

@onready var world: Control = %World
@onready var position_label: Label = %PositionLabel
@onready var hud: PanelContainer = %Hud
@onready var status_label: Label = %Status
@onready var door_controls: HBoxContainer = %DoorControls
@onready var door_toggle_button: Button = %DoorToggleButton
@onready var door_lock_button: Button = %DoorLockButton
@onready var crew_controls: VBoxContainer = %CrewControls
@onready var crew_name_label: Label = %CrewName
@onready var crew_assignment_label: Label = %CrewAssignment
@onready var crew_vitals_label: Label = %CrewVitals
@onready var crew_morale_bar: ProgressBar = %CrewMoraleBar
@onready var crew_stats_label: Label = %CrewStats
@onready var equipment_slot_list: HBoxContainer = %EquipmentSlotList
@onready var release_crew_camera_button: Button = %ReleaseCrewCameraButton
@onready var unassign_crew_button: Button = %UnassignCrewButton
@onready var roster_button: Button = %RosterButton
@onready var roster_panel: PanelContainer = %RosterPanel
@onready var roster_search: LineEdit = %Search
@onready var roster_filter: OptionButton = %RosterFilter
@onready var roster_sort: OptionButton = %RosterSort
@onready var roster_list: VBoxContainer = %RosterList

var camera_position := Vector2.ZERO
var zoom_level := 1.0
var is_drag_panning := false
var selected_door_id := ""
var selected_crew_id := 0
var following_selected_crew := false
var roster_refresh_time := 0.0
var displayed_equipment_signature := ""


func _ready() -> void:
	clip_contents = true
	resized.connect(_clamp_and_update_camera)
	hud.call("power_off", true)
	door_toggle_button.pressed.connect(_toggle_selected_door)
	door_lock_button.pressed.connect(_toggle_selected_door_lock)
	release_crew_camera_button.pressed.connect(func() -> void: following_selected_crew = false)
	unassign_crew_button.pressed.connect(_unassign_selected_crew)
	roster_button.toggled.connect(_toggle_roster)
	roster_search.text_changed.connect(func(_text: String) -> void: _refresh_roster())
	roster_filter.item_selected.connect(func(_index: int) -> void: _refresh_roster())
	roster_sort.item_selected.connect(func(_index: int) -> void: _refresh_roster())
	for label: String in ["ALL CREW", "ASSIGNED", "UNASSIGNED", "IN TRANSIT"]:
		roster_filter.add_item(label)
	for label: String in ["NAME", "ASSIGNMENT", "ACTIVITY"]:
		roster_sort.add_item(label)
	roster_panel.call("power_off", true)
	_refresh_roster()
	call_deferred("_center_camera")


func _process(delta: float) -> void:
	# Combat and maintenance continue even while this camera is stationary.
	# Redraw live module overlays every frame so reload progress never waits for input.
	world.queue_redraw()
	_update_selected_door_readout()
	_update_selected_crew_readout()
	roster_refresh_time -= delta
	if roster_panel.visible and roster_refresh_time <= 0.0:
		_refresh_roster()
		roster_refresh_time = 0.5
	if is_drag_panning:
		return
	if following_selected_crew and selected_crew_id > 0:
		var target_position: Vector2 = world.call("get_crew_canvas_position", selected_crew_id)
		if target_position != Vector2.ZERO:
			camera_position = camera_position.lerp(target_position, 1.0 - exp(-5.0 * delta))
			_clamp_and_update_camera()
		return

	var pan_direction := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")

	if pan_direction.is_zero_approx():
		return

	camera_position += pan_direction.limit_length(1.0) * (pan_speed / zoom_level) * delta
	_clamp_and_update_camera()


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if _mouse_is_over_interface() and not (event.button_index == MOUSE_BUTTON_MIDDLE and is_drag_panning):
			return
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed and _is_mouse_inside_view():
			var crew_id: int = world.call("get_crew_at_local_position", world.get_local_mouse_position())
			if crew_id > 0:
				_select_crew_member(crew_id)
				get_viewport().set_input_as_handled()
				return
			var door_id: String = world.call("get_door_at_local_position", world.get_local_mouse_position())
			if not door_id.is_empty():
				_clear_crew_selection()
				selected_door_id = door_id
				door_controls.visible = true
				_update_selected_door_readout()
				hud.call("power_on_from", get_viewport().get_mouse_position())
				get_viewport().set_input_as_handled()
				return
			var room: Resource = world.call("get_room_at_local_position", world.get_local_mouse_position())
			if room != null:
				if selected_crew_id > 0:
					_assign_selected_crew_to_room(room.get("room_id"))
					get_viewport().set_input_as_handled()
					return
				_clear_crew_selection()
				selected_door_id = ""
				door_controls.visible = false
				status_label.text = "SELECTED: %s • CREW NOT YET DEPLOYED" % room.get("display_name")
				hud.call("power_on_from", get_viewport().get_mouse_position())
			else:
				_clear_crew_selection()
				selected_door_id = ""
				door_controls.visible = false
				if hud.visible:
					_play_menu_cancel()
				hud.call("power_off")
			get_viewport().set_input_as_handled()
			return
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			if event.pressed and _is_mouse_inside_view():
				is_drag_panning = true
				following_selected_crew = false
				get_viewport().set_input_as_handled()
			elif not event.pressed and is_drag_panning:
				is_drag_panning = false
				get_viewport().set_input_as_handled()
			return

		if not event.pressed or not _is_mouse_inside_view():
			return

		var requested_zoom := zoom_level
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			requested_zoom *= zoom_step
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			requested_zoom /= zoom_step
		else:
			return

		var mouse_position := get_local_mouse_position()
		var world_point_under_mouse := camera_position + (mouse_position - size * 0.5) / zoom_level
		zoom_level = clampf(requested_zoom, minimum_zoom, maximum_zoom)
		camera_position = world_point_under_mouse - (mouse_position - size * 0.5) / zoom_level
		_clamp_and_update_camera()
		get_viewport().set_input_as_handled()

	elif event is InputEventMouseMotion and is_drag_panning:
		camera_position -= event.relative / zoom_level
		_clamp_and_update_camera()
		get_viewport().set_input_as_handled()


func _player_structural_state() -> ShipStructuralState:
	var combat := get_tree().get_first_node_in_group("combat_simulation")
	return combat.call("get_structural_state", 0, 0) if is_instance_valid(combat) else null


func _toggle_selected_door() -> void:
	var structure := _player_structural_state()
	if structure == null or not structure.doors.has(selected_door_id):
		return
	var door: Dictionary = structure.doors[selected_door_id]
	structure.request_door_open(selected_door_id, not bool(door["requested_open"]))


func _toggle_selected_door_lock() -> void:
	var structure := _player_structural_state()
	if structure == null or not structure.doors.has(selected_door_id):
		return
	var door: Dictionary = structure.doors[selected_door_id]
	structure.set_door_locked(selected_door_id, not bool(door["locked"]))


func _update_selected_door_readout() -> void:
	if selected_door_id.is_empty():
		return
	var structure := _player_structural_state()
	if structure == null or not structure.doors.has(selected_door_id):
		selected_door_id = ""
		door_controls.visible = false
		return
	var door: Dictionary = structure.doors[selected_door_id]
	var locked := bool(door["locked"])
	var pressure_locked := bool(door["pressure_interlocked"])
	var openness := float(door["openness"])
	var state := "PRESSURE INTERLOCK" if pressure_locked else ("LOCKED" if locked else ("OPEN" if openness > 0.85 else ("OPENING" if bool(door["requested_open"]) else "CLOSED")))
	status_label.text = "DOOR • %s" % state
	door_toggle_button.text = "CLOSE" if bool(door["requested_open"]) else "OPEN"
	door_toggle_button.disabled = locked or pressure_locked
	door_lock_button.text = "UNLOCK" if locked else "LOCK"


func _select_crew_member(crew_id: int) -> void:
	selected_crew_id = crew_id
	selected_door_id = ""
	following_selected_crew = true
	door_controls.visible = false
	crew_controls.visible = true
	world.call("set_selected_crew", crew_id)
	displayed_equipment_signature = "__FORCE__"
	_update_selected_crew_readout()
	hud.call("power_on_from", get_viewport().get_mouse_position())


func _clear_crew_selection() -> void:
	selected_crew_id = 0
	following_selected_crew = false
	crew_controls.visible = false
	world.call("set_selected_crew", 0)


func _update_selected_crew_readout() -> void:
	if selected_crew_id <= 0:
		return
	var crew := get_tree().get_first_node_in_group("crew_simulation")
	if not is_instance_valid(crew):
		return
	var member: Dictionary = crew.call("get_member", selected_crew_id)
	if member.is_empty():
		_clear_crew_selection()
		return
	crew_name_label.text = String(member["name"])
	var assignment: String = crew.call("get_room_display_name", StringName(member["assigned_room_id"]))
	crew_assignment_label.text = "ASSIGNMENT • %s\nACTIVITY • %s\nCAMERA • %s" % [assignment, String(member["state"]), "TRACKING" if following_selected_crew else "RELEASED"]
	var health_percentage := 100.0 * float(member["health"]) / maxf(float(member["maximum_health"]), 0.001)
	crew_vitals_label.text = "HEALTH • %d%%" % roundi(health_percentage)
	_set_morale_bar(crew_morale_bar, float(member["morale"]))
	crew_stats_label.text = "STANDARD CREW • UNIVERSAL QUALIFICATION"
	_refresh_equipment_slots(member)
	status_label.text = "SELECTED CREW • %s" % String(member["name"])
	unassign_crew_button.disabled = StringName(member["assigned_room_id"]) == &""


func _refresh_equipment_slots(member: Dictionary) -> void:
	var equipment: Array[Resource] = member["equipment"]
	var signature_parts: PackedStringArray = []
	for item: Resource in equipment:
		signature_parts.append(item.resource_path if item != null else "EMPTY")
	var signature := "|".join(signature_parts)
	if signature == displayed_equipment_signature:
		return
	displayed_equipment_signature = signature
	for child: Node in equipment_slot_list.get_children():
		child.free()
	for index: int in range(equipment.size()):
		var item := equipment[index]
		var slot_button := Button.new()
		slot_button.custom_minimum_size = Vector2(48.0, 48.0)
		slot_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		slot_button.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		slot_button.expand_icon = true
		slot_button.text = "+" if item == null else ""
		if item != null:
			slot_button.icon = item.get("icon")
			if slot_button.icon == null:
				slot_button.text = String(item.get("display_name")).left(3).to_upper()
			slot_button.tooltip_text = _equipment_tooltip(item, index)
		else:
			slot_button.tooltip_text = "EMPTY • SLOT %d" % (index + 1)
		_apply_equipment_slot_style(slot_button, item != null)
		equipment_slot_list.add_child(slot_button)


func _equipment_tooltip(item: Resource, _slot_index: int) -> String:
	var lines: PackedStringArray = []
	var description := String(item.get("description")).strip_edges()
	if not description.is_empty():
		lines.append(description)
	var modifiers: Dictionary = item.get("stat_modifiers")
	if not modifiers.is_empty():
		var modifier_parts: PackedStringArray = []
		for stat_id: Variant in modifiers.keys():
			var amount := float(modifiers[stat_id])
			modifier_parts.append("%s %+.1f" % [String(stat_id).to_upper(), amount])
		lines.append("".join(modifier_parts))
	return "\n".join(lines)


func _apply_equipment_slot_style(button: Button, occupied: bool) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.025, 0.055, 0.07, 0.96)
	normal.border_width_left = 2
	normal.border_width_top = 2
	normal.border_width_right = 2
	normal.border_width_bottom = 2
	normal.border_color = Color(0.16, 0.48, 0.54, 0.95) if occupied else Color(0.12, 0.28, 0.32, 0.8)
	normal.corner_radius_top_left = 2
	normal.corner_radius_bottom_right = 2
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.04, 0.13, 0.16, 1.0)
	hover.border_color = Color(0.3, 0.95, 1.0, 1.0)
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(0.08, 0.28, 0.3, 1.0)
	pressed.border_color = Color(0.95, 0.68, 0.24, 1.0)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("focus", hover)
	button.add_theme_color_override("font_color", Color(0.3, 0.78, 0.82, 0.8))
	button.add_theme_font_size_override("font_size", 16)


func _assign_selected_crew_to_room(room_id: StringName) -> void:
	var crew := get_tree().get_first_node_in_group("crew_simulation")
	if not is_instance_valid(crew):
		return
	if crew.call("assign_crew_to_room", selected_crew_id, room_id):
		status_label.text = "ORDER ISSUED • REPORT TO %s" % crew.call("get_room_display_name", room_id)
		_refresh_roster()
	else:
		status_label.text = "ASSIGNMENT FAILED • NO OPEN SLOT OR ROUTE"


func _unassign_selected_crew() -> void:
	var crew := get_tree().get_first_node_in_group("crew_simulation")
	if is_instance_valid(crew) and selected_crew_id > 0:
		crew.call("unassign_crew", selected_crew_id)
		_refresh_roster()


func _toggle_roster(is_open: bool) -> void:
	if is_open:
		_refresh_roster()
		roster_panel.call("power_on_from", roster_button.get_global_rect().get_center())
	else:
		roster_panel.call("power_off")


func _refresh_roster() -> void:
	for child: Node in roster_list.get_children():
		child.free()
	var crew := get_tree().get_first_node_in_group("crew_simulation")
	if not is_instance_valid(crew):
		return
	var visible_members: Array[Dictionary] = []
	var search := roster_search.text.strip_edges().to_upper()
	for member: Dictionary in crew.crew_members:
		var assigned := StringName(member["assigned_room_id"]) != &""
		var in_transit := String(member["state"]) in ["MOVING", "REPORTING", "WAITING FOR DOOR"]
		if roster_filter.selected == 1 and not assigned:
			continue
		if roster_filter.selected == 2 and assigned:
			continue
		if roster_filter.selected == 3 and not in_transit:
			continue
		var assignment: String = crew.call("get_room_display_name", StringName(member["assigned_room_id"]))
		if not search.is_empty() and not String(member["name"]).to_upper().contains(search) and not assignment.to_upper().contains(search):
			continue
		visible_members.append(member)
	visible_members.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		match roster_sort.selected:
			1:
				return String(crew.call("get_room_display_name", StringName(a["assigned_room_id"]))) < String(crew.call("get_room_display_name", StringName(b["assigned_room_id"])))
			2:
				return String(a["state"]) < String(b["state"])
			_:
				return String(a["name"]) < String(b["name"])
	)
	for member: Dictionary in visible_members:
		var assignment: String = crew.call("get_room_display_name", StringName(member["assigned_room_id"]))
		var health_percentage := 100.0 * float(member["health"]) / maxf(float(member["maximum_health"]), 0.001)
		var row := PanelContainer.new()
		var row_style := StyleBoxFlat.new()
		row_style.bg_color = Color(0.025, 0.045, 0.06, 0.94)
		row_style.border_width_left = 2
		row_style.border_width_bottom = 1
		row_style.border_color = Color(0.18, 0.54, 0.6, 0.72)
		row_style.content_margin_left = 6.0
		row_style.content_margin_top = 5.0
		row_style.content_margin_right = 6.0
		row_style.content_margin_bottom = 5.0
		row.add_theme_stylebox_override("panel", row_style)
		var row_content := HBoxContainer.new()
		row_content.add_theme_constant_override("separation", 7)
		row.add_child(row_content)
		var portrait_scene: PackedScene = member["portrait_scene"]
		if portrait_scene != null:
			var portrait := portrait_scene.instantiate() as Control
			var portrait_color: Color = crew.crew_definition.get("base_color")
			portrait.call("configure", int(member["id"]), portrait_color.lightened(float(member["color_shift"])), health_percentage, float(member["morale"]))
			portrait.tooltip_text = "CLICK • FOLLOW"
			portrait.gui_input.connect(_on_roster_portrait_input.bind(int(member["id"])))
			row_content.add_child(portrait)
		var details := VBoxContainer.new()
		details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		details.add_theme_constant_override("separation", 2)
		row_content.add_child(details)
		var button := Button.new()
		button.flat = true
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.text = "%s • HP %d%%\n  %s • %s" % [String(member["name"]), roundi(health_percentage), assignment, String(member["state"])]
		button.tooltip_text = "CLICK • FOLLOW"
		button.pressed.connect(_select_crew_from_roster.bind(int(member["id"])))
		details.add_child(button)
		var morale_bar := ProgressBar.new()
		morale_bar.custom_minimum_size = Vector2(0.0, 6.0)
		morale_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		morale_bar.show_percentage = false
		_set_morale_bar(morale_bar, float(member["morale"]))
		details.add_child(morale_bar)
		roster_list.add_child(row)


func _on_roster_portrait_input(event: InputEvent, crew_id: int) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_select_crew_from_roster(crew_id)


func _select_crew_from_roster(crew_id: int) -> void:
	_select_crew_member(crew_id)
	roster_button.set_pressed_no_signal(false)
	roster_panel.call("power_off")


func _set_morale_bar(bar: ProgressBar, morale: float) -> void:
	var normalized := clampf(morale / 100.0, 0.0, 1.0)
	var low := Color(0.88, 0.16, 0.12, 1.0)
	var middle := Color(0.95, 0.68, 0.16, 1.0)
	var high := Color(0.25, 0.82, 0.4, 1.0)
	var fill_color := low.lerp(middle, normalized * 2.0) if normalized < 0.5 else middle.lerp(high, (normalized - 0.5) * 2.0)
	var background := StyleBoxFlat.new()
	background.bg_color = Color(0.025, 0.035, 0.04, 0.95)
	background.border_width_left = 1
	background.border_width_top = 1
	background.border_width_right = 1
	background.border_width_bottom = 1
	background.border_color = Color(0.24, 0.28, 0.3, 1.0)
	var fill := StyleBoxFlat.new()
	fill.bg_color = fill_color
	bar.add_theme_stylebox_override("background", background)
	bar.add_theme_stylebox_override("fill", fill)
	bar.value = morale


func _play_menu_cancel() -> void:
	var menu_audio := get_tree().get_first_node_in_group("menu_audio")
	if is_instance_valid(menu_audio):
		menu_audio.call("play_cancel")


func _center_camera() -> void:
	camera_position = world.size * 0.5
	_clamp_and_update_camera()


func _clamp_and_update_camera() -> void:
	var visible_world_size := size / zoom_level
	camera_position.x = _clamp_axis(camera_position.x, visible_world_size.x, world.size.x)
	camera_position.y = _clamp_axis(camera_position.y, visible_world_size.y, world.size.y)
	world.scale = Vector2.ONE * zoom_level
	world.position = size * 0.5 - camera_position * zoom_level
	world.queue_redraw()
	position_label.text = "CAMERA X %04d Y %04d • %.2fx" % [camera_position.x, camera_position.y, zoom_level]


func _clamp_axis(value: float, viewport_extent: float, world_extent: float) -> float:
	if world_extent <= viewport_extent:
		return world_extent * 0.5
	return clampf(value, viewport_extent * 0.5, world_extent - viewport_extent * 0.5)


func _is_mouse_inside_view() -> bool:
	return Rect2(Vector2.ZERO, size).has_point(get_local_mouse_position())


func _mouse_is_over_interface() -> bool:
	var hovered := get_viewport().gui_get_hovered_control()
	if hovered == null or hovered == self or hovered == world:
		return false
	return true
