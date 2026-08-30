class_name CrewVisualDefinition
extends Resource

@export_category("Crew Dot Visual")
## Radius of a crew dot in Crew-view pixels.
@export_range(3.0, 40.0, 1.0) var dot_radius := 13.0
## Radius of the same live crew dots when viewed from Settlement scale.
@export_range(0.5, 12.0, 0.1) var settlement_dot_radius := 1.85
## Outline width used to keep crew readable over room colors.
@export_range(1.0, 10.0, 0.5) var outline_width := 4.0
## Base crew color; individual members receive a small deterministic variation.
@export var base_color := Color(0.48, 0.96, 0.86, 1.0)
## Color used around the selected crew member.
@export var selection_color := Color(1.0, 0.72, 0.24, 1.0)

@export_category("Crew Sprite Visual")
## Horizontal Aseprite-exported animation sheet used by the close Crew view.
@export var sprite_sheet: Texture2D
## Untrimmed size of each frame in the horizontal animation sheet.
@export var sprite_frame_size := Vector2i(64, 64)
## Display scale applied to each frame in Crew-view pixels.
@export_range(0.25, 4.0, 0.05) var sprite_scale := 2.0
## The authored resting frame is much taller than the bed mattress. Scale only
## that pose down so walking and working crew keep their readable size while a
## sleeper fits from the pillow to the foot of the bed.
@export_range(0.25, 1.0, 0.01) var rest_sprite_scale_multiplier := 0.68
## Local resting-pose alignment as a fraction of the final sprite size. The
## source frame includes raised hands above the head, so the whole figure sits
## slightly farther toward the foot of the mattress without being distorted.
@export var rest_sprite_offset_ratio := Vector2(0.0, 0.16)
## Logical clearance kept between a crew member's center and solid room walls.
## Door crossings temporarily use the doorway center, but parking and work
## positions always remain inside this inset walkable area.
@export_range(0.05, 0.48, 0.01) var collision_radius_cells := 0.44

@export_category("Crew Routine")
## Number of usable crew work positions generated in every occupied grid cell.
@export_range(1, 4, 1) var work_slots_per_cell := 4
## Movement speed measured in grid cells per second.
@export_range(0.1, 4.0, 0.05) var movement_speed_cells := 0.65
## Shortest idle pause after reaching a work position.
@export_range(0.0, 30.0, 0.25) var minimum_idle_seconds := 2.0
## Longest idle pause after reaching a work position.
@export_range(0.0, 60.0, 0.25) var maximum_idle_seconds := 9.0
