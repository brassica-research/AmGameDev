class_name CommandBus
extends RefCounted
## ALL mutations of the simulation enter as timestamped Commands —
## player input, AI decisions, and script triggers alike. This is the
## seam that makes co-op an add-on instead of a rewrite: in multiplayer,
## clients submit commands and the authoritative host drains them
## (docs/07-technical-design.md).

## Command shape: {tick: int, actor: String, verb: String, params: Dictionary}
## Verbs (docs/02): form_line, form_column, form_skirmish, form_square,
## present, fire, fix_bayonets, charge, hold, advance, withdraw, rally.

var _queue: Array[Dictionary] = []


func submit(tick: int, actor: String, verb: String, params: Dictionary = {}) -> void:
	_queue.append({"tick": tick, "actor": actor, "verb": verb, "params": params})


## Returns (and removes) every command scheduled for `tick` or earlier,
## in deterministic order (tick, then actor, then insertion).
func drain_through(tick: int) -> Array[Dictionary]:
	var due: Array[Dictionary] = []
	var remaining: Array[Dictionary] = []
	for cmd in _queue:
		if int(cmd["tick"]) <= tick:
			due.append(cmd)
		else:
			remaining.append(cmd)
	_queue = remaining
	due.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["tick"]) != int(b["tick"]):
			return int(a["tick"]) < int(b["tick"])
		return String(a["actor"]) < String(b["actor"]))
	return due
