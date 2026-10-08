class_name PhysicsProjectile
extends RigidBody2D

signal impact_detected(projectile: RigidBody2D, collider: RigidBody2D, point: Vector2, normal: Vector2, incoming_velocity: Vector2, projectile_id: int)

@export_category("Projectile Physics")
@export_range(0.5, 20.0, 0.25) var collision_radius := 2.0
@export_range(0.01, 100.0, 0.05) var projectile_mass := 1.0
@export_range(0.0, 1.0, 0.05) var bounce := 0.05
@export_range(0.0, 1.0, 0.05) var friction := 0.0

var has_impacted := false
var projectile_id := -1
var collision_shape: CollisionShape2D
var projectile_physics_material: PhysicsMaterial
var tracked_collision_exceptions: Array[WeakRef] = []


func _ready() -> void:
	collision_shape = get_node("CollisionShape2D") as CollisionShape2D
	projectile_physics_material = PhysicsMaterial.new()
	physics_material_override = projectile_physics_material
	contact_monitor = true
	max_contacts_reported = 4
	continuous_cd = RigidBody2D.CCD_MODE_CAST_RAY
	configure_projectile(collision_radius, projectile_mass, bounce)


func configure_projectile(radius: float, configured_mass: float, configured_bounce: float) -> void:
	collision_radius = radius
	projectile_mass = configured_mass
	bounce = configured_bounce
	mass = projectile_mass
	var circle := CircleShape2D.new()
	circle.radius = collision_radius
	if is_instance_valid(collision_shape):
		collision_shape.shape = circle
	if projectile_physics_material == null:
		projectile_physics_material = PhysicsMaterial.new()
	projectile_physics_material.bounce = bounce
	projectile_physics_material.friction = friction
	physics_material_override = projectile_physics_material


func activate_projectile(new_id: int, world_position: Vector2, world_rotation: float, velocity: Vector2) -> void:
	projectile_id = new_id
	has_impacted = false
	freeze = false
	collision_layer = 2
	collision_mask = 9
	global_position = world_position
	global_rotation = world_rotation
	linear_velocity = velocity
	angular_velocity = 0.0
	sleeping = false


func add_projectile_collision_exception(body: PhysicsBody2D) -> void:
	if not is_instance_valid(body):
		return
	add_collision_exception_with(body)
	tracked_collision_exceptions.append(weakref(body))


func prepare_for_pool() -> void:
	has_impacted = true
	projectile_id = -1
	freeze = true
	collision_layer = 0
	collision_mask = 0
	linear_velocity = Vector2.ZERO
	angular_velocity = 0.0
	# Never query get_collision_exceptions() here. If a friendly ship was freed,
	# Godot's native lookup reports an error while converting its stale RID back
	# into an Object. Weak references let the pool remove living exceptions and
	# silently discard bodies the physics server has already destroyed.
	for exception_ref: WeakRef in tracked_collision_exceptions:
		var exception_value: Variant = exception_ref.get_ref()
		if not is_instance_valid(exception_value) or not exception_value is PhysicsBody2D:
			continue
		remove_collision_exception_with(exception_value as PhysicsBody2D)
	tracked_collision_exceptions.clear()


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
	impact_detected.emit(self, collider, point, normal, incoming_velocity, projectile_id)


func stop_after_impact() -> void:
	set_deferred("freeze", true)
	set_deferred("collision_layer", 0)
	set_deferred("collision_mask", 0)
	linear_velocity = Vector2.ZERO
	angular_velocity = 0.0
