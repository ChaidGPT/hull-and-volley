@tool
class_name FactionDefinition
extends Resource

@export_category("Identity")
@export var faction_id: StringName
@export var display_name := "UNAFFILIATED"
@export var short_name := "NONE"
@export_multiline var description := ""
@export var signal_color := Color(0.55, 0.78, 0.76, 1.0)
@export var insignia_glyph := "◇"

@export_category("Run Standing")
@export_range(-100.0, 100.0, 1.0) var starting_reputation := 0.0
## Relationship to other factions from -1 (enemy) to +1 (ally). Reputation
## incidents spill across this matrix without recursively chaining.
@export var diplomatic_relations: Dictionary = {}

@export_category("Shipbuilding Identity")
@export_multiline var ship_design_language := ""
@export var favored_grid_types := PackedStringArray()
@export var encounter_tags := PackedStringArray()
