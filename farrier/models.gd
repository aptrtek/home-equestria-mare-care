extends RefCounted
## The farrier's tools and horseshoes, built from primitives (no imported art), in the same way
## as the brushes (brushing/items/brush_item.gd). tools/make_farrier_models.gd saves each tool as
## farrier/models/<kind>.scn for the game's item visual. Horseshoes are also built at runtime
## by shoe() for the shoes nailed onto her hooves.
##
## Frame: grip at the origin, working end toward -Z. Every mesh sits under a "container_*" node,
## so the game treats it as a container part (never eaten, never hidden).

const KINDS := ["hoof_pick", "nippers", "rasp", "hammer", "hoof_oil", "shoe_steel", "shoe_silver", "shoe_gold", "shoe_rainbow"]
## Where each tool works, in its own frame (before the game centres the model on its bounds).
const TIPS := {
	"hoof_pick": Vector3(0, -0.012, -0.135),
	"nippers": Vector3(0, 0, -0.215),
	"rasp": Vector3(0, -0.006, -0.2),
	"hammer": Vector3(0, -0.03, -0.235),
	"hoof_oil": Vector3(0, -0.02, -0.17),
	"shoe_steel": Vector3.ZERO, "shoe_silver": Vector3.ZERO, "shoe_gold": Vector3.ZERO, "shoe_rainbow": Vector3.ZERO,
}
const STYLES := ["steel", "silver", "gold", "rainbow"]
const STYLE_NAMES := {"steel": "Steel", "silver": "Silver", "gold": "Gold", "rainbow": "Rainbow"}

const WOOD := Color("9a6a3e")
const GRIP := Color("2f4a7a")
const STEEL := Color("8d939b")
const DARK := Color("3a3d42")
const RAINBOW := [Color("e8404a"), Color("f39a2b"), Color("f6d23a"), Color("53c25a"), Color("3d8be0"), Color("8a55d4")]


static func build(kind: String) -> Node3D:
	var root := Node3D.new()
	root.name = kind.to_pascal_case()
	var parts := Node3D.new()
	parts.name = "container_" + kind
	root.add_child(parts)
	match kind:
		"hoof_pick": _pick(parts)
		"nippers": _nippers(parts)
		"rasp": _rasp(parts)
		"hammer": _hammer(parts)
		"hoof_oil": _oil(parts)
		_:
			if kind.begins_with("shoe_"):
				var shoe := MeshInstance3D.new()
				shoe.mesh = shoe_mesh(0.11)
				shoe.material_override = shoe_material(kind.trim_prefix("shoe_"))
				# Held flat in the hand, toe away.
				shoe.transform = Transform3D(Basis.IDENTITY, Vector3(0, 0, -0.06))
				parts.add_child(shoe)
	_own(root, root)
	return root


static func _own(node: Node, owner: Node) -> void:
	for child in node.get_children():
		child.owner = owner
		_own(child, owner)


## Hoof pick: a wooden handle, a hooked steel pick, and a stiff little brush on the back.
static func _pick(parts: Node3D) -> void:
	_part(parts, _cylinder(0.012, 0.014, 0.1), WOOD, Transform3D(Basis(Vector3.RIGHT, PI / 2), Vector3(0, 0, -0.03)))
	_part(parts, _cylinder(0.004, 0.005, 0.05), STEEL, Transform3D(Basis(Vector3.RIGHT, PI / 2), Vector3(0, 0, -0.1)), 0.35, 0.8)
	# The hook: bent down at the end.
	_part(parts, _cylinder(0.002, 0.004, 0.026), STEEL, Transform3D(Basis(Vector3.RIGHT, PI / 2 + 0.9), Vector3(0, -0.008, -0.128)), 0.35, 0.8)
	_part(parts, _box(Vector3(0.02, 0.012, 0.05)), Color("c9a46a"), Transform3D(Basis.IDENTITY, Vector3(0, 0.014, -0.045)))
	_part(parts, _box(Vector3(0.018, 0.012, 0.046)), Color("4a3a2a"), Transform3D(Basis.IDENTITY, Vector3(0, 0.026, -0.045)))


## Hoof nippers: two long handles and a pair of rounded jaws.
static func _nippers(parts: Node3D) -> void:
	for side in [-1.0, 1.0]:
		_part(parts, _cylinder(0.007, 0.008, 0.16), GRIP, Transform3D(Basis(Vector3.RIGHT, PI / 2).rotated(Vector3.UP, side * 0.06), Vector3(side * 0.012, 0, -0.03)))
		_part(parts, _cylinder(0.005, 0.006, 0.07), STEEL, Transform3D(Basis(Vector3.RIGHT, PI / 2).rotated(Vector3.UP, -side * 0.12), Vector3(side * 0.007, 0, -0.14)), 0.3, 0.85)
		_part(parts, _box(Vector3(0.012, 0.03, 0.03)), STEEL, Transform3D(Basis.IDENTITY, Vector3(side * 0.008, 0, -0.195)), 0.3, 0.85)
	_part(parts, _cylinder(0.008, 0.008, 0.026), DARK, Transform3D(Basis(Vector3.FORWARD, PI / 2), Vector3(0, 0, -0.115)), 0.4, 0.7)


## Rasp: a long flat file with a coarse side, on a wooden handle.
static func _rasp(parts: Node3D) -> void:
	_part(parts, _cylinder(0.013, 0.015, 0.1), WOOD, Transform3D(Basis(Vector3.RIGHT, PI / 2), Vector3(0, 0, -0.02)))
	_part(parts, _box(Vector3(0.036, 0.007, 0.2)), STEEL, Transform3D(Basis.IDENTITY, Vector3(0, 0, -0.17)), 0.55, 0.75)
	# Teeth: rows of little ridges on the underside.
	var tooth := _box(Vector3(0.032, 0.002, 0.003))
	for i in 24:
		_part(parts, tooth, DARK, Transform3D(Basis.IDENTITY, Vector3(0, -0.004, -0.08 - i * 0.0075)), 0.6, 0.6)


## Farrier's hammer: a handle and a short head with a round face.
static func _hammer(parts: Node3D) -> void:
	_part(parts, _cylinder(0.011, 0.013, 0.22), WOOD, Transform3D(Basis(Vector3.RIGHT, PI / 2), Vector3(0, 0, -0.1)))
	_part(parts, _box(Vector3(0.022, 0.07, 0.03)), STEEL, Transform3D(Basis.IDENTITY, Vector3(0, -0.005, -0.225)), 0.35, 0.85)
	_part(parts, _cylinder(0.015, 0.015, 0.012), STEEL.lightened(0.15), Transform3D(Basis.IDENTITY, Vector3(0, -0.044, -0.225)), 0.3, 0.9)


## Hoof oil: a small amber bottle with a dabbing brush in its cap.
static func _oil(parts: Node3D) -> void:
	_part(parts, _cylinder(0.024, 0.026, 0.08), Color("b5651d"), Transform3D(Basis(Vector3.RIGHT, PI / 2), Vector3(0, 0, -0.02)), 0.2)
	_part(parts, _cylinder(0.012, 0.014, 0.024), Color("222222"), Transform3D(Basis(Vector3.RIGHT, PI / 2), Vector3(0, 0, -0.072)))
	_part(parts, _cylinder(0.003, 0.003, 0.07), Color("d8c9a8"), Transform3D(Basis(Vector3.RIGHT, PI / 2), Vector3(0, 0, -0.115)))
	_part(parts, _cylinder(0.008, 0.004, 0.026), Color("e9d27a"), Transform3D(Basis(Vector3.RIGHT, PI / 2), Vector3(0, 0, -0.16)), 0.6)


## A horseshoe, flat on the XZ plane: toe toward -Z, the open heels toward +Z, `width` across,
## its ground face at y = 0 and its top face at y = thickness. Nail holes are little dents.
static func shoe_mesh(width: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rx := width * 0.5
	var rz := width * 0.55
	var web := width * 0.2
	var thick := width * 0.07
	var steps := 36
	var from := deg_to_rad(-200.0)
	var to := deg_to_rad(20.0)
	var outer: Array[Vector3] = []
	var inner: Array[Vector3] = []
	for i in steps + 1:
		var a := lerpf(from, to, float(i) / steps)
		var d := Vector3(cos(a), 0, sin(a))
		outer.append(Vector3(d.x * rx, 0, d.z * rz))
		inner.append(Vector3(d.x * (rx - web), 0, d.z * (rz - web)))
	var up := Vector3.UP * thick
	for i in steps:
		var o0 := outer[i]; var o1 := outer[i + 1]; var n0 := inner[i]; var n1 := inner[i + 1]
		_quad(st, o0 + up, o1 + up, n1 + up, n0 + up)   # top
		_quad(st, n0, n1, o1, o0)                       # ground face
		_quad(st, o0, o1, o1 + up, o0 + up)             # outer rim
		_quad(st, n1, n0, n0 + up, n1 + up)             # inner rim
	# Heel ends.
	_quad(st, inner[0], outer[0], outer[0] + up, inner[0] + up)
	_quad(st, outer[steps], inner[steps], inner[steps] + up, outer[steps] + up)
	st.generate_normals()
	return st.commit()


## How many nails hold a shoe: two down each branch.
const NAIL_COUNT := 4


## Where the nails go on shoe_mesh(width): two down each branch, in the middle of the web.
static func nail_points(width: float) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var rx := width * 0.5 - width * 0.1
	var rz := width * 0.55 - width * 0.1
	for deg: float in [-150.0, -115.0, -65.0, -30.0]:
		var a := deg_to_rad(deg)
		out.append(Vector3(cos(a) * rx, 0, sin(a) * rz))
	return out


static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	for p in [a, b, c, a, c, d]:
		st.set_uv(Vector2(p.x, p.z) * 8.0)
		st.add_vertex(p)


static func shoe_material(style: String) -> Material:
	var m := StandardMaterial3D.new()
	match style:
		"silver":
			m.albedo_color = Color("e4e8ee"); m.metallic = 0.55; m.roughness = 0.3
		"gold":
			m.albedo_color = Color("f2c14e"); m.metallic = 0.55; m.roughness = 0.3
		"rainbow":
			m.albedo_texture = _rainbow_texture(); m.metallic = 0.6; m.roughness = 0.3
			m.uv1_scale = Vector3(0.6, 0.6, 1)
		_:
			m.albedo_color = STEEL; m.metallic = 0.5; m.roughness = 0.4
	# Fully metallic surfaces only show what they reflect, and a lifted hoof is seen from below,
	# where that is dark: keep some body colour, and a little glow, so every shoe reads as itself.
	if style != "rainbow":
		m.emission_enabled = true
		m.emission = m.albedo_color * 0.14
	return m


static func _rainbow_texture() -> Texture2D:
	var image := Image.create(64, 4, false, Image.FORMAT_RGB8)
	for x in 64:
		var c: Color = RAINBOW[int(x / 64.0 * RAINBOW.size()) % RAINBOW.size()]
		for y in 4: image.set_pixel(x, y, c)
	var texture := ImageTexture.create_from_image(image)
	return texture


static func _part(parent: Node3D, mesh: Mesh, color: Color, at: Transform3D, roughness := 0.75, metallic := 0.0) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var m := StandardMaterial3D.new(); m.albedo_color = color; m.roughness = roughness; m.metallic = metallic
	mi.material_override = m
	mi.transform = at
	parent.add_child(mi)


static func _cylinder(top: float, bottom: float, height: float) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = top; c.bottom_radius = bottom; c.height = height; c.radial_segments = 14; c.rings = 1
	return c


static func _box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new(); b.size = size
	return b
