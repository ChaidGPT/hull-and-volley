class_name MenuAudio
extends Node

@export_category("Conversational Menu Sounds")
## Played whenever a contextual CRT menu or submenu powers into view.
@export var menu_open_sound: AudioStream
## Played when a CRT panel powers closed. A reversed version of the open sound works especially well.
@export var menu_close_sound: AudioStream
## Played when the player commits the final choice in a menu flow.
@export var menu_execute_sound: AudioStream
## Played when a menu is dismissed, cancelled, or backed out of without committing.
@export var menu_cancel_sound: AudioStream
## Drydock feedback used when an attempted grid installation is rejected.
@export var builder_denied_sound: AudioStream
## Drydock feedback used when a grid piece locks successfully into the hull.
@export var builder_install_sound: AudioStream
## Shared volume for conversational menu effects.
@export_range(-40.0, 12.0, 0.5) var volume_db := -4.0
## Small random pitch variation keeps repeated interface sounds from becoming fatiguing.
@export_range(0.0, 0.25, 0.01) var pitch_variation := 0.02

var last_close_time_msec := -1000
var suppress_close_until_msec := -1000


func _ready() -> void:
	add_to_group("menu_audio")


func play_open() -> void:
	_play(menu_open_sound)


func play_execute() -> void:
	_play(menu_execute_sound)


func play_cancel() -> void:
	# A deliberate back/cancel sound takes priority over the panel's automatic power-off sound.
	suppress_close_until_msec = Time.get_ticks_msec() + 100
	_play(menu_cancel_sound)


func play_close() -> void:
	var now := Time.get_ticks_msec()
	if now < suppress_close_until_msec or now - last_close_time_msec < 80:
		return
	last_close_time_msec = now
	_play(menu_close_sound)


func play_builder_denied() -> void:
	_play(builder_denied_sound)


func play_grid_install() -> void:
	_play(builder_install_sound)


func _play(stream: AudioStream) -> void:
	if stream == null:
		return
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.volume_db = volume_db
	if pitch_variation > 0.0:
		player.pitch_scale = randf_range(1.0 - pitch_variation, 1.0 + pitch_variation)
	add_child(player)
	player.finished.connect(player.queue_free)
	player.play()
