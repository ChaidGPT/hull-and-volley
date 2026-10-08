class_name CrewRequirementDisplay
extends RefCounted

const STAFFED_ICON := preload("res://assets/sprites/ui/icons/crew.png")
const PENDING_ICON := preload("res://assets/sprites/ui/icons/crew_dark.png")
const SHORTAGE_ICON := preload("res://assets/sprites/ui/icons/crew_alert.png")

const STAFFED_ICON_PATH := "res://assets/sprites/ui/icons/crew.png"
const PENDING_ICON_PATH := "res://assets/sprites/ui/icons/crew_dark.png"
const SHORTAGE_ICON_PATH := "res://assets/sprites/ui/icons/crew_alert.png"


static func bbcode(required_crew: int, operating_crew: int, eventual_crew_available: bool) -> String:
	var result := ""
	for station_index: int in range(maxi(required_crew, 0)):
		var icon_path := STAFFED_ICON_PATH if station_index < operating_crew else (
			PENDING_ICON_PATH if eventual_crew_available else SHORTAGE_ICON_PATH
		)
		result += "[img=16x16]%s[/img]" % icon_path
	return result


static func status_bbcode(required_crew: int, operating_crew: int, eventual_crew_available: bool) -> String:
	var required := maxi(required_crew, 0)
	if required <= 0:
		return ""
	var texture_path := STAFFED_ICON_PATH if operating_crew >= required else (
		PENDING_ICON_PATH if eventual_crew_available else SHORTAGE_ICON_PATH
	)
	return "[img=14x14]%s[/img] [color=#6a9d96]%d/%d[/color]" % [
		texture_path, clampi(operating_crew, 0, required), required,
	]


static func plain_text(required_crew: int, operating_crew: int, eventual_crew_available: bool) -> String:
	var required := maxi(required_crew, 0)
	if required <= 0:
		return "NO CREW STATIONS REQUIRED"
	var staffed := clampi(operating_crew, 0, required)
	var open := required - staffed
	if open <= 0:
		return "%d/%d STATIONS MANNED • FULL WATCH" % [staffed, required]
	if eventual_crew_available:
		return "%d/%d STATIONS MANNED • %d CREW PENDING" % [staffed, required, open]
	return "%d/%d STATIONS MANNED • %d CREW SHORT" % [staffed, required, open]


static func draw_strip(
	canvas: CanvasItem,
	center: Vector2,
	required_crew: int,
	operating_crew: int,
	eventual_crew_available: bool,
	icon_size := 14.0,
	gap := 1.0
) -> Rect2:
	var required := maxi(required_crew, 0)
	if required <= 0:
		return Rect2(center, Vector2.ZERO)
	var total_width := float(required) * icon_size + float(required - 1) * gap
	var strip_rect := Rect2(center - Vector2(total_width, icon_size) * 0.5, Vector2(total_width, icon_size))
	for station_index: int in range(required):
		var texture := STAFFED_ICON if station_index < operating_crew else (
			PENDING_ICON if eventual_crew_available else SHORTAGE_ICON
		)
		var icon_rect := Rect2(
			strip_rect.position + Vector2(float(station_index) * (icon_size + gap), 0.0),
			Vector2.ONE * icon_size
		)
		canvas.draw_texture_rect(texture, icon_rect, false)
	return strip_rect


static func draw_status(
	canvas: CanvasItem,
	center: Vector2,
	required_crew: int,
	operating_crew: int,
	eventual_crew_available: bool,
	icon_size := 10.0
) -> Rect2:
	var required := maxi(required_crew, 0)
	if required <= 0:
		return Rect2(center, Vector2.ZERO)
	var texture := STAFFED_ICON if operating_crew >= required else (
		PENDING_ICON if eventual_crew_available else SHORTAGE_ICON
	)
	var font_size := maxi(roundi(icon_size * 0.78), 7)
	var count_text := str(required)
	var count_width := ThemeDB.fallback_font.get_string_size(count_text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x
	var gap := 2.0
	var total_width := icon_size + gap + count_width
	var status_rect := Rect2(center - Vector2(total_width, icon_size) * 0.5, Vector2(total_width, icon_size))
	var icon_rect := Rect2(status_rect.position, Vector2.ONE * icon_size)
	canvas.draw_texture_rect(texture, icon_rect, false)
	var text_color := Color(0.36, 0.92, 0.72) if operating_crew >= required else (
		Color(0.58, 0.7, 0.68) if eventual_crew_available else Color(1.0, 0.34, 0.22)
	)
	canvas.draw_string(
		ThemeDB.fallback_font,
		Vector2(icon_rect.end.x + gap, status_rect.position.y + icon_size - 1.0),
		count_text,
		HORIZONTAL_ALIGNMENT_LEFT,
		count_width + 1.0,
		font_size,
		text_color
	)
	return status_rect
