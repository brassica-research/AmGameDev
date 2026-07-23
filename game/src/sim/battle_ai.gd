class_name BattleAI
extends RefCounted
## A simple period-doctrine commander: advance to effective range, halt,
## work the Present-Fire cycle with a steady hold, and go in with the
## bayonet once volleys have done their work or the enemy wavers.
## Architecture note (docs/07): the AI has NO special powers — it issues
## the same commands through the same CommandBus as a human player.

const THINK_PERIOD := 10          # every 0.5 s of sim time
const ENGAGE_RANGE := 80.0
const MIN_HOLD := 2.0             # seconds of Present before giving Fire
const VOLLEYS_BEFORE_CHARGE := 3

var company_id: String


func _init(id: String) -> void:
	company_id = id


func think(sim: BattleSim) -> void:
	if sim.tick % THINK_PERIOD != 0:
		return
	var me := sim.get_company(company_id)
	if me == null or not me.is_active():
		return
	if me.state == BattleCompany.State.BROKEN:
		sim.bus.submit(sim.tick, company_id, "rally")
		return
	if me.state == BattleCompany.State.CHARGING or me.state == BattleCompany.State.MELEE:
		return
	var foe := sim.nearest_enemy(me)
	if foe == null:
		return
	var dist := absf(foe.pos_y - me.pos_y)

	var foe_shaken := foe.state == BattleCompany.State.BROKEN \
		or foe.cohesion() < MoraleModel.WAVER_THRESHOLD
	var volleys_spent := me.brigade.volleys_fired >= VOLLEYS_BEFORE_CHARGE and not me.loaded
	if (foe_shaken or volleys_spent) and dist < ENGAGE_RANGE * 1.5:
		sim.bus.submit(sim.tick, company_id, "charge")
		return

	if dist > ENGAGE_RANGE:
		if me.move_order != 1:
			sim.bus.submit(sim.tick, company_id, "advance")
		return

	if me.move_order != 0 and me.state != BattleCompany.State.PRESENTING:
		sim.bus.submit(sim.tick, company_id, "halt")
	if me.loaded:
		if me.state != BattleCompany.State.PRESENTING:
			sim.bus.submit(sim.tick, company_id, "present")
		elif me.present_hold >= MIN_HOLD:
			sim.bus.submit(sim.tick, company_id, "fire")
