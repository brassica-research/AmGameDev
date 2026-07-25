extends RefCounted
## Procedural colonial scenery — the M2 art "form pass" (docs/04, docs/09).
## Turns the stage-JSON prop boxes into buildings that read as 18th-century
## New England: brick or clapboard walls (procedural textures, triplanar so
## any box size works), a window grid with a candlelit fraction, a door, a
## snow-capped pitched roof, chimneys. Everything is deterministic from the
## prop's name — same JSON, same town, every run.
##
## Use via preload:
##   const ColonialLib := preload("res://src/presentation/colonial_lib.gd")

const SNOW_ROOF := Color(0.55, 0.58, 0.66)
const CHIMNEY := Color(0.30, 0.17, 0.13)
const DOOR := Color(0.16, 0.11, 0.07)
const TRUNK := Color(0.22, 0.17, 0.12)
const RAIL := Color(0.33, 0.27, 0.19)


static func _hash(x: int) -> int:
	var h := (x * 2654435761) & 0x7FFFFFFF
	h = (h ^ (h >> 13)) * 1103515245 & 0x7FFFFFFF
	return h ^ (h >> 7)


static func _str_hash(s: String) -> int:
	var h := 5381
	for i in s.length():
		h = ((h << 5) + h + s.unicode_at(i)) & 0x7FFFFFFF
	return h


# --- textures -----------------------------------------------------------

static func brick_texture(seed_v: int) -> ImageTexture:
	var img := Image.create(96, 96, false, Image.FORMAT_RGB8)
	var mortar := Color(0.44, 0.41, 0.39)
	for y in 96:
		for x in 96:
			var row := y / 8
			var stagger := 7 if row % 2 == 1 else 0
			var in_mortar := (y % 8 == 0) or ((x + stagger) % 14 == 0)
			if in_mortar:
				img.set_pixel(x, y, mortar)
			else:
				var j := float(_hash(seed_v + row * 131 + (x + stagger) / 14) % 100) / 100.0
				img.set_pixel(x, y, Color(0.34 + j * 0.10, 0.17 + j * 0.06, 0.13 + j * 0.04))
	return ImageTexture.create_from_image(img)


static func clapboard_texture(tint: Color, seed_v: int) -> ImageTexture:
	var img := Image.create(96, 96, false, Image.FORMAT_RGB8)
	for y in 96:
		var board := y / 8
		var j := float(_hash(seed_v + board * 17) % 100) / 100.0
		var c := Color(
			clampf(tint.r * (1.35 + j * 0.35), 0.0, 1.0),
			clampf(tint.g * (1.35 + j * 0.35), 0.0, 1.0),
			clampf(tint.b * (1.35 + j * 0.35), 0.0, 1.0))
		if y % 8 == 7:
			c = c.darkened(0.45)  # the shadow line under each board
		for x in 96:
			var g := float(_hash(seed_v + y * 977 + x) % 100) / 100.0
			img.set_pixel(x, y, c.darkened(g * 0.08))
	return ImageTexture.create_from_image(img)


static func _mottle_texture(base: Color, others: Array, seed_v: int) -> ImageTexture:
	var img := Image.create(96, 96, false, Image.FORMAT_RGB8)
	for y in 96:
		for x in 96:
			var h := _hash(seed_v + y * 96 + x)
			var c := base
			if h % 100 < 38:
				c = others[(h / 100) % others.size()]
			var j := float((h / 7) % 100) / 100.0
			img.set_pixel(x, y, c.darkened(j * 0.10))
	return ImageTexture.create_from_image(img)


## Ground materials: "snow" (trampled town snow) or "field"/"night_field"
## (New England pasture). Triplanar, so one material fits any plane.
static func ground_material(kind: String) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	match kind:
		"snow":
			mat.albedo_texture = _mottle_texture(Color(0.52, 0.54, 0.62),
				[Color(0.46, 0.48, 0.57), Color(0.58, 0.60, 0.67), Color(0.42, 0.43, 0.50)], 11)
		"field":
			mat.albedo_texture = _mottle_texture(Color(0.25, 0.29, 0.16),
				[Color(0.30, 0.27, 0.15), Color(0.21, 0.25, 0.13), Color(0.33, 0.31, 0.18)], 23)
		_:
			mat.albedo_texture = _mottle_texture(Color(0.13, 0.15, 0.11),
				[Color(0.11, 0.13, 0.10), Color(0.16, 0.17, 0.12)], 31)
	mat.uv1_triplanar = true
	mat.uv1_scale = Vector3(0.22, 0.22, 0.22)
	mat.roughness = 1.0
	return mat


# --- buildings ----------------------------------------------------------

## Build a colonial building where the grey prop box stood. `size` is the
## full wall box (w, h, d); the roof and chimneys rise above it. `tint`
## is the old prop color — it steers the clapboard paint so the JSON's
## palette still means something.
static func make_building(parent: Node3D, prop_name: String, pos: Vector3,
		size: Vector3, tint: Color) -> Node3D:
	var h := _str_hash(prop_name)
	var root := Node3D.new()
	root.name = prop_name
	root.position = Vector3(pos.x, 0.0, pos.z)
	parent.add_child(root)
	# Walls.
	var body := MeshInstance3D.new()
	var body_mesh := BoxMesh.new()
	body_mesh.size = size
	var wall := StandardMaterial3D.new()
	if h % 2 == 0:
		wall.albedo_texture = brick_texture(h)
	else:
		wall.albedo_texture = clapboard_texture(tint, h)
	wall.uv1_triplanar = true
	wall.uv1_scale = Vector3(0.5, 0.5, 0.5)
	wall.roughness = 0.95
	body_mesh.material = wall
	body.mesh = body_mesh
	body.position = Vector3(0.0, size.y / 2.0, 0.0)
	root.add_child(body)
	# Windows: a lit fraction — Boston is home tonight, candles up.
	var lit := StandardMaterial3D.new()
	lit.albedo_color = Color(0.55, 0.38, 0.16)
	lit.emission_enabled = true
	lit.emission = Color(1.0, 0.70, 0.32)
	lit.emission_energy_multiplier = 1.6
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.05, 0.06, 0.09)
	dark.roughness = 0.25
	var mesh_z := BoxMesh.new()
	mesh_z.size = Vector3(0.55, 0.85, 0.06)
	var mesh_x := BoxMesh.new()
	mesh_x.size = Vector3(0.06, 0.85, 0.55)
	var rows := clampi(int((size.y - 1.0) / 1.7), 1, 3)
	for face in 4:
		var along_x := face < 2                 # faces 0,1 = ±z walls
		var span := (size.x if along_x else size.z) - 1.2
		if span < 1.0:
			continue
		var cols := clampi(int(span / 1.9), 1, 6)
		var face_sign := 1.0 if face % 2 == 0 else -1.0
		for r in rows:
			for cidx in cols:
				var along := -span / 2.0 + span * (float(cidx) + 0.5) / float(cols)
				var y := 1.15 + float(r) * 1.7 + 0.42
				if y + 0.55 > size.y:
					continue
				var w := MeshInstance3D.new()
				w.mesh = mesh_z if along_x else mesh_x
				w.material_override = lit \
					if _hash(h + face * 31 + r * 13 + cidx * 7) % 100 < 28 else dark
				if along_x:
					w.position = Vector3(along, y, face_sign * (size.z / 2.0 + 0.035))
				else:
					w.position = Vector3(face_sign * (size.x / 2.0 + 0.035), y, along)
				root.add_child(w)
	# Door on the -z face, off-center by taste of the hash.
	var door := MeshInstance3D.new()
	var door_mesh := BoxMesh.new()
	door_mesh.size = Vector3(0.95, 2.0, 0.10)
	var dmat := StandardMaterial3D.new()
	dmat.albedo_color = DOOR
	door_mesh.material = dmat
	door.mesh = door_mesh
	var dx := (float(_hash(h + 5) % 100) / 100.0 - 0.5) * maxf(size.x - 2.0, 0.0) * 0.5
	door.position = Vector3(dx, 1.0, -(size.z / 2.0 + 0.05))
	root.add_child(door)
	# Snow-capped pitched roof, ridge along the long axis.
	var roof := MeshInstance3D.new()
	var prism := PrismMesh.new()
	var roof_h := clampf(minf(size.x, size.z) * 0.35, 1.0, 3.2)
	var overhang := 0.6
	if size.x >= size.z:
		prism.size = Vector3(size.z + overhang, roof_h, size.x + overhang)
		roof.rotation.y = PI / 2.0
	else:
		prism.size = Vector3(size.x + overhang, roof_h, size.z + overhang)
	var rmat := StandardMaterial3D.new()
	rmat.albedo_color = SNOW_ROOF
	rmat.roughness = 0.9
	prism.material = rmat
	roof.mesh = prism
	roof.position = Vector3(0.0, size.y + roof_h / 2.0, 0.0)
	root.add_child(roof)
	# Chimneys along the ridge — smoke means winter and someone home.
	var cmat := StandardMaterial3D.new()
	cmat.albedo_color = CHIMNEY
	for k in 1 + (h % 2):
		var chim := MeshInstance3D.new()
		var cbox := BoxMesh.new()
		cbox.size = Vector3(0.55, 1.7, 0.55)
		cbox.material = cmat
		chim.mesh = cbox
		var frac := -0.28 if k == 0 else 0.28
		var along_ridge := (size.x if size.x >= size.z else size.z) * frac
		if size.x >= size.z:
			chim.position = Vector3(along_ridge, size.y + roof_h * 0.55 + 0.5, 0.0)
		else:
			chim.position = Vector3(0.0, size.y + roof_h * 0.55 + 0.5, along_ridge)
		root.add_child(chim)
	return root


# --- field dressing -----------------------------------------------------

const THIRDPARTY_NATURE := "res://assets/thirdparty/nature-kit"


## List GLBs in a third-party pack dir whose filename contains `needle`.
## Returns [] when the pack isn't fetched — callers MUST keep their
## procedural fallback (assets are dressing, never a dependency).
static func thirdparty_glbs(dir_path: String, needle: String) -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	for f in dir.get_files():
		if f.get_extension() == "glb" and f.to_lower().contains(needle):
			out.append(dir_path + "/" + f)
	out.sort()  # deterministic pick order across platforms
	return out


## Instance a GLB prop scaled so its tallest mesh is `target_h` units.
static func _instance_glb(parent: Node3D, path: String, pos: Vector3,
		target_h: float, seed_v: int) -> bool:
	var packed := load(path) as PackedScene
	if packed == null:
		return false
	var node := packed.instantiate() as Node3D
	if node == null:
		return false
	var mesh_node := node.find_children("*", "MeshInstance3D", true, false)
	var h := 0.0
	for m in mesh_node:
		h = maxf(h, (m as MeshInstance3D).get_aabb().size.y * (m as MeshInstance3D).scale.y)
	if h > 0.001:
		node.scale = Vector3.ONE * (target_h / h)
	node.position = Vector3(pos.x, 0.0, pos.z)
	node.rotation.y = float(_hash(seed_v) % 628) / 100.0
	parent.add_child(node)
	return true


## Kenney's nature kit is every biome at once — keep only what grows in
## Massachusetts (oaks, pines, plain broadleafs), in spring colors.
const TREE_REJECT := ["palm", "cactus", "blocks", "cone", "plateau", "_fall", "snow"]


## A bare winter/early-spring tree: a CC0 model when the nature pack is
## fetched, else trunk and a few reaching branch boxes.
static func make_bare_tree(parent: Node3D, pos: Vector3, seed_v: int) -> void:
	var picks: Array[String] = []
	for p in thirdparty_glbs(THIRDPARTY_NATURE, "tree"):
		var ok := true
		for bad in TREE_REJECT:
			if p.to_lower().contains(bad):
				ok = false
				break
		if ok:
			picks.append(p)
	if not picks.is_empty():
		var choice := picks[absi(_hash(seed_v)) % picks.size()]
		if _instance_glb(parent, choice, pos, 3.6 + float(_hash(seed_v + 3) % 100) / 100.0 * 1.4, seed_v):
			return
	_make_procedural_tree(parent, pos, seed_v)


static func _make_procedural_tree(parent: Node3D, pos: Vector3, seed_v: int) -> void:
	var root := Node3D.new()
	root.position = Vector3(pos.x, 0.0, pos.z)
	root.rotation.y = float(_hash(seed_v) % 628) / 100.0
	parent.add_child(root)
	var tmat := StandardMaterial3D.new()
	tmat.albedo_color = TRUNK
	var trunk := MeshInstance3D.new()
	var tbox := BoxMesh.new()
	var height := 3.0 + float(_hash(seed_v + 1) % 100) / 100.0 * 1.6
	tbox.size = Vector3(0.28, height, 0.28)
	tbox.material = tmat
	trunk.mesh = tbox
	trunk.position = Vector3(0.0, height / 2.0, 0.0)
	root.add_child(trunk)
	for b in 4 + _hash(seed_v + 2) % 3:
		var branch := MeshInstance3D.new()
		var bbox := BoxMesh.new()
		var blen := 1.0 + float(_hash(seed_v + 10 + b) % 100) / 100.0 * 0.9
		bbox.size = Vector3(0.09, blen, 0.09)
		bbox.material = tmat
		branch.mesh = bbox
		var ang := float(b) * TAU / 5.0 + float(_hash(seed_v + 20 + b) % 100) / 100.0
		var lean := 0.6 + float(_hash(seed_v + 30 + b) % 100) / 100.0 * 0.5
		branch.position = Vector3(cos(ang) * 0.35, height - 1.1 + float(b % 3) * 0.35,
			sin(ang) * 0.35)
		branch.rotation = Vector3(cos(ang) * lean, ang, sin(ang) * lean)
		root.add_child(branch)


## A split-rail fence run along z at a fixed x: two long rails plus a
## MultiMesh of posts — three draw calls for the whole run.
static func make_rail_fence(parent: Node3D, x: float, z0: float, z1: float) -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = RAIL
	var length := absf(z1 - z0)
	var mid_z := (z0 + z1) / 2.0
	for rail_y in [0.55, 0.95]:
		var rail := MeshInstance3D.new()
		var rbox := BoxMesh.new()
		rbox.size = Vector3(0.07, 0.09, length)
		rbox.material = mat
		rail.mesh = rbox
		rail.position = Vector3(x, rail_y, mid_z)
		parent.add_child(rail)
	var post_box := BoxMesh.new()
	post_box.size = Vector3(0.12, 1.1, 0.12)
	post_box.material = mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = post_box
	mm.instance_count = maxi(int(length / 3.0), 2)
	for i in mm.instance_count:
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY,
			Vector3(x, 0.55, z0 + (length / float(mm.instance_count - 1)) * float(i) * signf(z1 - z0))))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	parent.add_child(mmi)


## The quarter moon, hung opposite the moonlight's travel so the light
## direction and the disc agree. Only wide shots will catch it.
static func make_moon(parent: Node3D, light: DirectionalLight3D) -> void:
	var moon := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 2.4
	sphere.height = 4.8
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.93, 0.94, 0.90)
	sphere.material = mat
	moon.mesh = sphere
	moon.position = light.transform.basis.z * 170.0
	parent.add_child(moon)
