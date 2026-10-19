# GlassActionBars: plan

## Context

GlassActionBars (GAB) is a new WoW: Forever addon (Interface 16001, which uses the Retail/Mainline codebase). It gives the stock action bars the liquid-glass look from the mockup [`mockups/action-bars.png`](mockups/action-bars.png). Today's stock bars, with Apotheca placed at their end by hand: [`mockups/stock-with-apotheca.png`](mockups/stock-with-apotheca.png). It ships on GitHub and CurseForge.

It also becomes the home for **smart bars**:
- A native **Utility bar**, ported from Apotheca's profession bar.
- **Docking**, which snaps a smart bar to the edge of a stock bar. Today the user places Apotheca at the right of the bars by hand.
- A **public provider API** so separate addons plug in when GAB is installed: Apotheca (consumables), 123 (Warlock), and Portal Roulette, whose launcher becomes a real bar button instead of a macro.

Decisions taken:
- **Split Apotheca.** The profession bar moves into GAB as the Utility bar. Apotheca stays a standalone consumables addon and docks through the API.
- **Public API on the GAB global** (AltStable `PUBLIC_API` pattern), not an embedded library.
- **Skin first.** v0.1.0 is the reskin only. v0.2.0 adds the dock, the API and the Utility bar. Provider repos adopt the API after that.
- **All work runs through GitHub issues and PRs** (see Workflow).

Review: three adversarial rounds with Codex (gpt-6-astra, high effort) reached consensus. Round 1 found 2 blockers and 6 should-fixes; round 2 found 5 more should-fixes; round 3 found nothing new. All of them are folded into this plan.

## Hard constraints (from the References docs and sibling experience)

- **Never own action buttons.** Reskin Blizzard's `ActionButton1-12`, `MultiBar*Button1-12` (bars 1–7), `StanceButton*` and `PetActionButton*` where they are.
  - Owned buttons hit secret-value `SetCooldown` errors in combat (ForeverUI).
  - Paging owned buttons needs state drivers. The porting guide says those are broken, but Bartender4 4.18.3.1 (16001 TOC) and EllesmereUI use them. The probe checks which is true. Either way, reskinning in place is less code and keeps paging, Edit Mode and cooldowns on Blizzard's own path.
- **Touch Blizzard frames only through approved paths:** `hooksecurefunc`, `HookScript`, method calls on regions (`SetAlpha`, `SetFont`), and our own child frames.
  - Never write a field onto a Blizzard frame and never replace a method. ForeverUI's wrappers tainted `MultiBarBottomLeftButton11:SetAttribute`.
  - Keep per-button state in weak side tables.
- **Hiding art:** fade it with `SetAlpha(0)`. Never `Hide()` it, never reparent managed Edit Mode frames, and re-apply after each Blizzard writer (listed in Phase 1).
- **Combat:** no geometry, parent or attribute changes on protected frames in combat. Queue the work for `PLAYER_REGEN_ENABLED`. `InCombatLockdown()` is still false inside the `PLAYER_REGEN_DISABLED` handler.
- **Load order:** read SavedVariables only at `ADDON_LOADED`/`PLAYER_LOGIN`. Wrap `RegisterEvent`. Assemble the version token at runtime.
- **Options:** a canvas Settings page, hidden at creation, with no UIDropDownMenu (radio groups instead).
- **Other bar addons:** there is no addon-specific guard. Skinning a stock button that Bartender4, ElvUI or another addon has hidden is invisible and harmless.
  - Dock and fade treat a stock bar as **unavailable** while it isn't effectively visible.
  - A first install whose targets are all replaced simply has nothing to dock to, so smart bars stay in standalone placement.

## Repo scaffold (copy the GlassMail template)

Copy from `C:\Projects\WoW\GlassMail`:
- `.pkgmeta` (package-as GlassActionBars; LibGlass external `tag: r6` plus repeated ignores), `.gitignore`, `.gitattributes`
- `LICENSE` (MIT plus a third-party block), `CHANGELOG.md`, `CLAUDE.md` (same sections), `README.md`
- `Tools/deploy.ps1`, `Tools/LibGlassPin.ps1`
- `tests/{wow_stubs,harness,run.ps1,fetch_external.sh,test_toc}`, plus the no-field-write check from `tests/test_skin.lua`
- `.github/workflows/package-check.yml`: luac, tests, packager dry run at the pinned SHA, zip allowlist, and `gh release` on a `v*` tag.

Copy from `C:\Projects\WoW\GlassMiniMap`: `Compat.lua` helpers (`Try`, `Fade`/`Unfade`, `ClassColor`) and the `Theme.lua` surface registry (clear / smoked / class).

Owner steps (outward-facing, so the owner does them or confirms them first):
- `git init` and create the GitHub repo (Spotnick2/GlassActionBars).
- Create the CurseForge project, then put its id into `## X-Curse-Project-ID` and the README.

TOC (v0.1). GAB depends on no provider; dependencies go only **provider → GAB**.
```
## Interface: 16001
## Title: |cff7fd4ffGlass|r Action Bars
## Version: @project-version@
## SavedVariables: GlassActionBarsDB
Libs\LibGlass-1.0\LibGlass-1.0.xml
Compat.lua  Glass.lua  Theme.lua  Buttons.lua  Bars.lua  Options.lua  GlassActionBars.lua
```

## Workflow: GitHub issues and PRs for all work

- Once the GitHub repo exists, open one issue per work item below, before any code. The issue body carries the relevant slice of this plan and its acceptance checks. Group the issues with a milestone per release (v0.1.0, v0.2.0).
- One branch per issue (`<n>-short-slug`), one PR per issue. The PR body says `Closes #N`, or `Part of #N` when a PR only covers part of an issue. Closing keywords match anywhere in the body, even negated, so never write "doesn't close #N".
- The owner reviews and merges. Plans and risky diffs get a Codex review (`/codex-consult`) before the PR is opened.
- Provider work (Phase 3) gets its own issue and PR in each provider's repo. Each links back to the GAB issue for the API it consumes.
- Only the very first scaffold commit, which creates the repo, goes to `main` directly. Everything after that goes through a PR.

Issues:
- **v0.1.0:**
  1. Scaffold: template, CI, tests harness, deploy.
  2. In-game probe.
  3. Button skin.
  4. Bar art fade.
  5. Theme and options.
  6. README, screenshots, CurseForge and the release.
- **v0.2.0:**
  7. Dock.
  8. Provider API and `docs/PUBLIC-API.md`.
  9. Utility bar port and the Apotheca settings import.
  10. Bar fade (mouseover / out of combat).
- **Provider repos:**
  - PortalRoulette: launcher as a GAB button.
  - Apotheca: dock through the API, and hand the profession bar over to GAB.
  - 123: compact docked layout.

## Phase 0: Probe (dev-only `Tools/GABProbe`)

Measured on build 70374, which is newer than the wow-ui-source checkout (70338). The answers decide the details in Phase 1.
- Which regions each button family has: action, stance, pet.
- Whether these per-button hooks fire on keybind presses, paging and form swaps: `hooksecurefunc` on `UpdateButtonArt`, `Update`, `SetButtonState` and `UpdateFlash`.
- Whether `HasAction(btn.action)` can return a secret value.
- How the cooldown frame's level (`useParentLevel`) stacks against our rim frame's level.
- Whether bar `SetAlpha` works in combat, for the fade feature.
- Whether `C_Spell.GetSpellCooldownDuration` on Hearthstone's use spell (`C_Item.GetItemSpell(6948)`) gives a clean item swipe in combat.

All of it runs under `/console taintLog 1`. A `RegisterStateDriver` check, which settles the porting guide versus Bartender4 conflict, is optional reference upkeep and not a release gate.

## Phase 1, v0.1.0: the glass skin

| File | What it does |
|---|---|
| `Glass.lua` | `LibStub("LibGlass-1.0"):New({ preset = "clean" })`, plus `GAB.MEDIA` for our own art. |
| `Bars.lua` | Lists the buttons from `ActionButtonUtil.ActionBarButtonNames`, plus Stance and Pet. Fades `MainActionBar.BorderArt`, the end caps (`Camelot/MainMenuBarEndCaps`; Bartender4's `BlizzardArt.lua` has a Forever case) and the dividers. Divider fades are re-applied, deferred, after `MainActionBar:UpdateDividers`, because pooled dividers are acquired again there. Everything is re-applied on `EDIT_MODE_LAYOUTS_UPDATED`. |
| `Buttons.lua` | One visual builder shared by every family, plus a family adapter per family; details below. |
| `Theme.lua` | Presets (clear / smoked / class) with live repaint through `Glass.SetSurfaceTint`. |
| `Options.lua` | Canvas page: theme, show hotkeys and macro names, gryphons, skin on/off (after a `/reload`). Empty-slot strength, rim strength and font size wait for the first in-game look: their numbers are tuned to the owner's eye first, then exposed if still wanted. |
| `GlassActionBars.lua` | Bootstrap (copy GlassMail): `DEFAULTS` stored as a sparse table with an `__index` fallback, setters shared by `/gab` and the options page, `MEASURED_ON_BUILD` warning. |

`Buttons.lua`:
- **Shared builder, `Build(btn, regions)`:**
  - Glass on mouse-disabled child frames, using LibGlass `Pill`/`Mask` with the `body_mask_small` and `rim_thin_small` sets.
  - The rim sits over the icon edge. The icon is **not** moved: stock cooldowns anchor inside the icon, so insetting it would shrink their coverage.
  - Sets the `HotKey` font (top-right) and the `Count` font (bottom-right).
  - `SetOccupied(btn, bool)` switches between a faint rim (empty) and a bright rim (has an action).
- **Family adapters** (each says which writers to hook and how to read whether a slot is filled):
  - **Action buttons:**
    - Re-fade `NormalTexture`, `SlotArt` and `SlotBackground`, and re-apply the pushed styling, after `UpdateButtonArt`, which resets the pushed atlas too.
    - Read the filled state from `HasAction(btn.action)` after `Update`.
  - **Stance:** hook `StanceBar:UpdateState`.
  - **Pet:** hook `PetActionBar:Update`, which runs per bar, re-read every pet button from the pet API, and fill in each button from it.
- **Left to Blizzard:** the checked texture's alpha (only its colour is restyled), proc glow, range and usable tint, and cooldowns. Secret values stay on Blizzard's own untainted path.

Every builder runs under `pcall` and reports failures through `API.Fail`, as in GlassMail.

Tests:
- Stub templates for the action, stance and pet buttons.
- A no-field-write check on Blizzard frames.
- `strictLockdown` fails any change to a protected frame in combat.
- Re-fade after each hooked writer.
- Failure isolation: one bad button doesn't stop the others.
- Skinning a hidden or reparented stock button raises no errors.

Release v0.1.0 following `References/Docs/RELEASING.md`: an alpha tag first, then `Tools/check_package.py` on CurseForge's zip, screenshots, and a CHANGELOG section.

## Phase 2, v0.2.0: dock, provider API, Utility bar and fade

**`Dock.lua`**
- **Targets:** a smart bar docks to one of the **8 stock bars** only (no chaining), on a side (L/R/T/B) with an alignment and a gap. The mockup needs nothing more.
- **Position:** computed out of combat from the **union rectangle of the target bar's slot containers**. Empty slots are kept as spacers, so this also covers multi-row and reversed bars.
  - The result is converted to UIParent absolute coordinates (`effectiveScale / UIParent:GetEffectiveScale()`), so our protected frames are never anchored to Blizzard's.
  - If the target is unavailable (hidden, replaced or without a rectangle), the bar keeps its last docked position. If it never had one, it stays in the provider's standalone placement.
  - `OnHosted(true)` is sent only once a **valid target** is found, and the first placement is a transaction: `OnHosted(true)`, `Layout`, place, then hosted. Anything short of that (a callback throwing, an unreadable size) is followed by `OnHosted(false)`, so a provider never stops positioning a bar GAB didn't place. (Codex review of #7.)
- **When it recomputes:** at world entry, on `EDIT_MODE_LAYOUTS_UPDATED`, on UI-scale changes, after deferred hooks on the bar's grid and shown-button updates, and from `RequestLayout`.
  - A light geometry poll runs while Edit Mode is open, because its sliders fire no events, plus one final refresh when it closes.
  - All of it is coalesced to one pass per frame, and deferred to after combat when needed.
- **Geometry match:** icon size and padding from the target bar's Edit Mode settings. Port `API.ActionBarLayout(n)` and `ACTION_BARS` from `Apotheca/ApothecaCompat.lua`. Geometry is passed in the **client frame's own units**: `size` and `padding` scaled by `UIParent:GetEffectiveScale() / frame:GetEffectiveScale()`; `rows` (a count) and `orientation` (`Enum.ActionBarOrientation`) raw.

**`API.lua`** (`GlassActionBars.PUBLIC_API_VERSION = 1`, checked with `==`; same rules as AltStable `PublicAPI.lua`, whose name it shares because `GlassActionBars.API` is the client adapter. The contract is `docs/PUBLIC-API.md`; Codex review of #8.)
- **`RegisterBar{ id, label, frame, Layout(geom), OnHosted(isHosted), default }`.** No `Buttons()`: the provider calls `SkinButton` itself.
  - `OnHosted(true)` is called before the host's first `Layout`. From then on the provider stops its own position, drag, scale and geometry polling, but keeps arranging its own contents (and calls `RequestLayout` when they change).
  - `OnHosted(false)` is called after the host lets go, when the bar is undocked in options or GAB is disabled. The provider then restores its own saved position and layout.
  - `Layout(geom)` is called on every placement, always out of combat: `{size, padding, orientation, rows}` when matching, `nil` ("your own geometry") otherwise.
- **`RegisterButton{ id, label, icon, OnClick, binding, tooltip, IsEnabled, OnHosted(isHosted) }`.**
  - The host creates an insecure button in the Utility bar, and the user orders it like a native action.
  - `OnHosted` reports whether the button is **actually shown**: it is false when the Utility bar is off or the button is hidden. Portal Roulette hides its own launcher only while it is true.
  - Clicks are refused in combat when `IsEnabled()` says so.
  - Hotkey text comes from `GetBindingKey(binding)`, refreshed on `UPDATE_BINDINGS`. The provider keeps owning the binding.
- **`RequestLayout(id)`:** coalesced and non-recursive. A call from inside `Layout` is ignored.
- **`SkinButton(btn, regions)`:** takes explicit regions (`icon, normal, pushed, highlight` Textures; `hotkey, count, name` FontStrings; `cooldown`), each checked against its type, and assumes no Blizzard fields. Queued in combat. Not undone on undock.
- **Registration:** accepted at any time and queued until login. Duplicate ids are ignored, required fields are validated, and every provider callback runs under `xpcall(geterrorhandler)`.
- **Deferred:** providers handing over their own secure frames, and a `THEME_CHANGED` callback.

**`Utility.lua`**
- Port `Apotheca/ApothecaUtility.lua` (496 lines): `ACTIONS`, `KnownSpell`, `Collect`/`Reconcile`, and the combat `pending` flag. Port Apotheca's `GridLayout` and `ShortKey` too; the skin comes from `Build`.
- Cooldowns:
  - **Spells** use 123's duration-object path (`123/Core/SecureAction.lua` `ApplySpellCooldown`), as Bartender's LibActionButton does.
  - **Items** (only Hearthstone) have no item duration-object API on this client. They use the use-spell's duration if the probe confirms it works, and otherwise 123's `ApplyItemCooldown`.
  - The Hearthstone swipe in combat is an explicit acceptance check.
- Secure buttons are named `GlassActionBarsUtil_<key>`, with `CLICK` entries in a new `Bindings.xml` (`category=`).
- Buttons registered by providers appear in the same order list.

**Apotheca settings import**
- At `PLAYER_LOGIN`, if `ApothecaDB` exists and the **saved** GAB DB has no `utility` table: deep-copy the active Apotheca profile's `utility` table (`enabled`, `show`, `order`, layout) into the saved DB.
  - The check must run against the persisted table before any `__index` defaults apply, otherwise a default table would block the first import.
  - From then on the saved DB owns its own `utility` table.
- The position lives in `ApothecaCharDB.utility` and is not imported: the bar docks instead.
- No flag is needed, because once GAB has its own utility settings the import never runs again.
- **Key bindings are not migrated automatically.** Binding sets can be per-account or per-character, which makes auto-migration fragile. Options get a **"Move my Apotheca utility keybinds"** button instead. Out of combat, for the current binding set, it:
  - rebinds every key of each `CLICK ApothecaUtil_<k>:LeftButton` to `CLICK GlassActionBarsUtil_<k>:LeftButton`, skipping a key already bound to a GAB action;
  - checks each write with `GetBindingAction` and prints any failures;
  - then saves with `SaveBindings(GetCurrentBindingSet())`.
  It is safe to run again, and runs per character as needed.

**Bar fade** (an idea from Bartender4's `Bar.lua` `fadeout`/`fadeoutalpha`/`fadeoutdelay`):
- Per stock bar: fade to an alpha when out of combat, or when the mouse isn't over the bar.
- Uses `SetAlpha` only, never show or hide, so no state driver is needed. It ships only if the probe confirms bar `SetAlpha` works in combat.
- The "mouse is over the bar" check also counts an open `SpellFlyout` whose parent button belongs to that bar. The flyout is parented to the button and inherits the bar's alpha; Bartender4 does the same in `Bar.lua`. Acceptance check: open a flyout, move onto it, and the bar stays opaque.

**Options:** a Dock tab (per bar: docked, target, side, alignment, gap, match size), a Utility tab (show/order, reusing Apotheca's `EnableRowDrag` pattern, plus the keybind button) and a Fade tab.

**Tests:**
- Dock maths against mocked multi-row and reversed rects.
- Unavailable targets: a replaced target never ends a provider's own placement, and `OnHosted` arrives only after the first valid placement.
- Flyout counts as mouseover.
- Edit Mode poll start and stop; combat deferral.
- API validation, error isolation, `OnHosted` ordering, non-recursive `RequestLayout`.
- The import runs only when GAB has no utility settings.
- The keybind mover: skips conflicts, verifies, and is safe to run again.
- Every utility key has a `Bindings.xml` line (port `test_utility`).

## Phase 3: provider adoption (separate issue and PR in each repo)

Each provider adds `## OptionalDeps: GlassActionBars` and runs `if GlassActionBars and GlassActionBars.PUBLIC_API_VERSION == 1` at `PLAYER_LOGIN`.

- **Portal Roulette:**
  - `RegisterButton{ id="portalroulette", OnClick=PortalRoulette_Toggle, binding="PORTALROULETTE_TOGGLE", OnHosted=... }`.
  - While hosted, hide the floating launcher and skip the "drag the macro" prompt. Restore both when it is no longer hosted.
- **Apotheca:**
  - `RegisterBar` around `ApothecaFrame`. `Layout(geom)` feeds `GridLayout`; `OnHosted` turns off the Alt-drag, `RestorePosition` and the `matchBar` layout poll. `RequestLayout` is called after `UpdateAllButtons`.
  - **Profession-bar handoff:** when GAB is present with the Utility bar on, the hand-over becomes a lasting condition in `Utility.Reconcile`.
    - It clears the `ApothecaUtil_*` secure attributes out of combat, because measurements show hidden buttons still fire their key bindings.
    - It keeps the bar hidden, prints a one-time hint, and restores standalone behaviour when the condition ends.
    - The profession bar is removed in a later Apotheca major.
  - Apotheca's "no libraries" rule is unaffected, because no library is needed.
- **123:** `RegisterBar` with a compact layout mode (only the 5 secure buttons in a grid, no pill or labels). `OnHosted` stops `ApplyScale` and the shift-drag.

## Verification

- `pwsh tests/run.ps1` locally. CI must pass: luac, tests, packager dry run, zip allowlist.
- `Tools/deploy.ps1`, then in game with `/console taintLog 1`:
  - Press keybinds.
  - Page bars and swap stance or form in combat.
  - Watch cooldown swipes in combat (secret values).
  - Check the pet bar.
  - Toggle Edit Mode "Hide Bar Art", "Always show buttons" and rows/size, then `/reload`.
  - Check there is no `ADDON_ACTION_BLOCKED` and no taint lines that blame GAB.
  - Compare against the mockup.
- v0.2 adds:
  - Docks follow Edit Mode moves live, and a change during combat applies after combat.
  - Hosting and undocking restore the provider's own position.
  - The keybind mover works under both account and character binding sets.
  - Apotheca's old utility keys do nothing once it is hosted.
  - The Portal Roulette button opens the wheel, the floating launcher comes back when the Utility bar is off, and the button is refused in combat.
- Releases: alpha tag → `Tools/check_package.py` on CurseForge's zip → `vX.Y.Z` tag → GitHub Release made by the workflow.
