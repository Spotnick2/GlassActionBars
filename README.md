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
button gets a thin glass rim, lit from the top, and a clear glass body. A slot with an action gets
the full rim and an empty one a quieter one; pressing a button lights its rim. The main bar's
frame art and dividers fade away, and so do the gryphons unless you keep them.

**The bag bar and the micro menu match.** The backpack, bag slots, reagent bag and key ring get
the same glass (a slot with a bag gets the full rim, an empty one the quieter one). The micro
menu sits on a subtle glass panel instead of Blizzard's dark one, and its buttons keep their own
icons and states.

![The micro menu on a faint glass panel above the bag bar: the backpack and one bag with full rims, the empty bag slots with quieter ones](https://raw.githubusercontent.com/Spotnick2/GlassActionBars/main/docs/images/bags-micro.png)

**Blizzard's bars, not a replacement.** Paging, stances and forms, key bindings, Edit Mode
layouts, cooldowns, range and proc glows all stay the game's own, in and out of combat.

**Three looks**, switched live: clear, smoked and class colour glass.

## Commands

`/gab help` lists them; the same settings are on the options page (Esc > Options > AddOns >
Glass Action Bars).

- `/gab theme clear/smoked/class` - the glass
- `/gab hotkeys on/off`, `/gab macros on/off` - key bindings and macro names on the buttons
- `/gab gryphons on/off` - the main bar's end caps
- `/gab skin on/off` - glass, or Blizzard's own art (after a `/reload`)
- `/gab tune` - the glass's numbers (rim, empty slots, inner line, haze, body), live

## What's next

The plan is [docs/PLAN.md](docs/PLAN.md). Next, **v0.2.0**: smart bars docked to the end of a
bar (a Utility bar with your Hearthstone and professions), and an API so other addons (Apotheca,
123, Portal Roulette) can dock their bars and buttons there.

## License

MIT, see [LICENSE](LICENSE). The bundled LibGlass-1.0 keeps its own MIT license.
