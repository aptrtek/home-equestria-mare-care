extends RefCounted
## Her four hooves: where each sole is, lifting a hoof for the farrier and letting it down.
##
## Legs go by the game's names (pony_gait_profile.gd): FL, FR (front), RL, RR (hind). A hoof's
## bone is the one its capsule is skinned to: pony_finger_<side> in front, pony_hoof_<side> behind.
##
## The sole frame of a hoof is found once per body mesh: the body's vertices on that hoof bone,
## the lowest ring of them at rest is the sole. Its frame is held in the hoof bone's rest frame
## (through the skin's bind pose), so it follows the hoof wherever it goes, lifted or walking.
## Frame: origin at the middle of the sole, +Y up into the hoof, -Z toward the toe, as the body
## mesh stands at rest.

const LEGS := ["FL", "FR", "RL", "RR"]
const NAMES := {"FL": "front left", "FR": "front right", "RL": "back left", "RR": "back right"}
const BONES := {"FL": "pony_finger_L", "FR": "pony_finger_R", "RL": "pony_hoof_L", "RR": "pony_hoof_R"}
## How high above the lowest vertex still counts as the sole ring (mesh metres).
const SOLE_BAND := 0.012
## How long a lift holds before she puts the hoof down by herself (seconds).
const LIFT_SECONDS := 600.0
const RESERVE := "mare_care:farrier"
## A front hoof for the farrier: the knee a little higher than her talking raise, and the cannon
## folded back further, so the sole turns up and back toward you. Joint limits have the last word.
const FRONT_LIFT := 0.07   # extra knee lift, metres at body scale 1
const FRONT_CURL_DEG := -125.0

## mesh RID -> {leg: {"bone": int, "local": Transform3D, "width": float, "length": float}}
static var _soles: Dictionary = {}


## {leg: {bone, local, width, length}} for her body, or {} if her body isn't the usual one.
static func soles(pony: Node3D) -> Dictionary:
	var model: Node = pony.get("_model")
	var skeleton: Skeleton3D = pony.get("skeleton")
	if model == null or skeleton == null: return {}
	var mi := _body_mesh(model, skeleton)
	if mi == null: return {}
	var key := mi.mesh.get_rid().get_id()
	if _soles.has(key): return _soles[key]
	var out := {}
	for leg: String in LEGS:
		var bone_name: String = BONES[leg]
		var bind := -1
		for i in mi.skin.get_bind_count():
			var name := String(mi.skin.get_bind_name(i))
			if name == bone_name or (name.is_empty() and mi.skin.get_bind_bone(i) == skeleton.find_bone(bone_name)): bind = i; break
		if bind < 0: continue
		var points := PackedVector3Array()
		for surface in mi.mesh.get_surface_count():
			var arrays := mi.mesh.surface_get_arrays(surface)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			if arrays[Mesh.ARRAY_BONES] == null: continue
			var vb: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
			var vw: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
			var per := vb.size() / verts.size()
			for v in verts.size():
				var main := -1
				var weight := 0.0
				for k in per:
					if vw[v * per + k] > weight: weight = vw[v * per + k]; main = vb[v * per + k]
				if main == bind: points.append(verts[v])
		if points.is_empty(): continue
		var low := INF
		for p in points: low = minf(low, p.y)
		var box := AABB()
		var first := true
		for p in points:
			if p.y > low + SOLE_BAND: continue
			if first: box = AABB(p, Vector3.ZERO); first = false
			else: box = box.expand(p)
		var centre := Vector3(box.get_center().x, low, box.get_center().z)
		out[leg] = {"bone": skeleton.find_bone(bone_name), "local": mi.skin.get_bind_pose(bind) * Transform3D(Basis.IDENTITY, centre),
			"width": box.size.x, "length": box.size.z}
	_soles[key] = out
	return out


## The body mesh with the hooves: the biggest skinned mesh on her body skeleton.
static func _body_mesh(model: Node, skeleton: Skeleton3D) -> MeshInstance3D:
	var best: MeshInstance3D = null
	for node: Node in model.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null or mi.skin == null: continue
		if String(mi.name) == "MareBody": return mi
		if best == null or mi.mesh.get_faces().size() > best.mesh.get_faces().size(): best = mi
	return best


## The sole frame of `leg` in the world now, or an invalid transform (origin INF).
## Read through a BoneAttachment3D: the skeleton's own bone poses don't include what her leg
## solvers do to them (a lifted hoof), the attachment follows the pose as drawn.
static func sole(pony: Node3D, leg: String) -> Transform3D:
	var marker := _marker(pony, leg)
	return marker.global_transform if marker != null else Transform3D(Basis.IDENTITY, Vector3.INF)


static func _marker(pony: Node3D, leg: String) -> Node3D:
	var skeleton: Skeleton3D = pony.get("skeleton")
	if skeleton == null: return null
	var found := skeleton.get_node_or_null("MareCareSole_" + leg)
	if found != null: return found.get_child(0) as Node3D
	var all := soles(pony)
	if not all.has(leg): return null
	var row: Dictionary = all[leg]
	var attachment := BoneAttachment3D.new()
	attachment.name = "MareCareSole_" + leg
	skeleton.add_child(attachment)
	attachment.bone_idx = int(row.bone)
	var marker := Node3D.new()
	marker.transform = row.local
	attachment.add_child(marker)
	# A new attachment only follows its bone from the skeleton's next update: catch it up now, or
	# this first reading is the bone at rest.
	attachment.on_skeleton_update()
	return marker


## The point in the middle of the sole's underside, nudged out of the hoof (world).
static func sole_point(pony: Node3D, leg: String) -> Vector3:
	var frame := sole(pony, leg)
	if not frame.origin.is_finite(): return Vector3.INF
	return frame.origin - frame.basis.y.normalized() * 0.002


static func scale_of(pony: Node3D) -> float:
	var s: Variant = pony.get("body_scale")
	return float(s) if s != null else 1.0


## The profile index of `leg`, or -1.
static func leg_index(pony: Node3D, leg: String) -> int:
	var profile: Variant = pony.get("profile")
	if profile == null: return -1
	for i in profile.legs.size():
		if String(profile.legs[i].name) == leg: return i
	return -1


## The leg she has up for us now, or "".
static func raised(pony: Node3D) -> String:
	var hold: Variant = pony.get("hoof_hold")
	if hold == null or int(hold.leg_index) < 0 or not hold.active(): return ""
	var profile: Variant = pony.get("profile")
	return String(profile.legs[int(hold.leg_index)].name)


## Asks her to lift `leg`: a front hoof is raised and curled the way she raises it to talk, a hind
## hoof is lifted back and up. False if she can't right now (held, sitting, already lifting one).
static func lift(pony: Node3D, leg: String) -> bool:
	var hold: Variant = pony.get("hoof_hold")
	# Ponies with the full leg rig only (Spike's hoof_hold is a stub without lifts).
	if hold == null or not hold.has_method("raise") or not hold.has_method("kick") or pony.get("profile") == null: return false
	if raised(pony) == leg: return true
	if int(hold.leg_index) >= 0:
		if hold.active(): hold.release()
		return false   # the other hoof is still going down; ask again in a moment
	# Sitting or lying down: she gets up first (ask again once she's standing).
	var posture: Variant = pony.get("posture")
	if posture != null and posture.active():
		if pony.has_method("request_posture"): pony.call("request_posture", "stand")
		return false
	var side := 0 if leg.ends_with("L") else 1
	var ok: bool = hold.raise(side, LIFT_SECONDS) if leg.begins_with("F") else hold.kick(side, LIFT_SECONDS)
	if ok and leg.begins_with("F"):
		hold.set("curl", deg_to_rad(FRONT_CURL_DEG))
		var goal: Variant = hold.get("_gesture_local")
		if goal is Vector3 and (goal as Vector3).is_finite():
			hold.set("_gesture_local", Vector3(goal) + Vector3.UP * FRONT_LIFT * scale_of(pony))
	if ok: hold_still(pony, true)
	return ok


static func lower(pony: Node3D) -> void:
	var hold: Variant = pony.get("hoof_hold")
	if hold != null and hold.active(): hold.release()
	hold_still(pony, false)


## While she has a hoof up for us, nothing else walks her off (the navigator's own reservation,
## as the courier uses). Not for a spa client: the spa's lease already holds her, and a reservation
## would take her navigator from the spa and end her visit.
static func hold_still(pony: Node3D, on: bool) -> void:
	if on and pony.has_meta("spa_client"): return
	var nav := pony.get_node_or_null("Navigator")
	if nav == null: return
	if on and nav.has_method("reserve"): nav.reserve(RESERVE, [RESERVE])
	elif not on and nav.has_method("release_reservation"): nav.release_reservation(RESERVE)
