extends Node
## Aloe and Lotus's spa looks after hooves too, so mares do not depend on the player alone.
##
## The spa (world/minigames/spa/spa_customers.gd) is a venue where live mares come as clients and
## the player's hands do the filing. It announces what happens through its own signals, which this
## listens to; nothing of the game is changed:
##   service_finished(pony_id, "file", bits)   both front hooves were filed at the footbath
##   service_finished(pony_id, "rub", bits)    the back hooves were filed and massaged on the table
##   client_left(pony_id, "Back to the daily routine")   she finished a whole visit
## A finished service counts for the hooves it covered; a finished visit counts for all four, since
## the staff see to a client's hooves whoever held the file. Either way the hooves are cleaned
## out, trimmed and (after a whole visit) oiled, exactly as if the farrier had done it, so the
## upkeep clocks start again. Settings > Mare Care can switch this off.
##
## With the farrier station on (spa_station.gd), the player does the rest of the hoof care there:
## filing then counts as a trim only, and finishing a visit adds nothing more.

const CARE := preload("res://mods/mare_care/farrier/hoof_care.gd")
const HOOVES := preload("res://mods/mare_care/farrier/hooves.gd")
const SPA_PATH := "res://world/minigames/spa/spa_customers.gd"
## The reason the spa gives when a client finishes her visit and goes back to her day.
const VISIT_DONE := "Back to the daily routine"
const SERVICE_LEGS := {"file": ["FL", "FR"], "rub": ["RL", "RR"]}

var mod_id := "mare_care"
var _watching := {}


func _ready() -> void:
	Mods.on_node(SPA_PATH, _on_spa)


func _on_spa(spa: Node) -> void:
	if not is_instance_valid(spa) or _watching.has(spa.get_instance_id()): return
	if not spa.has_signal("service_finished") or not spa.has_signal("client_left"):
		print("[mare_care] the spa has changed: its hoof care is skipped")
		return
	_watching[spa.get_instance_id()] = true
	spa.connect("service_finished", _on_service)
	spa.connect("client_left", _on_left)
	print("[mare_care] listening to the spa for hoof care")


func _on_service(pony_id: String, service: String, _bits: int) -> void:
	if not SERVICE_LEGS.has(service): return
	_clean(pony_id, SERVICE_LEGS[service], false, service == "rub", not CARE.spa_farrier)


func _on_left(pony_id: String, reason: String) -> void:
	if reason != VISIT_DONE or CARE.spa_farrier: return
	_clean(pony_id, HOOVES.LEGS, true, false, true)


## The hooves in `legs` are trimmed (and cleaned out, oiled, and the back ones massaged).
func _clean(pony_id: String, legs: Array, oil: bool, massage: bool, pick: bool) -> void:
	if pony_id.is_empty() or not CARE.spa_care or not CARE.dirt_enabled: return
	var day := CARE.now()
	for leg: String in legs:
		var hoof := CARE.hoof(mod_id, pony_id, leg)
		if pick: hoof["picked"] = day
		hoof["trimmed"] = day
		if oil: hoof["oiled"] = day
		if massage: hoof["massaged_at"] = Time.get_unix_time_from_system()
	Mods.save_changed()
	print("[mare_care] the spa saw to %s's %s hooves" % [pony_id, ", ".join(legs)])
	var shoes := get_parent().get_node_or_null("Shoes") if get_parent() != null else null
	if shoes != null and shoes.has_method("refresh_all"): shoes.call("refresh_all")
