extends Control

@export_range(0.0, 0.5, 0.01) var parallax_strength := 0.1
@export_range(0.0, 12.0, 0.5) var maximum_trail_length := 4.0

const STAR_COUNT := 180

var normalized_stars: Array[Vector2] = []
var star_brightness: Array[float] = []
var star_sizes: Array[float] = []
var star_offset := Vector2.ZERO
var trail_vector := Vector2.ZERO
var previous_camera_position := Vector2.ZERO
var camera_position_initialized := false


func _ready() -> void:
	var random := RandomNumberGenerator.new()
	random.seed = 4815162342
	for index: int in range(STAR_COUNT):
		normalized_stars.append(Vector2(random.randf(), random.randf()))
		star_brightness.append(random.randf_range(0.26, 0.78))
		star_sizes.append(random.randf_range(0.7, 1.5))
	queue_redraw()


func reset_camera_position(camera_position: Vector2) -> void:
	previous_camera_position = camera_position
	camera_position_initialized = true
	trail_vector = Vector2.ZERO


func update_camera_position(camera_position: Vector2) -> void:
	if not camera_position_initialized:
		reset_camera_position(camera_position)
		return

	var camera_delta := camera_position - previous_camera_position
	previous_camera_position = camera_position
	star_offset += camera_delta * parallax_strength
	trail_vector = trail_vector.lerp(camera_delta.limit_length(maximum_trail_length), 0.35)
	queue_redraw()


func _draw() -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return

	for index: int in range(normalized_stars.size()):
		var base_position := normalized_stars[index] * size
		var star_position := Vector2(
			fposmod(base_position.x + star_offset.x, size.x),
			fposmod(base_position.y + star_offset.y, size.y)
		)
		var brightness := star_brightness[index]
		if trail_vector.length_squared() > 0.04:
			draw_line(
				star_position - trail_vector,
				star_position,
				Color(0.35, 0.58, 0.68, brightness * 0.22),
				1.0
			)
		draw_circle(
			star_position,
			star_sizes[index],
			Color(0.56, 0.72, 0.8, brightness)
		)

