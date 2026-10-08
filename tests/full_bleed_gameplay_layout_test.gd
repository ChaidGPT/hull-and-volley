extends SceneTree


func _init() -> void:
	var packed := load("res://scenes/main.tscn") as PackedScene
	if packed == null:
		push_error("FULL BLEED LAYOUT TEST // FAIL // main scene could not be loaded")
		quit(1)
		return
	var main := packed.instantiate()
	var content_host := main.get_node("Layout/ContentPanel/ContentHost") as MarginContainer
	var footer := main.get_node("Layout/Footer") as Control
	var left_margin := content_host.get_theme_constant("margin_left")
	var right_margin := content_host.get_theme_constant("margin_right")
	var bottom_margin := content_host.get_theme_constant("margin_bottom")
	if left_margin != 0 or right_margin != 0 or bottom_margin != 0:
		push_error("FULL BLEED LAYOUT TEST // FAIL // gameplay still has side or bottom margins")
		main.free()
		quit(1)
		return
	if footer.visible:
		push_error("FULL BLEED LAYOUT TEST // FAIL // bottom control border is still visible")
		main.free()
		quit(1)
		return
	main.free()
	print("FULL BLEED LAYOUT TEST // PASS // LEFT RIGHT BOTTOM EDGES RELEASED")
	quit(0)
