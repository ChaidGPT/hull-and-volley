class_name FighterBehaviorDefinition
extends Resource

@export_category("Identity and Visual")
## Player-facing name for this autonomous craft pattern.
@export var display_name := "INTERCEPTOR"
## Editable scene used to draw the craft in the Ship view.
@export var visual_scene: PackedScene
## Tactical Ship-view scale applied to the editable fighter visual scene.
@export_range(0.1, 3.0, 0.05) var visual_scale := 0.5
## Radius of the fighter's physical collision body. Keep this aligned with the visible hull scale.
@export_range(1.0, 30.0, 0.5) var collision_radius := 4.0
## Hull damage the fighter can sustain before being destroyed.
@export_range(1.0, 1000.0, 1.0) var maximum_hull := 12.0

@export_category("Flight Behavior")
## Maximum travel speed relative to the tactical world.
@export_range(10.0, 1000.0, 5.0) var maximum_speed := 145.0
## How quickly the craft can change its velocity.
@export_range(1.0, 1000.0, 5.0) var acceleration := 180.0
## Maximum autonomous turn rate in degrees per second.
@export_range(10.0, 1080.0, 5.0) var turn_speed_degrees := 300.0
## How quickly sideways drift is corrected. Lower values preserve wider, more physical turns.
@export_range(0.0, 20.0, 0.1) var lateral_damping := 2.4
## Gentle overall velocity loss per second. This should remain low so fighters retain momentum.
@export_range(0.0, 5.0, 0.05) var flight_drag := 0.2
## How quickly desired guidance may change. Lower values produce broader, bee-like flowing paths.
@export_range(10.0, 720.0, 5.0) var guidance_turn_degrees := 75.0
## Minimum throttle retained through hard turns so fighters flow through maneuvers instead of stopping.
@export_range(0.0, 1.0, 0.05) var minimum_turn_throttle := 0.42
## Preferred circling distance from the hostile capital ship.
@export_range(20.0, 1000.0, 5.0) var attack_orbit_distance := 125.0
## Preferred maneuvering distance while dogfighting another small craft.
@export_range(10.0, 500.0, 5.0) var dogfight_distance := 55.0
## Distance from the carrier at which a returning craft is recovered into its hangar.
@export_range(5.0, 200.0, 1.0) var recovery_distance := 28.0
## Seconds spent clearing the launch bay before the craft begins its attack run.
@export_range(0.0, 10.0, 0.1) var launch_clearance_time := 0.7
## Straight-line speed maintained while the craft clears its hangar launch corridor.
@export_range(5.0, 500.0, 5.0) var launch_speed := 105.0

@export_category("Attack Run Behavior")
## Distance at which pursuit may become a committed straight attack run.
@export_range(20.0, 1000.0, 5.0) var attack_run_entry_distance := 220.0
## Required nose alignment before committing to an attack run.
@export_range(1.0, 90.0, 1.0) var attack_run_entry_degrees := 18.0
## Maximum time the fighter holds its attack heading before breaking away.
@export_range(0.1, 10.0, 0.1) var attack_run_duration := 1.15
## Time spent flying straight past the target before any new turn is permitted.
@export_range(0.1, 10.0, 0.1) var breakaway_duration := 0.85
## Separation the fighter seeks before beginning another pursuit.
@export_range(20.0, 1000.0, 5.0) var reposition_distance := 190.0
## Safety timeout that prevents a fighter from remaining in reposition forever.
@export_range(0.2, 15.0, 0.1) var reposition_timeout := 2.5
## Seconds of target velocity used to predict an intercept point during pursuit.
@export_range(0.0, 3.0, 0.05) var intercept_lead_seconds := 0.3

@export_category("Obstacle Avoidance")
## Forward collision look-ahead distance used to detect capital hulls and large obstacles.
@export_range(10.0, 500.0, 5.0) var avoidance_lookahead := 190.0
## Angle of the port and starboard avoidance whiskers.
@export_range(5.0, 80.0, 1.0) var avoidance_whisker_degrees := 28.0
## Strength with which detected hull normals bend the fighter's desired guidance.
@export_range(0.0, 5.0, 0.05) var avoidance_strength := 2.4
## Distance at which an attack run against a capital ship must peel away, even if it has not fired.
@export_range(20.0, 500.0, 5.0) var capital_breakaway_distance := 115.0
## Extra clearance added beyond a capital ship's generated hull radius.
@export_range(0.0, 300.0, 5.0) var capital_safety_margin := 65.0
## Multiplier for physical side-thrust during an imminent collision warning.
@export_range(0.0, 5.0, 0.1) var emergency_avoidance_thrust := 1.8

@export_category("Hangar Recovery")
## Distance outside the hangar mouth that must be reached before final docking begins.
@export_range(20.0, 500.0, 5.0) var docking_approach_distance := 90.0
## Radius around the outside staging point that permits transition into the docking corridor.
@export_range(5.0, 100.0, 1.0) var docking_approach_radius := 24.0
## Distance from the hangar mouth at which the craft is considered recovered.
@export_range(2.0, 100.0, 1.0) var docking_capture_distance := 12.0
## Time a fighter keeps a chosen target before reconsidering nearer threats.
@export_range(0.1, 10.0, 0.1) var target_lock_seconds := 1.4

@export_category("Pilot Variation")
## Per-fighter variation applied to speed, acceleration, and maneuver timing so wings do not move in lockstep.
@export_range(0.0, 0.5, 0.01) var behavior_variation := 0.16
## Random thinking time before a fighter may commit to each new attack run.
@export_range(0.0, 3.0, 0.05) var maximum_commit_delay := 0.65

@export_category("Autonomous Weapon")
## Weapon resource fired automatically at the assigned hostile ship.
@export var weapon: Resource
## Maximum angle between the fighter's nose and its target before the fixed gun may fire.
@export_range(0.5, 45.0, 0.5) var firing_alignment_degrees := 6.0
## Additional delay applied between autonomous firing attempts.
@export_range(0.0, 10.0, 0.05) var firing_interval_bonus := 0.0
