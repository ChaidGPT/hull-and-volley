class_name VectorImpactBurst
extends Node2D

@export_category("Burst Shape")
@export_range(3, 32, 1) var particle_count := 11
@export_range(10.0, 300.0, 5.0) var minimum_speed := 55.0
@export_range(10.0, 400.0, 5.0) var maximum_speed := 145.0
@export_range(1.0, 20.0, 0.5) var minimum_length := 3.0
@export_range(1.0, 30.0, 0.5) var maximum_length := 9.0
@export_range(0.1, 2.0, 0.05) var lifetime := 0.48
@export_range(0.1, 8.0, 0.1) var line_width := 1.5
@export_range(0.0, 500.0, 5.0) var drag := 95.0
@export_range(5.0, 90.0, 1.0) var spread_degrees := 72.0
@export_range(0.0, 1.0, 0.05) var incoming_energy_influence := 0.2
@export_range(0.0, 1.5, 0.05) var surface_velocity_inheritance := 1.0
@export_range(0.0, 12.0, 0.5) var surface_offset := 2.5

@export_category("Appearance")
@export var spark_color := Color(1.0, 0.68, 0.22, 1.0)
@export var hot_color := Color(0.72, 1.0, 0.96, 1.0)
@export_range(0.0, 1.0, 0.05) var hot_particle_chance := 0.3

var particles: Array[Dictionary] = []
var elapsed := 0.0
var random := RandomNumberGenerator.new()
var impact_normal := Vector2.RIGHT
var incoming_velocity := Vector2.ZERO
var surface_velocity := Vector2.ZERO


func _ready() -> void:
	random.randomize()
	for index: int in range(particle_count):
		var direction := impact_normal.rotated(deg_to_rad(random.randf_range(-spread_degrees, spread_degrees)))
		var impact_energy := incoming_velocity.length() * incoming_energy_influence
		particles.append({
			"position": impact_normal * surface_offset,
			"velocity": direction * (random.randf_range(minimum_speed, maximum_speed) + impact_energy) + surface_velocity * surface_velocity_inheritance,
			"length": random.randf_range(minimum_length, maximum_length),
			"color": hot_color if random.randf() < hot_particle_chance else spark_color,
		})
	queue_redraw()


func configure_impact(color: Color, surface_normal: Vector2, projectile_velocity: Vector2, impacted_surface_velocity: Vector2) -> void:
	spark_color = color
	impact_normal = surface_normal.normalized() if surface_normal.length_squared() > 0.01 else -projectile_velocity.normalized()
	incoming_velocity = projectile_velocity
	surface_velocity = impacted_surface_velocity


func _process(delta: float) -> void:
	elapsed += delta
	for particle: Dictionary in particles:
		var velocity: Vector2 = particle["velocity"]
		particle["position"] = (particle["position"] as Vector2) + velocity * delta
		particle["velocity"] = velocity.move_toward(Vector2.ZERO, drag * delta)
	queue_redraw()
	if elapsed >= lifetime:
		queue_free()


func _draw() -> void:
	var life_ratio := clampf(elapsed / maxf(lifetime, 0.001), 0.0, 1.0)
	var alpha := 1.0 - smoothstep(0.35, 1.0, life_ratio)
	for particle: Dictionary in particles:
		var point: Vector2 = particle["position"]
		var velocity: Vector2 = particle["velocity"]
		var direction := velocity.normalized() if velocity.length_squared() > 0.01 else Vector2.RIGHT
		var color: Color = particle["color"]
		color.a *= alpha
		draw_line(point, point - direction * float(particle["length"]), color, line_width, true)
