# LET TYRANTS SHAKE (working title)

[![CI](https://github.com/brassica-research/AmGameDev/actions/workflows/ci.yml/badge.svg)](https://github.com/brassica-research/AmGameDev/actions/workflows/ci.yml)

A brigade-scale action game of the American Revolution — inspired by the
battalion hack-and-slash structure of *Tears of Metal*, but grounded,
realistic, and built on the historical record.

You fight as one soldier *and* command as one officer. Your brigade is made
of persistent, named soldiers who march with you from Lexington Green to
Yorktown — and the ones you lose stay lost. Between campaigns, your winter
encampment (Cambridge, Morristown, Valley Forge, Newburgh) is the hub where
the army is rebuilt, drilled, fed, and held together.

**Design stance:** history is the spine. Battles the Continentals lost are
not "win anyway" missions — they are survival, delay, and extraction
missions (the night evacuation of Long Island is an extraction run). What
you control is *how much of your army survives history*, and the campaign
economy feels every casualty.

## Repository map

| Path | Contents |
|---|---|
| `docs/01-vision.md` | Vision, pillars, and what we take (and reject) from *Tears of Metal* |
| `docs/02-game-design.md` | Core loop, combat model, brigade & formation systems, campaign economy |
| `docs/03-campaign.md` | Full three-act campaign: every mission is a documented historical event |
| `docs/04-characters.md` | Historical character roster — playable commanders, allies, adversaries |
| `docs/05-cutscenes.md` | Cinematic philosophy + scripted treatments built on primary sources |
| `docs/06-art-audio-direction.md` | Realistic look & feel, painting/film references, period music |
| `docs/07-technical-design.md` | Engine choice, multiplayer-ready architecture, data-driven content |
| `docs/08-historical-sources.md` | Primary/secondary source bibliography and accuracy workflow |
| `docs/09-roadmap.md` | Milestones from vertical slice → full single-player → co-op |
| `docs/10-engine-evaluation.md` | Godot vs Unreal, weighed against current and expanded scope |
| `game/` | Godot 4 project scaffold (data-driven campaign, sim-core stubs) |

## Opening the project

The `game/` directory is a Godot **4.4+** project. Install Godot from
[godotengine.org](https://godotengine.org/download), open `game/project.godot`,
and run the main scene. Everything is text-based (`.tscn`, `.gd`, `.json`)
so the whole project diffs cleanly in git.

## Playing the M1 volley prototype

Press Play in the editor: the boot scene prints the campaign timeline,
then opens a grey-box battlefield — your Continental company against a
Crown regular company, 240 yards apart.

| Key | Order |
|---|---|
| `1` / `2` / `3` | Advance / Halt / Withdraw |
| **hold `SPACE`** | *Present* — the line steadies; the longer you hold, the harder the volley hits |
| **release `SPACE`** | **Fire** |
| `F` | Toggle volley fire ↔ fire at will (platoons fire on their own clocks) |
| `C` | Fix bayonets and charge |
| `R` | Rally (when your line wavers or breaks) |
| `V` | Toggle cinematic camera (the demo-capture director) |
| `M` | The memorial book — every soldier you have lost, by name |
| `ENTER` | Campaign: march again after the after-action report. Demos: restart |

The 15–20 second reload is the heart of the game — commit your volley
badly and the field belongs to the bayonet. The AI plays by the same
rules through the same command bus.

**Manual play is the campaign.** Pressing Play fights your persistent
company — forty named men with home towns, ages, and histories. The sim
wounds and kills the actual soldiers on your muster roll; the
after-action screen reads the butcher's bill by name; fourteen days in
camp let wounds mend (or not) while recruiting aims at forty men *fit
to stand* — though the company's books carry at most sixty names, so a
deep wounded list still starves the line; veterans' drill rises with
battles survived, so the company you lose men from is mechanically
worse tomorrow. When recovered men crowd past forty fit, the most
drilled take the field and the rest wait in reserve. Everything persists in
`user://muster_roll.json` (backed up on every write). There are no
mid-battle restarts in the campaign: the roll is the roll.

Demo scenarios (command-line, after `--`): `--scenario=field` for the
ephemeral meeting engagement, or `--scenario=night_assault` — the Stony
Point pattern, where you lead a bayonets-only column (your muskets are
unloaded by order and the fire keys will not save you) against a
garrison whose sentries are listening for you in the dark.

Headless test suite (same one CI runs):

```
godot --headless --path game --import
godot --headless --path game -s res://tests/run_tests.gd
```

## Status

Pre-production, milestone **M1** (see `docs/09-roadmap.md`).
Single-player campaign is the focus; the simulation core is deliberately
structured so 2–4 player co-op can be added later without a rewrite
(see `docs/07-technical-design.md`). Engine decision gates are defined
in `docs/10-engine-evaluation.md`.
