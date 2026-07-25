class_name BattleCompany
extends RefCounted
## A company on the field: the battle-instance wrapper around a
## persistent Brigade roster (docs/07: persistent army vs battle sim).
## Spatial state is 1D along the battle axis for M1 — the volley
## prototype needs range, not maneuver; lateral movement arrives with
## formations-as-shapes in M2.

enum State { STEADY, PRESENTING, CHARGING, MELEE, BROKEN, FLED, DESTROYED }
enum FireMode { VOLLEY, AT_WILL }

## Pacing pass #1 (first human playtest, Jul 2026): historical march
## rates read as frozen on screen. Speeds sit ~40% above drill-manual
## literalism — the rhythm keeps its shape, the screen keeps moving.
const ADVANCE_SPEED := 1.6    # yd/s — brisk quick step
const WITHDRAW_SPEED := 1.2   # backward, still facing the enemy
const CHARGE_SPEED := 3.2
const ROUT_SPEED := 3.4       # fear is faster than orders
const MELEE_RANGE := 2.0
const CHARGE_FEAR_RANGE := 80.0   # where the incoming-bayonets shock lands
const MAX_HOLD_SECONDS := 5.0     # Present hold time for full steadiness bonus

## Close-combat scrum (playtest #2 directive): inside this range a
## charge stops being a formation event and becomes forty separate
## decisions — surge, pause to fire, or close with steel.
const SCRUM_RANGE := 25.0
const SCRUM_FILES := 20           # formation geometry mirrored from presentation
const SCRUM_FILE_SPACING := 0.75
const SCRUM_RANK_SPACING := 0.9
enum ManState { NONE, SURGE, FIRE_PAUSE, FIGHTING, REGROUP }

## The lockstep-breaker (docs/02 "two fire disciplines"): a company
## fights as PLATOON_COUNT platoons with INDEPENDENT reload clocks, so
## the field's rhythm is emergent, never a turn exchange. A commanded
## volley fires whichever platoons are loaded; fire-at-will lets each
## platoon shoot on its own jittered cadence.
const PLATOON_COUNT := 2
const PLATOON_NAMES := ["1st platoon", "2nd platoon"]
const AT_WILL_MAX_RANGE := 130.0
const AT_WILL_DISCIPLINE := 0.85  # unsynchronized aim costs accuracy

var id: String
var side: int                 # side 0 advances +y, side 1 advances -y
var lane: int = 0             # battle lane: companies engage their own lane first
var brigade: Brigade
## Scenario flags (night assault — docs/03 mission 2.12 "Bayonets Only"):
var bayonets_only := false    # muskets unloaded by written order; fire commands are ignored
var is_garrison := false      # defends in place; subject to the night surrender rule
var detect_range := 55.0      # sentry alertness: how close a silent column gets at night
var advance_speed := ADVANCE_SPEED  # light infantry columns move at the quick step
## Scenario flag (Lexington — docs/03 mission 1.5): the captain's standing
## order. While true, fire and charge commands are refused, not queued.
var hold_fire := false
## Seconds since last taking fire (counts down). A line being shot at
## does not regain its nerve — recovery is gated on this (capture 15).
var under_fire_s := 0.0
var pos_y: float = 0.0
var prev_pos_y: float = 0.0   # for render interpolation
var move_order: int = 0       # -1 withdraw, 0 halt, +1 advance
var state: int = State.STEADY
var fire_mode: int = FireMode.VOLLEY
var platoon_loaded: Array[bool] = [true, true]
var platoon_reload: Array[float] = [0.0, 0.0]
var platoon_ready_delay: Array[float] = [0.0, 0.0]  # fire-at-will jitter timers
var platoon_shots: Array[int] = [0, 0]
var platoon_first_fire_tick: Array[int] = [-1, -1]
var present_hold := 0.0
var rally_left := 0.0         # seconds of officer-rally recovery boost
var charge_feared := false    # this company's charge already shocked its target
var melee_accum := 0.0        # fractional melee casualties carried between ticks

## Per-man scrum state (sim-side, index-parallel to brigade.soldiers).
var scrum_active := false
var scrum_foe_id := ""
var scrum_shots := 0          # individual shots fired in the press
var man_x := PackedFloat32Array()
var man_y := PackedFloat32Array()
var man_prev_x := PackedFloat32Array()
var man_prev_y := PackedFloat32Array()
var man_state := PackedInt32Array()
var man_speed := PackedFloat32Array()
var man_timer := PackedFloat32Array()
var man_fired := PackedByteArray()


## Every man takes his formation slot as his starting point, then makes
## his own choice: the drilled lean toward steel, the raw toward one
## more shot; attackers surge harder than braced defenders. Bayonets-
## only companies (night storms) have no shot to give — all steel.
func enter_scrum(foe_id: String, attacker: bool, rng: RandomNumberGenerator) -> void:
	scrum_active = true
	scrum_foe_id = foe_id
	var n := brigade.soldiers.size()
	man_x.resize(n)
	man_y.resize(n)
	man_state.resize(n)
	man_speed.resize(n)
	man_timer.resize(n)
	man_fired.resize(n)
	for i in n:
		var file := i % SCRUM_FILES
		var rank := floori(float(i) / float(SCRUM_FILES))
		man_x[i] = (float(file) - float(SCRUM_FILES) / 2.0 + 0.5) * SCRUM_FILE_SPACING
		man_y[i] = pos_y - float(rank) * SCRUM_RANK_SPACING * facing()
		man_speed[i] = 2.4 + rng.randf() * 1.6  # every man runs his own pace
		var p_surge := 0.45 + 0.15 * float(drill()) + (0.0 if attacker else -0.2)
		if bayonets_only or rng.randf() < p_surge:
			man_state[i] = ManState.SURGE
			man_timer[i] = rng.randf() * 2.0  # the surge ripples, not a wall
		else:
			man_state[i] = ManState.FIRE_PAUSE
			man_timer[i] = 0.8 + rng.randf() * 3.0
		man_fired[i] = 0
	man_prev_x = man_x.duplicate()
	man_prev_y = man_y.duplicate()


func exit_scrum() -> void:
	scrum_active = false
	scrum_foe_id = ""


func slot_x(i: int) -> float:
	return (float(i % SCRUM_FILES) - float(SCRUM_FILES) / 2.0 + 0.5) * SCRUM_FILE_SPACING


func slot_y(i: int) -> float:
	return pos_y - float(floori(float(i) / float(SCRUM_FILES))) * SCRUM_RANK_SPACING * facing()


## The press is over but the men are scattered: every survivor jogs
## back to his slot, individually, on the ground the company now holds.
func begin_regroup() -> void:
	scrum_foe_id = ""
	for i in brigade.soldiers.size():
		if brigade.soldiers[i].status == SimSoldier.Status.FIT:
			man_state[i] = ManState.REGROUP


## A fresh enemy arrives while the men are still scattered: no neat
## re-entry — whoever has a loaded musket may snap a shot, the rest
## turn and meet the steel where they stand.
func re_engage(foe_id: String, rng: RandomNumberGenerator) -> void:
	scrum_foe_id = foe_id
	for i in brigade.soldiers.size():
		if brigade.soldiers[i].status != SimSoldier.Status.FIT:
			continue
		if bayonets_only or man_fired[i] == 1 or rng.randf() < 0.5 + 0.15 * float(drill()):
			man_state[i] = ManState.SURGE
			man_timer[i] = rng.randf()
		else:
			man_state[i] = ManState.FIRE_PAUSE
			man_timer[i] = 0.5 + rng.randf() * 2.0


func regrouped() -> bool:
	for i in brigade.soldiers.size():
		if brigade.soldiers[i].status != SimSoldier.Status.FIT:
			continue
		if absf(man_x[i] - slot_x(i)) > 0.7 or absf(man_y[i] - slot_y(i)) > 0.7:
			return false
	return true


func fighting_count() -> int:
	if not scrum_active:
		return 0
	var n := 0
	for i in brigade.soldiers.size():
		if brigade.soldiers[i].status == SimSoldier.Status.FIT and man_state[i] == ManState.FIGHTING:
			n += 1
	return n


func facing() -> float:
	return 1.0 if side == 0 else -1.0


func drill() -> int:
	return brigade.formation.drill


func effectives() -> int:
	return brigade.effectives()


func cohesion() -> float:
	return brigade.cohesion


func is_active() -> bool:
	return state != State.FLED and state != State.DESTROYED


func platoon_effectives(p: int) -> int:
	var total := effectives()
	var base := floori(float(total) / float(PLATOON_COUNT))
	return base + (1 if p < total % PLATOON_COUNT else 0)


func any_loaded() -> bool:
	for p in PLATOON_COUNT:
		if platoon_loaded[p]:
			return true
	return false


func all_loaded() -> bool:
	for p in PLATOON_COUNT:
		if not platoon_loaded[p]:
			return false
	return true


func fire_mode_name() -> String:
	return "VOLLEY" if fire_mode == FireMode.VOLLEY else "AT WILL"


## Steadiness bonus earned by holding Present under pressure —
## "don't fire until you see the whites of their eyes" (docs/02).
func hold_bonus() -> float:
	return VolleyModel.MAX_HOLD_BONUS * clampf(present_hold / MAX_HOLD_SECONDS, 0.0, 1.0)


## Bayonet confidence: militia historically broke against the bayonet;
## drilled troops held (docs/02). Scales melee damage dealt.
func bayonet_confidence() -> float:
	return 0.5 + 0.25 * float(drill())


func state_name() -> String:
	return ["STEADY", "PRESENTING", "CHARGING", "MELEE", "BROKEN", "FLED", "DESTROYED"][state]
