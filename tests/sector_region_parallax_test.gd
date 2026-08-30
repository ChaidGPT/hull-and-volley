extends SceneTree

const REGION_PARALLAX := preload("res://scripts/sector_region_parallax.gd")
const SPECIAL_REGION := preload("res://scripts/resources/sector_special_region.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failures := PackedStringArray()
	var view := Control.new()
	view.size = Vector2(800.0, 600.0)
	root.add_child(view)
	var parallax := REGION_PARALLAX.new() as SectorRegionParallax
	parallax.size = view.size
	view.add_child(parallax)
	var world := Control.new()
	world.size = Vector2(10000.0, 10000.0)
	world.pivot_offset = Vector2(5000.0, 5000.0)
	world.position = Vector2(-4700.0, -4700.0)
	view.add_child(world)
	parallax.world = world

	var strength := 0.78
	var anchor := Vector2.ZERO
	var start: Vector2 = parallax.call("_parallax_screen_point", Vector2.ZERO, strength, anchor)
	world.position.x += 100.0
	var near_step: Vector2 = parallax.call("_parallax_screen_point", Vector2.ZERO, strength, anchor)
	world.position.x += 2000.0
	var far_start: Vector2 = parallax.call("_parallax_screen_point", Vector2.ZERO, strength, anchor)
	world.position.x += 100.0
	var far_step: Vector2 = parallax.call("_parallax_screen_point", Vector2.ZERO, strength, anchor)
	_check(is_equal_approx(near_step.x - start.x, 78.0), "near camera motion was not linear", failures)
	_check(is_equal_approx(far_step.x - far_start.x, 78.0), "far camera motion changed speed", failures)

	var first: Vector2 = parallax.call("_parallax_screen_point", Vector2.ZERO, strength, anchor)
	var second: Vector2 = parallax.call("_parallax_screen_point", Vector2(120.0, 0.0), strength, anchor)
	_check(is_equal_approx(second.x - first.x, 120.0), "flat sheet distorted object spacing", failures)

	var defaults := SPECIAL_REGION.new() as SectorSpecialRegion
	_check(defaults.far_parallax > 0.7, "far layer is still too loosely registered", failures)
	_check(defaults.middle_parallax > defaults.far_parallax, "layer depth order is inverted", failures)

	if not failures.is_empty():
		for failure: String in failures:
			push_error("SECTOR PARALLAX TEST • FAIL • %s" % failure)
		quit(1)
		return
	print("SECTOR PARALLAX TEST • PASS • LINEAR FLAT-SHEET MOTION")
	quit(0)


func _check(condition: bool, message: String, failures: PackedStringArray) -> void:
	if not condition:
		failures.append(message)
