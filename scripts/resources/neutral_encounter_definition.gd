@tool
class_name NeutralEncounterDefinition
extends Resource

@export_category("Encounter Pool")
@export var encounter_id: StringName
@export var display_name := "CIVILIAN ACTIVITY"
@export_multiline var description := ""
@export_range(0.0, 100.0, 0.25) var selection_weight := 1.0
@export_range(0, 12, 1) var minimum_contacts := 1
@export_range(1, 24, 1) var maximum_contacts := 1
@export var sector_tags := PackedStringArray()
## Factions capable of sponsoring or populating this encounter.
@export var faction_ids := PackedStringArray()

@export_category("World Features")
@export var creates_station := false
@export var creates_asteroid_field := false
@export var creates_shipping_lane := false
@export var creates_moving_formation := false
