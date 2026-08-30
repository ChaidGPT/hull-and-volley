extends Control

signal forge_inventory_piece_dropped(room_type: String, cell: Vector2i, source_instance_id: int)
signal forge_inventory_piece_rejected(reason: String, source_instance_id: int)
signal installed_piece_relocated(room_type: String, room_id: StringName, source_cell: Vector2i, target_cell: Vector2i)

signal room_selected(room_id: StringName)
signal editor_cell_clicked(cell: Vector2i)
signal editor_cell_activated(cell: Vector2i, button_index: int)
signal editor_cells_dragged(cells: Array[Vector2i])
signal room_hovered(room_name: String, anchor_local: Vector2)
signal room_hover_exited
signal empty_space_selected
signal structural_wall_selected(wall_key: String)

## Quarter-lattice cell size. Legacy 36px rooms migrate from 1x1 to 2x2 and
## therefore retain their original on-screen dimensions.
const CELL_SIZE := 18
const CANVAS_PADDING := Vector2(28, 38)
const EDIT_MARGIN_CELLS := 1
const GRID_GEOMETRY := preload("res://scripts/grid_geometry.gd")
const SHIP_RESOURCE_ANALYZER := preload("res://scripts/ship_builder_analyzer.gd")
const ROOM_STAFFING_RULES := preload("res://scripts/room_staffing_rules.gd")
const TACTICAL_SHIP_VISUAL_SCRIPT := preload("res://scripts/tactical_ship_visual.gd")
const TACTICAL_CELL_SIZE := 10.0
const TACTICAL_CANVAS_PADDING := Vector2(10, 22)
const ForgeInventoryPieceScript := preload("res://scripts/forge_inventory_piece.gd")
const DOOR_VISUALS := preload("res://scripts/door_visuals.gd")
const QUARTER_ROOM_BASE := preload("res://assets/sprites/interiors/rooms/quarter/base.png")
const QUARTER_ROOM_CONNECTOR := preload("res://assets/sprites/interiors/rooms/quarter/connector.png")
const LIGHT_BALLISTIC_MOUNT := preload("res://assets/sprites/weapons/authored/light_ballistic_mount.png")
const INVALID_CELL := Vector2i(2147483647, 2147483647)
const CREW_ANIMATION_RANGES := {
	"Idle": Vector2i(0, 1),
	"Walk": Vector2i(2, 11),
	"Pistol_idle": Vector2i(24, 25),
	"Rest": Vector2i(37, 37),
	"Die": Vector2i(36, 37),
}
const CREW_FRAME_DURATION_MS := 100

@export var ship_layout: Resource

@export_category("Grid Indicators")
@export var hull_edge_indicator_color := Color(1.0, 0.58, 0.18, 0.95)
@export_range(1.0, 10.0, 0.5) var hull_edge_indicator_width := 4.0
@export var editor_hover_valid_color := Color(0.2, 0.95, 1.0, 0.95)
@export var editor_hover_blocked_color := Color(1.0, 0.24, 0.16, 0.95)
@export var editor_selection_color := Color(0.95, 0.72, 0.24, 0.95)
@export var module_facing_indicator_color := Color(0.2, 0.95, 1.0, 0.95)
@export_range(1.0, 10.0, 0.5) var module_facing_indicator_width := 3.0
@export_range(6.0, 40.0, 1.0) var module_facing_arrow_length := 16.0

@export_category("Builder Detail Transition")
## Zoom at which the planning blocks resolve into authored room artwork.
@export_range(0.5, 3.0, 0.05) var editor_deck_detail_zoom := 1.25
@export_range(0.05, 1.0, 0.05) var editor_deck_detail_blend_width := 0.3

@export_category("Status Indicators")
## Tiny room-status lamp color when the compartment is healthy and fully useful.
@export var status_nominal_color := Color(0.34, 1.0, 0.62, 0.95)
## Tiny room-status lamp color when output is reduced but the room is not in immediate danger.
@export var status_degraded_color := Color(1.0, 0.82, 0.24, 0.95)
## Tiny room-status lamp color when structure is damaged or repairs are active.
@export var status_damaged_color := Color(1.0, 0.48, 0.18, 0.95)
## Tiny room-status lamp color when air or hull integrity is critical.
@export var status_danger_color := Color(1.0, 0.18, 0.12, 0.96)
## Secondary room lamp color shown when assigned crew are still traveling to stations.
@export var crew_en_route_status_color := Color(0.28, 0.8, 1.0, 0.95)
## Directional link color for a beneficial room-adjacency effect.
@export var synergy_link_color := Color(0.25, 1.0, 0.72, 0.92)
## Directional link color for a harmful room-adjacency effect.
@export var interference_link_color := Color(1.0, 0.5, 0.18, 0.92)
## Directional link color for an informational room-adjacency effect.
@export var neutral_link_color := Color(0.4, 0.82, 1.0, 0.88)
@export var power_field_color := Color(0.12, 0.92, 1.0, 0.18)
@export var power_field_overload_color := Color(1.0, 0.58, 0.12, 0.24)
@export var power_field_uncovered_color := Color(1.0, 0.18, 0.12, 0.82)

@export_category("Breach Atmosphere Effect")
## Color of atmosphere particles escaping through breached outer hull walls.
@export var breach_jet_color := Color(0.5, 0.9, 1.0, 0.72)
## Number of animated atmosphere motes drawn at each active breach.
@export_range(1, 20, 1) var breach_jet_particles := 7
## Distance in pixels traveled by venting atmosphere in this view.
@export_range(4.0, 80.0, 1.0) var breach_jet_length := 28.0
## Half-angle of the turbulent atmosphere fan escaping a breach.
@export_range(0.0, 1.2, 0.05) var breach_jet_spread := 0.48

var selected_room_id: StringName = &""
var selected_room_cell := INVALID_CELL
var last_editor_click_was_hardware := false
var hovered_room_id: StringName = &""
var editor_mode := false
## Embedded workbenches provide their own viewport and must not inherit the
## full blueprint canvas as a UI minimum size.
var editor_viewport_constrained := false
## Unlimited Forge blueprints may stage modules anywhere inside the authorized
## frame. Live refits leave this false and still require hull-edge attachment.
var free_blueprint_placement := false
var editor_selection_mode := false
var show_all_indicators := false
var show_all_weapon_envelopes := false
var show_weapon_envelopes_outside_editor := false
var group_selection: Dictionary = {}
var generated_labels: Array[Label] = []
var hovered_build_cell := INVALID_CELL
var hovered_build_offset := Vector2.ZERO
var editor_focus_cell := INVALID_CELL
var editor_focus_offset := Vector2.ZERO
var editor_drag_start_position := Vector2.INF
var editor_dragging := false
var editor_drag_selection: Dictionary = {}
var editor_view_zoom := 1.0
var editor_view_pan := Vector2.ZERO
var editor_view_panning := false
var editor_view_pan_with_left := false
var editor_view_pan_moved := false
var editor_edit_locked := false
var core_frame_edit_locked := true
var inventory_piece_drag_active := false
var inventory_piece_armed := false
var inventory_piece_install_allowed := true
var inventory_piece_room_type := ""
var inventory_piece_footprint := Vector2i(2, 2)
var installed_drag_data: Dictionary = {}
var installed_drag_drop_committed := false
var installed_drag_pointer_position := Vector2.INF
var installed_drag_grab_offset := Vector2.ZERO
var installed_drag_returning := false
var installed_drag_return_tween: Tween
var combat_overlay: CloseCombatOverlay
var module_piece_view_cache: Dictionary = {}
var damage_lab_mode := false
var hovered_structural_wall := ""
var selected_structural_wall := ""
var room_status_indicators: Dictionary = {}
var editor_deck_detail_visual: Control


func _ready() -> void:
	if ship_layout == null:
		push_error("SettlementGrid requires a ship layout resource.")
		return
	if ship_layout.has_method("ensure_quarter_lattice"):
		ship_layout.call("ensure_quarter_lattice")
	_update_canvas_size()
	_create_labels()
	combat_overlay = CloseCombatOverlay.new()
	combat_overlay.name = "CloseCombatOverlay"
	add_child(combat_overlay)
	combat_overlay.configure(self, ship_layout, _hull_pixel_origin(), CELL_SIZE)
	_create_editor_deck_detail_visual()
	mouse_exited.connect(_on_mouse_exited)
	queue_redraw()


func _process(_delta: float) -> void:
	_sync_editor_deck_detail_visual()
	# Moving hardware needs animation frames. A stationary Forge selection does
	# not: continuously repainting the complete drydock made cost grow with every
	# installed grid merely to pulse one outline.
	if not installed_drag_data.is_empty():
		queue_redraw()
	var live_ship := get_tree().get_first_node_in_group("ship_simulation")
	if not editor_mode and is_instance_valid(live_ship) and (
		not (live_ship.get("module_damage") as Dictionary).is_empty()
		or not (live_ship.get("module_ion_disable_remaining") as Dictionary).is_empty()
	):
		queue_redraw()
	if DOOR_VISUALS.is_transitioning(_get_player_structure()):
		queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		if editor_mode and editor_view_panning:
			editor_view_pan += motion.relative
			editor_view_pan_moved = editor_view_pan_moved or motion.relative.length_squared() > 0.01
			_clamp_editor_view_pan()
			queue_redraw()
			accept_event()
			return
		var pointer_position := _screen_to_editor_content(motion.position)
		if editor_mode and editor_dragging and not installed_drag_data.is_empty():
			# Installed modules move inside the workbench without entering Godot's
			# generic Control drag/drop handshake. A Control is not a reliable drop
			# target for a drag it originated itself, which made the ghost appear to
			# place successfully while the authored layout stayed unchanged.
			_update_hovered_build_candidate(pointer_position)
			installed_drag_pointer_position = pointer_position
			queue_redraw()
			accept_event()
			return
		if damage_lab_mode:
			hovered_structural_wall = _structural_wall_at_position(pointer_position)
			queue_redraw()
			return
		_update_hovered_room_id(pointer_position)
		if editor_mode:
			_update_hovered_build_candidate(pointer_position)
			if not editor_edit_locked and editor_drag_start_position != Vector2.INF and (motion.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
				var drag_delta := pointer_position - editor_drag_start_position
				if drag_delta.length() > 6.0:
					var drag_cell := _occupied_cell_at_position(editor_drag_start_position)
					if drag_cell != INVALID_CELL:
						var drag_room := _room_at_cell(drag_cell)
						if _begin_installed_piece_drag(drag_room, drag_cell, pointer_position, editor_drag_start_position):
							_update_hovered_build_candidate(pointer_position)
							queue_redraw()
							accept_event()
							return
			room_hover_exited.emit()
		else:
			_update_room_hover(pointer_position)
		return
	if not event is InputEventMouseButton:
		return
	var mouse_event := event as InputEventMouseButton
	var pointer_position := _screen_to_editor_content(mouse_event.position)
	if editor_mode and mouse_event.button_index == MOUSE_BUTTON_MIDDLE:
		editor_view_panning = mouse_event.pressed
		editor_view_pan_with_left = false
		editor_view_pan_moved = false
		accept_event()
		return
	if damage_lab_mode:
		if mouse_event.button_index != MOUSE_BUTTON_LEFT or not mouse_event.pressed:
			return
		selected_structural_wall = _structural_wall_at_position(pointer_position)
		if not selected_structural_wall.is_empty():
			structural_wall_selected.emit(selected_structural_wall)
		accept_event()
		queue_redraw()
		return

	if editor_mode:
		if mouse_event.button_index == MOUSE_BUTTON_LEFT and not mouse_event.pressed and editor_dragging:
			_finish_installed_workbench_drag(pointer_position)
			accept_event()
			return
		if mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed:
			var pressed_cell := _occupied_cell_at_position(pointer_position)
			if pressed_cell == INVALID_CELL and not inventory_piece_armed:
				editor_view_panning = true
				editor_view_pan_with_left = true
				editor_view_pan_moved = false
				editor_drag_start_position = Vector2.INF
			else:
				editor_drag_start_position = Vector2.INF if editor_edit_locked else pointer_position
			editor_dragging = false
			editor_drag_selection.clear()
			accept_event()
			return
		if mouse_event.button_index == MOUSE_BUTTON_LEFT and not mouse_event.pressed:
			if editor_view_pan_with_left:
				var was_camera_drag := editor_view_pan_moved
				editor_view_panning = false
				editor_view_pan_with_left = false
				editor_view_pan_moved = false
				if not was_camera_drag:
					var empty_click_cell := _editor_cell_for_position(pointer_position)
					if empty_click_cell != INVALID_CELL:
						editor_cell_activated.emit(empty_click_cell, MOUSE_BUTTON_LEFT)
						editor_cell_clicked.emit(empty_click_cell)
					else:
						clear_room_selection()
						empty_space_selected.emit()
				accept_event()
				return
			editor_drag_start_position = Vector2.INF
			var click_cell := _editor_cell_for_position(pointer_position)
			if click_cell != INVALID_CELL:
				last_editor_click_was_hardware = _pointer_hits_module_hardware(click_cell, pointer_position)
				editor_cell_activated.emit(click_cell, MOUSE_BUTTON_LEFT)
				editor_cell_clicked.emit(click_cell)
				accept_event()
			else:
				clear_room_selection()
				empty_space_selected.emit()
				accept_event()
			return
		if mouse_event.button_index == MOUSE_BUTTON_RIGHT and mouse_event.pressed:
			if editor_edit_locked:
				accept_event()
				return
			var right_cell := _occupied_cell_at_position(pointer_position)
			if right_cell != INVALID_CELL:
				editor_cell_activated.emit(right_cell, MOUSE_BUTTON_RIGHT)
				accept_event()
			return
		return

	for room: Resource in _rooms():
		for cell_value: Variant in _room_cells(room).keys():
			if _get_grid_rect(Rect2i(cell_value, Vector2i.ONE)).has_point(pointer_position):
				select_room(room.get("room_id"), cell_value)
				accept_event()
				return
	empty_space_selected.emit()
	accept_event()


func _finish_installed_workbench_drag(pointer_position: Vector2) -> void:
	_update_hovered_build_candidate(pointer_position)
	if hovered_build_cell != INVALID_CELL:
		installed_drag_drop_committed = true
		installed_piece_relocated.emit(
			String(installed_drag_data.get("room_type", "UNASSIGNED")),
			StringName(installed_drag_data.get("room_id", &"")),
			Vector2i(installed_drag_data.get("cell", INVALID_CELL)),
			hovered_build_cell
		)
		_clear_installed_workbench_drag()
	else:
		forge_inventory_piece_rejected.emit("NO VALID HULL SOCKET UNDER CURSOR", 0)
		_return_installed_piece_to_source()


func _begin_installed_piece_drag(
	drag_room: Resource,
	drag_cell: Vector2i,
	pointer_position: Vector2,
	grab_position: Vector2 = Vector2.INF
) -> bool:
	if drag_room == null or drag_cell == INVALID_CELL:
		return false
	var source_rect := _room_piece_lattice_rect(drag_room, drag_cell)
	if core_frame_edit_locked and ship_layout != null and ship_layout.has_method("rect_contains_core") and bool(ship_layout.call("rect_contains_core", source_rect)):
		forge_inventory_piece_rejected.emit("CORE FRAME LOCKED", 0)
		return false
	if is_instance_valid(installed_drag_return_tween):
		installed_drag_return_tween.kill()
	installed_drag_return_tween = null
	installed_drag_returning = false
	# A combined room can contain several physical modules. Lift only the module
	# under the cursor, preserving its exact footprint and the point it was held.
	var drag_footprint := _room_piece_lattice_footprint(drag_room, drag_cell)
	var source_pixel_rect := _get_grid_rect(source_rect)
	if grab_position == Vector2.INF:
		grab_position = pointer_position
	installed_drag_data = {
		"kind": "installed_grid_piece",
		"room_type": String(drag_room.get("type_name")),
		"room_id": StringName(drag_room.get("room_id")),
		"cell": drag_cell,
		"footprint": drag_footprint,
		"source_rect": source_rect,
	}
	installed_drag_pointer_position = pointer_position
	installed_drag_grab_offset = grab_position - source_pixel_rect.position
	inventory_piece_drag_active = true
	inventory_piece_room_type = String(drag_room.get("type_name"))
	inventory_piece_footprint = drag_footprint
	installed_drag_drop_committed = false
	editor_dragging = true
	editor_drag_start_position = Vector2.INF
	return true


func _return_installed_piece_to_source() -> void:
	if installed_drag_data.is_empty() or installed_drag_returning:
		return
	installed_drag_returning = true
	editor_dragging = false
	inventory_piece_drag_active = false
	hovered_build_cell = INVALID_CELL
	hovered_build_offset = Vector2.ZERO
	var source_rect: Rect2i = installed_drag_data.get("source_rect", Rect2i())
	var target_pointer := _get_grid_rect(source_rect).position + installed_drag_grab_offset
	var start_pointer := installed_drag_pointer_position
	if start_pointer == Vector2.INF:
		start_pointer = target_pointer
	installed_drag_return_tween = create_tween()
	installed_drag_return_tween.set_trans(Tween.TRANS_CUBIC)
	installed_drag_return_tween.set_ease(Tween.EASE_IN_OUT)
	installed_drag_return_tween.tween_method(
		_set_installed_drag_pointer_position,
		start_pointer,
		target_pointer,
		0.18
	)
	installed_drag_return_tween.tween_callback(_finish_installed_piece_return)
	queue_redraw()


func _set_installed_drag_pointer_position(pointer_position: Vector2) -> void:
	installed_drag_pointer_position = pointer_position
	queue_redraw()


func _finish_installed_piece_return() -> void:
	installed_drag_return_tween = null
	_clear_installed_workbench_drag()


func _clear_installed_workbench_drag() -> void:
	if is_instance_valid(installed_drag_return_tween):
		installed_drag_return_tween.kill()
	installed_drag_return_tween = null
	editor_dragging = false
	editor_drag_start_position = Vector2.INF
	installed_drag_data.clear()
	installed_drag_drop_committed = false
	installed_drag_pointer_position = Vector2.INF
	installed_drag_grab_offset = Vector2.ZERO
	installed_drag_returning = false
	inventory_piece_drag_active = false
	hovered_build_cell = INVALID_CELL
	hovered_build_offset = Vector2.ZERO
	queue_redraw()


func select_room(room_id: StringName, room_cell := INVALID_CELL) -> void:
	for room: Resource in _rooms():
		if room.get("room_id") == room_id:
			selected_room_id = room_id
			selected_room_cell = Vector2i(room_cell)
			room_selected.emit(room_id)
			queue_redraw()
			return


func get_selected_room_cell() -> Vector2i:
	return selected_room_cell


func was_last_editor_click_on_hardware() -> bool:
	return last_editor_click_was_hardware


func set_editor_mode(is_enabled: bool) -> void:
	var was_enabled := editor_mode
	editor_mode = is_enabled
	editor_view_panning = false
	editor_view_pan_with_left = false
	editor_view_pan_moved = false
	if is_enabled:
		room_hover_exited.emit()
		if not was_enabled:
			call_deferred("fit_editor_view")
	_sync_editor_deck_detail_visual()
	queue_redraw()


func set_editor_viewport_constrained(is_constrained: bool) -> void:
	editor_viewport_constrained = is_constrained
	_update_canvas_size()


func set_free_blueprint_placement(is_enabled: bool) -> void:
	free_blueprint_placement = is_enabled
	hovered_build_cell = INVALID_CELL
	hovered_build_offset = Vector2.ZERO
	queue_redraw()


func set_editor_edit_locked(is_locked: bool) -> void:
	if editor_edit_locked == is_locked:
		return
	editor_edit_locked = is_locked
	editor_drag_start_position = Vector2.INF
	editor_dragging = false
	editor_drag_selection.clear()
	queue_redraw()


func set_core_frame_edit_locked(is_locked: bool) -> void:
	core_frame_edit_locked = is_locked


func set_damage_lab_mode(is_enabled: bool) -> void:
	damage_lab_mode = is_enabled
	hovered_structural_wall = ""
	selected_structural_wall = ""
	if is_enabled:
		room_hover_exited.emit()
	queue_redraw()


func set_editor_selection_mode(is_enabled: bool) -> void:
	editor_selection_mode = is_enabled
	queue_redraw()


func set_show_all_weapon_envelopes(is_enabled: bool) -> void:
	show_all_weapon_envelopes = is_enabled
	queue_redraw()


func set_weapon_envelopes_outside_editor(is_enabled: bool) -> void:
	show_weapon_envelopes_outside_editor = is_enabled
	queue_redraw()


func clear_room_selection() -> void:
	selected_room_id = &""
	selected_room_cell = INVALID_CELL
	queue_redraw()


func set_inventory_piece_armed(is_armed: bool, can_install := true, room_type := "", footprint := Vector2i(2, 2)) -> void:
	inventory_piece_armed = is_armed
	inventory_piece_install_allowed = can_install
	inventory_piece_room_type = room_type if is_armed else ""
	inventory_piece_footprint = Vector2i(footprint) if is_armed else Vector2i(2, 2)
	if not is_armed:
		hovered_build_cell = INVALID_CELL
		hovered_build_offset = Vector2.ZERO
	queue_redraw()


func controller_hover_armed_piece_at_global_position(global_position: Vector2) -> void:
	if not editor_mode or not inventory_piece_armed:
		return
	var local_position := get_global_transform_with_canvas().affine_inverse() * global_position
	_update_hovered_build_candidate(_screen_to_editor_content(local_position))


func controller_place_armed_piece_at_global_position(global_position: Vector2) -> bool:
	if not editor_mode or editor_edit_locked or not inventory_piece_armed:
		return false
	var local_position := get_global_transform_with_canvas().affine_inverse() * global_position
	var content_position := _screen_to_editor_content(local_position)
	_update_hovered_build_candidate(content_position)
	if hovered_build_cell == INVALID_CELL:
		return false
	last_editor_click_was_hardware = false
	editor_cell_activated.emit(hovered_build_cell, MOUSE_BUTTON_LEFT)
	editor_cell_clicked.emit(hovered_build_cell)
	return true


func get_pending_placement_offset() -> Vector2:
	return hovered_build_offset


func set_group_selection(cells: Dictionary) -> void:
	group_selection = cells.duplicate()
	queue_redraw()


func set_editor_focus_cell(cell: Vector2i, offset: Vector2 = Vector2.ZERO) -> void:
	editor_focus_cell = cell
	editor_focus_offset = offset
	queue_redraw()


func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	if not editor_mode or editor_edit_locked or not (data is Dictionary):
		return false
	var drag_kind := String(data.get("kind", ""))
	if drag_kind not in ["forge_grid_piece", "installed_grid_piece"]:
		return false
	inventory_piece_drag_active = true
	inventory_piece_room_type = String(data.get("room_type", ""))
	inventory_piece_footprint = Vector2i(data.get("footprint", Vector2i(2, 2)))
	var content_position := _screen_to_editor_content(at_position)
	_update_hovered_build_candidate(content_position)
	queue_redraw()
	# Accept drops anywhere inside the drydock console so invalid targets can
	# report why they failed instead of silently swallowing the action.
	return true


func _drop_data(at_position: Vector2, data: Variant) -> void:
	var content_position := _screen_to_editor_content(at_position)
	_update_hovered_build_candidate(content_position)
	var cell := hovered_build_cell
	if cell == INVALID_CELL:
		forge_inventory_piece_rejected.emit("NO OPEN BUILD CELL UNDER CURSOR", int(data.get("source_instance_id", 0)))
		if String(data.get("kind", "")) == "installed_grid_piece":
			installed_drag_pointer_position = content_position
			_return_installed_piece_to_source()
			return
		inventory_piece_drag_active = false
		hovered_build_cell = INVALID_CELL
		hovered_build_offset = Vector2.ZERO
		queue_redraw()
		return
	if String(data.get("kind", "")) == "installed_grid_piece":
		installed_drag_drop_committed = true
		installed_piece_relocated.emit(
			String(data.get("room_type", "UNASSIGNED")),
			StringName(data.get("room_id", &"")),
			Vector2i(data.get("cell", INVALID_CELL)),
			cell
		)
		_clear_installed_workbench_drag()
		return
	else:
		forge_inventory_piece_dropped.emit(String(data.get("room_type", "UNASSIGNED")), cell, int(data.get("source_instance_id", 0)))
	inventory_piece_drag_active = false
	hovered_build_cell = INVALID_CELL
	hovered_build_offset = Vector2.ZERO
	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END:
		# Godot does not consistently route a forced drag back into the same
		# Control that originated it. If this installed part was released over
		# the workbench and _drop_data never ran, commit the self-drop here.
		if installed_drag_returning:
			return
		if not installed_drag_data.is_empty() and not installed_drag_drop_committed:
			var local_mouse := get_local_mouse_position()
			if Rect2(Vector2.ZERO, size).has_point(local_mouse):
				var content_position := _screen_to_editor_content(local_mouse)
				installed_drag_pointer_position = content_position
				_update_hovered_build_candidate(content_position)
				if hovered_build_cell != INVALID_CELL:
					installed_drag_drop_committed = true
					installed_piece_relocated.emit(
						String(installed_drag_data.get("room_type", "UNASSIGNED")),
						StringName(installed_drag_data.get("room_id", &"")),
						Vector2i(installed_drag_data.get("cell", INVALID_CELL)),
						hovered_build_cell
					)
					_clear_installed_workbench_drag()
					return
				else:
					forge_inventory_piece_rejected.emit("NO VALID HULL SOCKET UNDER CURSOR", 0)
					_return_installed_piece_to_source()
					return
			if get_viewport().gui_is_drag_successful():
				_clear_installed_workbench_drag()
				return
			installed_drag_pointer_position = _screen_to_editor_content(local_mouse)
			forge_inventory_piece_rejected.emit("MODULE RELEASED OUTSIDE A VALID SOCKET", 0)
			_return_installed_piece_to_source()


func fit_editor_view() -> void:
	if not editor_mode:
		return
	var content_size := _editor_content_size()
	var viewport_size := size
	if viewport_size.x <= 1.0 or viewport_size.y <= 1.0:
		viewport_size = custom_minimum_size
	var fit_zoom := minf(viewport_size.x / maxf(content_size.x, 1.0), viewport_size.y / maxf(content_size.y, 1.0)) * 0.88
	editor_view_zoom = clampf(fit_zoom, 0.35, 4.0)
	editor_view_pan = (viewport_size - content_size * editor_view_zoom) * 0.5
	_clamp_editor_view_pan()
	queue_redraw()


func _create_editor_deck_detail_visual() -> void:
	if is_instance_valid(editor_deck_detail_visual) or ship_layout == null:
		return
	editor_deck_detail_visual = TACTICAL_SHIP_VISUAL_SCRIPT.new() as Control
	editor_deck_detail_visual.name = "BuilderDeckDetail"
	editor_deck_detail_visual.mouse_filter = Control.MOUSE_FILTER_IGNORE
	editor_deck_detail_visual.show_behind_parent = true
	# show_behind_parent places the art beneath this grid's editor overlays. A
	# negative z-index also put it behind the Shipyard modal's opaque background,
	# making the rooms invisible while their schematic layer faded away.
	editor_deck_detail_visual.z_index = 0
	editor_deck_detail_visual.set("blueprint_preview_mode", true)
	editor_deck_detail_visual.set("ship_layout", ship_layout)
	add_child(editor_deck_detail_visual)
	editor_deck_detail_visual.call("set_deck_detail_visible", true)
	# Builder artwork is static between layout edits. The live renderer normally
	# repaints for crew, damage, and weapon animation, none of which belongs here.
	editor_deck_detail_visual.process_mode = Node.PROCESS_MODE_DISABLED
	_sync_editor_deck_detail_visual()


func _editor_deck_detail_mix() -> float:
	if not editor_mode:
		return 0.0
	var blend_half := editor_deck_detail_blend_width * 0.5
	return smoothstep(
		editor_deck_detail_zoom - blend_half,
		editor_deck_detail_zoom + blend_half,
		editor_view_zoom
	)


func _sync_editor_deck_detail_visual() -> void:
	if not is_instance_valid(editor_deck_detail_visual) or ship_layout == null:
		return
	# Reassert this for already-open Forge instances after script hot reloads.
	editor_deck_detail_visual.show_behind_parent = true
	editor_deck_detail_visual.z_index = 0
	var detail_mix := _editor_deck_detail_mix()
	editor_deck_detail_visual.visible = editor_mode and detail_mix > 0.001
	if not editor_deck_detail_visual.visible:
		return
	var occupied: Rect2i = ship_layout.call("get_occupied_bounds", false)
	if occupied.size.x <= 0 or occupied.size.y <= 0:
		editor_deck_detail_visual.visible = false
		return
	var art_scale := CELL_SIZE / TACTICAL_CELL_SIZE
	var target_top_left := _get_grid_rect(Rect2i(occupied.position, Vector2i.ONE)).position
	editor_deck_detail_visual.position = (
		editor_view_pan
		+ (target_top_left - TACTICAL_CANVAS_PADDING * art_scale) * editor_view_zoom
	)
	editor_deck_detail_visual.scale = Vector2.ONE * art_scale * editor_view_zoom
	editor_deck_detail_visual.modulate = Color(1.0, 1.0, 1.0, detail_mix)


func fit_editor_view_to_hull(fill_ratio: float = 0.72) -> void:
	if not editor_mode or not is_instance_valid(ship_layout):
		return
	var occupied: Rect2i = ship_layout.call("get_occupied_bounds", false)
	if occupied.size.x <= 0 or occupied.size.y <= 0:
		fit_editor_view()
		return
	var viewport_size := size
	if viewport_size.x <= 1.0 or viewport_size.y <= 1.0:
		viewport_size = custom_minimum_size
	var hull_rect := _get_grid_rect(occupied)
	var safe_ratio := clampf(fill_ratio, 0.25, 0.88)
	var horizontal_room := viewport_size.x * minf(safe_ratio, 0.78)
	var vertical_room := viewport_size.y * safe_ratio
	var fit_zoom := minf(
		horizontal_room / maxf(hull_rect.size.x, 1.0),
		vertical_room / maxf(hull_rect.size.y, 1.0)
	)
	editor_view_zoom = clampf(fit_zoom, 0.35, 4.0)
	editor_view_pan = viewport_size * 0.5 - hull_rect.get_center() * editor_view_zoom
	_clamp_editor_view_pan()
	queue_redraw()


func adjust_editor_zoom(factor: float) -> void:
	_zoom_editor_view_at(size * 0.5, factor)


func set_room_status_indicators(indicators: Dictionary) -> void:
	room_status_indicators = indicators.duplicate(true)
	queue_redraw()


func _input(event: InputEvent) -> void:
	if (
		editor_mode
		and is_visible_in_tree()
		and editor_dragging
		and not installed_drag_data.is_empty()
		and event is InputEventMouseMotion
		and ((event as InputEventMouseMotion).button_mask & MOUSE_BUTTON_MASK_LEFT) != 0
		and not get_global_rect().has_point((event as InputEventMouseMotion).position)
	):
		# Once an installed module leaves the workbench, hand it back to Godot's
		# normal drag/drop system so the shared locker and disposal chute remain
		# valid destinations. Internal moves never need this less-reliable path.
		var drag_room := _get_room_by_id(StringName(installed_drag_data.get("room_id", &"")))
		var preview: Control = ForgeInventoryPieceScript.new()
		var room_type := String(installed_drag_data.get("room_type", "UNASSIGNED"))
		var display_name := room_type.capitalize()
		var preview_color := Color(0.18, 0.5, 0.48, 1.0)
		if drag_room != null:
			display_name = String(drag_room.get("display_name"))
			preview_color = _inventory_color_for_room(drag_room)
		preview.call("configure", room_type, display_name, preview_color, inventory_piece_footprint)
		preview.set("drag_ghost", true)
		preview.custom_minimum_size = Vector2(inventory_piece_footprint) * 22.0
		preview.size = preview.custom_minimum_size
		preview.position = Vector2(8, 8)
		editor_dragging = false
		force_drag(installed_drag_data, preview)
		get_viewport().set_input_as_handled()
		return
	if (
		editor_mode
		and is_visible_in_tree()
		and event is InputEventMouseButton
		and (event as InputEventMouseButton).pressed
		and (event as InputEventMouseButton).button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]
		and get_global_rect().has_point((event as InputEventMouseButton).position)
	):
		var wheel_event := event as InputEventMouseButton
		_zoom_editor_view_at(
			get_local_mouse_position(),
			1.12 if wheel_event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.12
		)
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey:
		var key_event := event as InputEventKey
		if key_event.keycode == KEY_CTRL and key_event.pressed and not key_event.echo:
			show_all_indicators = not show_all_indicators
			show_all_weapon_envelopes = show_all_indicators
			queue_redraw()


func refresh_layout() -> void:
	for label: Label in generated_labels:
		if is_instance_valid(label):
			label.free()
	generated_labels.clear()
	module_piece_view_cache.clear()
	_update_canvas_size()
	_create_labels()
	if is_instance_valid(combat_overlay):
		combat_overlay.refresh_layout(ship_layout)
	if is_instance_valid(editor_deck_detail_visual):
		editor_deck_detail_visual.call("set_ship_layout", ship_layout)
	_sync_editor_deck_detail_visual()
	queue_redraw()


func _draw() -> void:
	var grid_size := Vector2(_columns() * CELL_SIZE, _rows() * CELL_SIZE)
	var hull_cells := _all_occupied_cells()
	var planning_alpha := 1.0 - _editor_deck_detail_mix()
	if editor_mode:
		draw_set_transform(editor_view_pan, 0.0, Vector2.ONE * editor_view_zoom)
	if not editor_mode and show_weapon_envelopes_outside_editor:
		_draw_weapon_envelopes()
	if _should_draw_power_field():
		_draw_power_network_overlay(true, false)

	if editor_mode and (inventory_piece_drag_active or inventory_piece_armed):
		# The drydock now exposes one stable quarter-module lattice rather than
		# overlapping whole/half offset guesses.
		var build_bounds: Rect2i = ship_layout.call("get_build_bounds")
		for lattice_y: int in range(build_bounds.position.y, build_bounds.end.y):
			for lattice_x: int in range(build_bounds.position.x, build_bounds.end.x):
				var lattice_rect := _get_candidate_grid_rect(Vector2i(lattice_x, lattice_y), Vector2.ZERO, Vector2i.ONE)
				draw_rect(lattice_rect.grow(-0.75), Color(editor_hover_valid_color, 0.035), true)
				draw_rect(lattice_rect.grow(-0.75), Color(editor_hover_valid_color, 0.13), false, 1.0)
		for candidate: Dictionary in _available_build_candidates(hull_cells):
			var build_cell: Vector2i = candidate["cell"]
			var build_offset: Vector2 = candidate["offset"]
			var build_rect := _get_candidate_grid_rect(build_cell, build_offset, inventory_piece_footprint)
			# Exact module clearance and power checks are reserved for the hovered
			# socket below. Re-running the complete ship analyzer for every outline
			# on every pointer frame was the dominant Forge slowdown.
			var candidate_color := editor_hover_valid_color if inventory_piece_install_allowed else editor_hover_blocked_color
			draw_rect(build_rect.grow(-1.0), Color(candidate_color, 0.065), true)
			draw_rect(build_rect.grow(-1.0), Color(candidate_color, 0.3), false, 1.0)
		if hovered_build_cell != INVALID_CELL:
			var hover_rect := _get_candidate_grid_rect(hovered_build_cell, hovered_build_offset, inventory_piece_footprint).grow(-2.0)
			var hover_is_valid := (
				inventory_piece_install_allowed
				and _installation_clearance_valid(hovered_build_cell, hovered_build_offset)
				and bool(ship_layout.call("is_cell_buildable", hovered_build_cell))
				and _can_place_active_footprint(hovered_build_cell, inventory_piece_footprint, hovered_build_offset)
			)
			var hover_color := editor_hover_valid_color if hover_is_valid else editor_hover_blocked_color
			draw_rect(hover_rect, Color(hover_color, 0.22), true)
			draw_rect(hover_rect, hover_color, false, 3.0)
			var notch_start := hover_rect.position + Vector2(5.0, 5.0)
			draw_line(notch_start, notch_start + Vector2(10.0, 0.0), hover_color.lightened(0.35), 2.0)
			if hovered_build_offset.x > 0.0:
				draw_line(notch_start, notch_start + Vector2(0.0, 10.0), hover_color.lightened(0.35), 2.0)
			if hovered_build_offset.y > 0.0:
				draw_line(notch_start + Vector2(0.0, 10.0), notch_start + Vector2(10.0, 10.0), hover_color.lightened(0.35), 2.0)

	for hull_cell_value: Variant in hull_cells.keys():
		var hull_cell: Vector2i = hull_cell_value
		draw_rect(_get_grid_rect(Rect2i(hull_cell, Vector2i.ONE)), Color(0.055, 0.075, 0.08, planning_alpha), true)

	for room: Resource in _rooms():
		for cell_value: Variant in _room_cells(room).keys():
			var cell: Vector2i = cell_value
			if _is_authored_quarter_room(room):
				continue
			var room_color: Color = room.get("color")
			draw_rect(_get_grid_rect(Rect2i(cell, Vector2i.ONE)), Color(room_color, room_color.a * planning_alpha), true)
	_draw_quarter_room_skins(planning_alpha)
	for room: Resource in _rooms():
		if not _is_authored_quarter_room(room):
			_draw_room_boundary(room, Color(0.62, 0.7, 0.68, 0.6 * planning_alpha), 2.0, hull_cells)
		if planning_alpha > 0.01:
			_draw_grouped_piece_dividers(room)
		if planning_alpha > 0.5 and String(room.get("type_name")) == "HANGAR":
			_draw_docked_fighters(room)
		if planning_alpha > 0.5 and String(room.get("type_name")) == "WEAPONS":
			_draw_weapon_operation(room, hull_cells)
		if room.get("room_id") == selected_room_id:
			if not editor_mode:
				_draw_room_boundary(room, Color(0.94, 0.72, 0.3, 0.95), 3.0, hull_cells)
		elif editor_mode and room.get("room_id") == hovered_room_id:
			_draw_room_boundary(room, editor_hover_valid_color, 3.0, hull_cells)
		if (
			editor_mode
			and String(room.get("type_name")) in ["PROPULSION", "WEAPONS", "HANGAR", "SHIELDS"]
		) or (
			_should_draw_indicators_for_room(room)
			and (room.get("type_name") in ["WEAPONS", "HANGAR", "DOCKING"] or room.get("module_recipe") != null)
		):
			if String(room.get("type_name")) in ["WEAPONS", "PROPULSION", "SHIELDS"]:
				for mount_room: Resource in _module_piece_views(room):
					if String(room.get("type_name")) == "WEAPONS" and _is_authored_quarter_room(mount_room):
						continue
					_draw_module_facing_indicator(mount_room, hull_cells)
			else:
				_draw_module_facing_indicator(room, hull_cells)
		# The Forge is editing an authored blueprint while the paused simulation
		# still describes the pre-refit ship. Applying that stale live status here
		# painted newly moved/added rooms as destroyed black rectangles over the
		# close-detail artwork.
		var simulation := get_tree().get_first_node_in_group("ship_simulation")
		if not editor_mode and is_instance_valid(simulation) and simulation.has_method("get_module_piece_status"):
			_draw_module_state(room, simulation, hull_cells)
		if not editor_mode and is_instance_valid(simulation) and simulation.get_room_health_percentage(room.get("room_id")) <= 0.001:
			var disabled_rect := _room_pixel_bounds(room).grow(-3.0)
			var warning_pulse := 0.72 + sin(Time.get_ticks_msec() * 0.009) * 0.22
			draw_rect(disabled_rect, Color(0.025, 0.01, 0.012, 0.82), true)
			draw_rect(disabled_rect, Color(1.0, 0.18, 0.08, warning_pulse), false, 3.0)
			draw_line(disabled_rect.position + Vector2(5.0, 5.0), disabled_rect.end - Vector2(5.0, 5.0), Color(1.0, 0.3, 0.08, warning_pulse), 2.0, true)
			draw_line(Vector2(disabled_rect.end.x - 5.0, disabled_rect.position.y + 5.0), Vector2(disabled_rect.position.x + 5.0, disabled_rect.end.y - 5.0), Color(1.0, 0.3, 0.08, warning_pulse), 2.0, true)
	if show_all_indicators or (editor_mode and free_blueprint_placement):
		_draw_power_network_overlay(false, true)
	if editor_mode and not installed_drag_data.is_empty():
		_draw_installed_piece_socket()
	if editor_mode and ship_layout != null and bool(ship_layout.get("core_frame_initialized")):
		var core_cells: Dictionary = {}
		for core_cell: Vector2i in ship_layout.get("core_frame_cells"):
			if hull_cells.has(core_cell):
				core_cells[core_cell] = true
		if not core_cells.is_empty():
			_draw_cell_set_boundary(core_cells, Color(0.5, 0.74, 0.76, 0.28), 5.0)
			_draw_cell_set_boundary(core_cells, Color(0.66, 0.86, 0.84, 0.62), 1.5)

	if editor_mode and selected_room_id != &"" and installed_drag_data.is_empty():
		var selected_hardware := _selected_hardware_view()
		if selected_hardware != null:
			# One combined room can contain several physical mounts. Selection is a
			# glow around the clicked piece itself—no bounding box or corner glyphs.
			_draw_room_boundary(selected_hardware, Color(0.18, 0.9, 1.0, 0.25), 9.0, hull_cells)
			_draw_room_boundary(selected_hardware, Color(0.42, 1.0, 0.96, 0.94), 3.0, hull_cells)
	elif editor_mode and not group_selection.is_empty():
		# Drag-selection is still a multi-piece operation, but it uses the same
		# contained outline language instead of a floating selection rectangle.
		_draw_cell_set_boundary(group_selection, Color(0.2, 0.92, 1.0, 0.18), 8.0)
		_draw_cell_set_boundary(group_selection, Color(0.42, 1.0, 0.96, 0.95), 3.0)
	if editor_mode and not editor_drag_selection.is_empty():
		for selected_cell_value: Variant in editor_drag_selection.keys():
			var selected_cell: Vector2i = selected_cell_value
			_draw_selection_brackets(
				_get_grid_rect(Rect2i(selected_cell, Vector2i.ONE)).grow(-4.0),
				Color(0.95, 0.72, 0.24, 0.95),
				2.0,
				8.0
			)
		_draw_cell_set_boundary(editor_drag_selection, Color(0.95, 0.72, 0.24, 0.95), 2.5)

	# Hull and room art are painted first. Door leaves are a deck fixture and must
	# sit above both; otherwise the close-view room walls completely cover them.
	_draw_special_exterior_profiles(
		hull_cells,
		Color(0.35, 0.48, 0.5, planning_alpha),
		3.0,
		false,
		planning_alpha
	)
	_draw_profiled_hull_boundary(hull_cells, Color(0.35, 0.48, 0.5, planning_alpha), 3.0)
	if show_all_indicators:
		_draw_hull_edge_indicators(hull_cells)
		_draw_room_synergy_links()
	elif hovered_room_id != &"":
		var hovered_room := _get_room_by_id(hovered_room_id)
		if hovered_room != null:
			_draw_hull_edge_indicators_for_cells(_room_cells(hovered_room), hull_cells)
	# Live pressure and structural state belongs to the running deck. The Damage
	# Lab explicitly opts back in; ordinary construction must show the blueprint.
	if not editor_mode or damage_lab_mode:
		_draw_pressure_and_structural_damage()
	if show_all_indicators:
		_draw_room_status_indicators()
	_draw_damage_lab_selection()
	if editor_mode and not installed_drag_data.is_empty():
		_draw_lifted_installed_piece()
	if not editor_mode:
		_draw_simulated_doors()
	# Blueprint/editor grids show the authored hull, not the live occupants whose
	# deck-space coordinates belong to the running ship view.
	if not editor_mode:
		_draw_crew_reinforcement_gauges()
		_draw_live_crew()
	if editor_mode:
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		# Targeting graphics are plotted in screen space after the scaled hull.
		# This keeps one-pixel strokes and terminal text crisp at every editor zoom.
		_draw_weapon_envelopes()


func _is_authored_quarter_room(room: Resource) -> bool:
	if not ROOM_STAFFING_RULES.is_unmanned_exterior_module(room):
		return false
	var rects: Array[Rect2i] = room.get("grid_rects")
	if rects.is_empty():
		return false
	for rect: Rect2i in rects:
		if rect.size != Vector2i.ONE:
			return false
	return true


## The Aseprite connector faces west/left. Every exterior module's saved
## facing points toward space, so its attachment points in the opposite quarter.
func _draw_quarter_room_skins(alpha: float = 1.0) -> void:
	var hull_cells := _all_occupied_cells()
	for room: Resource in _rooms():
		if not _is_authored_quarter_room(room):
			continue
		var rects: Array[Rect2i] = room.get("grid_rects")
		var facings: Array = room.get("module_mount_facings")
		for piece_index: int in range(rects.size()):
			var destination := _get_grid_rect(rects[piece_index])
			draw_texture_rect(QUARTER_ROOM_BASE, destination, false, Color(1.0, 1.0, 1.0, alpha))
			var facing := int(room.get("module_facing_quarters"))
			if piece_index < facings.size():
				facing = int(facings[piece_index])
			facing = posmod(facing, 4)
			var attachment_quarter := _quarter_attachment_quarter(rects[piece_index], room, facing, hull_cells)
			var connector_rotation := float(posmod(attachment_quarter - 3, 4)) * PI * 0.5
			_set_quarter_art_transform(destination.get_center(), connector_rotation)
			draw_texture_rect(QUARTER_ROOM_CONNECTOR, Rect2(-destination.size * 0.5, destination.size), false, Color(1.0, 1.0, 1.0, alpha))
			_restore_forge_canvas_transform()
			if String(room.get("type_name")) != "WEAPONS":
				continue
			var weapon: Resource = room.get("weapon_definition")
			if weapon == null or StringName(weapon.get("weapon_id")) != &"ballistic_repeater":
				continue
			var source_scale := destination.size.x / 80.0
			var weapon_rotation := PI + float(facing) * PI * 0.5
			_set_quarter_art_transform(destination.get_center(), weapon_rotation)
			draw_texture_rect(
				LIGHT_BALLISTIC_MOUNT,
				Rect2(Vector2(-32.0, -16.0) * source_scale, Vector2(48.0, 64.0) * source_scale),
				false,
				Color(1.0, 1.0, 1.0, alpha)
			)
			_restore_forge_canvas_transform()


## Local rotation for authored quarter-room layers must compose with the Forge's
## pan and zoom. Replacing that outer transform made every subsequent room in
## the same draw pass jump into a different coordinate space.
func _set_quarter_art_transform(content_center: Vector2, rotation_radians: float) -> void:
	if editor_mode:
		draw_set_transform(
			editor_view_pan + content_center * editor_view_zoom,
			rotation_radians,
			Vector2.ONE * editor_view_zoom
		)
		return
	draw_set_transform(content_center, rotation_radians, Vector2.ONE)


func _restore_forge_canvas_transform() -> void:
	if editor_mode:
		draw_set_transform(editor_view_pan, 0.0, Vector2.ONE * editor_view_zoom)
		return
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _quarter_attachment_quarter(
	piece_rect: Rect2i,
	room: Resource,
	outward_facing: int,
	hull_cells: Dictionary
) -> int:
	var room_cells := _room_cells(room)
	for quarter: int in range(4):
		var neighbor := piece_rect.position + GRID_GEOMETRY.quarter_direction(quarter)
		if hull_cells.has(neighbor) and not room_cells.has(neighbor):
			return quarter
	return posmod(outward_facing + 2, 4)


func _draw_module_state(room: Resource, simulation: Node, hull_cells: Dictionary) -> void:
	var rects: Array[Rect2i] = room.get("grid_rects")
	for index: int in range(rects.size()):
		var status: Dictionary = simulation.call("get_module_piece_status", room.get("room_id"), index)
		if status.is_empty():
			continue
		var ion_seconds := float(status.get("ion_seconds", 0.0))
		var health_ratio := float(status.get("health_ratio", 1.0))
		if ion_seconds <= 0.0 and health_ratio > 0.25:
			continue
		var piece := room.duplicate(false)
		piece.set("grid_rects", [rects[index]])
		piece.set("installed_piece_count", 1)
		var pulse := 0.68 + sin(float(Time.get_ticks_msec()) * 0.012) * 0.25
		var color := Color(0.18, 0.92, 1.0, pulse) if ion_seconds > 0.0 else Color(1.0, 0.24, 0.06, pulse)
		_draw_room_boundary(piece, Color(color, 0.16), 7.0, hull_cells)
		_draw_room_boundary(piece, color, 2.0, hull_cells)


func _draw_weapon_envelopes() -> void:
	if not editor_mode and not show_weapon_envelopes_outside_editor:
		return
	var weapon_rooms: Array[Resource] = []
	for source_room: Resource in _rooms():
		if String(source_room.get("type_name")) == "WEAPONS":
			weapon_rooms.append_array(_module_piece_views(source_room))
	for room: Resource in weapon_rooms:
		if String(room.get("type_name")) != "WEAPONS":
			continue
		if _is_dragged_hardware_view(room):
			continue
		var is_selected := _is_selected_hardware_view(room)
		if not is_selected and not show_all_weapon_envelopes:
			continue
		var weapon: Resource = room.get("weapon_definition")
		if weapon == null:
			continue
		var quarters := GRID_GEOMETRY.weapon_coverage_quarters(ship_layout, room, weapon)
		if quarters.is_empty():
			continue
		var weapon_color: Color = weapon.get("visual_color")
		var line_color := (
			Color(0.3, 1.0, 0.82, 0.94)
			if is_selected
			else Color(weapon_color.lerp(Color(0.24, 0.76, 0.7), 0.45), 0.34)
		)
		var fill_color := Color(line_color, 0.035 if is_selected else 0.012)
		var maximum_range := float(weapon.get("maximum_range"))
		# Tactical ranges are much larger than a drydock cell. This compressed
		# plotting scale keeps the envelope legible while preserving useful
		# differences between short-, medium-, and long-range mounts.
		var plotted_radius := _targeting_distance(
			clampf(maximum_range * 0.075, CELL_SIZE * 1.45, CELL_SIZE * 4.5)
		)
		if bool(weapon.get("uses_exposed_hull_edges")):
			_draw_continuous_gimbal_envelope(
				room,
				quarters,
				line_color,
				fill_color,
				plotted_radius,
				maximum_range,
				is_selected
			)
			continue
		var half_arc_degrees := float(weapon.get("traverse_degrees"))
		if half_arc_degrees <= 0.0:
			half_arc_degrees = 7.0
		var label_drawn := false
		for quarter: int in quarters:
			var direction := Vector2(GRID_GEOMETRY.quarter_direction(quarter))
			var mount_position := _targeting_point(_weapon_edge_center(room, quarter))
			var start_angle := direction.angle() - deg_to_rad(half_arc_degrees)
			var end_angle := direction.angle() + deg_to_rad(half_arc_degrees)
			var envelope := PackedVector2Array([mount_position])
			var point_count := 28
			for index: int in range(point_count + 1):
				var angle := lerpf(start_angle, end_angle, float(index) / float(point_count))
				envelope.append(mount_position + Vector2.RIGHT.rotated(angle) * plotted_radius)
			draw_colored_polygon(envelope, fill_color)
			_draw_dashed_targeting_line(mount_position, envelope[1], Color(line_color, line_color.a * 0.6), 1.0, 6.0)
			_draw_dashed_targeting_line(mount_position, envelope[envelope.size() - 1], Color(line_color, line_color.a * 0.6), 1.0, 6.0)
			_draw_dashed_targeting_line(
				mount_position + direction * 7.0,
				mount_position + direction * plotted_radius,
				Color(line_color, line_color.a * (0.72 if is_selected else 0.38)),
				1.0 if not is_selected else 1.5,
				7.0
			)
			var ring_ratios: Array[float] = [1.0]
			if is_selected:
				ring_ratios = [0.55, 1.0]
			for ring_ratio: float in ring_ratios:
				draw_arc(
					mount_position,
					plotted_radius * ring_ratio,
					start_angle,
					end_angle,
					point_count,
					Color(line_color, line_color.a * (1.0 if ring_ratio >= 0.99 else 0.42)),
					_targeting_stroke(2.0 if is_selected and ring_ratio >= 0.99 else 1.0),
					false
				)
			for tick_index: int in range(5):
				var tick_angle := lerpf(start_angle, end_angle, float(tick_index) / 4.0)
				var tick_direction := Vector2.RIGHT.rotated(tick_angle)
				var tick_outer := mount_position + tick_direction * plotted_radius
				var tick_inner := tick_outer - tick_direction * (5.0 if is_selected else 3.0)
				draw_line(
					tick_inner,
					tick_outer,
					line_color,
					_targeting_stroke(1.5 if is_selected else 1.0),
					false
				)
			_draw_targeting_mount_brackets(mount_position, line_color, is_selected)
			if is_selected and not label_drawn:
				var label_position := mount_position + direction * minf(
					plotted_radius * 0.72,
					_targeting_distance(CELL_SIZE * 3.2)
				)
				_draw_fixed_scale_range_label(label_position, maximum_range)
				label_drawn = true


func _draw_continuous_gimbal_envelope(
	room: Resource,
	quarters: Array[int],
	line_color: Color,
	fill_color: Color,
	plotted_radius: float,
	maximum_range: float,
	is_selected: bool
) -> void:
	var exposed := [false, false, false, false]
	for quarter: int in quarters:
		exposed[posmod(quarter, 4)] = true
	var runs: Array[Vector2i] = []
	if quarters.size() >= 4:
		runs.append(Vector2i(0, 4))
	else:
		for quarter: int in range(4):
			if not exposed[quarter] or exposed[posmod(quarter - 1, 4)]:
				continue
			var run_length := 1
			while run_length < 4 and exposed[posmod(quarter + run_length, 4)]:
				run_length += 1
			runs.append(Vector2i(quarter, run_length))
	var mount_position := _targeting_point(_room_pixel_bounds(room).get_center())
	var desired_half_degrees := clampf(maxf(float(room.get("weapon_definition").get("traverse_degrees")), 45.0), 0.0, 89.0)
	var label_drawn := false
	for run: Vector2i in runs:
		var first_quarter := posmod(run.x, 4)
		var last_quarter := posmod(run.x + run.y - 1, 4)
		var first_direction := Vector2(GRID_GEOMETRY.quarter_direction(first_quarter))
		var last_direction := Vector2(GRID_GEOMETRY.quarter_direction(last_quarter))
		var first_clearance: Vector2 = GRID_GEOMETRY.weapon_face_clearance_degrees(
			ship_layout, room, first_quarter, desired_half_degrees
		)
		var last_clearance: Vector2 = GRID_GEOMETRY.weapon_face_clearance_degrees(
			ship_layout, room, last_quarter, desired_half_degrees
		)
		var start_angle := (
			0.0
			if run.y >= 4
			else first_direction.angle() + deg_to_rad(first_clearance.x)
		)
		var end_angle := (
			TAU
			if run.y >= 4
			else last_direction.angle() + deg_to_rad(last_clearance.y)
		)
		while end_angle < start_angle:
			end_angle += TAU
		var point_count := maxi(run.y * 20, 24)
		var start_origin := _targeting_point(_weapon_edge_center(room, first_quarter))
		var end_origin := _targeting_point(_weapon_edge_center(room, last_quarter))
		var envelope := PackedVector2Array([start_origin])
		for index: int in range(point_count + 1):
			var angle := lerpf(start_angle, end_angle, float(index) / float(point_count))
			envelope.append(mount_position + Vector2.RIGHT.rotated(angle) * plotted_radius)
		envelope.append(end_origin)
		draw_colored_polygon(envelope, fill_color)
		var ring_ratios: Array[float] = [1.0]
		if is_selected:
			ring_ratios = [0.55, 1.0]
		for ring_ratio: float in ring_ratios:
			draw_arc(
				mount_position,
				plotted_radius * ring_ratio,
				start_angle,
				end_angle,
				point_count,
				Color(line_color, line_color.a * (1.0 if ring_ratio >= 0.99 else 0.42)),
				_targeting_stroke(2.0 if is_selected and ring_ratio >= 0.99 else 1.0),
				false
			)
		if run.y < 4:
			_draw_dashed_targeting_line(
				start_origin,
				mount_position + Vector2.RIGHT.rotated(start_angle) * plotted_radius,
				Color(line_color, line_color.a * 0.62),
				1.0,
				6.0
			)
			_draw_dashed_targeting_line(
				end_origin,
				mount_position + Vector2.RIGHT.rotated(end_angle) * plotted_radius,
				Color(line_color, line_color.a * 0.62),
				1.0,
				6.0
			)
		var tick_count := maxi(run.y * 4, 4)
		for tick_index: int in range(tick_count + 1):
			var tick_angle := lerpf(start_angle, end_angle, float(tick_index) / float(tick_count))
			var tick_direction := Vector2.RIGHT.rotated(tick_angle)
			var tick_outer := mount_position + tick_direction * plotted_radius
			draw_line(
				tick_outer - tick_direction * (5.0 if is_selected else 3.0),
				tick_outer,
				line_color,
				_targeting_stroke(1.5 if is_selected else 1.0),
				false
			)
		if is_selected and not label_drawn:
			var center_angle := lerpf(start_angle, end_angle, 0.5)
			var center_direction := Vector2.RIGHT.rotated(center_angle)
			var label_position := mount_position + center_direction * minf(
				plotted_radius * 0.72,
				_targeting_distance(CELL_SIZE * 3.2)
			)
			_draw_fixed_scale_range_label(label_position, maximum_range)
			label_drawn = true
	_draw_targeting_mount_brackets(mount_position, line_color, is_selected)


func _draw_fixed_scale_range_label(label_position: Vector2, maximum_range: float) -> void:
	# The deck camera scales this entire Control. Counter-scale only the terminal
	# label so its type remains one crisp screen-space size while its anchor stays
	# attached to the weapon in world space.
	var inherited_scale := get_global_transform().get_scale().abs()
	inherited_scale.x = maxf(inherited_scale.x, 0.001)
	inherited_scale.y = maxf(inherited_scale.y, 0.001)
	var global_anchor := get_global_transform() * label_position
	var snapped_anchor := get_global_transform().affine_inverse() * global_anchor.round()
	draw_set_transform(snapped_anchor, 0.0, Vector2.ONE / inherited_scale)
	var label_rect := Rect2(Vector2(-39.0, -10.0), Vector2(78.0, 20.0))
	draw_rect(label_rect, Color(0.008, 0.035, 0.034, 0.92), true)
	draw_rect(label_rect, Color(1.0, 0.66, 0.2, 0.9), false, 1.0, false)
	draw_string(
		get_theme_default_font(),
		Vector2(-35.0, 4.0),
		"RNG • %d" % roundi(maximum_range),
		HORIZONTAL_ALIGNMENT_CENTER,
		70.0,
		11,
		Color(1.0, 0.72, 0.28, 0.98)
	)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_dashed_targeting_line(
	start: Vector2,
	finish: Vector2,
	color: Color,
	width: float,
	dash_length: float
) -> void:
	var distance := start.distance_to(finish)
	if distance <= 0.001:
		return
	var direction := start.direction_to(finish)
	var cursor := 0.0
	while cursor < distance:
		var segment_end := minf(cursor + dash_length, distance)
		draw_line(
			start + direction * cursor,
			start + direction * segment_end,
			color,
			_targeting_stroke(width),
			false
		)
		cursor += dash_length * 1.8


func _draw_grouped_piece_dividers(room: Resource) -> void:
	var rects: Array[Rect2i] = room.get("grid_rects")
	if rects.size() <= 1:
		return
	var piece_by_cell: Dictionary = {}
	for piece_index: int in range(rects.size()):
		var rect := rects[piece_index]
		for y: int in range(rect.position.y, rect.end.y):
			for x: int in range(rect.position.x, rect.end.x):
				piece_by_cell[Vector2i(x, y)] = piece_index
	var underlay := Color(0.015, 0.035, 0.04, 0.48)
	var divider := Color(0.72, 0.86, 0.82, 0.72)
	for cell_value: Variant in piece_by_cell.keys():
		var cell: Vector2i = cell_value
		var piece_index := int(piece_by_cell[cell])
		var cell_rect := _get_grid_rect(Rect2i(cell, Vector2i.ONE))
		for direction: Vector2i in [Vector2i.RIGHT, Vector2i.DOWN]:
			var neighbor := cell + direction
			if not piece_by_cell.has(neighbor) or int(piece_by_cell[neighbor]) == piece_index:
				continue
			var start := Vector2(cell_rect.end.x, cell_rect.position.y) if direction == Vector2i.RIGHT else Vector2(cell_rect.position.x, cell_rect.end.y)
			var finish := cell_rect.end if direction == Vector2i.RIGHT else Vector2(cell_rect.end.x, cell_rect.end.y)
			draw_line(start, finish, underlay, 2.5, false)
			_draw_dashed_targeting_line(start, finish, divider, 1.2, 3.5)


func _targeting_stroke(requested_width: float) -> float:
	return requested_width


func _targeting_point(content_point: Vector2) -> Vector2:
	if not editor_mode:
		return content_point
	return editor_view_pan + content_point * editor_view_zoom


func _targeting_distance(content_distance: float) -> float:
	return content_distance * editor_view_zoom if editor_mode else content_distance


func _draw_targeting_mount_brackets(mount_position: Vector2, color: Color, is_selected: bool) -> void:
	var radius := 7.0 if is_selected else 5.0
	var arm := 3.0
	var bracket_color := Color(color, color.a * (1.0 if is_selected else 0.6))
	for corner: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		var point := mount_position + corner * radius
		draw_line(point, point - Vector2(corner.x, 0.0) * arm, bracket_color, _targeting_stroke(1.5), false)
		draw_line(point, point - Vector2(0.0, corner.y) * arm, bracket_color, _targeting_stroke(1.5), false)


func _weapon_edge_center(room: Resource, quarter: int) -> Vector2:
	var direction := GRID_GEOMETRY.quarter_direction(quarter)
	var hull_cells := GRID_GEOMETRY.layout_cells(ship_layout)
	var edge_centers: Array[Vector2] = []
	for cell_value: Variant in _room_cells(room).keys():
		var cell := cell_value as Vector2i
		if GRID_GEOMETRY.face_contact_strength(ship_layout, cell, direction, hull_cells) >= 0.999:
			continue
		edge_centers.append(_get_grid_rect(Rect2i(cell, Vector2i.ONE)).get_center() + Vector2(direction) * CELL_SIZE * 0.5)
	if edge_centers.is_empty():
		return _room_pixel_bounds(room).get_center()
	var center := Vector2.ZERO
	for edge_center: Vector2 in edge_centers:
		center += edge_center
	return center / float(edge_centers.size())


func _draw_live_crew() -> void:
	var crew := get_tree().get_first_node_in_group("crew_simulation")
	if not is_instance_valid(crew) or crew.crew_definition == null:
		return
	var radius := float(crew.crew_definition.get("settlement_dot_radius"))
	var scale_ratio := CELL_SIZE / 256.0
	var outline_width := maxf(float(crew.crew_definition.get("outline_width")) * scale_ratio, 0.5)
	var base_color: Color = crew.crew_definition.get("base_color")
	for member: Dictionary in crew.crew_members:
		if bool(member.get("ejected", false)) or int(member.get("carried_by", 0)) > 0:
			continue
		var point := _hull_pixel_origin() + (Vector2(member["position"]) - Vector2(_bounds().position)) * CELL_SIZE
		var dot_color := _crew_state_color(member, base_color).lightened(float(member["color_shift"]) * 0.35)
		var ring_color := _crew_state_ring_color(member, dot_color)
		var heading: Vector2 = member.get("facing_direction", Vector2.UP)
		if not _draw_crew_sprite(member, point, heading, crew.crew_definition):
			draw_circle(point, radius + outline_width + 1.0, Color(0.01, 0.02, 0.025, 0.95))
			draw_circle(point, radius + outline_width * 0.55, ring_color, false, maxf(outline_width, 0.75))
			draw_circle(point, radius, dot_color)
		elif bool(member.get("evacuating", false)) or int(member.get("active_job_id", 0)) > 0 or float(member.get("health", 100.0)) <= 25.0:
			draw_arc(point, radius + 2.5, 0.0, TAU, 16, ring_color, maxf(outline_width, 0.75), true)
		_draw_crew_spawn_effect(member, point)
	for job: Dictionary in crew.damage_control_jobs:
		var target: Dictionary = job["target"]
		var point := _hull_pixel_origin() + (Vector2(target["position"]) - Vector2(_bounds().position)) * CELL_SIZE
		var color := Color(1.0, 0.58, 0.18, 0.95) if String(job["state"]) != "REPAIRING" else Color(0.28, 1.0, 0.72, 0.95)
		draw_line(point + Vector2(-3, -3), point + Vector2(3, 3), color, 1.5, true)
		draw_line(point + Vector2(3, -3), point + Vector2(-3, 3), color, 1.5, true)
		draw_arc(point, 5.0, -PI * 0.5, -PI * 0.5 + TAU * float(job["progress"]), 12, color, 1.25, true)


func _draw_crew_reinforcement_gauges() -> void:
	var crew := get_tree().get_first_node_in_group("crew_simulation")
	if not is_instance_valid(crew) or not crew.has_method("get_reinforcement_status"):
		return
	var status: Dictionary = crew.call("get_reinforcement_status")
	if not bool(status.get("active", false)):
		return
	var duration: float = maxf(float(status.get("duration", 1.0)), 0.001)
	var remaining: float = float(status.get("remaining", duration))
	var progress: float = clampf(1.0 - remaining / duration, 0.0, 1.0)
	var pulse: float = 0.82 + sin(float(Time.get_ticks_msec()) * 0.012) * 0.12
	var gauge_color := Color(0.28, 1.0, 0.78, 0.94)
	if progress >= 0.88:
		gauge_color = Color(1.0, 0.76, 0.24, pulse)
	for room: Resource in _rooms():
		if String(room.get("type_name")) not in ["CREW", "CREW_QUARTERS"]:
			continue
		# A full Crew Quarters module occupies four quarter-lattice cells, but it is
		# still one room and owns one reinforcement cycle indicator.
		var center := _crew_reinforcement_gauge_anchor(room)
		if not center.is_finite():
			continue
		var radius := 4.5
		var segment_total := 8
		var completed_segments := clampi(ceili(progress * float(segment_total)), 0, segment_total)
		var segment_span := TAU / float(segment_total)
		var segment_gap := deg_to_rad(5.0)
		draw_circle(center, radius + 1.5, Color(0.008, 0.022, 0.024, 0.96), true)
		draw_circle(center, radius + 0.5, Color(0.08, 0.24, 0.22, 0.72), false, 1.0, false)
		for segment_index: int in range(segment_total):
			var start_angle := -PI * 0.5 + float(segment_index) * segment_span + segment_gap
			var end_angle := -PI * 0.5 + float(segment_index + 1) * segment_span - segment_gap
			var segment_color := gauge_color if segment_index < completed_segments else Color(0.08, 0.25, 0.23, 0.8)
			draw_arc(center, radius, start_angle, end_angle, 3, segment_color, 1.25, false)
		var sweep_angle := -PI * 0.5 + TAU * progress
		draw_line(center, center + Vector2.from_angle(sweep_angle) * 3.2, gauge_color, 1.0, false)
		draw_rect(Rect2(center - Vector2.ONE, Vector2(2.0, 2.0)), Color(gauge_color, 0.96), true)


func _crew_reinforcement_gauge_anchor(room: Resource) -> Vector2:
	# A merged room's bounding-box corner is not necessarily occupied (L/T shapes
	# are the common failure). Pick the uppermost real cell, preferring a cell with
	# the most same-room neighbours, and center the gauge inside that cell.
	var cells := _room_cells(room)
	if cells.is_empty():
		return Vector2(INF, INF)
	var best_cell := INVALID_CELL
	var best_row := 2147483647
	var best_neighbors := -1
	var best_column := 2147483647
	for cell_value: Variant in cells.keys():
		var cell: Vector2i = cell_value
		var neighbors := 0
		for direction: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			if cells.has(cell + direction):
				neighbors += 1
		if (
			cell.y < best_row
			or (cell.y == best_row and neighbors > best_neighbors)
			or (cell.y == best_row and neighbors == best_neighbors and cell.x < best_column)
		):
			best_cell = cell
			best_row = cell.y
			best_neighbors = neighbors
			best_column = cell.x
	if best_cell == INVALID_CELL:
		return Vector2(INF, INF)
	return _get_grid_rect(Rect2i(best_cell, Vector2i.ONE)).get_center().round()


func _draw_crew_spawn_effect(member: Dictionary, point: Vector2) -> void:
	var remaining: float = float(member.get("spawn_visual_remaining", 0.0))
	if remaining <= 0.0:
		return
	var duration: float = maxf(float(member.get("spawn_visual_duration", 1.0)), 0.001)
	var progress: float = clampf(1.0 - remaining / duration, 0.0, 1.0)
	var fade: float = clampf(remaining / minf(duration, 0.45), 0.0, 1.0)
	var pulse: float = 0.72 + sin(float(Time.get_ticks_msec()) * 0.025) * 0.2
	var signal_color := Color(0.28, 1.0, 0.82, fade * pulse)
	var effect_radius := lerpf(8.0, 4.5, progress)
	draw_circle(point, effect_radius + 2.0, Color(signal_color, 0.055), true)
	draw_arc(point, effect_radius, -PI * 0.5, -PI * 0.5 + TAU * progress, 20, signal_color, 1.25, true)
	var scan_y := lerpf(-7.0, 7.0, progress)
	draw_line(point + Vector2(-5.0, scan_y), point + Vector2(5.0, scan_y), Color(signal_color, fade), 1.0, false)
	for corner: Vector2 in [Vector2(-1.0, -1.0), Vector2(1.0, -1.0), Vector2(1.0, 1.0), Vector2(-1.0, 1.0)]:
		var corner_point := point + corner * effect_radius
		draw_line(corner_point, corner_point - Vector2(corner.x, 0.0) * 2.5, signal_color, 1.0, false)
		draw_line(corner_point, corner_point - Vector2(0.0, corner.y) * 2.5, signal_color, 1.0, false)


func _draw_crew_sprite(member: Dictionary, point: Vector2, heading: Vector2, definition: Resource) -> bool:
	var sprite_sheet: Texture2D = definition.get("sprite_sheet")
	if sprite_sheet == null:
		return false
	var frame_size: Vector2i = definition.get("sprite_frame_size")
	if frame_size.x <= 0 or frame_size.y <= 0:
		return false
	var animation_name := _crew_animation_name(member)
	var frame_range: Vector2i = CREW_ANIMATION_RANGES.get(animation_name, CREW_ANIMATION_RANGES["Idle"])
	var frame_count := frame_range.y - frame_range.x + 1
	var phase_ms := int(member.get("id", 0)) * 37
	var frame_offset := int((Time.get_ticks_msec() + phase_ms) / CREW_FRAME_DURATION_MS) % frame_count
	if animation_name == "Die":
		frame_offset = mini(int(float(member.get("incapacitated_seconds", 0.0)) * 1000.0 / CREW_FRAME_DURATION_MS), frame_count - 1)
	var frame_index := frame_range.x + frame_offset
	var source_rect := Rect2(Vector2(frame_index * frame_size.x, 0.0), Vector2(frame_size))
	var deck_scale := CELL_SIZE / 256.0
	var draw_size := Vector2(frame_size) * float(definition.get("sprite_scale")) * deck_scale
	if animation_name == "Rest":
		draw_size *= float(definition.get("rest_sprite_scale_multiplier"))
	var rotation := heading.angle() + PI * 0.5 if not heading.is_zero_approx() else 0.0
	var draw_point := point
	if animation_name == "Rest":
		var rest_offset_ratio: Vector2 = definition.get("rest_sprite_offset_ratio")
		draw_point += Vector2(
			rest_offset_ratio.x * draw_size.x,
			rest_offset_ratio.y * draw_size.y
		).rotated(rotation)
	draw_set_transform(draw_point, rotation)
	draw_texture_rect_region(sprite_sheet, Rect2(-draw_size * 0.5, draw_size), source_rect)
	draw_set_transform(Vector2.ZERO, 0.0)
	return true


func _crew_animation_name(member: Dictionary) -> String:
	var state := String(member.get("state", ""))
	if bool(member.get("incapacitated", false)) or bool(member.get("dead", false)):
		return "Die"
	if bool(member.get("resting", false)) or state == "RESTING":
		return "Rest"
	if state == "MOVING":
		return "Walk"
	var repairing := int(member.get("active_job_id", 0)) > 0 and bool(member.get("at_job", false))
	var working := bool(member.get("at_assignment", false)) or state in ["WORKING", "MANNING", "OUTFITTING", "SECURITY WATCH", "SECURITY PATROL"]
	return "Pistol_idle" if repairing or working else "Idle"


func _draw_room_status_indicators() -> void:
	if room_status_indicators.is_empty():
		return
	for room: Resource in _rooms():
		var room_id: StringName = room.get("room_id")
		if not room_status_indicators.has(room_id):
			continue
		var indicator: Dictionary = room_status_indicators[room_id]
		var indicator_cell := _room_indicator_cell(room)
		if indicator_cell == INVALID_CELL:
			continue
		var state := String(indicator.get("state", "NOMINAL"))
		var color := _status_color_for_state(state)
		var cell_rect := _get_grid_rect(Rect2i(indicator_cell, Vector2i.ONE))
		var pip_center := cell_rect.position + Vector2(7.0, 7.0)
		draw_circle(pip_center, 5.0, Color(0.01, 0.018, 0.02, 0.95))
		draw_circle(pip_center, 3.2, color)
		if bool(indicator.get("crew_en_route", false)):
			var crew_pip := pip_center + Vector2(8.5, 0.0)
			draw_circle(crew_pip, 4.0, Color(0.01, 0.018, 0.02, 0.95))
			draw_circle(crew_pip, 2.35, crew_en_route_status_color)


func _draw_room_synergy_links() -> void:
	if ship_layout == null or not ship_layout.has_method("collect_adjacency_effects"):
		return
	var effects: Array[Dictionary] = ship_layout.call("collect_adjacency_effects")
	for entry: Dictionary in effects:
		var source := entry.get("source") as Resource
		var target := entry.get("target") as Resource
		var effect := entry.get("effect") as Resource
		if source == null or target == null or effect == null:
			continue
		var source_center := _room_visual_center(source)
		var target_center := _room_visual_center(target)
		var link_vector := target_center - source_center
		var link_length := link_vector.length()
		if link_length < 8.0:
			continue
		var direction := link_vector / link_length
		var endpoint_padding := minf(13.0, link_length * 0.22)
		var start := source_center + direction * endpoint_padding
		var finish := target_center - direction * endpoint_padding
		var color := _adjacency_link_color(int(effect.get("effect_kind")))
		draw_line(start, finish, Color(color, 0.18), 6.0, true)
		draw_line(start, finish, color, 2.0, true)
		var arrow_length := minf(8.0, link_length * 0.18)
		var arrow_left := finish - direction.rotated(0.58) * arrow_length
		var arrow_right := finish - direction.rotated(-0.58) * arrow_length
		draw_colored_polygon(PackedVector2Array([finish, arrow_left, arrow_right]), color)
		var pulse_center := start.lerp(finish, 0.5)
		draw_circle(pulse_center, 3.0, Color(0.01, 0.02, 0.025, 0.95))
		draw_circle(pulse_center, 1.75, color)


func _room_visual_center(room: Resource) -> Vector2:
	var cells := _room_cells(room)
	if cells.is_empty():
		return Vector2.ZERO
	var center := Vector2.ZERO
	for cell_value: Variant in cells.keys():
		center += _get_grid_rect(Rect2i(cell_value, Vector2i.ONE)).get_center()
	return center / float(cells.size())


func _adjacency_link_color(effect_kind: int) -> Color:
	match effect_kind:
		1:
			return interference_link_color
		2:
			return neutral_link_color
		_:
			return synergy_link_color


func status_color_for_state(state: String) -> Color:
	return _status_color_for_state(state)


func _room_indicator_cell(room: Resource) -> Vector2i:
	var cells := _room_cells(room)
	if cells.is_empty():
		return INVALID_CELL
	var best_cell := INVALID_CELL
	var best_score := INF
	for cell_value: Variant in cells.keys():
		var cell: Vector2i = cell_value
		var rect := _get_grid_rect(Rect2i(cell, Vector2i.ONE))
		var score := rect.position.x + rect.position.y * 10000.0
		if score < best_score:
			best_score = score
			best_cell = cell
	return best_cell


func _status_color_for_state(state: String) -> Color:
	match state:
		"BREACH", "NO AIR", "DANGER", "SYSTEM DOWN":
			return status_danger_color
		"DAMAGED", "REPAIRING":
			return status_damaged_color
		"NOMINAL":
			return status_nominal_color
		_:
			return status_degraded_color


func _crew_state_color(member: Dictionary, base_color: Color) -> Color:
	var state := String(member.get("state", ""))
	if bool(member.get("evacuating", false)) or float(member.get("health", 100.0)) <= 25.0:
		return Color(1.0, 0.22, 0.18, 0.96)
	if int(member.get("active_job_id", 0)) > 0:
		return Color(1.0, 0.6, 0.2, 0.96)
	if state.contains("WAIT"):
		return Color(0.46, 0.52, 0.52, 0.86)
	if not bool(member.get("at_assignment", false)) and StringName(member.get("assigned_room_id", &"")) != &"":
		return Color(1.0, 0.86, 0.28, 0.96)
	if bool(member.get("at_assignment", false)):
		return Color(0.35, 1.0, 0.72, 0.96)
	return base_color


func _crew_state_ring_color(member: Dictionary, dot_color: Color) -> Color:
	if bool(member.get("evacuating", false)) or float(member.get("health", 100.0)) <= 25.0:
		return Color(1.0, 0.1, 0.08, 0.95)
	if int(member.get("active_job_id", 0)) > 0:
		return Color(1.0, 0.58, 0.18, 0.92)
	if not bool(member.get("at_assignment", false)) and StringName(member.get("assigned_room_id", &"")) != &"":
		return Color(1.0, 0.82, 0.22, 0.88)
	return Color(dot_color, 0.72)


func _draw_simulated_doors() -> void:
	var structure := _get_player_structure()
	if structure == null or structure.door_definition == null:
		return
	var bounds := _bounds()
	for door_value: Variant in structure.doors.values():
		var door: Dictionary = door_value
		var start := _hull_pixel_origin() + (Vector2(door["start"]) - Vector2(bounds.position)) * CELL_SIZE
		var finish := _hull_pixel_origin() + (Vector2(door["end"]) - Vector2(bounds.position)) * CELL_SIZE
		DOOR_VISUALS.draw_door(
			self,
			start,
			finish,
			float(door["openness"]),
			bool(door["locked"]) or bool(door["pressure_interlocked"])
		)


func _get_player_structure() -> ShipStructuralState:
	var combat := get_tree().get_first_node_in_group("combat_simulation")
	if not is_instance_valid(combat):
		return null
	return combat.call("get_structural_state", 0, 0)


func _structural_wall_at_position(local_position: Vector2) -> String:
	var structure := _get_player_structure()
	if structure == null:
		return ""
	var closest_key := ""
	var closest_distance := 9.0
	var bounds := _bounds()
	for wall_value: Variant in structure.walls.values():
		var wall: Dictionary = wall_value
		var start := _hull_pixel_origin() + (Vector2(wall["start"]) - Vector2(bounds.position)) * CELL_SIZE
		var finish := _hull_pixel_origin() + (Vector2(wall["end"]) - Vector2(bounds.position)) * CELL_SIZE
		var closest := Geometry2D.get_closest_point_to_segment(local_position, start, finish)
		var distance := local_position.distance_to(closest)
		if distance < closest_distance:
			closest_distance = distance
			closest_key = String(wall["key"])
	return closest_key


func _draw_damage_lab_selection() -> void:
	if not damage_lab_mode:
		return
	var structure := _get_player_structure()
	if structure == null:
		return
	var bounds := _bounds()
	for key: String in [selected_structural_wall, hovered_structural_wall]:
		if key.is_empty() or not structure.walls.has(key):
			continue
		var wall: Dictionary = structure.walls[key]
		var start := _hull_pixel_origin() + (Vector2(wall["start"]) - Vector2(bounds.position)) * CELL_SIZE
		var finish := _hull_pixel_origin() + (Vector2(wall["end"]) - Vector2(bounds.position)) * CELL_SIZE
		var color := Color(1.0, 0.28, 0.16, 1.0) if key == selected_structural_wall else Color(0.35, 1.0, 0.95, 0.95)
		draw_line(start, finish, color, 8.0 if key == selected_structural_wall else 6.0, false)


func _draw_pressure_and_structural_damage() -> void:
	var combat := get_tree().get_first_node_in_group("combat_simulation")
	if not is_instance_valid(combat):
		return
	var structure: ShipStructuralState = combat.call("get_structural_state", 0, 0)
	if structure == null or structure.material == null:
		return
	for cell_value: Variant in structure.cell_pressure.keys():
		var cell: Vector2i = cell_value
		var pressure := structure.get_cell_pressure(cell)
		if pressure < 0.99:
			draw_rect(_get_grid_rect(Rect2i(cell, Vector2i.ONE)).grow(-3.0), Color(0.04, 0.2, 0.3, (1.0 - pressure) * 0.42), true)
	var bounds := _bounds()
	for wall_value: Variant in structure.walls.values():
		var wall: Dictionary = wall_value
		var start := _hull_pixel_origin() + (Vector2(wall["start"]) - Vector2(bounds.position)) * CELL_SIZE
		var finish := _hull_pixel_origin() + (Vector2(wall["end"]) - Vector2(bounds.position)) * CELL_SIZE
		if bool(wall["breached"]):
			draw_line(start, finish, Color(0.008, 0.012, 0.015), 7.0, false)
			draw_circle(start, 3.0, structure.material.get("breach_marker_color"))
			draw_circle(finish, 3.0, structure.material.get("breach_marker_color"))
			if bool(wall["outer"]):
				_draw_breach_atmosphere_jet(wall, start, finish, structure)
		else:
			var health: float = float(wall["current"]) / maxf(float(wall["maximum"]), 0.001)
			if health < 0.999:
				var color: Color = structure.material.get("damaged_wall_color").lerp(structure.material.get("healthy_wall_color"), health)
				draw_line(start, finish, color, 5.0, false)


func _draw_breach_atmosphere_jet(wall: Dictionary, start: Vector2, finish: Vector2, structure: ShipStructuralState) -> void:
	var cells: Array = wall["cells"]
	if cells.is_empty():
		return
	var pressure := structure.get_cell_pressure(cells[0])
	if pressure <= 0.01:
		return
	var mouth := start.lerp(finish, 0.5)
	var cell_center := _get_grid_rect(Rect2i(cells[0], Vector2i.ONE)).get_center()
	var outward := cell_center.direction_to(mouth)
	var phase := Time.get_ticks_msec() * 0.001
	for index: int in range(breach_jet_particles):
		var speed := 0.65 + fposmod(sin(float(index) * 41.73) * 9182.31, 1.0) * 0.85
		var progress := fposmod(phase * speed + float(index) / breach_jet_particles, 1.0)
		var spread_seed := sin(float(index) * 12.9898 + 4.21)
		var particle_direction := outward.rotated(spread_seed * breach_jet_spread)
		var tangent := particle_direction.orthogonal()
		var curl := sin(phase * (4.0 + speed) + index * 2.37) * breach_jet_length * 0.12 * progress * progress
		var travel := breach_jet_length * progress * (0.72 + speed * 0.28)
		var point := mouth + particle_direction * travel + tangent * curl
		var alpha := breach_jet_color.a * pressure * (1.0 - progress) * (0.55 + speed * 0.3)
		var color := Color(breach_jet_color, alpha)
		var streak := particle_direction * (2.0 + speed * 2.2) * (1.0 - progress)
		draw_line(point - streak, point, color, maxf(0.65, 1.25 - progress * 0.5), true)
		if index % 3 == 0:
			draw_circle(point, 1.7 - progress * 0.75, color)


func _draw_docked_fighters(room: Resource) -> void:
	var combat := get_tree().get_first_node_in_group("combat_simulation")
	if not is_instance_valid(combat):
		return
	var craft: Array[Dictionary] = combat.call("get_hangar_craft", 0, 0, room.get("room_id"), true)
	var center := _room_pixel_bounds(room).get_center()
	var offsets := [Vector2(-7.0, -7.0), Vector2(7.0, -7.0), Vector2(-7.0, 7.0), Vector2(7.0, 7.0)]
	for index: int in range(mini(craft.size(), offsets.size())):
		var point: Vector2 = center + offsets[index]
		draw_colored_polygon(PackedVector2Array([point + Vector2(0, -5), point + Vector2(4, 4), point, point + Vector2(-4, 4)]), Color(0.72, 0.94, 0.92, 0.95))


func _draw_weapon_operation(room: Resource, hull_cells: Dictionary) -> void:
	var combat := get_tree().get_first_node_in_group("combat_simulation")
	if not is_instance_valid(combat):
		return
	var state: Dictionary = combat.call("get_weapon_operation_state", 0, 0, room.get("room_id"))
	for mount_room: Resource in _module_piece_views(room):
		var center := _room_pixel_bounds(mount_room).get_center()
		var direction := _module_facing_direction(mount_room, _room_cells(mount_room), hull_cells)
		if String(state["state"]) == "FIRING":
			var muzzle := center + direction * 13.0
			draw_colored_polygon(PackedVector2Array([muzzle, muzzle + direction.rotated(-0.35) * 13.0, muzzle + direction * 19.0, muzzle + direction.rotated(0.35) * 13.0]), Color(1.0, 0.78, 0.24, 0.95))
		elif String(state["state"]) == "RELOADING":
			var total := maxf(float(state["reload_total"]), 0.001)
			var progress := 1.0 - float(state["reload_remaining"]) / total
			draw_arc(center, 10.0, -PI * 0.5, -PI * 0.5 + TAU * progress, 16, Color(0.95, 0.58, 0.22, 0.9), 2.0)


func _create_labels() -> void:
	# Travel direction is conveyed by the view-level moving starfield.
	pass


func _add_label(label_text: String, label_rect: Rect2, color: Color, font_size: int) -> void:
	var label := Label.new()
	label.text = label_text
	label.position = label_rect.position
	label.size = label_rect.size
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_size_override("font_size", font_size)
	add_child(label)
	generated_labels.append(label)


func _update_room_hover(mouse_position: Vector2) -> void:
	for room: Resource in _rooms():
		for cell_value: Variant in _room_cells(room).keys():
			if _get_grid_rect(Rect2i(cell_value, Vector2i.ONE)).has_point(mouse_position):
				room_hovered.emit(room.get("display_name"), _room_pixel_bounds(room).get_center())
				return
	room_hover_exited.emit()


func _update_hovered_room_id(mouse_position: Vector2) -> void:
	var next_hovered_id := StringName()
	for room: Resource in _rooms():
		for cell_value: Variant in _room_cells(room).keys():
			if _get_grid_rect(Rect2i(cell_value, Vector2i.ONE)).has_point(mouse_position):
				next_hovered_id = room.get("room_id")
				break
		if next_hovered_id != &"":
			break
	if hovered_room_id != next_hovered_id:
		hovered_room_id = next_hovered_id
		queue_redraw()


func _on_mouse_exited() -> void:
	if hovered_room_id != &"":
		hovered_room_id = &""
	hovered_build_cell = INVALID_CELL
	hovered_build_offset = Vector2.ZERO
	queue_redraw()
	room_hover_exited.emit()


func _should_draw_indicators_for_room(room: Resource) -> bool:
	return show_all_indicators or room.get("room_id") == hovered_room_id


func _get_room_by_id(room_id: StringName) -> Resource:
	for room: Resource in _rooms():
		if room.get("room_id") == room_id:
			return room
	return null


func _room_pixel_bounds(room: Resource) -> Rect2:
	var rects := _room_rects(room)
	if rects.is_empty():
		return Rect2()
	var combined := _get_grid_rect(rects[0])
	for index: int in range(1, rects.size()):
		combined = combined.merge(_get_grid_rect(rects[index]))
	return combined


func _cell_set_pixel_bounds(cells: Dictionary) -> Rect2:
	if cells.is_empty():
		return Rect2()
	var values: Array = cells.keys()
	var combined := _get_grid_rect(Rect2i(values[0], Vector2i.ONE))
	for index: int in range(1, values.size()):
		combined = combined.merge(_get_grid_rect(Rect2i(values[index], Vector2i.ONE)))
	return combined


func _largest_rect(rects: Array[Rect2i]) -> Rect2i:
	var largest := rects[0]
	for candidate: Rect2i in rects:
		if candidate.get_area() > largest.get_area():
			largest = candidate
	return largest


func _room_cells(room: Resource) -> Dictionary:
	var occupied_cells: Dictionary = {}
	for grid_rect: Rect2i in _room_rects(room):
		for y: int in range(grid_rect.position.y, grid_rect.end.y):
			for x: int in range(grid_rect.position.x, grid_rect.end.x):
				occupied_cells[Vector2i(x, y)] = true
	return occupied_cells


func _module_piece_views(room: Resource) -> Array[Resource]:
	var rects: Array[Rect2i] = room.get("grid_rects")
	var views: Array[Resource] = []
	if maxi(int(room.get("installed_piece_count")), 1) <= 1 or rects.size() <= 1:
		views.append(room)
		return views
	var facings: Array = room.get("module_mount_facings")
	for index: int in range(rects.size()):
		var facing := int(room.get("module_facing_quarters"))
		if index < facings.size():
			facing = int(facings[index])
		var key := "%d:%d:%s:%d" % [room.get_instance_id(), index, str(rects[index]), facing]
		var view: Resource = module_piece_view_cache.get(key)
		if view == null or not is_instance_valid(view):
			view = room.duplicate(false)
			var one_rect: Array[Rect2i] = [rects[index]]
			view.set("grid_rects", one_rect)
			view.set("module_facing_quarters", facing)
			view.set("installed_piece_count", 1)
			module_piece_view_cache[key] = view
		views.append(view)
	return views


func _room_lattice_footprint(room: Resource) -> Vector2i:
	var cells := _room_cells(room)
	if cells.is_empty():
		return Vector2i.ONE
	var minimum := Vector2i(2147483647, 2147483647)
	var maximum := Vector2i(-2147483648, -2147483648)
	for cell_value: Variant in cells.keys():
		var cell: Vector2i = cell_value
		minimum.x = mini(minimum.x, cell.x)
		minimum.y = mini(minimum.y, cell.y)
		maximum.x = maxi(maximum.x, cell.x)
		maximum.y = maxi(maximum.y, cell.y)
	return maximum - minimum + Vector2i.ONE


func _room_piece_lattice_footprint(room: Resource, cell: Vector2i) -> Vector2i:
	if room != null:
		for rect: Rect2i in room.get("grid_rects"):
			if rect.has_point(cell):
				return rect.size
	return _room_lattice_footprint(room)


func _room_piece_lattice_rect(room: Resource, cell: Vector2i) -> Rect2i:
	if room != null:
		for rect: Rect2i in room.get("grid_rects"):
			if rect.has_point(cell):
				return rect
	return Rect2i(cell, _room_lattice_footprint(room))


func _draw_installed_piece_socket() -> void:
	var source_rect: Rect2i = installed_drag_data.get("source_rect", Rect2i())
	if source_rect.size.x <= 0 or source_rect.size.y <= 0:
		return
	var socket := _get_grid_rect(source_rect).grow(-1.5)
	var source_room := _get_room_by_id(StringName(installed_drag_data.get("room_id", &"")))
	var module_color := _inventory_color_for_room(source_room) if source_room != null else Color(0.24, 0.5, 0.48)
	var phase_wave := (sin(float(Time.get_ticks_msec()) * 0.012) + 1.0) * 0.5
	var phase_alpha := lerpf(0.42, 0.68, phase_wave)
	if installed_drag_returning:
		phase_alpha = minf(phase_alpha + 0.18, 0.92)
	# The original compartment is deliberately blanked while its hardware is in
	# hand, but a low-energy afterimage preserves exactly where it came from.
	draw_rect(socket, Color(0.006, 0.022, 0.024, 0.94), true)
	draw_rect(socket.grow(-1.0), Color(module_color, 0.07 + phase_wave * 0.035), true)
	var scan_y := socket.position.y + 3.0
	while scan_y < socket.end.y - 2.0:
		draw_line(
			Vector2(socket.position.x + 2.0, scan_y),
			Vector2(socket.end.x - 2.0, scan_y),
			Color(module_color, 0.07 + phase_wave * 0.035),
			1.0
		)
		scan_y += 4.0
	var phase_color := Color(0.42, 1.0, 0.88, phase_alpha)
	_draw_phase_edge(socket.position, Vector2(socket.end.x, socket.position.y), phase_color)
	_draw_phase_edge(Vector2(socket.end.x, socket.position.y), socket.end, phase_color)
	_draw_phase_edge(socket.end, Vector2(socket.position.x, socket.end.y), phase_color)
	_draw_phase_edge(Vector2(socket.position.x, socket.end.y), socket.position, phase_color)
	draw_rect(socket.grow(-2.5), Color(module_color, phase_alpha * 0.42), false, 1.0)
	var corner := minf(7.0, minf(socket.size.x, socket.size.y) * 0.2)
	var socket_color := Color(0.58, 1.0, 0.9, phase_alpha)
	for point: Vector2 in [socket.position, Vector2(socket.end.x, socket.position.y), socket.end, Vector2(socket.position.x, socket.end.y)]:
		var horizontal_sign := 1.0 if is_equal_approx(point.x, socket.position.x) else -1.0
		var vertical_sign := 1.0 if is_equal_approx(point.y, socket.position.y) else -1.0
		draw_line(point, point + Vector2(horizontal_sign * corner, 0.0), socket_color, 2.0)
		draw_line(point, point + Vector2(0.0, vertical_sign * corner), socket_color, 2.0)


func _draw_phase_edge(from: Vector2, to: Vector2, color: Color) -> void:
	var edge_length := from.distance_to(to)
	if edge_length <= 0.01:
		return
	var direction := (to - from) / edge_length
	var edge_cursor := 0.0
	while edge_cursor < edge_length:
		var segment_end := minf(edge_cursor + 3.5, edge_length)
		draw_line(from + direction * edge_cursor, from + direction * segment_end, color, 1.4)
		edge_cursor += 6.5


func _draw_lifted_installed_piece() -> void:
	if installed_drag_pointer_position == Vector2.INF:
		return
	var footprint: Vector2i = installed_drag_data.get("footprint", Vector2i.ONE)
	var piece_size := Vector2(footprint) * CELL_SIZE
	var top_left := installed_drag_pointer_position - installed_drag_grab_offset
	var piece_rect := Rect2(top_left, piece_size).grow(-1.5)
	var source_room := _get_room_by_id(StringName(installed_drag_data.get("room_id", &"")))
	var piece_color := _inventory_color_for_room(source_room) if source_room != null else Color(0.24, 0.5, 0.48)
	# A small offset shadow and bright lower rim sell the sense that this physical
	# module has lifted clear of the hull instead of becoming a cursor icon.
	draw_rect(Rect2(piece_rect.position + Vector2(4.0, 5.0), piece_rect.size), Color(0.0, 0.0, 0.0, 0.46), true)
	draw_rect(piece_rect, Color(piece_color, 0.96), true)
	draw_rect(piece_rect, Color(0.48, 1.0, 0.9, 0.98), false, 2.0)
	draw_line(
		Vector2(piece_rect.position.x + 3.0, piece_rect.end.y - 2.0),
		Vector2(piece_rect.end.x - 3.0, piece_rect.end.y - 2.0),
		Color(1.0, 0.66, 0.22, 0.92),
		2.0
	)
	var center := piece_rect.get_center()
	var circuit_color := Color(0.04, 0.16, 0.16, 0.82)
	draw_circle(center, minf(5.0, minf(piece_rect.size.x, piece_rect.size.y) * 0.16), circuit_color, false, 1.5)
	draw_line(center - Vector2(7.0, 0.0), center + Vector2(7.0, 0.0), circuit_color, 1.0)


func _is_dragged_hardware_view(room: Resource) -> bool:
	if installed_drag_data.is_empty() or room == null:
		return false
	if StringName(room.get("room_id")) != StringName(installed_drag_data.get("room_id", &"")):
		return false
	var source_rect: Rect2i = installed_drag_data.get("source_rect", Rect2i())
	for rect: Rect2i in _room_rects(room):
		if rect == source_rect:
			return true
	return false


func _room_at_cell(cell: Vector2i) -> Resource:
	for room: Resource in _rooms():
		if _room_cells(room).has(cell):
			return room
	return null


func _all_occupied_cells() -> Dictionary:
	var occupied_cells: Dictionary = {}
	for room: Resource in _rooms():
		occupied_cells.merge(_room_cells(room), true)
	return occupied_cells


func _adjacent_build_cells(hull_cells: Dictionary) -> Dictionary:
	var build_cells: Dictionary = {}
	var build_bounds: Rect2i = ship_layout.call("get_build_bounds")
	for y: int in range(build_bounds.position.y, build_bounds.end.y):
		for x: int in range(build_bounds.position.x, build_bounds.end.x):
			var cell := Vector2i(x, y)
			if not hull_cells.has(cell) and _cell_touches_hull(cell, hull_cells):
				build_cells[cell] = true
	return build_cells


func _available_build_candidates(hull_cells: Dictionary) -> Array[Dictionary]:
	var candidates: Array[Dictionary] = []
	var build_bounds: Rect2i = ship_layout.call("get_build_bounds")
	var candidate_cells: Dictionary = {}
	var footprint := inventory_piece_footprint
	# The full lattice is already drawn beneath the cursor in free-layout Forge
	# mode. Avoid generating hundreds of redundant socket rectangles every frame.
	if free_blueprint_placement:
		return candidates
	# A brand-new blueprint has no hull edge from which to generate adjacent
	# sockets. Give it one stable keel socket at the center of its authorized
	# frame. After that first module is installed, normal edge attachment rules
	# immediately take over.
	if hull_cells.is_empty():
		var bootstrap_cell := build_bounds.position + Vector2i(
			floori(float(build_bounds.size.x - footprint.x) * 0.5),
			floori(float(build_bounds.size.y - footprint.y) * 0.5)
		)
		if (
			build_bounds.encloses(Rect2i(bootstrap_cell, footprint))
			and _can_place_active_footprint(bootstrap_cell, footprint, Vector2.ZERO)
		):
			candidates.append({"cell": bootstrap_cell, "offset": Vector2.ZERO})
		return candidates
	# A valid new module must share an edge with the hull. Generate only the
	# possible top-left cells along existing boundary cells instead of scanning
	# the entire 32x32 construction envelope.
	for occupied_value: Variant in hull_cells.keys():
		var occupied: Vector2i = occupied_value
		if not hull_cells.has(occupied + Vector2i.RIGHT):
			for row_offset: int in range(footprint.y):
				candidate_cells[Vector2i(occupied.x + 1, occupied.y - row_offset)] = true
		if not hull_cells.has(occupied + Vector2i.LEFT):
			for row_offset: int in range(footprint.y):
				candidate_cells[Vector2i(occupied.x - footprint.x, occupied.y - row_offset)] = true
		if not hull_cells.has(occupied + Vector2i.DOWN):
			for column_offset: int in range(footprint.x):
				candidate_cells[Vector2i(occupied.x - column_offset, occupied.y + 1)] = true
		if not hull_cells.has(occupied + Vector2i.UP):
			for column_offset: int in range(footprint.x):
				candidate_cells[Vector2i(occupied.x - column_offset, occupied.y - footprint.y)] = true
	for cell_value: Variant in candidate_cells.keys():
		var cell: Vector2i = cell_value
		var candidate_bounds := Rect2i(cell, footprint)
		if not build_bounds.encloses(candidate_bounds):
			continue
		var offset := Vector2.ZERO
		if not _can_place_active_footprint(cell, footprint, offset):
			continue
		if not _candidate_touches_hull(cell, offset, hull_cells, footprint):
			continue
		candidates.append({"cell": cell, "offset": offset})
	return candidates


func _cell_touches_hull(cell: Vector2i, hull_cells: Dictionary) -> bool:
	for connection: Dictionary in ship_layout.call("get_touching_cells", cell, false):
		if hull_cells.has(connection["cell"]):
			return true
	return false


func _installation_clearance_valid(cell: Vector2i, offset: Vector2 = Vector2.ZERO) -> bool:
	if inventory_piece_room_type.is_empty():
		return true
	if ship_layout.has_method("evaluate_cell_exterior_clearance"):
		var clearance: Dictionary = ship_layout.call(
			"evaluate_cell_exterior_clearance",
			inventory_piece_room_type,
			cell,
			offset,
			inventory_piece_footprint
		)
		if not bool(clearance.get("valid", true)):
			return false
	if free_blueprint_placement:
		return true
	var template := _room_type_template(inventory_piece_room_type)
	var power_status := SHIP_RESOURCE_ANALYZER.evaluate_power_placement(
		ship_layout,
		inventory_piece_room_type,
		cell,
		inventory_piece_footprint,
		template
	)
	return bool(power_status.get("valid", true))


## Placement previews normally test against the authored layout. While moving an
## installed module, its exact source rectangle is visually lifted but still
## exists in that layout until the controller commits the atomic relocation.
## Ignore only that rectangle so a one-cell nudge may overlap its former footprint.
func _can_place_active_footprint(
	cell: Vector2i,
	footprint: Vector2i,
	offset: Vector2 = Vector2.ZERO
) -> bool:
	if installed_drag_data.is_empty():
		return bool(ship_layout.call("can_place_footprint", cell, footprint, offset))
	if footprint.x < 1 or footprint.y < 1:
		return false
	var build_bounds: Rect2i = ship_layout.call("get_build_bounds")
	if not build_bounds.encloses(Rect2i(cell, footprint)):
		return false
	var candidate := Rect2(Vector2(cell) + offset, Vector2(footprint))
	var dragged_room_id := StringName(installed_drag_data.get("room_id", &""))
	var source_rect: Rect2i = installed_drag_data.get("source_rect", Rect2i())
	for room: Resource in _rooms():
		for rect: Rect2i in _room_rects(room):
			if StringName(room.get("room_id")) == dragged_room_id and rect == source_rect:
				continue
			for y: int in range(rect.position.y, rect.end.y):
				for x: int in range(rect.position.x, rect.end.x):
					var occupied_cell := Vector2i(x, y)
					var existing := GRID_GEOMETRY.logical_cell_rect(
						occupied_cell,
						GRID_GEOMETRY.cell_offset(ship_layout, occupied_cell)
					)
					var overlap := candidate.intersection(existing)
					if overlap.size.x > 0.001 and overlap.size.y > 0.001:
						return false
	return true


func _cell_belongs_to_dragged_source(cell: Vector2i) -> bool:
	if installed_drag_data.is_empty():
		return false
	var source_rect: Rect2i = installed_drag_data.get("source_rect", Rect2i())
	return source_rect.has_point(cell)


func _room_type_template(type_name: String) -> Resource:
	for template: Resource in ship_layout.get("room_types"):
		if String(template.get("type_name")) == type_name:
			return template
	return null


func _should_draw_power_field() -> bool:
	if editor_mode and (inventory_piece_drag_active or inventory_piece_armed):
		return inventory_piece_room_type in ["REACTOR", "POWER", "ENGINE"]
	var selected_room := _get_room_by_id(selected_room_id)
	return selected_room != null and String(selected_room.get("type_name")) in ["REACTOR", "POWER", "ENGINE"]


func _draw_power_network_overlay(draw_fields := true, draw_warnings := true) -> void:
	var simulation := get_tree().get_first_node_in_group("ship_simulation")
	var report: Dictionary
	if is_instance_valid(simulation) and simulation.has_method("get_power_network_report"):
		report = simulation.call("get_power_network_report")
	else:
		report = SHIP_RESOURCE_ANALYZER.power_network_report(ship_layout)
	var room_by_id: Dictionary = {}
	for room: Resource in _rooms():
		room_by_id[room.get("room_id")] = room
	if draw_fields:
		var source_cells: Dictionary = {}
		var field_color := power_field_color
		var selected_room := _get_room_by_id(selected_room_id)
		if editor_mode and (inventory_piece_drag_active or inventory_piece_armed) and inventory_piece_room_type in ["REACTOR", "POWER", "ENGINE"]:
			var preview_cell := hovered_build_cell if hovered_build_cell != INVALID_CELL else editor_focus_cell
			if preview_cell != INVALID_CELL:
				for preview_y: int in range(inventory_piece_footprint.y):
					for preview_x: int in range(inventory_piece_footprint.x):
						source_cells[preview_cell + Vector2i(preview_x, preview_y)] = true
		elif selected_room != null and String(selected_room.get("type_name")) in ["REACTOR", "POWER", "ENGINE"]:
			var selected_id: StringName = selected_room.get("room_id")
			var generator_ids: Array = [selected_id]
			for network_value: Variant in report.get("networks", []):
				var network: Dictionary = network_value
				if (network.get("generator_ids", []) as Array).has(selected_id):
					generator_ids = network.get("generator_ids", [])
					if float(network.get("demand", 0.0)) > float(network.get("capacity", 0.0)) + 0.001:
						field_color = power_field_overload_color
					break
			for generator_id: StringName in generator_ids:
				var generator := room_by_id.get(generator_id) as Resource
				if generator != null:
					source_cells.merge(_room_cells(generator), true)
		if not source_cells.is_empty():
			var coverage_cells := _power_field_coverage_cells(source_cells)
			# A broad, dim trace beneath the crisp line gives the field the glow of
			# a projected shipyard schematic without abandoning the lattice.
			_draw_cell_set_boundary(coverage_cells, Color(field_color, 0.16), 6.0)
			_draw_cell_set_boundary(coverage_cells, Color(field_color, 0.92), 1.5)
	if not draw_warnings:
		return
	var room_factors: Dictionary = report.get("room_factors", {})
	for room_id_value: Variant in room_factors.keys():
		var factor := float(room_factors[room_id_value])
		if factor >= 0.999:
			continue
		var room := room_by_id.get(room_id_value) as Resource
		if room == null:
			continue
		var warning_color := power_field_uncovered_color if factor <= 0.001 else power_field_overload_color
		_draw_room_boundary(room, warning_color, 3.0, _all_occupied_cells())


func _power_field_coverage_cells(source_cells: Dictionary) -> Dictionary:
	var coverage: Dictionary = {}
	if source_cells.is_empty():
		return coverage
	var radius := SHIP_RESOURCE_ANALYZER.REACTOR_FIELD_RADIUS_LATTICE
	var radius_cells := ceili(radius)
	for source_cell_value: Variant in source_cells.keys():
		var source_cell: Vector2i = source_cell_value
		for y: int in range(source_cell.y - radius_cells, source_cell.y + radius_cells + 1):
			for x: int in range(source_cell.x - radius_cells, source_cell.x + radius_cells + 1):
				var candidate := Vector2i(x, y)
				if Vector2(candidate - source_cell).length() <= radius + 0.001:
					coverage[candidate] = true
	return coverage


func _inventory_color_for_room(room: Resource) -> Color:
	match String(room.get("type_name")):
		"WEAPONS": return Color("#d94a42")
		"SHIELDS": return Color("#3e86d8")
		"REACTOR", "POWER": return Color("#d6a52f")
		"PROPULSION": return Color("#dc7135")
		"CREW", "CREW_QUARTERS": return Color("#7352a6")
		"MEDICAL": return Color("#42ad78")
		"HANGAR": return Color("#35a9a4")
		"SECURITY": return Color("#a84747")
		_: return Color("#627b79")


func _draw_room_boundary(room: Resource, color: Color, width: float, hull_cells: Dictionary = {}) -> void:
	var hull := hull_cells if not hull_cells.is_empty() else _all_occupied_cells()
	var replaced := GRID_GEOMETRY.exterior_replaced_edge_keys(_rooms(), hull, ship_layout)
	for segment: Dictionary in GRID_GEOMETRY.boundary_segments(ship_layout, _room_cells(room), _bounds(), CELL_SIZE, _hull_pixel_origin()):
		if replaced.has(GRID_GEOMETRY.exterior_edge_key(segment["cell"], segment["normal"])):
			continue
		draw_line(segment["start"], segment["end"], color, width)
	if GRID_GEOMETRY.has_exterior_profile(String(room.get("type_name"))):
		var facing := GRID_GEOMETRY.exterior_facing_quarters(room)
		for exterior_span: Rect2i in GRID_GEOMETRY.exterior_face_spans(room, hull, ship_layout):
			var profile := GRID_GEOMETRY.exterior_edge_profile(_get_grid_rect(exterior_span), String(room.get("type_name")), facing)
			if profile.size() >= 2:
				draw_polyline(profile, color, width, false)


func _is_selected_hardware_view(room: Resource) -> bool:
	if room == null or StringName(room.get("room_id")) != selected_room_id:
		return false
	if selected_room_cell == INVALID_CELL:
		return true
	for rect: Rect2i in _room_rects(room):
		if rect.has_point(selected_room_cell):
			return true
	return false


func _selected_hardware_view() -> Resource:
	var room := _get_room_by_id(selected_room_id)
	if room == null:
		return null
	if selected_room_cell == INVALID_CELL:
		return room
	for mount_room: Resource in _module_piece_views(room):
		if _is_selected_hardware_view(mount_room):
			return mount_room
	return room


func _pointer_hits_module_hardware(cell: Vector2i, pointer_position: Vector2) -> bool:
	var room := _room_at_cell(cell)
	if room == null or String(room.get("type_name")) not in ["WEAPONS", "PROPULSION", "SHIELDS"]:
		return false
	# A directional shield tile is the emitter itself. Its quarter-grid footprint
	# is too small to make players hunt for a sub-glyph before choosing a bank.
	if String(room.get("type_name")) == "SHIELDS":
		return true
	var hull_cells := _all_occupied_cells()
	var hit_radius := 6.0 / maxf(editor_view_zoom, 0.25)
	for mount_room: Resource in _module_piece_views(room):
		var anchor := _module_hardware_anchor(mount_room, hull_cells)
		if String(room.get("type_name")) == "PROPULSION":
			if pointer_position.distance_to(anchor) <= hit_radius + 2.0:
				return true
			continue
		var center := _room_pixel_bounds(mount_room).get_center()
		var direction := center.direction_to(anchor)
		var tip := anchor + direction * 9.0
		var closest := Geometry2D.get_closest_point_to_segment(pointer_position, center, tip)
		if pointer_position.distance_to(closest) <= hit_radius:
			return true
	return false


func _module_hardware_anchor(room: Resource, hull_cells: Dictionary) -> Vector2:
	var room_cells := _room_cells(room)
	if room_cells.is_empty():
		return Vector2.ZERO
	var direction := _module_facing_direction(room, room_cells, hull_cells)
	var cardinal := Vector2i(roundi(direction.x), roundi(direction.y))
	if cardinal == Vector2i.ZERO:
		cardinal = Vector2i.DOWN
	var facing_edge := Vector2.ZERO
	var facing_edge_count := 0
	for cell_value: Variant in room_cells.keys():
		var mount_cell := cell_value as Vector2i
		if room_cells.has(mount_cell + cardinal):
			continue
		var rect := _get_grid_rect(Rect2i(mount_cell, Vector2i.ONE))
		var edge_point := rect.get_center()
		if cardinal.x != 0:
			edge_point.x = rect.end.x if cardinal.x > 0 else rect.position.x
		else:
			edge_point.y = rect.end.y if cardinal.y > 0 else rect.position.y
		facing_edge += edge_point
		facing_edge_count += 1
	if facing_edge_count > 0:
		return facing_edge / float(facing_edge_count)
	return _room_pixel_bounds(room).get_center()


func _draw_cell_set_boundary(occupied_cells: Dictionary, color: Color, width: float) -> void:
	for segment: Dictionary in GRID_GEOMETRY.boundary_segments(ship_layout, occupied_cells, _bounds(), CELL_SIZE, _hull_pixel_origin()):
		draw_line(segment["start"], segment["end"], color, width)


func _draw_profiled_hull_boundary(hull_cells: Dictionary, color: Color, width: float) -> void:
	var replaced := GRID_GEOMETRY.exterior_replaced_edge_keys(_rooms(), hull_cells, ship_layout)
	var pieces: Array[PackedVector2Array] = []
	for room: Resource in _rooms():
		var room_type := String(room.get("type_name"))
		if not GRID_GEOMETRY.has_exterior_profile(room_type):
			continue
		var facing := GRID_GEOMETRY.exterior_facing_quarters(room)
		for exterior_span: Rect2i in GRID_GEOMETRY.exterior_face_spans(room, hull_cells, ship_layout):
			var profile := GRID_GEOMETRY.exterior_edge_profile(_get_grid_rect(exterior_span), room_type, facing)
			if profile.size() >= 2:
				pieces.append(profile)
	for segment: Dictionary in GRID_GEOMETRY.boundary_segments(ship_layout, hull_cells, _bounds(), CELL_SIZE, _hull_pixel_origin()):
		if replaced.has(GRID_GEOMETRY.exterior_edge_key(segment["cell"], segment["normal"])):
			continue
		pieces.append(PackedVector2Array([segment["start"], segment["end"]]))
	_draw_joined_boundary_pieces(pieces, color, width)


func _draw_joined_boundary_pieces(pieces: Array[PackedVector2Array], color: Color, width: float) -> void:
	while not pieces.is_empty():
		var contour: PackedVector2Array = pieces.pop_back()
		var start_point := contour[0]
		while contour.size() >= 2 and not contour[-1].is_equal_approx(start_point):
			var current_end := contour[-1]
			var match_index := -1
			var reverse_match := false
			for piece_index: int in range(pieces.size()):
				var candidate: PackedVector2Array = pieces[piece_index]
				if current_end.is_equal_approx(candidate[0]):
					match_index = piece_index
					break
				if current_end.is_equal_approx(candidate[-1]):
					match_index = piece_index
					reverse_match = true
					break
			if match_index < 0:
				break
			var next_piece: PackedVector2Array = pieces[match_index]
			pieces.remove_at(match_index)
			if reverse_match:
				next_piece.reverse()
			for point_index: int in range(1, next_piece.size()):
				contour.append(next_piece[point_index])
		if contour.size() >= 2:
			draw_polyline(contour, color, width, false)


func _draw_special_exterior_profiles(
	hull_cells: Dictionary,
	outline_color: Color,
	outline_width: float,
	draw_outline := true,
	fill_alpha := 1.0
) -> void:
	for room: Resource in _rooms():
		var room_type := String(room.get("type_name"))
		if not GRID_GEOMETRY.has_exterior_profile(room_type):
			continue
		var facing_quarters := GRID_GEOMETRY.exterior_facing_quarters(room)
		var source_fill_color: Color = room.get("color")
		var fill_color := Color(source_fill_color, source_fill_color.a * fill_alpha)
		for exterior_span: Rect2i in GRID_GEOMETRY.exterior_face_spans(room, hull_cells, ship_layout):
			var rect := _get_grid_rect(exterior_span)
			var polygon := GRID_GEOMETRY.exterior_cell_polygon(rect, room_type, facing_quarters)
			var profile := GRID_GEOMETRY.exterior_edge_profile(rect, room_type, facing_quarters)
			var aperture := GRID_GEOMETRY.exterior_aperture_polygon(rect, room_type, facing_quarters)
			if polygon.size() < 3 or profile.size() < 2:
				continue
			draw_colored_polygon(polygon, fill_color)
			if aperture.size() >= 3:
				draw_colored_polygon(aperture, Color(0.006, 0.025, 0.03, fill_alpha))
			if draw_outline:
				draw_polyline(profile, outline_color, outline_width, false)
			if draw_outline and room_type == "HANGAR":
				draw_polyline(profile, Color(0.2, 0.92, 0.88, 0.95), maxf(outline_width * 0.42, 1.0), false)


func _draw_selection_brackets(rect: Rect2, color: Color, width: float, bracket_length: float) -> void:
	var left := rect.position.x
	var right := rect.position.x + rect.size.x
	var top := rect.position.y
	var bottom := rect.position.y + rect.size.y
	var length := minf(bracket_length, minf(rect.size.x, rect.size.y) * 0.4)
	draw_line(Vector2(left, top), Vector2(left + length, top), color, width, true)
	draw_line(Vector2(left, top), Vector2(left, top + length), color, width, true)
	draw_line(Vector2(right, top), Vector2(right - length, top), color, width, true)
	draw_line(Vector2(right, top), Vector2(right, top + length), color, width, true)
	draw_line(Vector2(left, bottom), Vector2(left + length, bottom), color, width, true)
	draw_line(Vector2(left, bottom), Vector2(left, bottom - length), color, width, true)
	draw_line(Vector2(right, bottom), Vector2(right - length, bottom), color, width, true)
	draw_line(Vector2(right, bottom), Vector2(right, bottom - length), color, width, true)


func _draw_hull_edge_indicators(hull_cells: Dictionary) -> void:
	_draw_hull_edge_indicators_for_cells(hull_cells, hull_cells)


func _draw_hull_edge_indicators_for_cells(cells_to_check: Dictionary, hull_cells: Dictionary) -> void:
	for segment: Dictionary in GRID_GEOMETRY.boundary_segments(ship_layout, hull_cells, _bounds(), CELL_SIZE, _hull_pixel_origin()):
		if cells_to_check.has(segment["cell"]):
			_draw_hull_edge_segment(segment["start"], segment["end"], -Vector2(segment["normal"]))


func _draw_hull_edge_segment(start: Vector2, finish: Vector2, inward: Vector2) -> void:
	draw_line(start, finish, hull_edge_indicator_color, hull_edge_indicator_width, true)
	var midpoint := start.lerp(finish, 0.5)
	draw_line(midpoint, midpoint + inward * 5.0, hull_edge_indicator_color, maxf(hull_edge_indicator_width - 1.0, 1.0), true)


func _draw_module_facing_indicator(room: Resource, hull_cells: Dictionary) -> void:
	var room_cells := _room_cells(room)
	if room_cells.is_empty():
		return
	var direction := _module_facing_direction(room, room_cells, hull_cells)
	var cardinal := Vector2i(roundi(direction.x), roundi(direction.y))
	if cardinal == Vector2i.ZERO:
		cardinal = Vector2i.DOWN
	direction = Vector2(cardinal)
	var is_thruster := String(room.get("type_name")) == "PROPULSION"
	var indicator_color := Color(0.9, 0.42, 0.12, 0.94) if is_thruster else module_facing_indicator_color
	var center := Vector2.ZERO
	for cell_value: Variant in room_cells.keys():
		var cell: Vector2i = cell_value
		center += _get_grid_rect(Rect2i(cell, Vector2i.ONE)).get_center()
	center /= float(room_cells.size())
	var facing_edge := Vector2.ZERO
	var facing_edge_count := 0
	for cell_value: Variant in room_cells.keys():
		var cell := cell_value as Vector2i
		if room_cells.has(cell + cardinal):
			continue
		var rect := _get_grid_rect(Rect2i(cell, Vector2i.ONE))
		var edge_point := rect.get_center()
		if cardinal.x != 0:
			edge_point.x = rect.end.x if cardinal.x > 0 else rect.position.x
		else:
			edge_point.y = rect.end.y if cardinal.y > 0 else rect.position.y
		facing_edge += edge_point
		facing_edge_count += 1
	if facing_edge_count == 0:
		facing_edge = center
	else:
		facing_edge /= float(facing_edge_count)
	var arrow_start := center
	var arrow_tip := facing_edge + direction * 9.0
	var side := direction.orthogonal()
	draw_circle(center, 3.5, Color(0.03, 0.08, 0.09, 0.9), true)
	if is_thruster:
		# Deck/blueprint view uses a compact mechanical nozzle glyph. It avoids
		# the bright cyan selection language while still making exhaust direction
		# obvious before the engine is lit.
		var nozzle_side := side * 5.0
		var nozzle_base := facing_edge - direction * 3.0
		var nozzle_mouth := facing_edge + direction * 3.0
		draw_colored_polygon(
			PackedVector2Array([
				nozzle_base - nozzle_side,
				nozzle_base + nozzle_side,
				nozzle_mouth + nozzle_side * 0.68,
				nozzle_mouth - nozzle_side * 0.68,
			]),
			Color(0.025, 0.035, 0.035, 0.96)
		)
		draw_line(nozzle_base - nozzle_side, nozzle_base + nozzle_side, Color(0.23, 0.27, 0.27), 2.0, true)
		draw_line(nozzle_mouth - nozzle_side * 0.68, nozzle_mouth + nozzle_side * 0.68, indicator_color, 2.0, true)
		return
	draw_line(arrow_start, arrow_tip, indicator_color, module_facing_indicator_width, true)
	var arrow_back := arrow_tip - direction * 6.0
	draw_line(arrow_tip, arrow_back + side * 4.0, indicator_color, module_facing_indicator_width, true)
	draw_line(arrow_tip, arrow_back - side * 4.0, indicator_color, module_facing_indicator_width, true)


func _module_facing_direction(room: Resource, room_cells: Dictionary, hull_cells: Dictionary) -> Vector2:
	var explicit_facing := int(room.get("module_facing_quarters"))
	if explicit_facing >= 0:
		return Vector2(_quarter_turn_direction(explicit_facing))
	if room.get("module_recipe") != null:
		return Vector2(_quarter_turn_direction(int(room.get("module_rotation_quarters"))))
	var hull_bounds := _bounds()
	var hull_center := Vector2(hull_bounds.position) + GRID_GEOMETRY.grid_pixel_size(ship_layout, hull_bounds, 1.0) * 0.5
	var module_center := Vector2.ZERO
	for cell_value: Variant in room_cells.keys():
		var module_cell := cell_value as Vector2i
		module_center += GRID_GEOMETRY.logical_cell_rect(module_cell, GRID_GEOMETRY.cell_offset(ship_layout, module_cell)).get_center()
	module_center /= float(room_cells.size())
	var outward_bias := (module_center - hull_center).normalized()
	var best_direction := Vector2i.UP
	var best_score := -INF
	for direction: Vector2i in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
		var exposed_count := 0
		for cell_value: Variant in room_cells.keys():
			var exposed_cell := cell_value as Vector2i
			if GRID_GEOMETRY.face_contact_strength(ship_layout, exposed_cell, direction, hull_cells) < 0.999:
				exposed_count += 1
		var score := float(exposed_count) * 100.0 + Vector2(direction).dot(outward_bias)
		if score > best_score:
			best_score = score
			best_direction = direction
	return Vector2(best_direction)


func _quarter_turn_direction(rotation_quarters: int) -> Vector2i:
	match posmod(rotation_quarters, 4):
		1:
			return Vector2i.RIGHT
		2:
			return Vector2i.DOWN
		3:
			return Vector2i.LEFT
		_:
			return Vector2i.UP


func _draw_weapon_icon(room: Resource, _cells: Rect2i, room_rect: Rect2) -> void:
	var weapon: Resource = room.get("weapon_definition")
	var traverse := 0.0
	var weapon_color := Color(0.9, 0.58, 0.22)
	var family := "CANNON"
	if weapon != null:
		traverse = weapon.get("traverse_degrees")
		weapon_color = weapon.get("visual_color")
		family = String(weapon.get("weapon_family"))

	var center := room_rect.get_center()
	var quarters := GRID_GEOMETRY.weapon_coverage_quarters(ship_layout, room, weapon)
	for quarter: int in quarters:
		var coverage_direction := Vector2.UP.rotated(float(quarter) * PI * 0.5)
		_draw_weapon_family_icon(center, coverage_direction, family, weapon_color)
		var facing_angle := coverage_direction.angle()
		var half_arc := maxf(traverse, 8.0)
		draw_arc(
			center,
			11.0,
			facing_angle - deg_to_rad(half_arc),
			facing_angle + deg_to_rad(half_arc),
			14,
			Color(weapon_color, 0.65),
			1.5
		)


func _draw_weapon_family_icon(
	center: Vector2,
	direction: Vector2,
	family: String,
	color: Color
) -> void:
	var side := direction.orthogonal()
	match family:
		"BALLISTIC":
			draw_circle(center, 5.0, Color(0.03, 0.06, 0.065), true)
			draw_circle(center, 5.0, color, false, 2.0)
			draw_line(center + side * 2.0, center + direction * 13.0 + side * 2.0, color, 2.2)
			draw_line(center - side * 2.0, center + direction * 13.0 - side * 2.0, color, 2.2)
		"LASER":
			var diamond := PackedVector2Array([
				center - direction * 5.0,
				center + side * 5.0,
				center + direction * 5.0,
				center - side * 5.0,
				center - direction * 5.0,
			])
			draw_colored_polygon(diamond, Color(color, 0.34))
			draw_polyline(diamond, color, 2.0)
			draw_line(center + direction * 3.0, center + direction * 15.0, color.lightened(0.25), 2.0)
		"ENERGY":
			draw_circle(center, 6.0, Color(color, 0.2), true)
			draw_circle(center, 6.0, color, false, 2.0)
			draw_circle(center, 2.5, color.lightened(0.3), true)
			draw_line(center + side * 3.5, center + direction * 13.0 + side * 1.8, color, 2.2)
			draw_line(center - side * 3.5, center + direction * 13.0 - side * 1.8, color, 2.2)
		"MISSILE":
			for offset: float in [-4.0, 0.0, 4.0]:
				var tube_center := center + side * offset
				draw_line(tube_center - direction * 3.0, tube_center + direction * 10.0, color, 2.5)
				draw_circle(tube_center + direction * 10.0, 1.5, color.lightened(0.3), true)
		_:
			draw_rect(Rect2(center - Vector2(5.0, 5.0), Vector2(10.0, 10.0)), Color(color, 0.32), true)
			draw_rect(Rect2(center - Vector2(5.0, 5.0), Vector2(10.0, 10.0)), color, false, 2.0)
			draw_line(center, center + direction * 17.0, color, 4.0)


func _get_grid_rect(cells: Rect2i) -> Rect2:
	var rect := GRID_GEOMETRY.cell_rect(ship_layout, cells.position, _bounds(), CELL_SIZE, _hull_pixel_origin())
	rect.size = Vector2(cells.size) * CELL_SIZE
	return rect


func _get_candidate_grid_rect(cell: Vector2i, offset: Vector2, footprint: Vector2i = Vector2i.ONE) -> Rect2:
	var rect := _get_grid_rect(Rect2i(cell, Vector2i.ONE))
	var current_offset: Vector2 = GRID_GEOMETRY.cell_offset(ship_layout, cell)
	rect.position += (offset - current_offset) * CELL_SIZE
	rect.size = Vector2(footprint) * CELL_SIZE
	return rect


func _empty_build_cell_under_cursor(content_position: Vector2) -> Vector2i:
	_update_hovered_build_candidate(content_position)
	return hovered_build_cell


func _update_hovered_build_candidate(local_position: Vector2) -> void:
	var occupied_under_pointer := _occupied_cell_at_position(local_position)
	if occupied_under_pointer != INVALID_CELL and not _cell_belongs_to_dragged_source(occupied_under_pointer):
		if hovered_build_cell != INVALID_CELL:
			hovered_build_cell = INVALID_CELL
			hovered_build_offset = Vector2.ZERO
			queue_redraw()
		return
	var best_cell: Vector2i = INVALID_CELL
	var best_offset := Vector2.ZERO
	var best_distance: float = INF
	var build_bounds: Rect2i = ship_layout.call("get_build_bounds")
	var occupied_cells := _all_occupied_cells()
	if free_blueprint_placement:
		var placement_position := local_position
		if not installed_drag_data.is_empty():
			placement_position -= installed_drag_grab_offset
		var free_cell := build_bounds.position + Vector2i(
			floori((placement_position.x - _hull_pixel_origin().x) / CELL_SIZE),
			floori((placement_position.y - _hull_pixel_origin().y) / CELL_SIZE)
		)
		if (
			not build_bounds.encloses(Rect2i(free_cell, inventory_piece_footprint))
			or not _can_place_active_footprint(free_cell, inventory_piece_footprint, Vector2.ZERO)
		):
			free_cell = INVALID_CELL
		if hovered_build_cell != free_cell or not hovered_build_offset.is_zero_approx():
			hovered_build_cell = free_cell
			hovered_build_offset = Vector2.ZERO
			queue_redraw()
		return
	if occupied_cells.is_empty():
		var bootstrap_cell := build_bounds.position + Vector2i(
			floori(float(build_bounds.size.x - inventory_piece_footprint.x) * 0.5),
			floori(float(build_bounds.size.y - inventory_piece_footprint.y) * 0.5)
		)
		var bootstrap_rect := _get_candidate_grid_rect(
			bootstrap_cell,
			Vector2.ZERO,
			inventory_piece_footprint
		)
		var bootstrap_snap_distance := CELL_SIZE * 1.25
		var next_cell := (
			bootstrap_cell
			if bootstrap_rect.get_center().distance_squared_to(local_position)
				<= bootstrap_snap_distance * bootstrap_snap_distance
			else INVALID_CELL
		)
		if hovered_build_cell != next_cell or not hovered_build_offset.is_zero_approx():
			hovered_build_cell = next_cell
			hovered_build_offset = Vector2.ZERO
			queue_redraw()
		return
	var approximate_cell := build_bounds.position + Vector2i(
		floori((local_position.x - _hull_pixel_origin().x) / CELL_SIZE),
		floori((local_position.y - _hull_pixel_origin().y) / CELL_SIZE)
	)
	var search_radius := maxi(maxi(inventory_piece_footprint.x, inventory_piece_footprint.y) + 1, 2)
	for y: int in range(approximate_cell.y - search_radius, approximate_cell.y + search_radius + 1):
		for x: int in range(approximate_cell.x - search_radius, approximate_cell.x + search_radius + 1):
			var cell := Vector2i(x, y)
			if not build_bounds.encloses(Rect2i(cell, inventory_piece_footprint)):
				continue
			var candidate_offset := Vector2.ZERO
			if not _can_place_active_footprint(cell, inventory_piece_footprint, candidate_offset):
				continue
			if not _candidate_touches_hull(cell, candidate_offset, occupied_cells, inventory_piece_footprint):
				continue
			var candidate_rect: Rect2 = _get_candidate_grid_rect(cell, candidate_offset, inventory_piece_footprint)
			var distance: float = local_position.distance_squared_to(candidate_rect.get_center())
			if distance < best_distance:
				best_distance = distance
				best_cell = cell
				best_offset = candidate_offset
	var maximum_snap_distance: float = CELL_SIZE * 0.9
	if best_distance > maximum_snap_distance * maximum_snap_distance:
		best_cell = INVALID_CELL
	if hovered_build_cell != best_cell or hovered_build_offset != best_offset:
		hovered_build_cell = best_cell
		hovered_build_offset = best_offset
		queue_redraw()


func _candidate_touches_hull(cell: Vector2i, offset: Vector2, hull_cells: Dictionary, footprint: Vector2i = Vector2i.ONE) -> bool:
	var candidate := Rect2(Vector2(cell) + offset, Vector2(footprint))
	for occupied_value: Variant in hull_cells.keys():
		var occupied := occupied_value as Vector2i
		var existing := GRID_GEOMETRY.logical_cell_rect(occupied, GRID_GEOMETRY.cell_offset(ship_layout, occupied))
		if is_equal_approx(candidate.end.x, existing.position.x) or is_equal_approx(existing.end.x, candidate.position.x):
			if minf(candidate.end.y, existing.end.y) - maxf(candidate.position.y, existing.position.y) > 0.001:
				return true
		if is_equal_approx(candidate.end.y, existing.position.y) or is_equal_approx(existing.end.y, candidate.position.y):
			if minf(candidate.end.x, existing.end.x) - maxf(candidate.position.x, existing.position.x) > 0.001:
				return true
	return false


func _occupied_cell_at_position(local_position: Vector2) -> Vector2i:
	for cell_value: Variant in _all_occupied_cells().keys():
		var cell: Vector2i = cell_value
		if _get_grid_rect(Rect2i(cell, Vector2i.ONE)).has_point(local_position):
			return cell
	return Vector2i(2147483647, 2147483647)


func _editor_cell_for_position(local_position: Vector2) -> Vector2i:
	var occupied_cell := _occupied_cell_at_position(local_position)
	if occupied_cell != INVALID_CELL:
		return occupied_cell
	_update_hovered_build_candidate(local_position)
	if hovered_build_cell != INVALID_CELL and ship_layout.call("is_cell_buildable", hovered_build_cell):
		return hovered_build_cell
	return INVALID_CELL


func _occupied_cells_in_local_rect(local_rect: Rect2) -> Dictionary:
	var selected_cells: Dictionary = {}
	for cell_value: Variant in _all_occupied_cells().keys():
		var cell: Vector2i = cell_value
		if _get_grid_rect(Rect2i(cell, Vector2i.ONE)).intersects(local_rect, true):
			selected_cells[cell] = true
	return selected_cells


func _update_canvas_size() -> void:
	if editor_mode and editor_viewport_constrained:
		custom_minimum_size = Vector2.ZERO
		return
	custom_minimum_size = Vector2(
		CANVAS_PADDING.x * 2.0 + (GRID_GEOMETRY.grid_pixel_size(ship_layout, _bounds(), CELL_SIZE).x + EDIT_MARGIN_CELLS * 2.0 * CELL_SIZE),
		CANVAS_PADDING.y * 2.0 + (_rows() + EDIT_MARGIN_CELLS * 2) * CELL_SIZE
	)


func _editor_content_size() -> Vector2:
	return Vector2(
		CANVAS_PADDING.x * 2.0 + (GRID_GEOMETRY.grid_pixel_size(ship_layout, _bounds(), CELL_SIZE).x + EDIT_MARGIN_CELLS * 2.0 * CELL_SIZE),
		CANVAS_PADDING.y * 2.0 + (_rows() + EDIT_MARGIN_CELLS * 2) * CELL_SIZE
	)


func _screen_to_editor_content(point: Vector2) -> Vector2:
	if not editor_mode:
		return point
	return (point - editor_view_pan) / maxf(editor_view_zoom, 0.001)


func _zoom_editor_view_at(screen_point: Vector2, factor: float) -> void:
	var before := _screen_to_editor_content(screen_point)
	editor_view_zoom = clampf(editor_view_zoom * factor, 0.25, 5.0)
	editor_view_pan = screen_point - before * editor_view_zoom
	_clamp_editor_view_pan()
	queue_redraw()


func _clamp_editor_view_pan() -> void:
	if not editor_mode:
		return
	var viewport_size := size
	if viewport_size.x <= 1.0 or viewport_size.y <= 1.0:
		viewport_size = custom_minimum_size
	var content_size := _editor_content_size() * editor_view_zoom
	var keep_visible := Vector2(
		minf(96.0, maxf(24.0, content_size.x * 0.45)),
		minf(96.0, maxf(24.0, content_size.y * 0.45))
	)
	var minimum_pan := keep_visible - content_size
	var maximum_pan := viewport_size - keep_visible
	if minimum_pan.x > maximum_pan.x:
		var centered_x := (viewport_size.x - content_size.x) * 0.5
		minimum_pan.x = centered_x
		maximum_pan.x = centered_x
	if minimum_pan.y > maximum_pan.y:
		var centered_y := (viewport_size.y - content_size.y) * 0.5
		minimum_pan.y = centered_y
		maximum_pan.y = centered_y
	editor_view_pan.x = clampf(editor_view_pan.x, minimum_pan.x, maximum_pan.x)
	editor_view_pan.y = clampf(editor_view_pan.y, minimum_pan.y, maximum_pan.y)


func _hull_pixel_origin() -> Vector2:
	return CANVAS_PADDING + Vector2.ONE * EDIT_MARGIN_CELLS * CELL_SIZE


func _bounds() -> Rect2i:
	return ship_layout.call("get_build_bounds")


func _rooms() -> Array:
	return ship_layout.get("rooms")


func _room_rects(room: Resource) -> Array[Rect2i]:
	return room.get("grid_rects")


func _columns() -> int:
	return _bounds().size.x


func _rows() -> int:
	return _bounds().size.y
