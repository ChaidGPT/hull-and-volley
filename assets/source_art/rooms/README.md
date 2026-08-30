# Standard room source art

`res://assets/Aesprite/Base_Room.aseprite` is the single authored 160 x 160
source for one standard ship grid. Do not add a second copy here; runtime
exports are always regenerated from that live Aseprite project.

- Runtime exports belong in `assets/sprites/interiors/rooms/standard/`.
- Small, quarter-grid, and elongated room art deliberately remain on their existing fallback visuals.
- The inventory uses its compact symbolic grid pieces and does not use these textures.
- North is bow, east is starboard, south is aft, and west is port.

The Aseprite source is the visual authority. Runtime code only chooses which authored wall/door configuration to display from ship adjacency.

Run `tools/export_base_room_assets.ps1` after changing an overlay that the game
already consumes. The export script deliberately targets the canonical file
above, so later art revisions cannot accidentally come from a stale duplicate.
