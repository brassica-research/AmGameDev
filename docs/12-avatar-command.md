# 12 — The Avatar: commanding a company and being a man in it

Status: **DESIGN DRAFT, not scheduled.** Written from the directive
*"the player should be able to control the entire troop AND an
individual fighter — perhaps select their character and play them
through the campaign."* Nothing here is built yet; this document exists
so the idea can be argued with before code exists to defend.

## 1. Why this is the right instinct

The game already has two halves that don't talk to each other:

- The **company** is what you command (docs/02): volley discipline,
  the charge, the moment to fall back. It is where the tension lives.
- The **muster roll** is what you care about (docs/02, `roster.gd`):
  Ezekiel Whittemore, 19, of Menotomy, three battles, a scar. He dies
  and the memorial book remembers him. But you never *were* him.

An avatar closes the loop. The man you play is a name on the same roll,
subject to the same casualty tables. Command decisions become personal
because you are standing in the line you just ordered to hold. That is
the game's stated thesis — "history is the spine, your army is the
story" — with the camera lowered.

## 2. The load-bearing constraint

The sim is deterministic, fixed-tick, and command-driven (docs/07). An
avatar must NOT become an exception to that. The rule:

> **The avatar is a soldier the sim already simulates, whose per-tick
> intent comes from the player instead of from his company's orders.**

Concretely: no free-flying character controller writing straight into
world state. Avatar input becomes CommandBus commands (`avatar_move`,
`avatar_fire`, `avatar_bayonet`) stamped with the tick they were
issued on, resolved in the same deterministic order as everything else.
This keeps replays, headless tests, and future co-op intact — and co-op
is exactly where this feature pays off twice (one player commands, the
others fight in the ranks).

The scrum system (`battle_company.gd`) already simulates men
individually inside 25 yards: `man_x`, `man_y`, `man_state`, personal
speeds. **The avatar is that system, extended to the whole battle for
exactly one man.** That is much less new machinery than it sounds.

## 3. Three shapes it could take

### A. The Officer (recommended)
You are the company's officer. You stand in the line, you have a sword
and a pistol, and your *presence is positional* — the morale model
already assumes an officer is present everywhere (`recovery_rate`'s
`officer_present`); with an avatar it becomes true only where you
actually are. Walk to the wavering platoon and steady it. Lead the
charge from the front and the men follow faster; hang back and they
go in ragged.

- **Command feel:** unchanged — you still order the company.
- **New feel:** *where you are* is now a tactical decision.
- **Cost:** smallest. Morale already has the hooks. No new win
  conditions, no new failure states.
- **Risk:** low. An officer who fights too much dies, which is
  historically accurate and mechanically self-limiting.

### B. The Ranker
You are a private in the line. You load, present, fire on command —
your own command, if you're also the officer, which is the interesting
tension. Missing a volley because you fumbled a reload is the point.

- **New feel:** the volley becomes visceral rather than administrative.
- **Cost:** medium — needs a first-person-adjacent reload/fire loop
  that is fun on its own terms, which is a whole design problem.
- **Risk:** the two layers compete for attention. Commanding while
  reloading may simply be bad.

### C. The Character Campaign (the "select your character" reading)
You create or choose a man at the campaign's start — town, age, trade,
starting drill — and he is your body for the whole war. Promotion is
the progression: private → corporal → sergeant → ensign → captain, and
the *scope of what you command grows with rank*. Early missions you are
one musket in Parker's company; by Monmouth you command the company;
by the Newburgh chapter you are a field officer with a personal stake
in the mutiny.

- **This is the strongest version of the pitch** and it subsumes A and
  B: rank determines how much of the field you control.
- **Cost:** large, and it reaches into the campaign layer (promotion,
  save format, mission scoping, cutscene casting).
- **Risk:** permadeath vs. a 40-mission campaign. Needs an answer (see
  §5).

## 4. What each shape needs from the code

| Piece | A. Officer | B. Ranker | C. Character campaign |
|---|---|---|---|
| Avatar as a simulated man outside the scrum | ✅ | ✅ | ✅ |
| `avatar_*` commands on the bus | ✅ | ✅ | ✅ |
| Third-person follow camera + input rig | ✅ | ✅ | ✅ |
| Positional morale (officer presence by distance) | ✅ | — | ✅ |
| Personal fire/reload loop | — | ✅ | ✅ |
| Rank, promotion, command scope | — | — | ✅ |
| Character creation + save schema change | — | — | ✅ |
| Cutscene casting of the player character | — | — | ✅ |

The first three rows are common to all three and are the honest
prototype: **one man, sim-simulated, player-driven, on the existing
field.** Roughly a day's work to something playable, mostly camera and
input. Everything else is a branch point that can wait until the feel
of that day's build is known.

## 5. Open questions (the ones that need your answer, not mine)

1. **Death.** If your man dies in mission 12 of 40, what happens?
   Options: (a) you continue as the next-ranking survivor — brutal,
   thematically perfect, and it makes the muster roll the real
   protagonist; (b) wounded-not-killed for the player specifically —
   safe, slightly dishonest; (c) permadeath ends the campaign — Iron
   Brigade mode only.
   *My lean: (a) as the default, (c) as a difficulty option.*
2. **Scope of direct control.** Does the avatar ever control men
   directly (a squad, a platoon), or only the company through orders?
3. **First or third person?** Third person keeps the formation
   readable, which is the whole game. First person is more visceral
   and loses the picture. *My lean: third, with an optional shoulder
   camera at the present.*
4. **Multiplayer shape.** If co-op is officers-and-rankers, the avatar
   IS the netcode design. Worth deciding early even though M8 is far
   off.
5. **Does the avatar exist in cutscenes?** Casting the player's man in
   authored scenes is powerful and expensive; the alternative is that
   cutscenes stay historical-third-person and the avatar is a battle
   layer only.

## 6. Recommendation

Build the common core (§4, first three rows) as an unbranded spike
behind `--avatar`, on the Lexington field, with the officer variant's
positional morale as the one mechanic attached. Play it. The answers to
§5 will be much easier with a controller in hand, and nothing in the
spike is wasted for any of the three shapes.
