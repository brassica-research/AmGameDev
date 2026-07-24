class_name BattleAI
extends RefCounted
## A period-doctrine commander with a pulse, not a metronome. Decision
## ticks are phase-offset per commander, hold times and charge timing
## are jittered through the sim's seeded RNG (so battles stay
## deterministic), and it reads the same field cues a human can see:
## smoke thickening, an enemy line standing with unloaded muskets, a
## wavering foe. It issues orders through the same CommandBus as the
## player — no special powers (docs/07).

const THINK_PERIOD := 10          # thinks every 0.5 s, on its own phase
const MIN_CHARGE_RANGE := 120.0

var company_id: String
var doctrine := "line"            # "line" | "assault_column" | "garrison"
var _phase := 0
var _engage_range := 80.0         # personal doctrine, varies per commander
var _hold_target := 2.5           # redrawn after every volley


func _init(id: String, doctrine_name := "line") -> void:
	company_id = id
	doctrine = doctrine_name
	_phase = absi(id.hash()) % THINK_PERIOD
	_engage_range = 68.0 + float(absi(id.hash()) % 25)


func think(sim: BattleSim) -> void:
	if (sim.tick + _phase) % THINK_PERIOD != 0:
		return
	var me := sim.get_company(company_id)
	if me == null or not me.is_active():
		return
	if me.state == BattleCompany.State.BROKEN:
		sim.bus.submit(sim.tick, company_id, "rally")
		return
	if me.state == BattleCompany.State.CHARGING or me.state == BattleCompany.State.MELEE:
		return
	var foe := sim.nearest_enemy(me)
	if foe == null:
		return
	var dist := absf(foe.pos_y - me.pos_y)

	if doctrine == "assault_column":
		# Silence until discovered; the instant the alarm is up, steel.
		if not sim.alarm_raised:
			if me.move_order != 1:
				sim.bus.submit(sim.tick, company_id, "advance")
		elif dist < 90.0:
			sim.bus.submit(sim.tick, company_id, "charge")
		elif me.move_order != 1:
			sim.bus.submit(sim.tick, company_id, "advance")
		return

	if doctrine == "garrison":
		if not sim.alarm_raised:
			return  # asleep, at ease, or staring at the wrong dark
		if me.move_order != 0 and me.state != BattleCompany.State.PRESENTING:
			sim.bus.submit(sim.tick, company_id, "halt")
			return
		if foe.state == BattleCompany.State.BROKEN and dist < 40.0:
			sim.bus.submit(sim.tick, company_id, "charge")
			return
		# No time for parade-ground volleys with bayonets coming out of
		# the dark: get fire down the glacis at once.
		if me.fire_mode == BattleCompany.FireMode.VOLLEY:
			sim.bus.submit(sim.tick, company_id, "fire_at_will")
		return

	# A shaken enemy is an invitation the bayonet answers.
	var foe_shaken := foe.state == BattleCompany.State.BROKEN \
		or foe.cohesion() < MoraleModel.WAVER_THRESHOLD
	if foe_shaken and dist < MIN_CHARGE_RANGE:
		sim.bus.submit(sim.tick, company_id, "charge")
		return

	# Muskets empty after a hot exchange? Sometimes the answer is steel.
	if me.brigade.volleys_fired >= 3 and not me.any_loaded() \
			and dist < 100.0 and sim.rng.randf() < 0.4:
		sim.bus.submit(sim.tick, company_id, "charge")
		return

	# Press an enemy caught reloading — you can SEE the ramrods working.
	if not foe.any_loaded() and dist > 35.0 and dist < 95.0 \
			and me.move_order != 1 and sim.rng.randf() < 0.35:
		sim.bus.submit(sim.tick, company_id, "advance")
		return

	if dist > _engage_range:
		if me.move_order != 1:
			sim.bus.submit(sim.tick, company_id, "advance")
		return

	# In range: stand and fight.
	if me.move_order != 0 and me.state != BattleCompany.State.PRESENTING:
		sim.bus.submit(sim.tick, company_id, "halt")
		return

	# Close, confident, and an opening: go in without waiting for doctrine.
	if dist < 45.0 and me.cohesion() > foe.cohesion() + 0.1 and sim.rng.randf() < 0.1:
		sim.bus.submit(sim.tick, company_id, "charge")
		return

	# Fire discipline: thick smoke or close quarters favor a rolling
	# fire; clear air at distance favors the controlled crash.
	var smoke_v := sim.smoke.sample_between(me.pos_y, foe.pos_y)
	if me.fire_mode == BattleCompany.FireMode.VOLLEY:
		if (smoke_v > 0.45 or dist < 55.0) and sim.rng.randf() < 0.25:
			sim.bus.submit(sim.tick, company_id, "fire_at_will")
			return
	else:
		if smoke_v < 0.2 and dist > 55.0 and sim.rng.randf() < 0.15:
			sim.bus.submit(sim.tick, company_id, "volley_fire")
		return  # at-will fire runs itself inside the sim

	# The volley cycle, with a human-length finger on the trigger.
	if me.any_loaded():
		if me.state != BattleCompany.State.PRESENTING:
			sim.bus.submit(sim.tick, company_id, "present")
			_hold_target = sim.rng.randf_range(1.2, 3.6)
		elif me.present_hold >= _hold_target:
			sim.bus.submit(sim.tick, company_id, "fire")
