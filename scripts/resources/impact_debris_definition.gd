class_name ImpactDebrisDefinition
extends Resource

@export_category("Fragment Burst")
@export_range(1, 48, 1) var fragment_count := 12
@export_range(5.0, 500.0, 5.0) var minimum_speed := 55.0
@export_range(5.0, 600.0, 5.0) var maximum_speed := 145.0
## Total width of the ejecta cone around the reflected projectile path.
@export_range(5.0, 100.0, 1.0) var spread_degrees := 78.0
## Blends the cone from the surface normal (0) toward a true ricochet (1).
@export_range(0.0, 1.0, 0.05) var ricochet_bias := 0.75
@export_range(0.0, 1.0, 0.05) var projectile_energy_influence := 0.2
@export_range(0.1, 5.0, 0.05) var lifetime := 1.1

@export_category("Fragment Physics")
@export_range(0.25, 5.0, 0.25) var collision_radius := 0.75
@export_range(0.001, 10.0, 0.01) var fragment_mass := 0.08
@export_range(0.0, 1.0, 0.05) var bounce := 0.6
@export_range(0.0, 1.0, 0.05) var friction := 0.15
## Physical velocity damping applied every second after the burst. Higher values keep debris close to the impact.
@export_range(0.0, 20.0, 0.1) var linear_damping := 3.5
@export_range(0.0, 1.5, 0.05) var surface_velocity_inheritance := 1.0
## Minimum tumble rate for localized vector hull chips.
@export_range(0.0, 1080.0, 5.0) var minimum_tumble_degrees := 120.0
## Maximum tumble rate for localized vector hull chips.
@export_range(0.0, 1080.0, 5.0) var maximum_tumble_degrees := 420.0

@export_category("Vector Appearance")
@export_range(1.0, 20.0, 0.5) var minimum_length := 3.0
@export_range(1.0, 30.0, 0.5) var maximum_length := 8.0
@export_range(0.25, 5.0, 0.25) var line_width := 1.25
@export var hot_color := Color(0.72, 1.0, 0.96, 1.0)
@export_range(0.0, 1.0, 0.05) var hot_fragment_chance := 0.3
