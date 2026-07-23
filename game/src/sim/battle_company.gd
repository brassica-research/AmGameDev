class_name BattleCompany
extends RefCounted
## A company on the field: the battle-instance wrapper around a
## persistent Brigade roster (docs/07: persistent army vs battle sim).
## Spatial state is 1D along the battle axis for M1 — the volley
## prototype needs range, not maneuver; lateral movement arrives with
## formations-as-shapes in M2.

enum State { STEADY, PRESENTING, CHARGING, MELEE, BROKEN, FLED, DESTROYED }
enum FireMode { VOLLEY, AT_WILL }

const ADVANCE_SPEED := 1.1    # yd/s — common step, ~75 paces/min
const WITHDRAW_SPEED := 0.8   # backward, still facing the enemy
const CHARGE_SPEED := 2.6
const ROUT_SPEED := 2.8       # fear is faster than orders
const MELEE_RANGE := 2.0
const CHARGE_FEAR_RANGE := 80.0   # where the incoming-bayonets shock lands
const MAX_HOLD_SECONDS := 5.0     # Present hold time for full steadiness bonus

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
var brigade: Brigade
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
