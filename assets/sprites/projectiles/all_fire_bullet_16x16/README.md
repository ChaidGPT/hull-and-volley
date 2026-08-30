# Projectile sprite sheets

Each PNG is a 640×400 sheet arranged as 40 columns by 25 rows of 16×16 cells.

The editable projectile templates live in `res://scenes/projectiles/templates/`.
Open a template, select `AnimatedSprite2D`, then add frames from these sheets to:

- `flight` — looping projectile animation
- `spawn` — optional one-shot muzzle/departure animation
- `impact` — optional one-shot impact animation

Author the selected projectile frames facing right. The game rotates the complete
projectile scene to match its actual travel direction. Keep the useful pixels
centered on the 16×16 cell unless the template's Art Offset is deliberately used.

## Live weapon scenes

The small ballistic and station repeater use
`res://scenes/projectiles/traverse_projectile.tscn`. It is already connected to
the animation system and ships with a temporary four-frame `flight` animation.
Open that scene and select `AnimatedSprite2D` to replace its frames with your own.

Keep these animation names so no script changes are needed:

- `flight` loops for the life of the projectile.
- `spawn` is optional; enable **Play Spawn Before Flight** on the scene root to
  play it once before `flight`.
- `impact` is reserved for a projectile-specific impact animation. General hit
  sparks are currently presented by the combat impact effect.

You can drag individual 16×16 cells from any sheet into the SpriteFrames editor,
or use your own imported PNG/sprite sheet. Artwork should face right; aiming and
rotation remain controlled by the projectile simulation.

Impact animation scenes:

- `res://scenes/projectiles/impact_sprite_small.tscn` — 8 frames at 32×32;
  assigned to the light ballistic mount and fighter autocannon.
- `res://scenes/projectiles/impact_sprite_burst.tscn` — 7 frames at 48×48;
  used by medium weapon impacts and physical ship collisions.
- `res://scenes/projectiles/impact_sprite_heavy.tscn` — 16 frames at 64×64;
  assigned to explosive cannon, plasma, and missile impacts.

Select `AnimatedSprite2D` in either scene to edit the non-looping `impact`
animation. Each hit creates one animation and frees it when playback finishes;
there are no debris physics bodies or per-fragment update loops.
