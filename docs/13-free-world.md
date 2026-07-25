# 13 — The Free World: streets, stealth, and the space between battles

Status: **v1 SHIPPED as a playable spike** (`--scenario` equivalent:
`scenes/world.tscn`, `--world=boston_1775`). This document is both the
design and the honest account of what exists versus what is promised.

Directive: *"gameplay akin to Assassin's Creed, both inside and outside
the historically-accurate battles — free-world movement, stealth
tactics, and the like."*

## 1. The thesis, and the one line we won't cross

Assassin's Creed's real invention was not the hidden blade — it was
**an inhabited historical city you move through under observation**.
That is exactly what this game wants for the space between battles:
Boston under occupation, where walking down the wrong street at the
wrong hour is itself a mechanic.

What we take: free movement through a real city, patrols with actual
attention, blending into crowds, tailing and eavesdropping, the tension
of being *nearly* seen, and missions that are about arriving rather
than killing.

What we don't take: the fantasy. No hidden blades, no secret orders, no
climbing the Old North Church because it's tall. This game's stealth is
the historical article — Revere's "mechanics" walking patrol to watch
troop movements, Warren's couriers slipping out on the night of the
18th, the Culper ring's dead drops. That material is *better* than the
invented version, and it's free.

## 2. What is built (v1)

`src/world/world_sim.gd` — deterministic, fixed-tick, CommandBus-driven,
same contract as the battle sim (docs/07). It is not a character
controller bolted onto a renderer; it is a simulation the renderer
watches, which is what keeps replays, headless tests, and future co-op
possible.

- **Movement**: walk / run / crouch, camera-relative, integrated by the
  sim from commanded intent. Buildings are solid.
- **Watchers**: patrols, sentries, and piquets with waypoint beats,
  pauses at corners, facing, and a cone of attention.
- **Being seen** is a continuous quantity, not a boolean:
  `visibility = distance falloff × cone position × line of sight ×
  stance × crowd cover`. Suspicion accrues at that rate and decays when
  the eye moves on.
- **Three states, not two**: CALM → CHALLENGED ("Who goes there? Stand
  and be recognized.") → ALERTED (he comes for you, and tells the
  others). The middle state is the whole game — it's the moment you
  still have choices.
- **Crowd blending**: knots of townsfolk cut visibility by up to 75%,
  strongest at the center. Streetlamps mark where *not* to walk.
- **Noise**: running carries 14 yards and turns heads outside the cone.
- **Seizure**: an alerted watcher within 2.2 yards ends the night in
  the guardhouse.
- **Mission**: `data/world/boston_1775.json` — "The Eighteenth of
  April." Warren's house → the sexton's door → two lanterns in the
  steeple → the boat in the North End, through four patrols. Data-
  driven exactly like cutscenes: blocks, crowds, beats, and objectives
  are all authored JSON, no engine code per mission.

CI covers: geometry validity (nothing spawns inside a house), the sight
model (cone, back-of-head, walls, crouch, running, blending), the
courier's run end-to-end, the failure case, and determinism.

## 3. What is promised but NOT built

Named honestly so the roadmap doesn't lie:

| Feature | Status | Note |
|---|---|---|
| Climbing / rooftops | **not built** | Period Boston is 2–3 storeys; rooftop traversal is a real design question, not a given. Wants a proper vertical-space pass. |
| Tailing & eavesdropping | not built | The suspicion model already supports it: stay in a distance band behind a target without entering his cone. Cheap next step. |
| Pickpocket / dead drops | not built | The Culper ring's real tradecraft; better than lockpicking minigames. |
| Disguise (a coat, a pass) | not built | Historically potent — Gage's officers wore civilian clothes on the road to Concord. Would modulate cone entry rather than hide you. |
| Guards investigating a *last known position* | not built | Currently a hunting watcher beelines. Search behavior is the next fidelity step. |
| Persistent city between missions | not built | The hub (docs/03) is currently menu-driven. |
| The avatar inside BATTLES | not built | This is docs/12, and it's the bigger fish: the same avatar standing in the line he commands. |

## 4. Design rules learned building v1

1. **Stealth you can read is stealth you can play.** The cones are
   drawn on the ground and warm from amber to red as certainty builds.
   Hiding a stealth model behind a single "detected" icon makes the
   player feel cheated, not clever.
2. **The challenge state must be survivable.** Being noticed is not
   failure; it is a conversation with a clock. Everything interesting
   happens in that window.
3. **Cover must be legible from the world, not the HUD.** Crowds,
   walls, and lamplight — you should be able to plan a route by looking
   at the street.
4. **Tune the mission, not the model.** The v1 courier was walking the
   route untroubled; the fix was a genuinely attentive fixed sentry at
   the church (a man at a post *is* more watchful than a marching
   patrol) rather than making every eye in Boston sharper.

## 5. How this joins the battles

The connective tissue is docs/12 (the avatar). One man, one control
scheme, three contexts:

- **Free world** (built): he walks, hides, blends, arrives.
- **Battle, as a soldier** (docs/12 §3B): the same man in the line.
- **Battle, as an officer** (docs/12 §3A): the same man, and his
  presence steadies the company where he stands.

The sim contract is identical in all three — commands in, deterministic
state out — which is why the free-world spike took a day rather than a
month, and why co-op remains reachable.
