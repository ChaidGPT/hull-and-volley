class_name ImpactSpriteBurst
extends Node2D

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D


func _ready() -> void:
	animated_sprite.animation_finished.connect(queue_free)
	animated_sprite.play(&"impact")


func configure(outward_normal: Vector2, impact_color: Color, size_multiplier: float = 1.0) -> void:
	rotation = outward_normal.angle()
	scale = Vector2.ONE * size_multiplier
	# Preserve the authored hot center while allowing weapon families to tint it.
	modulate = impact_color.lerp(Color.WHITE, 0.68)
	if randf() < 0.5:
		animated_sprite.flip_v = true
