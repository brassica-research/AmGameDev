# 10 — Engine Evaluation: Godot 4 vs Unreal Engine 5

> **DECISION (July 2026):** Godot confirmed through M2. Re-evaluate only
> at the M2 exit gates below — "Godot it is until it isn't."

Requested after the scope conversation of July 2026. The question is no
longer just "brigade combat + hubs" — the concept may expand to include:

- **Estate/farm-building** (a plantation-era homestead economy layer)
- **Free-roaming Revolutionary-era towns** (Boston, Philadelphia, and
  smaller places as explorable spaces)
- **Conversational NPCs** delivering gameplay information and historical
  texture in natural dialogue

This document weighs both engines against the *original* scope and the
*expanded* scope separately, because the answer genuinely differs.

---

## Head-to-head

| Dimension | Godot 4 | Unreal 5 | Notes |
|---|---|---|---|
| **License cost** | $0, MIT, forever | Free until $1M gross revenue/product, then 5% royalty (waived for Epic Games Store sales) | For a hobby-to-indie trajectory both are effectively free; UE only costs money if we succeed |
| **Dev hardware** | Runs on a potato; editor ~100 MB | Wants a serious GPU + 16–32 GB RAM; install is tens of GB | Real cost if collaborators join |
| **Iteration speed** | Seconds — GDScript hot-reloads, tiny project loads instantly | Minutes — C++ compiles, shader compilation stalls, big editor | Iteration speed is where prototypes live or die |
| **Git & this workflow** | Everything is text (`.tscn`, `.gd`, `.tres`) — clean diffs, easy review, and *this AI-collaborative repo workflow works at full power* | Binary `.uasset`/`.umap`; needs Git LFS or Perforce; diffs are opaque; file-level merge conflicts are destructive | Worth saying plainly: the way we are building this game together — me writing reviewable text files you can diff — loses most of its leverage in UE |
| **Realistic environments** | Good: SDFGI, volumetric fog, decent PBR. "Painterly-realistic" (our stated art bar, doc 06) is achievable | State of the art: Nanite geometry, Lumen GI, free Megascans library — photoreal landscapes almost by default | If the bar drifts from "painterly-realistic" toward "photoreal," UE pulls ahead hard |
| **Realistic humans/faces** | Weakest point. Character fidelity is on us; close-up emotional faces are a major custom art lift | MetaHuman: film-grade rigged faces, free, with a full animation pipeline | Directly relevant to our cutscene ambitions (doc 05) — the spectacles scene is *made of* a face |
| **Cinematics tooling** | Basic AnimationPlayer tracks; our JSON cutscene system carries the load | Sequencer is the industry's best in-engine cinematic tool | Our data-driven cutscene design (doc 05/07) was chosen partly to be engine-portable |
| **Crowds (600+ soldiers)** | MultiMesh + custom LOD: very doable, we own the code | Mass Entity + Nanite skeletal meshes: bigger crowds, more built-in | Both pass our M1 bar; UE's ceiling is higher |
| **Open-world streaming** (towns, estates) | DIY chunking; no built-in world partition. Town-scale is fine; county-scale seamless is real engineering | World Partition, HLOD, level streaming — a solved, shipped problem | **The expanded scope's biggest technical differentiator** |
| **Period art content** | Small marketplace; mostly custom art | Fab marketplace + Megascans: colonial/18th-c. props, vegetation, buildings available off the shelf | A realistic Boston is mostly an *art cost* problem; UE's ecosystem shrinks it |
| **Building/economy systems** (estate layer) | Pure systems code — GDScript is excellent for this | Pure systems code — fine in C++/Blueprints | **Engine-neutral.** This layer is design + UI work wherever we build it |
| **Dialogue/NPC systems** | No first-class tool; Dialogic plugin or our own (we'd write our own — it must cite sources like everything else) | No first-class tool either; marketplace plugins or custom | **Engine-neutral.** The hard part is writing and historical sourcing, not tech |
| **Co-op netcode (2–4, PvE)** | High-level multiplayer API (ENet), adequate for host-authoritative co-op; our command-bus design does the heavy lifting | Best replication framework in the industry, proven at every scale | Both satisfy our co-op plan (doc 07); UE has more headroom we don't currently need |
| **Console ports later** | Third-party porting partners required (e.g., W4 Games); adds cost/time | First-class console pipelines | Only matters if/when we target consoles |
| **Hiring/community if team grows** | Growing fast, still smaller senior pool | Enormous professional talent pool | A "someday" consideration |
| **Engine risk** | Open source — can never be taken away or re-licensed out from under us | Epic's terms have been stable and generous, but they are Epic's terms | Philosophical more than practical |

---

## What the expanded scope actually demands

Breaking the new ideas into their real technical requirements:

1. **Estate/farm-building** → inventory, placement grid, production
   chains, seasonal calendar, labor economy. *Systems and UI code.*
   Engine-neutral; arguably easier to iterate in Godot. (Design note for
   later: an honest Revolutionary-era estate economy in the South
   includes enslaved labor — doc 08's sensitivity workflow applies
   before this feature is designed, not after.)
2. **Town free-roam** → streaming, LODs, lots of period architecture,
   crowd-of-civilians ambience. This is where UE's World Partition +
   Fab/Megascans materially reduce both engineering and art cost. In
   Godot, a *district-scale* town (a walkable half-mile of Boston, à la
   the Act I vignettes) is comfortable; a *seamless city + countryside*
   is a big custom engineering project.
3. **Conversational NPCs** → a dialogue runtime (we build it in either
   engine, JSON-driven like everything else, with `sources[]` on every
   historical tidbit), plus *faces good enough to carry conversation
   close-ups*. The runtime is neutral; the faces favor UE (MetaHuman) if
   we want filmic intimacy, and favor "handsome stylized-realistic" art
   direction if we stay in Godot.

## Cost summary (realistic, for this project's likely path)

| | Godot | Unreal |
|---|---|---|
| Cash outlay now | $0 | $0 |
| Cash at success | $0 | 5% of gross over $1M/product |
| Infra | GitHub free tier suffices | + Git LFS storage fees or a Perforce server; bigger CI runners |
| Your learning curve | GDScript is genuinely gentle | C++/Blueprint hybrid; bigger conceptual surface |
| Iteration tax | Near zero | Compile/build/import time on every loop |
| Art tax for realism | Higher (fewer ready assets, no MetaHuman) | Lower (Megascans, Fab, MetaHuman) |

## Recommendation

**Stay in Godot through M1 and M2, then decide at a defined gate.**

Reasoning:

- **M1 (the volley prototype) is engine-agnostic on purpose.** The sim
  core is pure logic + JSON data with a thin presentation shell (doc
  07). It is grey boxes; it would look identical in either engine. Every
  hour spent on M1 in Godot is preserved either way — the *design* is
  the deliverable, and the code translates.
- **M2 (vertical slice) is exactly when the deciding questions become
  answerable with evidence instead of speculation:** Can Godot hit our
  look on one real battlefield? Do cutscene faces at our art style carry
  the spectacles scene? Does a district of 1775 Boston stream acceptably?
- The expanded scope raises real UE arguments (streaming, MetaHuman,
  asset marketplace) — but it's still *maybe* scope. Committing to UE's
  workflow tax today for features we haven't designed yet is premature.

**Decision gates at M2 exit — move to Unreal if two or more fail in Godot:**

1. **Crowd gate:** 600 soldiers + smoke at 60 fps midrange GPU.
2. **Face gate:** a 20-second dialogue close-up at our art style that a
   playtester calls "moving," not "video-gamey."
3. **World gate:** a walkable, streamed district of Boston (Act I scale)
   with stable frame time.
4. **Ambition gate (yours, not technical):** if by M2 you *know* the
   estate/town/free-roam layer is core to the vision rather than an
   extension — count that as a failed gate and lean Unreal, because
   seamless-world scope is the one thing Godot makes genuinely expensive.

**If you already know today** that photoreal conversation scenes and a
seamless open world are non-negotiable pillars — then the honest answer
is to switch to Unreal now, while the codebase is one week old, and
accept the slower, binary-asset workflow (including significantly
reduced leverage from this repo's text-based collaboration). My read of
your message is that these are exciting *possible* extensions, not
settled pillars — which is exactly what the gate structure is for.

*Unity, for completeness: sits between the two on every axis, C# is
pleasant, HDRP is capable — but it offers neither Godot's workflow fit
nor Unreal's fidelity ceiling, and its licensing trust wobble in 2023–24
is the kind of risk neither alternative carries. Not recommended here.*

---

## Addendum: is there an open-source Unreal?

Short answer: **no — nothing open-source currently combines UE-class
fidelity with UE-class tooling and ecosystem.** The candidates, honestly:

| Engine | License | The pitch | Why it isn't the answer here |
|---|---|---|---|
| **O3DE** (Open 3D Engine) | Apache 2.0, Linux Foundation | The closest thing on paper: descended from Amazon Lumberyard (itself CryEngine lineage); modern high-end renderer (Atom), large-world ambitions, AAA DNA | Tooling maturity and editor stability well behind both UE *and* Godot; small community, thin docs and learning material, essentially no asset marketplace; corporate backing has visibly cooled since the 2021 launch. Adopting it trades Unreal's 5%-someday for a much larger risk today |
| **Stride** | MIT, C# | Solid mid-fidelity .NET engine, genuinely open | Small team/community; fidelity ceiling closer to Godot than Unreal, without Godot's momentum |
| **CryEngine** | Source-available, royalty | The original fidelity king | *Not* open source — license + 5% royalty; declining ecosystem |
| **Flax** | Source-available, royalty | "Small Unreal" ergonomics | *Not* open source — 4% royalty over $250k; small community |
| **Bevy** | MIT/Apache, Rust | Superb data-oriented architecture | No editor; code-first and young — wrong shape for a content-heavy historical game today |

The structural reason: Unreal's edge isn't just renderer code (which
open source can and does match in places) — it's the *decade of
integrated tooling* (Sequencer, World Partition, MetaHuman, Fab/
Megascans) and the army maintaining it. No open project has that
concentration of sustained investment; the one that comes closest in
investment terms is, in fact, **Godot** — it simply spends its budget
on breadth and usability rather than photoreal ceiling.

Practical conclusion, unchanged: Godot is the strongest open-source
choice and our home through M2. If we outgrow it at the gates, the
realistic moves are Unreal (accept the terms) or O3DE (accept frontier
life) — and we would choose with vertical-slice evidence in hand.
