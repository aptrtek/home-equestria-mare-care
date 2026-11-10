extends Node3D
## A freshly brushed mane or tail sparkles: little star glints that wink on and off across the hair
## for a while after a finished brushing, then fade away.
##
## How: the hair's vertices are sampled once per pony, each held in its main bone's rest frame
## (the same trick as built_in_hair.gd), so a glint sits on the hair wherever the springs and her
## head have moved it. The glints are one MultiMesh of small camera-facing quads, placed on the CPU
## every frame: a few dozen per pony at most, far cheaper than a particle system per pony, and
## it never touches the hair's own materials (the game merges the hair into one mesh near the
## camera and uses the overlay slot for its ink mask).
##
## One Sparkle node per pony, a child of her. main.gd / brushing.gd call shine("mane" or "tail").

## Seconds a finished brushing keeps the hair sparkling, and how long the last of it fades.
const CARE := preload("res://mods/mare_care/farrier/hoof_care.gd")
## Settings > Mare Care sets the length (CARE.sparkle_minutes) and whether it happens at all.
const FADE := 180.0
## Glints alive at once on a fully sparkling mane (a tail gets the same).
const GLINTS := 18
## A glint's life (seconds) and size (metres at body scale 1).
const LIFE := Vector2(0.45, 1.1)
const SIZE := Vector2(0.07, 0.12)
## Points kept per hair mesh.
const MAX_POINTS := 700
## Beyond this distance from the camera nothing is drawn or placed.
const DRAW_DISTANCE := 18.0
const TINTS := [Color(1.0, 1.0, 1.0), Color(1.0, 0.95, 0.8), Color(0.88, 0.95, 1.0), Color(1.0, 0.88, 0.97)]

var pony: Node3D
## part -> seconds of sparkle left
var _left := {"mane": 0.0, "tail": 0.0}
## part -> [[Skeleton3D, bone, local Vector3, local normal], ...]
var _points := {}
## part -> glints alive at once (GLINTS when not listed)
var _count := {}
var _hair_sampled := false
## part -> glint size factor (1 when not listed)
var _size := {}
var _glints: Array[Dictionary] = []   # {part, point, age, life, size, tint}
var _mm: MultiMesh
var _view: MultiMeshInstance3D
var _rng := RandomNumberGenerator.new()

static var _texture: Texture2D


## The Sparkle under `who`, made on first use.
static func of(who: Node3D) -> Node:
	var found := who.get_node_or_null("MareCareSparkle")
	if found != null: return found
	var made: Node3D = (load("res://mods/mare_care/brushing/sparkle.gd") as Script).new()
	made.name = "MareCareSparkle"
	made.set("pony", who)
	who.add_child(made)
	return made


## Start (or top up) the sparkle on her "mane" or "tail".
func shine(part: String) -> void:
	if not CARE.sparkle_on: return
	_left[part] = CARE.sparkle_minutes * 60.0


## Glints on one bone's part of her body for `seconds` (the farrier's hoof oil: part "hoof_FL" on
## pony_finger_L), `count` alive at once.
func shine_bone(part: String, bone_name: String, seconds: float, count := 5, size := 0.35) -> void:
	_size[part] = size
	if not _points.has(part):
		var model: Node = pony.get("_model")
		var skeleton: Skeleton3D = pony.get("skeleton")
		if model == null or skeleton == null: return
		var bone := skeleton.find_bone(bone_name)
		for node: Node in model.find_children("*", "MeshInstance3D", true, false):
			if String(node.name) == "MareBody": _add(part, node as MeshInstance3D, skeleton, bone)
	_left[part] = seconds
	_count[part] = count


func shining(part: String) -> bool:
	return float(_left.get(part, 0.0)) > 0.0


func _ready() -> void:
	_rng.randomize()
	top_level = true
	global_transform = Transform3D.IDENTITY
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_colors = true
	_mm.physics_interpolation_quality = MultiMesh.INTERP_QUALITY_FAST
	_mm.instance_count = GLINTS * 2 + 24
	_mm.visible_instance_count = 0
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	quad.material = _material()
	_mm.mesh = quad
	_view = MultiMeshInstance3D.new()
	_view.multimesh = _mm
	_view.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_view.name = "Glints"
	# Placed every rendered frame, so no physics-tick interpolation between placements.
	_view.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(_view)


func _process(delta: float) -> void:
	var any := false
	for part: String in _left:
		_left[part] = maxf(0.0, float(_left[part]) - delta)
		if float(_left[part]) > 0.0: any = true
	if not any and _glints.is_empty():
		_mm.visible_instance_count = 0
		return
	if not is_instance_valid(pony) or not pony.is_visible_in_tree():
		_mm.visible_instance_count = 0
		return
	var camera := get_viewport().get_camera_3d()
	if camera == null or camera.global_position.distance_to(pony.global_position) > DRAW_DISTANCE:
		_mm.visible_instance_count = 0
		return
	if not _hair_sampled: _hair_sampled = true; _sample()
	_spawn(camera.global_position)
	_draw(delta, camera)


## How strongly a part sparkles now: 1 for most of SECONDS, easing to 0 over the last FADE.
func _strength(part: String) -> float:
	return clampf(float(_left.get(part, 0.0)) / minf(FADE, CARE.sparkle_minutes * 60.0 * 0.3), 0.0, 1.0)


func _spawn(eye: Vector3) -> void:
	var size := _scale()
	for part: String in _left:
		var list: Array = _points.get(part, [])
		if list.is_empty(): continue
		var want := int(round(int(_count.get(part, GLINTS)) * _strength(part)))
		var have := 0
		for g in _glints:
			if g.part == part: have += 1
		# A few at a time, so they twinkle in rather than all appearing at once.
		for i in mini(want - have, 2):
			_glints.append({"part": part, "point": _facing(list, eye), "age": 0.0,
				"life": _rng.randf_range(LIFE.x, LIFE.y), "size": _rng.randf_range(SIZE.x, SIZE.y) * size * float(_size.get(part, 1.0)),
				"tint": TINTS[_rng.randi_range(0, TINTS.size() - 1)], "spin": _rng.randf_range(-0.6, 0.6)})


## A random hair point on the side of the hair facing the eye (a few tries, then any).
func _facing(list: Array, eye: Vector3) -> Array:
	var pick: Array = list[_rng.randi_range(0, list.size() - 1)]
	for attempt in 8:
		var skeleton: Skeleton3D = pick[0]
		var frame := skeleton.global_transform * skeleton.get_bone_global_pose(int(pick[1]))
		var at: Vector3 = frame * Vector3(pick[2])
		var normal: Vector3 = (frame.basis * Vector3(pick[3])).normalized()
		if normal.dot((eye - at).normalized()) > 0.25: return pick
		pick = list[_rng.randi_range(0, list.size() - 1)]
	return pick


func _draw(delta: float, camera: Camera3D) -> void:
	var view := camera.global_basis.orthonormalized()
	var toward := camera.global_position
	var shown := 0
	var frames := {}
	for i in range(_glints.size() - 1, -1, -1):
		var g: Dictionary = _glints[i]
		g.age = float(g.age) + delta
		if float(g.age) >= float(g.life): _glints.remove_at(i); continue
		if shown >= _mm.instance_count: continue
		var p: Array = g.point
		var skeleton: Skeleton3D = p[0]
		if not is_instance_valid(skeleton): continue
		var key := skeleton.get_instance_id() * 1000 + int(p[1])
		if not frames.has(key): frames[key] = skeleton.global_transform * skeleton.get_bone_global_pose(int(p[1]))
		var at: Vector3 = (frames[key] as Transform3D) * Vector3(p[2])
		# Nudged a hair toward the camera so the glint sits on the surface, not inside it.
		at += (toward - at).normalized() * 0.02
		var t := float(g.age) / float(g.life)
		var twinkle := sin(t * PI)
		var s := float(g.size) * (0.35 + 0.65 * twinkle)
		var basis := view * Basis(Vector3.BACK, float(g.spin) * float(g.age))
		_mm.set_instance_transform(shown, Transform3D(basis.scaled(Vector3.ONE * s), at))
		var c: Color = g.tint
		_mm.set_instance_color(shown, Color(c.r, c.g, c.b, twinkle))
		shown += 1
	_mm.visible_instance_count = shown


func _scale() -> float:
	var body: Variant = pony.get("body_scale")
	return float(body) if body != null else 1.0


## Her mane and tail as points: the devkit hair (ordinary ponies), else the hair built into her body
## model (the princesses).
func _sample() -> void:
	var hair: Node = pony.get("hair")
	var hair_skeleton: Skeleton3D = pony.get("hair_skeleton")
	var identity: Variant = pony.get("identity")
	if hair != null and hair_skeleton != null and identity != null:
		var prefix := str(identity.get("hair_prefix"))
		for part: String in ["mane", "tail"]:
			var mi := hair.find_child(prefix + ("DevkitMane" if part == "mane" else "DevkitTail"), true, false) as MeshInstance3D
			if mi != null: _add(part, mi, hair_skeleton)
	if not _points.has("mane") and not _points.has("tail"):
		var model: Node = pony.get("_model")
		var skeleton: Skeleton3D = pony.get("skeleton")
		if model != null and skeleton != null:
			for node: Node in model.find_children("*", "MeshInstance3D", true, false):
				var lower := String(node.name).to_lower()
				var part := "tail" if "tail" in lower else ("mane" if "mane" in lower else "")
				if not part.is_empty(): _add(part, node as MeshInstance3D, skeleton)


func _add(part: String, mi: MeshInstance3D, skeleton: Skeleton3D, only_bone := -1) -> void:
	if mi.mesh == null or mi.skin == null: return
	var skin := mi.skin
	var total := 0
	for surface in mi.mesh.get_surface_count(): total += mi.mesh.surface_get_array_len(surface)
	var every := maxi(1, total / MAX_POINTS) if only_bone < 0 else 1
	var list: Array = _points.get(part, [])
	for surface in mi.mesh.get_surface_count():
		var arrays := mi.mesh.surface_get_arrays(surface)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL] if arrays[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
		var vb: PackedInt32Array = arrays[Mesh.ARRAY_BONES] if arrays[Mesh.ARRAY_BONES] != null else PackedInt32Array()
		var vw: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS] if arrays[Mesh.ARRAY_WEIGHTS] != null else PackedFloat32Array()
		if verts.is_empty() or vb.size() < verts.size(): continue
		var per := vb.size() / verts.size()
		for v in range(_rng.randi_range(0, every - 1), verts.size(), every):
			var main := -1
			var weight := 0.0
			for k in per:
				if vw[v * per + k] > weight: weight = vw[v * per + k]; main = vb[v * per + k]
			if main < 0 or main >= skin.get_bind_count(): continue
			var bone := skin.get_bind_bone(main)
			if bone < 0: bone = skeleton.find_bone(skin.get_bind_name(main))
			if bone < 0 or (only_bone >= 0 and bone != only_bone): continue
			var bind := skin.get_bind_pose(main)
			var normal := (bind.basis * normals[v]).normalized() if v < normals.size() else Vector3.ZERO
			list.append([skeleton, bone, bind * verts[v], normal])
	if not list.is_empty(): _points[part] = list


## Additive, unlit glints drawn from a small star texture made once.
func _material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = _star()
	m.disable_fog = true
	m.disable_receive_shadows = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


## A four-point star with a soft glow, white on clear.
static func _star() -> Texture2D:
	if _texture != null: return _texture
	var n := 64
	var image := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var c := (n - 1) * 0.5
	for y in n:
		for x in n:
			var dx := absf(x - c) / c
			var dy := absf(y - c) / c
			var r := sqrt(dx * dx + dy * dy)
			var glow := pow(maxf(0.0, 1.0 - r * 1.6), 2.0) * 0.9
			var rays := maxf(pow(maxf(0.0, 1.0 - dx), 2.5) * pow(maxf(0.0, 1.0 - dy * 9.0), 1.5),
				pow(maxf(0.0, 1.0 - dy), 2.5) * pow(maxf(0.0, 1.0 - dx * 9.0), 1.5))
			var core := pow(maxf(0.0, 1.0 - r * 3.0), 1.2)
			var a := clampf(glow + rays + core, 0.0, 1.0)
			image.set_pixel(x, y, Color(1, 1, 1, a))
	image.generate_mipmaps()
	_texture = ImageTexture.create_from_image(image)
	return _texture
