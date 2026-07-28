extends Node3D
## M1 grey-box presentation shell (docs/07: presentation reads sim state,
## never mutates it — every input becomes a CommandBus command).
## Everything is built from code so the scene file stays trivially
## diffable; art replaces these boxes in M2, the sim never notices.
##
## CONTROLS
##   1 advance · 2 halt · 3 withdraw
##   SPACE (hold) Present … (release) FIRE
##   F toggle volley fire <-> fire at will
##   C fix bayonets & charge · R rally
##   V toggle cinematic camera · M memorial book (campaign)
##   H pin/unpin the officer's hand (the key card, which otherwise
##     folds away a few seconds in)
##   ENTER: campaign — march again after the after-action; demos — restart
##
## Manual play defaults to the CAMPAIGN: your persistent muster roll
## fights, bleeds, heals, and is saved (docs/02). Scenario args after `--`:
##   --auto                    player company is AI-driven (auto-battle)
##   --scenario=field          the ephemeral demo battle (no persistence)
##   --scenario=night_assault  bayonets-only night storm (Stony Point pattern)
##   --scenario=lexington      mission 1.5 opening: Parker's stand on the
##                             Green — hold fire, judge the moment, disperse
##                             or take the volley (docs/03)
##   --scenario=battle_road    mission 1.5 third act: the running fight —
##                             hold a wall, empty your musket into the
##                             column, fall back to the next wall
##   --scenario=campaign       with --auto: sandboxed campaign film — the
##                             save file is never touched (demo_mode)
##   --campaign-seed=N         founding seed for the sandboxed campaign
##   --battles=N               auto-campaign: quit after N battles
##   --weather=rain            damp powder: misfires, slow reloads, dark sky
##   --lowfx                   no shadows (software GL / low-end rigs)
##   --time-scale=X            speed the film up (Engine.time_scale)
##   --lanes=2                 two engagement lanes (four companies)
##   --start-range=N           opening distance in yards (field scenario only)
##   --quit-after=N            per-scene safety quit (or ~6 s after verdict)

const PLAYER_ID := "continentals"
const FILES := 20          # men per rank in the grey-box line
const FILE_SPACING := 0.75
const RANK_SPACING := 0.9

const FigureLib := preload("res://src/presentation/figure_lib.gd")
const LookDev := preload("res://src/presentation/look_dev.gd")
const UIKit := preload("res://src/presentation/ui_kit.gd")
const ColonialLib := preload("res://src/presentation/colonial_lib.gd")
const TerrainLib := preload("res://src/presentation/terrain_lib.gd")

# The form-pass wardrobe (docs/04): the King's regulars in red; the
# American line in blue regimentals only once it has drilled into one —
# a militia company fights in its own brown coats and round hats.
const RAIN_COUNT := 900
## How much the land rolls. The field is drumlin country; a town is graded.
const RELIEF := 1.0
const COAT_BRITISH := Color(0.55, 0.12, 0.11)
const COAT_CONTINENTAL := Color(0.17, 0.21, 0.44)
const COAT_MILITIA := Color(0.33, 0.26, 0.18)

# Cinematic shots
const SHOT_AERIAL := 0
const SHOT_TRACK := 1
const SHOT_OVER_BLUE := 2
const SHOT_OVER_RED := 3
const SHOT_WIDE := 4
const SHOT_MELEE := 5
const SHOT_CRANE := 6
const FIREFIGHT_CYCLE := [SHOT_OVER_BLUE, SHOT_WIDE, SHOT_OVER_RED]
const SHOT_MAX_AGE := 8.0

var sim: BattleSim
var clock := SimClock.new()

var _auto := false
var _lanes := 1
var _quit_after := 0.0
var _elapsed := 0.0
var _over_linger := 0.0
var _anim_time := 0.0

var _scenario := "field"
var _campaign := false
var _battles_limit := 0
var _report: Dictionary = {}
var _report_linger := 0.0
var _show_memorial := false
var _cinematic := false
var _zoom := 1.0
var _shot := SHOT_AERIAL
var _shot_age := 0.0
var _shot_max_age := SHOT_MAX_AGE
var _cycle_index := 0
var _focus_lane := 0

var _mm_by_id: Dictionary = {}        # company id -> Array[MultiMeshInstance3D], (skin, pose) buckets
var _last_shot_time: Dictionary = {}  # company id -> {platoon: anim_time of last discharge}
var _mat_by_id: Dictionary = {}       # company id -> StandardMaterial3D
var _coat_by_id: Dictionary = {}      # company id -> coat color (for the fallen)
var _fallen_mesh_by_id: Dictionary = {}  # built once; casualties share it
var _last_effectives: Dictionary = {}
var _prev_shots: Dictionary = {}      # company id -> [shots p0, shots p1]
var _fallen_parent: Node3D
var _fx_parent: Node3D
var _fx: Array[Dictionary] = []
var _smoke_boxes: Array[MeshInstance3D] = []
var _rain: MultiMeshInstance3D
var _lowfx := false
var _camera: Camera3D
var _hud: Label
var _log_label: Label
var _help_card: PanelContainer
var _help_age := 0.0
var _help_pinned := false


func _ready() -> void:
	var args := _parse_user_args()
	_auto = args.has("auto")
	_lowfx = args.has("lowfx")
	_scenario = String(args.get("scenario", "field" if _auto else "campaign"))
	_lanes = clampi(int(String(args.get("lanes", "1"))), 1, 2)
	_quit_after = float(String(args.get("quit-after", "0")))
	_cinematic = _auto
	Engine.time_scale = clampf(float(String(args.get("time-scale", "1"))), 0.5, 3.0)
	if _scenario == "campaign":
		_campaign = true
		_battles_limit = int(String(args.get("battles", "0")))
	# (echo wiring happens after sim creation, below)
		if _auto:
			GameState.demo_mode = true  # the real muster roll is untouchable
			if GameState.roster == null:
				GameState.new_campaign(int(String(args.get("campaign-seed", "17750419"))))
		else:
			GameState.ensure_campaign()
		sim = BattleSim.create_campaign_skirmish(GameState.next_battle_seed(),
			GameState.roster, _auto, 140.0 if _auto else 200.0)
	elif _scenario == "night_assault":
		sim = BattleSim.create_night_assault(17790716, _auto, _lanes)  # July 16, 1779
		_shot_max_age = 5.0  # the dark cuts faster
	elif _scenario == "lexington":
		sim = BattleSim.create_lexington(17750419, _auto)  # April 19, 1775
	elif _scenario == "battle_road":
		sim = BattleSim.create_battle_road(17750419, _auto)  # the same afternoon
	else:
		sim = BattleSim.create_demo(17750419, _auto, _lanes)
		var start_range := float(String(args.get("start-range", "240")))
		if start_range != 240.0:
			var half := start_range / 2.0
			for c in sim.companies:
				var stagger := 3.0 * float(c.lane)
				c.pos_y = (-half - stagger) if c.side == 0 else (half - stagger * 0.5)
				c.prev_pos_y = c.pos_y
	if not _auto:
		sim.echo_orders_for = PLAYER_ID  # orders answer back (playtest #1)
	# Weather is sim truth, not a filter: rain ruins priming and slows
	# reloading, and the sky is only how you SEE that (docs/06).
	var wx := String(args.get("weather", ""))
	if wx != "":
		sim.weather = wx
	_build_environment()
	_build_field()
	for c in sim.companies:
		var color := COAT_CONTINENTAL if c.side == 0 else COAT_BRITISH
		if c.lane == 1:
			color = color.lightened(0.12)
		_build_company_visual(c, color)
		_last_effectives[c.id] = c.effectives()
		_prev_shots[c.id] = [0, 0]
	_build_smoke()
	_build_hud()
	_fallen_parent = Node3D.new()
	add_child(_fallen_parent)
	_fx_parent = Node3D.new()
	add_child(_fx_parent)


func _process(delta: float) -> void:
	clock.advance(delta, func(_t: int) -> void: sim.step())
	_anim_time += delta
	for c in sim.companies:
		_update_company_visual(c)
		_spawn_fallen(c)
		_spawn_fire_effects(c)
	_update_fx(delta)
	_update_smoke()
	_update_rain()
	if _cinematic:
		_update_camera_cinematic(delta)
	else:
		_update_camera_follow()
	if _campaign and sim.over and _report.is_empty():
		_report = GameState.finish_battle(sim)  # the bill is paid exactly once
		if _auto:
			_show_memorial = true  # the film lingers on the book of the dead
	if _campaign and _auto and not _report.is_empty():
		_report_linger += delta
		if _report_linger > 7.0:
			if _battles_limit > 0 and GameState.battles_fought >= _battles_limit:
				get_tree().quit()
			else:
				# Films always open the chest — the mechanic on camera.
				GameState.rest_and_refit(GameState.CAMP_DAYS, true)
				get_tree().reload_current_scene()
	_update_hud()
	_update_help(delta)
	if _quit_after > 0.0:
		_elapsed += delta
		if sim.over:
			_over_linger += delta
		# In an auto-campaign the battles-limit flow owns the quit —
		# the 6 s post-verdict quit would cut the film off before the
		# after-action linger can advance to the next battle.
		var linger_quit := _over_linger > 6.0 and not _campaign
		if _elapsed >= _quit_after or linger_quit:
			get_tree().quit()
	else:
		_elapsed += delta


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


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		match (event as InputEventMouseButton).button_index:
			MOUSE_BUTTON_WHEEL_UP: _zoom = clampf(_zoom - 0.1, 0.55, 1.8)
			MOUSE_BUTTON_WHEEL_DOWN: _zoom = clampf(_zoom + 0.1, 0.55, 1.8)
		return
	if event is not InputEventKey:
		return
	var key := event as InputEventKey
	if key.echo:
		return
	if key.pressed:
		match key.keycode:
			KEY_1, KEY_KP_1: _order("advance")
			KEY_2, KEY_KP_2: _order("halt")
			KEY_3, KEY_KP_3: _order("withdraw")
			KEY_SPACE: _order("present")
			KEY_C: _order("charge")
			KEY_R: _order("rally")
			KEY_F:
				var pc := sim.get_company(PLAYER_ID)
				if pc != null and pc.fire_mode == BattleCompany.FireMode.VOLLEY:
					_order("fire_at_will")
				else:
					_order("volley_fire")
			KEY_V: _cinematic = not _cinematic
			KEY_H:
				_help_pinned = not _help_pinned
				_help_age = 0.0
				if _help_card != null:
					_help_card.visible = true
			KEY_M:
				if _campaign:
					_show_memorial = not _show_memorial
			KEY_ENTER:
				if _campaign:
					# No mid-battle restarts in the campaign: the roll is
					# the roll. To camp only once the bill is paid.
					if not _report.is_empty():
						get_tree().change_scene_to_file("res://scenes/camp.tscn")
				else:
					get_tree().reload_current_scene()
	else:
		if key.keycode == KEY_SPACE:
			_order("fire")


func _order(verb: String) -> void:
	sim.bus.submit(sim.tick + 1, PLAYER_ID, verb)


# --- construction -----------------------------------------------------

## Light is a scene's clock (docs/06). Every scenario names an hour and
## a sky, and the whole field's grade follows from it: Lexington is
## fought at first light, the Battle Road through a long afternoon,
## Stony Point under a quarter moon. Depth fog carries the distance —
## atmospheric perspective is most of what makes a field feel large.
func _build_environment() -> void:
	# One house look for the whole game (docs/06) — see look_dev.gd.
	var hour := LookDev.hour_for_scenario(_scenario, sim.night)
	var we := WorldEnvironment.new()
	we.environment = LookDev.environment(hour, sim.weather)
	add_child(we)
	var sun := LookDev.key_light(hour, sim.weather, not _lowfx)
	add_child(sun)
	add_child(LookDev.fill_light(hour))
	if sim.night:
		ColonialLib.make_moon(self, sun)
	_camera = Camera3D.new()
	add_child(_camera)
	_camera.position = Vector3(18.0, 24.0, -150.0)
	if sim.weather == "rain":
		_build_rain()


## Rain as falling streaks — one MultiMesh, scrolled in a column that
## follows the camera so a 400-yard field doesn't need 400 yards of drops.
func _build_rain() -> void:
	var streak := BoxMesh.new()
	streak.size = Vector3(0.02, 0.85, 0.02)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.78, 0.82, 0.88, 0.35)
	streak.material = mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = streak
	mm.instance_count = RAIN_COUNT
	_rain = MultiMeshInstance3D.new()
	_rain.multimesh = mm
	add_child(_rain)


func _update_rain() -> void:
	if _rain == null:
		return
	var mm := _rain.multimesh
	var origin := _camera.position
	var tilt := Basis(Vector3.RIGHT, 0.22)   # wind-driven, never vertical
	for i in mm.instance_count:
		var h1 := float((i * 2654435761) % 1000) / 1000.0
		var h2 := float((i * 1103515245 + 12345) % 1000) / 1000.0
		var fall := 26.0 + h1 * 12.0
		var y := 34.0 - fmod(_anim_time * fall + h2 * 34.0, 34.0)
		mm.set_instance_transform(i, Transform3D(tilt, Vector3(
			origin.x + (h1 - 0.5) * 90.0,
			y,
			origin.z + (h2 - 0.5) * 90.0 + 30.0)))


func _build_field() -> void:
	# Ground with relief and cover, not a plane with one texture: men,
	# walls and trees all ask terrain_lib where the earth is.
	TerrainLib.build_ground(self, Vector2(160.0, 420.0),
		"night_field" if sim.night else "field", RELIEF, 3.5)
	TerrainLib.scatter(self, Vector2(150.0, 400.0), 90, RELIEF, 3)
	# Field dressing, presentation-only: bare trees beyond the flanks and
	# a split-rail fence line either side of the fighting ground.
	for k in 14:
		var h := (k * 2654435761) % 1000
		var tx := (32.0 + float(h % 80) / 10.0) * (1.0 if k % 2 == 0 else -1.0)
		var tz := -160.0 + float(k) * 23.0 + float(h % 130) / 10.0
		ColonialLib.make_bare_tree(self,
			Vector3(tx, TerrainLib.height_at(tx, tz, RELIEF), tz), h + k)
	ColonialLib.make_rail_fence(self, 29.0, -80.0, 80.0)
	ColonialLib.make_rail_fence(self, -29.0, -80.0, 80.0)
	# Cover bands are sim truth — draw exactly what the sim scores, so a
	# player can read protection off the field instead of a HUD number.
	for b in sim.terrain.bands:
		var z: float = (float(b["y_min"]) + float(b["y_max"])) / 2.0
		if String(b["kind"]) == "fence":
			ColonialLib.make_rail_fence(self, 0.0, -26.0, 26.0)
			var f := get_child(get_child_count() - 1) as Node3D
			f.rotation.y = PI / 2.0
			f.position.z = z
		else:
			ColonialLib.make_stone_wall(self, z, -26.0, 26.0, int(z) * 31 + 7)


func _lane_x(lane: int) -> float:
	if _lanes == 1:
		return 0.0
	return -13.0 if lane == 0 else 13.0


## A company is drawn as SKIN_BUCKETS x POSE_COUNT MultiMeshes. A
## MultiMesh can't skin a skeleton, so motion comes from sorting each
## man into the bucket his sim state and his own gait phase call for —
## marching legs, muskets coming off the shoulder, ramrods working.
## Colors (coat and skin alike) are baked as vertex colors, so each
## bucket is one draw call and the material stays white for fades.
const SKIN_BUCKETS := 3

func _build_company_visual(c: BattleCompany, color: Color) -> void:
	var militia := c.side == 0 and c.drill() == 0
	var coat := COAT_MILITIA.lerp(color, 0.15) if militia else color
	var kind := "militia" if militia else "soldier"
	var mat := FigureLib.figure_material()
	var buckets: Array[MultiMeshInstance3D] = []
	for s in SKIN_BUCKETS:
		var skin: Color = FigureLib.skin_for(s * 7 + 1, absi(c.id.hash()))
		for mesh in FigureLib.build_pose_set(coat, kind, skin, s):
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_colors = true   # per-man cloth wear, on top of baked color
			mm.mesh = mesh
			mm.instance_count = c.brigade.soldiers.size()
			var mmi := MultiMeshInstance3D.new()
			mmi.multimesh = mm
			mmi.material_override = mat
			add_child(mmi)
			buckets.append(mmi)
	_mm_by_id[c.id] = buckets
	_mat_by_id[c.id] = mat
	_coat_by_id[c.id] = COAT_MILITIA if militia else color
	_fallen_mesh_by_id[c.id] = FigureLib.build_fallen(_coat_by_id[c.id],
		FigureLib.skin_for(3, absi(c.id.hash())))


func _build_smoke() -> void:
	for i in SmokeGrid.CELL_COUNT:
		var mi := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(64.0, 3.0, SmokeGrid.CELL_SIZE)
		var mat := StandardMaterial3D.new()
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = Color(0.80, 0.79, 0.75, 0.0)
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		box.material = mat
		mi.mesh = box
		mi.position = Vector3(0.0, 1.7, SmokeGrid.MIN_Y + (float(i) + 0.5) * SmokeGrid.CELL_SIZE)
		add_child(mi)
		_smoke_boxes.append(mi)


## The interface is a document (docs/04): an officer's orderly book at
## the top of the field, the day's occurrences written up beneath it.
func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var book := UIKit.document("ORDERLY BOOK", 3, 430.0)
	book.position = Vector2(16.0, 14.0)
	layer.add_child(book)
	_hud = book.get_meta("body")
	var occurrences := UIKit.document("OCCURRENCES OF THE DAY", 11, 520.0)
	occurrences.position = Vector2(16.0, 508.0)
	layer.add_child(occurrences)
	_log_label = occurrences.get_meta("body")
	_log_label.add_theme_font_size_override("font_size", 13)
	_log_label.add_theme_color_override("font_color", UIKit.INK_FADED)
	# The keys live on their own card and fade out of the way — a
	# permanent keybind list is a debug overlay wearing a costume.
	_help_card = UIKit.document("THE OFFICER'S HAND", 23, 430.0)
	_help_card.position = Vector2(16.0, 132.0)
	(_help_card.get_meta("body") as Label).text = \
		"1 advance · 2 halt · 3 withdraw\n" \
		+ "SPACE hold to present, release to FIRE\n" \
		+ "F volley or fire at will · C charge · R rally\n" \
		+ "V camera · wheel zoom · H these notes"
	layer.add_child(_help_card)


# --- per-frame updates ------------------------------------------------

func _render_z(c: BattleCompany) -> float:
	return lerpf(c.prev_pos_y, c.pos_y, clock.alpha())


## Organic formations (playtest #1 follow-up): the parade-ground look
## is dead — looseness is now a SIGNAL. Disorder scales with poor drill
## and draining cohesion; lines sag toward the center under pressure,
## stretch on the march, surge in a charge, swirl in melee, and break
## into individual flight when the company breaks. Presentation-only:
## a pure function of sim state + time, deterministic, no sim impact.
func _company_disorder(c: BattleCompany) -> float:
	var by_drill: float = [1.0, 0.7, 0.5, 0.35][c.drill()]
	var by_nerve := 1.0 + (1.0 - c.cohesion()) * 2.0
	var by_state := 1.0
	match c.state:
		BattleCompany.State.CHARGING: by_state = 2.2
		BattleCompany.State.MELEE: by_state = 3.0
		BattleCompany.State.BROKEN: by_state = 4.5
	return by_drill * by_nerve * by_state


## Which pose man `i` is holding this frame — sim state first, then his
## own gait phase, so a marching company's feet are never in lockstep.
func _pose_for(c: BattleCompany, i: int, h1: float, moving: bool) -> int:
	var step_rate := 2.6 if c.state == BattleCompany.State.BROKEN else 1.7
	var gait := int(_anim_time * step_rate + h1 * 2.0) % 2
	var stride := FigureLib.Pose.MARCH_A if gait == 0 else FigureLib.Pose.MARCH_B
	if c.scrum_active and i < c.man_state.size():
		match c.man_state[i]:
			BattleCompany.ManState.FIGHTING:
				return FigureLib.Pose.CHARGE
			BattleCompany.ManState.FIRE_PAUSE:
				return FigureLib.Pose.FIRE if c.man_fired[i] > 0 else FigureLib.Pose.PRESENT
			_:
				return stride
	match c.state:
		BattleCompany.State.BROKEN, BattleCompany.State.CHARGING:
			return FigureLib.Pose.CHARGE if c.state == BattleCompany.State.CHARGING else stride
		BattleCompany.State.PRESENTING:
			return FigureLib.Pose.PRESENT
	# A man reloads if his own platoon is empty — half the line works its
	# ramrod while the other half stands ready, which is the whole point
	# of platoon fire (docs/02).
	var platoon := 0 if i < c.effectives() / 2 else 1
	if _fired_recently(c, platoon):
		return FigureLib.Pose.FIRE
	if not c.platoon_loaded[platoon]:
		return FigureLib.Pose.RELOAD
	if moving:
		return stride
	return FigureLib.Pose.STAND


## True for ~0.4 s after a platoon discharges — long enough to read.
func _fired_recently(c: BattleCompany, platoon: int) -> bool:
	var t: Dictionary = _last_shot_time.get(c.id, {})
	return _anim_time - float(t.get(platoon, -99.0)) < 0.4


func _update_company_visual(c: BattleCompany) -> void:
	var buckets: Array = _mm_by_id[c.id]
	var counts := PackedInt32Array()
	counts.resize(buckets.size())
	var capacity: int = (buckets[0] as MultiMeshInstance3D).multimesh.instance_count
	var z := _render_z(c)
	var lx := _lane_x(c.lane)
	var alive := c.effectives()
	var moving := c.move_order != 0 \
		or c.state == BattleCompany.State.CHARGING \
		or c.state == BattleCompany.State.MELEE \
		or c.state == BattleCompany.State.BROKEN
	var disorder := _company_disorder(c)
	var broken := c.state == BattleCompany.State.BROKEN

	# Place each man into the (skin, pose) bucket he belongs in this frame.
	for i in capacity:
		if i < alive and c.is_active():
			var h1 := float((i * 2654435761) % 1000) / 1000.0   # persistent per-man character
			var h2 := float((i * 1103515245 + 12345) % 1000) / 1000.0
			var bucket := (i % SKIN_BUCKETS) * FigureLib.POSE_COUNT \
				+ _pose_for(c, i, h1, moving)
			var slot := counts[bucket]
			counts[bucket] = slot + 1
			# Sun, dirt, and years of wear: no two coats the same value.
			var wear := 0.88 + h1 * 0.22
			var body_y := 0.93 + h2 * 0.13   # no two men the same height
			var body_w := 0.95 + h1 * 0.10
			var body_scale := Vector3(body_w, body_y, body_w)
			var mm: MultiMesh = (buckets[bucket] as MultiMeshInstance3D).multimesh
			# In the scrum the SIM owns every man's position — surging,
			# pausing to fire, or locked in the press (playtest #2).
			if c.scrum_active and i < c.man_x.size():
				var sx := lx + lerpf(c.man_prev_x[i], c.man_x[i], clock.alpha())
				var sz := lerpf(c.man_prev_y[i], c.man_y[i], clock.alpha())
				var sbob := sin(_anim_time * 11.0 + float(i) * 1.7) * 0.05
				# In the press a man faces whoever is in front of him.
				var face_ang := (h2 - 0.5) * 1.6
				if c.man_state[i] == BattleCompany.ManState.FIGHTING:
					face_ang = (0.0 if c.facing() > 0.0 else PI) + (h1 - 0.5) * 0.8
				mm.set_instance_transform(slot, Transform3D(
					Basis.IDENTITY.rotated(Vector3.UP, face_ang).scaled(body_scale),
					Vector3(sx, TerrainLib.height_at(sx, sz, RELIEF)
						+ 0.85 * body_y + sbob, sz)))
				mm.set_instance_color(slot, Color(wear, wear, wear))
				continue
			var file := i % FILES
			var rank := floori(float(i) / float(FILES))
			# Base slot, plus the man's own standing error, scaled by disorder.
			var x := lx + (float(file) - float(FILES) / 2.0 + 0.5) * FILE_SPACING
			x += (h1 - 0.5) * 0.45 * disorder
			var zz := z - float(rank) * RANK_SPACING * c.facing()
			zz += (h2 - 0.5) * 0.5 * disorder
			# Slow individual wander — nobody stands statue-still.
			x += sin(_anim_time * (0.7 + h1) + h1 * 12.0) * 0.09 * disorder
			zz += cos(_anim_time * (0.5 + h2) + h2 * 9.0) * 0.09 * disorder
			# The line bows toward its center under pressure.
			zz -= sin(float(file) / float(FILES - 1) * PI) * 0.35 * (disorder - 0.35) * c.facing()
			# On the march the ranks stretch: every man lags his own amount.
			if moving and not broken:
				zz -= h1 * 0.8 * disorder * c.facing() * float(c.move_order != -1)
			# A broken company is not a formation — it is men, separately.
			if broken:
				var ang := h1 * TAU
				var flight := 2.0 + h2 * 6.0
				x += cos(ang) * flight
				zz += sin(ang) * flight * 0.6
			# Marching men rise and fall on the step; standing men barely.
			var bob := sin(_anim_time * (moving_step_rate(c) * TAU) + h1 * 6.3) \
				* (0.045 if moving else 0.012)
			# The line faces the enemy; each man stands a touch off-square.
			var facing := 0.0 if c.facing() > 0.0 else PI
			if broken:
				facing += PI + (h1 - 0.5) * 1.2   # a routing man faces away
			mm.set_instance_transform(slot, Transform3D(
				Basis.IDENTITY.rotated(Vector3.UP,
					facing + (h2 - 0.5) * 0.5 * disorder).scaled(body_scale),
				Vector3(x, TerrainLib.height_at(x, zz, RELIEF) + 0.85 * body_y + bob, zz)))
			mm.set_instance_color(slot, Color(wear, wear, wear))
	# Park every unused instance of every bucket out of sight.
	var hidden := Transform3D(Basis.IDENTITY.scaled(Vector3(0.001, 0.001, 0.001)),
		Vector3(0, -10, 0))
	for b in buckets.size():
		var mmb: MultiMesh = (buckets[b] as MultiMeshInstance3D).multimesh
		for k in range(counts[b], capacity):
			mmb.set_instance_transform(k, hidden)
	var mat: StandardMaterial3D = _mat_by_id[c.id]
	var faded := broken or not c.is_active()
	mat.albedo_color = Color.WHITE.lerp(Color(0.5, 0.5, 0.5), 0.6 if faded else 0.0)


func moving_step_rate(c: BattleCompany) -> float:
	return 2.6 if c.state == BattleCompany.State.BROKEN else 1.7


func _spawn_fallen(c: BattleCompany) -> void:
	var prev: int = _last_effectives[c.id]
	var now := c.effectives()
	if now >= prev:
		return
	var z := _render_z(c)
	var lx := _lane_x(c.lane)
	for k in (prev - now):
		var idx := prev - 1 - k
		var h := (idx * 2654435761) % 1000
		var mi := MeshInstance3D.new()
		mi.mesh = _fallen_mesh_by_id[c.id]
		mi.material_override = FigureLib.figure_material()
		var x := lx + (float(idx % FILES) - float(FILES) / 2.0 + 0.5) * FILE_SPACING
		x += (float(h % 100) / 100.0 - 0.5) * 0.6
		var zj := (float((h / 100) % 100) / 100.0 - 0.5) * 0.9
		var fz := z - float(floori(float(idx) / float(FILES))) * RANK_SPACING * c.facing() + zj
		mi.position = Vector3(x, TerrainLib.height_at(x, fz, RELIEF) + 0.02, fz)
		mi.rotation.y = (float(h % 63) / 63.0 - 0.5) * 1.3
		_fallen_parent.add_child(mi)
	_last_effectives[c.id] = now


## Muzzle flashes + rising powder puffs whenever a platoon discharges.
func _spawn_fire_effects(c: BattleCompany) -> void:
	var prev: Array = _prev_shots[c.id]
	for p in BattleCompany.PLATOON_COUNT:
		if c.platoon_shots[p] > int(prev[p]):
			# Remember the discharge so the men can hold the FIRE pose.
			if not _last_shot_time.has(c.id):
				_last_shot_time[c.id] = {}
			(_last_shot_time[c.id] as Dictionary)[p] = _anim_time
			var z := _render_z(c) + c.facing() * 0.9
			var lx := _lane_x(c.lane) + (-3.4 if p == 0 else 3.4)
			for j in 4:
				var x := lx + (float(j) - 1.5) * 1.6
				_spawn_flash(Vector3(x, 1.35, z))
			_spawn_puff(Vector3(lx - 1.5, 1.7, z))
			_spawn_puff(Vector3(lx + 1.5, 1.7, z))
		prev[p] = c.platoon_shots[p]


func _spawn_flash(pos: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.55, 0.28, 0.14)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.86, 0.45)
	box.material = mat
	mi.mesh = box
	mi.position = pos
	_fx_parent.add_child(mi)
	_fx.append({"n": mi, "mat": mat, "age": 0.0, "life": 0.13, "kind": "flash"})
	if sim.night:
		# At night the flash owns the frame: a brief real light.
		var lamp := OmniLight3D.new()
		lamp.light_color = Color(1.0, 0.75, 0.4)
		lamp.light_energy = 5.0
		lamp.omni_range = 14.0
		lamp.position = pos + Vector3(0, 0.6, 0)
		_fx_parent.add_child(lamp)
		_fx.append({"n": lamp, "mat": null, "age": 0.0, "life": 0.14, "kind": "light"})


func _spawn_puff(pos: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(1.1, 0.9, 0.9)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.86, 0.85, 0.80, 0.5)
	box.material = mat
	mi.mesh = box
	mi.position = pos
	_fx_parent.add_child(mi)
	_fx.append({"n": mi, "mat": mat, "age": 0.0, "life": 2.4, "kind": "puff"})


func _update_fx(delta: float) -> void:
	var keep: Array[Dictionary] = []
	for fx in _fx:
		fx["age"] = float(fx["age"]) + delta
		var n: Node3D = fx["n"]
		var t := float(fx["age"]) / float(fx["life"])
		if t >= 1.0:
			n.queue_free()
			continue
		match String(fx["kind"]):
			"puff":
				n.position.y += 0.55 * delta
				n.scale = Vector3.ONE * (1.0 + 1.1 * float(fx["age"]))
				var mat: StandardMaterial3D = fx["mat"]
				mat.albedo_color.a = 0.5 * (1.0 - t)
			"light":
				(n as OmniLight3D).light_energy = 5.0 * (1.0 - t)
		keep.append(fx)
	_fx = keep


func _update_smoke() -> void:
	var strength := 0.22 if sim.night else 0.4
	for i in _smoke_boxes.size():
		var mat := (_smoke_boxes[i].mesh as BoxMesh).material as StandardMaterial3D
		mat.albedo_color.a = clampf(sim.smoke.cells[i], 0.0, 1.0) * strength


# --- cameras -----------------------------------------------------------

func _update_camera_follow() -> void:
	var pc := sim.get_company(PLAYER_ID)
	if pc == null:
		return
	var z := _render_z(pc)
	var lx := _lane_x(pc.lane)
	_camera.position = _camera.position.lerp(
		Vector3(lx + 14.0 * _zoom, 18.0 * _zoom, z - 22.0 * _zoom), 0.12)
	_camera.look_at(Vector3(lx, 1.0, z + 32.0), Vector3.UP)


func _active_company(side: int, lane: int) -> BattleCompany:
	for c in sim.companies:
		if c.side == side and c.lane == lane and c.is_active():
			return c
	for c in sim.companies:
		if c.side == side and c.is_active():
			return c
	return null


## The demo director: hard cuts between a small vocabulary of shots,
## chosen from what the battle is actually doing. Deterministic — no RNG.
func _update_camera_cinematic(delta: float) -> void:
	_shot_age += delta
	var forced := -1
	for c in sim.companies:
		if not c.is_active():
			continue
		if c.state == BattleCompany.State.MELEE:
			forced = SHOT_MELEE
			_focus_lane = c.lane
			break
		elif c.state == BattleCompany.State.CHARGING and forced < 0:
			forced = SHOT_WIDE
			_focus_lane = c.lane
	if sim.over:
		forced = SHOT_CRANE

	var blue := _active_company(0, _focus_lane)
	var red := _active_company(1, _focus_lane)
	if blue == null and red == null:
		return
	var bz := _render_z(blue) if blue != null else _render_z(red)
	var rz := _render_z(red) if red != null else bz
	var dist := absf(rz - bz)

	var opening_shot := SHOT_TRACK if sim.night else SHOT_AERIAL
	var opening_secs := 6.0 if sim.night else 10.0
	if forced >= 0:
		if _shot != forced:
			_cut(forced)
	elif _elapsed < opening_secs:
		if _shot != opening_shot:
			_cut(opening_shot)
	elif dist > 95.0:
		if _shot != SHOT_TRACK and _shot_age > 3.0:
			_cut(SHOT_TRACK)
	elif _shot_age > _shot_max_age or not FIREFIGHT_CYCLE.has(_shot):
		_cycle_index += 1
		if _lanes > 1 and _cycle_index % 2 == 0:
			_focus_lane = 1 - _focus_lane
		_cut(FIREFIGHT_CYCLE[_cycle_index % FIREFIGHT_CYCLE.size()])

	var lx := _lane_x(_focus_lane)
	var mid := (bz + rz) / 2.0
	var age := _shot_age
	match _shot:
		SHOT_AERIAL:
			_camera.position = Vector3(lx + 34.0, maxf(22.0, 34.0 - age * 0.9), mid - 55.0 + age * 1.6)
			_camera.look_at(Vector3(lx, 0.0, mid), Vector3.UP)
		SHOT_TRACK:
			_camera.position = Vector3(lx - 15.0, 3.2, bz - 8.0 + age * 0.5)
			_camera.look_at(Vector3(lx, 1.4, bz + 30.0), Vector3.UP)
		SHOT_OVER_BLUE:
			_camera.position = Vector3(lx + 7.0, 5.5, bz - 12.0 - age * 0.3)
			_camera.look_at(Vector3(lx, 1.2, rz), Vector3.UP)
		SHOT_OVER_RED:
			_camera.position = Vector3(lx - 7.0, 5.5, rz + 12.0 + age * 0.3)
			_camera.look_at(Vector3(lx, 1.2, bz), Vector3.UP)
		SHOT_WIDE:
			_camera.position = Vector3(lx - 36.0 + age * 0.8, 9.0, mid)
			_camera.look_at(Vector3(lx, 1.5, mid), Vector3.UP)
		SHOT_MELEE:
			var ang := age * 0.3
			_camera.position = Vector3(lx + cos(ang) * 14.0, 4.2, mid + sin(ang) * 14.0)
			_camera.look_at(Vector3(lx, 1.2, mid), Vector3.UP)
		SHOT_CRANE:
			_camera.position = Vector3(lx + 14.0, 9.0 + age * 2.0, mid - 26.0)
			_camera.look_at(Vector3(lx, 1.0, mid), Vector3.UP)


func _cut(shot: int) -> void:
	_shot = shot
	_shot_age = 0.0


# --- HUD ---------------------------------------------------------------

## The notes lie open for a few seconds, then fold away. H brings them
## back and pins them.
func _update_help(delta: float) -> void:
	if _help_card == null:
		return
	_help_age += delta
	if _help_pinned:
		_help_card.modulate.a = 1.0
		return
	_help_card.modulate.a = clampf(1.0 - (_help_age - 7.0) / 1.5, 0.0, 1.0)
	_help_card.visible = _help_card.modulate.a > 0.01

func _update_hud() -> void:
	var pc := sim.get_company(PLAYER_ID)
	var foe := sim.nearest_enemy(pc) if pc != null else null
	var lines: Array[String] = []
	var wx_note := ""
	if sim.weather == "rain":
		wx_note = "   |   RAIN — priming damp, %d%% of shots fail, reloading slow" % \
			int(sim.misfire_loss() * 100.0)
	elif sim.night:
		wx_note = "   |   NIGHT — firing at shapes"
	lines.append("LET TYRANTS SHAKE — M2 vertical slice" + wx_note)
	if sim.night:
		var alarm := "THE ALARM IS RAISED" if sim.alarm_raised else "silence — the columns are undiscovered"
		lines.append("BAYONETS ONLY — night storm, Stony Point pattern   |   %s" % alarm)
	if _campaign and GameState.roster != null:
		var expiring := GameState.roster.expiring_by(GameState.roster.day + GameState.CAMP_DAYS).size()
		var expiry_note := "   |   %d terms expire within a fortnight" % expiring if expiring > 0 else ""
		lines.append("CAMPAIGN — day %d, battle %d   |   muster: %d fit, %d wounded, %d in the memorial book   |   %d specie%s   |   [M] memorial" % [
			GameState.roster.day, GameState.battles_fought + (1 if _report.is_empty() else 0),
			GameState.roster.fit_count(), GameState.roster.wounded_count(),
			GameState.roster.memorial.size(), GameState.specie, expiry_note])
		if _elapsed < 8.0:
			var bits: Array[String] = []
			if not GameState.last_expiry_report.is_empty():
				var er: Dictionary = GameState.last_expiry_report
				var n_stayed: int = (er["stayed"] as Array).size()
				var n_gone: int = (er["departed"] as Array).size()
				if n_stayed + n_gone > 0:
					bits.append("terms up: %d re-enlisted (%d bounties paid), %d went home" % [
						n_stayed, int(er["bounties_paid"]), n_gone])
			for note in GameState.last_camp_notes:
				bits.append(note)
			if not GameState.last_recruits.is_empty():
				bits.append("%d recruits joined: %s" % [
					GameState.last_recruits.size(), ", ".join(GameState.last_recruits)])
			if not bits.is_empty():
				lines.append("IN CAMP %d DAYS — %s" % [GameState.last_camp_days, "  |  ".join(bits)])
	lines.append("")
	if pc != null:
		var hold_txt := "  hold %.1fs (bonus %.0f%%)" % [pc.present_hold, pc.hold_bonus() * 100.0] \
			if pc.state == BattleCompany.State.PRESENTING else ""
		var cover := sim.terrain.cover_at(pc.pos_y)
		var cover_txt := "  COVER: %s (%.0f%%)" % [
			sim.terrain.kind_at(pc.pos_y), cover * 100.0] if cover > 0.0 else \
			("  IN THE OPEN" if not sim.terrain.bands.is_empty() else "")
		lines.append("%s — %d effectives  cohesion %.0f%%  %s  fire: %s  [%s | %s]%s%s" % [
			pc.brigade.display_name, pc.effectives(), pc.cohesion() * 100.0,
			_state_txt(pc), pc.fire_mode_name(),
			_platoon_txt(pc, 0), _platoon_txt(pc, 1), hold_txt, cover_txt])
	if pc != null and foe != null:
		lines.append("%s — %d effectives  cohesion %.0f%%  %s  range %d yds  smoke %.0f%%" % [
			foe.brigade.display_name, foe.effectives(), foe.cohesion() * 100.0,
			_state_txt(foe), int(absf(foe.pos_y - pc.pos_y)),
			sim.smoke.sample_between(pc.pos_y, foe.pos_y) * 100.0])
	if _lanes > 1:
		var extras: Array[String] = []
		for c in sim.companies:
			if c.lane == 1:
				extras.append("%s %d (%s)" % [c.brigade.display_name, c.effectives(), c.state_name()])
		if not extras.is_empty():
			lines.append("Second lane: " + " vs ".join(extras))
	if sim.over:
		lines.append("")
		match sim.winner_side:
			0: lines.append(">>> The field is yours. <<<")
			1: lines.append(">>> Your line has been driven from the field. <<<")
			_: lines.append(">>> Nightfall — the action ends in attrition. <<<")
	if not _report.is_empty():
		lines.append("")
		lines.append("--- AFTER ACTION: the butcher's bill ---")
		var killed: Array = _report["killed"]
		if killed.is_empty():
			lines.append("Killed: none — every man answers the next roll call.")
		else:
			lines.append("Killed (%d):" % killed.size())
			for i in mini(killed.size(), 10):
				lines.append("    %s" % killed[i])
			if killed.size() > 10:
				lines.append("    ...and %d more" % (killed.size() - 10))
		var wounded: Array = _report["wounded"]
		if not wounded.is_empty():
			lines.append("Wounded (%d): %s" % [wounded.size(), ", ".join(wounded)])
		lines.append("Company drill: %s   |   %d fit for duty   |   pay chest: %d specie" % [
			Formation.DRILL_NAMES[int(_report["drill"])], int(_report["fit"]),
			int(_report.get("specie", 0))])
		var expiring_n := int(_report.get("expiring", 0))
		if expiring_n > 0:
			lines.append("%d ENLISTMENTS EXPIRE during the coming camp." % expiring_n)
		lines.append("[ENTER] To camp — review the muster roll, set the fortnight's orders, then march.")
	if _show_memorial and _campaign and GameState.roster != null:
		lines.append("")
		lines.append("=== THE MEMORIAL BOOK — %d names ===" % GameState.roster.memorial.size())
		var book := GameState.roster.memorial
		for i in range(maxi(0, book.size() - 15), book.size()):
			var entry: Dictionary = book[i]
			lines.append("    %s %s of %s — %s" % [
				entry.get("given_name", "?"), entry.get("surname", "?"),
				entry.get("home_town", "?"), entry.get("fate", "?")])
		lines.append("Mustered out and gone home: %d" % GameState.roster.mustered_out.size())
	_hud.text = "\n".join(lines)
	var tail := sim.battle_log.slice(maxi(0, sim.battle_log.size() - 5))
	_log_label.text = "\n".join(tail)


## The state text a commander actually needs: movement is visible in
## words, not just in one-yard-per-second box drift (playtest #1).
func _state_txt(c: BattleCompany) -> String:
	if c.state == BattleCompany.State.STEADY:
		match c.move_order:
			1: return "ADVANCING"
			-1: return "FALLING BACK"
			_: return "HALTED"
	if c.state == BattleCompany.State.MELEE and c.scrum_active and c.scrum_foe_id == "":
		return "RE-FORMING"
	return c.state_name()


func _platoon_txt(c: BattleCompany, p: int) -> String:
	if c.bayonets_only:
		return "%s: UNLOADED BY ORDER" % BattleCompany.PLATOON_NAMES[p]
	if c.platoon_loaded[p]:
		return "%s loaded" % BattleCompany.PLATOON_NAMES[p]
	return "%s %.0fs" % [BattleCompany.PLATOON_NAMES[p], c.platoon_reload[p]]
