class_name BattleSim
extends RefCounted
## The deterministic battle simulation core (docs/07). No Nodes, no
## rendering, no wall-clock time: given (seed, initial state, ordered
## command stream) the battle plays out identically every run — the
## property that buys replays, headless CI tests, and future co-op.
## ALL mutations enter through the CommandBus, player and AI alike.

const FIELD_EDGE := 160.0            # routing past this = fled the field
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
## Set to a company id to echo that actor's orders (and WHY an order
## was refused) into the battle log — playtest finding #1: silent
## orders feel like dead controls. Empty = no echo (films, tests).
var echo_orders_for := ""
var _failsafe_fired := false

## Night-assault scenario state (docs/03 mission 2.12 "Bayonets Only").
var night := false
var alarm_raised := false

## Scripted-scenario state (docs/03 mission 1.5 "Nineteenth of April").
## The script is part of the sim — it submits through the CommandBus on
## fixed ticks, so scripted battles stay a pure function of the seed.
var scripted := ""
var script_stage := 0
var script_wait := 0.0
var first_shot_tick := -1     # the shot nobody will ever swear to
var dispersed := false        # Lexington's bloodless branch
var _auto_militia := false


## Standard M1 scenario: a drilled Continental company vs a regular
## Crown company, 240 yards apart. auto_player=true attaches an AI to
## the Continental side too (used by headless tests and demos).
## lanes=2 adds a second engagement lane — four companies, each pair
## fighting on its own asynchronous clock (richer demos, brigade preview).
static func create_demo(seed_value: int, auto_player := false, lanes := 1) -> BattleSim:
	var sim := BattleSim.new()
	sim.rng.seed = seed_value
	sim.companies.append(make_company(
		"continentals", 0, "Webb's Additional Continentals",
		40, Formation.Drill.DRILLED, -120.0, sim.rng, 0))
	sim.companies.append(make_company(
		"crown", 1, "His Majesty's 23rd Foot",
		40, Formation.Drill.REGULAR, 120.0, sim.rng, 0))
	sim.ais.append(BattleAI.new("crown"))
	if lanes >= 2:
		sim.companies.append(make_company(
			"continentals_2", 0, "Glover's Marblehead Company",
			40, Formation.Drill.DRILLED, -126.0, sim.rng, 1))
		sim.companies.append(make_company(
			"crown_2", 1, "Grenadiers von Rall",
			40, Formation.Drill.REGULAR, 114.0, sim.rng, 1))
		sim.ais.append(BattleAI.new("continentals_2"))
		sim.ais.append(BattleAI.new("crown_2"))
	if auto_player:
		sim.ais.append(BattleAI.new("continentals"))
	return sim


## Campaign skirmish: the player's PERSISTENT company (the actual
## roster soldiers, by reference) against a generated opposing force
## scaled to its strength. Casualties here are forever. auto=true puts
## an AI at the head of the player company (films, headless tests).
static func create_campaign_skirmish(seed_value: int, roster: Roster,
		auto := false, separation := 200.0) -> BattleSim:
	var sim := BattleSim.new()
	sim.rng.seed = seed_value
	var player := BattleCompany.new()
	player.id = "continentals"
	player.side = 0
	player.brigade = Brigade.from_roster(roster)
	player.pos_y = -separation / 2.0
	player.prev_pos_y = player.pos_y
	sim.companies.append(player)
	var count := clampi(roster.fit_count(), 24, 40)
	sim.companies.append(make_company("crown", 1, "Crown Foraging Escort",
		count, Formation.Drill.REGULAR, separation / 2.0, sim.rng, 0))
	sim.ais.append(BattleAI.new("crown"))
	if auto:
		sim.ais.append(BattleAI.new("continentals"))
	return sim


## The Stony Point pattern (Jul 16, 1779): light-infantry columns with
## muskets UNLOADED by order approach a garrison in the dark. Sentries
## detect them at jittered ranges; the alarm wakes the garrison; the
## columns go in with the bayonet alone. Garrison companies that break
## in the melee throw down their arms — quarter given, as it was.
static func create_night_assault(seed_value: int, auto_player := false, lanes := 2) -> BattleSim:
	var sim := BattleSim.new()
	sim.rng.seed = seed_value
	sim.night = true
	var atk_names := ["Wayne's Right Column", "Butler's Left Column"]
	var def_names := ["17th Foot Piquet", "Grenadier Piquet"]
	var atk_ids := ["continentals", "continentals_2"]
	var def_ids := ["crown", "crown_2"]
	for lane in maxi(1, mini(lanes, 2)):
		var atk := make_company(atk_ids[lane], 0, atk_names[lane],
			40, Formation.Drill.VETERAN, -80.0 - 4.0 * float(lane), sim.rng, lane)
		atk.bayonets_only = true
		atk.platoon_loaded = [false, false]
		atk.advance_speed = 1.7  # picked men at the quick step
		sim.companies.append(atk)
		var def := make_company(def_ids[lane], 1, def_names[lane],
			32, Formation.Drill.REGULAR, 25.0 + 3.0 * float(lane), sim.rng, lane)
		def.is_garrison = true
		def.detect_range = sim.rng.randf_range(45.0, 65.0)
		sim.companies.append(def)
		sim.ais.append(BattleAI.new(def_ids[lane], "garrison"))
		if lane > 0 or auto_player:
			sim.ais.append(BattleAI.new(atk_ids[lane], "assault_column"))
	return sim


## Mission 1.5, opening action: Lexington Green, dawn, April 19, 1775.
## Parker's ~38 fit militiamen stand on the Green under his order — stand
## your ground, don't fire unless fired upon. The light infantry come on,
## halt at close range, and demand dispersal. Then a single shot — the
## sources genuinely disagree on whose, and the sim never says — and the
## regulars' fire discipline snaps. The player's real decision is WHEN to
## disperse: promptly costs the Green and no men; standing costs the
## volley. Built strictly from the Parker and Pitcairn depositions.
static func create_lexington(seed_value: int, auto_player := false) -> BattleSim:
	var sim := BattleSim.new()
	sim.rng.seed = seed_value
	sim.scripted = "lexington"
	sim._auto_militia = auto_player
	var militia := make_company("continentals", 0, "Parker's Lexington Company",
		38, Formation.Drill.MILITIA, -20.0, sim.rng, 0)
	militia.hold_fire = true
	sim.companies.append(militia)
	sim.companies.append(make_company("crown", 1, "10th Regiment, Light Company",
		40, Formation.Drill.REGULAR, 80.0, sim.rng, 0))
	# No AI at first: the script walks the regulars on; command attaches
	# only after the shot, when the field stops being a stage.
	return sim


static func make_company(id: String, side: int, display_name: String,
		count: int, drill_level: int, start_y: float,
		rng_ref: RandomNumberGenerator, lane := 0) -> BattleCompany:
	var c := BattleCompany.new()
	c.id = id
	c.side = side
	c.lane = lane
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
	_update_script()
	for cmd in bus.drain_through(tick):
		_apply(cmd)
	_update_night_detection()
	for c in companies:
		c.prev_pos_y = c.pos_y
	for c in companies:
		_update_company(c)
	_update_scrum()
	smoke.step(SimClock.TICK_DT)
	_failsafe()
	_check_end()


func get_company(id: String) -> BattleCompany:
	for c in companies:
		if c.id == id:
			return c
	return null


## Same-lane enemies are engaged first; a company only turns on another
## lane once its own front is empty (keeps multi-lane battles coherent
## while guaranteeing termination when a lane collapses).
func nearest_enemy(c: BattleCompany) -> BattleCompany:
	var best: BattleCompany = null
	var best_d := INF
	var best_same_lane := false
	for other in companies:
		if other.side == c.side or not other.is_active():
			continue
		var same := other.lane == c.lane
		var d := absf(other.pos_y - c.pos_y)
		if (same and not best_same_lane) or (same == best_same_lane and d < best_d):
			best_d = d
			best = other
			best_same_lane = same
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
		h = _mix(h, c.fire_mode)
		h = _mix(h, int(roundf(c.present_hold * 20.0)))
		for p in BattleCompany.PLATOON_COUNT:
			h = _mix(h, 1 if c.platoon_loaded[p] else 0)
			h = _mix(h, int(roundf(c.platoon_reload[p] * 20.0)))
			h = _mix(h, c.platoon_shots[p])
		if c.scrum_active:
			h = _mix(h, c.scrum_shots)
			for i in c.man_x.size():
				h = _mix(h, int(roundf(c.man_x[i] * 8.0)))
				h = _mix(h, int(roundf(c.man_y[i] * 8.0)))
				h = _mix(h, c.man_state[i])
	h = _mix(h, int(roundf(smoke.total() * 4096.0)))
	return h


func _mix(h: int, v: int) -> int:
	return ((h * 31) ^ (v & 0xFFFFFFFF)) & 0xFFFFFFFF


func _log(text: String) -> void:
	battle_log.append("[%6.1fs] %s" % [float(tick) * SimClock.TICK_DT, text])


func _echo(c: BattleCompany, text: String) -> void:
	if c.id == echo_orders_for:
		_log(text)


func _apply(cmd: Dictionary) -> void:
	var c := get_company(String(cmd["actor"]))
	if c == null or not c.is_active():
		return
	if c.hold_fire and String(cmd["verb"]) in ["present", "fire", "fire_at_will", "charge"]:
		_echo(c, "Parker: 'Stand your ground. Don't fire unless fired upon.'")
		return
	match String(cmd["verb"]):
		"advance":
			if c.state == BattleCompany.State.STEADY or c.state == BattleCompany.State.PRESENTING:
				c.state = BattleCompany.State.STEADY
				c.move_order = 1
				_echo(c, "Orders: ADVANCE.")
			else:
				_echo(c, "Cannot advance — the company is %s." % c.state_name())
		"halt":
			if c.state != BattleCompany.State.BROKEN:
				c.move_order = 0
				_echo(c, "Orders: HALT.")
			else:
				_echo(c, "No one is listening — the company is broken.")
		"withdraw":
			if c.state == BattleCompany.State.STEADY or c.state == BattleCompany.State.PRESENTING:
				c.state = BattleCompany.State.STEADY
				c.move_order = -1
				_echo(c, "Orders: FALL BACK, faces to the enemy.")
			else:
				_echo(c, "Cannot withdraw — the company is %s." % c.state_name())
		"present":
			if c.state == BattleCompany.State.STEADY and not c.bayonets_only:
				c.state = BattleCompany.State.PRESENTING
				c.move_order = 0
				c.present_hold = 0.0
				_echo(c, "Orders: PRESENT — hold... hold...")
			elif c.bayonets_only:
				_echo(c, "The muskets are unloaded by order — bayonets only.")
			elif c.state != BattleCompany.State.STEADY:
				_echo(c, "Cannot present — the company is %s." % c.state_name())
		"fire":
			if c.state == BattleCompany.State.PRESENTING and c.any_loaded() and not c.bayonets_only:
				_fire_volley(c)
			elif c.state == BattleCompany.State.PRESENTING and not c.any_loaded():
				_echo(c, "The muskets are EMPTY — %d s to the next loaded platoon." % ceili(minf(c.platoon_reload[0], c.platoon_reload[1])))
		"fire_at_will":
			if c.bayonets_only:
				pass
			elif c.fire_mode != BattleCompany.FireMode.AT_WILL:
				c.fire_mode = BattleCompany.FireMode.AT_WILL
				if c.state == BattleCompany.State.PRESENTING:
					c.state = BattleCompany.State.STEADY
					c.present_hold = 0.0
				for p in BattleCompany.PLATOON_COUNT:
					if c.platoon_loaded[p]:
						c.platoon_ready_delay[p] = rng.randf_range(0.4, 2.4)
				_log("%s fires at will." % c.brigade.display_name)
		"volley_fire":
			if c.fire_mode != BattleCompany.FireMode.VOLLEY:
				c.fire_mode = BattleCompany.FireMode.VOLLEY
				_log("%s re-forms for volley fire." % c.brigade.display_name)
		"charge":
			if c.state == BattleCompany.State.STEADY or c.state == BattleCompany.State.PRESENTING:
				c.state = BattleCompany.State.CHARGING
				c.charge_feared = false
				c.move_order = 0
				_log("%s fixes bayonets and charges!" % c.brigade.display_name)
		"rally":
			c.rally_left = 10.0


## A commanded volley: every loaded platoon fires as one crash, with the
## full Present-hold steadiness bonus and the full morale shock.
func _fire_volley(c: BattleCompany) -> void:
	var target := nearest_enemy(c)
	if target == null:
		return
	var fired := 0
	for p in BattleCompany.PLATOON_COUNT:
		if c.platoon_loaded[p]:
			_fire_platoon(c, p, target, c.hold_bonus(), 1.0, -1)
			fired += 1
	if fired > 0:
		c.brigade.volleys_fired += 1
		target.brigade.take_morale_event(MoraleModel.Event.VOLLEY_RECEIVED)
	c.present_hold = 0.0
	c.state = BattleCompany.State.STEADY


## One platoon discharges. morale_event < 0 means the caller applies the
## shock itself (a commanded volley is one crash, not one per platoon).
func _fire_platoon(c: BattleCompany, p: int, target: BattleCompany,
		hold_bonus: float, discipline: float, morale_event: int) -> void:
	var shooters := c.platoon_effectives(p)
	if shooters == 0 or not target.is_active():
		return
	var dist := absf(target.pos_y - c.pos_y)
	var smoke_v := smoke.sample_between(c.pos_y, target.pos_y)
	var disc := discipline * (0.6 if night else 1.0)  # firing at shapes in the dark
	var hits := VolleyModel.resolve(shooters, dist, smoke_v,
		c.cohesion(), c.drill(), hold_bonus, rng, disc)
	target.brigade.take_casualties(hits, rng)
	if morale_event >= 0:
		target.brigade.take_morale_event(morale_event)
	smoke.deposit(c.pos_y + c.facing() * 3.0, 0.35 * float(shooters) / 40.0)
	c.platoon_loaded[p] = false
	c.platoon_reload[p] = Formation.RELOAD_TIME[c.drill()] * rng.randf_range(0.9, 1.2)
	c.platoon_shots[p] += 1
	if c.platoon_first_fire_tick[p] < 0:
		c.platoon_first_fire_tick[p] = tick
	_log("%s, %s fires at %d yards — %d hit (smoke %.0f%%)" % [
		c.brigade.display_name, BattleCompany.PLATOON_NAMES[p],
		int(dist), hits, smoke_v * 100.0])
	if target.effectives() == 0 and target.state != BattleCompany.State.DESTROYED:
		target.state = BattleCompany.State.DESTROYED
		_log("%s is destroyed." % target.brigade.display_name)


func _update_company(c: BattleCompany) -> void:
	if not c.is_active():
		return
	var dt := SimClock.TICK_DT
	if not c.bayonets_only:  # unloaded-by-order muskets stay unloaded
		for p in BattleCompany.PLATOON_COUNT:
			if not c.platoon_loaded[p]:
				c.platoon_reload[p] -= dt
				if c.platoon_reload[p] <= 0.0:
					c.platoon_reload[p] = 0.0
					c.platoon_loaded[p] = true
					c.platoon_ready_delay[p] = rng.randf_range(0.4, 2.4)
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
		# Winning the press is itself a rally: the moment one side
		# breaks, the other takes heart — a melee produces a standing
		# victor, not two shattered mobs (caught by the regroup test).
		if c.scrum_active and c.scrum_foe_id != "":
			var press_foe := get_company(c.scrum_foe_id)
			if press_foe != null and press_foe.scrum_active:
				press_foe.brigade.cohesion = maxf(press_foe.cohesion(),
					MoraleModel.WAVER_THRESHOLD + 0.15)
				_log("%s takes heart — the press is won." % press_foe.brigade.display_name)
		c.exit_scrum()
		# Night surrender rule: a garrison broken at bayonet point cries
		# for quarter — and receives it, as at Stony Point (docs/03 2.12).
		if night and c.is_garrison and c.state == BattleCompany.State.MELEE:
			c.state = BattleCompany.State.FLED
			_log("%s throws down its arms — quarter is given." % c.brigade.display_name)
			return
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
				# Inside scrum range the charge stops being a formation
				# event: both companies dissolve into individual men
				# (playtest #2 — no more stop-and-tick at contact).
				if dist <= BattleCompany.SCRUM_RANGE \
						and target.state != BattleCompany.State.BROKEN:
					if not target.scrum_active:
						c.state = BattleCompany.State.MELEE
						target.state = BattleCompany.State.MELEE
						c.enter_scrum(target.id, true, rng)
						target.enter_scrum(c.id, false, rng)
						_log("%s closes with the bayonet on %s — the lines dissolve into the press!" % [
							c.brigade.display_name, target.brigade.display_name])
					elif target.scrum_foe_id == "":
						# Caught mid-regroup: the next wave crashes into
						# men still scattered from the last one.
						c.state = BattleCompany.State.MELEE
						c.enter_scrum(target.id, true, rng)
						target.state = BattleCompany.State.MELEE
						target.re_engage(c.id, rng)
						_log("%s crashes into %s before the line can re-form!" % [
							c.brigade.display_name, target.brigade.display_name])
		BattleCompany.State.STEADY:
			if c.move_order != 0:
				var speed := c.advance_speed if c.move_order > 0 else -BattleCompany.WITHDRAW_SPEED
				c.pos_y = clampf(c.pos_y + c.facing() * speed * dt, -FIELD_EDGE, FIELD_EDGE)
			elif c.fire_mode == BattleCompany.FireMode.AT_WILL:
				_update_fire_at_will(c, dt)

	if c.state == BattleCompany.State.STEADY or c.state == BattleCompany.State.PRESENTING:
		c.brigade.cohesion = minf(1.0, c.cohesion()
			+ MoraleModel.recovery_rate(true, true, false, c.drill()) * SimClock.TICK_DT)


## Fire-at-will: each loaded platoon shoots on its own jittered clock —
## the rolling crackle that makes the field's rhythm emergent (docs/02).
func _update_fire_at_will(c: BattleCompany, dt: float) -> void:
	var target := nearest_enemy(c)
	if target == null or absf(target.pos_y - c.pos_y) > BattleCompany.AT_WILL_MAX_RANGE:
		return
	for p in BattleCompany.PLATOON_COUNT:
		if c.platoon_loaded[p]:
			c.platoon_ready_delay[p] -= dt
			if c.platoon_ready_delay[p] <= 0.0:
				_fire_platoon(c, p, target, 0.0, BattleCompany.AT_WILL_DISCIPLINE,
					MoraleModel.Event.PLATOON_VOLLEY_RECEIVED)


## The close-combat scrum (playtest #2): once a charge goes home, the
## fight is forty separate men — some surging at their own pace, some
## pausing for one last shot, some locked blade to blade. Ranks break;
## the engagement keeps moving.
const SCRUM_FIGHT_RATE := 0.05      # casualties/sec per enemy man locked in
const SCRUM_SHOT_HIT := 0.10        # a snapped shot in the press
const SCRUM_CONTACT_RANGE := 1.5


func _update_scrum() -> void:
	var dt := SimClock.TICK_DT
	for c in companies:
		if c.scrum_active and c.is_active():
			_update_scrum_men(c, dt)
	for c in companies:
		if not c.scrum_active or not c.is_active():
			continue
		var foe := get_company(c.scrum_foe_id)
		if foe == null or not foe.is_active() or not foe.scrum_active:
			if c.scrum_foe_id != "":
				# The press breaks up: survivors re-form, man by man,
				# on the ground they now hold (playtest #3 — no
				# stagnant victors). Destruction victories steady the
				# men the same way a broken foe does.
				c.brigade.cohesion = maxf(c.cohesion(), MoraleModel.WAVER_THRESHOLD + 0.15)
				c.begin_regroup()
				_log("The press breaks up — %s re-forms on the ground it holds." % c.brigade.display_name)
			elif c.regrouped():
				c.exit_scrum()
				if c.state == BattleCompany.State.MELEE:
					c.state = BattleCompany.State.STEADY
					c.move_order = 0
					_log("%s stands re-formed and ready." % c.brigade.display_name)
			continue
		var pressure := foe.fighting_count()
		if pressure > 0:
			c.melee_accum += float(pressure) * SCRUM_FIGHT_RATE \
				* foe.bayonet_confidence() * (1.5 if night else 1.0) * dt
			if c.melee_accum >= 1.0:
				var n := int(c.melee_accum)
				c.melee_accum -= float(n)
				c.brigade.take_casualties(n, rng)
				if c.effectives() == 0:
					c.exit_scrum()
					c.state = BattleCompany.State.DESTROYED
					_log("%s is destroyed in the press." % c.brigade.display_name)


func _update_scrum_men(c: BattleCompany, dt: float) -> void:
	var foe := get_company(c.scrum_foe_id)  # null while regrouping
	c.man_prev_x = c.man_x.duplicate()
	c.man_prev_y = c.man_y.duplicate()
	var foe_y := foe.pos_y if foe != null else c.pos_y
	var t := float(tick) * SimClock.TICK_DT
	var sum_y := 0.0
	var alive := 0
	for i in c.brigade.soldiers.size():
		if c.brigade.soldiers[i].status != SimSoldier.Status.FIT:
			continue
		match c.man_state[i]:
			BattleCompany.ManState.SURGE:
				if c.man_timer[i] > 0.0:
					c.man_timer[i] -= dt
				else:
					var phase := float((i * 2654435761) % 628) / 100.0
					c.man_y[i] += signf(foe_y - c.man_y[i]) * c.man_speed[i] * dt
					c.man_x[i] += sin(t * 2.0 + phase) * 0.5 * dt
					if absf(c.man_y[i] - foe_y) < SCRUM_CONTACT_RANGE:
						c.man_state[i] = BattleCompany.ManState.FIGHTING
			BattleCompany.ManState.FIRE_PAUSE:
				c.man_timer[i] -= dt
				if c.man_timer[i] <= 0.0 and c.man_fired[i] == 0:
					c.man_fired[i] = 1
					c.scrum_shots += 1
					if rng.randf() < SCRUM_SHOT_HIT * (0.6 if night else 1.0):
						foe.brigade.take_casualties(1, rng)
						if foe.effectives() == 0 and foe.state != BattleCompany.State.DESTROYED:
							foe.exit_scrum()
							foe.state = BattleCompany.State.DESTROYED
							_log("%s is destroyed in the press." % foe.brigade.display_name)
					# Shot away — nothing left but to go in.
					c.man_state[i] = BattleCompany.ManState.SURGE
					c.man_timer[i] = 0.2 + rng.randf() * 0.6
			BattleCompany.ManState.FIGHTING:
				var ph := float((i * 1103515245) % 628) / 100.0
				c.man_x[i] += cos(t * 3.0 + ph) * 0.9 * dt
				c.man_y[i] += sin(t * 2.3 + ph) * 0.7 * dt
			BattleCompany.ManState.REGROUP:
				var dx := c.slot_x(i) - c.man_x[i]
				var dy := c.slot_y(i) - c.man_y[i]
				var d := sqrt(dx * dx + dy * dy)
				if d > 0.15:
					var step := minf(c.man_speed[i] * 0.85 * dt, d)
					c.man_x[i] += dx / d * step
					c.man_y[i] += dy / d * step
		sum_y += c.man_y[i]
		alive += 1
	# During a live press the company IS wherever its men are; while
	# regrouping the anchor stays frozen (slots derive from it).
	if alive > 0 and c.scrum_foe_id != "":
		c.pos_y = sum_y / float(alive)


## Night detection: sentries spot the silent columns at their own
## jittered ranges. One challenge wakes the whole garrison.
func _update_night_detection() -> void:
	if not night or alarm_raised:
		return
	for atk in companies:
		if atk.side != 0 or not atk.is_active():
			continue
		for def in companies:
			if not def.is_garrison or not def.is_active():
				continue
			if absf(def.pos_y - atk.pos_y) <= def.detect_range:
				alarm_raised = true
				_log("A challenge rings out of the dark — THE ALARM IS RAISED!")
				for g in companies:
					if g.is_garrison and g.is_active():
						g.brigade.take_morale_event(MoraleModel.Event.NIGHT_ALARM)
				return


## The Lexington script (docs/03 mission 1.5). Stage 0: the regulars come
## on. Stage 1: at close range they halt and demand dispersal. Stage 2:
## the standoff — withdrawing pauses the clock and, past 75 yards, ends
## the action bloodless; standing runs the clock down to the shot. Stage
## 3: the shot (attributed to no musket in this sim, as in the sources),
## the regulars' discipline snaps, and command attaches to both sides.
func _update_script() -> void:
	if scripted != "lexington" or over:
		return
	var militia := get_company("continentals")
	var regulars := get_company("crown")
	if militia == null or regulars == null or not militia.is_active() or not regulars.is_active():
		return
	match script_stage:
		0:
			bus.submit(tick, "crown", "advance")
			_log("Dawn, the nineteenth of April, 1775. Parker's company stands on the Green.")
			script_stage = 1
		1:
			if absf(regulars.pos_y - militia.pos_y) < 55.0:
				bus.submit(tick, "crown", "halt")
				_log("An officer rides forward: 'Disperse, ye rebels! Damn you, throw down your arms and disperse!'")
				script_wait = 12.0
				script_stage = 2
		2:
			if absf(regulars.pos_y - militia.pos_y) > 75.0:
				over = true
				winner_side = 1
				dispersed = true
				_log("Parker's company disperses under protest, muskets kept. The Green is left to the King's troops.")
				return
			# Withdrawing holds the clock — the shot in this sim only
			# comes while men still stand on the Green.
			if militia.move_order != -1:
				script_wait -= SimClock.TICK_DT
				if script_wait <= 0.0:
					script_stage = 3
					first_shot_tick = tick
					_log("A single shot. No man will ever swear to whose musket it was.")
					militia.hold_fire = false
					militia.brigade.take_morale_event(MoraleModel.Event.VOLLEY_RECEIVED)
					bus.submit(tick, "crown", "fire_at_will")
					ais.append(BattleAI.new("crown"))
					if _auto_militia:
						ais.append(BattleAI.new("continentals"))
		_:
			pass  # stage 3+: the ordinary sim owns the field


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
