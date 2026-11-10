extends RefCounted
## The farrier's tools and horseshoes, built from primitives (no imported art), in the same way
## as the brushes (brushing/items/brush_item.gd). tools/make_farrier_models.gd saves each tool as
## farrier/models/<kind>.scn for the game's item visual. Horseshoes are also built at runtime
## by shoe() for the shoes nailed onto her hooves.
##
## Frame: grip at the origin, working end toward -Z. Every mesh sits under a "container_*" node,
## so the game treats it as a container part (never eaten, never hidden).

const KINDS := ["hoof_pick", "nippers", "rasp", "hammer", "hoof_oil", "shoe_steel", "shoe_silver", "shoe_gold", "shoe_rainbow",
	"jewels_crystal", "jewels_ruby", "jewels_sapphire", "jewels_rainbow", "jewels_starry", "jewels_royal"]
## Where each tool works, in its own frame (before the game centres the model on its bounds).
const TIPS := {
	"hoof_pick": Vector3(0, -0.012, -0.135),
	"nippers": Vector3(0, 0, -0.215),
	"rasp": Vector3(0, -0.006, -0.2),
	"hammer": Vector3(0, -0.03, -0.235),
	"hoof_oil": Vector3(0, -0.02, -0.17),
	"shoe_steel": Vector3.ZERO, "shoe_silver": Vector3.ZERO, "shoe_gold": Vector3.ZERO, "shoe_rainbow": Vector3.ZERO,
	"jewels_crystal": Vector3.ZERO, "jewels_ruby": Vector3.ZERO, "jewels_sapphire": Vector3.ZERO,
	"jewels_rainbow": Vector3.ZERO, "jewels_starry": Vector3.ZERO, "jewels_royal": Vector3.ZERO,
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
			if kind.begins_with("jewels_"): _jewel_case(parts, kind.trim_prefix("jewels_"))
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


## Where the nails go on shoe_mesh(width): three down each branch, in the middle of the web.
static func nail_points(width: float) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var rx := width * 0.5 - width * 0.1
	var rz := width * 0.55 - width * 0.1
	for deg: float in [-160.0, -130.0, -105.0, -75.0, -50.0, -20.0]:
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
			m.albedo_color = Color("e4e8ee"); m.metallic = 1.0; m.roughness = 0.18
		"gold":
			m.albedo_color = Color("f2c14e"); m.metallic = 1.0; m.roughness = 0.22
		"rainbow":
			m.albedo_texture = _rainbow_texture(); m.metallic = 0.6; m.roughness = 0.3
			m.uv1_scale = Vector3(0.6, 0.6, 1)
		_:
			m.albedo_color = STEEL; m.metallic = 0.85; m.roughness = 0.45
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


# ---------------------------------------------------------------- the frog

## The frog: the V-shaped pad on the underside of a hoof, in the sole frame (+Y into the hoof,
## -Z toward the toe), standing out below the sole. Two rounded lobes side by side with a deep
## cleft between them (the central sulcus), joined into one point toward the toe and ending at the
## heels in two round bulbs. Vertex colours darken its edges and the cleft, the grooves that make a
## frog read as a frog under cel shading (material: vertex colour times the frog colour).
static func frog_mesh(width: float, length: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var nu := 30
	var nv := 24
	var apex_z := -0.26 * length
	# The heels end just inside the hoof wall's rim (shoes.gd RIM_WALL).
	var heel_z := 0.5 * length - 0.07 * width
	var thick := 0.075 * width
	var rows := []
	for iu in nu + 1:
		var u := float(iu) / nu
		var row := []
		for iv in nv + 1:
			var v := lerpf(-1.0, 1.0, float(iv) / nv)
			row.append(_frog_point(u, v, apex_z, heel_z, width, thick))
		rows.append(row)
	for iu in nu:
		for iv in nv:
			var quad := [rows[iu][iv], rows[iu][iv + 1], rows[iu + 1][iv + 1], rows[iu + 1][iv]]
			for k: int in [0, 1, 2, 0, 2, 3]:
				st.set_color(quad[k][1])
				st.add_vertex(quad[k][0])
	st.index()
	st.generate_normals()
	return st.commit()


## [point, shade] on the frog: u 0 at its point, 1 at the heels; v -1..1 across.
static func _frog_point(u: float, v: float, apex_z: float, heel_z: float, width: float, thick: float) -> Array:
	var side := absf(v)
	# Half-width: a narrow point widening steadily to broad heels.
	var half := width * (0.035 + 0.27 * pow(u, 0.75))
	# Each lobe ends in a round bulb: the back edge is shortest at the cleft and the outside.
	var bulb := width * 0.09
	var lobe := clampf((side - 0.5) / 0.5, -1.0, 1.0)
	var end_z := heel_z - bulb * (1.0 - sqrt(maxf(0.0, 1.0 - lobe * lobe)))
	var z := lerpf(apex_z, end_z, u)
	var x := v * half
	# Across: one rounded ridge at the point, splitting into two lobes with a cleft between them.
	var split := smoothstep(0.15, 0.5, u)
	var one := sqrt(maxf(0.0, 1.0 - v * v))
	var two := sqrt(maxf(0.0, sin(PI * side)))
	var across := lerpf(one, two, split)
	var along := smoothstep(0.0, 0.18, u) * sqrt(maxf(0.0, 1.0 - pow(u, 8.0)))
	var h := thick * across * along * lerpf(0.55, 1.0, u)
	# The grooves: dark along the frog's edges (where the collateral grooves run) and down the cleft.
	var shade := 1.0
	shade -= 0.45 * smoothstep(0.72, 1.0, side)
	shade -= 0.5 * (1.0 - smoothstep(0.0, 0.16, side)) * split
	shade -= 0.3 * (1.0 - smoothstep(0.0, 0.12, u))
	var c := clampf(shade, 0.35, 1.0)
	return [Vector3(x, -h - 0.0015, z), Color(c, c, c)]


## The sole inside the hoof wall: a slightly domed oval just below the body's own sole, a shade
## darker than the frog so the frog stands out on it.
static func sole_mesh(width: float, length: float, wall: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 48
	var rx := width * 0.5 - wall * 0.8
	var rz := length * 0.5 - wall * 0.8
	var centre := Vector3(0, -0.0008, 0)
	for i in n:
		var a0 := float(i) / n * TAU
		var a1 := float(i + 1) / n * TAU
		var p0 := Vector3(cos(a0) * rx, -0.0008, sin(a0) * rz)
		var p1 := Vector3(cos(a1) * rx, -0.0008, sin(a1) * rz)
		for q: Vector3 in [centre, p1, p0]: st.add_vertex(q)
	st.generate_normals()
	return st.commit()


## The hoof wall's bearing edge around the sole: a rim `depth` deep standing out below the sole (so
## the frog sits recessed inside it), `wall` thick inward from the outside of the hoof. It follows
## the sole's oval (`width` across, `length` toe to heel), smooth all the way round.
static func rim_mesh(width: float, length: float, depth: float, wall: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 48
	var rx := width * 0.5
	var rz := length * 0.5
	var down := Vector3.DOWN * depth
	for i in n:
		var a0 := float(i) / n * TAU
		var a1 := float(i + 1) / n * TAU
		var ao := Vector3(cos(a0) * rx, 0.002, sin(a0) * rz)
		var bo := Vector3(cos(a1) * rx, 0.002, sin(a1) * rz)
		var ai := Vector3(cos(a0) * (rx - wall), 0.002, sin(a0) * (rz - wall))
		var bi := Vector3(cos(a1) * (rx - wall), 0.002, sin(a1) * (rz - wall))
		# Outer face, inner face, the bearing edge underneath.
		for q: Vector3 in [ao, bo, bo + down, ao, bo + down, ao + down]: st.add_vertex(q)
		for q: Vector3 in [ai, ai + down * 0.85, bi + down * 0.85, ai, bi + down * 0.85, bi]: st.add_vertex(q)
		for q: Vector3 in [ao + down, bo + down, bi + down * 0.85, ao + down, bi + down * 0.85, ai + down * 0.85]: st.add_vertex(q)
	st.index()
	st.generate_normals()
	return st.commit()


# ---------------------------------------------------------------- hoof jewellery

## Each design: name, the band around the hoof (metal colour or none), the gems on the front of the
## hoof wall [angle from the toe in degrees, colour], and gems on the sole around the frog.
const JEWELS := {
	"crystal": {"name": "Crystal Hoof Gems", "band": "", "wall": [[-22, "crystal"], [0, "crystal"], [22, "crystal"]], "sole": []},
	"ruby": {"name": "Ruby Hoof Band", "band": "gold", "wall": [[-20, "ruby"], [0, "ruby"], [20, "ruby"]], "sole": []},
	"sapphire": {"name": "Sapphire Hoof Band", "band": "silver", "wall": [[-30, "sapphire"], [-10, "crystal"], [10, "crystal"], [30, "sapphire"]], "sole": []},
	"rainbow": {"name": "Rainbow Hoof Gems", "band": "", "wall": [[-40, "ruby"], [-20, "topaz"], [0, "citrine"], [20, "emerald"], [40, "sapphire"]], "sole": []},
	"starry": {"name": "Starry Hooves", "band": "silver", "wall": [[-30, "crystal"], [0, "amethyst"], [30, "crystal"]], "sole": ["crystal", "amethyst", "crystal", "amethyst", "crystal", "amethyst"]},
	"royal": {"name": "Royal Hoof Jewels", "band": "gold", "wall": [[-35, "emerald"], [-15, "crystal"], [0, "ruby"], [15, "crystal"], [35, "emerald"]], "sole": ["citrine", "ruby", "citrine", "ruby"]},
}
const GEM_COLOURS := {
	"crystal": Color(0.92, 0.97, 1.0), "ruby": Color(0.9, 0.08, 0.2), "sapphire": Color(0.12, 0.3, 0.95),
	"emerald": Color(0.1, 0.8, 0.35), "topaz": Color(1.0, 0.55, 0.1), "citrine": Color(1.0, 0.85, 0.2),
	"amethyst": Color(0.65, 0.3, 0.95),
}


## A cut gem: a flat table on top, a crown and a pointed pavilion, `size` across. Table toward +Z.
static func gem_mesh(size: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sides := 8
	var r := size * 0.5
	var table := r * 0.55
	var crown := size * 0.18
	var pavilion := size * 0.38
	for i in sides:
		var a0 := float(i) / sides * TAU
		var a1 := float(i + 1) / sides * TAU
		var g0 := Vector3(cos(a0) * r, sin(a0) * r, 0)
		var g1 := Vector3(cos(a1) * r, sin(a1) * r, 0)
		var t0 := Vector3(cos(a0) * table, sin(a0) * table, crown)
		var t1 := Vector3(cos(a1) * table, sin(a1) * table, crown)
		var top := Vector3(0, 0, crown)
		var tip := Vector3(0, 0, -pavilion)
		for q: Vector3 in [top, t0, t1, t0, g0, g1, t0, g1, t1, g0, tip, g1]: st.add_vertex(q)
	st.generate_normals()
	return st.commit()


static func gem_material(kind: String) -> Material:
	var m := StandardMaterial3D.new()
	var c: Color = GEM_COLOURS.get(kind, Color.WHITE)
	m.albedo_color = c
	m.metallic = 0.3
	m.roughness = 0.04
	m.metallic_specular = 1.0
	m.emission_enabled = true
	m.emission = c * 0.25
	m.rim_enabled = true
	m.rim = 0.6
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


## A thin band around the hoof through `ring` points ([point, outward] from hooves.ring()), pushed
## out a little so it sits on the wall: a flat strip `height` tall.
static func band_mesh(ring: Array, height: float, out: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := ring.size()
	for i in n:
		var a: Array = ring[i]
		var b: Array = ring[(i + 1) % n]
		var pa: Vector3 = Vector3(a[0]) + Vector3(a[1]) * out
		var pb: Vector3 = Vector3(b[0]) + Vector3(b[1]) * out
		var up := Vector3.UP * height * 0.5
		var lip_a := Vector3(a[1]) * out * 0.6
		var lip_b := Vector3(b[1]) * out * 0.6
		# Outer face, then the top and bottom lips back to the wall.
		for q: Vector3 in [pa - up, pb + up, pb - up, pa - up, pa + up, pb + up]: st.add_vertex(q)
		for q: Vector3 in [pa + up, pb + up - lip_b, pb + up, pa + up, pa + up - lip_a, pb + up - lip_b]: st.add_vertex(q)
		for q: Vector3 in [pa - up, pb - up, pb - up - lip_b, pa - up, pb - up - lip_b, pa - up - lip_a]: st.add_vertex(q)
	st.generate_normals()
	return st.commit()


static func band_material(metal: String) -> Material:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color("f2c14e") if metal == "gold" else Color("e4e8ee")
	m.metallic = 1.0
	m.roughness = 0.2
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


## A little velvet case, its lid open, with the design's gems (and band) set in it.
static func _jewel_case(parts: Node3D, design: String) -> void:
	var row: Dictionary = JEWELS.get(design, {})
	_part(parts, _box(Vector3(0.07, 0.022, 0.06)), Color("5a1f3d"), Transform3D(Basis.IDENTITY, Vector3(0, 0, -0.03)), 0.95)
	_part(parts, _box(Vector3(0.064, 0.004, 0.054)), Color("f3e6ef"), Transform3D(Basis.IDENTITY, Vector3(0, 0.012, -0.03)), 0.9)
	_part(parts, _box(Vector3(0.07, 0.04, 0.006)), Color("5a1f3d"), Transform3D(Basis(Vector3.RIGHT, -0.35), Vector3(0, 0.03, 0.002)), 0.95)
	if str(row.get("band", "")) != "":
		var torus := TorusMesh.new()
		torus.inner_radius = 0.016; torus.outer_radius = 0.019; torus.rings = 24; torus.ring_segments = 6
		var band := MeshInstance3D.new()
		band.mesh = torus
		band.material_override = band_material(str(row.band))
		band.transform = Transform3D(Basis.IDENTITY, Vector3(0, 0.016, -0.03))
		parts.add_child(band)
	var gems: Array = row.get("wall", [])
	for i in gems.size():
		var gem := MeshInstance3D.new()
		gem.mesh = gem_mesh(0.011)
		gem.material_override = gem_material(str(gems[i][1]))
		var x := (float(i) - (gems.size() - 1) * 0.5) * 0.012
		gem.transform = Transform3D(Basis(Vector3.RIGHT, -PI / 2), Vector3(x, 0.017, -0.03))
		parts.add_child(gem)
