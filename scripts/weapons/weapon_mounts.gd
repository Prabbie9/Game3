class_name WeaponMounts
extends RefCounted
## Hand-socket offsets for weapon models (relative to the humanoid RightHand bone), tuned with
## tests/screenshots "weapons" renders so the grip sits in the palm and the barrel follows the forearm.

## Weapon root (origin = grip, barrel -Z, top +Y) relative to the RightHand bone.
## Hand bone axes (humanoid profile): +Y wrist->fingers, +X towards the thumb/back of the aimed hand.
static var PISTOL_GRIP := Transform3D(Basis(Vector3(0, 0, -1), Vector3(1, 0, 0), Vector3(0, -1, 0)), Vector3(-0.025, 0.075, 0.03))

## Left hand support target relative to the weapon root (origin = grip, barrel -Z, top +Y).
static var PISTOL_SUPPORT := Transform3D(Basis.from_euler(Vector3(0, deg_to_rad(-90), deg_to_rad(-80))), Vector3(-0.04, -0.035, 0.0))

## Knife, bat (handle across the fist, blade/barrel out of the thumb side) and grenade (in the palm).
static var BLADE_GRIP := Transform3D(Basis(Vector3(0, 0, -1), Vector3(0, -1, 0), Vector3(-1, 0, 0)), Vector3(0.0, 0.08, 0.03))
## Bat: the same fist grip, the barrel angled 45 degrees toward the fingers so it hangs forward and down.
static var BAT_GRIP := Transform3D(Basis(Vector3(0, 0, -1), Vector3(0.7071, -0.7071, 0), Vector3(-0.7071, -0.7071, 0)), Vector3(0.0, 0.08, 0.03))
static var PALM_GRIP := Transform3D(Basis.IDENTITY, Vector3(0.0, 0.085, 0.045))

## Long guns: right hand on the pistol grip, left hand under the fore-end (palm up, fingers round the left side).
static var LONG_GRIP := Transform3D(Basis(Vector3(0, 0, -1), Vector3(1, 0, 0), Vector3(0, -1, 0)), Vector3(-0.025, 0.075, 0.03))
static var LONG_SUPPORT_BASIS := Basis.from_euler(Vector3(deg_to_rad(10), deg_to_rad(-90), deg_to_rad(-170)))

## model id -> grip transform
static func grip(model: String) -> Transform3D:
	match model:
		"pistol":
			return PISTOL_GRIP
		"knife":
			return BLADE_GRIP
		"bat":
			return BAT_GRIP
		"grenade":
			return PALM_GRIP
	return LONG_GRIP
