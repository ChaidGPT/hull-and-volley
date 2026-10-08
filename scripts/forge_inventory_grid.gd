class_name ForgeInventoryGrid
extends Container

signal installed_piece_returned(room_type: String, room_id: StringName, cell: Vector2i, cursor_position: Vector2)
signal piece_position_changed(inventory_instance_id: int, inventory_position: Vector2i)

const RETURN_TIME := 0.22
const REFLOW_TIME := 0.14
const INVENTORY_COLUMNS := 10
const CELL_SIZE := 28.0
const CELL_GUTTER := 0.0
const MINIMUM_ROWS := 2

var _active_piece: Control
var _active_piece_id := 0
var _installed_drag_hovered := false
var _packed_rows := MINIMUM_ROWS
var manual_layout := false
var capacity_rows := MINIMUM_ROWS
var bounded_capacity := false
var _drop_preview_slot := Vector2i(-1, -1)
var _drop_preview_footprint := Vector2i.ONE
var _drop_preview_valid := false


func _ready() -> void:
	_packed_rows = maxi(capacity_rows, MINIMUM_ROWS)
	custom_minimum_size = Vector2(INVENTORY_COLUMNS * CELL_SIZE, _packed_rows * CELL_SIZE)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_STOP
	child_order_changed.connect(_inventory_changed)
	queue_sort()


func set_capacity_rows(rows: int, is_bounded: bool = true) -> void:
	capacity_rows = maxi(rows, 1)
	bounded_capacity = is_bounded
	_packed_rows = maxi(capacity_rows, MINIMUM_ROWS)
	custom_minimum_size = Vector2(INVENTORY_COLUMNS * CELL_SIZE, _packed_rows * CELL_SIZE)
	queue_sort()
	queue_redraw()


func has_empty_bay() -> bool:
	for child: Node in get_children():
		if "room_type" in child and String(child.get("room_type")).is_empty():
			return true
	return false


func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	if not data is Dictionary:
		return false
	var kind := String(data.get("kind", ""))
	var accepted := false
	if kind == "installed_grid_piece":
		accepted = _first_open_slot(_occupied_slots(), Vector2i(data.get("footprint", Vector2i.ONE))) != Vector2i(-1, -1)
	if kind == "forge_grid_piece" and manual_layout:
		var source := _piece_by_control_id(int(data.get("source_instance_id", 0)))
		if source != null:
			var footprint := Vector2i(data.get("footprint", Vector2i.ONE))
			var grab_offset := Vector2(data.get("grab_offset", Vector2.ZERO))
			var slot := Vector2i(floor((at_position.x - grab_offset.x) / CELL_SIZE), floor((at_position.y - grab_offset.y) / CELL_SIZE))
			_drop_preview_slot = slot
			_drop_preview_footprint = footprint
			_drop_preview_valid = _slot_is_open(slot, footprint, source.get_instance_id())
			accepted = _drop_preview_valid
			queue_redraw()
	if _installed_drag_hovered != accepted:
		_installed_drag_hovered = accepted
		queue_redraw()
	return accepted


func _drop_data(at_position: Vector2, data: Variant) -> void:
	var kind := String(data.get("kind", ""))
	if kind == "forge_grid_piece" and manual_layout:
		var piece := _piece_by_control_id(int(data.get("source_instance_id", 0)))
		if piece == null:
			return
		var grab_offset := Vector2(data.get("grab_offset", Vector2.ZERO))
		var slot := Vector2i(floor((at_position.x - grab_offset.x) / CELL_SIZE), floor((at_position.y - grab_offset.y) / CELL_SIZE))
		if not _slot_is_open(slot, _piece_footprint(piece), piece.get_instance_id()):
			return_piece(piece.get_instance_id(), get_viewport().get_mouse_position())
			return
		_set_piece_slot(piece, slot, true)
		piece.visible = true
		piece.modulate = Color.WHITE
		_active_piece = null
		_active_piece_id = 0
		_clear_drop_preview()
		queue_sort()
		return
	_installed_drag_hovered = false
	_clear_drop_preview()
	installed_piece_returned.emit(
		String(data.get("room_type", "UNASSIGNED")),
		StringName(data.get("room_id", &"")),
		data.get("cell", Vector2i.ZERO),
		get_viewport().get_mouse_position()
	)


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_SORT_CHILDREN:
			_layout_inventory()
		NOTIFICATION_RESIZED:
			queue_redraw()
		NOTIFICATION_DRAG_END:
			if _installed_drag_hovered:
				_installed_drag_hovered = false
			_clear_drop_preview()


func _draw() -> void:
	var edge := Color(0.26, 1.0, 0.85, 0.95) if _installed_drag_hovered else Color(0.08, 0.42, 0.39, 0.8)
	var fill := Color(0.02, 0.16, 0.14, 0.78) if _installed_drag_hovered else Color(0.004, 0.025, 0.025, 0.32)
	var grid_size := Vector2(INVENTORY_COLUMNS * CELL_SIZE, _packed_rows * CELL_SIZE)
	var grid_rect := Rect2(Vector2.ZERO, grid_size)
	draw_rect(grid_rect, fill, true)
	var lattice_color := Color(0.08, 0.34, 0.32, 0.62)
	for column: int in range(INVENTORY_COLUMNS + 1):
		var x := float(column) * CELL_SIZE
		draw_line(Vector2(x, 0.0), Vector2(x, grid_size.y), lattice_color, 1.0)
	for row: int in range(_packed_rows + 1):
		var y := float(row) * CELL_SIZE
		draw_line(Vector2(0.0, y), Vector2(grid_size.x, y), lattice_color, 1.0)
	draw_rect(grid_rect, edge, false, 2.0 if _installed_drag_hovered else 1.0)
	if manual_layout and _drop_preview_slot.x >= 0 and _drop_preview_slot.y >= 0:
		var preview_rect := Rect2(Vector2(_drop_preview_slot) * CELL_SIZE, Vector2(_drop_preview_footprint) * CELL_SIZE)
		draw_rect(preview_rect.grow(-1.0), Color(0.18, 0.95, 0.76, 0.18) if _drop_preview_valid else Color(1.0, 0.2, 0.12, 0.18), true)
		draw_rect(preview_rect.grow(-1.0), Color(0.3, 1.0, 0.84, 0.9) if _drop_preview_valid else Color(1.0, 0.28, 0.16, 0.9), false, 2.0)
	if _visible_piece_count() == 0 or _installed_drag_hovered:
		var prompt := "RELEASE TO STOW" if _installed_drag_hovered else "DROP HULL PARTS HERE"
		draw_string(
			ThemeDB.fallback_font,
			Vector2(0, grid_size.y * 0.5 + 4),
			prompt,
			HORIZONTAL_ALIGNMENT_CENTER,
			grid_size.x,
			10,
			Color(0.55, 1.0, 0.9, 0.95 if _installed_drag_hovered else 0.55)
		)


func _inventory_changed() -> void:
	queue_sort()
	queue_redraw()


func _layout_inventory() -> void:
	if manual_layout:
		_layout_manual_inventory()
		return
	var occupied := {}
	var highest_row := 0
	for child: Node in get_children():
		if not (child is Control) or not child.visible:
			continue
		var piece := child as Control
		var footprint := _piece_footprint(piece)
		var slot := _first_open_slot(occupied, footprint)
		if slot == Vector2i(-1, -1):
			piece.visible = false
			continue
		for y: int in range(slot.y, slot.y + footprint.y):
			for x: int in range(slot.x, slot.x + footprint.x):
				occupied[Vector2i(x, y)] = true
		highest_row = maxi(highest_row, slot.y + footprint.y)
		var piece_rect := Rect2(
			Vector2(slot) * CELL_SIZE + Vector2.ONE * CELL_GUTTER,
			Vector2(footprint) * CELL_SIZE - Vector2.ONE * CELL_GUTTER * 2.0
		)
		fit_child_in_rect(piece, piece_rect)
	_packed_rows = maxi(capacity_rows if bounded_capacity else highest_row, MINIMUM_ROWS)
	var required_size := Vector2(INVENTORY_COLUMNS * CELL_SIZE, _packed_rows * CELL_SIZE)
	if not custom_minimum_size.is_equal_approx(required_size):
		custom_minimum_size = required_size
	queue_redraw()


func _layout_manual_inventory() -> void:
	var occupied := {}
	var highest_row := 0
	for child: Node in get_children():
		if not child is Control:
			continue
		var piece := child as Control
		# A dragged brick is physically in the player's hand. Container sort
		# notifications must not quietly put it back into its source cells while
		# the drag is still active; those cells remain available for an
		# overlapping one-cell move.
		if piece.get_instance_id() == _active_piece_id:
			piece.visible = false
			continue
		var footprint := _piece_footprint(piece)
		var requested_slot := Vector2i(piece.get("inventory_position")) if "inventory_position" in piece else Vector2i(-1, -1)
		var slot := requested_slot
		if not _slot_is_open_in_map(slot, footprint, occupied):
			slot = _first_open_slot(occupied, footprint)
		if slot == Vector2i(-1, -1):
			piece.visible = false
			continue
		piece.visible = true
		_set_piece_slot(piece, slot, requested_slot != slot)
		_mark_occupied(occupied, slot, footprint)
		highest_row = maxi(highest_row, slot.y + footprint.y)
		fit_child_in_rect(piece, Rect2(Vector2(slot) * CELL_SIZE, Vector2(footprint) * CELL_SIZE))
	_packed_rows = maxi(capacity_rows if bounded_capacity else highest_row, MINIMUM_ROWS)
	var required_size := Vector2(INVENTORY_COLUMNS * CELL_SIZE, _packed_rows * CELL_SIZE)
	if not custom_minimum_size.is_equal_approx(required_size):
		custom_minimum_size = required_size
	queue_redraw()


func _set_piece_slot(piece: Control, slot: Vector2i, notify_owner: bool) -> void:
	if "inventory_position" in piece:
		piece.set("inventory_position", slot)
	if "inventory_condition" in piece:
		var condition: Dictionary = piece.get("inventory_condition")
		condition["inventory_position"] = slot
		piece.set("inventory_condition", condition)
	if notify_owner and "inventory_instance_id" in piece:
		var inventory_instance_id := int(piece.get("inventory_instance_id"))
		if inventory_instance_id > 0:
			piece_position_changed.emit(inventory_instance_id, slot)


func _mark_occupied(occupied: Dictionary, slot: Vector2i, footprint: Vector2i) -> void:
	for y: int in range(slot.y, slot.y + footprint.y):
		for x: int in range(slot.x, slot.x + footprint.x):
			occupied[Vector2i(x, y)] = true


func _slot_is_open_in_map(slot: Vector2i, footprint: Vector2i, occupied: Dictionary) -> bool:
	if slot.x < 0 or slot.y < 0 or slot.x + footprint.x > INVENTORY_COLUMNS:
		return false
	if bounded_capacity and slot.y + footprint.y > capacity_rows:
		return false
	for y: int in range(slot.y, slot.y + footprint.y):
		for x: int in range(slot.x, slot.x + footprint.x):
			if occupied.has(Vector2i(x, y)):
				return false
	return true


func _slot_is_open(slot: Vector2i, footprint: Vector2i, excluded_control_id: int = 0) -> bool:
	var occupied := {}
	for child: Node in get_children():
		if not child is Control:
			continue
		var control_id := child.get_instance_id()
		if control_id == excluded_control_id or control_id == _active_piece_id:
			continue
		var child_slot := Vector2i(child.get("inventory_position")) if "inventory_position" in child else Vector2i(-1, -1)
		if child_slot.x < 0 or child_slot.y < 0:
			continue
		_mark_occupied(occupied, child_slot, _piece_footprint(child as Control))
	return _slot_is_open_in_map(slot, footprint, occupied)


func _occupied_slots(excluded_control_id: int = 0) -> Dictionary:
	var occupied := {}
	for child: Node in get_children():
		if not child is Control:
			continue
		var control_id := child.get_instance_id()
		if control_id == excluded_control_id or control_id == _active_piece_id or not child.visible:
			continue
		var child_slot := Vector2i(child.get("inventory_position")) if "inventory_position" in child else Vector2i(-1, -1)
		if child_slot.x >= 0 and child_slot.y >= 0:
			_mark_occupied(occupied, child_slot, _piece_footprint(child as Control))
	return occupied


func _piece_by_control_id(control_id: int) -> Control:
	for child: Node in get_children():
		if child is Control and child.get_instance_id() == control_id:
			return child as Control
	return null


func _clear_drop_preview() -> void:
	_installed_drag_hovered = false
	_drop_preview_slot = Vector2i(-1, -1)
	_drop_preview_footprint = Vector2i.ONE
	_drop_preview_valid = false
	queue_redraw()


func _piece_footprint(piece: Control) -> Vector2i:
	if "footprint" not in piece:
		return Vector2i.ONE
	var raw := Vector2i(piece.get("footprint"))
	return Vector2i(clampi(raw.x, 1, INVENTORY_COLUMNS), maxi(raw.y, 1))


func _first_open_slot(occupied: Dictionary, footprint: Vector2i) -> Vector2i:
	var row := 0
	var row_limit := capacity_rows - footprint.y + 1 if bounded_capacity else 10000
	while row < row_limit:
		for column: int in range(INVENTORY_COLUMNS - footprint.x + 1):
			var open := true
			for y: int in range(row, row + footprint.y):
				for x: int in range(column, column + footprint.x):
					if occupied.has(Vector2i(x, y)):
						open = false
						break
				if not open:
					break
			if open:
				return Vector2i(column, row)
		row += 1
	return Vector2i(-1, -1)


func _visible_piece_count() -> int:
	var count := 0
	for child: Node in get_children():
		if child is Control and child.visible:
			count += 1
	return count


func begin_piece_drag(piece: Control) -> void:
	if not is_instance_valid(piece):
		return
	_active_piece = piece
	_active_piece_id = piece.get_instance_id()
	if manual_layout:
		piece.visible = false
		queue_redraw()
		return
	var old_positions := _visible_positions()
	piece.visible = false
	queue_sort()
	_animate_reflow.call_deferred(old_positions, null)


func commit_piece_drag(source_instance_id: int) -> void:
	if source_instance_id != _active_piece_id:
		return
	_active_piece = null
	_active_piece_id = 0


func restore_catalog_piece(source_instance_id: int) -> void:
	if source_instance_id != _active_piece_id or not is_instance_valid(_active_piece):
		return
	var old_positions := _visible_positions()
	var piece := _active_piece
	_active_piece = null
	_active_piece_id = 0
	piece.visible = true
	if manual_layout:
		queue_sort()
		return
	queue_sort()
	_animate_reflow.call_deferred(old_positions, piece)


func return_piece(source_instance_id: int, cursor_position: Vector2) -> void:
	if source_instance_id != _active_piece_id or not is_instance_valid(_active_piece):
		return
	var old_positions := _visible_positions()
	var piece := _active_piece
	_active_piece = null
	_active_piece_id = 0
	piece.visible = true
	piece.modulate.a = 0.0
	queue_sort()
	if manual_layout:
		_animate_return.call_deferred({}, piece, cursor_position)
		return
	_animate_return.call_deferred(old_positions, piece, cursor_position)


func receive_new_piece(piece: Control, cursor_position: Vector2) -> void:
	if not is_instance_valid(piece):
		return
	var old_positions := _visible_positions()
	piece.modulate.a = 0.0
	queue_sort()
	_animate_return.call_deferred(old_positions, piece, cursor_position)


func finish_unhandled_drag(source_instance_id: int, cursor_position: Vector2) -> void:
	if source_instance_id == _active_piece_id:
		return_piece(source_instance_id, cursor_position)


func _visible_positions() -> Dictionary:
	var positions := {}
	for child: Node in get_children():
		if child is Control and child.visible:
			positions[child.get_instance_id()] = (child as Control).global_position
	return positions


func _animate_reflow(old_positions: Dictionary, excluded_piece: Control) -> void:
	if manual_layout:
		return
	await get_tree().process_frame
	for child: Node in get_children():
		if not (child is Control) or not child.visible or child == excluded_piece:
			continue
		var control := child as Control
		var instance_id := control.get_instance_id()
		if not old_positions.has(instance_id):
			continue
		var target := control.position
		control.position += old_positions[instance_id] - control.global_position
		create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT).tween_property(
			control, "position", target, REFLOW_TIME
		)


func _animate_return(old_positions: Dictionary, piece: Control, cursor_position: Vector2) -> void:
	await get_tree().process_frame
	_animate_reflow(old_positions, piece)
	if not is_instance_valid(piece):
		return
	var layer := CanvasLayer.new()
	layer.layer = 120
	get_tree().root.add_child(layer)
	var ghost := ForgeInventoryPiece.new()
	ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ghost.configure(
		String(piece.get("room_type")),
		String(piece.get("display_name")),
		piece.get("piece_color"),
		piece.get("footprint"),
		int(piece.get("power_capacity")),
		int(piece.get("power_draw")),
		String(piece.get("inventory_key")),
		piece.get("module_recipe"),
		int(piece.get("inventory_instance_id")),
		piece.get("inventory_condition"),
		int(piece.get("crew_required"))
	)
	ghost.drag_ghost = true
	var returned_footprint := Vector2(piece.get("footprint"))
	ghost.custom_minimum_size = returned_footprint * 22.0
	ghost.size = ghost.custom_minimum_size
	ghost.position = cursor_position - ghost.size * 0.5
	layer.add_child(ghost)
	var target := piece.get_global_rect().get_center() - ghost.size * 0.5
	var tween := create_tween().set_parallel(true).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(ghost, "position", target, RETURN_TIME)
	tween.tween_property(ghost, "scale", Vector2(0.9, 0.9), RETURN_TIME)
	await tween.finished
	if is_instance_valid(piece):
		piece.modulate = Color.WHITE
	layer.queue_free()
