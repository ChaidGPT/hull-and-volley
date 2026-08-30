class_name CommunicationPanel
extends PanelContainer

signal response_selected(response_id: StringName)
signal channel_closed

const CREW_PORTRAIT_SCENE := preload("res://scenes/crew_portrait.tscn")
const CHARACTERS_PER_SECOND := 58.0

var portrait: Control
var speaker_title: Label
var speaker_name: Label
var standing_label: Label
var body: RichTextLabel
var choices: VBoxContainer
var end_signal_button: Button
var typed_characters := 0.0
var target_characters := 0
var motion_time := 0.0
var entrance_tween: Tween


func _ready() -> void:
	name = "CommunicationPanel"
	# The communications terminal remains interactive while the tactical
	# simulation behind it is paused.
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	_recenter()
	custom_minimum_size = Vector2(660.0, 370.0)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_style()
	_build_interface()
	visible = false
	set_process(false)


func _process(delta: float) -> void:
	if not visible or not is_instance_valid(body):
		return
	typed_characters = minf(typed_characters + CHARACTERS_PER_SECOND * delta, float(target_characters))
	body.visible_characters = floori(typed_characters)
	motion_time += delta
	if is_instance_valid(portrait):
		var pulse := 1.0 + (sin(motion_time * 2.1) + 1.0) * 0.004
		portrait.scale = Vector2.ONE * pulse
	if is_instance_valid(standing_label):
		standing_label.modulate.a = 0.78 + (sin(motion_time * 3.2) + 1.0) * 0.09


func show_view(view: Dictionary) -> void:
	# ShipView is instantiated before Main gives it its final full-screen rect.
	# Reassert anchor-relative offsets here so a channel opened immediately after
	# a sector transition cannot inherit the view's old zero-sized coordinates.
	_recenter()
	var opening := not visible
	speaker_title.text = String(view.get("speaker_title", "OPEN CHANNEL")).to_upper()
	speaker_name.text = String(view.get("speaker_name", "UNKNOWN CONTACT")).to_upper()
	standing_label.text = String(view.get("standing", "NEUTRAL")).to_upper()
	var accent := Color(view.get("portrait_color", Color(0.35, 0.9, 0.88, 1.0)))
	speaker_name.add_theme_color_override("font_color", accent)
	standing_label.add_theme_color_override("font_color", accent.lightened(0.12))
	portrait.call(
		"configure",
		int(view.get("portrait_seed", 1)),
		accent,
		100.0,
		75.0
	)
	body.text = String(view.get("body", ""))
	target_characters = body.get_total_character_count()
	typed_characters = 0.0
	body.visible_characters = 0
	_rebuild_choices(view.get("choices", []))
	visible = true
	set_process(true)
	if opening:
		_play_entrance()
	else:
		body.modulate.a = 0.35
		choices.modulate.a = 0.35
		var response_tween := create_tween().set_parallel(true)
		response_tween.tween_property(body, "modulate:a", 1.0, 0.12)
		response_tween.tween_property(choices, "modulate:a", 1.0, 0.16)


func _recenter() -> void:
	anchor_left = 0.5
	anchor_top = 0.5
	anchor_right = 0.5
	anchor_bottom = 0.5
	offset_left = -330.0
	offset_top = -185.0
	offset_right = 330.0
	offset_bottom = 185.0


func close_channel() -> void:
	visible = false
	set_process(false)


func _build_style() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.003, 0.015, 0.02, 0.985)
	style.border_color = Color(0.2, 0.86, 0.82, 0.95)
	style.set_border_width_all(1)
	style.corner_radius_top_left = 3
	style.corner_radius_bottom_right = 14
	style.shadow_color = Color(0.05, 0.9, 0.82, 0.22)
	style.shadow_size = 12
	add_theme_stylebox_override("panel", style)


func _build_interface() -> void:
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_bottom", 14)
	add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	margin.add_child(root)
	var header := HBoxContainer.new()
	header.custom_minimum_size = Vector2(0.0, 84.0)
	header.add_theme_constant_override("separation", 12)
	root.add_child(header)
	portrait = CREW_PORTRAIT_SCENE.instantiate() as Control
	portrait.custom_minimum_size = Vector2(76.0, 76.0)
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(portrait)
	var identity := VBoxContainer.new()
	identity.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	identity.add_theme_constant_override("separation", 2)
	header.add_child(identity)
	speaker_title = Label.new()
	speaker_title.add_theme_color_override("font_color", Color(0.35, 0.7, 0.75))
	speaker_title.add_theme_font_size_override("font_size", 10)
	identity.add_child(speaker_title)
	speaker_name = Label.new()
	speaker_name.add_theme_font_size_override("font_size", 20)
	identity.add_child(speaker_name)
	standing_label = Label.new()
	standing_label.add_theme_font_size_override("font_size", 9)
	identity.add_child(standing_label)
	end_signal_button = Button.new()
	end_signal_button.custom_minimum_size = Vector2(112.0, 58.0)
	end_signal_button.text = "END SIGNAL"
	end_signal_button.tooltip_text = "CLICK • CUT THE ACTIVE COMMUNICATIONS CARRIER"
	end_signal_button.add_theme_color_override("font_color", Color(1.0, 0.52, 0.3))
	end_signal_button.add_theme_color_override("font_hover_color", Color(1.0, 0.86, 0.62))
	end_signal_button.add_theme_font_size_override("font_size", 11)
	var end_normal := StyleBoxFlat.new()
	end_normal.bg_color = Color(0.075, 0.018, 0.012, 0.94)
	end_normal.border_color = Color(0.62, 0.18, 0.1, 0.9)
	end_normal.border_width_left = 3
	end_normal.border_width_top = 1
	end_normal.border_width_right = 1
	end_normal.border_width_bottom = 1
	end_normal.corner_radius_top_left = 2
	end_normal.corner_radius_bottom_right = 9
	end_signal_button.add_theme_stylebox_override("normal", end_normal)
	var end_hover := end_normal.duplicate() as StyleBoxFlat
	end_hover.bg_color = Color(0.2, 0.035, 0.015, 0.98)
	end_hover.border_color = Color(1.0, 0.42, 0.2, 1.0)
	end_hover.shadow_color = Color(1.0, 0.18, 0.05, 0.32)
	end_hover.shadow_size = 8
	end_signal_button.add_theme_stylebox_override("hover", end_hover)
	end_signal_button.add_theme_stylebox_override("pressed", end_hover)
	end_signal_button.pressed.connect(func() -> void: channel_closed.emit())
	end_signal_button.mouse_entered.connect(_animate_end_signal_hover.bind(true))
	end_signal_button.mouse_exited.connect(_animate_end_signal_hover.bind(false))
	header.add_child(end_signal_button)
	var divider := HSeparator.new()
	root.add_child(divider)
	body = RichTextLabel.new()
	body.custom_minimum_size = Vector2(0.0, 124.0)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.bbcode_enabled = false
	body.fit_content = false
	body.scroll_active = false
	body.add_theme_color_override("default_color", Color(0.73, 0.96, 0.91))
	body.add_theme_font_size_override("normal_font_size", 14)
	root.add_child(body)
	choices = VBoxContainer.new()
	choices.custom_minimum_size = Vector2(0.0, 94.0)
	choices.add_theme_constant_override("separation", 5)
	root.add_child(choices)


func _rebuild_choices(choice_data: Array) -> void:
	for child: Node in choices.get_children():
		# A response rebuild can be triggered by the button currently emitting
		# `pressed`. Hide it immediately, then retire it safely after the signal
		# stack unwinds.
		if child is Control:
			var control := child as Control
			control.visible = false
			control.mouse_filter = Control.MOUSE_FILTER_IGNORE
		child.queue_free()
	for choice_value: Variant in choice_data.slice(0, 4):
		var choice: Dictionary = choice_value
		var button := Button.new()
		button.custom_minimum_size = Vector2(0.0, 28.0)
		button.text = "›  %s" % String(choice.get("label", "RESPOND"))
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.add_theme_font_size_override("font_size", 11)
		var tone := StringName(choice.get("tone", &"normal"))
		var color := Color(0.55, 0.95, 0.9)
		if tone == &"positive":
			color = Color(0.45, 1.0, 0.62)
		elif tone == &"danger":
			color = Color(1.0, 0.42, 0.28)
		elif tone == &"quiet":
			color = Color(0.55, 0.66, 0.68)
		button.add_theme_color_override("font_color", color)
		button.pressed.connect(_on_choice_pressed.bind(StringName(choice.get("id", &"END"))))
		choices.add_child(button)


func _on_choice_pressed(response_id: StringName) -> void:
	if response_id == &"END":
		channel_closed.emit()
		return
	response_selected.emit(response_id)


func _play_entrance() -> void:
	if is_instance_valid(entrance_tween):
		entrance_tween.kill()
	pivot_offset = size * 0.5
	scale = Vector2(0.9, 0.055)
	modulate.a = 0.0
	entrance_tween = create_tween().set_parallel(true)
	entrance_tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	entrance_tween.tween_property(self, "scale", Vector2.ONE, 0.2)
	entrance_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	entrance_tween.tween_property(self, "modulate:a", 1.0, 0.1)


func _animate_end_signal_hover(is_hovered: bool) -> void:
	if not is_instance_valid(end_signal_button):
		return
	end_signal_button.pivot_offset = end_signal_button.size * 0.5
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(
		end_signal_button,
		"scale",
		Vector2.ONE * (1.035 if is_hovered else 1.0),
		0.1
	)
