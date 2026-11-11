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
##   "heart", "cushion", "arch", "rings": modelled here from the game's own sole, whose rim and shape
##               are kept: the sole's cap is replaced by a recessed floor with real relief (a raised
##               rim, stepped rings, a bulging heart or bean-shaped frog), skinned to the hoof. Heart: a
##               fat heart-shaped frog on a flat sole. Cushion: a soft heart frog in a dished sole.
##               Arch: a stepped two-line rim, squared off and open at the heel, and a bean frog.
##               Rings: terraced concentric rings and a tapering cleft slit.
##
## Switching while a world is open: every pony's hidden rig mesh uses the shared mesh, so it changes
## at once, but the game merges each pony's meshes into a "near" and a "far" mesh once and caches them.
## refresh_ponies() clears those caches and has every pony rebuild hers (the game's own near-mesh
## switch, a few ponies per frame), which can cause a brief hitch.

const BODY_SCENE := "res://world/characters/body_shapes/mare.scn"
const MITTY := "res://mods/mare_care/hooves/mitty_body.res"
const HOOF_BONES := ["pony_finger_L", "pony_finger_R", "pony_hoof_L", "pony_hoof_R"]
const PROCEDURAL := ["heart", "cushion", "arch", "rings"]
## How far the floor is recessed above the rim's bottom (mesh metres); the pads stand out of it.
const RECESS := 0.0055
## The sole cap is found by flood fill from the lowest point across triangles that are all within this
## of it, and face down more than CAP_FLAT (the fraction of a triangle's normal that points down).
const CAP_BAND := 0.012
const CAP_FLAT := 0.35
## Points per original edge segment round the new sole.
const SUBDIVIDE := 3
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
		arrays = _sculpt(_original.arrays, body.skin, want, with_frog)
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
	if applied in PROCEDURAL: return RECESS
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


# ---------------------------------------------------------------- Heart, Cushion, Arch, Rings

## The game's arrays with every hoof's sole cap replaced by a sculpted one.
static func _sculpt(source: Array, skin: Skin, model: String, with_frog: bool) -> Array:
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
	var done := 0
	var drop := {}                       # triangle start offsets to remove
	var original_size := verts.size()
	var original_index_size := index.size()
	for bone_name: String in HOOF_BONES:
		var bind := -1
		for i in skin.get_bind_count():
			if String(skin.get_bind_name(i)) == bone_name: bind = i
		if bind < 0: continue
		var mine := {}
		var low := INF
		for v in original_size:
			var main := -1
			var w := 0.0
			for k in per:
				if weights[v * per + k] > w: w = weights[v * per + k]; main = bones[v * per + k]
			if main == bind:
				mine[v] = true
				low = minf(low, verts[v].y)
		if mine.is_empty(): continue
		# The sole cap: flood fill from the lowest vertex across down-facing triangles near the bottom.
		var hoof_tris: Array[int] = []
		var by_edge := {}
		var seed := -1
		var lowest_vertex := -1
		for v in mine:
			if lowest_vertex < 0 or verts[v].y < verts[lowest_vertex].y: lowest_vertex = v
		for t in range(0, original_index_size, 3):
			var a := index[t]; var b := index[t + 1]; var c := index[t + 2]
			if not (mine.has(a) and mine.has(b) and mine.has(c)): continue
			hoof_tris.append(t)
			for e in [[a, b], [b, c], [c, a]]:
				var key := Vector2i(mini(e[0], e[1]), maxi(e[0], e[1]))
				if not by_edge.has(key): by_edge[key] = []
				(by_edge[key] as Array).append(t)
			if seed < 0 and (a == lowest_vertex or b == lowest_vertex or c == lowest_vertex): seed = t
		var cap: Array[int] = []
		var cross_y := 0.0
		if seed >= 0:
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
				if cap.size() > 0 and signf(n.y) != signf(cross_y): continue
				cap.append(t)
				cross_y += n.y
				for e in [[a, b], [b, c], [c, a]]:
					for other in by_edge[Vector2i(mini(e[0], e[1]), maxi(e[0], e[1]))]:
						if not seen.has(other):
							seen[other] = true
							queue.append(other)
		print("[mare_care] %s: sole cap of %d triangles" % [bone_name, cap.size()])
		if cap.size() < 20: continue
		# Boundary: edges used by exactly one cap triangle, chained into one loop.
		var edges := {}
		for t in cap:
			for e in [[index[t], index[t + 1]], [index[t + 1], index[t + 2]], [index[t + 2], index[t]]]:
				var key := Vector2i(mini(e[0], e[1]), maxi(e[0], e[1]))
				edges[key] = int(edges.get(key, 0)) + 1
		var next := {}
		for key: Vector2i in edges:
			if int(edges[key]) != 1: continue
			for pair in [[key.x, key.y], [key.y, key.x]]:
				if not next.has(pair[0]): next[pair[0]] = []
				(next[pair[0]] as Array).append(pair[1])
		var ok := not next.is_empty()
		for v in next:
			if (next[v] as Array).size() != 2: ok = false
		var loop: Array[int] = []
		if ok:
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
			ok = loop.size() == next.size() and loop.size() >= 12
		if ok: print("[mare_care] %s: sole edge of %d vertices" % [bone_name, loop.size()])
		if not ok:
			print("[mare_care] the %s sole could not be sculpted (its edge is not one simple loop)" % bone_name)
			continue
		for t in cap: drop[t] = true
		# Centre and extent of the sole.
		var centre := Vector2.ZERO
		for v in loop: centre += Vector2(verts[v].x, verts[v].z)
		centre /= loop.size()
		var half := Vector2.ZERO
		for v in loop: half = Vector2(maxf(half.x, absf(verts[v].x - centre.x)), maxf(half.y, absf(verts[v].z - centre.y)))
		var uv_centre := Vector2.ZERO
		for v in loop: uv_centre += uvs[v]
		uv_centre /= loop.size()
		# New vertices: ring by ring from the boundary (the original loop vertices) to the centre. Inside
		# the boundary every ring has SUBDIVIDE times as many points as the edge.
		var n_edge := loop.size()
		var n_ring := n_edge * SUBDIVIDE
		# The edge's own heights are uneven; smoothed, they do not leave creases in the new sole.
		var edge_y: Array[float] = []
		for i in n_edge: edge_y.append(verts[loop[i]].y - low)
		for pass_index in 8:
			var smoothed: Array[float] = []
			for i in n_edge: smoothed.append((edge_y[(i + n_edge - 1) % n_edge] + 2.0 * edge_y[i] + edge_y[(i + 1) % n_edge]) * 0.25)
			edge_y = smoothed
		var edge_mean := 0.0
		for i in n_edge: edge_mean += edge_y[i] / n_edge
		for i in n_edge: edge_y[i] = lerpf(edge_y[i], edge_mean, 0.7)
		var first_new := verts.size()
		var rings: Array = []
		var ring_list := _rings()
		for r in range(1, ring_list.size()):
			var t: float = ring_list[r]
			var row: Array[int] = []
			for m in n_ring:
				var i0 := m / SUBDIVIDE
				var frac := float(m % SUBDIVIDE) / SUBDIVIDE
				var a_v := loop[i0]
				var b_v := loop[(i0 + 1) % n_edge]
				var lv := verts[a_v].lerp(verts[b_v], frac)
				var x := centre.x + (lv.x - centre.x) * t
				var z := centre.y + (lv.z - centre.y) * t
				var angle := atan2(lv.z - centre.y, lv.x - centre.x)
				var edge_height := lerpf(edge_y[i0], edge_y[(i0 + 1) % n_edge], frac)
				var y := low + _height(model, t, angle, (x - centre.x) / half.x, (z - centre.y) / half.y, edge_height, with_frog)
				row.append(verts.size())
				verts.append(Vector3(x, y, z))
				normals.append(Vector3.DOWN)
				tangents.append_array(PackedFloat32Array([1.0, 0.0, 0.0, 1.0]))
				uvs.append(uvs[a_v].lerp(uvs[b_v], frac).lerp(uv_centre, 1.0 - t))
				for k in per:
					bones.append(bind if k == 0 else 0)
					weights.append(1.0 if k == 0 else 0.0)
			rings.append(row)
		var middle := verts.size()
		verts.append(Vector3(centre.x, low + _height(model, 0.0, 0.0, 0.0, 0.0, 0.0, with_frog), centre.y))
		normals.append(Vector3.DOWN)
		tangents.append_array(PackedFloat32Array([1.0, 0.0, 0.0, 1.0]))
		uvs.append(uv_centre)
		for k in per:
			bones.append(bind if k == 0 else 0)
			weights.append(1.0 if k == 0 else 0.0)
		# Triangles, wound the way the game's own cap was.
		var tris: Array[Vector3i] = []
		# From the original edge to the first inner ring: a fan per edge.
		var first: Array = rings[0]
		for i in n_edge:
			var oi := loop[i]
			var oj := loop[(i + 1) % n_edge]
			var q0: int = first[i * SUBDIVIDE]
			var q1: int = first[i * SUBDIVIDE + 1]
			var q2: int = first[i * SUBDIVIDE + 2]
			var q3: int = first[((i + 1) % n_edge) * SUBDIVIDE]
			tris.append(Vector3i(oi, oj, q2))
			tris.append(Vector3i(oi, q2, q1))
			tris.append(Vector3i(oi, q1, q0))
			tris.append(Vector3i(oj, q3, q2))
		for r in rings.size() - 1:
			var outer: Array = rings[r]
			var inner: Array = rings[r + 1]
			for m in n_ring:
				var j := (m + 1) % n_ring
				tris.append(Vector3i(outer[m], outer[j], inner[j]))
				tris.append(Vector3i(outer[m], inner[j], inner[m]))
		var last: Array = rings[rings.size() - 1]
		for m in n_ring:
			tris.append(Vector3i(last[m], last[(m + 1) % n_ring], middle))
		var mine_sum := 0.0
		for tri in tris:
			mine_sum += (verts[tri.y] - verts[tri.x]).cross(verts[tri.z] - verts[tri.x]).y
		var reverse := (mine_sum > 0.0) != (cross_y > 0.0)
		var accum := {}
		for tri in tris:
			var a := tri.x
			var b := tri.z if reverse else tri.y
			var c := tri.y if reverse else tri.z
			index.append(a); index.append(b); index.append(c)
			var n := (verts[b] - verts[a]).cross(verts[c] - verts[a])
			# The game's cap faces down: its winding fixes which way the cross product points outward.
			n = -n if cross_y > 0.0 else n
			for v in [a, b, c]:
				if v >= first_new: accum[v] = (accum.get(v, Vector3.ZERO) as Vector3) + n
		for v in accum: normals[v] = _shade_normal((accum[v] as Vector3).normalized())
		done += 1
	if done == 0: return []
	# Drop the old caps from the index list (offsets are into the original part).
	var kept := PackedInt32Array()
	for t in range(0, index.size(), 3):
		if not (t < original_index_size and drop.has(t)):
			kept.append(index[t]); kept.append(index[t + 1]); kept.append(index[t + 2])
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TANGENT] = tangents
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_BONES] = bones
	arrays[Mesh.ARRAY_WEIGHTS] = weights
	arrays[Mesh.ARRAY_INDEX] = kept
	return arrays


## Radial rings of the new sole, from the boundary inwards (fraction of the way to the centre): close
## together inside, so shapes have vertices to live on.
static func _rings() -> Array:
	var out: Array = [1.0, 0.97, 0.94, 0.91, 0.88]
	var t := 0.86
	while t > 0.09:
		out.append(t)
		t -= 0.022
	out.append(0.05)
	return out


## The game's cartoon shading draws a gentle slope as flat colour and only shows a wall whose normal tips
## well over, so the sideways part of a steep normal is exaggerated and a gentle one flattened.
static func _shade_normal(n: Vector3) -> Vector3:
	var side := Vector2(n.x, n.z)
	var steep := smoothstep(0.18, 0.5, side.length())
	var out := Vector3(n.x * (1.0 + 2.5 * steep), n.y * (1.0 - 0.6 * steep), n.z * (1.0 + 2.5 * steep))
	if steep < 0.01: out = Vector3(0.0, n.y, 0.0)
	return out.normalized()


## Height of the new sole above its lowest point (the rim's bottom) at a point `t` of the way from the
## centre to the boundary, at `angle` round the hoof (0 = +X; the toe is -Z, so the heel is PI / 2),
## in sole coordinates (nx, nz) of about -1..1, where the boundary sits `edge` above the lowest point.
static func _height(model: String, t: float, angle: float, nx: float, nz: float, edge: float, with_frog: bool) -> float:
	var from_heel := absf(wrapf(angle - PI * 0.5, -PI, PI))
	var rim_to_edge := clampf((t - 0.86) / 0.14, 0.0, 1.0)
	var y := edge * rim_to_edge * rim_to_edge * (3.0 - 2.0 * rim_to_edge)
	var floor_y := 0.0           # how high the floor is above the rim's bottom here
	var pad := 0.0                # how far the frog stands out of the floor (0..1 of RECESS)
	match model:
		"heart":
			floor_y = RECESS * _rise(t, 0.93, 0.07)
			if with_frog: pad = 1.0 * _inside(_heart(nx, nz, 1.45, 0.0), 0.07)
		"cushion":
			# A dished sole with a soft rim, and a fat heart with a gentle wall.
			floor_y = RECESS * _rise(t, 0.88, 0.16)
			if with_frog: pad = 1.0 * _inside(_heart(nx, nz, 1.3, 0.0), 0.13)
		"arch":
			# Two steps (the rim's two lines) round the toe and sides, ending square at the heel.
			var gate := smoothstep(0.82, 0.9, from_heel)
			var outer := lerpf(0.99, 0.84, gate)
			var inner := lerpf(0.99, 0.64, gate)
			floor_y = RECESS * (0.45 * _rise(t, outer, 0.035) + 0.55 * _rise(t, inner, 0.035))
			if with_frog: pad = 0.9 * _inside(_heart(nx, nz, 0.62, 0.4), 0.06)
		"rings":
			# Terraced concentric rings, and a cleft slit tapering toward the toe.
			floor_y = RECESS * (0.4 * _rise(t, 0.88, 0.04) + 0.6 * _rise(t, 0.66, 0.04))
			if with_frog: floor_y += RECESS * 0.7 * _wedge(nx, nz) * smoothstep(0.68, 0.6, t)
	pad *= smoothstep(0.8, 0.68, t)
	y = maxf(y, floor_y - RECESS * pad)
	return maxf(y, 0.0)


## 0 outside, 1 inside the radius `at`, over a band of `width` (a wall: steeper when narrow).
static func _rise(t: float, at: float, width: float) -> float:
	return smoothstep(at, at - width, t)


## 1 well inside a shape (negative distance), 0 outside, ramping over `wall`.
static func _inside(distance: float, wall: float) -> float:
	return smoothstep(0.0, -wall, distance)


static func _circle(p: Vector2, centre: Vector2, radius: float) -> float:
	return p.distance_to(centre) - radius


static func _smooth_min(a: float, b: float, k: float) -> float:
	var h := clampf(0.5 + 0.5 * (b - a) / k, 0.0, 1.0)
	return lerpf(b, a, h) - k * h * (1.0 - h)


## The signed distance to a heart (negative inside): rounded lobes at the heel (+z) with a notch between
## them, narrowing to a rounded point toward the toe. `scale` and the heel-ward shift `dz` place it.
static func _heart(nx: float, nz: float, scale: float, dz: float) -> float:
	var right: Array[Vector2] = [Vector2(0.0, -0.45), Vector2(0.07, -0.38), Vector2(0.15, -0.25), Vector2(0.24, -0.1), Vector2(0.31, 0.05), Vector2(0.34, 0.18), Vector2(0.32, 0.3), Vector2(0.25, 0.38), Vector2(0.16, 0.39), Vector2(0.08, 0.33), Vector2(0.03, 0.22), Vector2(0.0, 0.17)]
	var outline: Array[Vector2] = []
	for q in right: outline.append(q * scale + Vector2(0.0, dz))
	for k in range(right.size() - 2, 0, -1): outline.append(Vector2(-right[k].x, right[k].y) * scale + Vector2(0.0, dz))
	var steps := outline.size()
	var p := Vector2(nx, nz)
	var best := INF
	var inside := false
	for k in steps:
		var a := outline[k]
		var b := outline[(k + 1) % steps]
		var ab := b - a
		var u := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.000001), 0.0, 1.0)
		best = minf(best, p.distance_to(a + ab * u))
		if (a.y > p.y) != (b.y > p.y) and p.x < a.x + (p.y - a.y) / (b.y - a.y) * (b.x - a.x): inside = not inside
	return -best if inside else best


## 1 inside a thin wedge: widest at the heel end (z = 0.3), tapering to a point toward the toe (z = -0.12).
static func _wedge(nx: float, nz: float) -> float:
	var along := clampf((nz + 0.12) / 0.42, 0.0, 1.0)
	if nz < -0.12 or nz > 0.3: return 0.0
	return smoothstep(0.075 * along + 0.02, 0.075 * along * 0.4, absf(nx))
