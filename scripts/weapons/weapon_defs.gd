class_name WeaponDefs
extends RefCounted
## Every weapon's numbers in one place. Damage is per bullet/pellet against 100 health (x3 on the head);
## interval is seconds between shots; spread is radians of cone at rest, plus spread_move when moving and
## bloom per shot (recovers at 1.5 rad/s); recoil kicks the camera up (radians).

## Wheel / cycling order.
const ORDER := ["fists", "knife", "bat", "pistol", "smg", "shotgun", "rifle", "sniper", "launcher", "grenade"]

const DEFS := {
	"fists": {"name": "Fists", "kind": "melee", "damage": 12.0},
	"knife": {"name": "Knife", "kind": "melee", "damage": 45.0, "reach": 1.25, "clips": ["knife_stab", "knife_stab2"],
		"hit_at": 0.42, "model": "knife", "price": 120},
	"bat": {"name": "Bat", "kind": "melee", "damage": 38.0, "reach": 1.6, "clips": ["bat_swing", "bat_swing2"],
		"hit_at": 0.45, "model": "bat", "price": 90, "two_handed_swing": true},
	"pistol": {"name": "Pistol", "kind": "gun", "stance": 0, "model": "pistol", "damage": 34.0, "interval": 0.22,
		"mag": 12, "max": 240, "reload": 1.4, "spread": 0.006, "spread_move": 0.02, "bloom": 0.008, "recoil": 0.035,
		"range": 120.0, "sound": "pistol_%d", "sounds": 2, "volume": -2.0, "reload_sound": "reload_pistol",
		"reload_clip": "pistol_reload", "drive_by": true, "price": 400, "ammo_price": 60, "ammo_pack": 36},
	"smg": {"name": "SMG", "kind": "gun", "stance": 1, "model": "smg", "damage": 18.0, "interval": 0.075, "auto": true,
		"mag": 30, "max": 360, "reload": 1.9, "spread": 0.012, "spread_move": 0.025, "bloom": 0.006, "max_bloom": 0.05,
		"recoil": 0.018, "range": 90.0, "sound": "smg_%d", "sounds": 1, "volume": -3.0, "reload_sound": "reload_rifle",
		"reload_clip": "rifle_reload", "drive_by": true, "price": 1200, "ammo_price": 90, "ammo_pack": 90},
	"shotgun": {"name": "Shotgun", "kind": "gun", "stance": 1, "model": "shotgun", "damage": 14.0, "pellets": 8,
		"interval": 0.85, "mag": 6, "max": 72, "reload": 2.4, "spread": 0.045, "spread_move": 0.02, "bloom": 0.0,
		"recoil": 0.09, "range": 45.0, "sound": "shotgun_%d", "sounds": 1, "volume": 1.0, "reload_sound": "pump",
		"reload_clip": "rifle_reload", "pump": true, "price": 1500, "ammo_price": 80, "ammo_pack": 18},
	"rifle": {"name": "Assault Rifle", "kind": "gun", "stance": 1, "model": "rifle", "damage": 28.0, "interval": 0.1,
		"auto": true, "mag": 30, "max": 300, "reload": 2.2, "spread": 0.004, "spread_move": 0.02, "bloom": 0.005,
		"max_bloom": 0.04, "recoil": 0.025, "range": 200.0, "sound": "rifle_%d", "sounds": 2, "volume": 0.0,
		"reload_sound": "reload_rifle", "reload_clip": "rifle_reload", "price": 2500, "ammo_price": 120, "ammo_pack": 90},
	"sniper": {"name": "Sniper Rifle", "kind": "gun", "stance": 1, "model": "sniper", "damage": 120.0, "interval": 1.1,
		"mag": 10, "max": 60, "reload": 2.6, "spread": 0.0, "spread_move": 0.05, "bloom": 0.0, "recoil": 0.12,
		"range": 600.0, "sound": "sniper_%d", "sounds": 1, "volume": 3.0, "reload_sound": "reload_rifle",
		"reload_clip": "rifle_reload", "zoom": 12.0, "price": 4000, "ammo_price": 150, "ammo_pack": 20},
	"launcher": {"name": "Rocket Launcher", "kind": "launcher", "stance": 1, "model": "launcher", "damage": 260.0,
		"interval": 1.0, "mag": 1, "max": 10, "reload": 2.0, "spread": 0.0, "spread_move": 0.01, "bloom": 0.0,
		"recoil": 0.08, "range": 500.0, "sound": "launcher_%d", "sounds": 1, "volume": 2.0, "reload_sound": "reload_rifle",
		"reload_clip": "rifle_reload", "price": 8000, "ammo_price": 600, "ammo_pack": 2},
	"grenade": {"name": "Grenades", "kind": "throw", "stance": 0, "model": "grenade", "damage": 200.0, "interval": 1.1,
		"mag": 1, "max": 20, "price": 300, "ammo_price": 300, "ammo_pack": 5},
}


static func def_of(id: String) -> Dictionary:
	return DEFS.get(id, DEFS.fists)
