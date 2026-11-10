extends RefCounted
## Borrowed from modChad's Grooming mod (github.com/modChad/home-equestria-mods, grooming/).
## Ponies whose mane and tail are part of the body model (the princesses,
## world/characters/princesses/<id>_body.glb) rather than the separate devkit hair ordinary ponies
## wear. The game's touch body only fits hulls to devkit hair, so for these ponies hair_hit() offers
## the mane and tail as a cloud of points (sampled from their meshes, each held in its main bone's
## frame so it follows her), hit-tested along a ray. Ordinary ponies never reach it.
## (The Grooming mod's stray-feather pinning for preening is left out.)

## Points kept per hair mesh (sampled evenly).
const MAX_POINTS := 900
## How close a ray must pass to a hair point to touch it (metres, at body scale 1).
const RADIUS := 0.045

## pony -> {"has_hulls": bool, "points": [[skeleton bone, local Vector3, "mane"|"tail"], ...]}
var _cache: Dictionary = {}


## True when the game's touch body already has mane and tail hulls for her.
func _has_hulls(pony: Node, touch: Node) -> bool:
	var entries: Variant = touch.get("_entries")
	if not entries is Array or (entries as Array).is_empty(): return true   # not fitted yet: wait
	for e: Variant in entries:
		if e is Dictionary and str((e as Dictionary).get("region", "")) in ["mane", "tail"]: return true
	return false


func _row(pony: Node3D) -> Dictionary:
	if _cache.has(pony): return _cache[pony]
	var row := {"points": []}
	var model: Node = pony.get("_model")
	var skeleton: Skeleton3D = pony.get("skeleton")
	if model != null and skeleton != null:
		for node: Node in model.find_children("*", "MeshInstance3D", true, false):
			var mi := node as MeshInstance3D
			var lower := String(mi.name).to_lower()
			var part := "tail" if "tail" in lower else ("mane" if "mane" in lower else "")
			if part.is_empty() or mi.mesh == null or mi.skin == null: continue
			(row.points as Array).append_array(_sample(mi, skeleton, part))
	_cache[pony] = row
	pony.tree_exiting.connect(func() -> void: _cache.erase(pony), CONNECT_ONE_SHOT)
	return row


## Mesh vertices, each as its main bone plus its place in that bone's rest frame.
static func _sample(mi: MeshInstance3D, skeleton: Skeleton3D, part: String) -> Array:
	var out := []
	var skin := mi.skin
	var total := 0
	for surface in mi.mesh.get_surface_count(): total += mi.mesh.surface_get_array_len(surface)
	var every := maxi(1, total / MAX_POINTS)
	for surface in mi.mesh.get_surface_count():
		var arrays := mi.mesh.surface_get_arrays(surface)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var vb: PackedInt32Array = arrays[Mesh.ARRAY_BONES] if arrays[Mesh.ARRAY_BONES] != null else PackedInt32Array()
		var vw: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS] if arrays[Mesh.ARRAY_WEIGHTS] != null else PackedFloat32Array()
		if verts.is_empty() or vb.size() < verts.size(): continue
		var per := vb.size() / verts.size()
		for v in range(0, verts.size(), every):
			var main := -1
			var weight := 0.0
			for k in per:
				if vw[v * per + k] > weight: weight = vw[v * per + k]; main = vb[v * per + k]
			if main < 0 or main >= skin.get_bind_count(): continue
			var bone := skin.get_bind_bone(main)
			if bone < 0: bone = skeleton.find_bone(skin.get_bind_name(main))
			if bone < 0: continue
			out.append([bone, skin.get_bind_pose(main) * verts[v], part])
	return out


## The mane or tail point nearest along the ray from `from` to `to`, within reach of it.
## {target, point, normal, region, visible_pick} or {}.
func hair_hit(pony: Node3D, from: Vector3, to: Vector3, radius_scale: float = 1.0) -> Dictionary:
	var touch: Node = pony.get("touch_body")
	if touch != null and _has_hulls(pony, touch): return {}
	var row := _row(pony)
	if (row.points as Array).is_empty(): return {}
	var skeleton: Skeleton3D = pony.get("skeleton")
	var size := float(pony.get("body_scale")) if pony.get("body_scale") != null else 1.0
	var radius := RADIUS * size * radius_scale
	var ray := to - from
	var length := ray.length()
	if length < 0.0001: return {}
	var dir := ray / length
	var frames := {}
	var best := {}
	var best_along := INF
	for p: Array in row.points:
		var bone: int = p[0]
		if not frames.has(bone): frames[bone] = skeleton.global_transform * skeleton.get_bone_global_pose(bone)
		var at: Vector3 = (frames[bone] as Transform3D) * Vector3(p[1])
		var along := (at - from).dot(dir)
		if along < 0.0 or along > length or along >= best_along: continue
		if (from + dir * along).distance_to(at) > radius: continue
		best_along = along
		best = {"target": pony, "point": at, "normal": -dir, "region": p[2], "visible_pick": true}
	return best

