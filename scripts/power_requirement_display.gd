class_name PowerRequirementDisplay
extends RefCounted

const LIT_ICON := preload("res://assets/sprites/ui/icons/power.png")
const DARK_ICON := preload("res://assets/sprites/ui/icons/power_dark.png")
const ALERT_ICON := preload("res://assets/sprites/ui/icons/power_alert.png")

const LIT_ICON_PATH := "res://assets/sprites/ui/icons/power.png"
const DARK_ICON_PATH := "res://assets/sprites/ui/icons/power_dark.png"
const ALERT_ICON_PATH := "res://assets/sprites/ui/icons/power_alert.png"


static func bbcode(required_fields: int, supplied_fields: float) -> String:
	var result := ""
	for field_index: int in range(maxi(required_fields, 0)):
		result += "[img=16x16]%s[/img]" % _icon_path_for_field(field_index, supplied_fields)
	return result


static func plain_text(required_fields: int, supplied_fields: float) -> String:
	var required := maxi(required_fields, 0)
	if required <= 0:
		return "NO REACTOR LINK REQUIRED"
	var online := clampi(floori(supplied_fields + 0.001), 0, required)
	var partial := 1 if online < required and supplied_fields > float(online) + 0.001 else 0
	var missing := maxi(required - online - partial, 0)
	var bolts := ""
	for _field_index: int in range(required):
		bolts += "⚡"
	var parts := PackedStringArray()
	if online > 0:
		parts.append("%d LIT" % online)
	if partial > 0:
		parts.append("1 UNSTABLE")
	if missing > 0:
		parts.append("%d DARK" % missing)
	return "%s  %d REACTOR LINK%s • %s" % [
		bolts,
		required,
		"" if required == 1 else "S",
		" • ".join(parts),
	]


static func draw_strip(
	canvas: CanvasItem,
	center: Vector2,
	required_fields: int,
	supplied_fields: float,
	icon_size := 14.0,
	gap := 1.0
) -> Rect2:
	var required := maxi(required_fields, 0)
	if required <= 0:
		return Rect2(center, Vector2.ZERO)
	var total_width := float(required) * icon_size + float(required - 1) * gap
	var strip_rect := Rect2(center - Vector2(total_width, icon_size) * 0.5, Vector2(total_width, icon_size))
	for field_index: int in range(required):
		var icon_rect := Rect2(
			strip_rect.position + Vector2(float(field_index) * (icon_size + gap), 0.0),
			Vector2.ONE * icon_size
		)
		canvas.draw_texture_rect(_icon_for_field(field_index, supplied_fields), icon_rect, false)
	return strip_rect


static func _icon_path_for_field(field_index: int, supplied_fields: float) -> String:
	var delivered_to_link := supplied_fields - float(field_index)
	if delivered_to_link >= 0.999:
		return LIT_ICON_PATH
	if delivered_to_link > 0.001:
		return ALERT_ICON_PATH
	return DARK_ICON_PATH


static func _icon_for_field(field_index: int, supplied_fields: float) -> Texture2D:
	var delivered_to_link := supplied_fields - float(field_index)
	if delivered_to_link >= 0.999:
		return LIT_ICON
	if delivered_to_link > 0.001:
		return ALERT_ICON
	return DARK_ICON
