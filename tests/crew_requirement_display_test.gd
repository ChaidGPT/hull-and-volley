extends SceneTree

const DISPLAY := preload("res://scripts/crew_requirement_display.gd")


func _initialize() -> void:
	var failures := PackedStringArray()
	var full_watch := DISPLAY.bbcode(2, 2, true)
	if full_watch.count("crew.png") != 2 or full_watch.contains("crew_dark.png") or full_watch.contains("crew_alert.png"):
		failures.append("a fully staffed two-crew grid did not show two bright indicators")
	var pending_watch := DISPLAY.bbcode(2, 1, true)
	if pending_watch.count("crew.png") != 1 or pending_watch.count("crew_dark.png") != 1:
		failures.append("an eventually fillable grid did not show one bright and one pending indicator")
	var short_watch := DISPLAY.bbcode(2, 1, false)
	if short_watch.count("crew.png") != 1 or short_watch.count("crew_alert.png") != 1:
		failures.append("a grid with inadequate berth capacity did not show the alert indicator")
	if not DISPLAY.plain_text(2, 1, true).contains("CREW PENDING"):
		failures.append("the pending state was not explained on plain-text displays")
	if not DISPLAY.plain_text(2, 1, false).contains("CREW SHORT"):
		failures.append("the berth-shortage state was not explained on plain-text displays")
	var compact_full := DISPLAY.status_bbcode(4, 4, true)
	if compact_full.count("crew.png") != 1 or not compact_full.contains("4/4"):
		failures.append("the compact grid badge did not collapse a full watch to one status icon")
	var compact_pending := DISPLAY.status_bbcode(4, 2, true)
	if compact_pending.count("crew_dark.png") != 1 or not compact_pending.contains("2/4"):
		failures.append("the compact grid badge did not show the pending state and staffing count")
	var compact_short := DISPLAY.status_bbcode(4, 2, false)
	if compact_short.count("crew_alert.png") != 1:
		failures.append("the compact grid badge did not show the berth-shortage state")
	if failures.is_empty():
		print("CREW_REQUIREMENT_DISPLAY_TEST_PASS")
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	quit(1)
