# 07 — Technical Design

## Engine: Godot 4.4+ (recommended; decision open until vertical slice)

**Why Godot for this project:**
- Free/open-source, no revenue terms; ideal for a long exercise project.
- Text-based scenes/resources → clean git diffs, good for AI-assisted and
  collaborative iteration (this repo's workflow).
- Strong 3D since 4.x; `MultiMeshInstance3D` + GPU skinning handles
  hundreds of soldiers; volumetric fog covers the powder-smoke pillar.
- Built-in high-level multiplayer (ENet, scene replication) when we get
  to co-op — no engine switch needed.

**Honest alternatives:** Unreal 5 buys maximum photoreal fidelity
(Nanite/Lumen/MetaHuman) at the cost of C++ complexity, binary assets in
git (needs LFS/Perforce), and heavier iteration. Unity sits between.
**Recommendation:** prototype in Godot; revisit only if the vertical
slice hits a fidelity or crowd-scale wall. The design docs and all game
data (JSON) are engine-agnostic on purpose.

## Architecture: simulation core / presentation shell

The single most important structural decision, made now so co-op later
is an add-on, not a rewrite:

```
┌────────────────────────────────────────────────┐
│ PRESENTATION (Godot scenes)                    │
│  camera, animation, VFX/smoke, audio, UI       │
│  reads sim state; never mutates it directly    │
├────────────────────────────────────────────────┤
│ SIMULATION CORE (pure GDScript/C#, no nodes)   │
│  fixed 20 Hz tick · deterministic given        │
│  (seed, initial state, ordered command stream) │
│  units, formations, morale, ballistics, smoke  │
├────────────────────────────────────────────────┤
│ COMMAND BUS                                    │
│  ALL mutations enter as timestamped Commands   │
│  (player input, AI decisions, script triggers) │
└────────────────────────────────────────────────┘
```

- **Single-player:** local player feeds the command bus.
- **Co-op later:** host-authoritative server owns the sim; clients send
  commands, receive state deltas. Because *everything* already flows
  through the command bus, netcode wraps the bus rather than invading
  gameplay code.
- Determinism also gives us: replays (after-action review!), reliable
  bug repro, and headless CI simulation tests.

## Data-driven content (the historian/designer boundary)

All campaign content is JSON under `game/data/` — writers and researchers
edit data, not code:

| Path | Contents |
|---|---|
| `data/campaign/act*.json` | Mission list: id, date, place, type, objectives, forces, weather, `sources[]` |
| `data/units/*.json` | Unit archetypes: stats, drill level, equipment, morale profile |
| `data/characters/*.json` | Historical figures: bio, appearances, portrait ref, `sources[]` |
| `data/cutscenes/*.json` | Cutscene timelines: camera/actor/caption/audio tracks, codex links |
| `data/codex/*.json` | Field Journal entries with citations (every gameplay fact links here) |

**Schema rule:** every content object carries `sources[]`. CI fails a
content PR whose historical claims cite nothing (`tools/validate_data.py`,
to be added with the first content batch).

## Combat sim sketch

- **Soldiers** are sim entities (structs in arrays, not nodes); rendered
  via MultiMesh with a small pool of full-fidelity skeletal actors near
  the camera (LOD by proximity + narrative importance — named characters
  always full fidelity).
- **Formation** = ordered slots + state machine (line/column/skirmish/
  square/rout); soldiers steer to slots; cohesion is a scalar the whole
  design hangs on.
- **Volley model:** per-soldier hit rolls vs range/smoke/cohesion/drill,
  resolved on the tick the trigger falls — smoke then written back into
  a coarse grid that degrades everyone's accuracy. Historical fire
  effectiveness data (rounds per casualty) calibrates the tuning tables.
- **Morale:** event-driven drains (casualties/volley shock/flank/officer
  loss) vs regeneration (officer proximity, drums, cover, drill level),
  thresholds → waver → break → rout, rally hooks for the officer-presence
  mechanic.

## Cutscene system

`CutscenePlayer` consumes the JSON timeline format (tracks: camera,
actor, caption, audio, `codex_link`, `state_query`). `state_query` lets a
scene cast from live campaign state — e.g., the Yorktown surrender scene
places the player's actual surviving soldiers in the American line, and
burial vignettes pull real names from the muster roll.

## Persistence

Campaign save = muster roll + economy + timeline position + flags;
versioned JSON with migration shims. The muster roll is the sacred file —
back it up on every write (the game's whole emotional ledger lives there).

## Performance targets (vertical slice)

- 600 rendered soldiers @ 60 fps on a mid-range GPU (MultiMesh path)
- Sim tick ≤ 8 ms at 2,000 entities (headless benchmark in CI)
- Smoke: coarse sim grid (2 m cells) driving engine volumetric fog — the
  gameplay-affecting values live in the deterministic sim, visuals in
  the shell.

## Repository layout (`game/`)

```
game/
  project.godot
  scenes/          main.tscn (boot → hub/mission/cutscene routing)
  src/core/        game_state.gd, campaign_db.gd, command_bus.gd, sim_clock.gd
  src/combat/      sim entities: brigade.gd, formation.gd, soldier.gd, volley.gd, morale.gd
  src/cutscene/    cutscene_player.gd
  data/            campaign/ units/ characters/ cutscenes/ codex/
```

The scaffold committed with this document compiles conceptually against
this layout; scripts are annotated stubs establishing the contracts
above, ready to be fleshed out in the vertical slice milestone.
