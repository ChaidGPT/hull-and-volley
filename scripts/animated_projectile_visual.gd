@tool
class_name AnimatedProjectileVisual
extends ProjectileVisual

## Reusable visual shell for sprite-sheet projectiles.
##
## Author frames on the child AnimatedSprite2D. Source artwork should face
## right: the combat renderer rotates this whole scene along the shot vector.

@export_category("Projectile Animation")
@export var flight_animation: StringName = &"flight"
@export var spawn_animation: StringName = &"spawn"
@export var impact_animation: StringName = &"impact"
@export var play_spawn_before_flight := false
@export var randomize_flight_start := false

@export_category("Projectile Art")
@export_range(0.1, 8.0, 0.05) var art_scale := 1.0:
	set(value):
		art_scale = value
		_apply_art_transform()
@export_range(-180.0, 180.0, 1.0) var art_rotation_degrees := 0.0:
	set(value):
		art_rotation_degrees = value
		_apply_art_transform()
@export var art_offset := Vector2.ZERO:
	set(value):
		art_offset = value
		_apply_art_transform()

@onready var animated_sprite: AnimatedSprite2D = get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D


func _ready() -> void:
	super._ready()
	_apply_art_transform()
	if Engine.is_editor_hint():
		return
	if not is_instance_valid(animated_sprite):
		return
	if not animated_sprite.animation_finished.is_connected(_on_animation_finished):
		animated_sprite.animation_finished.connect(_on_animation_finished)
	play_flight()


func play_flight() -> void:
	if not _has_animation(flight_animation):
		return
	if play_spawn_before_flight and _has_animation(spawn_animation):
		animated_sprite.play(spawn_animation)
		return
	_start_flight_animation()


func play_impact() -> float:
	if not _has_animation(impact_animation):
		return 0.0
	animated_sprite.play(impact_animation)
	var speed := animated_sprite.sprite_frames.get_animation_speed(impact_animation)
	var frame_count := animated_sprite.sprite_frames.get_frame_count(impact_animation)
	return float(frame_count) / maxf(speed, 0.001)


func _start_flight_animation() -> void:
	animated_sprite.play(flight_animation)
	if randomize_flight_start:
		var frame_count := animated_sprite.sprite_frames.get_frame_count(flight_animation)
		if frame_count > 1:
			animated_sprite.frame = randi_range(0, frame_count - 1)


func _on_animation_finished() -> void:
	if animated_sprite.animation == spawn_animation:
		_start_flight_animation()


func _has_animation(animation_name: StringName) -> bool:
	return (
		is_instance_valid(animated_sprite)
		and animated_sprite.sprite_frames != null
		and animated_sprite.sprite_frames.has_animation(animation_name)
		and animated_sprite.sprite_frames.get_frame_count(animation_name) > 0
	)


func _apply_art_transform() -> void:
	var sprite := get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	if not is_instance_valid(sprite):
		return
	sprite.position = art_offset
	sprite.rotation = deg_to_rad(art_rotation_degrees)
	sprite.scale = Vector2.ONE * art_scale
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

