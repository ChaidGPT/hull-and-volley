class_name RunPrologueTerminal
extends Control

signal escape_confirmed
signal cancelled

const CYAN := Color(0.36, 1.0, 0.9, 1.0)
const AMBER := Color(1.0, 0.62, 0.18, 1.0)
const DIM := Color(0.42, 0.68, 0.65, 1.0)

var previous_pause_state := false
var transmission: Label
var continue_button: Button
var abort_button: Button
var typing_tween: Tween


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_interface()
	visible = false


func open_terminal() -> void:
	previous_pause_state = get_tree().paused
	get_tree().paused = true
	visible = true
	continue_button.disabled = true
	transmission.visible_ratio = 0.0
	if typing_tween != null and typing_tween.is_valid():
		typing_tween.kill()
	typing_tween = create_tween()
	typing_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	typing_tween.tween_property(transmission, "visible_ratio", 1.0, 3.8)
	typing_tween.tween_callback(func() -> void: continue_button.disabled = false)


func _close() -> void:
	visible = false
	get_tree().paused = previous_pause_state


func _confirm() -> void:
	_close()
	escape_confirmed.emit()


func _cancel() -> void:
	_close()
	cancelled.emit()


func _build_interface() -> void:
	var backdrop := ColorRect.new()
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0.0, 0.008, 0.012, 1.0)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(backdrop)

	var scanlines := ColorRect.new()
	scanlines.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scanlines.color = Color(0.02, 0.12, 0.11, 0.16)
	scanlines.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(scanlines)

	var terminal := VBoxContainer.new()
	terminal.anchor_left = 0.5
	terminal.anchor_top = 0.5
	terminal.anchor_right = 0.5
	terminal.anchor_bottom = 0.5
	terminal.offset_left = -390.0
	terminal.offset_top = -245.0
	terminal.offset_right = 390.0
	terminal.offset_bottom = 245.0
	terminal.add_theme_constant_override("separation", 14)
	add_child(terminal)

	terminal.add_child(_label("DETENTION NETWORK • UNAUTHORIZED CAPTAIN'S CHANNEL", 13, AMBER))
	terminal.add_child(_label("BLACKSITE SEVEN", 31, CYAN))
	terminal.add_child(_label("CELL BLOCK CONTROL HAS FAILED • SECURITY TRACE ACTIVE", 11, DIM))
	var divider := HSeparator.new()
	divider.add_theme_color_override("separator", Color(CYAN, 0.65))
	terminal.add_child(divider)

	transmission = _label(
		"The cell doors are open. You have no pardon and no rescue coming.\n\n"
		+ "A handful of prisoners made it out with you. The impound deck is three rings below, where station crews are stripping captured ships for parts. Three drive cores still answer. None of the hulls are complete.\n\n"
		+ "Take one. Break the clamps. Jump before the facility finishes tracing the stolen transponder. Every loud engagement will help the pursuit find you. Every sector you linger in gives the storm front time to close.\n\n"
		+ "This is not an extraction. This is a run.",
		16,
		Color(0.72, 0.96, 0.9)
	)
	transmission.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	transmission.size_flags_vertical = Control.SIZE_EXPAND_FILL
	terminal.add_child(transmission)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 12)
	terminal.add_child(actions)
	abort_button = _button("ABORT RUN SETUP", DIM)
	abort_button.pressed.connect(_cancel)
	actions.add_child(abort_button)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(spacer)
	continue_button = _button("BREACH IMPOUND DECK  >", AMBER)
	continue_button.pressed.connect(_confirm)
	actions.add_child(continue_button)


func _label(value: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = value
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label


func _button(value: String, color: Color) -> Button:
	var button := Button.new()
	button.text = value
	button.custom_minimum_size = Vector2(205, 48)
	button.add_theme_font_size_override("font_size", 12)
	button.add_theme_color_override("font_color", color)
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	return button
