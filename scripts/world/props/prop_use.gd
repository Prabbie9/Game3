class_name PropUse
extends Node3D
## "Use" proxy for a street prop near the player (made by PropWorld): vending machine (a drink, $5, a little
## health), ATM (your balance), payphone (with the police after you: pay to have a star dropped), bench (sit).

const DRINK := 5
const FAVOUR := 400   # per star

var kind := ""
var prop_xf := Transform3D()
var mmi: MultiMeshInstance3D
var inst := -1


func _ready() -> void:
	add_to_group("interactables")
	global_position = prop_xf.origin


func _front() -> Vector3:
	var f := prop_xf.basis.z
	f.y = 0.0
	return f.normalized()


func interact_point() -> Vector3:
	return prop_xf.origin + _front() * (0.55 if kind == "bench" else 0.8)


func interact_range() -> float:
	return 1.3


func _wanted() -> Wanted:
	var w := Game.world as World
	return w.wanted if w else null


func interact_prompt(_p: Node) -> String:
	if not is_instance_valid(mmi) or (mmi.get_meta("broken", {}) as Dictionary).has(inst):
		return ""   # knocked over meanwhile
	match kind:
		"vending_machine":
			return "Buy a drink ($%d)" % DRINK
		"atm":
			return "Check your balance"
		"payphone":
			var w := _wanted()
			if w and w.stars > 0:
				return "Call in a favour: lose a star ($%d)" % (FAVOUR * w.stars)
			return ""
		"bench":
			return "Sit down"
	return ""


func interact(p: Node) -> void:
	var pl := p as Player
	match kind:
		"vending_machine":
			if Game.money < DRINK:
				Game.message("Not enough cash for a drink.")
				return
			Game.money -= DRINK
			pl.health = minf(pl.health + 15.0, 100.0)
			pl.health_changed.emit(pl.health, pl.armor)
			Audio.play_at(Audio.stream("world/machine_0.ogg"), prop_xf.origin + Vector3(0, 1.0, 0), -4.0)
			get_tree().create_timer(0.9).timeout.connect(func():
				Audio.play_at(Audio.stream("world/can_drop.ogg"), prop_xf.origin + Vector3(0, 0.4, 0), -6.0, 1.3))
			Game.message("Ice-cold. +15 health.")
		"atm":
			Audio.play_at(Audio.stream("ui/click.ogg"), prop_xf.origin + Vector3(0, 1.2, 0), -8.0)
			Game.message("Balance: $%d. Daily withdrawal limit reached — come back with a card that works." % Game.money)
		"payphone":
			var w := _wanted()
			if w == null or w.stars == 0:
				return
			var price := FAVOUR * w.stars
			Audio.play_at(Audio.stream("world/payphone.ogg"), prop_xf.origin + Vector3(0, 1.4, 0), -6.0)
			if Game.money < price:
				Game.say("Contact", "That kind of favour costs $%d. Call back when you have it." % price)
				return
			Game.money -= price
			w.drop_star()
			Game.say("Contact", "Done. Records got lost. Keep your head down.")
		"bench":
			pl.sit_at(Transform3D(prop_xf.basis.orthonormalized(), prop_xf.origin) * Population.BENCH_SEAT)
