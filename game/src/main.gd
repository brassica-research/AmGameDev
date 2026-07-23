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


## Two 40-man companies exchange volleys at closing range until one
## breaks. Console-only, deterministic (fixed seed): the point is that
## the sim core runs headless with no scene tree — the property the
## whole architecture depends on (docs/07-technical-design.md).
func _run_volley_demo() -> void:
	print("\n--- Volley model demo: militia line vs regular line ---")
	var rng := RandomNumberGenerator.new()
	rng.seed = 17750419  # April 19, 1775

	var militia := Brigade.muster_company("Acton Minute Company", 40, Formation.Drill.MILITIA, rng)
	var regulars := Brigade.muster_company("His Majesty's 4th Foot", 40, Formation.Drill.REGULAR, rng)
	var range_yards := 100.0

	while militia.is_fighting() and regulars.is_fighting() and range_yards > 0.0:
		range_yards -= 20.0
		var smoke := 0.15 * float(militia.volleys_fired + regulars.volleys_fired)
		militia.fire_volley(regulars, range_yards, smoke, rng)
		regulars.fire_volley(militia, range_yards, smoke, rng)
		print("  @%3d yds | %s: %d up, cohesion %.2f | %s: %d up, cohesion %.2f" % [
			int(range_yards),
			militia.display_name, militia.effectives(), militia.cohesion,
			regulars.display_name, regulars.effectives(), regulars.cohesion,
		])

	var broken := militia if not militia.is_fighting() else regulars
	if broken.is_fighting():
		print("  Bayonet range — melee resolution is M1 work.")
	else:
		print("  %s breaks and quits the field." % broken.display_name)
