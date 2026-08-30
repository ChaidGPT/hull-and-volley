class_name SectorSpecialRegion
extends Resource

enum RegionType {
	ASTEROID_BELT,
	BATTLEFIELD,
	SHIP_GRAVEYARD,
	ICE_FIELD,
	INDUSTRIAL_ZONE,
	NEBULA,
}

@export var region_id: StringName = &"SPECIAL_REGION"
@export var display_name := "SPECIAL REGION"
@export var region_type := RegionType.ASTEROID_BELT
@export var center := Vector2.ZERO
@export_range(100.0, 5000.0, 25.0) var world_radius := 650.0
@export var generation_seed := 1
@export var gameplay_tags := PackedStringArray()

@export_category("Parallax Field")
## Values near 1 keep the sheet registered to the physical region while still
## giving it visible depth. Motion remains linear at every camera distance.
@export_range(0.05, 0.95, 0.05) var far_parallax := 0.78
@export_range(0.05, 0.95, 0.05) var middle_parallax := 0.9
## Broadens the deep decorative sheet beyond the playable belt so its edge
## appears first and creates a gradual visual transition into the region.
@export_range(1.0, 2.5, 0.05) var far_extent_multiplier := 1.6
@export var ambient_color := Color(0.18, 0.22, 0.24, 0.12)
@export var far_tint := Color(0.13, 0.16, 0.18, 0.26)
@export var middle_tint := Color(0.22, 0.25, 0.27, 0.48)

@export_category("Population")
@export_range(0, 240, 1) var far_object_count := 72
@export_range(0, 120, 1) var middle_object_count := 32
@export_range(0, 40, 1) var physical_object_count := 12
## Empty world-space distance maintained between decorative asteroids that
## belong to the same parallax sheet.
@export_range(0.0, 40.0, 1.0) var visual_object_gap := 4.0
## Extra clearance between collidable asteroids in the physical layer.
@export_range(0.0, 60.0, 1.0) var physical_object_gap := 8.0

var far_objects: Array[Dictionary] = []
var middle_objects: Array[Dictionary] = []
var physical_objects: Array[Dictionary] = []


func contains_world_position(world_position: Vector2, margin: float = 0.0) -> bool:
	return center.distance_to(world_position) <= world_radius + margin


func get_environment_report() -> Dictionary:
	return {
		"id": region_id,
		"display_name": display_name,
		"type": region_type,
		"center": center,
		"radius": world_radius,
		"tags": gameplay_tags,
		"far_object_count": far_objects.size(),
		"middle_object_count": middle_objects.size(),
		"physical_object_count": physical_objects.size(),
	}


func generate_asteroid_belt() -> void:
	region_type = RegionType.ASTEROID_BELT
	gameplay_tags = PackedStringArray(["ASTEROIDS", "MINING", "NAVIGATION_HAZARD"])
	far_objects.clear()
	middle_objects.clear()
	physical_objects.clear()
	var random := RandomNumberGenerator.new()
	random.seed = generation_seed
	far_objects = _generate_visual_layer(
		random,
		far_object_count,
		world_radius * 0.3,
		world_radius * far_extent_multiplier,
		12.0,
		42.0,
		far_tint
	)
	middle_objects = _generate_visual_layer(
		random,
		middle_object_count,
		world_radius * 0.24,
		world_radius,
		15.0,
		48.0,
		middle_tint
	)
	for index: int in range(physical_object_count):
		var offset := Vector2.ZERO
		var radius := 0.0
		var found_position := false
		for attempt: int in range(32):
			var angle := (
				TAU
				* (float(index) + random.randf_range(-0.28, 0.28))
				/ maxf(float(physical_object_count), 1.0)
			)
			var distance := random.randf_range(world_radius * 0.34, world_radius * 0.92)
			offset = Vector2(cos(angle) * distance, sin(angle) * distance * 0.62)
			offset += Vector2(
				random.randf_range(-48.0, 48.0),
				random.randf_range(-34.0, 34.0)
			)
			radius = random.randf_range(18.0, 38.0)
			if not _overlaps_layer_object(
				physical_objects,
				offset,
				radius,
				physical_object_gap
			):
				found_position = true
				break
		if not found_position:
			continue
		physical_objects.append({
			"id": physical_objects.size() + 1,
			"offset": offset,
			"radius": radius,
			"rotation": random.randf_range(-PI, PI),
			"silhouette": _generate_silhouette(random, radius, random.randi_range(8, 11)),
			"color": Color(
				random.randf_range(0.18, 0.25),
				random.randf_range(0.2, 0.27),
				random.randf_range(0.22, 0.3),
				1.0
			),
			"linear_velocity": Vector2.RIGHT.rotated(random.randf_range(-PI, PI)) * random.randf_range(0.2, 1.2),
			"angular_velocity": random.randf_range(-0.025, 0.025),
		})


func _generate_visual_layer(
	random: RandomNumberGenerator,
	count: int,
	minimum_distance: float,
	maximum_distance: float,
	minimum_radius: float,
	maximum_radius: float,
	base_tint: Color
) -> Array[Dictionary]:
	var objects: Array[Dictionary] = []
	for index: int in range(count):
		var offset := Vector2.ZERO
		var radius := 0.0
		var found_position := false
		for attempt: int in range(32):
			var angle := random.randf_range(-PI, PI)
			var distance := random.randf_range(minimum_distance, maximum_distance)
			offset = Vector2(cos(angle) * distance, sin(angle) * distance * 0.58)
			offset += Vector2(
				random.randf_range(-72.0, 72.0),
				random.randf_range(-45.0, 45.0)
			)
			radius = random.randf_range(minimum_radius, maximum_radius)
			if not _overlaps_layer_object(objects, offset, radius, visual_object_gap):
				found_position = true
				break
		if not found_position:
			continue
		var tint_variation := random.randf_range(-0.035, 0.035)
		objects.append({
			"id": objects.size() + 1,
			"offset": offset,
			"radius": radius,
			"rotation": random.randf_range(-PI, PI),
			"silhouette": _generate_silhouette(random, radius, random.randi_range(7, 11)),
			"color": Color(
				clampf(base_tint.r + tint_variation, 0.0, 1.0),
				clampf(base_tint.g + tint_variation, 0.0, 1.0),
				clampf(base_tint.b + tint_variation, 0.0, 1.0),
				base_tint.a * random.randf_range(0.72, 1.08)
			),
		})
	return objects


func _overlaps_layer_object(
	objects: Array[Dictionary],
	candidate_offset: Vector2,
	candidate_radius: float,
	minimum_gap: float
) -> bool:
	for object: Dictionary in objects:
		var required_distance := candidate_radius + float(object["radius"]) + minimum_gap
		if candidate_offset.distance_squared_to(Vector2(object["offset"])) < required_distance * required_distance:
			return true
	return false


func _generate_silhouette(
	random: RandomNumberGenerator,
	radius: float,
	point_count: int
) -> PackedVector2Array:
	var silhouette := PackedVector2Array()
	for point_index: int in range(point_count):
		var point_angle := TAU * float(point_index) / float(point_count)
		var point_radius := radius * random.randf_range(0.76, 1.12)
		silhouette.append(Vector2.RIGHT.rotated(point_angle) * point_radius)
	return silhouette
