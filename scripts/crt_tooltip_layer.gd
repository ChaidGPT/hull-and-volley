extends CanvasLayer

const TOOLTIP_META := &"_crt_terminal_tooltip"
const MINIMUM_BODY_WIDTH := 150.0
const MAXIMUM_BODY_WIDTH := 320.0
const APPROXIMATE_CHARACTER_WIDTH := 7.8
const HORIZONTAL_PANEL_PADDING := 24.0
const HOVER_DELAY := 0.16
const CHARACTERS_PER_SECOND := 62.0

var panel: PanelContainer
var body: RichTextLabel
var terminal_font: SystemFont
var active_source: Control
var active_text := ""
var hover_time := 0.0
var typed_characters := 0.0
var target_character_count := 0


func _ready() -> void:
	# Tooltips are ship-terminal overlays, so they must remain above every
	# modal console (including the full-screen starter acquisition terminal).
	layer = 300
	process_mode = Node.PROCESS_MODE_ALWAYS
	terminal_font = SystemFont.new()
	terminal_font.font_names = PackedStringArray([
		"Cascadia Mono",
		"Cascadia Code",
		"Consolas",
		"Courier New",
	])
	_build_terminal()


func _process(delta: float) -> void:
	var hovered := get_viewport().gui_get_hovered_control()
	var tooltip := _find_tooltip(hovered)
	var next_source: Control = tooltip.get("source")
	var next_text := String(tooltip.get("text", ""))
	if next_source != active_source:
		_arm_tooltip(next_source, next_text)
	elif is_instance_valid(active_source) and next_text != active_text and not next_text.is_empty():
		_set_terminal_text(next_text, false)
	if not is_instance_valid(active_source) or active_text.is_empty():
		_hide_terminal()
		return
	hover_time += delta
	if hover_time < HOVER_DELAY:
		return
	if not panel.visible:
		panel.visible = true
		_position_terminal()
	typed_characters = minf(
		typed_characters + CHARACTERS_PER_SECOND * delta,
		float(target_character_count)
	)
	body.visible_characters = floori(typed_characters)
	_position_terminal()


func _build_terminal() -> void:
	panel = PanelContainer.new()
	panel.name = "CrtTooltipTerminal"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.visible = false
	panel.custom_minimum_size = Vector2(MINIMUM_BODY_WIDTH + HORIZONTAL_PANEL_PADDING, 0.0)
	add_child(panel)
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.008, 0.025, 0.03, 0.98)
	panel_style.border_width_left = 0
	panel_style.border_width_top = 0
	panel_style.border_width_right = 0
	panel_style.border_width_bottom = 0
	panel_style.corner_radius_top_right = 3
	panel_style.corner_radius_bottom_left = 3
	panel_style.shadow_color = Color(0.0, 0.9, 0.78, 0.2)
	panel_style.shadow_size = 7
	panel.add_theme_stylebox_override("panel", panel_style)

	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 7)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 7)
	panel.add_child(margin)

	var stack := VBoxContainer.new()
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_theme_constant_override("separation", 3)
	margin.add_child(stack)

	var header := Label.new()
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.text = "◆  SHIPNET • LIVE"
	header.add_theme_font_override("font", terminal_font)
	header.add_theme_font_size_override("font_size", 10)
	header.add_theme_color_override("font_color", Color(1.0, 0.68, 0.24, 0.95))
	stack.add_child(header)

	var separator := ColorRect.new()
	separator.mouse_filter = Control.MOUSE_FILTER_IGNORE
	separator.custom_minimum_size = Vector2(0.0, 1.0)
	separator.color = Color(0.16, 0.78, 0.72, 0.72)
	stack.add_child(separator)

	body = RichTextLabel.new()
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.custom_minimum_size = Vector2(MINIMUM_BODY_WIDTH, 20.0)
	body.fit_content = true
	body.scroll_active = false
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_theme_font_override("normal_font", terminal_font)
	body.add_theme_font_size_override("normal_font_size", 13)
	body.add_theme_color_override("default_color", Color(0.64, 1.0, 0.88, 1.0))
	body.add_theme_constant_override("line_separation", 2)
	stack.add_child(body)

func _find_tooltip(hovered: Control) -> Dictionary:
	var candidate := hovered
	while is_instance_valid(candidate):
		var live_text := candidate.tooltip_text.strip_edges()
		if not live_text.is_empty():
			candidate.set_meta(TOOLTIP_META, live_text)
			candidate.tooltip_text = ""
		var stored_text := String(candidate.get_meta(TOOLTIP_META, "")).strip_edges()
		if not stored_text.is_empty():
			return {"source": candidate, "text": stored_text}
		candidate = candidate.get_parent() as Control
	return {}


func _arm_tooltip(source: Control, text: String) -> void:
	active_source = source
	active_text = ""
	hover_time = 0.0
	typed_characters = 0.0
	target_character_count = 0
	panel.visible = false
	if is_instance_valid(source) and not text.is_empty():
		_set_terminal_text(text, true)


func _set_terminal_text(text: String, restart_typing: bool) -> void:
	active_text = text
	var terminal_text := "> " + text.replace("\n", "\n  ")
	body.text = terminal_text
	target_character_count = body.get_total_character_count()
	if restart_typing:
		typed_characters = 0.0
	else:
		typed_characters = minf(typed_characters, float(target_character_count))
	body.visible_characters = floori(typed_characters)
	var longest_line_characters := 0
	for line: String in terminal_text.split("\n"):
		longest_line_characters = maxi(longest_line_characters, line.length())
	var body_width := clampf(
		float(longest_line_characters) * APPROXIMATE_CHARACTER_WIDTH + 8.0,
		MINIMUM_BODY_WIDTH,
		MAXIMUM_BODY_WIDTH
	)
	var estimated_lines := _estimate_line_count(terminal_text, body_width)
	body.custom_minimum_size = Vector2(body_width, maxf(20.0, float(estimated_lines) * 19.0))
	panel.custom_minimum_size = Vector2(body_width + HORIZONTAL_PANEL_PADDING, 0.0)
	panel.reset_size()
	panel.size = panel.get_combined_minimum_size()


func _estimate_line_count(text: String, available_width: float) -> int:
	var characters_per_line := maxi(floori(available_width / APPROXIMATE_CHARACTER_WIDTH), 1)
	var lines := 0
	for line: String in text.split("\n"):
		lines += maxi(ceili(float(line.length()) / float(characters_per_line)), 1)
	return lines


func _position_terminal() -> void:
	if not panel.visible or not is_instance_valid(active_source):
		return
	var viewport_size := get_viewport().get_visible_rect().size
	var panel_size := panel.size
	var source_rect := active_source.get_global_rect()
	var next_position := Vector2(source_rect.end.x + 12.0, source_rect.position.y)
	if next_position.x + panel_size.x > viewport_size.x - 8.0:
		next_position.x = source_rect.position.x - panel_size.x - 12.0
	if next_position.y + panel_size.y > viewport_size.y - 8.0:
		next_position.y = source_rect.position.y - panel_size.y - 12.0
	if next_position.y < 8.0:
		next_position.y = source_rect.end.y + 12.0
	panel.position = Vector2(
		clampf(next_position.x, 8.0, maxf(viewport_size.x - panel_size.x - 8.0, 8.0)),
		clampf(next_position.y, 8.0, maxf(viewport_size.y - panel_size.y - 8.0, 8.0))
	).round()


func _hide_terminal() -> void:
	panel.visible = false
