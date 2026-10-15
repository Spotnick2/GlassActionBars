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
  addon-owned frames; the one exception is the bar fade's `SetAlpha` on the ten bar frames (not
  protected, measured in combat: docs/FOREVER-PROBE.md Q5). Never reassign a Blizzard global,
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

TOC load order: `Libs\LibGlass-1.0\LibGlass-1.0.xml` -> `Compat.lua` -> `Glass.lua` -> `Theme.lua` ->
`Buttons.lua` -> `Bars.lua` -> `Bags.lua` -> `MicroMenu.lua` -> `Fade.lua` -> `Dock.lua` ->
`API.lua` -> `Inspect.lua` -> `Options.lua` -> `GlassActionBars.lua`. Feature files load between
`Glass.lua` and `Options.lua`.

- **`Compat.lua`**: `GlassActionBars.API`, the only route to client APIs that moved or may be
  absent: `IsSecret`, `Plain`, `NoteCombat` / `InCombat`, `Fail(key, err)` (the **one** failure
  recorder, read by `/gab failures`), `Try`, `RegisterEvents` (reports failures), `AddOnVersion`,
  `ClassColor`, `SafeFrame`; `MEASURED_ON_BUILD`.
- **`Glass.lua`**: `GlassActionBars.Glass = LibStub("LibGlass-1.0"):New({ preset = "clean" })`, and
  `GlassActionBars.MEDIA` for our own textures. Material changes are LibGlass PRs.
- **`Theme.lua`**: clear / smoked / class glass (GlassMiniMap's), repainted live on every
  registered surface; only body regions (tint, wash), never the rims.
- **`Buttons.lua`**: the skin. `Build(button, regions)` (shared by every family, and later by the
  provider API): a body frame one level under the button, its rim raised one level over it, the
  stock frame art faded, the pushed texture made a bright rim, the text in the glass font.
  `SetOccupied` makes the rim bright or faint. Family adapters: action buttons hook their own
  `UpdateButtonArt` / `Update` / `UpdateHotkeys`; stance and pet hook their bar's
  `UpdateState` / `Update`. A login in combat waits for the fight to end.
- **`Bars.lua`**: the main bar's `BorderArt`, its pooled dividers (re-faded after
  `UpdateDividers`) and the end caps' textures (`/gab gryphons`), re-applied on
  `EDIT_MODE_LAYOUTS_UPDATED`.
- **`Bags.lua`**: the bag bar (#14), full glass through `Buttons.Build`: the backpack, four bag
  slots, reagent bag and key ring, re-styled after each slot's own `UpdateTextures`, the rim by
  `GetInventoryItemTexture` (Blizzard's `HasBagEquipped`); `BagsBar.BorderArt` and its pooled
  dividers (after `Layout` / `UpdateDividers`) faded. Never `SetAlpha` on a bag button itself:
  `ItemButtonMixin` replaces it.
- **`MicroMenu.lua`**: a glass panel behind the micro menu (#14) in place of `MicroMenu.BorderArt` /
  `BackgroundArt`. The micro buttons are left alone: their bronze frame is baked into each icon
  atlas. The panel is its own frame (MicroMenu flattens its children's render layers), one level
  under, rims at its own level, shown only while MicroMenu is home in `MicroMenuContainer`.
- **`Fade.lua`**: the bar fade (#10), per bar off / mouseover / combat, one faded alpha. One
  addon-owned driver (OnUpdate only while a bar fades) polls the reasons a bar is shown (pointer,
  the main bar's page arrows, its flyout, the action and pet drag grids, Edit Mode, Quick Keybind,
  the spellbook / professions book, a fight) every 0.1 s; a reveal snaps to 1, fade-out starts
  0.25 s later and runs 0.2 s. `SetAlpha` on the bar frame only; a bar set back to off gets 1 once.
- **`Dock.lua`**: smart bars docked to Action Bar 1-8 (#7). `Dock.Register{ id, label, frame,
  Layout(geom), OnHosted(isHosted), default }` (internal; #8's `RegisterBar` and #9's Utility bar
  call it). Target = the union of the bar's `shownButtonContainers`; the client anchored to
  UIParent in its own units; `Layout(geom)` every pass, `geom` nil when not matching ("your own
  geometry": a hosted client keeps arranging its contents); geometry lengths scaled, counts raw; the first placement a
  transaction (`OnHosted(true)`, Layout, place, else `OnHosted(false)`). Passes coalesced, out of
  combat only; re-run on grid/shown-button hooks, Edit Mode's re-stacking, target `OnShow`, scale
  and layout events, and a 0.2 s poll while Edit Mode is open. Every geometry read through
  `API.Plain`.
- **`API.lua`**: the public provider API (#8); the contract is
  [docs/PUBLIC-API.md](docs/PUBLIC-API.md). `GlassActionBars.PUBLIC_API_VERSION` (1, checked
  with `==`; not `API_VERSION`: `GlassActionBars.API` is the client adapter), `RegisterBar` (wraps
  `Dock.Register`), `RequestLayout`, `SkinButton` (regions checked by role, queued in combat),
  `RegisterButton` (stored; the Utility bar hosts them). Inputs are copied on acceptance; refusals
  return `false, reason`. Any incompatible change bumps the version and the doc.
- **`Inspect.lua`**: `/gab inspect` and `/gab layer`, the in-game layer inspector.
- **`Options.lua`**: the Esc > Options > AddOns page, the porting guide's recipe. Features add a
  section with `Options.AddSection(function(panel, anchor) ... return last end)`, using
  `Options.radios` (choices, stacked or in a row) and `Options.checkbox` (on/off); a sub-page is
  `Options.AddPage(name, function(page, title) ... end)` (the Bar fade page).
- **`GlassActionBars.lua`**: bootstrap, saved settings (only what the player set is saved), the
  `Settings` helpers, `/gab`.
- **`Tools/GABProbe/`**: the throwaway measurement addon (`/gabprobe help`), results in
  `docs/FOREVER-PROBE.md`.

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

- `C:\Projects\WoW\References\PORTING-TBC-TO-FOREVER.md`: measured, addon-agnostic field notes.
  New addon-agnostic findings go there, not into a copy here.
- `C:\Projects\WoW\References\forever-api-1.60.1.70374.md`: the API dump. **Presence is not a contract.**
- `C:\Projects\WoW\References\EMBEDDED-LIBRARIES.md`, `LIBGLASS-MIGRATION.md`, `RELEASING.md`.
- `C:\Projects\WoW\References\Bartender4-4.18.3.1`: a behaviour reference (its Forever art
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
- CurseForge (project 1744070, https://www.curseforge.com/wow/addons/glass-action-bars) builds
  releases from the tag webhook through `.pkgmeta`; the `release` job publishes a GitHub Release
  from the tag's `## vX.Y.Z` section of `CHANGELOG.md`. Check CurseForge's own zip with an alpha
  tag first (`References\RELEASING.md`).

## Conventions

- **Right-size for a single maintainer.** The simplest thing that works; no speculative abstraction.
- **Measured beats reasoned.** If a claim about the client can be checked in game, check it.
- Match the surrounding code's idiom. Keep pure refactors in their own commit.
