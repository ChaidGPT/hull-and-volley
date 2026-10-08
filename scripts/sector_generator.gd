class_name SectorGenerator
extends RefCounted

const MINIMUM_SECTOR_RADIUS := 7200.0
const MAXIMUM_SECTOR_RADIUS := 8800.0
const ARRIVAL_CLEARANCE := 1050.0
const LANDMARK_CLEARANCE := 1150.0
const ENVIRONMENTS := [
	&"OPEN_SPACE",
	&"SCATTERED_ASTEROIDS",
	&"ASTEROID_FIELD",
	&"ASTEROID_BELT",
]


## Builds a deterministic spatial plan. GeneratedSector owns the result so a
## save/reload or a return to the same route never rerolls its geography.
func generate_plan(sector: GeneratedSector, opening_sector := false) -> void:
	if sector == null:
		return
	var random := RandomNumberGenerator.new()
	random.seed = sector.generation_seed ^ 0x5EC70A
	sector.sector_radius = random.randf_range(MINIMUM_SECTOR_RADIUS, MAXIMUM_SECTOR_RADIUS)
	sector.safe_radius = sector.sector_radius
	sector.entry_position = Vector2.ZERO
	sector.entry_rotation = 0.0
	sector.arrival_clearance = ARRIVAL_CLEARANCE
	for previous_environment: StringName in ENVIRONMENTS:
		sector.sector_tags.erase(String(previous_environment))
	sector.environment_type = _roll_environment(sector.archetype_id, random, opening_sector)
	sector.environment_regions = _build_environment_regions(sector, random)
	sector.landmarks = _build_landmarks(sector, random, opening_sector)
	sector.transit_routes = _build_transit_routes(sector, random)
	var environment_tag := String(sector.environment_type)
	if not sector.sector_tags.has(environment_tag):
		sector.sector_tags.append(environment_tag)
	for index: int in range(sector.intel_lines.size() - 1, -1, -1):
		if sector.intel_lines[index].begins_with("ENVIRONMENT •"):
			sector.intel_lines.remove_at(index)
	sector.intel_lines.append("ENVIRONMENT • %s" % environment_tag.replace("_", " "))


func _roll_environment(
	archetype_id: StringName,
	random: RandomNumberGenerator,
	opening_sector: bool
) -> StringName:
	var weights := [1.0, 1.0, 1.0, 1.0]
	match archetype_id:
		&"ASTEROID_FRONTIER":
			weights = [0.7, 2.4, 3.4, 3.0]
		&"FLEET_ANCHORAGE":
			weights = [4.0, 2.1, 0.8, 0.5]
		&"CONTESTED_FRONT":
			weights = [1.8, 3.0, 2.0, 1.1]
		&"PLANETOID_HOLD":
			weights = [0.8, 1.8, 3.3, 1.9]
	if opening_sector:
		# Every environment is legal in the escape sector, but the two middle
		# densities are friendlier to a newly assembled hull.
		weights = [1.4, 3.2, 3.0, 1.5]
	var total := 0.0
	for weight: float in weights:
		total += weight
	var cursor := random.randf_range(0.0, total)
	for index: int in range(ENVIRONMENTS.size()):
		cursor -= weights[index]
		if cursor <= 0.0:
			return ENVIRONMENTS[index]
	return ENVIRONMENTS.back()


func _build_environment_regions(
	sector: GeneratedSector,
	random: RandomNumberGenerator
) -> Array[Dictionary]:
	var regions: Array[Dictionary] = []
	match sector.environment_type:
		&"SCATTERED_ASTEROIDS":
			var count := random.randi_range(3, 5)
			for index: int in range(count):
				var radius := random.randf_range(520.0, 850.0)
				regions.append(_asteroid_region(
					sector,
					random,
					index,
					_sample_region_center(sector, regions, random, radius),
					radius,
					random.randi_range(3, 6),
					"SCATTERED ASTEROID CLUSTER"
				))
		&"ASTEROID_FIELD":
			var count := random.randi_range(1, 2)
			for index: int in range(count):
				var radius := random.randf_range(1450.0, 2050.0)
				regions.append(_asteroid_region(
					sector,
					random,
					index,
					_sample_region_center(sector, regions, random, radius),
					radius,
					random.randi_range(13, 20),
					"DEEP ASTEROID FIELD"
				))
		&"ASTEROID_BELT":
			var belt_angle := random.randf_range(-PI, PI)
			var along := Vector2.RIGHT.rotated(belt_angle)
			var across := along.orthogonal()
			var bend := random.randf_range(-950.0, 950.0)
			var node_count := random.randi_range(7, 8)
			for index: int in range(node_count):
				var progress := float(index) / float(node_count - 1)
				var distance := lerpf(-sector.sector_radius * 0.72, sector.sector_radius * 0.72, progress)
				var arc := sin(progress * PI) * bend
				var center := along * distance + across * arc
				var radius := random.randf_range(950.0, 1320.0)
				regions.append(_asteroid_region(
					sector,
					random,
					index,
					center,
					radius,
					random.randi_range(3, 5),
					"SECTOR-SPANNING ASTEROID BELT"
				))
		_:
			pass
	return regions


func _asteroid_region(
	sector: GeneratedSector,
	random: RandomNumberGenerator,
	index: int,
	center: Vector2,
	radius: float,
	physical_count: int,
	display_name: String
) -> Dictionary:
	var is_belt_node := display_name == "SECTOR-SPANNING ASTEROID BELT"
	return {
		"id": StringName("REGION_%02d_%08X" % [index, abs(random.randi()) % 0x7FFFFFFF]),
		"type": &"ASTEROIDS",
		"display_name": display_name,
		"center": center,
		"radius": radius,
		"seed": random.randi(),
		"physical_count": physical_count,
		# A belt is made from several overlapping sheets, so each sheet receives
		# a smaller draw budget than a stand-alone field.
		"far_count": random.randi_range(30, 40) if is_belt_node else clampi(int(radius / 8.0), 70, 240),
		"middle_count": random.randi_range(14, 22) if is_belt_node else clampi(int(radius / 17.0), 32, 120),
		"exclusion_center": sector.entry_position,
		"exclusion_radius": sector.arrival_clearance,
	}


func _sample_region_center(
	sector: GeneratedSector,
	existing: Array[Dictionary],
	random: RandomNumberGenerator,
	radius: float
) -> Vector2:
	for _attempt: int in range(48):
		var point := Vector2.RIGHT.rotated(random.randf_range(-PI, PI)) * random.randf_range(
			sector.arrival_clearance + radius * 0.55,
			sector.sector_radius - radius - 450.0
		)
		var clear := true
		for region: Dictionary in existing:
			if point.distance_to(Vector2(region["center"])) < radius + float(region["radius"]) * 0.7:
				clear = false
				break
		if clear:
			return point
	return Vector2.RIGHT.rotated(random.randf_range(-PI, PI)) * sector.sector_radius * 0.55


func _build_landmarks(
	sector: GeneratedSector,
	random: RandomNumberGenerator,
	opening_sector: bool
) -> Array[Dictionary]:
	var landmarks: Array[Dictionary] = []
	if opening_sector:
		landmarks.append(_landmark(&"STARTER_CACHE", _sample_landmark_position(sector, landmarks, random, 1050.0, 1850.0)))
		landmarks.append(_landmark(&"TRAINING_RANGE", _sample_landmark_position(sector, landmarks, random, 1900.0, 3200.0)))
		landmarks.append(_landmark(&"OUTPOST", _sample_landmark_position(sector, landmarks, random, 2300.0, 3900.0)))
	else:
		match sector.archetype_id:
			&"ASTEROID_FRONTIER":
				landmarks.append(_landmark(&"OUTPOST", _sample_landmark_position(sector, landmarks, random)))
			&"FLEET_ANCHORAGE":
				landmarks.append(_landmark(&"OUTPOST", _sample_landmark_position(sector, landmarks, random)))
			&"PLANETOID_HOLD":
				landmarks.append(_landmark(&"OUTPOST", _sample_landmark_position(sector, landmarks, random)))
	if random.randf() < 0.65:
		landmarks.append(_landmark(&"SALVAGE_SITE", _sample_landmark_position(sector, landmarks, random)))
	return landmarks


func _landmark(type: StringName, position: Vector2) -> Dictionary:
	return {"type": type, "position": position}


func _sample_landmark_position(
	sector: GeneratedSector,
	existing: Array[Dictionary],
	random: RandomNumberGenerator,
	minimum_distance := 1500.0,
	maximum_distance := -1.0
) -> Vector2:
	var outer := sector.sector_radius - 900.0 if maximum_distance < 0.0 else maximum_distance
	for _attempt: int in range(64):
		var point := Vector2.RIGHT.rotated(random.randf_range(-PI, PI)) * random.randf_range(minimum_distance, outer)
		var clear := point.distance_to(sector.entry_position) >= sector.arrival_clearance
		for landmark: Dictionary in existing:
			if point.distance_to(Vector2(landmark["position"])) < LANDMARK_CLEARANCE:
				clear = false
				break
		if clear:
			return point
	return Vector2.RIGHT.rotated(random.randf_range(-PI, PI)) * minimum_distance


func _build_transit_routes(
	sector: GeneratedSector,
	random: RandomNumberGenerator
) -> Array[PackedVector2Array]:
	var routes: Array[PackedVector2Array] = []
	if sector.archetype_id not in [&"FLEET_ANCHORAGE", &"CONTESTED_FRONT"] and random.randf() > 0.35:
		return routes
	var direction := Vector2.RIGHT.rotated(random.randf_range(-PI, PI))
	var across := direction.orthogonal()
	var extent := sector.sector_radius * 0.82
	var bend := random.randf_range(-650.0, 650.0)
	routes.append(PackedVector2Array([
		direction * -extent,
		direction * (-extent * 0.32) + across * bend,
		direction * (extent * 0.35) - across * bend * 0.55,
		direction * extent,
	]))
	return routes
