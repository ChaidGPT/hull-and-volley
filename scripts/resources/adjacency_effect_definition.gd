class_name AdjacencyEffectDefinition
extends Resource

enum EffectKind {
	SYNERGY,
	INTERFERENCE,
	NEUTRAL,
}

enum StackMode {
	ONCE,
	PER_UNIQUE_SECTION,
	PER_SHARED_EDGE,
}

@export_category("Identity")
## Stable identifier used by simulation and UI code.
@export var effect_id: StringName
## Player-facing name of this adjacency effect.
@export var display_name := "ADJACENCY EFFECT"
## Explanation of why the neighboring sections affect one another.
@export_multiline var description := ""
## Classifies the effect for future UI coloring and filtering; it does not alter the math by itself.
@export var effect_kind := EffectKind.SYNERGY

@export_category("Affected Neighbors")
## Grid types that can receive this effect. An empty list permits every neighboring grid type.
@export var affected_grid_types: PackedStringArray = []
## Installed-module tags that can receive this effect. An empty list does not filter by tags.
@export var affected_module_tags: PackedStringArray = []
## Allows corner-touching sections to receive the effect. Shared edges are used by default.
@export var allow_diagonal_connections := false

@export_category("Stacking")
## Determines whether this effect applies once, per neighboring section, or once per shared cell edge.
@export var stack_mode := StackMode.ONCE
## Scales the effect by shared-edge coverage. A half-edge staggered contact contributes 50% of one stack.
@export var scale_by_contact_strength := true
## Maximum number of stacks contributed by this effect. Use -1 for no limit.
@export_range(-1, 64, 1) var maximum_stacks := 1

@export_category("Payload")
## Editor-authored stat changes applied per stack when the simulation begins consuming adjacency effects.
@export var stat_modifiers: Array[Resource] = []
## Optional specialized payload for effects that cannot be represented by ordinary stat modifiers.
@export var payload_resource: Resource
