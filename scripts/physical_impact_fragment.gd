class_name PhysicalImpactFragment
extends RigidBody2D

@export_range(0.25, 5.0, 0.25) var collision_radius := 0.75
@export_range(0.001, 10.0, 0.01) var fragment_mass := 0.08
@export_range(0.0, 1.0, 0.05) var bounce := 0.6
@export_range(0.0, 1.0, 0.05) var friction := 0.15


func _ready() -> void:
	mass = fragment_mass
	continuous_cd = RigidBody2D.CCD_MODE_CAST_RAY
	var collision := get_node("CollisionShape2D") as CollisionShape2D
	var circle := CircleShape2D.new()
	circle.radius = collision_radius
	collision.shape = circle
	var fragment_physics_material := PhysicsMaterial.new()
	fragment_physics_material.bounce = bounce
	fragment_physics_material.friction = friction
	physics_material_override = fragment_physics_material
