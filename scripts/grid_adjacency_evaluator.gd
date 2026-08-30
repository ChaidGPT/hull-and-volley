class_name GridAdjacencyEvaluator
extends RefCounted

const GRID_GEOMETRY := preload("res://scripts/grid_geometry.gd")
const CONNECTION_COUNT_SHARED_EDGES := 0
const EFFECT_STACK_PER_SHARED_EDGE := 2
const BUILD_REQUIREMENT_OPEN_INSTALL := 0
const BUILD_REQUIREMENT_SHIP_CONTAINS := 1
const BUILD_REQUIREMENT_TOUCHING := 2


static func evaluate_grid_type_placement(layout: Resource, room_type: String, cell: Vector2i, placement_offset: Vector2 = Vector2.ZERO, footprint: Vector2i = Vector2i.ONE) -> Dictionary:
	var template := _room_type_template(layout, room_type)
	if template == null:
		return {
			"valid": false,
			"unmet_requirements": PackedStringArray(["Unknown grid type"]),
			"details": PackedStringArray(["No room template exists for %s." % room_type]),
		}
	var unmet_requirements := PackedStringArray()
	var details := PackedStringArray()
	var requirements: Array = template.get("build_requirements")
	for requirement_value: Variant in requirements:
		var requirement := requirement_value as Resource
		if requirement == null:
			continue
		var result := evaluate_grid_build_requirement(layout, cell, requirement, placement_offset, footprint)
		if not bool(result["satisfied"]):
			var requirement_name := String(requirement.get("display_name")).strip_edges()
			unmet_requirements.append(requirement_name if not requirement_name.is_empty() else requirement.call("requirement_summary"))
			details.append(String(result["detail"]))
	return {
		"valid": unmet_requirements.is_empty(),
		"unmet_requirements": unmet_requirements,
		"details": details,
	}


static func evaluate_grid_build_requirement(layout: Resource, cell: Vector2i, requirement: Resource, placement_offset: Vector2 = Vector2.ZERO, footprint: Vector2i = Vector2i.ONE) -> Dictionary:
	match int(requirement.get("scope")):
		BUILD_REQUIREMENT_SHIP_CONTAINS:
			return _evaluate_ship_contains_requirement(layout, requirement)
		BUILD_REQUIREMENT_TOUCHING:
			return _evaluate_touching_requirement(layout, cell, requirement, placement_offset, footprint)
		_:
			return {"satisfied": true, "count": 0, "detail": "Open install."}


static func _evaluate_ship_contains_requirement(layout: Resource, requirement: Resource) -> Dictionary:
	var required_types: PackedStringArray = requirement.get("required_grid_types")
	var count := 0
	var seen_sections: Dictionary = {}
	for room: Resource in layout.get("rooms"):
		if not _room_type_matches(String(room.get("type_name")), required_types):
			continue
		var key := room.get_instance_id()
		if seen_sections.has(key):
			continue
		seen_sections[key] = true
		count += 1
	var minimum := int(requirement.get("minimum_matches"))
	return {
		"satisfied": count >= minimum,
		"count": count,
		"detail": "Shipwide dependency: %d/%d matching section%s present." % [count, minimum, "" if minimum == 1 else "s"],
	}


static func _evaluate_touching_requirement(layout: Resource, cell: Vector2i, requirement: Resource, placement_offset: Vector2, footprint: Vector2i = Vector2i.ONE) -> Dictionary:
	var required_types: PackedStringArray = requirement.get("required_grid_types")
	var count := 0
	var seen_sections: Dictionary = {}
	var owners := _cell_owner_map(layout)
	var candidate_rect := Rect2(Vector2(cell) + placement_offset, Vector2(footprint))
	for neighbor_cell_value: Variant in owners.keys():
		var neighbor_cell := neighbor_cell_value as Vector2i
		var neighbor_rect := GRID_GEOMETRY.logical_cell_rect(neighbor_cell, GRID_GEOMETRY.cell_offset(layout, neighbor_cell))
		var contact_strength := _rect_contact_strength(candidate_rect, neighbor_rect)
		var diagonal_touch := bool(requirement.get("allow_diagonal_connections")) and _rects_touch_at_corner(candidate_rect, neighbor_rect)
		if contact_strength <= 0.0 and not diagonal_touch:
			continue
		var neighbor := owners.get(neighbor_cell) as Resource
		if neighbor == null:
			continue
		if not _room_type_matches(String(neighbor.get("type_name")), required_types):
			continue
		var key := neighbor.get_instance_id()
		if seen_sections.has(key):
			continue
		seen_sections[key] = true
		count += 1
	var minimum := int(requirement.get("minimum_matches"))
	return {
		"satisfied": count >= minimum,
		"count": count,
		"detail": "Local dependency: %d/%d adjacent matching section%s." % [count, minimum, "" if minimum == 1 else "s"],
	}


static func _rect_contact_strength(first: Rect2, second: Rect2) -> float:
	if is_equal_approx(first.end.x, second.position.x) or is_equal_approx(second.end.x, first.position.x):
		return maxf(0.0, minf(first.end.y, second.end.y) - maxf(first.position.y, second.position.y))
	if is_equal_approx(first.end.y, second.position.y) or is_equal_approx(second.end.y, first.position.y):
		return maxf(0.0, minf(first.end.x, second.end.x) - maxf(first.position.x, second.position.x))
	return 0.0


static func _rects_touch_at_corner(first: Rect2, second: Rect2) -> bool:
	var horizontal_touch := is_equal_approx(first.end.x, second.position.x) or is_equal_approx(second.end.x, first.position.x)
	var vertical_touch := is_equal_approx(first.end.y, second.position.y) or is_equal_approx(second.end.y, first.position.y)
	return horizontal_touch and vertical_touch


static func evaluate_recipe(layout: Resource, section: Resource, recipe: Resource) -> Dictionary:
	var unmet_requirements: Array[String] = []
	for rule: Resource in recipe.get("connection_requirements"):
		var result: Dictionary = evaluate_connection_rule(layout, section, rule)
		if not result["satisfied"]:
			unmet_requirements.append(String(rule.get("display_name")))
	return {
		"valid": unmet_requirements.is_empty(),
		"unmet_requirements": unmet_requirements,
	}


static func evaluate_connection_rule(layout: Resource, section: Resource, rule: Resource) -> Dictionary:
	var connections: Array[Dictionary] = get_connections(layout, section, bool(rule.get("allow_diagonal_connections")))
	var qualifying_sections: int = 0
	var qualifying_edges: float = 0.0
	for connection: Dictionary in connections:
		var neighbor: Resource = connection["section"]
		if not _neighbor_matches_rule(neighbor, rule):
			continue
		qualifying_sections += 1
		qualifying_edges += float(connection["contact_strength"])
		if bool(rule.get("allow_diagonal_connections")) and is_zero_approx(float(connection["contact_strength"])):
			qualifying_edges += float(connection["diagonal_touches"])
	var count: float = qualifying_edges if int(rule.get("count_mode")) == CONNECTION_COUNT_SHARED_EDGES else float(qualifying_sections)
	var minimum: int = int(rule.get("minimum_connections"))
	var maximum: int = int(rule.get("maximum_connections"))
	var minimum_strength: float = float(rule.get("minimum_contact_strength"))
	return {
		"satisfied": count >= minimum and qualifying_edges >= minimum_strength and (maximum < 0 or count <= maximum),
		"count": count,
		"contact_strength": qualifying_edges,
		"minimum": minimum,
		"maximum": maximum,
	}


static func collect_layout_effects(layout: Resource) -> Array[Dictionary]:
	var resolved: Array[Dictionary] = []
	for source: Resource in layout.get("rooms"):
		var effects: Array[Resource] = []
		effects.append_array(source.get("adjacency_effects"))
		var installed_recipe: Resource = source.get("module_recipe")
		if installed_recipe != null:
			effects.append_array(installed_recipe.get("adjacency_effects"))
		for effect: Resource in effects:
			for connection: Dictionary in get_connections(layout, source, bool(effect.get("allow_diagonal_connections"))):
				var target: Resource = connection["section"]
				if not _neighbor_matches_effect(target, effect):
					continue
				var stacks: float = _effect_stack_count(effect, connection)
				if stacks > 0:
					resolved.append({"source": source, "target": target, "effect": effect, "stacks": stacks, "contact_strength": connection["contact_strength"]})
	return resolved


static func get_connections(layout: Resource, source: Resource, include_diagonals: bool = false) -> Array[Dictionary]:
	var cell_owners: Dictionary = _cell_owner_map(layout)
	var source_cells: Dictionary = _section_cells(source)
	var by_neighbor: Dictionary = {}
	for cell_value: Variant in source_cells.keys():
		var cell: Vector2i = cell_value
		for touching: Dictionary in GRID_GEOMETRY.touching_neighbors(layout, cell, include_diagonals):
			_accumulate_connection(
				by_neighbor,
				source,
				cell_owners.get(touching["cell"]),
				float(touching["strength"]),
				bool(touching["diagonal"])
			)
	var connections: Array[Dictionary] = []
	for entry: Dictionary in by_neighbor.values():
		connections.append(entry)
	return connections


static func _accumulate_connection(by_neighbor: Dictionary, source: Resource, neighbor_value: Variant, strength: float, diagonal: bool) -> void:
	var neighbor: Resource = neighbor_value as Resource
	if neighbor == null or neighbor == source:
		return
	var key: int = neighbor.get_instance_id()
	if not by_neighbor.has(key):
		by_neighbor[key] = {"section": neighbor, "shared_edges": 0, "contact_strength": 0.0, "diagonal_touches": 0}
	if not diagonal:
		by_neighbor[key]["shared_edges"] = int(by_neighbor[key]["shared_edges"]) + 1
		by_neighbor[key]["contact_strength"] = float(by_neighbor[key]["contact_strength"]) + strength
	else:
		by_neighbor[key]["diagonal_touches"] = int(by_neighbor[key]["diagonal_touches"]) + 1


static func _neighbor_matches_rule(neighbor: Resource, rule: Resource) -> bool:
	var grid_types: PackedStringArray = rule.get("neighbor_grid_types")
	if not grid_types.is_empty() and not grid_types.has(String(neighbor.get("type_name"))):
		return false
	var recipe: Resource = neighbor.get("module_recipe")
	if bool(rule.get("require_installed_module")) and recipe == null:
		return false
	var required_tags: PackedStringArray = rule.get("neighbor_module_tags")
	if required_tags.is_empty():
		return true
	if recipe == null:
		return false
	var tags: PackedStringArray = recipe.get("tags")
	if bool(rule.get("require_all_module_tags")):
		for tag: String in required_tags:
			if not tags.has(tag):
				return false
		return true
	for tag: String in required_tags:
		if tags.has(tag):
			return true
	return false


static func _neighbor_matches_effect(neighbor: Resource, effect: Resource) -> bool:
	var grid_types: PackedStringArray = effect.get("affected_grid_types")
	if not grid_types.is_empty() and not grid_types.has(String(neighbor.get("type_name"))):
		return false
	var required_tags: PackedStringArray = effect.get("affected_module_tags")
	if required_tags.is_empty():
		return true
	var recipe: Resource = neighbor.get("module_recipe")
	if recipe == null:
		return false
	var tags: PackedStringArray = recipe.get("tags")
	for tag: String in required_tags:
		if tags.has(tag):
			return true
	return false


static func _effect_stack_count(effect: Resource, connection: Dictionary) -> float:
	var stacks: float = 1.0
	match int(effect.get("stack_mode")):
		EFFECT_STACK_PER_SHARED_EDGE:
			stacks = float(connection["contact_strength"])
			if is_zero_approx(stacks) and bool(effect.get("allow_diagonal_connections")):
				stacks = float(connection["diagonal_touches"])
		1:
			stacks = 1
	if bool(effect.get("scale_by_contact_strength")) and int(effect.get("stack_mode")) != EFFECT_STACK_PER_SHARED_EDGE:
		stacks *= minf(float(connection["contact_strength"]), 1.0)
	var maximum: int = int(effect.get("maximum_stacks"))
	return minf(stacks, float(maximum)) if maximum >= 0 else stacks


static func _cell_owner_map(layout: Resource) -> Dictionary:
	var owners: Dictionary = {}
	for section: Resource in layout.get("rooms"):
		for cell_value: Variant in _section_cells(section).keys():
			owners[cell_value] = section
	return owners


static func _room_type_template(layout: Resource, room_type: String) -> Resource:
	for template: Resource in layout.get("room_types"):
		if String(template.get("type_name")) == room_type:
			return template
	return null


static func _room_type_matches(room_type: String, accepted_types: PackedStringArray) -> bool:
	return accepted_types.is_empty() or accepted_types.has(room_type)


static func _section_cells(section: Resource) -> Dictionary:
	var cells: Dictionary = {}
	for rect: Rect2i in section.get("grid_rects"):
		for y: int in range(rect.position.y, rect.end.y):
			for x: int in range(rect.position.x, rect.end.x):
				cells[Vector2i(x, y)] = true
	return cells
