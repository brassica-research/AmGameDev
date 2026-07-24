extends RefCounted
## Procedural period figures — the M2 art "form pass" (docs/04, docs/09).
## Every figure is one ArrayMesh of oriented boxes with colors baked as
## vertex colors, so a whole company stays a single MultiMesh draw call.
## Silhouette first: tricorn, coat skirts, shouldered musket over the
## left shoulder — the shapes that read "1770s" at gameplay distance.
## Final art replaces these meshes at look-dev; every call site keeps
## the same contract (a ~1.7-unit figure centered on y = 0, so instances
## are placed at y ≈ 0.85 exactly as the old grey boxes were).
##
## Use via preload (no class_name, so headless test loads never depend
## on the global class cache):
##   const FigureLib := preload("res://src/presentation/figure_lib.gd")

const SKIN := Color(0.70, 0.54, 0.42)
const HAT_BLACK := Color(0.07, 0.07, 0.08)
const BOOT := Color(0.10, 0.08, 0.07)
const BELT_WHITE := Color(0.80, 0.78, 0.70)
const STOCK_WHITE := Color(0.84, 0.83, 0.79)
const BUFF := Color(0.72, 0.66, 0.52)
const WOOD := Color(0.30, 0.19, 0.11)
const STEEL := Color(0.60, 0.64, 0.70)
const DARK_BREECH := Color(0.20, 0.18, 0.15)

# Feet sit at local y = -0.85 so the figure is centered on its origin.
const FEET := -0.85


## A British regular or a uniformed Continental: tricorn, crossbelts,
## regimental coat, shouldered musket with bayonet.
static func build_soldier(coat: Color, breeches: Color = BUFF) -> ArrayMesh:
	return _figure(coat, breeches, "tricorn", true, true)


## A man of the town: round hat, greatcoat down past the knee, empty hands.
static func build_civilian(coat: Color) -> ArrayMesh:
	return _figure(coat, DARK_BREECH, "round", false, false)


## A minuteman: his own brown coat and round hat, but a musket on his
## shoulder — the Act I American line before uniforms exist (docs/02).
static func build_militiaman(coat: Color) -> ArrayMesh:
	return _figure(coat, DARK_BREECH, "round", true, false)


## A body in the snow: prone figure, one arm flung out, hat beside him.
## Origin at ground level; caller rotates around Y for variety.
static func build_fallen(coat: Color) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var dim := coat.darkened(0.25)
	_box(st, dim, Vector3(0.0, 0.10, 0.05), Vector3(0.40, 0.16, 0.58))
	_box(st, dim, Vector3(0.0, 0.09, -0.28), Vector3(0.44, 0.14, 0.26))
	_box(st, DARK_BREECH, Vector3(0.10, 0.07, -0.65), Vector3(0.13, 0.12, 0.62))
	_box(st, DARK_BREECH, Vector3(-0.10, 0.07, -0.65), Vector3(0.13, 0.12, 0.62))
	_box(st, BOOT, Vector3(0.10, 0.07, -1.02), Vector3(0.13, 0.12, 0.14))
	_box(st, BOOT, Vector3(-0.10, 0.07, -1.02), Vector3(0.13, 0.12, 0.14))
	_box(st, dim, Vector3(0.35, 0.06, 0.18), Vector3(0.11, 0.10, 0.50),
		Basis(Vector3.UP, -0.55))
	_box(st, dim, Vector3(-0.27, 0.07, 0.02), Vector3(0.11, 0.10, 0.48))
	_box(st, SKIN, Vector3(0.0, 0.10, 0.46), Vector3(0.19, 0.20, 0.22))
	_box(st, HAT_BLACK, Vector3(0.42, 0.03, 0.55), Vector3(0.30, 0.04, 0.30))
	_box(st, HAT_BLACK, Vector3(0.42, 0.08, 0.55), Vector3(0.16, 0.09, 0.16))
	return st.commit()


static func _figure(coat: Color, breeches: Color, hat: String,
		musket: bool, belts: bool) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Boots and legs.
	for sx in [-1.0, 1.0]:
		_box(st, BOOT, Vector3(sx * 0.095, FEET + 0.07, 0.02), Vector3(0.13, 0.14, 0.21))
		_box(st, breeches, Vector3(sx * 0.095, FEET + 0.44, 0.0), Vector3(0.13, 0.60, 0.16))
	# Coat body; the unbelted (civilian coats, militia frocks) hang longer.
	_box(st, coat, Vector3(0.0, 0.13, 0.0), Vector3(0.40, 0.56, 0.25))
	if not belts:
		_box(st, coat, Vector3(0.0, -0.30, 0.0), Vector3(0.46, 0.34, 0.31))
	else:
		_box(st, coat, Vector3(0.0, -0.25, 0.0), Vector3(0.44, 0.24, 0.29))
	# Arms and hands.
	for sx in [-1.0, 1.0]:
		_box(st, coat, Vector3(sx * 0.26, 0.12, 0.0), Vector3(0.11, 0.52, 0.14))
		_box(st, SKIN, Vector3(sx * 0.26, -0.19, 0.0), Vector3(0.09, 0.09, 0.11))
	# Neck stock, head, hat.
	_box(st, STOCK_WHITE if belts else coat.darkened(0.3),
		Vector3(0.0, 0.435, 0.0), Vector3(0.13, 0.06, 0.13))
	_box(st, SKIN, Vector3(0.0, 0.55, 0.0), Vector3(0.19, 0.22, 0.20))
	if hat == "tricorn":
		_box(st, HAT_BLACK, Vector3(0.0, 0.685, 0.0), Vector3(0.34, 0.05, 0.34))
		_box(st, HAT_BLACK, Vector3(0.0, 0.77, 0.0), Vector3(0.17, 0.12, 0.17))
	else:
		_box(st, HAT_BLACK, Vector3(0.0, 0.675, 0.0), Vector3(0.30, 0.04, 0.30))
		_box(st, HAT_BLACK, Vector3(0.0, 0.75, 0.0), Vector3(0.19, 0.11, 0.19))
	# Crossbelts and cartridge box — the regular's white X.
	if belts:
		_box(st, BELT_WHITE, Vector3(0.0, 0.14, 0.135), Vector3(0.065, 0.58, 0.02),
			Basis(Vector3.BACK, 0.6))
		_box(st, BELT_WHITE, Vector3(0.0, 0.14, 0.135), Vector3(0.065, 0.58, 0.02),
			Basis(Vector3.BACK, -0.6))
		_box(st, HAT_BLACK, Vector3(0.14, -0.08, -0.15), Vector3(0.16, 0.12, 0.08))
	# Shouldered musket, left side, tip well above the hat: the single
	# strongest period silhouette a marching block can have.
	if musket:
		var tilt := Basis(Vector3.BACK, 0.08)
		_box(st, STEEL, Vector3(-0.29, 0.62, -0.02), Vector3(0.035, 1.10, 0.035), tilt)
		_box(st, WOOD, Vector3(-0.29, 0.05, -0.02), Vector3(0.055, 0.50, 0.06), tilt)
		_box(st, STEEL, Vector3(-0.29, 1.28, -0.02), Vector3(0.018, 0.24, 0.018), tilt)
	return st.commit()


## One axis-aligned (or basis-rotated) box as 12 flat-shaded triangles,
## clockwise winding (Godot front faces), color baked per vertex.
static func _box(st: SurfaceTool, color: Color, center: Vector3, size: Vector3,
		basis := Basis.IDENTITY) -> void:
	var ax := basis.x * (size.x / 2.0)
	var ay := basis.y * (size.y / 2.0)
	var az := basis.z * (size.z / 2.0)
	# Each face: outward normal axis, then four corners clockwise from
	# outside as (sx, sy, sz) signs.
	var faces := [
		[Vector3(0, 0, 1), [[-1, 1, 1], [1, 1, 1], [1, -1, 1], [-1, -1, 1]]],
		[Vector3(0, 0, -1), [[1, 1, -1], [-1, 1, -1], [-1, -1, -1], [1, -1, -1]]],
		[Vector3(1, 0, 0), [[1, 1, 1], [1, 1, -1], [1, -1, -1], [1, -1, 1]]],
		[Vector3(-1, 0, 0), [[-1, 1, -1], [-1, 1, 1], [-1, -1, 1], [-1, -1, -1]]],
		[Vector3(0, 1, 0), [[-1, 1, -1], [1, 1, -1], [1, 1, 1], [-1, 1, 1]]],
		[Vector3(0, -1, 0), [[-1, -1, 1], [1, -1, 1], [1, -1, -1], [-1, -1, -1]]],
	]
	for face in faces:
		var normal: Vector3 = (basis * (face[0] as Vector3)).normalized()
		var quad: Array = face[1]
		var pts: Array[Vector3] = []
		for s in quad:
			pts.append(center + ax * s[0] + ay * s[1] + az * s[2])
		for tri in [[0, 1, 2], [0, 2, 3]]:
			for idx in tri:
				st.set_color(color)
				st.set_normal(normal)
				st.add_vertex(pts[idx])


## The one material every figure MultiMesh needs: white albedo modulated
## by the baked vertex colors (so callers can still fade a broken company
## by tinting the material).
static func figure_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color.WHITE
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.95
	return mat
