class_name ModuleVisualDefinition
extends Resource

@export_category("Scenes")
## Exterior scene used on the zoomed-out tactical ship view.
@export var tactical_scene: PackedScene
## Scene used while viewing and editing the ship's settlement grid.
@export var settlement_scene: PackedScene
## Detailed interior scene used on the close crew view.
@export var crew_scene: PackedScene
## Optional persistent effect while this module is powered or operating.
@export var active_effect_scene: PackedScene
## Optional effect spawned when this module itself is struck.
@export var impact_effect_scene: PackedScene
## Effect spawned at the muzzle during the authored firing frame.
@export var muzzle_effect_scene: PackedScene
## Optional effect played during reload, charging, venting, or ammunition handling.
@export var reload_effect_scene: PackedScene

@export_category("Animation Contract")
## Path to the scene's AnimationPlayer. Keep this contract when replacing the template artwork.
@export var animation_player_path := NodePath("AnimationPlayer")
## Pivot that turns to aim the complete weapon mount.
@export var turret_pivot_path := NodePath("TurretPivot")
## Pivot for recoil or secondary barrel motion.
@export var barrel_pivot_path := NodePath("TurretPivot/BarrelPivot")
## Marker used as the projectile and muzzle-effect origin.
@export var idle_animation: StringName = &"idle"
@export var aim_animation: StringName = &"aim"
@export var fire_animation: StringName = &"fire"
@export var reload_animation: StringName = &"reload"
@export var charge_animation: StringName = &"charge"
@export var cooldown_animation: StringName = &"cooldown"
@export var activate_animation: StringName = &"activate"
@export var active_animation: StringName = &"active"
@export var damaged_animation: StringName = &"damaged"
@export var destroyed_animation: StringName = &"destroyed"
@export var muzzle_marker_path := NodePath("Muzzle")
## Marker for shell casings, exhaust, coolant, or other secondary emissions.
@export var secondary_effect_marker_path := NodePath("SecondaryEffect")
@export_range(0.05, 10.0, 0.05) var animation_speed_scale := 1.0

@export_category("Audio")
## Sound played when the firing animation reaches its firing event.
@export var fire_sound: AudioStream
## Mechanical or energy sound played while reloading.
@export var reload_sound: AudioStream
## Optional looping or one-shot charging sound.
@export var charge_sound: AudioStream
## Sound used when this module is damaged or malfunctions.
@export var damaged_sound: AudioStream

@export_category("Placement")
@export var local_offset := Vector2.ZERO
@export var local_scale := Vector2.ONE
@export var rotate_with_module := true
## Extra rotation applied after the module's grid-facing direction.
@export_range(-180.0, 180.0, 1.0) var rotation_offset_degrees := 0.0
## Whether this visual should be clipped to the combined module footprint.
@export var clip_to_footprint := false
