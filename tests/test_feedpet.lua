-- Feed Pet on the Utility bar (#65): shown for a live hunter pet with food
-- it eats; GlassPearls' food order; disarmed at rest, after every rebuild and
-- at both combat edges; armed only by a release's PreClick that passed every
-- check, with the food chosen at the click, type last; PostClick disarms.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

WoW.layoutBar(MainActionBar, 500, 100)
local GAB = loadAddon()
local U = GAB.Utility
eq(next(GAB.failures), nil, "nothing failed")
local b = U.buttons.feedpet
b._protected = true
local ATTRS = { "type", "spell", "target-bag", "target-slot" }
local function disarmed()
    for _, k in ipairs(ATTRS) do if b:GetAttribute(k) ~= nil then return false end end
    return true
end
local function shown()
    for _, x in ipairs(U._test.shown()) do if x == b then return true end end
    return false
end
local function rebuild() U.Refresh(); WoW.tick() end
local pre, post = b:GetScript("PreClick"), b:GetScript("PostClick")
-- A release: PreClick, then (what the secure click would read) the attributes, then PostClick.
local function release(mouseButton)
    pre(b, mouseButton or "LeftButton", false)
    local seen = { type = b:GetAttribute("type"), spell = b:GetAttribute("spell"),
        bag = b:GetAttribute("target-bag"), slot = b:GetAttribute("target-slot") }
    post(b, mouseButton or "LeftButton", false)
    return seen
end

check(_G.GlassActionBarsUtil_feedpet == b, "a named button from load")
eq(b:GetAttribute("useOnKeyDown"), false, "  the release acts")
check(pre ~= nil and post ~= nil, "  PreClick and PostClick set")
eq(U.Order()[2], "feedpet", "right after the Hearthstone by default")

-- A hunter with Feed Pet, a live hunter pet at level 30, food in the bags.
WoW.known[6991] = true
WoW.pet = { hunter = true, level = 30 }
WoW.edible = { [101] = true, [102] = true, [103] = true, [104] = true }
WoW.itemInfo = { [101] = { level = 32, price = 50 }, [102] = { level = 30, price = 10 },
    [103] = { level = 15, price = 1 }, [104] = { level = 18, price = 1 } }
WoW.bags[0] = { [1] = { itemID = 101, stackCount = 5 }, [2] = { itemID = 103, stackCount = 2 } }
WoW.bags[1] = { [4] = { itemID = 102, stackCount = 3 }, [9] = { itemID = 102, stackCount = 4 } }
rebuild()
check(shown(), "a live hunter pet and food: shown")
check(disarmed(), "  disarmed at rest")
local s = U._test.state[b]
eq(s.food.id, 102, "  within 10 levels: the cheapest")
check(s.food.bag == 1 and s.food.slot == 4, "  its first stack")
eq(s.food.count, 7, "  its total in the bags")
eq(U._test.regions[b].count:GetText(), "7", "  the count shown")
eq(U._test.regions[b].icon._file, 200000 + 6991, "  Feed Pet's icon")
b:GetScript("OnEnter")(b)
check(table.concat(GameTooltip._lines, "|"):find("Feeds: item 102 (7)", 1, true), "  the tooltip names the food")

-- Out of the band: the highest level first.
WoW.pet.level = 50
WoW.fire("UNIT_LEVEL", "pet")
WoW.tick()
eq(U._test.state[b].food.id, 101, "no food within 10 levels of the pet: the highest item level")
WoW.pet.level = 30
WoW.fire("UNIT_LEVEL", "pet")
WoW.tick()

-- Locked stacks skipped; an uncached food asked for once, then chosen.
WoW.bags[1][4].isLocked, WoW.bags[1][9].isLocked = true, true
rebuild()
eq(U._test.state[b].food.id, 101, "a locked stack is skipped")
WoW.bags[1][4].isLocked, WoW.bags[1][9].isLocked = nil, nil
WoW.edible[105] = true
WoW.bags[2] = { [1] = { itemID = 105, stackCount = 1 } }
rebuild()
rebuild()
eq(WoW.requested[105], 1, "an uncached food requested once")
eq(U._test.state[b].food.id, 102, "  not chosen yet")
WoW.itemInfo[105] = { level = 29, price = 2 }
WoW.fire("GET_ITEM_INFO_RECEIVED", 105, true)
WoW.tick()
eq(U._test.state[b].food.id, 105, "  chosen once its info arrived")
WoW.bags[2] = nil

-- Secrets in the bag reads: skipped, never touched.
WoW.bags[2] = { [1] = { secret = true }, [2] = { itemID = 106, stackCount = 1 } }
WoW.edible[106] = true
WoW.itemInfo[106] = { level = 30, price = 0, secretName = true }
rebuild()
eq(next(GAB.failures), nil, "a secret bag record and a secret item name: no error")
check(U._test.state[b].food.id ~= 106, "  the food with a secret name not chosen")
WoW.fire("GET_ITEM_INFO_RECEIVED", WoW.Secret("id"), true)
WoW.tick()
eq(next(GAB.failures), nil, "  a secret item id in GET_ITEM_INFO_RECEIVED: no error")
WoW.bags[2] = nil

-- Not shown: no pet, a warlock's pet, a dead pet, no food, secrets.
local function hiddenWhen(label, setup, undo)
    setup(); rebuild()
    check(not shown(), label)
    check(disarmed(), "  disarmed")
    undo(); rebuild()
    check(shown(), "  back when that ends: " .. label)
end
hiddenWhen("no pet out", function() WoW.pet = nil end, function() WoW.pet = { hunter = true, level = 30 } end)
hiddenWhen("a warlock's pet", function() WoW.pet.hunter = false end, function() WoW.pet.hunter = true end)
hiddenWhen("Feed Pet not known", function() WoW.known[6991] = nil end, function() WoW.known[6991] = true end)
hiddenWhen("a secret hunter flag", function() WoW.pet.hunter = WoW.Secret("hunter") end, function() WoW.pet.hunter = true end)
hiddenWhen("nothing it eats", function() WoW.edible = {} end,
    function() WoW.edible = { [101] = true, [102] = true, [103] = true, [104] = true } end)
hiddenWhen("a secret CanPetEatItem", function() WoW.edible = { [101] = WoW.Secret("e"), [102] = WoW.Secret("e"),
    [103] = WoW.Secret("e") } end, function() WoW.edible = { [101] = true, [102] = true, [103] = true } end)
hiddenWhen("a refused CanPetEatItem", function() WoW.edible = { [101] = "throw", [102] = "throw", [103] = "throw" } end,
    function() WoW.edible = { [101] = true, [102] = true, [103] = true } end)

-- Death: UNIT_HEALTH rebuilds only when the dead state changes.
local reconciles = 0
local real = U.Reconcile
U.Reconcile = function() reconciles = reconciles + 1; return real() end
WoW.fire("UNIT_HEALTH", "pet")
WoW.tick()
eq(reconciles, 0, "a health tick, still alive: no rebuild")
WoW.pet.dead = true
WoW.fire("UNIT_HEALTH", "pet")
WoW.tick()
eq(reconciles, 1, "the pet died: one rebuild")
check(not shown(), "  hidden")
WoW.fire("UNIT_HEALTH", "player")
WoW.tick()
eq(reconciles, 1, "the player's health: ignored")
WoW.pet.dead = nil
WoW.fire("UNIT_HEALTH", "pet")
WoW.tick()
check(shown(), "revived: shown again")
U.Reconcile = real
WoW.pet = nil
WoW.fire("UNIT_PET", "player")
WoW.tick()
check(not shown(), "UNIT_PET, dismissed: hidden")
WoW.pet = { hunter = true, level = 30 }
WoW.fire("UNIT_PET", "player")
WoW.tick()
check(shown(), "UNIT_PET, called: shown")

-- The click: armed for the release only, with the food chosen at the click.
WoW.bags[1][4] = nil                              -- the stack moved after the rebuild
WoW.bags[3] = { [7] = { itemID = 102, stackCount = 3 } }
local seen = release()
eq(seen.type, "spell", "a release arms it")
eq(seen.spell, 6991, "  Feed Pet")
check(seen.bag == 1 and seen.slot == 9, "  the food chosen at the click (the moved stack's other)")
check(disarmed(), "  PostClick disarms")
local order = {}
local realSet = b.SetAttribute
b.SetAttribute = function(self, k, v) if v ~= nil then order[#order + 1] = k end return realSet(self, k, v) end
release()
b.SetAttribute = realSet
local firstType
for i, k in ipairs(order) do if k == "type" then firstType = firstType or i end end
eq(firstType, 4, "  type set last, after the target and the spell")

pre(b, "LeftButton", true)
check(disarmed(), "the down edge arms nothing")
post(b, "LeftButton", true)
seen = release("RightButton")
eq(seen.type, nil, "a right click arms nothing")

-- Each refusal arms nothing.
local function refused(label, setup, undo)
    setup()
    local r = release()
    check(r.type == nil and r.bag == nil and r.slot == nil, "refused: " .. label)
    undo()
end
refused("the cursor holds an item", function() WoW.cursorItem = "item" end, function() WoW.cursorItem = nil end)
refused("a secret cursor", function() WoW.cursorItem = WoW.Secret("c") end, function() WoW.cursorItem = nil end)
refused("a spell is targeting", function() WoW.targeting = true end, function() WoW.targeting = nil end)
refused("SpellCanTargetItem", function() WoW.targetItem = true end, function() WoW.targetItem = nil end)
refused("SpellCanTargetItemID", function() WoW.targetItemID = true end, function() WoW.targetItemID = nil end)
refused("a secret SpellCanTargetItem", function() WoW.targetItem = WoW.Secret("t") end, function() WoW.targetItem = nil end)
refused("Feed Pet not usable", function() WoW.feedUsable = false end, function() WoW.feedUsable = nil end)
refused("the pet died", function() WoW.pet.dead = true end, function() WoW.pet.dead = nil end)
refused("no pet", function() WoW.pet = nil end, function() WoW.pet = { hunter = true, level = 30 } end)
refused("no food left", function() WoW.edible = {} end,
    function() WoW.edible = { [101] = true, [102] = true, [103] = true } end)
check(release().type == "spell", "every check passing again: armed")

-- Not on the bar: its binding arms nothing.
WoW.pet = nil
rebuild()
check(release().type == nil, "hidden: a binding press arms nothing")
WoW.pet = { hunter = true, level = 30 }
rebuild()

-- Left armed (a click that never reached PostClick): a rebuild and both combat edges disarm.
pre(b, "LeftButton", false)
check(not disarmed(), "a PreClick without its PostClick leaves it armed")
rebuild()
check(disarmed(), "  a rebuild disarms it")
pre(b, "LeftButton", false)
WoW.fire("PLAYER_REGEN_DISABLED")                  -- still before lockdown
check(disarmed(), "  so does the fight's start")
-- In combat: nothing armed, no protected change.
WoW.combat = true
seen = release()
eq(seen.type, nil, "in combat: a click arms nothing")
eq(#WoW.violations, 0, "  no protected change in combat")
WoW.combat = false
pre(b, "LeftButton", false)
WoW.combat = true
WoW.fire("PLAYER_REGEN_DISABLED")
check(not disarmed(), "armed when lockdown came first: it stays (no change in combat)")
eq(#WoW.violations, 0, "  no protected change tried")
WoW.combat = false
WoW.fire("PLAYER_REGEN_ENABLED")
check(disarmed(), "  the fight's end disarms it")

-- Off: cleared like any action.
GAB.Settings.SetUtilityEnabled(false)
check(disarmed() and not b:IsShown(), "/gab utility off: disarmed, hidden")

done("test_feedpet")
