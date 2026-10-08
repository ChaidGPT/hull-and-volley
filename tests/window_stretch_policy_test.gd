extends SceneTree


func _init() -> void:
	var stretch_mode := String(ProjectSettings.get_setting("display/window/stretch/mode", ""))
	var stretch_aspect := String(ProjectSettings.get_setting("display/window/stretch/aspect", ""))
	var window_mode := int(ProjectSettings.get_setting("display/window/size/mode", -1))
	if window_mode != DisplayServer.WINDOW_MODE_MAXIMIZED:
		push_error("WINDOW STRETCH TEST // FAIL // game does not launch as a native maximized window")
		quit(1)
		return
	if stretch_mode != "canvas_items":
		push_error("WINDOW STRETCH TEST // FAIL // UI canvas is not configured to scale")
		quit(1)
		return
	if stretch_aspect != "expand":
		push_error("WINDOW STRETCH TEST // FAIL // maximized window remains aspect-boxed")
		quit(1)
		return
	print("WINDOW STRETCH TEST // PASS // RESPONSIVE FULL-WINDOW CANVAS")
	quit(0)
