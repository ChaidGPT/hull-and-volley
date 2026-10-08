class_name ShipBuilderAnalyzer
extends RefCounted

const CREW_CAPACITY_PER_QUARTERS_CELL := 8
## The construction lattice is 2x2 cells per regular room. A basic reactor
## reaches two regular room widths from any cell it occupies.
const REACTOR_FIELD_RADIUS_LATTICE := 4.0
const ROOM_STAFFING_RULES := preload("res://scripts/room_staffing_rules.gd")


static func analyze(layout: Resource, preview_size: Vector2i = Vector2i.ZERO) -> Dictionary:
	var stats := {
		"build_size": preview_size,
		"occupied_cells": 0,
		"hull_size": Vector2i.ZERO,
		"crew_capacity": 0,
		"minimum_crew": 0,
		"optimal_crew": 0,
		"energy_capacity": 0.0,
		"energy_demand": 0.0,
		"reactor_field_count": 0,
		"powered_room_count": 0,
		"underpowered_room_count": 0,
		"missing_reactor_links": 0.0,
		"shield_capacity": 0.0,
		"shield_regen": 0.0,
		"thrust_rating": 0.0,
		"maneuver_rating": 0.0,
		"weapon_count": 0,
		"weapon_alpha": 0.0,
		"weapon_dps": 0.0,
		"weapon_range": 0.0,
		"weapon_families": {},
		"hangar_capacity": 0,
		"damage_control_channels": 0,
		"medical_channels": 0,
		"security_channels": 0,
		"supply_capacity": 0.0,
		"cargo_capacity": 0.0,
		"room_counts": {},
	}
	if layout == null:
		return stats
	if preview_size == Vector2i.ZERO:
		stats["build_size"] = Vector2i(int(layout.get("columns")), int(layout.get("rows")))
	var occupied: Dictionary = {}
	var hull_bounds: Rect2i = layout.call("get_occupied_bounds")
	stats["hull_size"] = hull_bounds.size
	for room: Resource in layout.get("rooms"):
		var room_type := String(room.get("type_name"))
		var cell_count := _room_cell_count(room)
		var piece_count := _installed_piece_count(room)
		_add_count(stats["room_counts"], room_type, cell_count)
		for cell: Vector2i in _room_cells(room):
			occupied[cell] = true
		var minimum_crew := int(room.get("minimum_crew"))
		var optimal_crew := int(room.get("optimal_crew"))
		var recipe: Resource = room.get("module_recipe")
		if recipe != null:
			minimum_crew = maxi(minimum_crew, int(recipe.get("minimum_crew")))
			optimal_crew = maxi(optimal_crew, int(recipe.get("optimal_crew")))
		if not room_type_uses_staffing(room_type):
			minimum_crew = 0
			optimal_crew = 0
		else:
			var staffing := ROOM_STAFFING_RULES.effective_requirements(room, minimum_crew, optimal_crew)
			minimum_crew = staffing.x
			optimal_crew = staffing.y
		stats["minimum_crew"] = int(stats["minimum_crew"]) + minimum_crew
		stats["optimal_crew"] = int(stats["optimal_crew"]) + maxi(optimal_crew, minimum_crew)
		match room_type:
			"CREW", "CREW_QUARTERS":
				stats["crew_capacity"] = int(stats["crew_capacity"]) + maxi(cell_count, piece_count) * CREW_CAPACITY_PER_QUARTERS_CELL
			"REACTOR", "POWER", "ENGINE":
				pass
			"SHIELDS":
				stats["shield_capacity"] = float(stats["shield_capacity"]) + cell_count * 55.0
				stats["shield_regen"] = float(stats["shield_regen"]) + cell_count * 0.75
			"PROPULSION":
				stats["thrust_rating"] = float(stats["thrust_rating"]) + cell_count * 12.0
				stats["maneuver_rating"] = float(stats["maneuver_rating"]) + _propulsion_facing_value(room, layout) * float(cell_count)
			"WEAPONS":
				_accumulate_weapon_stats(stats, room, cell_count)
			"HANGAR":
				stats["hangar_capacity"] = int(stats["hangar_capacity"]) + _hangar_capacity(room, cell_count)
			"MEDICAL", "SECURITY", "WORKSHOP":
				if room_type == "WORKSHOP":
					stats["damage_control_channels"] = int(stats["damage_control_channels"]) + cell_count
				elif room_type == "MEDICAL":
					stats["medical_channels"] = int(stats["medical_channels"]) + cell_count
				else:
					stats["security_channels"] = int(stats["security_channels"]) + cell_count
		var power_delta := room_power_delta(room_type, cell_count, room)
		stats["energy_capacity"] = float(stats["energy_capacity"]) + power_delta.x
		stats["energy_demand"] = float(stats["energy_demand"]) + power_delta.y
		var storage_role := String(room.get("storage_role"))
		var storage_capacity := float(room.get("storage_capacity_per_cell")) * float(cell_count)
		if storage_role == "SUPPLY":
			stats["supply_capacity"] = float(stats["supply_capacity"]) + storage_capacity
		elif storage_role == "CARGO":
			stats["cargo_capacity"] = float(stats["cargo_capacity"]) + storage_capacity
	stats["occupied_cells"] = occupied.size()
	var local_power := power_network_report(layout)
	stats["power_networks"] = local_power["networks"]
	stats["room_power_factors"] = local_power["room_factors"]
	stats["energy_uncovered_demand"] = local_power["uncovered_demand"]
	stats["reactor_field_count"] = local_power["reactor_field_count"]
	stats["powered_room_count"] = local_power["powered_room_count"]
	stats["underpowered_room_count"] = local_power["underpowered_room_count"]
	stats["missing_reactor_links"] = local_power["missing_field_links"]
	return stats


## Resolves reactor coverage. A reactor field has unlimited capacity inside its
## radius; consumers care only about how many active fields overlap them.
static func power_network_report(layout: Resource, generator_factors: Dictionary = {}) -> Dictionary:
	if layout == null:
		return {
			"networks": [], "room_factors": {}, "room_coverage": {},
			"room_requirements": {}, "uncovered_demand": 0.0,
			"missing_field_links": 0.0, "reactor_field_count": 0,
			"active_reactor_fields": 0.0, "powered_room_count": 0,
			"underpowered_room_count": 0,
		}
	return _power_network_report_for_rooms(layout, layout.get("rooms"), generator_factors)


## Blueprint placement check used by both the full drydock and live workbench.
static func evaluate_power_placement(
	layout: Resource,
	room_type: String,
	cell: Vector2i,
	footprint: Vector2i,
	candidate_template: Resource = null,
	ignored_room: Resource = null
) -> Dictionary:
	if layout == null:
		return {"valid": false, "message": "POWER LINK UNAVAILABLE"}
	var candidate := candidate_template.duplicate(true) if candidate_template != null else RoomLayoutData.new()
	candidate.set("room_id", &"__power_preview__")
	candidate.set("type_name", room_type)
	candidate.set("grid_rects", [Rect2i(cell, footprint)])
	candidate.set("installed_piece_count", 1)
	var preview_rooms: Array[Resource] = []
	for room: Resource in layout.get("rooms"):
		if room != ignored_room:
			preview_rooms.append(room)
	preview_rooms.append(candidate)
	var report := _power_network_report_for_rooms(layout, preview_rooms, {})
	var factor := float(report["room_factors"].get(&"__power_preview__", 1.0 if _is_generator_type(room_type) else 0.0))
	var required := float(report["room_requirements"].get(&"__power_preview__", room_power_requirement(room_type, candidate)))
	var coverage := float(report["room_coverage"].get(&"__power_preview__", 0.0))
	var covered := _is_generator_type(room_type) or required <= 0.0 or coverage > 0.001
	var valid := _is_generator_type(room_type) or required <= 0.0 or coverage + 0.001 >= required
	var missing := maxf(required - coverage, 0.0)
	return {
		"valid": valid,
		"covered": covered,
		"factor": factor,
		"coverage": coverage,
		"coverage_count": floori(coverage + 0.001),
		"required_fields": roundi(required),
		"required": required,
		"available": coverage,
		"missing": ceili(missing),
		"message": (
			"POWER FIELD ABSENT • PLACE WITHIN A REACTOR RADIUS"
			if not covered else "REACTOR COVERAGE LOW • REQUIRES %d FIELDS • %.1f ACTIVE • ADD OR MOVE A REACTOR" % [
				roundi(required), coverage,
			]
		),
	}


static func _power_network_report_for_rooms(layout: Resource, room_list: Array, generator_factors: Dictionary) -> Dictionary:
	var generators: Array[Dictionary] = []
	var consumers: Array[Dictionary] = []
	var room_factors: Dictionary = {}
	var room_coverage: Dictionary = {}
	var room_requirements: Dictionary = {}
	for room_value: Variant in room_list:
		var room := room_value as Resource
		if room == null:
			continue
		var room_id: StringName = room.get("room_id")
		var room_type := String(room.get("type_name"))
		var cells := _room_cells(room)
		if _is_generator_type(room_type):
			var strength := clampf(float(generator_factors.get(room_id, 1.0)), 0.0, 1.0)
			var rects: Array = room.get("grid_rects")
			var room_field_count := 0
			if rects.is_empty():
				generators.append({"room": room, "id": room_id, "cells": cells, "strength": strength})
				room_field_count = 1
			else:
				for rect_value: Variant in rects:
					var rect := rect_value as Rect2i
					var unit_cells: Array[Vector2i] = []
					for y: int in range(rect.position.y, rect.end.y):
						for x: int in range(rect.position.x, rect.end.x):
							unit_cells.append(Vector2i(x, y))
					generators.append({"room": room, "id": room_id, "cells": unit_cells, "strength": strength})
					room_field_count += 1
			room_factors[room_id] = 1.0
			room_coverage[room_id] = float(room_field_count)
			room_requirements[room_id] = 0
			continue
		var required := room_power_requirement(room_type, room)
		room_requirements[room_id] = required
		if required > 0:
			consumers.append({"room": room, "id": room_id, "cells": cells, "required": required})
		else:
			room_factors[room_id] = 1.0
			room_coverage[room_id] = 0.0

	# Group overlapping fields for presentation. Power is never pooled or spent;
	# every reactor field independently contributes one level of local coverage.
	var parents: Array[int] = []
	for index: int in range(generators.size()):
		parents.append(index)
	for first: int in range(generators.size()):
		for second: int in range(first + 1, generators.size()):
			if _cell_set_distance(generators[first]["cells"], generators[second]["cells"]) <= REACTOR_FIELD_RADIUS_LATTICE * 2.0:
				_union_power_parent(parents, first, second)
	var networks_by_root: Dictionary = {}
	for generator_index: int in range(generators.size()):
		var root := _power_parent(parents, generator_index)
		if not networks_by_root.has(root):
			networks_by_root[root] = {
				"generator_indices": [], "generator_ids": [], "room_ids": [],
				"field_count": 0, "active_field_strength": 0.0,
				"required_links": 0.0, "provided_links": 0.0,
				"missing_links": 0.0, "factor": 1.0,
			}
		var network: Dictionary = networks_by_root[root]
		network["generator_indices"].append(generator_index)
		var generator_id: StringName = generators[generator_index]["id"]
		if not network["generator_ids"].has(generator_id):
			network["generator_ids"].append(generator_id)
			network["room_ids"].append(generator_id)
		network["field_count"] = int(network["field_count"]) + 1
		network["active_field_strength"] = float(network["active_field_strength"]) + float(generators[generator_index]["strength"])

	var missing_field_links := 0.0
	var powered_room_count := 0
	var underpowered_room_count := 0
	for consumer: Dictionary in consumers:
		var matching_root := -1
		var coverage := 0.0
		for generator_index: int in range(generators.size()):
			if _cell_set_distance(consumer["cells"], generators[generator_index]["cells"]) <= REACTOR_FIELD_RADIUS_LATTICE:
				matching_root = _power_parent(parents, generator_index)
				coverage += float(generators[generator_index]["strength"])
		var required := float(consumer["required"])
		var factor := clampf(coverage / required, 0.0, 1.0)
		room_coverage[consumer["id"]] = coverage
		room_factors[consumer["id"]] = factor
		var missing := maxf(required - coverage, 0.0)
		missing_field_links += missing
		if missing <= 0.001:
			powered_room_count += 1
		else:
			underpowered_room_count += 1
		if matching_root < 0:
			continue
		var network: Dictionary = networks_by_root[matching_root]
		if not network["room_ids"].has(consumer["id"]):
			network["room_ids"].append(consumer["id"])
		network["required_links"] = float(network["required_links"]) + required
		network["provided_links"] = float(network["provided_links"]) + minf(coverage, required)
		network["missing_links"] = float(network["missing_links"]) + missing

	var networks: Array[Dictionary] = []
	for network_value: Variant in networks_by_root.values():
		var network := network_value as Dictionary
		var required_links := float(network["required_links"])
		network["factor"] = 1.0 if required_links <= 0.0 else clampf(float(network["provided_links"]) / required_links, 0.0, 1.0)
		# Compatibility aliases for older presentation code. These describe field
		# links, never a consumable output pool.
		network["capacity"] = float(network["active_field_strength"])
		network["demand"] = required_links
		networks.append(network)
	var active_reactor_fields := 0.0
	for generator: Dictionary in generators:
		active_reactor_fields += float(generator["strength"])
	return {
		"networks": networks,
		"room_factors": room_factors,
		"room_coverage": room_coverage,
		"room_requirements": room_requirements,
		"uncovered_demand": missing_field_links,
		"missing_field_links": missing_field_links,
		"reactor_field_count": generators.size(),
		"active_reactor_fields": active_reactor_fields,
		"powered_room_count": powered_room_count,
		"underpowered_room_count": underpowered_room_count,
	}


static func _is_generator_type(room_type: String) -> bool:
	return room_type in ["POWER", "REACTOR", "ENGINE"]


static func _cell_set_distance(first: Array, second: Array) -> float:
	var closest := INF
	for first_cell: Vector2i in first:
		for second_cell: Vector2i in second:
			closest = minf(closest, (Vector2(first_cell) - Vector2(second_cell)).length())
	return closest


static func _power_parent(parents: Array[int], index: int) -> int:
	var cursor := index
	while parents[cursor] != cursor:
		cursor = parents[cursor]
	var root := cursor
	cursor = index
	while parents[cursor] != cursor:
		var next := parents[cursor]
		parents[cursor] = root
		cursor = next
	return root


static func _union_power_parent(parents: Array[int], first: int, second: int) -> void:
	var first_root := _power_parent(parents, first)
	var second_root := _power_parent(parents, second)
	if first_root != second_root:
		parents[second_root] = first_root


static func room_type_uses_staffing(room_type: String) -> bool:
	return room_type not in [
		"UNASSIGNED",
		"CREW",
		"CREW_QUARTERS",
		"MESS_HALL",
		"SUPPLY_STORAGE",
		"CARGO",
	]


static func _accumulate_weapon_stats(stats: Dictionary, room: Resource, cell_count: int) -> void:
	var weapon: Resource = room.get("weapon_definition")
	var recipe: Resource = room.get("module_recipe")
	if recipe != null and recipe.get("payload_resource") != null:
		weapon = recipe.get("payload_resource")
	if weapon == null:
		stats["weapon_count"] = int(stats["weapon_count"]) + cell_count
		stats["weapon_alpha"] = float(stats["weapon_alpha"]) + cell_count * 8.0
		stats["weapon_dps"] = float(stats["weapon_dps"]) + cell_count * 1.0
		_add_count(stats["weapon_families"], "UNASSIGNED", cell_count)
		return
	var mount_cells := maxi(int(weapon.get("required_mount_cells")), 1)
	var mount_count := maxi(_installed_piece_count(room), maxi(floori(float(cell_count) / float(mount_cells)), 1))
	var damage := float(weapon.get("damage")) * float(mount_count)
	var reload := maxf(float(weapon.get("reload_seconds")), 0.1)
	stats["weapon_count"] = int(stats["weapon_count"]) + mount_count
	stats["weapon_alpha"] = float(stats["weapon_alpha"]) + damage
	stats["weapon_dps"] = float(stats["weapon_dps"]) + damage / reload
	stats["weapon_range"] = maxf(float(stats["weapon_range"]), float(weapon.get("maximum_range")))
	_add_count(stats["weapon_families"], String(weapon.get("weapon_family")), mount_count)


## Returns the number of overlapping reactor fields a room needs. Authored
## requirements win; legacy module power draw is interpreted as field count.
static func room_power_requirement(room_type: String, room: Resource = null) -> int:
	if _is_generator_type(room_type):
		return 0
	if room != null:
		var authored := int(room.get("required_reactor_fields"))
		if authored > 0:
			return authored
		var recipe: Resource = room.get("module_recipe")
		if recipe != null:
			var recipe_requirement := int(recipe.get("required_reactor_fields"))
			if recipe_requirement > 0:
				return recipe_requirement
			var legacy_draw := float(recipe.get("power_draw"))
			if legacy_draw > 0.0:
				return maxi(ceili(legacy_draw), 1)
	match room_type:
		"SHIELDS":
			return 1
		"PROPULSION", "HANGAR", "MEDICAL", "SECURITY", "WORKSHOP":
			return 1
		"WEAPONS":
			# A bare weapon grid is ordinary equipment. Advanced mounts opt into
			# multiple fields through their room/recipe requirement above.
			return 1
	return 0


## Legacy inventory/UI tuple. X is reactor field sources and Y is required
## overlapping fields; neither value represents consumable power capacity.
static func room_power_delta(room_type: String, cell_count: int, room: Resource = null) -> Vector2:
	if _is_generator_type(room_type):
		var source_count := _installed_piece_count(room) if room != null else maxi(cell_count, 1)
		return Vector2(float(source_count), 0.0)
	return Vector2(0.0, float(room_power_requirement(room_type, room)))


static func _hangar_capacity(room: Resource, fallback_cells: int) -> int:
	var recipe: Resource = room.get("module_recipe")
	if recipe != null and recipe.get("payload_resource") != null:
		var hangar: Resource = recipe.get("payload_resource")
		if hangar != null and hangar.has_method("get"):
			return int(hangar.get("craft_capacity"))
	return fallback_cells * 4


static func _propulsion_facing_value(room: Resource, layout: Resource) -> float:
	var facing := int(room.get("module_facing_quarters"))
	if facing >= 0:
		return 1.0
	var bounds: Rect2i = layout.call("get_occupied_bounds")
	var center := Vector2(bounds.position) + Vector2(bounds.size) * 0.5
	var room_center := Vector2.ZERO
	var cells := _room_cells(room)
	for cell: Vector2i in cells:
		room_center += Vector2(cell) + Vector2(0.5, 0.5)
	room_center /= maxf(float(cells.size()), 1.0)
	return clampf(room_center.distance_to(center) / maxf(Vector2(bounds.size).length() * 0.5, 0.01), 0.25, 1.0)


static func _room_cell_count(room: Resource) -> int:
	var count := 0
	for rect: Rect2i in room.get("grid_rects"):
		count += rect.size.x * rect.size.y
	# Four lattice cells equal one original full-grid capacity unit. A smaller
	# installed module still counts as one functioning system.
	return maxi(ceili(float(count) / 4.0), 1)


static func _installed_piece_count(room: Resource) -> int:
	if room == null:
		return 1
	return maxi(int(room.get("installed_piece_count")), 1)


static func _room_cells(room: Resource) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for rect: Rect2i in room.get("grid_rects"):
		for y: int in range(rect.position.y, rect.end.y):
			for x: int in range(rect.position.x, rect.end.x):
				cells.append(Vector2i(x, y))
	return cells


static func _add_count(target: Dictionary, key: String, amount: int) -> void:
	target[key] = int(target.get(key, 0)) + amount
