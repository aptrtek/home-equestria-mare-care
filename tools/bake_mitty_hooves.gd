extends SceneTree
## Bakes one of Mitty's hoof models into two small resources the mod loads (farrier/body_hooves.gd):
## the MareBody mesh from his .glb, and its skin (for the bone names). Run from the game project:
##   1. copy the .glb from hooves/source/ to res://tmp_mitty/hooves.glb and run
##      godot --headless --xr-mode off --path <project> --import
##   2. godot --headless --xr-mode off --path <project> --script res://mods/mare_care/tools/bake_mitty_hooves.gd
##      Environment: BAKE_OUT, the output mesh (default res://tmp_mitty/mitty_body.res).
##   3. move the output .res and its _skin.res into the mod's hooves/ folder, and delete tmp_mitty.
##
## A file exported without its rig (no skin: the puffy-frog hooves) borrows its bone weights from the
## rigged Mitty's model already in the mod: each vertex takes the weights of the nearest vertex there.
## That works because both are the game's body with only the hooves changed: the rest of the body
## matches vertex for vertex, and every new hoof vertex lies on (or next to) the old hoof.
const SRC := "res://tmp_mitty/hooves.glb"
const RIGGED := "res://mods/mare_care/hooves/mitty_body.res"
## Grid cell for the nearest-vertex search (mesh metres).
const CELL := 0.01


func _initialize() -> void:
	run.call_deferred()


func run() -> void:
	var out := OS.get_environment("BAKE_OUT") if OS.get_environment("BAKE_OUT") != "" else "res://tmp_mitty/mitty_body.res"
	var root := (load(SRC) as PackedScene).instantiate()
	var body: MeshInstance3D = null
	for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		if String(mi.name) == "MareBody": body = mi
	var arrays := body.mesh.surface_get_arrays(0)
	var skin: Skin
	if body.skin != null:
		skin = Skin.new()
		for i in body.skin.get_bind_count():
			skin.add_named_bind(String(body.skin.get_bind_name(i)), body.skin.get_bind_pose(i))
	else:
		print("[bake] no rig in the file: borrowing bone weights from ", RIGGED)
		skin = load(RIGGED.get_basename() + "_skin.res") as Skin
		if not _borrow_weights(arrays, (load(RIGGED) as ArrayMesh).surface_get_arrays(0)):
			root.free()
			quit(1)
			return
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.resource_name = out.get_file().get_basename()
	print("[bake] %d vertices; mesh %s" % [(arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size(), ResourceSaver.save(mesh, out, ResourceSaver.FLAG_COMPRESS)])
	print("[bake] skin ", ResourceSaver.save(skin, out.get_basename() + "_skin.res", ResourceSaver.FLAG_COMPRESS))
	root.free()
	quit()


## Gives `arrays` the bones and weights of the nearest vertex in `rigged`. False if a vertex has none.
func _borrow_weights(arrays: Array, rigged: Array) -> bool:
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var ov: PackedVector3Array = rigged[Mesh.ARRAY_VERTEX]
	var ob: PackedInt32Array = rigged[Mesh.ARRAY_BONES]
	var ow: PackedFloat32Array = rigged[Mesh.ARRAY_WEIGHTS]
	var per := ob.size() / ov.size()
	var grid := {}
	for i in ov.size():
		var k := _cell(ov[i])
		if not grid.has(k): grid[k] = PackedInt32Array()
		grid[k].append(i)   # in place: a cast (as PackedInt32Array) would append to a copy
	var bones := PackedInt32Array(); bones.resize(verts.size() * per)
	var weights := PackedFloat32Array(); weights.resize(verts.size() * per)
	var exact := 0
	var worst := 0.0
	for i in verts.size():
		var p := verts[i]
		var c := _cell(p)
		var best := -1
		var bd := INF
		for r in 4:   # rings of cells outward until the nearest is certainly found
			for dx in range(-r, r + 1):
				for dy in range(-r, r + 1):
					for dz in range(-r, r + 1):
						if maxi(absi(dx), maxi(absi(dy), absi(dz))) != r: continue
						var cell: Variant = grid.get(c + Vector3i(dx, dy, dz))
						if cell == null: continue
						for j: int in cell:
							var d := p.distance_squared_to(ov[j])
							if d < bd: bd = d; best = j
			if best >= 0 and sqrt(bd) <= r * CELL: break
		if best < 0:
			push_error("[bake] vertex %d at %s has no rigged vertex within %d cm: not baked" % [i, p, 4 * int(CELL * 100)])
			return false
		if sqrt(bd) < 0.0001: exact += 1
		worst = maxf(worst, sqrt(bd))
		for k in per:
			bones[i * per + k] = ob[best * per + k]
			weights[i * per + k] = ow[best * per + k]
	print("[bake] weights: %d of %d vertices match exactly; the farthest is %.1f mm from a rigged vertex" % [exact, verts.size(), worst * 1000.0])
	arrays[Mesh.ARRAY_BONES] = bones
	arrays[Mesh.ARRAY_WEIGHTS] = weights
	return true


func _cell(p: Vector3) -> Vector3i:
	return Vector3i(floori(p.x / CELL), floori(p.y / CELL), floori(p.z / CELL))
