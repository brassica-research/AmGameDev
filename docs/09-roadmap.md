# 09 — Roadmap

Single-player first; co-op designed-for now, built later. Milestones are
scoped so each one produces something *playable and judgeable*.

## M0 — Foundation (this commit)
- ✅ Design bible (docs 01–08)
- ✅ Godot project scaffold: sim-core architecture stubs, data-driven
  campaign format, sample mission/unit/character/cutscene data
- ✅ Working title: ***Let Tyrants Shake*** — the first line of William
  Billings' "Chester" (1770), the de facto anthem of New England's war.
  Period-accurate, and it ties the title directly to the score's Patriot
  hymn-motif (doc 06). Formal trademark check still due at M2.

## M1 — The Volley Prototype (grey-box, ~"find the fun") — IN PROGRESS
The entire game bets on one feeling: a disciplined volley under pressure.
Prove it in a grey-box field:
- ✅ Player officer's 40-man company vs AI company (`src/sim/`, `src/presentation/`)
- ✅ Present–Fire hold mechanic, reload rhythm, smoke grid, cohesion/morale,
  bayonet charge resolution, rout & rally (first-pass tuning values)
- ✅ Sim/presentation split + command bus working end-to-end (AI issues
  commands through the same bus as the player)
- ✅ Headless sim tests (determinism, morale, termination) + GitHub
  Actions CI (`game/tests/`, `.github/workflows/ci.yml`)
**Exit test: ✅ PASSED (July 2026).** First human playtest, after
patch #1 (order echo + pacing pass): *"the volley hold produces real
tension... a good first pass; refine as we go."* Design directive from
the same session: reduce formation rigidity — landed as the organic-
formations pass (disorder as a live signal of drill/cohesion/state).
Tuning knobs live in `volley.gd`, `morale.gd`, `formation.gd`.

## M2 — Vertical Slice: "Nineteenth of April"
Mission 1.5 (Lexington Green → North Bridge → Battle Road) at target
quality:
- Full art style proof (realistic look, smoke, natural light)
  - ✅ Form pass (playtest directive: "people and scenery should look
    like people and scenery"): procedural period figures — tricorn/
    round hat, coat skirts, crossbelts, shouldered musket, baked vertex
    colors, one draw call per company — plus colonial buildings (brick/
    clapboard, candlelit windows, snow-capped roofs, chimneys), textured
    ground, fences, bare trees, the moon (`src/presentation/figure_lib.gd`,
    `colonial_lib.gd`). Militia fight in brown coats and round hats;
    regulars in regimentals — drill is visible at a glance. Final art
    replaces these meshes at look-dev; call sites keep the contract.
  - ✅ Motion pass: figures POSE. A MultiMesh can't skin a skeleton, so
    each company builds a pose set (stand / march A / march B / present
    / fire / reload / charge) and every frame sorts each man into the
    bucket his sim state and his own gait phase call for — marching
    legs and counter-swinging arms, muskets coming down to the present,
    ramrods working in the platoon that just fired while the other
    stands ready, chargers leaning in with the bayonet level, routers
    facing away. Skin tones vary across the ranks (docs/08 §4: the
    Continental line was integrated, and should look it).
  - ✅ Weather + light as scene clock: per-scenario hour and sky
    (Lexington at first light with ground mist, the Battle Road through
    a high afternoon, Stony Point under a quarter moon), depth fog for
    atmospheric perspective, and RAIN — which is sim truth, not a
    filter: damp priming costs 45% of an aimed discharge and reloading
    runs a third slower (the Battle of the Clouds, Sept 1777, ruined
    400,000 cartridges and ended without a fight). `--weather=rain`.
- ✅ One authored cutscene ("King Street") through the JSON cutscene
  system — full trial-testimony script, data-driven grey-box staging
  (props/groups/snow from the scene JSON), camera/actor/caption cues
  streaming end-to-end, codex link firing. Final art replaces the
  boxes at look-dev; the JSON never changes.
- ✅ Muster roll v1 (landed early, during M1): named persistent
  soldiers with towns/ages/traits, permadeath into the memorial book,
  wound recovery, battle-earned veterancy that drives company drill,
  campaign save/load with backup, after-action butcher's bill, and a
  playable battle → camp → battle loop (`src/campaign/roster.gd`)
- ✅ Enlistment expiry v1 (also early): 60–120-day terms, the
  fortnight warning, the march-or-bounty choice at after-action,
  specie pay by battle outcome, and the mustered-out ledger — the
  December 1776 crisis as a system (docs/02)
- ✅ Camp screen v1 (also early): the encampment hub as a real scene —
  paged muster-roll review, fortnight postures (drill / forage / rest),
  the bounty decision, and the memorial book, between every battle
- ✅ Lexington Green opening action (mission 1.5, first beat): the
  scripted stand as sim — Parker's hold-fire order enforced through the
  CommandBus, the dispersal demand, the standoff clock that pauses
  while you withdraw, the shot no musket owns (`first_shot_tick`, never
  attributed), the regulars' discipline snapping, and both endings
  honest: disperse in time and every man walks off the Green; stand and
  take the volley. `--scenario=lexington`; both branches + determinism
  in CI. Still to come for the full slice: North Bridge, mission chaining.
- ✅ Terrain as cover + the Battle Road (mission 1.5, third act): cover
  bands along the axis of advance (`src/sim/terrain.gd`) — fieldstone
  walls, rail fences, sunken road — that cut incoming fire and steady
  nerve, drawn exactly where the sim scores them. Two new doctrines:
  `skirmish` (hold a wall, empty your musket, fall back to the next
  wall before the bayonets arrive) and `column_march` (the column's
  business is getting home). The column wins by reaching the far edge,
  not by holding the field. `--scenario=battle_road`.
- Field Journal codex with real citations end-to-end
- Sim-level individual movement (playtest directives): ✅ v1 landed as
  the close-combat scrum — inside 25 yds every man surges, fires, or
  fights at his own pace, sim-side and deterministic. ✅ v1.1: no
  stagnant victors — survivors re-form man-by-man on won ground, a
  fresh charge can catch them mid-re-form, and command (AI doctrine or
  the player) resumes only once the line is dressed. Still open:
  stragglers on the march, skirmish spread at range, individual rout
  paths, cover-seeking (needs the terrain system — walls, fences)
**Exit test:** a stranger plays 30 minutes and can describe the game's
identity ("realistic Revolution, you fight and command, your men are
mortal") unprompted.

## M3 — Act I complete
- Missions 1.0–1.6 + Cambridge hub; vignette systems (crowd, stealth,
  standoff); enlistment/recruitment economy v1
- First external playtest round

## M4 — Act II, chapters 1–3 (Boston → Valley Forge)
- Extraction mission tech (Long Island), winter attrition march,
  Trenton/Princeton, the detachment CHOICE system, Valley Forge hub
  with the von Steuben drill-upgrade questline
- Cutscenes 2 & 3 ("The Crisis," "The Naked and the Starving")

## M5 — Act II complete (Monmouth → Yorktown)
- Southern chapter paths, siege system (Yorktown parallels),
  night-assault missions, cutscene 4
- Command Moments mode v1 (Cowpens first — it's the best-documented
  tactical set-piece and the mode's proof of concept)

## M6 — Act III + full campaign alpha
- Newburgh/Shays vignette systems (influence/standoff), epilogue,
  cutscenes 5 & 6, memorial-book finale
- Full campaign playable start to finish; content freeze for tuning

## M7 — Single-player beta → release
- Difficulty modes (incl. Iron Brigade), accessibility (subtitles,
  colorblind-safe unit ID, remapping, arachnophobia-free by nature),
  localization prep (codex quote handling per-language is a real
  problem — plan early), performance pass

## M8 — Co-op (post-SP-release)
- Host-authoritative netcode wrapping the command bus (the architecture
  from 07 finally pays off)
- Skirmish mode as the co-op flagship: 2–4 officers, one field
- Command Moments co-op variants (one player as Morgan, others as line
  commanders at Cowpens)

## Standing risks

| Risk | Mitigation |
|---|---|
| Crowd rendering vs realism budget | M1 proves MultiMesh path before art investment; Godot→Unreal escape hatch documented in 07 |
| Historical-accuracy scope creep | The sources[] CI gate keeps claims honest; the codex absorbs depth so the game doesn't have to lecture |
| Tone (war gravity vs. game fun) | M1/M2 exit tests are explicitly about *feeling*; Act I structure front-loads restraint |
| Sensitive content (slavery, Native war, Shays) | Dedicated review pass per 08 §4 before ship |
| Title/trademark | Clear the name during M2 |
