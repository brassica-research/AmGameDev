class_name MoraleModel
extends RefCounted
## Cohesion drains and recovery (docs/02). Most 18th-century battles
## ended when a line broke, not when it was annihilated; morale is the
## real health bar and missions are tuned so breaking the enemy is the
## efficient win.

enum Event {
	VOLLEY_RECEIVED,     # the shock of a synchronized volley, beyond raw losses
	PLATOON_VOLLEY_RECEIVED,  # rolling fire-at-will: steadier drip, less crash
	CASUALTY,            # per man down, weighted by proximity/veterancy
	FLANK_TURNED,
	OFFICER_DOWN,
	DRUMS_SILENCED,
	BAYONET_CHARGE_INCOMING,
	FRIEND_ROUTED,       # contagion: watching another unit break
	NIGHT_ALARM,         # jolted awake: a silent column is already inside musket range
}

const DRAIN := {
	Event.VOLLEY_RECEIVED: 0.06,
	Event.PLATOON_VOLLEY_RECEIVED: 0.035,
	Event.CASUALTY: 0.015,
	Event.FLANK_TURNED: 0.20,
	Event.OFFICER_DOWN: 0.12,
	Event.DRUMS_SILENCED: 0.05,
	Event.BAYONET_CHARGE_INCOMING: 0.15,
	Event.FRIEND_ROUTED: 0.10,
	Event.NIGHT_ALARM: 0.15,
}

## Below WAVER units obey slowly and fire raggedly; below BREAK they rout.
const WAVER_THRESHOLD := 0.45
const BREAK_THRESHOLD := 0.25

## The butcher's-bill shock: losing men drains nerve in PROPORTION to
## how many stood beside you. Capture 15 finding (Lexington film): the
## flat per-man drip let 38 militiamen stand to the last two at full
## cohesion. Losing 5 of 38 in one exchange should shake a green
## company toward WAVER on its own; the same 5 out of a full battalion
## barely registers.
const CASUALTY_SHOCK_SCALE := 1.4

static func casualty_shock(count: int, effectives_before: int, drill_level: int) -> float:
	if count <= 0 or effectives_before <= 0:
		return 0.0
	return CASUALTY_SHOCK_SCALE * float(count) / float(effectives_before) \
		* (1.0 - 0.15 * float(drill_level))


## Drill dampens shock: veterans have seen it before.
static func drain_for(event: int, drill_level: int) -> float:
	var base: float = DRAIN.get(event, 0.0)
	return base * (1.0 - 0.15 * float(drill_level))


## Recovery per second from steadying influences (docs/02: the officer
## must physically GO to the wavering unit — presence is positional).
static func recovery_rate(officer_present: bool, drums_playing: bool,
		in_cover: bool, drill_level: int) -> float:
	var rate := 0.004 + 0.002 * float(drill_level)
	if officer_present:
		rate += 0.02
	if drums_playing:
		rate += 0.005
	if in_cover:
		rate += 0.005
	return rate
