class_name SimSoldier
extends RefCounted
## One persistent, named soldier. Sim-side only (no Node); rendering is
## the presentation shell's problem. Soldiers live on the muster roll
## between battles and their deaths are permanent (docs/02).

enum Status { FIT, WOUNDED, SICK, ROUTED, DESERTED, DEAD }

var id: int
var given_name: String
var surname: String
var home_town: String = ""
var age: int = 20
var enlisted: String = ""       # flavor record of when he signed
var enlistment_ends: String = ""
var term_ends_day: int = -1     # campaign day his term expires (docs/02: enlistments EXPIRE); -1 = no term on record
var drill_level: int = 0        # Formation.Drill
var status: int = Status.FIT
var battles: int = 0
var recovery_days: int = 0      # for WOUNDED: days until fit (or the grave)
var traits: Array[String] = []  # e.g. "marksman", "mariner", "steady"


func display_name() -> String:
	return "%s %s" % [given_name, surname]


func to_dict() -> Dictionary:
	return {
		"id": id, "given_name": given_name, "surname": surname,
		"home_town": home_town, "age": age, "enlisted": enlisted,
		"enlistment_ends": enlistment_ends, "term_ends_day": term_ends_day,
		"drill_level": drill_level,
		"status": status, "battles": battles,
		"recovery_days": recovery_days, "traits": traits,
	}


static func from_dict(d: Dictionary) -> SimSoldier:
	var s := SimSoldier.new()
	s.id = int(d.get("id", 0))
	s.given_name = d.get("given_name", "")
	s.surname = d.get("surname", "")
	s.home_town = d.get("home_town", "")
	s.age = int(d.get("age", 20))
	s.enlisted = d.get("enlisted", "")
	s.enlistment_ends = d.get("enlistment_ends", "")
	s.term_ends_day = int(d.get("term_ends_day", -1))
	s.drill_level = int(d.get("drill_level", 0))
	s.status = int(d.get("status", Status.FIT))
	s.battles = int(d.get("battles", 0))
	s.recovery_days = int(d.get("recovery_days", 0))
	s.traits.assign(d.get("traits", []))
	return s
