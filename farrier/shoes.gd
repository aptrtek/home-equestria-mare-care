extends Node
## The horseshoes on her hooves. Every pony whose save record says a hoof is shod wears that
## shoe, in its style, on a BoneAttachment3D that follows the hoof bone: walking, trotting,
## lifted for the farrier. A shoe that has worked loose (its reset is due, hoof_care.gd) sits a
## little crooked with its nail heads standing proud, until it's re-nailed.
##
## While the farrier works a hoof, farrier.gd shows the shoe being fitted through fitting().

const MODELS := preload("res://mods/mare_care/farrier/models.gd")
const HOOVES := preload("res://mods/mare_care/farrier/hooves.gd")
const CARE := preload("res://mods/mare_care/farrier/hoof_care.gd")
## Seconds between looks over the ponies in the world.
const SCAN := 1.5
## Drawn up to this far from the camera (they're small).
const VISIBLE_TO := 25.0
const NODE := "MareCareShoe_"

var mod_id := "mare_care"
var _clock := 0.0
## pony -> {leg: {style, nails (Array[bool] shown), loose}} that farrier.gd is showing right now
var _fitting := {}
static var _materials := {}
static var _nail_mesh: Mesh
static var _nail_materials := {}


func _process(delta: float) -> void:
	_clock -= delta
	if _clock > 0.0: return
	_clock = SCAN
	refresh_all()


func refresh_all() -> void:
	var game: Node = Mods.game
	if not is_instance_valid(game): return
	var mares: Variant = game.get("mares")
	if not mares is Array: return
	for pony: Variant in mares:
		if is_instance_valid(pony) and (pony as Node3D).is_inside_tree(): refresh(pony)


## Shows a shoe being fitted on `leg` (nails: one bool per nail, true once it's driven home), or
## clears it with an empty style.
func fitting(pony: Node3D, leg: String, style: String, nails: Array) -> void:
	if not _fitting.has(pony): _fitting[pony] = {}
	if style.is_empty(): (_fitting[pony] as Dictionary).erase(leg)
	else: _fitting[pony][leg] = {"style": style, "nails": nails.duplicate(), "loose": false}
	refresh(pony)


## Puts each of her hooves' shoes on, off or right, from her save record and any fitting.
func refresh(pony: Node3D) -> void:
	var id := pony_id(pony)
	var skeleton: Skeleton3D = pony.get("skeleton")
	if id.is_empty() or skeleton == null: return
	var state := Mods.state(mod_id)
	var record: Dictionary = (state.get("hooves", {}) as Dictionary).get(id, {})
	var shown: Dictionary = _fitting.get(pony, {})
	for leg: String in HOOVES.LEGS:
		var want := {}
		if shown.has(leg):
			want = shown[leg]
		else:
			var hoof: Dictionary = record.get(leg, {})
			var style := str(hoof.get("shoe", ""))
			if not style.is_empty():
				var loose := CARE.due(hoof, "shoe")
				var nails := []
				for i in MODELS.NAIL_COUNT: nails.append(not loose)
				want = {"style": style, "nails": nails, "loose": loose}
		_show(pony, skeleton, leg, want)


func _show(pony: Node3D, skeleton: Skeleton3D, leg: String, want: Dictionary) -> void:
	var node := skeleton.get_node_or_null(NODE + leg) as BoneAttachment3D
	if want.is_empty():
		if node != null: node.queue_free()
		return
	var key := "%s|%s|%s" % [want.style, str(want.nails), str(want.loose)]
	if node != null and str(node.get_meta("key", "")) == key: return
	var soles := HOOVES.soles(pony)
	if not soles.has(leg): return
	var row: Dictionary = soles[leg]
	if node == null:
		node = BoneAttachment3D.new()
		node.name = NODE + leg
		skeleton.add_child(node)
		node.bone_idx = int(row.bone)
	for child in node.get_children(): child.queue_free()
	node.set_meta("key", key)
	var width: float = float(row.width) * 0.94
	var length_scale: float = clampf(float(row.length) / (width * 1.1), 0.8, 1.25)
	var thick := width * 0.07
	var holder := Node3D.new()
	# The shoe's top face against the sole, half sunk into the hoof so it never floats.
	var tilt := Basis(Vector3.RIGHT, deg_to_rad(10.0)).rotated(Vector3.FORWARD, deg_to_rad(6.0)) if bool(want.loose) else Basis.IDENTITY
	holder.transform = Transform3D(row.local) * Transform3D(tilt, Vector3.ZERO) * Transform3D(Basis.from_scale(Vector3(1, 1, length_scale)), Vector3.ZERO)
	node.add_child(holder)
	var shoe := MeshInstance3D.new()
	shoe.name = "Shoe"
	shoe.mesh = MODELS.shoe_mesh(width)
	shoe.material_override = _material(str(want.style))
	shoe.visibility_range_end = VISIBLE_TO
	shoe.position = Vector3(0, -thick * 0.5, 0)
	holder.add_child(shoe)
	# Nail heads on the ground face: flush once driven, standing proud until then.
	var points := MODELS.nail_points(width)
	var nails: Array = want.nails
	for i in points.size():
		var nail := MeshInstance3D.new()
		nail.name = "Nail%d" % i
		nail.mesh = _nail()
		nail.material_override = _nail_mat(str(want.style))
		nail.visibility_range_end = VISIBLE_TO
		var driven: bool = i < nails.size() and bool(nails[i])
		var s := width / 0.11
		nail.transform = Transform3D(Basis.from_scale(Vector3.ONE * s), points[i] + Vector3(0, -thick * 0.5 - (0.0005 if driven else 0.006) * s, 0))
		holder.add_child(nail)


## Where nail `i` of the shoe on `leg` is (world), for the hammer.
func nail_point(pony: Node3D, leg: String, i: int) -> Vector3:
	var skeleton: Skeleton3D = pony.get("skeleton")
	if skeleton == null: return Vector3.INF
	var node := skeleton.get_node_or_null(NODE + leg) as BoneAttachment3D
	if node == null or node.get_child_count() == 0: return Vector3.INF
	var nail := (node.get_child(0) as Node3D).get_node_or_null("Nail%d" % i) as Node3D
	return nail.global_position if nail != null else Vector3.INF


static func pony_id(pony: Node) -> String:
	var id := str(pony.get_meta("relationship_id", ""))
	if id.is_empty():
		var identity: Variant = pony.get("identity")
		if identity != null: id = str(identity.get("id"))
	return id


static func _material(style: String) -> Material:
	if not _materials.has(style): _materials[style] = MODELS.shoe_material(style)
	return _materials[style]


static func _nail() -> Mesh:
	if _nail_mesh == null:
		# Small, low heads: nails hold a shoe on, they are not meant to stand out.
		var c := CylinderMesh.new()
		c.top_radius = 0.0021; c.bottom_radius = 0.0027; c.height = 0.0035; c.radial_segments = 10; c.rings = 1
		_nail_mesh = c
	return _nail_mesh


## A nail head in the shoe's own metal, a shade darker, so it reads as part of the shoe.
static func _nail_mat(style: String) -> Material:
	if not _nail_materials.has(style):
		var m := StandardMaterial3D.new()
		var shoe := _material(style) as StandardMaterial3D
		var base := shoe.albedo_color if style != "rainbow" else Color("8a8fa0")
		m.albedo_color = base.darkened(0.3)
		m.metallic = 0.55
		m.roughness = 0.4
		_nail_materials[style] = m
	return _nail_materials[style]


## The mod switched off: every shoe comes off with it.
func _exit_tree() -> void:
	var game: Node = Mods.game
	if not is_instance_valid(game): return
	var mares: Variant = game.get("mares")
	if not mares is Array: return
	for pony: Variant in mares:
		if not is_instance_valid(pony): continue
		var skeleton: Skeleton3D = pony.get("skeleton")
		if skeleton == null: continue
		for leg: String in HOOVES.LEGS:
			for prefix: String in [NODE, "MareCareSole_"]:
				var node := skeleton.get_node_or_null(prefix + leg)
				if node != null: node.queue_free()
