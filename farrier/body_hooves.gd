extends RefCounted
## Hoof models that live in the body mesh itself.
##
## The adult mare's body is one shared mesh (body_shapes/mare.scn, MareBody), the same for every
## adult pony including the Mare Fair mares. A hoof model replaces that mesh's surface in memory, so
## the hooves are part of the body: they move, scale, shade, outline and cast shadows with her, in
## every pose and at every distance. Nothing in the game's files changes, and "original" puts the
## game's own surface back.
##
##   "mitty":    the hooves from Mitty's hooves.glb (hooves/mitty_body.res, baked by
##               tools/bake_mitty_hooves.gd). His skin lists the bones in a different order from the
##               game's, so each vertex's bone indices are remapped by bone name.
##   "classic", "round": line-art hooves made here from the game's own sole, which is left exactly as
##               it is. The shapes of the references (a rim line, the frog's outline and its cleft)
##               are added as thin raised ridges in the same mesh, skinned to the hoof: the game's
##               cartoon shading draws a gentle surface as one flat colour, but thickens its outline
##               around a thin ridge, so the ridges read as clean drawn lines. Classic: a closed rim
##               line and an anatomical frog with a cleft. Round: an arch-shaped rim that is open at the
##               heel, and a rounded, bean-shaped frog with a cleft.
##
## Switching while a world is open: every pony's hidden rig mesh uses the shared mesh, so it changes
## at once, but the game merges each pony's meshes into a "near" and a "far" mesh once and caches them.
## refresh_ponies() clears those caches and has every pony rebuild hers (the game's own near-mesh
## switch, a few ponies per frame), which can cause a brief hitch.

const BODY_SCENE := "res://world/characters/body_shapes/mare.scn"
const MITTY := "res://mods/mare_care/hooves/mitty_body.res"
const HOOF_BONES := ["pony_finger_L", "pony_finger_R", "pony_hoof_L", "pony_hoof_R"]
const PROCEDURAL := ["heart", "cushion", "arch", "rings"]
## The lines: ridge width and how far each stands out of the sole (mesh metres). The sole is not
## flat (it domes down toward the middle), so a ridge never stands out further than the sole's own
## height above its lowest point.
const LINE_WIDTH := 0.0026
const LINE_HEIGHT := 0.0035
## The sole cap is found by flood fill from the lowest point across triangles that are all within this
## of it, and face down more than CAP_FLAT (the fraction of a triangle's normal that points down).
const CAP_BAND := 0.012
const CAP_FLAT := 0.35
## Points per original edge segment along a line, and per run of a contour.
const LINE_STEPS := 3
## Ponies rebuilt per step, and the pause between steps (seconds).
const REBUILD_BATCH := 2
const REBUILD_PAUSE := 0.12

static var _original: Dictionary = {}
static var applied := "original"
static var applied_frog := true
static var rebuilding := false


## The adult body's mesh and skin from the shared scene: {mesh, skin}, or {} if it is not as expected.
## Both are shared resources, so they stay valid after the scene instance is freed.
static func _body() -> Dictionary:
	var scene := load(BODY_SCENE) as PackedScene
	if scene == null:
		print("[mare_care] the adult body scene did not load")
		return {}
	var root := scene.instantiate()
	var out := {}
	for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		if String(mi.name) == "MareBody" and mi.mesh is ArrayMesh and mi.skin != null and mi.mesh.get_surface_count() == 1:
			out = {"mesh": mi.mesh, "skin": mi.skin}
	root.free()
	return out


## True when `model` (with or without the frog) is not what the body mesh carries now.
static func needs_change(model: String, with_frog := true) -> bool:
	var want := model if (model == "mitty" or model in PROCEDURAL) else "original"
	if want != applied: return true
	return want in PROCEDURAL and with_frog != applied_frog


## Puts `model`'s hooves into the body mesh (`with_frog` false leaves the frog out). True when the
## mesh now carries them; false, with the mesh left as it was, if anything is not as expected.
static func apply(model: String, with_frog := true) -> bool:
	var want := model if (model == "mitty" or model in PROCEDURAL) else "original"
	if not needs_change(model, with_frog): return true
	var body := _body()
	if body.is_empty():
		print("[mare_care] the adult body mesh is not as expected: hoof model left as it was")
		return false
	var mesh: ArrayMesh = body.mesh
	if _original.is_empty():
		_original = {"arrays": mesh.surface_get_arrays(0), "format": mesh.surface_get_format(0), "material": mesh.surface_get_material(0)}
	var arrays: Array = (_original.arrays as Array).duplicate(true)
	var flags: int = int(_original.format) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS
	if want == "mitty":
		arrays = _load_arrays(MITTY, body.skin, int((_original.arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()))
		flags = 0
	elif want in PROCEDURAL:
		arrays = _draw_lines(_original.arrays, body.skin, want, with_frog)
	if arrays.is_empty():
		print("[mare_care] hoof model %s could not be built: using the game's own" % want)
		return false
	var material: Material = _original.material
	mesh.clear_surfaces()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, flags)
	mesh.surface_set_material(0, material)
	applied = want
	applied_frog = with_frog
	print("[mare_care] body hooves: %s (%d vertices)" % [want, (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()])
	return true


## How far the floor of the current hoof's sole is recessed (mesh metres): where dirt sits.
static func floor_height() -> float:
	return 0.004 if applied == "mitty" else 0.0


# ---------------------------------------------------------------- rebuilding the ponies

## Forgets the game's merged near and far meshes, so ponies built or asked to rebuild from now on use
## the body mesh as it is.
static func clear_caches() -> void:
	var near: Script = load("res://world/characters/hybrid_mare/hybrid_near_mesh.gd")
	var far: Script = load("res://world/characters/hybrid_mare/hybrid_far_mesh.gd")
	if near != null:
		near.call("discard_pending")
		(near.get("cache") as Dictionary).clear()
	if far != null:
		for name in ["cache", "shadow_cache"]:
			var table: Variant = far.get(name)
			if table is Dictionary: (table as Dictionary).clear()


## Has every pony in the world rebuild her merged meshes from the (new) body mesh. Runs over several
## frames; `done` (if valid) is called when it has finished. Safe to call with nothing to do.
static func refresh_ponies(tree: SceneTree, done := Callable()) -> void:
	if rebuilding or tree == null:
		return
	rebuilding = true
	clear_caches()
	var ponies: Array = []
	for node: Node in tree.root.find_children("*", "", true, false):
		if node.has_method("set_near_mesh") and node.get("near_mesh_enabled") != null and node.get("_model") != null:
			ponies.append(node)
	var handled := 0
	for pony: Variant in ponies:
		if not is_instance_valid(pony): continue
		var was_on: bool = bool(pony.get("near_mesh_enabled"))
		if was_on:
			pony.call("set_near_mesh", false)
			pony.call("set_near_mesh", true)
		# A pony showing her far mesh drops it and gathers a new one.
		if bool(pony.get("_far_mesh_shown")) and pony.has_method("_show_far_mesh"):
			pony.call("_show_far_mesh", null, false)
			pony.set("_far_mesh_waiting", true)
		handled += 1
		if handled % REBUILD_BATCH == 0:
			await tree.create_timer(REBUILD_PAUSE).timeout
	print("[mare_care] rebuilt the meshes of %d ponies for the new hooves" % handled)
	rebuilding = false
	if done.is_valid(): done.call()


# ---------------------------------------------------------------- Mitty's

## The baked mesh's arrays with bone indices remapped onto the game's skin, or [] if it cannot be used.
static func _load_arrays(path: String, game_skin: Skin, game_vertices: int) -> Array:
	var baked := load(path) as ArrayMesh
	var baked_skin := load(path.get_basename() + "_skin.res") as Skin
	if baked == null or baked_skin == null or baked.get_surface_count() != 1: return []
	var arrays := baked.surface_get_arrays(0)
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	if bones.is_empty() or verts.is_empty() or bones.size() % verts.size() != 0: return []
	var game_index := {}
	for i in game_skin.get_bind_count(): game_index[String(game_skin.get_bind_name(i))] = i
	var map := PackedInt32Array()
	map.resize(baked_skin.get_bind_count())
	for i in baked_skin.get_bind_count():
		var name := String(baked_skin.get_bind_name(i))
		if not game_index.has(name):
			print("[mare_care] bone %s is not in the game's rig: hoof model not used" % name)
			return []
		map[i] = int(game_index[name])
	for k in bones.size():
		var b := bones[k]
		bones[k] = map[b] if b >= 0 and b < map.size() else 0
	arrays[Mesh.ARRAY_BONES] = bones
	if absi(verts.size() - game_vertices) > game_vertices / 4:
		print("[mare_care] baked body has %d vertices against the game's %d: hoof model not used" % [verts.size(), game_vertices])
		return []
	return arrays


# ---------------------------------------------------------------- Classic and Round

## The game's arrays with the lines of `model` added to every hoof's sole (the sole itself unchanged).
static func _draw_lines(source: Array, skin: Skin, model: String, with_frog: bool) -> Array:
	var arrays: Array = source.duplicate(true)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var tangents: PackedFloat32Array = arrays[Mesh.ARRAY_TANGENT]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	var index: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	if verts.is_empty() or bones.is_empty() or index.is_empty() or tangents.is_empty() or uvs.is_empty(): return []
	var per := bones.size() / verts.size()
	var original_size := verts.size()
	var original_index_size := index.size()
	var done := 0
	for bone_name: String in HOOF_BONES:
		var bind := -1
		for i in skin.get_bind_count():
			if String(skin.get_bind_name(i)) == bone_name: bind = i
		if bind < 0: continue
		var cap := _find_cap(verts, index, original_size, original_index_size, bones, weights, per, bind)
		if cap.is_empty():
			print("[mare_care] the %s sole was not found: no lines drawn" % bone_name)
			continue
		var loop: Array = cap.loop
		var centre: Vector2 = cap.centre
		var half: Vector2 = cap.half
		var low: float = cap.low
		var cross_y: float = cap.cross_y
		var tris: Array = cap.tris
		var contours := _contours(model, with_frog, loop, verts, centre, half)
		for contour: Dictionary in contours:
			_ridge(contour.points, bool(contour.closed), verts, normals, tangents, uvs, bones, weights, index, per, bind, tris, low, cross_y, centre)
		done += 1
	if done == 0: return []
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TANGENT] = tangents
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_BONES] = bones
	arrays[Mesh.ARRAY_WEIGHTS] = weights
	arrays[Mesh.ARRAY_INDEX] = index
	return arrays


## One hoof's sole cap: {tris: [[a, b, c] vertex triples], loop: edge vertices in order, centre, half,
## low, cross_y}, or {} if it is not as expected.
static func _find_cap(verts: PackedVector3Array, index: PackedInt32Array, vertex_count: int, index_count: int, bones: PackedInt32Array, weights: PackedFloat32Array, per: int, bind: int) -> Dictionary:
	var mine := {}
	var low := INF
	var lowest := -1
	for v in vertex_count:
		var main := -1
		var w := 0.0
		for k in per:
			if weights[v * per + k] > w: w = weights[v * per + k]; main = bones[v * per + k]
		if main == bind:
			mine[v] = true
			if verts[v].y < low: low = verts[v].y; lowest = v
	if lowest < 0: return {}
	var by_edge := {}
	var seed := -1
	for t in range(0, index_count, 3):
		var a := index[t]; var b := index[t + 1]; var c := index[t + 2]
		if not (mine.has(a) and mine.has(b) and mine.has(c)): continue
		for e in [[a, b], [b, c], [c, a]]:
			var key := Vector2i(mini(e[0], e[1]), maxi(e[0], e[1]))
			if not by_edge.has(key): by_edge[key] = []
			(by_edge[key] as Array).append(t)
		if seed < 0 and (a == lowest or b == lowest or c == lowest): seed = t
	if seed < 0: return {}
	var cap_offsets: Array[int] = []
	var cross_y := 0.0
	var seen := {seed: true}
	var queue: Array[int] = [seed]
	var qi := 0
	while qi < queue.size():
		var t := queue[qi]
		qi += 1
		var a := index[t]; var b := index[t + 1]; var c := index[t + 2]
		var n := (verts[b] - verts[a]).cross(verts[c] - verts[a])
		if n.length() < 0.0000001: continue
		if maxf(verts[a].y, maxf(verts[b].y, verts[c].y)) > low + CAP_BAND: continue
		if absf(n.y) < CAP_FLAT * n.length(): continue
		if cap_offsets.size() > 0 and signf(n.y) != signf(cross_y): continue
		cap_offsets.append(t)
		cross_y += n.y
		for e in [[a, b], [b, c], [c, a]]:
			for other in by_edge[Vector2i(mini(e[0], e[1]), maxi(e[0], e[1]))]:
				if not seen.has(other):
					seen[other] = true
					queue.append(other)
	if cap_offsets.size() < 20: return {}
	# Its edge: edges used by exactly one cap triangle, chained into one loop.
	var edges := {}
	for t in cap_offsets:
		for e in [[index[t], index[t + 1]], [index[t + 1], index[t + 2]], [index[t + 2], index[t]]]:
			var key := Vector2i(mini(e[0], e[1]), maxi(e[0], e[1]))
			edges[key] = int(edges.get(key, 0)) + 1
	var next := {}
	for key: Vector2i in edges:
		if int(edges[key]) != 1: continue
		for pair in [[key.x, key.y], [key.y, key.x]]:
			if not next.has(pair[0]): next[pair[0]] = []
			(next[pair[0]] as Array).append(pair[1])
	if next.is_empty(): return {}
	for v in next:
		if (next[v] as Array).size() != 2: return {}
	var loop: Array = []
	var start: int = next.keys().min()
	var prev := -1
	var cur := start
	for guard in next.size() + 1:
		loop.append(cur)
		var options: Array = next[cur]
		var step: int = options[0] if options[0] != prev else options[1]
		prev = cur
		cur = step
		if cur == start: break
	if loop.size() != next.size() or loop.size() < 12: return {}
	var centre := Vector2.ZERO
	for v in loop: centre += Vector2(verts[v].x, verts[v].z)
	centre /= loop.size()
	var half := Vector2.ZERO
	for v in loop: half = Vector2(maxf(half.x, absf(verts[v].x - centre.x)), maxf(half.y, absf(verts[v].z - centre.y)))
	var tris: Array = []
	for t in cap_offsets: tris.append([index[t], index[t + 1], index[t + 2]])
	return {"tris": tris, "loop": loop, "centre": centre, "half": half, "low": low, "cross_y": cross_y}


## The lines of a model, as polylines in the sole's own coordinates:
## [{points: Array[Vector2] (x, z in mesh space), closed: bool}]. Each follows one of the references.
static func _contours(model: String, with_frog: bool, loop: Array, verts: PackedVector3Array, centre: Vector2, half: Vector2) -> Array:
	var out: Array = []
	match model:
		"heart":
			# A fat heart-shaped frog on a plain sole.
			if with_frog: _add(out, _heart(1.6), true, centre, half)
		"cushion":
			# A heart-shaped frog and one rim line round the toe and sides.
			var arc := _arc(_ring(loop, verts, centre, 0.88), centre, 0.8)
			if arc.size() > 4: out.append({"points": arc, "closed": false})
			if with_frog: _add(out, _heart(1.3), true, centre, half)
		"arch":
			# A rim drawn as two lines, open at the heel and squared off there, and a bean-shaped frog.
			var outer := _arc(_ring(loop, verts, centre, 0.9), centre, 0.95)
			var inner := _arc(_ring(loop, verts, centre, 0.68), centre, 0.95)
			if outer.size() > 4 and inner.size() > 4:
				out.append({"points": outer, "closed": false})
				out.append({"points": inner, "closed": false})
				out.append({"points": [outer[0], inner[0]], "closed": false})
				out.append({"points": [outer[outer.size() - 1], inner[inner.size() - 1]], "closed": false})
			if with_frog:
				_add(out, _bean_outline(), true, centre, half)
				_add(out, _cleft_line(true), false, centre, half)
		"rings":
			# Two concentric rings and a thin cleft slit.
			out.append({"points": _ring(loop, verts, centre, 0.84), "closed": true})
			out.append({"points": _ring(loop, verts, centre, 0.62), "closed": true})
			if with_frog:
				var slit: Array[Vector2] = []
				for k in 9: slit.append(Vector2(0.0, lerpf(-0.12, 0.26, float(k) / 8.0)))
				_add(out, slit, false, centre, half)
	return out


## Lines in the sole's fractions (x and z in half-widths about the centre) added as mesh-space contours.
static func _add(out: Array, shape: Array[Vector2], closed: bool, centre: Vector2, half: Vector2) -> void:
	var points: Array[Vector2] = []
	for p: Vector2 in shape: points.append(Vector2(centre.x + p.x * half.x, centre.y + p.y * half.y))
	out.append({"points": points, "closed": closed})


## The sole's own outline, pulled in to `scale` of the way to the centre, smoothed to a clean curve.
static func _ring(loop: Array, verts: PackedVector3Array, centre: Vector2, scale: float) -> Array[Vector2]:
	var around: Array[Vector2] = []
	for i in loop.size():
		var a: Vector3 = verts[loop[i]]
		var b: Vector3 = verts[loop[(i + 1) % loop.size()]]
		for k in LINE_STEPS:
			var p := a.lerp(b, float(k) / LINE_STEPS)
			around.append(centre + (Vector2(p.x, p.z) - centre) * scale)
	var n := around.size()
	for pass_index in 6:
		var smoothed: Array[Vector2] = []
		for i in n: smoothed.append((around[(i + n - 2) % n] + around[(i + n - 1) % n] * 2.0 + around[i] * 3.0 + around[(i + 1) % n] * 2.0 + around[(i + 2) % n]) / 9.0)
		around = smoothed
	return around


## The longest run of the ring that is at least `gap` radians from the heel (+z): an arch open at the heel.
static func _arc(around: Array[Vector2], centre: Vector2, gap: float) -> Array[Vector2]:
	var run: Array[Vector2] = []
	var best: Array[Vector2] = []
	for pass_index in 2:
		for p in around:
			var d := p - centre
			if absf(wrapf(atan2(d.y, d.x) - PI * 0.5, -PI, PI)) >= gap: run.append(p)
			else:
				if run.size() > best.size(): best = run.duplicate()
				run.clear()
	if run.size() > best.size(): best = run.duplicate()
	return best


## A heart: rounded lobes at the heel (+z) with a notch between them, narrowing to a rounded point
## toward the toe.
static func _heart(scale: float) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var steps := 36
	for k in steps:
		var t := TAU * float(k) / steps
		var hx := 16.0 * pow(sin(t), 3.0)
		var hy := 13.0 * cos(t) - 5.0 * cos(2.0 * t) - 2.0 * cos(3.0 * t) - cos(4.0 * t)
		out.append(Vector2(hx / 16.0 * 0.4, (hy + 2.5) / 14.5 * 0.45) * scale)
	return out


## The frog's outline, anatomical (the references): a rounded point toward the toe widening to two
## rounded heel bulbs with a notch between them. In sole coordinates, half-widths and half-lengths
## (x across, z toward the heel; the toe is at -z).
static func _frog_outline() -> Array[Vector2]:
	var right: Array[Vector2] = [
		Vector2(0.0, -0.5), Vector2(0.06, -0.485), Vector2(0.11, -0.43), Vector2(0.14, -0.34), Vector2(0.17, -0.22),
		Vector2(0.21, -0.08), Vector2(0.26, 0.06), Vector2(0.3, 0.2), Vector2(0.33, 0.32), Vector2(0.34, 0.43),
		Vector2(0.32, 0.52), Vector2(0.26, 0.565), Vector2(0.18, 0.56), Vector2(0.1, 0.52), Vector2(0.05, 0.46), Vector2(0.0, 0.4)]
	return _mirrored(right)


## The round model's frog: a bean, rounded all round, with a notch at the heel.
static func _bean_outline() -> Array[Vector2]:
	var right: Array[Vector2] = []
	var n := 12
	for i in n + 1:
		var a := PI * float(i) / n     # toe (0) round the right side to the heel (PI)
		var angle := -PI * 0.5 + a
		right.append(Vector2(cos(angle) * 0.3, 0.02 + sin(angle) * 0.5))
	right[n] = Vector2(0.03, 0.43)     # the notch
	return _mirrored(right)


## A right-hand half run from the toe (x = 0) to the heel notch (x = 0), as one closed outline.
static func _mirrored(right: Array[Vector2]) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for p in right: out.append(p)
	for i in range(right.size() - 2, 0, -1): out.append(Vector2(-right[i].x, right[i].y))
	return out


## The cleft: a line from the heel notch up the frog's middle.
static func _cleft_line(round_model: bool) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var steps := 8
	var from_z := 0.42 if not round_model else 0.43
	var to_z := -0.08 if not round_model else 0.0
	for i in steps + 1: out.append(Vector2(0.0, lerpf(from_z, to_z, float(i) / steps)))
	return out


## The sole's height (y) at (x, z), from the cap's triangles; the nearest vertex's if outside them.
static func _surface_y(point: Vector2, tris: Array, verts: PackedVector3Array) -> float:
	var best := INF
	var best_y := 0.0
	for tri: Array in tris:
		var a: Vector3 = verts[tri[0]]; var b: Vector3 = verts[tri[1]]; var c: Vector3 = verts[tri[2]]
		var v0 := Vector2(b.x - a.x, b.z - a.z)
		var v1 := Vector2(c.x - a.x, c.z - a.z)
		var v2 := Vector2(point.x - a.x, point.y - a.z)
		var den := v0.x * v1.y - v1.x * v0.y
		if absf(den) < 0.0000000001: continue
		var u := (v2.x * v1.y - v1.x * v2.y) / den
		var w := (v0.x * v2.y - v2.x * v0.y) / den
		if u >= -0.0001 and w >= -0.0001 and u + w <= 1.0001:
			return a.y + (b.y - a.y) * u + (c.y - a.y) * w
		for corner in [a, b, c]:
			var dist := Vector2(corner.x, corner.z).distance_to(point)
			if dist < best: best = dist; best_y = corner.y
	return best_y


## Adds a thin raised ridge along a polyline on the sole, wound the way the game's own sole is.
static func _ridge(points: Array, closed: bool, verts: PackedVector3Array, normals: PackedVector3Array, tangents: PackedFloat32Array, uvs: PackedVector2Array, bones: PackedInt32Array, weights: PackedFloat32Array, index: PackedInt32Array, per: int, bind: int, tris: Array, low: float, cross_y: float, centre: Vector2) -> void:
	var n := points.size()
	if n < 2: return
	var sections: Array = []   # per point: [left, peak, right] vertex indices
	var uv_centre := Vector2.ZERO
	for tri: Array in tris: uv_centre += uvs[tri[0]]
	uv_centre /= tris.size()
	for i in n:
		var here: Vector2 = points[i]
		var before: Vector2 = points[(i + n - 1) % n] if (closed or i > 0) else here
		var after: Vector2 = points[(i + 1) % n] if (closed or i < n - 1) else here
		var along := (after - before)
		if along.length() < 0.0000001: along = Vector2(1, 0)
		along = along.normalized()
		var perp := Vector2(-along.y, along.x)
		var surface := _surface_y(here, tris, verts)
		var height := LINE_HEIGHT
		var row: Array[int] = []
		for part in 3:
			var side := (1.0 if part == 0 else (0.0 if part == 1 else -1.0))
			var at := here + perp * (LINE_WIDTH * 0.5) * side
			var y := surface - (height if part == 1 else 0.0)
			row.append(verts.size())
			verts.append(Vector3(at.x, y, at.y))
			var nrm := Vector3(perp.x * side * 0.6, -0.8, perp.y * side * 0.6).normalized()
			normals.append(nrm)
			tangents.append_array(PackedFloat32Array([1.0, 0.0, 0.0, 1.0]))
			uvs.append(uv_centre)
			for k in per:
				bones.append(bind if k == 0 else 0)
				weights.append(1.0 if k == 0 else 0.0)
		sections.append(row)
	var last := n if closed else n - 1
	var quads: Array = []
	for i in last:
		var a: Array = sections[i]
		var b: Array = sections[(i + 1) % n]
		quads.append([a[0], a[1], b[1], b[0]])
		quads.append([a[1], a[2], b[2], b[1]])
	for quad: Array in quads:
		for pair in [[quad[0], quad[1], quad[2]], [quad[0], quad[2], quad[3]]]:
			var a: int = pair[0]; var b: int = pair[1]; var c: int = pair[2]
			# Both ways round, so the ridge shows whichever way the line runs.
			index.append(a); index.append(b); index.append(c)
			index.append(a); index.append(c); index.append(b)
