extends SceneTree

const PANEL := preload("res://scripts/communication_panel.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failures := PackedStringArray()
	# Reproduce Main's view-install order: the child enters the tree before its
	# parent receives its final viewport-sized rect.
	var late_sized_view := Control.new()
	root.add_child(late_sized_view)
	var panel := PANEL.new() as CommunicationPanel
	late_sized_view.add_child(panel)
	late_sized_view.size = Vector2(1200.0, 560.0)
	panel.show_view({
		"speaker_title": "SALVAGE EXCHANGE",
		"speaker_name": "MORROW DRIFT",
		"standing": "NEUTRAL",
		"body": "Channel established.",
		"choices": [{"id": &"IDENTITY", "label": "IDENTIFY YOURSELF"}],
	})
	await process_frame
	_check(panel.position.x >= 0.0, "comms panel escaped the left edge", failures)
	_check(panel.position.y >= 0.0, "comms panel escaped the top edge", failures)
	_check(panel.position.x + panel.size.x <= late_sized_view.size.x + 0.5, "comms panel escaped the right edge", failures)
	_check(panel.position.y + panel.size.y <= late_sized_view.size.y + 0.5, "comms panel escaped the bottom edge", failures)
	var speaker: Label = panel.get("speaker_name")
	var body: RichTextLabel = panel.get("body")
	_check(speaker.text == "MORROW DRIFT", "speaker identity was blank", failures)
	_check(body.text == "Channel established.", "transmission body was blank", failures)

	if not failures.is_empty():
		for failure: String in failures:
			push_error("COMMUNICATION PANEL LAYOUT TEST // FAIL // %s" % failure)
		quit(1)
		return
	print("COMMUNICATION PANEL LAYOUT TEST // PASS // LATE-SIZED VIEW REMAINS CONTAINED")
	quit(0)


func _check(condition: bool, message: String, failures: PackedStringArray) -> void:
	if not condition:
		failures.append(message)
