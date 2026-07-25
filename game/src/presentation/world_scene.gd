extends Node3D
## The free-world / stealth scene (docs/13): occupied Boston at street
## level. Presentation only — it reads WorldSim state and turns input
## into CommandBus commands, exactly as the battle scene does, so a
## walk through town is as deterministic and replayable as a volley.
##
## CONTROLS
##   W A S D / arrows   walk (camera-relative)
##   SHIFT (hold)       run — fast, and loud enough to turn heads
##   CTRL (hold)        crouch — slow, and half as visible
##   Q / E              swing the camera
##   ENTER              restart · ESC back to the battle
##
## Args after `--`:
##   --world=<id>       which data/world/<id>.json to walk
##   --auto             the scripted walk (films, tests)
##   --lowfx            painted light pools instead of omni lights
##                      (software GL / low-end rigs)
##   --quit-after=N     film-mode safety quit

const FigureLib := preload("res://src/presentation/figure_lib.gd")
const ColonialLib := preload("res://src/presentation/colonial_lib.gd")
const WORLD_DIR := "res://data/world"

var sim: WorldSim
var clock := SimClock.new()

var _auto := false
var _quit_after := 0.0
var _elapsed := 0.0
var _anim_time := 0.0
var _cam_yaw := 0.0
var _cam: Camera3D
var _avatar: Node3D
var _watcher_nodes: Dictionary = {}
var _cone_nodes: Dictionary = {}
var _hud: Label
var _log_label: Label
var _title: Label
var _last_stance := WorldSim.Stance.WALK
## Capture / low-end rig: trades real omni lights for painted pools.
var _lowfx := false


func _ready() -> void:
	var args := _parse_user_args()
	_auto = args.has("auto")
	_lowfx = args.has("lowfx")
	_quit_after = float(String(args.get("quit-after", "0")))
	var id := String(args.get("world", "boston_1775"))
	var file := FileAccess.open("%s/%s.json" % [WORLD_DIR, id], FileAccess.READ)
	if file == null:
		push_error("World not found: %s" % id)
		return
	var data: Dictionary = JSON.parse_string(file.get_as_text())
	sim = WorldSim.from_data(data, 17750418)
	if not _auto:
		sim.demo_path = []      # a human is driving
	_build_environment()
	_build_town(data)
	_build_actors()
	_build_hud(String(data.get("title", "")))


func _parse_user_args() -> Dictionary:
	var out := {}
	for a in OS.get_cmdline_user_args():
		if not a.begins_with("--"):
			continue
		var body := a.substr(2)
		if body.contains("="):
			var kv := body.split("=", true, 1)
			out[kv[0]] = kv[1]
		else:
			out[body] = "true"
	return out


func _process(delta: float) -> void:
	_anim_time += delta
	_elapsed += delta
	if not _auto and not sim.over:
		_read_input()
	clock.advance(delta, func(_t: int) -> void: sim.step())
	_update_avatar()
	_update_watchers()
	_update_camera(delta)
	_update_hud()
	if _quit_after > 0.0 and _elapsed >= _quit_after:
		get_tree().quit()


## Input becomes COMMANDS, never direct state — the avatar is a man the
## sim simulates, not a puppet the renderer moves (docs/12 §2).
func _read_input() -> void:
	var ix := 0.0
	var iz := 0.0
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		iz += 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		iz -= 1.0
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		ix -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		ix += 1.0
	# Camera-relative, so "forward" always means "away from the camera".
	var cos_y := cos(_cam_yaw)
	var sin_y := sin(_cam_yaw)
	var wx := ix * cos_y + iz * sin_y
	var wz := -ix * sin_y + iz * cos_y
	sim.bus.submit(sim.tick + 1, "avatar", "move", {"x": wx, "z": wz})
	var stance := WorldSim.Stance.WALK
	if Input.is_key_pressed(KEY_SHIFT):
		stance = WorldSim.Stance.RUN
	elif Input.is_key_pressed(KEY_CTRL):
		stance = WorldSim.Stance.CROUCH
	if stance != _last_stance:
		_last_stance = stance
		sim.bus.submit(sim.tick + 1, "avatar", "stance", {"stance": stance})
	if Input.is_key_pressed(KEY_Q):
		_cam_yaw -= 1.6 * get_process_delta_time()
	if Input.is_key_pressed(KEY_E):
		_cam_yaw += 1.6 * get_process_delta_time()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and (event as InputEventKey).pressed:
		match (event as InputEventKey).keycode:
			KEY_ENTER: get_tree().reload_current_scene()
			KEY_ESCAPE: get_tree().change_scene_to_file("res://scenes/battle.tscn")


# --- construction ------------------------------------------------------

func _build_environment() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.05, 0.06, 0.11)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.42, 0.48, 0.66)
	env.ambient_light_energy = 0.55
	env.fog_enabled = true
	env.fog_light_color = Color(0.10, 0.13, 0.21)
	env.fog_density = 0.010          # a April night off the harbor
	env.fog_sky_affect = 0.0
	we.environment = env
	add_child(we)
	var moon := DirectionalLight3D.new()
	moon.rotation_degrees = Vector3(-38.0, -28.0, 0.0)
	moon.light_energy = 0.62
	moon.light_color = Color(0.70, 0.79, 0.99)
	add_child(moon)
	ColonialLib.make_moon(self, moon)
	_cam = Camera3D.new()
	_cam.fov = 62.0
	add_child(_cam)


func _build_town(data: Dictionary) -> void:
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(220.0, 220.0)
	plane.material = ColonialLib.ground_material("night_field")
	ground.mesh = plane
	add_child(ground)
	for b in sim.blocks:
		ColonialLib.make_building(self, String(b["name"]),
			Vector3(float(b["x"]), 0.0, float(b["z"])),
			Vector3(float(b["w"]), float(b["h"]), float(b["d"])),
			Color(0.24, 0.23, 0.27))
	# Streetlamps at the crossings: pools of light are places NOT to walk.
	# Under software GL each omni light costs an extra forward pass on
	# every object in range, and a town is a lot of objects — so the
	# capture rig trades the real lights for painted pools of light.
	for c in data.get("crowds", []):
		var at := Vector3(float(c["pos"][0]), 0.0, float(c["pos"][1]))
		if _lowfx:
			var pool := MeshInstance3D.new()
			var disc := CylinderMesh.new()
			disc.top_radius = 7.5
			disc.bottom_radius = 7.5
			disc.height = 0.02
			disc.radial_segments = 16
			var pmat := StandardMaterial3D.new()
			pmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			pmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			pmat.albedo_color = Color(1.0, 0.80, 0.45, 0.13)
			disc.material = pmat
			pool.mesh = disc
			pool.position = at + Vector3(0.0, 0.06, 0.0)
			add_child(pool)
		else:
			var lamp := OmniLight3D.new()
			lamp.light_color = Color(1.0, 0.78, 0.42)
			lamp.light_energy = 2.6
			lamp.omni_range = 16.0
			lamp.position = at + Vector3(0.0, 3.4, 0.0)
			add_child(lamp)
		# The lamp post itself, either way.
		var post := MeshInstance3D.new()
		var pbox := BoxMesh.new()
		pbox.size = Vector3(0.16, 3.4, 0.16)
		var postmat := StandardMaterial3D.new()
		postmat.albedo_color = Color(0.12, 0.11, 0.10)
		pbox.material = postmat
		post.mesh = pbox
		post.position = at + Vector3(0.0, 1.7, 0.0)
		add_child(post)
	# The crowds themselves — cover you can walk into.
	for c in sim.crowds:
		var poses := FigureLib.build_pose_set(Color(0.30, 0.29, 0.34), "civilian",
			FigureLib.skin_for(int(float(c["x"])) + 5))
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = poses[FigureLib.Pose.STAND]
		mm.instance_count = int(c["count"])
		for i in mm.instance_count:
			var a := float(i) * TAU / float(mm.instance_count) + float(c["x"])
			var rr: float = float(c["r"]) * (0.35 + 0.5 * float((i * 37) % 10) / 10.0)
			mm.set_instance_transform(i, Transform3D(
				Basis.IDENTITY.rotated(Vector3.UP, a + PI),
				Vector3(float(c["x"]) + cos(a) * rr, 0.85, float(c["z"]) + sin(a) * rr)))
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = FigureLib.figure_material()
		add_child(mmi)


func _build_actors() -> void:
	_avatar = MeshInstance3D.new()
	(_avatar as MeshInstance3D).mesh = FigureLib.build_civilian(
		Color(0.26, 0.24, 0.30), FigureLib.Pose.STAND, FigureLib.skin_for(2))
	(_avatar as MeshInstance3D).material_override = FigureLib.figure_material()
	add_child(_avatar)
	for w in sim.watchers:
		var node := MeshInstance3D.new()
		node.mesh = FigureLib.build_soldier(Color(0.56, 0.13, 0.12),
			FigureLib.Pose.STAND, FigureLib.skin_for(absi(String(w["id"]).hash())))
		node.material_override = FigureLib.figure_material()
		add_child(node)
		_watcher_nodes[w["id"]] = node
		# The cone of his attention, drawn on the ground: stealth you can
		# READ is stealth you can play (docs/13 §4).
		var cone := MeshInstance3D.new()
		var mesh := _cone_mesh(float(w["cone"]), float(w["range"]))
		cone.mesh = mesh
		var cmat := StandardMaterial3D.new()
		cmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		cmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		cmat.albedo_color = Color(1.0, 0.85, 0.5, 0.10)
		# Back faces of a ground-flat cone are never seen; drawing them
		# doubles the blended fill, which software GL charges for.
		cmat.cull_mode = BaseMaterial3D.CULL_BACK
		cone.material_override = cmat
		add_child(cone)
		_cone_nodes[w["id"]] = cone


func _cone_mesh(angle: float, reach: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var steps := 14
	for i in steps:
		var a0 := -angle / 2.0 + angle * float(i) / float(steps)
		var a1 := -angle / 2.0 + angle * float(i + 1) / float(steps)
		for v in [Vector3.ZERO,
				Vector3(sin(a1) * reach, 0.0, cos(a1) * reach),
				Vector3(sin(a0) * reach, 0.0, cos(a0) * reach)]:
			st.set_normal(Vector3.UP)
			st.add_vertex(v + Vector3(0.0, 0.05, 0.0))
	return st.commit()


func _build_hud(title: String) -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_title = Label.new()
	_title.position = Vector2(14, 10)
	_title.text = title
	layer.add_child(_title)
	_hud = Label.new()
	_hud.position = Vector2(14, 36)
	layer.add_child(_hud)
	_log_label = Label.new()
	_log_label.position = Vector2(14, 470)
	_log_label.modulate = Color(1, 1, 1, 0.8)
	layer.add_child(_log_label)


# --- per-frame ---------------------------------------------------------

func _update_avatar() -> void:
	var a := clock.alpha()
	var x := lerpf(sim.av_prev_x, sim.av_x, a)
	var z := lerpf(sim.av_prev_z, sim.av_z, a)
	var crouch := 0.72 if sim.av_stance == WorldSim.Stance.CROUCH else 1.0
	_avatar.position = Vector3(x, 0.85 * crouch, z)
	_avatar.rotation.y = sim.av_heading
	_avatar.scale = Vector3(1.0, crouch, 1.0)


func _update_watchers() -> void:
	var a := clock.alpha()
	for w in sim.watchers:
		var node: Node3D = _watcher_nodes[w["id"]]
		var x := lerpf(float(w["prev_x"]), float(w["x"]), a)
		var z := lerpf(float(w["prev_z"]), float(w["z"]), a)
		node.position = Vector3(x, 0.85, z)
		node.rotation.y = float(w["heading"])
		var cone: Node3D = _cone_nodes[w["id"]]
		cone.position = Vector3(x, 0.0, z)
		cone.rotation.y = float(w["heading"])
		# The cone warms as he grows sure of you.
		var s: float = float(w["suspicion"])
		var mat := cone.material_override as StandardMaterial3D
		mat.albedo_color = Color(1.0, 0.85 - s * 0.55, 0.5 - s * 0.45,
			0.08 + s * 0.20)


func _update_camera(delta: float) -> void:
	# Over-the-shoulder, high enough to read the street (docs/12 §5.3:
	# third person, because the picture is the game).
	var target := _avatar.position
	var back := Vector3(sin(_cam_yaw), 0.0, cos(_cam_yaw)) * 9.5
	var want := target - back + Vector3(0.0, 6.2, 0.0)
	_cam.position = _cam.position.lerp(want, clampf(delta * 4.0, 0.0, 1.0))
	_cam.look_at(target + Vector3(0.0, 1.1, 0.0), Vector3.UP)


func _update_hud() -> void:
	var heat := sim.heat()
	var eye := "·····"
	if heat >= WorldSim.ALERT_AT:
		eye = "SEEN — RUN"
	elif heat >= WorldSim.CHALLENGE_AT:
		eye = "CHALLENGED"
	elif heat > 0.15:
		eye = "WATCHED"
	var stance_name := ["walking", "running", "crouched"][sim.av_stance]
	var obj := sim.current_objective()
	var lines := PackedStringArray()
	lines.append("%s   |   %s   |   cover %d%%" % [
		eye, stance_name, int(sim.crowd_cover() * 100.0)])
	if not obj.is_empty():
		var dx := sim.av_x - float(obj["x"])
		var dz := sim.av_z - float(obj["z"])
		lines.append("%d yards to go" % int(sqrt(dx * dx + dz * dz)))
	if sim.over:
		lines.append("")
		lines.append("SEIZED — taken up in the street." if sim.outcome == "seized"
			else "AWAY — the word is across the water.")
		lines.append("[ENTER] again   [ESC] to the field")
	else:
		lines.append("[W A S D] walk   [SHIFT] run   [CTRL] crouch   [Q/E] camera")
	_hud.text = "\n".join(lines)
	_log_label.text = "\n".join(sim.log_lines.slice(maxi(0, sim.log_lines.size() - 6)))
