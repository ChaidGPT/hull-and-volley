extends SceneTree

const GENERATED_SECTOR := preload("res://scripts/resources/generated_sector.gd")
const SECTOR_GENERATOR := preload("res://scripts/sector_generator.gd")
const SPECIAL_REGION := preload("res://scripts/resources/sector_special_region.gd")


func _init() -> void:
	var failures: Array[String] = []
	var generator := SECTOR_GENERATOR.new() as SectorGenerator
	var first := _sector(481516, &"ASTEROID_FRONTIER")
	var repeated := _sector(481516, &"ASTEROID_FRONTIER")
	generator.generate_plan(first, true)
	generator.generate_plan(repeated, true)
	_check(first.sector_radius >= 7200.0, "generated sector is still using the compact legacy scale", failures)
	_check(first.environment_type == repeated.environment_type, "identical seeds chose different environments", failures)
	_check(var_to_str(first.environment_regions) == var_to_str(repeated.environment_regions), "identical seeds produced different asteroid geography", failures)
	_check(var_to_str(first.landmarks) == var_to_str(repeated.landmarks), "identical seeds produced different landmarks", failures)

	var landmark_types := PackedStringArray()
	for landmark: Dictionary in first.landmarks:
		landmark_types.append(String(landmark.get("type", "")))
		_check(
			Vector2(landmark.get("position", Vector2.ZERO)).distance_to(first.entry_position) >= first.arrival_clearance,
			"opening landmark intrudes into the jump-arrival safety pocket",
			failures
		)
	_check(landmark_types.has("STARTER_CACHE"), "opening plan lost its guaranteed starter salvage", failures)
	_check(landmark_types.has("TRAINING_RANGE"), "opening plan lost its proving targets", failures)
	_check(landmark_types.has("OUTPOST"), "opening plan lost its dockable waystation", failures)

	var environments := PackedStringArray()
	var geography_signatures := PackedStringArray()
	for seed_value: int in range(100, 124):
		var generated := _sector(seed_value, &"ASTEROID_FRONTIER")
		generator.generate_plan(generated, true)
		if not environments.has(String(generated.environment_type)):
			environments.append(String(generated.environment_type))
		var signature := "%s:%s:%s" % [generated.environment_type, generated.environment_regions, generated.landmarks]
		if not geography_signatures.has(signature):
			geography_signatures.append(signature)
	_check(environments.size() >= 3, "opening generation does not expose meaningful environmental variety", failures)
	_check(geography_signatures.size() >= 20, "opening geography repeats too often across run seeds", failures)

	var belt_sector := _sector(8675309, &"ASTEROID_FRONTIER")
	belt_sector.sector_radius = 8000.0
	belt_sector.arrival_clearance = 1050.0
	belt_sector.environment_type = &"ASTEROID_BELT"
	var belt_random := RandomNumberGenerator.new()
	belt_random.seed = belt_sector.generation_seed
	var belt_regions: Array[Dictionary] = generator.call("_build_environment_regions", belt_sector, belt_random)
	_check(belt_regions.size() >= 7, "full asteroid belt is still a single local clump", failures)
	var minimum_projection := INF
	var maximum_projection := -INF
	if belt_regions.size() >= 2:
		var axis := Vector2(belt_regions[0]["center"]).direction_to(Vector2(belt_regions.back()["center"]))
		for region: Dictionary in belt_regions:
			var projection := Vector2(region["center"]).dot(axis)
			minimum_projection = minf(minimum_projection, projection)
			maximum_projection = maxf(maximum_projection, projection)
	_check(maximum_projection - minimum_projection > 9000.0, "full asteroid belt does not span the sector", failures)

	var physical_region := SPECIAL_REGION.new() as SectorSpecialRegion
	physical_region.center = Vector2.ZERO
	physical_region.world_radius = 1800.0
	physical_region.generation_seed = 9001
	physical_region.physical_object_count = 40
	physical_region.exclusion_center = Vector2.ZERO
	physical_region.exclusion_radius = 1050.0
	physical_region.generate_asteroid_belt()
	for object: Dictionary in physical_region.physical_objects:
		_check(
			Vector2(object["offset"]).length() >= 1050.0 + float(object["radius"]),
			"physical asteroid generated inside the arrival safety pocket",
			failures
		)

	if failures.is_empty():
		print("SECTOR GENERATOR TEST // PASS // DETERMINISTIC LARGE-SCALE GEOGRAPHY AND SAFE ARRIVAL")
	else:
		for failure: String in failures:
			push_error("SECTOR GENERATOR TEST // FAIL // %s" % failure)
	quit(0 if failures.is_empty() else 1)


func _sector(seed_value: int, archetype: StringName) -> GeneratedSector:
	var sector := GENERATED_SECTOR.new() as GeneratedSector
	sector.generation_seed = seed_value
	sector.archetype_id = archetype
	return sector


func _check(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
