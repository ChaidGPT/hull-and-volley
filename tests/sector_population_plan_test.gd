extends SceneTree

const MAIN_SCENE := preload("res://scenes/main.tscn")
const GENERATED_SECTOR := preload("res://scripts/resources/generated_sector.gd")
const SECTOR_GENERATOR := preload("res://scripts/sector_generator.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failures: Array[String] = []
	var main := MAIN_SCENE.instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	var population := main.get_node("SectorPopulation") as SectorPopulation
	var combat := main.get_node("CombatSimulation")
	var sector_simulation := main.get_node("SectorSimulation") as SectorSimulation
	var generator := SECTOR_GENERATOR.new() as SectorGenerator
	var sector: GeneratedSector
	for seed_value: int in range(200, 240):
		var candidate := GENERATED_SECTOR.new() as GeneratedSector
		candidate.generation_seed = seed_value
		candidate.archetype_id = &"ASTEROID_FRONTIER"
		candidate.display_name = "TEST REACH"
		generator.generate_plan(candidate, true)
		if not candidate.environment_regions.is_empty():
			sector = candidate
			break
	_check(sector != null, "test could not roll a physical asteroid environment", failures)
	if sector != null:
		sector.sector_tags.append("ESCAPE_ENTRY")
		sector_simulation.configure_generated_sector(sector)
		population.populate_generated_sector(sector)
		await physics_frame
		await process_frame
		_check(sector_simulation.objectives.has(&"RECOVER_GRID"), "generated opening sector lost its salvage objective", failures)
		_check(sector_simulation.objectives.has(&"ARM_PROVING_TARGET"), "generated opening sector lost its proving-range objective", failures)
		_check(population.special_regions.size() == sector.environment_regions.size(), "population ignored generated environment regions", failures)
		_check(population.physical_asteroids.size() > 0, "generated asteroid environment has no physical navigation hazards", failures)
		for asteroid: Dictionary in population.physical_asteroids:
			var body := asteroid.get("body") as RigidBody2D
			if not is_instance_valid(body):
				continue
			_check(
				body.position.distance_to(sector.entry_position) >= sector.arrival_clearance + float(asteroid.get("radius", 0.0)),
				"populated asteroid intrudes into the arrival safety pocket",
				failures
			)
		_check(combat.get("grid_pickups").size() >= 3, "generated opening sector lost its salvage cache", failures)
		_check(population.spawned_contact_ids.size() >= 3, "generated opening sector lost its targets or waystation", failures)

	main.queue_free()
	await process_frame
	if failures.is_empty():
		print("SECTOR POPULATION PLAN TEST // PASS // PLAN MATERIALIZES INTO SAFE LIVE CONTENT")
	else:
		for failure: String in failures:
			push_error("SECTOR POPULATION PLAN TEST // FAIL // %s" % failure)
	quit(0 if failures.is_empty() else 1)


func _check(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
