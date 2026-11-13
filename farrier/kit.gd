extends Node
## Keeps the briefcase in step with the Tools settings: every tool the mod gives (the farrier's kit,
## the horseshoes, the brushes) can be switched off in Settings > Mare Care.
##
##   - Switched on: the tool is given once, when the world loads or the moment it is switched on
##     (if the briefcase has room; otherwise at the next load or the next change).
##   - Switched off: it leaves the briefcase. A tool in your hand goes as soon as you put it away.
##     Tools that were dropped in the world are left where they are.
##
## Which tools were handed out is saved in the world (Mods.state("mare_care").granted_tools), so a
## tool you have used up or thrown away is not given a second time. Worlds saved before this
## existed remember their old flags (granted_farrier, granted_brushes).

const CARE := preload("res://mods/mare_care/farrier/hoof_care.gd")
## Seconds between tries while a switched-off tool is still in a hand.
const RETRY := 1.0

var mod_id := "mare_care"
var _retry_in := 0.0
var _waiting := false


func _ready() -> void:
	Mods.world_ready.connect(func(_game: Node) -> void: reconcile())
	if Mods.game != null: reconcile.call_deferred()


func _process(delta: float) -> void:
	if not _waiting: return
	_retry_in -= delta
	if _retry_in > 0.0: return
	_retry_in = RETRY
	reconcile()


## Gives every switched-on tool that has not been given and takes away every switched-off one.
func reconcile() -> void:
	var game: Node = Mods.game
	if game == null or not is_instance_valid(game): return
	var inventory: Node = game.get("inventory")
	if inventory == null: return
	var store: Variant = inventory.get("inventory")
	if store == null or not store.has_method("grant") or not store.has_method("discard"): return
	var state := Mods.state(mod_id)
	var granted := _granted(state)
	var changed := false
	_waiting = false
	for tool: Array in CARE.TOOLS:
		var id := str(tool[1])
		if CARE.tool_on(str(tool[0])):
			if bool(granted.get(id, false)): continue
			if int(store.grant(id)) >= 0:
				granted[id] = true
				changed = true
			else:
				print("[mare_care] no room for the %s yet; it comes next time" % str(tool[2]).to_lower())
		else:
			store.discard(id)
			if _in_briefcase(store, id):
				_waiting = true   # still in a hand: try again once it is put away
				continue
			if granted.has(id):
				granted.erase(id)
				changed = true
	if changed:
		Mods.save_changed()
		print("[mare_care] briefcase tools updated")


## The saved record of what was given, moving the two old flags into it.
func _granted(state: Dictionary) -> Dictionary:
	if not state.get("granted_tools") is Dictionary:
		var granted := {}
		var legacy := {"granted_farrier": ["hoof_pick", "nippers", "rasp", "hammer", "hoof_oil", "shoe_steel", "shoe_silver", "shoe_gold", "shoe_rainbow"],
			"granted_brushes": ["mane_brush", "coat_brush"]}
		for flag: String in legacy:
			if not bool(state.get(flag, false)): continue
			for key: String in legacy[flag]:
				for tool: Array in CARE.TOOLS:
					if tool[0] == key: granted[str(tool[1])] = true
		state["granted_tools"] = granted
	return state["granted_tools"]


## discard() leaves a unit that is in a hand, and still reports success, so look for what is left.
func _in_briefcase(store: Variant, id: String) -> bool:
	for slot: Variant in store.get("slots"):
		if slot is Dictionary and str(slot.get("id", "")) == id and int(slot.get("count", 0)) > 0: return true
	return false
