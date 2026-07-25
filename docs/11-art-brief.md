# 11 — Commissioned Art Brief (M2 → look-dev)

Status: DRAFT for the user to circulate to candidate artists/studios.
Owner decision pending: budget, headcount, timeline. This document is
the technical + creative contract either way; nothing in the game code
needs to change when real assets arrive (docs/07 — presentation swaps,
sim never notices; every procedural mesh is a placeholder honoring the
same contract).

## 1. What we are making (one paragraph for the artist)

*Let Tyrants Shake* is a brigade-scale action game of the American
Revolution: grounded, muted, sourced — Barry Lyndon and Turn, not
Assassin's Creed. The camera lives at 10–60 yards from ranks of
soldiers; the emotional register is restraint (docs/04, docs/06). Art
must read at formation distance first, portrait distance second, and
must never cartoon: real wool, real mud, real winter light.

## 2. Hard technical constraints

| Constraint | Value |
|---|---|
| Engine | Godot 4.4+, glTF 2.0 (.glb) delivery |
| Renderer floor | `gl_compatibility` (OpenGL 3.3) — no material may depend on Forward+ features; PBR metal/rough textures, no custom shaders required to read correctly |
| World scale | 1 unit = 1 yard. Standing soldier = **1.7 units** to hat crown, origin at feet, +Z facing |
| Rank-and-file budget | ≤ 6,000 tris, one 2048 atlas (albedo/normal/ORM), LOD1 ≤ 1,500 tris at 60 yds |
| Principals (cutscene) | ≤ 25,000 tris, 2× 2048 atlases, blendshape-free (we cut before faces need to act; captions carry the scene) |
| Buildings | ≤ 8,000 tris each, tiling trim sheets preferred, interiors not modeled (lit-window planes) |
| Skeleton | Godot Humanoid-compatible rig (Mixamo-retargetable). One shared rank-and-file skeleton; principals may extend fingers |
| Crowd rendering | Rank-and-file must ALSO ship as 4 baked static poses (march A/B, present, ram) for MultiMesh crowds — the battle draws 160+ men on 2015 laptops (GeForce 930MX is our floor) |

## 3. Priority list

### P0 — the battle reads (needed for M2 look-dev)
1. **Massachusetts militiaman, 1775** — civilian wool coat (drab browns,
   greys, one dark red), round hat / cocked hat mix, powder horn,
   hunting bag. 3 head + 3 coat-color variants off one atlas.
2. **British regular, 1775** — red regimental, white/buff facings
   variants (we field the 4th, 10th, 23rd), Brown Bess with bayonet,
   cartridge box, crossbelts, cocked hat.
3. **Continental regular, 1777** — blue regimental, buff facings,
   French musket acceptable.
4. **Animation set (shared rig)**: idle ×2 (cold weather shuffle),
   march, quick-step, present, fire (with full 12-step reload as ONE
   loopable sequence), bayonet charge run, melee ×3, fall ×4 (forward,
   back, crumple, dragged-linger), rout run, rally re-form.
5. **New England field kit**: stone walls (3 segments + corner),
   split-rail fences, bare oak/maple ×4, stack of arms, campfire.

### P1 — Boston & the campaign hub
6. Town buildings: meetinghouse, tavern, row house ×3, Custom House
   (brick), wharf pieces. Clapboard + brick trim sheets.
7. Civilians: townsman ×3, townswoman ×2, dockworker (for King Street
   and the vignettes) — same rig.
8. Officers: mounted + dismounted (Parker, Pitcairn stand-ins; named
   principals come later), horse (walk/canter/rear).
9. Camp: bell tents, marquee, muster table, colors (flag cloth sim
   baked to bones), drum, cook fires.

### P2 — principals & setpieces (M3+)
10. Named principals for cutscenes 2–6 (Washington, Adams, an
    Oneida warrior — see docs/08 §4 sensitivity review before briefing).
11. Artillery: 3- and 6-pounder + limber + crew poses.
12. Winter set: Valley Forge huts, snow variants of P0 kit.

## 4. Style bible pointers (full: docs/04)

- Palette: madder red (not scarlet), indigo blue (worn, not royal),
  drab, snow-grey, black powder smoke. Saturation ceiling ~70%.
- Wear: every uniform patched, faded at elbows/knees; militia shows
  more homespun than uniform. Nothing parade-fresh except British
  grenadiers in Act I (the contrast IS the story).
- Light: overcast New England, low winter sun, night = first-quarter
  moon + candle/muzzle sources only. Test every asset under
  `gl_compatibility` with our light rig (scene provided).
- NO: gore decals beyond docs/08 limits, caricature faces, fantasy
  proportions, clean teeth.

## 5. Delivery & acceptance

- GLB + source (.blend), textures as PNG, checked into
  `game/assets/commissioned/<pack>/` via PR — CI validates scale,
  naming (`snake_case`), tri budgets, and that every GLB imports
  headless in Godot 4.4 (validator script ships with the repo).
- Acceptance test per batch: dropped into the live scenes
  (`--scenario=field`, `--cutscene=king_street`) and filmed by the
  existing capture workflow; approval happens on the film, on the
  target-floor renderer, not on turntables.
- License: work-for-hire or exclusive perpetual; no marketplace
  resale of period-specific pieces.

## 6. Interim plan (already shipping)

Until commissioned assets land: procedural figures & buildings
(`src/presentation/figure_lib.gd`, `colonial_lib.gd`) hold the layout
contract, and CC0 packs (Kenney nature/props — see
`assets/manifest.json`) dress terrain and camps. Anything CC0 that
survives to look-dev gets re-skinned or replaced by P0/P1 work.
