class_name GridBuildRequirement
extends Resource

enum RequirementScope {
	OPEN_INSTALL,
	SHIP_CONTAINS,
	TOUCHING,
}

@export_category("Identity")
## Short designer-facing name shown when this build requirement is not satisfied.
@export var display_name := "BUILD REQUIREMENT"
## Longer explanation for tooltips and shipyard status text.
@export_multiline var description := ""

@export_category("Requirement")
## Open Install means this requirement always passes. Ship Contains checks the whole hull. Touching checks edge-adjacent sections.
@export var scope := RequirementScope.OPEN_INSTALL
## Grid types that can satisfy this rule, such as POWER, CREW_QUARTERS, WEAPONS, or SUPPLY_STORAGE.
@export var required_grid_types: PackedStringArray = []
## Minimum number of matching sections needed.
@export_range(1, 64, 1) var minimum_matches := 1
## Allows corner-touching cells to satisfy Touching requirements. Edge-touching remains the default.
@export var allow_diagonal_connections := false


func requirement_summary() -> String:
	match scope:
		RequirementScope.SHIP_CONTAINS:
			return "Requires shipwide %s" % _formatted_grid_types()
		RequirementScope.TOUCHING:
			return "Requires adjacent %s" % _formatted_grid_types()
		_:
			return "Open install"


func _formatted_grid_types() -> String:
	if required_grid_types.is_empty():
		return "compatible section"
	var labels: PackedStringArray = []
	for grid_type: String in required_grid_types:
		labels.append(grid_type.capitalize().replace("_", " "))
	return " / ".join(labels)
