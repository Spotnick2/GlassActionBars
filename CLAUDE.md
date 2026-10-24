# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

GlassActionBars (GAB) is an **action bar addon for World of Warcraft: Forever 1.60.1** (Interface
`16001`), written in **Lua 5.1**. It has a single owner (Spotnick) and uses the same stack and
conventions as the sibling Forever addons, above all `..\GlassMail` (the template for this repo's
tooling, tests and CI) and `..\GlassMiniMap` (fading Edit Mode systems' art, the theme registry).
When this file doesn't cover something, check how those handle it before you invent a new idiom.

**Goal:** the liquid-glass look on Blizzard's own action bars (v0.1.0), then smart bars docked to
them: a Utility bar ported from Apotheca's profession bar, and a public API so other addons
(Apotheca, 123, PortalRoulette) dock their bars and buttons (v0.2.0). The reviewed plan is
[docs/PLAN.md](docs/PLAN.md); the mockup is [docs/mockups/action-bars.png](docs/mockups/action-bars.png).
Measured results go in `docs/FOREVER-PROBE.md`.

**Status: v0.1.0 released (2026-10-15); v0.2.0 in progress**, starting with the bar fade (#10).
Still open from the probe: stance secrets (needs a character with a form), pet spell-slot secrets
with an active pet, and the per-operation hook trials.

## The UI contract (non-negotiable)

**Reskin Blizzard's action buttons in place; never own action buttons.** Owned action buttons hit
secret-value `SetCooldown` errors in combat (ForeverUI), and paging them needs state drivers.
- Keep `ActionButton1-12`, `MultiBar*Button1-12` (bars 1-7), `StanceButton*`, `PetActionButton*`.
- Only `hooksecurefunc`, `HookScript`, method calls on regions (`SetAlpha`, `SetFont`, ...) and
  addon-owned frames. Two exceptions: the bar fade's `SetAlpha` on the ten bar frames (not
  protected, measured in combat: docs/FOREVER-PROBE.md Q5), and `Follow.lua`'s
  `ClearAllPointsBase` / `SetPointBase` on `StanceBar` and `PetActionBar` (Edit Mode's saved
  originals: out of combat with Edit Mode closed, plus putting an owned bar back as Edit Mode
  opens; measured by GABProbe's `barmove`, #30). Never reassign a Blizzard global,
  never replace a Blizzard method, never write a field onto a Blizzard frame (ForeverUI's wrappers
  tainted `SetAttribute` in combat). Per-button state lives in weak side tables. Reading a
  template's `parentKey` child is fine.
- Stock art is faded with `SetAlpha(0)`, never `Hide()`n, never reparented, and re-faded after each
  Blizzard writer (`UpdateButtonArt` resets the pushed atlas; `MainActionBar:UpdateDividers`
  acquires pooled dividers).
- Never move the icon: the stock cooldowns anchor inside it.
- Leave proc glow, range and usable tints, the checked texture's alpha and every cooldown to
  Blizzard: secret values stay on its untainted path.
- No geometry, parent or attribute change on a protected frame in combat; queue it for
  `PLAYER_REGEN_ENABLED`. `InCombatLockdown()` is still false inside `PLAYER_REGEN_DISABLED`.
- Dependencies go **provider -> GAB** only: the TOC never names another addon.

## Layout

TOC load order: `Libs\LibGlass-1.0\LibGlass-1.0.xml` -> `Compat.lua` -> `Glass.lua` -> `Look.lua` -> `Theme.lua` ->
`Buttons.lua` -> `Bars.lua` -> `Bags.lua` -> `MicroMenu.lua` -> `Fade.lua` -> `Dock.lua` ->
`Follow.lua` -> `Edges.lua` -> `API.lua` -> `Utility.lua` -> `Inspect.lua` -> `Options.lua` -> `GlassActionBars.lua`. Feature files load between
`Glass.lua` and `Options.lua`.

- **`Compat.lua`**: `GlassActionBars.API`, the only route to client APIs that moved or may be
  absent: `IsSecret`, `Plain`, `NoteCombat` / `InCombat`, `Fail(key, err)` (the **one** failure
  recorder, read by `/gab failures`), `Try`, `RegisterEvents` (reports failures), `AddOnVersion`,
  `ClassColor`, `SafeFrame`; `MEASURED_ON_BUILD`.
- **`Glass.lua`**: the LibGlass instance, built once at PLAYER_LOGIN by `GAB.BuildGlass(preset)` (Look.lua
  picks the preset); `GAB.Glass` is a stand-in that reaches it once built (nothing reads it
  before login). Pearl (r11, the default; the owner kept it after the trial, 2026-10-19), Clean or Classic; an unknown preset builds Clean
  and says why. `GlassActionBars.MEDIA` for our own textures. Material changes are LibGlass PRs.
- **`Look.lua`**: the look (#39; Glass UI's SUITE.md, SUITE-LOOK.md). At PLAYER_LOGIN, before any
  glass: asks `GlassUI.Suite.Theme` (API 1 exactly; no TOC line) once per session. Following: the
  suite's material, and each look key (`theme` = Glass UI's `tint`, `hover`, `press`,
  `emptySlots`) is the player's own in `GlassActionBarsDB.look` (never pruned) else the suite's,
  live from `GlassUI.Suite.LookChanged`; not following: own material (`db.material`) and own look
  else `Look.DEFAULTS`. `Look.Get(key)` is the one read. `Suite.Report`: built, look, own,
  tenants (`SkinButton`'s owners). The live refresh is colours and alphas only (combat-safe).
- **`Theme.lua`**: clear / smoked / class glass (GlassMiniMap's), repainted live on every
  registered surface; only body regions (tint, wash), never the rims.
- **`Buttons.lua`**: the skin. `Build(button, regions)` (shared by every family, and later by the
  provider API): a body frame one level under the button, its rim raised one level over it, the
  stock frame art faded, the pushed texture made a bright rim, the text in the glass font.
  `SetOccupied` makes the rim bright or faint. Family adapters: action buttons hook their own
  `UpdateButtonArt` / `Update` / `UpdateHotkeys`; stance and pet hook their bar's
  `UpdateState` / `Update`. A login in combat waits for the fight to end.
  Feedback (#34): `Buttons.LOOK` (hover off/glow/halo, press off/flash/ripple, emptySlots),
  `Buttons.PRESETS` (glass = defaults: glow, flash, frosted; soft; minimal), `Buttons.Preset()`
  ("custom" when none). The halo (Media/ButtonHalo, 16 px padding, sliced at 24) and the ripple
  (ButtonRipple, masked by ButtonMask) are our textures on `g.top`, driven by one OnUpdate only
  while one moves, from `HookScript` OnEnter/OnLeave/OnHide/OnMouseDown (a click only: key presses
  have no hookable signal, they flash). The empty factor goes through the theme's scale callback
  and the rim once (`Theme.Repaint` per surface); every family takes it, the bag slots too (#50). The key text stays where Blizzard puts it: moving it above the buttons was tried and
  taken out (docs/FOREVER-PROBE.md session 5). Textures from `Tools/make_rim.py`.
  Pearl's face (#44, the owner's FFXIV reference; Pearl built only): `Buttons.PEARL` overrides
  `TUNE`'s defaults (`TuneDefault`; a saved tune of a PEARL key is never pruned, the material is
  only known at login), a neutral frosted fill, a frosted empty slot's recessed socket
  (ButtonSocketRim / ButtonSocketShade in place of the rim and inner line) and a filled slot's
  reflection (ButtonGloss, masked by ButtonMask), all on `g.top`: over the cooldown sweep like the
  rim, by choice (a fixed order); `/gab tune gloss 0` takes it off. GABProbe's `pearl` checks it.
- **`Bars.lua`**: the main bar's `BorderArt`, its pooled dividers (re-faded after
  `UpdateDividers`) and the end caps' textures (`/gab gryphons`), re-applied on
  `EDIT_MODE_LAYOUTS_UPDATED`.
- **`Bags.lua`**: the bag bar (#14), full glass through `Buttons.Build`: the backpack, four bag
  slots, reagent bag and key ring, re-styled after each slot's own `UpdateTextures`, empty or not by
  `GetInventoryItemTexture` (Blizzard's `HasBagEquipped`), the key ring by `HasKey`; an empty
  slot's greyed icon faded, given back only where GAB faded it (#57); `BagsBar.BorderArt` and its
  pooled dividers (after `Layout` / `UpdateDividers`) faded. Never `SetAlpha` on a bag button
  itself: `ItemButtonMixin` replaces it.
- **`MicroMenu.lua`**: the micro menu on glass (#14, #57). `MicroMenu.BorderArt` /
  `BackgroundArt` faded; each button's bronze frame (inside its state atlases) cropped off with
  `SetTexCoord(CROP...)` (relative to the atlas: docs/FOREVER-PROBE.md session 7), again after
  each `Set*Atlas`, its `FlashContent` too; ButtonBG and the portrait's shadows faded. Then
  `microStyle`: `tiles` (each button through `Buttons.Build(b, {}, { inset })`: they overlap by 5)
  or `pill` (an own frame under UIParent, one level under MicroMenu, shown while it is visible
  and home in `MicroMenuContainer`); both built once, switched live. Built out of combat.
- **`Fade.lua`**: the bar fade (#10), per bar off / mouseover / combat, one faded alpha. One
  addon-owned driver (OnUpdate only while a bar fades) polls the reasons a bar is shown (pointer,
  the main bar's page arrows, its flyout, the action and pet drag grids, Edit Mode, Quick Keybind,
  the spellbook / professions book, a fight) every 0.1 s; a reveal snaps to 1, fade-out starts
  0.25 s later and runs 0.2 s. `SetAlpha` on the bar frame only; a bar set back to off gets 1 once.
- **`Dock.lua`**: smart bars docked to Action Bar 1-8 (#7). `Dock.Register{ id, label, frame,
  Layout(geom), OnHosted(isHosted), default }` (internal; #8's `RegisterBar` and #9's Utility bar
  call it). Target = the union of the bar's `shownButtonContainers`; the client anchored to
  UIParent in its own units; `Layout(geom)` every pass, `geom` carrying size/padding when the
  player matches them (`match`) and rows/orientation when matching those (`matchRows`, #48; a
  saved `match = false` from before keeps the rows off), nil when neither ("your own
  geometry": a hosted client keeps arranging its contents); geometry lengths scaled, counts raw; the first placement a
  transaction (`OnHosted(true)`, Layout, place, else `OnHosted(false)`). Passes coalesced, out of
  combat only; re-run on grid/shown-button hooks, Edit Mode's re-stacking, target `OnShow`, scale
  and layout events, and a 0.2 s poll while Edit Mode is open. Every geometry read through
  `API.Plain`.
- **`Follow.lua`**: the stance and pet bars follow Glass Unit Frames (#30, GlassUI#28 5b). GUF's
  EventRegistry `GlassUnitFrames.LayoutChanged` (linked, player and pet rects, `dx`, `petDx`) and
  `GlassUF.LayoutState()` at world entry; no dependency. `StanceBar` moves by `dx`, `PetActionBar`
  by `petDx`, horizontally from the anchor Blizzard gave it (the base, a side table; the layout is
  never written). Ownership marker = the anchor read back after our write: after Blizzard's
  passes (`UpdateBottomActionBarPositions`, `ApplySystemAnchor`, deferred a frame) a different
  anchor is the new base. Edit Mode entry puts an owned bar back. Snaps: a hidden bar's
  `BreakSnappedFrames` freezes its snapped bars where they are, copies that into the layout and
  clears their default flag, and nothing can undo that without writing the layout; so a bar in any
  snap stays put (bars snapped to it, snapped to another bar, or in its default place, which on
  Forever is stacked on Action Bar 1). Moved once in Edit Mode it is screen-anchored and follows.
  One plain anchor only; combat and Edit Mode wait; scale events re-apply.
  Snap, no glide. `/gab follow [on/off]` shows each bar's state.
- **`Edges.lua`**: the bars at the screen's sides for the suite (#37; Glass UI's GROUP-LAYOUT.md
  5c): `GlassActionBars.EdgeState()` -> `{ left, right, width }` (UIParent units) and EventRegistry
  `GlassActionBars.EdgesChanged`, out of combat, past 0.5 units from the last announced. Counted:
  Action Bars 1-8 (`Dock.TargetRect(n, true)`, strict: one unreadable container skips the bar) and
  every dock client (`Dock.Frames()`), visible and taller than wide; per side a stack from the
  edge (each within 40 of the edge or the bars counted), the inner edge only grows. Measured a
  frame after a request: a Dock pass, a watched bar's or client's OnShow/OnHide, Edit Mode exit,
  layout/scale/display events, the Utility bar placed by hand.
- **`API.lua`**: the public provider API (#8); the contract is
  [docs/PUBLIC-API.md](docs/PUBLIC-API.md). `GlassActionBars.PUBLIC_API_VERSION` (2 since #48, checked
  with `==`; not `API_VERSION`: `GlassActionBars.API` is the client adapter), `RegisterBar` (wraps
  `Dock.Register`), `RequestLayout`, `SkinButton` (regions checked by role, queued in combat),
  `SetButtonEmpty` (a provider's empty slot), `RegisterButton` (stored; the Utility bar hosts them).
  A provider's icon, and the Utility bar's, is rounded to the glass (`Build`'s `maskIcon`, #46):
  Blizzard's have the template's IconMask. Inputs are copied on acceptance; refusals return
  `false, reason`. Any incompatible change bumps the version and the doc.
- **`Utility.lua`**: the Utility bar (#9), Apotheca's profession bar plus the camping items.
  `ACTIONS` (Apotheca's, `measured` marked), `CAMPING` (the authoritative list: 3 kits + 34
  features; a feature needs `CAMPFIRE_AURA`, read through `API.HasPlayerAura`), the `camping`
  group in the order. Secure buttons `GlassActionBarsUtil_<key>` made at load with their own
  regions, skinned at login; `Bindings.xml` (shipped by deploy.ps1 and the package allowlist) has a
  CLICK binding per action and kit. Reconcile coalesced, deferred in combat. The dock client
  `utility` (default right of bar 1; its frame raised over every stock action button at each rebuild, so an overlapped stock button never takes its clicks); `Layout(geom|nil)`, nil = its own layout (`LAYOUT`, Apotheca's
  keys: orientation, rows, iconSize, iconPadding). Alt-drag (Apotheca's overlay and combat handling)
  undocks at the drag's start and saves `utility.pos` at the drop; undocked, the bar sits there. Cooldowns: the
  Hearthstone by its use spell's duration object, other items by `GetItemCooldown`. Settings in
  `GlassActionBarsDB.utility`, created by the first change only (Apotheca's import marker).
  Provider buttons (`RegisterButton`, #52): `provider:<id>` keys, off by default (`show[key] =
  true` stored), kept in the order even when not registered this session (unseen: no button, no
  row, MoveUtility steps past them); an insecure `GlassActionBarsUtilProvider_<id>` made at the
  first Reconcile that shows it; the click asks `IsEnabled` each time; dimmed from it on refresh
  and a frame after combat starts/ends; `OnHosted` once with false, then on change, after
  Reconcile (never in combat).
- **`Inspect.lua`**: `/gab inspect` and `/gab layer`, the in-game layer inspector.
- **`Options.lua`**: the Esc > Options > AddOns page, the porting guide's recipe. Features add a
  section with `Options.AddSection(function(panel, anchor) ... return last end)`, using
  `Options.radios` (choices, stacked or in a row) and `Options.checkbox` (on/off); a sub-page is
  `Options.AddPage(name, function(page, title) ... end)` (the Bar fade page).
- **`GlassActionBars.lua`**: bootstrap, saved settings (only what the player set is saved), the
  `Settings` helpers, `/gab`.
- **`Tools/GABProbe/`**: the throwaway measurement module on ForeverProbe (`/fp gab`;
  `References\Docs\PROBES.md`), results in `docs/FOREVER-PROBE.md`. In-game experiments are
  procedures (`/fp steps gab <name>`; `campfire` for #9). The standalone v0.1.0 probe
  (`/gabprobe`) is in git history before #32; port its open checks when an issue needs them. Its
  test (`tests/test_probe.lua`) needs `..\ForeverProbe` and runs locally only.

## Action bar facts for this client

- The source to read is `C:\Projects\WoW\wow-ui-source` (branch `forever`, 1.60.1.70338), the
  Mainline family plus Camelot overrides: `Interface\AddOns\Blizzard_ActionBar\Shared\ActionButton.lua`,
  `Mainline\ActionButtonTemplate.xml` (the 45x45 button's regions), `Mainline\ActionButtonOverrides.lua`
  (`UpdateButtonArt`), `Shared\MainActionBar.lua` (dividers, end caps), `Shared\StanceBar.lua`,
  `Shared\PetActionBar.lua`, `Camelot\MainMenuBarEndCaps.*`.
- Bar names: `ActionButtonUtil.ActionBarButtonNames`. The main bar is `MainActionBar` (there is no
  `MainMenuBar`). Stance and pet buttons are `SmallActionButtonTemplate` (30x30).
- The end caps are an Edit Mode system of their own on Forever (left/right, with a visibility
  setting).
- Occupancy: `HasAction(btn.action)`; stance `GetShapeshiftFormInfo(btn.index)`; pet
  `GetPetActionInfo(btn.index)`.

## Forever basics (shared with the siblings)

- One plain `GlassActionBars.toc`, `## Interface: 16001` (**`11601` is a transposed-digit bug**).
  Never commit a literal version over `@project-version@`; the deploy script writes `dev` into its copy.
- One global namespace, `GlassActionBars`; files start `GlassActionBars = GlassActionBars or {}` and
  alias it `local GAB = GlassActionBars`. A `_test` seam table exposes file-local internals to tests.
- **Secret values:** test with `issecretvalue(v)` **before** any other use; never save one.
- **`RegisterEvent` throws on unknown names and returns `false` for refusals**: always
  `API.RegisterEvents`.
- SavedVariables: read them at `ADDON_LOADED` / `PLAYER_LOGIN`, cope when they're absent.
- **IDs, never names**: never compare against or save an English display string.

## References: read these before touching an unfamiliar API

- `C:\Projects\WoW\References\Docs\PORTING-TBC-TO-FOREVER.md`: measured, addon-agnostic field notes.
  New addon-agnostic findings go there, not into a copy here.
- `C:\Projects\WoW\References\Forever\api\forever-api-1.60.1.70374.md`: the API dump. **Presence is not a contract.**
- `C:\Projects\WoW\References\Docs\EMBEDDED-LIBRARIES.md`, `LIBGLASS-MIGRATION.md`, `RELEASING.md`.
- `C:\Projects\WoW\References\Addons\ActionBars\Bartender4`: a behaviour reference (its Forever art
  handling, bar fade with flyouts, LibActionButton's duration-object cooldowns). It owns its buttons
  and uses state drivers; we don't.
- `C:\Projects\WoW\Apotheca` (`ApothecaUtility.lua`, `ApothecaCompat.lua`), `..\123`
  (`Core\SecureAction.lua`), `..\PortalRoulette`, `..\AltStable\PublicAPI.lua`: the v0.2 sources.

## Toolchain and commands

Lua 5.1 at `C:\Program Files (x86)\Lua\5.1\` (`lua.exe`, `luac.exe`). No build step.

```powershell
pwsh tests\run.ps1                                                   # luac -p on the TOC files + probe, then every tests\test_*.lua (needs ..\LibGlass or $env:LIBGLASS)
& 'C:\Program Files (x86)\Lua\5.1\lua.exe' tests\test_boot.lua      # one test, from the repo root
pwsh Tools\deploy.ps1 -Probe                                         # copy the addon (+ GABProbe) into AddOns
```

- Default AddOns path: `C:\Program Files (x86)\World of Warcraft\_classic_beta_\Interface\AddOns`
  (`-AddOnsPath` to change).
- In game: `/console scriptErrors 1` and `/console taintLog 1`, then `/reload`.
- Shell heredocs in this environment can collapse `\\` to `\`: write files that contain Lua
  backslash escapes or Windows paths with the Write/Edit tools.

## Testing

GlassMail's harness: `tests\wow_stubs.lua` (strict globals as an allowlist of APIs verified in the
dump, secrets as throwing `newproxy` values, event names validated against the dump or
`tests\events-70374.txt`, every widget method recorded, `hooksecurefunc` recorded in `WoW.hooked`),
`tests\harness.lua` (`check`, `eq`, `loadAddon`, `newChat`, `chatHas`), `test_methods.lua` (every
method called exists on this client). **Mutation-test every new test**: break the behaviour,
confirm it goes red. Offline tests can't cover taint, real secrets or rendering; that's the probe
and an in-game checklist.

## Workflow and releasing

- **GitHub issues and pull requests for all work.** Issue -> branch off `main` (`<n>-short-slug`)
  -> PR with `Closes #N` (or `Part of #N`). Closing keywords match anywhere in a PR body, even
  negated. `luac -p` clean and tests green before committing; check the PR's `package-check` run
  after pushing.
- **The owner merges and closes PRs and launches reviews.**
- **Plans** get an adversarial review before coding: Codex via the `codex-consult` skill,
  `gpt-6-astra` at high effort, looping until consensus without overengineering.
- Provider work (Apotheca, 123, PortalRoulette) is an issue and PR in that addon's own repo.
- A `v*` tag publishes three times (`References\Docs\RELEASING.md`). CurseForge (project 1744070,
  https://www.curseforge.com/wow/addons/glass-action-bars) builds its own file from the tag
  webhook through `.pkgmeta`. After `check`, the `release` job publishes CI's zip and
  `release.json` as a GitHub Release, and the `wago` job uploads the same zip to Wago Addons
  (project `aND9586o`, the TOC's `X-Wago-ID`; the `WAGO_API_TOKEN` secret). The notes are the tag's
  `## vX.Y.Z` section of `CHANGELOG.md` (`tests/release_files.sh`, RELEASING.md's template, kept
  unchanged). Check CurseForge's own zip with an alpha tag first.

## Conventions

- **Right-size for a single maintainer.** The simplest thing that works; no speculative abstraction.
- **Measured beats reasoned.** If a claim about the client can be checked in game, check it.
- Match the surrounding code's idiom. Keep pure refactors in their own commit.

## Consulting Codex

The shared `codex-consult` skill (user level) has the invocation and the gotchas. For this repo:

For GlassActionBars, good things to hand Codex:
- anything that touches a Blizzard action button or bar (hooks, fades, region method calls), where
  taint can get `SetAttribute` or paging blocked in combat;
- anything that creates, moves or re-attributes a secure frame (the Utility bar, docking), and
  what happens when it is asked to in combat;
- the provider API's contract (`RegisterBar` / `RegisterButton`, `OnHosted` ordering);
- anything that writes to SavedVariables or key bindings (the Apotheca import, the keybind mover);
- any plan that grows scope toward a bar replacement (Bartender4, ElvUI), or owns action buttons.

**Always hand it `CLAUDE.md` and `docs/PLAN.md` alongside the diff or plan**, plus
`C:/Projects/WoW/References/Docs/PORTING-TBC-TO-FOREVER.md` and `docs/FOREVER-PROBE.md` once it exists.
Those findings were measured on the live client. Without them, a cold reviewer argues from
Classic-era or Retail behaviour that doesn't hold here.
`C:/Projects/WoW/References/Forever/api/forever-api-<version>.<build>.md` (take the highest build) is the full API surface when a question
turns on whether something exists, and `C:/Projects/WoW/wow-ui-source` (branch `forever`) is the
client's own FrameXML (`Blizzard_ActionBar`). `C:/Projects/WoW/References/Addons/ActionBars/Bartender4` is
a behaviour reference: it owns its buttons, which we deliberately don't.
