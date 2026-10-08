extends SceneTree

const PHYSICS_PROJECTILE := preload("res://scenes/physics_projectile.tscn")


func _init() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var projectile := PHYSICS_PROJECTILE.instantiate() as PhysicsProjectile
	var former_friendly := StaticBody2D.new()
	root.add_child(projectile)
	root.add_child(former_friendly)
	projectile.add_projectile_collision_exception(former_friendly)
	former_friendly.queue_free()
	await process_frame
	# This is the fleet-battle failure: a ship disappears before its projectile is
	# returned to the pool. The reset must ignore the resulting null exception.
	projectile.prepare_for_pool()
	projectile.free()
	print("PROJECTILE POOL STALE EXCEPTION TEST // PASS")
	quit(0)
