class_name Terrain
extends RefCounted
## Cover as terrain (docs/03 mission 1.5 "Battle Road"; the last open
## sim item from the M2 playtest directives). A field is a list of
## cover bands along the axis of advance — stone walls, rail fences,
## sunken roads. Standing in a band means lead finds you less often and
## your nerve steadies faster; it is also the thing worth withdrawing
## TO when a column comes on.
##
## Deterministic and Node-free like the rest of the sim core: cover is a
## pure function of position, so it costs nothing in the state hash.

const WALL_COVER := 0.60      # New England fieldstone: chest-high, solid
const FENCE_COVER := 0.35     # split rail: broken outline, no protection
const ROAD_COVER := 0.25      # a sunken roadbed or ditch
const COVER_HIT_SCALE := 0.55 # at full cover, fire is 55% less effective

## Each band: {"y_min", "y_max", "cover", "kind"}
var bands: Array[Dictionary] = []


func add(y_center: float, cover: float, kind := "wall", depth := 3.0) -> void:
	bands.append({
		"y_min": y_center - depth / 2.0,
		"y_max": y_center + depth / 2.0,
		"cover": cover,
		"kind": kind,
	})
	bands.sort_custom(func(a, b): return float(a["y_min"]) < float(b["y_min"]))


## How much cover a company standing at `y` enjoys. Overlapping bands
## don't stack — you are behind the best thing you're behind.
func cover_at(y: float) -> float:
	var best := 0.0
	for b in bands:
		if y >= float(b["y_min"]) and y <= float(b["y_max"]):
			best = maxf(best, float(b["cover"]))
	return best


func kind_at(y: float) -> String:
	for b in bands:
		if y >= float(b["y_min"]) and y <= float(b["y_max"]):
			return String(b["kind"])
	return ""


## The center of the nearest band, in any direction. INF if the field
## is open ground.
func nearest_cover(y: float) -> float:
	var best := INF
	var best_d := INF
	for b in bands:
		var c := (float(b["y_min"]) + float(b["y_max"])) / 2.0
		var d := absf(c - y)
		if d < best_d:
			best_d = d
			best = c
	return best


## The next band BEHIND a company — the one it falls back to. `facing`
## is +1 for a company advancing up-field, -1 for one advancing down,
## so "behind" is the opposite direction. INF when there is nothing
## left to fall back to and the next wall is the road itself.
func cover_behind(y: float, facing: float, min_gap := 6.0) -> float:
	var best := INF
	var best_d := INF
	for b in bands:
		var c := (float(b["y_min"]) + float(b["y_max"])) / 2.0
		var behind := (c - y) * -facing        # positive = to my rear
		if behind < min_gap:
			continue
		if behind < best_d:
			best_d = behind
			best = c
	return best


## Fire multiplier against a target standing at `y`.
func fire_multiplier(target_y: float) -> float:
	return 1.0 - cover_at(target_y) * COVER_HIT_SCALE


## The Battle Road (April 19, 1775, afternoon): sixteen miles of stone
## wall between Concord and Charlestown, and militia behind them.
static func battle_road() -> Terrain:
	var t := Terrain.new()
	t.add(-70.0, WALL_COVER, "wall")
	t.add(-24.0, WALL_COVER, "wall")
	t.add(18.0, FENCE_COVER, "fence")
	t.add(58.0, WALL_COVER, "wall")
	return t
