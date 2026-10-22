class_name WeaponMounts
extends RefCounted
## Hand-socket offsets for weapon models (relative to the humanoid RightHand bone), tuned with
## tests/grounding_check screenshots so the grip sits in the palm and the barrel follows the forearm.

## Weapon root (origin = grip, barrel -Z, top +Y) relative to the RightHand bone.
## Hand bone axes (humanoid profile): +Y wrist->fingers, +X towards the thumb/back of the aimed hand.
static var PISTOL_GRIP := Transform3D(Basis(Vector3(0, 0, -1), Vector3(1, 0, 0), Vector3(0, -1, 0)), Vector3(-0.025, 0.075, 0.03))

## Left hand support target relative to the weapon root (origin = grip, barrel -Z, top +Y).
static var PISTOL_SUPPORT := Transform3D(Basis.from_euler(Vector3(0, deg_to_rad(-90), deg_to_rad(-80))), Vector3(-0.04, -0.035, 0.0))
