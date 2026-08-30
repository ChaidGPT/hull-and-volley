class_name ShipInventoryEntryDefinition
extends Resource

enum StorageClass {
	SUPPLY,
	CARGO,
}

@export_category("Identity")
## Stable identifier used by inventories, reservations, trade, and saved games.
@export var item_id: StringName
## Player-facing item name.
@export var display_name := "SHIP ITEM"
## Short description shown in logistics menus and tooltips.
@export_multiline var description := ""
@export var icon: Texture2D

@export_category("Storage")
## Supply items can be fetched and used aboard ship; cargo items are inert freight until sold or refined.
@export var storage_class := StorageClass.SUPPLY
## Number of units present when a new game begins.
@export_range(0, 1000000, 1) var starting_quantity := 0
## Storage capacity consumed by one unit.
@export_range(0.01, 1000.0, 0.01) var volume_per_unit := 1.0

@export_category("Operational Payload")
## Optional crew equipment granted when one unit is withdrawn. Empty is safe for materials and ammunition.
@export var equipment_definition: Resource

