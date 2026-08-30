class_name ModuleVisualController
extends Node2D

## Emitted by an animation method track on the exact frame a projectile should leave the muzzle.
signal projectile_requested(muzzle_transform: Transform2D)
## Emitted when an animation reaches its authored muzzle-effect frame.
signal muzzle_effect_requested(muzzle_transform: Transform2D)
## Emitted when the reload animation reports that ammunition is ready.
signal reload_completed

@export_category("Template Node Contract")
## Node that rotates across the module's allowed traverse arc.
@export var turret_pivot_path := NodePath("TurretPivot")
## Optional second pivot used for barrel elevation, recoil, or independent motion.
@export var barrel_pivot_path := NodePath("TurretPivot/BarrelPivot")
## Marker where projectiles, flashes, sparks, and smoke originate.
@export var muzzle_path := NodePath("TurretPivot/BarrelPivot/Muzzle")
## AnimationPlayer containing idle, aim, fire, reload, and damage animations.
@export var animation_player_path := NodePath("AnimationPlayer")

@export_category("Preview and Runtime")
## Maximum left/right rotation allowed for this visual in degrees.
@export_range(0.0, 180.0, 1.0) var traverse_degrees := 45.0
## Visual turning speed in degrees per second.
@export_range(1.0, 720.0, 1.0) var traverse_speed_degrees := 120.0

var target_local_angle := 0.0


func _process(delta: float) -> void:
	var turret := get_node_or_null(turret_pivot_path) as Node2D
	if turret == null:
		return
	var limit := deg_to_rad(traverse_degrees)
	var desired := clampf(target_local_angle, -limit, limit)
	turret.rotation = move_toward(turret.rotation, desired, deg_to_rad(traverse_speed_degrees) * delta)


## Supplies an aim direction in this visual scene's local coordinates.
func set_local_aim_direction(direction: Vector2) -> void:
	if direction.length_squared() > 0.001:
		target_local_angle = direction.angle()


## Plays a named animation when it exists. Custom scenes may safely omit unused animations.
func play_module_animation(animation_name: StringName) -> void:
	var player := get_node_or_null(animation_player_path) as AnimationPlayer
	if player != null and player.has_animation(animation_name):
		player.play(animation_name)


## Call this from a fire animation's method track on the frame the projectile should spawn.
func animation_fire_projectile() -> void:
	projectile_requested.emit(_muzzle_transform())


## Call this from a fire animation's method track when sparks, smoke, or muzzle flash should appear.
func animation_emit_muzzle_effect() -> void:
	muzzle_effect_requested.emit(_muzzle_transform())


## Call this from the final frame of a reload animation.
func animation_finish_reload() -> void:
	reload_completed.emit()


func _muzzle_transform() -> Transform2D:
	var muzzle := get_node_or_null(muzzle_path) as Node2D
	return muzzle.global_transform if muzzle != null else global_transform

