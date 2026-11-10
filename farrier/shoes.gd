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
## pony -> {leg: true} hooves showing their frog right now (lifted for the farrier)
var _frogs := {}
const JEWEL_NODE := "MareCareJewel_"
const FROG_NODE := "MareCareFrog_"
## Gems and bands sit this high up the hoof wall (fraction of the hoof's width above the sole).
const BAND_HEIGHT := 0.16
const GEM_HEIGHT := 0.36
static var _frog_material := {}
## The hoof wall's rim stands this far out below the sole on a lifted hoof (fraction of its width),
## and the shoe on a lifted hoof sits on it.
const RIM_DEPTH := 0.07
const RIM_WALL := 0.09
const RIM_NODE := "MareCareRim_"

static var _materials := {}
static var _nail_mesh: Mesh
static var _nail_material: Material


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
				for i in 6: nails.append(not loose)
				want = {"style": style, "nails": nails, "loose": loose}
		_show(pony, skeleton, leg, want)
		_show_jewels(pony, skeleton, leg, str((record.get(leg, {}) as Dictionary).get("jewel", "")))
		var up := bool((_frogs.get(pony, {}) as Dictionary).get(leg, false))
		_show_frog(pony, skeleton, leg, CARE.show_frog and up)
		_show_rim(pony, skeleton, leg, up)


func _show(pony: Node3D, skeleton: Skeleton3D, leg: String, want: Dictionary) -> void:
	var node := skeleton.get_node_or_null(NODE + leg) as BoneAttachment3D
	if want.is_empty():
		if node != null: node.queue_free()
		return
	var lifted := bool((_frogs.get(pony, {}) as Dictionary).get(leg, false))
	var key := "%s|%s|%s|%s" % [want.style, str(want.nails), str(want.loose), str(lifted)]
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
	var tilt := Basis(Vector3.RIGHT, deg_to_rad(5.0)).rotated(Vector3.FORWARD, deg_to_rad(3.0)) if bool(want.loose) else Basis.IDENTITY
	var rim_drop := float(row.width) * RIM_DEPTH if lifted else 0.0
	holder.transform = Transform3D(row.local) * Transform3D(tilt, Vector3.DOWN * rim_drop) * Transform3D(Basis.from_scale(Vector3(1, 1, length_scale)), Vector3.ZERO)
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
		nail.material_override = _nail_material
		nail.visibility_range_end = VISIBLE_TO
		var driven: bool = i < nails.size() and bool(nails[i])
		var s := width / 0.11
		nail.transform = Transform3D(Basis.from_scale(Vector3.ONE * s), points[i] + Vector3(0, -thick * 0.5 - (0.0005 if driven else 0.006) * s, 0))
		holder.add_child(nail)


## Shows her frog on `leg` while the hoof is up (farrier.gd), or hides it.
func frog(pony: Node3D, leg: String, on: bool) -> void:
	if not _frogs.has(pony): _frogs[pony] = {}
	if on: _frogs[pony][leg] = true
	else: (_frogs[pony] as Dictionary).erase(leg)
	refresh(pony)


func _attachment(skeleton: Skeleton3D, node_name: String, bone: int) -> BoneAttachment3D:
	var node := skeleton.get_node_or_null(node_name) as BoneAttachment3D
	if node == null:
		node = BoneAttachment3D.new()
		node.name = node_name
		skeleton.add_child(node)
		node.bone_idx = bone
		node.on_skeleton_update()
	return node


## The gems and band of `design` (models.gd JEWELS) on her hoof, or none.
func _show_jewels(pony: Node3D, skeleton: Skeleton3D, leg: String, design: String) -> void:
	var node := skeleton.get_node_or_null(JEWEL_NODE + leg)
	if design.is_empty() or not MODELS.JEWELS.has(design):
		if node != null: node.queue_free()
		return
	if node != null and str(node.get_meta("design", "")) == design: return
	var soles := HOOVES.soles(pony)
	if not soles.has(leg): return
	var row: Dictionary = soles[leg]
	var attachment := _attachment(skeleton, JEWEL_NODE + leg, int(row.bone))
	for child in attachment.get_children(): child.queue_free()
	attachment.set_meta("design", design)
	var holder := Node3D.new()
	holder.transform = row.local
	attachment.add_child(holder)
	var spec: Dictionary = MODELS.JEWELS[design]
	var width: float = row.width
	var gem_size := width * 0.17
	if str(spec.band) != "":
		var band_ring := HOOVES.ring(pony, leg, width * BAND_HEIGHT)
		if not band_ring.is_empty():
			var band := MeshInstance3D.new()
			band.mesh = MODELS.band_mesh(band_ring, width * 0.09, width * 0.008)
			band.material_override = MODELS.band_material(str(spec.band))
			band.visibility_range_end = VISIBLE_TO
			holder.add_child(band)
	var gem_ring := HOOVES.ring(pony, leg, width * GEM_HEIGHT)
	for g: Array in spec.wall:
		if gem_ring.is_empty(): break
		# The toe is -Z: angle -90 degrees in the ring's terms; designs count from the toe.
		var angle := deg_to_rad(-90.0 + float(g[0]))
		var step := int(round(fposmod(angle, TAU) / TAU * HOOVES.RING_STEPS)) % HOOVES.RING_STEPS
		var at: Vector3 = gem_ring[step][0]
		var out: Vector3 = gem_ring[step][1]
		holder.add_child(_gem(str(g[1]), gem_size, at + out * gem_size * 0.15, out))
	var sole_gems: Array = spec.sole
	for i in sole_gems.size():
		# Around the frog, in an arc toward the toe and down the sides.
		var a := deg_to_rad(lerpf(-150.0, -30.0, float(i) / maxf(1.0, sole_gems.size() - 1)))
		var at := Vector3(cos(a) * width * 0.3, -0.001, sin(a) * float(row.length) * 0.3)
		holder.add_child(_gem(str(sole_gems[i]), gem_size * 0.75, at, Vector3.DOWN))


func _gem(kind: String, size: float, at: Vector3, out: Vector3) -> MeshInstance3D:
	var gem := MeshInstance3D.new()
	gem.mesh = MODELS.gem_mesh(size)
	gem.material_override = MODELS.gem_material(kind)
	gem.visibility_range_end = VISIBLE_TO
	# The gem's table (+Z) faces out of the hoof.
	var up := Vector3.UP if absf(out.dot(Vector3.UP)) < 0.9 else Vector3.FORWARD
	gem.transform = Transform3D(Basis.looking_at(-out, up), at)
	return gem


## Her frog on the sole of `leg`, in her own coat colour a shade darker.
func _show_frog(pony: Node3D, skeleton: Skeleton3D, leg: String, on: bool) -> void:
	var node := skeleton.get_node_or_null(FROG_NODE + leg)
	if not on:
		if node != null: node.queue_free()
		return
	if node != null: return
	var soles := HOOVES.soles(pony)
	if not soles.has(leg): return
	var row: Dictionary = soles[leg]
	var attachment := _attachment(skeleton, FROG_NODE + leg, int(row.bone))
	var frog := MeshInstance3D.new()
	frog.name = "Frog"
	frog.mesh = MODELS.frog_mesh(float(row.width), float(row.length))
	frog.material_override = _frog_mat(pony)
	frog.transform = row.local
	attachment.add_child(frog)


## The hoof wall's rim around the sole of a lifted hoof.
func _show_rim(pony: Node3D, skeleton: Skeleton3D, leg: String, on: bool) -> void:
	var node := skeleton.get_node_or_null(RIM_NODE + leg)
	if not on:
		if node != null: node.queue_free()
		return
	if node != null: return
	var soles := HOOVES.soles(pony)
	if not soles.has(leg): return
	var row: Dictionary = soles[leg]
	var attachment := _attachment(skeleton, RIM_NODE + leg, int(row.bone))
	var rim := MeshInstance3D.new()
	rim.name = "Rim"
	rim.mesh = MODELS.rim_mesh(float(row.width) * 1.02, float(row.length) * 1.02, float(row.width) * RIM_DEPTH, float(row.width) * RIM_WALL)
	var m := (_frog_mat(pony) as StandardMaterial3D).duplicate() as StandardMaterial3D
	m.albedo_color = m.albedo_color.darkened(0.12)
	rim.material_override = m
	rim.transform = row.local
	attachment.add_child(rim)


func _frog_mat(pony: Node3D) -> Material:
	var coat := Color(0.8, 0.7, 0.6)
	var feathers: Script = load("res://world/minigames/spa/spa_feathers.gd")
	if feathers != null and feathers.has_method("coat_of"): coat = feathers.call("coat_of", pony)
	var key := coat.to_html()
	if not _frog_material.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = coat.darkened(0.18).lerp(Color(0.85, 0.55, 0.6), 0.12)
		m.roughness = 0.85
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		_frog_material[key] = m
	return _frog_material[key]


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
		var c := CylinderMesh.new()
		c.top_radius = 0.0035; c.bottom_radius = 0.0045; c.height = 0.006; c.radial_segments = 8; c.rings = 1
		_nail_mesh = c
		var m := StandardMaterial3D.new()
		m.albedo_color = Color("5b5f66"); m.metallic = 0.9; m.roughness = 0.35
		_nail_material = m
	return _nail_mesh


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
			for prefix: String in [NODE, "MareCareSole_", JEWEL_NODE, FROG_NODE, RIM_NODE]:
				var node := skeleton.get_node_or_null(prefix + leg)
				if node != null: node.queue_free()
