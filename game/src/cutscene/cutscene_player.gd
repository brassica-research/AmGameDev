class_name CutscenePlayer
extends Node
## Plays data-driven cinematic timelines from res://data/cutscenes/*.json
## (docs/05 "Production format", docs/07). Writers author scenes as JSON;
## this node schedules tracks against a scene clock. In-engine rendering
## only — cutscenes must flow into gameplay without a visual seam.
##
## Timeline shape:
##   { "id": "...", "title": "...", "sources": [...],
##     "events": [ {"t": 0.0, "track": "caption"|"camera"|"actor"|"audio"|"codex",
##                  ...track-specific fields } ] }
##
## `state_query` fields let a scene cast from live campaign state —
## e.g. the Yorktown surrender places the player's ACTUAL surviving
## soldiers in the American line (docs/05).

signal caption_shown(text: String, attribution: String)
signal codex_linked(entry_id: String)
signal finished(cutscene_id: String)

var _events: Array = []
var _cursor: int = 0
var _clock: float = 0.0
var _playing: bool = false
var _id: String = ""


func play_file(path: String) -> void:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("CutscenePlayer: cannot read %s" % path)
		return
	var data: Variant = JSON.parse_string(file.get_as_text())
	if data is not Dictionary:
		push_error("CutscenePlayer: %s is not a JSON object" % path)
		return
	_id = data.get("id", path)
	_events = data.get("events", [])
	_events.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("t", 0.0)) < float(b.get("t", 0.0)))
	_cursor = 0
	_clock = 0.0
	_playing = true


func _process(delta: float) -> void:
	if not _playing:
		return
	_clock += delta
	while _cursor < _events.size() and float(_events[_cursor].get("t", 0.0)) <= _clock:
		_dispatch(_events[_cursor])
		_cursor += 1
	if _cursor >= _events.size():
		_playing = false
		finished.emit(_id)


func _dispatch(event: Dictionary) -> void:
	match String(event.get("track", "")):
		"caption":
			caption_shown.emit(event.get("text", ""), event.get("attribution", ""))
		"codex":
			codex_linked.emit(event.get("entry", ""))
		"camera", "actor", "audio":
			# M2 work: camera rigs, actor cue graphs, audio events.
			pass
		_:
			push_warning("CutscenePlayer: unknown track in %s: %s" % [_id, event])
