class_name CrewRulesDefinition
extends Resource

@export_category("Vitals")
## Maximum health assigned to a newly created crew member.
@export_range(1.0, 10000.0, 1.0) var starting_maximum_health := 100.0
## Starting morale percentage for new crew.
@export_range(0.0, 100.0, 1.0) var starting_morale := 75.0
## Seconds an untreated incapacitated crew member survives before death.
@export_range(1.0, 600.0, 1.0) var incapacitation_survival_seconds := 30.0
## Health percentage at which an unassigned mobile crew member seeks Medical.
@export_range(1.0, 99.0, 1.0) var medical_seek_health_percentage := 60.0
## Health restored per second in a staffed Medical room per normal medical output unit.
@export_range(0.1, 100.0, 0.5) var medical_healing_per_second := 3.0

@export_category("Skills")
## Editor-authored skill definitions generated for every crew member.
@export var stats: Array[Resource] = []

@export_category("Equipment")
## Number of general equipment slots created for each crew member.
@export_range(0, 12, 1) var equipment_slot_count := 2
## Default editable vector portrait scene used by crew menus. Individual crew may override this later.
@export var default_portrait_scene: PackedScene

@export_category("Damage Control")
## Base room-health points restored per second by one average engineer.
@export_range(0.1, 100.0, 0.5) var room_repair_per_second := 4.0
## Base wall-durability points restored per second by one average engineer.
@export_range(0.1, 100.0, 0.5) var wall_repair_per_second := 5.0
## Engineering skill treated as normal 100% repair speed.
@export_range(0.1, 100.0, 0.5) var baseline_engineering_skill := 5.0
## Maximum crew automatically assigned to one damage-control order.
@export_range(1, 8, 1) var maximum_repairers_per_job := 1

@export_category("Room Operations")
## Skill value treated as a normal 100% station operator for weapons, shields, engines, hangars, and other systems.
@export_range(0.1, 100.0, 0.5) var baseline_station_skill := 5.0
## Maximum per-crew station output from high skill. Keeps one ace from replacing an entire staffed room.
@export_range(1.0, 3.0, 0.05) var maximum_station_skill_multiplier := 1.35
## Minimum per-crew station output from low skill when the crew member is otherwise able to operate.
@export_range(0.1, 1.0, 0.05) var minimum_station_skill_multiplier := 0.65

@export_category("Atmosphere Survival")
## Oxygen level below which exposed crew begin losing health.
@export_range(0.0, 1.0, 0.01) var oxygen_hazard_threshold := 0.35
## Health lost per second in complete vacuum. Partial oxygen scales this damage down.
@export_range(0.0, 100.0, 0.5) var vacuum_damage_per_second := 6.0
## Health percentage at which crew automatically abandon unsafe work and evacuate.
@export_range(1.0, 100.0, 1.0) var evacuation_health_percentage := 35.0
## Oxygen level at which an unprotected crew member immediately abandons work and seeks a safe room.
@export_range(0.0, 1.0, 0.01) var evacuation_trigger_oxygen := 0.22
## Minimum oxygen level considered safe for an emergency evacuation destination.
@export_range(0.0, 1.0, 0.01) var evacuation_safe_oxygen := 0.65
## Minimum room oxygen required for ordinary, unprotected damage-control work.
@export_range(0.0, 1.0, 0.01) var safe_repair_oxygen := 0.3
