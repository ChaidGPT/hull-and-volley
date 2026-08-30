class_name WeaponDefinition
extends Resource

@export var weapon_id: StringName
@export var display_name := "WEAPON"
@export_multiline var description := ""
@export_enum("CANNON", "BALLISTIC", "LASER", "ENERGY", "MISSILE") var weapon_family := "CANNON"
@export_enum("KINETIC", "EXPLOSIVE", "THERMAL", "ENERGY") var damage_type := "KINETIC"
@export_range(1, 12, 1) var required_mount_cells := 1
@export_range(1.0, 10000.0, 10.0) var maximum_range := 1000.0
@export_range(0.0, 180.0, 1.0) var traverse_degrees := 0.0
## Turret mounts may traverse through every open hull face around their grid.
## Fixed and casemate weapons remain restricted to their selected business edge.
@export var uses_exposed_hull_edges := false
@export_range(1.0, 1000.0, 1.0) var damage := 10.0
@export_category("Target Effectiveness")
## Weapon damage is authored once, then shaped by the kind of target it reaches.
## This lets rapid weapons threaten fighters and machinery without sawing through
## capital hulls or manufacturing catastrophic breaches.
@export_range(0.0, 5.0, 0.05) var shield_damage_multiplier := 1.0
@export_range(0.0, 5.0, 0.05) var hull_damage_multiplier := 1.0
@export_range(0.0, 5.0, 0.05) var system_damage_multiplier := 1.0
@export_range(0.0, 5.0, 0.05) var breach_damage_multiplier := 1.0
@export_range(0.0, 5.0, 0.05) var fighter_damage_multiplier := 1.0
## Optional non-destructive disruption applied to the struck physical module.
## Future ion weapons can use this without inventing a second projectile path.
@export_range(0.0, 120.0, 0.25) var ion_disruption_seconds := 0.0
## Half-angle of the weapon's shot dispersion cone. Zero remains perfectly accurate.
@export_range(0.0, 20.0, 0.1) var accuracy_degrees := 0.0
@export_category("Projectile")
## Energy available for breaking successive wall segments after shields are bypassed.
@export_range(0.0, 5000.0, 1.0) var penetration_power := 10.0
@export_range(0.1, 60.0, 0.1) var reload_seconds := 5.0
@export_range(10.0, 5000.0, 10.0) var projectile_speed := 500.0
@export_range(0.5, 20.0, 0.25) var projectile_collision_radius := 2.0
@export_range(0.01, 100.0, 0.05) var projectile_mass := 1.0
@export_range(0.0, 1.0, 0.05) var projectile_bounce := 0.05
@export_range(0.0, 500.0, 5.0) var blast_radius := 0.0
@export var visual_color := Color(0.9, 0.58, 0.22)
@export var projectile_scene: PackedScene
## Optional one-shot visual created at the physical contact point. Empty uses
## the game's default larger impact animation.
@export var impact_effect_scene: PackedScene
## Optional localized debris profile used by this weapon on impact. Empty uses the global capital-scale profile.
@export var impact_debris_definition: Resource

@export_category("Weapon Mount Visual")
## Optional self-contained weapon scene. Its root is installed at the room's
## weapon socket and its Muzzle marker is the authoritative projectile origin.
@export var mount_visual_scene: PackedScene
@export_category("Legacy Authored Muzzle")
## Pixel offset from the weapon art's rotation socket to the exact barrel tip.
## Used only by older weapons that do not yet provide mount_visual_scene.
@export var authored_muzzle_offset_pixels := Vector2.ZERO
## Width of the Aseprite room canvas that authored_muzzle_offset_pixels was measured on.
## A normal room is currently 160 px wide and maps to one 2x2 ship grid piece.
@export_range(1.0, 2048.0, 1.0) var authored_room_source_pixels := 160.0

@export_category("Audio")
## Optional sound played whenever this weapon fires. Leave empty to fire silently without errors.
@export var firing_sound: AudioStream
## Volume adjustment applied only to this weapon's firing sound.
@export_range(-40.0, 12.0, 0.5) var firing_volume_db := 0.0
## Small random pitch variation prevents rapid-fire weapons from sounding mechanically identical on every shot.
@export_range(0.0, 0.5, 0.01) var firing_pitch_variation := 0.0
## Optional sound emitted at the projectile's physical impact point.
@export var impact_sound: AudioStream
## Volume adjustment applied only to this weapon's impact sound.
@export_range(-40.0, 12.0, 0.5) var impact_volume_db := 0.0
## Impact pitch variation gives repeated hits some material and weight variation.
@export_range(0.0, 0.5, 0.01) var impact_pitch_variation := 0.0
