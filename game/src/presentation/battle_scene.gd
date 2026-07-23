extends Node3D
## M1 grey-box presentation shell (docs/07: presentation reads sim state,
## never mutates it — every input becomes a CommandBus command).
## Everything is built from code so the scene file stays trivially
## diffable; art replaces these boxes in M2, the sim never notices.
##
## CONTROLS
##   1 advance · 2 halt · 3 withdraw
##   SPACE (hold) Present … (release) FIRE
##   C fix bayonets & charge · R rally · ENTER restart

const PLAYER_ID := "continentals"
const FILES := 20          # men per rank in the grey-box line
const FILE_SPACING := 0.75
const RANK_SPACING := 0.9

var sim: BattleSim
var clock := SimClock.new()

var _mm_by_id: Dictionary = {}        # company id -> MultiMeshInstance3D
var _mat_by_id: Dictionary = {}       # company id -> StandardMaterial3D
var _base_color_by_id: Dictionary = {}
var _last_effectives: Dictionary = {}
var _fallen_parent: Node3D
var _smoke_boxes: Array[MeshInstance3D] = []
var _camera: Camera3D
var _hud: Label
var _log_label: Label


func _ready() -> void:
	sim = BattleSim.create_demo(17750419, false)
	_build_environment()
	_build_field()
	_build_company_visual("continentals", Color(0.16, 0.24, 0.52))
	_build_company_visual("crown", Color(0.58, 0.13, 0.13))
	_build_smoke()
	_build_hud()
	_fallen_parent = Node3D.new()
	add_child(_fallen_parent)
	for c in sim.companies:
		_last_effectives[c.id] = c.effectives()


func _process(delta: float) -> void:
	clock.advance(delta, func(_t: int) -> void: sim.step())
	for c in sim.companies:
		_update_company_visual(c)
		_spawn_fallen(c)
	_update_smoke()
	_update_camera()
	_update_hud()


func _unhandled_input(event: InputEvent) -> void:
	if event is not InputEventKey:
		return
	var key := event as InputEventKey
	if key.echo:
		return
	if key.pressed:
		match key.keycode:
			KEY_1: _order("advance")
			KEY_2: _order("halt")
			KEY_3: _order("withdraw")
			KEY_SPACE: _order("present")
			KEY_C: _order("charge")
			KEY_R: _order("rally")
			KEY_ENTER: get_tree().reload_current_scene()
	else:
		if key.keycode == KEY_SPACE:
			_order("fire")


func _order(verb: String) -> void:
	sim.bus.submit(sim.tick + 1, PLAYER_ID, verb)


# --- construction -----------------------------------------------------

func _build_environment() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.62, 0.66, 0.70)  # overcast — doc 06 light rules
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.82, 0.83, 0.86)
	env.ambient_light_energy = 0.55
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48.0, 35.0, 0.0)
	sun.light_energy = 1.1
	add_child(sun)


func _build_field() -> void:
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(90.0, 400.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.24, 0.28, 0.19)
	plane.material = mat
	ground.mesh = plane
	add_child(ground)


func _build_company_visual(id: String, color: Color) -> void:
	var box := BoxMesh.new()
	box.size = Vector3(0.45, 1.7, 0.45)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	box.material = mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = box
	mm.instance_count = sim.get_company(id).brigade.soldiers.size()
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	add_child(mmi)
	_mm_by_id[id] = mmi
	_mat_by_id[id] = mat
	_base_color_by_id[id] = color


func _build_smoke() -> void:
	for i in SmokeGrid.CELL_COUNT:
		var mi := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(70.0, 4.5, SmokeGrid.CELL_SIZE)
		var mat := StandardMaterial3D.new()
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = Color(0.78, 0.78, 0.74, 0.0)
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		box.material = mat
		mi.mesh = box
		mi.position = Vector3(0.0, 2.4, SmokeGrid.MIN_Y + (float(i) + 0.5) * SmokeGrid.CELL_SIZE)
		add_child(mi)
		_smoke_boxes.append(mi)


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_hud = Label.new()
	_hud.position = Vector2(14.0, 10.0)
	layer.add_child(_hud)
	_log_label = Label.new()
	_log_label.position = Vector2(14.0, 460.0)
	_log_label.modulate = Color(1, 1, 1, 0.75)
	layer.add_child(_log_label)
	_camera = Camera3D.new()
	add_child(_camera)
	_camera.position = Vector3(18.0, 24.0, -150.0)


# --- per-frame updates ------------------------------------------------

func _render_z(c: BattleCompany) -> float:
	return lerpf(c.prev_pos_y, c.pos_y, clock.alpha())


func _update_company_visual(c: BattleCompany) -> void:
	var mmi: MultiMeshInstance3D = _mm_by_id[c.id]
	var mm := mmi.multimesh
	var z := _render_z(c)
	var alive := c.effectives()
	var hidden := Transform3D(Basis.IDENTITY.scaled(Vector3(0.001, 0.001, 0.001)), Vector3(0, -10, 0))
	for i in mm.instance_count:
		if i < alive and c.is_active():
			var file := i % FILES
			var rank := i / FILES
			var x := (float(file) - float(FILES) / 2.0 + 0.5) * FILE_SPACING
			var zz := z - float(rank) * RANK_SPACING * c.facing()
			mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, Vector3(x, 0.85, zz)))
		else:
			mm.set_instance_transform(i, hidden)
	var mat: StandardMaterial3D = _mat_by_id[c.id]
	var base: Color = _base_color_by_id[c.id]
	var faded := c.state == BattleCompany.State.BROKEN or not c.is_active()
	mat.albedo_color = base.lerp(Color(0.55, 0.55, 0.55), 0.7 if faded else 0.0)


func _spawn_fallen(c: BattleCompany) -> void:
	var prev: int = _last_effectives[c.id]
	var now := c.effectives()
	if now >= prev:
		return
	var z := _render_z(c)
	for k in (prev - now):
		var idx := prev - 1 - k
		var mi := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.45, 0.14, 1.6)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.28, 0.16, 0.14)
		box.material = mat
		mi.mesh = box
		var x := (float(idx % FILES) - float(FILES) / 2.0 + 0.5) * FILE_SPACING
		mi.position = Vector3(x, 0.08, z - float(idx / FILES) * RANK_SPACING * c.facing())
		_fallen_parent.add_child(mi)
	_last_effectives[c.id] = now


func _update_smoke() -> void:
	for i in _smoke_boxes.size():
		var mat := (_smoke_boxes[i].mesh as BoxMesh).material as StandardMaterial3D
		mat.albedo_color.a = clampf(sim.smoke.cells[i], 0.0, 1.0) * 0.5


func _update_camera() -> void:
	var pc := sim.get_company(PLAYER_ID)
	if pc == null:
		return
	var z := _render_z(pc)
	_camera.position = _camera.position.lerp(Vector3(18.0, 24.0, z - 28.0), 0.05)
	_camera.look_at(Vector3(0.0, 1.0, z + 32.0), Vector3.UP)


func _update_hud() -> void:
	var pc := sim.get_company(PLAYER_ID)
	var foe := sim.nearest_enemy(pc) if pc != null else null
	var lines: Array[String] = []
	lines.append("TWILIGHT'S GLEAMING — M1 volley prototype")
	lines.append("[1] advance  [2] halt  [3] withdraw   [SPACE hold] present -> [release] FIRE   [C] charge  [R] rally  [ENTER] restart")
	lines.append("")
	if pc != null:
		var reload_txt := "loaded" if pc.loaded else "reloading %.0fs" % pc.reload_left
		var hold_txt := "  hold %.1fs (bonus %.0f%%)" % [pc.present_hold, pc.hold_bonus() * 100.0] \
			if pc.state == BattleCompany.State.PRESENTING else ""
		lines.append("%s — %d effectives  cohesion %.0f%%  %s  %s%s" % [
			pc.brigade.display_name, pc.effectives(), pc.cohesion() * 100.0,
			pc.state_name(), reload_txt, hold_txt])
	if pc != null and foe != null:
		lines.append("%s — %d effectives  cohesion %.0f%%  %s  range %d yds  smoke %.0f%%" % [
			foe.brigade.display_name, foe.effectives(), foe.cohesion() * 100.0,
			foe.state_name(), int(absf(foe.pos_y - pc.pos_y)),
			sim.smoke.sample_between(pc.pos_y, foe.pos_y) * 100.0])
	if sim.over:
		lines.append("")
		match sim.winner_side:
			0: lines.append(">>> The field is yours. <<<")
			1: lines.append(">>> Your line has been driven from the field. <<<")
			_: lines.append(">>> Nightfall — the action ends in attrition. <<<")
	_hud.text = "\n".join(lines)
	var tail := sim.battle_log.slice(maxi(0, sim.battle_log.size() - 8))
	_log_label.text = "\n".join(tail)
