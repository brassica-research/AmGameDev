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
	_test_roster_lifecycle()
	_test_veterancy_and_drill()
	_test_wound_recovery()
	_test_roster_persistence_roundtrip()
	_test_refit_to_fighting_strength()
	_test_field_strength_cap()
	_test_enlistment_expiry()
	_test_camp_postures()
	_test_player_command_sequences()
	_test_campaign_three_battles()
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


func _test_roster_lifecycle() -> void:
	print("\n-- Muster roll: battle casualties flow back by reference")
	var roster := Roster.muster_new("Test Company", 40, 1775)
	check(roster.soldiers.size() == 40, "forty men answer the founding muster")
	var ids := {}
	var ages_ok := true
	for s in roster.soldiers:
		ids[s.id] = true
		if s.age < 16 or s.age > 45:
			ages_ok = false
	check(ids.size() == 40, "every soldier has a unique id")
	check(ages_ok, "ages fall in the enlistment envelope (16-45)")
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var brigade := Brigade.from_roster(roster)
	check(brigade.effectives() == 40, "the battle brigade borrows the fit men")
	brigade.take_casualties(10, rng)
	check(roster.fit_count() == 30, "sim casualties land on the roster itself — same objects")
	var report := roster.apply_after_action(brigade.soldiers, rng)
	var killed: Array = report["killed"]
	var wounded: Array = report["wounded"]
	check(killed.size() + wounded.size() == 10, "the butcher's bill accounts for every man down")
	check(roster.memorial.size() == killed.size(), "the dead enter the memorial book")
	check(roster.soldiers.size() == 40 - killed.size(), "the dead leave the muster roll")
	var battles_counted := true
	for s in roster.soldiers:
		if s.battles != 1:
			battles_counted = false
	check(battles_counted, "survivors and wounded alike are credited the battle")


func _test_veterancy_and_drill() -> void:
	print("\n-- Veterancy: losing veterans lowers the line")
	var roster := Roster.muster_new("Vets & Recruits", 40, 42)
	for i in roster.soldiers.size():
		roster.soldiers[i].battles = 9 if i < 20 else 0
	roster._update_veterancy()
	check(roster.soldiers[0].drill_level == Formation.Drill.VETERAN,
		"nine battles makes a veteran")
	check(roster.soldiers[39].drill_level == Formation.Drill.MILITIA,
		"a green recruit is still militia")
	var mixed := roster.company_drill()
	for i in 20:
		roster.soldiers[i].status = SimSoldier.Status.DEAD
	var gutted := roster.company_drill()
	check(mixed > gutted, "kill the veterans and the company's drill rating falls")


func _test_wound_recovery() -> void:
	print("\n-- Hospital: wounds close or kill, deterministically")
	var roster := Roster.muster_new("Invalids", 20, 99)
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	for s in roster.soldiers:
		s.status = SimSoldier.Status.WOUNDED
		s.recovery_days = 10
	roster.advance_days(14, rng)
	var fit := roster.fit_count()
	var buried := roster.memorial.size()
	check(fit + buried == 20, "every wounded man either returns or is buried")
	check(fit > 0, "most wounds heal")
	check(roster.day == 14, "the campaign calendar advances")
	var still := Roster.muster_new("Long Cases", 5, 99)
	for s in still.soldiers:
		s.status = SimSoldier.Status.WOUNDED
		s.recovery_days = 100
	still.advance_days(14, rng)
	check(still.wounded_count() == 5, "long recoveries stay in hospital")


func _test_roster_persistence_roundtrip() -> void:
	print("\n-- Persistence: the muster roll survives the save file")
	var roster := Roster.muster_new("Round Trip Company", 40, 1783)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var brigade := Brigade.from_roster(roster)
	brigade.take_casualties(8, rng)
	roster.apply_after_action(brigade.soldiers, rng)
	roster.advance_days(30, rng)
	for s in roster.soldiers:
		s.term_ends_day = roster.day  # everyone's term is up
	roster.process_expirations(rng, 3)
	check(roster.mustered_out.size() > 0, "round-trip case includes mustered-out men")
	var a := JSON.stringify(roster.to_dict())
	var b := JSON.stringify(Roster.from_dict(JSON.parse_string(a)).to_dict())
	check(a == b, "save -> load -> save is byte-identical")
	var restored := Roster.from_dict(JSON.parse_string(a))
	check(restored.memorial.size() == roster.memorial.size(),
		"the memorial book crosses the save intact")
	check(restored.company_drill() == roster.company_drill(),
		"drill rating survives the round trip")


func _test_refit_to_fighting_strength() -> void:
	print("\n-- Refit: recruit toward the LINE, not the books")
	var roster := Roster.muster_new("Hollowed Company", 40, 8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 8
	for i in 25:
		roster.soldiers[i].status = SimSoldier.Status.WOUNDED
		roster.soldiers[i].recovery_days = 30
	check(roster.fit_count() == 15, "the wounded backlog hollows the line to 15")
	var recruits := roster.refit(40, 60, rng)
	check(recruits.size() == 20, "recruiting aims at 40 fit but stops at the 60-name books cap")
	check(roster.fit_count() == 35 and roster.soldiers.size() == 60,
		"35 men can now stand; the books are full")
	check(roster.refit(40, 60, rng).is_empty(), "full books admit no more recruits")


func _test_field_strength_cap() -> void:
	print("\n-- Fielding: at most forty muskets, the most drilled first")
	var roster := Roster.muster_new("Overfull Company", 55, 21)
	for i in 10:
		roster.soldiers[i].battles = 9
	roster._update_veterancy()
	var b := Brigade.from_roster(roster)
	check(b.soldiers.size() == Brigade.FIELD_STRENGTH, "the line fields exactly forty of fifty-five")
	var vets := 0
	for s in b.soldiers:
		if s.drill_level == Formation.Drill.VETERAN:
			vets += 1
	check(vets == 10, "every veteran takes the field ahead of recruits")
	var ordered := true
	for i in b.soldiers.size() - 1:
		if b.soldiers[i].id >= b.soldiers[i + 1].id:
			ordered = false
	check(ordered, "battle order is neutral — veterans don't head the casualty queue")


func _test_enlistment_expiry() -> void:
	print("\n-- Enlistments expire: the December 1776 mechanic")
	# The decision curve, diceless and monotonic.
	var green := SimSoldier.new()
	var vet := SimSoldier.new()
	vet.drill_level = Formation.Drill.VETERAN
	vet.battles = 6
	check(Roster.stay_chance(vet, false) > Roster.stay_chance(green, false),
		"veterans are likelier to stand by the colors")
	check(Roster.stay_chance(green, true) > Roster.stay_chance(green, false),
		"hard money talks")
	check(Roster.stay_chance(vet, true) <= 0.9, "no man is a certainty")
	# Integration: a whole company's terms come due at once, no chest.
	var roster := Roster.muster_new("Short-Term Levies", 40, 1776)
	for s in roster.soldiers:
		s.term_ends_day = 0
	var rng := RandomNumberGenerator.new()
	rng.seed = 1776
	var report := roster.process_expirations(rng, 0)
	var n_stayed: int = (report["stayed"] as Array).size()
	var n_departed: int = (report["departed"] as Array).size()
	check(n_stayed + n_departed == 40, "every expiring man decides")
	check(n_departed > 0 and n_stayed > 0, "some go home, some stand")
	check(int(report["bounties_paid"]) == 0, "no chest, no bounties")
	check(roster.mustered_out.size() == n_departed, "the departed enter the mustered-out ledger, not the memorial")
	check(roster.memorial.is_empty(), "going home is not dying")
	check(roster.soldiers.size() == n_stayed, "the roll holds only those who signed again")
	var renewed := true
	for s in roster.soldiers:
		if s.term_ends_day != roster.day + Roster.REENLIST_TERM_DAYS:
			renewed = false
	check(renewed, "re-enlistment writes a fresh ninety-day term")
	# The chest changes the arithmetic (same dice, more men persuaded).
	var roster2 := Roster.muster_new("Short-Term Levies", 40, 1776)
	for s in roster2.soldiers:
		s.term_ends_day = 0
	var rng2 := RandomNumberGenerator.new()
	rng2.seed = 1776
	var report2 := roster2.process_expirations(rng2, 99)
	check((report2["stayed"] as Array).size() > n_stayed,
		"the bounty keeps more men than the speech alone")
	check(int(report2["bounties_paid"]) == (report2["stayed"] as Array).size(),
		"bounties are paid only to men who took one and stayed")


func _test_camp_postures() -> void:
	print("\n-- Camp postures: drill, forage, rest")
	# Drill: green men may reach the standard; nobody else is touched.
	var roster := Roster.muster_new("Drill Camp", 40, 1778)
	for i in 5:
		roster.soldiers[i].battles = 9
	roster._update_veterancy()
	var rng := RandomNumberGenerator.new()
	rng.seed = 1778
	var promoted := roster.drill_company(rng)
	check(promoted.size() > 0, "a fortnight of drill raises some recruits to the standard")
	var drilled := 0
	var vets := 0
	for s in roster.soldiers:
		if s.drill_level == Formation.Drill.DRILLED:
			drilled += 1
		elif s.drill_level == Formation.Drill.VETERAN:
			vets += 1
	check(drilled == promoted.size(), "exactly the promoted men carry the new rating")
	check(vets == 5, "drill does not touch the veterans")
	# Rest: double healing clears a 20-day wound in a 14-day camp.
	var resting := Roster.muster_new("Rest Camp", 10, 3)
	var marching := Roster.muster_new("March Camp", 10, 3)
	for r in [resting, marching]:
		for s in r.soldiers:
			s.status = SimSoldier.Status.WOUNDED
			s.recovery_days = 20
	var rng2 := RandomNumberGenerator.new()
	rng2.seed = 3
	resting.advance_days(14, rng2, 2.0)
	marching.advance_days(14, rng2, 1.0)
	check(resting.wounded_count() == 0, "a resting camp mends 20-day wounds in a fortnight")
	check(marching.wounded_count() == 10, "an ordinary camp does not")
	# Forage: sometimes a patrol finds the parties, usually not.
	var mishaps := 0
	var clean := 0
	for seed_value in 30:
		var f := Roster.muster_new("Foragers", 20, seed_value)
		var frng := RandomNumberGenerator.new()
		frng.seed = seed_value
		var name := f.forage_mishap(frng)
		if name == "":
			clean += 1
		else:
			mishaps += 1
			check_quiet(f.wounded_count() == 1, "the mishap wounds exactly one forager")
	check(mishaps > 0 and clean > 0, "foraging risk is real but not certain (%d/30 mishaps)" % mishaps)


## Playtest #1 regression: the exact sequences reported as unresponsive,
## replayed against the sim. Proves the command paths; the presentation
## fix (order echo, HUD movement text) makes the results visible.
func _test_player_command_sequences() -> void:
	print("\n-- Player command sequences (first-playtest report)")
	var sim := BattleSim.create_demo(9, false)  # crown AI only; player manual
	var pc := sim.get_company("continentals")
	# Fire-mode toggle, three times over.
	sim.bus.submit(sim.tick + 1, "continentals", "fire_at_will")
	for i in 3: sim.step()
	check(pc.fire_mode == BattleCompany.FireMode.AT_WILL, "F engages fire-at-will")
	sim.bus.submit(sim.tick + 1, "continentals", "volley_fire")
	for i in 3: sim.step()
	check(pc.fire_mode == BattleCompany.FireMode.VOLLEY, "F toggles BACK to volley fire")
	sim.bus.submit(sim.tick + 1, "continentals", "fire_at_will")
	for i in 3: sim.step()
	check(pc.fire_mode == BattleCompany.FireMode.AT_WILL, "and toggles again — no one-way trap")
	sim.bus.submit(sim.tick + 1, "continentals", "volley_fire")
	for i in 3: sim.step()
	# Advance -> halt -> withdraw.
	sim.bus.submit(sim.tick + 1, "continentals", "advance")
	for i in 100: sim.step()
	var after_advance := pc.pos_y
	check(after_advance > -120.0, "advance moves the line forward")
	sim.bus.submit(sim.tick + 1, "continentals", "halt")
	for i in 3: sim.step()
	var at_halt := pc.pos_y
	for i in 100: sim.step()
	check(pc.pos_y == at_halt, "halt stops the line dead — no drift")
	sim.bus.submit(sim.tick + 1, "continentals", "withdraw")
	for i in 100: sim.step()
	check(pc.pos_y < at_halt, "withdraw moves the line back")
	sim.bus.submit(sim.tick + 1, "continentals", "halt")
	for i in 3: sim.step()
	# Present -> fire -> reload -> present -> fire: the cycle repeats.
	sim.bus.submit(sim.tick + 1, "continentals", "present")
	for i in 40: sim.step()
	sim.bus.submit(sim.tick + 1, "continentals", "fire")
	for i in 3: sim.step()
	var first_volley: int = pc.platoon_shots[0] + pc.platoon_shots[1]
	check(first_volley == 2, "first volley: both platoons discharge")
	check(not pc.any_loaded(), "muskets empty after the volley")
	for i in 400: sim.step()  # 20 s — past the longest drilled reload
	check(pc.all_loaded(), "the company reloads")
	sim.bus.submit(sim.tick + 1, "continentals", "present")
	for i in 40: sim.step()
	sim.bus.submit(sim.tick + 1, "continentals", "fire")
	for i in 3: sim.step()
	check(pc.platoon_shots[0] + pc.platoon_shots[1] == 4, "a second volley follows — SPACE keeps working")


## Quiet variant for assertions inside loops — only failures print.
func check_quiet(cond: bool, label: String) -> void:
	checks += 1
	if not cond:
		failures += 1
		print("  FAIL  %s" % label)


## The whole loop the film shows, run headless: three engagements with
## ONE persistent roster — casualties accumulate, camp heals or buries,
## recruits refill, and every man is accounted for at the end.
func _test_campaign_three_battles() -> void:
	print("\n-- Campaign integration: three battles, one muster roll")
	var roster := Roster.muster_new("Campaign Company", 40, 555)
	var rng := RandomNumberGenerator.new()
	rng.seed = 555
	var recruits_total := 0
	for b in 3:
		var sim := BattleSim.create_campaign_skirmish(1000 + b, roster, true, 140.0)
		var steps := 0
		while not sim.over and steps < 12000:
			sim.step()
			steps += 1
		check(sim.over, "campaign battle %d reaches a verdict" % (b + 1))
		roster.apply_after_action(
			sim.get_company("continentals").brigade.soldiers, rng)
		roster.advance_days(14, rng)
		recruits_total += roster.refit(40, 60, rng).size()
	check(roster.soldiers.size() + roster.memorial.size() + roster.mustered_out.size() == 40 + recruits_total,
		"every man who ever mustered is on the roll, in the book, or home — none lost to bookkeeping")
	check(roster.memorial.size() > 0, "three battles against regulars leave names in the book")
	check(roster.day == 42, "six weeks of campaign have passed")
	var veterans := 0
	for s in roster.soldiers:
		if s.battles >= 2:
			veterans += 1
	check(veterans > 0, "survivors of multiple battles are becoming veterans")


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
