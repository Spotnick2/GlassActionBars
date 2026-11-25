# Changelog

## v1.2.0 - 2026-11-25

- **Proc alerts**, Glass Action Bars' own, in place of SpellActivationOverlay, with three
  switches on the new **Proc alerts** options page: Blizzard's proc art on the screen around your
  character, a ring on the action button of the spell to press, and a sound. Each alert uses the
  ones it has: Missile Barrage shows its art and plays the sound, but rings no button; Execute
  only rings its button. The page also sets the art's opacity, size and spacing.
  - Alerts for every class, from SpellActivationOverlay's Forever ones: buffs and target effects
    such as the mage's Missile Barrage, Clearcasting, Fingers of Frost, Heating Up and a frozen
    target, and the Revelation weapon enchant for the classes that have one. A character only
    gets its own class's.
  - They work in combat: the game's own aura engine shows the buff and target alerts, since
    addons can't read procs in a fight on this client.
  - **Ready alerts** for the abilities that light up when they become usable, from the spell's
    usability and cooldown: Overpower, Execute, Revenge and Victory Rush; Counterattack and
    Mongoose Bite; Hammer of Wrath; Riposte. Ice Barrier, Holy Shock and Stormstrike are there
    too, off until you tick them. Exorcism isn't one: whether the target is a demon or undead
    may be hidden from addons in combat.
  - Untick any alert on the page. The rings show on Action Bars 1-8 and fade with their bar.
  - With SpellActivationOverlay loaded, they start off so you don't get both: tick them and turn
    SpellActivationOverlay off.
  - A change made in combat or during a boss encounter waits for it to end.
  - The mage's alerts were checked in game. The other classes' come from SpellActivationOverlay's
    data and are checked as they are played: tell us if one is wrong.
- `/gab procs` lists what each alert reports, for a bug report.
- Checked on the 1.60.1.71037 client.

## v1.1.1 - 2026-11-18

- **The button glass now comes from LibGlass**, the library the Glass addons share, so Apotheca
  can give its buttons the same look without Glass Action Bars. Your bars look the same.
- Checked on the 1.60.1.70959 client.
- For addon authors: `SkinButton` returns `false, "skinned by another addon's glass"` for a
  button that another addon's LibGlass already skins.

## v1.1.0 - 2026-11-16

- **Add spells to the Utility bar**: drag a spell from your spellbook onto it, or click a button
  with the spell on the cursor. Class buffs, resurrections, utility spells: it goes where you
  drop it, and shows on the characters that know it.
  - A spell the bar already has a button for (a profession, Feed Pet, Disenchant...) turns that
    button on instead of adding a copy.
  - Refused and left on your cursor: passive spells, items and macros (with the reason at the
    top of the screen), and anything during combat. Up to 40 added spells.
  - Added spells have a **Remove** button on the Utility bar options page.
- **Rearrange it on the bar**, out of combat: hold Shift (Blizzard's Pick Up Action key) and drag
  a button. It takes the place of the button you drop it on. Drag it off the bar to take it off:
  an added spell leaves the bar, any other button is unticked (tick it again on the options page).
  Out of combat a Shift-click never casts; in a fight it is an ordinary click.
- **Utility bar 2**, off until you tick it on its own options page: a second bar for anything the
  first one shows, such as a class's spells or Feed Pet in a column beside your action bars. It has
  its own layout, docking (by default left of Action Bar 1) and Alt-drag position. Shift-drag a
  button from one bar to the other, drop a spell on it, or use the **Bar 1 / Bar 2** buttons on
  the Utility bar options page. Turned off, its buttons show nowhere.
- An empty Utility bar keeps one empty slot, a place to drop a spell or drag a button.
- **Gardening and Tanning**: the Herbalism and Skinning buttons now cast them (each opens that
  profession's camp features), not the gathering spells, which did nothing from a bar. Your order,
  ticks and key bindings carry over.
- **The Mining button is gone**: it cast the gathering spell, and Mining has no camp feature.
  Smelting and Mining's camp features stay.
- **Russian, Korean and Chinese clients**: key bindings and counts on the buttons use a font with
  your language's letters instead of boxes.

## v1.0.2 - 2026-11-06

- `/gab` help and usage lines no longer lose letters: the choices are separated by `/`, not `|`.

## v1.0.1 - 2026-11-06

- **Comprehend Scroll** on the Utility bar, for mages who know it, with its own key binding.

## v1.0.0 - 2026-11-04

- **Feed Pet** on the Utility bar, for a hunter with a live pet out: one click (or its key
  binding) feeds your pet a food from your bags that it eats, chosen as Glass Pearls' pet care
  does: within 10 levels of the pet the cheapest, else the highest level. Its tooltip names the
  food and how many you carry. It shows only while your pet is alive and you have food it eats.
- **A padlock** on the Utility bar that locks and unlocks your action bars (Blizzard's "Lock
  Action Bars"), out of combat. Off until you tick **Lock action bars** on the Utility bar options
  page; it follows the setting when you change it in Blizzard's options too.

## v0.2.0 - 2026-10-21

- **Bar fade**: each action bar, the stance bar and the pet bar can fade until you point at it
  (`mouseover`), or fade only out of combat (`combat`). A faded bar comes back while you drag a
  spell or item to it, open its flyout, use Edit Mode or Quick Keybind mode, or have the spellbook
  open. Choose how faded it is: hidden, faint or half. On the new **Bar fade** options page, or
  `/gab fade`.
- **Pearl glass**: the glass is now LibGlass's Pearl material by default (a softer light and a
  quieter outline); choose Pearl, Clean or Classic on the options page or with
  `/gab material` (after a /reload). With Pearl, the buttons take after Final Fantasy XIV's: a
  frosted empty slot is a grey, recessed tile (a dark top edge, a light bottom lip), and a filled
  one has a soft reflection over the top of its icon (`/gab tune gloss 0` takes it off).
- **The bag bar and the micro menu**: an empty bag slot, and the key ring with no keys, is now a
  plain frosted tile like an empty action slot (it follows `/gab look`), without Blizzard's greyed
  icon. The micro buttons lose their bronze frames and sit on glass: each on its own tile, or all
  on one glass pill (`/gab micro tiles/pill`, or the options page).
- **Glass UI**: with Glass UI's "Use Glass UI appearance" on for Glass Action Bars, its material is
  Glass UI's, and its tint and button feedback follow Glass UI's look live; anything you set in
  Glass Action Bars stays yours (a "Glass UI" choice on each control goes back to following it).
- **Button feedback**, on a new **Buttons** options page (`/gab look`): how a button answers the
  pointer (off, Blizzard's glow, or a warm **halo** that fades in), a click (off, the flash, or a
  **ripple** from the pointer), and how empty slots show (hidden, faint, half, full, or **frosted**,
  a pale tile: the default). Three presets set them all: **Glass** (the default), **Soft** (halo,
  ripple, frosted empty slots) and **Minimal**.
- **The Utility bar**: your Hearthstone, Cooking, First Aid, Fishing, your professions and their
  actions (Disenchant, Smelting, Find Herbs, Pick Lock...), and your **camping** items: a campfire
  kit whenever you carry one, the camp features (Camp Chair, Mana Well, Fish Bowl...) when you are
  near a campfire. Each button shows only what this character can use. It docks right of the main
  action bar and matches its buttons; every action and campfire kit has a key binding (Esc >
  Options > Keybindings > Glass Action Bars). Hold **Alt and drag** it to put it anywhere instead,
  and choose its direction, rows, button size and spacing. Choose and order its buttons on the new
  **Utility bar** options page; `/gab utility on/off`. Other addons can add their buttons to it
  (Portal Roulette's launcher, for one): they're listed there unticked until you turn them on.
- **Dock**: smart bars dock beside one of Edit Mode's Action Bars 1-8 and follow it (the new
  **Dock** options page, `/gab dock`), matching its button size and spacing, its rows and
  direction, or both (`/gab dock <bar> match on/off`, `/gab dock <bar> rows on/off`). Their buttons,
  and the Utility bar's, wear the same glass, with rounded icons like the action bars'.
- **With Glass Unit Frames**: when it slides your player and pet frames beside the raid grid, the
  stance bar and the pet bar move with them, and come back when it lets go. Your Edit Mode layout
  is never changed. A bar still in Edit Mode's default place (stacked on Action Bar 1), or snapped
  to another bar, stays where it is: move it once in Edit Mode to let it follow (`/gab follow`
  says why a bar stays). On by default; `/gab follow on/off`. Glass Raid Frames' grid keeps clear
  of the bars along the screen's sides.

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
