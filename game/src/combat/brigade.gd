class_name Brigade
extends RefCounted
## A fighting unit of persistent SimSoldiers (company-scale for now;
## the class will grow into companies-within-brigade). Sim-side only.
## Used today by the main-scene volley demo; grows into the M1 prototype.

## Period-plausible name pools for generated recruits. Production
## replaces these with sampling from digitized muster rolls (docs/02).
const GIVEN := ["Ebenezer", "Josiah", "Amos", "Silas", "Prince", "Cato",
	"Nathan", "Elijah", "Asa", "Jonas", "Seth", "Reuben", "Cuff",
	"Isaac", "Moses", "Levi", "Jabez", "Obadiah", "Peleg", "Zadok"]
const SURNAMES := ["Parker", "Hosmer", "Buttrick", "Davis", "Munroe",
	"Estabrook", "Whittemore", "Barrett", "Brown", "Hayward", "Salem",
	"Prescott", "Glover", "Hale", "Warren", "Dawes", "Cooper", "Tidd"]

var display_name: String = ""
var soldiers: Array[SimSoldier] = []
var formation := Formation.new()
var cohesion: float = 1.0
var volleys_fired: int = 0


## Wrap a persistent roster for battle: the SAME SimSoldier objects, so
## every casualty the sim inflicts is already on the muster roll when
## the smoke clears (docs/02: the muster roll is the emotional ledger).
static func from_roster(roster: Roster) -> Brigade:
	var b := Brigade.new()
	b.display_name = roster.company_name
	b.soldiers = roster.fit_soldiers()
	b.formation.drill = roster.company_drill()
	return b


static func muster_company(name: String, count: int, drill_level: int,
		rng: RandomNumberGenerator) -> Brigade:
	var b := Brigade.new()
	b.display_name = name
	b.formation.drill = drill_level
	for i in count:
		var s := SimSoldier.new()
		s.id = i
		s.given_name = GIVEN[rng.randi() % GIVEN.size()]
		s.surname = SURNAMES[rng.randi() % SURNAMES.size()]
		s.drill_level = drill_level
		b.soldiers.append(s)
	return b


func effectives() -> int:
	var n := 0
	for s in soldiers:
		if s.status == SimSoldier.Status.FIT:
			n += 1
	return n


func is_fighting() -> bool:
	return effectives() > 0 and cohesion > MoraleModel.BREAK_THRESHOLD


func take_casualties(count: int, rng: RandomNumberGenerator) -> void:
	var down := 0
	for s in soldiers:
		if down >= count:
			break
		if s.status == SimSoldier.Status.FIT:
			# Wound-vs-kill split resolved properly in after-action
			# (docs/02: the hospital system); the demo downs men only.
			s.status = SimSoldier.Status.WOUNDED if rng.randf() < 0.7 else SimSoldier.Status.DEAD
			down += 1
	for i in down:
		take_morale_event(MoraleModel.Event.CASUALTY)


func take_morale_event(event: int) -> void:
	cohesion = maxf(0.0, cohesion - MoraleModel.drain_for(event, formation.drill))
