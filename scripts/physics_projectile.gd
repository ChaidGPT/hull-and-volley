class_name PhysicsProjectile
extends RigidBody2D

signal impact_detected(projectile: RigidBody2D, collider: RigidBody2D, point: Vector2, normal: Vector2, incoming_velocity: Vector2)

@export_category("Projectile Physics")
@export_range(0.5, 20.0, 0.25) var collision_radius := 2.0
@export_range(0.01, 100.0, 0.05) var projectile_mass := 1.0
@export_range(0.0, 1.0, 0.05) var bounce := 0.05
@export_range(0.0, 1.0, 0.05) var friction := 0.0

var has_impacted := false


func _ready() -> void:
	mass = projectile_mass
	contact_monitor = true
	max_contacts_reported = 4
	continuous_cd = RigidBody2D.CCD_MODE_CAST_RAY
	var collision := get_node("CollisionShape2D") as CollisionShape2D
	var circle := CircleShape2D.new()
	circle.radius = collision_radius
	collision.shape = circle
	var projectile_physics_material := PhysicsMaterial.new()
	projectile_physics_material.bounce = bounce
	projectile_physics_material.friction = friction
	physics_material_override = projectile_physics_material


func _integrate_forces(state: PhysicsDirectBodyState2D) -> void:
	if has_impacted or state.get_contact_count() == 0:
		return
	for contact_index: int in range(state.get_contact_count()):
		var collider := state.get_contact_collider_object(contact_index) as RigidBody2D
		if not is_instance_valid(collider):
			continue
		has_impacted = true
		var local_point := state.get_contact_local_position(contact_index)
		var local_normal := state.get_contact_local_normal(contact_index)
		# Godot reports 2D contact positions and normals in world coordinates here,
		# despite the historical "local" method names.
		var world_point := local_point
		var world_normal := local_normal.normalized()
		call_deferred("_emit_impact", collider, world_point, world_normal, state.linear_velocity)
		break


func _emit_impact(collider: RigidBody2D, point: Vector2, normal: Vector2, incoming_velocity: Vector2) -> void:
	impact_detected.emit(self, collider, point, normal, incoming_velocity)


func stop_after_impact() -> void:
	set_deferred("freeze", true)
	set_deferred("collision_layer", 0)
	set_deferred("collision_mask", 0)
	linear_velocity = Vector2.ZERO
	angular_velocity = 0.0
