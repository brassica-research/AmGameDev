class_name WorldSim
extends RefCounted
## The free-world / stealth simulation (docs/13). Occupied Boston at
## street level: you walk, you are watched, and being recognized has
## consequences. Same contract as the battle sim (docs/07) — fixed
## tick, seeded RNG, no wall-clock, every player intent arriving
## through the CommandBus — so a walk through town is as replayable,
## testable, and co-op-ready as a volley.
##
## The vocabulary is the period's, not a fantasy of it: patrols and
## sentries of the occupying regiments, townsfolk to lose yourself
## among, an eye that grows suspicious before it is certain, and a
## challenge — "Who goes there?" — before you are taken up.

const WALK_SPEED := 1.5       # yards/second
const RUN_SPEED := 3.4
const CROUCH_SPEED := 0.85
const RUN_NOISE := 14.0       # yards a run carries
const WALK_NOISE := 4.0

## An officer's eye: how fast certainty builds inside the cone, and how
## fast doubt fades outside it.
const SUSPICION_RISE := 0.90  # per second at point-blank, full view
const SUSPICION_FALL := 0.22
const CHALLENGE_AT := 0.55    # "Who goes there?" — you can still talk/walk it off
const ALERT_AT := 1.0         # recognized: the patrol comes for you
const SEIZE_RANGE := 2.2      # close enough to lay hands on you

enum Stance { WALK, RUN, CROUCH }
enum Alert { CALM, CHALLENGED, ALERTED }

var rng := RandomNumberGenerator.new()
var bus := CommandBus.new()
var tick := 0
var over := false
var outcome := ""             # "" | "arrived" | "seized"
var log_lines: Array[String] = []

## Avatar state. `intent_*` is the last commanded direction; the sim
## integrates it, never the input layer (determinism).
var av_x := 0.0
var av_z := 0.0
var av_prev_x := 0.0
var av_prev_z := 0.0
var av_heading := 0.0
var av_stance := Stance.WALK
var intent_x := 0.0
var intent_z := 0.0
var noise := 0.0              # decays; patrols investigate loud moments

var watchers: Array[Dictionary] = []   # patrols and sentries
var crowds: Array[Dictionary] = []     # market/wharf knots you can blend into
var blocks: Array[Dictionary] = []     # building footprints: sight blockers
var objectives: Array[Dictionary] = []
var objective_index := 0
var alarm := Alert.CALM

## Scripted walk for films/tests: [[x, z], ...] waypoints the auto
## avatar steers through. Empty = a human is driving.
var demo_path: Array = []
var _demo_leg := 0


static func from_data(data: Dictionary, seed_value: int) -> WorldSim:
	var w := WorldSim.new()
	w.rng.seed = seed_value
	var start: Array = data.get("start", [0, 0])
	w.av_x = float(start[0])
	w.av_z = float(start[1])
	w.av_prev_x = w.av_x
	w.av_prev_z = w.av_z
	for b in data.get("blocks", []):
		w.blocks.append({
			"x": float(b["pos"][0]), "z": float(b["pos"][1]),
			"w": float(b["size"][0]), "d": float(b["size"][1]),
			"h": float(b.get("height", 7.0)),
			"name": String(b.get("name", "house")),
		})
	for c in data.get("crowds", []):
		w.crowds.append({
			"x": float(c["pos"][0]), "z": float(c["pos"][1]),
			"r": float(c.get("radius", 4.0)), "count": int(c.get("count", 10)),
			"name": String(c.get("name", "knot of townsfolk")),
		})
	for k in data.get("watchers", []):
		var route: Array = k.get("route", [])
		w.watchers.append({
			"id": String(k.get("id", "patrol")),
			"kind": String(k.get("kind", "patrol")),
			"x": float(route[0][0]) if not route.is_empty() else float(k["pos"][0]),
			"z": float(route[0][1]) if not route.is_empty() else float(k["pos"][1]),
			"prev_x": 0.0, "prev_z": 0.0,
			"heading": float(k.get("heading", 0.0)),
			"route": route, "leg": 0, "pause": 0.0,
			"speed": float(k.get("speed", 1.1)),
			"cone": deg_to_rad(float(k.get("cone_degrees", 75.0))),
			"range": float(k.get("range", 26.0)),
			"suspicion": 0.0,
			"hunting": false,
		})
	for o in data.get("objectives", []):
		w.objectives.append({
			"x": float(o["pos"][0]), "z": float(o["pos"][1]),
			"r": float(o.get("radius", 3.0)),
			"label": String(o.get("label", "")),
		})
	w.demo_path = data.get("demo_path", [])
	return w


func step() -> void:
	if over:
		return
	tick += 1
	for cmd in bus.drain_through(tick):
		_apply(cmd)
	av_prev_x = av_x
	av_prev_z = av_z
	if not demo_path.is_empty():
		_steer_demo()
	_move_avatar()
	for w in watchers:
		_update_watcher(w)
	noise = maxf(0.0, noise - 6.0 * SimClock.TICK_DT)
	_check_objective()


func _apply(cmd: Dictionary) -> void:
	match String(cmd["verb"]):
		"move":
			var args: Dictionary = cmd.get("params", {})
			intent_x = clampf(float(args.get("x", 0.0)), -1.0, 1.0)
			intent_z = clampf(float(args.get("z", 0.0)), -1.0, 1.0)
		"stance":
			var s: Dictionary = cmd.get("params", {})
			av_stance = int(s.get("stance", Stance.WALK))


func _move_avatar() -> void:
	var dt := SimClock.TICK_DT
	var len_v := sqrt(intent_x * intent_x + intent_z * intent_z)
	if len_v < 0.02:
		return
	var speed := WALK_SPEED
	match av_stance:
		Stance.RUN: speed = RUN_SPEED
		Stance.CROUCH: speed = CROUCH_SPEED
	var nx := av_x + (intent_x / len_v) * speed * dt
	var nz := av_z + (intent_z / len_v) * speed * dt
	# You cannot walk through a house. (Climbing one is docs/13 P1.)
	if not _inside_block(nx, nz):
		av_x = nx
		av_z = nz
	elif not _inside_block(nx, av_z):
		av_x = nx
	elif not _inside_block(av_x, nz):
		av_z = nz
	av_heading = atan2(intent_x, intent_z)
	noise = maxf(noise, RUN_NOISE if av_stance == Stance.RUN else
		(WALK_NOISE if av_stance == Stance.WALK else 1.0))


## How visible the avatar is to one watcher, 0..1. Distance, the cone of
## his attention, what stands between you, whether you are crouched, and
## whether you are just another man in a crowd.
func visibility_to(w: Dictionary) -> float:
	var dx := av_x - float(w["x"])
	var dz := av_z - float(w["z"])
	var dist := sqrt(dx * dx + dz * dz)
	var reach: float = float(w["range"])
	if dist > reach:
		return 0.0
	var to_ang := atan2(dx, dz)
	var off := absf(wrapf(to_ang - float(w["heading"]), -PI, PI))
	var half_cone: float = float(w["cone"]) / 2.0
	# A hunting watcher looks everywhere; a bored one looks ahead.
	if bool(w["hunting"]):
		half_cone = PI
	if off > half_cone:
		return 0.0
	if _sight_blocked(float(w["x"]), float(w["z"]), av_x, av_z):
		return 0.0
	var by_dist := 1.0 - (dist / reach)
	var by_cone := 1.0 - (off / maxf(half_cone, 0.001)) * 0.6
	var v := by_dist * by_cone
	if av_stance == Stance.CROUCH:
		v *= 0.45
	elif av_stance == Stance.RUN:
		v *= 1.35   # a running man in an occupied town is a question
	v *= 1.0 - 0.75 * crowd_cover()
	return clampf(v, 0.0, 1.0)


## Blending: inside a knot of townsfolk you are one more coat. Falls off
## toward the edge of the crowd.
func crowd_cover() -> float:
	var best := 0.0
	for c in crowds:
		var dx := av_x - float(c["x"])
		var dz := av_z - float(c["z"])
		var d := sqrt(dx * dx + dz * dz)
		var r: float = float(c["r"])
		if d < r:
			best = maxf(best, 1.0 - d / r * 0.5)
	return clampf(best, 0.0, 1.0)


func _sight_blocked(x0: float, z0: float, x1: float, z1: float) -> bool:
	for b in blocks:
		if _segment_hits_box(x0, z0, x1, z1, b):
			return true
	return false


## Deterministic slab test, sampled — no physics server, no floats we
## can't hash. 24 samples resolves a 4-yard alley at 60 yards.
func _segment_hits_box(x0: float, z0: float, x1: float, z1: float, b: Dictionary) -> bool:
	for i in range(1, 24):
		var t := float(i) / 24.0
		var x := x0 + (x1 - x0) * t
		var z := z0 + (z1 - z0) * t
		if _point_in_box(x, z, b):
			return true
	return false


func _point_in_box(x: float, z: float, b: Dictionary) -> bool:
	return absf(x - float(b["x"])) < float(b["w"]) / 2.0 \
		and absf(z - float(b["z"])) < float(b["d"]) / 2.0


func _inside_block(x: float, z: float) -> bool:
	for b in blocks:
		if _point_in_box(x, z, b):
			return true
	return false


func _update_watcher(w: Dictionary) -> void:
	var dt := SimClock.TICK_DT
	w["prev_x"] = w["x"]
	w["prev_z"] = w["z"]
	var vis := visibility_to(w)
	var before: float = float(w["suspicion"])
	if vis > 0.0:
		w["suspicion"] = minf(1.0, before + SUSPICION_RISE * vis * dt)
	else:
		w["suspicion"] = maxf(0.0, before - SUSPICION_FALL * dt)
	var s: float = float(w["suspicion"])
	if before < CHALLENGE_AT and s >= CHALLENGE_AT:
		_log("\"Who goes there? Stand and be recognized.\"")
		if alarm == Alert.CALM:
			alarm = Alert.CHALLENGED
	if before < ALERT_AT and s >= ALERT_AT:
		w["hunting"] = true
		alarm = Alert.ALERTED
		_log("You are recognized — the %s comes on at the double." % String(w["kind"]))
		for other in watchers:
			if other != w:
				other["suspicion"] = maxf(float(other["suspicion"]), CHALLENGE_AT)

	if bool(w["hunting"]):
		_walk_toward(w, av_x, av_z, float(w["speed"]) * 2.1)
		var dx := av_x - float(w["x"])
		var dz := av_z - float(w["z"])
		if sqrt(dx * dx + dz * dz) <= SEIZE_RANGE:
			over = true
			outcome = "seized"
			_log("Taken up in the street. The night ends in the guardhouse.")
		return

	# A noise pulls a patrol's attention even out of its cone.
	if noise > 8.0 and not bool(w["hunting"]):
		var dxn := av_x - float(w["x"])
		var dzn := av_z - float(w["z"])
		if sqrt(dxn * dxn + dzn * dzn) < noise:
			w["heading"] = atan2(dxn, dzn)
			return
	_patrol(w, dt)


func _patrol(w: Dictionary, dt: float) -> void:
	var route: Array = w["route"]
	if route.size() < 2:
		return
	if float(w["pause"]) > 0.0:
		w["pause"] = float(w["pause"]) - dt
		return
	var leg := int(w["leg"])
	var target: Array = route[leg]
	var reached := _walk_toward(w, float(target[0]), float(target[1]), float(w["speed"]))
	if reached:
		w["leg"] = (leg + 1) % route.size()
		# Sentries and patrols stop, look about, and move on.
		w["pause"] = rng.randf_range(1.0, 3.5)


func _walk_toward(w: Dictionary, tx: float, tz: float, speed: float) -> bool:
	var dx := tx - float(w["x"])
	var dz := tz - float(w["z"])
	var d := sqrt(dx * dx + dz * dz)
	if d < 0.6:
		return true
	w["heading"] = atan2(dx, dz)
	w["x"] = float(w["x"]) + (dx / d) * speed * SimClock.TICK_DT
	w["z"] = float(w["z"]) + (dz / d) * speed * SimClock.TICK_DT
	return false


func _steer_demo() -> void:
	if _demo_leg >= demo_path.size():
		intent_x = 0.0
		intent_z = 0.0
		return
	var wp: Array = demo_path[_demo_leg]
	var dx := float(wp[0]) - av_x
	var dz := float(wp[1]) - av_z
	var d := sqrt(dx * dx + dz * dz)
	if d < 1.2:
		_demo_leg += 1
		return
	intent_x = dx / d
	intent_z = dz / d
	# The scripted walker uses cover the way a player should: crouch when
	# an eye is on him, walk otherwise. Never runs — running is a shout.
	var seen := 0.0
	for w in watchers:
		seen = maxf(seen, visibility_to(w))
	# A courier carrying Warren's word is bold, not timid: he keeps
	# walking until an eye is genuinely on him, then goes low.
	av_stance = Stance.CROUCH if seen > 0.35 else Stance.WALK


func _check_objective() -> void:
	if objective_index >= objectives.size():
		return
	var o: Dictionary = objectives[objective_index]
	var dx := av_x - float(o["x"])
	var dz := av_z - float(o["z"])
	if sqrt(dx * dx + dz * dz) <= float(o["r"]):
		_log(String(o["label"]))
		objective_index += 1
		if objective_index >= objectives.size():
			over = true
			outcome = "arrived"


func current_objective() -> Dictionary:
	if objective_index >= objectives.size():
		return {}
	return objectives[objective_index]


## Loudest suspicion on the board — what the HUD's eye shows.
func heat() -> float:
	var h := 0.0
	for w in watchers:
		h = maxf(h, float(w["suspicion"]))
	return h


func _log(text: String) -> void:
	log_lines.append("[%6.1fs] %s" % [float(tick) * SimClock.TICK_DT, text])


## Deterministic digest — the same property the battle sim guarantees.
func state_hash() -> int:
	var h := 5381
	h = _mix(h, tick)
	h = _mix(h, int(roundf(av_x * 64.0)))
	h = _mix(h, int(roundf(av_z * 64.0)))
	h = _mix(h, av_stance)
	h = _mix(h, objective_index)
	h = _mix(h, alarm)
	for w in watchers:
		h = _mix(h, int(roundf(float(w["x"]) * 64.0)))
		h = _mix(h, int(roundf(float(w["z"]) * 64.0)))
		h = _mix(h, int(roundf(float(w["suspicion"]) * 4096.0)))
		h = _mix(h, 1 if bool(w["hunting"]) else 0)
	return h


func _mix(h: int, v: int) -> int:
	return ((h * 31) ^ (v & 0xFFFFFFFF)) & 0xFFFFFFFF
