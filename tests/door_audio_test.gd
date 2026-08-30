extends SceneTree

const DOOR_DEFINITION := preload("res://resources/default_door_definition.tres")


func _init() -> void:
	var opening_sound := DOOR_DEFINITION.get("opening_sound") as AudioStream
	var closing_sound := DOOR_DEFINITION.get("closing_sound") as AudioStream
	_assert(opening_sound != null, "default door has no opening sound")
	_assert(closing_sound != null, "default door has no closing sound")
	_assert(opening_sound.get_length() > 0.0, "opening sound has no playable duration")
	_assert(closing_sound.get_length() > 0.0, "closing sound has no playable duration")
	_assert(float(DOOR_DEFINITION.get("minimum_audible_zoom")) >= 2.0, "door audio must remain close-detail only")
	_assert(float(DOOR_DEFINITION.get("sound_volume_db")) <= -10.0, "door audio is too loud for repeated ambient use")
	print("DOOR AUDIO TEST - PASS - OPEN + CLOSE - QUIET CLOSE-ZOOM MIX")
	quit(0)


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error("DOOR AUDIO TEST - FAIL - %s" % message)
	quit(1)
