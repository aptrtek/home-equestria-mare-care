extends SceneTree
## Bakes Mitty's hooves into two small resources the mod loads (farrier/body_hooves.gd): the
## MareBody mesh from his hooves.glb, and its skin (for the bone names). Run from the game project:
##   1. copy hooves/source/mitty_hooves.glb to res://tmp_mitty/hooves.glb and run
##      godot --headless --xr-mode off --path <project> --import
##   2. godot --headless --xr-mode off --path <project> --script res://mods/mare_care/tools/bake_mitty_hooves.gd
##   3. move res://tmp_mitty/mitty_body.res and mitty_body_skin.res into the mod's hooves/ folder,
##      and delete tmp_mitty.
const SRC := "res://tmp_mitty/hooves.glb"
const OUT := "res://tmp_mitty/mitty_body.res"


func _initialize() -> void:
	run.call_deferred()


func run() -> void:
	var root := (load(SRC) as PackedScene).instantiate()
	var body: MeshInstance3D = null
	for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		if String(mi.name) == "MareBody": body = mi
	var arrays := body.mesh.surface_get_arrays(0)
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.resource_name = "mitty_body"
	print("mesh ", ResourceSaver.save(mesh, OUT, ResourceSaver.FLAG_COMPRESS))
	var skin := Skin.new()
	for i in body.skin.get_bind_count():
		skin.add_named_bind(String(body.skin.get_bind_name(i)), body.skin.get_bind_pose(i))
	print("skin ", ResourceSaver.save(skin, OUT.get_basename() + "_skin.res", ResourceSaver.FLAG_COMPRESS))
	root.free()
	quit()
