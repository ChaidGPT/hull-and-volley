class_name HangarModuleDefinition
extends Resource

enum MaximumCraftSize {
	LIGHT,
	MEDIUM,
	HEAVY,
}

@export_category("Identity")
## Stable identifier used by carried-craft and save systems.
@export var hangar_id: StringName
## Player-facing name for this hangar configuration.
@export var display_name := "HANGAR MODULE"
## Description shown when selecting a hangar recipe.
@export_multiline var description := ""

@export_category("Craft Capacity")
## Total number of ordinary craft this module can house.
@export_range(1, 1000, 1) var craft_capacity := 4
## Number of craft that can launch or recover simultaneously.
@export_range(1, 64, 1) var simultaneous_launches := 1
## Largest craft frame this hangar can physically service.
@export var maximum_craft_size := MaximumCraftSize.LIGHT
## Craft roles permitted by this module, such as FIGHTER, MINING, SALVAGE, or UTILITY.
@export var allowed_craft_roles: PackedStringArray = []

@export_category("Hangar Services")
## Hull points repaired on housed craft per second. Zero means no internal repair capability.
@export_range(0.0, 100.0, 0.1) var repair_per_second := 0.0
## Enables automatic refueling when the carrier has the required resources.
@export var supports_refueling := true
## Enables automatic rearming when compatible ammunition is available.
@export var supports_rearming := false
## Multiplier applied to launch and recovery cycle time. Values below one are faster.
@export_range(0.1, 5.0, 0.05) var launch_cycle_multiplier := 1.0

@export_category("Autonomous Flight Wing")
## Behavior, movement, weapon, and editable visual used by craft launched from this hangar.
@export var default_craft_behavior: Resource
## Maximum distance from the carrier at which this hangar will detect and engage hostile ships.
@export_range(50.0, 5000.0, 10.0) var operating_radius := 520.0
## Base delay between individual craft launches. The launch-cycle multiplier is applied to this value.
@export_range(0.1, 30.0, 0.1) var deployment_interval := 1.8
