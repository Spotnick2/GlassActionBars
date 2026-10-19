# Glass Action Bars' public API

For addons that want their bars or buttons on Glass Action Bars: dock a bar beside one of the
action bars, put buttons in glass, or offer a button for the Utility bar. Build on these
functions only: everything else in `GlassActionBars` is internal and changes without notice.

```toc
## OptionalDeps: GlassActionBars
```

Glass Action Bars is not load-on-demand, so with that line these functions exist by the time your
addon's files run. The player may not have it installed, so check the version first:

```lua
local GAB = GlassActionBars
if GAB and GAB.PUBLIC_API_VERSION == 2 then
    -- register here (at PLAYER_LOGIN, or when your bar exists)
end
```

## `GlassActionBars.PUBLIC_API_VERSION`

`2`. It changes on **any incompatible change**: a function's arguments or return values, a
field's meaning, a callback's timing or arguments, a removed function. Check it with `==`: a
provider written for 1 must not run against an incompatible 2. **Adding** a function or an
optional field does not change it: test for a newer function with `if GAB.SomeNewFunction then`.

**What changed in 2** (#48): the player matches a docked bar's button size and spacing and its
rows and direction separately, so `Layout(geom)` carries only what is matched (below): in 1,
`geom` always had all four fields. `RegisterBar`'s `default` takes `matchRows`. Everything else
is as in 1; a provider that handled `geom` field by field can accept both (on 1, ignore
`geom.rows` and `geom.orientation` if the player is meant to keep your own).

Not `GlassActionBars.API`: that is the addon's internal adapter for the client's API.

## Rules for every function

- **Arguments are checked before anything happens.** A refusal returns `false` and a reason
  string; nothing is half done.
- **Your tables are copied when accepted.** Changing your definition or region table afterwards
  changes nothing; register again under a new id if you must.
- **Your callbacks run protected.** An error in one goes to the game's error handler and to
  `/gab failures`, and never stops Glass Action Bars or another provider.
- **Nothing hands out a live internal table.**

## `GlassActionBars.RegisterBar(def)` → `true` or `false, reason`

Docks your bar frame beside one of Edit Mode's Action Bars 1-8. Where, and whether, is the
player's choice: Esc > Options > AddOns > Glass Action Bars > **Dock**, or `/gab dock`.

| Field | Type | |
|---|---|---|
| `id` | string | Required. Letters, digits and `_`; `utility` is reserved. The player's dock settings are saved under it, so keep it stable. |
| `label` | string | The name in Options. Defaults to `id`. |
| `frame` | frame | Required. The frame to place. |
| `OnHosted(isHosted)` | function | Required. See below. |
| `Layout(geom)` | function | Optional. See below. |
| `default` | table | Optional dock settings for a player who hasn't chosen: `bar` (1-8, or `false`: not docked), `side` (`LEFT`, `RIGHT`, `TOP`, `BOTTOM`), `align` (`START`, `CENTER`, `END`), `gap` (0-32), `match` (boolean: the bar's button size and spacing), `matchRows` (boolean: its rows and direction). Invalid keys are dropped. Without it, the bar is **not docked** until the player docks it. |

You can register at any time: before Glass Action Bars has finished logging in, the bar is
queued.

**`OnHosted(true)`** comes once a target bar is available, **before** the first `Layout`. From
then on the dock owns your frame's **position**: stop moving, dragging and scaling it, stop
restoring a saved position, stop any polling of your own geometry. **`OnHosted(false)`** comes when
the player undocks it, or when a first placement fails. Restore your own position and layout
then. If the target bar is hidden or missing, your bar stays where it is: it keeps its last
docked position, or, if it was never docked, it is never told it is hosted.

**`Layout(geom)`** comes on every placement, always **out of combat**:
- `geom` holds what the player chose to match; each field absent is yours to choose:
  - `size` (a button's width and height) and `padding`, in **your frame's own units**, when
    matching the bar's button size and spacing;
  - `rows` and `orientation` when matching its rows and direction. `rows` is Edit Mode's row
    count, which it calls columns on a vertical bar (the count across the bar), and
    `orientation` is 0 for horizontal or 1 for vertical (`Enum.ActionBarOrientation`).
- `geom = nil` when matching neither, or when the target's geometry can't be read: lay out with
  **your own** geometry.

Either way, size your frame to its contents before returning: the dock then places it by its
size.

**Your contents stay yours.** When your buttons change (one appears, one goes), arrange them
yourself, using the last `geom` you got or your own geometry if it was `nil`. Then call
`RequestLayout(id)` so the dock places the resized frame again.

**Combat:** nothing is moved or laid out in combat. A change waits for the fight to end.

## `GlassActionBars.RequestLayout(id)`

Ask for your bar to be laid out and placed again. Calls are combined into one pass on the next
frame, out of combat. A call from inside your own `Layout` is ignored, so it can't loop.

## `GlassActionBars.SkinButton(button, regions, owner)` → `true` or `false, reason`

Puts one of your buttons in glass: the same body, rim and pressed look as the action buttons,
with the hotkey and count in the glass font, and the player's look (tint, hover, press, empty
slots), followed live as they change it. `button` must be a Button or CheckButton.

`owner`, optional: your addon's name (`"Apotheca"`). Glass Action Bars reports it to Glass UI,
whose page then says your addon follows Glass Action Bars' look. It is an additive argument:
version 1 callers that omit it are unaffected. A request made before Glass Action Bars has built
its glass (before its `PLAYER_LOGIN`) waits, its regions and owner kept, and is built then.

`regions` names its parts, and each one is checked against its type:

| Key | Type | What happens to it |
|---|---|---|
| `icon` | Texture | Rounded to the glass's shape: a mask added on it, made on the icon's own frame (so that frame must be yours). Your own masks stay; its art, texture coordinates and anchors stay yours. Only the icon is rounded: a cooldown the size of the button keeps its square swipe. |
| `normal` | Texture | Faded. |
| `pushed` | Texture | Becomes the bright rim. |
| `highlight` | Texture | Dimmed to the glass highlight. |
| `hotkey`, `count` | FontString | The glass font. The hotkey also follows the player's "Key bindings" setting. |
| `name` | FontString | Follows the player's "Macro names" setting. |
| `cooldown` | Cooldown | Left as it is. |

Other keys are ignored. A button already in glass returns `true`. **In combat** the skin is applied
when the fight ends. If the player turned the glass off (`/gab skin off`), it returns `false`.

**The skin isn't undone** when your bar is undocked: it stays until a `/reload`. If your buttons
need their standalone look back as soon as they are undocked, don't call `SkinButton` on them;
their look is then yours.

## `GlassActionBars.RegisterButton(def)` → `true` or `false, reason`

A button for the player's **Utility bar** (Hearthstone, professions, and buttons like yours), in
the order the player chooses. Glass Action Bars builds and shows it; it is an ordinary
(insecure) button, so it can't cast spells or use items itself.

| Field | Type | |
|---|---|---|
| `id` | string | Required. Letters, digits and `_`. |
| `label` | string | The name in Options. Defaults to `id`. |
| `icon` | number or string | Required. A file ID or a texture path. |
| `OnClick(button, mouseButton)` | function | Required. |
| `binding` | string | Your key binding's command name (from your `Bindings.xml`). Its key shows on the button. The binding stays yours. |
| `tooltip` | string or function | A string, or `function(tooltip)` that fills the GameTooltip. |
| `IsEnabled()` | function | `false` refuses clicks, and dims the button. |
| `OnHosted(isHosted)` | function | `true` while the button is actually **shown** on the Utility bar, `false` when it isn't (the bar is off, or the player hid it). Hide your own launcher only while it is `true`. |

## `GlassActionBars.EdgeState()` → `{ left, right, width }` or `nil`

Where the bars at the screen's sides end, so a frame you place along a side can keep clear of
them (Glass Raid Frames' grid, Glass UI's docs/GROUP-LAYOUT.md section 5c). UIParent units from
its bottom-left, in a fresh table each call; `nil` before Glass Action Bars has measured.

- `left`: the right edge of the bars at the screen's left (`0` when there are none).
- `right`: the left edge of the bars at its right (`width` when there are none).
- `width`: UIParent's width.

**Which bars count:** Action Bars 1-8 and every bar registered with `RegisterBar` (docked or
not), the Utility bar included, when they are visible and taller than wide. On each side, a bar
counts when it starts within 40 units of the screen's edge or of the bars already counted there,
so a stack of side bars counts as one. A bar any of whose edges can't be read is skipped.

**The event** `GlassActionBars.EdgesChanged` (`left`, `right`, `width`) fires on Blizzard's
`EventRegistry`, out of combat, whenever a value moved more than half a unit from the last one
announced (Edit Mode, a bar shown or hidden, a scale change). The same values may come again:
apply the latest each time.

```lua
EventRegistry:RegisterCallback("GlassActionBars.EdgesChanged", function(_, left, right, width)
    -- keep your frame between left and right
end, MyAddon)
local e = GlassActionBars and GlassActionBars.EdgeState and GlassActionBars.EdgeState()
```

If you move a bar you registered without a dock pass (your own drag, a scale change), call
`RequestLayout(id)` afterwards so the edges are measured again.

## Example

```lua
local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function()
    local GAB = GlassActionBars
    if not (GAB and GAB.PUBLIC_API_VERSION == 2) then return end
    GAB.RegisterBar({
        id = "mybar", label = "My bar", frame = MyBarFrame,
        OnHosted = function(hosted)
            MyBar.hosted = hosted
            if not hosted then MyBar:RestorePosition() end
        end,
        Layout = function(geom)
            MyBar:Arrange(geom and geom.size or MyBar.size, geom and geom.padding or MyBar.padding)
        end,
    })
    for _, b in ipairs(MyBar.buttons) do
        GAB.SkinButton(b, { icon = b.icon, cooldown = b.cooldown, hotkey = b.hotkey })
    end
end)
```
