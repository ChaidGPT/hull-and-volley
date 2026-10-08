class_name GridInventoryCatalog
extends RefCounted

const SHIP_ANALYZER := preload("res://scripts/ship_builder_analyzer.gd")
const ROOM_STAFFING_RULES := preload("res://scripts/room_staffing_rules.gd")


static func describe(layout: Resource, inventory_key: String) -> Dictionary:
	var recipe := recipe_for_key(layout, inventory_key)
	var room_type := "WEAPONS" if recipe != null else inventory_key
	var template := template_for_type(layout, room_type)
	var piece_name := String(recipe.get("display_name")) if recipe != null else palette_name(room_type)
	var piece_footprint := footprint(room_type, template, recipe)
	var power_delta := SHIP_ANALYZER.room_power_delta(room_type, 1, template)
	if recipe != null:
		var recipe_requirement := int(recipe.get("required_reactor_fields"))
		if recipe_requirement <= 0 and float(recipe.get("power_draw")) > 0.0:
			recipe_requirement = maxi(ceili(float(recipe.get("power_draw"))), 1)
		power_delta = Vector2(0.0, float(recipe_requirement))
	var minimum_crew := int(template.get("minimum_crew")) if template != null else 0
	var optimal_crew := int(template.get("optimal_crew")) if template != null else 0
	if recipe != null:
		minimum_crew = maxi(minimum_crew, int(recipe.get("minimum_crew")))
		optimal_crew = maxi(optimal_crew, int(recipe.get("optimal_crew")))
	if template != null:
		optimal_crew = ROOM_STAFFING_RULES.effective_requirements(template, minimum_crew, optimal_crew).y
	return {
		"inventory_key": inventory_key,
		"room_type": room_type,
		"template": template,
		"recipe": recipe,
		"display_name": piece_name,
		"color": category_color(room_type),
		"footprint": piece_footprint,
		"power_capacity": roundi(power_delta.x),
		"power_draw": roundi(power_delta.y),
		"crew_required": maxi(optimal_crew, minimum_crew),
	}


static func template_for_type(layout: Resource, room_type: String) -> Resource:
	if layout == null:
		return null
	for template: Resource in layout.get("room_types"):
		if String(template.get("type_name")) == room_type:
			return template
	return null


static func recipe_for_key(layout: Resource, inventory_key: String) -> Resource:
	if layout == null or not inventory_key.begins_with("WEAPON:"):
		return null
	var module_id := StringName(inventory_key.trim_prefix("WEAPON:"))
	for recipe: Resource in layout.get("module_recipes"):
		if recipe != null and recipe.get("module_id") == module_id:
			return recipe
	return null


static func category_color(room_type: String) -> Color:
	match room_type:
		"WEAPONS": return Color("#d94a42")
		"SHIELDS": return Color("#3e86d8")
		"REACTOR", "POWER": return Color("#d6a52f")
		"PROPULSION": return Color("#dc7135")
		"CREW", "CREW_QUARTERS": return Color("#7352a6")
		"MEDICAL": return Color("#42ad78")
		"HANGAR": return Color("#35a9a4")
		"COMMAND", "BRIDGE": return Color("#3d9daf")
		"SECURITY": return Color("#a84747")
		_: return Color("#627b79")


static func footprint(room_type: String, template: Resource, recipe: Resource) -> Vector2i:
	if room_type in ["PROPULSION", "SHIELDS"]:
		return Vector2i.ONE
	if room_type == "MEDICAL":
		return Vector2i(1, 2)
	if recipe != null:
		if String(recipe.get("module_id")) == "light_ballistic_mount":
			return Vector2i.ONE
		var footprint_resource: Resource = recipe.get("footprint")
		if footprint_resource != null:
			var source_cells: Array[Vector2i] = footprint_resource.call("transformed_cells", 0, false)
			if not source_cells.is_empty():
				var maximum := Vector2i.ZERO
				for source_cell: Vector2i in source_cells:
					maximum.x = maxi(maximum.x, source_cell.x)
					maximum.y = maxi(maximum.y, source_cell.y)
				return (maximum + Vector2i.ONE) * 2
	if template != null and "build_footprint_lattice" in template:
		return Vector2i(template.get("build_footprint_lattice"))
	return Vector2i(2, 2)


static func footprint_label(piece_footprint: Vector2i) -> String:
	if piece_footprint == Vector2i.ONE:
		return "QUARTER GRID"
	if piece_footprint == Vector2i(1, 2) or piece_footprint == Vector2i(2, 1):
		return "LONG HALF GRID"
	if piece_footprint == Vector2i(2, 2):
		return "FULL GRID"
	return "%dx%d LATTICE" % [piece_footprint.x, piece_footprint.y]


static func palette_name(room_type: String) -> String:
	match room_type:
		"COMMAND": return "Bridge"
		"PROPULSION": return "Thruster"
		"WEAPONS": return "Ship Weapon"
		"UNASSIGNED": return "Unassigned"
		"CREW_QUARTERS": return "Crew Quarters"
		"SECURITY": return "Security"
		"SHIELDS": return "Directional Shield Array"
		"POWER": return "Reactor"
		"MEDICAL": return "Medical Bay"
		"MESS_HALL": return "Mess Hall"
		"WORKSHOP": return "Engineering Bay"
		"CARGO": return "Cargo Hold"
		"SUPPLY_STORAGE": return "Supply Storage"
		"HANGAR": return "Hangar"
	return room_type.capitalize()
