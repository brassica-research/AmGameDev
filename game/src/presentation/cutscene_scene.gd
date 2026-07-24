extends Node3D
## The cutscene theater (docs/05 "Production format", M2 deliverable):
## a data-driven grey-box stage. The scene JSON's "stage" section builds
## props, figure groups, and weather; the CutscenePlayer streams the
## timeline; this scene answers camera, actor, and caption cues. Writers
## author scenes without touching engine code — final art replaces the
## boxes at look-dev and the JSON never notices.
##
## Args after `--`:
##   --cutscene=<id>     which data/cutscenes/<id>.json to play
##   --quit-after=N      film mode: quit N seconds in (or at scene end)
## Manual play: ENTER or ESC skips; the scene returns to the campaign.

const CUTSCENE_DIR := "res://data/cutscenes"
const SNOW_COUNT := 220
const FigureLib := preload("res://src/presentation/figure_lib.gd")
const ColonialLib := preload("res://src/presentation/colonial_lib.gd")

var player: CutscenePlayer
var _data: Dictionary = {}
var _camera: Camera3D
var _cam_drift := Vector3.ZERO
var _cam_look := Vector3.ZERO
var _caption: Label
var _attribution: Label
var _codex_label: Label
var _caption_age := 0.0
var _codex_age := 99.0
var _groups: Dictionary = {}   # who -> state dict
var _fallen_parent: Node3D
var _fx: Array[Dictionary] = []
var _snow: MultiMeshInstance3D
var _env_light: DirectionalLight3D
var _anim_time := 0.0
var _quit_after := 0.0
var _elapsed := 0.0
var _done := false


func _ready() -> void:
	var args := _parse_user_args()
	_quit_after = float(String(args.get("quit-after", "0")))
	var id := String(args.get("cutscene", "king_street"))
	var file := FileAccess.open("%s/%s.json" % [CUTSCENE_DIR, id], FileAccess.READ)
	if file == null:
		push_error("Cutscene not found: %s" % id)
		return
	_data = JSON.parse_string(file.get_as_text())
	_build_environment()
	_build_stage(_data.get("stage", {}))
	_build_hud()
	_fallen_parent = Node3D.new()
	add_child(_fallen_parent)
	player = CutscenePlayer.new()
	add_child(player)
	player.caption_shown.connect(_on_caption)
	player.codex_linked.connect(_on_codex)
	player.camera_cue.connect(_on_camera)
	player.actor_cue.connect(_on_actor)
	player.finished.connect(_on_finished)
	player.play_file("%s/%s.json" % [CUTSCENE_DIR, id])


func _parse_user_args() -> Dictionary:
	var out := {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--") and a.contains("="):
			var kv := a.substr(2).split("=", true, 1)
			out[kv[0]] = kv[1]
		elif a.begins_with("--"):
			out[a.substr(2)] = "true"
	return out


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and (event as InputEventKey).pressed:
		var kc := (event as InputEventKey).keycode
		if kc == KEY_ENTER or kc == KEY_ESCAPE:
			_leave()


func _process(delta: float) -> void:
	_anim_time += delta
	_elapsed += delta
	_camera.position += _cam_drift * delta
	_camera.look_at(_cam_look, Vector3.UP)
	_update_groups(delta)
	_update_snow()
	_update_fx(delta)
	_update_captions(delta)
	if _quit_after > 0.0 and (_elapsed >= _quit_after or (_done and _elapsed > 3.0)):
		get_tree().quit()


# --- construction ------------------------------------------------------

func _build_environment() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.07, 0.09, 0.14)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.48, 0.53, 0.70)
	# Bright enough to read the stage; moonlight-on-snow does the rest.
	# (Playtest note: the first capture was near-black on real displays.)
	env.ambient_light_energy = 0.75
	we.environment = env
	add_child(we)
	_env_light = DirectionalLight3D.new()
	_env_light.rotation_degrees = Vector3(-40.0, -30.0, 0.0)
	_env_light.light_energy = 0.8  # first-quarter moon over snow (docs/05)
	_env_light.light_color = Color(0.7, 0.78, 0.98)
	add_child(_env_light)
	ColonialLib.make_moon(self, _env_light)
	_camera = Camera3D.new()
	add_child(_camera)
	_camera.position = Vector3(-16, 7, -18)
	_cam_look = Vector3(4, 1.5, 6)


func _build_stage(stage: Dictionary) -> void:
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(120.0, 120.0)
	plane.material = ColonialLib.ground_material("snow")
	ground.mesh = plane
	add_child(ground)
	for prop in stage.get("props", []):
		var size: Array = prop.get("size", [4, 4, 4])
		var col: Array = prop.get("color", [0.2, 0.2, 0.2])
		var pos: Array = prop.get("pos", [0, 0, 0])
		ColonialLib.make_building(self, String(prop.get("name", "house")),
			Vector3(pos[0], 0.0, pos[2]),
			Vector3(size[0], size[1], size[2]),
			Color(col[0], col[1], col[2]))
	for g in stage.get("groups", []):
		_make_group(g)
	if bool(stage.get("snow", false)):
		_build_snow()


func _make_group(g: Dictionary) -> void:
	var who := String(g.get("who", "group"))
	var color: Array = g.get("color", [0.3, 0.3, 0.3])
	var coat := Color(color[0], color[1], color[2])
	var mesh: ArrayMesh
	match String(g.get("kind", "civilian")):
		"soldier":
			mesh = FigureLib.build_soldier(coat)
		"militia":
			mesh = FigureLib.build_militiaman(coat)
		_:
			mesh = FigureLib.build_civilian(coat)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = 96  # capacity; visible count animates
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = FigureLib.figure_material()
	add_child(mmi)
	var pos: Array = g.get("pos", [0, 0])
	_groups[who] = {
		"mmi": mmi,
		"coat": coat,
		"pos": Vector2(pos[0], pos[1]),
		"move_from": Vector2(pos[0], pos[1]),
		"move_t": 1.0, "move_dur": 1.0,
		"spread": float(g.get("spread", 1.0)),
		"count": float(g.get("count", 0)),
		"count_from": float(g.get("count", 0)),
		"count_target": float(g.get("count", 0)),
		"count_t": 1.0, "count_dur": 1.0,
	}


func _build_snow() -> void:
	var box := BoxMesh.new()
	box.size = Vector3(0.05, 0.05, 0.05)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.85, 0.87, 0.95)
	box.material = mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = box
	mm.instance_count = SNOW_COUNT
	_snow = MultiMeshInstance3D.new()
	_snow.multimesh = mm
	add_child(_snow)


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_caption = Label.new()
	_caption.position = Vector2(80, 520)
	_caption.size = Vector2(990, 80)
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layer.add_child(_caption)
	_attribution = Label.new()
	_attribution.position = Vector2(80, 602)
	_attribution.size = Vector2(990, 30)
	_attribution.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_attribution.modulate = Color(1, 1, 1, 0.7)
	layer.add_child(_attribution)
	_codex_label = Label.new()
	_codex_label.position = Vector2(14, 10)
	layer.add_child(_codex_label)


# --- cue handlers ------------------------------------------------------

func _on_caption(text: String, attribution: String) -> void:
	_caption.text = text
	_attribution.text = attribution
	_caption_age = 0.0


func _on_codex(entry_id: String) -> void:
	_codex_label.text = "Field Journal — new entry: %s" % entry_id.trim_prefix("codex_").replace("_", " ")
	_codex_age = 0.0


func _on_camera(event: Dictionary) -> void:
	var pos: Array = event.get("pos", [0, 6, -12])
	var look: Array = event.get("look", [0, 1, 0])
	_camera.position = Vector3(pos[0], pos[1], pos[2])
	_cam_look = Vector3(look[0], look[1], look[2])
	var drift: Array = event.get("drift", [0, 0, 0])
	_cam_drift = Vector3(drift[0], drift[1], drift[2])


func _on_actor(event: Dictionary) -> void:
	var who := String(event.get("who", ""))
	match String(event.get("cue", "")):
		"count":
			if _groups.has(who):
				var g: Dictionary = _groups[who]
				g["count_from"] = g["count"]
				g["count_target"] = float(event.get("count", 0))
				g["count_t"] = 0.0
				g["count_dur"] = maxf(0.1, float(event.get("duration", 1.0)))
		"move":
			if _groups.has(who):
				var g: Dictionary = _groups[who]
				var to: Array = event.get("to", [0, 0])
				g["move_from"] = g["pos"]
				g["move_target"] = Vector2(to[0], to[1])
				g["move_t"] = 0.0
				g["move_dur"] = maxf(0.1, float(event.get("duration", 1.0)))
		"fall":
			var at: Array = event.get("at", [0, 0])
			var coat: Color = _groups[who]["coat"] if _groups.has(who) \
				else Color(0.30, 0.28, 0.26)
			for k in int(event.get("bodies", 1)):
				var mi := MeshInstance3D.new()
				mi.mesh = FigureLib.build_fallen(coat)
				mi.material_override = FigureLib.figure_material()
				var h := (k * 2654435761) % 100
				mi.position = Vector3(at[0] + float(h % 10) * 0.3 - 1.5, 0.02,
					at[1] + float(h / 10) * 0.25 - 1.2)
				mi.rotation.y = float(h) * 0.06
				_fallen_parent.add_child(mi)
		"flash":
			var at2: Array = event.get("at", [0, 0])
			for k in int(event.get("shots", 1)):
				_spawn_flash(Vector3(at2[0] + float(k) * 0.7 - 1.4, 1.35, at2[1]))
		"dim":
			_env_light.light_energy = float(event.get("energy", 0.4))


func _on_finished(_id: String) -> void:
	_done = true
	if _quit_after <= 0.0:
		_leave()


func _leave() -> void:
	# Cutscenes flow back into the campaign (docs/05: no visual seam).
	get_tree().change_scene_to_file("res://scenes/battle.tscn")


# --- per-frame ---------------------------------------------------------

func _spawn_flash(pos: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.6, 0.3, 0.15)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.85, 0.45)
	box.material = mat
	mi.mesh = box
	mi.position = pos
	add_child(mi)
	_fx.append({"n": mi, "age": 0.0, "life": 0.14})
	var lamp := OmniLight3D.new()
	lamp.light_color = Color(1.0, 0.75, 0.4)
	lamp.light_energy = 6.0
	lamp.omni_range = 16.0
	lamp.position = pos + Vector3(0, 0.5, 0)
	add_child(lamp)
	_fx.append({"n": lamp, "age": 0.0, "life": 0.16})


func _update_fx(delta: float) -> void:
	var keep: Array[Dictionary] = []
	for fx in _fx:
		fx["age"] = float(fx["age"]) + delta
		if float(fx["age"]) >= float(fx["life"]):
			(fx["n"] as Node).queue_free()
		else:
			keep.append(fx)
	_fx = keep


func _update_groups(delta: float) -> void:
	for who in _groups:
		var g: Dictionary = _groups[who]
		if float(g["count_t"]) < 1.0:
			g["count_t"] = minf(1.0, float(g["count_t"]) + delta / float(g["count_dur"]))
			g["count"] = lerpf(float(g["count_from"]), float(g["count_target"]), float(g["count_t"]))
		if float(g["move_t"]) < 1.0 and g.has("move_target"):
			g["move_t"] = minf(1.0, float(g["move_t"]) + delta / float(g["move_dur"]))
			g["pos"] = (g["move_from"] as Vector2).lerp(g["move_target"] as Vector2, float(g["move_t"]))
		var mm: MultiMesh = (g["mmi"] as MultiMeshInstance3D).multimesh
		var visible_count := int(g["count"])
		var base: Vector2 = g["pos"]
		var spread: float = g["spread"]
		var hidden := Transform3D(Basis.IDENTITY.scaled(Vector3(0.001, 0.001, 0.001)), Vector3(0, -10, 0))
		for i in mm.instance_count:
			if i < visible_count:
				var h1 := float((i * 2654435761) % 1000) / 1000.0
				var h2 := float((i * 1103515245 + 12345) % 1000) / 1000.0
				var h3 := float((i * 805306457 + 2749) % 1000) / 1000.0
				var x := base.x + (h1 - 0.5) * 2.0 * spread
				var z := base.y + (h2 - 0.5) * 2.0 * spread
				x += sin(_anim_time * (0.4 + h1) + h1 * 9.0) * 0.06
				z += cos(_anim_time * (0.3 + h2) + h2 * 7.0) * 0.06
				# No two townsmen are the same height or girth.
				var sy := 0.93 + h3 * 0.13
				var sw := 0.95 + h1 * 0.10
				mm.set_instance_transform(i, Transform3D(
					Basis.IDENTITY.rotated(Vector3.UP, (h2 - 0.5) * 1.2).scaled(
						Vector3(sw, sy, sw)),
					Vector3(x, 0.85 * sy, z)))
			else:
				mm.set_instance_transform(i, hidden)


func _update_snow() -> void:
	if _snow == null:
		return
	var mm := _snow.multimesh
	for i in mm.instance_count:
		var h1 := float((i * 2654435761) % 1000) / 1000.0
		var h2 := float((i * 1103515245 + 12345) % 1000) / 1000.0
		var fall := 0.5 + h1 * 0.8
		var y := 12.0 - fmod(_anim_time * fall + h2 * 12.0, 12.0)
		var x := (h1 - 0.5) * 60.0 + sin(_anim_time * 0.5 + h2 * 6.0) * 1.5
		var z := (h2 - 0.5) * 60.0
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, Vector3(x, y, z)))


func _update_captions(delta: float) -> void:
	_caption_age += delta
	_codex_age += delta
	var a := clampf(_caption_age / 0.6, 0.0, 1.0)   # fade in
	if _caption_age > 7.0:
		a = clampf(1.0 - (_caption_age - 7.0) / 1.0, 0.0, 1.0)  # fade out
	_caption.modulate = Color(1, 1, 1, a)
	_attribution.modulate = Color(1, 1, 1, a * 0.7)
	_codex_label.modulate = Color(1, 1, 1, clampf(1.0 - (_codex_age - 5.0) / 1.0, 0.0, 1.0))
