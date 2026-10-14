# Forever probe: Glass Action Bars

What the live client does, measured with `Tools/GABProbe` (`/gabprobe help`). docs/PLAN.md's
Phase 0 questions; each answer decides a detail of the skin. Facts that hold for every addon go
to `C:\Projects\WoW\References\PORTING-TBC-TO-FOREVER.md` instead.

## How to run session 1

1. `pwsh Tools\deploy.ps1 -Probe` (the addon itself may stay disabled; the probe stands alone).
2. In game: `/console scriptErrors 1`, `/console taintLog 1`, `/reload`.
3. `/gabprobe regions` (every region of the action, stance and pet buttons, child frames
   included) and `/gabprobe levels`.
   The secret samples (question 3) read a slot that holds something: have at least one action on
   a bar, and play a character with a form or stance and one with a pet if you can. A family
   with nothing to read is logged "not sampled", which answers nothing; the question stays open
   for it.
4. `/gabprobe alpha on`, `/gabprobe hearth` (use the Hearthstone first if it is ready, so its
   cooldown runs), and optionally `/gabprobe driver`.
5. One trial per operation, so each count belongs to one cause: `/gabprobe trial <label>`, do
   that ONE thing, then `/gabprobe counts`. The trials:
   - `trial key` - press one action keybind once
   - `trial click` - click one action button once
   - `trial page` - page the main bar once (Shift+wheel or the arrows)
   - `trial editmode` - open Edit Mode, then close it
   - `trial hideart` - toggle "Hide Bar Art" on the main bar (and back in a second trial)
   - `trial form` - change form or stance once (druid / warrior / rogue stealth), if you can
   - `trial pet` - summon or dismiss a pet (warlock / hunter), if you can
   - `trial combat` - then fight something for a few seconds (more than one: the samples are
     taken 1 s in, and skipped if the fight is already over), pressing keybinds and swapping form
     or stance; the counts print when the fight ends
6. Exit the client fully. Send `WTF\Account\<account>\SavedVariables\GABProbe.lua` and
   `Logs\taint.log`.

## Session 2: the skin itself

Session 1 measures hook delivery and the probe's own experiments; it doesn't exercise the skin's
own changes (the pushed texture, the fonts, the glass frames). With the skin branch deployed and
enabled (`pwsh Tools\deploy.ps1 -Probe`), `/console taintLog 1`, repeat the trials above, then
the checklist in docs/PLAN.md's Verification. Send a screenshot of the bars and `Logs\taint.log`.

## Results

| # | Question | Answer | Build |
|---|---|---|---|
| 1 | Regions of the action, stance and pet buttons (names, sizes, layers) | **As the forever FrameXML declares them** (session 1, below): the skin's keys all exist on every family. | 70374 |
| 2 | Do the per-button hooks (`UpdateButtonArt`, `Update`, `SetButtonState`, `UpdateFlash`) fire on keybind presses, paging and form swaps? | open | |
| 3 | Can `HasAction(btn.action)` (and the stance / pet readers) be secret in combat? | Open. Out of combat, `HasAction` and `C_ActionBar.HasAction` on an occupied slot are plain. Needs a fight longer than a second; stance and pet need a druid/warrior/rogue and a hunter/warlock. | 70374 |
| 4 | Frame levels: the cooldowns (`useParentLevel`) against a child at button + 1 | **The rim sits over the cooldowns, under the text**: ActionButton1 at 52, its cooldowns at 52 (`useParentLevel`), our body at 51 and rim at 53, `TextOverlayContainer` at 500. Stance/pet: button 72, body 71, rim 73. | 70374 |
| 5 | Does `SetAlpha` on a bar work in combat (bar fade)? | open | |
| 6 | Hearthstone: does its use spell's `GetSpellCooldownDuration` give a clean swipe in combat? | open | |
| 7 | Taint: anything blamed on GABProbe in taint.log? | open | |
| 8 | (optional) Do attribute and state drivers work? (porting guide vs Bartender4) | open | |

## Session 1 (2026-10-14, 70374): regions

`/gabprobe regions`, with the skin loaded (its frames show as `<frame>`).

- **Action button (ActionButton1, 45x45, level 52):**
  - Regions: `icon` (45x45, BACKGROUND), `IconMask` (MaskTexture), `SlotBackground` and `SlotArt` (alpha 0: the skin's fades), `Flash`, `Name`, `Border`, `NewActionTexture`, `SpellHighlightTexture`, `LevelLinkLockIcon`, `NormalTexture` (atlas `UI-HUD-ActionBar-IconFrame-AddRow`, 51x51: the hide-bar-art art; alpha 0), `PushedTexture` (45x45: ours), `HighlightTexture` (0.4: ours), `CheckedTexture`, `QuickKeybindHighlightTexture`, `BorderShadow`, `Arrow` (flyout).
  - Child frames: `TextOverlayContainer` (level 500: `HotKey`, `Count`), `AutoCastOverlay`, `cooldown` / `lossOfControlCooldown` / `chargeCooldown` (level 52), `InterruptDisplay`, `SpellCastAnimFrame`, `TargetReticleAnimFrame`, `CooldownFlash`, each with its own textures (all hidden at rest).
- **Stance and pet (30x30, level 72):** the same keys. The small template sizes its overlays 31.6x30.9 and its `NormalTexture` 35x35. The pet's `SpellHighlightTexture` is `bags-newitem`; the template's original `SpellHighlightTexture` stays as an unkeyed region.
- **Ours, as built:**
  - body frame one level under, holding shadow (alpha 0), mask, tint, grain (alpha 0) and wash;
  - rim frame one level over, holding the dark line and `ButtonRim`: 0.85 on a filled slot, 0.64 on an empty one (0.85 x 0.75);
  - the LibGlass edge, hidden.
- **Another addon's frame on the button:** ActionButton1 carries `__fcaBorder`, a frame at level 60 with top/bottom/left/right textures. Its name points to ForeverCombatAssistant, which writes that field onto Blizzard's button. It isn't ours, but it is the kind of field write the porting guide warns taints the button. Worth a look in that addon.
