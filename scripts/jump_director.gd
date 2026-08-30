class_name JumpDirector
extends Node

signal routes_generated(routes: Array[Resource])
signal destination_committed(destination: GeneratedSector)

@export var archetype_pool: Array[Resource] = []
@export var modifier_pool: Array[Resource] = []
@export_range(2, 4, 1) var default_route_count := 3

var run_state: RunState
var generation_serial := 0


func _ready() -> void:
	add_to_group("jump_director")
	run_state = get_tree().get_first_node_in_group("run_state") as RunState
	if archetype_pool.is_empty():
		_build_default_archetypes()
	if modifier_pool.is_empty():
		_build_default_modifiers()


func generate_jump_routes(route_count: int = -1) -> Array[Resource]:
	if not is_instance_valid(run_state):
		run_state = get_tree().get_first_node_in_group("run_state") as RunState
	var count := default_route_count if route_count < 0 else clampi(route_count, 2, 4)
	var next_depth := (run_state.sector_depth if is_instance_valid(run_state) else 0) + 1
	var random := RandomNumberGenerator.new()
	var base_seed := run_state.run_seed if is_instance_valid(run_state) else 1
	random.seed = base_seed + next_depth * 104729 + generation_serial * 8191
	generation_serial += 1
	var available: Array[SectorArchetype] = []
	for archetype_value: Resource in archetype_pool:
		var archetype := archetype_value as SectorArchetype
		if archetype != null and archetype.is_available_at_depth(next_depth):
			available.append(archetype)
	var chosen: Array[SectorArchetype] = []
	while not available.is_empty() and chosen.size() < count:
		var chosen_index := _weighted_archetype_index(available, random)
		chosen.append(available.pop_at(chosen_index))
	var routes: Array[Resource] = []
	for index: int in range(chosen.size()):
		routes.append(_build_generated_sector(chosen[index], next_depth, random, index))
	routes_generated.emit(routes)
	return routes


func commit_destination(destination: GeneratedSector) -> void:
	if destination == null:
		return
	destination_committed.emit(destination)


func generate_opening_sector() -> GeneratedSector:
	if archetype_pool.is_empty():
		_build_default_archetypes()
	var random := RandomNumberGenerator.new()
	var base_seed := run_state.run_seed if is_instance_valid(run_state) else 1
	random.seed = base_seed + 7717
	var opening_archetype := archetype_pool[0] as SectorArchetype
	var sector := _build_generated_sector(opening_archetype, 1, random, 0)
	sector.display_name = "MORROW DRIFT"
	sector.intel_summary = "A thin salvage belt beyond the blacksite patrol envelope."
	sector.danger_rating = mini(sector.danger_rating, 14)
	sector.sector_tags.append("ESCAPE_ENTRY")
	sector.intel_lines = PackedStringArray([
		"SCATTERED SALVAGE RETURNS",
		"IMPOUND TRANSPONDER TRAIL DECAYING",
		"LIMITED HOSTILE PRESENCE",
	])
	return sector


func _weighted_archetype_index(
	available: Array[SectorArchetype],
	random: RandomNumberGenerator
) -> int:
	var total_weight := 0.0
	var weights: Array[float] = []
	for archetype: SectorArchetype in available:
		var weight := archetype.selection_weight
		if is_instance_valid(run_state) and run_state.has_recent_archetype(archetype.archetype_id):
			weight *= 0.22
		weights.append(weight)
		total_weight += weight
	if total_weight <= 0.0:
		return random.randi_range(0, available.size() - 1)
	var cursor := random.randf_range(0.0, total_weight)
	for index: int in range(weights.size()):
		cursor -= weights[index]
		if cursor <= 0.0:
			return index
	return weights.size() - 1


func _build_generated_sector(
	archetype: SectorArchetype,
	depth: int,
	random: RandomNumberGenerator,
	option_index: int
) -> GeneratedSector:
	var sector := GeneratedSector.new()
	sector.run_depth = depth
	sector.generation_seed = random.randi()
	sector.archetype_id = archetype.archetype_id
	sector.environment_type = archetype.environment_type
	sector.display_name = _sector_name_for(archetype, random)
	sector.sector_id = StringName(
		"%s_%02d_%04X" % [
			String(archetype.archetype_id),
			depth,
			abs(sector.generation_seed) % 65536,
		]
	)
	sector.intel_summary = archetype.description
	sector.sector_tags = archetype.intel_tags.duplicate()
	sector.faction_signals = archetype.likely_factions.duplicate()
	sector.safe_radius = archetype.safe_radius
	sector.hazard_enabled = archetype.hazard_enabled
	sector.signal_color = archetype.signal_color
	var depth_pressure := maxi(depth - 1, 0) * 4
	sector.danger_rating = clampi(archetype.base_danger + depth_pressure + random.randi_range(-3, 4), 0, 100)
	var lines := PackedStringArray()
	for tag: String in archetype.intel_tags:
		lines.append(_humanize_tag(tag))
	for faction: String in archetype.likely_factions:
		lines.append("%s SIGNALS DETECTED" % faction)
	var modifier := _roll_modifier(archetype, depth, random, option_index)
	if modifier != null:
		sector.modifier_ids.append(String(modifier.modifier_id))
		sector.danger_rating = clampi(
			sector.danger_rating + modifier.danger_adjustment,
			0,
			100
		)
		for tag: String in modifier.added_tags:
			if not sector.sector_tags.has(tag):
				sector.sector_tags.append(tag)
		if not modifier.intel_line.is_empty():
			lines.append(modifier.intel_line.to_upper())
	sector.intel_lines = lines
	return sector


func _roll_modifier(
	archetype: SectorArchetype,
	depth: int,
	random: RandomNumberGenerator,
	option_index: int
) -> SectorModifier:
	var available: Array[SectorModifier] = []
	for modifier_value: Resource in modifier_pool:
		var modifier := modifier_value as SectorModifier
		if modifier != null and modifier.supports_archetype(archetype, depth):
			available.append(modifier)
	if available.is_empty() or (depth <= 1 and option_index == 0):
		return null
	var total_weight := 0.0
	for modifier: SectorModifier in available:
		total_weight += modifier.selection_weight
	var cursor := random.randf_range(0.0, total_weight)
	for modifier: SectorModifier in available:
		cursor -= modifier.selection_weight
		if cursor <= 0.0:
			return modifier
	return available.back()


func _sector_name_for(archetype: SectorArchetype, random: RandomNumberGenerator) -> String:
	var prefixes := [
		"KHEPRI", "TALARIS", "VESPER", "MERIDIAN",
		"ANCHORSTONE", "CARINA", "ORISON", "DRAKE",
	]
	var suffixes := [
		"REACH", "BREAK", "DEEP", "CROSSING",
		"ANCHORAGE", "EXPANSE", "FRONT", "DRIFT",
	]
	return "%s %s" % [
		prefixes[random.randi_range(0, prefixes.size() - 1)],
		suffixes[random.randi_range(0, suffixes.size() - 1)],
	]


func _humanize_tag(tag: String) -> String:
	return tag.replace("_", " ").to_upper()


func _build_default_archetypes() -> void:
	archetype_pool = [
		_make_archetype(
			&"ASTEROID_FRONTIER",
			"DEEP BELT",
			"Heavy mineral bodies crowd the local navigation volume.",
			&"ASTEROID_BELT",
			PackedStringArray(["HEAVY_ASTEROID_PRESENCE", "SALVAGE_PROSPECTS"]),
			PackedStringArray(["UDC"]),
			18,
			Color(0.95, 0.63, 0.22)
		),
		_make_archetype(
			&"FLEET_ANCHORAGE",
			"FLEET ANCHORAGE",
			"Capital-scale drive signatures dominate the survey return.",
			&"FLEET_ANCHORAGE",
			PackedStringArray(["MASSIVE_FLEET_PRESENCE", "CONTROLLED_SPACE"]),
			PackedStringArray(["UDC"]),
			27,
			Color(0.34, 0.86, 1.0)
		),
		_make_archetype(
			&"CONTESTED_FRONT",
			"CONTESTED FRONT",
			"Overlapping military signals indicate an active territorial engagement.",
			&"BATTLEFIELD",
			PackedStringArray(["OPEN_CONFLICT", "BATTLEFIELD_SALVAGE"]),
			PackedStringArray(["USC", "FSR"]),
			34,
			Color(1.0, 0.3, 0.24)
		),
		_make_archetype(
			&"PLANETOID_HOLD",
			"PLANETOID HOLD",
			"Grid-built structures are anchored to a planetoid-scale asteroid.",
			&"PLANETOID_SETTLEMENT",
			PackedStringArray(["FORTIFIED_ASTEROID", "STRUCTURE_SIGNATURES"]),
			PackedStringArray(["UNKNOWN"]),
			23,
			Color(0.72, 0.45, 1.0)
		),
	]


func _make_archetype(
	id: StringName,
	name: String,
	description: String,
	environment: StringName,
	tags: PackedStringArray,
	factions: PackedStringArray,
	danger: int,
	color: Color
) -> SectorArchetype:
	var archetype := SectorArchetype.new()
	archetype.archetype_id = id
	archetype.display_name = name
	archetype.description = description
	archetype.environment_type = environment
	archetype.intel_tags = tags
	archetype.likely_factions = factions
	archetype.base_danger = danger
	archetype.signal_color = color
	return archetype


func _build_default_modifiers() -> void:
	modifier_pool = [
		_make_modifier(
			&"ION_PRESSURE",
			"ION FRONT CLOSER THAN CHARTED",
			1,
			6,
			PackedStringArray(["ION_PRESSURE"])
		),
		_make_modifier(
			&"RICH_SALVAGE",
			"UNCLAIMED SALVAGE RETURNS",
			1,
			3,
			PackedStringArray(["RICH_SALVAGE"])
		),
		_make_modifier(
			&"FLEET_TRANSIT",
			"CAPITAL TRANSIT WINDOW ACTIVE",
			2,
			9,
			PackedStringArray(["FLEET_TRANSIT"])
		),
	]


func _make_modifier(
	id: StringName,
	intel: String,
	minimum_depth: int,
	danger: int,
	tags: PackedStringArray
) -> SectorModifier:
	var modifier := SectorModifier.new()
	modifier.modifier_id = id
	modifier.display_name = intel
	modifier.intel_line = intel
	modifier.minimum_depth = minimum_depth
	modifier.danger_adjustment = danger
	modifier.added_tags = tags
	return modifier
