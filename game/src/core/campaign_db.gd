extends Node
## Autoload: read-only database of all campaign content, loaded from
## res://data/. Writers and researchers edit JSON, never code
## (docs/07-technical-design.md). Every content object carries a
## sources[] list resolving to docs/08-historical-sources.md.

const CAMPAIGN_DIR := "res://data/campaign"

var _missions: Array[Dictionary] = []
var _missions_by_id: Dictionary = {}


func _ready() -> void:
	_load_campaign()


func all_missions() -> Array[Dictionary]:
	return _missions


func get_mission(id: String) -> Dictionary:
	return _missions_by_id.get(id, {})


func _load_campaign() -> void:
	_missions.clear()
	_missions_by_id.clear()
	var dir := DirAccess.open(CAMPAIGN_DIR)
	if dir == null:
		push_error("CampaignDB: cannot open %s" % CAMPAIGN_DIR)
		return
	for file_name in dir.get_files():
		if not file_name.ends_with(".json"):
			continue
		var act: Dictionary = _read_json("%s/%s" % [CAMPAIGN_DIR, file_name])
		for mission: Dictionary in act.get("missions", []):
			if not mission.has("sources") or (mission["sources"] as Array).is_empty():
				push_warning("CampaignDB: mission '%s' has no sources[] — the codex rule says every fact cites" % mission.get("id", file_name))
			_missions.append(mission)
			_missions_by_id[mission.get("id", "")] = mission
	_missions.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a.get("date", "")) < String(b.get("date", "")))


func _read_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("CampaignDB: cannot read %s" % path)
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		return parsed
	push_error("CampaignDB: %s is not a JSON object" % path)
	return {}
