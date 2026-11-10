extends SceneTree
## Saves the farrier tool models the game's item visual loads. Run from the project root:
##   godot --headless --xr-mode off --path . --script res://mods/mare_care/farrier/tools/make_farrier_models.gd
## Prints each model's bounds centre (the game centres a held model on its bounds; farrier.gd
## works that out itself, this is for reference).
const MODELS := preload("res://mods/mare_care/farrier/models.gd")

func _initialize() -> void: run.call_deferred()

func run() -> void:
	for kind: String in MODELS.KINDS:
		var root: Node3D = MODELS.build(kind)
		var packed := PackedScene.new()
		packed.pack(root)
		var path := "res://mods/mare_care/farrier/models/%s.scn" % kind
		print(path, " ", ResourceSaver.save(packed, path), " centre ", _bounds(root).get_center())
		root.free()
	quit()

func _bounds(root: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		var b: AABB = mi.transform * mi.mesh.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box
