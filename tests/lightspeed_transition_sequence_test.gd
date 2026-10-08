extends SceneTree

const LIGHTSPEED_TRANSITION := preload("res://scripts/lightspeed_transition.gd")
const GENERATED_SECTOR := preload("res://scripts/resources/generated_sector.gd")


class ShipProbe extends Node:
	var ship_rotation := PI * 0.6
	var previous_ship_rotation := ship_rotation
	var velocity := Vector2(4.0, -2.0)


class VisualProbe extends Control:
	var forward_thrust := 0.0
	var propulsion_was_cleared := false

	func set_propulsion_visual_command(command: Dictionary) -> void:
		forward_thrust = float(command.get("forward", 0.0))

	func clear_propulsion_visual_command() -> void:
		propulsion_was_cleared = true
		forward_thrust = 0.0


class ViewProbe extends Node:
	var offset_y := 0.0
	var streak_strength := 0.0
	var maximum_offset := 0.0
	var was_cleared := false

	func set_jump_background_motion(new_offset_y: float, new_streak_strength: float) -> void:
		offset_y = new_offset_y
		streak_strength = new_streak_strength
		maximum_offset = maxf(maximum_offset, new_offset_y)

	func clear_jump_background_motion() -> void:
		was_cleared = true
		offset_y = 0.0
		streak_strength = 0.0

	func prepare_for_display() -> void:
		pass


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var failures := PackedStringArray()
	var transition := LIGHTSPEED_TRANSITION.new() as LightspeedTransition
	var ship := ShipProbe.new()
	var visual := VisualProbe.new()
	var view := ViewProbe.new()
	root.add_child(view)
	view.add_child(ship)
	view.add_child(visual)
	root.add_child(transition)

	var destination := GENERATED_SECTOR.new() as GeneratedSector
	destination.display_name = "Sequence Test"
	transition.begin_jump(destination, ship, visual, view)

	await create_timer(0.72, true).timeout
	if absf(ship.ship_rotation) > 0.001 or not ship.velocity.is_zero_approx():
		failures.append("ship did not finish facing up and stop before acceleration")
	if visual.forward_thrust <= 0.0 or view.offset_y <= 0.0:
		failures.append("thrusters and tactical background did not start after alignment")
	if view.streak_strength > 0.001:
		failures.append("jump streaks appeared before the initial acceleration beat")

	await transition.jump_midpoint
	if view.maximum_offset < 700.0:
		failures.append("departure background never reached jump-speed travel")
	await process_frame
	if visual.position.y < 60.0:
		failures.append("arrival did not stage the ship below its settled position")

	await transition.jump_completed
	if not visual.propulsion_was_cleared or not view.was_cleared:
		failures.append("jump-only propulsion or background motion was not cleared")
	if not is_zero_approx(visual.position.y) or not is_zero_approx(view.offset_y):
		failures.append("arrival did not settle ship and background at rest")

	if not failures.is_empty():
		for failure: String in failures:
			push_error("LIGHTSPEED TRANSITION TEST - FAIL - %s" % failure)
		quit(1)
		return
	print("LIGHTSPEED TRANSITION TEST - PASS - ALIGN, THRUST, STREAK, AND ARRIVAL BEATS")
	quit(0)
