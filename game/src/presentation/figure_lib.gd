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
		skin: Color = SKIN_TONES[0], breeches: Color = BUFF) -> ArrayMesh:
	return _figure(coat, breeches, skin, "tricorn", true, true, pose)


static func build_militiaman(coat: Color, pose: int = Pose.STAND,
		skin: Color = SKIN_TONES[0]) -> ArrayMesh:
	return _figure(coat, DARK_BREECH, skin, "round", true, false, pose)


static func build_civilian(coat: Color, pose: int = Pose.STAND,
		skin: Color = SKIN_TONES[0]) -> ArrayMesh:
	return _figure(coat, DARK_BREECH, skin, "round", false, false, pose)


## Build every pose for one dress, in Pose enum order — the set a
## company animates through.
static func build_pose_set(coat: Color, kind := "soldier",
		skin: Color = SKIN_TONES[0]) -> Array[ArrayMesh]:
	var out: Array[ArrayMesh] = []
	for p in POSE_COUNT:
		match kind:
			"militia":
				out.append(build_militiaman(coat, p, skin))
			"civilian":
				out.append(build_civilian(coat, p, skin))
			_:
				out.append(build_soldier(coat, p, skin))
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
		musket: bool, belts: bool, pose: int) -> ArrayMesh:
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
	_box(st, coat, torso_c + pitch * Vector3(0.0, 0.03, 0.0),
		Vector3(0.40, 0.54, 0.25), pitch)
	# Coat skirts: the unbelted (militia frocks, greatcoats) hang longer.
	var skirt_h := 0.34 if not belts else 0.24
	_box(st, coat, torso_c + pitch * Vector3(0.0, -0.38, 0.0),
		Vector3(0.45, skirt_h, 0.30), pitch)

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
	_box(st, STOCK_WHITE if belts else coat.darkened(0.3),
		head_c + Vector3(0.0, -0.10, 0.0), Vector3(0.13, 0.07, 0.13))
	_box(st, skin, head_c, Vector3(0.185, 0.21, 0.195))
	# A queue of hair, clubbed at the neck — every man of the period had one.
	_box(st, Color(0.20, 0.15, 0.11), head_c + Vector3(0.0, -0.02, -0.13),
		Vector3(0.13, 0.20, 0.08))
	if hat == "tricorn":
		_box(st, HAT_BLACK, head_c + Vector3(0.0, 0.135, 0.0), Vector3(0.35, 0.045, 0.35))
		_box(st, HAT_BLACK, head_c + Vector3(0.0, 0.135, 0.10), Vector3(0.30, 0.10, 0.10),
			Basis(Vector3.RIGHT, 0.5))   # the cocked front brim
		_box(st, HAT_BLACK, head_c + Vector3(0.0, 0.215, 0.0), Vector3(0.17, 0.12, 0.17))
	else:
		_box(st, HAT_BLACK, head_c + Vector3(0.0, 0.125, 0.0), Vector3(0.31, 0.04, 0.31))
		_box(st, HAT_BLACK, head_c + Vector3(0.0, 0.195, 0.0), Vector3(0.19, 0.11, 0.19))

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
	_box(st, STEEL, origin + basis * Vector3(0, 0.20, 0), Vector3(0.038, 1.06, 0.038), basis)
	_box(st, WOOD, origin + basis * Vector3(0, -0.36, 0), Vector3(0.06, 0.52, 0.065), basis)
	_box(st, WOOD, origin + basis * Vector3(0, -0.62, 0.01), Vector3(0.075, 0.18, 0.10), basis)
	_box(st, STEEL, origin + basis * Vector3(0, 0.86, 0), Vector3(0.019, 0.26, 0.019), basis)
	if pose == Pose.RELOAD:
		# The ramrod, half-drawn.
		_box(st, STEEL, origin + basis * Vector3(0.05, 0.62, 0.06),
			Vector3(0.016, 0.62, 0.016), basis)


## A limb hanging from `pivot`, swung `angle` radians about X.
static func _leg(st: SurfaceTool, cloth: Color, pivot: Vector3, angle: float) -> void:
	var b := Basis(Vector3.RIGHT, angle)
	_box(st, cloth, pivot + b * Vector3(0, -LEG_LEN / 2.0, 0),
		Vector3(0.135, LEG_LEN, 0.16), b)
	# Gaiters over the shoe — black, buttoned, to the knee.
	_box(st, BOOT, pivot + b * Vector3(0, -LEG_LEN - 0.055, 0.02),
		Vector3(0.14, 0.13, 0.22), b)


static func _arm(st: SurfaceTool, coat: Color, skin: Color, shoulder: Vector3,
		angle: float, spread: float) -> void:
	var b := Basis(Vector3.RIGHT, angle) * Basis(Vector3.BACK, spread)
	_box(st, coat, shoulder + b * Vector3(0, -ARM_LEN / 2.0, 0),
		Vector3(0.115, ARM_LEN, 0.14), b)
	_box(st, skin, shoulder + b * Vector3(0, -ARM_LEN - 0.045, 0),
		Vector3(0.095, 0.10, 0.115), b)


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
