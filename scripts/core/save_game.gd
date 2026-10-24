class_name SaveGame
extends RefCounted
## Save slots (user://save_1..3.json): where the player stands, health and armour, money, weapons and ammo,
## career stats, the time of day and the weather. Saving needs the player on foot with no wanted level (the
## police and the car you sit in aren't part of a save). Loading reloads the world and puts everything back
## (Game.pending_load is picked up by World once the player exists).

const SLOTS := 3
const VERSION := 1


static func path(slot: int) -> String:
	return "user://save_%d.json" % slot


## Why the game can't be saved right now ("" when it can).
static func blocked_reason() -> String:
	var w := Game.world as World
	var p := Game.player as Player
	if w == null or p == null:
		return "Nothing to save."
	if w.wanted and w.wanted.stars > 0:
		return "You can't save while the police are after you."
	if p.vehicle != null or p.state != Player.State.ON_FOOT:
		return "Get out of the vehicle to save."
	return ""


static func save(slot: int) -> bool:
	var w := Game.world as World
	var p := Game.player as Player
	if blocked_reason() != "":
		return false
	var ammo := {}
	for id: String in p.weapon.ammo:
		ammo[id] = (p.weapon.ammo[id] as Array).duplicate()
	var data := {
		"version": VERSION,
		"saved_at": Time.get_unix_time_from_system(),
		"place": district_at(p.global_position),
		"player": {"pos": [p.global_position.x, p.global_position.y, p.global_position.z], "yaw": p.rotation.y,
			"health": p.health, "armor": p.armor},
		"money": Game.money,
		"weapons": {"owned": p.weapon.owned.keys(), "ammo": ammo, "current": p.weapon.current},
		"stats": Game.stats.duplicate(),
		"collected": Game.collected.duplicate(),
		"world": {"time": w.time_of_day, "weather": w.weather.kind if w.weather else 0},
	}
	var f := FileAccess.open(path(slot), FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	return true


static func load_data(slot: int) -> Dictionary:
	if not FileAccess.file_exists(path(slot)):
		return {}
	var f := FileAccess.open(path(slot), FileAccess.READ)
	if f == null:
		return {}
	var d = JSON.parse_string(f.get_as_text())
	return d if d is Dictionary and int(d.get("version", 0)) >= 1 else {}


## For the load / save lists: "Downtown · $1,240 · 1h 05m · 24 Oct 14:02", or "" for an empty slot.
static func describe(slot: int) -> String:
	var d := load_data(slot)
	if d.is_empty():
		return ""
	var played := float((d.get("stats", {}) as Dictionary).get("time_played", 0.0))
	var when := Time.get_datetime_dict_from_unix_time(int(d.get("saved_at", 0)) + _tz_offset())
	var months := ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
	return "%s  ·  $%d  ·  %dh %02dm played  ·  %d %s %02d:%02d" % [d.get("place", "Port Solano"), int(d.get("money", 0)),
		int(played / 3600.0), int(fmod(played, 3600.0) / 60.0), when.day, months[int(when.month) - 1], when.hour, when.minute]


static func _tz_offset() -> int:
	return int(Time.get_time_zone_from_system().get("bias", 0)) * 60


static func latest_slot() -> int:
	var best := -1
	var t := -1.0
	for s in range(1, SLOTS + 1):
		var d := load_data(s)
		if not d.is_empty() and float(d.get("saved_at", 0)) > t:
			t = float(d.saved_at)
			best = s
	return best


## Put a loaded save into the running world (called by World once the player is set up).
static func apply(d: Dictionary) -> void:
	var w := Game.world as World
	var p := Game.player as Player
	if w == null or p == null or d.is_empty():
		return
	Game.loading = true
	Game.money = int(d.get("money", Game.money))
	Game.loading = false
	Game.stats = (d.get("stats", {}) as Dictionary).duplicate()
	Game.collected = []
	for id in d.get("collected", []):
		Game.collected.append(int(id))
	if w.collectibles:
		w.collectibles.refresh()
	var wd: Dictionary = d.get("world", {})
	w.time_of_day = float(wd.get("time", w.time_of_day))
	if w.weather:
		w.weather.set_weather(int(wd.get("weather", 0)), true)
	var pd: Dictionary = d.get("player", {})
	var pos: Array = pd.get("pos", [])
	if pos.size() == 3:
		p._respawn(Transform3D(Basis(Vector3.UP, float(pd.get("yaw", 0.0))), Vector3(pos[0], pos[1] + 0.1, pos[2])), "")
	p.health = float(pd.get("health", 100.0))
	p.armor = float(pd.get("armor", 0.0))
	p.health_changed.emit(p.health, p.armor)
	var wp: Dictionary = d.get("weapons", {})
	p.weapon.confiscate()
	var ammo: Dictionary = wp.get("ammo", {})
	for id: String in wp.get("owned", []):
		if id == "fists" or not WeaponDefs.DEFS.has(id):
			continue
		p.weapon.give(id, 0)
		if ammo.has(id):
			p.weapon.ammo[id] = [int(ammo[id][0]), int(ammo[id][1])]
	p.weapon.select(String(wp.get("current", "fists")) if p.weapon.has(String(wp.get("current", "fists"))) else "fists")
	Game.message("Game loaded.")


static func district_at(pos: Vector3) -> String:
	var best := INF
	var name := "Port Solano"
	for d: Dictionary in WorldData.get_data().districts:
		var dd := Vector2(pos.x - float(d.x), pos.z - float(d.z)).length()
		if dd < best:
			best = dd
			name = String(d.name)
	return name
