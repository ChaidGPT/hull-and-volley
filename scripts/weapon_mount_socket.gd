class_name WeaponMountSocket
extends RefCounted

## Shared contract between the authored 160px weapon room and every weapon
## mount scene. The enlarged socket remains centered at source pixel (80, 96).
## Weapon scenes place the center of their round turret base at their root /
## TurretBase marker and rooms place that marker here.
const STANDARD_ROOM_SOURCE_SIZE := Vector2(160.0, 160.0)
const STANDARD_ROOM_TURRET_SOCKET := Vector2(80.0, 96.0)


## The source room faces south/down. Installed facing zero is north/up, hence
## the half turn before applying the saved N/E/S/W quarter rotation.
static func standard_room_socket_position(room_rect: Rect2, facing_quarters: int) -> Vector2:
	var source_offset := STANDARD_ROOM_TURRET_SOCKET - STANDARD_ROOM_SOURCE_SIZE * 0.5
	var scaled_offset := Vector2(
		source_offset.x * room_rect.size.x / STANDARD_ROOM_SOURCE_SIZE.x,
		source_offset.y * room_rect.size.y / STANDARD_ROOM_SOURCE_SIZE.y
	)
	var installed_rotation := PI + float(posmod(facing_quarters, 4)) * PI * 0.5
	return room_rect.get_center() + scaled_offset.rotated(installed_rotation)
