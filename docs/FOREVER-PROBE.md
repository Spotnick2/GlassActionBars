# Forever probe: Glass Action Bars

What the live client does, measured with `Tools/GABProbe`. Sessions 1 and 2 used the standalone
probe (`/gabprobe help`, in git history before #32); from session 3 it is a ForeverProbe module
(`/fp gab`, procedures with `/fp steps gab <name>`). docs/PLAN.md's Phase 0 questions; each answer
decides a detail of the skin. Facts that hold for every addon go to
`C:\Projects\WoW\References\Docs\PORTING-TBC-TO-FOREVER.md` instead.

## Session 5: button feedback (#34), 2026-10-19, build 70450

`/fp steps gab look` on the owner's character, the Soft preset.
- **The halo:** its alpha reached 1 under the pointer (measured), a warm glow round the button in the
  screenshot; it faded in and out (owner: yes). Also on the stance/pet buttons and the Utility bar.
- **The ripple** on a mouse click: yes, out of combat and in a fight.
- **The flash on a key press:** seen on a spell with a cast time, not sure on an instant one. It is
  Blizzard's pushed state, shown only while the key is held, as without GAB; a key press has no
  signal an addon can hook here (session 1), so it stays as it is.
- **Key text above:** it worked, but on the owner's tightly stacked bars each row's numbers sat
  on the edge of the row above (the pet bar's over the pet frame's power bar), and long labels
  ("Mouse Button 4") ran into each other. The owner: revert it. The key-text settings (position,
  size) are gone; the key text stays where Blizzard puts it.
- **Empty slots:** faint showed as faint squares, but next to the reference (owner, 2026-10-19) the
  reference's empty slot is a pale neutral tile, ours a near-clear body with a rim. A new choice,
  **frosted** (a light grey fill at 16% in place of the theme's tint, the rim at 0.6), is Soft's.
- **A fight** with the halo, ripple and flash: nothing blocked (owner: yes; no `ADDON_ACTION_BLOCKED`
  in ForeverProbe's log for the run).
## Session 4: moving the stance and pet bars (#30), 2026-10-18, build 70450

`/fp steps gab barmove` (procedure rev 1) on the owner's hunter, pet out, GUF's link off. GAB's
own `Follow.lua` moved the bars by a made-up 120 with `ClearAllPointsBase` / `SetPointBase`; the
probe measured the bars' real left edges (UIParent units) by putting them back and moving them
again.

- **The pet bar moved cleanly.** Exactly +120.0, buttons and glass together (owner: yes).
- **No blocked action, no taint.** ForeverProbe's host log has no `ADDON_ACTION_BLOCKED` /
  `_FORBIDDEN` in the three sessions, and `taint.log` gained no line. In a fight the owner clicked
  pet buttons and pressed their key bindings: nothing blocked (owner: no), still +120 after it.
- **Edit Mode:** a layout edited and saved while following: the new place became the base and the
  bar followed from there (+120). Edited and discarded: back at the saved place + 120 (342.9588 vs
  342.9588). The first close was inconclusive (Done pressed 2.5 s after opening, likely before Edit
  Mode had closed); the two later closes take the same path and passed.
- **UI scale** changed (effective 0.64 -> 1.05): still +120.
- **Put back** landed exactly on the saved place, and after a `/reload` the pet bar's anchor was
  identical (`TOP UIParent TOP -300 -307.7`): the saved layout untouched.
- **Another addon anchored the pet bar:** before the owner's Edit Mode save it hung from
  `SwingTimerOffHandFrame` (a swing-timer addon's frame). Follow adopts whatever anchor it finds
  as the base, so it moved correctly from there too.
- **The stance bar** (rev 2, the owner's paladin, its one aura on the stance bar, 23:53): moved
  exactly +120 (`CENTER UIParent CENTER -461.9 -> -341.9`), owner: yes; back at its Edit Mode place
  the moment Edit Mode opened (589.77 vs 589.77), re-pinned at +120 when it closed; +120 after a UI
  scale change (effective 0.64 -> 0.80); a layout edited and saved: followed from the new place
  (+120); edited and discarded: the saved place + 120 (495.3333 vs 495.3333); put back exactly
  (375.33); after a `/reload` its anchor read back identical (`TOP UIParent TOP -463.0 -642.0`). No
  blocked action in the three sessions. The fight step was skipped, so the stance bar wasn't
  clicked in combat after a move; the pet bar's fight (same calls) was.
- **The pet dismissed and summoned** (the hunter run, step 7): Next was pressed before the pet bar
  came back, so that check found no bar; the next one, after the fight, found the returned pet bar at
  exactly +120, nothing blocked. The resummoned bar was where it belonged.
- **Not measured:** the stance bar clicked in combat after a move (above).
- Probe flaws in rev 2, fixed in rev 3: a bar hidden after Edit Mode (shown while it's open)
  failed the place checks, and a step finished by hand while Edit Mode was still open read +0.
- The probe recorded the start before the pet bar showed and needed the bar visible after the
  reload; rev 2 records at Move and compares anchors after the reload.

## Session 3: the campfire buff and camping cooldowns (#9, pending)

`pwsh Tools\deploy.ps1 -Probe`, `/reload`, then `/fp steps gab campfire` and follow the panel.
Whether aura 1283391 is a campfire's buff (every helpful aura's id is logged by the fire), whether
the Utility bar adds and drops the camp features with it, and whether camp features share one
cooldown.

## How to run session 1

1. `pwsh Tools\deploy.ps1 -Probe` (the addon itself may stay disabled; the probe stands alone).
2. In game: `/console scriptErrors 1`, `/console taintLog 1`, `/reload`. With taint logging on,
   hovering a tooltip throws errors on this client whatever addons are loaded: ignore those.
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
| 2 | Do the per-button hooks (`UpdateButtonArt`, `Update`, `SetButtonState`, `UpdateFlash`) fire on keybind presses, paging and form swaps? | Partly. A combat trial (00:32:27-00:33:07): `ActionButton1:Update`, `UpdateFlash`, `UpdateUsable` once each (out of combat); `MainActionBar:UpdateDividers` and `UpdateShownButtons` 13x (1 in combat): the dividers come and go often, so hooking `UpdateDividers` is right; `PetActionBar:Update` 7x (6 in combat), even with no pet; `StanceBar:Update` once. `UpdateButtonArt` and `SetButtonState` never fired in that trial, nor in session 2's two fights (below). Per-operation trials (key, click, page) still to run. | 70374 |
| 3 | Can `HasAction(btn.action)` (and the stance / pet readers) be secret in combat? | **Action: no.** In combat, `HasAction` and `C_ActionBar.HasAction` on an occupied slot (ActionButton1, slot 1) were plain. **Pet: open.** In session 2's fight, `GetPetActionInfo(1)` was plain (`PET_ACTION_ATTACK`), on a level 5 druid with no pet out. That covers the default attack command only. Spell slots with an active pet in combat still need a character with a pet. Stance is open too: neither test character has a form yet. | 70374 |
| 4 | Frame levels: the cooldowns (`useParentLevel`) against a child at button + 1 | **The rim sits over the cooldowns, under the text**: ActionButton1 at 52, its cooldowns at 52 (`useParentLevel`), our body at 51 and rim at 53, `TextOverlayContainer` at 500. Stance/pet: button 72, body 71, rim 73. | 70374 |
| 5 | Does `SetAlpha` on a bar work in combat (bar fade)? | **Yes.** In combat (lockdown true), `MultiBarBottomLeft:SetAlpha(0.4)` worked and read back 0.4, and `SetAlpha(1)` 2 s later too. The bar fade (#10) can ship. | 70374 |
| 6 | Hearthstone: does its use spell's `GetSpellCooldownDuration` give a clean swipe in combat? | **Yes.** `C_Item.GetItemSpell(6948)` is Hearthstone's spell 8690. In combat, `C_Spell.GetSpellCooldownDuration(8690)` returned a plain duration object (not secret), and `SetCooldownFromDurationObject` applied it without error. `C_Container.GetItemCooldown` was plain too (the GCD: 1.485 s). The Utility bar uses the duration object. | 70374 |
| 7 | Taint: anything blamed on GABProbe or the skin in taint.log? | **Nothing found.** No line in `Logs\taint.log` names GlassActionBars or GABProbe. Its newest entries (2026-10-14 18:48) blame Apotheca. Session 2 (23:22-23:26) ran with taint logging on, but the file wasn't rewritten. The only errors in that session were the tooltip-hover errors that `taintLog` 1 or 2 causes on this client by itself (the owner's finding from another addon). | 70374 |
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

## Session 1, combat (2026-10-14, 70374)

The probe's saved log, read off disk: fight 00:32:39-00:33:07.
- **Alpha armed:** `MultiBarBottomLeft` went to 0.4 at 1 s and back at 3 s, in lockdown.
- **Hearthstone:** the duration object applied in combat with no error. The Hearthstone was ready, so the test icon showed only the GCD.
- **ActionButton1's slot:** at login, ActionButton1 was slot 25, i.e. page 3, after an "Action Page 3" keypress; in the fight it was slot 1.

**An error the owner saw while paging** (6x), from Blizzard's own code:
`ActionBarController.lua:151: attempt to call a nil value`, in `ActionBarController_UpdateAll`, from `SetActionBarPage` through the `ACTIONPAGE3` binding.
- At 70374 (upstream `forever` 735496d, identical to 70338 for these files), line 151 is `StanceBar:Update()`.
- Neither the skin nor the probe assigns `StanceBar` or its `Update`. The probe post-hooks `StanceBar.Update` with `hooksecurefunc`, and later counts show it called normally.
- No installed addon writes either name; Leatrix Plus only reparents `StanceBar`.
- Not reproduced in session 2 (below): everything was enabled, no error appeared, and `StanceBar:Update` ran normally 10-13 times. The bisect needs the error, so it wasn't run. If it comes back, bisect then: GABProbe off, then GlassActionBars off, then Leatrix Plus off, paging with the binding each time.

## Session 2 (2026-10-14, 70374): the skin

`main` at e3da420 (the skin, the bag bar and the micro menu) with GABProbe, on a level 5 druid; taint logging on.
- **Screenshot (23:22):** as intended. Every action bar, the bag bar and the micro menu are on glass:
  - filled slots have the bright rim, empty ones the faint rim;
  - the hotkey and count text is in the glass font;
  - the gryphons and frame art are gone;
  - the micro buttons keep their icons and their disabled state;
  - empty bag slots keep their silhouette;
  - Apotheca's own bar is untouched.
- **Secrets:** at rest and in combat (23:26:01 and 23:26:09), `HasAction` and `C_ActionBar.HasAction` were plain, and so was `GetPetActionInfo(1)`. That was the default attack command, with no pet out. Stance wasn't sampled: no form.
- **Writer counts:**
  - fight 23:26:00-23:26:14: `UpdateDividers` / `UpdateShownButtons` 22x (4 in combat), `PetActionBar:Update` 20x (10 in combat), `StanceBar:Update` 10x;
  - fight 23:26:20-23:26:21: too short, so its samples were skipped;
  - `UpdateButtonArt` and `SetButtonState` never fired.
- **Errors:** only the tooltip-hover errors that `taintLog` causes by itself; none from the addon, and no paging error.
