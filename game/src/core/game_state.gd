extends Node
## Autoload: the campaign's persistent state and its file IO. The muster
## roll is the sacred object (docs/02, docs/07): it is backed up on
## every write, and the dead are never deleted. All campaign randomness
## flows through one seeded, state-saved RNG so a reloaded campaign
## continues exactly where it left off.

const SAVE_VERSION := 2
const SAVE_PATH := "user://muster_roll.json"
const BACKUP_PATH := "user://muster_roll.backup.json"
const COMPANY_STRENGTH := 40
const ROLL_CAP := 60  # the books carry at most half again the line
const CAMP_DAYS := 14
const BOUNTY_COST := 8    # specie per man who takes the bounty and stays
const VICTORY_PAY := 25   # the paymaster is generous when the field is yours
const DEFEAT_PAY := 5     # and nearly empty-handed when it isn't

var roster: Roster = null
var battles_fought := 0
var campaign_rng := RandomNumberGenerator.new()

## Demo/film sandbox: when true, save() is a no-op so an automated
## campaign capture can never touch a player's real muster roll.
var demo_mode := false

## Transient camp news for the HUD (not persisted).
var last_recruits: Array[String] = []
var last_camp_days := 0
var last_expiry_report: Dictionary = {}

## Economy (docs/02): hard money vs depreciating Continental paper.
## Wired into the hub loop in a later milestone; persisted now.
var specie := 0
var continental_dollars := 0
var paper_exchange_rate := 1.0


## Load the saved campaign, or found a new company if none exists.
func ensure_campaign() -> void:
	if roster != null:
		return
	if _load():
		return
	new_campaign(int(Time.get_unix_time_from_system()) & 0x7FFFFFFF)


func new_campaign(seed_value: int) -> void:
	campaign_rng.seed = seed_value
	roster = Roster.muster_new("The Middlesex Company", COMPANY_STRENGTH, seed_value)
	battles_fought = 0
	save()


## Each engagement's sim seed comes from the campaign stream — and the
## stream's state is saved at after-action, so quitting mid-battle
## replays the SAME battle, not a fresh roll of the dice.
func next_battle_seed() -> int:
	return int(campaign_rng.randi())


## After-action: apply the butcher's bill to the roster and persist.
func finish_battle(sim: BattleSim) -> Dictionary:
	var pc := sim.get_company("continentals")
	var report := roster.apply_after_action(pc.brigade.soldiers, campaign_rng)
	battles_fought += 1
	report["battle"] = battles_fought
	report["victory"] = sim.winner_side == 0
	specie += VICTORY_PAY if bool(report["victory"]) else DEFEAT_PAY
	report["specie"] = specie
	report["expiring"] = roster.expiring_by(roster.day + CAMP_DAYS).size()
	save()
	return report


## Camp between engagements: wounds close or kill, recruits fill the
## ranks back toward strength — green men beside the veterans.
## Camp: wounds resolve, terms come due (with or without the bounty),
## and recruiting parties refill toward fighting strength.
func rest_and_refit(days: int, offer_bounty := false) -> Array[String]:
	roster.advance_days(days, campaign_rng)
	var slots := floori(float(specie) / float(BOUNTY_COST)) if offer_bounty else 0
	last_expiry_report = roster.process_expirations(campaign_rng, slots)
	specie -= int(last_expiry_report["bounties_paid"]) * BOUNTY_COST
	var recruits := roster.refit(COMPANY_STRENGTH, ROLL_CAP, campaign_rng)
	last_recruits = recruits
	last_camp_days = days
	save()
	return recruits


func save() -> void:
	if roster == null or demo_mode:
		return
	var data := {
		"version": SAVE_VERSION,
		"battles_fought": battles_fought,
		"rng_seed": campaign_rng.seed,
		"rng_state": campaign_rng.state,
		"specie": specie,
		"continental_dollars": continental_dollars,
		"paper_exchange_rate": paper_exchange_rate,
		"roster": roster.to_dict(),
	}
	# The sacred-file rule (docs/07): back up before every write.
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.copy_absolute(ProjectSettings.globalize_path(SAVE_PATH),
			ProjectSettings.globalize_path(BACKUP_PATH))
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		push_error("GameState: cannot write %s" % SAVE_PATH)
		return
	f.store_string(JSON.stringify(data, "\t"))


func _load() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		return false
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return false
	var data: Variant = JSON.parse_string(f.get_as_text())
	if data is not Dictionary:
		push_error("GameState: corrupt save — see %s for the backup" % BACKUP_PATH)
		return false
	# Version migrations live here as the schema evolves.
	roster = Roster.from_dict(data.get("roster", {}))
	battles_fought = int(data.get("battles_fought", 0))
	campaign_rng.seed = int(data.get("rng_seed", 0))
	campaign_rng.state = int(data.get("rng_state", 0))
	specie = int(data.get("specie", 0))
	continental_dollars = int(data.get("continental_dollars", 0))
	paper_exchange_rate = float(data.get("paper_exchange_rate", 1.0))
	return true
