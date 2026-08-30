extends SceneTree

const SHIP_SIMULATION := preload("res://scripts/ship_simulation.gd")


func _init() -> void:
	var factor := Callable(SHIP_SIMULATION, "calculate_weapon_mount_staffing_factor")
	_assert(is_equal_approx(float(factor.call(1, 6, 6, 0, 3)), 0.0), "one crew must not operate a two-crew cannon")
	_assert(is_equal_approx(float(factor.call(2, 6, 6, 0, 3)), 1.0), "the first fully staffed cannon should operate")
	_assert(is_equal_approx(float(factor.call(2, 6, 6, 1, 3)), 0.0), "the second cannon should remain unstaffed")
	_assert(is_equal_approx(float(factor.call(4, 6, 6, 1, 3)), 1.0), "four crew should operate two cannons")
	_assert(is_equal_approx(float(factor.call(4, 6, 6, 2, 3)), 0.0), "the third cannon should remain unstaffed")
	_assert(is_equal_approx(float(factor.call(6, 6, 6, 2, 3)), 1.0), "six crew should operate all three cannons")
	print("WEAPON MOUNT STAFFING TEST // PASS // PER-MOUNT CREW ALLOCATION")
	quit(0)


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error("WEAPON MOUNT STAFFING TEST // FAIL // %s" % message)
	quit(1)
