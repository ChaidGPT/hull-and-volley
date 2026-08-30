class_name CrewStatDefinition
extends Resource

## Stable identifier used by gameplay systems and equipment modifiers.
@export var stat_id: StringName = &"operations"
## Player-facing name displayed in crew menus.
@export var display_name := "OPERATIONS"
## Explanation shown when inspecting this stat.
@export_multiline var description := "General ability to operate ship systems."
## Lowest possible natural value.
@export_range(0.0, 1000.0, 0.5) var minimum_value := 0.0
## Highest possible natural value before equipment modifiers.
@export_range(1.0, 1000.0, 0.5) var maximum_value := 10.0
## Starting value around which individual crew variation is generated.
@export_range(0.0, 1000.0, 0.5) var base_value := 5.0
## Maximum random variation applied above or below the base value.
@export_range(0.0, 100.0, 0.5) var starting_variation := 1.5
## Accent color used when displaying this stat.
@export var display_color := Color(0.48, 0.9, 0.82, 1.0)
