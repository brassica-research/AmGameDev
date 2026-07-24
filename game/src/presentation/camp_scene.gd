extends Control
## The encampment hub, v1 (docs/02 "Encampment hub"), grey-box text UI.
## Between battles the player reviews the muster roll man by man, sets
## the company's posture for the fortnight, decides the bounty question,
## and breaks camp. The battle scene routes here after each after-action.
##
## KEYS
##   D drill the recruits · P send foraging parties · H rest and heal
##   B toggle re-enlistment bounty · M memorial book
##   UP/DOWN page through the muster roll · ENTER break camp and march

const ROWS_PER_PAGE := 14

var _posture := "rest"
var _bounty := false
var _show_memorial := false
var _page := 0
var _label: Label


func _ready() -> void:
	GameState.ensure_campaign()
	_label = Label.new()
	_label.position = Vector2(14.0, 10.0)
	add_child(_label)
	_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if event is not InputEventKey:
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return
	match key.keycode:
		KEY_D: _posture = "drill"
		KEY_P: _posture = "forage"
		KEY_H: _posture = "rest"
		KEY_B: _bounty = not _bounty
		KEY_M: _show_memorial = not _show_memorial
		KEY_UP: _page = maxi(0, _page - 1)
		KEY_DOWN: _page += 1
		KEY_ENTER:
			GameState.rest_and_refit(GameState.CAMP_DAYS, _bounty, _posture)
			get_tree().change_scene_to_file("res://scenes/battle.tscn")
			return
		_:
			return
	_refresh()


func _posture_row(key: String, id: String, text: String) -> String:
	return " %s [%s] %s" % [">" if _posture == id else " ", key, text]


func _refresh() -> void:
	var r: Roster = GameState.roster
	var lines: Array[String] = []
	lines.append("%s — IN CAMP, campaign day %d" % [r.company_name.to_upper(), r.day])
	lines.append("Pay chest: %d specie   |   battles fought: %d   |   memorial: %d   |   mustered out: %d" % [
		GameState.specie, GameState.battles_fought, r.memorial.size(), r.mustered_out.size()])
	lines.append("")

	# The muster roll, paged.
	var total := r.soldiers.size()
	var pages := maxi(1, ceili(float(total) / float(ROWS_PER_PAGE)))
	_page = clampi(_page, 0, pages - 1)
	lines.append("MUSTER ROLL — %d names (%d fit, %d wounded)   [UP/DOWN] page %d/%d" % [
		total, r.fit_count(), r.wounded_count(), _page + 1, pages])
	var start := _page * ROWS_PER_PAGE
	for i in range(start, mini(start + ROWS_PER_PAGE, total)):
		var s: SimSoldier = r.soldiers[i]
		var status := ""
		match s.status:
			SimSoldier.Status.WOUNDED:
				status = "  WOUNDED (%d days)" % s.recovery_days
			_:
				status = ""
		var term := ""
		if s.term_ends_day >= 0:
			var left := s.term_ends_day - r.day
			term = "  TERM UP" if left <= 0 else ("  term ends in %dd" % left if left <= 28 else "")
		var traits := "  (%s)" % ", ".join(s.traits) if not s.traits.is_empty() else ""
		lines.append("  %-22s %-12s %s, %d battles%s%s%s" % [
			s.display_name() + ",", s.home_town,
			Formation.DRILL_NAMES[s.drill_level], s.battles, status, term, traits])
	lines.append("")

	var expiring := r.expiring_by(r.day + GameState.CAMP_DAYS).size()
	if expiring > 0:
		lines.append("%d ENLISTMENTS COME DUE this camp." % expiring)
	lines.append("ORDERS FOR THE FORTNIGHT:")
	lines.append(_posture_row("D", "drill", "Drill the recruits — green men may reach the Drilled standard"))
	lines.append(_posture_row("P", "forage", "Send foraging parties — +%d specie, at some risk to the men" % GameState.FORAGE_PAY))
	lines.append(_posture_row("H", "rest", "Rest and heal — wounds mend twice as fast"))
	lines.append("   [B] Re-enlistment bounty: %s (%d specie a man who stays)" % [
		"OFFERED" if _bounty else "WITHHELD", GameState.BOUNTY_COST])
	lines.append("")
	lines.append("[ENTER] Break camp and march   [M] memorial book")

	if _show_memorial:
		lines.append("")
		lines.append("=== THE MEMORIAL BOOK — %d names ===" % r.memorial.size())
		for i in range(maxi(0, r.memorial.size() - 12), r.memorial.size()):
			var entry: Dictionary = r.memorial[i]
			lines.append("    %s %s of %s — %s" % [
				entry.get("given_name", "?"), entry.get("surname", "?"),
				entry.get("home_town", "?"), entry.get("fate", "?")])
		lines.append("Mustered out and gone home: %d" % r.mustered_out.size())

	_label.text = "\n".join(lines)
