-- The Utility bar's own layout and free placement: the layout settings (used
-- undocked or unmatched), undocking saves the spot, Alt-drag (the overlay,
-- undock at the drag's start, the drop saved), a drag caught by combat, the
-- options rows, saved settings cleaned.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local function close(a, b) return type(a) == "number" and type(b) == "number" and math.abs(a - b) < 1e-6 end

WoW.layoutBar(MainActionBar, 500, 100)          -- bar 1: 500..1062 x 55..100
WoW.known[3413] = true                          -- Cooking
WoW.items[6948] = 1                             -- Hearthstone
WoW.items[279981] = 1                           -- Basic Campfire Kit
local GAB = loadAddon()
local U, Settings, Dock = GAB.Utility, GAB.Settings, GAB.Dock
local F, M, P = U.frame, U._test.mover, U._test.poller
for _, b in pairs(U.buttons) do b._protected = true end
F._protected = true                             -- it parents secure buttons
WoW.tick(); WoW.tick()
eq(next(GAB.failures), nil, "nothing failed")
check(Dock.IsHosted("utility"), "docked by default")
eq(rawget(GAB.db, "utility"), nil, "nothing saved yet")
check(F._movable, "the frame is movable")

-- Its own layout: validated, ignored while matching a docked bar.
eq(Settings.SetUtilityLayout("rows", 13), false, "rows 13 refused")
eq(Settings.SetUtilityLayout("rows", 1.5), false, "  1.5 rows refused")
eq(Settings.SetUtilityLayout("orientation", "DIAGONAL"), false, "  an unknown direction refused")
eq(Settings.SetUtilityLayout("iconSize", 70), false, "  size 70 refused")
eq(Settings.SetUtilityLayout("bogus", 1), false, "  an unknown key refused")
eq(rawget(GAB.db, "utility"), nil, "  a refusal saves nothing")
check(Settings.SetUtilityLayout("iconSize", 30), "size 30")
WoW.tick()
check(close(U.buttons.cooking:GetWidth(), 45), "  docked and matched: the bar's 45 still")
Settings.SetDock("utility", "match", false)
Settings.SetDock("utility", "matchRows", false)
WoW.tick()
check(close(U.buttons.cooking:GetWidth(), 30), "  nothing matched: its own 30")
Settings.SetUtilityLayout("orientation", "VERTICAL")
Settings.SetUtilityLayout("rows", 3)
Settings.SetUtilityLayout("iconPadding", 2)
WoW.tick()
check(close(F:GetWidth(), 94) and close(F:GetHeight(), 30), "  vertical, 3 columns, 3 buttons: 3 wide, 1 high")
Settings.SetUtilityLayout("orientation", "HORIZONTAL")
check(close(F:GetWidth(), 30) and close(F:GetHeight(), 94), "  horizontal, 3 rows: 1 wide, 3 high")
Settings.SetUtilityLayout("orientation", "VERTICAL")
Settings.SetUtilityLayout("rows", 2)
check(close(F:GetWidth(), 62) and close(F:GetHeight(), 62), "  vertical, 2 columns: 2 by 2")
-- The size matched, the rows not (#48): the bar's 45, our own direction and
-- count (vertical, 3 columns: 3 wide, 1 high; horizontal would be 1 by 3).
Settings.SetUtilityLayout("rows", 3)
Settings.SetDock("utility", "match", true)
WoW.tick()
check(close(U.buttons.cooking:GetWidth(), 45), "size matched, rows not: the bar's 45")
check(F:GetWidth() > F:GetHeight() * 2, "  our own vertical 3 columns kept: 3 wide, 1 high")
Settings.SetDock("utility", "match", false)
Settings.SetUtilityLayout("rows", 2)
WoW.tick()

-- Undocking with no saved spot saves where the dock had it.
F._rect = { 1066, 1128, 162, 100 }             -- left, right, top, bottom
Settings.SetDock("utility", "bar", false)
WoW.tick()
check(not Dock.IsHosted("utility"), "undocked")
local pos = GAB.db.utility.pos
check(pos and pos.x == 1066 and pos.y == 100, "  the docked spot saved")
local p = F._points[1]
check(p and p[1] == "BOTTOMLEFT" and p[3] == "BOTTOMLEFT" and close(p[4], 1066) and close(p[5], 100),
    "  anchored bottom-left there")
Settings.SetDock("utility", "bar", 1)
WoW.tick()
check(Dock.IsHosted("utility"), "docked again")

-- The overlay: Alt held over the bar, out of combat; either order.
WoW.altDown = true
WoW.fire("MODIFIER_STATE_CHANGED", "LALT", 1)
check(not M:IsShown(), "Alt away from the bar: no overlay")
check(P:GetScript("OnUpdate") ~= nil, "  but polling while Alt is held")
WoW.hover[F] = true
WoW.tick(0.1)
check(M:IsShown(), "the pointer reaches the bar, Alt held: the overlay")
WoW.altDown = false
WoW.fire("MODIFIER_STATE_CHANGED", "LALT", 0)
check(not M:IsShown(), "Alt released: gone")
eq(P:GetScript("OnUpdate"), nil, "  polling stopped")
WoW.altDown = true
WoW.fire("MODIFIER_STATE_CHANGED", "LALT", 1)
check(M:IsShown(), "over the bar, then Alt: the overlay")
WoW.combat = true
WoW.tick(0.1)
check(not M:IsShown(), "  never in combat")
WoW.combat = false
WoW.tick(0.1)
check(M:IsShown(), "  back after it")

-- A drag: undocked at its start; nothing re-places the bar until the drop.
M:GetScript("OnDragStart")(M)
check(F._moving, "Alt-drag: moving")
eq(Dock.Setting("utility", "bar"), false, "  undocked at the drag's start")
F._points = { { "UNDER THE POINTER" } }
WoW.tick()
Dock.Request()
WoW.trigger("EditMode.Enter")
WoW.fire("BAG_UPDATE_DELAYED")
WoW.tick(0.3); WoW.tick(0.3)
WoW.trigger("EditMode.Exit")
WoW.tick()
eq(F._points[1][1], "UNDER THE POINTER", "  no dock pass or rebuild moved it mid-drag")
F._rect = { 1700, 1762, 900, 838 }
M:GetScript("OnDragStop")(M)
check(not F._moving, "the drop: stopped")
p = F._points[1]
check(p and p[1] == "BOTTOMLEFT" and close(p[4], 1700) and close(p[5], 838), "  anchored where it was dropped")
check(GAB.db.utility.pos.x == 1700 and GAB.db.utility.pos.y == 838, "  the spot saved")

-- Re-docked then undocked: the saved spot, not the docked one.
Settings.SetDock("utility", "bar", 1)
WoW.tick()
F._rect = { 1066, 1128, 162, 100 }
Settings.SetDock("utility", "bar", false)
WoW.tick()
p = F._points[1]
check(p and close(p[4], 1700) and close(p[5], 838), "undocked again: back at the saved spot")
eq(GAB.db.utility.pos.x, 1700, "  the saved spot kept")

-- Combat coming: PLAYER_REGEN_DISABLED (before lockdown) stops the drag where it is.
M:GetScript("OnDragStart")(M)
F._rect = { 1600, 1662, 800, 738 }
WoW.fire("PLAYER_REGEN_DISABLED")
check(not F._moving, "a fight starting: the drag stopped before lockdown")
eq(GAB.db.utility.pos.x, 1600, "  where it was")
WoW.combat = false

-- Lockdown already on: the stop waits, the overlay stays, combat's spot wins.
M:GetScript("OnDragStart")(M)
WoW.combat = true
F._rect = { 1500, 1562, 700, 638 }
WoW.tick(0.1)
local dragging, stopPending = U._test.dragging()
check(dragging and stopPending, "lockdown mid-drag: the stop pending")
check(F._moving, "  no StopMovingOrSizing in combat")
check(M:IsShown(), "  the overlay keeps clicks off the buttons")
eq(#WoW.violations, 0, "  no protected change in combat")
F._rect = { 100, 162, 400, 338 }                -- the pointer wandered on
WoW.altDown = false
WoW.combat = false
WoW.fire("PLAYER_REGEN_ENABLED")
check(not F._moving, "the fight over: stopped")
p = F._points[1]
check(p and close(p[4], 1500) and close(p[5], 638), "  where combat caught it")
eq(GAB.db.utility.pos.x, 1500, "  saved there")
check(not M:IsShown(), "  the overlay gone")

-- The options page: the layout rows.
GAB.Options.utilityPage:Show()
local rows = GAB.Options._test.utilityLayout.rows
rows[3]:GetScript("OnClick")(rows[3])
eq(U.LayoutSetting("rows"), 3, "the page: Rows 3")
local dir = GAB.Options._test.utilityLayout.orientation
dir[1]:GetScript("OnClick")(dir[1])
eq(U.LayoutSetting("orientation"), "HORIZONTAL", "  Horizontal")
eq(next(GAB.failures), nil, "nothing failed")

-- Saved settings cleaned at load.
local ensure = GAB._test.ensureDefaults
GlassActionBarsDB = { utility = { rows = 1.5, iconSize = 99, orientation = "X", iconPadding = 3,
    pos = { x = 0 / 0, y = 1 } } }
local u = rawget(ensure(), "utility")
check(u.rows == nil and u.iconSize == nil and u.orientation == nil, "load: bad layout values dropped")
eq(u.iconPadding, 3, "  Apotheca's padding 3 kept")
eq(u.pos, nil, "  a NaN position dropped")
GlassActionBarsDB = { utility = { pos = { x = 10, y = 20 } } }
eq(rawget(ensure(), "utility").pos.y, 20, "  a good position kept")

done("test_utility_move")
