class_name SectorRegionParallax
extends Control

const WORLD_ORIGIN := Vector2(5000.0, 5000.0)
const SMALL_ASTEROID_TEXTURE := preload("res://assets/sprites/asteroids/asteroid_small_01.png")
const MEDIUM_ASTEROID_TEXTURE := preload("res://assets/sprites/asteroids/asteroid_medium_01.png")
const LARGE_ASTEROID_TEXTURE := preload("res://assets/sprites/asteroids/asteroid_large_01.png")
## Procedural parallax rocks at or below this radius use the authored 32 px sprite.
## Larger rocks remain procedural until matching medium and large art is available.
const SMALL_ASTEROID_MAXIMUM_RADIUS := 18.0
const MEDIUM_ASTEROID_MAXIMUM_RADIUS := 32.0

@export var world_path: NodePath

var world: Control
var sector_population: Node


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	world = get_node_or_null(world_path) as Control
	sector_population = get_tree().get_first_node_in_group("sector_population")
	set_process(true)
	queue_redraw()


func _process(_delta: float) -> void:
	if not is_instance_valid(sector_population):
		sector_population = get_tree().get_first_node_in_group("sector_population")
	if is_instance_valid(sector_population) and not sector_population.get("special_regions").is_empty():
		queue_redraw()


func _draw() -> void:
	if not is_instance_valid(world) or not is_instance_valid(sector_population):
		return
	for region_value: Variant in sector_population.get("special_regions"):
		var region := region_value as SectorSpecialRegion
		if region == null:
			continue
		_draw_region_haze(region)
		_draw_object_layer(
			region,
			region.far_objects,
			region.far_parallax,
			false
		)
		_draw_object_layer(
			region,
			region.middle_objects,
			region.middle_parallax,
			true
		)


func _draw_region_haze(region: SectorSpecialRegion) -> void:
	var center_screen := _parallax_screen_point(
		region.center,
		region.far_parallax,
		region.center
	)
	var zoom := maxf(absf(world.scale.x), 0.001)
	var horizontal_radius := region.world_radius * region.far_extent_multiplier * zoom
	var vertical_radius := horizontal_radius * 0.56
	for band: int in range(5, 0, -1):
		var weight := float(band) / 5.0
		var polygon := PackedVector2Array()
		for index: int in range(48):
			var angle := TAU * float(index) / 48.0
			polygon.append(center_screen + Vector2(
				cos(angle) * horizontal_radius * weight,
				sin(angle) * vertical_radius * weight
			))
		var color := region.ambient_color
		color.a *= (1.0 - weight * 0.55) * 0.38
		draw_colored_polygon(polygon, color)


func _draw_object_layer(
	region: SectorSpecialRegion,
	objects: Array[Dictionary],
	parallax_strength: float,
	show_edge_light: bool
) -> void:
	for object: Dictionary in objects:
		var object_world_position := region.center + Vector2(object["offset"])
		var center_screen := _parallax_screen_point(
			object_world_position,
			parallax_strength,
			region.center
		)
		var rotation_value := float(object["rotation"])
		var radius := float(object.get("radius", 0.0))
		var screen_scale := maxf(absf(world.scale.x), 0.001)
		var texture := (
			SMALL_ASTEROID_TEXTURE
			if radius <= SMALL_ASTEROID_MAXIMUM_RADIUS
			else (
				MEDIUM_ASTEROID_TEXTURE
				if radius <= MEDIUM_ASTEROID_MAXIMUM_RADIUS
				else LARGE_ASTEROID_TEXTURE
			)
		)
		_draw_authored_asteroid(
			center_screen,
			rotation_value,
			radius * screen_scale,
			object["color"],
			show_edge_light,
			texture
		)


func _draw_authored_asteroid(
	center_screen: Vector2,
	rotation_value: float,
	screen_radius: float,
	object_color: Color,
	show_edge_light: bool,
	texture: Texture2D
) -> void:
	if screen_radius <= 0.25:
		return
	var brightness := 0.78 if show_edge_light else 0.62
	var modulation := Color(
		brightness,
		brightness * 1.03,
		brightness * 1.08,
		object_color.a
	)
	draw_set_transform(center_screen, rotation_value)
	draw_texture_rect(
		texture,
		Rect2(Vector2.ONE * -screen_radius, Vector2.ONE * screen_radius * 2.0),
		false,
		modulation
	)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _parallax_screen_point(
	world_position: Vector2,
	parallax_strength: float,
	layer_anchor_world_position: Vector2 = Vector2.INF
) -> Vector2:
	var foreground_global := world.get_global_transform_with_canvas() * (WORLD_ORIGIN + world_position)
	var foreground_local := get_global_transform_with_canvas().affine_inverse() * foreground_global
	if layer_anchor_world_position == Vector2.INF:
		layer_anchor_world_position = world_position
	var anchor_global := (
		world.get_global_transform_with_canvas()
		* (WORLD_ORIGIN + layer_anchor_world_position)
	)
	var anchor_local := get_global_transform_with_canvas().affine_inverse() * anchor_global
	var screen_center := size * 0.5
	# Keep each decorative depth as a flat sheet. A radial distance clamp makes
	# the layer change speed when it reaches the clamp and visually bends the
	# field around the viewport like a lens.
	var layer_offset := (screen_center - anchor_local) * (1.0 - parallax_strength)
	return foreground_local + layer_offset
