extends Control

const CELL_SIZE := 10
const CANVAS_PADDING := Vector2(10, 22)
const GRID_GEOMETRY := preload("res://scripts/grid_geometry.gd")
const WEAPON_MOUNT_SOCKET := preload("res://scripts/weapon_mount_socket.gd")
const ROOM_STAFFING_RULES := preload("res://scripts/room_staffing_rules.gd")
const DOOR_VISUALS := preload("res://scripts/door_visuals.gd")
const CREW_ANIMATION_RANGES := {
	"Idle": Vector2i(0, 1),
	"Walk": Vector2i(2, 11),
	"Pistol_idle": Vector2i(24, 25),
	"Rest": Vector2i(37, 37),
	"Die": Vector2i(36, 37),
}
const CREW_FRAME_DURATION_MS := 100
const CREW_CLOSE_DETAIL_SCALE := 2.0
const STANDARD_ROOM_LATTICE_SIZE := Vector2i(2, 2)
const QUARTER_ROOM_LATTICE_SIZE := Vector2i.ONE
const QUARTER_ROOM_BASE := preload("res://assets/sprites/interiors/rooms/quarter/base.png")
const QUARTER_ROOM_CONNECTOR := preload("res://assets/sprites/interiors/rooms/quarter/connector.png")
const STANDARD_ROOM_FLOOR := preload("res://assets/sprites/interiors/rooms/standard/masks/floor.png")
const STANDARD_CREW_QUARTERS_OVERLAY := preload("res://assets/sprites/interiors/rooms/standard/overlays/crew_quarters.png")
const STANDARD_BRIDGE_OVERLAY := preload("res://assets/sprites/interiors/rooms/standard/overlays/bridge.png")
const STANDARD_REACTOR_OVERLAY := preload("res://assets/sprites/interiors/rooms/standard/overlays/reactor.png")
const STANDARD_THRUSTER_OVERLAY := preload("res://assets/sprites/interiors/rooms/standard/overlays/thruster.png")
const STANDARD_SHIELD_OVERLAY := preload("res://assets/sprites/interiors/rooms/standard/overlays/shield.png")
const STANDARD_NARROW_WEAPON_OVERLAY := preload("res://assets/sprites/interiors/rooms/standard/overlays/weapon_narrow.png")
const STANDARD_NARROW_WEAPON_CUTOUT := preload("res://assets/sprites/interiors/rooms/standard/overlays/weapon_narrow_cutout.png")
const STANDARD_ROOM_SOURCE_PIXELS := 160.0
## Door-mask bits are N=1, E=2, S=4, W=8. The authored perimeter layers
## remain completely inside their own 160px room canvas; neighboring rooms
## contribute their matching half of the shared wall/door.
const STANDARD_ROOM_PERIMETERS := {
	0: preload("res://assets/sprites/interiors/rooms/standard/masks/walls_0000.png"),
	1: preload("res://assets/sprites/interiors/rooms/standard/masks/walls_0001_n.png"),
	2: preload("res://assets/sprites/interiors/rooms/standard/masks/walls_0010_e.png"),
	3: preload("res://assets/sprites/interiors/rooms/standard/masks/walls_0011_ne.png"),
	4: preload("res://assets/sprites/interiors/rooms/standard/masks/walls_0100_s.png"),
	5: preload("res://assets/sprites/interiors/rooms/standard/masks/walls_0101_ns.png"),
	6: preload("res://assets/sprites/interiors/rooms/standard/masks/walls_0110_es.png"),
	7: preload("res://assets/sprites/interiors/rooms/standard/masks/walls_0111_nes.png"),
	8: preload("res://assets/sprites/interiors/rooms/standard/masks/walls_1000_w.png"),
	9: preload("res://assets/sprites/interiors/rooms/standard/masks/walls_1001_nw.png"),
	10: preload("res://assets/sprites/interiors/rooms/standard/masks/walls_1010_ew.png"),
	11: preload("res://assets/sprites/interiors/rooms/standard/masks/walls_1011_new.png"),
	12: preload("res://assets/sprites/interiors/rooms/standard/masks/walls_1100_sw.png"),
	13: preload("res://assets/sprites/interiors/rooms/standard/masks/walls_1101_nsw.png"),
	14: preload("res://assets/sprites/interiors/rooms/standard/masks/walls_1110_esw.png"),
	15: preload("res://assets/sprites/interiors/rooms/standard/masks/walls_1111_nesw.png"),
}
## A standard room edge is two quarter-lattice cells wide. These authored
## variants open only one of those two cells, allowing half-offset rooms to
## meet without falling back to a centered full-width doorway.
const STANDARD_ROOM_HALF_PERIMETERS := {
	"n_l": preload("res://assets/sprites/interiors/rooms/standard/half_masks/half_n_l.png"),
	"n_r": preload("res://assets/sprites/interiors/rooms/standard/half_masks/half_n_r.png"),
	"e_t": preload("res://assets/sprites/interiors/rooms/standard/half_masks/half_e_t.png"),
	"e_b": preload("res://assets/sprites/interiors/rooms/standard/half_masks/half_e_b.png"),
	"s_l": preload("res://assets/sprites/interiors/rooms/standard/half_masks/half_s_l.png"),
	"s_r": preload("res://assets/sprites/interiors/rooms/standard/half_masks/half_s_r.png"),
	"w_t": preload("res://assets/sprites/interiors/rooms/standard/half_masks/half_w_t.png"),
	"w_b": preload("res://assets/sprites/interiors/rooms/standard/half_masks/half_w_b.png"),
}
const STANDARD_ROOM_ART_PIXELS := 160
const STANDARD_ROOM_EDGE_PIXELS := 16
const STANDARD_ROOM_HALF_DOOR_PIXELS := 32
## The first half-door layers were authored on whole 16px art tiles, placing
## their apertures at 32..64 and 96..128. A physically half-offset room begins
## 80px away, so those local openings miss each other by 16px. At runtime we
## preserve the authored aperture but center it inside its physical 80px half:
## 24..56 and 104..136. Both sides then resolve to the exact same world strip.
const STANDARD_ROOM_HALF_DOOR_SOURCE_STARTS := [32, 96]
const STANDARD_ROOM_HALF_DOOR_TARGET_STARTS := [24, 104]

var standard_weapon_cutout_texture_cache: Dictionary = {}

@export var ship_layout: Resource
## Static builder previews reuse the authored room renderer without live crew,
## damage, doors, or combat animation layered on top.
@export var blueprint_preview_mode := false

@export_category("Grid Indicators")
## Color used to mark exposed, space-facing edges of grid modules.
@export var hull_edge_indicator_color := Color(1.0, 0.58, 0.18, 0.92)
## Width of exposed hull-edge indicators in tactical pixels.
@export_range(0.5, 5.0, 0.25) var hull_edge_indicator_width := 1.5
## Color used by weapon and module facing indicators.
@export var module_facing_indicator_color := Color(0.2, 0.95, 1.0, 0.95)
## Width of module direction indicator lines.
@export_range(0.5, 5.0, 0.25) var module_facing_indicator_width := 1.5
## Length of the module-facing arrow inside its room or hardpoint.
@export_range(3.0, 20.0, 0.5) var module_facing_arrow_length := 9.0
## Recessed metal color used for dormant thruster nozzles.
@export var thruster_indicator_color := Color(0.16, 0.19, 0.19, 1.0)
## Color of the short thrust plume drawn outside a thruster module.
@export var thruster_plume_color := Color(0.95, 0.62, 0.24, 0.72)
## Hot inner color used by active thrust plumes.
@export var active_thruster_core_color := Color(1.0, 0.9, 0.46, 0.98)
## Outer flame color used by active thrust plumes.
@export var active_thruster_flame_color := Color(1.0, 0.54, 0.12, 0.82)
## Tactical-pixel length multiplier for active thrust plumes.
@export_range(0.2, 4.0, 0.1) var active_thruster_plume_scale := 1.2
@export_category("Hull Style")
## Tactical view defaults to a clean exterior silhouette instead of showing the room grid.
@export var tactical_hull_only_mode := true
## Main exterior hull fill used when Tactical view hides individual rooms.
@export var tactical_hull_fill_color := Color(0.11, 0.16, 0.17, 1.0)
## Subtle inner metal tint used to keep the silhouette from looking flat.
@export var tactical_hull_core_color := Color(0.18, 0.23, 0.24, 0.9)
## Color for small tactical hardpoint hints such as weapons, hangars, and docking ports.
@export var tactical_system_marker_color := Color(0.28, 0.96, 1.0, 0.88)
## Fine module seams remain visible at tactical scale so the hull still reads as
## a collection of physical grid pieces rather than one featureless polygon.
@export var tactical_module_seam_color := Color(0.28, 0.78, 0.72, 0.78)
## Steel color used for the ship's outer physical hull line.
@export var outer_hull_color := Color(0.48, 0.53, 0.55, 1.0)
## Width of the steel outer hull line in tactical pixels.
@export_range(1.0, 8.0, 1.0) var outer_hull_width := 3.0

var selected_room_ids: Array[StringName] = []
var targeted_room_id: StringName = &""
var hovered_room_id: StringName = &""
var simulation_faction := 0
var simulation_ship_id := 0
var low_detail_mode := false
var tactical_interest_room_types := PackedStringArray(["DOCKING", "WEAPONS", "HANGAR"])
var visual_forward_throttle := 0.0
var visual_brake_throttle := 0.0
var visual_turn_command := 0.0
var visual_translation_exhaust := Vector2.ZERO
var plume_animation_time := 0.0
var direct_fire_states: Dictionary = {}
var geometry_cache_signature := 0
var cached_hull_cells: Dictionary = {}
var cached_room_cells: Dictionary = {}
var cached_hull_boundary_segments: Array[Dictionary] = []
var cached_exterior_replaced_edges: Dictionary = {}
var module_piece_view_cache: Dictionary = {}
var standard_room_segment_perimeter_cache: Dictionary = {}
var weapon_mount_visuals: Dictionary = {}
var weapon_mount_visual_signature := ""


func _ready() -> void:
	if ship_layout == null:
		push_error("TacticalShipVisual requires a ship layout resource.")
		return
	if not blueprint_preview_mode:
		add_to_group("weapon_mount_visual_provider")
	if ship_layout.has_method("ensure_quarter_lattice"):
		ship_layout.call("ensure_quarter_lattice")
	set_process(true)
	_update_size_from_layout()
	_sync_weapon_mount_visuals(true)
	queue_redraw()


func _process(delta: float) -> void:
	plume_animation_time += delta
	_sync_weapon_mount_visuals()
	if not tactical_hull_only_mode or _has_active_thruster_visuals() or not direct_fire_states.is_empty():
		queue_redraw()


func _draw() -> void:
	var hull_cells := _all_occupied_cells()
	if low_detail_mode:
		_draw_low_detail()
		return
	if tactical_hull_only_mode:
		_draw_tactical_hull_exterior(hull_cells)
		return
	var all_authored_cells: Dictionary = {}
	for authored_room: Resource in _rooms():
		for authored_cell_value: Variant in _standard_skin_cells(authored_room).keys():
			all_authored_cells[authored_cell_value] = true
	for hull_cell_value: Variant in hull_cells.keys():
		var hull_cell: Vector2i = hull_cell_value
		# Authored room floors are opaque wherever deck exists. Do not paint the
		# legacy dark cell backing beneath them: real transparent apertures (such
		# as an exposed weapon well) must reveal the world and stars below.
		if all_authored_cells.has(hull_cell):
			continue
		draw_rect(_get_grid_rect(Rect2i(hull_cell, Vector2i.ONE)), Color(0.055, 0.075, 0.08), true)

	for room: Resource in _rooms():
		var authored_cells := _standard_skin_cells(room)
		for cell_value: Variant in _room_cells(room).keys():
			var cell: Vector2i = cell_value
			# The authored standard-room canvas owns its entire visual footprint.
			# Letting the old solid room color show through its transparent edge
			# creates a false colored outline and makes adjacent modules appear
			# separated even though their grid footprints touch.
			if authored_cells.has(cell):
				continue
			draw_rect(_get_grid_rect(Rect2i(cell, Vector2i.ONE)), room.get("color"), true)

	_draw_standard_room_skins(hull_cells)

	for room: Resource in _rooms():
		# Standard rooms supply their own finished walls. Drawing the old
		# procedural seam over them makes the authored side rails look pinched
		# and fuzzy at close zoom. Non-standard shapes keep the fallback until
		# they receive their own artwork.
		if not _room_uses_standard_skin(room):
			_draw_room_boundary(room, Color(0.64, 0.76, 0.74, 0.45), 1.0)
		_draw_grouped_piece_dividers(room)
		if room.get("type_name") in ["WEAPONS", "PROPULSION", "HANGAR", "DOCKING"] or room.get("module_recipe") != null:
			if String(room.get("type_name")) in ["WEAPONS", "PROPULSION"]:
				for mount_room: Resource in _module_piece_views(room):
					# Authored gun art communicates its facing directly. Keep the cyan
					# arrow only as a fallback for modules that do not have a sprite.
					if _room_uses_authored_weapon_mount(mount_room):
						continue
					_draw_module_facing_indicator(mount_room, hull_cells)
			else:
				_draw_module_facing_indicator(room, hull_cells)
	# The ship-wide silhouette belongs to tactical zoom only. At close zoom the
	# authored room walls (and procedural fallbacks above) are the physical hull,
	# so an additional contour would sit on top of the room art.
	for room: Resource in _rooms():
		var room_id: StringName = room.get("room_id")
		if not blueprint_preview_mode and String(room.get("type_name")) == "HANGAR":
			_draw_docked_fighters(room)
		if not blueprint_preview_mode and String(room.get("type_name")) == "WEAPONS":
			_draw_weapon_operation(room, hull_cells)
			_draw_direct_fire_state(room)
		if selected_room_ids.has(room_id):
			_draw_room_boundary(room, Color(0.25, 1.0, 0.82), 3.0)
		if room_id == targeted_room_id:
			_draw_room_boundary(room, Color(1.0, 0.25, 0.2), 4.0)
		elif room_id == hovered_room_id:
			_draw_room_boundary(room, Color(1.0, 0.72, 0.24), 2.0)
	# Doors sit above the authored room walls but below crew, so the physical
	# threshold remains readable without covering anyone walking through it.
	if not blueprint_preview_mode:
		_draw_simulated_doors()
		_draw_structural_damage()
		_draw_live_crew()


## Selects one complete authored perimeter from the room's N/E/S/W neighbor
## mask. A full room is 2x2 cells in the quarter-module lattice. Smaller and
## elongated modules intentionally stay on their procedural fallback until
## they receive their own authored source files.
func _draw_standard_room_skins(_hull_cells: Dictionary) -> void:
	var room_owner_by_cell: Dictionary = {}
	var room_id_by_cell: Dictionary = {}
	for room: Resource in _rooms():
		var room_id: StringName = room.get("room_id")
		# Track the authored piece, not merely its combined room. Two touching
		# pieces can belong to one merged room while still requiring two distinct
		# half-door openings along a neighbor's edge.
		var piece_rects := _room_rects(room)
		for piece_index: int in range(piece_rects.size()):
			var owner_key := "%s:%d" % [String(room_id), piece_index]
			var owner_rect: Rect2i = piece_rects[piece_index]
			for y: int in range(owner_rect.position.y, owner_rect.end.y):
				for x: int in range(owner_rect.position.x, owner_rect.end.x):
					var cell := Vector2i(x, y)
					room_owner_by_cell[cell] = owner_key
					room_id_by_cell[cell] = room_id
	for room: Resource in _rooms():
		var room_id: StringName = room.get("room_id")
		var piece_rects: Array[Rect2i] = _room_rects(room)
		for piece_index: int in range(piece_rects.size()):
			var piece_rect: Rect2i = piece_rects[piece_index]
			if piece_rect.size == QUARTER_ROOM_LATTICE_SIZE and ROOM_STAFFING_RULES.is_unmanned_exterior_module(room):
				_draw_quarter_room_piece(piece_rect, room, piece_index, _hull_cells)
				continue
			if piece_rect.size != STANDARD_ROOM_LATTICE_SIZE:
				continue
			_draw_standard_room_piece(piece_rect, room_id, piece_index, room_owner_by_cell, room_id_by_cell)


## Quarter-room source art is an 80px one-cell module. The connector was
## authored facing west/left; installed modules face outward, so the connector
## rotates to the opposite quarter and visually meets the rest of the hull.
func _draw_quarter_room_piece(
	piece_rect: Rect2i,
	room: Resource,
	piece_index: int,
	hull_cells: Dictionary
) -> void:
	var destination := _get_grid_rect(piece_rect)
	draw_texture_rect(QUARTER_ROOM_BASE, destination, false)
	var attachment_quarter := _quarter_attachment_quarter(piece_rect, room, piece_index, hull_cells)
	var connector_rotation := float(posmod(attachment_quarter - 3, 4)) * PI * 0.5
	draw_set_transform(destination.get_center(), connector_rotation)
	draw_texture_rect(
		QUARTER_ROOM_CONNECTOR,
		Rect2(-destination.size * 0.5, destination.size),
		false
	)
	draw_set_transform(Vector2.ZERO, 0.0)


func _quarter_attachment_quarter(
	piece_rect: Rect2i,
	room: Resource,
	piece_index: int,
	hull_cells: Dictionary
) -> int:
	var room_cells := _room_cells(room)
	for quarter: int in range(4):
		var neighbor := piece_rect.position + GRID_GEOMETRY.quarter_direction(quarter)
		if hull_cells.has(neighbor) and not room_cells.has(neighbor):
			return quarter
	# A temporarily detached Forge preview has no neighbor yet. Keep its connector
	# on the intended inward side until it is placed beside another hull piece.
	return posmod(_standard_piece_facing(room, piece_index) + 2, 4)


func _draw_standard_room_piece(
	piece_rect: Rect2i,
	room_id: StringName,
	piece_index: int,
	room_owner_by_cell: Dictionary,
	room_id_by_cell: Dictionary
) -> void:
	var destination := _get_grid_rect(piece_rect)
	var source_room := _get_room_by_id(room_id)
	var weapon_facing := _standard_piece_facing(source_room, piece_index)
	var uses_narrow_weapon_skin := _standard_room_uses_narrow_weapon_skin(source_room)
	var floor_texture: Texture2D = STANDARD_ROOM_FLOOR
	if uses_narrow_weapon_skin:
		floor_texture = _standard_texture_with_weapon_cutout(STANDARD_ROOM_FLOOR, weapon_facing)
	draw_texture_rect(floor_texture, destination, false)
	if source_room != null and String(source_room.get("type_name")) == "COMMAND":
		_draw_standard_oriented_overlay(STANDARD_BRIDGE_OVERLAY, source_room, piece_index, destination)
	elif source_room != null and String(source_room.get("type_name")) == "POWER":
		_draw_standard_oriented_overlay(STANDARD_REACTOR_OVERLAY, source_room, piece_index, destination)
	elif source_room != null and String(source_room.get("type_name")) in ["CREW", "CREW_QUARTERS"]:
		draw_texture_rect(STANDARD_CREW_QUARTERS_OVERLAY, destination, false)
	elif source_room != null and String(source_room.get("type_name")) == "PROPULSION":
		_draw_standard_thruster_overlay(source_room, piece_index, destination)
	elif source_room != null and String(source_room.get("type_name")) == "SHIELDS":
		_draw_standard_oriented_overlay(STANDARD_SHIELD_OVERLAY, source_room, piece_index, destination)
	elif uses_narrow_weapon_skin:
		_draw_standard_narrow_weapon_overlay(source_room, weapon_facing, destination)
	var connection_segments := _standard_piece_connection_segments(piece_rect, room_id, room_owner_by_cell, room_id_by_cell)
	var perimeter := _standard_room_perimeter_for_segments(
		int(connection_segments.get("door_mask", 0)),
		int(connection_segments.get("open_mask", 0))
	)
	if uses_narrow_weapon_skin:
		perimeter = _standard_texture_with_weapon_cutout(perimeter, weapon_facing)
	draw_texture_rect(perimeter, destination, false)


## Bridge and reactor source art both face north. Keep their overlay rotation
## locked to the same installed module facing used by collision and stations.
func _draw_standard_oriented_overlay(texture: Texture2D, room: Resource, piece_index: int, destination: Rect2) -> void:
	var raw_facing := int(room.get("module_facing_quarters"))
	var mount_facings: Array = room.get("module_mount_facings")
	if piece_index >= 0 and piece_index < mount_facings.size():
		raw_facing = int(mount_facings[piece_index])
	var rotation := float(posmod(maxi(raw_facing, 0), 4)) * PI * 0.5
	draw_set_transform(destination.get_center(), rotation)
	draw_texture_rect(texture, Rect2(-destination.size * 0.5, destination.size), false)
	draw_set_transform(Vector2.ZERO, 0.0)


## Fixed, narrow-arc weapons use the authored casemate room. Broad exposed-edge
## turrets keep the ordinary room floor because they need several hull faces.
func _standard_room_uses_narrow_weapon_skin(room: Resource) -> bool:
	if room == null or String(room.get("type_name")) != "WEAPONS":
		return false
	var weapon: Resource = room.get("weapon_definition")
	if weapon == null or bool(weapon.get("uses_exposed_hull_edges")):
		return false
	return float(weapon.get("traverse_degrees")) < 90.0


func _standard_piece_facing(room: Resource, piece_index: int) -> int:
	if room == null:
		return 0
	var facing_quarters := int(room.get("module_facing_quarters"))
	var mount_facings: Array = room.get("module_mount_facings")
	if piece_index >= 0 and piece_index < mount_facings.size():
		facing_quarters = int(mount_facings[piece_index])
	return posmod(facing_quarters, 4)


## The source art faces down. Rotate its socket and casemate to the installed
## module direction. The authored explosive cannon then replaces the temporary
## X socket, anchored by its upper 2x2 tiles instead of by its full image size.
func _draw_standard_narrow_weapon_overlay(room: Resource, facing_quarters: int, destination: Rect2) -> void:
	var center := destination.get_center()
	var rotation := PI + float(posmod(facing_quarters, 4)) * PI * 0.5
	draw_set_transform(center, rotation)
	draw_texture_rect(
		STANDARD_NARROW_WEAPON_OVERLAY,
		Rect2(-destination.size * 0.5, destination.size),
		false
	)
	draw_set_transform(Vector2.ZERO, 0.0)


func _standard_room_uses_authored_explosive_cannon(room: Resource) -> bool:
	if room == null or String(room.get("type_name")) != "WEAPONS":
		return false
	var weapon: Resource = room.get("weapon_definition")
	if weapon == null or StringName(weapon.get("weapon_id")) != &"explosive_cannon":
		return false
	var rects: Array[Rect2i] = room.get("grid_rects")
	return rects.size() == 1 and rects[0].size == STANDARD_ROOM_LATTICE_SIZE


## Any weapon with scene-authored mount art communicates its facing through the
## barrel itself. The legacy cyan arrow is retained only for placeholder guns.
func _room_uses_authored_weapon_mount(room: Resource) -> bool:
	if room == null or String(room.get("type_name")) != "WEAPONS":
		return false
	var weapon: Resource = room.get("weapon_definition")
	return weapon != null and weapon.get("mount_visual_scene") is PackedScene


## Applies the authored yellow cutout as transparency. The mask is never drawn;
## both the room floor and its perimeter are cleared so the opening is actual
## visible space, including at the hull edge.
func _standard_texture_with_weapon_cutout(source_texture: Texture2D, facing_quarters: int) -> Texture2D:
	var facing := posmod(facing_quarters, 4)
	var cache_key := "%d:%d" % [source_texture.get_instance_id(), facing]
	if standard_weapon_cutout_texture_cache.has(cache_key):
		return standard_weapon_cutout_texture_cache[cache_key]
	# Texture2D.get_image() may return storage shared with subsequent reads.
	# Always edit a private copy so generating N/E/S/W variants cannot compound
	# transparency onto the source or onto one another.
	var target_image := source_texture.get_image().duplicate()
	var mask_image := STANDARD_NARROW_WEAPON_CUTOUT.get_image()
	var width := mini(target_image.get_width(), mask_image.get_width())
	var height := mini(target_image.get_height(), mask_image.get_height())
	# Source forward is south (quarter 2). Convert the target pixel back into
	# source-mask coordinates for the installed quarter-turn.
	var clockwise_turns := posmod(facing - 2, 4)
	for target_y: int in range(height):
		for target_x: int in range(width):
			var source_point := _weapon_cutout_source_point(
				Vector2i(target_x, target_y),
				width,
				height,
				clockwise_turns
			)
			var mask_pixel: Color = mask_image.get_pixelv(source_point)
			# The authored cutout convention is yellow. Ignore guide marks or
			# accidental visible pixels elsewhere on the layer.
			if mask_pixel.a <= 0.01 or mask_pixel.r < 0.55 or mask_pixel.g < 0.45 or mask_pixel.b > 0.35:
				continue
			var pixel: Color = target_image.get_pixel(target_x, target_y)
			pixel.a = 0.0
			target_image.set_pixel(target_x, target_y, pixel)
	var result := ImageTexture.create_from_image(target_image)
	standard_weapon_cutout_texture_cache[cache_key] = result
	return result


func _weapon_cutout_source_point(target: Vector2i, width: int, height: int, clockwise_turns: int) -> Vector2i:
	match posmod(clockwise_turns, 4):
		1:
			return Vector2i(target.y, height - 1 - target.x)
		2:
			return Vector2i(width - 1 - target.x, height - 1 - target.y)
		3:
			return Vector2i(width - 1 - target.y, target.x)
		_:
			return target


## The authored source points north. Rotate each physical thruster piece around
## its own room center so combined propulsion rooms retain independent nozzles.
func _draw_standard_thruster_overlay(room: Resource, piece_index: int, destination: Rect2) -> void:
	var facing_quarters := _standard_piece_facing(room, piece_index)
	var center := destination.get_center()
	# The authored overlay's nozzle points opposite the module-facing convention
	# used by the simulation, so turn the art half a rotation before applying the
	# installed thruster's saved quarter-turn direction.
	draw_set_transform(center, PI + float(posmod(facing_quarters, 4)) * PI * 0.5)
	draw_texture_rect(
		STANDARD_THRUSTER_OVERLAY,
		Rect2(-destination.size * 0.5, destination.size),
		false
	)
	draw_set_transform(Vector2.ZERO, 0.0)


func _standard_piece_edge_cell(piece_rect: Rect2i, direction: Vector2i, segment_index: int) -> Vector2i:
	match direction:
		Vector2i.UP:
			return piece_rect.position + Vector2i(segment_index, 0)
		Vector2i.RIGHT:
			return piece_rect.position + Vector2i(1, segment_index)
		Vector2i.DOWN:
			return piece_rect.position + Vector2i(segment_index, 1)
		_:
			return piece_rect.position + Vector2i(0, segment_index)


## Segment bits are N-L=1, N-R=2, E-T=4, E-B=8,
## S-L=16, S-R=32, W-T=64, W-B=128. Bits 8-11 mark an edge
## whose two occupied halves belong to different physical pieces; that edge
## needs two half doors instead of one centered full-side door. Connections to
## another piece of the same merged room are returned separately as open seams:
## they are continuous interior floor, not doors between rooms.
func _standard_piece_connection_segments(
	piece_rect: Rect2i,
	room_id: StringName,
	room_owner_by_cell: Dictionary,
	room_id_by_cell: Dictionary
) -> Dictionary:
	var door_mask := 0
	var open_mask := 0
	var directions := [
		{"vector": Vector2i.UP, "bits": [1, 2], "split_bit": 256},
		{"vector": Vector2i.RIGHT, "bits": [4, 8], "split_bit": 512},
		{"vector": Vector2i.DOWN, "bits": [16, 32], "split_bit": 1024},
		{"vector": Vector2i.LEFT, "bits": [64, 128], "split_bit": 2048},
	]
	for direction_data: Dictionary in directions:
		var direction: Vector2i = direction_data["vector"]
		var segment_bits: Array = direction_data["bits"]
		var segment_owners: Array[Variant] = [null, null]
		for segment_index: int in range(2):
			var edge_cell := _standard_piece_edge_cell(piece_rect, direction, segment_index)
			var neighbor_cell := edge_cell + direction
			if room_owner_by_cell.has(neighbor_cell):
				var segment_bit := int(segment_bits[segment_index])
				var neighbor_room_id := StringName(room_id_by_cell.get(neighbor_cell, &""))
				var neighbor_room := _get_room_by_id(neighbor_room_id)
				# Exterior quarter modules are bolted to the hull; they are not
				# walkable compartments and must not cut a doorway into this wall.
				if ROOM_STAFFING_RULES.is_unmanned_exterior_module(neighbor_room):
					continue
				if neighbor_room_id == room_id:
					open_mask |= segment_bit
				else:
					door_mask |= segment_bit
					segment_owners[segment_index] = room_owner_by_cell[neighbor_cell]
		if segment_owners[0] != null and segment_owners[1] != null and segment_owners[0] != segment_owners[1]:
			door_mask |= int(direction_data["split_bit"])
	return {"door_mask": door_mask, "open_mask": open_mask}


func _standard_room_perimeter_for_segments(segment_mask: int, open_mask: int) -> Texture2D:
	var cache_key := "%d:%d" % [segment_mask, open_mask]
	if standard_room_segment_perimeter_cache.has(cache_key):
		return standard_room_segment_perimeter_cache[cache_key]
	var perimeter_image := STANDARD_ROOM_PERIMETERS[0].get_image()
	_standard_room_replace_edge(perimeter_image, segment_mask & 3, 0, (segment_mask & 256) != 0)
	_standard_room_replace_edge(perimeter_image, (segment_mask >> 2) & 3, 1, (segment_mask & 512) != 0)
	_standard_room_replace_edge(perimeter_image, (segment_mask >> 4) & 3, 2, (segment_mask & 1024) != 0)
	_standard_room_replace_edge(perimeter_image, (segment_mask >> 6) & 3, 3, (segment_mask & 2048) != 0)
	_standard_room_clear_open_edge(perimeter_image, open_mask & 3, 0)
	_standard_room_clear_open_edge(perimeter_image, (open_mask >> 2) & 3, 1)
	_standard_room_clear_open_edge(perimeter_image, (open_mask >> 4) & 3, 2)
	_standard_room_clear_open_edge(perimeter_image, (open_mask >> 6) & 3, 3)
	var perimeter_texture := ImageTexture.create_from_image(perimeter_image)
	standard_room_segment_perimeter_cache[cache_key] = perimeter_texture
	return perimeter_texture


## Removes the authored wall band wherever another physical piece belongs to
## this same merged room. Half-open masks handle staggered/offset pieces; a
## value of 3 removes the complete shared side.
func _standard_room_clear_open_edge(target: Image, edge_state: int, edge_index: int) -> void:
	if edge_state == 0:
		return
	var half_pixels := STANDARD_ROOM_ART_PIXELS / 2
	for half_index: int in range(2):
		if (edge_state & (1 << half_index)) == 0:
			continue
		var clear_rect: Rect2i
		match edge_index:
			0:
				clear_rect = Rect2i(half_index * half_pixels, 0, half_pixels, STANDARD_ROOM_EDGE_PIXELS)
			1:
				clear_rect = Rect2i(STANDARD_ROOM_ART_PIXELS - STANDARD_ROOM_EDGE_PIXELS, half_index * half_pixels, STANDARD_ROOM_EDGE_PIXELS, half_pixels)
			2:
				clear_rect = Rect2i(half_index * half_pixels, STANDARD_ROOM_ART_PIXELS - STANDARD_ROOM_EDGE_PIXELS, half_pixels, STANDARD_ROOM_EDGE_PIXELS)
			_:
				clear_rect = Rect2i(0, half_index * half_pixels, STANDARD_ROOM_EDGE_PIXELS, half_pixels)
		target.fill_rect(clear_rect, Color.TRANSPARENT)


## Replaces only one 16px edge band. The source layers may contain a complete
## perimeter in Aseprite; cropping here prevents one variant from painting over
## a doorway selected on another edge.
func _standard_room_replace_edge(target: Image, edge_state: int, edge_index: int, split_edge: bool) -> void:
	if edge_state == 0:
		return
	if edge_state == 3 and split_edge:
		_standard_room_replace_split_edge(target, edge_index)
		return
	var source_texture: Texture2D
	match edge_index:
		0:
			source_texture = STANDARD_ROOM_PERIMETERS[1] if edge_state == 3 else STANDARD_ROOM_HALF_PERIMETERS["n_l" if edge_state == 1 else "n_r"]
		1:
			source_texture = STANDARD_ROOM_PERIMETERS[2] if edge_state == 3 else STANDARD_ROOM_HALF_PERIMETERS["e_t" if edge_state == 1 else "e_b"]
		2:
			source_texture = STANDARD_ROOM_PERIMETERS[4] if edge_state == 3 else STANDARD_ROOM_HALF_PERIMETERS["s_l" if edge_state == 1 else "s_r"]
		_:
			source_texture = STANDARD_ROOM_PERIMETERS[8] if edge_state == 3 else STANDARD_ROOM_HALF_PERIMETERS["w_t" if edge_state == 1 else "w_b"]
	var source_image := source_texture.get_image()
	if edge_state != 3:
		_standard_room_apply_centered_half_door(target, source_image, edge_index, edge_state - 1)
		return
	var edge_rect: Rect2i
	match edge_index:
		0:
			edge_rect = Rect2i(0, 0, STANDARD_ROOM_ART_PIXELS, STANDARD_ROOM_EDGE_PIXELS)
		1:
			edge_rect = Rect2i(STANDARD_ROOM_ART_PIXELS - STANDARD_ROOM_EDGE_PIXELS, 0, STANDARD_ROOM_EDGE_PIXELS, STANDARD_ROOM_ART_PIXELS)
		2:
			edge_rect = Rect2i(0, STANDARD_ROOM_ART_PIXELS - STANDARD_ROOM_EDGE_PIXELS, STANDARD_ROOM_ART_PIXELS, STANDARD_ROOM_EDGE_PIXELS)
		_:
			edge_rect = Rect2i(0, 0, STANDARD_ROOM_EDGE_PIXELS, STANDARD_ROOM_ART_PIXELS)
	target.blit_rect(source_image, edge_rect, edge_rect.position)


func _standard_room_replace_split_edge(target: Image, edge_index: int) -> void:
	var first_texture: Texture2D
	var second_texture: Texture2D
	match edge_index:
		0:
			first_texture = STANDARD_ROOM_HALF_PERIMETERS["n_l"]
			second_texture = STANDARD_ROOM_HALF_PERIMETERS["n_r"]
		1:
			first_texture = STANDARD_ROOM_HALF_PERIMETERS["e_t"]
			second_texture = STANDARD_ROOM_HALF_PERIMETERS["e_b"]
		2:
			first_texture = STANDARD_ROOM_HALF_PERIMETERS["s_l"]
			second_texture = STANDARD_ROOM_HALF_PERIMETERS["s_r"]
		_:
			first_texture = STANDARD_ROOM_HALF_PERIMETERS["w_t"]
			second_texture = STANDARD_ROOM_HALF_PERIMETERS["w_b"]
	_standard_room_apply_centered_half_door(target, first_texture.get_image(), edge_index, 0)
	_standard_room_apply_centered_half_door(target, second_texture.get_image(), edge_index, 1)


## Copies only the authored doorway aperture, repositioned to the center of the
## physical half-edge it represents. The untouched base perimeter supplies the
## corners and rails, so correcting a doorway cannot disturb adjacent edges.
func _standard_room_apply_centered_half_door(
	target: Image,
	source: Image,
	edge_index: int,
	half_index: int
) -> void:
	var resolved_half := clampi(half_index, 0, 1)
	var source_axis_start := int(STANDARD_ROOM_HALF_DOOR_SOURCE_STARTS[resolved_half])
	var target_axis_start := int(STANDARD_ROOM_HALF_DOOR_TARGET_STARTS[resolved_half])
	var source_rect: Rect2i
	var target_position: Vector2i
	match edge_index:
		0:
			source_rect = Rect2i(source_axis_start, 0, STANDARD_ROOM_HALF_DOOR_PIXELS, STANDARD_ROOM_EDGE_PIXELS)
			target_position = Vector2i(target_axis_start, 0)
		1:
			source_rect = Rect2i(STANDARD_ROOM_ART_PIXELS - STANDARD_ROOM_EDGE_PIXELS, source_axis_start, STANDARD_ROOM_EDGE_PIXELS, STANDARD_ROOM_HALF_DOOR_PIXELS)
			target_position = Vector2i(STANDARD_ROOM_ART_PIXELS - STANDARD_ROOM_EDGE_PIXELS, target_axis_start)
		2:
			source_rect = Rect2i(source_axis_start, STANDARD_ROOM_ART_PIXELS - STANDARD_ROOM_EDGE_PIXELS, STANDARD_ROOM_HALF_DOOR_PIXELS, STANDARD_ROOM_EDGE_PIXELS)
			target_position = Vector2i(target_axis_start, STANDARD_ROOM_ART_PIXELS - STANDARD_ROOM_EDGE_PIXELS)
		_:
			source_rect = Rect2i(0, source_axis_start, STANDARD_ROOM_EDGE_PIXELS, STANDARD_ROOM_HALF_DOOR_PIXELS)
			target_position = Vector2i(0, target_axis_start)
	target.blit_rect(source, source_rect, target_position)


func _draw_tactical_hull_exterior(hull_cells: Dictionary) -> void:
	_draw_tactical_hull_fill_runs(hull_cells)
	# Paint exterior extensions first, without their own outline. The complete
	# perimeter is stroked later as connected contours so profile-to-rail joins
	# are real line joins rather than two capped lines touching each other.
	_draw_special_exterior_profiles(hull_cells, outer_hull_color, outer_hull_width, tactical_hull_fill_color, true, false)
	# Draw only authored module boundaries here. The quarter lattice is an
	# implementation detail and must not turn the ship into a noisy checkerboard.
	for room: Resource in _rooms():
		_draw_room_boundary(room, tactical_module_seam_color, 1.0)
		_draw_grouped_piece_dividers(room)
	for room: Resource in _rooms():
		if _is_tactical_system_room(room):
			_draw_tactical_system_marker(room, hull_cells)
	# Keep nozzles and other edge hardware beneath the physical steel frame.
	_draw_profiled_hull_contours(hull_cells, outer_hull_color, outer_hull_width)
	_draw_structural_damage()
	for room: Resource in _rooms():
		var room_id: StringName = room.get("room_id")
		if String(room.get("type_name")) == "WEAPONS":
			_draw_direct_fire_state(room)
		if selected_room_ids.has(room_id):
			_draw_room_boundary(room, Color(0.25, 1.0, 0.82), 3.0)
		if room_id == targeted_room_id:
			_draw_room_boundary(room, Color(1.0, 0.25, 0.2), 4.0)
		elif room_id == hovered_room_id:
			_draw_room_boundary(room, Color(1.0, 0.72, 0.24), 2.0)


func _draw_tactical_hull_fill_runs(hull_cells: Dictionary) -> void:
	# The quarter lattice multiplied identical tactical fill calls by four. Merge
	# contiguous cells with the same authored offset into a single draw command;
	# the cached contour still provides the exact exterior silhouette afterward.
	var bounds := _bounds()
	for y: int in range(bounds.position.y, bounds.end.y):
		var run_start := 0
		var run_length := 0
		var run_offset := Vector2.ZERO
		for x: int in range(bounds.position.x, bounds.end.x + 1):
			var cell := Vector2i(x, y)
			var occupied := hull_cells.has(cell)
			var offset := GRID_GEOMETRY.cell_offset(ship_layout, cell) if occupied else Vector2(INF, INF)
			if occupied and run_length == 0:
				run_start = x
				run_length = 1
				run_offset = offset
			elif occupied and offset == run_offset:
				run_length += 1
			else:
				if run_length > 0:
					draw_rect(
						_get_grid_rect(Rect2i(Vector2i(run_start, y), Vector2i(run_length, 1))),
						tactical_hull_fill_color,
						true
					)
				run_start = x
				run_length = 1 if occupied else 0
				run_offset = offset


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
			_draw_dashed_divider(start, finish)


func _draw_dashed_divider(start: Vector2, finish: Vector2) -> void:
	var distance := start.distance_to(finish)
	if distance <= 0.001:
		return
	var direction := start.direction_to(finish)
	draw_line(start, finish, Color(0.01, 0.025, 0.03, 0.5), 2.0, false)
	var cursor := 0.0
	while cursor < distance:
		var segment_end := minf(cursor + 3.5, distance)
		draw_line(start + direction * cursor, start + direction * segment_end, Color(0.7, 0.84, 0.8, 0.68), 1.0, false)
		cursor += 6.0


func _is_tactical_system_room(room: Resource) -> bool:
	var type_name := String(room.get("type_name"))
	return type_name in ["WEAPONS", "PROPULSION", "HANGAR", "DOCKING", "SHIELDS"]


func _draw_tactical_system_marker(room: Resource, hull_cells: Dictionary) -> void:
	var type_name := String(room.get("type_name"))
	var room_cells := _room_cells(room)
	if room_cells.is_empty():
		return
	var center := get_room_local_center(room.get("room_id"))
	var direction := _module_facing_direction(room, room_cells, hull_cells)
	var side := direction.orthogonal()
	match type_name:
		"PROPULSION":
			# A merged propulsion bay is one room for staffing/damage, but each
			# installed thruster remains physical hardware with its own nozzle.
			for mount_room: Resource in _module_piece_views(room):
				var mount_cells := _build_room_cells(mount_room)
				var mount_direction := _module_facing_direction(mount_room, mount_cells, hull_cells)
				_draw_thruster_indicator(
					mount_cells,
					mount_direction,
					_thruster_activity(mount_room, mount_direction)
				)
		"WEAPONS":
			for mount_room: Resource in _module_piece_views(room):
				var mount_center := _resource_room_center(mount_room)
				var mount_cells := _build_room_cells(mount_room)
				var weapon: Resource = mount_room.get("weapon_definition")
				var mount_direction := _module_facing_direction(
					mount_room,
					mount_cells,
					hull_cells
				)
				var weapon_family := "CANNON"
				if weapon != null:
					weapon_family = String(weapon.get("weapon_family"))
				# A dormant hardpoint is physical ship hardware, not a targeting
				# readout. Cyan/amber/red illumination belongs exclusively to the
				# direct-fire state drawn later in the frame.
				_draw_weapon_family_mount(
					mount_center,
					mount_direction,
					weapon_family,
					Color(0.92, 0.48, 0.18, 0.92),
					0.52
				)
		"SHIELDS":
			for mount_room: Resource in _module_piece_views(room):
				var mount_center := _resource_room_center(mount_room)
				var facing := GRID_GEOMETRY.resolved_module_facing(ship_layout, mount_room)
				var shield_direction := Vector2.UP.rotated(float(facing) * PI * 0.5)
				var emitter := mount_center + shield_direction * 4.0
				draw_line(mount_center, emitter, Color(0.18, 0.66, 0.72, 0.76), 1.2, false)
				draw_circle(emitter, 2.2, Color(0.28, 0.94, 1.0, 0.92), true)
		"HANGAR":
			var bay_center := center + direction * 5.5
			draw_line(bay_center - side * 5.0, bay_center + side * 5.0, tactical_system_marker_color, 2.0, false)
			_draw_docked_fighters(room)
		"DOCKING":
			draw_line(center - side * 5.0, center + side * 5.0, Color(0.95, 0.68, 0.24, 0.9), 1.6, false)
			draw_line(center, center + direction * 8.0, Color(0.95, 0.68, 0.24, 0.65), 1.2, false)


func _draw_structural_damage() -> void:
	var combat := get_tree().get_first_node_in_group("combat_simulation")
	if not is_instance_valid(combat):
		return
	var structure: ShipStructuralState = combat.call("get_structural_state", simulation_faction, simulation_ship_id)
	if structure == null or structure.material == null:
		return
	var bounds := _bounds()
	for wall_value: Variant in structure.walls.values():
		var wall: Dictionary = wall_value
		var start := CANVAS_PADDING + (Vector2(wall["start"]) - Vector2(bounds.position)) * CELL_SIZE
		var finish := CANVAS_PADDING + (Vector2(wall["end"]) - Vector2(bounds.position)) * CELL_SIZE
		if bool(wall["breached"]):
			draw_line(start, finish, Color(0.008, 0.012, 0.015), outer_hull_width + 2.0, false)
			draw_circle(start, 1.5, structure.material.get("breach_marker_color"))
			draw_circle(finish, 1.5, structure.material.get("breach_marker_color"))
		else:
			var health: float = float(wall["current"]) / maxf(float(wall["maximum"]), 0.001)
			if health < 0.999:
				var color: Color = structure.material.get("damaged_wall_color").lerp(structure.material.get("healthy_wall_color"), health)
				draw_line(start, finish, color, outer_hull_width + 0.5, false)


func _draw_simulated_doors() -> void:
	var structure := _get_structural_state()
	if structure == null or structure.door_definition == null:
		return
	var bounds := _bounds()
	for door_value: Variant in structure.doors.values():
		var door: Dictionary = door_value
		var start := CANVAS_PADDING + (Vector2(door["start"]) - Vector2(bounds.position)) * CELL_SIZE
		var finish := CANVAS_PADDING + (Vector2(door["end"]) - Vector2(bounds.position)) * CELL_SIZE
		var openness := clampf(float(door["openness"]), 0.0, 1.0)
		var locked := bool(door["locked"]) or bool(door["pressure_interlocked"])
		DOOR_VISUALS.draw_door(self, start, finish, openness, locked)


func _get_structural_state() -> ShipStructuralState:
	var combat := get_tree().get_first_node_in_group("combat_simulation")
	if not is_instance_valid(combat):
		return null
	return combat.call("get_structural_state", simulation_faction, simulation_ship_id)


func set_simulation_identity(faction: int, ship_id: int) -> void:
	if simulation_faction == faction and simulation_ship_id == ship_id:
		return
	simulation_faction = faction
	simulation_ship_id = ship_id
	queue_redraw()


func set_ship_layout(layout: Resource) -> void:
	if layout == null:
		return
	# Live refits mutate the existing layout resource in place. Even when the
	# object identity is unchanged, its bounds, room pieces, and mount centers may
	# have changed and every geometry-dependent visual cache must be rebuilt.
	ship_layout = layout
	geometry_cache_signature = 0
	cached_hull_cells.clear()
	cached_room_cells.clear()
	cached_hull_boundary_segments.clear()
	cached_exterior_replaced_edges.clear()
	if ship_layout.has_method("ensure_quarter_lattice"):
		ship_layout.call("ensure_quarter_lattice")
	for label: Label in find_children("*", "Label", true, false):
		if label.get_parent() == self:
			label.queue_free()
	_update_size_from_layout()
	_sync_weapon_mount_visuals(true)
	queue_redraw()


func set_low_detail_mode(is_enabled: bool) -> void:
	if low_detail_mode == is_enabled:
		return
	low_detail_mode = is_enabled
	_sync_weapon_mount_visuals(true)
	queue_redraw()


func set_deck_detail_visible(is_visible: bool) -> void:
	var next_hull_only := not is_visible
	if tactical_hull_only_mode == next_hull_only:
		return
	tactical_hull_only_mode = next_hull_only
	_sync_weapon_mount_visuals(true)
	queue_redraw()


func _sync_weapon_mount_visuals(force: bool = false) -> void:
	if ship_layout == null:
		return
	var entries: Array[Dictionary] = []
	var signature_parts := PackedStringArray([str(tactical_hull_only_mode), str(low_detail_mode)])
	for room: Resource in _rooms():
		if String(room.get("type_name")) != "WEAPONS":
			continue
		var weapon: Resource = room.get("weapon_definition")
		var mount_scene := weapon.get("mount_visual_scene") as PackedScene if weapon != null else null
		if mount_scene == null:
			continue
		var rects: Array[Rect2i] = room.get("grid_rects")
		var facings: Array = room.get("module_mount_facings")
		for mount_index: int in range(rects.size()):
			if rects[mount_index].size not in [STANDARD_ROOM_LATTICE_SIZE, QUARTER_ROOM_LATTICE_SIZE]:
				continue
			var facing := int(room.get("module_facing_quarters"))
			if mount_index < facings.size():
				facing = int(facings[mount_index])
			var key := "%s#%d" % [String(room.get("room_id")), mount_index]
			entries.append({"key": key, "scene": mount_scene, "rect": rects[mount_index], "facing": facing})
			signature_parts.append("%s:%s:%d:%d" % [key, str(rects[mount_index]), facing, mount_scene.get_instance_id()])
	var next_signature := "|".join(signature_parts)
	if not force and next_signature == weapon_mount_visual_signature:
		return
	weapon_mount_visual_signature = next_signature
	var live_keys: Dictionary = {}
	for entry: Dictionary in entries:
		var key: String = entry["key"]
		live_keys[key] = true
		var mount := weapon_mount_visuals.get(key) as Node2D
		if not is_instance_valid(mount):
			mount = (entry["scene"] as PackedScene).instantiate() as Node2D
			if mount == null:
				continue
			mount.name = "WeaponMount_%s" % key.replace("#", "_")
			add_child(mount)
			weapon_mount_visuals[key] = mount
		if mount.has_method("set_installed_facing_quarters"):
			mount.call("set_installed_facing_quarters", int(entry["facing"]))
		var room_rect := _get_grid_rect(entry["rect"])
		var socket_position := room_rect.get_center()
		var installed_rect: Rect2i = entry["rect"]
		if installed_rect.size == STANDARD_ROOM_LATTICE_SIZE:
			socket_position = WEAPON_MOUNT_SOCKET.standard_room_socket_position(
				room_rect,
				int(entry["facing"])
			)
		# Every authored mount exposes the center of its round turret base as
		# TurretBase. Keeping this explicit prevents differently sized barrels
		# from shifting the mount according to their overall sprite bounds.
		var turret_base := mount.get_node_or_null("TurretBase") as Marker2D
		mount.position = socket_position
		if turret_base != null and not turret_base.position.is_zero_approx():
			mount.position -= (turret_base.position * mount.scale).rotated(mount.rotation)
		var weapon_definition: Resource = _get_room_by_id(StringName(key.get_slice("#", 0))).get("weapon_definition")
		if weapon_definition != null and "traverse_degrees" in mount:
			# An exposed quarter-grid turret is not tied to one authored hull face.
			# Combat combines all of its exposed faces and performs the real hull-
			# clearance test, so its artwork must be free to follow that resulting
			# controller/mouse bearing rather than clamping around installation facing.
			var visual_traverse := float(weapon_definition.get("traverse_degrees"))
			if bool(weapon_definition.get("uses_exposed_hull_edges")):
				visual_traverse = 180.0
			mount.set("traverse_degrees", visual_traverse)
		mount.visible = not tactical_hull_only_mode and not low_detail_mode
	for old_key_value: Variant in weapon_mount_visuals.keys():
		var old_key := String(old_key_value)
		if live_keys.has(old_key):
			continue
		var old_mount := weapon_mount_visuals[old_key] as Node
		if is_instance_valid(old_mount):
			old_mount.queue_free()
		weapon_mount_visuals.erase(old_key)


## Returns the exact barrel-tip socket authored in the live weapon scene.
## The result is in ship-pivot space, matching the local coordinate system used
## by combat.  Keeping this on the rendered instance means room placement,
## installed facing, scene scale, and future firing animation are all already
## represented before a projectile is spawned.
func get_weapon_muzzle_ship_local_position(room_id: StringName, mount_index: int) -> Variant:
	_sync_weapon_mount_visuals()
	var key := "%s#%d" % [String(room_id), mount_index]
	var mount := weapon_mount_visuals.get(key) as Node2D
	if not is_instance_valid(mount):
		return null
	var muzzle := mount.get_node_or_null("Muzzle") as Marker2D
	if muzzle == null:
		return null
	# The mount is a direct child of this Control. Its transform contains the
	# authored scene scale and the installed N/E/S/W rotation. Subtracting the
	# same pivot used to position the ship converts the marker into simulation
	# ship-local space without re-deriving any offsets.
	return mount.transform * muzzle.position - pivot_offset


## Turns the authored mount itself toward the real world-space firing bearing.
## Combat calls this before sampling Muzzle, so the art and projectile always
## agree even for traversing weapons and rotated ships.
func aim_weapon_mount_world_direction(
		room_id: StringName,
		mount_index: int,
		world_direction: Vector2,
		play_fire_animation: bool = false
) -> void:
	_sync_weapon_mount_visuals()
	var key := "%s#%d" % [String(room_id), mount_index]
	var mount := weapon_mount_visuals.get(key) as Node2D
	if not is_instance_valid(mount) or world_direction.is_zero_approx():
		return
	var parent_direction := world_direction.rotated(-get_global_transform().get_rotation())
	if mount.has_method("aim_toward_parent_direction"):
		mount.call("aim_toward_parent_direction", parent_direction)
	if play_fire_animation and mount.has_method("play_fire"):
		mount.call("play_fire")
	queue_redraw()


func matches_weapon_mount_identity(faction: int, ship_id: int) -> bool:
	return simulation_faction == faction and simulation_ship_id == ship_id


func is_deck_detail_visible() -> bool:
	return not tactical_hull_only_mode


func set_tactical_interest_room_types(room_types: PackedStringArray) -> void:
	if room_types == tactical_interest_room_types:
		return
	tactical_interest_room_types = room_types
	queue_redraw()


func set_propulsion_visual_command(command: Dictionary) -> void:
	var next_forward := clampf(float(command.get("forward", 0.0)), 0.0, 1.0)
	var next_brake := clampf(float(command.get("brake", 0.0)), 0.0, 1.0)
	var next_turn := clampf(float(command.get("turn", 0.0)), -1.0, 1.0)
	var next_translation_exhaust: Vector2 = command.get("translation_exhaust", Vector2.ZERO)
	next_translation_exhaust = next_translation_exhaust.limit_length(1.0)
	if (
		is_equal_approx(next_forward, visual_forward_throttle)
		and is_equal_approx(next_brake, visual_brake_throttle)
		and is_equal_approx(next_turn, visual_turn_command)
		and next_translation_exhaust.is_equal_approx(visual_translation_exhaust)
	):
		return
	visual_forward_throttle = next_forward
	visual_brake_throttle = next_brake
	visual_turn_command = next_turn
	visual_translation_exhaust = next_translation_exhaust
	queue_redraw()


func clear_propulsion_visual_command() -> void:
	set_propulsion_visual_command({})


func _draw_low_detail() -> void:
	var center := size * 0.5
	var radius := minf(size.x, size.y) * 0.43
	var hull_cells := _all_occupied_cells()
	for room: Resource in _rooms():
		var type_name := String(room.get("type_name"))
		var base_color := Color(room.get("color"))
		var fill_alpha := 0.74 if tactical_interest_room_types.has(type_name) else 0.42
		for cells: Rect2i in _room_rects(room):
			draw_rect(_get_grid_rect(cells), Color(base_color, fill_alpha), true)
	_draw_hull_boundary(Color(0.44, 0.58, 0.6, 0.85), outer_hull_width + 1.0)
	_draw_hull_boundary(outer_hull_color, maxf(outer_hull_width - 1.0, 1.0))
	_draw_special_exterior_profiles(hull_cells, outer_hull_color, maxf(outer_hull_width - 1.0, 1.0))
	draw_arc(center, radius * 0.72, 0.0, TAU, 64, Color(0.28, 0.48, 0.5, 0.22), 1.1, true)
	draw_arc(center, radius * 0.42, 0.0, TAU, 48, Color(0.18, 0.34, 0.38, 0.18), 1.0, true)
	for room: Resource in _rooms():
		var type_name := String(room.get("type_name"))
		# Propulsion remains physically readable at low zoom even when it is not
		# part of the player's configurable tactical-interest overlay.
		if not tactical_interest_room_types.has(type_name) and type_name != "PROPULSION":
			continue
		if tactical_interest_room_types.has(type_name):
			for cells: Rect2i in _room_rects(room):
				var rect := _get_grid_rect(cells)
				draw_rect(rect, Color(room.get("color"), 0.86), true)
				draw_rect(rect, _tactical_interest_color(type_name), false, 1.45)
		if type_name == "DOCKING":
			var dock_center := get_room_local_center(room.get("room_id"))
			var direction := (dock_center - center).normalized()
			if direction.is_zero_approx():
				direction = Vector2.UP
			var dock_cross := direction.orthogonal() * 6.0
			draw_line(dock_center - direction * 8.0, dock_center + direction * 13.0, module_facing_indicator_color, 1.4, true)
			draw_line(dock_center - dock_cross, dock_center + dock_cross, module_facing_indicator_color, 1.1, true)
		elif type_name == "WEAPONS":
			for mount_room: Resource in _module_piece_views(room):
				_draw_low_detail_weapon_node(mount_room, hull_cells)
		elif type_name == "PROPULSION":
			for mount_room: Resource in _module_piece_views(room):
				var mount_cells := _build_room_cells(mount_room)
				var mount_direction := _module_facing_direction(mount_room, mount_cells, hull_cells)
				_draw_thruster_indicator(
					mount_cells,
					mount_direction,
					_thruster_activity(mount_room, mount_direction)
				)
		elif type_name == "HANGAR":
			_draw_low_detail_hangar_node(room, hull_cells)
	for room_id: StringName in selected_room_ids:
		var room := _get_room_by_id(room_id)
		if room != null:
			_draw_room_boundary(room, Color(0.25, 1.0, 0.82), 3.0)
	if targeted_room_id != &"":
		var target_room := _get_room_by_id(targeted_room_id)
		if target_room != null:
			_draw_room_boundary(target_room, Color(1.0, 0.25, 0.2), 4.0)
	elif hovered_room_id != &"":
		var hover_room := _get_room_by_id(hovered_room_id)
		if hover_room != null:
			_draw_room_boundary(hover_room, Color(1.0, 0.72, 0.24), 2.0)


func _tactical_interest_color(type_name: String) -> Color:
	match type_name:
		"DOCKING":
			return Color(0.95, 0.68, 0.24, 0.9)
		"WEAPONS":
			return Color(1.0, 0.34, 0.22, 0.9)
		"HANGAR":
			return Color(0.25, 0.95, 1.0, 0.9)
		_:
			return Color(0.72, 0.9, 0.9, 0.6)


func _draw_low_detail_weapon_node(room: Resource, hull_cells: Dictionary) -> void:
	var room_cells := _build_room_cells(room)
	var center := _resource_room_center(room)
	var direction := _module_facing_direction(room, room_cells, hull_cells)
	draw_circle(center, 3.2, Color(1.0, 0.34, 0.16, 0.92), true)
	draw_line(center, center + direction * 11.0, Color(1.0, 0.45, 0.18, 0.9), 2.2, true)


func _draw_low_detail_hangar_node(room: Resource, hull_cells: Dictionary) -> void:
	var room_cells := _room_cells(room)
	var center := get_room_local_center(room.get("room_id"))
	var direction := _module_facing_direction(room, room_cells, hull_cells)
	var side := direction.orthogonal()
	var mouth_center := center + direction * 8.0
	draw_line(mouth_center - side * 5.0, mouth_center + side * 5.0, Color(0.28, 1.0, 0.95, 0.9), 2.0, true)
	draw_line(center - side * 3.0, mouth_center - side * 5.0, Color(0.28, 1.0, 0.95, 0.55), 1.2, true)
	draw_line(center + side * 3.0, mouth_center + side * 5.0, Color(0.28, 1.0, 0.95, 0.55), 1.2, true)


func _has_active_thruster_visuals() -> bool:
	return (
		visual_forward_throttle > 0.01
		or visual_brake_throttle > 0.01
		or absf(visual_turn_command) > 0.01
		or visual_translation_exhaust.length_squared() > 0.001
	)


func _draw_docked_fighters(room: Resource) -> void:
	var combat := get_tree().get_first_node_in_group("combat_simulation")
	if not is_instance_valid(combat):
		return
	var craft: Array[Dictionary] = combat.call("get_hangar_craft", simulation_faction, simulation_ship_id, room.get("room_id"), true)
	var center := get_room_local_center(room.get("room_id"))
	var offsets := [Vector2(-3.0, -3.0), Vector2(3.0, -3.0), Vector2(-3.0, 3.0), Vector2(3.0, 3.0)]
	for index: int in range(mini(craft.size(), offsets.size())):
		var point: Vector2 = center + offsets[index]
		draw_colored_polygon(PackedVector2Array([point + Vector2(0, -2.2), point + Vector2(1.8, 1.8), point, point + Vector2(-1.8, 1.8)]), Color(0.72, 0.94, 0.92, 0.95))


func _draw_weapon_operation(room: Resource, hull_cells: Dictionary) -> void:
	var combat := get_tree().get_first_node_in_group("combat_simulation")
	if not is_instance_valid(combat):
		return
	var mount_rooms := _module_piece_views(room)
	for mount_index: int in range(mount_rooms.size()):
		var mount_room: Resource = mount_rooms[mount_index]
		var state: Dictionary = combat.call(
			"get_weapon_operation_state",
			simulation_faction,
			simulation_ship_id,
			room.get("room_id"),
			mount_index
		)
		var center := _resource_room_center(mount_room)
		var direction := _module_facing_direction(mount_room, _build_room_cells(mount_room), hull_cells)
		if String(state["state"]) == "FIRING":
			var weapon: Resource = mount_room.get("weapon_definition")
			# Authored mounts own their muzzle flashes and recoil. Keep the old
			# procedural flash only for weapons that have not received a scene yet.
			if weapon == null or not weapon.get("mount_visual_scene") is PackedScene:
				var muzzle := center + direction * 8.0
				draw_line(muzzle - direction.orthogonal() * 2.0, muzzle + direction * 5.0, Color(1.0, 0.82, 0.3), 2.0)
		elif String(state["state"]) == "RELOADING":
			var total := maxf(float(state["reload_total"]), 0.001)
			var progress := 1.0 - float(state["reload_remaining"]) / total
			draw_arc(center, 5.0, -PI * 0.5, -PI * 0.5 + TAU * progress, 10, Color(0.95, 0.58, 0.22, 0.8), 1.0)


func _draw_direct_fire_state(room: Resource) -> void:
	var room_id: StringName = room.get("room_id")
	var mount_rooms := _module_piece_views(room)
	for mount_index: int in range(mount_rooms.size()):
		var state_key := "%s#%d" % [String(room_id), mount_index]
		if not direct_fire_states.has(state_key) and not direct_fire_states.has(room_id):
			continue
		var state_value: Variant = direct_fire_states.get(
			state_key, direct_fire_states.get(room_id, &"BLOCKED")
		)
		var status := _direct_fire_status(state_value)
		var color := Color(0.36, 0.42, 0.43, 0.8)
		match status:
			&"READY":
				color = Color(0.28, 1.0, 0.78, 0.98)
			&"RELOADING":
				color = Color(1.0, 0.68, 0.2, 0.95)
			&"DISABLED":
				color = Color(1.0, 0.25, 0.16, 0.88)
		var pulse := 0.75 + sin(plume_animation_time * 7.0) * 0.2 if status == &"READY" else 0.8
		var mount_room: Resource = mount_rooms[mount_index]
		var center := _resource_room_center(mount_room)
		var weapon: Resource = mount_room.get("weapon_definition")
		var mount_visual_key := "%s#%d" % [String(room_id), mount_index]
		var authored_mount := weapon_mount_visuals.get(mount_visual_key) as Node2D
		if is_instance_valid(authored_mount):
			var sprite := authored_mount.get_node_or_null("Sprite") as Sprite2D
			if sprite != null:
				sprite.modulate = color.lerp(Color.WHITE, 0.72) if status != &"READY" else Color(1.12, 1.12, 1.12, 1.0)
			continue
		var quarters := GRID_GEOMETRY.weapon_coverage_quarters(ship_layout, mount_room, weapon)
		# Readiness belongs to each preserved hardpoint, never the shared room.
		draw_circle(center, 4.2, Color(color, 0.1 * pulse), true)
		draw_circle(center, 2.8, Color(color, pulse), true)
		for quarter: int in quarters:
			var direction := Vector2.UP.rotated(float(quarter) * PI * 0.5)
			var muzzle := center + direction * 9.0
			draw_line(center, muzzle, Color(color, pulse), 2.6, false)
			draw_circle(muzzle, 1.5, Color(color, pulse), true)


func _draw_live_crew() -> void:
	var crew := get_tree().get_first_node_in_group("crew_simulation")
	if not is_instance_valid(crew) or crew.get("crew_definition") == null:
		return
	var definition: Resource = crew.get("crew_definition")
	var base_color: Color = definition.get("base_color")
	for member: Dictionary in crew.get("crew_members"):
		if bool(member.get("ejected", false)) or int(member.get("carried_by", 0)) > 0:
			continue
		var point := (
			CANVAS_PADDING
			+ (Vector2(member.get("position", Vector2.ZERO)) - Vector2(_bounds().position)) * CELL_SIZE
		)
		var heading: Vector2 = member.get("facing_direction", Vector2.UP)
		if not _draw_crew_sprite(member, point, heading, definition):
			var color := base_color.lightened(float(member.get("color_shift", 0.0)) * 0.35)
			draw_circle(point, 1.9, Color(0.01, 0.02, 0.025, 0.95), true)
			draw_circle(point, 1.2, color, true)
		_draw_crew_spawn_effect(member, point)
	var captain: Dictionary = crew.get("captain_member")
	if not captain.is_empty():
		var captain_point := (
			CANVAS_PADDING
			+ (Vector2(captain.get("position", Vector2.ZERO)) - Vector2(_bounds().position)) * CELL_SIZE
		)
		var captain_heading: Vector2 = captain.get("facing_direction", Vector2.UP)
		_draw_captain_marker(captain_point)
		_draw_crew_sprite(captain, captain_point, captain_heading, definition)


func _draw_captain_marker(point: Vector2) -> void:
	var pulse := 0.78 + sin(float(Time.get_ticks_msec()) * 0.004) * 0.18
	var color := Color(0.16, 0.78, 1.0, pulse)
	draw_arc(point, 2.6, 0.0, TAU, 16, color, 0.65, false)
	draw_line(point + Vector2(-2.2, 2.8), point + Vector2(0.0, 4.0), color, 0.65, false)
	draw_line(point + Vector2(0.0, 4.0), point + Vector2(2.2, 2.8), color, 0.65, false)


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
		frame_offset = mini(
			int(float(member.get("incapacitated_seconds", 0.0)) * 1000.0 / CREW_FRAME_DURATION_MS),
			frame_count - 1
		)
	var frame_index := frame_range.x + frame_offset
	var source_rect := Rect2(Vector2(frame_index * frame_size.x, 0.0), Vector2(frame_size))
	var draw_size := (
		Vector2(frame_size)
		* float(definition.get("sprite_scale"))
		* (CELL_SIZE / 256.0)
		* CREW_CLOSE_DETAIL_SCALE
	)
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
	var working := bool(member.get("at_assignment", false)) or state in [
		"WORKING", "MANNING", "OUTFITTING", "SECURITY WATCH", "SECURITY PATROL"
	]
	return "Pistol_idle" if repairing or working else "Idle"


func _draw_crew_spawn_effect(member: Dictionary, point: Vector2) -> void:
	var remaining := float(member.get("spawn_visual_remaining", 0.0))
	if remaining <= 0.0:
		return
	var duration := maxf(float(member.get("spawn_visual_duration", 1.0)), 0.001)
	var progress := clampf(1.0 - remaining / duration, 0.0, 1.0)
	var color := Color(0.28, 1.0, 0.82, clampf(remaining / minf(duration, 0.45), 0.0, 1.0))
	draw_arc(point, lerpf(4.0, 2.4, progress), -PI * 0.5, -PI * 0.5 + TAU * progress, 12, color, 0.8, false)


func get_room_at_local_position(local_position: Vector2) -> Resource:
	var cell := GRID_GEOMETRY.cell_at_position(ship_layout, local_position, _bounds(), CELL_SIZE, CANVAS_PADDING)
	for room: Resource in _rooms():
		if _room_cells(room).has(cell):
			return room
	return null


func get_room_local_center(room_id: StringName) -> Vector2:
	for room: Resource in _rooms():
		if room.get("room_id") != room_id:
			continue
		var cells := _room_cells(room)
		if not cells.is_empty():
			var center := Vector2.ZERO
			for cell_value: Variant in cells.keys():
				center += _get_grid_rect(Rect2i(cell_value, Vector2i.ONE)).get_center()
			return center / float(cells.size())
	return size * 0.5


func _resource_room_center(room: Resource) -> Vector2:
	# A merged weapon room deliberately keeps one room_id for staffing/damage, but
	# each duplicated mount view has its own grid_rect. Looking it up through the
	# room-id cache collapses every mount back onto the combined compartment.
	var cells := _build_room_cells(room)
	if cells.is_empty():
		return size * 0.5
	var center := Vector2.ZERO
	for cell_value: Variant in cells.keys():
		center += _get_grid_rect(Rect2i(cell_value, Vector2i.ONE)).get_center()
	return center / float(cells.size())


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


func _get_room_by_id(room_id: StringName) -> Resource:
	for room: Resource in _rooms():
		if room.get("room_id") == room_id:
			return room
	return null


func set_manual_highlights(selected_ids: Array[StringName], target_id: StringName, hover_id: StringName = &"") -> void:
	selected_room_ids = selected_ids.duplicate()
	targeted_room_id = target_id
	hovered_room_id = hover_id
	queue_redraw()


func set_direct_fire_states(states: Dictionary) -> void:
	direct_fire_states = states.duplicate()
	_sync_weapon_mount_visuals()
	for key_value: Variant in weapon_mount_visuals.keys():
		var key := String(key_value)
		var mount := weapon_mount_visuals[key] as Node2D
		if is_instance_valid(mount):
			var sprite := mount.get_node_or_null("Sprite") as Sprite2D
			if sprite != null:
				sprite.modulate = Color.WHITE
			var state_value: Variant = direct_fire_states.get(key)
			if state_value is Dictionary:
				var local_aim: Vector2 = (state_value as Dictionary).get(
					"local_aim_direction", Vector2.ZERO
				)
				if not local_aim.is_zero_approx() and mount.has_method("aim_toward_parent_direction"):
					mount.call("aim_toward_parent_direction", local_aim)
	queue_redraw()


func _direct_fire_status(state_value: Variant) -> StringName:
	if state_value is Dictionary:
		return StringName((state_value as Dictionary).get("status", &"BLOCKED"))
	return StringName(state_value)


func get_hull_side_extremes(local_direction: Vector2) -> PackedVector2Array:
	var cardinal := Vector2i(roundi(local_direction.x), roundi(local_direction.y))
	if cardinal == Vector2i.ZERO:
		return PackedVector2Array()
	var hull_cells := _all_occupied_cells()
	var edge_points: Array[Vector2] = []
	for cell_value: Variant in hull_cells.keys():
		var cell := cell_value as Vector2i
		if GRID_GEOMETRY.face_contact_strength(ship_layout, cell, cardinal, hull_cells) >= 0.999:
			continue
		var rect := _get_grid_rect(Rect2i(cell, Vector2i.ONE))
		if cardinal == Vector2i.RIGHT:
			edge_points.append(Vector2(rect.end.x, rect.position.y))
			edge_points.append(rect.end)
		elif cardinal == Vector2i.LEFT:
			edge_points.append(rect.position)
			edge_points.append(Vector2(rect.position.x, rect.end.y))
		elif cardinal == Vector2i.UP:
			edge_points.append(rect.position)
			edge_points.append(Vector2(rect.end.x, rect.position.y))
		else:
			edge_points.append(Vector2(rect.position.x, rect.end.y))
			edge_points.append(rect.end)
	if edge_points.is_empty():
		return PackedVector2Array()
	var tangent := Vector2(cardinal).rotated(PI * 0.5)
	var minimum_point := edge_points[0]
	var maximum_point := edge_points[0]
	var minimum_projection := minimum_point.dot(tangent)
	var maximum_projection := minimum_projection
	for point: Vector2 in edge_points:
		var projection := point.dot(tangent)
		if projection < minimum_projection:
			minimum_projection = projection
			minimum_point = point
		if projection > maximum_projection:
			maximum_projection = projection
			maximum_point = point
	return PackedVector2Array([minimum_point, maximum_point])


func _create_labels() -> void:
	for room: Resource in _rooms():
		var label_text: String = room.get("grid_label")
		var rects := _room_rects(room)
		if rects.is_empty():
			continue
		if not label_text.is_empty():
			for cells: Rect2i in rects:
				_add_label("W", _get_grid_rect(cells), 6)
		else:
			var short_name: String = room.get("display_name")
			if room.get("room_id") == &"unassigned":
				short_name = "HULL"
			elif room.get("room_id") == &"engine":
				short_name = "THRUSTER"
			_add_label(short_name, _get_grid_rect(_largest_rect(rects)), 7)


func _add_label(label_text: String, label_rect: Rect2, font_size: int) -> void:
	var label := Label.new()
	label.text = label_text
	label.position = label_rect.position
	label.size = label_rect.size
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", Color(0.82, 0.88, 0.84))
	label.add_theme_font_size_override("font_size", font_size)
	add_child(label)


func _draw_weapon_barrel(room: Resource, _cells: Rect2i, room_rect: Rect2) -> void:
	var weapon: Resource = room.get("weapon_definition")
	var traverse := 0.0
	var color := Color(0.9, 0.58, 0.22)
	var family := "CANNON"
	if weapon != null:
		traverse = weapon.get("traverse_degrees")
		color = weapon.get("visual_color")
		family = String(weapon.get("weapon_family"))
	var center := room_rect.get_center()
	var mount_scale := clampf(minf(room_rect.size.x, room_rect.size.y) / 20.0, 0.5, 1.5)
	var quarters := GRID_GEOMETRY.weapon_coverage_quarters(ship_layout, room, weapon)
	for quarter: int in quarters:
		var coverage_direction := Vector2.UP.rotated(float(quarter) * PI * 0.5)
		_draw_weapon_family_mount(center, coverage_direction, family, color, mount_scale)
		var half_arc := maxf(traverse, 8.0)
		draw_arc(center, 8.0 * mount_scale, coverage_direction.angle() - deg_to_rad(half_arc), coverage_direction.angle() + deg_to_rad(half_arc), 12, Color(color, 0.65), maxf(mount_scale, 0.75))


func _draw_weapon_family_mount(
	center: Vector2,
	direction: Vector2,
	family: String,
	color: Color,
	scale_factor: float
) -> void:
	var side := direction.orthogonal()
	match family:
		"BALLISTIC":
			draw_circle(center, 3.4 * scale_factor, Color(0.03, 0.06, 0.065), true)
			draw_circle(center, 3.4 * scale_factor, color, false, 1.5 * scale_factor)
			draw_line(center + side * 1.5 * scale_factor, center + direction * 10.0 * scale_factor + side * 1.5 * scale_factor, color, 1.6 * scale_factor)
			draw_line(center - side * 1.5 * scale_factor, center + direction * 10.0 * scale_factor - side * 1.5 * scale_factor, color, 1.6 * scale_factor)
		"LASER":
			var nose := center + direction * 10.5 * scale_factor
			var diamond := PackedVector2Array([
				center - direction * 3.5 * scale_factor,
				center + side * 3.5 * scale_factor,
				center + direction * 3.5 * scale_factor,
				center - side * 3.5 * scale_factor,
			])
			draw_colored_polygon(diamond, Color(color, 0.42))
			draw_polyline(diamond + PackedVector2Array([diamond[0]]), color, 1.4 * scale_factor)
			draw_line(center + direction * 2.0 * scale_factor, nose, color.lightened(0.25), 1.4 * scale_factor)
		"ENERGY":
			draw_circle(center, 4.0 * scale_factor, Color(color, 0.22), true)
			draw_circle(center, 4.0 * scale_factor, color, false, 1.5 * scale_factor)
			draw_circle(center, 1.7 * scale_factor, color.lightened(0.35), true)
			draw_line(center + side * 2.4 * scale_factor, center + direction * 9.0 * scale_factor + side * 1.2 * scale_factor, color, 1.5 * scale_factor)
			draw_line(center - side * 2.4 * scale_factor, center + direction * 9.0 * scale_factor - side * 1.2 * scale_factor, color, 1.5 * scale_factor)
		"MISSILE":
			for offset: float in [-2.5, 0.0, 2.5]:
				var tube_center := center + side * offset * scale_factor
				draw_line(tube_center - direction * 2.0 * scale_factor, tube_center + direction * 7.0 * scale_factor, color, 1.7 * scale_factor)
				draw_circle(tube_center + direction * 7.0 * scale_factor, 1.0 * scale_factor, color.lightened(0.25), true)
		_:
			draw_rect(Rect2(center - Vector2(3.5, 3.5) * scale_factor, Vector2(7.0, 7.0) * scale_factor), Color(color, 0.34), true)
			draw_rect(Rect2(center - Vector2(3.5, 3.5) * scale_factor, Vector2(7.0, 7.0) * scale_factor), color, false, 1.5 * scale_factor)
			draw_line(center, center + direction * 13.0 * scale_factor, color, 3.0 * scale_factor)


func _largest_rect(rects: Array[Rect2i]) -> Rect2i:
	var largest := rects[0]
	for candidate: Rect2i in rects:
		if candidate.get_area() > largest.get_area():
			largest = candidate
	return largest


func _room_cells(room: Resource) -> Dictionary:
	_ensure_geometry_cache()
	var room_id: StringName = room.get("room_id")
	if cached_room_cells.has(room_id):
		return cached_room_cells[room_id]
	return {}


func _build_room_cells(room: Resource) -> Dictionary:
	var occupied_cells: Dictionary = {}
	for grid_rect: Rect2i in _room_rects(room):
		for y: int in range(grid_rect.position.y, grid_rect.end.y):
			for x: int in range(grid_rect.position.x, grid_rect.end.x):
				occupied_cells[Vector2i(x, y)] = true
	return occupied_cells


func _all_occupied_cells() -> Dictionary:
	_ensure_geometry_cache()
	return cached_hull_cells


func _ensure_geometry_cache() -> void:
	var signature := _geometry_signature()
	if signature == geometry_cache_signature and not cached_hull_cells.is_empty():
		return
	geometry_cache_signature = signature
	cached_hull_cells.clear()
	cached_room_cells.clear()
	cached_hull_boundary_segments.clear()
	cached_exterior_replaced_edges.clear()
	for room: Resource in _rooms():
		var cells := _build_room_cells(room)
		cached_room_cells[room.get("room_id")] = cells
		cached_hull_cells.merge(cells, true)
	cached_hull_boundary_segments.assign(GRID_GEOMETRY.boundary_segments(ship_layout, cached_hull_cells, _bounds(), CELL_SIZE, CANVAS_PADDING))
	cached_exterior_replaced_edges = GRID_GEOMETRY.exterior_replaced_edge_keys(_rooms(), cached_hull_cells, ship_layout)


func _geometry_signature() -> int:
	var signature := hash([ship_layout, int(ship_layout.get("lattice_version"))])
	for room: Resource in _rooms():
		signature = hash([signature, room.get("room_id"), room.get("grid_rect"), room.get("grid_rects")])
	return signature


func _draw_room_boundary(room: Resource, color: Color, width: float) -> void:
	_ensure_geometry_cache()
	for segment: Dictionary in GRID_GEOMETRY.boundary_segments(ship_layout, _room_cells(room), _bounds(), CELL_SIZE, CANVAS_PADDING):
		if cached_exterior_replaced_edges.has(GRID_GEOMETRY.exterior_edge_key(segment["cell"], segment["normal"])):
			continue
		draw_line(segment["start"], segment["end"], color, width)
	_draw_room_exterior_profile_lines(room, color, width)


func _draw_cell_set_boundary(occupied_cells: Dictionary, color: Color, width: float) -> void:
	for segment: Dictionary in GRID_GEOMETRY.boundary_segments(ship_layout, occupied_cells, _bounds(), CELL_SIZE, CANVAS_PADDING):
		draw_line(segment["start"], segment["end"], color, width)


func _draw_hull_boundary(color: Color, width: float) -> void:
	_ensure_geometry_cache()
	for segment: Dictionary in cached_hull_boundary_segments:
		if cached_exterior_replaced_edges.has(GRID_GEOMETRY.exterior_edge_key(segment["cell"], segment["normal"])):
			continue
		draw_line(segment["start"], segment["end"], color, width)


func _draw_room_exterior_profile_lines(room: Resource, color: Color, width: float) -> void:
	if not GRID_GEOMETRY.has_exterior_profile(String(room.get("type_name"))):
		return
	var facing := GRID_GEOMETRY.exterior_facing_quarters(room)
	for exterior_span: Rect2i in GRID_GEOMETRY.exterior_face_spans(room, cached_hull_cells, ship_layout):
		var profile := GRID_GEOMETRY.exterior_edge_profile(_get_grid_rect(exterior_span), String(room.get("type_name")), facing)
		if profile.size() >= 2:
			draw_polyline(profile, color, width, false)


func _draw_special_exterior_profiles(hull_cells: Dictionary, outline_color: Color, outline_width: float, override_fill := Color.TRANSPARENT, use_override_fill := false, draw_outline := true) -> void:
	for room: Resource in _rooms():
		var room_type := String(room.get("type_name"))
		if not GRID_GEOMETRY.has_exterior_profile(room_type):
			continue
		var facing_quarters := GRID_GEOMETRY.exterior_facing_quarters(room)
		var fill_color: Color = override_fill if use_override_fill else room.get("color")
		for exterior_span: Rect2i in GRID_GEOMETRY.exterior_face_spans(room, hull_cells, ship_layout):
			var rect := _get_grid_rect(exterior_span)
			var polygon := GRID_GEOMETRY.exterior_cell_polygon(rect, room_type, facing_quarters)
			var profile := GRID_GEOMETRY.exterior_edge_profile(rect, room_type, facing_quarters)
			var aperture := GRID_GEOMETRY.exterior_aperture_polygon(rect, room_type, facing_quarters)
			if polygon.size() < 3 or profile.size() < 2:
				continue
			draw_colored_polygon(polygon, fill_color)
			if aperture.size() >= 3:
				draw_colored_polygon(aperture, Color(0.006, 0.025, 0.03, 1.0))
			if draw_outline:
				draw_polyline(profile, outline_color, outline_width, false)
			if draw_outline and room_type == "HANGAR":
				draw_polyline(profile, Color(0.2, 0.92, 0.88, 0.95), maxf(outline_width * 0.42, 1.0), false)


func _draw_profiled_hull_contours(hull_cells: Dictionary, color: Color, width: float) -> void:
	_ensure_geometry_cache()
	var pieces: Array[PackedVector2Array] = []
	# Add authored profiles before ordinary edges. Since traversal pops from the
	# back, every contour begins on a straight rail; its closed seam is therefore
	# hidden on a collinear section instead of landing on a bridge/profile corner.
	for room: Resource in _rooms():
		var room_type := String(room.get("type_name"))
		if not GRID_GEOMETRY.has_exterior_profile(room_type):
			continue
		var facing := GRID_GEOMETRY.exterior_facing_quarters(room)
		for exterior_span: Rect2i in GRID_GEOMETRY.exterior_face_spans(room, hull_cells, ship_layout):
			var profile := GRID_GEOMETRY.exterior_edge_profile(_get_grid_rect(exterior_span), room_type, facing)
			if profile.size() >= 2:
				pieces.append(profile)
	for segment: Dictionary in cached_hull_boundary_segments:
		if cached_exterior_replaced_edges.has(GRID_GEOMETRY.exterior_edge_key(segment["cell"], segment["normal"])):
			continue
		pieces.append(PackedVector2Array([segment["start"], segment["end"]]))

	# Each boundary segment and authored profile is a piece of the same graph.
	# Joining the pieces before drawing gives the bridge corners a continuous
	# mitered stroke and removes the tiny cap/gap artifacts visible at high zoom.
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


func _draw_hull_edge_indicators(hull_cells: Dictionary) -> void:
	_ensure_geometry_cache()
	for segment: Dictionary in cached_hull_boundary_segments:
		if cached_exterior_replaced_edges.has(GRID_GEOMETRY.exterior_edge_key(segment["cell"], segment["normal"])):
			continue
		draw_line(segment["start"], segment["end"], hull_edge_indicator_color, hull_edge_indicator_width, false)
	for room: Resource in _rooms():
		_draw_room_exterior_profile_lines(room, hull_edge_indicator_color, hull_edge_indicator_width)


func _draw_module_facing_indicator(room: Resource, hull_cells: Dictionary) -> void:
	var room_cells := _build_room_cells(room)
	if room_cells.is_empty():
		return
	var direction := _module_facing_direction(room, room_cells, hull_cells)
	if room.get("type_name") == "PROPULSION":
		_draw_thruster_indicator(room_cells, direction, _thruster_activity(room, direction))
		return
	var center := Vector2.ZERO
	for cell_value: Variant in room_cells.keys():
		center += _get_grid_rect(Rect2i(cell_value, Vector2i.ONE)).get_center()
	center /= float(room_cells.size())
	var arrow_tip := center + direction * module_facing_arrow_length * 0.65
	var arrow_start := center - direction * module_facing_arrow_length * 0.25
	draw_line(arrow_start, arrow_tip, module_facing_indicator_color, module_facing_indicator_width, false)
	var side := direction.orthogonal()
	var arrow_back := arrow_tip - direction * 3.5
	draw_line(arrow_tip, arrow_back + side * 2.5, module_facing_indicator_color, module_facing_indicator_width, false)
	draw_line(arrow_tip, arrow_back - side * 2.5, module_facing_indicator_color, module_facing_indicator_width, false)


func _draw_thruster_indicator(room_cells: Dictionary, direction: Vector2, activity: float = 0.0) -> void:
	var cardinal := Vector2i(roundi(direction.x), roundi(direction.y))
	if cardinal == Vector2i.ZERO:
		cardinal = Vector2i.DOWN
	direction = Vector2(cardinal)
	var edge_points: Array[Vector2] = []
	var side := direction.orthogonal()
	for cell_value: Variant in room_cells.keys():
		var cell: Vector2i = cell_value
		var neighbor := cell + cardinal
		if room_cells.has(neighbor):
			continue
		var rect := _get_grid_rect(Rect2i(cell, Vector2i.ONE)).grow(-0.75)
		# Rotating a cardinal vector can leave a microscopic component on the
		# other axis (for example PI radians produces x ~= -0.000000087).
		# Choose the dominant axis so an aft-facing nozzle stays centered.
		if absf(direction.x) > absf(direction.y):
			var x := rect.end.x if direction.x > 0.0 else rect.position.x
			edge_points.append(Vector2(x, rect.position.y + rect.size.y * 0.25))
			edge_points.append(Vector2(x, rect.position.y + rect.size.y * 0.75))
		else:
			var y := rect.end.y if direction.y > 0.0 else rect.position.y
			edge_points.append(Vector2(rect.position.x + rect.size.x * 0.25, y))
			edge_points.append(Vector2(rect.position.x + rect.size.x * 0.75, y))
	if edge_points.is_empty():
		return
	var edge_min := INF
	var edge_max := -INF
	var forward_total := 0.0
	for point: Vector2 in edge_points:
		var edge_coordinate := point.dot(side)
		edge_min = minf(edge_min, edge_coordinate)
		edge_max = maxf(edge_max, edge_coordinate)
		forward_total += point.dot(direction)
	# Rebuild the anchor from the full exposed face span. This prevents the
	# quarter-cell iteration order from shifting a multi-cell thruster sideways.
	var edge_center := (
		direction * (forward_total / float(edge_points.size()))
		+ side * ((edge_min + edge_max) * 0.5)
	)
	var nozzle_half_size := maxf(4.0, (edge_max - edge_min) * 0.42)
	var nozzle_half := side * nozzle_half_size
	var nozzle_a := edge_center - nozzle_half
	var nozzle_b := edge_center + nozzle_half
	var nozzle_tip := edge_center + direction * 4.5
	# This is ship hardware, not a UI vector: a dark recessed throat with a
	# restrained amber ignition lip remains readable without the old cyan glow.
	var nozzle_shadow := Color(0.025, 0.035, 0.035, 1.0)
	var ignition_lip := Color(0.92, 0.43, 0.12, 0.92)
	draw_colored_polygon(PackedVector2Array([nozzle_a, nozzle_b, nozzle_tip]), nozzle_shadow)
	draw_line(nozzle_a, nozzle_b, thruster_indicator_color, module_facing_indicator_width + 1.0, false)
	draw_line(nozzle_a, nozzle_tip, thruster_indicator_color, module_facing_indicator_width, false)
	draw_line(nozzle_b, nozzle_tip, thruster_indicator_color, module_facing_indicator_width, false)
	draw_line(
		edge_center - side * nozzle_half_size * 0.42,
		edge_center + side * nozzle_half_size * 0.42,
		ignition_lip,
		maxf(module_facing_indicator_width, 1.25),
		false
	)
	if activity <= 0.01:
		return
	var flicker := 0.82 + 0.18 * sin(plume_animation_time * 36.0 + edge_center.length() * 0.19)
	var plume_strength := clampf(activity * flicker, 0.0, 1.0)
	var plume_length := lerpf(3.0, 14.0, plume_strength) * active_thruster_plume_scale
	var plume_width := lerpf(module_facing_indicator_width + 1.0, module_facing_indicator_width + 4.5, plume_strength)
	var plume_tip := nozzle_tip + direction * plume_length
	var plume_mid := nozzle_tip + direction * plume_length * 0.55
	var plume_base_half := side * nozzle_half_size * 0.72
	var plume_mid_half := side * nozzle_half_size * 0.38
	var flame_polygon := PackedVector2Array([
		nozzle_tip - plume_base_half,
		nozzle_tip + plume_base_half,
		plume_mid + plume_mid_half,
		plume_tip,
		plume_mid - plume_mid_half,
	])
	draw_colored_polygon(flame_polygon, Color(active_thruster_flame_color, active_thruster_flame_color.a * plume_strength))
	draw_polyline(flame_polygon + PackedVector2Array([flame_polygon[0]]), Color(thruster_plume_color, thruster_plume_color.a * plume_strength), maxf(plume_width * 0.32, 1.0), false)
	draw_line(nozzle_tip, nozzle_tip + direction * plume_length * 0.72, Color(active_thruster_core_color, active_thruster_core_color.a * plume_strength), maxf(plume_width * 0.38, 0.8), false)


func _thruster_activity(room: Resource, direction: Vector2) -> float:
	if not _has_active_thruster_visuals():
		return 0.0
	var rearward_exhaust := maxf(0.0, direction.normalized().dot(Vector2.DOWN))
	var forward_exhaust := maxf(0.0, direction.normalized().dot(Vector2.UP))
	var activity := maxf(
		visual_forward_throttle * rearward_exhaust,
		visual_brake_throttle * forward_exhaust
	)
	if visual_translation_exhaust.length_squared() > 0.001:
		activity = maxf(
			activity,
			maxf(0.0, direction.normalized().dot(visual_translation_exhaust.normalized()))
			* visual_translation_exhaust.length()
		)
	var turn_amount := absf(visual_turn_command)
	if turn_amount > 0.01:
		# A proxy mount shares its parent room_id, so an id lookup would collapse
		# every merged thruster onto the room center and light the wrong jets while
		# turning. Read this mount's authored footprint instead.
		var room_center := _resource_room_center(room)
		var lever := room_center - size * 0.5
		var force_direction := -direction.normalized()
		var torque := lever.cross(force_direction)
		if absf(torque) > 0.001 and signf(torque) == signf(visual_turn_command):
			var torque_leverage := clampf(absf(torque) / maxf(size.length() * 0.18, 1.0), 0.25, 1.0)
			activity = maxf(activity, turn_amount * torque_leverage)
	return clampf(activity, 0.0, 1.0)


func _module_facing_direction(room: Resource, room_cells: Dictionary, hull_cells: Dictionary) -> Vector2:
	var explicit_facing := int(room.get("module_facing_quarters"))
	if explicit_facing >= 0:
		return Vector2.UP.rotated(float(explicit_facing) * PI * 0.5)
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


func _get_grid_rect(cells: Rect2i) -> Rect2:
	var rect := GRID_GEOMETRY.cell_rect(ship_layout, cells.position, _bounds(), CELL_SIZE, CANVAS_PADDING)
	rect.size = Vector2(cells.size) * CELL_SIZE
	return rect


func _update_size_from_layout() -> void:
	var grid_size := GRID_GEOMETRY.grid_pixel_size(ship_layout, _bounds(), CELL_SIZE)
	custom_minimum_size = CANVAS_PADDING * 2.0 + grid_size
	size = custom_minimum_size
	var shield_visual := get_node_or_null("ShieldVisual") as Control
	if is_instance_valid(shield_visual):
		shield_visual.position = Vector2.ZERO
		shield_visual.size = custom_minimum_size
		shield_visual.call("set_hull_geometry", ship_layout, CANVAS_PADDING, CELL_SIZE)


func _bounds() -> Rect2i:
	return ship_layout.call("get_occupied_bounds")


func _rooms() -> Array:
	return ship_layout.get("rooms")


func _room_rects(room: Resource) -> Array[Rect2i]:
	return room.get("grid_rects")


func _room_uses_standard_skin(room: Resource) -> bool:
	var rects := _room_rects(room)
	if rects.is_empty():
		return false
	var uses_quarter_skin := ROOM_STAFFING_RULES.is_unmanned_exterior_module(room)
	for rect: Rect2i in rects:
		if rect.size != STANDARD_ROOM_LATTICE_SIZE and not (uses_quarter_skin and rect.size == QUARTER_ROOM_LATTICE_SIZE):
			return false
	return true


func _standard_skin_cells(room: Resource) -> Dictionary:
	var cells: Dictionary = {}
	var uses_quarter_skin := ROOM_STAFFING_RULES.is_unmanned_exterior_module(room)
	for rect: Rect2i in _room_rects(room):
		if rect.size != STANDARD_ROOM_LATTICE_SIZE and not (uses_quarter_skin and rect.size == QUARTER_ROOM_LATTICE_SIZE):
			continue
		for y: int in range(rect.position.y, rect.end.y):
			for x: int in range(rect.position.x, rect.end.x):
				cells[Vector2i(x, y)] = true
	return cells


func _columns() -> int:
	return _bounds().size.x


func _rows() -> int:
	return _bounds().size.y
