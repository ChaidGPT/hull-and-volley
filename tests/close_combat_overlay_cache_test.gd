extends SceneTree

const CLOSE_COMBAT_OVERLAY := preload("res://scripts/close_combat_overlay.gd")
const STARTING_LAYOUT := preload("res://resources/starting_ship_layout.tres")


class CountingHost extends Control:
	var requested_bounds := Rect2i(Vector2i(-2, -3), Vector2i(8, 10))
	var bounds_calls := 0

	func _bounds() -> Rect2i:
		bounds_calls += 1
		return requested_bounds


func _init() -> void:
	var host := CountingHost.new()
	var overlay: CloseCombatOverlay = CLOSE_COMBAT_OVERLAY.new()
	overlay.configure(host, STARTING_LAYOUT, Vector2(24.0, 32.0), 36.0)
	overlay.call("_refresh_geometry_cache")
	_assert(host.bounds_calls == 1, "initial cache build should request bounds once")

	var body := RigidBody2D.new()
	for index: int in range(500):
		var point := overlay.call("_world_to_view", body, Vector2(index, -index)) as Vector2
		overlay.call("_is_near_ship", point)
	_assert(host.bounds_calls == 1, "projectile transforms must reuse cached layout geometry")

	overlay.call("_refresh_geometry_cache")
	_assert(host.bounds_calls == 2, "a frame-level refresh should perform one cheap bounds check")
	host.requested_bounds = Rect2i(Vector2i(-4, -3), Vector2i(12, 10))
	overlay.call("_refresh_geometry_cache")
	_assert(host.bounds_calls == 3, "changed bounds should be detected")
	_assert(Vector2(overlay.get("cached_geometry_size")).x > 0.0, "changed bounds should rebuild geometry")

	body.free()
	overlay.free()
	host.free()
	print("CLOSE COMBAT OVERLAY CACHE TEST // PASS")
	quit(0)


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error("CLOSE COMBAT OVERLAY CACHE TEST // FAIL // %s" % message)
	quit(1)
