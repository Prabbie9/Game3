class_name Respray
extends Storefront
## Respray garage: drive in and stop. For $100 the car is repaired and repainted, and if no officer is watching,
## the police lose track of it (wanted level cleared). Unbranded: the sign just says RESPRAY.

const PRICE := 100
const COLORS := [Color(0.62, 0.08, 0.08), Color(0.08, 0.2, 0.48), Color(0.12, 0.12, 0.13), Color(0.85, 0.85, 0.82),
	Color(0.18, 0.36, 0.2), Color(0.75, 0.55, 0.12), Color(0.35, 0.36, 0.38)]

var _t := 0.0
var _done_for: Vehicle


func _init() -> void:
	garage = true
	sign_text = "RESPRAY"
	sign_color = Color(0.4, 1.0, 0.6)
	wall = "corrugated_iron_02"
	height = 5.2


func _physics_process(delta: float) -> void:
	var p := Game.player as Player
	if p == null or p.vehicle == null or p.state != Player.State.DRIVING:
		_t = 0.0
		return
	var v := p.vehicle
	var inside := rect.grow(-1.0).has_point(Vector2(v.global_position.x, v.global_position.z))
	if not inside:
		_t = 0.0
		if _done_for == v:
			_done_for = null
		return
	if v == _done_for or v.linear_velocity.length() > 0.6:
		return
	_t += delta
	if _t < 1.0:
		return
	_t = 0.0
	_done_for = v
	if Game.money < PRICE:
		Game.message("A respray costs $%d." % PRICE)
		return
	Game.money -= PRICE
	v.damage.repair()
	var c: Color = COLORS[randi() % COLORS.size()]
	while c.is_equal_approx(v.paint) and COLORS.size() > 1:
		c = COLORS[randi() % COLORS.size()]
	v.repaint(c)
	Audio.play_at(Audio.stream("vehicles/door_close.ogg"), v.global_position, -2.0, 0.7)
	var w = Game.world.get("wanted")
	if w and int(w.stars) > 0:
		if float(w.unseen) > 0.5:
			w.clear()
			Game.message("New paint, new plates. The police have lost you.")
		else:
			Game.message("Resprayed, but the police saw you go in.")
	else:
		Game.message("Resprayed and repaired: $%d." % PRICE)
