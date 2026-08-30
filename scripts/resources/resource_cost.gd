class_name ResourceCost
extends Resource

## Commodity consumed by this cost entry.
@export var resource: Resource
## Number of units required. Fractional costs are supported for future fuels and energy materials.
@export_range(0.0, 1000000.0, 0.1, "or_greater") var amount := 0.0
## When enabled, construction returns this material if the module is dismantled successfully.
@export var recoverable_on_dismantle := true
## Fraction of the original amount returned during dismantling.
@export_range(0.0, 1.0, 0.05) var recovery_ratio := 0.5


func formatted() -> String:
	if resource == null:
		return "UNASSIGNED RESOURCE"
	var decimals := int(resource.get("decimal_places"))
	return "%.*f %s" % [decimals, amount, String(resource.get("display_name"))]

