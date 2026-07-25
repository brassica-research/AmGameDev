class_name VolleyModel
extends RefCounted
## The volley hit model (docs/02: "the volley is sacred"). Pure static
## math — deterministic given inputs — so it runs identically in
## headless tests, single-player, and a future authoritative server.
##
## Calibration note (docs/07): period fire-effectiveness studies put
## smoothbore musketry vs a formed line at very roughly 5–15% hits at
## 100 yards under battle conditions, rising steeply as range closes.
## These curves are tuned to "feels historically brutal," then checked
## against the rounds-per-casualty literature.

const BASE_HIT := 0.42          # point-blank, calm, drilled, clear air
const RANGE_FALLOFF := 0.0038   # per yard
const SMOKE_PENALTY := 0.5      # multiplier scale at full smoke
const MIN_HIT := 0.01

## Steadiness bonus for holding Present under approaching fire —
## "don't fire until you see the whites of their eyes" as a mechanic.
const MAX_HOLD_BONUS := 0.35


## `discipline` scales for fire order: 1.0 for a commanded volley,
## < 1.0 for independent fire-at-will (unsynchronized aim, docs/02).
## `cover_mult` is the target's terrain protection (Terrain.fire_multiplier):
## 1.0 in the open, lower behind a wall.
static func hit_probability(range_yards: float, smoke: float, cohesion: float,
		drill_level: int, hold_bonus: float = 0.0, discipline: float = 1.0,
		cover_mult: float = 1.0) -> float:
	var drill_factor: float = 0.55 + 0.15 * float(drill_level)  # MILITIA .55 → VETERAN 1.0
	var p := BASE_HIT - RANGE_FALLOFF * range_yards
	p *= drill_factor
	p *= clampf(cohesion, 0.2, 1.0)
	p *= 1.0 - clampf(smoke, 0.0, 1.0) * SMOKE_PENALTY
	p *= 1.0 + clampf(hold_bonus, 0.0, MAX_HOLD_BONUS)
	p *= discipline
	p *= clampf(cover_mult, 0.0, 1.0)
	return maxf(p, MIN_HIT)


## Resolve one fire order: `shooters` muskets firing at a formed target.
## Returns casualties inflicted.
static func resolve(shooters: int, range_yards: float, smoke: float,
		cohesion: float, drill_level: int, hold_bonus: float,
		rng: RandomNumberGenerator, discipline: float = 1.0,
		cover_mult: float = 1.0) -> int:
	var p := hit_probability(range_yards, smoke, cohesion, drill_level,
		hold_bonus, discipline, cover_mult)
	var hits := 0
	for i in shooters:
		if rng.randf() < p:
			hits += 1
	return hits
