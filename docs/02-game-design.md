# 02 — Game Design

## Core loop

```
CAMPAIGN MAP (historical timeline)
   └─> BRIEFING (historical context, muster, loadout, formation plan)
         └─> MISSION (authored battlefield, 15–40 min)
               │   fight / command / adapt to dynamic events
               └─> AFTER-ACTION (butcher's bill, honors, loot, journal entry)
                     └─> ENCAMPMENT HUB (recruit, drill, heal, equip, morale)
                           └─> next mission on the timeline
```

One full act ends in **winter quarters** — an extended hub chapter with its
own systems (disease, supply, desertion, drilling) that transforms the
brigade before the next campaign season. This mirrors the real rhythm of
the war: armies fought in season and survived in winter.

## The player character

A created officer (name, colony, backstory pick) who begins as a lieutenant
of Massachusetts militia in April 1775. Rank advances at historical
promotion moments. Backstory choices (farmer, printer's apprentice,
merchant sailor, freed Black freeman, frontier rifleman) alter starting
stats, some dialogue, and how certain historical characters receive you —
never the historical events themselves.

## Moment-to-moment combat

Third-person, over-the-shoulder pulled back enough to read your line
(camera sits closer than a RTS, farther than a soulslike). The player
fights with musket + bayonet, officer's sword/spontoon, or rifle, and
issues brigade commands in real time.

### The black-powder rhythm

- **Muskets are devastating and slow.** A volley at 50 yards shreds a
  formation; a reload takes 15–20 real seconds (skill-reducible). This is
  the game's fundamental beat — the equivalent of a fighting game's meter.
- **Volley discipline.** Holding `Present` builds an accuracy/cohesion
  bonus as your line steadies ("don't fire until you see the whites of
  their eyes" is literally the mechanic — the longer you hold under
  approaching fire, the more devastating the release, and the more morale
  it costs your own men to stand and take it).
- **Two fire disciplines, no scripted cadence.** Companies fight as
  platoons with *independent* reload clocks. *Volley fire*: one
  commanded crash from every loaded platoon — maximum shock, then
  seconds of nakedness. *Fire at will*: platoons load and fire on their
  own jittered rhythm — a rolling crackle of continuous pressure,
  weaker per shot, smoke piling up fast. Switching between them
  mid-fight (and reading which the enemy is using by ear) is core play.
  The field's rhythm is emergent — reload clocks, nerve, and smoke —
  never an exchange of turns.
- **The bayonet decides.** Once volleys are spent, charges resolve in
  brutal, short melee. Militia break easily against bayonets (historically
  true and mechanically true); drilled Continentals post–Valley Forge
  hold. Melee is deliberate and weighty — no aerial combos.
- **Smoke is a system.** Powder smoke accumulates and drifts with wind,
  blocking line of sight for both AI and player. Sustained fire blinds the
  field; a breeze is tactical information.
- **Artillery and terrain.** Guns are crewed by your soldiers, are slow to
  move (Knox's problem), and dominate open ground. Stone walls, worm
  fences, woods, and earthworks matter the way they did at Concord,
  Bunker Hill, and Yorktown.

### Command layer (real-time, no pause in standard difficulty)

| Command | Effect |
|---|---|
| **Form line / column / skirmish / square** | Formation state machine; each has speed, frontage, vulnerability tradeoffs |
| **Present – Fire** | The volley system above; can stagger by platoon for rolling fire |
| **Fix bayonets / Charge** | Morale shock attack; costs cohesion, can rout enemies or your own line if mistimed |
| **Hold / Advance / Withdraw by ranks** | Positional orders; orderly withdrawal is a drilled skill your brigade must learn |
| **Rally** | Officer presence restores wavering units — you must physically ride/run to them, exposing yourself (officer casualties were enormous and the game should tempt you into the same risk) |

### Morale

Every unit tracks **cohesion**. Volleys received, casualties, flanks
turned, officers down, drums silenced — all drain it. Broken units rout;
routed *veterans* you fail to rally may desert permanently. Morale is also
the enemy's health bar in many missions: most 18th-century battles ended
when a line broke, not when it was annihilated, and missions are tuned so
breaking the enemy is usually the efficient win.

## The brigade (persistent army)

- Soldiers are **named individuals** (names sampled from period muster
  rolls, public domain) with traits, a skill track (Green → Drilled →
  Veteran → Old Guard), a wound/disease state, and an **enlistment date**.
- **Enlistments expire.** The December 1776 crisis — the army dissolving
  on January 1 — is a *system*: before Trenton you will beg men to stay
  six more weeks, exactly as Washington did, spending money, favors, or a
  speech check you'd better have the reputation to make.
- **Death is permanent; the muster roll remembers.** A memorial book in
  the hub lists every soldier lost, where, and when. This is the emotional
  ledger of the game.
- Companies specialize: line infantry, light infantry, riflemen (deadly,
  fragile, no bayonet — the Morgan tradeoff), artillery crews, dragoons
  (small, late-game).

## Encampment hub

Changes location by act/season — Cambridge (1775), Morristown (1777),
**Valley Forge (1777–78, the pivotal hub chapter)**, Newburgh (1782–83).
Hub verbs:

- **Recruit** (bounties cost hard money; the Continental dollar inflates
  across the war — prices in paper rise act by act, a real mechanic)
- **Drill** (von Steuben's program at Valley Forge is a questline that
  permanently upgrades formation-change speed and volley cohesion)
- **Provision** (food/clothing/shoes; scarcity events are scripted from
  the record — "no meat! no meat!" chant at Valley Forge)
- **Hospital** (wounds heal with time/risk; smallpox inoculation is a
  gamble Washington historically ordered — you choose it too)
- **Campfire** (character scenes, letters home, morale, the human layer)

## Difficulty & failure

- Missions based on American defeats have **historical objectives**:
  survive N minutes, hold the Old Post Road, get X% of your brigade to the
  Brooklyn ferry line. "Winning" is saving the army.
- Mission failure = retry (this is a game about an army, not a save-scummed
  officer), but *casualties from your best attempt are negotiable only by
  replaying*. Iron Brigade mode: no retries, the roll is the roll.
- No alternate history in the campaign. The counterfactual itch is served
  by **Skirmish mode** (see below).

## Skirmish mode (the roguelite valve)

The *Tears of Metal* run-structure lives here, explicitly fictional:
procedurally assembled engagements ("a foraging column is ambushed in the
Jerseys, winter 1777") using campaign-earned veterans, with run modifiers,
extraction stakes, and leaderboard-friendly scoring. This is also the
future co-op playground — 2–4 officers, one field, separate wings.

## Codex: the Field Journal

Every mission, character, and event unlocks journal entries that quote the
underlying sources — the relevant paragraph of a Washington letter, a line
from Joseph Plumb Martin, a loyalist's diary for the other side. History
UI rule: **the game never shows a fact the codex can't cite.**
