class_name SimClock
extends RefCounted
## Fixed-tick accumulator for the deterministic simulation core.
## The sim advances at exactly TICK_HZ regardless of frame rate; the
## presentation layer interpolates between the last two sim states.
## Determinism (same seed + same command stream => same battle) buys
## replays, co-op netcode, and headless CI tests (docs/07).

const TICK_HZ := 20
const TICK_DT := 1.0 / float(TICK_HZ)

var tick: int = 0
var _accumulator: float = 0.0


## Call from _process(delta); invokes step_fn(tick) zero or more times.
func advance(delta: float, step_fn: Callable) -> void:
	_accumulator += delta
	while _accumulator >= TICK_DT:
		_accumulator -= TICK_DT
		tick += 1
		step_fn.call(tick)


## 0..1 fraction between the last tick and the next, for render interpolation.
func alpha() -> float:
	return _accumulator / TICK_DT
