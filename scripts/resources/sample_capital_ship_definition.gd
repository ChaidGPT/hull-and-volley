@tool
class_name SampleCapitalShipDefinition
extends Resource

@export_category("Identity")
## Stable identifier used by dev spawning and future encounter tables.
@export var ship_id: StringName
## Name shown in development tools and future contact readouts.
@export var display_name := "SAMPLE CAPITAL SHIP"
## Short description of this hull's intended role.
@export_multiline var description := ""

@export_category("Construction")
## Grid-built layout shared by physics, Ship, Settlement, and Crew representations.
@export var ship_layout: Resource
## Optional authoring/physics scene override. Empty uses the standard capital-ship body.
@export var physics_scene: PackedScene
## Optional ship-view visual scene override. Useful for large stations that need authored exterior art instead of full grid rendering.
@export var tactical_exterior_scene: PackedScene
## Tactical tint applied to this sample ship.
@export var tactical_tint := Color(1.0, 0.68, 0.68, 1.0)
## Political affiliation used by run reputation, contact readouts, and encounter tables.
@export var faction_id: StringName = &"UNAFFILIATED"
## Context-sensitive communications identity used when this contact is hailed.
@export var dialogue_profile: Resource

@export_category("Combat Defaults")
## Starting shield capacity for this sample hull.
@export_range(0.0, 10000.0, 5.0) var maximum_shield := 100.0
## Starting abstract hull value used by the current combat prototype.
@export_range(1.0, 10000.0, 5.0) var maximum_hull := 100.0
## Default AI behavior index: 0 hold, 1 approach, 2 orbit, 3 retreat.
@export_range(0, 3, 1) var default_behavior := 0
## If true, this body is treated as an anchored world structure instead of a mobile capital ship.
@export var stationary_world_object := false
## If false, the object is visible/collidable but ignored by automatic combat targeting and carrier launches.
@export var participates_in_combat := true
## Extra distance beyond the grid-built hull face where a custom exterior's docking clamp sits.
@export_range(0.0, 100.0, 1.0) var docking_connector_extension := 0.0

@export_category("Tactical Exterior")
## Room types drawn on the ship-level exterior proxy when this object uses low-detail rendering.
## Useful for stations: keep docking arms, weapons, and hangars visible without drawing every internal service room.
@export var tactical_interest_room_types := PackedStringArray(["DOCKING", "WEAPONS", "HANGAR"])
## Non-combat services offered by this object. These are data tags for future docking/station menus, not tactical geometry.
@export var station_service_tags := PackedStringArray()
