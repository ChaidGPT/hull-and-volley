extends SceneTree

const WEAPON_PATHS := [
	"res://resources/weapons/fighter_autocannon.tres",
	"res://resources/weapons/traverse_gun.tres",
	"res://resources/weapons/laser_emitter.tres",
	"res://resources/weapons/longshot_cannon.tres",
	"res://resources/weapons/plasma_projector.tres",
	"res://resources/weapons/missile_launcher.tres",
]

const IMPORTED_AUDIO_PATHS := [
	"res://assets/audio/weapons/prunus/scifi_weapon_big.ogg",
	"res://assets/audio/weapons/prunus/scifi_weapon_laser_big.ogg",
	"res://assets/audio/weapons/prunus/scifi_weapon_laser_medium.ogg",
	"res://assets/audio/weapons/prunus/scifi_weapon_laser_medium_auto.ogg",
	"res://assets/audio/weapons/prunus/scifi_weapon_laser_medium_burst.ogg",
	"res://assets/audio/weapons/prunus/scifi_weapon_laser_small.ogg",
	"res://assets/audio/weapons/prunus/scifi_weapon_laser_small_auto.ogg",
	"res://assets/audio/weapons/prunus/scifi_weapon_laser_small_burst.ogg",
	"res://assets/audio/weapons/prunus/scifi_weapon_medium.ogg",
	"res://assets/audio/weapons/prunus/scifi_weapon_medium_auto.ogg",
	"res://assets/audio/weapons/prunus/scifi_weapon_medium_burst.ogg",
	"res://assets/audio/weapons/prunus/scifi_weapon_small.ogg",
	"res://assets/audio/weapons/prunus/scifi_weapon_small_auto.ogg",
	"res://assets/audio/weapons/prunus/scifi_weapon_small_burst.ogg",
	"res://assets/audio/sfx/scifi_hit_large_01.mp3",
]


func _init() -> void:
	for audio_path: String in IMPORTED_AUDIO_PATHS:
		var stream := load(audio_path) as AudioStream
		_assert(stream != null, "audio asset failed to load: %s" % audio_path)
		_assert(stream.get_length() > 0.0, "audio asset has no playable duration: %s" % audio_path)

	for weapon_path: String in WEAPON_PATHS:
		var weapon := load(weapon_path) as Resource
		_assert(weapon != null, "weapon resource failed to load: %s" % weapon_path)
		_assert(weapon.get("firing_sound") is AudioStream, "weapon has no firing sound: %s" % weapon_path)
		_assert(weapon.get("impact_sound") is AudioStream, "weapon has no impact sound: %s" % weapon_path)

	print("WEAPON AUDIO TEST - PASS - 6 WEAPONS - 15 AUDIO ASSETS")
	quit(0)


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error("WEAPON AUDIO TEST - FAIL - %s" % message)
	quit(1)
