# 05 — Cinematics

## Philosophy

Tension in this period is *stillness before noise*: a line of men standing
in silence while another line walks toward them. Our cinematic language:

- **Natural light only.** Candle, hearth, overcast, muzzle flash (the
  *Barry Lyndon* discipline). Night scenes are actually dark.
- **Long takes, locked or slowly moving camera.** No shaky-cam, no speed
  ramps. The dread is in duration.
- **Documented words.** Where a scene has surviving text — a letter, an
  address, a memoir — the script uses it. Reconstructed dialogue is kept
  plain and minimal. Every scene ends with a codex link: *"What we know,
  and how we know it."*
- **Sound before image.** Drums, boots on frozen ground, the ramrod's
  ring, wind in tent canvas. Score is sparse; period instruments (fife,
  drum, fiddle) carry motifs stated first as *diegetic* camp music.
- **In-engine rendering** with the gameplay art style — cutscenes must
  flow into playable moments without a visual seam (see 06, 07).

## The six anchor cinematics

### 1. "King Street" — Boston Massacre (opens the game)
*March 5, 1770. Snow, moonlight, a lone sentry, a growing crowd.*
Built strictly from trial testimony (Rex v. Preston — the sources
disagree, and the scene honors that): we never show who said "Fire."
Bells ring "fire" into the night — the town thinks there's a blaze;
that ambiguity *is* the scene. Snowballs, oyster shells, a thrown club;
Private Montgomery slips, rises, fires. Seven seconds of smoke and
silence before anyone understands. Crispus Attucks dead in the snow.
End card: John Adams — who *defended the soldiers in court* — quoted:
"Facts are stubborn things." The game announces its ethic in scene one:
this will not be propaganda.

### 2. "The Crisis" — before the Delaware (Dec 23–25, 1776)
Campfires at McConkey's Ferry. An officer reads to ragged men, per
Washington's order, from a pamphlet printed four days earlier:
*"These are the times that try men's souls. The summer soldier and the
sunshine patriot will, in this crisis, shrink from the service of their
country..."* The camera never leaves the men's faces — frostbitten,
listening, deciding. It ends on the password chalked on a scrap of
paper: **Victory or Death**. Hard cut to black; the sound of ice on the
river; mission begins.

### 3. "The Naked and the Starving" — Valley Forge (Feb 1778)
Anchored to Washington's Dec 23, 1777 letter to Henry Laurens: *"...unless
some great and capital change suddenly takes place... this Army must
inevitably be reduced to one or other of these three things. Starve,
dissolve, or disperse."* Intercut: the letter being written by candle;
bloody footprints in snow (Washington's own reported image); the "No meat!
No meat!" chant rising like an owl-call through the huts (from Martin's
memoir and camp accounts). The scene turns on a hinge — von Steuben's
sleigh arriving through the same snow — and ends on 100 men drilling
where 100 men were dying. No music until the drill cadence *becomes* the
music.

### 4. "The World Turned Upside Down" — Yorktown surrender (Oct 19, 1781)
The long double line: French in white, Americans in rags and hunting
shirts facing them. The British march out, colors cased, drums beating a
British march. General O'Hara — Cornwallis pleads illness — offers his
sword to Rochambeau, who gestures across the road to Washington, who
indicates General Benjamin Lincoln (humiliated at Charleston a year
before). Protocol as drama: three silent gestures carrying the whole
meaning of the war. The player's own brigade is visible in the American
line — the actual soldiers from the player's muster roll, rendered in
their actual campaign-worn state.

### 5. "The Spectacles" — Newburgh (Mar 15, 1783)
The Temple hall, officers seething over an anonymous call to turn the
army on Congress. Washington enters unexpected, reads his address —
coldly received — then fumbles for a letter, and for his glasses, and
says (as recorded by multiple witnesses): *"Gentlemen, you will permit me
to put on my spectacles, for I have not only grown gray but almost blind
in the service of my country."* Officers who were ready to march on the
capital are weeping. The republic survives its most dangerous hour not by
a battle but by nine seconds of human frailty. This is the emotional
summit of the entire game, and it costs nothing to render but faces.

### 6. "The Return of the Sword" — Annapolis (Dec 23, 1783)
The Maryland State House. Washington, hands trembling (recorded by
witnesses — he steadied the page with both hands), returns his commission
to the civilian Congress: *"Having now finished the work assigned me, I
retire from the great theatre of Action."* Mifflin's reply. He leaves by
the door at once, mounts, and rides toward Mount Vernon to be home for
Christmas Eve. Coda card: George III's reported remark that if Washington
gave up power *"he will be the greatest man in the world."* He did.

## Systemic cinematics

- **Muster-roll vignettes.** Short, generated in-engine: a burial detail
  after a battle uses the *actual names and histories* of the player's
  dead. The game's most personal cinematics are procedurally cast but
  hand-authored in structure.
- **Journal transitions.** Between chapters, the PC's journal (Martin-style
  prose, reactive to the player's real casualties and choices) is read
  over engine dioramas of the coming ground.
- **News arrivals.** Fort Washington's fall, the French alliance,
  Charleston's surrender — each arrives as a courier scene in the hub,
  staged once, remembered forever.

## Production format

Cutscenes are data: a JSON timeline (`game/data/cutscenes/`) of camera
tracks, actor cues, captions, audio events, and codex links, played by
`CutscenePlayer`. Writers author scenes without touching engine code, and
scenes can reference live campaign state (muster roll, chosen path,
weather). See `07-technical-design.md`.
