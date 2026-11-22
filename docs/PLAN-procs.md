# Proc alerts: plan (#115)

## Context

The owner wants GAB's own proc alerts, so SpellActivationOverlay (SAO) can be removed (2026-11-21).
They are the two things SAO gives:
- **Overlays:** big textures around the middle of the screen while a proc is up.
- **Button glow:** Blizzard's proc ring on the action button of the spell to press.

Each is an option. The case that started it: a frost mage's Fingers of Frost shows SAO's overlay,
but Ice Lance never glows. SAO's Forever effect has no buttons.

Reference: `References\Addons\Combat\SpellActivationOverlay` (3.0.0-forever, **MIT**). Ported data
keeps SAO's copyright notice: a header in the data file and a third-party section in `LICENSE`.

Review: Codex (gpt-6.2-astra, high).
- **Round 1:** 1 blocker (the glow's `Show()` and its loop replay) and 6 should-fixes:
  - the target refresh;
  - the real page-change test;
  - one retargetable slot per button;
  - exact-stack composites;
  - Encounter-time configuration;
  - the three kinds of ids.

  Plus a nit (counters to PR 3, a small stub). All are folded in below.
- **Round 2:** no new blocker. Four should-fixes were folded in:
  - the slot key on `SetAuraSlotEnabled`, and re-enabling it;
  - the slot frame's anchor, and a real `OnHide` in the replay test;
  - an `Update` hook of `Procs.lua`'s own, since the skin's is absent with the skin off;
  - an explicit fallback rule.

  Plus a nit on wording.
- **Round 3:** one should-fix. The replay test still allowed the fade, which only sets alpha; it now
  needs a real `OnHide`.
- **Round 4:** no new defects; consensus.
- **PR #117's review (commit 8838e94):** two P2s, folded in:
  - every container's setup is spelled out (the engine's load, the unit, `SetEnabled(true)`), and
    Phase 0 adds a clean run with SAO disabled;
  - Eclipse's texture ships as a `.tga`, so deployment and the package check carry it.
- **Its follow-up (commit 1e5f3ad):** one P2, folded in: turning an option back on calls `Show()`
  as well as `SetEnabled(true)`, with an off -> on check in Phase 0.

## What was measured (docs/FOREVER-PROBE.md session 10, build 71037)

- **A proc buff can't be read in combat.**
  - `C_Secrets.GetSpellAuraSecrecy(400670)` (Fingers of Frost) is `2` (ContextuallySecret).
  - `GetPlayerAuraBySpellID` returned **a quiet nil** in every combat read while the buff was up.
  - `ShouldAurasBeSecret()` also turns true out of combat at a boss (the Encounter restriction).
  - So addon code can't decide that a proc is up. Any design that reads the aura fails exactly
    in the fights that matter.
- **Blizzard's aura engine can show it for us.**
  - A `CustomAuraContainerTemplate` container (`Blizzard_AuraContainer`) has a slot per aura
    (`AddAuraSlot`, `candidateFilters.includeSpellIDs`).
  - The engine shows the slot frame while the aura is up and hides it after, in combat. Anything
    parented to that frame comes and goes with it.
  - Over Ice Lance, a slot holding an `ActionButtonSpellAlertTemplate` frame lit with the proc and
    went out when the charges were spent. Nothing was blocked, and the button still clicked.
  - The slot's `IsShown()` is secret, and it throws in combat. The engine's decision stays its own.
- **Blizzard's own proc events stayed silent for Fingers of Frost.**
  - `SPELL_ACTIVATION_OVERLAY_SHOW` / `GLOW_*` never fired, and `IsSpellOverlayed` stayed false.
  - Only `SPELL_ACTIVATION_OVERLAY_HIDE` fired, with no spell.
  - Other spells and classes weren't measured, so this stays open (Phase 0).
- **Ids:** Ice Lance 400640 (rank 1) and **1240044 (rank 2, seen on the bars at level 34, run
  #591)**; `SkillLineAbility` lists 400640, 1240044-1240047 and 1312002. Deep Freeze 428739.
  `C_ActionBar.GetSpell(slot)` reads plain in combat.
- **The glow over the glass:** an addon-made `ActionButtonSpellAlertTemplate` frame at the button's
  level + 1 (the glass's level) and at + 5 both drew over the glass. We use + 5.

## What SAO does on Forever (3.0.0, the effect table)

- **41 effects across nine classes:**
  - **Aura effects:** a player buff or a target debuff, with stacks.
  - **Counter effects:** a reactive ability became usable.
  - **Six Revelation enchant buffs**, one per caster or hybrid class.
- **Its aura effects glow no button on Forever.** Only counters glow, by spell name. The
  frozen-target Ice Lance handler is off on Forever (`mage.lua:10`).
- **No execute-health effects and no native effects run on Forever.** Its combat-log handlers are
  off too.
- **Counters decide in addon code:** `C_Spell.IsSpellUsable` plus the cooldown
  (`variables/actionusable.lua`). Whether those read plain in combat on Forever is unmeasured.
- **Textures:** client fileDataIDs (`textures/texname.lua`). Eclipse is the one exception: SAO
  ships `Eclipse_Moon.blp`.

## Hard constraints (CLAUDE.md, the UI contract)

- **Button state lives in our side table.** The glow container is an addon-owned child frame of a
  Blizzard button, as LibGlass's body already is, keyed by button in a weak side table. No field is
  written onto a Blizzard frame, and no Blizzard method is replaced.
- **Containers and slots are built out of combat, and not at a boss.** A login in combat waits
  for the fight to end, as the skin does. A build or option change while a boss's Encounter
  restriction is on waits for it to lift too (Settings, below).
- **No aura read decides anything.** Overlays and aura glows are the engine's.
- **IDs, never names.** Glows match spell IDs, every rank listed in the data. Never match names (SAO
  matches by name).
- **Dependencies:** provider -> GAB only. GAB checks whether SAO is loaded
  (`C_AddOns.IsAddOnLoaded`). It doesn't depend on SAO.

## Design

### Files

`ProcData.lua` (data) and `Procs.lua` (engine), loaded after `Utility.lua` in the TOC.

### Data (`ProcData.lua`)

The data is GAB's own table, per class, Forever only, ported from SAO's effect table and checked in
game. One entry per effect:

```lua
{ key = "fingers_of_frost", kind = "aura", unit = "player", filter = "HELPFUL",
  auras = { 400670 },
  overlays = { { stacks = 1, texture = 449489, position = "LEFT" },
               { stacks = 2, texture = 449489, position = "RIGHT", hflip = true } },
  glow = { 400640, 1240044, 1240045, 1240046, 1240047, 1312002,   -- Ice Lance: every rank id
           428739 } }                                               -- Deep Freeze
```

- **`glow` is new data.** SAO has none for aura effects on Forever. Each glow pair is confirmed in
  game before it ships, starting with the mage, the owner's class.
- **Three kinds of ids, kept apart:**
  - `auras`: the filter's ids, every alias included. Mage's freeze filters on its debuff aliases,
    never SAO's display stand-in 5276 (`mage.lua:514-533`).
  - `glow`: the cast ranks that glow.
  - Display and label ids, if any.
- **Rank candidates** come from the build's DB2 rows (`SkillLineAbility` / `SpellName` through the
  `wago-tools` skill). Each is confirmed by the id the action slot actually returns. Names are never
  used at runtime. Not optional: run #591 had Ice Lance rank 2 on its bars, which SAO's table
  lacks, and nothing glowed. Round 3b logs `C_Spell.GetBaseSpell` and
  `C_SpellBook.FindBaseSpellByID` for each rank. If one maps every rank to rank 1 on this client,
  the data can hold the first rank and the button's spell is mapped once per retarget.
- **Textures:** a fileDataID, or a file GAB ships. Eclipse's `eclipse_moon.blp` (SAO's, MIT) is
  converted once to `Media/Eclipse_Moon.tga` (Pillow reads BLP), with a `Tools/` script like
  `make_lock.py`. `Tools/deploy.ps1` and the package check select `Media/*.tga` only, so a `.tga`
  is deployed and expected in the zip with no change to either. PR 2 checks the packaged zip lists
  it. Druid's Omen of Clarity keeps one texture in v1; SAO's per-form art needs a stance
  read, which is deferred.
- **Out of the data:** counter effects (PR 3) and Exorcism's creature-type check. Each effect is
  its own setting key, `procs.off[key] = true`.

### Every container: the probe's setup

Each container, overlay or glow, is set up as the probe's `containerGlow` was:
1. `C_AddOns.LoadAddOn("Blizzard_AuraContainer")` once, before the first `CreateFrame`. With SAO
   gone, nothing else may have loaded it; a refusal is recorded through `API.Fail` and the feature
   stays off.
2. `CreateFrame("AuraContainer", nil, parent, "CustomAuraContainerTemplate")`.
3. `SetUnit(unit)`, then `SetEnabled(true)`. A container starts disabled, and it registers its
   dynamic `UNIT_AURA` events only while enabled and visible
   (`Blizzard_AuraContainer.lua:157`), so a missing `SetEnabled` leaves it frozen.
4. Its slots, then `UpdateAllAuras()`.

Turning a feature off is `SetEnabled(false)` and `Hide()`, as the probe's teardown did. Turning it
back on reuses the containers: `Show()`, then `SetEnabled(true)`. Both are needed, since a hidden
container registers no `UNIT_AURA` even when enabled (`Blizzard_AuraContainer.lua:28`, `:157`).
`Show()` re-registers and refreshes (`OnShow_Intrinsic`), and so does `SetEnabled` on a change. A
unit test checks that an off -> on toggle leaves every container shown and enabled.

### Overlays: one screen container

- **One `AuraContainer` for the player** (`CustomAuraContainerTemplate`), under `UIParent` and
  centred. Target debuff effects (Mage's freeze, Shaman's Stormstrike debuff) get a second
  container with unit `target` and filter `HARMFUL` (`HARMFUL|PLAYER` for mine only).
- **One slot per (effect, overlay).**
  - Its frame holds the texture at SAO's geometry: long side 256 × 0.8, short side 128 × 0.8,
    times the scale option. Flips and rotations are `SetTexCoord`.
  - A slot that isn't stack-gated holds the texture directly, so it shows whenever the buff is up.
  - A stack-gated slot holds the texture inside its **application bar**: a StatusBar made in
    `initializeFrame` and handed over with `SetApplicationBar(bar, { minApplications = n,
    maxApplications = n })`, as SAO does (`components/auracontainer.lua:206-216`, with its own XML
    StatusBar). The engine shows the bar while stacks are at least n
    (`Blizzard_CustomAuraButton.lua:430`).
- **Stack rule:** the engine shows ">= n" only. It has no exact-count option on this path, and
  SAO's own Forever AuraContainer path has the same threshold. Where it matters, each slot keeps
  its overlay's own scale, tint, alpha and offset.
  - **Additive effects fit as they are.** Fingers of Frost at 2 stacks shows left and right.
  - **Effects that swap textures don't.** Heating Up 1/2/3 changes scale and tint, and Maelstrom
    1-5 changes texture. Their lower layers show through transparent pixels, so each is either
    shown as an accepted composite (checked in game at reduced opacity) or simplified to one
    overlay at its top stack. Heating Up's mock (run #591) was clean as a composite, and the owner
    couldn't tell it from the top layer alone, so it keeps the composite: stacks 1 and 2 still
    show.
  - **Eclipse** puts later stacks on the opposite side, so it's simplified, not composited.
  - The plan's data states which of the two each stacked effect gets.
- **Pulse:** SAO's scale loop (1.08 ↔ 0.926, 0.5 s each way) on the texture, per the effect's
  `pulse` flag.
- **Settings:** opacity, scale, offset from the centre.
- **Left out of v1:** the countdown shrink and number, and the out-of-combat dimming.

### Sound (v1, the owner's call, 2026-11-22)

- **The engine plays it:** `C_UnitAuras.AddAuraSound(trigger, { unitToken, spellID, soundFileID })`
  per aura id, on `Added` and on `ApplicationsIncreased`, as SAO does (`components/sound.lua`). No
  addon code decides when it plays, so it works on a secret aura.
- **The file is the game's own:** SoundKit 23287 (`UI_POWER_AURA_GENERIC`, SAO's sound) is file
  568016 in the build's `SoundKitEntry`, so GAB ships no `.ogg`. SAO passes the kit id as a file id
  outside Forever, and ships its own copy on Forever; the file id is what Phase 0 tests.
- **One registration per aura id** of an enabled effect, made when the overlays or glows are built
  and removed with `RemoveAuraSound` when they're turned off or the effect is unticked.
- **Setting:** `sound`, on by default (SAO's default), off with SAO loaded like the other two.
- **If the engine refuses** (a nil id, or a throw), it's recorded through `API.Fail` and the
  alerts go on silently. `AddAuraSound` is a restricted function (`HasRestrictions`), so its
  registrations and removals wait out the Encounter restriction with the containers.

### Button glow: one retargetable slot per button and unit

- **Which buttons:** Action Bars 1-8 (`ActionButton*`, `MultiBar*Button*`) while the glow option is
  on. Not stance, pet, bag or Utility buttons in v1.
- **The container:** `CreateFrame("AuraContainer", nil, button, "CustomAuraContainerTemplate")`.
  - `SetAllPoints(button)`, level + 5, `EnableMouse(false)`, built out of combat.
  - Unit player: **one slot**, `"glow"`. A class with target-debuff glows (freeze -> Ice Lance) gets
    a second container with unit `target`, also with one slot.
  - The slot's `initializeFrame`:
    - disables the mouse, hides the icon, and anchors the **slot frame** to the container
      (`ClearAllPoints`, `SetAllPoints(container)`);
    - puts an `ActionButtonSpellAlertTemplate` frame in it at 1.4 × the button, centred on the slot;
    - calls `Show()` on it (the template starts hidden), sets `animationPlaying = true` and plays
      `ProcLoop`. This is what the probe did (`GABProbe.lua`'s `containerGlow`).
  - **The loop's replay:** the XML wires both handlers to `OnHide`
    (`ActionButtonSpellAlerts.xml:34`), so `animationPlaying` alone doesn't prove the loop restarts.
    Phase 0 checks two procs in a row and an ancestor really hidden and shown mid-proc (Edit Mode,
    or a bar turned off and on; GAB's fade only sets alpha, so it fires no `OnHide`). If the loop doesn't
    restart, the engine's `AddAuraShownAnimation(g.ProcLoop)` is the next thing to try
    (`Blizzard_CustomAuraButton.lua:694`).
- **What the slot watches:** the button's spell, read through `C_ActionBar.GetSpell(button.action)`
  (plain in combat), on each button's `Update` (paging, drags, form changes).
  - `Procs.lua` installs its own `hooksecurefunc(b, "Update", ...)` while the glow is on.
  - It can't use the skin's hook: `Buttons.Start` returns before installing it when the skin is off
    (`Buttons.lua:307`).
  - The paging check runs once with the skin off.
  - The slot's `includeSpellIDs` is every enabled aura id whose effect glows that spell, aliases
    included, through `SetAuraSlotCandidateFilters`.
  - A spell nothing glows gets `SetAuraSlotEnabled("glow", false)`.
  - Back to a populated set, the filter is installed and `SetAuraSlotEnabled("glow", true)` called,
    even when the ids equal the last populated set.
  - Otherwise the last set written is cached per button, and an unchanged one isn't written again:
    both setters request a full rebuild even when nothing changed
    (`Blizzard_ManagedAuraContainer.lua:250`).
  - Several auras in one slot mean "any of them is up": `ExpirationOnly` picks the one shown, and
    the next takes over when it ends (`Blizzard_AuraContainerSlots.lua:177`).
  - So two buttons with the same spell both glow, and the glow fades with its own bar.
- **Cost:** a container with no enabled slot receives no `UNIT_AURA` updates
  (`Blizzard_ManagedAuraContainer.lua:128`; it still registers `AURA_DATA_PROVIDER_SWITCH`), and a changed aura walks only the enabled slots
  (`Blizzard_AuraContainerSlots.lua:112`). 96 containers don't mean 96 aura scans. Containers and
  slots are made once and reused across settings changes.
- **In combat:** both setters are public delegates with no combat guard in the Lua
  (`Blizzard_CustomAuraContainer.lua:452`). Whether the engine follows them mid-proc is Phase 0.
  **The decision rule:**
  - **The probe passes** (retargeting follows, the loop replays): every button retargets.
  - **Retargeting fails:** glows only on plain spells shown in game to stay bound through combat.
  - **That subset or the loop replay can't be verified:** v1 ships the screen overlays alone.
- **Target changes:** on `PLAYER_TARGET_CHANGED`, each `target` container gets `UpdateAllAuras()`
  on the next frame, as SAO does (`components/auracontainer.lua:408`). `SetUnit("target")` again
  does nothing, because the token is unchanged (`Blizzard_AuraContainer.lua:40`).
- **Faded bars:** the glow is a child of the button, so it fades with the bar (`Fade.lua`). A proc
  can't reveal the bar, since GAB can't see it. Documented, not worked around.
- **Theme:** Blizzard's own flipbook look. A glass-styled glow (LibGlass) is a later issue.

### Counter effects

They come only if PR 3's probe round shows `C_Spell.IsSpellUsable` and the cooldown read plain in combat for
those spells. They cover Overpower, Revenge, Victory Rush, Execute, Counterattack, Mongoose Bite,
Riposte, Hammer of Wrath, Holy Shock, Ice Barrier and Stormstrike.

If they do read plain, addon code decides, and the glow and overlay need an addon-driven path:
- **The glow:** the same `ActionButtonSpellAlertTemplate` frame, shown by GAB, on its own frame per
  button.
- **The overlay:** a plain texture frame.

If they don't, they are out, and Blizzard's own usable tint stays the only cue.

### Settings (`GlassActionBarsDB.procs`, only what the player set)

| key | default | |
|---|---|---|
| `overlays` | on | the screen overlays |
| `glow` | on | the button glow |
| `sound` | on | the proc sound |
| `opacity`, `scale`, `offset` | 1, 1, 0 | the overlays' look (radios: Options has no slider) |
| `off[effectKey]` | | an effect turned off |

**With SAO loaded,** both default to off, and the page says why. The player can still tick them.
Once SAO is gone, the defaults apply.
- **When it's decided:** at `PLAYER_LOGIN`.
- **What's saved:** `nil` (not set: the default applies), an explicit `true` and an explicit
  `false` stay distinct across reloads.

**Options:** a "Proc alerts" sub-page (`Options.AddPage`):
- the two checkboxes;
- the look radios;
- a checkbox per effect of the player's class.

A change rebuilds out of combat. In combat the rebuild is queued to `PLAYER_REGEN_ENABLED`.

**At a boss, changes wait (the owner, 2026-11-22).** `ShouldAurasBeSecret()` turns true before the
pull at a boss (session 10), and building there isn't measured. So everything that builds or
changes the alerts waits while
`C_RestrictedActions.IsAddOnRestrictionActive(Enum.AddOnRestrictionType.Encounter)` is true:
- a login or `/reload` at the boss;
- an option change: the two checkboxes, the sound, the look, an effect's checkbox;
- the sound registrations.

It's queued like a change in combat and applied at the `ADDON_RESTRICTION_STATE_CHANGED` that ends
the Encounter restriction, or at `PLAYER_REGEN_ENABLED` once neither is on. Until then, the
alerts already built keep working. The options page says the change waits for the encounter to
end. The rule costs little: it only matters to someone changing options at a boss. A button's
retarget on a page change isn't an option change: it follows Phase 0 item 1, measured in combat.

## Phase 0: measure before code (GABProbe round 3)

1. **A page change in combat, during one proc.** Ice Lance on a bar that pages, with a second copy
   on another bar. With Fingers of Frost up:
   - page away from Ice Lance and back, through `SetAuraSlotCandidateFilters` /
     `SetAuraSlotEnabled`;
   - check the old ring clears, both copies light, and a click casts the spell shown;
   - also a conditional macro (`C_ActionBar.GetSpell` on a macro slot). The form change needs a
     class with forms, so it's checked with PR 2's first class that has one (a mage has none).

   This decides the "in combat" fallback above. `AddAuraSlot` in combat isn't tried: no design
   needs it.
2. **The loop's replay:** two procs in a row, and during one proc a real hide and show of an
   ancestor (the probe hides and shows the bar frame out of combat, or the slot's container). GAB's
   fade doesn't count: it only sets alpha. The ring must animate again each time.
3. **A target-debuff glow.** A `target` container for Mage's freeze aliases over Ice Lance. Then:
   - frozen enemy -> unfrozen enemy -> no target, with `UpdateAllAuras()` on
     `PLAYER_TARGET_CHANGED`;
   - the cue must not survive the switch.
4. **Stack gating and composites.** On Fingers of Frost, an application bar with
   `minApplications = 2`: shown at 2, hidden at 1. A screen overlay slot at `LEFT` and `RIGHT`,
   with the flip. Heating Up's three layers as a static mock (plain textures at SAO's scales and
   greys, no aura: the owner plays frost), to choose between the composite and the simplification.
5. **At a boss before the pull** (the Encounter restriction, out of combat): a settings change that
   rebuilds the containers, with the blocked-action listener confirmed on. **Not needed for v1**
   (the owner, 2026-11-22): changes wait out the restriction instead (Settings, above). `procboss`
   runs whenever the owner is next at a boss; if it passes, the wait can go.
6. **A clean launch with SAO disabled.** SAO turned off in the AddOns list and a `/reload`, then
   the probe's containers alone: the engine's load result logged, and a proc seen to appear and
   clear on both an overlay and a ring. Rounds 1 and 2 ran with SAO loaded, which may have loaded
   the engine for us. Then both options off and on again, with no reload: the next proc must show
   the overlay and the ring again.
7. **Native events on other classes (passive).** A logger of `SPELL_ACTIVATION_OVERLAY_*` and
   `IsSpellOverlayed` across the owner's normal play on several classes (Codex on PR #116). If
   some spells do fire, Blizzard's own alert shows on those buttons. GAB then makes sure the glass
   doesn't cover it, and doesn't double it. Each class's result gates only that class's release; the
   mage slice goes ahead on the mage evidence.

8. **The sound:** `AddAuraSound` with file 568016 on Fingers of Frost, heard on each proc and on
   the second charge, in combat.

GABProbe's `procs3` runs items 1-4, 6 and 8 in one procedure; `procboss` is item 5, and item 7 is
counted per class from load while the probe is installed (`GABProbeDB.native`).

**Status after run #591** (docs/FOREVER-PROBE.md session 10, round 3): items 4 (stack gating, the
flip, Heating Up's mock), 6 (clean launch, off and on) and 8 (the sound) passed. Items 1, 2, 3 and
the ring half of 6 went unmeasured: the bars held Ice Lance rank 2, which the probe didn't know.
Item 7 so far: mage and warrior, `HIDE` with no spell only. Round 3b re-runs `procs3` with every
rank; item 5 waits for the owner's next boss and no longer gates the slice.

Counters are measured in PR 3's own probe round, not here. A readable cooldown table alone doesn't
make a working counter. That round tests, for each supported spell:
- `IsSpellUsable`'s two returns;
- the cooldown's `isActive` / `isOnGCD`;
- a reactive window seen opening and closing.

The probe is removed from the client when the findings are written (owner, 2026-11-21).

## Phases

- **PR 1, the mage slice:** `Procs.lua` (both containers, the glow, settings, the SAO default),
  `ProcData.lua` with the mage's Forever effects and the glow pairs confirmed, and the Options page.
  In-game check on the frost mage.
- **PR 2, the other classes:** their aura effects, glow pairs confirmed per class in play,
  Revelation.
- **PR 3, counters:** its own probe round first (above). They ship only if it allows them.
- **Later issues:** the countdown, a glass-styled glow, a proc revealing a faded bar if ever
  measurable, and the stance, pet and Utility buttons.

## Testing

- **The kit:** WowTestKit has no `CustomAuraContainerTemplate`. That is an issue on the kit, worked
  around meanwhile in `tests\wow_stubs.lua` (`-- WowTestKit #N:`).
  - The stub stays small: it records slots, their filters, their enabled state and the
    `UpdateAllAuras` calls.
  - That's enough to test GAB's decisions. Combat legality, animations and stack rendering belong
    to the live probe.
- **What the tests cover:**
  - containers built out of combat only, and queued from combat;
  - a build, an option change and the sound registrations queued while the Encounter restriction
    is on, and applied when it ends (and not before combat ends too);
  - each button's filter follows its spell through paging, and an unchanged filter isn't written
    again;
  - the target refresh;
  - nothing is written on Blizzard frames, and `WoW.violations` stays empty;
  - settings saved only when set, with `nil` / `true` / `false` kept apart;
  - the SAO default;
  - the data's shape (ids are numbers; a texture is a fileDataID or a shipped `Media/` path; known
    positions; no display stand-in in a filter).
- **Every new test is mutation-tested.**
- **In game:** a GABProbe procedure per PR. Then the probe is removed.

## Open questions for the owner

- ~~Sound on proc: v1, or later?~~ v1 (owner, 2026-11-22).
- Faded bars: is it acceptable that a proc glow fades with its bar?
