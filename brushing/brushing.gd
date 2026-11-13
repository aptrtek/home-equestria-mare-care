extends Node
## Mane, tail and coat brushing. Borrowed from modChad's Grooming mod
## (github.com/modChad/home-equestria-mods, grooming/main.gd), with wing preening left out (that
## stays the Grooming mod's own) and one addition: a finished mane or tail brushing leaves the
## hair sparkling for a while (sparkle.gd).
##
## How it works
##   - Both brushes are briefcase items, given once per world. They are non-edible entries in the
##     game's item data (merge/world/food/definitions.json).
##   - VR: stroke a pony with the brush; the bristles touching the right part of her is enough.
##   - Desktop: brush in hand, look at her mane, tail or coat, hold the mouse button
##     (input_catcher.gd, a small node placed last under the root so it sees the click first).
##   - Each action has its own animation on her (groom_pose.gd) and on the brush (desktop strokes).
##   - Finishing a brushing (GOAL seconds of good strokes) raises friendship, and love with an adult
##     pony already fond of Anon. Her AI is told what happened. Each pony and action pays at most
##     once per COOLDOWN seconds; brushing past that is just nice.
## Fillies, colts and a young player get friendship only. A pony who is angry or asked for space
## turns away.

const POSE := preload("res://mods/mare_care/brushing/groom_pose.gd")
## The princesses' mane and tail are built into their body model: the mod's own reach for those.
const BUILT_IN := preload("res://mods/mare_care/brushing/built_in_hair.gd")
const INPUT := preload("res://mods/mare_care/brushing/input_catcher.gd")
const SPARKLE := preload("res://mods/mare_care/brushing/sparkle.gd")
const MANE_BRUSH := "food:care-mane-brush"
const COAT_BRUSH := "food:care-coat-brush"
## Bristle tips in the item visual's frame (the game centres the model on its bounds;
## tools/make_models.gd prints those centres).
const BRISTLE := {"food:care-mane-brush": Vector3(0, -0.0214, -0.07685), "food:care-coat-brush": Vector3(0, -0.0305, 0)}
## Sounds: modChad's own recordings, from the Grooming mod.
const SND := "res://mods/mare_care/brushing/sounds/"
const COAT_STROKES := 8
const MANE_LOOP := SND + "mane_brushing_loop.ogg"
const LOOP_DB := -8.0
const LOOP_LINGER := 0.35
const MANE_REGIONS := ["mane", "tail", "head"]
const COAT_REGIONS := ["neck", "withers", "back", "barrel", "shoulder", "chest", "rump", "flank", "belly", "leg"]
## Seconds of good strokes that complete one brushing.
const GOAL := {"mane": 10.0, "tail": 8.0, "coat": 14.0}
## Real seconds before the same pony pays again for the same action.
const COOLDOWN := 600.0
## Friendship and love tag values (the game doubles positive gains and caps them per sitting).
const FRIENDSHIP := {"mane": 2, "tail": 2, "coat": 2}
const ROMANCE := {"mane": 1, "tail": 1, "coat": 1}
const THOUGHTS := {
	"mane": "Anon brushed my mane until it sparkled. I could get used to that.",
	"tail": "Anon brushed out my tail. It feels so light and soft, and it's all sparkly now.",
	"coat": "Anon brushed my coat all over. I'm so relaxed I could nap.",
}
const MEMORIES := {
	"mane": "Anon brushed your mane with a mane brush until it sparkled.",
	"tail": "Anon brushed your tail with a mane brush until it sparkled.",
	"coat": "Anon brushed your coat with a body brush.",
}
const TICK := 0.05
const DESKTOP_REACH := 1.6
## A contact gap shorter than this keeps the session (and its animation) going.
const GAP := 1.5
## VR brush speeds that count as a stroke (m/s).
const MIN_SPEED := 0.03
const MAX_SPEED := 2.0
const CONTACT := 0.06

## The mod's id for Mods.state().
var mod_id := "mare_care"

## pony -> {tool, good, last, pose, side, done, aside, ending}
var _sessions: Dictionary = {}
var _tick := 0.0
var _last_tip: Dictionary = {}   # side -> Vector3
var _desk_down := false
var _desk_hit: Dictionary = {}
var _desk_blend := 0.0
var _desk_stroke := 0.0
var _desk_item: Node3D
var _sound_clock := 0.0
var _refused: Dictionary = {}    # pony -> msec
var _grooming_seen: Dictionary = {}   # finished Grooming brushings already sparkled (session pose id -> true)
var _audio: AudioStreamPlayer3D
var _catcher: Node
var _loop: AudioStreamPlayer3D
var _loop_until := 0
var _loop_pitch := 1.0
var _loop_at := Vector3.INF
var _built_in := BUILT_IN.new()


func _ready() -> void:
	add_to_group("interaction_hint_sources")
	Mods.world_ready.connect(_on_world)
	Mods.world_closed.connect(_on_world_closed)
	_audio = AudioStreamPlayer3D.new()
	_audio.volume_db = -14.0; _audio.max_distance = 8.0
	add_child(_audio)
	_loop = AudioStreamPlayer3D.new()
	_loop.max_distance = 8.0
	add_child(_loop)
	if Mods.game != null: _on_world(Mods.game)


func _on_world(_game: Node) -> void:
	_place_catcher.call_deferred()


func _on_world_closed(_game: Node) -> void:
	for pony: Variant in _sessions.keys(): _end(pony, true)
	_sessions.clear()
	_desk_down = false; _desk_hit = {}; _desk_item = null


## The desktop click must reach us before the briefcase's own _input, which runs earlier the later
## a node is in the tree: so a tiny node goes last under the root, re-placed for every world.
func _place_catcher() -> void:
	if not is_inside_tree(): return
	if not is_instance_valid(_catcher):
		_catcher = INPUT.new()
		_catcher.name = "MareCareBrushInput"
		_catcher.set("groomer", self)
		get_tree().root.add_child(_catcher)
	get_tree().root.move_child(_catcher, -1)


func _game() -> Node:
	var game: Node = Mods.game
	return game if is_instance_valid(game) and game.is_inside_tree() else null


# ---------------------------------------------------------------- desktop

## Called by input_catcher.gd. True when the click was used.
func desktop_click(pressed: bool) -> bool:
	if not pressed:
		var was := _desk_down
		_desk_down = false
		return was
	var hit := _desktop_target()
	if hit.is_empty() or str(hit.get("tool", "")).is_empty(): return false
	if not _willing(hit.target): _turn_away(hit.target); return true
	_desk_down = true
	_desk_hit = hit
	return true


## What the desktop brush points at: {target, point, normal, region, tool, item} or {}.
func _desktop_target() -> Dictionary:
	var game := _game()
	if game == null: return {}
	var inventory: Node = game.get("inventory")
	if inventory == null or not bool(inventory.get("_desktop")): return {}
	var held: Dictionary = inventory.get("held")
	if not held.has("desktop") or not is_instance_valid(held.desktop): return {}
	var item: Node3D = held.desktop
	var item_id := str(item.get_meta("item_id", ""))
	if item_id not in [MANE_BRUSH, COAT_BRUSH]: return {}
	var camera: Camera3D = inventory.get("camera")
	if camera == null: return {}
	var origin := camera.global_position
	var end := origin - camera.global_basis.z * DESKTOP_REACH
	var best := {}
	var closest := INF
	for pony: Variant in _ponies(game):
		if (pony as Node3D).global_position.distance_squared_to(origin) > 9.0: continue
		var touch: Node = pony.get("touch_body")
		if touch == null or not touch.has_method("desktop_offer"): continue
		var hit: Dictionary = touch.desktop_offer(origin, end)
		if item_id == MANE_BRUSH: hit = _with_hair(pony, hit, origin, end, 1.0)
		if hit.is_empty(): continue
		var distance := origin.distance_to(hit.point)
		if distance < closest: closest = distance; best = hit
	if best.is_empty(): return {}
	best.tool = _tool_for(item_id, str(best.region))
	best.item = item
	return best


## A mane or tail built into her body (the princesses), when it is nearer than the game's hit.
func _with_hair(pony: Node3D, hit: Dictionary, from: Vector3, to: Vector3, radius_scale: float) -> Dictionary:
	var hair := _built_in.hair_hit(pony, from, to, radius_scale)
	if hair.is_empty(): return hit
	if hit.is_empty() or from.distance_to(hair.point) <= from.distance_to(Vector3(hit.point)) + 0.03: return hair
	return hit


func _tool_for(item_id: String, region: String) -> String:
	if item_id == MANE_BRUSH and region in MANE_REGIONS: return "tail" if region == "tail" else "mane"
	if item_id == COAT_BRUSH and region in COAT_REGIONS: return "coat"
	return ""


## The game's hint line under the crosshair (interaction_hint_sources).
func interaction_hint() -> Dictionary:
	var hit := _desktop_target()
	if hit.is_empty(): return {}
	var text := ""
	match str(hit.tool):
		"mane": text = "Hold click · Brush mane"
		"tail": text = "Hold click · Brush tail"
		"coat": text = "Hold click · Brush coat"
		_: text = "Mane brush: mane and tail" if str(hit.item.get_meta("item_id", "")) == MANE_BRUSH else "Coat brush: her coat"
	var session: Dictionary = _sessions.get(hit.target, {})
	if not session.is_empty() and session.tool == hit.tool and not bool(session.done):
		text += "  %d%%" % int(100.0 * float(session.good) / float(GOAL[session.tool]))
	elif str(hit.tool) in ["mane", "tail"] and SPARKLE.of(hit.target).call("shining", str(hit.tool)):
		text += "  ✦ sparkling"
	return {"target": hit.target, "text": text, "point": hit.point, "outline": null}


## Desktop brush animation: the brush model leaves the hand and strokes over her, then comes back.
func _animate_desktop_brush(delta: float) -> void:
	var item: Node3D = _desk_hit.get("item", null) if _desk_down else _desk_item
	if _desk_down and is_instance_valid(item): _desk_item = item
	_desk_blend = move_toward(_desk_blend, 1.0 if _desk_down and not _desk_hit.is_empty() else 0.0, delta / 0.2)
	if not is_instance_valid(_desk_item): return
	var model := _visual(_desk_item)
	if model == null: return
	if _desk_blend <= 0.0:
		model.transform = Transform3D.IDENTITY
		_desk_item = null
		return
	if _desk_hit.is_empty(): return
	var tool := str(_desk_hit.tool)
	var pony: Node3D = _desk_hit.target
	var normal: Vector3 = Vector3(_desk_hit.normal).normalized()
	# Stroke direction along her surface: down the mane and tail, toward her tail on the coat.
	var along := Vector3.DOWN if tool in ["mane", "tail"] else pony.global_basis.z
	along = (along - normal * along.dot(normal))
	if along.length() < 0.05: along = (pony.global_basis.z - normal * pony.global_basis.z.dot(normal))
	along = along.normalized()
	_desk_stroke += delta * (1.4 if tool in ["mane", "tail"] else 2.2)
	var t := fposmod(_desk_stroke, 1.0)
	var length := 0.12 if tool in ["mane", "tail"] else 0.07
	# Mane and tail: a long stroke down, lifted on the way back. Coat: short brisk flicks with a curl.
	var travel := 0.0
	var lift := 0.0
	if t < 0.7:
		travel = lerpf(-0.5, 0.5, smoothstep(0.0, 1.0, t / 0.7))
	else:
		travel = lerpf(0.5, -0.5, smoothstep(0.0, 1.0, (t - 0.7) / 0.3)); lift = sin((t - 0.7) / 0.3 * PI) * 0.03
	var side_curl := 0.0 if tool != "coat" else sin(_desk_stroke * TAU) * 0.012
	var tangent := normal.cross(along).normalized()
	var point: Vector3 = Vector3(_desk_hit.point) + along * travel * length + normal * lift + tangent * side_curl
	# Brush frame: bristles (-Y) into her, head (-Z) along the stroke.
	var y := normal
	var z := -along
	var x := y.cross(z).normalized()
	var brush_basis := Basis(x, y, z).orthonormalized()
	var bristle: Vector3 = BRISTLE.get(str(_desk_item.get_meta("item_id", "")), Vector3.ZERO)
	var goal := Transform3D(brush_basis, point - brush_basis * bristle)
	var local_goal := (_desk_item as Node3D).global_transform.affine_inverse() * goal
	model.transform = Transform3D.IDENTITY.interpolate_with(local_goal, _desk_blend)


# ---------------------------------------------------------------- per tick

func _physics_process(delta: float) -> void:
	_animate_desktop_brush(delta)
	_animate_sessions(delta)
	_tick_loop(delta)
	_tick += delta
	if _tick < TICK: return
	var dt := _tick
	_tick = 0.0
	var game := _game()
	if game == null: return
	_sense_desktop(dt)
	_sense_vr_brushes(game, dt)
	_expire()
	_watch_grooming()


## The game's bundled Grooming mod (0.3.1 and later) has its own mane brush. When one of its mane or
## tail brushings is finished, her hair sparkles as it does after Mare Care's brush (when the sparkle
## setting is on). Grooming has no signal for it, so its sessions are read; if a later Grooming keeps
## them differently, nothing happens.
func _watch_grooming() -> void:
	var grooming := get_tree().get_first_node_in_group("grooming_mod")
	if grooming == null:
		_grooming_seen.clear()
		return
	var sessions: Variant = grooming.get("_sessions")
	if not sessions is Dictionary: return
	var live := {}
	for pony: Variant in (sessions as Dictionary).keys():
		var session: Variant = sessions[pony]
		if not is_instance_valid(pony) or not pony is Node3D or not session is Dictionary: continue
		var tool := str((session as Dictionary).get("tool", ""))
		if tool not in ["mane", "tail"] or not bool((session as Dictionary).get("done", false)): continue
		var pose: Variant = (session as Dictionary).get("pose")
		var key: int = (pose as Object).get_instance_id() if is_instance_valid(pose) else hash(session)
		live[key] = true
		if _grooming_seen.has(key): continue
		_grooming_seen[key] = true
		SPARKLE.of(pony as Node3D).call("shine", tool)
		print("[mare_care] %s's %s sparkles after Grooming's brush" % [_pony_id(pony as Node3D), tool])
	for key: int in _grooming_seen.keys():
		if not live.has(key): _grooming_seen.erase(key)


func _sense_desktop(dt: float) -> void:
	if not _desk_down: return
	var hit := _desktop_target()
	if hit.is_empty() or str(hit.tool).is_empty() or (not _desk_hit.is_empty() and hit.target != _desk_hit.target):
		# Looked away: the stroke stops, the button press stays until released.
		_desk_hit = {}
		return
	_desk_hit = hit
	_stroke(hit.target, str(hit.tool), hit.point, dt)


func _sense_vr_brushes(game: Node, dt: float) -> void:
	var inventory: Node = game.get("inventory")
	if inventory == null or bool(inventory.get("_desktop")): return
	var held: Dictionary = inventory.get("held")
	for side: String in held.keys():
		if side == "desktop": continue
		var item: Variant = held[side]
		if not is_instance_valid(item): _last_tip.erase(side); continue
		var item_id := str((item as Node).get_meta("item_id", ""))
		if item_id not in [MANE_BRUSH, COAT_BRUSH]: _last_tip.erase(side); continue
		var model := _visual(item)
		if model == null: continue
		var xform: Transform3D = model.global_transform
		var tip := xform * Vector3(BRISTLE[item_id])
		var speed := 0.0
		if _last_tip.has(side): speed = tip.distance_to(_last_tip[side]) / dt
		_last_tip[side] = tip
		var down := -xform.basis.y.normalized()
		for pony: Variant in _ponies(game):
			if (pony as Node3D).global_position.distance_to(tip) > 2.5: continue
			var touch: Node = pony.get("touch_body")
			if touch == null or not touch.has_method("desktop_offer"): continue
			var hit: Dictionary = touch.desktop_offer(tip - down * 0.08, tip + down * 0.05)
			if item_id == MANE_BRUSH: hit = _with_hair(pony, hit, tip - down * 0.08, tip + down * 0.05, 1.3)
			if hit.is_empty() or Vector3(hit.point).distance_to(tip) > CONTACT: continue
			var tool := _tool_for(item_id, str(hit.region))
			if tool.is_empty(): continue
			if speed < MIN_SPEED or speed > MAX_SPEED: _hold(pony, tool); break
			if not _willing(pony): _turn_away(pony); break
			_stroke(pony, tool, hit.point, dt)
			if inventory.has_method("_haptic") and randf() < 0.15: inventory.call("_haptic", side)
			break


# ---------------------------------------------------------------- sessions

func _stroke(pony: Node3D, tool: String, point: Vector3, dt: float) -> void:
	var session: Dictionary = _sessions.get(pony, {})
	if not session.is_empty() and session.tool != tool:
		_end(pony, true)
		session = {}
	if not session.is_empty() and bool(session.ending): session.ending = false
	if session.is_empty():
		session = _begin(pony, tool)
		if session.is_empty(): return
	session.last = Time.get_ticks_msec()
	session.good = float(session.good) + dt
	session.side = _side_of(pony)
	(session.pose as Node).set("phase", float((session.pose as Node).get("phase")) + dt * TAU * 0.8)
	if not bool(session.done) and float(session.good) >= float(GOAL[tool]):
		session.done = true
		_reward(pony, tool, float(session.good))
	_play_sound(tool, point if point.is_finite() else pony.global_position, dt)
	# She stays put while groomed, as she does while petted.
	if pony.has_method("begin_touch") and not pony.call("is_held"): pony.call("begin_touch", Vector3.ZERO, 0.5)


## Contact without a stroke (a brush held still on her): keeps the session alive, no progress.
func _hold(pony: Node3D, tool: String) -> void:
	var session: Dictionary = _sessions.get(pony, {})
	if not session.is_empty() and session.tool == tool: session.last = Time.get_ticks_msec()


func _begin(pony: Node3D, tool: String) -> Dictionary:
	var skeleton: Skeleton3D = pony.get("skeleton")
	if skeleton == null: return {}
	var pose: SkeletonModifier3D = POSE.new()
	pose.name = "MareCareGroomPose"
	pose.mare = pony; pose.tool = tool; pose.side = _side_of(pony)
	skeleton.add_child(pose)
	var session := {"tool": tool, "good": 0.0, "last": Time.get_ticks_msec(), "pose": pose, "side": pose.side,
		"done": false, "aside": false, "ending": false}
	_sessions[pony] = session
	if pony.has_method("set_action_gaze") and tool in ["mane", "coat"]:
		var camera: Node3D = _camera()
		if camera != null: pony.call("set_action_gaze", camera)
	if tool == "tail":
		var tail: Variant = pony.get("tail_motion")
		if tail != null and "aside_goal" in tail: session.aside = true
	# Her AI hears about it like petting (one line per session; the director rate-limits it).
	if pony.has_signal("physical_reaction"):
		pony.emit_signal("physical_reaction", "petted:" + ("tail" if tool == "tail" else ("mane" if tool == "mane" else "back")))
	return session


## A session ends after GAP seconds without contact.
func _expire() -> void:
	var now := Time.get_ticks_msec()
	for pony: Variant in _sessions.keys():
		var session: Dictionary = _sessions[pony]
		if not is_instance_valid(pony) or not (pony as Node).is_inside_tree():
			_end(pony, true); continue
		var asleep := bool(pony.get("sleeping")) or bool(pony.call("is_held"))
		if asleep or float(now - int(session.last)) / 1000.0 > GAP: _end(pony, false)


## Eases each pose in and out, drives her face and tail.
func _animate_sessions(delta: float) -> void:
	for pony: Variant in _sessions.keys():
		var session: Dictionary = _sessions[pony]
		var pose: Variant = session.pose
		if not is_instance_valid(pony) or not is_instance_valid(pose): continue
		var ending: bool = session.ending
		pose.amount = move_toward(float(pose.amount), 0.0 if ending else 1.0, delta / (0.6 if ending else 0.45))
		pose.side = lerpf(float(pose.side), float(session.side), clampf(delta * 3.0, 0.0, 1.0))
		var a: float = pose.amount
		var tool := str(session.tool)
		var expressions: Variant = pony.get("expressions")
		if expressions != null and expressions.has_method("touch"):
			# Smile and how shut her eyes are.
			var face := {"mane": Vector2(0.7, 0.55), "tail": Vector2(0.55, 0.3), "coat": Vector2(0.75, 0.7)}
			var f: Vector2 = face.get(tool, Vector2(0.6, 0.4))
			expressions.touch("mare_care", f.x * a, f.y * a)
		if bool(session.aside):
			var tail: Variant = pony.get("tail_motion")
			if tail != null:
				# Tail lifted away from the groomer, swishing gently while brushed.
				var swish := 0.12 * sin(float(pose.phase) * 0.5)
				tail.aside_goal = (-float(session.side) * 0.3 + swish) * a if not ending else 0.0
		if ending and a <= 0.0: _finish(pony)


func _end(pony: Variant, now: bool) -> void:
	var session: Dictionary = _sessions.get(pony, {})
	if session.is_empty(): return
	session.ending = true
	if is_instance_valid(pony):
		if session.tool == "coat" and bool(session.done) and not now:
			# A good long brush ends with a happy stretch.
			var affection: Node = (pony as Node).get_node_or_null("Affection")
			if affection != null and affection.has_method("fidget"): affection.call("fidget", "stretch", float(session.side) < 0.0)
		if (pony as Node).has_method("set_action_gaze") and session.tool in ["mane", "coat"]: pony.call("set_action_gaze", null)
	if now: _finish(pony)


func _finish(pony: Variant) -> void:
	var session: Dictionary = _sessions.get(pony, {})
	_sessions.erase(pony)
	if session.is_empty(): return
	if is_instance_valid(session.pose): (session.pose as Node).queue_free()
	if not is_instance_valid(pony): return
	var expressions: Variant = pony.get("expressions")
	if expressions != null and expressions.has_method("release_touch"): expressions.release_touch("mare_care")
	if bool(session.aside):
		var tail: Variant = pony.get("tail_motion")
		if tail != null: tail.aside_goal = 0.0


# ---------------------------------------------------------------- relationship

func _pony_id(pony: Node) -> String:
	var id := str(pony.get_meta("relationship_id", ""))
	if id.is_empty():
		var identity: Variant = pony.get("identity")
		if identity != null: id = str(identity.get("id"))
	return id


func _bonds() -> Node:
	var game := _game()
	if game == null or game.get("world_context") == null: return null
	return game.world_context.get("player_bonds")


## Like hand feeding: not while she is cross with Anon or asked for space.
func _willing(pony: Node3D) -> bool:
	if bool(pony.get("sleeping")) or pony.has_meta("spa_client"): return false
	var identity: Variant = pony.get("identity")
	if identity != null and bool(identity.get("filly")): return true
	var bonds := _bonds()
	var id := _pony_id(pony)
	if bonds == null or id.is_empty(): return true
	var record: Dictionary = bonds.record_for(id)
	var space := Time.get_unix_time_from_system() < float(record.get("cooldowns", {}).get("boundary", 0.0))
	return float(bonds.anger(id)) < 35.0 and not space


func _turn_away(pony: Node3D) -> void:
	var now := Time.get_ticks_msec()
	if now - int(_refused.get(pony, -100000)) < 4000: return
	_refused[pony] = now
	if pony.has_method("set_action_gaze"): pony.call("set_action_gaze", null)
	print("[mare_care] %s turns away" % _pony_id(pony))


func _reward(pony: Node3D, tool: String, seconds: float) -> void:
	# The sparkle comes every time, cooldown or not: a brushed mane is a brushed mane.
	if tool in ["mane", "tail"]: SPARKLE.of(pony).call("shine", tool)
	var id := _pony_id(pony)
	var game := _game()
	if id.is_empty() or game == null or game.get("world_context") == null: return
	var state := Mods.state(mod_id)
	if not state.has("paid"): state["paid"] = {}
	var key := id + ":" + tool
	var now := Time.get_unix_time_from_system()
	var expressions: Variant = pony.get("expressions")
	if expressions != null and expressions.has_method("fluster"): expressions.fluster(1.0)
	_sigh(pony)
	if now - float((state["paid"] as Dictionary).get(key, 0.0)) < COOLDOWN: return
	state["paid"][key] = now
	Mods.save_changed()
	var context: Node = game.world_context
	var bonds := _bonds()
	var tags := {"friendship": FRIENDSHIP[tool], "mood": "relaxed", "thought": THOUGHTS[tool]}
	if bonds != null and bonds.eligible_for_romance(id):
		var stage := str(bonds.record_for(id).get("stage", "acquaintance"))
		if int(bonds.interest(id)) >= 25 or stage in ["dating", "engaged", "married"]:
			tags["romance"] = ROMANCE[tool]
			tags["mood"] = "happy"
	var impressions: Variant = context.get("impressions")
	if impressions != null and is_instance_valid(impressions):
		impressions.commit(id, tags, "mare_care_%s_%d" % [tool, Time.get_ticks_usec()])
	if bonds != null:
		bonds.add_together(id, seconds)
		# A little familiarity and trust, the bond stage's own currencies (player_bonds.gd).
		if bonds.has_method("_save"):
			var r: Dictionary = bonds.record_for(id)
			r.familiarity = minf(100.0, float(r.get("familiarity", 0.0)) + 2.0)
			r.trust = minf(100.0, float(r.get("trust", 0.0)) + 1.0)
			bonds.call("_save", id, r)
	if context.has_method("record"):
		context.record("mare_care", MEMORIES[tool], [id, "player"], [id, "player"])
	print("[mare_care] %s enjoyed %s brushing (%s)" % [id, tool, str(tags)])


# ---------------------------------------------------------------- helpers

## The game's visual node of a held item (the food visual the item data points at our model).
func _visual(item: Variant) -> Node3D:
	if not is_instance_valid(item): return null
	var visual: Variant = (item as Node).get_meta("food_visual", null)
	return visual as Node3D if is_instance_valid(visual) else null


func _ponies(game: Node) -> Array:
	var out := []
	var mares: Variant = game.get("mares")
	if not mares is Array: return out
	for pony: Variant in mares:
		if is_instance_valid(pony) and (pony as Node3D).is_inside_tree() and (pony as Node3D).is_visible_in_tree() and not bool(pony.get("sleeping")):
			out.append(pony)
	return out


func _camera() -> Node3D:
	var game := _game()
	if game == null: return null
	var inventory: Node = game.get("inventory")
	return inventory.get("camera") if inventory != null else null


## +1 when Anon is on her right, -1 on her left.
func _side_of(pony: Node3D) -> float:
	var camera := _camera()
	if camera == null: return 1.0
	return 1.0 if (camera.global_position - pony.global_position).dot(pony.global_basis.x) >= 0.0 else -1.0


func _play_sound(tool: String, at: Vector3, dt: float) -> void:
	if tool in ["mane", "tail"]:
		_loop_until = Time.get_ticks_msec() + int(LOOP_LINGER * 1000.0)
		_loop_pitch = 0.92 if tool == "tail" else 1.0
		_loop_at = at
		return
	_sound_clock -= dt
	if _sound_clock > 0.0 or _audio == null: return
	_sound_clock = randf_range(0.35, 0.6)
	var path := SND + "coat_stroke_%02d.wav" % (randi() % COAT_STROKES + 1)
	if not ResourceLoader.exists(path): return
	_audio.stream = load(path)
	_audio.volume_db = randf_range(-11.0, -9.0)
	_audio.pitch_scale = randf_range(0.94, 1.06)
	_audio.global_position = at
	_audio.play()


## The mane loop follows the brush, fades in while strokes land and out once they stop.
func _tick_loop(delta: float) -> void:
	if _loop == null: return
	var on := Time.get_ticks_msec() < _loop_until
	if on and not _loop.playing:
		if _loop.stream == null:
			var stream: AudioStream = load(MANE_LOOP) if ResourceLoader.exists(MANE_LOOP) else null
			if stream == null: return
			if "loop" in stream: stream.set("loop", true)
			_loop.stream = stream
		_loop.volume_db = -40.0
		_loop.play(randf() * 12.0)
	if not _loop.playing: return
	if _loop_at.is_finite(): _loop.global_position = _loop_at
	_loop.pitch_scale = move_toward(_loop.pitch_scale, _loop_pitch, delta)
	_loop.volume_db = move_toward(_loop.volume_db, LOOP_DB if on else -40.0, delta * (60.0 if on else 90.0))
	if not on and _loop.volume_db <= -39.9: _loop.stop()


## A finished brushing: a contented sigh in her own breath (the game's soft breaths).
func _sigh(pony: Node3D) -> void:
	var boop: Variant = pony.get("boop_node")
	if boop != null and is_instance_valid(boop) and boop.has_method("play_breath"): boop.call("play_breath", -20.0)


## Switched off in Settings → Mods: every pony goes back to normal, the brush back in the hand.
func _exit_tree() -> void:
	for pony: Variant in _sessions.keys(): _end(pony, true)
	_sessions.clear()
	if is_instance_valid(_desk_item):
		var model := _visual(_desk_item)
		if model != null: model.transform = Transform3D.IDENTITY
	if is_instance_valid(_catcher): _catcher.queue_free()
	# The sparkles go with the mod.
	var game := _game()
	if game != null:
		for pony: Variant in _ponies(game):
			var sparkle: Node = (pony as Node).get_node_or_null("MareCareSparkle")
			if sparkle != null: sparkle.queue_free()
