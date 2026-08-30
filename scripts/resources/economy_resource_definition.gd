class_name EconomyResourceDefinition
extends Resource

@export_category("Identity")
## Stable identifier used by inventories, costs, rewards, and saved games.
@export var resource_id: StringName
## Player-facing singular name, such as Metal or Credit.
@export var display_name := "RESOURCE"
## Short label used where the full name will not fit.
@export var short_name := "RES"
## Description shown in future inventory and construction interfaces.
@export_multiline var description := ""

@export_category("Presentation")
## Color used for this commodity in costs, storage displays, and charts.
@export var display_color := Color.WHITE
## Optional icon. Pixel art imported with nearest filtering will remain crisp.
@export var icon: Texture2D
## Number of decimal places shown in the UI. Most physical resources should use zero.
@export_range(0, 3, 1) var decimal_places := 0

@export_category("Storage")
## Whether this commodity consumes cargo capacity.
@export var uses_storage_capacity := true
## Cargo-space consumed by one unit of this resource.
@export_range(0.0, 1000.0, 0.01) var storage_per_unit := 1.0

