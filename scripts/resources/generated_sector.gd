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
@export_range(600.0, 5000.0, 50.0) var safe_radius := 2100.0
@export var hazard_enabled := true
@export var signal_color := Color(0.25, 0.95, 0.9, 1.0)


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
	}

