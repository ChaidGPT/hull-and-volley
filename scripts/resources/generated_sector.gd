class_name GeneratedSector
extends Resource

@export var sector_id: StringName = &"UNRESOLVED"
@export var display_name := "UNRESOLVED VECTOR"
@export var archetype_id: StringName = &"UNKNOWN"
@export var environment_type: StringName = &"OPEN_SPACE"
@export var run_depth := 0
@export var generation_seed := 1
@export_range(0, 100, 1) var danger_rating := 0
@export var intel_summary := ""
@export var intel_lines := PackedStringArray()
@export var sector_tags := PackedStringArray()
@export var faction_signals := PackedStringArray()
@export var modifier_ids := PackedStringArray()
@export_range(600.0, 12000.0, 50.0) var safe_radius := 2100.0
@export var hazard_enabled := true
@export var signal_color := Color(0.25, 0.95, 0.9, 1.0)

## Deterministic spatial plan generated once when this route is created.
@export_range(2000.0, 12000.0, 100.0) var sector_radius := 8000.0
@export var entry_position := Vector2.ZERO
@export var entry_rotation := 0.0
@export_range(300.0, 3000.0, 50.0) var arrival_clearance := 1050.0
@export var environment_regions: Array[Dictionary] = []
@export var landmarks: Array[Dictionary] = []
@export var transit_routes: Array[PackedVector2Array] = []


func get_route_report() -> Dictionary:
	return {
		"id": sector_id,
		"name": display_name,
		"depth": run_depth,
		"seed": generation_seed,
		"danger": danger_rating,
		"summary": intel_summary,
		"intel": intel_lines,
		"tags": sector_tags,
		"factions": faction_signals,
		"modifiers": modifier_ids,
		"environment": environment_type,
		"sector_radius": sector_radius,
	}
