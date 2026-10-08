@tool
class_name ShipContactDefinition
extends Resource

@export_category("Identity")
## Encounter identity. Construction always comes from a saved Shipyard blueprint.
@export var ship_id: StringName
@export var display_name := "SHIP CONTACT"
@export_multiline var description := ""

@export_category("Shipyard Blueprint")
## Saved lattice-version-2 blueprint used by physics, combat, interiors, and visuals.
@export var ship_layout: Resource
@export var tactical_tint := Color(1.0, 0.68, 0.68, 1.0)
@export var faction_id: StringName = &"UNAFFILIATED"
@export var dialogue_profile: Resource

@export_category("Encounter Role")
## Default AI behavior index: 0 hold, 1 approach, 2 orbit, 3 retreat.
@export_range(0, 3, 1) var default_behavior := 0
@export var stationary_world_object := false
@export var participates_in_combat := true
@export_range(0.0, 100.0, 1.0) var docking_connector_extension := 0.0
@export var tactical_interest_room_types := PackedStringArray(["DOCKING", "WEAPONS", "HANGAR"])
@export var station_service_tags := PackedStringArray()

@export_category("Compatibility Fallbacks")
## Used only if a malformed blueprint cannot provide layout-derived durability.
@export_range(0.0, 10000.0, 5.0) var maximum_shield := 0.0
@export_range(1.0, 10000.0, 5.0) var maximum_hull := 100.0
