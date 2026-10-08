extends Control
## Hold-to-open weapon wheel. Icons and operation state come from live mounts.
const GEOMETRY := preload("res://scripts/grid_geometry.gd")
const DIRECTIONS := ["FORWARD", "STARBOARD", "AFT", "PORT"]
const MODES := ["LINKED", "TRIGGER", "SENTRY"]
const MODE_HELP := ["Automatic fire + direct volleys", "Direct volleys only", "Automatic fire only"]
const PAGE_SIZE := 12
var entries: Array[Dictionary] = []
var visible_entries: Array[Dictionary] = []
var hits: Array[Dictionary] = []
var texture_cache: Dictionary = {}
var opened := false
var expanded_direction := -1
var page := 0
var selected := ""
var center := Vector2.ZERO
var radius := 190.0
var saved_time_scale := 1.0
var saved_menu_active := false
var controller_device := -1
var open_device := -1
var last_refresh := 0

func _ready() -> void:
	name = "WeaponsHUD"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	z_index = 90
	visible = false

func _exit_tree() -> void:
	close_wheel()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and opened:
		close_wheel()

func handle_input(event: InputEvent) -> bool:
	var open_key: bool = event is InputEventKey and event.keycode == KEY_R
	var open_button: bool = event is InputEventJoypadButton and event.button_index == JOY_BUTTON_LEFT_STICK
	if open_key or open_button:
		if event is InputEventKey and event.echo:
			return opened
		if event.pressed:
			if not opened:
				open_device = event.device if open_button else -1
				open_wheel()
		elif opened and ((open_key and open_device == -1) or (open_button and event.device == open_device)):
			close_wheel()
		return true
	if not opened:
		return false
	if event is InputEventJoypadMotion:
		controller_device = event.device
	if event is InputEventMouseMotion:
		controller_device = -1
		_point_at(get_local_mouse_position())
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			_back()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_change_page(1)
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_change_page(-1)
		elif event.button_index == MOUSE_BUTTON_LEFT:
			_click_at(get_local_mouse_position())
	if event is InputEventJoypadButton and event.pressed:
		controller_device = event.device
		match event.button_index:
			JOY_BUTTON_A: _accept()
			JOY_BUTTON_B: _back()
			JOY_BUTTON_LEFT_SHOULDER: _change_page(-1)
			JOY_BUTTON_RIGHT_SHOULDER: _change_page(1)
			JOY_BUTTON_DPAD_LEFT: _step(-1)
			JOY_BUTTON_DPAD_RIGHT: _step(1)
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_ESCAPE: _back()
			KEY_ENTER, KEY_SPACE: _accept()
			KEY_LEFT: _step(-1)
			KEY_RIGHT: _step(1)
			KEY_BRACKETLEFT: _change_page(-1)
			KEY_BRACKETRIGHT: _change_page(1)
	queue_redraw()
	return true

func open_wheel() -> void:
	if opened or get_tree().paused or not get_parent().is_visible_in_tree():
		return
	var main := get_tree().current_scene
	if main != null and main.has_method("_controller_primary_panel_open") and main.call("_controller_primary_panel_open"):
		return
	opened = true
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	expanded_direction = -1
	page = 0
	selected = ""
	controller_device = open_device
	saved_time_scale = Engine.time_scale
	Engine.time_scale = saved_time_scale * 0.15
	saved_menu_active = bool(get_parent().get("controller_menu_active"))
	get_parent().call("set_controller_menu_active", true)
	get_parent().call("_set_direct_fire_active", false)
	get_parent().call("_center_camera_on_ship")
	_refresh()
	_update_center()
	queue_redraw()

func close_wheel() -> void:
	if not opened:
		return
	opened = false
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	Engine.time_scale = saved_time_scale
	if is_instance_valid(get_parent()) and get_parent().has_method("set_controller_menu_active"):
		get_parent().call("set_controller_menu_active", saved_menu_active)
	selected = ""

func _process(_delta: float) -> void:
	if not opened:
		return
	if not get_parent().is_visible_in_tree() or (open_device >= 0 and not Input.get_connected_joypads().has(open_device)):
		close_wheel()
		return
	_update_center()
	if Time.get_ticks_msec() - last_refresh >= 100:
		last_refresh = Time.get_ticks_msec()
		_refresh()
	if controller_device >= 0:
		var stick := Vector2(Input.get_joy_axis(controller_device, JOY_AXIS_LEFT_X), Input.get_joy_axis(controller_device, JOY_AXIS_LEFT_Y))
		if stick.length() > 0.35:
			_point_at(center + stick.normalized() * radius)
	queue_redraw()

func _update_center() -> void:
	var view := get_parent()
	var ship := get_tree().get_first_node_in_group("ship_simulation")
	center = size * 0.5
	if ship != null and view.get("world") != null:
		center = view.world.get_transform() * (Vector2(5000, 5000) + Vector2(ship.ship_position))
	radius = clampf(minf(size.x, size.y) * 0.32, 110.0, 210.0)
	# Recentering at open places the wheel around the ship; clamp only near edges.
	var margin := Vector2.ONE * (radius + 40.0)
	center = center.clamp(margin, size - margin)

func _refresh() -> void:
	var player := get_tree().get_first_node_in_group("ship_simulation")
	var combat := get_tree().get_first_node_in_group("combat_simulation")
	if player == null or combat == null or player.ship_layout == null:
		close_wheel()
		return
	entries.clear()
	for room: Resource in player.ship_layout.get("rooms"):
		var weapon := room.get("weapon_definition") as Resource
		if String(room.get("type_name")) != "WEAPONS" or weapon == null:
			continue
		for mount_index: int in range(int(combat.call("_weapon_mount_count", room))):
			var key := "%s#%d" % [room.get("room_id"), mount_index]
			var mount: Resource = combat.call("_weapon_mount_room", room, mount_index)
			var facing := posmod(GEOMETRY.resolved_module_facing(player.ship_layout, mount), 4)
			var room_id: StringName = room.get("room_id")
			var operation: Dictionary = combat.call("get_weapon_operation_state", 0, 0, room_id, mount_index)
			var remaining := float(combat.player_weapon_cooldowns.get(key, 0.0))
			var total := maxf(float(operation.get("reload_total", 0.0)), remaining)
			var status := "READY"
			if player.call("is_module_piece_disabled", room_id, mount_index):
				status = "DAMAGED"
			elif float(player.call("get_room_power_factor", room_id)) <= 0.0:
				status = "NO POWER"
			elif float(player.call("get_weapon_mount_efficiency", room_id, mount_index)) <= 0.0:
				status = "OFFLINE"
			elif float(operation.get("fire_pulse", 0.0)) > 0.0:
				status = "FIRING"
			elif combat.manual_fire_reservations.has(key):
				status = "QUEUED"
			elif remaining > 0.0:
				status = "RELOADING"
			var geometry: Dictionary = combat.call("_get_mount_data", player.ship_layout, mount, Vector2.ZERO, 0.0)
			var direction := Vector2.UP.rotated(facing * PI / 2.0)
			var firing: Dictionary = combat.call("_resolve_firing_mount_for_bearing", geometry, direction, direction, weapon)
			var position_local: Vector2 = firing.get("position", geometry.get("position", Vector2.ZERO))
			entries.append({"key": key, "room": room, "room_id": room_id, "mount_index": mount_index, "weapon": weapon, "facing": facing,
				"status": status, "remaining": remaining, "progress": 1.0 - remaining / total if total > 0.0 else 1.0,
				"bow_order": position_local.dot(Vector2.UP), "mode": int(room.call("get_weapon_fire_mode", mount_index))})
	entries.sort_custom(combat.weapon_firing_order_before)
	_build_visible_entries()

func _members(facing: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry: Dictionary in entries:
		if entry.facing == facing:
			result.append(entry)
	return result

func _build_visible_entries() -> void:
	visible_entries.clear()
	if expanded_direction >= 0:
		var members := _members(expanded_direction)
		page = clampi(page, 0, maxi(ceili(members.size() / float(PAGE_SIZE)) - 1, 0))
		var count := mini(PAGE_SIZE, members.size() - page * PAGE_SIZE)
		for i: int in range(count):
			var entry := members[page * PAGE_SIZE + i].duplicate()
			entry["angle"] = -PI / 2.0 + (i - (count - 1) * 0.5) * minf(TAU / maxf(count, 1), 0.48)
			entry["ordinal"] = page * PAGE_SIZE + i + 1
			visible_entries.append(entry)
	else:
		for facing: int in range(4):
			var members := _members(facing)
			if members.size() > 5:
				var entry := members[0].duplicate()
				entry["key"] = "group:%d" % facing
				entry["group"] = true
				entry["count"] = members.size()
				entry["angle"] = -PI / 2.0 + facing * PI / 2.0
				visible_entries.append(entry)
			else:
				for i: int in range(members.size()):
					var entry := members[i].duplicate()
					entry["angle"] = -PI / 2.0 + facing * PI / 2.0 + (i - (members.size() - 1) * 0.5) * 0.28
					entry["ordinal"] = i + 1
					visible_entries.append(entry)
	if not selected.is_empty() and not visible_entries.any(func(entry: Dictionary) -> bool: return entry.key == selected):
		selected = ""

func _selected_entry() -> Dictionary:
	for entry: Dictionary in entries:
		if entry.key == selected:
			return entry
	return {}

func _point_at(point: Vector2) -> void:
	if controller_device < 0:
		selected = ""
		for entry: Dictionary in visible_entries:
			var icon_point := center + Vector2.from_angle(entry.angle) * radius
			if Rect2(icon_point - Vector2(24, 30), Vector2(48, 60)).has_point(point):
				selected = entry.key
				break
		return
	var offset := point - center
	if offset.length() < 65.0:
		return
	var best := 0.85
	for entry: Dictionary in visible_entries:
		var difference := absf(angle_difference(offset.angle(), entry.angle))
		if difference < best:
			best = difference
			selected = entry.key

func _click_at(point: Vector2) -> void:
	for hit: Dictionary in hits:
		if not hit.rect.has_point(point):
			continue
		if hit.has("page"):
			_change_page(hit.page)
		else:
			selected = hit.key
			_accept()
		return

func _accept() -> void:
	for entry: Dictionary in visible_entries:
		if entry.key != selected:
			continue
		if entry.get("group", false):
			expanded_direction = entry.facing
			page = 0
			selected = ""
			_build_visible_entries()
		else:
			_cycle_mode()
		return

func _back() -> void:
	if expanded_direction >= 0:
		expanded_direction = -1
		page = 0
		selected = ""
		_build_visible_entries()
	else:
		close_wheel()

func _step(amount: int) -> void:
	if not visible_entries.is_empty():
		var index := -1
		for i: int in range(visible_entries.size()):
			if visible_entries[i].key == selected:
				index = i
		selected = visible_entries[posmod(index + amount, visible_entries.size())].key

func _change_page(amount: int) -> void:
	if expanded_direction < 0:
		return
	var pages := maxi(ceili(_members(expanded_direction).size() / float(PAGE_SIZE)), 1)
	page = posmod(page + amount, pages)
	selected = ""
	_build_visible_entries()

func _cycle_mode(amount: int = 1) -> void:
	var entry := _selected_entry()
	if not entry.is_empty():
		_set_mode(posmod(int(entry.room.call("get_weapon_fire_mode", entry.mount_index)) + amount, MODES.size()))

func _set_mode(mode: int) -> void:
	var entry := _selected_entry()
	if entry.is_empty():
		return
	entry.room.call("set_weapon_fire_mode", entry.mount_index, mode)
	get_tree().get_first_node_in_group("ship_simulation").ship_layout.emit_changed()
	_refresh()
	queue_redraw()

func _draw() -> void:
	if not opened:
		return
	hits.clear()
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.015, 0.035, 0.055, 0.65))
	draw_arc(center, radius, 0, TAU, 100, Color("3b596c"), 2.0, true)
	draw_circle(center, 105, Color("10202aee"))
	for entry: Dictionary in visible_entries:
		var point := center + Vector2.from_angle(entry.angle) * radius
		var active: bool = selected == entry.key
		var rect := Rect2(point - Vector2(24, 30), Vector2(48, 60))
		if active:
			draw_arc(point - Vector2(0, 5), 23, 0, TAU, 40, Color("9ee8e3"), 1.0, true)
		var texture := _weapon_texture(entry.weapon)
		if texture != null:
			# Authored turret muzzles point down. Correct to forward, then face the bank.
			draw_set_transform(point - Vector2(0, 5), PI + entry.facing * PI / 2.0)
			var dimensions := texture.get_size()
			var scale_factor := 35.0 / maxf(dimensions.x, dimensions.y)
			draw_texture_rect(texture, Rect2(-dimensions * scale_factor * 0.5, dimensions * scale_factor), false)
			draw_set_transform(Vector2.ZERO)
		else:
			_text(point, "NO ART", 9, Color("a9b5bf"))
		var color := Color("87e2b8") if entry.status == "READY" else Color("ecb767")
		if entry.status in ["DAMAGED", "NO POWER", "OFFLINE"]:
			color = Color("9a9eaa")
		if entry.remaining > 0.0 and not entry.get("group", false):
			draw_rect(Rect2(point + Vector2(-19, 18), Vector2(38, 3)), Color("344554"))
			draw_rect(Rect2(point + Vector2(-19, 18), Vector2(38 * entry.progress, 3)), color)
		hits.append({"rect": rect, "key": entry.key})
	var entry := _selected_entry()
	_text(center + Vector2(0, -62), "WEAPON CONTROL", 12, Color("8cbdcb"))
	if not entry.is_empty():
		_text(center + Vector2(0, -37), String(entry.weapon.get("display_name")), 13, Color.WHITE, 190)
		_text(center + Vector2(0, -17), "%s · #%d" % [DIRECTIONS[entry.facing], entry.mount_index + 1], 11, Color("adc5cf"))
		_text(center + Vector2(0, 3), "%s%s" % [entry.status, " %.1fs" % entry.remaining if entry.remaining > 0 else ""], 12, Color("ecb767"))
		_text(center + Vector2(0, 29), MODES[entry.mode], 12, Color.WHITE)
		_text(center + Vector2(0, 53), MODE_HELP[entry.mode], 10, Color("adc5cf"))
		_text(center + Vector2(0, 76), "A / Click turret to cycle", 10, Color("adc5cf"))
	else:
		_text(center + Vector2(0, -12), "No weapons installed" if entries.is_empty() else "Point to a weapon", 13, Color.WHITE)
		_text(center + Vector2(0, 15), "Left stick / Mouse", 12, Color("adc5cf"))
		_text(center + Vector2(0, 41), "A / Click turret to cycle", 11, Color("adc5cf"))
		if selected.begins_with("group:"):
			var facing := int(selected.trim_prefix("group:"))
			_text(center + Vector2(0, 66), "%d weapons · Select to expand" % _members(facing).size(), 10, Color("ecb767"))
	if expanded_direction >= 0:
		var pages := maxi(ceili(_members(expanded_direction).size() / float(PAGE_SIZE)), 1)
		if pages > 1:
			_text(center + Vector2(0, -radius - 48), "PAGE %d/%d" % [page + 1, pages], 13, Color.WHITE)
		if pages > 1:
			for amount: int in [-1, 1]:
				var rect := Rect2(center + Vector2(amount * 70 - 24, radius + 35), Vector2(48, 25))
				draw_style_box(_tile_style(false), rect)
				_text(rect.get_center() + Vector2(0, 4), "< LB" if amount < 0 else "RB >", 11, Color.WHITE)
				hits.append({"rect": rect, "page": amount})
	_text(Vector2(size.x * 0.5, size.y - 15), "HOLD R / LEFT STICK CLICK · RELEASE TO FLY     |     B / ESC BACK     |     15% TIME", 12, Color("adc5cf"), size.x - 30.0)

func _tile_style(active: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("244758") if active else Color("122632")
	style.border_color = Color("9ee8e3") if active else Color("46606f")
	style.set_border_width_all(2 if active else 1)
	style.set_corner_radius_all(7)
	return style

func _text(point: Vector2, value: String, font_size: int, color: Color, width: float = 260) -> void:
	var font := ThemeDB.fallback_font
	while font_size > 8 and font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > width:
		font_size -= 1
	var text_width := font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	draw_string(font, point - Vector2(text_width * 0.5, 0), value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)

func _weapon_texture(weapon: Resource) -> Texture2D:
	if texture_cache.has(weapon):
		return texture_cache[weapon]
	var scene := weapon.get("mount_visual_scene") as PackedScene
	var texture: Texture2D
	if scene != null:
		var state := scene.get_state()
		for node_index: int in range(state.get_node_count()):
			for property_index: int in range(state.get_node_property_count(node_index)):
				var property := state.get_node_property_name(node_index, property_index)
				if property == &"texture":
					texture = state.get_node_property_value(node_index, property_index) as Texture2D
				elif property == &"sprite_frames":
					var frames := state.get_node_property_value(node_index, property_index) as SpriteFrames
					if frames != null:
						var animation := "idle" if frames.has_animation("idle") else "default"
						if frames.has_animation(animation) and frames.get_frame_count(animation) > 0:
							texture = frames.get_frame_texture(animation, 0)
	if texture != null:
		var pixels := texture.get_image()
		if pixels != null:
			var used := pixels.get_used_rect()
			if used.has_area() and used.size != pixels.get_size():
				var cropped := AtlasTexture.new()
				cropped.atlas = texture
				cropped.region = Rect2(used)
				texture = cropped
	texture_cache[weapon] = texture
	return texture
