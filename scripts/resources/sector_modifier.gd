class_name SectorModifier
extends Resource

@export var modifier_id: StringName = &"NONE"
@export var display_name := "NO ANOMALY"
@export_multiline var intel_line := ""
@export var required_tags := PackedStringArray()
@export_range(0, 20, 1) var minimum_depth := 0
@export_range(0.0, 20.0, 0.1) var selection_weight := 1.0
@export_range(-20, 100, 1) var danger_adjustment := 0
@export var added_tags := PackedStringArray()


func supports_archetype(archetype: SectorArchetype, depth: int) -> bool:
	if depth < minimum_depth or selection_weight <= 0.0:
		return false
	for tag: String in required_tags:
		if not archetype.intel_tags.has(tag):
			return false
	return true

