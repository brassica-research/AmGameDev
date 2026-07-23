class_name BattleSim
extends RefCounted
## The deterministic battle simulation core (docs/07). No Nodes, no
## rendering, no wall-clock time: given (seed, initial state, ordered
## command stream) the battle plays out identically every run — the
## property that buys replays, headless CI tests, and future co-op.
## ALL mutations enter through the CommandBus, player and AI alike.

const FIELD_EDGE := 160.0            # routing past this = fled the field
const MELEE_CASUALTY_RATE := 0.05    # fraction of enemy effectives per second
const FAILSAFE_CHARGE_TICK := 8000   # force the issue in auto battles
const HARD_END_TICK := 11000         # attrition verdict — guarantees termination

var rng := RandomNumberGenerator.new()
var bus := CommandBus.new()
var smoke := SmokeGrid.new()
var companies: Array[BattleCompany] = []
var ais: Array[BattleAI] = []
var tick := 0
var over := false
var winner_side := -1
var battle_log: Array[String] = []
var _failsafe_fired := false


## Standard M1 scenario: a drilled Continental company vs a regular
## Crown company, 240 yards apart. auto_player=true attaches an AI to
## the Continental side too (used by headless tests and demos).
static func create_demo(seed_value: int, auto_player := false) -> BattleSim:
	var sim := BattleSim.new()
	sim.rng.seed = seed_value
	sim.companies.append(make_company(
		"continentals", 0, "Webb's Additional Continentals",
		40, Formation.Drill.DRILLED, -120.0, sim.rng))
	sim.companies.append(make_company(
		"crown", 1, "His Majesty's 23rd Foot",
		40, Formation.Drill.REGULAR, 120.0, sim.rng))
	sim.ais.append(BattleAI.new("crown"))
	if auto_player:
		sim.ais.append(BattleAI.new("continentals"))
	return sim


static func make_company(id: String, side: int, display_name: String,
		count: int, drill_level: int, start_y: float,
		rng_ref: RandomNumberGenerator) -> BattleCompany:
	var c := BattleCompany.new()
	c.id = id
	c.side = side
	c.brigade = Brigade.muster_company(display_name, count, drill_level, rng_ref)
	c.pos_y = start_y
	c.prev_pos_y = start_y
	return c


func step() -> void:
	if over:
		return
	tick += 1
	for ai in ais:
		ai.think(self)
	for cmd in bus.drain_through(tick):
		_apply(cmd)
	for c in companies:
		c.prev_pos_y = c.pos_y
	for c in companies:
		_update_company(c)
	_update_melee()
	smoke.step(SimClock.TICK_DT)
	_failsafe()
	_check_end()


func get_company(id: String) -> BattleCompany:
	for c in companies:
		if c.id == id:
			return c
	return null


func nearest_enemy(c: BattleCompany) -> BattleCompany:
	var best: BattleCompany = null
	var best_d := INF
	for other in companies:
		if other.side == c.side or not other.is_active():
			continue
		var d := absf(other.pos_y - c.pos_y)
		if d < best_d:
			best_d = d
			best = other
	return best


## Deterministic digest of the whole battle state, for determinism
## tests and (later) desync detection in co-op.
func state_hash() -> int:
	var h := 5381
	h = _mix(h, tick)
	for c in companies:
		h = _mix(h, c.id.hash())
		h = _mix(h, int(roundf(c.pos_y * 16.0)))
		h = _mix(h, c.effectives())
		h = _mix(h, int(roundf(c.cohesion() * 4096.0)))
		h = _mix(h, c.state)
		h = _mix(h, 1 if c.loaded else 0)
		h = _mix(h, int(roundf(c.reload_left * 20.0)))
		h = _mix(h, int(roundf(c.present_hold * 20.0)))
	h = _mix(h, int(roundf(smoke.total() * 4096.0)))
	return h


func _mix(h: int, v: int) -> int:
	return ((h * 31) ^ (v & 0xFFFFFFFF)) & 0xFFFFFFFF


func _log(text: String) -> void:
	battle_log.append("[%6.1fs] %s" % [float(tick) * SimClock.TICK_DT, text])


func _apply(cmd: Dictionary) -> void:
	var c := get_company(String(cmd["actor"]))
	if c == null or not c.is_active():
		return
	match String(cmd["verb"]):
		"advance":
			if c.state == BattleCompany.State.STEADY or c.state == BattleCompany.State.PRESENTING:
				c.state = BattleCompany.State.STEADY
				c.move_order = 1
		"halt":
			if c.state != BattleCompany.State.BROKEN:
				c.move_order = 0
		"withdraw":
			if c.state == BattleCompany.State.STEADY or c.state == BattleCompany.State.PRESENTING:
				c.state = BattleCompany.State.STEADY
				c.move_order = -1
		"present":
			if c.state == BattleCompany.State.STEADY:
				c.state = BattleCompany.State.PRESENTING
				c.move_order = 0
				c.present_hold = 0.0
		"fire":
			if c.state == BattleCompany.State.PRESENTING and c.loaded:
				_fire(c)
		"charge":
			if c.state == BattleCompany.State.STEADY or c.state == BattleCompany.State.PRESENTING:
				c.state = BattleCompany.State.CHARGING
				c.charge_feared = false
				c.move_order = 0
				_log("%s fixes bayonets and charges!" % c.brigade.display_name)
		"rally":
			c.rally_left = 10.0


func _fire(c: BattleCompany) -> void:
	var target := nearest_enemy(c)
	if target == null:
		return
	var dist := absf(target.pos_y - c.pos_y)
	var smoke_v := smoke.sample_between(c.pos_y, target.pos_y)
	var hits := VolleyModel.resolve(c.effectives(), dist, smoke_v,
		c.cohesion(), c.drill(), c.hold_bonus(), rng)
	c.brigade.volleys_fired += 1
	target.brigade.take_casualties(hits, rng)
	target.brigade.take_morale_event(MoraleModel.Event.VOLLEY_RECEIVED)
	smoke.deposit(c.pos_y + c.facing() * 3.0, 0.35 * float(c.effectives()) / 40.0)
	c.loaded = false
	c.reload_left = Formation.RELOAD_TIME[c.drill()]
	c.present_hold = 0.0
	c.state = BattleCompany.State.STEADY
	_log("%s fires at %d yards — %d hit (smoke %.0f%%)" % [
		c.brigade.display_name, int(dist), hits, smoke_v * 100.0])
	if target.effectives() == 0:
		target.state = BattleCompany.State.DESTROYED
		_log("%s is destroyed." % target.brigade.display_name)


func _update_company(c: BattleCompany) -> void:
	if not c.is_active():
		return
	var dt := SimClock.TICK_DT
	if not c.loaded:
		c.reload_left -= dt
		if c.reload_left <= 0.0:
			c.reload_left = 0.0
			c.loaded = true
	if c.rally_left > 0.0:
		c.rally_left -= dt

	if c.state == BattleCompany.State.BROKEN:
		c.pos_y -= c.facing() * BattleCompany.ROUT_SPEED * dt
		var mult := 6.0 if c.rally_left > 0.0 else 1.0
		c.brigade.cohesion = minf(1.0, c.cohesion()
			+ MoraleModel.recovery_rate(c.rally_left > 0.0, true, false, c.drill()) * mult * dt)
		if c.cohesion() >= MoraleModel.WAVER_THRESHOLD:
			c.state = BattleCompany.State.STEADY
			c.move_order = 0
			_log("%s rallies and reforms." % c.brigade.display_name)
		elif absf(c.pos_y) >= FIELD_EDGE:
			c.state = BattleCompany.State.FLED
			_log("%s quits the field." % c.brigade.display_name)
		return

	if c.cohesion() < MoraleModel.BREAK_THRESHOLD:
		c.state = BattleCompany.State.BROKEN
		c.move_order = 0
		c.melee_accum = 0.0
		_log("%s BREAKS!" % c.brigade.display_name)
		return

	match c.state:
		BattleCompany.State.PRESENTING:
			c.present_hold += dt
		BattleCompany.State.CHARGING:
			var target := nearest_enemy(c)
			if target == null:
				c.state = BattleCompany.State.STEADY
			else:
				var dir := signf(target.pos_y - c.pos_y)
				c.pos_y += dir * BattleCompany.CHARGE_SPEED * dt
				var dist := absf(target.pos_y - c.pos_y)
				if dist <= BattleCompany.CHARGE_FEAR_RANGE and not c.charge_feared:
					c.charge_feared = true
					target.brigade.take_morale_event(MoraleModel.Event.BAYONET_CHARGE_INCOMING)
				if dist <= BattleCompany.MELEE_RANGE:
					c.state = BattleCompany.State.MELEE
					if target.state != BattleCompany.State.BROKEN:
						target.state = BattleCompany.State.MELEE
					_log("%s closes with the bayonet on %s." % [
						c.brigade.display_name, target.brigade.display_name])
		BattleCompany.State.STEADY:
			if c.move_order != 0:
				var speed := BattleCompany.ADVANCE_SPEED if c.move_order > 0 else -BattleCompany.WITHDRAW_SPEED
				c.pos_y = clampf(c.pos_y + c.facing() * speed * dt, -FIELD_EDGE, FIELD_EDGE)

	if c.state == BattleCompany.State.STEADY or c.state == BattleCompany.State.PRESENTING:
		c.brigade.cohesion = minf(1.0, c.cohesion()
			+ MoraleModel.recovery_rate(true, true, false, c.drill()) * SimClock.TICK_DT)


func _update_melee() -> void:
	var dt := SimClock.TICK_DT
	for a in companies:
		if a.state != BattleCompany.State.MELEE or not a.is_active():
			continue
		var b := nearest_enemy(a)
		if b == null or absf(b.pos_y - a.pos_y) > BattleCompany.MELEE_RANGE * 2.0 \
				or b.state != BattleCompany.State.MELEE:
			a.state = BattleCompany.State.STEADY
			a.move_order = 0
			continue
		# b cuts into a this tick; the reverse happens on b's iteration.
		a.melee_accum += float(b.effectives()) * MELEE_CASUALTY_RATE * b.bayonet_confidence() * dt
		if a.melee_accum >= 1.0:
			var n := int(a.melee_accum)
			a.melee_accum -= float(n)
			a.brigade.take_casualties(n, rng)
			if a.effectives() == 0:
				a.state = BattleCompany.State.DESTROYED
				_log("%s is destroyed in the melee." % a.brigade.display_name)


## Auto-battle guarantees: force a decision late, and if bayonets still
## haven't settled it, call the attrition verdict. Keeps CI finite.
func _failsafe() -> void:
	if tick == FAILSAFE_CHARGE_TICK and not _failsafe_fired:
		_failsafe_fired = true
		for c in companies:
			if c.is_active():
				bus.submit(tick + 1, c.id, "charge")
	if tick >= HARD_END_TICK and not over:
		over = true
		winner_side = _side_with_more_effectives()
		_log("Nightfall ends the action — attrition verdict.")


func _check_end() -> void:
	if over:
		return
	for side in [0, 1]:
		var total := 0
		var active := 0
		for c in companies:
			if c.side == side:
				total += 1
				if c.is_active():
					active += 1
		if total > 0 and active == 0:
			over = true
			winner_side = 1 - side
			_log("The field belongs to side %d." % winner_side)
			return


func _side_with_more_effectives() -> int:
	var eff := [0, 0]
	for c in companies:
		if c.is_active():
			eff[c.side] += c.effectives()
	if eff[0] == eff[1]:
		return -1
	return 0 if eff[0] > eff[1] else 1
