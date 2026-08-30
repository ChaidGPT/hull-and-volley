class_name DestructionDebrisDefinition
extends Resource

@export_category("Hull Fragmentation")
## Chance that each exposed hull-edge segment becomes a physical debris piece.
@export_range(0.1, 1.0, 0.05) var outline_fragment_coverage := 0.9
## Minimum outward breakup speed added to each hull fragment.
@export_range(0.0, 500.0, 5.0) var minimum_break_speed := 18.0
## Maximum outward breakup speed added to each hull fragment.
@export_range(0.0, 800.0, 5.0) var maximum_break_speed := 65.0
## How long physical hull fragments remain visible before fading away.
@export_range(0.2, 20.0, 0.1) var lifetime := 4.0
## Shortens or lengthens the sampled hull-edge lines without changing the original ship geometry.
@export_range(0.25, 1.5, 0.05) var fragment_length_scale := 0.82

@export_category("Fragment Physics")
## Physical collision radius used by tumbling hull fragments.
@export_range(0.25, 10.0, 0.25) var collision_radius := 1.0
## Physical mass assigned to each fragment.
@export_range(0.01, 100.0, 0.05) var fragment_mass := 0.35
## Energy retained when a fragment bounces off another capital hull.
@export_range(0.0, 1.0, 0.05) var bounce := 0.35
## Surface friction applied during fragment collisions.
@export_range(0.0, 1.0, 0.05) var friction := 0.2
## Slow velocity loss applied after breakup. Keep low for the classic drifting-vector effect.
@export_range(0.0, 10.0, 0.05) var linear_damping := 0.28
## Minimum random tumble rate in degrees per second.
@export_range(0.0, 1080.0, 5.0) var minimum_tumble_degrees := 45.0
## Maximum random tumble rate in degrees per second.
@export_range(0.0, 1080.0, 5.0) var maximum_tumble_degrees := 220.0

@export_category("Vector Appearance")
## Main steel-colored line used for broken hull edges.
@export var hull_color := Color(0.62, 0.72, 0.74, 1.0)
## Chance that an individual fragment appears superheated.
@export_range(0.0, 1.0, 0.05) var hot_fragment_chance := 0.22
## Color assigned to superheated fragments.
@export var hot_color := Color(1.0, 0.48, 0.12, 1.0)
## Width of the vector hull fragments in tactical pixels.
@export_range(0.25, 6.0, 0.25) var line_width := 1.5
