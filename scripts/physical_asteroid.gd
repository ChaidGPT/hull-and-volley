class_name PhysicalAsteroid
extends RigidBody2D

signal ship_impact_received(
	ship: RigidBody2D,
	point: Vector2,
	relative_velocity: Vector2,
	collision_energy: float
)
signal health_changed(asteroid_id: int, current_health: float, maximum_health: float)
signal destroyed(
	asteroid_id: int,
	world_position: Vector2,
	world_rotation: float,
	visual_radius: float,
	size_class: StringName
)

const ASTEROID_COLLISION_LAYER := 16
const PROJECTILE_TARGET_COLLISION_LAYER := 8
const CAPITAL_SHIP_COLLISION_LAYER := 1
const PROJECTILE_COLLISION_LAYER := 2
const SMALL_MAXIMUM_HEALTH := 18.0
const MEDIUM_MAXIMUM_HEALTH := 45.0
const LARGE_MAXIMUM_HEALTH := 100.0

## Half-width of the artwork in the authored asteroid scene. The complete scene
## is scaled uniformly at spawn time so hand-edited collision geometry continues
## to match the procedural radius selected for this asteroid.
@export_range(1.0, 256.0, 1.0) var authored_visual_radius := 16.0

var asteroid_id := -1
var region_id: StringName = &""
var visual_radius := 24.0
var silhouette := PackedVector2Array()
var visual_color := Color(0.2, 0.23, 0.26, 1.0)
var last_impact_speed := 0.0
var last_impact_energy := 0.0
var maximum_health := 18.0
var health := 18.0
var is_destroyed := false
var impact_damage_per_energy_unit := 1.5
var size_class: StringName = &"SMALL"


func configure(
	new_asteroid_id: int,
	new_region_id: StringName,
	radius: float,
	points: PackedVector2Array,
	color: Color
) -> void:
	asteroid_id = new_asteroid_id
	region_id = new_region_id
	visual_radius = radius
	silhouette = points
	visual_color = color
	collision_layer = ASTEROID_COLLISION_LAYER | PROJECTILE_TARGET_COLLISION_LAYER
	collision_mask = CAPITAL_SHIP_COLLISION_LAYER | PROJECTILE_COLLISION_LAYER
	gravity_scale = 0.0
	mass = maxf(radius * radius * 0.32, 80.0)
	size_class = &"SMALL" if radius <= 22.0 else (&"MEDIUM" if radius <= 32.0 else &"LARGE")
	match size_class:
		&"MEDIUM":
			maximum_health = MEDIUM_MAXIMUM_HEALTH
		&"LARGE":
			maximum_health = LARGE_MAXIMUM_HEALTH
		_:
			maximum_health = SMALL_MAXIMUM_HEALTH
	health = maximum_health
	linear_damp = 0.0
	angular_damp = 0.0
	continuous_cd = RigidBody2D.CCD_MODE_CAST_SHAPE
	can_sleep = true
	add_to_group("sector_obstacles")
	add_to_group("asteroids")
	set_meta("obstacle_type", &"ASTEROID")
	set_meta("asteroid_size", size_class)
	set_meta("region_id", region_id)
	var size_scale := radius / maxf(authored_visual_radius, 1.0)
	scale = Vector2.ONE * size_scale
	var material := PhysicsMaterial.new()
	material.bounce = 0.08
	material.friction = 0.48
	physics_material_override = material


func _ready() -> void:
	# This sprite is an editor alignment guide. TacticalWorld renders the live
	# asteroid because physics coordinates and display coordinates use different
	# origins in the command view.
	var editor_preview := get_node_or_null("EditorPreview") as Sprite2D
	if editor_preview != null:
		editor_preview.visible = false


func register_ship_impact(
	ship: RigidBody2D,
	point: Vector2,
	relative_velocity: Vector2,
	collision_energy: float
) -> void:
	last_impact_speed = relative_velocity.length()
	last_impact_energy = maxf(collision_energy, 0.0)
	ship_impact_received.emit(ship, point, relative_velocity, last_impact_energy)
	_apply_damage(last_impact_energy / 1000.0 * impact_damage_per_energy_unit)


func apply_projectile_damage(damage: float) -> void:
	_apply_damage(damage)


func _apply_damage(damage: float) -> void:
	if is_destroyed or damage <= 0.0:
		return
	health = maxf(health - damage, 0.0)
	health_changed.emit(asteroid_id, health, maximum_health)
	if health > 0.0:
		return
	is_destroyed = true
	collision_layer = 0
	collision_mask = 0
	destroyed.emit(
		asteroid_id,
		global_position,
		global_rotation,
		visual_radius,
		size_class
	)
	queue_free()


func get_health_report() -> Dictionary:
	return {
		"id": asteroid_id,
		"size": size_class,
		"health": health,
		"maximum_health": maximum_health,
		"destroyed": is_destroyed,
	}
