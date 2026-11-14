extends Node
## A farrier station at Aloe and Lotus's spa: the last stop of a visit, where the player picks out,
## trims, shoes and oils a client's hooves with Mare Care's own tools.
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
const CADDY_AT := Vector3(1.0, 0.36, -3.85)
## Walked off the mat further than this (a chat, a bump), she walks back.
const DRIFT := 0.6
const TRAVEL_SECONDS := 120.0
## The spa's own patience (spa_customers.gd PATIENCE): work on her, or waiting for the station,
## keeps her this much longer.
const PATIENCE := 300.0
const CHECK_SECONDS := 0.25
## Jobs that bring a client to the station, and the tools each one needs switched on.
const JOB_TOOLS := {"pick": ["hoof_pick"], "trim": ["nippers", "rasp"], "shoe": ["hammer"], "oil": ["hoof_oil"]}
const JOB_WORDS := {"pick": "picking", "trim": "a trim", "shoe": "a shoe reset", "oil": "oil"}

var mod_id := "mare_care"
var _spa: Node
var _owner_id := ""
## Clients this has taken over: id -> actor, to settle up with the ones who leave half shod.
var _taken := {}
var _prop: Node3D
var _check := 0.0


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


## The jobs due on any of her hooves whose tools the player has.
func _wanted(pony_id: String, with_trim: bool) -> Array:
	var out := []
	var hooves := CARE.hooves(mod_id, pony_id)
	for job: String in ["pick", "trim", "shoe", "oil"]:
		if job == "trim" and not with_trim: continue
		var tools_on := true
		for tool: String in JOB_TOOLS[job]: tools_on = tools_on and CARE.tool_on(tool)
		if not tools_on: continue
		for leg: String in HOOVES.LEGS:
			if CARE.due(hooves.get(leg, {}), job):
				out.append(job); break
	return out


# ---------------------------------------------------------------- per tick

func _physics_process(delta: float) -> void:
	if not is_instance_valid(_spa):
		_spa = null
		return
	_build_prop()
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


## Everything she came for is done on all four hooves, and she isn't shod on only some.
func _finished(visit: Dictionary) -> bool:
	var hooves := CARE.hooves(mod_id, str(visit.id))
	var bare := 0
	for leg: String in HOOVES.LEGS:
		var record: Dictionary = hooves.get(leg, {})
		if str(record.get("shoe", "")).is_empty(): bare += 1
		for job: String in visit.get("farrier_jobs", []):
			if CARE.due(record, job): return false
	return bare == 0 or bare == 4


func _finish(visit: Dictionary) -> void:
	var id := str(visit.id)
	print("[mare_care] %s is done at the farrier station" % id)
	_taken.erase(id)
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
		if not bare.is_empty() and bare.size() < 4: farrier.call("_left_uneven", pony)


# ---------------------------------------------------------------- the station itself

## A rubber mat where she stands and a farrier's caddy with the tools in it, in the venue's space.
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
	_prop.add_child(_caddy())


## An open wooden tool box with a handle, the hammer, rasp, nippers and pick standing in it.
func _caddy() -> Node3D:
	var caddy := Node3D.new()
	caddy.name = "Caddy"
	caddy.position = CADDY_AT
	caddy.rotation.y = deg_to_rad(20.0)
	var wood := _material(MODELS.WOOD, 0.8)
	var size := Vector3(0.46, 0.16, 0.24)
	for part: Array in [
			[Vector3(size.x, 0.015, size.z), Vector3(0, 0.0075, 0)],
			[Vector3(size.x, size.y, 0.015), Vector3(0, size.y * 0.5, size.z * 0.5)],
			[Vector3(size.x, size.y, 0.015), Vector3(0, size.y * 0.5, -size.z * 0.5)],
			[Vector3(0.015, size.y + 0.12, size.z), Vector3(size.x * 0.5, (size.y + 0.12) * 0.5, 0)],
			[Vector3(0.015, size.y + 0.12, size.z), Vector3(-size.x * 0.5, (size.y + 0.12) * 0.5, 0)]]:
		var board := MeshInstance3D.new()
		var mesh := BoxMesh.new(); mesh.size = part[0]
		board.mesh = mesh
		board.material_override = wood
		board.position = part[1]
		caddy.add_child(board)
	var handle := MeshInstance3D.new()
	var bar := CylinderMesh.new(); bar.top_radius = 0.012; bar.bottom_radius = 0.012; bar.height = size.x
	handle.mesh = bar
	handle.material_override = wood
	handle.rotation.z = PI * 0.5
	handle.position = Vector3(0, size.y + 0.1, 0)
	caddy.add_child(handle)
	# Handles down in the box, working ends up (the models hold their grip at the origin, the
	# working end toward -Z).
	var x := -0.16
	for kind: String in ["hammer", "rasp", "nippers", "hoof_pick"]:
		var tool := MODELS.build(kind)
		tool.rotation = Vector3(PI * 0.5 - 0.25, 0.0, 0.0)
		tool.position = Vector3(x, 0.03, -0.04 if kind in ["rasp", "hoof_pick"] else 0.04)
		caddy.add_child(tool)
		x += 0.105
	return caddy


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
