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

## Brick, and brick that has stood in weather: soot carried down from
## the chimneys, salt bloom, a damp dark course near the ground, and no
## two bricks the same firing.
static func brick_texture(seed_v: int) -> ImageTexture:
	var img := Image.create(96, 96, false, Image.FORMAT_RGB8)
	var mortar := Color(0.44, 0.41, 0.39)
	for y in 96:
		for x in 96:
			var row := y / 8
			var stagger := 7 if row % 2 == 1 else 0
			var in_mortar := (y % 8 == 0) or ((x + stagger) % 14 == 0)
			var c: Color
			if in_mortar:
				# Old lime mortar is uneven and dirtier low down.
				var mj := float(_hash(seed_v + x * 31 + y * 17) % 100) / 100.0
				c = mortar.darkened(mj * 0.22)
			else:
				var j := float(_hash(seed_v + row * 131 + (x + stagger) / 14) % 100) / 100.0
				c = Color(0.34 + j * 0.10, 0.17 + j * 0.06, 0.13 + j * 0.04)
				# Some bricks were burnt darker in the kiln.
				if _hash(seed_v + row * 977 + (x + stagger) / 14 * 13) % 100 < 12:
					c = c.darkened(0.30)
			# Rain-borne soot streaks, strongest under the eaves.
			var streak := _hash(seed_v + (x / 3) * 6151) % 100
			if streak < 26:
				var down := 1.0 - float(y) / 96.0
				c = c.darkened(down * 0.30 * (1.0 - float(streak) / 26.0))
			# The damp course: the bottom of a wall is always darker.
			if y > 78:
				c = c.darkened((float(y) - 78.0) / 18.0 * 0.35)
			img.set_pixel(x, y, c)
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



# --- window joinery ------------------------------------------------------

## One box, flat-shaded, colour baked per vertex (colonial_lib keeps its
## own copy so it does not depend on the figure library).
static func _wbox(st: SurfaceTool, color: Color, center: Vector3, size: Vector3) -> void:
	var a := size / 2.0
	var faces := [
		[Vector3(0, 0, 1), [[-1, 1, 1], [1, 1, 1], [1, -1, 1], [-1, -1, 1]]],
		[Vector3(0, 0, -1), [[1, 1, -1], [-1, 1, -1], [-1, -1, -1], [1, -1, -1]]],
		[Vector3(1, 0, 0), [[1, 1, 1], [1, 1, -1], [1, -1, -1], [1, -1, 1]]],
		[Vector3(-1, 0, 0), [[-1, 1, -1], [-1, 1, 1], [-1, -1, 1], [-1, -1, -1]]],
		[Vector3(0, 1, 0), [[-1, 1, -1], [1, 1, -1], [1, 1, 1], [-1, 1, 1]]],
		[Vector3(0, -1, 0), [[-1, -1, 1], [1, -1, 1], [1, -1, -1], [-1, -1, -1]]],
	]
	for face in faces:
		var n: Vector3 = face[0]
		var quad: Array = face[1]
		var pts: Array[Vector3] = []
		for sgn in quad:
			pts.append(center + Vector3(a.x * sgn[0], a.y * sgn[1], a.z * sgn[2]))
		for tri in [[0, 1, 2], [0, 2, 3]]:
			for idx in tri:
				st.set_color(color)
				st.set_normal(n)
				st.add_vertex(pts[idx])


## A twelve-light sash window: painted frame, projecting sill, a lintel
## over it, glass set BACK in the reveal, and the muntins that divide the
## lights. The playtest note was exact — flat coloured boxes on a wall
## are the single clearest tell that nobody built this house.
##   kind: "lit" | "dark" | "shuttered"
static func window_mesh(kind := "dark") -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var w := 0.62
	var hgt := 0.95
	var frame := Color(0.74, 0.71, 0.63)          # lead-white paint, dirtied
	var frame_dark := Color(0.52, 0.49, 0.43)
	var glass := Color(0.07, 0.09, 0.13)
	if kind == "lit":
		glass = Color(1.0, 0.80, 0.42)
	# The reveal: glass sits 8cm back from the wall face.
	_wbox(st, glass, Vector3(0, 0, -0.06), Vector3(w - 0.10, hgt - 0.10, 0.02))
	# Muntins — two vertical, three horizontal: twelve lights.
	var bar := Color(0.68, 0.65, 0.58) if kind != "lit" else Color(0.80, 0.70, 0.50)
	for k in 2:
		var mx := -w / 6.0 + float(k) * (w / 3.0)
		_wbox(st, bar, Vector3(mx, 0, -0.05), Vector3(0.022, hgt - 0.10, 0.02))
	for k in 3:
		var my := -hgt / 4.0 + float(k) * (hgt / 4.0)
		_wbox(st, bar, Vector3(0, my, -0.05), Vector3(w - 0.10, 0.022, 0.02))
	# The frame proper.
	_wbox(st, frame, Vector3(0, hgt / 2.0, 0), Vector3(w, 0.075, 0.10))       # head
	_wbox(st, frame, Vector3(0, -hgt / 2.0, 0.01), Vector3(w, 0.075, 0.13))   # sill body
	_wbox(st, frame_dark, Vector3(0, -hgt / 2.0 - 0.045, 0.05),
		Vector3(w + 0.14, 0.05, 0.20))                                        # projecting sill
	_wbox(st, frame, Vector3(-w / 2.0, 0, 0), Vector3(0.075, hgt, 0.10))      # jambs
	_wbox(st, frame, Vector3(w / 2.0, 0, 0), Vector3(0.075, hgt, 0.10))
	if kind == "shuttered":
		# Board shutters, one closed across the light.
		var shut := Color(0.24, 0.30, 0.26)
		for k in 4:
			_wbox(st, shut.darkened(0.04 * float(k % 2)),
				Vector3(-w / 2.0 + 0.09 + float(k) * (w - 0.18) / 3.0, 0, 0.055),
				Vector3((w - 0.18) / 3.2, hgt - 0.06, 0.035))
	return st.commit()


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
	# Honour the caller's y: on graded ground the foundation follows the
	# slope. (This used to be hard-zeroed, which floats a house on a hill.)
	root.position = pos
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
	# Three classes of window, each its own little building: the glass
	# glows only in the lit one, and the material carries vertex colour
	# so frame, muntin and pane all come from one mesh.
	var win_mat := StandardMaterial3D.new()
	win_mat.vertex_color_use_as_albedo = true
	win_mat.albedo_color = Color.WHITE
	win_mat.roughness = 0.6
	var lit := StandardMaterial3D.new()
	lit.vertex_color_use_as_albedo = true
	lit.albedo_color = Color.WHITE
	lit.emission_enabled = true
	lit.emission = Color(1.0, 0.72, 0.34)
	lit.emission_energy_multiplier = 0.55
	var lit_windows: Array[Transform3D] = []
	var dark_windows: Array[Transform3D] = []
	var shut_windows: Array[Transform3D] = []
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
				var at := Vector3(along, y, face_sign * (size.z / 2.0 + 0.035)) \
					if along_x else Vector3(face_sign * (size.x / 2.0 + 0.035), y, along)
				var xf := Transform3D(Basis.IDENTITY if along_x
					else Basis(Vector3.UP, PI / 2.0), at)
				var roll := _hash(h + face * 31 + r * 13 + cidx * 7) % 100
				if roll < 24:
					lit_windows.append(xf)
				elif roll < 38:
					shut_windows.append(xf)     # shut against the cold
				else:
					dark_windows.append(xf)
	# Windows as two MultiMeshes, not forty nodes: a town of fifteen
	# houses was ~900 draw calls, which software GL felt keenly — the
	# Boston capture ran 2.5x slower per frame than the battlefield.
	for pair in [[lit_windows, lit, "lit"], [dark_windows, win_mat, "dark"],
			[shut_windows, win_mat, "shuttered"]]:
		var xforms: Array = pair[0]
		if xforms.is_empty():
			continue
		var wmm := MultiMesh.new()
		wmm.transform_format = MultiMesh.TRANSFORM_3D
		wmm.mesh = window_mesh(String(pair[2]))
		wmm.instance_count = xforms.size()
		for i in xforms.size():
			wmm.set_instance_transform(i, xforms[i])
		var wmmi := MultiMeshInstance3D.new()
		wmmi.multimesh = wmm
		wmmi.material_override = pair[1]
		root.add_child(wmmi)
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
	# Pitch is a builder's choice, not a constant: steep for a garret,
	# shallow on a shed. A street of identical roofs is the giveaway.
	var pitch := 0.26 + float(_hash(h + 71) % 100) / 100.0 * 0.26
	var roof_h := clampf(minf(size.x, size.z) * pitch, 1.0, 3.6)
	var overhang := 0.6
	if size.x >= size.z:
		prism.size = Vector3(size.z + overhang, roof_h, size.x + overhang)
		roof.rotation.y = PI / 2.0
	else:
		prism.size = Vector3(size.x + overhang, roof_h, size.z + overhang)
	var rmat := StandardMaterial3D.new()
	var age := float(_hash(h + 211) % 100) / 100.0
	rmat.albedo_color = SNOW_ROOF.lerp(Color(0.34, 0.33, 0.32), age * 0.55)
	rmat.roughness = 0.9
	prism.material = rmat
	roof.mesh = prism
	roof.position = Vector3(0.0, size.y + roof_h / 2.0, 0.0)
	root.add_child(roof)
	# Dormers: a garret window pushed through the pitch. Only some
	# houses have them, and never the sheds.
	if size.y > 5.5 and _hash(h + 91) % 100 < 45:
		var dormers := 1 + _hash(h + 97) % 2
		var long_x := size.x >= size.z
		for k in dormers:
			var frac := (float(k) + 1.0) / (float(dormers) + 1.0) - 0.5
			var along := (size.x if long_x else size.z) * frac
			var d_root := Node3D.new()
			d_root.position = Vector3(along, size.y + roof_h * 0.30, 0.0) if long_x \
				else Vector3(0.0, size.y + roof_h * 0.30, along)
			root.add_child(d_root)
			var cheek := MeshInstance3D.new()
			var cbox2 := BoxMesh.new()
			cbox2.size = Vector3(1.5, 1.5, 1.4)
			var dmat2 := StandardMaterial3D.new()
			dmat2.albedo_color = Color(0.42, 0.40, 0.36)
			dmat2.roughness = 0.95
			cbox2.material = dmat2
			cheek.mesh = cbox2
			var off := (size.z if long_x else size.x) / 2.0 - 0.8
			cheek.position = Vector3(0.0, 0.0, off) if long_x else Vector3(off, 0.0, 0.0)
			if not long_x:
				cheek.rotation.y = PI / 2.0
			d_root.add_child(cheek)
			var dwin := MeshInstance3D.new()
			dwin.mesh = window_mesh("lit" if _hash(h + k * 13) % 100 < 35 else "dark")
			var wm := StandardMaterial3D.new()
			wm.vertex_color_use_as_albedo = true
			wm.albedo_color = Color.WHITE
			dwin.material_override = wm
			dwin.position = Vector3(0.0, 0.0, off + 0.72) if long_x \
				else Vector3(off + 0.72, 0.0, 0.0)
			if not long_x:
				dwin.rotation.y = PI / 2.0
			d_root.add_child(dwin)

	# A lean-to against the gable end — the commonest addition in New
	# England, and it breaks the box outline that says "generated".
	if _hash(h + 137) % 100 < 40:
		var lean := MeshInstance3D.new()
		var lbox := BoxMesh.new()
		var lw := minf(size.x, size.z) * 0.55
		lbox.size = Vector3(lw, size.y * 0.5, size.z * 0.7)
		lbox.material = wall
		lean.mesh = lbox
		var side := 1.0 if _hash(h + 139) % 2 == 0 else -1.0
		lean.position = Vector3(side * (size.x / 2.0 + lw / 2.0 - 0.1),
			size.y * 0.25, 0.0)
		root.add_child(lean)
		var lroof := MeshInstance3D.new()
		var lprism := PrismMesh.new()
		lprism.size = Vector3(lw + 0.3, 0.9, size.z * 0.7 + 0.3)
		lprism.left_to_right = 0.0 if side > 0.0 else 1.0     # a true shed slope
		var lrmat := StandardMaterial3D.new()
		lrmat.albedo_color = SNOW_ROOF.darkened(0.10)
		lrmat.roughness = 0.92
		lprism.material = lrmat
		lroof.mesh = lprism
		lroof.position = Vector3(side * (size.x / 2.0 + lw / 2.0 - 0.1),
			size.y * 0.5 + 0.45, 0.0)
		root.add_child(lroof)

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
	node.position = pos
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
	root.position = pos            # trees stand on the grade, like everything else
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


## A New England fieldstone wall: irregular stacked stones, chest high,
## running across the field at a given z. The thing the militia fought
## from all the way to Charlestown (docs/03 1.5).
static func make_stone_wall(parent: Node3D, z: float, x0: float, x1: float,
		seed_v: int) -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = _mottle_texture(Color(0.44, 0.44, 0.42),
		[Color(0.38, 0.38, 0.37), Color(0.50, 0.49, 0.46), Color(0.34, 0.35, 0.34)], seed_v)
	mat.uv1_triplanar = true
	mat.uv1_scale = Vector3(0.35, 0.35, 0.35)
	mat.roughness = 1.0
	var stone := BoxMesh.new()
	stone.size = Vector3(1.0, 0.42, 0.85)
	stone.material = mat
	var span := absf(x1 - x0)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = stone
	var per_course := maxi(int(span / 0.95), 2)
	mm.instance_count = per_course * 3
	var i := 0
	for course in 3:
		for k in per_course:
			var h := _hash(seed_v + course * 613 + k)
			var x := minf(x0, x1) + span * (float(k) + 0.5) / float(per_course)
			x += (float(h % 100) / 100.0 - 0.5) * 0.35
			var y := 0.21 + float(course) * 0.36
			var zz := z + (float((h / 100) % 100) / 100.0 - 0.5) * 0.22
			var scale := 0.85 + float((h / 7) % 100) / 100.0 * 0.35
			mm.set_instance_transform(i, Transform3D(
				Basis.IDENTITY.rotated(Vector3.UP, float(h % 62) / 62.0 * 0.5 - 0.25)
					.scaled(Vector3(scale, 1.0, scale)),
				Vector3(x, y, zz)))
			i += 1
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
