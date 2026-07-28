extends RefCounted
## The house look (docs/04, docs/06) in one place. Every scene — field,
## town, cutscene — builds its environment here, so the game has ONE eye
## rather than three hand-rolled ones that drift apart.
##
## The reference is the modern historical-open-world grade (the playtest
## directive: "closer to an Assassin's Creed aesthetic"), pulled toward
## this game's own restraint: filmic tonemapping, a real gradient sky
## instead of a flat clear colour, warm key against cool shadow, glow
## that only blooms where fire and candlelight actually are, muted
## saturation, and depth fog doing the work of distance. What we do NOT
## take is the saturated postcard look — Boston in April is a cold town.
##
## Use via preload:
##   const LookDev := preload("res://src/presentation/look_dev.gd")

## Named hours. Each is a full grade: sky, light, fog, and exposure.
const HOURS := {
	"dawn": {                                  # Lexington, 05:00, April 19
		"sky_top": Color(0.30, 0.40, 0.62), "sky_horizon": Color(0.78, 0.72, 0.66),
		"ground": Color(0.24, 0.24, 0.26),
		"sun_angle": Vector3(-12.0, 55.0, 0.0), "sun_energy": 1.15,
		"sun_color": Color(1.0, 0.88, 0.76),
		"ambient": Color(0.50, 0.57, 0.74), "ambient_energy": 0.42,
		"fog": Color(0.60, 0.58, 0.58), "fog_density": 0.0014,
		"fill_color": Color(0.52, 0.62, 0.92),   # dawn shadows are blue
		"exposure": 0.90,
	},
	"overcast": {                              # the default New England day
		"sky_top": Color(0.52, 0.56, 0.62), "sky_horizon": Color(0.70, 0.72, 0.74),
		"ground": Color(0.26, 0.27, 0.26),
		"sun_angle": Vector3(-44.0, 40.0, 0.0), "sun_energy": 1.05,
		"sun_color": Color(1.0, 0.97, 0.92),
		"ambient": Color(0.78, 0.80, 0.84), "ambient_energy": 0.66,
		"fog": Color(0.64, 0.67, 0.70), "fog_density": 0.0016,
		"exposure": 1.0,
	},
	"afternoon": {                             # the Battle Road, going home
		"sky_top": Color(0.26, 0.44, 0.72), "sky_horizon": Color(0.74, 0.78, 0.80),
		"ground": Color(0.28, 0.28, 0.24),
		"sun_angle": Vector3(-52.0, 25.0, 0.0), "sun_energy": 1.35,
		"sun_color": Color(1.0, 0.96, 0.86),
		"ambient": Color(0.72, 0.78, 0.88), "ambient_energy": 0.60,
		"fog": Color(0.62, 0.67, 0.72), "fog_density": 0.0015,
		"fill_color": Color(0.62, 0.74, 0.98),
		"exposure": 1.0,
	},
	"night": {                                 # a quarter moon over a field
		"sky_top": Color(0.03, 0.04, 0.09), "sky_horizon": Color(0.09, 0.12, 0.20),
		"ground": Color(0.04, 0.05, 0.07),
		"sun_angle": Vector3(-36.0, -25.0, 0.0), "sun_energy": 0.42,
		"sun_color": Color(0.66, 0.76, 0.98),
		"ambient": Color(0.30, 0.38, 0.56), "ambient_energy": 0.30,
		"fog": Color(0.08, 0.11, 0.18), "fog_density": 0.0034,
		"exposure": 1.15,
	},
	"town_night": {                            # Boston under occupation
		"sky_top": Color(0.02, 0.03, 0.08), "sky_horizon": Color(0.10, 0.12, 0.19),
		"ground": Color(0.05, 0.05, 0.07),
		"sun_angle": Vector3(-38.0, -28.0, 0.0), "sun_energy": 0.55,
		"sun_color": Color(0.68, 0.78, 1.0),
		"ambient": Color(0.36, 0.44, 0.64), "ambient_energy": 0.55,
		"fog": Color(0.07, 0.10, 0.17), "fog_density": 0.0075,
		"fill_color": Color(0.42, 0.54, 0.86),
		"exposure": 1.2,
	},
}


## The graded environment for an hour. `weather` may be "clear",
## "overcast", or "rain"; rain eats light and distance both.
static func environment(hour: String, weather := "clear") -> Environment:
	var h: Dictionary = HOURS.get(hour, HOURS["overcast"])
	var env := Environment.new()

	# A real sky, not a fill colour: the horizon gradient is most of what
	# sells depth in an exterior, and it lights the scene for free.
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = h["sky_top"]
	sky_mat.sky_horizon_color = h["sky_horizon"]
	sky_mat.ground_bottom_color = h["ground"]
	sky_mat.ground_horizon_color = h["sky_horizon"]
	sky_mat.sky_energy_multiplier = 1.0
	sky_mat.sun_angle_max = 12.0
	sky_mat.sun_curve = 0.12
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = h["ambient"]
	env.ambient_light_energy = h["ambient_energy"]

	# Filmic tonemapping with a little exposure headroom: highlights roll
	# off instead of clipping, which is the single biggest difference
	# between "engine output" and "a photographed scene".
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = h["exposure"]
	env.tonemap_white = 1.15

	# Bloom only where there is real fire: candles, muzzle flash, lamps.
	env.glow_enabled = true
	env.glow_intensity = 0.38
	env.glow_bloom = 0.10
	env.glow_strength = 1.05
	env.glow_hdr_threshold = 1.35
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT

	# Muted, cool-shadowed grade (docs/06: saturation ceiling ~70%).
	env.adjustment_enabled = true
	env.adjustment_brightness = 1.0
	env.adjustment_contrast = 1.16
	env.adjustment_saturation = 0.88

	env.fog_enabled = true
	env.fog_light_color = h["fog"]
	env.fog_density = h["fog_density"]
	env.fog_sky_affect = 0.12     # a touch of horizon haze, not a milk bath
	env.fog_aerial_perspective = 0.28

	if weather == "rain":
		env.ambient_light_color = (h["ambient"] as Color).lerp(Color(0.55, 0.58, 0.62), 0.6)
		env.ambient_light_energy = float(h["ambient_energy"]) * 0.75
		env.fog_light_color = (h["fog"] as Color).darkened(0.35)
		env.fog_density = float(h["fog_density"]) * 3.2
		env.adjustment_saturation = 0.72
	return env


## The key light for an hour — sun or moon, with shadows unless the rig
## can't afford them (software GL).
static func key_light(hour: String, weather := "clear", shadows := true) -> DirectionalLight3D:
	var h: Dictionary = HOURS.get(hour, HOURS["overcast"])
	var light := DirectionalLight3D.new()
	light.rotation_degrees = h["sun_angle"]
	light.light_energy = float(h["sun_energy"]) * (0.45 if weather == "rain" else 1.0)
	light.light_color = h["sun_color"]
	light.light_angular_distance = 1.2      # soft-edged shadows, not razor
	if shadows:
		light.shadow_enabled = true
		light.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
		light.directional_shadow_max_distance = 145.0
		light.directional_shadow_blend_splits = true
		light.directional_shadow_split_1 = 0.06     # detail close to the camera
		light.directional_shadow_split_2 = 0.18
		light.shadow_bias = 0.035
		light.shadow_normal_bias = 1.2
		light.shadow_blur = 1.35                    # the sun is not a laser
	return light


## A cool fill from the opposite side. Real scenes are never lit from one
## direction only; this is what keeps shadowed coats from going to mud.
static func fill_light(hour: String) -> DirectionalLight3D:
	var h: Dictionary = HOURS.get(hour, HOURS["overcast"])
	var angle: Vector3 = h["sun_angle"]
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-26.0, angle.y + 158.0, 0.0)
	fill.light_energy = 0.26
	fill.light_color = h.get("fill_color", Color(0.60, 0.70, 0.95))
	fill.shadow_enabled = false
	return fill


## Light thrown back UP off the ground. Half of what makes an outdoor
## photograph look outdoors is the earth bouncing the sun into the
## undersides of things — coat skirts, hat brims, the belly of a horse.
## Without it, everything below the waist goes to flat shadow, which is
## most of why a scene reads as "engine output" (docs/06).
static func bounce_light(hour: String) -> DirectionalLight3D:
	var h: Dictionary = HOURS.get(hour, HOURS["overcast"])
	var ground: Color = h["ground"]
	var bounce := DirectionalLight3D.new()
	# Pointing UP: elevation positive.
	bounce.rotation_degrees = Vector3(62.0, float((h["sun_angle"] as Vector3).y) + 20.0, 0.0)
	bounce.light_energy = float(h["sun_energy"]) * 0.18
	# The bounce carries the colour of what it bounced off.
	bounce.light_color = ground.lerp(h["sun_color"], 0.55)
	bounce.shadow_enabled = false
	return bounce


## A back light that separates a dark figure from a dark background.
## The one deliberate cheat in the rig, and the oldest one in the trade.
static func rim_light(hour: String) -> DirectionalLight3D:
	var h: Dictionary = HOURS.get(hour, HOURS["overcast"])
	var angle: Vector3 = h["sun_angle"]
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-14.0, angle.y + 196.0, 0.0)
	rim.light_energy = 0.30
	rim.light_color = (h["sun_color"] as Color).lerp(Color(0.72, 0.82, 1.0), 0.5)
	rim.shadow_enabled = false
	return rim


## Which hour a battle scenario is fought at.
static func hour_for_scenario(scenario: String, night: bool) -> String:
	if night:
		return "night"
	match scenario:
		"lexington": return "dawn"
		"battle_road": return "afternoon"
		_: return "overcast"
