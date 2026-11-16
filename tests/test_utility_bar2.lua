-- The second Utility bar (#86, PR 2): off until turned on, its own frame,
-- dock client, layout and position; an entry assigned to it (utility.bar)
-- has its button moved onto its frame; turned off, its entries show nowhere;
-- an enabled bar with nothing on it keeps an empty slot to drop on; a Shift-
-- drag between the bars and a spellbook drop on bar 2; MoveUtility within a
-- bar; providers hosted on either bar; nothing secure changes in combat; the
-- saved settings cleaned; the options rows and the Utility bar 2 page.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local function close(a, b) return type(a) == "number" and type(b) == "number" and math.abs(a - b) < 1e-6 end

WoW.layoutBar(MainActionBar, 500, 100)
WoW.known[3413] = true                          -- Cooking
WoW.known[7620] = true                          -- Fishing
WoW.known[3273] = true                          -- First Aid
WoW.known[2006] = true                          -- a priest's Resurrection
WoW.spellNames = { [2006] = "Resurrection" }
WoW.items[6948] = 1                             -- Hearthstone
local GAB = loadAddon()
local U, Settings, Dock = GAB.Utility, GAB.Settings, GAB.Dock
local bar1, bar2 = U._test.bars[1], U._test.bars[2]
local F1, F2 = bar1.frame, bar2.frame
local function protect()
    for _, b in pairs(U.buttons) do b._protected = true end
    F1._protected, F2._protected = true, true
end
protect()
WoW.tick(); WoW.tick()
eq(next(GAB.failures), nil, "nothing failed")

local function rebuild() U.Refresh(); WoW.tick(); protect() end
local function keys(bar)
    local out = {}
    for _, b in ipairs(bar.shown) do
        local s = U._test.state[b]
        out[#out + 1] = s.placeholder and "(empty)" or s.key
    end
    return table.concat(out, " ")
end

-- Off by default; its own frame and dock client.
eq(_G.GlassActionBarsUtilityFrame2, F2, "bar 2's frame: GlassActionBarsUtilityFrame2")
eq(U.Enabled(2), false, "bar 2 off by default")
check(not F2:IsShown(), "  hidden")
eq(keys(bar1), "hearthstone cooking firstaid fishing", "bar 1 shows everything")
local ids = {}
for _, c in ipairs(Dock.Clients()) do ids[#ids + 1] = c.id .. "=" .. c.label end
eq(table.concat(ids, " "), "utility=Utility bar utility2=Utility bar 2", "two dock clients")
check(Dock.Setting("utility2", "bar") == 1 and Dock.Setting("utility2", "side") == "LEFT"
    and Dock.Setting("utility2", "align") == "END", "  bar 2 docks left of Action Bar 1, bottom-aligned")
local frames = Dock.Frames()
eq(frames[2], F2, "  its frame counted for the screen edges")
eq(rawget(GAB.db, "utility"), nil, "nothing saved yet")

-- Turned on with nothing assigned: its empty slot only.
check(Settings.SetUtilityEnabled(true, 2), "bar 2 on")
eq(GAB.db.utility.second.enabled, true, "  saved in utility.second")
eq(GAB.db.utility.enabled, nil, "  bar 1's own setting untouched")
check(F2:IsShown() and bar2.placeholder:IsShown(), "  shown, with its empty slot")
eq(keys(bar2), "(empty)", "  the slot alone")
local ph = GAB.Buttons.State(bar2.placeholder)
check(ph ~= nil and ph.occupied == false, "  skinned: the glass's empty slot")
eq(U._test.regions[bar2.placeholder].icon:GetAlpha(), 0, "  Blizzard's empty-slot art faded under it")
check(not bar1.placeholder:IsShown(), "  bar 1, not empty, has none")
eq(Settings.SetUtilityEnabled(true, 3), false, "a bar 3 refused")

-- An entry assigned to bar 2: its button moves onto bar 2's frame.
check(Settings.SetUtilityBar("fishing", 2), "Fishing to bar 2")
eq(GAB.db.utility.bar.fishing, 2, "  saved: utility.bar.fishing = 2")
eq(keys(bar2), "fishing", "  bar 2: Fishing, the empty slot gone")
check(not bar2.placeholder:IsShown(), "  the slot hidden")
eq(keys(bar1), "hearthstone cooking firstaid", "  bar 1 without it")
local fish = U.buttons.fishing
eq(fish:GetParent(), F2, "  its button on bar 2's frame")
eq(fish:GetAttribute("spell"), 7620, "  still armed")
check(fish:IsShown(), "  shown")
check(close(fish:GetWidth(), 45), "  matched to the bar's 45 (docked)")
Settings.SetUtilityBar("firstaid", 2)
eq(keys(bar2), "firstaid fishing", "First Aid too: the saved order kept on bar 2")
eq(Settings.SetUtilityBar("firstaid", 3), false, "a bar 3 refused")
eq(Settings.SetUtilityBar("nonsense", 2), false, "an unknown key refused")

-- MoveUtility steps within its own bar, past the other bar's keys.
local order = table.concat(U.Order(), " ", 1, 4)
eq(order, "hearthstone feedpet cooking firstaid", "the order: bar 2's First Aid after bar 1's Cooking")
check(Settings.MoveUtility("fishing", -1), "Fishing up on bar 2")
eq(keys(bar2), "fishing firstaid", "  above First Aid")
eq(keys(bar1), "hearthstone cooking", "  bar 1 unchanged")
eq(Settings.MoveUtility("fishing", -1), false, "  the top of bar 2: refused, though bar 1 has keys above")
check(Settings.MoveUtility("cooking", 1), "Cooking down on bar 1")
eq(table.concat(U.Order(), " ", 3, 6), "baittackle fishing firstaid cooking",
    "  swapped with bar 1's next key, past bar 2's (which keep their places)")

-- Bar 2 off: its entries show nowhere, without their attributes.
Settings.SetUtilityEnabled(false, 2)
check(not F2:IsShown(), "bar 2 off: hidden")
eq(keys(bar1), "hearthstone cooking", "  bar 1 doesn't take its entries")
check(not fish:IsShown() and fish:GetAttribute("type") == nil, "  Fishing hidden, no attributes")
check(not bar2.placeholder:IsShown(), "  no empty slot on a bar that's off")
-- Bar 1 off, bar 2 on: each its own.
Settings.SetUtilityEnabled(true, 2)
Settings.SetUtilityEnabled(false)
check(not F1:IsShown() and F2:IsShown(), "bar 1 off, bar 2 on: only bar 2")
eq(keys(bar2), "fishing firstaid", "  with its entries")
check(not U.buttons.cooking:IsShown() and U.buttons.cooking:GetAttribute("type") == nil, "  bar 1's Cooking cleared")
Settings.SetUtilityEnabled(true)

-- Back to bar 1: back on its frame, nothing stored.
Settings.SetUtilityBar("firstaid", 1)
Settings.SetUtilityBar("fishing", 1)
eq(fish:GetParent(), F1, "Fishing back: on bar 1's frame")
eq(GAB.db.utility.bar, nil, "  utility.bar emptied away")
eq(keys(bar2), "(empty)", "  bar 2 empty again: its slot")

-- Geometry for the pointer: bar 1's buttons in a row at y 64..100, bar 2's
-- (or its slot) at 400..436, y 64..100.
local function layout()
    for i, b in ipairs(bar1.shown) do b._rect = { 1000 + (i - 1) * 40, 1036 + (i - 1) * 40, 100, 64 } end
    F1._rect = { 1000, 996 + #bar1.shown * 40, 100, 64 }
    for i, b in ipairs(bar2.shown) do b._rect = { 400 + (i - 1) * 40, 436 + (i - 1) * 40, 100, 64 } end
    F2._rect = { 400, 396 + #bar2.shown * 40, 100, 64 }
end
local function on(b, side)
    WoW.cursor = { side == "trailing" and b._rect[2] - 4 or b._rect[1] + 4, 82 }
end
local function shiftDrag(b, target, side)
    rebuild(); layout()
    WoW.pickupDown = true
    WoW.press(b, "LeftButton", { drag = true, during = function() on(target, side) end })
    WoW.pickupDown = false
end

-- A Shift-drag onto bar 2's empty slot: the entry moves to bar 2.
shiftDrag(U.buttons.cooking, bar2.placeholder, "leading")
eq(keys(bar2), "cooking", "Shift-drag onto bar 2's empty slot: Cooking on bar 2")
eq(keys(bar1), "hearthstone fishing firstaid", "  off bar 1")
eq(GAB.db.utility.bar.cooking, 2, "  saved")
eq(U.buttons.cooking:GetParent(), F2, "  its button on bar 2's frame")
eq(WoW.takeDispatched(), "", "  nothing cast")
-- Between the bars, before or after the target.
shiftDrag(U.buttons.fishing, U.buttons.cooking, "leading")
eq(keys(bar2), "fishing cooking", "onto Cooking's leading half on bar 2: before it")
shiftDrag(U.buttons.hearthstone, U.buttons.cooking, "trailing")
eq(keys(bar2), "fishing cooking hearthstone", "  onto its trailing half: after it")
eq(keys(bar1), "firstaid", "  bar 1 keeps First Aid")
shiftDrag(U.buttons.cooking, U.buttons.firstaid, "leading")
eq(keys(bar1), "cooking firstaid", "and back to bar 1, before First Aid")
eq(GAB.db.utility.bar.cooking, nil, "  bar 1: nothing stored for it")
eq(U.buttons.cooking:GetParent(), F1, "  its button back on bar 1's frame")
-- Within bar 2, the slot-taking rule (#88) still holds.
shiftDrag(U.buttons.fishing, U.buttons.hearthstone, "leading")
eq(keys(bar2), "hearthstone fishing", "within bar 2, forward onto a left half: after it")
-- Off both bars: unticked, wherever it was.
rebuild(); layout()
WoW.pickupDown = true
WoW.press(U.buttons.hearthstone, "LeftButton", { drag = true, during = function() WoW.cursor = { 700, 600 } end })
WoW.pickupDown = false
eq(U.IsShown("hearthstone"), false, "dragged off the bars: unticked")
eq(keys(bar2), "fishing", "  gone from bar 2")
Settings.SetUtilityShown("hearthstone", true)
eq(keys(bar2), "hearthstone fishing", "ticked again: back on bar 2")

-- A spellbook drop on bar 2: a new spell lands there.
rebuild(); layout()
on(U.buttons.fishing, "trailing")
WoW.cursorInfo = { "spell", 12, "spell", 2006 }
U.buttons.fishing:GetScript("OnReceiveDrag")(U.buttons.fishing)
WoW.flushTimers(0)
eq(WoW.cursorInfo, nil, "a spell dropped on bar 2: taken")
eq(keys(bar2), "hearthstone fishing spell:2006", "  after Fishing on bar 2")
eq(GAB.db.utility.bar["spell:2006"], 2, "  assigned to bar 2")
eq(_G.GlassActionBarsUtilSpell_2006:GetParent(), F2, "  its button made on bar 2's frame")
-- Removed: its assignment goes with it.
Settings.RemoveUtility("spell:2006")
eq(GAB.db.utility.bar["spell:2006"], nil, "removed: its bar gone too")
-- A drop on an empty bar's slot.
Settings.SetUtilityBar("hearthstone", 1)
Settings.SetUtilityBar("fishing", 1)
rebuild(); layout()
eq(keys(bar2), "(empty)", "bar 2 empty")
WoW.cursorInfo = { "spell", 12, "spell", 2006 }
bar2.placeholder:GetScript("OnReceiveDrag")(bar2.placeholder)
eq(keys(bar2), "spell:2006", "a spell dropped on the empty slot: on bar 2")
-- A click with a spell on the cursor places too; without one, nothing.
Settings.RemoveUtility("spell:2006")
rebuild(); layout()
bar2.placeholder:GetScript("OnClick")(bar2.placeholder, "LeftButton")
eq(keys(bar2), "(empty)", "a click on the empty slot with nothing on the cursor: nothing")
WoW.cursorInfo = { "spell", 12, "spell", 2006 }
bar2.placeholder:GetScript("OnClick")(bar2.placeholder, "LeftButton")
eq(keys(bar2), "spell:2006", "  with a spell on the cursor: placed")
Settings.RemoveUtility("spell:2006")

-- Its own layout: utility.second, used undocked or unmatched.
eq(Settings.SetUtilityLayout("iconSize", 30, 3), false, "a bar 3's layout refused")
check(Settings.SetUtilityLayout("iconSize", 30, 2), "bar 2's size 30")
eq(GAB.db.utility.second.iconSize, 30, "  saved in utility.second")
eq(U.LayoutSetting("iconSize"), U.SIZE, "  bar 1's own unchanged")
eq(U.LayoutSetting("iconSize", 2), 30, "  bar 2's read back")
Settings.SetUtilityBar("fishing", 2)
Settings.SetDock("utility2", "match", false)
Settings.SetDock("utility2", "matchRows", false)
WoW.tick()
check(close(fish:GetWidth(), 30), "  undocked from the size: its own 30")
check(close(U.buttons.cooking:GetWidth(), 45), "  bar 1's buttons still the bar's 45")

-- Undocking bar 2 saves its own spot; the Alt overlay is its own.
F2._rect = { 400, 430, 100, 70 }
Settings.SetDock("utility2", "bar", false)
WoW.tick()
local pos = GAB.db.utility.second.pos
check(pos and pos.x == 400 and pos.y == 70, "bar 2 undocked: its spot saved in utility.second")
eq(GAB.db.utility.pos, nil, "  bar 1's spot untouched")
WoW.altDown = true
WoW.hover[F2] = true
WoW.fire("MODIFIER_STATE_CHANGED", "LALT", 1)
check(bar2.mover:IsShown() and not bar1.mover:IsShown(), "Alt over bar 2: its overlay only")
bar2.mover:GetScript("OnDragStart")(bar2.mover)
check(F2._moving and not F1._moving, "  dragging bar 2")
F2._rect = { 200, 230, 300, 270 }
bar2.mover:GetScript("OnDragStop")(bar2.mover)
check(GAB.db.utility.second.pos.x == 200 and GAB.db.utility.second.pos.y == 270, "  the drop saved in utility.second")
WoW.altDown, WoW.hover[F2] = false, nil
WoW.fire("MODIFIER_STATE_CHANGED", "LALT", 0)
Settings.SetDock("utility2", "bar", 1)
WoW.tick()

-- Providers: hosted on either bar.
local hosted = {}
check(GAB.RegisterButton({ id = "roulette", icon = 1, OnClick = function() end,
    OnHosted = function(on) hosted[#hosted + 1] = tostring(on) end }), "a provider registers")
Settings.SetUtilityShown("provider:roulette", true)
WoW.tick()
Settings.SetUtilityBar("provider:roulette", 2)
WoW.tick()
local pb = _G.GlassActionBarsUtilProvider_roulette
check(pb:GetParent() == F2 and pb:IsShown(), "its button on bar 2")
eq(table.concat(hosted, ","), "true", "  OnHosted(true) once: moving bars isn't a change")
Settings.SetUtilityEnabled(false, 2)
eq(table.concat(hosted, ","), "true,false", "  bar 2 off: OnHosted(false)")
Settings.SetUtilityEnabled(true, 2)
eq(table.concat(hosted, ","), "true,false,true", "  on again: true")
eq((GAB.RegisterBar({ id = "utility2", frame = CreateFrame("Frame"), OnHosted = function() end })), false,
    "the dock id utility2 is reserved")

-- In combat: nothing moves between the bars until the fight ends.
rebuild()
WoW.combat = true
WoW.fire("PLAYER_REGEN_DISABLED")
Settings.SetUtilityBar("cooking", 2)
WoW.tick()
eq(#WoW.violations, 0, "in combat: no protected change")
eq(U.buttons.cooking:GetParent(), F1, "  Cooking still on bar 1's frame")
check(U.IsPending(), "  the rebuild pending")
WoW.combat = false
WoW.fire("PLAYER_REGEN_ENABLED")
eq(U.buttons.cooking:GetParent(), F2, "the fight over: moved")
Settings.SetUtilityBar("cooking", 1)

-- The options: rows by bar, a button to the other bar; the Utility bar 2 page.
GAB.Options.utilityPage:Show()
local rows = GAB.Options._test.utilityRows
local heads = GAB.Options._test.utilityHeads
local function y(r) return r._points[#r._points][5] end
eq(heads[2]:GetText(), "Utility bar 2", "bar 2's heading")
check(y(rows.fishing.frame) < y(heads[2]) and y(rows.cooking.frame) > y(heads[2]),
    "  Fishing listed under it, Cooking above it")
eq(rows.fishing.bar:GetText(), "Bar 1", "  Fishing's button: to bar 1")
eq(rows.cooking.bar:GetText(), "Bar 2", "  Cooking's: to bar 2")
rows.cooking.bar:GetScript("OnClick")(rows.cooking.bar)
eq(U.BarOf("cooking"), 2, "  clicked: Cooking on bar 2")
check(y(rows.cooking.frame) < y(heads[2]), "  and its row under bar 2's heading at once")
eq(rows.cooking.bar:GetText(), "Bar 1", "  its button now: to bar 1")
GAB.Options.utility2Page:Show()
local cb = GAB.Options._test.utility2Enabled
check(cb:GetChecked(), "the Utility bar 2 page: on")
cb:SetChecked(false)
cb:GetScript("OnClick")(cb)
eq(U.Enabled(2), false, "  unticked: bar 2 off")
local size = GAB.Options._test.utility2Layout.iconSize
size[4]:GetScript("OnClick")(size[4])
eq(GAB.db.utility.second.iconSize, 45, "  its size radios write bar 2's own")
eq(rawget(GAB.db.utility, "iconSize"), nil, "  not bar 1's")
eq(next(GAB.failures), nil, "nothing failed")

-- Saved settings cleaned at load.
local ensure = GAB._test.ensureDefaults
GlassActionBarsDB = { utility = { order = { "spell:2006" }, bar = { cooking = 2, hearthstone = 1, bogus = 2,
    ["spell:2006"] = 2, ["spell:5"] = 2 }, second = { enabled = "yes", rows = 99, iconSize = 40, pos = { x = "a" } } } }
local u = rawget(ensure(), "utility")
check(u.bar.cooking == 2 and u.bar["spell:2006"] == 2, "load: bar 2 entries kept")
check(u.bar.hearthstone == nil and u.bar.bogus == nil, "  a bar 1 value and an unknown key dropped")
eq(u.bar["spell:5"], nil, "  a spell not in the order dropped")
check(u.second.enabled == nil and u.second.rows == nil and u.second.pos == nil, "  bad bar 2 settings dropped")
eq(u.second.iconSize, 40, "  a good one kept")
GlassActionBarsDB = { utility = { bar = "junk", second = 7 } }
u = rawget(ensure(), "utility")
check(u.bar == nil and u.second == nil, "  junk tables dropped")

done("test_utility_bar2")
