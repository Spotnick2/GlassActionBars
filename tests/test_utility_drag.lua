-- Editing the Utility bar on the bar (#86): spells dropped on it (spell:<id>
-- in the order), a built-in's spell turning that entry on, refusals that keep
-- the cursor, the cap, another class's spells keeping their slot, the Shift
-- reorder drag and dragging off; the gesture guard, clicked the way the
-- client delivers clicks (WoW.press, measured on 70938): a placement or a
-- pick-up never reaches the secure action with an action on it, on either
-- ActionButtonUseKeyDown value, Feed Pet and the lock included, while a
-- Shift key binding still acts; the saved settings cleaned; the options rows.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

WoW.layoutBar(MainActionBar, 500, 100)
WoW.known[3413] = true                          -- Cooking
WoW.items[6948] = 1                             -- Hearthstone
for _, id in ipairs({ 1978, 13549, 2006, 2050, 81 }) do WoW.known[id] = true end
WoW.passive = { [81] = true }                   -- Dodge
WoW.spellNames = { [1978] = "Serpent Sting", [13549] = "Serpent Sting", [2006] = "Resurrection", [2050] = "Lesser Heal" }
WoW.spellRanks = { [1978] = "Rank 1", [13549] = "Rank 2" }
WoW.cvars.ActionButtonUseKeyDown = "1"
local GAB = loadAddon()
local U, Settings = GAB.Utility, GAB.Settings
local function protect()
    for _, b in pairs(U.buttons) do b._protected = true end
    U.frame._protected = true
end
protect()
WoW.tick(); WoW.tick()
eq(next(GAB.failures), nil, "nothing failed")

local function rebuild() U.Refresh(); WoW.tick(); protect() end
local function shown()
    local out = {}
    for _, b in ipairs(U._test.shown()) do out[#out + 1] = U._test.state[b].key end
    return table.concat(out, " ")
end
-- Rects for the shown buttons, left to right, and the bar around them.
local function layout()
    local list = U._test.shown()
    for i, b in ipairs(list) do b._rect = { 1000 + (i - 1) * 40, 1036 + (i - 1) * 40, 100, 64 } end
    U.frame._rect = { 1000, 996 + #list * 40, 100, 64 }
end
local function at(b, side)
    WoW.cursor = { side == "trailing" and b._rect[2] - 4 or b._rect[1] + 4, 82 }
end
local function away() WoW.cursor = { 300, 600 } end
local function spellOn(id) WoW.cursorInfo = { "spell", 12, "spell", id } end
local function receive(b) b:GetScript("OnReceiveDrag")(b); WoW.flushTimers(0) end
-- Nothing reached the secure action carrying an action ("" or only nils).
local function noAction()
    local d = WoW.takeDispatched()
    return not d:find("spell") and not d:find("item") and not d:find("macro"), d
end

eq(shown(), "hearthstone cooking", "to start: the Hearthstone and Cooking")
check(U.ValidKey("spell:1978") and not U.ValidKey("spell:0") and not U.ValidKey("spell:x"), "spell:<id> keys valid, others not")
eq(U.Registered("spell:1978"), true, "  a known spell's key is registered")
eq(U.Registered("spell:999"), false, "  an unknown one's isn't")
eq(U.Label("spell:1978"), "Serpent Sting (Rank 1)", "  its label: name and rank")

-- A spellbook drop on Cooking's leading half: before it.
layout()
local cook, hearth = U.buttons.cooking, U.buttons.hearthstone
at(cook, "leading")
spellOn(1978)
receive(cook)
eq(WoW.cursorInfo, nil, "a spellbook drop: the cursor taken")
eq(shown(), "hearthstone spell:1978 cooking", "  the spell before Cooking")
local sting = _G.GlassActionBarsUtilSpell_1978
check(sting ~= nil and U.buttons["spell:1978"] == sting, "  its own named secure button")
eq(sting._template, "SecureActionButtonTemplate", "  secure")
check(sting:GetAttribute("type") == "spell" and sting:GetAttribute("spell") == 1978, "  armed with the dropped rank")
eq(WoW.takeDispatched(), "", "  nothing clicked")
eq(U._test.gesture[cook], nil, "  its gesture ended a frame later")
check(GAB.db.utility.order ~= nil, "  saved in the order")

-- Click-to-place on the last button's trailing half: appended. Both CVar values.
for _, cv in ipairs({ "1", "0" }) do
    WoW.cvars.ActionButtonUseKeyDown = cv
    rebuild(); layout()
    local last = U._test.shown()[#U._test.shown()]
    at(last, "trailing")
    local id = cv == "1" and 2006 or 2050
    spellOn(id)
    WoW.takeDispatched()
    WoW.press(last)
    local ok, d = noAction()
    check(ok, "[keydown " .. cv .. "] a click with a spell on the cursor casts nothing (" .. d .. ")")
    eq(WoW.cursorInfo, nil, "  [keydown " .. cv .. "] the spell taken")
    check(shown():find("spell:" .. id .. "$") ~= nil, "  [keydown " .. cv .. "] appended: " .. shown())
    eq(last:GetAttribute("type"), U._test.state[last].kind == "item" and "item" or "spell", "  [keydown " .. cv .. "] the clicked button re-armed")
    eq(U._test.gesture[last], nil, "  [keydown " .. cv .. "] the gesture ended")
end
WoW.cvars.ActionButtonUseKeyDown = "1"
eq(shown(), "hearthstone spell:1978 cooking spell:2006 spell:2050", "two more spells at the end")

-- A built-in's spell (Cooking, any rank) turns that entry on and moves it.
Settings.SetUtilityShown("cooking", false)
rebuild(); layout()
eq(shown(), "hearthstone spell:1978 spell:2006 spell:2050", "Cooking unticked")
at(hearth, "leading")
spellOn(3413)
receive(hearth)
eq(shown(), "cooking hearthstone spell:1978 spell:2006 spell:2050", "  dropping Cooking's spell: Cooking on, first")
check(not U.ValidKey("spell:3413") or not GAB.db.utility.order[1]:find("spell:3413"), "  no spell:3413 entry")
local n = 0
for _, k in ipairs(U.Order()) do if k == "spell:3413" then n = n + 1 end end
eq(n, 0, "  never duplicated as a spell")

-- The same spell again: moved, not added.
rebuild(); layout()
at(U.buttons.cooking, "leading")
spellOn(2050)
receive(U.buttons.cooking)
eq(shown(), "spell:2050 cooking hearthstone spell:1978 spell:2006", "the same spell dropped again: moved")
eq(U.SpellCount(U.Order()), 3, "  still three spells")
-- Dropped on its own button: stays.
rebuild(); layout()
local heal = U.buttons["spell:2050"]
at(heal, "leading")
spellOn(2050)
receive(heal)
eq(shown(), "spell:2050 cooking hearthstone spell:1978 spell:2006", "  on its own button: stays")

-- A hidden spell re-dropped shows again.
Settings.SetUtilityShown("spell:1978", false)
rebuild()
eq(GAB.db.utility.show["spell:1978"], false, "a spell hidden from Options")
eq(shown(), "spell:2050 cooking hearthstone spell:2006", "  not shown")
layout()
at(U.buttons.hearthstone, "trailing")
spellOn(1978)
receive(U.buttons.hearthstone)
eq(GAB.db.utility.show["spell:1978"], nil, "  re-dropped: the hidden mark cleared")
eq(shown(), "spell:2050 cooking hearthstone spell:1978 spell:2006", "  shown where it landed")

-- Refusals: the cursor keeps its contents, nothing is added, nothing acts.
rebuild(); layout()
local before = shown()
local function refused(label, cursor)
    WoW.cursorInfo = cursor
    WoW.takeDispatched()
    receive(cook)
    check(WoW.cursorInfo == cursor, label .. ": the cursor keeps it")
    WoW.press(cook)
    check(WoW.cursorInfo == cursor, label .. ": a click keeps it too")
    local ok, d = noAction()
    check(ok, label .. ": the click casts nothing (" .. d .. ")")
    eq(shown(), before, label .. ": the bar unchanged")
end
cook = U.buttons.cooking
at(cook, "leading")
refused("a passive spell", { "spell", 3, "spell", 81 })
refused("an unknown spell", { "spell", 3, "spell", 4242 })
refused("an item", { "item", 6948 })
refused("a secret", { WoW.Secret("cursor kind") })
refused("a spell with a secret ID", { "spell", 3, "spell", WoW.Secret("id") })
WoW.cursorInfo = nil
eq(select(2, Settings.AddUtilitySpell(81)), "a passive spell can't go on the bar", "  the reason: passive")
-- In combat: no drop; a click acts (the stated exception: no gesture begins).
WoW.combat = true
spellOn(13549)
receive(cook)
check(WoW.cursorInfo ~= nil, "in combat a drop is refused, the cursor keeps it")
WoW.press(cook)
eq(WoW.takeDispatched(), "spell", "  a click in combat acts as before")
WoW.combat = false
WoW.cursorInfo = nil
eq(shown(), before, "  the bar unchanged")

-- The cap: new spells refused at it, a move still allowed.
U.MAX_SPELLS = 4
check(Settings.AddUtilitySpell(13549), "the fourth spell")
local ok, why = Settings.AddUtilitySpell(2050 + 0 == 2050 and 2006 or 0)
check(ok, "  a spell already there moves at the cap")
WoW.known[555] = true
ok, why = Settings.AddUtilitySpell(555)
check(not ok and why:find("4 added spells"), "  a fifth refused: " .. tostring(why))
U.MAX_SPELLS = 40
Settings.RemoveUtility("spell:13549")
rebuild()

-- Another class's spell keeps its slot, with no button and no row.
WoW.known[1978] = nil
rebuild()
eq(shown(), "spell:2050 cooking hearthstone spell:2006", "a spell this character doesn't know: not shown")
check(not U.Registered("spell:1978"), "  not registered")
local function pos(key)
    for i, k in ipairs(U.Order()) do if k == key then return i end end
end
local unseen = pos("spell:1978")
check(unseen ~= nil, "  its slot kept in the order")
eq(pos("spell:2006"), unseen + 1, "  just before Resurrection")
check(Settings.MoveUtility("spell:2006", -1), "  Resurrection moved up past it")
eq(pos("spell:1978"), unseen, "  the unseen key stays put")
check(pos("spell:2006") < unseen, "  Resurrection now before it")
check(Settings.PlaceUtility("spell:2050", "spell:1978"), "  placed before the unseen key")
eq(pos("spell:2050"), pos("spell:1978") - 1, "  right before it")
WoW.known[1978] = true
rebuild()
check(shown():find("spell:2050 spell:1978", 1, true) ~= nil, "known again: back in its place, " .. shown())

-- The Shift reorder drag. Nothing acts; the ghost follows; the drop places it.
rebuild(); layout()
local resur = U.buttons["spell:2006"]
WoW.pickupDown = true
WoW.takeDispatched()
local ghostShown
WoW.press(resur, "LeftButton", { drag = true, during = function()
    ghostShown = U._test.ghost:IsShown()
    at(U.buttons.cooking, "leading")
end })
WoW.pickupDown = false
check(ghostShown, "a Shift-drag: the ghost shown during it")
check(not U._test.ghost:IsShown() and not U._test.marker:IsShown(), "  gone after")
check(noAction(), "  nothing acted")
eq(shown(), "spell:2006 cooking hearthstone spell:2050 spell:1978", "  dropped before Cooking")
eq(U._test.gesture[resur], nil, "  the gesture ended at OnDragStop (no OnMouseUp after a drag)")
eq(resur:GetAttribute("type"), "spell", "  re-armed")
-- On its own trailing half: nothing moves.
rebuild(); layout()
WoW.pickupDown = true
WoW.press(U.buttons.cooking, "LeftButton", { drag = true, during = function() at(U.buttons.cooking, "trailing") end })
WoW.pickupDown = false
eq(shown(), "spell:2006 cooking hearthstone spell:2050 spell:1978", "  dropped where it started: unchanged")
-- Off the bar: a spell leaves it, a built-in is unticked.
rebuild(); layout()
WoW.pickupDown = true
WoW.press(U.buttons["spell:2050"], "LeftButton", { drag = true, during = away })
eq(shown(), "spell:2006 cooking hearthstone spell:1978", "dragged off: the spell taken off")
local found = false
for _, k in ipairs(U.Order()) do if k == "spell:2050" then found = true end end
check(not found, "  gone from the order")
rebuild(); layout()
WoW.press(U.buttons.hearthstone, "LeftButton", { drag = true, during = away })
WoW.pickupDown = false
eq(GAB.db.utility.show.hearthstone, false, "  a built-in dragged off: unticked")
eq(shown(), "spell:2006 cooking spell:1978", "  not shown")
Settings.SetUtilityShown("hearthstone", true)
-- A drag without the modifier does nothing.
rebuild(); layout()
WoW.press(U.buttons.cooking, "LeftButton", { drag = true, during = away })
eq(shown(), "spell:2006 cooking hearthstone spell:1978", "a drag without Shift: nothing moves")
WoW.takeDispatched()
-- Combat cancels a drag.
WoW.pickupDown = true
WoW.press(U.buttons.cooking, "LeftButton", { drag = true, during = function()
    WoW.fire("PLAYER_REGEN_DISABLED")
    away()
end })
WoW.pickupDown = false
eq(shown(), "spell:2006 cooking hearthstone spell:1978", "a fight starting mid-drag: nothing changes")
check(not U._test.ghost:IsShown(), "  the ghost gone")
WoW.fire("PLAYER_REGEN_ENABLED")
WoW.tick()

-- The camping group drags as one.
WoW.items[279981] = 1                           -- Basic Campfire Kit
rebuild(); layout()
eq(shown(), "spell:2006 cooking hearthstone spell:1978 camp_basic", "the camping group shown")
WoW.pickupDown = true
WoW.press(U.buttons.camp_basic, "LeftButton", { drag = true, during = function() at(U.buttons.cooking, "leading") end })
WoW.pickupDown = false
eq(shown(), "spell:2006 camp_basic cooking hearthstone spell:1978", "  a camping item moves the group")
check(U.Order()[2] == "camping", "  the order key is the group's")

-- Shift-clicks: neither edge acts, on both CVar values; a Shift key binding acts.
for _, cv in ipairs({ "1", "0" }) do
    WoW.cvars.ActionButtonUseKeyDown = cv
    rebuild()
    WoW.takeDispatched()
    WoW.pickupDown = true
    WoW.press(U.buttons.cooking)
    local okC, d = noAction()
    check(okC, "[keydown " .. cv .. "] a Shift-click acts on neither edge (" .. d .. ")")
    eq(U.buttons.cooking:GetAttribute("type"), "spell", "  [keydown " .. cv .. "] restored after")
    WoW.press(U.buttons.cooking, "LeftButton", { key = true })
    eq(WoW.takeDispatched(), "spell", "  [keydown " .. cv .. "] a Shift key binding acts")
    WoW.pickupDown = false
    WoW.press(U.buttons.cooking)
    eq(WoW.takeDispatched(), "spell", "  [keydown " .. cv .. "] a plain click acts")
end
-- Overlap: Shift-left down, Shift let go, a right click, left released: still nothing.
WoW.cvars.ActionButtonUseKeyDown = "0"
cook = U.buttons.cooking
WoW.takeDispatched()
WoW.pickupDown = true
WoW.mouseDown.LeftButton = true
cook:GetScript("OnMouseDown")(cook, "LeftButton")
cook:GetScript("PreClick")(cook, "LeftButton", true)
cook:GetScript("PostClick")(cook, "LeftButton", true)
WoW.pickupDown = false
WoW.press(cook, "RightButton")
WoW.mouseDown.LeftButton = nil
cook:GetScript("OnMouseUp")(cook, "LeftButton")
cook:GetScript("PreClick")(cook, "LeftButton", false)
table.insert(WoW.dispatched, { type = cook:GetAttribute("type") })   -- the left release's dispatch
cook:GetScript("PostClick")(cook, "LeftButton", false)
WoW.flushTimers(0)
check(noAction(), "a right click mid-gesture doesn't let the left release act")
eq(U._test.gesture[cook], nil, "  the gesture ended with the left release")
WoW.cvars.ActionButtonUseKeyDown = "1"

-- Feed Pet: a Shift-click neither arms nor feeds; a plain click feeds.
WoW.known[6991] = true
WoW.pet = { hunter = true, level = 30 }
WoW.edible = { [102] = true }
WoW.itemInfo = { [102] = { level = 30, price = 10 } }
WoW.bags[0] = { [1] = { itemID = 102, stackCount = 3 } }
rebuild()
local feed = U.buttons.feedpet
check(feed:IsShown(), "Feed Pet shown")
WoW.takeDispatched()
WoW.pickupDown = true
WoW.press(feed)
WoW.pickupDown = false
local d = WoW.dispatched
check(noAction(), "  a Shift-click on Feed Pet feeds nothing")
for _, k in ipairs({ "type", "spell", "target-bag", "target-slot" }) do
    eq(feed:GetAttribute(k), nil, "  disarmed after: " .. k)
end
WoW.dispatched = {}
WoW.press(feed)
local fedWith = WoW.dispatched[1]
check(fedWith and fedWith.type == "spell" and fedWith.spell == 6991 and fedWith.bag == 0 and fedWith.slot == 1,
    "  a plain click feeds (the release armed it)")
WoW.dispatched = {}
eq(feed:GetAttribute("type"), nil, "  disarmed after")
spellOn(2050)
WoW.press(feed)
check(noAction(), "  a click with a spell on the cursor feeds nothing")
eq(WoW.cursorInfo, nil, "  it took the spell")
eq(feed:GetAttribute("target-bag"), nil, "  no target left on it")
WoW.pet = nil
rebuild()

-- The lock: a Shift-click doesn't toggle; its Shift key binding does.
WoW.cvars.lockActionBars = "1"
Settings.SetUtilityShown("lockbars", true)
rebuild()
local lock = U.buttons.lockbars
check(lock:IsShown(), "the lock shown")
WoW.pickupDown = true
WoW.press(lock)
eq(WoW.cvars.lockActionBars, "1", "  a Shift-click doesn't toggle it")
WoW.press(lock, "LeftButton", { key = true })
eq(WoW.cvars.lockActionBars, "0", "  its Shift key binding does")
WoW.pickupDown = false
WoW.cursorInfo = { "item", 6948 }
WoW.press(lock)
eq(WoW.cvars.lockActionBars, "0", "  a click with an item on the cursor doesn't")
check(WoW.cursorInfo ~= nil, "  and leaves the item")
WoW.cursorInfo = nil
WoW.press(lock)
eq(WoW.cvars.lockActionBars, "1", "  a plain click does")

-- The options page: a Remove button on a spell's row; a removed row hides.
GAB.Options.utilityPage:Show()
local rows = GAB.Options._test.utilityRows
check(rows["spell:2006"] and rows["spell:2006"].remove ~= nil, "the page: a Remove button on a spell's row")
eq(rows.cooking.remove, nil, "  none on a built-in's")
eq(rows["spell:2006"].text:GetText(), "Resurrection", "  the spell's name")
rows["spell:2006"].remove:GetScript("OnClick")(rows["spell:2006"].remove)
check(not rows["spell:2006"].frame:IsShown(), "  removed: its row hidden")
found = false
for _, k in ipairs(U.Order()) do if k == "spell:2006" then found = true end end
check(not found, "  gone from the order")
-- A spell added from the bar shows its row at once.
rebuild(); layout()
spellOn(2006)
at(U.buttons.cooking, "leading")
receive(U.buttons.cooking)
check(rows["spell:2006"].frame:IsShown(), "  added again from the bar: its row back")
eq(next(GAB.failures), nil, "nothing failed")

-- Saved settings cleaned: spells past the cap dropped, a hidden mark without its spell dropped.
local saved = { utility = { order = {}, show = { ["spell:7"] = false, ["spell:99999"] = false, ["spell:8"] = true } } }
for i = 1, 45 do saved.utility.order[i] = "spell:" .. i end
saved.utility.order[46] = "spell:1"          -- a duplicate
local G2 = loadAddon({ db = saved })
local u = G2.db.utility
eq(#u.order, 40, "saved: 40 spells kept")
eq(u.order[40], "spell:40", "  the first ones")
eq(u.show["spell:7"], false, "  a hidden spell's mark kept")
eq(u.show["spell:99999"], nil, "  a mark without its spell dropped")
eq(u.show["spell:8"], nil, "  a spell's 'shown' mark dropped (only what differs)")

done("test_utility_drag")
