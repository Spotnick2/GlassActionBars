# Changelog

## Unreleased

- **Bar fade**: each action bar, the stance bar and the pet bar can fade until you point at it
  (`mouseover`), or fade only out of combat (`combat`). A faded bar comes back while you drag a
  spell or item to it, open its flyout, use Edit Mode or Quick Keybind mode, or have the spellbook
  open. Choose how faded it is: hidden, faint or half. On the new **Bar fade** options page, or
  `/gab fade`.
- **Button feedback**, on a new **Buttons** options page (`/gab look`): how a button answers the
  pointer (off, Blizzard's glow, or a warm **halo** that fades in), a click (off, the flash, or a
  **ripple** from the pointer), how empty slots show (hidden, faint, half, full), and the key text
  inside the button or **above** it, normal or large. Three presets set them all: **Glass** (the
  look so far), **Soft** and **Minimal**.
- **The Utility bar**: your Hearthstone, Cooking, First Aid, Fishing, your professions and their
  actions (Disenchant, Smelting, Find Herbs, Pick Lock...), and your **camping** items: a campfire
  kit whenever you carry one, the camp features (Camp Chair, Mana Well, Fish Bowl...) when you are
  near a campfire. Each button shows only what this character can use. It docks right of the main
  action bar and matches its buttons; every action and campfire kit has a key binding (Esc >
  Options > Keybindings > Glass Action Bars). Hold **Alt and drag** it to put it anywhere instead,
  and choose its direction, rows, button size and spacing. Choose and order its buttons on the new
  **Utility bar** options page; `/gab utility on/off`.
- **Dock**: smart bars dock beside one of Edit Mode's Action Bars 1-8 and follow it (the new
  **Dock** options page, `/gab dock`).
- **With Glass Unit Frames**: when it slides your player and pet frames beside the raid grid, the
  stance bar and the pet bar move with them, and come back when it lets go. Your Edit Mode layout
  is never changed. A bar still in Edit Mode's default place (stacked on Action Bar 1), or snapped
  to another bar, stays where it is: move it once in Edit Mode to let it follow (`/gab follow`
  says why a bar stays). On by default; `/gab follow on/off`.

## v0.1.0

- **The glass on Blizzard's own action bars**: the main bar, the seven extra bars, the stance
  bar and the pet bar. Blizzard's buttons stay, so paging, key bindings, Edit Mode and cooldowns
  work as they always do. Each button gets a glass body and a thin glass rim, bright on a slot
  with an action and faint on an empty one; pressing it lights the rim. The main bar's frame
  art and dividers fade away, and so do the gryphons unless you keep them (`/gab gryphons on`).
- **The bag bar and the micro menu** match: the backpack, bag slots, reagent bag and key ring get
  the same glass body and rim (a bag slot with a bag gets the full rim, an empty one the quieter
  one), and the micro menu sits on a subtle glass panel instead of Blizzard's dark one. The micro
  buttons keep their own icons and states.
- Three looks, switched live: **clear**, **smoked** and **class colour** glass (`/gab theme`).
- Key bindings and macro names on the buttons can each be turned off (`/gab hotkeys`,
  `/gab macros`). `/gab skin off` gives Blizzard's own art back after a `/reload`.
- `/gab tune` adjusts the glass's numbers live: rim, empty slots, inner line, haze and body.
- Every setting is also on the options page (Esc > Options > AddOns > Glass Action Bars).
