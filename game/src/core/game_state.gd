extends Node
## Autoload: the campaign's persistent state. The muster roll is the
## sacred object — the game's emotional ledger (docs/02-game-design.md).
## Everything here must be serializable to versioned JSON.

const SAVE_VERSION := 1

## The player's persistent army: Array of soldier dictionaries
## (see Brigade/SimSoldier for the runtime form). Names, enlistment
## dates, drill level, wounds, fate. Dead soldiers move to memorial_roll
## and NEVER get deleted.
var muster_roll: Array[Dictionary] = []
var memorial_roll: Array[Dictionary] = []

## Campaign position & flags.
var current_mission_id: String = ""
var campaign_flags: Dictionary = {}  # e.g. {"path_b_saratoga": true, "inoculated": true}

## Economy (docs/02): hard money vs depreciating Continental paper.
var specie: int = 0
var continental_dollars: int = 0
var paper_exchange_rate: float = 1.0  # rises act by act — inflation as history


func record_death(soldier: Dictionary, mission_id: String, date: String) -> void:
	soldier["fate"] = {"mission": mission_id, "date": date}
	memorial_roll.append(soldier)


func to_save_dict() -> Dictionary:
	return {
		"version": SAVE_VERSION,
		"muster_roll": muster_roll,
		"memorial_roll": memorial_roll,
		"current_mission_id": current_mission_id,
		"campaign_flags": campaign_flags,
		"specie": specie,
		"continental_dollars": continental_dollars,
		"paper_exchange_rate": paper_exchange_rate,
	}


func load_save_dict(data: Dictionary) -> void:
	# Version migrations live here as the schema evolves.
	muster_roll.assign(data.get("muster_roll", []))
	memorial_roll.assign(data.get("memorial_roll", []))
	current_mission_id = data.get("current_mission_id", "")
	campaign_flags = data.get("campaign_flags", {})
	specie = int(data.get("specie", 0))
	continental_dollars = int(data.get("continental_dollars", 0))
	paper_exchange_rate = float(data.get("paper_exchange_rate", 1.0))
