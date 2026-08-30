class_name StructuralMaterialDefinition
extends Resource

@export_category("Wall Durability")
## Durability per full grid edge for walls exposed directly to space.
@export_range(1.0, 10000.0, 1.0) var outer_hull_durability := 90.0
## Durability per full grid edge for bulkheads separating different rooms.
@export_range(1.0, 10000.0, 1.0) var internal_bulkhead_durability := 55.0
## Penetration energy consumed for each point of wall durability destroyed.
@export_range(0.1, 10.0, 0.05) var penetration_resistance := 1.0

@export_category("Atmosphere")
## Pressure lost per second from a cell directly exposed to vacuum.
@export_range(0.01, 10.0, 0.01) var breach_vent_rate := 0.08
## Pressure equalization speed between openly connected cells.
@export_range(0.01, 10.0, 0.05) var equalization_rate := 1.4

@export_category("Decompression Physics")
## Total breached outer-wall length required before airflow begins pulling objects. Smaller holes still drain oxygen.
@export_range(0.1, 4.0, 0.1) var large_breach_length := 1.0
## Maximum distance, in grid cells, at which a large breach pulls nearby objects.
@export_range(0.25, 8.0, 0.25) var decompression_pull_radius := 2.5
## Acceleration applied toward a large breach, measured in grid cells per second squared.
@export_range(0.0, 20.0, 0.1) var decompression_pull_strength := 3.2
## Velocity damping applied to objects being carried by decompression airflow.
@export_range(0.0, 20.0, 0.1) var decompression_velocity_damping := 2.0

@export_category("Damage Colors")
## Color of structurally healthy walls in close views.
@export var healthy_wall_color := Color(0.58, 0.68, 0.69, 0.92)
## Color approached as a wall nears failure.
@export var damaged_wall_color := Color(1.0, 0.38, 0.16, 1.0)
## Marker color drawn at the ends of a complete breach.
@export var breach_marker_color := Color(1.0, 0.22, 0.12, 1.0)
