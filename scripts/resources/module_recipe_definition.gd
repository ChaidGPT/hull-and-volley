class_name ModuleRecipeDefinition
extends Resource

enum ModuleFamily {
	WEAPON,
	THRUSTER,
	POWER,
	SHIELD,
	CREW,
	MEDICAL,
	SECURITY,
	CARGO,
	HANGAR,
	SENSOR,
	UTILITY,
}

@export_category("Identity")
@export var module_id: StringName
@export var display_name := "MODULE"
@export_multiline var description := ""
@export var family := ModuleFamily.UTILITY
@export var tags: PackedStringArray = []

@export_category("Construction")
@export var footprint: Resource
@export var compatible_grid_types: PackedStringArray = ["UNASSIGNED"]
## Legacy single-currency prototype cost. Prefer Construction Costs for new recipes.
@export_range(0.0, 100000.0, 1.0) var build_cost := 0.0
## Credits, metals, electronics, fuel, or other commodities consumed during construction.
@export var construction_costs: Array[Resource] = []
@export_range(0.0, 10000.0, 0.5) var build_time := 0.0
@export var can_be_dismantled := true

@export_category("Module Adjacency")
## Connections that must be present before this module can be installed. They never prevent placement of the underlying grid type.
@export var connection_requirements: Array[Resource] = []
## Ongoing synergies or interference this installed module applies to touching sections.
@export var adjacency_effects: Array[Resource] = []

@export_category("Operation")
@export_range(0.0, 100.0, 1.0) var power_draw := 0.0
@export_range(0, 1000, 1) var minimum_crew := 0
@export_range(0, 1000, 1) var optimal_crew := 0
@export_range(1.0, 100000.0, 1.0) var maximum_health := 100.0
@export var can_be_disabled := true

@export_category("Effects")
@export var stat_modifiers: Array[Resource] = []
@export var payload_resource: Resource

@export_category("Visuals and Animation")
## Per-view scenes, animation names, effects, sounds, sockets, and placement settings for this module.
@export var visuals: Resource


func formatted_construction_costs() -> PackedStringArray:
	var lines: PackedStringArray = []
	for cost: Resource in construction_costs:
		if cost != null:
			lines.append(cost.call("formatted"))
	return lines


func footprint_cell_count() -> int:
	return footprint.call("cell_count") if footprint != null else 0


func supports_grid_type(grid_type: String) -> bool:
	return compatible_grid_types.has(grid_type)
