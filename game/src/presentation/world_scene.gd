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
##   TAB (hold)         survey — take the measure of the street
##   ENTER              restart · ESC back to the battle
## (The keys are listed here rather than painted permanently on the
## courier's card — the paper is for what is happening, not for a
## reference sheet.)
##
## Args after `--`:
##   --world=<id>       which data/world/<id>.json to walk
##   --auto             the scripted walk (films, tests)
##   --lowfx            painted light pools instead of omni lights
##                      (software GL / low-end rigs)
##   --time-scale=X     run the night faster (films)
##   --quit-after=N     film-mode safety quit

const FigureLib := preload("res://src/presentation/figure_lib.gd")
const ColonialLib := preload("res://src/presentation/colonial_lib.gd")
const LookDev := preload("res://src/presentation/look_dev.gd")
const UIKit := preload("res://src/presentation/ui_kit.gd")
const TerrainLib := preload("res://src/presentation/terrain_lib.gd")
const WORLD_DIR := "res://data/world"

# The camera rides close and low, over the shoulder — the open-world
# convention, and the one that makes a street feel like a place rather
# than a diagram (playtest directive: closer to that aesthetic).
const BASE_FOV := 58.0
const RUN_FOV := 68.0
const CAM_BACK := 5.6
const CAM_HEIGHT := 2.5
const CAM_SIDE := 1.15        # over the right shoulder, not down the spine
const TOWN_RELIEF := 0.28     # graded streets still fall away toward the water

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
## "Take the measure of the street" — hold TAB: the courier stops and
## reads the ground, and the watchers' attention becomes plainly legible.
## Presentation only; the sim neither knows nor cares (docs/13 §4).
var _survey := 0.0
var _crowd_buckets: Array[Dictionary] = []
var _alarm_seal: PanelContainer
var _avatar_poses: Array[ArrayMesh] = []
var _avatar_pose := 0


func _ready() -> void:
	var args := _parse_user_args()
	_auto = args.has("auto")
	_lowfx = args.has("lowfx")
	# Films run the night at speed: the courier's walk is 91 seconds of
	# sim time, and software-GL capture pays for every frame of it.
	Engine.time_scale = clampf(float(String(args.get("time-scale", "1"))), 0.5, 3.0)
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
	# Survey rises while held, falls off when released.
	var want_survey := 1.0 if (not _auto and Input.is_key_pressed(KEY_TAB)) else 0.0
	_survey = move_toward(_survey, want_survey, delta * 3.0)
	clock.advance(delta, func(_t: int) -> void: sim.step())
	_update_avatar()
	_update_watchers()
	_update_crowds()
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
	# One house look for the whole game (docs/06) — see look_dev.gd.
	var we := WorldEnvironment.new()
	we.environment = LookDev.environment("town_night")
	add_child(we)
	var moon := LookDev.key_light("town_night", "clear", not _lowfx)
	add_child(moon)
	add_child(LookDev.fill_light("town_night"))
	add_child(LookDev.bounce_light("town_night"))
	add_child(LookDev.rim_light("town_night"))
	ColonialLib.make_moon(self, moon)
	_cam = Camera3D.new()
	_cam.fov = BASE_FOV
	add_child(_cam)


func _build_town(data: Dictionary) -> void:
	# A town is graded flatter than a pasture, but not a billiard table:
	# Boston is built on hills and the streets remember it.
	TerrainLib.build_ground(self, Vector2(240.0, 240.0), "snow", TOWN_RELIEF, 5.0)
	for b in sim.blocks:
		# Houses sit INTO the grade, foundations buried a little, so no
		# building floats above the street on a slope.
		ColonialLib.make_building(self, String(b["name"]),
			Vector3(float(b["x"]),
				TerrainLib.height_at(float(b["x"]), float(b["z"]), TOWN_RELIEF) - 0.35,
				float(b["z"])),
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
	# The crowds themselves — cover you can walk into, and the thing that
	# makes a town read as inhabited rather than staged. Each knot gets
	# every pose in the set so its people stand, walk, and turn about
	# instead of facing one way like fenceposts.
	for c in sim.crowds:
		var count := int(c["count"])
		var poses := FigureLib.build_pose_set(Color(0.30, 0.29, 0.34), "civilian",
			FigureLib.skin_for(int(float(c["x"])) + 5), int(absf(float(c["x"]))) % 3)
		var buckets: Array[MultiMeshInstance3D] = []
		for mesh in poses:
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_colors = true
			mm.mesh = mesh
			mm.instance_count = count
			var mmi := MultiMeshInstance3D.new()
			mmi.multimesh = mm
			mmi.material_override = FigureLib.figure_material()
			add_child(mmi)
			buckets.append(mmi)
		_crowd_buckets.append({"node": buckets, "c": c, "count": count})


## Townsfolk drift about their knot: a slow wander, each on his own
## clock, so a crowd looks like people waiting rather than a formation.
func _update_crowds() -> void:
	var hidden := Transform3D(Basis.IDENTITY.scaled(Vector3(0.001, 0.001, 0.001)),
		Vector3(0, -10, 0))
	for knot in _crowd_buckets:
		var buckets: Array = knot["node"]
		var c: Dictionary = knot["c"]
		var count: int = knot["count"]
		var counts := PackedInt32Array()
		counts.resize(buckets.size())
		for i in count:
			var h1 := float((i * 2654435761) % 1000) / 1000.0
			var h2 := float((i * 1103515245 + 12345) % 1000) / 1000.0
			# A slow orbit of his own patch of street, at his own pace.
			var speed := 0.10 + h1 * 0.16
			var ang := h1 * TAU + _anim_time * speed * (1.0 if h2 > 0.5 else -1.0)
			var rr: float = float(c["r"]) * (0.30 + 0.55 * h2)
			var x := float(c["x"]) + cos(ang) * rr
			var z := float(c["z"]) + sin(ang) * rr
			# Walking poses while he drifts, standing while he pauses.
			var pausing := sin(_anim_time * 0.4 + h1 * 6.3) > 0.45
			var pose := FigureLib.Pose.STAND
			if not pausing:
				pose = FigureLib.Pose.MARCH_A if int(_anim_time * 1.6 + h1 * 3.0) % 2 == 0 \
					else FigureLib.Pose.MARCH_B
			var slot := counts[pose]
			counts[pose] = slot + 1
			var facing := ang + PI / 2.0 if not pausing else h2 * TAU
			var sy := 0.93 + h2 * 0.13
			var mm: MultiMesh = (buckets[pose] as MultiMeshInstance3D).multimesh
			mm.set_instance_transform(slot, Transform3D(
				Basis.IDENTITY.rotated(Vector3.UP, facing).scaled(Vector3(1.0, sy, 1.0)),
				Vector3(x, TerrainLib.height_at(x, z, TOWN_RELIEF) + 0.85 * sy, z)))
			var wear := 0.86 + h1 * 0.26
			mm.set_instance_color(slot, Color(wear, wear, wear))
		for b in buckets.size():
			var mmb: MultiMesh = (buckets[b] as MultiMeshInstance3D).multimesh
			for k in range(counts[b], mmb.instance_count):
				mmb.set_instance_transform(k, hidden)


func _build_actors() -> void:
	_avatar = MeshInstance3D.new()
	_avatar_poses = FigureLib.build_pose_set(Color(0.26, 0.24, 0.30), "civilian",
		FigureLib.skin_for(2))
	(_avatar as MeshInstance3D).mesh = _avatar_poses[FigureLib.Pose.STAND]
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


## In the free world the document is a courier's scrap of paper: where
## he is going, and how the street is regarding him.
func _build_hud(title: String) -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var card := UIKit.document(title, 5, 360.0)
	card.position = Vector2(16.0, 14.0)
	layer.add_child(card)
	_title = card.get_meta("title")
	(_title as Label).add_theme_font_size_override("font_size", 15)
	_hud = card.get_meta("body")
	# The seal only appears when the street has taken an interest.
	_alarm_seal = UIKit.seal("")
	_alarm_seal.position = Vector2(16.0, 122.0)
	_alarm_seal.visible = false
	layer.add_child(_alarm_seal)
	var journal := UIKit.document("THE NIGHT'S DOINGS", 17, 520.0)
	journal.position = Vector2(16.0, 540.0)
	layer.add_child(journal)
	_log_label = journal.get_meta("body")
	_log_label.add_theme_font_size_override("font_size", 13)
	_log_label.add_theme_color_override("font_color", UIKit.INK_FADED)


# --- per-frame ---------------------------------------------------------

func _update_avatar() -> void:
	var a := clock.alpha()
	var x := lerpf(sim.av_prev_x, sim.av_x, a)
	var z := lerpf(sim.av_prev_z, sim.av_z, a)
	var crouch := 0.72 if sim.av_stance == WorldSim.Stance.CROUCH else 1.0
	_avatar.position = Vector3(x, TerrainLib.height_at(x, z, TOWN_RELIEF) + 0.85 * crouch, z)
	_avatar.rotation.y = sim.av_heading
	_avatar.scale = Vector3(1.0, crouch, 1.0)
	# He walks rather than glides: pose-swap on his own gait clock, at
	# the cadence his stance implies.
	var moving := absf(sim.intent_x) + absf(sim.intent_z) > 0.02
	var pose := FigureLib.Pose.STAND
	if moving:
		var rate := 2.9 if sim.av_stance == WorldSim.Stance.RUN else \
			(1.3 if sim.av_stance == WorldSim.Stance.CROUCH else 1.9)
		pose = FigureLib.Pose.MARCH_A if int(_anim_time * rate) % 2 == 0 \
			else FigureLib.Pose.MARCH_B
	if pose != _avatar_pose:
		_avatar_pose = pose
		(_avatar as MeshInstance3D).mesh = _avatar_poses[pose]


func _update_watchers() -> void:
	var a := clock.alpha()
	for w in sim.watchers:
		var node: Node3D = _watcher_nodes[w["id"]]
		var x := lerpf(float(w["prev_x"]), float(w["x"]), a)
		var z := lerpf(float(w["prev_z"]), float(w["z"]), a)
		node.position = Vector3(x, TerrainLib.height_at(x, z, TOWN_RELIEF) + 0.85, z)
		node.rotation.y = float(w["heading"])
		var cone: Node3D = _cone_nodes[w["id"]]
		cone.position = Vector3(x, TerrainLib.height_at(x, z, TOWN_RELIEF) + 0.05, z)
		cone.rotation.y = float(w["heading"])
		# The cone warms as he grows sure of you.
		var s: float = float(w["suspicion"])
		var mat := cone.material_override as StandardMaterial3D
		# Surveying the street makes every eye on it plain.
		mat.albedo_color = Color(1.0, 0.85 - s * 0.55, 0.5 - s * 0.45,
			0.08 + s * 0.20 + _survey * 0.22)


## Over-the-shoulder, close and low, with the small dishonesties that
## make a camera feel operated rather than mounted: it leads the walk,
## widens on the run, drops with the crouch, breathes on a slow cycle,
## and pulls in when the street is reading you.
func _update_camera(delta: float) -> void:
	var target := _avatar.position
	var t := clampf(delta * 4.5, 0.0, 1.0)
	var stance_drop := 0.55 if sim.av_stance == WorldSim.Stance.CROUCH else 0.0
	var heat := sim.heat()
	# Attention pulls the lens in — being watched should feel closer.
	var back := CAM_BACK - heat * 0.9 - _survey * 0.8
	var back_v := Vector3(sin(_cam_yaw), 0.0, cos(_cam_yaw))
	var side_v := Vector3(cos(_cam_yaw), 0.0, -sin(_cam_yaw))
	# Lead the walk: the camera looks a little where he is going.
	var lead := Vector3(sim.intent_x, 0.0, sim.intent_z) * 1.4
	var want := target - back_v * back + side_v * CAM_SIDE \
		+ Vector3(0.0, CAM_HEIGHT - stance_drop, 0.0) + lead * 0.35
	# A slow handheld breath, never a shake.
	want += Vector3(sin(_anim_time * 0.6) * 0.055, sin(_anim_time * 0.83) * 0.04, 0.0)
	_cam.position = _cam.position.lerp(want, t)
	var look := target + Vector3(0.0, 1.15 - stance_drop * 0.5, 0.0) + lead
	_cam.look_at(look, Vector3.UP)
	var want_fov := BASE_FOV
	if sim.av_stance == WorldSim.Stance.RUN:
		want_fov = RUN_FOV
	elif _survey > 0.01:
		want_fov = BASE_FOV - 6.0 * _survey    # the world narrows as he reads it
	_cam.fov = lerpf(_cam.fov, want_fov, t)


func _update_hud() -> void:
	var heat := sim.heat()
	var eye := "·····"
	if heat >= WorldSim.ALERT_AT:
		eye = "SEEN — RUN"
	elif heat >= WorldSim.CHALLENGE_AT:
		eye = "CHALLENGED"
	elif heat > 0.15:
		eye = "WATCHED"
	var stance_name: String = ["walking", "running", "crouched"][sim.av_stance]
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
	elif _survey > 0.5:
		lines.append("Reading the street — every eye on it is plain.")
	_hud.text = "\n".join(lines)
	if _alarm_seal != null:
		var seal_text := ""
		if sim.outcome == "seized":
			seal_text = "TAKEN UP"
		elif heat >= WorldSim.ALERT_AT:
			seal_text = "RECOGNIZED — RUN"
		elif heat >= WorldSim.CHALLENGE_AT:
			seal_text = "CHALLENGED"
		_alarm_seal.visible = seal_text != ""
		if _alarm_seal.visible:
			(_alarm_seal.get_meta("body") as Label).text = seal_text
	_log_label.text = "\n".join(sim.log_lines.slice(maxi(0, sim.log_lines.size() - 4)))
