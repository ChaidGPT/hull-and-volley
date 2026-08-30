class_name ContractTerminalPanel
extends CrtContextPanel

signal plot_course_requested(pickup_id: int)

var list: VBoxContainer
var status: Label


func _ready() -> void:
	custom_minimum_size = Vector2(470.0, 310.0)
	size = custom_minimum_size
	_build_style()
	_build_interface()


func refresh_contracts() -> void:
	if not is_instance_valid(list):
		return
	for child: Node in list.get_children():
		if child is Control:
			(child as Control).visible = false
		child.queue_free()
	var quests := get_tree().get_first_node_in_group("quest_simulation")
	if not is_instance_valid(quests):
		status.text = "CONTRACT NETWORK OFFLINE"
		return
	var reports: Array = quests.call("get_open_quest_reports")
	status.text = (
		"%d ACTIVE COMMITMENT%s" % [reports.size(), "" if reports.size() == 1 else "S"]
		if not reports.is_empty()
		else "NO ACTIVE COMMITMENTS"
	)
	if reports.is_empty():
		var empty := Label.new()
		empty.custom_minimum_size = Vector2(0.0, 120.0)
		empty.text = "THE BOARD IS CLEAR\n\nHail ships and stations to discover work."
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		empty.add_theme_color_override("font_color", Color(0.38, 0.55, 0.55))
		list.add_child(empty)
		return
	for report_value: Variant in reports.slice(0, 3):
		_add_contract_card(report_value)


func set_terminal_status(message: String) -> void:
	status.text = message


func _build_style() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.004, 0.018, 0.02, 0.985)
	style.border_color = Color(1.0, 0.57, 0.16, 0.9)
	style.set_border_width_all(1)
	style.corner_radius_top_left = 3
	style.corner_radius_bottom_right = 12
	style.shadow_color = Color(1.0, 0.32, 0.05, 0.18)
	style.shadow_size = 9
	add_theme_stylebox_override("panel", style)


func _build_interface() -> void:
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 13)
	margin.add_theme_constant_override("margin_top", 11)
	margin.add_theme_constant_override("margin_right", 13)
	margin.add_theme_constant_override("margin_bottom", 11)
	add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 6)
	margin.add_child(root)
	var title := Label.new()
	title.text = "CONTRACT TELEMETRY"
	title.add_theme_color_override("font_color", Color(1.0, 0.7, 0.25))
	title.add_theme_font_size_override("font_size", 17)
	root.add_child(title)
	status = Label.new()
	status.add_theme_color_override("font_color", Color(0.5, 0.72, 0.7))
	status.add_theme_font_size_override("font_size", 9)
	root.add_child(status)
	root.add_child(HSeparator.new())
	list = VBoxContainer.new()
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 7)
	root.add_child(list)


func _add_contract_card(report: Dictionary) -> void:
	var card := PanelContainer.new()
	var card_style := StyleBoxFlat.new()
	card_style.bg_color = Color(0.02, 0.055, 0.055, 0.94)
	card_style.border_color = Color(0.22, 0.5, 0.47, 0.85)
	card_style.border_width_left = 3
	card_style.border_width_bottom = 1
	card_style.corner_radius_bottom_right = 7
	card.add_theme_stylebox_override("panel", card_style)
	list.add_child(card)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 7)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_bottom", 7)
	card.add_child(margin)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 4)
	margin.add_child(body)
	var header := HBoxContainer.new()
	body.add_child(header)
	var name := Label.new()
	name.text = String(report.get("display_name", "CONTRACT")).to_upper()
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name.add_theme_color_override("font_color", Color(1.0, 0.76, 0.32))
	name.add_theme_font_size_override("font_size", 13)
	header.add_child(name)
	var state := Label.new()
	state.text = String(report.get("state", "ACTIVE"))
	state.add_theme_color_override(
		"font_color",
		Color(0.4, 1.0, 0.62) if StringName(report.get("state", &"")) == &"READY" else Color(0.45, 0.9, 0.9)
	)
	header.add_child(state)
	var objective := Label.new()
	objective.text = String(report.get("objective_label", "OBJECTIVE"))
	objective.add_theme_color_override("font_color", Color(0.7, 0.94, 0.88))
	objective.add_theme_font_size_override("font_size", 10)
	body.add_child(objective)
	var progress_row := HBoxContainer.new()
	progress_row.add_theme_constant_override("separation", 4)
	body.add_child(progress_row)
	var count := maxi(int(report.get("objective_count", 1)), 1)
	var progress := int(report.get("progress", 0))
	for segment_index: int in range(count):
		var segment := ColorRect.new()
		segment.custom_minimum_size = Vector2(22.0, 7.0)
		segment.color = Color(0.28, 1.0, 0.63) if segment_index < progress else Color(0.07, 0.22, 0.2)
		progress_row.add_child(segment)
	var giver := Label.new()
	giver.text = "ISSUED BY • %s" % String(report.get("giver_name", "UNKNOWN CONTACT")).to_upper()
	giver.add_theme_color_override("font_color", Color(0.38, 0.62, 0.61))
	giver.add_theme_font_size_override("font_size", 9)
	body.add_child(giver)
	var pickup_id := int(report.get("objective_pickup_id", -1))
	var quest_state := StringName(report.get("state", &"ACTIVE"))
	if quest_state == &"READY":
		var ready := Label.new()
		ready.text = "✓  OBJECTIVE SECURED • HAIL ISSUER TO TRANSMIT"
		ready.add_theme_color_override("font_color", Color(0.42, 1.0, 0.62))
		body.add_child(ready)
	elif pickup_id >= 0:
		var course := Button.new()
		course.text = "◈  PLOT SALVAGE BEACON COURSE"
		course.tooltip_text = "CLICK • SET THE CONTRACT OBJECTIVE AS FLIGHT DESTINATION"
		course.add_theme_color_override("font_color", Color(1.0, 0.68, 0.25))
		course.pressed.connect(func() -> void: plot_course_requested.emit(pickup_id))
		body.add_child(course)
