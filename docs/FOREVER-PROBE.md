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
| 1 | Regions of the action, stance and pet buttons (names, sizes, layers) | open | |
| 2 | Do the per-button hooks (`UpdateButtonArt`, `Update`, `SetButtonState`, `UpdateFlash`) fire on keybind presses, paging and form swaps? | open | |
| 3 | Can `HasAction(btn.action)` (and the stance / pet readers) be secret in combat? | open | |
| 4 | Frame levels: the cooldowns (`useParentLevel`) against a child at button + 1 | open | |
| 5 | Does `SetAlpha` on a bar work in combat (bar fade)? | open | |
| 6 | Hearthstone: does its use spell's `GetSpellCooldownDuration` give a clean swipe in combat? | open | |
| 7 | Taint: anything blamed on GABProbe in taint.log? | open | |
| 8 | (optional) Do attribute and state drivers work? (porting guide vs Bartender4) | open | |
