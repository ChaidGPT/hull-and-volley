class_name DoorDefinition
extends Resource

@export_category("Door Motion")
## Seconds required for a door to slide completely open or closed.
@export_range(0.05, 5.0, 0.05) var travel_time := 0.45
## Pressure difference above which the automatic safety interlock refuses to open a door.
@export_range(0.0, 1.0, 0.01) var safe_pressure_difference := 0.2
## Automatically prevent opening when the two connected cells have unsafe pressure differences.
@export var automatic_pressure_interlock := false

@export_category("Door Visuals")
## Color of a normally operating door.
@export var closed_color := Color(0.88, 0.62, 0.24, 1.0)
## Color shown while a door is open.
@export var open_color := Color(0.25, 0.9, 0.82, 1.0)
## Color shown when a door is manually locked or pressure-interlocked.
@export var locked_color := Color(1.0, 0.2, 0.14, 1.0)
## Recess/backplate color drawn behind the moving door so open doorways remain readable.
@export var threshold_color := Color(0.42, 1.0, 0.88, 0.7)
## Door width as a fraction of one grid edge.
@export_range(0.1, 0.9, 0.05) var edge_width_fraction := 0.42

@export_category("Door Audio")
## Mechanical cue played at the doorway when its panels begin opening.
@export var opening_sound: AudioStream
## Mechanical cue played at the doorway when its panels begin closing.
@export var closing_sound: AudioStream
## Shared level for close-range interior door sounds.
@export_range(-40.0, 12.0, 0.5) var sound_volume_db := -12.0
## Slight variation keeps busy corridors from sounding like one repeated sample.
@export_range(0.0, 0.25, 0.01) var sound_pitch_variation := 0.025
## Doors are interior detail. Below this tactical zoom they remain silent.
@export_range(0.25, 5.0, 0.05) var minimum_audible_zoom := 2.0
