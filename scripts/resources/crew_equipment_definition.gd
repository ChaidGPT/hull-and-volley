class_name CrewEquipmentDefinition
extends Resource

## Player-facing equipment name.
@export var display_name := "CREW EQUIPMENT"
## Longer equipment description shown in crew menus.
@export_multiline var description := ""
## Optional inventory/menu icon. Empty is safe.
@export var icon: Texture2D
## Additive skill modifiers keyed by CrewStatDefinition stat_id.
@export var stat_modifiers: Dictionary = {}
## Optional scene used for equipment visible on the crew member. Empty is safe.
@export var equipped_visual_scene: PackedScene

@export_category("Environmental Protection")
## Fraction of vacuum health damage blocked while this item is equipped. Values from multiple items stack up to 100%.
@export_range(0.0, 1.0, 0.05) var vacuum_damage_reduction := 0.0
## Allows this item to qualify its wearer for damage-control work in rooms below the safe repair pressure.
@export var permits_vacuum_work := false
