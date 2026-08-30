extends Control

@export_category("Travel Starfield")
## Number of background stars visible across the view.
@export_range(12, 300, 1) var star_count := 110
## Star travel speed in screen pixels per second while the capital ship is at full speed.
@export_range(10.0, 500.0, 5.0) var maximum_stream_speed := 235.0
## Baseline stream strength while viewing the ship, even when tactical movement is very slow.
@export_range(0.0, 1.0, 0.01) var ambient_travel_ratio := 0.48
## Minimum fraction of full ship speed required before visible streaming begins.
@export_range(0.0, 0.5, 0.01) var movement_threshold := 0.025
## Maximum length of each star trail at full travel speed.
@export_range(0.0, 80.0, 1.0) var maximum_trail_length := 38.0
## How quickly the background responds when the ship accelerates or stops.
@export_range(0.5, 12.0, 0.25) var response_speed := 3.5
## Tint used for the bright head of each passing star.
@export var star_color := Color(0.58, 0.79, 0.86, 0.72)
## Tint used for the fading travel streak behind each star.
@export var trail_color := Color(0.22, 0.55, 0.67, 0.24)
## Stable random seed used to arrange this starfield.
@export var random_seed := 8675309

var normalized_positions: Array[Vector2] = []
var brightness: Array[float] = []
var star_sizes: Array[float] = []
var speed_variation: Array[float] = []
var stream_offset := 0.0
var displayed_speed_ratio := 0.0
var ship_simulation: Node


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	ship_simulation = get_node_or_null("/root/Main/ShipSimulation")
	_rebuild_stars()
	queue_redraw()


func _process(delta: float) -> void:
	if not is_instance_valid(ship_simulation):
		ship_simulation = get_node_or_null("/root/Main/ShipSimulation")
	var target_ratio := _ship_speed_ratio()
	displayed_speed_ratio = lerpf(displayed_speed_ratio, target_ratio, 1.0 - exp(-response_speed * delta))
	stream_offset = fposmod(stream_offset + maximum_stream_speed * displayed_speed_ratio * delta, maxf(size.y, 1.0))
	queue_redraw()


func _ship_speed_ratio() -> float:
	if not is_instance_valid(ship_simulation):
		return ambient_travel_ratio
	var maximum_speed := maxf(float(ship_simulation.get("maximum_speed")), 0.001)
	var velocity: Vector2 = ship_simulation.get("velocity")
	var ratio := clampf(velocity.length() / maximum_speed, 0.0, 1.0)
	if ratio < movement_threshold:
		ratio = 0.0
	return lerpf(ambient_travel_ratio, 1.0, ratio)


func _rebuild_stars() -> void:
	normalized_positions.clear()
	brightness.clear()
	star_sizes.clear()
	speed_variation.clear()
	var random := RandomNumberGenerator.new()
	random.seed = random_seed
	for index: int in range(star_count):
		normalized_positions.append(Vector2(random.randf(), random.randf()))
		brightness.append(random.randf_range(0.35, 1.0))
		star_sizes.append(random.randf_range(0.65, 1.45))
		speed_variation.append(random.randf_range(0.72, 1.28))


func _draw() -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return
	var trail_length := maximum_trail_length * displayed_speed_ratio
	for index: int in range(normalized_positions.size()):
		var variation := speed_variation[index]
		var position := Vector2(
			normalized_positions[index].x * size.x,
			fposmod(normalized_positions[index].y * size.y + stream_offset * variation, size.y)
		)
		var alpha := brightness[index]
		if trail_length > 0.5:
			draw_line(
				position - Vector2.DOWN * trail_length * variation,
				position,
				Color(trail_color, trail_color.a * alpha),
				maxf(star_sizes[index] * 0.75, 0.7),
				true
			)
		draw_circle(position, star_sizes[index], Color(star_color, star_color.a * alpha))
