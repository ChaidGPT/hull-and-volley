class_name ForgeInventoryPiece
extends Control

const POWER_REQUIREMENT_DISPLAY := preload("res://scripts/power_requirement_display.gd")
const CREW_REQUIREMENT_DISPLAY := preload("res://scripts/crew_requirement_display.gd")

signal selected(room_type: String, source_instance_id: int)

var room_type := "UNASSIGNED"
var display_name := "GRID PIECE"
var piece_color := Color(0.16, 0.72, 0.66)
var footprint := Vector2i.ONE
var power_capacity := 0
var power_draw := 0
var crew_required := 0
var inventory_key := ""
var inventory_instance_id := 0
var inventory_condition: Dictionary = {}
var inventory_position := Vector2i(-1, -1)
var module_recipe: Resource
var drag_enabled := true
var drag_ghost := false:
	set(value):
		drag_ghost = value
		set_process(value)
		queue_redraw()
var drift_time := 0.0
var _drag_inventory: Node


func _ready() -> void:
	set_process(drag_ghost)
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND


func _process(delta: float) -> void:
	if not drag_ghost:
		return
	drift_time += delta
	queue_redraw()


func configure(
	type_name: String,
	label: String,
	color: Color,
	size_cells := Vector2i.ONE,
	capacity := 0,
	required_power := 0,
	item_key := "",
	recipe: Resource = null,
	item_instance_id := 0,
	item_condition: Dictionary = {},
	required_crew := 0
) -> void:
	room_type = type_name
	display_name = label
	piece_color = color
	footprint = size_cells
	power_capacity = maxi(capacity, 0)
	power_draw = maxi(required_power, 0)
	inventory_key = item_key if not item_key.is_empty() else room_type
	inventory_instance_id = item_instance_id
	inventory_condition = item_condition.duplicate(true)
	crew_required = maxi(required_crew, 0)
	inventory_position = Vector2i(item_condition.get("inventory_position", Vector2i(-1, -1)))
	module_recipe = recipe
	# The inventory container assigns this control exactly the rectangle occupied
	# by its real footprint. It must not impose a card-sized minimum of its own.
	custom_minimum_size = Vector2.ZERO
	tooltip_text = "%s\nDRAG TO INSTALL" % display_name.to_upper()
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		selected.emit(room_type, get_instance_id())


func _get_drag_data(at_position: Vector2) -> Variant:
	if not drag_enabled:
		return null
	var preview := ForgeInventoryPiece.new()
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview.configure(
		room_type,
		display_name,
		piece_color,
		footprint,
		power_capacity,
		power_draw,
		inventory_key,
		module_recipe,
		inventory_instance_id,
		inventory_condition,
		crew_required
	)
	preview.drag_ghost = true
	preview.custom_minimum_size = Vector2(22 * footprint.x, 22 * footprint.y)
	preview.size = preview.custom_minimum_size
	preview.position = Vector2(8.0, 8.0)
	set_drag_preview(preview)
	_drag_inventory = get_parent()
	if is_instance_valid(_drag_inventory) and _drag_inventory.has_method("begin_piece_drag"):
		_drag_inventory.call("begin_piece_drag", self)
	return {
		"kind": "forge_grid_piece",
		"room_type": room_type,
		"inventory_key": inventory_key,
		"inventory_instance_id": inventory_instance_id,
		"footprint": footprint,
		"anchor": Vector2i.ZERO,
		"grab_offset": at_position,
		"source_instance_id": get_instance_id(),
	}


func _notification(what: int) -> void:
	if what != NOTIFICATION_DRAG_END or drag_ghost:
		return
	if is_instance_valid(_drag_inventory) and _drag_inventory.has_method("finish_unhandled_drag"):
		_drag_inventory.call_deferred(
			"finish_unhandled_drag",
			get_instance_id(),
			get_viewport().get_mouse_position()
		)
	_drag_inventory = null


func _draw() -> void:
	var bob := Vector2.ZERO
	var tile_rotation := 0.0
	if drag_ghost:
		bob = Vector2(sin(drift_time * 2.1) * 2.0, cos(drift_time * 1.65) * 2.5)
		tile_rotation = sin(drift_time * 1.25) * 0.065
	var center := size * 0.5 + bob
	var tile_size := _silhouette_size()
	draw_set_transform(center, tile_rotation)
	var rect := Rect2(-tile_size * 0.5, tile_size)
	if drag_ghost:
		draw_rect(rect.grow(3.0), Color(piece_color, 0.11), true)
	# Locker lattice lines must stop at a module's hull. An opaque, slightly
	# darkened fill keeps a multi-cell module visibly solid instead of making the
	# background grid look like seams between several separate pieces.
	var solid_fill := Color(piece_color, 0.68) if drag_ghost else Color(0.015, 0.055, 0.055, 0.98).lerp(piece_color, 0.24)
	draw_rect(rect, solid_fill, true)
	draw_rect(rect.grow(-0.5), Color(piece_color, 0.82), false, 1.0)
	# A module is one physical object even when it spans several placement
	# lattice cells. Internal lattice lines made full rooms look like several
	# loose quarter-parts, so only the true outside silhouette is drawn here.
	var grid_glyph := _grid_glyph()
	draw_string(
		ThemeDB.fallback_font,
		Vector2(rect.position.x, 4.0),
		grid_glyph,
		HORIZONTAL_ALIGNMENT_CENTER,
		rect.size.x,
		8 if grid_glyph.length() > 3 else 10,
		Color(piece_color.lightened(0.5), 0.9)
	)
	# Locker pieces advertise their authored requirements; they are not reporting
	# live ship state yet.  Keep these icons bright so the catalog reads as a
	# palette of available parts rather than a wall of fault indicators.
	if power_draw > 0:
		var bolt_size := 7.0
		var bolt_width := float(power_draw) * bolt_size + float(power_draw - 1)
		var bolt_center := Vector2(rect.end.x - bolt_width * 0.5 - 3.0, rect.end.y - bolt_size * 0.5 - 3.0)
		POWER_REQUIREMENT_DISPLAY.draw_strip(
			self,
			bolt_center,
			power_draw,
			float(power_draw),
			bolt_size,
			1.0
		)
	if crew_required > 0:
		CREW_REQUIREMENT_DISPLAY.draw_status(
			self,
			Vector2(rect.end.x - 9.0, rect.position.y + 7.0),
			crew_required,
			crew_required,
			true,
			7.0
		)
	draw_set_transform(Vector2.ZERO, 0.0)
	if drag_ghost:
		for mote_index: int in range(3):
			var angle := drift_time * (0.6 + mote_index * 0.15) + float(mote_index) * 2.1
			var mote := center + Vector2(cos(angle), sin(angle)) * (19.0 + mote_index * 2.0)
			draw_circle(mote, 1.0, Color(0.72, 1.0, 0.96, 0.7))


func _silhouette_size() -> Vector2:
	if not drag_ghost:
		return Vector2(maxf(size.x, 4.0), maxf(size.y, 4.0))
	return Vector2(
		maxf(size.x - 6.0, 4.0),
		maxf(size.y - 6.0, 4.0)
	)


func _grid_glyph() -> String:
	if module_recipe != null:
		var payload: Resource = module_recipe.get("payload_resource")
		if payload != null:
			match String(payload.get("weapon_family")):
				"BALLISTIC":
					return "BAL"
				"CANNON":
					return "CAN"
				"LASER":
					return "LAS"
				"ENERGY":
					return "ENG"
				"MISSILE":
					return "MSL"
	match room_type:
		"COMMAND":
			return "CMD"
		"CREW_QUARTERS":
			return "CREW"
		"POWER":
			return "PWR"
		"PROPULSION":
			return "THR"
		"WEAPONS":
			return "WPN"
		"SHIELDS":
			return "SHD"
		"HANGAR":
			return "HGR"
		"MEDICAL":
			return "MED"
		"SECURITY":
			return "SEC"
		"WORKSHOP":
			return "SHOP"
		"CARGO":
			return "CARGO"
		_:
			return "GRID"
