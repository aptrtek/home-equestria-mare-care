extends Node
## The farrier: hoof pick, nippers, rasp, horseshoes, hammer and hoof oil.
##
## How it goes
##   1. Hold any farrier tool and aim at one of her legs: click (desktop) or touch the leg with the
##      tool (VR), and she lifts that hoof for you. A front hoof is raised and curled, a hind hoof
##      lifted back. She holds still while it's up.
##   2. Work the raised hoof with the tool in hand:
##      - Hoof pick: stones and packed dirt sit in the sole while picking is due. Aim at one and
##        hold (desktop), or scrape it with the pick (VR), and it pops out.
##      - Nippers: trim the hoof wall (hold / work it), then the rasp levels it. On a shod hoof
##        the nippers pull the shoe off first.
##      - Horseshoe (one item per style): fit it to a bare, trimmed hoof.
##      - Hammer: drive the four nails, one at a time. A shoe that has worked loose is re-nailed
##        the same way.
##      - Hoof oil: work it in, and the hoof shines for a while.
##   3. Walk away, or aim at another leg, and she puts it down.
## Shoes stay on (shoes.gd) and everything is saved per pony and hoof (hoof_care.gd), which also
## holds how often each job comes due again (settings.cfg, every in-game week by default).
##
## A job done on a hoof that needed it brings you and her closer, as brushing does.

const HOOVES := preload("res://mods/mare_care/farrier/hooves.gd")
const CARE := preload("res://mods/mare_care/farrier/hoof_care.gd")
## The game's one way to move bits (world/mechanics/ledger.gd): she pays from her own purse.
const LEDGER := preload("res://world/mechanics/ledger.gd")
const MODELS := preload("res://mods/mare_care/farrier/models.gd")
const SPARKLE := preload("res://mods/mare_care/brushing/sparkle.gd")
const PLAYER_MOUTH := preload("res://player/player_mouth.gd")
const BODY_HOOVES := preload("res://mods/mare_care/farrier/body_hooves.gd")
const INPUT := preload("res://mods/mare_care/brushing/input_catcher.gd")

## Item id -> tool kind (models.gd KINDS).
const TOOLS := {
	"food:care-hoof-pick": "hoof_pick", "food:care-nippers": "nippers", "food:care-rasp": "rasp",
	"food:care-hammer": "hammer", "food:care-hoof-oil": "hoof_oil",
	"food:care-shoe-steel": "shoe_steel", "food:care-shoe-silver": "shoe_silver",
	"food:care-shoe-gold": "shoe_gold", "food:care-shoe-rainbow": "shoe_rainbow",
	# The spa farrier station's own set, kept in its toolbox (spa_station.gd); they work the same.
	"food:care-spa-hoof-pick": "hoof_pick", "food:care-spa-nippers": "nippers", "food:care-spa-rasp": "rasp",
	"food:care-spa-hammer": "hammer", "food:care-spa-hoof-oil": "hoof_oil", "food:care-spa-shoe-steel": "shoe_steel",
}
## A hoof massage: seconds of slow rubbing on a lifted hoof, empty-handed. Grown mares only.
const MASSAGE_SECONDS := 10.0
## The same hoof gives its massage bonus at most this often (real seconds).
const MASSAGE_COOLDOWN := 600.0
const VR_MASSAGE_REACH := 0.08
const VR_MASSAGE_SPEED := Vector2(0.02, 0.6)
const MASSAGE_THOUGHT := "Anon massaged all four of my hooves. I feel like I'm walking on clouds..."
const MASSAGE_MEMORY := "Anon gave you a slow, soothing hoof massage on all four hooves."
## Licking a lifted hoof clean until it sparkles: seconds of licking, empty-handed with your face
## close to her sole (desktop: the mouth within LICK_REACH of it; VR: your mouth moving slowly
## over it, and each fresh touch is a kiss worth KISS_BOOST). Grown mares only. It cleans the hoof
## (it counts as picking, unpaid) and leaves it sparkling.
const LICK_SECONDS := 12.0
const LICK_REACH := 0.55
const VR_LICK_REACH := 0.07
const VR_LICK_SPEED := Vector2(0.01, 0.5)
const KISS_BOOST := 0.12
const KISS_GAP := 0.5
const LICK_COOLDOWN := 600.0
## How she takes it. Most mares are a little bemused; some love it (the bolder, bossier ones);
## shy ones are flustered. Named mares are set here, every other mare by a fixed roll on her id.
const DOMINANT := ["rainbow_dash", "rarity"]
const SHY := ["fluttershy"]
const LICK_THOUGHTS := {
	"dominant": "Anon licked all four of my hooves until they sparkled, so eager to please. Good. I could get very used to that.",
	"neutral": "Anon licked my hooves clean until they sparkled. Strange... but honestly, kind of sweet.",
	"shy": "Anon licked my hooves until they sparkled! I didn't know where to look... but I didn't want him to stop.",
}
const LICK_MEMORY := "Anon licked all four of your hooves clean until they sparkled."
const DESKTOP_REACH := 2.4
## A leg is aimed at within this of its lower part (sole up LEG_HEIGHT), metres at body scale 1.
const LEG_AIM := 0.06
const LEG_HEIGHT := 0.28
## Aiming this close to a raised hoof's sole works on it (metres at body scale 1).
const HOOF_AIM := 0.11
const PIECE_AIM := 0.035
const NAIL_AIM := 0.03
## VR: a tool tip this close to the sole / a piece / a nail touches it.
const VR_CONTACT := 0.06
const VR_MIN_SPEED := 0.03
const VR_HAMMER_SPEED := 0.6
## Seconds of work for each job.
const PIECE_SECONDS := 0.45
const NIP_SECONDS := 3.5
const RASP_SECONDS := 4.0
const PULL_SECONDS := 1.5
const OIL_SECONDS := 3.0
const HAMMER_REPEAT := 0.35
## She puts the hoof down when the player is this far away, or nothing has happened for this long.
const LEAVE_DISTANCE := 2.6
const IDLE_SECONDS := 30.0
## Stones and dirt in a hoof that needs picking.
const PIECES := Vector2i(3, 5)
## Bits for each job on a hoof that needed it (a new shoe by its style; re-nailing a loose one is
## "reset"). Paid when she puts the hoof down, by the mares who pay (see _pays()).
const PRICES := {"pick": 2, "trim": 4, "oil": 2, "reset": 3, "massage": 3,
	"shoe_steel": 6, "shoe_silver": 9, "shoe_gold": 12, "shoe_rainbow": 10}
## Roughly this share of grown mares pay for hoof care; the rest take it as a favour between
## friends. Which ones is fixed per pony, the same in every world.
const PAYING_SHARE := 65
## Shod on some hooves but not all four, she'd walk lopsided: she waits for the rest. She gives
## up when Anon is this far off, or after this long (real seconds), a little hurt.
const UNEVEN_LEAVE := 9.0
const UNEVEN_PATIENCE := 300.0
const UNEVEN_THOUGHT := "Anon only shod some of my hooves and left. I'm walking all lopsided now..."
const UNEVEN_MEMORY := "Anon put shoes on only some of your hooves and walked off, leaving you lopsided."
const SND := {
	"pick": ["res://world/audio/designed/foley/select_01.wav"],
	"nip": ["res://world/audio/designed/foley/carrot_01.wav", "res://world/audio/designed/foley/carrot_02.wav", "res://world/audio/designed/foley/carrot_03.wav"],
	"rasp": ["res://world/audio/designed/foley/paper_01.wav", "res://world/audio/designed/foley/paper_02.wav", "res://world/audio/designed/foley/paper_03.wav"],
	"tap": ["res://world/audio/designed/foley/metal_01.wav", "res://world/audio/designed/foley/metal_02.wav", "res://world/audio/designed/foley/metal_03.wav"],
	"oil": ["res://world/audio/designed/foley/cloth_01.wav", "res://world/audio/designed/foley/cloth_02.wav", "res://world/audio/designed/foley/cloth_03.wav"],
}
const JOB_NAMES := {"pick": "picked out", "trim": "trimmed", "shoe": "shod", "oil": "oiled"}
const THOUGHTS := {
	"pick": "Anon picked the stones out of my hooves. Walking feels so much better.",
	"trim": "Anon trimmed and rasped my hooves. They feel neat and even now.",
	"shoe": "Anon put new shoes on me. I keep wanting to clip-clop around in them!",
	"oil": "Anon oiled my hooves. They're all glossy and shiny!",
}
const MEMORIES := {
	"pick": "Anon cleaned out your hooves with a hoof pick.",
	"trim": "Anon trimmed and rasped your hooves like a farrier.",
	"shoe": "Anon nailed new %s horseshoes onto your hooves.",
	"oil": "Anon rubbed hoof oil into your hooves until they shone.",
}

## VR licking: whether the mouth is on her sole, and the gap before another kiss counts.
var _mouth_on := false
var _kiss_clock := 0.0
var mod_id := "mare_care"

## The hoof being worked on: {pony, leg, record, pieces: [Node3D], nip, rasp, oil, pull,
## fitting: {style, nails: [bool x4]} or {}, idle, work}. Empty when no hoof is up.
var _session := {}
## A lift asked for while she stands up or puts the other hoof down: {pony, leg, until}.
var _pending := {}
## Ponies waiting for the rest of their shoes: pony -> msec when she started waiting.
var _waiting := {}
var _desk_down := false
var _desk_hit := {}
var _hammer_clock := 0.0
var _sound_clock := 0.0
var _catcher: Node
var _audio: AudioStreamPlayer3D
var _tick := 0.0
var _last_tip := {}
var _centres := {}
var _desk_item: Node3D
var _desk_blend := 0.0
var _desk_clock := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	add_to_group("interaction_hint_sources")
	Mods.world_ready.connect(_on_world)
	Mods.world_closed.connect(func(_g: Node) -> void: _end_session(); _waiting.clear())
	_audio = AudioStreamPlayer3D.new()
	_audio.max_distance = 8.0
	add_child(_audio)
	if Mods.game != null: _on_world(Mods.game)


func _on_world(_game: Node) -> void:
	_place_catcher.call_deferred()


func _place_catcher() -> void:
	if not is_inside_tree(): return
	if not is_instance_valid(_catcher):
		_catcher = INPUT.new()
		_catcher.name = "MareCareFarrierInput"
		_catcher.set("groomer", self)
		get_tree().root.add_child(_catcher)
	get_tree().root.move_child(_catcher, -1)


func _game() -> Node:
	var game: Node = Mods.game
	return game if is_instance_valid(game) and game.is_inside_tree() else null


func _inventory() -> Node:
	var game := _game()
	return game.get("inventory") if game != null else null


# ---------------------------------------------------------------- aiming (desktop)

## The farrier tool in the desktop hand: {item, kind} or {}.
func _desk_tool() -> Dictionary:
	var inventory := _inventory()
	if inventory == null or not bool(inventory.get("_desktop")): return {}
	var held: Dictionary = inventory.get("held")
	if not held.has("desktop") or not is_instance_valid(held.desktop): return {}
	var id := str((held.desktop as Node).get_meta("item_id", ""))
	if not TOOLS.has(id): return {}
	return {"item": held.desktop, "kind": TOOLS[id]}


## What the desktop tool points at:
##   {what: "hoof", pony, leg, point, piece?, nail?} on the raised hoof,
##   {what: "leg", pony, leg, point} on a leg to ask her to lift,
## plus kind and item; {} for nothing.
func _desktop_target() -> Dictionary:
	var tool := _desk_tool()
	if tool.is_empty():
		# Empty-handed on her lifted hoof: a massage.
		if _session.is_empty() or not _empty_hand() or not _can_massage(_session.pony): return {}
		tool = {"item": null, "kind": "massage"}
	var camera: Camera3D = _inventory().get("camera")
	if camera == null: return {}
	if tool.kind == "massage" and CARE.lick_enabled and _mouth_near(camera, LICK_REACH): tool.kind = "lick"
	var origin := camera.global_position
	var forward := -camera.global_basis.z
	var hit := _aim_hoof(origin, forward, tool.kind)
	if hit.is_empty() and tool.kind != "massage" and tool.kind != "lick": hit = _aim_leg(origin, origin + forward * DESKTOP_REACH)
	if hit.is_empty(): return {}
	hit.kind = tool.kind
	hit.item = tool.item
	return hit


func _empty_hand() -> bool:
	var inventory := _inventory()
	if inventory == null or not bool(inventory.get("_desktop")): return false
	var held: Dictionary = inventory.get("held")
	return not held.has("desktop") or not is_instance_valid(held.desktop)


## True when the player's mouth is within `reach` (at her body scale) of her lifted sole.
func _mouth_near(camera: Node3D, reach: float) -> bool:
	if _session.is_empty() or not is_instance_valid(_session.pony) or camera == null: return false
	var sole := HOOVES.sole_point(_session.pony, _session.leg)
	if not sole.is_finite(): return false
	return PLAYER_MOUTH.point(camera).distance_to(sole) <= reach * HOOVES.scale_of(_session.pony)


## Hoof massages are for grown mares, and not at the spa's farrier station (spa care is not
## romance, and the spa has its own massage table).
func _can_massage(pony: Variant) -> bool:
	if not is_instance_valid(pony) or (pony as Node).has_meta("spa_client"): return false
	var identity: Variant = pony.get("identity")
	return identity == null or not bool(identity.get("filly"))


func _aim_hoof(origin: Vector3, forward: Vector3, kind: String) -> Dictionary:
	if _session.is_empty() or not is_instance_valid(_session.pony): return {}
	var pony: Node3D = _session.pony
	var size := HOOVES.scale_of(pony)
	var point := HOOVES.sole_point(pony, _session.leg)
	if not point.is_finite(): return {}
	var along := (point - origin).dot(forward)
	if along < 0.05 or along > DESKTOP_REACH: return {}
	if (origin + forward * along).distance_to(point) > HOOF_AIM * size: return {}
	var hit := {"what": "hoof", "pony": pony, "leg": _session.leg, "point": point}
	if kind == "hoof_pick":
		var best := PIECE_AIM * size
		for piece: Variant in _session.pieces:
			if not is_instance_valid(piece): continue
			var at: Vector3 = (piece as Node3D).global_position
			var gap: float = (origin + forward * (at - origin).dot(forward)).distance_to(at)
			if gap < best: best = gap; hit.piece = piece; hit.point = at
	elif kind == "hammer" and not (_session.fitting as Dictionary).is_empty():
		var best := NAIL_AIM * size
		var nails: Array = _session.fitting.nails
		for i in nails.size():
			if bool(nails[i]): continue
			var at: Vector3 = _shoes().nail_point(pony, _session.leg, i)
			if not at.is_finite(): continue
			var gap: float = (origin + forward * (at - origin).dot(forward)).distance_to(at)
			if gap < best: best = gap; hit.nail = i; hit.point = at
	return hit


## A leg of a pony near the ray: the lower leg, from the sole up to about the knee or hock, as a
## segment the ray must pass close to (the game's touch hulls don't reach down the legs).
## The nearest along the ray wins.
func _aim_leg(from: Vector3, to: Vector3) -> Dictionary:
	var game := _game()
	if game == null: return {}
	var best := {}
	var closest := INF
	for pony: Variant in _ponies(game):
		if (pony as Node3D).global_position.distance_to(from) > 3.5: continue
		var size := HOOVES.scale_of(pony)
		for leg: String in HOOVES.LEGS:
			var sole := HOOVES.sole_point(pony, leg)
			if not sole.is_finite(): continue
			var top := sole + Vector3.UP * LEG_HEIGHT * size
			var pair := Geometry3D.get_closest_points_between_segments(from, to, sole, top)
			if (pair[0] as Vector3).distance_to(pair[1]) > LEG_AIM * size: continue
			var distance := from.distance_to(pair[0])
			if distance < closest: closest = distance; best = {"what": "leg", "pony": pony, "leg": leg, "point": pair[1]}
	return best


## input_catcher.gd: true when the click was ours.
func desktop_click(pressed: bool) -> bool:
	if not pressed:
		var was := _desk_down
		_desk_down = false
		_desk_hit = {}
		return was
	var hit := _desktop_target()
	if hit.is_empty(): return false
	if hit.what == "leg":
		if not _session.is_empty() and _session.pony == hit.pony and _session.leg == hit.leg: return true
		if not _willing(hit.pony): _turn_away(hit.pony); return true
		_ask_lift(hit.pony, hit.leg)
		return true
	_desk_down = true
	_desk_hit = hit
	_hammer_clock = 0.0
	return true


# ---------------------------------------------------------------- hints

func interaction_hint() -> Dictionary:
	var hit := _desktop_target()
	if hit.is_empty(): return {}
	var text := ""
	if hit.what == "leg":
		var record := _record(hit.pony, hit.leg)
		text = "Click · Ask her to lift her %s hoof" % HOOVES.NAMES[hit.leg]
		var needs := _needs(record)
		var bare := _bare_hooves(hit.pony)
		if not bare.is_empty() and bare.size() < 4 and not _shod(record):
			text += "  (she'd like this one shod too, to match)"
		elif not needs.is_empty():
			text += "  (needs: %s)" % ", ".join(needs)
			if hit.pony.has_meta("spa_client"):
				if CARE.pay_enabled: text += " · spa add-on"
			elif _pays(hit.pony): text += " · she pays"
	else:
		text = _hoof_hint(hit)
	return {"target": hit.pony, "text": text, "point": hit.point, "outline": null}


## What the tool in hand will do to the raised hoof, and how far along it is.
func _hoof_hint(hit: Dictionary) -> String:
	var record: Dictionary = _session.record
	var fitting: Dictionary = _session.fitting
	var kind: String = hit.kind
	match kind:
		"hoof_pick":
			if (_session.pieces as Array).is_empty(): return "Hoof pick: this hoof is clean"
			return "Hold click · Pick out %s  %d left" % ["the stone" if hit.has("piece") else "stones and dirt", _pieces_left()]
		"nippers":
			if _shod(record) or not fitting.is_empty():
				return "Hold click · Pull the shoe  %d%%" % int(100.0 * float(_session.pull))
			if float(_session.nip) >= 1.0: return "Trimmed · Now level it with the rasp"
			return "Hold click · Trim the hoof wall  %d%%" % int(100.0 * float(_session.nip))
		"rasp":
			if _shod(record) or not fitting.is_empty(): return "Rasp: pull the shoe first (nippers)"
			if CARE.due(record, "trim") and float(_session.nip) < 1.0: return "Rasp: trim it with the nippers first"
			return "Hold click · Rasp it level  %d%%" % int(100.0 * float(_session.rasp))
		"hammer":
			if fitting.is_empty():
				if _shod(record) and CARE.due(record, "shoe"): return "Click · Reset the loose shoe"
				if _shod(record): return "Hammer: the shoe is on tight"
				return "Hammer: fit a horseshoe first"
			var driven := 0
			for n: bool in fitting.nails:
				if n: driven += 1
			return ("Click · Drive the nail  %d/%d" if hit.has("nail") else "Hammer: aim at a nail  %d/%d") % [driven, MODELS.NAIL_COUNT]
		"hoof_oil":
			return "Hold click · Oil the hoof  %d%%" % int(100.0 * float(_session.oil))
		"lick":
			if float(_session.get("lick", 0.0)) >= 1.0: return "Sparkling clean"
			return "Hold click · Lick her hoof clean  %d%%" % int(100.0 * float(_session.get("lick", 0.0)))
		"massage":
			if float(_session.get("massage", 0.0)) >= 1.0: return "Hoof massaged"
			return "Hold click · Massage her hoof  %d%%" % int(100.0 * float(_session.get("massage", 0.0)))
		_:
			var style := kind.trim_prefix("shoe_")
			if not fitting.is_empty(): return "Nail the shoe on with the hammer"
			if _shod(record): return "Already shod · Pull the shoe with the nippers to change it"
			if CARE.due(record, "trim") and float(_session.rasp) < 1.0: return "Trim and rasp the hoof before shoeing"
			return "Click · Fit the %s shoe" % MODELS.STYLE_NAMES[style].to_lower()
	return ""


func _needs(record: Dictionary) -> Array:
	var out := []
	if CARE.due(record, "pick"): out.append("picking")
	if CARE.due(record, "trim"): out.append("a trim")
	if _shod(record) and CARE.due(record, "shoe"): out.append("a shoe reset")
	if CARE.due(record, "oil"): out.append("oil")
	return out


# ---------------------------------------------------------------- per tick

func _physics_process(delta: float) -> void:
	_animate_desktop_tool(delta)
	_tick += delta
	if _tick < 0.05: return
	var dt := _tick
	_tick = 0.0
	var game := _game()
	if game == null: return
	_try_pending()
	if not _session.is_empty(): _keep_session(dt)
	_keep_waiting()
	if _desk_down: _work_desktop(dt)
	_sense_vr(game, dt)


func _work_desktop(dt: float) -> void:
	var hit := _desktop_target()
	if hit.is_empty() or hit.what != "hoof":
		_desk_hit = {}
		return
	_desk_hit = hit
	_work(hit.kind, hit, dt, true)


## One tick of work with `kind` on the raised hoof. `held`: the button is down (desktop) or the tool
## is moving on the hoof (VR). The hammer drives a nail per press, or per swing in VR.
func _work(kind: String, hit: Dictionary, dt: float, held: bool) -> void:
	if _session.is_empty() or not held: return
	var pony: Node3D = _session.pony
	var record: Dictionary = _session.record
	var fitting: Dictionary = _session.fitting
	_session.idle = 0.0
	match kind:
		"hoof_pick":
			var piece: Variant = hit.get("piece", null)
			if piece == null or not is_instance_valid(piece) or (piece as Node).has_meta("popped"): return
			var t := float((piece as Node).get_meta("work", 0.0)) + dt
			(piece as Node).set_meta("work", t)
			(piece as Node3D).position += Vector3(_rng.randf_range(-1, 1), 0, _rng.randf_range(-1, 1)) * 0.0008
			if t < PIECE_SECONDS: return
			_pop(piece)
			_sound("pick", (piece as Node3D).global_position, -6.0, _rng.randf_range(0.9, 1.2))
			if _pieces_left() == 0: _done("pick")
		"nippers":
			if _shod(record) or not fitting.is_empty():
				_session.pull = minf(1.0, float(_session.pull) + dt / PULL_SECONDS)
				_rhythm("nip", hit.point, 0.4, 0.75)
				if float(_session.pull) >= 1.0: _pull_shoe()
				return
			if float(_session.nip) >= 1.0: return
			_session.nip = minf(1.0, float(_session.nip) + dt / NIP_SECONDS)
			if _rhythm("nip", hit.point, 0.55, 1.35): _chip(hit.point)
		"rasp":
			if _shod(record) or not fitting.is_empty(): return
			if CARE.due(record, "trim") and float(_session.nip) < 1.0: return
			if float(_session.rasp) >= 1.0: return
			_session.rasp = minf(1.0, float(_session.rasp) + dt / RASP_SECONDS)
			_rhythm("rasp", hit.point, 0.3, 1.5)
			if float(_session.rasp) >= 1.0:
				_session.nip = 1.0
				_done("trim")
		"hammer":
			_hammer_clock -= dt
			if _hammer_clock > 0.0: return
			if fitting.is_empty():
				if _shod(record) and CARE.due(record, "shoe"):
					_fit(str(record.get("shoe", "")), true)
				return
			if not hit.has("nail"): return
			_hammer_clock = HAMMER_REPEAT
			fitting.nails[int(hit.nail)] = true
			_shoes().fitting(pony, _session.leg, fitting.style, fitting.nails)
			_sound("tap", hit.point, -4.0, _rng.randf_range(1.05, 1.25))
			var expressions: Variant = pony.get("expressions")
			if expressions != null and expressions.has_method("fluster"): expressions.fluster(0.15)
			if not (fitting.nails as Array).has(false): _shod_done()
		"hoof_oil":
			if float(_session.oil) >= 1.0: return
			_session.oil = minf(1.0, float(_session.oil) + dt / OIL_SECONDS)
			_rhythm("oil", hit.point, 0.6, 1.0)
			if float(_session.oil) >= 1.0:
				_done("oil")
				_hoof_sparkle(pony)
		"lick":
			if not CARE.lick_enabled or float(_session.get("lick", 0.0)) >= 1.0: return
			_lick_progress(float(hit.get("boost", dt / LICK_SECONDS)), hit.point)
		"massage":
			if float(_session.get("massage", 0.0)) >= 1.0: return
			_session.massage = minf(1.0, float(_session.get("massage", 0.0)) + dt / MASSAGE_SECONDS)
			var expressions: Variant = pony.get("expressions")
			if expressions != null and expressions.has_method("touch"):
				expressions.touch("mare_care_hoof", 0.6, lerpf(0.4, 0.85, float(_session.massage)))
			_rhythm("oil", hit.point, 0.9, 0.8)
			if float(_session.massage) >= 1.0: _massaged()
		_:
			if not kind.begins_with("shoe_") or not fitting.is_empty() or _shod(record): return
			if CARE.due(record, "trim") and float(_session.rasp) < 1.0: return
			_fit(kind.trim_prefix("shoe_"), false)
			_desk_down = false


## A sound every `every` seconds of work. True when one played.
func _rhythm(kind: String, at: Vector3, every: float, pitch: float) -> bool:
	_sound_clock -= 0.05
	if _sound_clock > 0.0: return false
	_sound_clock = every * _rng.randf_range(0.85, 1.15)
	_sound(kind, at, -8.0, pitch * _rng.randf_range(0.93, 1.07))
	return true


# ---------------------------------------------------------------- lifting and the session

func _ask_lift(pony: Node3D, leg: String) -> void:
	if not _session.is_empty():
		if _session.pony == pony and _session.leg == leg: return
		_end_session()
	_pending = {"pony": pony, "leg": leg, "until": Time.get_ticks_msec() + 5000}
	_try_pending()


func _try_pending() -> void:
	if _pending.is_empty(): return
	var pony: Variant = _pending.pony
	if not is_instance_valid(pony) or Time.get_ticks_msec() > int(_pending.until):
		_pending = {}
		return
	if not HOOVES.lift(pony, _pending.leg): return
	_begin(pony, _pending.leg)
	_pending = {}


func _begin(pony: Node3D, leg: String) -> void:
	var record := _record(pony, leg)
	_session = {"pony": pony, "leg": leg, "record": record, "pieces": [], "nip": 0.0, "rasp": 0.0,
		"oil": 0.0, "pull": 0.0, "fitting": {}, "idle": 0.0, "done": [], "owed": 0}
	if not CARE.due(record, "trim"): _session.nip = 1.0
	if CARE.due(record, "pick"): _spawn_pieces(pony, leg)
	var camera := _camera()
	if camera != null and pony.has_method("set_action_gaze"): pony.call("set_action_gaze", camera)
	if leg.begins_with("R"):
		var tail: Variant = pony.get("tail_motion")
		if tail != null and "aside_goal" in tail: tail.aside_goal = (-0.5 if leg.ends_with("R") else 0.5)   # away from the lifted hoof (and you)
	var needs := _needs(record)
	print("[mare_care] %s lifts her %s hoof (%s)" % [_pony_id(pony), HOOVES.NAMES[leg], ("needs: " + ", ".join(needs)) if not needs.is_empty() else "nothing due"])


func _keep_session(dt: float) -> void:
	var pony: Variant = _session.pony
	if not is_instance_valid(pony) or not (pony as Node).is_inside_tree():
		_end_session(); return
	_session.idle = float(_session.idle) + dt
	var player := _player_point()
	var far := player.is_finite() and Vector2(player.x - pony.global_position.x, player.z - pony.global_position.z).length() > LEAVE_DISTANCE
	if far or float(_session.idle) > IDLE_SECONDS or HOOVES.raised(pony) != _session.leg or bool(pony.get("sleeping")):
		_end_session()
		return
	var expressions: Variant = pony.get("expressions")
	if expressions != null and expressions.has_method("touch"): expressions.touch("mare_care_hoof", 0.45, 0.25)


func _end_session() -> void:
	if _session.is_empty(): return
	var pony: Variant = _session.pony
	var leg: String = _session.leg
	var owed := int(_session.get("owed", 0))
	for piece: Variant in _session.pieces:
		if is_instance_valid(piece): (piece as Node).queue_free()
	var holder: Variant = _session.get("holder", null)
	if is_instance_valid(holder): (holder as Node).queue_free()
	_session = {}
	_desk_down = false
	if not is_instance_valid(pony): return
	# A shoe that wasn't nailed all the way comes off again.
	_shoes().fitting(pony, leg, "", [])
	HOOVES.lower(pony)
	if owed > 0: _collect(pony, leg, owed)
	var expressions: Variant = pony.get("expressions")
	if expressions != null and expressions.has_method("release_touch"): expressions.release_touch("mare_care_hoof")
	var tail: Variant = pony.get("tail_motion")
	if tail != null and "aside_goal" in tail: tail.aside_goal = 0.0
	var bare := _bare_hooves(pony)
	if not bare.is_empty() and bare.size() < 4 and _willing(pony):
		# Shod on some hooves only: she stays put and waits for the rest (_keep_waiting).
		if not _waiting.has(pony):
			_waiting[pony] = Time.get_ticks_msec()
			_note("%s would like the rest of her hooves shod too" % _display_name(pony))
		HOOVES.hold_still(pony, true)
		return
	_waiting.erase(pony)
	if pony.has_method("set_action_gaze"): pony.call("set_action_gaze", null)


# ---------------------------------------------------------------- the jobs

## Stones and clumps of dirt pressed into the sole, on a node that follows the hoof.
func _spawn_pieces(pony: Node3D, leg: String) -> void:
	var soles := HOOVES.soles(pony)
	var skeleton: Skeleton3D = pony.get("skeleton")
	if not soles.has(leg) or skeleton == null: return
	var row: Dictionary = soles[leg]
	var holder := BoneAttachment3D.new()
	holder.name = "MareCareHoofDirt"
	skeleton.add_child(holder)
	holder.bone_idx = int(row.bone)
	_session.holder = holder
	var frame := Node3D.new()
	frame.transform = row.local
	holder.add_child(frame)
	var width: float = row.width
	for i in _rng.randi_range(PIECES.x, PIECES.y):
		var stone := _rng.randf() < 0.5
		var mesh := SphereMesh.new()
		var r := width * (_rng.randf_range(0.05, 0.08) if stone else _rng.randf_range(0.07, 0.11))
		mesh.radius = r; mesh.height = r * (1.4 if stone else 0.9); mesh.radial_segments = 8; mesh.rings = 4
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		var m := StandardMaterial3D.new()
		m.albedo_color = Color("8b8580").lerp(Color("b5ada3"), _rng.randf()) if stone else Color("5a4030").lerp(Color("7a5a3a"), _rng.randf())
		m.roughness = 0.9
		mi.material_override = m
		var a := _rng.randf() * TAU
		var d := sqrt(_rng.randf()) * 0.28
		# On the floor of the sole: recessed for the hoof models that have a rim.
		mi.position = Vector3(cos(a) * d * width, BODY_HOOVES.floor_height() - r * 0.35, sin(a) * d * float(row.length))
		mi.rotation = Vector3(_rng.randf() * TAU, _rng.randf() * TAU, 0)
		frame.add_child(mi)
		(_session.pieces as Array).append(mi)


func _pieces_left() -> int:
	var n := 0
	for piece: Variant in _session.pieces:
		if is_instance_valid(piece) and not (piece as Node).has_meta("popped"): n += 1
	return n


## A picked piece flicks out and drops to the ground, then is gone.
func _pop(piece: Node3D) -> void:
	piece.set_meta("popped", true)
	(_session.pieces as Array).erase(piece)
	var at := piece.global_transform
	var world := _game()
	piece.get_parent().remove_child(piece)
	world.add_child(piece)
	piece.global_transform = at
	_fall(piece, Vector3(_rng.randf_range(-0.6, 0.6), 1.2, _rng.randf_range(-0.6, 0.6)))


## A little piece thrown from `from` that falls to the ground and fades.
func _fall(piece: Node3D, kick: Vector3) -> void:
	var start := piece.global_position
	var ground := start.y - 1.5
	var space := piece.get_world_3d().direct_space_state
	var ray := space.intersect_ray(PhysicsRayQueryParameters3D.create(start + Vector3.UP * 0.05, start + Vector3.DOWN * 3.0))
	if not ray.is_empty(): ground = float(ray.position.y) + 0.01
	var tween := piece.create_tween()
	var seconds := 0.9
	tween.tween_method(_fall_step.bind(piece, start, kick, ground), 0.0, seconds, seconds)
	tween.tween_interval(2.0)
	tween.tween_callback(piece.queue_free)


func _fall_step(t: float, piece: Node3D, start: Vector3, kick: Vector3, ground: float) -> void:
	if not is_instance_valid(piece): return
	var p := start + Vector3(kick.x, 0, kick.z) * 0.25 * t
	p.y = maxf(ground, start.y + kick.y * 0.25 * t - 4.9 * t * t)
	piece.global_position = p


## A sliver of trimmed hoof wall.
func _chip(at: Vector3) -> void:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.012, 0.003, 0.006) * HOOVES.scale_of(_session.pony)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var m := StandardMaterial3D.new(); m.albedo_color = Color("d9c9a8"); m.roughness = 0.8
	mi.material_override = m
	_game().add_child(mi)
	mi.global_position = at
	mi.rotation = Vector3(_rng.randf() * TAU, _rng.randf() * TAU, 0)
	_fall(mi, Vector3(_rng.randf_range(-0.5, 0.5), 0.5, _rng.randf_range(-0.5, 0.5)))


func _fit(style: String, reset: bool) -> void:
	var nails := []
	for i in MODELS.NAIL_COUNT: nails.append(false)
	_session.fitting = {"style": style, "nails": nails, "reset": reset}
	_shoes().fitting(_session.pony, _session.leg, style, nails)
	_sound("tap", HOOVES.sole_point(_session.pony, _session.leg), -10.0, 0.8)


func _shod_done() -> void:
	var record: Dictionary = _session.record
	var fitting: Dictionary = _session.fitting
	_session.reset_shoe = bool(fitting.get("reset", false))
	record["shoe"] = str(fitting.style)
	_session.fitting = {}
	_shoes().fitting(_session.pony, _session.leg, "", [])
	_done("shoe", str(fitting.style))


func _pull_shoe() -> void:
	var record: Dictionary = _session.record
	record.erase("shoe")
	record.erase("shod")
	_session.fitting = {}
	_session.pull = 0.0
	_shoes().fitting(_session.pony, _session.leg, "", [])
	_sound("tap", HOOVES.sole_point(_session.pony, _session.leg), -6.0, 0.7)
	Mods.save_changed()


## Her legs with no shoe on (saved shoes only, not one being fitted).
func _bare_hooves(pony: Node3D) -> Array:
	var out := []
	var hooves := CARE.hooves(mod_id, _pony_id(pony))
	for leg: String in HOOVES.LEGS:
		if not _shod(hooves.get(leg, {})): out.append(leg)
	return out


## Shoe money waits for the full set (saved, so finishing another day still pays).
func _add_set_owed(pony: Node3D, amount: int) -> void:
	var state := Mods.state(mod_id)
	if not state.get("set_owed") is Dictionary: state["set_owed"] = {}
	var all: Dictionary = state["set_owed"]
	var id := _pony_id(pony)
	all[id] = int(all.get(id, 0)) + amount
	Mods.save_changed()
	if _bare_hooves(pony).is_empty():
		var total := int(all[id])
		all.erase(id)
		_waiting.erase(pony)
		if total > 0: _collect(pony, "", total)


## Ponies waiting for the rest of their shoes: done, or given up on.
func _keep_waiting() -> void:
	var now := Time.get_ticks_msec()
	var player := _player_point()
	for pony: Variant in _waiting.keys():
		if not is_instance_valid(pony):
			_waiting.erase(pony); continue
		if not _session.is_empty() and _session.pony == pony: continue
		# At the spa's farrier station the station decides when she's done waiting.
		if pony.has_meta("spa_client"): continue
		var bare := _bare_hooves(pony)
		if bare.is_empty() or bare.size() == 4:
			_stop_waiting(pony); continue
		var far := player.is_finite() and Vector2(player.x - pony.global_position.x, player.z - pony.global_position.z).length() > UNEVEN_LEAVE
		if far or float(now - int(_waiting[pony])) / 1000.0 > UNEVEN_PATIENCE or bool(pony.get("sleeping")):
			_stop_waiting(pony)
			_left_uneven(pony)
			continue
		# Waiting: she watches you.
		var camera := _camera()
		if camera != null and pony.has_method("set_action_gaze"): pony.call("set_action_gaze", camera)


func _stop_waiting(pony: Node3D) -> void:
	_waiting.erase(pony)
	HOOVES.hold_still(pony, false)
	if pony.has_method("set_action_gaze"): pony.call("set_action_gaze", null)


## Anon walked off with her half shod: a little hurt, and she'll remember it.
func _left_uneven(pony: Node3D) -> void:
	var id := _pony_id(pony)
	var game := _game()
	if id.is_empty() or game == null or game.get("world_context") == null: return
	var context: Node = game.world_context
	var impressions: Variant = context.get("impressions")
	if impressions != null and is_instance_valid(impressions):
		impressions.commit(id, {"friendship": -1, "mood": "sad", "thought": UNEVEN_THOUGHT}, "mare_care_uneven_%d" % Time.get_ticks_usec())
	if context.has_method("record"): context.record("mare_care", UNEVEN_MEMORY, [id, "player"], [id, "player"])
	_note("%s is walking off lopsided, with only some of her hooves shod" % _display_name(pony))
	print("[mare_care] %s gave up waiting for the rest of her shoes" % id)


func _note(text: String) -> void:
	var inventory := _inventory()
	if inventory != null: LEDGER.say(inventory, text)


## True when she pays for hoof care: a grown mare, not married to Anon (hoof care is free for a
## wife), not a spa client, and one of the mares who pay (PAYING_SHARE of them, fixed per pony).
func _pays(pony: Node3D) -> bool:
	if not CARE.pay_enabled or pony.has_meta("spa_client"): return false
	var identity: Variant = pony.get("identity")
	if identity != null and bool(identity.get("filly")): return false
	var id := _pony_id(pony)
	if id.is_empty(): return false
	if _stage(id) == "married": return false
	return absi(hash("mare_care:pays:" + id)) % 100 < PAYING_SHARE


func _stage(id: String) -> String:
	var game := _game()
	var context: Variant = game.get("world_context") if game != null else null
	var bonds: Variant = context.get("player_bonds") if context != null else null
	if bonds == null or not bonds.has_method("record_for"): return ""
	return str(bonds.record_for(id).get("stage", ""))


## She pays for the jobs done on the hoof she just put down, from her own purse. Short of bits,
## she says so and that's that.
func _collect(pony: Node3D, leg: String, amount: int) -> void:
	# At the spa's farrier station every client pays, as a spa add-on.
	var station := _station()
	if station != null and bool(station.call("pay", pony, amount)): return
	if not _pays(pony): return
	var game := _game()
	if game == null: return
	var id := _pony_id(pony)
	var name := _display_name(pony)
	var why := LEDGER.transfer(game, id, LEDGER.PLAYER, amount, "service", {
		"pony": pony,
		"receipt": "mare_care:%s:%s:%d" % [id, leg, Time.get_ticks_usec()],
		"say": ("%s paid you %d bits for hoof care" if not leg.is_empty() else "%s paid you %d bits for her new set of shoes") % [name, amount],
		"text": ("%s paid Anon %d bits for looking after her %s hoof." % [name, amount, HOOVES.NAMES[leg]]) if not leg.is_empty() else "%s paid Anon %d bits for a full set of horseshoes." % [name, amount],
		"witnesses": [id, "player"],
	})
	if why.is_empty():
		print("[mare_care] %s paid %d bits%s" % [id, amount, (" for her %s hoof" % HOOVES.NAMES[leg]) if not leg.is_empty() else " for her set of shoes"])
	else:
		print("[mare_care] %s couldn't pay %d bits: %s" % [id, amount, why])
		var inventory := _inventory()
		if inventory != null: LEDGER.say(inventory, "%s is short of bits today, but thanks you warmly" % name)


func _display_name(pony: Node3D) -> String:
	var identity: Variant = pony.get("identity")
	for key: String in ["display_name", "name"]:
		var value: Variant = identity.get(key) if identity != null else null
		if value is String and not (value as String).is_empty(): return value
	return _pony_id(pony).capitalize()


## A hoof massage finished: a little friendship per hoof (once per MASSAGE_COOLDOWN), and once
## all four have been massaged within the cooldown, more, a thought and a memory.
func _massaged() -> void:
	var pony: Node3D = _session.pony
	var record: Dictionary = _session.record
	var now := Time.get_unix_time_from_system()
	var fresh := now - float(record.get("massaged_at", 0.0)) >= MASSAGE_COOLDOWN
	record["massaged_at"] = now
	Mods.save_changed()
	_sigh_soft(pony)
	print("[mare_care] %s: %s hoof massaged" % [_pony_id(pony), HOOVES.NAMES[_session.leg]])
	if not fresh: return
	_session.owed = int(_session.owed) + int(PRICES.massage)
	var all_four := true
	for leg: String in HOOVES.LEGS:
		var r: Dictionary = CARE.hooves(mod_id, _pony_id(pony)).get(leg, {})
		if now - float(r.get("massaged_at", 0.0)) > MASSAGE_COOLDOWN * 1.5: all_four = false
	_grateful(pony, 2 if all_four else 1, MASSAGE_THOUGHT if all_four else "", MASSAGE_MEMORY if all_four else "", "relaxed")


## Licking moves on by `amount` (0..1): her dirt comes away as it goes, and at 1 the hoof is clean
## and sparkles.
func _lick_progress(amount: float, at: Vector3) -> void:
	var pony: Node3D = _session.pony
	if not _session.has("lick_pieces"): _session.lick_pieces = _pieces_left()
	_session.lick = minf(1.0, float(_session.get("lick", 0.0)) + amount)
	var keep := ceili((1.0 - float(_session.lick)) * int(_session.lick_pieces))
	for piece: Variant in (_session.pieces as Array).duplicate():
		if _pieces_left() <= keep: break
		if is_instance_valid(piece) and not (piece as Node).has_meta("popped"): _pop(piece)
	var expressions: Variant = pony.get("expressions")
	var keen := _disposition(pony) == "dominant"
	if expressions != null and expressions.has_method("touch"):
		expressions.touch("mare_care_hoof", 0.7 if keen else 0.5, lerpf(0.45, 0.95 if keen else 0.8, float(_session.lick)))
	if _disposition(pony) == "shy" and expressions != null and expressions.has_method("fluster") and _rng.randf() < 0.05: expressions.fluster(0.4)
	_rhythm("oil", at, 0.75, 1.4)
	if float(_session.lick) >= 1.0: _licked()


## A hoof licked clean: it counts as picked (unpaid), sparkles, and she reacts in her own way; once all
## four have been licked within the cooldown, a thought and a memory.
func _licked() -> void:
	var pony: Node3D = _session.pony
	var record: Dictionary = _session.record
	if CARE.due(record, "pick"): CARE.mark(mod_id, record, "pick")
	_shoes().refresh(pony)
	_hoof_sparkle(pony)
	var now := Time.get_unix_time_from_system()
	var fresh := now - float(record.get("licked_at", 0.0)) >= LICK_COOLDOWN
	record["licked_at"] = now
	Mods.save_changed()
	_sigh_soft(pony)
	var way := _disposition(pony)
	print("[mare_care] %s: %s hoof licked clean (%s)" % [_pony_id(pony), HOOVES.NAMES[_session.leg], way])
	if not fresh: return
	var all_four := true
	for leg: String in HOOVES.LEGS:
		var r: Dictionary = CARE.hooves(mod_id, _pony_id(pony)).get(leg, {})
		if now - float(r.get("licked_at", 0.0)) > LICK_COOLDOWN * 1.5: all_four = false
	var mood := {"dominant": "happy", "shy": "shy", "neutral": "amused"}[way] as String
	var friendship := (2 if way == "dominant" else 1) + (1 if all_four else 0)
	_grateful(pony, friendship, str(LICK_THOUGHTS[way]) if all_four else "", LICK_MEMORY if all_four else "", mood)


## The lifted hoof sparkles (after oiling or licking), for as long as the settings say.
func _hoof_sparkle(pony: Node3D) -> void:
	if not CARE.hoof_sparkle_on: return
	SPARKLE.of(pony).call("shine_bone", "hoof_" + str(_session.leg), HOOVES.BONES[_session.leg], CARE.hoof_sparkle_minutes * 60.0)


## How she takes having her hooves licked: "dominant" (she loves it), "shy" or "neutral".
func _disposition(pony: Node3D) -> String:
	var id := _pony_id(pony)
	if id in DOMINANT: return "dominant"
	if id in SHY: return "shy"
	var roll := absi(hash("mare_care_lick_" + id)) % 100
	if roll < 30: return "dominant"
	if roll < 55: return "shy"
	return "neutral"


## Friendship, and when `thought` is given her thought, a memory and (care given freely, an adult
## already fond of Anon) a little love.
func _grateful(pony: Node3D, friendship: int, thought: String, memory: String, mood: String) -> void:
	var id := _pony_id(pony)
	var game := _game()
	if id.is_empty() or game == null or game.get("world_context") == null: return
	var context: Node = game.world_context
	var bonds: Variant = context.get("player_bonds")
	var tags := {"friendship": friendship, "mood": mood}
	if not thought.is_empty():
		tags["thought"] = thought
		if not _pays(pony) and not pony.has_meta("spa_client") and bonds != null and bonds.has_method("eligible_for_romance") and bonds.eligible_for_romance(id):
			var stage := str(bonds.record_for(id).get("stage", "acquaintance"))
			if int(bonds.interest(id)) >= 25 or stage in ["dating", "engaged", "married"]: tags["romance"] = 1
	var impressions: Variant = context.get("impressions")
	if impressions != null and is_instance_valid(impressions):
		impressions.commit(id, tags, "mare_care_%d" % Time.get_ticks_usec())
	if not memory.is_empty() and context.has_method("record"): context.record("mare_care", memory, [id, "player"], [id, "player"])
	print("[mare_care] %s: %s" % [id, str(tags)])


func _sigh_soft(pony: Node3D) -> void:
	var boop: Variant = pony.get("boop_node")
	if boop != null and is_instance_valid(boop) and boop.has_method("play_breath"): boop.call("play_breath", -22.0)


func _shod(record: Dictionary) -> bool:
	return not str(record.get("shoe", "")).is_empty()


## A job finished on the raised hoof: saved, and if it was due, she's grateful.
func _done(job: String, style := "") -> void:
	var pony: Node3D = _session.pony
	var record: Dictionary = _session.record
	var was_due := job == "shoe" or CARE.due(record, job)
	if was_due:
		var price_key := job
		if job == "shoe": price_key = "reset" if bool((_session.get("reset_shoe", false))) else "shoe_" + style
		if job == "shoe": _add_set_owed(pony, int(PRICES.get(price_key, 0)))
		else: _session.owed = int(_session.owed) + int(PRICES.get(price_key, 0))
	CARE.mark(mod_id, record, job)
	_shoes().refresh(pony)
	print("[mare_care] %s: %s hoof %s" % [_pony_id(pony), HOOVES.NAMES[_session.leg], JOB_NAMES[job]])
	var expressions: Variant = pony.get("expressions")
	if expressions != null and expressions.has_method("fluster"): expressions.fluster(0.6)
	if was_due: _reward(pony, job, style)


func _reward(pony: Node3D, job: String, style: String) -> void:
	var id := _pony_id(pony)
	var game := _game()
	if id.is_empty() or game == null or game.get("world_context") == null: return
	var context: Node = game.world_context
	var bonds: Variant = context.get("player_bonds")
	var impressions: Variant = context.get("impressions")
	var tags := {"friendship": 1, "mood": "relaxed"}
	# Once all four of her hooves have had this job, she thinks about it and remembers it.
	var all_four := true
	var hooves := CARE.hooves(mod_id, id)
	for leg: String in HOOVES.LEGS:
		var r: Dictionary = hooves.get(leg, {})
		if CARE.due(r, job) or (job == "shoe" and not _shod(r)): all_four = false
	if all_four:
		tags["friendship"] = 2
		tags["thought"] = THOUGHTS[job]
		# Romance only for care given freely: a mare who pays had a service done, not a gesture.
		if not _pays(pony) and not pony.has_meta("spa_client") and bonds != null and bonds.has_method("eligible_for_romance") and bonds.eligible_for_romance(id):
			var stage := str(bonds.record_for(id).get("stage", "acquaintance"))
			if int(bonds.interest(id)) >= 25 or stage in ["dating", "engaged", "married"]:
				tags["romance"] = 1
				tags["mood"] = "happy"
		if context.has_method("record"):
			var memory: String = MEMORIES[job] % MODELS.STYLE_NAMES.get(style, "").to_lower() if job == "shoe" else MEMORIES[job]
			context.record("mare_care", memory, [id, "player"], [id, "player"])
		var boop: Variant = pony.get("boop_node")
		if boop != null and is_instance_valid(boop) and boop.has_method("play_breath"): boop.call("play_breath", -20.0)
	if impressions != null and is_instance_valid(impressions):
		impressions.commit(id, tags, "mare_care_%s_%d" % [job, Time.get_ticks_usec()])
	if bonds != null and bonds.has_method("add_together"): bonds.add_together(id, 6.0)
	print("[mare_care] %s: %s (%s)" % [id, job, str(tags)])


# ---------------------------------------------------------------- VR

## VR: a farrier tool's working end on her leg asks for the hoof; on the raised hoof it works.
func _sense_vr(game: Node, dt: float) -> void:
	var inventory: Node = game.get("inventory")
	if inventory == null or bool(inventory.get("_desktop")): return
	_sense_vr_massage(inventory, dt)
	_sense_vr_lick(dt)
	var held: Dictionary = inventory.get("held")
	for side: String in held.keys():
		if side == "desktop": continue
		var item: Variant = held[side]
		var id := str((item as Node).get_meta("item_id", "")) if is_instance_valid(item) else ""
		if not TOOLS.has(id): _last_tip.erase(side); continue
		var kind: String = TOOLS[id]
		var tip := _tip(item, kind)
		if not tip.is_finite(): continue
		var speed := 0.0
		if _last_tip.has(side): speed = tip.distance_to(_last_tip[side]) / dt
		_last_tip[side] = tip
		var hit := _vr_hoof(tip, kind)
		if not hit.is_empty():
			var moving := speed > VR_MIN_SPEED
			if kind == "hammer": moving = speed > VR_HAMMER_SPEED and hit.has("nail")
			if kind.begins_with("shoe_"): moving = true
			_work(kind, hit, dt, moving)
			if moving and inventory.has_method("_haptic") and _rng.randf() < 0.2: inventory.call("_haptic", side)
			continue
		var leg := _aim_leg(tip + Vector3.UP * 0.05, tip - Vector3.UP * 0.05)
		if not leg.is_empty() and (_session.is_empty() or _session.pony != leg.pony or _session.leg != leg.leg):
			if _pending.is_empty() and _willing(leg.pony): _ask_lift(leg.pony, leg.leg)


## VR: your mouth on her lifted sole. Moving slowly over it licks it; each fresh touch is a kiss.
func _sense_vr_lick(dt: float) -> void:
	_kiss_clock = maxf(0.0, _kiss_clock - dt)
	if _session.is_empty() or not _can_massage(_session.pony) or not CARE.lick_enabled:
		_mouth_on = false
		return
	var camera := get_viewport().get_camera_3d()
	var near := _mouth_near(camera, VR_LICK_REACH)
	if not near:
		_mouth_on = false
		_last_tip.erase("mouth")
		return
	var mouth := PLAYER_MOUTH.point(camera)
	var hit := {"what": "hoof", "pony": _session.pony, "leg": _session.leg, "point": mouth}
	if not _mouth_on and _kiss_clock <= 0.0:
		_kiss_clock = KISS_GAP
		hit.boost = KISS_BOOST
		_work("lick", hit, dt, true)
		hit.erase("boost")
	_mouth_on = true
	var speed := 0.0
	if _last_tip.has("mouth"): speed = mouth.distance_to(_last_tip["mouth"]) / dt
	_last_tip["mouth"] = mouth
	if speed >= VR_LICK_SPEED.x and speed <= VR_LICK_SPEED.y: _work("lick", hit, dt, true)


## VR: an empty hand rubbing slowly on her lifted sole massages it.
func _sense_vr_massage(inventory: Node, dt: float) -> void:
	if _session.is_empty() or not _can_massage(_session.pony) or not inventory.has_method("hand_sample"): return
	var held: Dictionary = inventory.get("held")
	var sole := HOOVES.sole_point(_session.pony, _session.leg)
	if not sole.is_finite(): return
	for side: String in ["left", "right"]:
		if held.has(side) and is_instance_valid(held[side]): continue
		var sample: Dictionary = inventory.call("hand_sample", side)
		if not bool(sample.get("active", false)): continue
		var palm: Vector3 = sample.get("grip_position", Vector3.INF)
		if not palm.is_finite() or palm.distance_to(sole) > VR_MASSAGE_REACH * HOOVES.scale_of(_session.pony): continue
		var key := "palm_" + side
		var speed := 0.0
		if _last_tip.has(key): speed = palm.distance_to(_last_tip[key]) / dt
		_last_tip[key] = palm
		if speed >= VR_MASSAGE_SPEED.x and speed <= VR_MASSAGE_SPEED.y:
			_work("massage", {"what": "hoof", "pony": _session.pony, "leg": _session.leg, "point": palm}, dt, true)
			if _rng.randf() < 0.1 and inventory.has_method("_haptic"): inventory.call("_haptic", side)
		return


func _vr_hoof(tip: Vector3, kind: String) -> Dictionary:
	if _session.is_empty() or not is_instance_valid(_session.pony): return {}
	var pony: Node3D = _session.pony
	var size := HOOVES.scale_of(pony)
	var point := HOOVES.sole_point(pony, _session.leg)
	if not point.is_finite() or point.distance_to(tip) > (VR_CONTACT + HOOF_AIM * 0.5) * size: return {}
	var hit := {"what": "hoof", "pony": pony, "leg": _session.leg, "point": tip}
	if kind == "hoof_pick":
		for piece: Variant in _session.pieces:
			if is_instance_valid(piece) and (piece as Node3D).global_position.distance_to(tip) < VR_CONTACT * size: hit.piece = piece; break
	elif kind == "hammer" and not (_session.fitting as Dictionary).is_empty():
		var nails: Array = _session.fitting.nails
		for i in nails.size():
			if bool(nails[i]): continue
			var at: Vector3 = _shoes().nail_point(pony, _session.leg, i)
			if at.is_finite() and at.distance_to(tip) < VR_CONTACT * size: hit.nail = i; break
	return hit


## The tool's working end in the world (models.gd TIPS, moved by the game's centring of the model).
func _tip(item: Node, kind: String) -> Vector3:
	var model := _visual(item)
	if model == null: return Vector3.INF
	return model.global_transform * (Vector3(MODELS.TIPS[kind]) - _centre(kind))


func _centre(kind: String) -> Vector3:
	if not _centres.has(kind):
		var path := "res://mods/mare_care/farrier/models/%s.scn" % kind
		var centre := Vector3.ZERO
		if ResourceLoader.exists(path):
			var root := (load(path) as PackedScene).instantiate() as Node3D
			var box := AABB()
			var first := true
			for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
				var b: AABB = mi.transform * mi.mesh.get_aabb()
				box = b if first else box.merge(b)
				first = false
			centre = box.get_center()
			root.free()
		_centres[kind] = centre
	return _centres[kind]


# ---------------------------------------------------------------- desktop tool motion

## Desktop: the tool leaves the hand and works the hoof, then comes back.
func _animate_desktop_tool(delta: float) -> void:
	var working: bool = _desk_down and not _desk_hit.is_empty() and _desk_hit.what == "hoof"
	if working and is_instance_valid(_desk_hit.item): _desk_item = _desk_hit.item
	_desk_blend = move_toward(_desk_blend, 1.0 if working else 0.0, delta / 0.18)
	if not is_instance_valid(_desk_item): return
	var model := _visual(_desk_item)
	if model == null: return
	if _desk_blend <= 0.0:
		model.transform = Transform3D.IDENTITY
		_desk_item = null
		return
	if _desk_hit.is_empty() or _session.is_empty(): return
	_desk_clock += delta
	var kind: String = _desk_hit.kind
	if not MODELS.TIPS.has(kind): return
	var camera := _camera()
	if camera == null: return
	var point: Vector3 = _desk_hit.point
	var sole := HOOVES.sole(_session.pony, _session.leg)
	var out := -sole.basis.y.normalized()      # out of the sole
	var across := sole.basis.x.normalized()
	var toward := (point - camera.global_position).normalized()
	var t := _desk_clock
	var offset := Vector3.ZERO
	match kind:
		"hoof_pick": offset = out * (0.012 + 0.012 * absf(sin(t * 9.0))) + across * 0.01 * sin(t * 4.5)
		"nippers": offset = out * 0.004 + across * 0.004 * sin(t * 11.0)
		"rasp": offset = out * 0.006 + across * 0.035 * sin(t * 7.0)
		"hammer": offset = out * (0.006 + 0.05 * pow(absf(sin(t * PI / HAMMER_REPEAT)), 3.0))
		"hoof_oil": offset = out * 0.008 + (across * cos(t * 6.0) + out.cross(across) * sin(t * 6.0)) * 0.015
	# Working end into the hoof: -Z along the view, tool up toward the camera's up.
	var z := -toward
	var y := camera.global_basis.y.normalized()
	if kind == "hammer": z = -out; y = toward.cross(out).normalized().cross(z).normalized() if absf(toward.dot(out)) < 0.95 else y
	var x := y.cross(z).normalized()
	y = z.cross(x).normalized()
	var basis := Basis(x, y, z)
	var tip := Vector3(MODELS.TIPS[kind]) - _centre(kind)
	var goal := Transform3D(basis, point + offset - basis * tip)
	var local_goal := (_desk_item as Node3D).global_transform.affine_inverse() * goal
	model.transform = Transform3D.IDENTITY.interpolate_with(local_goal, _desk_blend)


# ---------------------------------------------------------------- helpers

func _station() -> Node:
	return get_parent().get_node_or_null("SpaStation") if get_parent() != null else null


func _shoes() -> Node:
	return get_parent().get_node("Shoes")


func _record(pony: Node3D, leg: String) -> Dictionary:
	return CARE.hoof(mod_id, _pony_id(pony), leg)


func _pony_id(pony: Node) -> String:
	var id := str(pony.get_meta("relationship_id", ""))
	if id.is_empty():
		var identity: Variant = pony.get("identity")
		if identity != null: id = str(identity.get("id"))
	return id


func _ponies(game: Node) -> Array:
	var out := []
	var mares: Variant = game.get("mares")
	if not mares is Array: return out
	for pony: Variant in mares:
		if is_instance_valid(pony) and (pony as Node3D).is_inside_tree() and (pony as Node3D).is_visible_in_tree() \
				and not bool(pony.get("sleeping")) and pony.get("hoof_hold") != null and (pony.get("hoof_hold") as Object).has_method("kick"):
			out.append(pony)
	return out


## Like brushing: not while she's cross with Anon or asked for space, or asleep, or at the spa.
func _willing(pony: Node3D) -> bool:
	if bool(pony.get("sleeping")): return false
	# A spa client only at the spa's farrier station, where she is there for it.
	if pony.has_meta("spa_client"):
		var station := _station()
		return station != null and bool(station.call("serving", pony))
	var identity: Variant = pony.get("identity")
	if identity != null and bool(identity.get("filly")): return true
	var game := _game()
	var context: Variant = game.get("world_context") if game != null else null
	var bonds: Variant = context.get("player_bonds") if context != null else null
	var id := _pony_id(pony)
	if bonds == null or id.is_empty(): return true
	var record: Dictionary = bonds.record_for(id)
	var space := Time.get_unix_time_from_system() < float(record.get("cooldowns", {}).get("boundary", 0.0))
	return float(bonds.anger(id)) < 35.0 and not space


func _turn_away(pony: Node3D) -> void:
	if pony.has_method("set_action_gaze"): pony.call("set_action_gaze", null)
	print("[mare_care] %s won't lift her hoof right now" % _pony_id(pony))


func _camera() -> Camera3D:
	var inventory := _inventory()
	return inventory.get("camera") if inventory != null else null


func _player_point() -> Vector3:
	var game := _game()
	var player: Variant = game.get("player") if game != null else null
	return (player as Node3D).global_position if player is Node3D else Vector3.INF


func _visual(item: Variant) -> Node3D:
	if not is_instance_valid(item): return null
	var visual: Variant = (item as Node).get_meta("food_visual", null)
	return visual as Node3D if is_instance_valid(visual) else null


func _sound(kind: String, at: Vector3, volume: float, pitch: float) -> void:
	var list: Array = SND[kind]
	var path: String = list[_rng.randi_range(0, list.size() - 1)]
	if not ResourceLoader.exists(path) or not at.is_finite(): return
	var player := AudioStreamPlayer3D.new()
	player.stream = load(path); player.volume_db = volume; player.pitch_scale = pitch; player.max_distance = 6.0
	add_child(player)
	player.global_position = at
	player.finished.connect(player.queue_free)
	player.play()


func _exit_tree() -> void:
	_end_session()
	for pony: Variant in _waiting.keys():
		if is_instance_valid(pony): _stop_waiting(pony)
	_waiting.clear()
	if is_instance_valid(_desk_item):
		var model := _visual(_desk_item)
		if model != null: model.transform = Transform3D.IDENTITY
	if is_instance_valid(_catcher): _catcher.queue_free()
