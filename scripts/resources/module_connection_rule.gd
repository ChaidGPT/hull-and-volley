class_name ModuleConnectionRule
extends Resource

enum CountMode {
	SHARED_EDGES,
	UNIQUE_SECTIONS,
}

@export_category("Identity")
## Short designer-facing name shown when this requirement is not satisfied.
@export var display_name := "CONNECTION REQUIREMENT"
## Longer explanation of why the installed module needs this connection.
@export_multiline var description := ""

@export_category("Accepted Neighbors")
## Grid types that may satisfy this rule, such as REACTOR or MEDICAL. An empty list accepts any type.
@export var neighbor_grid_types: PackedStringArray = []
## Module tags that may satisfy this rule. An empty list does not check installed-module tags.
@export var neighbor_module_tags: PackedStringArray = []
## When enabled, every listed module tag must be present. Otherwise, any one matching tag is enough.
@export var require_all_module_tags := false
## When enabled, a neighboring section must have a module installed; its base grid type alone is insufficient.
@export var require_installed_module := false

@export_category("Connection Counting")
## Shared Edges counts every touching cell edge. Unique Sections counts each neighboring grouped section once.
@export var count_mode := CountMode.UNIQUE_SECTIONS
## Minimum number of qualifying connections needed when counting unique neighboring sections.
@export_range(1, 64, 1) var minimum_connections := 1
## Optional maximum. Use -1 when there is no upper limit.
@export_range(-1, 64, 1) var maximum_connections := -1
## Allows corner-touching sections to count in addition to the normal shared-edge rule.
@export var allow_diagonal_connections := false
## Minimum total shared-edge strength. A full edge is 1.0 and a half-edge staggered contact is 0.5. Set to zero to use only connection count.
@export_range(0.0, 64.0, 0.25) var minimum_contact_strength := 0.0
