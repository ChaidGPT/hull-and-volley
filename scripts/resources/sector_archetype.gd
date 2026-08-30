class_name SectorArchetype
extends Resource

@export var archetype_id: StringName = &"UNKNOWN"
@export var display_name := "UNCHARTED SECTOR"
@export_multiline var description := "Long-range survey data is incomplete."
@export var environment_type: StringName = &"OPEN_SPACE"
@export var intel_tags := PackedStringArray()
@export var likely_factions := PackedStringArray()
@export_range(0, 100, 1) var base_danger := 10
@export_range(0, 20, 1) var minimum_depth := 0
@export_range(0, 99, 1) var maximum_depth := 99
@export_range(0.0, 20.0, 0.1) var selection_weight := 1.0
@export_range(600.0, 5000.0, 50.0) var safe_radius := 2100.0
@export var hazard_enabled := true
@export var signal_color := Color(0.25, 0.95, 0.9, 1.0)


func is_available_at_depth(depth: int) -> bool:
	return depth >= minimum_depth and depth <= maximum_depth and selection_weight > 0.0

