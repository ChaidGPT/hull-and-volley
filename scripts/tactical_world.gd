extends Control

const WORLD_ORIGIN := Vector2(5000, 5000)
const SMALL_ASTEROID_TEXTURE := preload("res://assets/sprites/asteroids/asteroid_small_01.png")
const MEDIUM_ASTEROID_TEXTURE := preload("res://assets/sprites/asteroids/asteroid_medium_01.png")
const LARGE_ASTEROID_TEXTURE := preload("res://assets/sprites/asteroids/asteroid_large_01.png")
const LARGE_ASTEROID_DESTROY_TEXTURE := preload(
	"res://assets/sprites/asteroids/animations/large_destroy/asteroid_large_destroy_strip.png"
)
const MEDIUM_ASTEROID_DESTROY_TEXTURE := preload(
	"res://assets/sprites/asteroids/animations/medium_destroy/asteroid_medium_destroy_strip.png"
)
const SMALL_ASTEROID_DESTROY_TEXTURE := preload(
	"res://assets/sprites/asteroids/animations/small_destroy/asteroid_small_destroy_strip.png"
)
const SMALL_ASTEROID_MAXIMUM_RADIUS := 22.0
const MEDIUM_ASTEROID_MAXIMUM_RADIUS := 32.0
const LARGE_DESTROY_FRAME_SIZE := Vector2(96.0, 96.0)
const LARGE_DESTROY_FRAME_COUNT := 10
const LARGE_DESTROY_FPS := 12.0
const MEDIUM_DESTROY_FRAME_SIZE := Vector2(64.0, 64.0)
const MEDIUM_DESTROY_FRAME_COUNT := 8
const MEDIUM_DESTROY_FPS := 12.0
const SMALL_DESTROY_FRAME_SIZE := Vector2(32.0, 32.0)
const SMALL_DESTROY_FRAME_COUNT := 10
const SMALL_DESTROY_FPS := 1000.0 / 150.0

@export_category("Course Plotting")
## Color of a committed route currently being followed by the ship.
@export var active_route_color := Color(0.24, 0.68, 0.7, 0.65)
## Color of a route being assembled while the player holds Shift.
@export var pending_route_color := Color(1.0, 0.68, 0.22, 0.82)
@export var heading_lock_color := Color(0.38, 0.92, 1.0, 0.9)
## Radius of each waypoint marker in tactical pixels.
@export_range(4.0, 30.0, 1.0) var waypoint_radius := 10.0
## Temporary presentation switch. Navigation remains fully simulated while
## only destination reticles are shown on the tactical display.
@export var show_travel_path_visuals := false
## Time taken by a newly committed destination to snap into a navigation lock.
@export_range(0.1, 0.8, 0.05) var destination_lock_duration := 0.35
## Speed of the subtle idle pulse on destination markers.
@export_range(0.2, 3.0, 0.1) var destination_pulse_speed := 1.15
## Fractional size change at the crest of the idle pulse.
@export_range(0.0, 0.2, 0.01) var destination_pulse_amount := 0.06

var simulation
var sector_simulation
var sector_population
var route_pulse_phase := 0.0
var destination_pulse_phase := 0.0
var destination_lock_remaining := 0.0
var tracked_destination := Vector2.ZERO
var has_tracked_destination := false
var storm_phase := 0.0
var tracked_asteroid_bodies: Dictionary = {}
var asteroid_destruction_animations: Array[Dictionary] = []


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	simulation = get_tree().get_first_node_in_group("ship_simulation")
	sector_simulation = get_tree().get_first_node_in_group("sector_simulation")
	sector_population = get_tree().get_first_node_in_group("sector_population")
	queue_redraw()


func _process(delta: float) -> void:
	_sync_asteroid_destruction_signals()
	_update_asteroid_destruction_animations(delta)
	route_pulse_phase = fmod(route_pulse_phase + delta * 34.0, 48.0)
	destination_pulse_phase = fmod(
		destination_pulse_phase + delta * destination_pulse_speed * TAU,
		TAU
	)
	destination_lock_remaining = maxf(destination_lock_remaining - delta, 0.0)
	_update_committed_destination_animation()
	storm_phase = fmod(storm_phase + delta * 0.65, TAU)
	if is_instance_valid(sector_simulation) and bool(sector_simulation.get("hazard_enabled")):
		queue_redraw()
	if is_instance_valid(simulation) and (
		simulation.has_destination
		or simulation.course_preview_active
		or simulation.is_plotting_route
		):
		queue_redraw()


func _update_committed_destination_animation() -> void:
	if not is_instance_valid(simulation) or not simulation.has_destination:
		has_tracked_destination = false
		destination_lock_remaining = 0.0
		return
	var docking_to_object: bool = StringName(simulation.get("docking_state")) in [
		&"APPROACH",
		&"ALIGN",
		&"FINAL",
	]
	if docking_to_object or bool(simulation.active_route_ends_at_object_destination()):
		has_tracked_destination = false
		destination_lock_remaining = 0.0
		return
	var active_points: Array[Vector2] = simulation.get_active_route_points()
	if active_points.is_empty():
		has_tracked_destination = false
		destination_lock_remaining = 0.0
		return
	var destination: Vector2 = active_points[-1]
	if not has_tracked_destination or not destination.is_equal_approx(tracked_destination):
		tracked_destination = destination
		has_tracked_destination = true
		destination_lock_remaining = destination_lock_duration


func _draw() -> void:
	_draw_sector_storm()
	for grid_coordinate: int in range(0, 10001, 500):
		var grid_color := Color(0.08, 0.15, 0.19, 0.42)
		draw_line(Vector2(grid_coordinate, 0), Vector2(grid_coordinate, size.y), grid_color, 1.0)
		draw_line(Vector2(0, grid_coordinate), Vector2(size.x, grid_coordinate), grid_color, 1.0)
	_draw_sector_population()
	_draw_asteroid_destruction_animations()

	if not is_instance_valid(simulation):
		return

	var ship_point: Vector2 = WORLD_ORIGIN + simulation.ship_position
	if simulation.has_destination:
		var docking_to_object: bool = StringName(simulation.get("docking_state")) in [&"APPROACH", &"ALIGN", &"FINAL"]
		var object_destination: bool = docking_to_object or bool(simulation.active_route_ends_at_object_destination())
		var active_points: Array[Vector2] = simulation.get_active_route_points()
		if show_travel_path_visuals:
			_draw_route(
				ship_point,
				simulation.get_display_route_points(),
				active_route_color,
				not object_destination,
				[],
				true
			)
		elif not object_destination and not active_points.is_empty():
			if bool(simulation.get("heading_lock_course_active")):
				_draw_translation_destination(active_points[-1], heading_lock_color, true)
			else:
				_draw_destination_only(active_points[-1], active_route_color, true)
	if simulation.course_preview_active:
		var preview_points: Array[Vector2] = simulation.get_course_preview_navigation_points()
		var preview_object_destination: bool = simulation.course_preview_has_object_destination()
		if show_travel_path_visuals:
			_draw_route(
				ship_point,
				preview_points,
				pending_route_color,
				not preview_object_destination,
				[],
				true
			)
		elif not preview_object_destination and not preview_points.is_empty():
			if bool(simulation.get("course_preview_heading_lock")):
				_draw_translation_destination(preview_points[-1], heading_lock_color)
			else:
				_draw_destination_only(preview_points[-1], pending_route_color)
	if simulation.is_plotting_route and not simulation.pending_route_waypoints.is_empty():
		var pending_object_destination: bool = simulation.pending_route_ends_at_object_destination()
		if show_travel_path_visuals:
			_draw_route(
				ship_point,
				simulation.get_pending_route_navigation_points(),
				pending_route_color,
				false,
				simulation.get_pending_route_marker_points(),
				pending_object_destination
			)
		elif not pending_object_destination:
			var pending_markers: Array[Vector2] = simulation.get_pending_route_marker_points()
			if not pending_markers.is_empty():
				_draw_destination_only(pending_markers[-1], pending_route_color)


func _draw_sector_population() -> void:
	if not is_instance_valid(sector_population):
		sector_population = get_tree().get_first_node_in_group("sector_population")
	if not is_instance_valid(sector_population):
		return
	for lane_value: Variant in sector_population.get("shipping_lanes"):
		var lane: Dictionary = lane_value
		var points: PackedVector2Array = lane.get("points", PackedVector2Array())
		if points.size() < 2:
			continue
		var lane_color: Color = lane.get("color", Color(0.2, 0.7, 0.7, 0.16))
		for index: int in range(points.size() - 1):
			var start := WORLD_ORIGIN + points[index]
			var finish := WORLD_ORIGIN + points[index + 1]
			_draw_dashed_world_line(start, finish, lane_color, 34.0, 18.0)
		for point: Vector2 in points:
			var beacon := WORLD_ORIGIN + point
			draw_circle(beacon, 4.0, Color(lane_color.r, lane_color.g, lane_color.b, 0.42), false, 1.2)
			draw_line(beacon + Vector2(-7.0, 0.0), beacon + Vector2(7.0, 0.0), lane_color, 1.0)
			draw_line(beacon + Vector2(0.0, -7.0), beacon + Vector2(0.0, 7.0), lane_color, 1.0)

	for asteroid_value: Variant in sector_population.get("physical_asteroids"):
		var asteroid: Dictionary = asteroid_value
		var body_value: Variant = asteroid.get("body")
		if not is_instance_valid(body_value):
			continue
		var body := body_value as RigidBody2D
		var center := WORLD_ORIGIN + body.position
		var asteroid_rotation := body.rotation
		var radius := float(asteroid["radius"])
		var texture := (
			SMALL_ASTEROID_TEXTURE
			if radius <= SMALL_ASTEROID_MAXIMUM_RADIUS
			else (
				MEDIUM_ASTEROID_TEXTURE
				if radius <= MEDIUM_ASTEROID_MAXIMUM_RADIUS
				else LARGE_ASTEROID_TEXTURE
			)
		)
		draw_set_transform(center, asteroid_rotation)
		draw_texture_rect(
			texture,
			Rect2(Vector2.ONE * -radius, Vector2.ONE * radius * 2.0),
			false
		)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _sync_asteroid_destruction_signals() -> void:
	if not is_instance_valid(sector_population):
		return
	for asteroid_value: Variant in sector_population.get("physical_asteroids"):
		var asteroid: Dictionary = asteroid_value
		var body_value: Variant = asteroid.get("body")
		if not is_instance_valid(body_value):
			continue
		var body := body_value as RigidBody2D
		var instance_id := body.get_instance_id()
		if tracked_asteroid_bodies.has(instance_id):
			continue
		tracked_asteroid_bodies[instance_id] = true
		if body.has_signal("destroyed"):
			body.connect("destroyed", _on_asteroid_destroyed)


func _on_asteroid_destroyed(
	_asteroid_id: int,
	world_position: Vector2,
	world_rotation: float,
	visual_radius: float,
	size_class: StringName
) -> void:
	var texture: Texture2D
	var frame_size: Vector2
	var frame_count: int
	var fps: float
	match size_class:
		&"LARGE":
			texture = LARGE_ASTEROID_DESTROY_TEXTURE
			frame_size = LARGE_DESTROY_FRAME_SIZE
			frame_count = LARGE_DESTROY_FRAME_COUNT
			fps = LARGE_DESTROY_FPS
		&"MEDIUM":
			texture = MEDIUM_ASTEROID_DESTROY_TEXTURE
			frame_size = MEDIUM_DESTROY_FRAME_SIZE
			frame_count = MEDIUM_DESTROY_FRAME_COUNT
			fps = MEDIUM_DESTROY_FPS
		&"SMALL":
			texture = SMALL_ASTEROID_DESTROY_TEXTURE
			frame_size = SMALL_DESTROY_FRAME_SIZE
			frame_count = SMALL_DESTROY_FRAME_COUNT
			fps = SMALL_DESTROY_FPS
		_:
			return
	if texture == null:
		return
	asteroid_destruction_animations.append({
		"position": world_position,
		"rotation": world_rotation,
		"radius": visual_radius,
		"elapsed": 0.0,
		"texture": texture,
		"frame_size": frame_size,
		"frame_count": frame_count,
		"fps": fps,
	})
	queue_redraw()


func _update_asteroid_destruction_animations(delta: float) -> void:
	if asteroid_destruction_animations.is_empty():
		return
	for index: int in range(asteroid_destruction_animations.size() - 1, -1, -1):
		var animation: Dictionary = asteroid_destruction_animations[index]
		animation["elapsed"] = float(animation["elapsed"]) + delta
		var duration := float(animation["frame_count"]) / float(animation["fps"])
		if float(animation["elapsed"]) >= duration:
			asteroid_destruction_animations.remove_at(index)
	queue_redraw()


func _draw_asteroid_destruction_animations() -> void:
	for animation: Dictionary in asteroid_destruction_animations:
		var fps := float(animation["fps"])
		var frame_count := int(animation["frame_count"])
		var frame_size := Vector2(animation["frame_size"])
		var frame := clampi(
			floori(float(animation["elapsed"]) * fps),
			0,
			frame_count - 1
		)
		var radius := float(animation["radius"])
		var center := WORLD_ORIGIN + Vector2(animation["position"])
		draw_set_transform(center, float(animation["rotation"]))
		draw_texture_rect_region(
			animation["texture"],
			Rect2(Vector2.ONE * -radius, Vector2.ONE * radius * 2.0),
			Rect2(
				Vector2(float(frame) * frame_size.x, 0.0),
				frame_size
			)
		)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_dashed_world_line(
	start: Vector2,
	finish: Vector2,
	color: Color,
	dash_length: float,
	gap_length: float
) -> void:
	var segment := finish - start
	var length := segment.length()
	if length <= 0.01:
		return
	var direction := segment / length
	var cursor := 0.0
	while cursor < length:
		var dash_end := minf(cursor + dash_length, length)
		draw_line(start + direction * cursor, start + direction * dash_end, color, 1.0, true)
		cursor += dash_length + gap_length


func _draw_sector_storm() -> void:
	if not is_instance_valid(sector_simulation) or not bool(sector_simulation.get("hazard_enabled")):
		return
	var center := WORLD_ORIGIN + Vector2(sector_simulation.get("sector_center"))
	var safe_radius := float(sector_simulation.get("current_safe_radius"))
	var outer_radius := 7600.0
	var segment_count := 112
	var storm_fill := Color(0.18, 0.025, 0.23, 0.22)
	for index: int in range(segment_count):
		var angle_a := TAU * float(index) / float(segment_count)
		var angle_b := TAU * float(index + 1) / float(segment_count)
		var inner_a := center + Vector2.RIGHT.rotated(angle_a) * safe_radius
		var inner_b := center + Vector2.RIGHT.rotated(angle_b) * safe_radius
		var outer_a := center + Vector2.RIGHT.rotated(angle_a) * outer_radius
		var outer_b := center + Vector2.RIGHT.rotated(angle_b) * outer_radius
		draw_colored_polygon(PackedVector2Array([inner_a, inner_b, outer_b, outer_a]), storm_fill)

	# Several restless filaments make the boundary read as a cloud front rather
	# than a map circle. Their motion is visual only; the simulation radius is exact.
	for layer: int in range(5):
		var points := PackedVector2Array()
		for index: int in range(segment_count + 1):
			var angle := TAU * float(index) / float(segment_count)
			var wave := (
				sin(angle * (5.0 + layer) + storm_phase * (0.7 + layer * 0.13)) * 22.0
				+ sin(angle * 13.0 - storm_phase * 1.4 + layer) * 9.0
			)
			var radius := safe_radius + 16.0 + layer * 31.0 + wave
			points.append(center + Vector2.RIGHT.rotated(angle) * radius)
		var filament := Color(0.45 + layer * 0.05, 0.12, 0.72 + layer * 0.035, 0.35 - layer * 0.035)
		draw_polyline(points, filament, 2.0 + layer * 0.45, true)

	for index: int in range(44):
		var angle := TAU * float(index) / 44.0 + sin(float(index) * 4.17) * 0.045
		var depth := 95.0 + fmod(float(index * 137), 520.0)
		var flicker := 0.55 + 0.45 * sin(storm_phase * 2.1 + float(index) * 1.9)
		var start := center + Vector2.RIGHT.rotated(angle) * (safe_radius + depth)
		var tangent := Vector2.UP.rotated(angle)
		var finish := start + tangent * (32.0 + flicker * 44.0)
		draw_line(start, finish, Color(0.64, 0.16, 0.92, 0.16 + flicker * 0.18), 2.0, true)


func _draw_route(
	start: Vector2,
	world_points: Array[Vector2],
	color: Color,
	mark_final: bool,
	anchor_points: Array[Vector2],
	trim_final: bool
) -> void:
	var previous := start
	var camera_zoom := maxf(absf(scale.x), 0.001)
	for point_index: int in range(world_points.size()):
		var world_point: Vector2 = world_points[point_index]
		var point := WORLD_ORIGIN + world_point
		var segment_start := previous
		var segment_end := point
		var segment_direction := previous.direction_to(point)
		var endpoint_gap := 18.0 / camera_zoom
		if point_index == 0 and previous.distance_to(point) > endpoint_gap * 2.0:
			segment_start += segment_direction * endpoint_gap
		if (
			point_index == world_points.size() - 1
			and trim_final
			and segment_start.distance_to(point) > endpoint_gap * 2.0
		):
			segment_end -= segment_direction * endpoint_gap
		_draw_holographic_segment(segment_start, segment_end, color, camera_zoom)
		previous = point
	for index: int in range(anchor_points.size()):
		var anchor := WORLD_ORIGIN + anchor_points[index]
		var marker_radius := waypoint_radius / camera_zoom
		_draw_bracket_reticle(anchor, marker_radius, color, camera_zoom, false)
		draw_string(
			ThemeDB.fallback_font,
			anchor + Vector2(marker_radius + 4.0 / camera_zoom, -4.0 / camera_zoom),
			str(index + 1),
			HORIZONTAL_ALIGNMENT_LEFT,
			-1.0,
			roundi(11.0 / camera_zoom),
			color
		)
	if mark_final and not world_points.is_empty():
		var destination_point := WORLD_ORIGIN + world_points[-1]
		_draw_bracket_reticle(destination_point, 15.0 / camera_zoom, color, camera_zoom, true)


func _draw_destination_only(
	world_point: Vector2,
	color: Color,
	play_lock_animation: bool = false
) -> void:
	var camera_zoom := maxf(absf(scale.x), 0.001)
	var center := WORLD_ORIGIN + world_point
	var pulse_wave := 0.5 + 0.5 * sin(destination_pulse_phase)
	var pulse_scale := 1.0 + pulse_wave * destination_pulse_amount
	var screen_radius := 15.0 * pulse_scale
	if play_lock_animation and destination_lock_remaining > 0.0:
		var progress := 1.0 - destination_lock_remaining / maxf(destination_lock_duration, 0.001)
		var ease_out := 1.0 - pow(1.0 - progress, 3.0)
		screen_radius += (1.0 - ease_out) * 20.0
		_draw_destination_lock_flash(center, color, camera_zoom, progress)
	_draw_bracket_reticle(
		center,
		screen_radius / camera_zoom,
		color,
		camera_zoom,
		true
	)
	var pulse_color := color
	pulse_color.a *= 0.1 + pulse_wave * 0.12
	draw_circle(
		center,
		(7.0 + pulse_wave * 2.0) / camera_zoom,
		pulse_color,
		false,
		1.0 / camera_zoom
	)


func _draw_translation_destination(
	world_point: Vector2,
	color: Color,
	play_lock_animation: bool = false
) -> void:
	var camera_zoom := maxf(absf(scale.x), 0.001)
	var center := WORLD_ORIGIN + world_point
	var pulse_wave := 0.5 + 0.5 * sin(destination_pulse_phase)
	var radius := (15.0 + pulse_wave * 1.5) / camera_zoom
	var arm := 7.0 / camera_zoom
	var width := 1.25 / camera_zoom
	if play_lock_animation and destination_lock_remaining > 0.0:
		var progress := 1.0 - destination_lock_remaining / maxf(destination_lock_duration, 0.001)
		_draw_destination_lock_flash(center, color, camera_zoom, progress)
	var diamond := PackedVector2Array([
		center + Vector2.UP * radius,
		center + Vector2.RIGHT * radius,
		center + Vector2.DOWN * radius,
		center + Vector2.LEFT * radius,
		center + Vector2.UP * radius,
	])
	draw_polyline(diamond, color, width, false)
	for direction: Vector2 in [Vector2.UP, Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT]:
		var tip := center + direction * (radius + arm)
		var side := direction.orthogonal()
		draw_line(tip, tip - direction * arm + side * arm * 0.45, color, width, false)
		draw_line(tip, tip - direction * arm - side * arm * 0.45, color, width, false)
	var core := color
	core.a *= 0.14 + pulse_wave * 0.12
	draw_circle(center, (5.0 + pulse_wave) / camera_zoom, core, true)


func _draw_destination_lock_flash(
	center: Vector2,
	color: Color,
	camera_zoom: float,
	progress: float
) -> void:
	var fade := 1.0 - clampf(progress, 0.0, 1.0)
	var ring_color := color
	ring_color.a *= fade * 0.75
	var ring_radius := lerpf(34.0, 19.0, progress) / camera_zoom
	draw_arc(center, ring_radius, 0.0, TAU, 32, ring_color, 1.15 / camera_zoom, false)
	var tick_color := color
	tick_color.a *= fade
	var tick_outer := lerpf(43.0, 23.0, progress) / camera_zoom
	var tick_inner := (tick_outer * camera_zoom - 7.0) / camera_zoom
	for direction: Vector2 in [Vector2.UP, Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT]:
		draw_line(
			center + direction * tick_outer,
			center + direction * tick_inner,
			tick_color,
			1.4 / camera_zoom,
			false
		)


func _draw_holographic_segment(from: Vector2, to: Vector2, color: Color, camera_zoom: float) -> void:
	var segment := to - from
	var segment_length := segment.length()
	if segment_length <= 0.01:
		return
	var direction := segment / segment_length
	var normal := Vector2(-direction.y, direction.x)
	var fine_width := 0.85 / camera_zoom
	var glow := color
	glow.a *= 0.13
	draw_line(from, to, glow, 4.0 / camera_zoom, false)
	var filament := color
	filament.a *= 0.42
	draw_line(from, to, filament, fine_width, false)

	# Sparse paired chevrons read as projected helm telemetry instead of a road.
	var spacing := 48.0 / camera_zoom
	var pulse_offset := route_pulse_phase / camera_zoom
	var cursor := fmod(pulse_offset, spacing)
	var wing_back := 7.0 / camera_zoom
	var wing_half := 4.0 / camera_zoom
	var chevron_color := color
	chevron_color.a = minf(1.0, color.a * 0.9)
	while cursor < segment_length:
		var tip := from + direction * cursor
		var back := tip - direction * wing_back
		draw_line(back + normal * wing_half, tip, chevron_color, fine_width, false)
		draw_line(back - normal * wing_half, tip, chevron_color, fine_width, false)
		cursor += spacing


func _draw_bracket_reticle(
	center: Vector2,
	radius: float,
	color: Color,
	camera_zoom: float,
	with_core: bool
) -> void:
	var arm := 5.0 / camera_zoom
	var width := 1.15 / camera_zoom
	var bracket_color := color
	bracket_color.a = minf(1.0, color.a * 0.9)
	for diagonal: Vector2 in [
		Vector2(-1.0, -1.0),
		Vector2(1.0, -1.0),
		Vector2(1.0, 1.0),
		Vector2(-1.0, 1.0),
	]:
		var corner := center + diagonal * radius
		draw_line(corner, corner - Vector2(diagonal.x * arm, 0.0), bracket_color, width, false)
		draw_line(corner, corner - Vector2(0.0, diagonal.y * arm), bracket_color, width, false)
	if not with_core:
		return
	if not center.is_finite() or not is_finite(camera_zoom) or camera_zoom <= 0.001:
		return
	var core_radius := maxf(2.5 / camera_zoom, 0.25)
	var core_color := color
	core_color.a = minf(1.0, color.a + 0.2)
	# A primitive core remains stable at every camera scale. Polygon triangulation
	# can collapse at extreme zoom and previously flooded the debugger every frame.
	draw_circle(center, core_radius, core_color, true)
