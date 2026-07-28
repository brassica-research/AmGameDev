extends RefCounted
## Procedural period figures — the M2 art form pass, second iteration
## (docs/04, docs/09). Every figure is one ArrayMesh of oriented boxes
## with colors baked as vertex colors, so a company still costs a
## handful of draw calls.
##
## Second pass adds POSES. A MultiMesh can't skin a skeleton, so the
## motion comes from swapping which posed mesh a man is drawn in:
## build the set once per company, then each frame sort every man into
## the bucket his sim state and his own gait phase call for. Marching
## legs swing, arms counter-swing, muskets come off the shoulder to
## present, ramrods work, chargers run leaning with the bayonet level.
##
## Silhouette first: tricorn, coat skirts, crossbelts, and the musket
## above the hat line — the shapes that read "1770s" at 40 yards.
## Final art replaces these meshes at look-dev; call sites keep the
## contract (a ~1.7-unit figure standing on y = 0, facing +Z).
##
## Use via preload:
##   const FigureLib := preload("res://src/presentation/figure_lib.gd")

enum Pose {
	STAND,      # at ease in the ranks
	MARCH_A,    # left foot forward
	MARCH_B,    # right foot forward
	PRESENT,    # musket levelled at the shoulder
	FIRE,       # the recoil, half a second of it
	RELOAD,     # musket upright, ramrod working
	CHARGE,     # running in, bayonet level
}

const POSE_COUNT := 7

const SKIN_TONES := [
	Color(0.76, 0.60, 0.47), Color(0.68, 0.51, 0.38),
	Color(0.55, 0.40, 0.29), Color(0.41, 0.29, 0.21),
	Color(0.80, 0.66, 0.54),
]
const HAT_BLACK := Color(0.09, 0.08, 0.08)
const BOOT := Color(0.12, 0.09, 0.07)
const BELT_WHITE := Color(0.78, 0.76, 0.69)
const STOCK_WHITE := Color(0.84, 0.83, 0.79)
const BUFF := Color(0.72, 0.66, 0.52)
const WOOD := Color(0.28, 0.17, 0.10)
const STEEL := Color(0.62, 0.66, 0.72)
const DARK_BREECH := Color(0.19, 0.17, 0.14)

# Body landmarks, feet at -0.85 so the figure centers on its origin.
const FEET := -0.85
const HIP_Y := -0.20
const LEG_LEN := 0.52
const SHOULDER_Y := 0.34
const ARM_LEN := 0.48


static func build_soldier(coat: Color, pose: int = Pose.STAND,
		skin: Color = SKIN_TONES[0], breeches: Color = BUFF, variant := 0) -> ArrayMesh:
	return _figure(coat, breeches, skin, "tricorn", true, true, pose, variant)


static func build_militiaman(coat: Color, pose: int = Pose.STAND,
		skin: Color = SKIN_TONES[0], variant := 0) -> ArrayMesh:
	# Militia wore what they owned: a round hat here, an old cocked hat
	# there, and no two coats the same brown.
	var hat := "tricorn" if variant % 2 == 1 else "round"
	return _figure(coat, DARK_BREECH, skin, hat, true, false, pose, variant)


static func build_civilian(coat: Color, pose: int = Pose.STAND,
		skin: Color = SKIN_TONES[0], variant := 0) -> ArrayMesh:
	var hat := "tricorn" if variant % 3 == 1 else "round"
	return _figure(coat, DARK_BREECH, skin, hat, false, false, pose, variant)


## Build every pose for one dress, in Pose enum order — the set a
## company animates through. `variant` shifts hat, cut, kit, and the
## exact shade of the cloth, so three sets across a company already
## look like a company rather than one man repeated forty times.
static func build_pose_set(coat: Color, kind := "soldier",
		skin: Color = SKIN_TONES[0], variant := 0) -> Array[ArrayMesh]:
	var worn := coat.lerp(Color(0.36, 0.33, 0.30), 0.05 * float(variant % 3))
	var out: Array[ArrayMesh] = []
	for p in POSE_COUNT:
		match kind:
			"militia":
				out.append(build_militiaman(worn, p, skin, variant))
			"civilian":
				out.append(build_civilian(worn, p, skin, variant))
			_:
				out.append(build_soldier(worn, p, skin, BUFF, variant))
	return out


## A body in the snow or the grass: prone, one arm flung out, hat beside
## him. Origin at ground level; callers rotate around Y for variety.
static func build_fallen(coat: Color, skin: Color = SKIN_TONES[0]) -> ArrayMesh:
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
	_box(st, skin, Vector3(0.0, 0.10, 0.46), Vector3(0.19, 0.20, 0.22))
	_box(st, HAT_BLACK, Vector3(0.42, 0.03, 0.55), Vector3(0.30, 0.04, 0.30))
	_box(st, HAT_BLACK, Vector3(0.42, 0.08, 0.55), Vector3(0.16, 0.09, 0.16))
	# A musket fallen where he dropped it.
	_box(st, WOOD, Vector3(-0.45, 0.04, -0.15), Vector3(0.07, 0.07, 1.05),
		Basis(Vector3.UP, 0.35))
	return st.commit()


static func _figure(coat: Color, breeches: Color, skin: Color, hat: String,
		musket: bool, belts: bool, pose: int, variant := 0) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# --- stance -------------------------------------------------------
	# Positive leg angle swings the foot back, negative swings it forward.
	var l_leg := 0.0
	var r_leg := 0.0
	var lean := 0.0        # forward pitch of the whole torso
	var crouch := 0.0      # how much the knees eat
	match pose:
		Pose.MARCH_A:
			l_leg = -0.42
			r_leg = 0.34
			lean = 0.05
		Pose.MARCH_B:
			l_leg = 0.34
			r_leg = -0.42
			lean = 0.05
		Pose.CHARGE:
			l_leg = -0.75
			r_leg = 0.62
			lean = 0.28
			crouch = 0.04
		Pose.PRESENT, Pose.FIRE:
			l_leg = 0.16     # right foot braced back, the firing stance
			r_leg = -0.10
			lean = 0.06 if pose == Pose.PRESENT else -0.05  # recoil rocks him back
		Pose.RELOAD:
			l_leg = -0.12
			r_leg = 0.10

	var hip := Vector3(0.0, HIP_Y - crouch, 0.0)
	_leg(st, breeches, Vector3(0.095, hip.y, 0.0), l_leg)
	_leg(st, breeches, Vector3(-0.095, hip.y, 0.0), r_leg)

	# --- torso --------------------------------------------------------
	var pitch := Basis(Vector3.RIGHT, lean)
	var torso_c := Vector3(0.0, 0.10 - crouch, 0.0)
	# Chest tapers to the waist; the coat skirt flares back out over the
	# hips. Two frusta, not two blocks.
	_tube(st, coat, torso_c + pitch * Vector3(0.0, 0.03, 0.0),
		Vector3(0.40, 0.54, 0.26), pitch, 1.12)
	_tube(st, coat.darkened(0.06), torso_c + pitch * Vector3(0.0, -0.16, 0.0),
		Vector3(0.36, 0.10, 0.24), pitch, 1.0)   # the waistband
	# Coat skirts: the unbelted (militia frocks, greatcoats) hang longer.
	var skirt_h := 0.34 if not belts else 0.24
	_tube(st, coat, torso_c + pitch * Vector3(0.0, -0.22 - skirt_h / 2.0, 0.0),
		Vector3(0.34, skirt_h, 0.26), pitch, 1.30)

	# --- arms ---------------------------------------------------------
	var l_sh := torso_c + pitch * Vector3(0.24, SHOULDER_Y - 0.10, 0.0)
	var r_sh := torso_c + pitch * Vector3(-0.24, SHOULDER_Y - 0.10, 0.0)
	match pose:
		Pose.MARCH_A:
			_arm(st, coat, skin, l_sh, 0.30, 0.0)
			_arm(st, coat, skin, r_sh, -0.34, 0.0)
		Pose.MARCH_B:
			_arm(st, coat, skin, l_sh, -0.34, 0.0)
			_arm(st, coat, skin, r_sh, 0.30, 0.0)
		Pose.PRESENT, Pose.FIRE:
			# Both hands up on the piece, elbows out.
			_arm(st, coat, skin, l_sh, -1.35, 0.22)
			_arm(st, coat, skin, r_sh, -1.05, -0.30)
		Pose.RELOAD:
			_arm(st, coat, skin, l_sh, -1.15, 0.10)
			_arm(st, coat, skin, r_sh, -1.60, 0.05)   # ramrod hand high
		Pose.CHARGE:
			_arm(st, coat, skin, l_sh, -1.25, 0.14)
			_arm(st, coat, skin, r_sh, -0.85, -0.16)
		_:
			_arm(st, coat, skin, l_sh, 0.04, 0.0)
			_arm(st, coat, skin, r_sh, -0.04, 0.0)

	# --- head ---------------------------------------------------------
	var head_c := torso_c + pitch * Vector3(0.0, 0.46, 0.0)
	_tube(st, STOCK_WHITE if belts else coat.darkened(0.3),
		head_c + Vector3(0.0, -0.105, 0.0), Vector3(0.135, 0.08, 0.135))
	# Skull, then a jaw narrowing to the chin — a head, not a die.
	_tube(st, skin, head_c + Vector3(0.0, 0.03, 0.0),
		Vector3(0.185, 0.15, 0.20), Basis.IDENTITY, 1.0, 1.06)
	_tube(st, skin, head_c + Vector3(0.0, -0.075, 0.005),
		Vector3(0.185, 0.08, 0.20), Basis.IDENTITY, 0.72)
	# A queue of hair, clubbed at the neck — every man of the period had one.
	_tube(st, Color(0.20, 0.15, 0.11), head_c + Vector3(0.0, 0.02, -0.10),
		Vector3(0.15, 0.19, 0.12), Basis(Vector3.RIGHT, -0.25), 0.7)
	if hat == "tricorn":
		# Three cocked corners over a round crown: the period's signature.
		_tube(st, HAT_BLACK, head_c + Vector3(0.0, 0.135, 0.0),
			Vector3(0.36, 0.035, 0.36))
		for corner in [Vector3(0.0, 0.0, 0.15), Vector3(0.13, 0.0, -0.09),
				Vector3(-0.13, 0.0, -0.09)]:
			_box(st, HAT_BLACK, head_c + Vector3(0.0, 0.15, 0.0) + corner,
				Vector3(0.20, 0.075, 0.11),
				Basis(Vector3.UP, atan2(corner.x, corner.z)) * Basis(Vector3.RIGHT, 0.55))
		_tube(st, HAT_BLACK, head_c + Vector3(0.0, 0.205, 0.0),
			Vector3(0.185, 0.11, 0.185), Basis.IDENTITY, 0.88)
	else:
		_tube(st, HAT_BLACK, head_c + Vector3(0.0, 0.125, 0.0),
			Vector3(0.32, 0.035, 0.32))
		_tube(st, HAT_BLACK, head_c + Vector3(0.0, 0.19, 0.0),
			Vector3(0.20, 0.11, 0.20), Basis.IDENTITY, 0.92)

	# --- kit ----------------------------------------------------------
	if belts:
		var belt_c := torso_c + pitch * Vector3(0.0, 0.04, 0.135)
		_box(st, BELT_WHITE, belt_c, Vector3(0.065, 0.56, 0.02),
			pitch * Basis(Vector3.BACK, 0.6))
		_box(st, BELT_WHITE, belt_c, Vector3(0.065, 0.56, 0.02),
			pitch * Basis(Vector3.BACK, -0.6))
		_box(st, HAT_BLACK, torso_c + pitch * Vector3(0.15, -0.22, -0.14),
			Vector3(0.17, 0.13, 0.09), pitch)   # cartridge box on the hip
	else:
		# Militia: powder horn and hunting bag on a strap.
		_box(st, Color(0.55, 0.47, 0.28), torso_c + pitch * Vector3(0.17, -0.16, 0.10),
			Vector3(0.09, 0.09, 0.24), pitch * Basis(Vector3.UP, 0.4))
		_box(st, Color(0.32, 0.24, 0.16), torso_c + pitch * Vector3(-0.16, -0.20, 0.08),
			Vector3(0.16, 0.16, 0.08), pitch)

	# Kit a man carries because he chose to: a rolled blanket over the
	# shoulder, a wooden canteen on a cord. Varies per variant, so a
	# company reads as individuals who packed differently.
	if variant % 3 == 2:
		_tube(st, coat.lerp(Color(0.45, 0.42, 0.36), 0.55),
			torso_c + pitch * Vector3(0.02, 0.14, -0.06),
			Vector3(0.14, 0.52, 0.14), pitch * Basis(Vector3.BACK, 1.15), 1.0)
	if variant % 3 == 1:
		_tube(st, Color(0.42, 0.33, 0.21), torso_c + pitch * Vector3(-0.20, -0.17, 0.09),
			Vector3(0.19, 0.09, 0.19), pitch * Basis(Vector3.RIGHT, PI / 2.0))
	if musket:
		_musket(st, pose, torso_c, pitch)
	return st.commit()


## The piece, wherever this pose holds it. Barrel + stock + bayonet, so
## the bayonet line reads even at distance.
static func _musket(st: SurfaceTool, pose: int, torso_c: Vector3, pitch: Basis) -> void:
	var origin := Vector3.ZERO
	var basis := Basis.IDENTITY
	match pose:
		Pose.PRESENT, Pose.FIRE:
			# Levelled at the enemy: barrel forward, butt at the shoulder.
			origin = torso_c + Vector3(0.20, 0.26, 0.42)
			basis = Basis(Vector3.RIGHT, PI / 2.0 - 0.06)
			if pose == Pose.FIRE:
				basis = Basis(Vector3.RIGHT, PI / 2.0 - 0.16)  # muzzle jump
		Pose.RELOAD:
			# Butt on the ground between the feet, muzzle up, ramrod in.
			origin = torso_c + Vector3(0.16, 0.10, 0.20)
			basis = Basis(Vector3.RIGHT, 0.18)
		Pose.CHARGE:
			# Both hands, bayonet level at chest height, running.
			origin = torso_c + Vector3(0.10, 0.10, 0.40)
			basis = Basis(Vector3.RIGHT, PI / 2.0 + 0.10)
		_:
			# Shouldered: near-vertical on the left shoulder.
			origin = torso_c + pitch * Vector3(-0.28, 0.42, -0.02)
			basis = pitch * Basis(Vector3.BACK, 0.08)
	_tube(st, STEEL, origin + basis * Vector3(0, 0.20, 0), Vector3(0.036, 1.06, 0.036), basis)
	_tube(st, WOOD, origin + basis * Vector3(0, -0.36, 0), Vector3(0.058, 0.52, 0.062), basis)
	_box(st, WOOD, origin + basis * Vector3(0, -0.62, 0.01), Vector3(0.075, 0.18, 0.10), basis)
	_tube(st, STEEL, origin + basis * Vector3(0, 0.86, 0), Vector3(0.018, 0.26, 0.018), basis)
	if pose == Pose.RELOAD:
		# The ramrod, half-drawn.
		_box(st, STEEL, origin + basis * Vector3(0.05, 0.62, 0.06),
			Vector3(0.016, 0.62, 0.016), basis)


## A limb hanging from `pivot`, swung `angle` radians about X.
static func _leg(st: SurfaceTool, cloth: Color, pivot: Vector3, angle: float) -> void:
	var b := Basis(Vector3.RIGHT, angle)
	# Thigh tapering to the knee, then the gaitered calf below it.
	_tube(st, cloth, pivot + b * Vector3(0, -LEG_LEN * 0.28, 0),
		Vector3(0.155, LEG_LEN * 0.56, 0.17), b, 0.80)
	_tube(st, BOOT, pivot + b * Vector3(0, -LEG_LEN * 0.78, 0.005),
		Vector3(0.125, LEG_LEN * 0.48, 0.135), b, 0.86)
	# The shoe: a low block, because a shoe IS a low block.
	_box(st, BOOT, pivot + b * Vector3(0, -LEG_LEN - 0.045, 0.035),
		Vector3(0.125, 0.09, 0.24), b)


static func _arm(st: SurfaceTool, coat: Color, skin: Color, shoulder: Vector3,
		angle: float, spread: float) -> void:
	var b := Basis(Vector3.RIGHT, angle) * Basis(Vector3.BACK, spread)
	_tube(st, coat, shoulder + b * Vector3(0, -ARM_LEN * 0.30, 0),
		Vector3(0.125, ARM_LEN * 0.62, 0.135), b, 0.82)
	_tube(st, coat.lightened(0.05), shoulder + b * Vector3(0, -ARM_LEN * 0.76, 0),
		Vector3(0.10, ARM_LEN * 0.40, 0.11), b, 0.92)   # the turned-back cuff
	_tube(st, skin, shoulder + b * Vector3(0, -ARM_LEN - 0.04, 0),
		Vector3(0.095, 0.11, 0.115), b, 0.85)


## An octagonal prism along the basis' Y axis — limbs, torsos, barrels.
## Eight sides instead of four is the whole difference between "boxes
## wearing coats" and a body: silhouettes lose their corners and the
## shading rolls around the form. `taper` scales the top ring, so the
## same call makes a tapering thigh, a coat narrowing to the waist, or
## a flaring skirt.
static func _tube(st: SurfaceTool, color: Color, center: Vector3, size: Vector3,
		basis := Basis.IDENTITY, taper := 1.0, front_bias := 1.0) -> void:
	var half_h := size.y / 2.0
	var ring: Array[Vector2] = []
	for k in 8:
		var a := (float(k) + 0.5) * TAU / 8.0
		ring.append(Vector2(cos(a), sin(a)))
	var bottom: Array[Vector3] = []
	var top: Array[Vector3] = []
	for r in ring:
		var zb := r.y * (size.z / 2.0) * (front_bias if r.y > 0.0 else 1.0)
		bottom.append(center + basis * Vector3(r.x * size.x / 2.0, -half_h, zb))
		top.append(center + basis * Vector3(r.x * size.x / 2.0 * taper, half_h,
			zb * taper))
	for k in 8:
		var n := (k + 1) % 8
		var normal: Vector3 = (basis * Vector3(ring[k].x, 0.0, ring[k].y)).normalized()
		for tri in [[top[k], top[n], bottom[n]], [top[k], bottom[n], bottom[k]]]:
			for v in tri:
				st.set_color(color)
				st.set_normal(normal)
				st.add_vertex(v)
	# Caps.
	for cap in [[top, basis * Vector3.UP], [bottom, basis * Vector3.DOWN]]:
		var pts: Array = cap[0]
		var normal: Vector3 = cap[1]
		var center_pt := Vector3.ZERO
		for p in pts:
			center_pt += p
		center_pt /= float(pts.size())
		for k in 8:
			var n := (k + 1) % 8
			var tri: Array = [center_pt, pts[k], pts[n]] if normal.dot(basis * Vector3.UP) > 0.0 \
				else [center_pt, pts[n], pts[k]]
			for v in tri:
				st.set_color(color)
				st.set_normal(normal)
				st.add_vertex(v)


## One box as 12 flat-shaded triangles, clockwise from outside (Godot
## front faces), color baked per vertex.
static func _box(st: SurfaceTool, color: Color, center: Vector3, size: Vector3,
		basis := Basis.IDENTITY) -> void:
	var ax := basis.x * (size.x / 2.0)
	var ay := basis.y * (size.y / 2.0)
	var az := basis.z * (size.z / 2.0)
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
## by baked vertex colors, so callers can still fade a broken company.
static func figure_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color.WHITE
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.95
	return mat


## Deterministic skin tone for man `i` of a company — the Continental
## line was the most integrated American army until the Second World
## War (docs/08 §4); the ranks should look it.
static func skin_for(i: int, salt: int = 0) -> Color:
	return SKIN_TONES[absi((i * 2654435761 + salt * 97) / 7) % SKIN_TONES.size()]

# --- the men who are not privates ---------------------------------------
#
# A company read as forty identical figures because that is what it was.
# Every real company had a handful of men you could pick out at two
# hundred yards by silhouette alone: the officer with a sword and no
# musket, the sergeant carrying a spontoon, the drummer, and the ensign
# with the colours. They are built as single meshes (four per company,
# not forty), so they cost nothing and they break the rank.

## An officer: no musket, a sword at his side, a spontoon-free hand for
## gesturing, and a laced hat. He stands a little straighter.
static func build_officer(coat: Color, skin: Color = SKIN_TONES[1]) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_body(st, coat.lightened(0.06), BUFF, skin, "tricorn", Pose.STAND, 0, false)
	# A sword hung on the left hip, hilt forward.
	var b := Basis(Vector3.RIGHT, 0.30)
	_box(st, Color(0.72, 0.62, 0.28), Vector3(-0.24, -0.34, -0.02),
		Vector3(0.05, 0.62, 0.05), b)
	_box(st, Color(0.72, 0.62, 0.28), Vector3(-0.24, 0.02, -0.02),
		Vector3(0.09, 0.13, 0.09))
	# A gorget at the throat — the mark of a commissioned man on duty.
	_box(st, Color(0.78, 0.66, 0.30), Vector3(0.0, 0.40, 0.115),
		Vector3(0.13, 0.06, 0.03))
	# Hat lace.
	_tube(st, Color(0.80, 0.70, 0.34), Vector3(0.0, 0.585, 0.0),
		Vector3(0.365, 0.018, 0.365))
	return st.commit()


## A sergeant: musket exchanged for a spontoon, which is a nine-foot
## silhouette nobody else has.
static func build_sergeant(coat: Color, skin: Color = SKIN_TONES[3]) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_body(st, coat, BUFF, skin, "tricorn", Pose.STAND, 0, true)
	var b := Basis(Vector3.BACK, 0.07)
	_tube(st, WOOD, Vector3(0.30, 0.30, 0.06), Vector3(0.045, 2.6, 0.045), b)
	_box(st, STEEL, Vector3(0.30, 1.68, 0.06), Vector3(0.10, 0.34, 0.03), b)
	_box(st, STEEL, Vector3(0.30, 1.50, 0.06), Vector3(0.26, 0.05, 0.03), b)
	return st.commit()


## A drummer: the drum at his hip is unmistakable, and drummers wore
## reversed facings — the coat colours swapped — so he reads as odd at
## any distance, which is exactly what he was for.
static func build_drummer(coat: Color, facing_col: Color,
		skin: Color = SKIN_TONES[2]) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_body(st, facing_col, BUFF, skin, "round", Pose.STAND, 1, false)
	# The drum, slung at the left hip.
	_tube(st, Color(0.76, 0.66, 0.44), Vector3(-0.30, -0.36, 0.10),
		Vector3(0.52, 0.44, 0.52), Basis(Vector3.BACK, 0.35))
	_tube(st, coat, Vector3(-0.30, -0.14, 0.10),
		Vector3(0.54, 0.05, 0.54), Basis(Vector3.BACK, 0.35))
	_tube(st, coat, Vector3(-0.30, -0.58, 0.10),
		Vector3(0.54, 0.05, 0.54), Basis(Vector3.BACK, 0.35))
	# Sticks.
	_box(st, Color(0.84, 0.78, 0.62), Vector3(-0.10, -0.16, 0.30),
		Vector3(0.03, 0.03, 0.42), Basis(Vector3.UP, 0.3))
	return st.commit()


## The ensign with the colours: a pole twice his height and a cloth that
## catches the wind. One of these in a company changes the whole read of
## a line at distance.
static func build_colours(coat: Color, flag: Color,
		skin: Color = SKIN_TONES[0]) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_body(st, coat, BUFF, skin, "tricorn", Pose.STAND, 2, false)
	_tube(st, WOOD, Vector3(0.28, 0.75, 0.04), Vector3(0.05, 3.5, 0.05))
	# The cloth, hanging in folds rather than as one flat sheet.
	for k in 4:
		var fold := 0.06 * sin(float(k) * 1.7)
		_box(st, flag.darkened(0.06 * float(k % 2)),
			Vector3(0.28 + 0.36 + float(k) * 0.26, 1.95, 0.04 + fold),
			Vector3(0.26, 0.78, 0.03))
	_box(st, Color(0.80, 0.70, 0.34), Vector3(0.28, 2.55, 0.04),
		Vector3(0.08, 0.16, 0.08))   # the finial
	return st.commit()


## The shared body used by the command figures — the same construction
## the ranks use, exposed so an officer is a soldier who is dressed
## differently rather than a different species.
static func _body(st: SurfaceTool, coat: Color, breeches: Color, skin: Color,
		hat: String, pose: int, variant: int, musket: bool) -> void:
	var built := _figure(coat, breeches, skin, hat, musket, true, pose, variant)
	var arrays := built.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var cols: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	for i in verts.size():
		st.set_color(cols[i])
		st.set_normal(norms[i])
		st.add_vertex(verts[i])
