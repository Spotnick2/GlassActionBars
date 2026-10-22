# Glass Action Bars

The liquid-glass look of the Glass addons for **World of Warcraft: Forever**'s own action bars.
It keeps Blizzard's bars, so paging, key bindings, Edit Mode and cooldowns work exactly as they
always do; only the look changes.

![Three rows of twelve glass action buttons and a block of twelve beside them, in game: crisp light rims lit from the top, clear glass on the empty slots, spell icons framed by the rim](https://raw.githubusercontent.com/Spotnick2/GlassActionBars/main/docs/images/bars.png)

## Install

Install **Glass Action Bars** from
[CurseForge](https://www.curseforge.com/wow/addons/glass-action-bars), either with the
CurseForge app or by unzipping it into the `Interface\AddOns` folder inside your Forever game
folder. Then `/reload`, or start the game. There is nothing to set up.

## What it does

**Glass on every bar**: the main bar, the seven extra bars, the stance bar and the pet bar. Each
button gets a thin glass rim, lit from the top, and a glass body. A slot with an action gets
the full rim and an empty one is a pale frosted tile; pressing a button lights its rim. The main
bar's frame art and dividers fade away, and so do the gryphons unless you keep them.

**Pearl glass** by default: a soft light and a quiet outline. A frosted empty slot is a grey,
recessed tile, and a filled one has a soft reflection over the top of its icon. Pearl, Clean or
Classic, on the options page or with `/gab material` (after a `/reload`).

**Button feedback**: how a button answers the pointer (Blizzard's glow, a warm halo, or nothing),
a click (the flash, a ripple from the pointer, or nothing), and how empty slots show (hidden to
frosted). The **Glass**, **Soft** and **Minimal** presets set them all, on the **Buttons**
options page or with `/gab look`.

**The bag bar and the micro menu match.** The backpack, bag slots, reagent bag and key ring get
the same glass; an empty bag slot, or a key ring with no keys, is a plain frosted tile like an
empty action slot, and still takes clicks and dropped bags. The micro menu loses Blizzard's
bronze frames and dark panel: each button sits on its own glass tile, or all of them on one glass
pill (`/gab micro tiles/pill`, or the options page).

![The micro menu above the bag bar, the backpack and bags on glass](https://raw.githubusercontent.com/Spotnick2/GlassActionBars/main/docs/images/bags-micro.png)

**Blizzard's bars, not a replacement.** Paging, stances and forms, key bindings, Edit Mode
layouts, cooldowns, range and proc glows all stay the game's own, in and out of combat.

**Three tints**, switched live: clear, smoked and class colour glass.

**The Utility bar**: your Hearthstone, Cooking, First Aid, Fishing, your professions and their
actions (Disenchant, Smelting, Find Herbs, Pick Lock...), and your camping items: a campfire kit
whenever you carry one, the camp features when you are near a campfire. It shows only what this
character can use, docks right of the main bar and matches its buttons, and every action has a
key binding (Esc > Options > Keybindings > Glass Action Bars). **Alt-drag** it to put it anywhere
instead. Choose and order its buttons on the **Utility bar** options page; other addons can add
theirs there too (unticked until you turn them on).

**Dock**: smart bars dock beside one of Edit Mode's Action Bars 1-8 and follow it, matching its
button size and spacing, its rows and direction, or both (the **Dock** options page, `/gab dock`).

**Bar fade**: any bar can fade until you point at it, or only out of combat. It comes back while
you drag something to it, open its flyout, use Edit Mode or Quick Keybind mode, or have the
spellbook open (the **Bar fade** options page, `/gab fade`).

**With the other Glass addons**:
- With Glass UI's "Use Glass UI appearance" on for Glass Action Bars, the glass, the tint and the
  button feedback follow Glass UI's look, live; anything you set here stays yours.
- When Glass Unit Frames slides your player and pet frames beside the raid grid, the stance and
  pet bars move with them (`/gab follow`). Your Edit Mode layout is never changed: a bar in its
  default place, or snapped to another bar, stays put until you move it once in Edit Mode.
- Glass Raid Frames' grid keeps clear of the bars along the screen's sides.

## Commands

`/gab help` lists them; the same settings are on the options page (Esc > Options > AddOns >
Glass Action Bars).

- `/gab theme clear/smoked/class|suite` - the glass's tint (`suite`: Glass UI's)
- `/gab material pearl/clean/classic` - the glass itself (after a `/reload`)
- `/gab look glass|soft|minimal`, `/gab look hover|press|empty <choice>` - button feedback
- `/gab hotkeys on/off`, `/gab macros on/off` - key bindings and macro names on the buttons
- `/gab gryphons on/off` - the main bar's end caps
- `/gab micro tiles/pill` - the micro menu's glass
- `/gab skin on/off` - glass, or Blizzard's own art (after a `/reload`)
- `/gab tune` - the glass's numbers (rim, empty slots, inner line, haze, body), live
  (with Pearl, also `gloss`, the reflection on filled buttons, and `socketShade`, an empty
  slot's dark top edge)
- `/gab fade 1-8|stance|pet|all off/mouseover/combat` - fade a bar until you point at it, or out
  of combat; `/gab fade alpha 0..1` - how faded
- `/gab utility on/off` - the Utility bar
- `/gab dock` - where smart bars dock: `/gab dock <bar> 1-8|off [side] [align]`,
  `<bar> gap 0-32`, `<bar> match on/off`, `<bar> rows on/off`
- `/gab follow [on/off]` - the stance and pet bars follow Glass Unit Frames, and why a bar stays
- `/gab options` - the options page; `/gab version` - the addon's version and the client build

## For addon authors

Other addons can dock their bars beside an action bar, put their buttons on the Utility bar, and
wear the same glass on their own buttons: [docs/PUBLIC-API.md](https://github.com/Spotnick2/GlassActionBars/blob/main/docs/PUBLIC-API.md).

## What's next

The plan is [docs/PLAN.md](https://github.com/Spotnick2/GlassActionBars/blob/main/docs/PLAN.md). Next: importing Apotheca's profession bar settings and
key bindings into the Utility bar, and Apotheca, 123 and Portal Roulette adopting the API.

## License

MIT, see [LICENSE](https://github.com/Spotnick2/GlassActionBars/blob/main/LICENSE). The bundled LibGlass-1.0 keeps its own MIT license.
