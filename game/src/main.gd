extends Node
## Boot scene. For now: proves the data pipeline and the sim core exist.
## Loads the campaign database, prints the mission timeline, and runs a
## tiny deterministic volley-exchange simulation in the console — the
## seed of the M1 "Volley Prototype" (see docs/09-roadmap.md).


func _ready() -> void:
	print("=====================================================")
	print("  TWILIGHT'S GLEAMING (working title) — M1 volley prototype")
	print("=====================================================")
	_print_campaign_timeline()
	_run_volley_demo()
	if DisplayServer.get_name() != "headless":
		get_tree().change_scene_to_file.call_deferred("res://scenes/battle.tscn")


func _print_campaign_timeline() -> void:
	print("\n--- Campaign timeline (from data/campaign/*.json) ---")
	for mission: Dictionary in CampaignDB.all_missions():
		print("  %s  [%s]  %s — %s" % [
			mission.get("date", "????-??-??"),
			mission.get("type", "?"),
			mission.get("title", "?"),
			mission.get("location", "?"),
		])
	print("  (%d missions loaded)" % CampaignDB.all_missions().size())


## Run the REAL battle sim headless to a verdict — no scene tree, no
## rendering, fully deterministic. This is the property the whole
## architecture depends on (docs/07-technical-design.md), exercised on
## every boot. The battle's rhythm is emergent: platoon reload clocks,
## fire-at-will crackle, and jittered AI nerve — never a turn exchange.
func _run_volley_demo() -> void:
	print("\n--- Headless auto-battle (deterministic sim core) ---")
	var sim := BattleSim.create_demo(17750419, true)
	while not sim.over and sim.tick < 12000:
		sim.step()
	for line in sim.battle_log.slice(maxi(0, sim.battle_log.size() - 10)):
		print("  %s" % line)
	print("  Verdict after %.0f s of battle: %s" % [
		float(sim.tick) * SimClock.TICK_DT,
		"side %d holds the field" % sim.winner_side if sim.winner_side >= 0 else "attrition"])
