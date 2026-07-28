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
	_test_close_combat_scrum()
	_test_scrum_regroup()
	_test_king_street_cutscene()
	_test_art_form_pass()
	_test_lexington_green()
	_test_terrain_and_battle_road()
	_test_weather()
	_test_world_stealth()
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


## Playtest #2 directive: at contact the fight becomes individual men —
## no more stop-and-tick. Companies enter the scrum together, men MOVE,
## some fire their last shot, and the battle still reaches a verdict.
func _test_close_combat_scrum() -> void:
	print("\n-- Close-combat scrum: men, not rows")
	var sim := BattleSim.create_demo(31, true)
	var pc := sim.get_company("continentals")
	var foe := sim.get_company("crown")
	var entered := false
	var moved := false
	var steps := 0
	while not sim.over and steps < 12000:
		sim.step()
		steps += 1
		if pc.scrum_active and not entered:
			entered = true
			check(foe.scrum_active, "both companies dissolve into the press together")
			check(pc.state == BattleCompany.State.MELEE and foe.state == BattleCompany.State.MELEE,
				"the scrum is the close-combat state")
			var before := pc.man_y.duplicate()
			for j in 100:  # five seconds inside the press
				sim.step()
			var diffs := 0
			for k in before.size():
				if absf(pc.man_y[k] - before[k]) > 0.5:
					diffs += 1
			moved = diffs >= 5
			break
	check(entered, "a charge inside 25 yards becomes a scrum")
	check(moved, "men move individually inside the scrum — nobody is frozen in rank")
	while not sim.over and steps < 12000:
		sim.step()
		steps += 1
	check(sim.over, "the scrum still resolves to a verdict (tick %d)" % sim.tick)
	var shots := 0
	for c in sim.companies:
		shots += c.scrum_shots
	check(shots >= 1, "some men pause for one last shot in the press")


## Playtest #3 directive: no stagnant victors. A controlled press —
## charge forced, defender's morale shattered by hand so it BREAKS
## (routs, battle continues) — guaranteeing the regroup window exists:
## the victor must jog back to his slots and return to command.
func _test_scrum_regroup() -> void:
	print("\n-- After the press: regroup, man by man")
	var sim := BattleSim.new()
	sim.rng.seed = 77
	var a := BattleSim.make_company("a", 0, "Attacker Company", 40,
		Formation.Drill.DRILLED, -30.0, sim.rng)
	var b := BattleSim.make_company("b", 1, "Defender Company", 40,
		Formation.Drill.REGULAR, 30.0, sim.rng)
	sim.companies.append(a)
	sim.companies.append(b)
	sim.bus.submit(1, "a", "charge")
	var steps := 0
	while not a.scrum_active and steps < 2000:
		sim.step()
		steps += 1
	check(a.scrum_active and b.scrum_active, "the forced charge produces a press")
	for k in 8:
		b.brigade.take_morale_event(MoraleModel.Event.FLANK_TURNED)
	for j in 4:
		sim.step()
	check(b.state == BattleCompany.State.BROKEN, "the shattered defender breaks and routs")
	check(a.cohesion() >= MoraleModel.WAVER_THRESHOLD, "winning the press steadies the victor")
	for j in 600:  # thirty seconds: the men jog home
		sim.step()
	check(not a.scrum_active and a.state == BattleCompany.State.STEADY,
		"the victor re-forms and returns to command")
	var worst := 0.0
	for i in a.brigade.soldiers.size():
		if a.brigade.soldiers[i].status != SimSoldier.Status.FIT:
			continue
		worst = maxf(worst, absf(a.man_x[i] - a.slot_x(i)))
		worst = maxf(worst, absf(a.man_y[i] - a.slot_y(i)))
	check(worst <= 0.8, "every survivor re-formed on his slot (worst %.2f yd)" % worst)
	while not sim.over and steps < 12000:
		sim.step()
		steps += 1
	check(sim.over, "the battle still reaches a verdict after the regroup")


## M2 deliverable: the King Street cutscene plays end-to-end through
## the JSON system — schema sound, sources cited, codex link resolving,
## and the CutscenePlayer streaming every cue in order.
func _test_king_street_cutscene() -> void:
	print("\n-- King Street: the opening scene, end to end")
	var file := FileAccess.open("res://data/cutscenes/king_street.json", FileAccess.READ)
	var data: Dictionary = JSON.parse_string(file.get_as_text())
	check(not (data.get("sources", []) as Array).is_empty(), "the scene cites its sources")
	var events: Array = data.get("events", [])
	var sorted_ok := true
	var known := ["caption", "codex", "camera", "actor", "audio"]
	var last_t := -1.0
	for e in events:
		if float(e.get("t", 0.0)) < last_t:
			sorted_ok = false
		last_t = float(e.get("t", 0.0))
		check_quiet(known.has(String(e.get("track", ""))), "unknown track: %s" % e)
		if String(e.get("track", "")) == "caption":
			check_quiet(String(e.get("text", "")) != "", "caption without text at t=%s" % e.get("t"))
	check(sorted_ok, "the timeline is ordered")
	for e in events:
		if String(e.get("track", "")) == "codex":
			var entry := String(e.get("entry", ""))
			var codex_path := "res://data/codex/%s.json" % entry.trim_prefix("codex_")
			check(FileAccess.file_exists(codex_path), "codex link resolves: %s" % entry)
	# Drive the player headless: every cue must stream, then finish.
	var cp := CutscenePlayer.new()
	var counts := [0, 0, 0, 0, 0]  # captions, codex, camera, actor, done
	cp.caption_shown.connect(func(_t: String, _a: String) -> void: counts[0] += 1)
	cp.codex_linked.connect(func(_e: String) -> void: counts[1] += 1)
	cp.camera_cue.connect(func(_e: Dictionary) -> void: counts[2] += 1)
	cp.actor_cue.connect(func(_e: Dictionary) -> void: counts[3] += 1)
	cp.finished.connect(func(_i: String) -> void: counts[4] += 1)
	cp.play_file("res://data/cutscenes/king_street.json")
	for i in 320:
		cp._process(0.5)
	check(counts[0] >= 12, "the captions stream (%d shown)" % counts[0])
	check(counts[1] == 1, "the codex entry fires once")
	check(counts[2] >= 5, "the camera cuts (%d cues)" % counts[2])
	check(counts[3] >= 6, "the actors move (%d cues)" % counts[3])
	check(counts[4] == 1, "the scene finishes")
	cp.free()


## M2 art form pass: the procedural figure and scenery builders must
## produce real geometry headless, and every presentation script must
## still parse (load() returning null = a syntax error CI should catch).
func _test_art_form_pass() -> void:
	print("\n-- Art form pass: figures and scenery build headless")
	# Loaded at runtime (not preload), so every call on these is dynamic —
	# keep them Variant and type each result explicitly.
	var fig_lib: Variant = load("res://src/presentation/figure_lib.gd")
	var col_lib: Variant = load("res://src/presentation/colonial_lib.gd")
	check(fig_lib != null, "figure_lib parses")
	check(col_lib != null, "colonial_lib parses")
	if fig_lib == null or col_lib == null:
		return
	for kind in [["soldier", fig_lib.build_soldier(Color(0.55, 0.12, 0.11))],
			["militiaman", fig_lib.build_militiaman(Color(0.33, 0.26, 0.18))],
			["civilian", fig_lib.build_civilian(Color(0.30, 0.30, 0.36))],
			["fallen", fig_lib.build_fallen(Color(0.3, 0.3, 0.3))],
			["charging soldier", fig_lib.build_soldier(Color(0.5, 0.1, 0.1), 6)]]:
		var mesh: ArrayMesh = kind[1]
		check(mesh != null and mesh.get_surface_count() == 1, "%s mesh commits" % kind[0])
		var arrays := mesh.surface_get_arrays(0)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
		check(verts.size() >= 300, "%s has a body (%d verts)" % [kind[0], verts.size()])
		check(colors.size() == verts.size(), "%s colors are baked per vertex" % kind[0])
	# A soldier must carry his musket above the hat — the silhouette test.
	var soldier: ArrayMesh = fig_lib.build_soldier(Color(0.5, 0.1, 0.1))
	var top := 0.0
	for v in (soldier.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array):
		top = maxf(top, v.y)
	check(top > 1.0, "the musket rises above the ranks (top %.2f)" % top)
	# A building gets walls, windows, a roof, and at least one chimney.
	var stage := Node3D.new()
	col_lib.make_building(stage, "custom_house", Vector3(8, 0, 8),
		Vector3(12, 8, 9), Color(0.24, 0.23, 0.27))
	check(stage.get_child_count() == 1, "the building hangs off the stage")
	var parts := (stage.get_child(0) as Node3D).get_child_count()
	check(parts >= 6, "walls, windows, door, roof, chimney (%d parts)" % parts)
	# Windows are batched into MultiMeshes — a fifteen-house town was
	# ~900 draw calls before, which software GL felt keenly.
	var batched := 0
	var lit_panes := 0
	for child in (stage.get_child(0) as Node3D).get_children():
		if child is MultiMeshInstance3D:
			batched += 1
			lit_panes += (child as MultiMeshInstance3D).multimesh.instance_count
	# Lit, dark and shuttered — three classes since the joinery pass, so
	# three is the ceiling. (This assertion said two and went red for
	# four runs: a stale test is a broken signal, docs/14 §2.)
	check(batched > 0 and batched <= 3,
		"windows batch into at most three draw calls (%d)" % batched)
	check(lit_panes >= 8, "the house has windows (%d panes)" % lit_panes)
	var ground: StandardMaterial3D = col_lib.ground_material("snow")
	check(ground.albedo_texture != null and ground.uv1_triplanar, "snow ground is textured")
	stage.free()
	# Poses: the whole set must build, and the stances must actually
	# differ — a marching man's feet are not a standing man's.
	var poses: Array = fig_lib.build_pose_set(Color(0.5, 0.1, 0.1), "soldier")
	check(poses.size() == fig_lib.POSE_COUNT, "every pose in the set builds")
	var footprints: Array[float] = []
	for p in poses:
		var lo := 99.0
		var hi := -99.0
		for v in ((p as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array):
			lo = minf(lo, v.z)
			hi = maxf(hi, v.z)
		footprints.append(hi - lo)
	check(footprints[fig_lib.Pose.MARCH_A] > footprints[fig_lib.Pose.STAND],
		"a marching man covers more ground than a standing one")
	check(footprints[fig_lib.Pose.CHARGE] > footprints[fig_lib.Pose.MARCH_A],
		"a charging man is at full stride")
	check(footprints[fig_lib.Pose.PRESENT] > footprints[fig_lib.Pose.STAND],
		"presenting puts the musket out front")
	var tones := {}
	for i in 40:
		tones[fig_lib.skin_for(i, 3)] = true
	check(tones.size() >= 3, "the ranks are not one man repeated (%d tones)" % tones.size())
	# CC0 shim: with packs unfetched the tree must fall back to procedural,
	# and with packs fetched it must still build exactly one node.
	var grove := Node3D.new()
	col_lib.make_bare_tree(grove, Vector3(5, 0, 5), 42)
	check(grove.get_child_count() == 1, "bare tree builds with or without third-party packs")
	grove.free()
	# Ground that is ground: relief, and cover that varies across it.
	var terra: Variant = load("res://src/presentation/terrain_lib.gd")
	check(terra != null, "terrain_lib parses")
	if terra != null:
		var heights: Array[float] = []
		for i in 40:
			heights.append(terra.height_at(float(i) * 11.0, float(i) * 7.0, 1.0))
		var lo := heights[0]
		var hi := heights[0]
		for v in heights:
			lo = minf(lo, v)
			hi = maxf(hi, v)
		check(hi - lo > 1.5, "the land actually rolls (%.1f yd of relief)" % (hi - lo))
		check(absf(terra.height_at(12.0, 34.0, 1.0) - terra.height_at(12.0, 34.0, 1.0)) < 0.0001,
			"the same spot is the same height every time")
		check(terra.height_at(12.0, 34.0, 0.0) == 0.0, "relief 0 gives flat ground")
		var n: Vector3 = terra.normal_at(20.0, 40.0, 1.0)
		check(n.y > 0.7 and absf(n.length() - 1.0) < 0.01, "slopes have sane normals")
		# Cover must vary — the whole complaint was one texture everywhere.
		var cover_tones := {}
		for i in 30:
			var c: Color = terra.cover_at(float(i) * 13.0, float(i) * 17.0, "field", 1.0)
			cover_tones[Vector3i(int(c.r * 40.0), int(c.g * 40.0), int(c.b * 40.0))] = true
		check(cover_tones.size() >= 8, "the field is many colours, not one (%d tones)" % cover_tones.size())
		var stage2 := Node3D.new()
		terra.build_ground(stage2, Vector2(60.0, 60.0), "field", 1.0, 10.0)
		check(stage2.get_child_count() == 1, "the ground is one mesh")
		var gm: MeshInstance3D = stage2.get_child(0)
		check(gm.mesh.get_surface_count() == 1 and \
			(gm.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() > 100,
			"and it is a real displaced grid")
		stage2.free()
	# Windows must be joinery, not a coloured box.
	if col_lib != null:
		var win: ArrayMesh = col_lib.window_mesh("lit")
		var wv: PackedVector3Array = win.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		check(wv.size() > 200, "a window has frame, sill and muntins (%d verts)" % wv.size())
		var wc: PackedColorArray = win.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
		var wtones := {}
		for c in wc:
			wtones[Vector3i(int(c.r * 20.0), int(c.g * 20.0), int(c.b * 20.0))] = true
		check(wtones.size() >= 3, "glass, frame and muntin are different things")
		check(col_lib.window_mesh("shuttered").surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size()
			> wv.size(), "a shuttered window carries its boards")

	# The command party: a company is not forty identical privates.
	if fig_lib != null:
		var officer: ArrayMesh = fig_lib.build_officer(Color(0.5, 0.1, 0.1))
		var sergeant: ArrayMesh = fig_lib.build_sergeant(Color(0.5, 0.1, 0.1))
		var drummer: ArrayMesh = fig_lib.build_drummer(Color(0.5, 0.1, 0.1),
			Color(0.85, 0.8, 0.6))
		var colours: ArrayMesh = fig_lib.build_colours(Color(0.5, 0.1, 0.1),
			Color(0.2, 0.26, 0.52))
		var private_top := 0.0
		for v in (fig_lib.build_soldier(Color(0.5, 0.1, 0.1))
				.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array):
			private_top = maxf(private_top, v.y)
		for named in [["officer", officer], ["sergeant", sergeant],
				["drummer", drummer], ["colours", colours]]:
			var m: ArrayMesh = named[1]
			check_quiet(m != null and m.get_surface_count() == 1,
				"%s builds" % named[0])
		# Each must be distinguishable by SILHOUETTE, which is the whole
		# point — you should know them at two hundred yards.
		var serg_top := 0.0
		for v in (sergeant.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array):
			serg_top = maxf(serg_top, v.y)
		var col_top := 0.0
		for v in (colours.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array):
			col_top = maxf(col_top, v.y)
		check(serg_top > private_top, "the sergeant's spontoon tops the muskets")
		check(col_top > serg_top, "the colours top everything on the field")
		var off_verts: PackedVector3Array = officer.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var off_top := 0.0
		for v in off_verts:
			off_top = maxf(off_top, v.y)
		check(off_top < private_top,
			"the officer carries no musket, so nothing rises above his hat")
		check(drummer.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size() > off_verts.size(),
			"the drummer carries his drum")

	# The house look: one graded environment for every scene (docs/06).
	var look: Variant = load("res://src/presentation/look_dev.gd")
	check(look != null, "look_dev parses")
	if look != null:
		for hour in ["dawn", "overcast", "afternoon", "night", "town_night"]:
			var env: Environment = look.environment(hour)
			check_quiet(env.background_mode == Environment.BG_SKY,
				"%s has a real sky, not a fill colour" % hour)
			check_quiet(env.tonemap_mode == Environment.TONE_MAPPER_FILMIC,
				"%s is filmic-tonemapped" % hour)
			check_quiet(env.fog_enabled and env.fog_density > 0.0,
				"%s carries its distance in fog" % hour)
			check_quiet(env.adjustment_saturation < 1.0,
				"%s keeps the saturation ceiling (docs/06)" % hour)
		check(true, "every hour grades: sky, filmic tonemap, fog, muted saturation")
		var wet: Environment = look.environment("afternoon", "rain")
		var dry: Environment = look.environment("afternoon")
		check(wet.fog_density > dry.fog_density and wet.adjustment_saturation < dry.adjustment_saturation,
			"rain closes the distance down and drains the colour")
		var key: DirectionalLight3D = look.key_light("dawn", "clear", true)
		check(key.shadow_enabled, "the key light casts")
		var flat: DirectionalLight3D = look.key_light("dawn", "clear", false)
		check(not flat.shadow_enabled, "--lowfx rigs skip the shadow pass")
		check(look.fill_light("dawn").light_energy < key.light_energy,
			"the fill is a fill, not a second sun")
		# The bounce carries the ground's colour up into the undersides.
		var bounce: DirectionalLight3D = look.bounce_light("afternoon")
		check(bounce.rotation_degrees.x > 0.0, "the bounce light points UP off the earth")
		check(bounce.light_energy < key.light_energy * 0.4, "and it stays a bounce")
		check(not bounce.shadow_enabled and not look.rim_light("dawn").shadow_enabled,
			"neither bounce nor rim casts — one sun, one set of shadows")
		check(key.shadow_blur > 1.0, "shadow edges are soft: the sun is not a laser")
		check(look.hour_for_scenario("lexington", false) == "dawn"
			and look.hour_for_scenario("battle_road", false) == "afternoon"
			and look.hour_for_scenario("field", true) == "night",
			"each scenario is fought at its own hour")
	# The parchment UI (docs/04: the interface is a document).
	var ui: Variant = load("res://src/presentation/ui_kit.gd")
	check(ui != null, "ui_kit parses")
	if ui != null:
		var tex: ImageTexture = ui.parchment_texture(3, 64)
		check(tex != null and tex.get_width() == 64, "parchment is made, not loaded")
		var img := tex.get_image()
		# Handled edges must be darker than the middle of the sheet.
		var middle := img.get_pixel(32, 32).get_luminance()
		var corner := img.get_pixel(2, 2).get_luminance()
		check(corner < middle, "the sheet is darker where it has been handled")
		var doc: PanelContainer = ui.document("ORDERLY BOOK", 3)
		check(doc.get_meta("body") is Label and doc.get_meta("title") is Label,
			"a document has a title and a body to write in")
		check((doc.get_meta("title") as Label).text == "ORDERLY BOOK",
			"the heading is the document's name")
		var seal: PanelContainer = ui.seal("CHALLENGED")
		check((seal.get_meta("body") as Label).text == "CHALLENGED",
			"the seal carries its one word")
		check(ui.INK.get_luminance() < ui.PARCHMENT.get_luminance(),
			"ink is darker than paper")
		doc.free()
		seal.free()
	# EVERY script must parse. Hand-listing the scenes let world_scene.gd
	# ship a parse error: the scene then ran with no script at all, so
	# _process never fired, --quit-after never quit, and three capture
	# jobs sat recording an empty world until the runner killed them.
	# A missing script is silent at runtime and expensive in CI minutes —
	# so the suite sweeps the whole source tree instead.
	var scripts := _all_scripts("res://src")
	check(scripts.size() >= 15, "the sweep found the source tree (%d scripts)" % scripts.size())
	var bad: Array[String] = []
	for path in scripts:
		if load(path) == null:
			bad.append(path)
	check(bad.is_empty(), "every script in src/ parses%s" % (
		"" if bad.is_empty() else " — FAILED: %s" % ", ".join(bad)))
	# Scene files must point at scripts that exist, too.
	for scene_path in ["res://scenes/battle.tscn", "res://scenes/camp.tscn",
			"res://scenes/cutscene.tscn", "res://scenes/world.tscn"]:
		var packed := load(scene_path) as PackedScene
		check(packed != null, "scene loads: %s" % scene_path)


## Every .gd under a directory, recursively.
func _all_scripts(dir_path: String) -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	for f in dir.get_files():
		if f.get_extension() == "gd":
			out.append(dir_path + "/" + f)
	for sub in dir.get_directories():
		out.append_array(_all_scripts(dir_path + "/" + sub))
	out.sort()
	return out


## Mission 1.5 opening (docs/03): the Lexington script is part of the
## sim, so both of its endings must be deterministic and honest — the
## shot belongs to no musket, dispersing in time is bloodless, and
## standing means the volley.
func _test_lexington_green() -> void:
	print("\n-- Lexington Green: the nineteenth of April")
	# Capture 15 regression: nerve must scale with the butcher's bill.
	check(MoraleModel.casualty_shock(4, 38, 0) > MoraleModel.casualty_shock(4, 380, 0),
		"casualty shock is proportional to the company, not flat")
	check(MoraleModel.casualty_shock(19, 38, 0) > 0.5,
		"losing half the line shatters a green company's nerve")
	var sim := BattleSim.create_lexington(19775, true)
	var militia := sim.get_company("continentals")
	check(militia != null and militia.hold_fire, "Parker's order stands: hold your fire")
	var guard := 0
	while sim.first_shot_tick < 0 and not sim.over and guard < 8000:
		sim.step()
		guard += 1
	check(sim.first_shot_tick > 0, "the shot rings out")
	check(militia.platoon_shots[0] + militia.platoon_shots[1] == 0,
		"not a militia musket fired before it")
	check(not militia.hold_fire, "after the shot, the order is moot")
	guard = 0
	var broke := false
	while not sim.over and guard < 12000:
		sim.step()
		if militia.state == BattleCompany.State.BROKEN:
			broke = true
		guard += 1
	check(sim.over, "the Green is decided")
	check(sim.winner_side == 1, "history holds: the regulars clear the Green")
	check(not sim.dispersed, "standing meant the volley")
	check(militia.effectives() < 38, "and the volley cost men")
	check(sim.tick < BattleSim.HARD_END_TICK, "decided by arms, not the attrition clock")
	check(broke, "the company breaks and scatters — no one rallies them back")
	check(militia.effectives() > 2,
		"the company BREAKS before it is annihilated (capture 15 regression)")
	# Deterministic despite the script: same seed, same battle, tick for tick.
	var a := BattleSim.create_lexington(4444, true)
	var b := BattleSim.create_lexington(4444, true)
	var traces_match := true
	for i in 900:
		a.step()
		b.step()
		if a.state_hash() != b.state_hash():
			traces_match = false
			break
	check(traces_match, "the scripted scenario stays deterministic")
	# The bloodless branch: withdraw at the demand and keep every man.
	var s2 := BattleSim.create_lexington(19775, false)
	guard = 0
	while s2.script_stage < 2 and guard < 8000:
		s2.step()
		guard += 1
	check(s2.script_stage == 2, "the dispersal demand is made")
	s2.bus.submit(s2.tick + 1, "continentals", "withdraw")
	guard = 0
	while not s2.over and guard < 8000:
		s2.step()
		guard += 1
	check(s2.over and s2.dispersed, "dispersing in time ends it without a volley")
	check(s2.first_shot_tick < 0, "no shot was ever fired")
	var m2 := s2.get_company("continentals")
	check(m2.effectives() == 38, "every man walks off the Green")


## Terrain as cover, and the running fight it makes possible (docs/03
## 1.5 third act) — the last open sim item from the M2 directives.
func _test_terrain_and_battle_road() -> void:
	print("\n-- Terrain: cover, and the Battle Road")
	var t := Terrain.battle_road()
	check(t.cover_at(-70.0) >= Terrain.WALL_COVER, "a man at the wall is behind the wall")
	check(t.cover_at(-45.0) == 0.0, "open ground between walls is open ground")
	check(t.fire_multiplier(-70.0) < t.fire_multiplier(-45.0),
		"fire finds the sheltered less often")
	check(t.kind_at(18.0) == "fence" and t.cover_at(18.0) < Terrain.WALL_COVER,
		"a rail fence is not a stone wall")
	# Fall-back geometry: side 0 faces +y, so its rear is DOWN-field.
	check(t.cover_behind(-24.0, 1.0) == -70.0, "the next wall back is the one to your rear")
	check(t.cover_behind(-70.0, 1.0) == INF, "at the last wall there is nothing behind you")
	check(t.nearest_cover(-45.0) == -24.0, "caught in the open, the nearest wall is nearest")
	# Cover has to matter to the volley math, not just the map.
	var open_p := VolleyModel.hit_probability(60.0, 0.0, 1.0, 2, 0.0, 1.0, 1.0)
	var wall_p := VolleyModel.hit_probability(60.0, 0.0, 1.0, 2, 0.0, 1.0,
		t.fire_multiplier(-70.0))
	check(wall_p < open_p * 0.8, "the wall is worth at least a fifth of the incoming")
	# The running fight: militia give ground wall to wall, the column
	# takes its beating and gets home, and it terminates either way.
	var sim := BattleSim.create_battle_road(1775, true)
	var militia := sim.get_company("continentals_2")
	var column := sim.get_company("crown")
	var start_y := militia.pos_y
	var guard := 0
	while not sim.over and guard < 11000:
		sim.step()
		guard += 1
	check(sim.over, "the road reaches a verdict (tick %d)" % sim.tick)
	check(column.brigade.volleys_fired > 0 or column.effectives() < 42,
		"the column is engaged on the march")
	check(militia.pos_y < start_y + 1.0,
		"the skirmishers gave ground rather than stand (%.0f -> %.0f)" % [start_y, militia.pos_y])
	check(sim.tick < BattleSim.HARD_END_TICK, "decided before the attrition clock")
	# Determinism holds with terrain in play.
	var a := BattleSim.create_battle_road(88, true)
	var b := BattleSim.create_battle_road(88, true)
	var same := true
	for i in 700:
		a.step()
		b.step()
		if a.state_hash() != b.state_hash():
			same = false
			break
	check(same, "the running fight stays deterministic")


## Weather is sim truth, not a filter (docs/06): a flintlock in a
## downpour is a pike. Battle of the Clouds, Sept 16 1777 — a storm
## ruined 400,000 cartridges and ended the action without a fight.
func _test_weather() -> void:
	print("\n-- Weather: damp powder is a mechanic, not a filter")
	var clear := BattleSim.create_demo(2024, true)
	var wet := BattleSim.create_demo(2024, true)
	wet.weather = "rain"
	check(wet.misfire_loss() > 0.3, "rain ruins a large share of the priming")
	check(clear.misfire_loss() == 0.0, "clear weather costs nothing")
	check(wet.reload_penalty() > clear.reload_penalty(), "wet hands reload slower")
	# Same seed, same commands, one difference: the sky. The rain-soaked
	# field must be measurably less lethal over the same span.
	for i in 2400:
		clear.step()
		wet.step()
	var clear_down := 0
	var wet_down := 0
	for c in clear.companies:
		clear_down += c.brigade.soldiers.size() - c.effectives()
	for c in wet.companies:
		wet_down += c.brigade.soldiers.size() - c.effectives()
	check(wet_down < clear_down,
		"the storm costs fewer men than the clear day (%d vs %d)" % [wet_down, clear_down])
	check(wet.state_hash() != clear.state_hash(), "weather reaches the sim state")
	# And it stays deterministic.
	var a := BattleSim.create_demo(55, true)
	var b := BattleSim.create_demo(55, true)
	a.weather = "rain"
	b.weather = "rain"
	var same := true
	for i in 600:
		a.step()
		b.step()
		if a.state_hash() != b.state_hash():
			same = false
			break
	check(same, "a rainy battle is as deterministic as a dry one")


## The free-world / stealth layer (docs/13): a walk through occupied
## Boston must obey the same contract as a volley — deterministic,
## command-driven, and honest about what an eye can and cannot see.
func _test_world_stealth() -> void:
	print("\n-- Free world: the eighteenth of April, occupied Boston")
	var file := FileAccess.open("res://data/world/boston_1775.json", FileAccess.READ)
	check(file != null, "the world data loads")
	if file == null:
		return
	var data: Dictionary = JSON.parse_string(file.get_as_text())
	check(not (data.get("sources", []) as Array).is_empty(), "the world cites its sources")
	# Geometry sanity: nobody starts, patrols, or must stand inside a house.
	var geo := WorldSim.from_data(data, 1)
	var clear := not geo._inside_block(geo.av_x, geo.av_z)
	for o in geo.objectives:
		if geo._inside_block(float(o["x"]), float(o["z"])):
			clear = false
	for w in geo.watchers:
		for pt in (w["route"] as Array):
			if geo._inside_block(float(pt[0]), float(pt[1])):
				clear = false
	check(clear, "no start, objective, or patrol route stands inside a building")

	# Sight: the cone, the range, the walls, and the crowd all bite.
	var s := WorldSim.from_data(data, 17750418)
	var watcher: Dictionary = s.watchers[0]
	watcher["x"] = 0.0
	watcher["z"] = 0.0
	watcher["heading"] = 0.0          # looking up +z
	s.av_x = 0.0
	s.av_z = 8.0                      # dead ahead, close
	var front := s.visibility_to(watcher)
	check(front > 0.3, "a man in the open ahead of a patrol is seen (%.2f)" % front)
	s.av_z = -8.0                     # behind him
	check(s.visibility_to(watcher) == 0.0, "nobody sees out the back of his head")
	s.av_z = 8.0
	s.av_stance = WorldSim.Stance.CROUCH
	check(s.visibility_to(watcher) < front, "crouching cuts what he can see of you")
	s.av_stance = WorldSim.Stance.RUN
	check(s.visibility_to(watcher) > front, "a running man draws the eye")
	s.av_stance = WorldSim.Stance.WALK
	# A building between you and him is a wall, not a suggestion.
	var blocked_sim := WorldSim.from_data(data, 5)
	var bw: Dictionary = blocked_sim.watchers[0]
	var house: Dictionary = blocked_sim.blocks[5]
	bw["x"] = float(house["x"]) - float(house["w"]) / 2.0 - 6.0
	bw["z"] = float(house["z"])
	bw["heading"] = PI / 2.0
	blocked_sim.av_x = float(house["x"]) + float(house["w"]) / 2.0 + 6.0
	blocked_sim.av_z = float(house["z"])
	check(blocked_sim.visibility_to(bw) == 0.0, "a house between you is cover")
	# Blending into a knot of townsfolk.
	var crowd_sim := WorldSim.from_data(data, 7)
	var cw: Dictionary = crowd_sim.watchers[0]
	var knot: Dictionary = crowd_sim.crowds[0]
	crowd_sim.av_x = float(knot["x"])
	crowd_sim.av_z = float(knot["z"])
	cw["x"] = float(knot["x"])
	cw["z"] = float(knot["z"]) - 10.0
	cw["heading"] = 0.0
	var in_crowd := crowd_sim.visibility_to(cw)
	check(crowd_sim.crowd_cover() > 0.4, "inside the knot you are one more coat")
	# Isolate the variable: same man, same spot, same watcher — the only
	# difference is whether there is a crowd around him to be lost in.
	# Move the CROWD away, don't shrink it: cover falls off with distance
	# from the centre, so a knot of radius ~0 still hides a man standing
	# exactly on its centre (which is what broke this test twice).
	var knot_x := float(knot["x"])
	knot["x"] = knot_x + 500.0
	var alone := crowd_sim.visibility_to(cw)
	check(crowd_sim.crowd_cover() == 0.0, "with the knot gone there is no cover")
	check(in_crowd < alone, "blending beats standing alone in the same spot (%.2f vs %.2f)"
		% [in_crowd, alone])
	# And stepping out of a knot that is still there loses you its cover.
	knot["x"] = knot_x
	crowd_sim.av_x = knot_x + float(knot["r"]) + 5.0
	check(crowd_sim.crowd_cover() == 0.0, "outside the knot there is no cover")

	# The scripted courier makes it through — challenged, but away.
	var run_sim := WorldSim.from_data(data, 17750418)
	var guard := 0
	while not run_sim.over and guard < 6000:
		run_sim.step()
		guard += 1
	check(run_sim.over and run_sim.outcome == "arrived",
		"the courier reaches the boat (%s at %.0fs)" % [run_sim.outcome, float(run_sim.tick) * SimClock.TICK_DT])
	check(run_sim.objective_index == run_sim.objectives.size(),
		"every objective was made in order")
	check(run_sim.log_lines.size() >= 3, "the night is narrated (%d lines)" % run_sim.log_lines.size())

	# And walking straight up to a patrol gets you taken up.
	var caught := WorldSim.from_data(data, 99)
	caught.demo_path = []
	var target: Dictionary = caught.watchers[0]
	caught.av_x = float(target["x"])
	caught.av_z = float(target["z"]) + 12.0
	target["heading"] = 0.0
	for i in 900:
		var dx := float(target["x"]) - caught.av_x
		var dz := float(target["z"]) - caught.av_z
		var d := maxf(0.001, sqrt(dx * dx + dz * dz))
		caught.bus.submit(caught.tick + 1, "avatar", "move", {"x": dx / d, "z": dz / d})
		caught.step()
		if caught.over:
			break
	check(caught.over and caught.outcome == "seized",
		"walk into a patrol's face and you are taken up (%s)" % caught.outcome)
	check(caught.alarm == WorldSim.Alert.ALERTED, "the street knows")

	# Determinism, the property everything depends on.
	var a := WorldSim.from_data(data, 4242)
	var b := WorldSim.from_data(data, 4242)
	var same := true
	for i in 1200:
		a.step()
		b.step()
		if a.state_hash() != b.state_hash():
			same = false
			break
	check(same, "the same night plays out identically, tick for tick")


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
