class_name SectorPopulation
extends Node

const SPECIAL_REGION := preload("res://scripts/resources/sector_special_region.gd")
const SMALL_ASTEROID_SCENE := preload("res://scenes/asteroids/asteroid_small_01.tscn")
const MEDIUM_ASTEROID_SCENE := preload("res://scenes/asteroids/asteroid_medium_01.tscn")
const LARGE_ASTEROID_SCENE := preload("res://scenes/asteroids/asteroid_large_01.tscn")
const SMALL_ASTEROID_MAXIMUM_RADIUS := 22.0
const MEDIUM_ASTEROID_MAXIMUM_RADIUS := 32.0

@export_category("Neutral Encounter Pool")
## Weighted possibilities available to future procedural sector rolls.
@export var neutral_encounter_pool: Array[Resource] = []

@export_category("Opening Sector")
@export var populate_opening_sector := true
@export var mining_outpost_definition: Resource
@export var bulk_miner_definition: Resource
@export var freighter_definition: Resource

var special_regions: Array[Resource] = []
var physical_asteroids: Array[Dictionary] = []
var shipping_lanes: Array[Dictionary] = []
var spawned_contact_ids: Array[int] = []
var combat_simulation: Node


func _ready() -> void:
	add_to_group("sector_population")
	combat_simulation = get_tree().get_first_node_in_group("combat_simulation")
	if populate_opening_sector:
		call_deferred("_populate_opening_sector")


func get_neutral_encounter_pool() -> Array[Resource]:
	return neutral_encounter_pool


func populate_generated_sector(sector: GeneratedSector) -> void:
	if sector == null:
		return
	clear_sector_population()
	var random := RandomNumberGenerator.new()
	random.seed = sector.generation_seed
	match sector.environment_type:
		&"ASTEROID_BELT":
			_build_generated_asteroid_belt(
				Vector2(-260.0, -80.0),
				sector.generation_seed,
				880.0,
				18
			)
			_spawn_generated_outpost(
				Vector2(-420.0, -160.0),
				"%s SALVAGE EXCHANGE" % sector.display_name
			)
		&"FLEET_ANCHORAGE":
			_build_generated_shipping_lane(random, -720.0)
			_spawn_generated_outpost(Vector2(720.0, -180.0), "UDC VECTOR CONTROL")
			if freighter_definition != null:
				spawn_neutral_formation(
					freighter_definition,
					PackedStringArray(["UDC ATLAS", "UDC LEDGER", "UDC MAGNATE"]),
					[
						Vector2(-1450.0, 520.0),
						Vector2(-420.0, 460.0),
						Vector2(620.0, 560.0),
						Vector2(1460.0, 420.0),
					],
					120.0
				)
		&"BATTLEFIELD":
			_build_generated_asteroid_belt(
				Vector2(620.0, -460.0),
				sector.generation_seed,
				540.0,
				8
			)
			_build_generated_shipping_lane(random, 680.0)
			if freighter_definition != null:
				spawn_neutral_formation(
					freighter_definition,
					PackedStringArray(["USC RELAY", "FSR RUNNER"]),
					[
						Vector2(-1250.0, 650.0),
						Vector2(0.0, 520.0),
						Vector2(1250.0, 680.0),
					],
					180.0
				)
		&"PLANETOID_SETTLEMENT":
			_build_generated_asteroid_belt(
				Vector2(760.0, -120.0),
				sector.generation_seed,
				980.0,
				14
			)
			_spawn_generated_outpost(Vector2(760.0, -120.0), "ANCHORSTONE HOLD")
		_:
			_build_generated_shipping_lane(random, 540.0)


func clear_sector_population() -> void:
	if not is_instance_valid(combat_simulation):
		combat_simulation = get_tree().get_first_node_in_group("combat_simulation")
	if is_instance_valid(combat_simulation):
		combat_simulation.call("clear_enemies")
	for asteroid: Dictionary in physical_asteroids:
		var body_value: Variant = asteroid.get("body")
		if is_instance_valid(body_value):
			(body_value as RigidBody2D).queue_free()
	special_regions.clear()
	physical_asteroids.clear()
	shipping_lanes.clear()
	spawned_contact_ids.clear()


func get_special_region_at_position(world_position: Vector2) -> Resource:
	for region: Resource in special_regions:
		if region != null and bool(region.call("contains_world_position", world_position)):
			return region
	return null


func get_special_region_reports() -> Array[Dictionary]:
	var reports: Array[Dictionary] = []
	for region: Resource in special_regions:
		if region != null:
			reports.append(region.call("get_environment_report"))
	return reports


## Stable obstacle data for helm pathfinding, NPC steering, mining, and targeting.
## The physics body remains authoritative for moving region objects.
func get_navigation_obstacles() -> Array[Dictionary]:
	var obstacles: Array[Dictionary] = []
	for asteroid: Dictionary in physical_asteroids:
		var body_value: Variant = asteroid.get("body")
		if not is_instance_valid(body_value):
			continue
		var body := body_value as RigidBody2D
		obstacles.append({
			"id": int(asteroid.get("id", -1)),
			"region_id": StringName(asteroid.get("region_id", &"")),
			"type": &"ASTEROID",
			"position": body.position,
			"velocity": body.linear_velocity,
			"radius": float(asteroid.get("radius", 0.0)),
			"body": body,
		})
	return obstacles


## Stable test/gameplay entry point for mining tools, scripted hazards, and developer checks.
func damage_asteroid(asteroid_id: int, damage: float) -> bool:
	for asteroid: Dictionary in physical_asteroids:
		if int(asteroid.get("id", -1)) != asteroid_id:
			continue
		var body_value: Variant = asteroid.get("body")
		if not is_instance_valid(body_value):
			return false
		var body := body_value as RigidBody2D
		if not body.has_method("apply_projectile_damage"):
			return false
		body.call("apply_projectile_damage", damage)
		return true
	return false


func get_asteroid_health_reports() -> Array[Dictionary]:
	var reports: Array[Dictionary] = []
	for asteroid: Dictionary in physical_asteroids:
		var body_value: Variant = asteroid.get("body")
		if not is_instance_valid(body_value):
			continue
		var body := body_value as RigidBody2D
		if body.has_method("get_health_report"):
			reports.append(body.call("get_health_report"))
	return reports


func roll_neutral_encounters(
	result_count: int,
	required_sector_tags: PackedStringArray = PackedStringArray(),
	seed: int = 0
) -> Array[Resource]:
	var available: Array[Resource] = []
	for encounter: Resource in neutral_encounter_pool:
		if encounter == null or float(encounter.get("selection_weight")) <= 0.0:
			continue
		var encounter_tags: PackedStringArray = encounter.get("sector_tags")
		var matches := true
		for required_tag: String in required_sector_tags:
			if not encounter_tags.has(required_tag):
				matches = false
				break
		if matches:
			available.append(encounter)
	var results: Array[Resource] = []
	var random := RandomNumberGenerator.new()
	random.seed = seed if seed != 0 else int(Time.get_unix_time_from_system())
	while not available.is_empty() and results.size() < maxi(result_count, 0):
		var total_weight := 0.0
		for encounter: Resource in available:
			total_weight += float(encounter.get("selection_weight"))
		var cursor := random.randf_range(0.0, total_weight)
		var chosen_index := available.size() - 1
		for index: int in range(available.size()):
			cursor -= float(available[index].get("selection_weight"))
			if cursor <= 0.0:
				chosen_index = index
				break
		results.append(available.pop_at(chosen_index))
	return results


func spawn_neutral_formation(
	ship_definition: Resource,
	contact_names: PackedStringArray,
	route: Array[Vector2],
	formation_spacing: float = 95.0
) -> Array[int]:
	var contact_ids: Array[int] = []
	if (
		not is_instance_valid(combat_simulation)
		or ship_definition == null
		or route.is_empty()
		or contact_names.is_empty()
	):
		return contact_ids
	var forward := Vector2.UP
	if route.size() > 1:
		forward = route[0].direction_to(route[1])
	var across := forward.orthogonal()
	var center_index := (float(contact_names.size()) - 1.0) * 0.5
	for index: int in range(contact_names.size()):
		var offset := across * (float(index) - center_index) * formation_spacing
		var offset_route: Array[Vector2] = []
		for route_point: Vector2 in route:
			offset_route.append(route_point + offset)
		var contact_id: int = combat_simulation.call(
			"spawn_neutral_contact",
			ship_definition,
			offset_route[0],
			Vector2.UP.angle_to(forward),
			contact_names[index],
			&"TRANSIT_FLEET",
			offset_route,
			true,
			2.0
		)
		if contact_id >= 0:
			contact_ids.append(contact_id)
			spawned_contact_ids.append(contact_id)
	return contact_ids


func _populate_opening_sector() -> void:
	if not is_instance_valid(combat_simulation):
		combat_simulation = get_tree().get_first_node_in_group("combat_simulation")
	if not is_instance_valid(combat_simulation):
		return

	# The first sector is deliberately compact: collect parts, refit at the
	# proving yard, then arm a reusable target before committing to a jump.
	_build_generated_asteroid_belt(Vector2(-620.0, -420.0), 0x51A27E, 330.0, 4)
	_spawn_starter_grid_cache()
	_spawn_opening_training_range()


func _spawn_starter_grid_cache() -> void:
	# Run loot is intentionally limited to rooms with finished in-world art.
	# The Forge keeps its complete development catalog.
	var cache := [
		{"type": "WEAPON:explosive_cannon_mount", "position": Vector2(-250.0, -65.0)},
		{"type": "WEAPON:laser_emitter_mount", "position": Vector2(-305.0, -120.0)},
		{"type": "REACTOR", "position": Vector2(-365.0, -80.0)},
	]
	for index: int in range(cache.size()):
		var entry: Dictionary = cache[index]
		combat_simulation.call(
			"spawn_grid_pickup",
			String(entry["type"]),
			Vector2(entry["position"]),
			Vector2(0.0, -2.0).rotated(float(index) * 0.7)
		)


func _spawn_opening_training_range() -> void:
	var positions := [Vector2(420.0, -190.0), Vector2(680.0, -270.0)]
	for index: int in range(2):
		var target_id: int = combat_simulation.call(
			"spawn_training_target",
			index % 2,
			positions[index],
			"PROVING TARGET %02d" % (index + 1)
		)
		if target_id >= 0:
			spawned_contact_ids.append(target_id)


func _build_shipping_lane() -> void:
	shipping_lanes.append({
		"id": &"EAST_WEST_FREIGHT",
		"display_name": "MERIDIAN SHIPPING LANE",
		"points": PackedVector2Array([
			Vector2(-1780.0, 760.0),
			Vector2(-780.0, 690.0),
			Vector2(180.0, 760.0),
			Vector2(1060.0, 560.0),
			Vector2(1750.0, 720.0),
		]),
		"color": Color(0.22, 0.72, 0.7, 0.18),
	})


func _build_asteroid_worksite(center: Vector2) -> void:
	_build_generated_asteroid_belt(center, 0x5EC70A, 680.0, 12)


func _build_generated_asteroid_belt(
	center: Vector2,
	seed: int,
	radius: float,
	physical_count: int
) -> void:
	var region := SPECIAL_REGION.new() as SectorSpecialRegion
	region.region_id = StringName("BELT_%08X" % (abs(seed) % 0x7FFFFFFF))
	region.display_name = "CHARTED ASTEROID FIELD"
	region.center = center
	region.world_radius = radius
	region.generation_seed = seed
	region.physical_object_count = clampi(physical_count, 0, 40)
	region.generate_asteroid_belt()
	special_regions.append(region)
	_spawn_physical_asteroids(region)


func _build_generated_shipping_lane(
	random: RandomNumberGenerator,
	vertical_position: float
) -> void:
	var bend := random.randf_range(-180.0, 180.0)
	var lane_points: Array[Vector2] = [
		Vector2(-1750.0, vertical_position),
		Vector2(-620.0, vertical_position + bend),
		Vector2(520.0, vertical_position - bend * 0.45),
		Vector2(1750.0, vertical_position + bend * 0.2),
	]
	shipping_lanes.append({
		"id": StringName("GENERATED_LANE_%08X" % (abs(random.randi()) % 0x7FFFFFFF)),
		"display_name": "LONG-RANGE TRANSIT CORRIDOR",
		"points": PackedVector2Array(lane_points),
		"color": Color(0.22, 0.72, 0.7, 0.18),
	})
	if freighter_definition == null:
		return
	for index: int in range(2):
		var route := lane_points.duplicate()
		if index == 1:
			route.reverse()
		var contact_id: int = combat_simulation.call(
			"spawn_neutral_contact",
			freighter_definition,
			route[0],
			-PI * 0.5 if index == 0 else PI * 0.5,
			["MV FAR SIGNAL", "MV QUIET CURRENT"][index],
			&"LANE_FREIGHTER",
			route,
			true,
			3.0 + index
		)
		if contact_id >= 0:
			spawned_contact_ids.append(contact_id)


func _spawn_generated_outpost(position: Vector2, display_name: String) -> void:
	if mining_outpost_definition == null or not is_instance_valid(combat_simulation):
		return
	var contact_id: int = combat_simulation.call(
		"spawn_neutral_contact",
		mining_outpost_definition,
		position,
		0.0,
		display_name,
		&"GENERATED_OUTPOST",
		[],
		true,
		6.0
	)
	if contact_id >= 0:
		spawned_contact_ids.append(contact_id)


func _spawn_physical_asteroids(region: SectorSpecialRegion) -> void:
	var physics_parent := get_node_or_null("../PhysicsWorld")
	if not is_instance_valid(physics_parent):
		push_warning("SectorPopulation could not find PhysicsWorld for physical region objects.")
		return
	for object: Dictionary in region.physical_objects:
		var radius := float(object["radius"])
		var asteroid_scene := _asteroid_scene_for_radius(radius)
		var body := asteroid_scene.instantiate() as PhysicalAsteroid
		body.configure(
			int(object["id"]),
			region.region_id,
			radius,
			object["silhouette"],
			object["color"]
		)
		physics_parent.add_child(body)
		body.destroyed.connect(_on_physical_asteroid_destroyed.bind(region.region_id))
		body.position = region.center + Vector2(object["offset"])
		body.rotation = float(object["rotation"])
		body.linear_velocity = Vector2(object["linear_velocity"])
		body.angular_velocity = float(object["angular_velocity"])
		physical_asteroids.append({
			"id": int(object["id"]),
			"region_id": region.region_id,
			"body": body,
			"radius": float(object["radius"]),
			"silhouette": object["silhouette"],
			"color": object["color"],
		})


func _asteroid_scene_for_radius(radius: float) -> PackedScene:
	if radius <= SMALL_ASTEROID_MAXIMUM_RADIUS:
		return SMALL_ASTEROID_SCENE
	if radius <= MEDIUM_ASTEROID_MAXIMUM_RADIUS:
		return MEDIUM_ASTEROID_SCENE
	return LARGE_ASTEROID_SCENE


func _on_physical_asteroid_destroyed(
	asteroid_id: int,
	_world_position: Vector2,
	_world_rotation: float,
	_visual_radius: float,
	_size_class: StringName,
	region_id: StringName
) -> void:
	call_deferred("_remove_destroyed_asteroid", asteroid_id, region_id)


func _remove_destroyed_asteroid(asteroid_id: int, region_id: StringName) -> void:
	for index: int in range(physical_asteroids.size() - 1, -1, -1):
		if (
			int(physical_asteroids[index].get("id", -1)) == asteroid_id
			and StringName(physical_asteroids[index].get("region_id", &"")) == region_id
		):
			physical_asteroids.remove_at(index)
