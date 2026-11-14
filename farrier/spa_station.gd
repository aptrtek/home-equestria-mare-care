extends Node
## A farrier station at Aloe and Lotus's spa: the last stop of a visit, where the player picks out,
## trims, shoes and oils a client's hooves, with the station's own tools or their own.
##
## The station's tools lie on its tool bench: a hoof pick, nippers, rasp, hammer, hoof oil and a set
## of steel shoes (items "food:care-spa-*", which farrier.gd treats like the player's own). They
## belong to the spa, the way its hoof file belongs to the counter (spa_hands.gd _keep_file_home):
## exactly one of each, and once a second any that left the spa go back on the bench. Walk out with
## one in hand or in the briefcase and it goes back too. They don't count against the Tools
## switches, so the station works with every one of the player's own tools switched off.
##
## The spa (world/minigames/spa/spa_customers.gd) is the game's, and it stays unchanged. It keeps
## owning each client (her navigator lease, the romance firewall, interruptions, leaving); this
## only adds one more stop to her list of services and runs that stop:
##   1. client_arrived: a client whose hooves need picking, oiling or a shoe reset gets "farrier"
##      put at the end of her services (after the footbath, the table and the wing cushion).
##   2. When her last spa service is done, the spa finds "farrier" next and, not knowing it, leaves
##      her where she is. This takes over before the spa's next tick: she walks to the station (or,
##      while another client has it, waits on the lobby bench), using the spa's own routing.
##   3. At the station she stands on the mat and the farrier (farrier.gd) treats her like any mare:
##      aim a tool at a leg and she lifts that hoof. Every job is paid as a spa add-on, at Mare
##      Care's prices, by every client (Settings > Mare Care > pay).
##   4. Once everything she came for is done on all four hooves (and she isn't shod on only some),
##      "farrier" comes off her list and the spa sends her home. Run out of patience half shod and
##      she leaves hurt, as she would in town.
## Phases the spa doesn't know ("farrier_wait", "farrier_walk", "farrier") leave her untouched on
## its side, apart from what every phase gets: patience, interruptions and ownership checks.

const CARE := preload("res://mods/mare_care/farrier/hoof_care.gd")
const HOOVES := preload("res://mods/mare_care/farrier/hooves.gd")
const MODELS := preload("res://mods/mare_care/farrier/models.gd")
const SPA_PATH := "res://world/minigames/spa/spa_customers.gd"
const SERVICE := "farrier"
const WAIT := "farrier_wait"
const WALK := "farrier_walk"
const STAND := "farrier"
const PHASES := [WAIT, WALK, STAND]
const LEAVING := ["to_door_in", "to_door_out"]
## Where she stands, in the spa venue's own space (spa_venue.gd: door toward +Z, shop floor
## y 0.36): behind the lobby's partition, in the free west half of the wing nook, facing the back
## wall so the player can walk all the way round her.
const STATION := Vector3(1.9, 0.36, -3.2)
const FACING := Vector3(0, 0, -1)
const MAT_SIZE := Vector3(1.0, 0.012, 2.0)
## The tool bench: west of the mat, against the wall, running along her side. No collision, so it
## never changes anypony's way through the nook.
const BENCH_AT := Vector3(0.98, 0.36, -3.35)
const BENCH_TOP := Vector3(0.32, 0.03, 0.74)
const BENCH_HEIGHT := 0.55
## The station's tools: item id, and where along the bench (venue z) it lies. Each lies flat across
## the bench, working end toward the wall and handle toward the mat.
const BENCH_TOOLS := [
	["food:care-spa-hoof-pick", -3.06], ["food:care-spa-nippers", -3.17], ["food:care-spa-rasp", -3.29],
	["food:care-spa-hammer", -3.41], ["food:care-spa-hoof-oil", -3.53], ["food:care-spa-shoe-steel", -3.64],
]
## Left off the bench while shoeing at the spa is switched off.
const SHOE_TOOLS := ["food:care-spa-hammer", "food:care-spa-shoe-steel"]
const TOOLS_HOME_SECONDS := 1.0
## Away from the spa further than this, the bench is restocked only once the player comes back.
const RESTOCK_REACH := 30.0
## Walked off the mat further than this (a chat, a bump), she walks back.
const DRIFT := 0.6
const TRAVEL_SECONDS := 120.0
## The spa's own patience (spa_customers.gd PATIENCE): work on her, or waiting for the station,
## keeps her this much longer.
const PATIENCE := 300.0
const CHECK_SECONDS := 0.25
const JOB_WORDS := {"pick": "picking", "trim": "a trim", "shoe": "a shoe reset", "oil": "oil"}

var mod_id := "mare_care"
var _spa: Node
var _owner_id := ""
## Clients this has taken over: id -> actor, to settle up with the ones who leave half shod.
var _taken := {}
## How many bare hooves each taken-over client came with: she is held for an even set, or hurt by
## leaving lopsided, only when the shoeing done here changed that.
var _bare_start := {}
var _prop: Node3D
var _check := 0.0
var _tools_clock := 0.0


func _ready() -> void:
	add_to_group("mare_care_spa_station")
	Mods.on_node(SPA_PATH, _on_spa)


func _on_spa(spa: Node) -> void:
	if not is_instance_valid(spa) or spa == _spa: return
	for needed: String in ["_visits", "_clock"]:
		if spa.get(needed) == null:
			print("[mare_care] the spa has changed: no farrier station"); return
	for method: String in ["_route", "_arrived", "_stalled_near", "_face", "_next_station", "_leave", "_pay",
			"_wait_on_bench", "_off_seat", "_free_seat", "_relax", "marker", "venue_transform", "_owned"]:
		if not spa.has_method(method):
			print("[mare_care] the spa has changed (%s): no farrier station" % method); return
	_spa = spa
	spa.connect("client_arrived", _on_arrived)
	print("[mare_care] farrier station ready at the spa")


func enabled() -> bool:
	return CARE.spa_farrier and CARE.dirt_enabled


# ---------------------------------------------------------------- for farrier.gd

## True while `pony` stands at the station: the farrier works on her as on any mare.
func serving(pony: Node) -> bool:
	var visit := _visit_of(pony)
	return not visit.is_empty() and str(visit.phase) == STAND


## A spa client at the station pays for farrier work as a spa add-on. True when this handled it
## (paid, or pay is switched off); false when she isn't a station client.
func pay(pony: Node, amount: int) -> bool:
	var visit := _visit_of(pony)
	if visit.is_empty() or not _taken.has(str(visit.id)): return false
	if not CARE.pay_enabled or amount <= 0: return true
	if bool(_spa.call("_pay", visit, amount, SERVICE)):
		print("[mare_care] %s paid %d bits at the spa's farrier station" % [visit.id, amount])
	return true


## Text for a hint: what she came to the station for, or "".
func came_for(pony: Node) -> String:
	var visit := _visit_of(pony)
	if visit.is_empty(): return ""
	var words := []
	for job: String in visit.get("farrier_jobs", []): words.append(JOB_WORDS[job])
	return ", ".join(words)


# ---------------------------------------------------------------- joining a visit

func _on_arrived(pony_id: String, _display_name: String) -> void:
	if not enabled() or not is_instance_valid(_spa): return
	var visit: Dictionary = _spa._visits.get(pony_id, {})
	if visit.is_empty() or bool(visit.get("walk_in", false)) or (visit.services as Array).has(SERVICE): return
	if not is_instance_valid(visit.actor) or HOOVES.soles(visit.actor).size() != 4: return
	# A trim is left out here: the spa's own filing trims her on the way.
	var jobs := _wanted(pony_id, false)
	if jobs.is_empty(): return
	(visit.services as Array).append(SERVICE)
	print("[mare_care] %s will see the farrier at the spa (%s)" % [pony_id, ", ".join(jobs)])


## The jobs due on any of her hooves (the station has a tool for every one).
func _wanted(pony_id: String, with_trim: bool) -> Array:
	var out := []
	var hooves := CARE.hooves(mod_id, pony_id)
	for job: String in ["pick", "trim", "shoe", "oil"]:
		if job == "trim" and not with_trim: continue
		for leg: String in HOOVES.LEGS:
			var record: Dictionary = hooves.get(leg, {})
			if CARE.due(record, job) and CARE.spa_job(record, job):
				out.append(job); break
	return out


# ---------------------------------------------------------------- per tick

func _physics_process(delta: float) -> void:
	if not is_instance_valid(_spa):
		_spa = null
		return
	_build_prop()
	_keep_tools_home(delta)
	var visits: Dictionary = _spa._visits
	# Every frame: a client whose next stop is the station is taken over before the spa's next
	# tick, which would otherwise run her last phase again (raise a filed hoof, hop off the table
	# twice, find her wings gone).
	for id: String in visits.keys():
		var visit: Dictionary = visits[id]
		var services: Array = visit.services
		if not services.is_empty() and services[0] == SERVICE and not str(visit.phase) in PHASES and not str(visit.phase) in LEAVING:
			_take(visit)
	_settle_departures()
	_check += delta
	if _check < CHECK_SECONDS: return
	_check = 0.0
	if not _owner_id.is_empty():
		var owner: Dictionary = visits.get(_owner_id, {})
		if owner.is_empty() or not str(owner.phase) in [WALK, STAND]: _owner_id = ""
	for id: String in visits.keys():
		if not visits.has(id): continue
		var visit: Dictionary = visits[id]
		if str(visit.phase) in PHASES: _tick_visit(visit)


func _take(visit: Dictionary) -> void:
	var id := str(visit.id)
	var jobs := _wanted(id, true) if enabled() else []
	if jobs.is_empty():
		_skip(visit); return
	visit.farrier_jobs = jobs
	_taken[id] = visit.actor
	_bare_start[id] = _bare_count(id)
	if bool(visit.get("sat", false)):
		visit.actor.request_posture("stand"); visit.sat = false
	visit.patience = float(_spa._clock) + PATIENCE
	if _owner_id.is_empty(): _go(visit)
	else: _queue(visit)


## Nothing left for the farrier (or the station was switched off): on to the spa's next stop.
func _skip(visit: Dictionary) -> void:
	(visit.services as Array).erase(SERVICE)
	if _owner_id == str(visit.id): _owner_id = ""
	_spa.call("_next_station", visit)


func _go(visit: Dictionary) -> void:
	_owner_id = str(visit.id)
	visit.farrier_deadline = float(_spa._clock) + TRAVEL_SECONDS
	_spa.call("_route", visit, WALK, _point())


func _queue(visit: Dictionary) -> void:
	if _spa.call("_free_seat", "lobby", visit) != null:
		visit.phase = WAIT; visit.since = _spa._clock
		_spa.call("_wait_on_bench", visit, "lobby")
	else:
		_spa.call("_route", visit, WAIT, (_spa.call("marker", "SPA_LOBBY_WAIT_%d" % (int(visit.slot) + 1)) as Transform3D).origin)


func _tick_visit(visit: Dictionary) -> void:
	var clock := float(_spa._clock)
	match str(visit.phase):
		WAIT:
			# Waiting for the station is not waiting for Anon: her patience waits too.
			visit.patience = clock + PATIENCE
			if _owner_id.is_empty() or _owner_id == str(visit.id):
				if bool(_spa.call("_off_seat", visit)): _go(visit)
			elif visit.seat != null or _spa.call("_free_seat", "lobby", visit) != null:
				_spa.call("_wait_on_bench", visit, "lobby")
		WALK:
			if bool(_spa.call("_arrived", visit, true)) or bool(_spa.call("_stalled_near", visit, 1.2)):
				visit.phase = STAND; visit.since = clock
				_spa.call("_face", visit, _facing())
				_spa.call("_relax", visit, 0.25)
				_announce(visit)
			elif clock > float(visit.get("farrier_deadline", INF)) or visit.nav.state in [visit.nav.State.UNREACHABLE, visit.nav.State.BLOCKED]:
				_spa.call("_leave", visit, "No way to the farrier station")
		STAND:
			_tick_stand(visit, clock)


func _tick_stand(visit: Dictionary, clock: float) -> void:
	var actor: Node3D = visit.actor
	var farrier := _farrier()
	var session: Dictionary = farrier.get("_session") if farrier != null else {}
	var working: bool = not session.is_empty() and session.get("pony") == actor
	if working: visit.patience = clock + PATIENCE
	if not HOOVES.raised(actor).is_empty() or working: return
	var gap := actor.global_position - _point()
	if Vector2(gap.x, gap.z).length() > DRIFT * maxf(float(visit.size), 1.0):
		_spa.call("_route", visit, WALK, _point())
		visit.farrier_deadline = clock + TRAVEL_SECONDS
		return
	var status: Dictionary = actor.posture_status() if actor.has_method("posture_status") else {}
	if str(status.get("kind", "stand")) not in ["stand", ""] and str(status.get("requested", "stand")) != "stand":
		actor.request_posture("stand")
	if _finished(visit): _finish(visit)
	elif clock - float(visit.get("faced_at", 0.0)) > 3.0:
		visit.faced_at = clock
		_spa.call("_face", visit, _facing())


func _bare_count(pony_id: String) -> int:
	var hooves := CARE.hooves(mod_id, pony_id)
	var bare := 0
	for leg: String in HOOVES.LEGS:
		if str((hooves.get(leg, {}) as Dictionary).get("shoe", "")).is_empty(): bare += 1
	return bare


## Everything she came for is done on all four hooves, and she isn't left shod on only some (unless
## she came in that way and nothing was shod here).
func _finished(visit: Dictionary) -> bool:
	var hooves := CARE.hooves(mod_id, str(visit.id))
	var bare := 0
	for leg: String in HOOVES.LEGS:
		var record: Dictionary = hooves.get(leg, {})
		if str(record.get("shoe", "")).is_empty(): bare += 1
		for job: String in visit.get("farrier_jobs", []):
			if CARE.due(record, job) and CARE.spa_job(record, job): return false
	return bare == 0 or bare == 4 or bare == int(_bare_start.get(str(visit.id), bare))


func _finish(visit: Dictionary) -> void:
	var id := str(visit.id)
	print("[mare_care] %s is done at the farrier station" % id)
	_taken.erase(id)
	_bare_start.erase(id)
	var farrier := _farrier()
	if farrier != null and farrier.has_method("_stop_waiting"): farrier.call("_stop_waiting", visit.actor)
	_spa.call("_relax", visit, 0.8)
	if _spa.has_signal("reaction"): _spa.emit_signal("reaction", id, "stretch")
	_skip(visit)


func _announce(visit: Dictionary) -> void:
	var farrier := _farrier()
	if farrier != null and farrier.has_method("_note"):
		farrier.call("_note", "%s is at the farrier station: %s" % [visit.display_name, came_for(visit.actor)])


## Clients taken over who are now on their way out (or gone): a hoof still up is let down, and
## one shod on only some hooves leaves hurt, as she would in town.
func _settle_departures() -> void:
	for id: String in _taken.keys():
		var visit: Dictionary = _spa._visits.get(id, {})
		if not visit.is_empty() and not str(visit.phase) in LEAVING: continue
		var pony: Variant = _taken[id]
		_taken.erase(id)
		if _owner_id == id: _owner_id = ""
		if not is_instance_valid(pony): continue
		var farrier := _farrier()
		if farrier == null: continue
		var session: Dictionary = farrier.get("_session")
		if not session.is_empty() and session.get("pony") == pony: farrier.call("_end_session")
		farrier.call("_stop_waiting", pony)
		var bare: Array = farrier.call("_bare_hooves", pony)
		var start := int(_bare_start.get(id, bare.size()))
		_bare_start.erase(id)
		if not bare.is_empty() and bare.size() < 4 and bare.size() != start: farrier.call("_left_uneven", pony)


# ---------------------------------------------------------------- the station itself

## A rubber mat where she stands and a tool bench beside it, in the venue's space.
func _build_prop() -> void:
	if is_instance_valid(_prop): return
	var venue: Node3D = _spa.get("_venue") as Node3D
	if not is_instance_valid(venue) or not venue.is_inside_tree(): return
	var parent: Node3D = venue.get("interior") as Node3D
	if not is_instance_valid(parent): parent = venue
	_prop = Node3D.new()
	_prop.name = "MareCareFarrierStation"
	parent.add_child(_prop)
	_prop.global_transform = _spa.call("venue_transform")
	var mat := MeshInstance3D.new()
	mat.name = "Mat"
	var box := BoxMesh.new(); box.size = MAT_SIZE
	mat.mesh = box
	mat.material_override = _material(Color("3b4a3f"), 0.95)
	mat.position = STATION + Vector3.UP * MAT_SIZE.y * 0.5
	_prop.add_child(mat)
	var trim := MeshInstance3D.new()
	trim.name = "MatEdge"
	var edge := BoxMesh.new(); edge.size = Vector3(MAT_SIZE.x + 0.06, MAT_SIZE.y * 0.6, MAT_SIZE.z + 0.06)
	trim.mesh = edge
	trim.material_override = _material(Color("c9a46a"), 0.8)
	trim.position = STATION + Vector3.UP * MAT_SIZE.y * 0.3
	_prop.add_child(trim)
	_prop.add_child(_bench())


## A small wooden tool bench: a top on four legs, with a lower shelf.
func _bench() -> Node3D:
	var bench := Node3D.new()
	bench.name = "ToolBench"
	bench.position = BENCH_AT
	var wood := _material(MODELS.WOOD, 0.8)
	var dark := _material(MODELS.WOOD.darkened(0.25), 0.85)
	var parts := [[BENCH_TOP, Vector3(0, BENCH_HEIGHT - BENCH_TOP.y * 0.5, 0), wood],
		[Vector3(BENCH_TOP.x - 0.06, 0.02, BENCH_TOP.z - 0.08), Vector3(0, 0.16, 0), dark]]
	var leg := Vector3(0.04, BENCH_HEIGHT - BENCH_TOP.y, 0.04)
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			parts.append([leg, Vector3(sx * (BENCH_TOP.x * 0.5 - 0.03), leg.y * 0.5, sz * (BENCH_TOP.z * 0.5 - 0.03)), dark])
	for part: Array in parts:
		var board := MeshInstance3D.new()
		var mesh := BoxMesh.new(); mesh.size = part[0]
		board.mesh = mesh
		board.material_override = part[2]
		board.position = part[1]
		bench.add_child(board)
	return bench


# ---------------------------------------------------------------- the station's tools

## Where a station tool lies on the bench, in world space: flat across the top, working end (the
## models' -Z) toward the wall, handle toward the mat.
func _tool_rest(z: float) -> Transform3D:
	var local := Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(BENCH_AT.x, BENCH_AT.y + BENCH_HEIGHT + 0.015, z))
	return (_spa.call("venue_transform") as Transform3D) * local


## Once a second, the spa's hoof file rule (spa_hands.gd _keep_file_home) for each station tool:
## one of each, kept at the spa. A tool lying outside the spa goes back on the bench; with the
## player outside, one in a hand or in the briefcase does too; a missing one is laid again. With the
## station switched off they are all put away.
func _keep_tools_home(delta: float) -> void:
	_tools_clock -= delta
	if _tools_clock > 0.0: return
	_tools_clock = TOOLS_HOME_SECONDS
	var game: Node = Mods.game
	var inventory: Node = game.get("inventory") as Node if is_instance_valid(game) else null
	var venue: Node3D = _spa.get("_venue") as Node3D
	if not is_instance_valid(inventory) or not is_instance_valid(venue) or not venue.has_method("is_inside"): return
	var store: Variant = inventory.get("inventory")
	var camera: Node3D = inventory.get("camera") as Node3D
	var held: Variant = inventory.get("held")
	var loose: Variant = inventory.get("loose")
	if store == null or not is_instance_valid(camera) or not held is Dictionary or not loose is Dictionary: return
	if not inventory.has_method("spawn_owned_drop") or not store.has_method("discard"): return
	if not CARE.spa_farrier:
		_put_tools_away(inventory, store, [])
		return
	if not CARE.spa_shoes: _put_tools_away(inventory, store, SHOE_TOOLS)
	var player_out: bool = not bool(venue.call("is_inside", camera.global_position))
	var far := camera.global_position.distance_squared_to(venue.global_position) > RESTOCK_REACH * RESTOCK_REACH
	for entry: Array in BENCH_TOOLS:
		var id := str(entry[0])
		if not CARE.spa_shoes and id in SHOE_TOOLS: continue
		var rest := _tool_rest(float(entry[1]))
		var home: RigidBody3D = null
		for token: Variant in (loose as Dictionary).keys():
			var item: RigidBody3D = (loose as Dictionary)[token] as RigidBody3D
			if not is_instance_valid(item) or item in (held as Dictionary).values() or str(item.get_meta("item_id", "")) != id: continue
			if bool(venue.call("is_inside", item.global_position)) and home == null: home = item
			else: _to_bench(item, str(token), rest, store)
		if player_out:
			for side: Variant in (held as Dictionary).keys():
				var in_hand: Variant = (held as Dictionary)[side]
				if is_instance_valid(in_hand) and str((in_hand as Node).get_meta("item_id", "")) == id: _take_out_of_hand(inventory, str(side), store)
			store.discard(id)
			if far: continue
		if home != null or _held_or_loose(held, loose, id): continue
		# A loaned tool with no body in the world (out of the case but nowhere to be found): its loan
		# ends, and a fresh one goes on the bench.
		if store.get("loans") is Dictionary:
			var lost: Array[String] = []
			for token: Variant in (store.loans as Dictionary).keys():
				var loan: Dictionary = store.loans[token]
				if str(loan.get("id", "")) == id and not loan.get("equipped", false) and not (loose as Dictionary).has(token): lost.append(str(token))
			for token: String in lost: store.consume(token)
		# Stashed in the briefcase inside the spa: still the player's to take out again.
		if _in_case(store, id): continue
		var spawned: RigidBody3D = inventory.call("spawn_owned_drop", id, rest)
		if spawned != null: spawned.freeze = true


func _held_or_loose(held: Dictionary, loose: Dictionary, id: String) -> bool:
	for item: Variant in loose.values():
		if is_instance_valid(item) and str((item as Node).get_meta("item_id", "")) == id: return true
	for item: Variant in held.values():
		if is_instance_valid(item) and str((item as Node).get_meta("item_id", "")) == id: return true
	return false


func _in_case(store: Variant, id: String) -> bool:
	for slot: Variant in store.get("slots"):
		if slot is Dictionary and not (slot as Dictionary).is_empty() and str(slot.get("id", "")) == id and int(slot.get("count", 0)) > 0: return true
	return false


func _to_bench(item: RigidBody3D, token: String, rest: Transform3D, store: Variant) -> void:
	item.linear_velocity = Vector3.ZERO; item.angular_velocity = Vector3.ZERO
	item.global_transform = rest
	item.freeze = true
	if store.has_method("update_drops"): store.update_drops({token: rest})


## The tool leaves the hand and the case without a drop (spa_hands.gd _take_out_of_hand); the next
## check lays a fresh one on the bench.
func _take_out_of_hand(inventory: Node, side: String, store: Variant) -> void:
	var held: Dictionary = inventory.get("held")
	var item: RigidBody3D = held.get(side) as RigidBody3D
	if item == null: return
	var token := str(item.get_meta("token", ""))
	if not store.consume(token): return
	if inventory.has_method("_unglow"): inventory.call("_unglow", item)
	held.erase(side)
	(inventory.get("loose") as Dictionary).erase(token)
	for key: String in ["_track", "_eat_time"]:
		if inventory.get(key) is Dictionary: (inventory.get(key) as Dictionary).erase(side)
	if inventory.has_method("_claim"): inventory.call("_claim", side, false)
	item.queue_free()
	if inventory.has_method("_refresh_holding"): inventory.call("_refresh_holding")


## The station (or its shoeing) switched off: its tools (`only` these ids, or all of them when
## empty) leave the world and the briefcase. One in a hand goes once it is put away, or the player
## leaves the spa.
func _put_tools_away(inventory: Node, store: Variant, only: Array) -> void:
	var held: Dictionary = inventory.get("held")
	var loose: Dictionary = inventory.get("loose")
	for entry: Array in BENCH_TOOLS:
		var id := str(entry[0])
		if not only.is_empty() and not id in only: continue
		for token: Variant in loose.keys():
			var item: Variant = loose[token]
			if not is_instance_valid(item) or item in held.values() or str((item as Node).get_meta("item_id", "")) != id: continue
			if store.consume(str(token)):
				loose.erase(token)
				(item as Node).queue_free()
		store.discard(id)


static func _material(color: Color, roughness: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	return material


func _exit_tree() -> void:
	if is_instance_valid(_prop): _prop.queue_free()


# ---------------------------------------------------------------- helpers

func _point() -> Vector3:
	return (_spa.call("venue_transform") as Transform3D) * STATION


func _facing() -> Vector3:
	var forward := (_spa.call("venue_transform") as Transform3D).basis * FACING
	forward.y = 0.0
	return forward.normalized()


func _visit_of(pony: Node) -> Dictionary:
	if not is_instance_valid(_spa) or not is_instance_valid(pony) or not pony.has_meta("spa_client"): return {}
	for visit: Dictionary in (_spa._visits as Dictionary).values():
		if visit.actor == pony: return visit
	return {}


func _farrier() -> Node:
	return get_parent().get_node_or_null("Farrier") if get_parent() != null else null
