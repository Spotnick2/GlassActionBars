# Forever probe: Glass Action Bars

What the live client does, measured with `Tools/GABProbe` (`/gabprobe help`). docs/PLAN.md's
Phase 0 questions; each answer decides a detail of the skin. Facts that hold for every addon go
to `C:\Projects\WoW\References\PORTING-TBC-TO-FOREVER.md` instead.

## How to run session 1

1. `pwsh Tools\deploy.ps1 -Probe` (the addon itself may stay disabled; the probe stands alone).
2. In game: `/console scriptErrors 1`, `/console taintLog 1`, `/reload`.
3. `/gabprobe regions` and `/gabprobe levels`.
4. `/gabprobe alpha on`, `/gabprobe hearth` (use the Hearthstone first if it is ready, so its
   cooldown runs), and optionally `/gabprobe driver`.
5. Out of combat: press a few action keybinds, click buttons, page the main bar (Shift+wheel or
   the arrows), open and close Edit Mode, toggle "Hide Bar Art" on the main bar and back, summon a
   pet (warlock / hunter) or change form or stance (druid / warrior / rogue stealth).
6. Fight something for a few seconds; during the fight press keybinds and swap form or stance.
7. After the fight the counts print; also `/gabprobe counts`.
8. Exit the client fully. Send `WTF\Account\<account>\SavedVariables\GABProbe.lua` and
   `Logs\taint.log`.

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
