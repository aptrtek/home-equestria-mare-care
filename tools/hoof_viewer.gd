extends SceneTree
## A standalone viewer for the hoof models, drawn by the game's own pony rendering (its cartoon
## shading and outlines), so the pictures match what a player sees. No world: a base-game mare
## stands in a bare scene, the camera sits under the floor looking up at her hind-left sole, and a
## light shines up from below. Each model is applied to the body mesh, the game's merged-mesh caches
## are cleared, and a fresh pony is built, once bare and once wearing a horseshoe.
##
## Run from the game project (the mod staged at res://mods/mare_care), with a window:
##   godot --xr-mode off --path <project> --mod-src mare_care --script res://mods/mare_care/tools/hoof_viewer.gd
## Environment (all optional): VIEW_OUT (output png), VIEW_MODELS (comma list, default all four),
## VIEW_THUMBS (a folder: also saves each model's bare hoof there as hoof_<model>.png, the settings
## thumbnails), VIEW_PONY (a scene under res://world/characters/mane6/, default applejack).
## Use a scratch APPDATA so the real profile's settings are not touched.
const BODY := preload("res://mods/mare_care/farrier/body_hooves.gd")
const MODELS := preload("res://mods/mare_care/farrier/models.gd")
const HOOVES := preload("res://mods/mare_care/farrier/hooves.gd")
const LEG := "RL"
const LABELS := {"original": "Original", "detailed": "Detailed", "soft": "Soft", "mitty": "Mitty's"}
const CELL := Vector2i(560, 480)

var world: Node3D
var camera: Camera3D
var pony: Node3D
var shoe: MeshInstance3D


func _initialize() -> void:
	run.call_deferred()


func run() -> void:
	root.size = CELL
	_build_world()
	var wanted: PackedStringArray = OS.get_environment("VIEW_MODELS").split(",") if OS.get_environment("VIEW_MODELS") != "" else PackedStringArray(["original", "detailed", "soft", "mitty"])
	var shots := {}
	for model in wanted:
		BODY.apply(model, true)
		BODY.clear_caches()
		await _new_pony()
		for shod in [false, true]:
			shoe.visible = shod
			for i in 40:
				_aim()           # she keeps settling: follow her
				await process_frame
			await RenderingServer.frame_post_draw
			await RenderingServer.frame_post_draw
			shots[model + ("_shod" if shod else "_bare")] = root.get_texture().get_image()
		print("[view] ", model, " done")
	_thumbs(wanted, shots)
	await _compose(wanted, shots)
	quit()


## A bare scene: sky colour, an invisible floor (collision only), a light shining up from below.
func _build_world() -> void:
	world = Node3D.new()
	root.add_child(world)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("2a1d40")
	var env_node := WorldEnvironment.new(); env_node.environment = environment; world.add_child(env_node)
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new(); box.size = Vector3(40, 1, 40)
	shape.shape = box; shape.position = Vector3(0, -0.5, 0)
	floor_body.add_child(shape)
	world.add_child(floor_body)
	var below := DirectionalLight3D.new()
	below.rotation_degrees = Vector3(55, 25, 0)    # shines up and across
	world.add_child(below)
	var above := DirectionalLight3D.new()
	above.rotation_degrees = Vector3(-50, 35, 0)
	above.light_energy = 0.5
	world.add_child(above)
	camera = Camera3D.new()
	camera.fov = 30
	camera.far = 50.0
	world.add_child(camera)
	camera.current = true
	shoe = MeshInstance3D.new()
	shoe.visible = false
	world.add_child(shoe)


## A fresh pony, built from the body mesh as it is now.
func _new_pony() -> void:
	if is_instance_valid(pony):
		pony.queue_free()
		await process_frame
	var scene := "res://world/characters/mane6/%s.tscn" % (OS.get_environment("VIEW_PONY") if OS.get_environment("VIEW_PONY") != "" else "applejack")
	pony = (load(scene) as PackedScene).instantiate()
	world.add_child(pony)
	pony.global_position = Vector3.ZERO
	for i in 240: await process_frame
	for leg in HOOVES.LEGS: HOOVES.sole_point(pony, leg)   # creates the sole markers
	_place_shoe()


func _place_shoe() -> void:
	var soles := HOOVES.soles(pony)
	if not soles.has(LEG): return
	var row: Dictionary = soles[LEG]
	var width := float(row.width) * 0.94
	shoe.mesh = MODELS.shoe_mesh(width)
	shoe.material_override = MODELS.shoe_material("silver")
	var thick := width * 0.07
	shoe.global_transform = HOOVES.sole(pony, LEG) * Transform3D(Basis.from_scale(Vector3(1, 1, clampf(float(row.length) / (width * 1.1), 0.8, 1.25))), Vector3(0, -thick * 0.5, 0))


## The camera under the floor, looking up at the sole with the toe at the top of the picture. (The shoe
## follows the hoof, so it is placed again here in case she has settled.)
func _aim() -> void:
	var frame := HOOVES.sole(pony, LEG)
	var sole := frame.origin
	var toe := -pony.global_basis.z.normalized()
	camera.global_position = sole + Vector3(0, -0.34, 0) - toe * 0.02
	camera.look_at(sole, toe)
	_place_shoe()


func _thumbs(models: PackedStringArray, shots: Dictionary) -> void:
	var folder := OS.get_environment("VIEW_THUMBS")
	if folder == "": return
	for model in models:
		var img: Image = (shots[model + "_bare"] as Image).duplicate()
		img = img.get_region(Rect2i(0, 30, CELL.x, CELL.x * 3 / 4))
		img.resize(448, 336, Image.INTERPOLATE_LANCZOS)
		img.save_png(folder.path_join("hoof_%s.png" % model))
		print("[view] thumbnail ", model)


func _compose(models: PackedStringArray, shots: Dictionary) -> void:
	var margin := 16
	var title := 56
	var width := models.size() * (CELL.x + margin) + margin
	var height := title + 2 * (CELL.y + margin) + margin
	world.queue_free()
	await process_frame
	root.size = Vector2i(width, height)
	var back := ColorRect.new(); back.color = Color("1d1230"); back.size = Vector2(width, height); root.add_child(back)
	for i in models.size():
		var x := margin + i * (CELL.x + margin)
		var label := Label.new()
		label.text = str(LABELS.get(models[i], models[i]))
		label.add_theme_font_size_override("font_size", 34)
		label.position = Vector2(x + 4, 8)
		root.add_child(label)
		for row in 2:
			var key: String = models[i] + ("_bare" if row == 0 else "_shod")
			if not shots.has(key): continue
			var rect := TextureRect.new()
			rect.texture = ImageTexture.create_from_image(shots[key])
			rect.position = Vector2(x, title + row * (CELL.y + margin))
			rect.size = Vector2(CELL)
			root.add_child(rect)
	for i in 4: await process_frame
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var path := OS.get_environment("VIEW_OUT") if OS.get_environment("VIEW_OUT") != "" else "res://tmp_view/all_hooves_viewer.png"
	print("[view] saved ", path, " ", root.get_texture().get_image().save_png(path))
