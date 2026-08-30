class_name WeaponMountVisual
extends Node2D

## A weapon mount owns its art-space pivot and muzzle. Rooms only decide where
## this pivot is installed. Future recoil, barrel motion, muzzle flash, and
## firing animations can therefore stay inside this scene.
@export_range(0.0, 180.0, 1.0) var traverse_degrees := 12.0

@onready var muzzle: Marker2D = $Muzzle
@onready var animation_player: AnimationPlayer = get_node_or_null("AnimationPlayer") as AnimationPlayer
@onready var animated_sprite: AnimatedSprite2D = get_node_or_null("Sprite") as AnimatedSprite2D

var installed_facing_quarters := 0


func _ready() -> void:
	if animated_sprite != null:
		animated_sprite.animation_finished.connect(_on_sprite_animation_finished)


func _on_sprite_animation_finished() -> void:
	if animated_sprite == null or animated_sprite.animation != &"fire":
		return
	if animated_sprite.sprite_frames.has_animation(&"idle"):
		animated_sprite.play(&"idle")
	else:
		animated_sprite.stop()
		animated_sprite.frame = 0


## Returns the source-facing socket-to-muzzle vector after this scene's authored
## scale. Combat caches this value and rotates it with the installed facing.
func get_authored_muzzle_offset() -> Vector2:
	var marker := get_node_or_null("Muzzle") as Marker2D
	if marker == null:
		return Vector2.ZERO
	# Combat needs the source-facing art vector. Installed rotation is applied
	# separately from the room's saved facing, while authored scale belongs to
	# this scene and must remain part of the muzzle contract.
	return Vector2(marker.position.x * scale.x, marker.position.y * scale.y)


func set_installed_facing_quarters(facing_quarters: int) -> void:
	installed_facing_quarters = posmod(facing_quarters, 4)
	# Weapon art is authored facing south/down.
	rotation = PI + float(installed_facing_quarters) * PI * 0.5


## Aiming is local to the mount and clamped around its installed direction.
## The current cannon is fixed/narrow, but this is ready for traversing art.
func aim_toward_parent_direction(direction: Vector2) -> void:
	if direction.is_zero_approx():
		return
	var installed_rotation := PI + float(installed_facing_quarters) * PI * 0.5
	var desired_rotation := direction.angle() - PI * 0.5
	var maximum_offset := deg_to_rad(traverse_degrees)
	rotation = installed_rotation + clampf(
		angle_difference(installed_rotation, desired_rotation),
		-maximum_offset,
		maximum_offset
	)


func play_fire() -> void:
	if (
		animated_sprite != null
		and animated_sprite.sprite_frames != null
		and animated_sprite.sprite_frames.has_animation(&"fire")
	):
		# Restarting from frame zero keeps rapid or simultaneous cannon reports
		# visually synchronized with the shot that triggered them.
		animated_sprite.stop()
		animated_sprite.play(&"fire")
		return
	if animation_player != null and animation_player.has_animation(&"fire"):
		animation_player.play(&"fire")
