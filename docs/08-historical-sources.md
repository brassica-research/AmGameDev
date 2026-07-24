# 08 — Historical Sources & Accuracy Workflow

The game's promise: **no fact on screen without a citation in the codex.**
This file is the working bibliography; every `data/**/*.json` object's
`sources[]` field should resolve to an entry here.

## Primary source repositories (free, digitized, citable)

| Source | What we use it for |
|---|---|
| **Founders Online** (founders.archives.gov, NARA) | Washington/Adams/Jefferson/Hamilton/Franklin/Madison correspondence — searchable, definitive texts for letters quoted in cutscenes (e.g., Washington to Laurens, Dec 23, 1777: "Starve, dissolve, or disperse") |
| **Library of Congress** — Washington Papers, Continental Congress Journals | Orders, muster documents, the Newburgh addresses |
| **Avalon Project** (Yale Law) | Declaration, Articles, treaties, Paris 1783 |
| **National Archives** — Revolutionary War pension files (M804) | Veterans' own accounts; goldmine for brigade-soldier biographies and Act III's "Home" chapter |
| **Joseph Plumb Martin**, *A Narrative of Some of the Adventures, Dangers and Sufferings of a Revolutionary Soldier* (1830) | The game's narrative voice; Fort Mifflin, Monmouth, Yorktown from the ranks |
| **Thomas Paine**, *Common Sense* (Jan 1776), *The American Crisis I* (Dec 19, 1776) | The Crisis cutscene text, verbatim |
| **Rex v. Preston / Rex v. Wemms trial records** (1770) | Boston Massacre scene built from testimony, including its contradictions |
| **Johann Ewald**, *Diary of the American War* | The enemy's honest eyes; Hessian codex entries |
| **Frederick Mackenzie / Lt. John Barker diaries** | British perspective on Apr 19, 1775 and Boston |
| **Baron von Steuben**, *Regulations for the Order and Discipline of the Troops of the United States* ("Blue Book," 1779) | Drill mechanics, animation reference, hub questline |
| **The 1764 Manual Exercise** | Pre-Valley Forge drill animation set |
| **George Washington's General Orders** (via Founders Online) | Password "Victory or Death" (Dec 25, 1776), smallpox inoculation order (Feb 1777), reading of the Crisis |
| **James Thacher**, *Military Journal* | Surgeon's-eye view; Yorktown surrender eyewitness detail |
| **Sarah Osborn's pension deposition** (1837) | Camp follower's Yorktown account ("It would not do for the men to fight and starve too") — anchors the followers' storyline |
| **Boston Gazette / Pennsylvania Evening Post / Rivington's Gazette** | Period voice for news arrivals — including the Loyalist press |
| **Peter Force**, *American Archives* | Powder Alarm, Leslie's Retreat, committee correspondence |

## Key secondary works (interpretation & synthesis)

- David Hackett Fischer — *Paul Revere's Ride*; *Washington's Crossing* (Acts I–II backbone)
- David McCullough — *1776*
- Rick Atkinson — *The British Are Coming*; *The Fate of the Day* (2019–, Revolution trilogy)
- Robert Middlekauff — *The Glorious Cause*
- John Buchanan — *The Road to Guilford Courthouse* (southern campaign)
- Lawrence Babits — *A Devil of a Whipping* (Cowpens, minute-by-minute — mission design source)
- Wayne Bodle — *The Valley Forge Winter* (against the myths, for the record)
- Ron Chernow — *Washington: A Life*
- Gary Nash — *The Unknown American Revolution*; Douglas Egerton — *Death or Liberty* (Black Americans' revolution)
- Colin Calloway — *The American Revolution in Indian Country* (Oriskany/Sullivan chapters)
- Maya Jasanoff — *Liberty's Exiles* (the Loyalist epilogue)
- Alan Taylor — *American Revolutions: A Continental History*
- Leonard Richards — *Shays's Rebellion: The American Revolution's Final Battle* (Act III)
- Holger Hoock — *Scars of Independence* (the war's violence, kept honest)
- Charles Royster — *A Revolutionary People at War* (the army's soul; Newburgh)

## Material & visual references

- Don Troiani, *Soldiers of the American Revolution* (uniforms/equipment)
- Trumbull, Peale, Gilbert Stuart portrait corpus (faces)
- Xavier della Gatta's Paoli & Germantown paintings (eyewitness-informed battle staging)
- William Faden's engraved battle maps, 1776–1784 (campaign UI style + terrain)
- Anne S. K. Brown Military Collection (Brown Univ., digitized uniforms)
- Park service HABS/HAERS surveys & LiDAR where public (battlefield terrain)
- Colonial Williamsburg / Fort Ticonderoga collections (objects, drill interpretation)

## Music sources

- Period fife & drum repertoire (Camus, *Military Music of the American Revolution*)
- William Billings, *The New-England Psalm-Singer* (1770) — "Chester"
- "The World Turned Upside Down" / "Yankee Doodle" traditions with their
  documented ironies (played *at* the Americans in 1775, *by* them in 1781)

## Accuracy workflow

1. **Claim → citation.** Every mission/codex/cutscene JSON carries
   `sources[]`; CI rejects uncited historical claims.
2. **Contradiction policy.** Where sources disagree (who fired first at
   Lexington; who shot Fraser), the game *shows the ambiguity* and the
   codex presents the competing accounts. Ambiguity honestly displayed
   beats false certainty.
3. **Myth flags.** Known myths (Betsy Ross's flag, the cherry tree,
   Pitcher-as-single-person) are either excluded or explicitly codex-
   labeled as legend. Molly Pitcher appears as *Mary Hays at Monmouth*,
   the documented core, with the legend discussed in her codex entry.
4. **Sensitivity review.** Slavery, Native nations, and loyalist
   suffering get dedicated review passes against the listed scholarship
   (Nash, Calloway, Jasanoff, Hoock) before any such content ships.
5. **Living document.** New claims → new entries here first, then data.
