class_name SmokeGrid
extends RefCounted
## Powder smoke as a system (docs/01 pillar 2, docs/02). Coarse 1D grid
## along the battle axis: volleys deposit smoke at the firing line, it
## decays slowly, and accumulated smoke degrades everyone's accuracy.
## Gameplay-affecting values live here in the deterministic sim; the
## presentation shell renders its own pretty version from these cells.

const CELL_SIZE := 10.0    # yards per cell
const MIN_Y := -200.0
const CELL_COUNT := 40     # covers -200..+200 yards
const DECAY_PER_SECOND := 0.02   # ~35 s half-life — powder smoke lingers
const MAX_DENSITY := 1.5

var cells := PackedFloat32Array()


func _init() -> void:
	cells.resize(CELL_COUNT)  # zero-filled


func deposit(y: float, amount: float) -> void:
	var i := _index(y)
	cells[i] = minf(cells[i] + amount, MAX_DENSITY)


## Mean density over the cells between two positions (a firer and its
## target), clamped to the 0..1 range VolleyModel expects.
func sample_between(y1: float, y2: float) -> float:
	var a := _index(minf(y1, y2))
	var b := _index(maxf(y1, y2))
	var total := 0.0
	for i in range(a, b + 1):
		total += cells[i]
	return clampf(total / float(b - a + 1), 0.0, 1.0)


func step(dt: float) -> void:
	var keep := 1.0 - DECAY_PER_SECOND * dt
	for i in CELL_COUNT:
		var v := cells[i] * keep
		cells[i] = v if v > 0.001 else 0.0


func total() -> float:
	var t := 0.0
	for i in CELL_COUNT:
		t += cells[i]
	return t


func _index(y: float) -> int:
	return clampi(int((y - MIN_Y) / CELL_SIZE), 0, CELL_COUNT - 1)
