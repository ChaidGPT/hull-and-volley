extends SceneTree

const DISPLAY := preload("res://scripts/power_requirement_display.gd")


func _initialize() -> void:
	var failures := PackedStringArray()
	var one_online := DISPLAY.bbcode(1, 1.0)
	if one_online.count("power.png") != 1 or one_online.contains("power_dark.png"):
		failures.append("a powered one-field grid did not show one lit bolt")
	var two_partial := DISPLAY.bbcode(2, 1.0)
	if two_partial.count("power.png") != 1 or two_partial.count("power_dark.png") != 1:
		failures.append("a two-field grid with one link did not show one lit and one dark bolt")
	var two_offline := DISPLAY.bbcode(2, 0.0)
	if two_offline.count("power_dark.png") != 2:
		failures.append("an unpowered two-field grid did not show two dark bolts")
	var damaged := DISPLAY.bbcode(2, 1.5)
	if damaged.count("power.png") != 1 or damaged.count("power_alert.png") != 1:
		failures.append("a damaged reactor link did not use the warning bolt")
	if not DISPLAY.plain_text(2, 1.0).contains("1 LIT") or not DISPLAY.plain_text(2, 1.0).contains("1 DARK"):
		failures.append("plain-text surfaces did not explain lit and dark link state")
	if failures.is_empty():
		print("POWER_REQUIREMENT_DISPLAY_TEST_PASS")
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	quit(1)
