class_name Formation
extends RefCounted
## Formation state machine (docs/02). A formation is ordered slots that
## soldiers steer toward; its shape trades speed, frontage, firepower,
## and vulnerability. Cohesion is the scalar the whole design hangs on.

enum Shape { LINE, COLUMN, SKIRMISH, SQUARE, ROUT }

## Drill quality gates which shapes a unit can take and how fast it
## changes shape. Valley Forge's von Steuben questline literally raises
## this (docs/02, docs/03 mission 2.H2).
enum Drill { MILITIA, DRILLED, REGULAR, VETERAN }

const DRILL_NAMES := ["Militia", "Drilled", "Regular", "Veteran"]

## Seconds to change formation shape, by drill level. Militia reforming
## under fire is where battles are lost.
const CHANGE_TIME := {
	Drill.MILITIA: 45.0,
	Drill.DRILLED: 25.0,
	Drill.REGULAR: 15.0,
	Drill.VETERAN: 10.0,
}

## Reload time in seconds by drill level (docs/02: the fundamental
## rhythm of combat). Historical prime-and-load ran 15–20s for trained
## troops at 3–4 rounds/minute in ideal drill conditions.
const RELOAD_TIME := {
	Drill.MILITIA: 24.0,
	Drill.DRILLED: 20.0,
	Drill.REGULAR: 16.0,
	Drill.VETERAN: 14.0,
}

var shape: int = Shape.LINE
var drill: int = Drill.MILITIA


static func can_form_square(drill_level: int) -> bool:
	# Forming square under cavalry threat is beyond untrained militia.
	return drill_level >= Drill.DRILLED
