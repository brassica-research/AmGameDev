extends SceneTree
## Headless sim test suite (docs/09 M1: "headless sim tests in CI").
## Run:  godot --headless --path game -s res://tests/run_tests.gd
## The suite exercises ONLY the sim core — no rendering, no scenes —
## which is the whole point of the sim/presentation split (docs/07).

var checks := 0
var failures := 0


func _initialize() -> void:
	print("== Let Tyrants Shake — deterministic sim test suite ==")
	_test_command_bus()
	_test_volley_model()
	_test_morale_model()
	_test_smoke_grid()
	_test_break_and_rally()
	_test_fire_at_will_stagger()
	_test_lane_targeting()
	_test_night_assault()
	_test_full_battle_terminates()
	_test_determinism()
	print("")
	print("%d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)


func check(cond: bool, label: String) -> void:
	checks += 1
	if cond:
		print("  ok    %s" % label)
	else:
		failures += 1
		print("  FAIL  %s" % label)


func _test_command_bus() -> void:
	print("\n-- CommandBus ordering")
	var bus := CommandBus.new()
	bus.submit(5, "b", "later")
	bus.submit(3, "b", "x")
	bus.submit(3, "a", "x")
	var due := bus.drain_through(4)
	check(due.size() == 2, "drains only commands due by the tick")
	check(String(due[0]["actor"]) == "a" and String(due[1]["actor"]) == "b",
		"same-tick commands ordered deterministically by actor")
	var rest := bus.drain_through(10)
	check(rest.size() == 1 and int(rest[0]["tick"]) == 5, "future command retained then drained")
	check(bus.drain_through(100).is_empty(), "bus empties")


func _test_volley_model() -> void:
	print("\n-- VolleyModel")
	check(VolleyModel.hit_probability(30.0, 0.0, 1.0, 3) >
		VolleyModel.hit_probability(120.0, 0.0, 1.0, 3), "closer range hits harder")
	check(VolleyModel.hit_probability(60.0, 0.0, 1.0, 2) >
		VolleyModel.hit_probability(60.0, 0.9, 1.0, 2), "smoke degrades fire")
	check(VolleyModel.hit_probability(60.0, 0.0, 1.0, 3) >
		VolleyModel.hit_probability(60.0, 0.0, 1.0, 0), "drill improves fire")
	check(VolleyModel.hit_probability(60.0, 0.0, 1.0, 2, VolleyModel.MAX_HOLD_BONUS) >
		VolleyModel.hit_probability(60.0, 0.0, 1.0, 2, 0.0), "holding Present pays off")
	var in_bounds := true
	for r in [0.0, 25.0, 50.0, 100.0, 150.0, 200.0]:
		for s in [0.0, 0.5, 1.0]:
			for d in [0, 1, 2, 3]:
				var p := VolleyModel.hit_probability(r, s, 1.0, d)
				if p <= 0.0 or p > 1.0:
					in_bounds = false
	check(in_bounds, "hit probability stays in (0, 1] across the envelope")


func _test_morale_model() -> void:
	print("\n-- MoraleModel")
	check(MoraleModel.drain_for(MoraleModel.Event.VOLLEY_RECEIVED, 3) <
		MoraleModel.drain_for(MoraleModel.Event.VOLLEY_RECEIVED, 0),
		"veterans absorb shock better than militia")
	check(MoraleModel.recovery_rate(true, true, false, 1) >
		MoraleModel.recovery_rate(false, true, false, 1),
		"officer presence speeds recovery")
	check(MoraleModel.BREAK_THRESHOLD < MoraleModel.WAVER_THRESHOLD,
		"break threshold sits below waver threshold")


func _test_smoke_grid() -> void:
	print("\n-- SmokeGrid")
	var g := SmokeGrid.new()
	g.deposit(0.0, 0.5)
	check(g.sample_between(-5.0, 5.0) > 0.0, "deposited smoke is sampled")
	check(g.sample_between(100.0, 120.0) == 0.0, "distant cells stay clear")
	var before := g.total()
	for i in 200:
		g.step(1.0)
	check(g.total() < before, "smoke decays over time")


func _test_break_and_rally() -> void:
	print("\n-- Break, rout, and rally")
	var sim := BattleSim.new()
	sim.rng.seed = 42
	var c := BattleSim.make_company("test", 0, "Test Company", 40,
		Formation.Drill.MILITIA, -100.0, sim.rng)
	sim.companies.append(c)
	for i in 8:
		c.brigade.take_morale_event(MoraleModel.Event.FLANK_TURNED)
	sim.step()
	check(c.state == BattleCompany.State.BROKEN, "shattered cohesion breaks the company")
	for i in 40:
		sim.step()
	check(c.pos_y < -100.0, "a broken company runs for its own edge")
	sim.bus.submit(sim.tick + 1, "test", "rally")
	for i in 800:
		sim.step()
	check(c.state == BattleCompany.State.STEADY, "the rally reforms the company")
	check(c.cohesion() >= MoraleModel.WAVER_THRESHOLD, "rallied cohesion clears the waver line")


func _test_fire_at_will_stagger() -> void:
	print("\n-- Fire at will: asynchronous platoon cadence")
	var sim := BattleSim.new()
	sim.rng.seed = 7
	var a := BattleSim.make_company("a", 0, "A Company", 40,
		Formation.Drill.DRILLED, -30.0, sim.rng)
	var b := BattleSim.make_company("b", 1, "B Company", 40,
		Formation.Drill.REGULAR, 30.0, sim.rng)
	sim.companies.append(a)
	sim.companies.append(b)
	sim.bus.submit(1, "a", "fire_at_will")
	for i in 1200:  # 60 seconds
		sim.step()
	check(a.fire_mode == BattleCompany.FireMode.AT_WILL, "fire-at-will mode engages")
	check(a.platoon_shots[0] > 0 and a.platoon_shots[1] > 0,
		"both platoons fire on their own clocks")
	check(a.platoon_first_fire_tick[0] != a.platoon_first_fire_tick[1],
		"platoon fire is staggered — no lockstep cadence")
	check(a.platoon_shots[0] + a.platoon_shots[1] >= 4,
		"the rolling fire keeps rolling")


func _test_lane_targeting() -> void:
	print("\n-- Lane targeting")
	var sim := BattleSim.new()
	sim.rng.seed = 3
	var a := BattleSim.make_company("a", 0, "A Company", 10,
		Formation.Drill.DRILLED, -50.0, sim.rng, 0)
	var near_cross := BattleSim.make_company("x", 1, "Cross-lane Company", 10,
		Formation.Drill.DRILLED, -30.0, sim.rng, 1)
	var far_same := BattleSim.make_company("s", 1, "Same-lane Company", 10,
		Formation.Drill.DRILLED, 80.0, sim.rng, 0)
	sim.companies.append(a)
	sim.companies.append(near_cross)
	sim.companies.append(far_same)
	check(sim.nearest_enemy(a) == far_same, "same-lane enemy preferred even when farther")
	far_same.state = BattleCompany.State.FLED
	check(sim.nearest_enemy(a) == near_cross, "falls back across lanes when own front is empty")


func _test_night_assault() -> void:
	print("\n-- Night assault: bayonets only (Stony Point pattern)")
	var sim := BattleSim.create_night_assault(17790716, true, 2)
	var steps := 0
	while not sim.over and steps < 6000:
		sim.step()
		steps += 1
	check(sim.over and sim.tick < 4000, "the storm is decided quickly (tick %d)" % sim.tick)
	var attacker_shots := 0
	for id in ["continentals", "continentals_2"]:
		var c := sim.get_company(id)
		attacker_shots += c.platoon_shots[0] + c.platoon_shots[1]
	check(attacker_shots == 0, "the columns never fire — muskets unloaded by order")
	var log_text := "\n".join(sim.battle_log)
	check(log_text.contains("ALARM"), "the sentries raise the alarm")
	check(log_text.contains("closes with the bayonet"), "the assault goes in with steel")
	check(sim.winner_side == 0, "the works are carried")


func _test_full_battle_terminates() -> void:
	print("\n-- Full auto battle (both sides AI)")
	var sim := BattleSim.create_demo(20260723, true)
	var steps := 0
	while not sim.over and steps < 12000:
		sim.step()
		steps += 1
	check(sim.over, "the battle reaches a verdict (tick %d)" % sim.tick)
	check(sim.winner_side == 0 or sim.winner_side == 1 or sim.winner_side == -1,
		"verdict is a valid side or attrition")
	var fired := false
	for line in sim.battle_log:
		if line.contains("fires at"):
			fired = true
			break
	check(fired, "volleys were actually exchanged")
	var eff_total := 0
	for c in sim.companies:
		eff_total += c.effectives()
	check(eff_total < 80, "the field took casualties")


func _test_determinism() -> void:
	print("\n-- Determinism (the property everything depends on)")
	var h1 := _run_hash_trace(17761224)
	var h2 := _run_hash_trace(17761224)
	check(h1 == h2, "same seed + same commands => identical battle, tick for tick")
	var h3 := _run_hash_trace(17770103)
	check(h1 != h3, "different seed => different battle")


func _run_hash_trace(seed_value: int) -> Array[int]:
	var sim := BattleSim.create_demo(seed_value, true)
	var trace: Array[int] = []
	var steps := 0
	while not sim.over and steps < 12000:
		sim.step()
		steps += 1
		if steps % 1000 == 0:
			trace.append(sim.state_hash())
	trace.append(sim.state_hash())
	trace.append(sim.tick)
	return trace
