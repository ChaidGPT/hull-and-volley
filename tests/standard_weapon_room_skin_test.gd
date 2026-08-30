extends SceneTree

const TACTICAL_VISUAL := preload("res://scripts/tactical_ship_visual.gd")
const FLOOR := preload("res://assets/sprites/interiors/rooms/standard/masks/floor.png")


func _init() -> void:
	var failures := PackedStringArray()
	var visual: Control = TACTICAL_VISUAL.new()
	for facing: int in range(4):
		var cut_floor: Texture2D = visual.call("_standard_texture_with_weapon_cutout", FLOOR, facing)
		var image := cut_floor.get_image()
		var transparent_counts := [0, 0, 0, 0] # N, E, S, W edge bands.
		for index: int in range(160):
			if image.get_pixel(index, 159).a < 0.01:
				transparent_counts[2] += 1
			if image.get_pixel(159, index).a < 0.01:
				transparent_counts[1] += 1
			if image.get_pixel(index, 0).a < 0.01:
				transparent_counts[0] += 1
			if image.get_pixel(0, index).a < 0.01:
				transparent_counts[3] += 1
		var expected_edge := facing
		var strongest_edge := 0
		for edge: int in range(1, 4):
			if transparent_counts[edge] > transparent_counts[strongest_edge]:
				strongest_edge = edge
		_check(
			strongest_edge == expected_edge and transparent_counts[expected_edge] > 16,
			"weapon cutout did not rotate to quarter %d: %s" % [facing, str(transparent_counts)],
			failures
		)

	visual.free()
	if not failures.is_empty():
		for failure: String in failures:
			push_error("STANDARD WEAPON ROOM SKIN TEST - FAIL - %s" % failure)
		quit(1)
		return
	print("STANDARD WEAPON ROOM SKIN TEST - PASS - AUTHORED CUTOUT ROTATES N/E/S/W")
	quit(0)


func _check(condition: bool, message: String, failures: PackedStringArray) -> void:
	if not condition:
		failures.append(message)
