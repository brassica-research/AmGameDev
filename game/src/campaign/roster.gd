class_name Roster
extends RefCounted
## The muster roll: the persistent company of named soldiers that is the
## game's emotional ledger (docs/02 "The brigade"). Battles borrow the
## ACTUAL SimSoldier objects, so casualties flow back here by reference;
## after-action moves the dead to the memorial book — permanently.
## Pure logic, no Nodes, no autoload dependencies: fully testable headless.

## Period-plausible pools; production replaces these with sampling from
## digitized muster rolls (docs/02). Names include documented Black
## patriots' given names (Prince, Cato, Cuff, Salem — see docs/04).
const GIVEN := ["Ebenezer", "Josiah", "Amos", "Silas", "Prince", "Cato",
	"Nathan", "Elijah", "Asa", "Jonas", "Seth", "Reuben", "Cuff", "Salem",
	"Isaac", "Moses", "Levi", "Jabez", "Obadiah", "Peleg", "Zadok",
	"William", "John", "Thomas", "Samuel", "Joseph", "Benjamin", "David",
	"Jonathan", "Timothy", "Abner", "Caleb", "Eli", "Ezra", "Gideon",
	"Hezekiah", "Israel", "Nathaniel", "Oliver", "Phineas", "Solomon"]
const SURNAMES := ["Parker", "Hosmer", "Buttrick", "Davis", "Munroe",
	"Estabrook", "Whittemore", "Barrett", "Brown", "Hayward", "Salem",
	"Prescott", "Glover", "Hale", "Warren", "Dawes", "Cooper", "Tidd",
	"Adams", "Bailey", "Chandler", "Cutler", "Eaton", "Fiske", "Gould",
	"Harrington", "Ingalls", "Jewett", "Kimball", "Lawrence", "Mead",
	"Nutting", "Osgood", "Pratt", "Reed", "Stearns", "Thorp", "Upham",
	"Varnum", "Wheeler", "Wyman"]
const TOWNS := ["Acton", "Concord", "Lexington", "Woburn", "Sudbury",
	"Bedford", "Lincoln", "Menotomy", "Cambridge", "Charlestown",
	"Watertown", "Medford", "Danvers", "Beverly", "Marblehead", "Salem",
	"Roxbury", "Dorchester", "Braintree", "Chelmsford"]
const TRAITS := ["marksman", "steady", "mariner", "old soldier",
	"fifer", "drummer", "quick hands", "strong as an ox"]

const TRAIT_CHANCE := 0.22
const DIE_OF_WOUNDS_CHANCE := 0.12
## Battles survived -> earned drill (docs/02: Green -> Drilled ->
## Veteran -> Old Guard track, mapped onto Formation.Drill).
const VETERANCY_TIERS := [
	[9, Formation.Drill.VETERAN],
	[5, Formation.Drill.REGULAR],
	[2, Formation.Drill.DRILLED],
]

var company_name := ""
var day := 0                    # campaign day counter
var founded_seed := 0
var soldiers: Array[SimSoldier] = []
var memorial: Array[Dictionary] = []   # the book of the dead — never shrinks
var _next_id := 0


static func muster_new(name: String, count: int, seed_value: int) -> Roster:
	var r := Roster.new()
	r.company_name = name
	r.founded_seed = seed_value
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	for i in count:
		r.soldiers.append(r._generate(rng))
	return r


func _generate(rng: RandomNumberGenerator) -> SimSoldier:
	var s := SimSoldier.new()
	s.id = _next_id
	_next_id += 1
	s.given_name = GIVEN[rng.randi() % GIVEN.size()]
	s.surname = SURNAMES[rng.randi() % SURNAMES.size()]
	s.home_town = TOWNS[rng.randi() % TOWNS.size()]
	s.age = 16 + int(pow(rng.randf(), 1.5) * 29.0)  # young army, some greybeards
	s.enlisted = "campaign day %d" % day
	if rng.randf() < TRAIT_CHANCE:
		s.traits.append(TRAITS[rng.randi() % TRAITS.size()])
	return s


func fit_soldiers() -> Array[SimSoldier]:
	var out: Array[SimSoldier] = []
	for s in soldiers:
		if s.status == SimSoldier.Status.FIT:
			out.append(s)
	return out


func fit_count() -> int:
	return fit_soldiers().size()


func wounded_count() -> int:
	var n := 0
	for s in soldiers:
		if s.status == SimSoldier.Status.WOUNDED:
			n += 1
	return n


## The company's fighting quality is its soldiers': the average earned
## drill of the men actually standing. Losing veterans LOWERS this —
## the Tears-of-Metal hook, made mechanical (docs/01 pillar 1).
func company_drill() -> int:
	var fit := fit_soldiers()
	if fit.is_empty():
		return Formation.Drill.MILITIA
	var total := 0
	for s in fit:
		total += s.drill_level
	return clampi(int(float(total) / float(fit.size())), 0, Formation.Drill.VETERAN)


## The butcher's bill. `fought` is the battle brigade's soldier list —
## the same objects, already status-marked by the sim. Returns a report
## for the after-action screen.
func apply_after_action(fought: Array[SimSoldier], rng: RandomNumberGenerator) -> Dictionary:
	var killed: Array[String] = []
	var wounded: Array[String] = []
	for s in fought:
		match s.status:
			SimSoldier.Status.DEAD:
				killed.append("%s of %s, aged %d" % [s.display_name(), s.home_town, s.age])
				_bury(s, "killed in action, campaign day %d" % day)
			SimSoldier.Status.WOUNDED:
				s.recovery_days = 14 + rng.randi_range(0, 45)
				s.battles += 1
				wounded.append("%s (%d weeks)" % [s.display_name(), ceili(float(s.recovery_days) / 7.0)])
			SimSoldier.Status.FIT:
				s.battles += 1
	_update_veterancy()
	return {
		"killed": killed,
		"wounded": wounded,
		"fit": fit_count(),
		"wounded_total": wounded_count(),
		"drill": company_drill(),
		"memorial_total": memorial.size(),
	}


## Camp time: wounds close or kill; the campaign calendar advances.
func advance_days(days: int, rng: RandomNumberGenerator) -> void:
	day += days
	for s in soldiers.duplicate():  # _bury() may remove entries
		if s.status != SimSoldier.Status.WOUNDED:
			continue
		s.recovery_days -= days
		if s.recovery_days <= 0:
			if rng.randf() < DIE_OF_WOUNDS_CHANCE:
				s.status = SimSoldier.Status.DEAD
				_bury(s, "died of wounds, campaign day %d" % day)
			else:
				s.status = SimSoldier.Status.FIT
				s.recovery_days = 0


## Fresh men from the recruiting party: green, unknown, and about to
## stand next to veterans who remember everyone they've replaced.
func recruit(count: int, rng: RandomNumberGenerator) -> Array[String]:
	var names: Array[String] = []
	for i in count:
		var s := _generate(rng)
		soldiers.append(s)
		names.append(s.display_name())
	return names


func _bury(s: SimSoldier, fate: String) -> void:
	var d := s.to_dict()
	d["fate"] = fate
	memorial.append(d)
	soldiers.erase(s)


func _update_veterancy() -> void:
	for s in soldiers:
		for tier in VETERANCY_TIERS:
			if s.battles >= int(tier[0]):
				s.drill_level = maxi(s.drill_level, int(tier[1]))
				break


func to_dict() -> Dictionary:
	var soldier_dicts: Array = []
	for s in soldiers:
		soldier_dicts.append(s.to_dict())
	return {
		"company_name": company_name,
		"day": day,
		"founded_seed": founded_seed,
		"next_id": _next_id,
		"soldiers": soldier_dicts,
		"memorial": memorial,
	}


static func from_dict(d: Dictionary) -> Roster:
	var r := Roster.new()
	r.company_name = d.get("company_name", "")
	r.day = int(d.get("day", 0))
	r.founded_seed = int(d.get("founded_seed", 0))
	r._next_id = int(d.get("next_id", 0))
	for sd in d.get("soldiers", []):
		r.soldiers.append(SimSoldier.from_dict(sd))
	# Canonicalize memorial entries through the soldier serializer:
	# JSON parsing floats every number, and the book must round-trip
	# byte-identically (the save/load test holds us to it).
	for entry in d.get("memorial", []):
		var nd: Dictionary = SimSoldier.from_dict(entry).to_dict()
		nd["fate"] = entry.get("fate", "")
		r.memorial.append(nd)
	return r
