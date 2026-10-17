-- The Utility bar (#9): what shows (known spells, carried items, camping by
-- kit or campfire aura), in the player's order; attributes set and cleared;
-- combat deferral; the dock's geometry or our own; cooldown routing; key
-- text; Bindings.xml and its shipping; settings, /gab utility, the page.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local function close(a, b) return type(a) == "number" and type(b) == "number" and math.abs(a - b) < 1e-6 end

WoW.layoutBar(MainActionBar, 500, 100)          -- bar 1: 500..1062 x 55..100
local GAB = loadAddon()
local U, Settings = GAB.Utility, GAB.Settings
eq(next(GAB.failures), nil, "nothing failed")
local B = U.buttons
for _, b in pairs(B) do b._protected = true end  -- secure buttons
local function attrs(key) local b = B[key]; return b:GetAttribute("type"), b:GetAttribute("spell"), b:GetAttribute("item") end
local function shownKeys()
    local out = {}
    for _, b in ipairs(U._test.shown()) do out[#out + 1] = U._test.state[b].key end
    return table.concat(out, ",")
end
local function rebuild() U.Refresh(); WoW.tick() end

-- Every action and camping item has a named button from load.
eq(#U.CAMPING, 37, "37 camping items (3 kits + 34 features)")
local kits = 0
for _, a in ipairs(U.CAMPING) do if a.kit then kits = kits + 1 end end
eq(kits, 3, "  3 of them kits")
for _, a in ipairs(U.ACTIONS) do check(_G["GlassActionBarsUtil_" .. a.key] == B[a.key], "named button " .. a.key) end
for _, a in ipairs(U.CAMPING) do check(_G["GlassActionBarsUtil_" .. a.key] ~= nil, "named button " .. a.key) end
for _, b in pairs(B) do check(GAB.Buttons.IsSkinned(b), "skinned at login: " .. b:GetName()) end

-- Nothing known, nothing carried: hidden, no attributes.
rebuild()
check(not U.frame:IsShown(), "nothing to show: hidden")
eq((attrs("cooking")), nil, "  no attributes")

-- A profession's current rank; the Hearthstone carried.
WoW.known[3413] = true
WoW.items[6948] = 1
rebuild()
local t, spell = attrs("cooking")
eq(t, "spell", "Cooking known: a spell button")
eq(spell, 3413, "  its known rank")
local ti, _, item = attrs("hearthstone")
eq(ti, "item", "Hearthstone carried: an item button")
eq(item, "item:6948", "  by item ID")
eq(shownKeys(), "hearthstone,cooking", "  in the default order")
check(U.frame:IsShown(), "  the bar shown")

-- The player's order.
check(Settings.MoveUtility("cooking", -1), "move Cooking up")
WoW.tick()
eq(shownKeys(), "cooking,hearthstone", "  Cooking first")
eq(Settings.MoveUtility("cooking", -1), false, "  can't move past the top")
Settings.MoveUtility("cooking", 1)
WoW.tick()

-- Camping: a kit whenever carried; a feature only near a campfire.
WoW.items[279981] = 1                           -- Basic Campfire Kit
WoW.items[279979] = 2                           -- Camp Chair
rebuild()
eq(shownKeys(), "hearthstone,cooking,camp_basic", "a kit shows without the campfire aura; the Camp Chair doesn't")
WoW.auras[U.CAMPFIRE_AURA] = true
WoW.fire("UNIT_AURA", "player")
WoW.tick()
eq(shownKeys(), "hearthstone,cooking,camp_basic,camp_skinning1", "near a campfire: the Camp Chair too")
eq(U._test.regions[B.camp_skinning1].count:GetText(), "2", "  its count")
eq(U._test.regions[B.hearthstone].count:GetText(), "", "  no count on the Hearthstone")
WoW.auras[U.CAMPFIRE_AURA] = WoW.Secret("aura")
WoW.fire("UNIT_AURA", "player")
WoW.tick()
eq(shownKeys(), "hearthstone,cooking,camp_basic,camp_skinning1", "a secret aura read keeps the last state")
WoW.auras[U.CAMPFIRE_AURA] = "throw"
WoW.fire("UNIT_AURA", "player")
WoW.tick()
eq(shownKeys(), "hearthstone,cooking,camp_basic,camp_skinning1", "a refused aura read keeps the last state")
WoW.fire("UNIT_AURA", "target")
WoW.auras[U.CAMPFIRE_AURA] = nil
WoW.fire("UNIT_AURA", "target")
WoW.tick()
eq(shownKeys(), "hearthstone,cooking,camp_basic,camp_skinning1", "another unit's UNIT_AURA: ignored")
WoW.fire("UNIT_AURA", "player")
WoW.tick()
eq(shownKeys(), "hearthstone,cooking,camp_basic", "away from the campfire: the Camp Chair goes")
eq((attrs("camp_skinning1")), nil, "  its attributes cleared")
Settings.SetUtilityShown("camping", false)
eq(shownKeys(), "hearthstone,cooking", "the Camping group hidden")
Settings.SetUtilityShown("camping", true)

-- Combat: no protected change; it all happens when the fight ends.
WoW.combat = true
WoW.fire("PLAYER_REGEN_DISABLED")
WoW.known[18260] = true                         -- a new rank
WoW.items[6948] = nil
WoW.fire("SPELLS_CHANGED")
WoW.fire("BAG_UPDATE_DELAYED")
WoW.tick()
eq(select(2, attrs("cooking")), 3413, "in combat: unchanged")
eq(#WoW.violations, 0, "  no protected change in combat")
check(U.IsPending(), "  a rebuild pending")
WoW.combat = false
WoW.fire("PLAYER_REGEN_ENABLED")
eq(select(2, attrs("cooking")), 18260, "  the fight over: the new rank")
eq((attrs("hearthstone")), nil, "  the Hearthstone gone")
WoW.items[6948] = 1

-- Placement: docked right of bar 1 by default, matched to it.
rebuild()
WoW.tick()
check(GAB.Dock.IsHosted("utility"), "docked by default")
check(close(B.cooking:GetWidth(), 45), "  matched: 45-wide buttons")
local p = U.frame._points[#U.frame._points]
check(p and close(p[4], 1062 + 4), "  right of bar 1")
Settings.SetDock("utility", "match", false)
WoW.tick()
check(close(B.cooking:GetWidth(), U.SIZE), "match off: its own 36")
Settings.SetDock("utility", "match", true)
WoW.tick()
check(close(B.cooking:GetWidth(), 45), "  matched again")
Settings.SetDock("utility", "bar", false)
WoW.tick()
check(not GAB.Dock.IsHosted("utility"), "undocked")
check(close(B.cooking:GetWidth(), U.SIZE), "  its own geometry again")
eq(U._test.geom(), nil, "  the cached geometry dropped")
Settings.SetDock("utility", "bar", 1)
WoW.tick()

-- Cooldowns: spells and the Hearthstone by duration object; other items by GetItemCooldown.
local dCook, dHearth = newproxy and newproxy() or {}, newproxy and newproxy() or {}
WoW.durations[18260], WoW.durations[8690] = dCook, dHearth
WoW.itemCooldowns[279981] = { 100, 3600 }
WoW.itemSpells = { [279981] = 1307227 }         -- camping items have use spells too
WoW.durations[1307227] = newproxy and newproxy() or {}
U.RefreshVisuals()
local R = U._test.regions
eq(R[B.cooking].cooldown._cd.duration, dCook, "a spell: its duration object")
eq(R[B.hearthstone].cooldown._cd.duration, dHearth, "the Hearthstone: its use spell's duration object")
local cd = R[B.camp_basic].cooldown._cd
check(cd[1] == 100 and cd[2] == 3600, "a camping item: GetItemCooldown's start and duration")
WoW.durations[18260] = nil
U.RefreshVisuals()
eq(R[B.cooking].cooldown._cd, "cleared", "no duration: cleared")
local secretStart = WoW.Secret("start")
WoW.itemCooldowns[279981] = { secretStart, 3600 }
U.RefreshVisuals()
check(rawequal(R[B.camp_basic].cooldown._cd[1], secretStart), "a secret start goes to the widget untouched")

-- Key text: the bound key, shortened; none on a camping feature.
WoW.bindings[U.BindingAction("cooking")] = "CTRL-SHIFT-F"
WoW.fire("UPDATE_BINDINGS")
eq(R[B.cooking].hotkey:GetText(), "csF", "the bound key, shortened")
eq(R[B.camp_basic].hotkey:GetText(), "", "a kit with no key bound: empty")
WoW.auras[U.CAMPFIRE_AURA] = true
WoW.fire("UNIT_AURA", "player")
WoW.tick()
WoW.bindings[U.BindingAction("camp_skinning1")] = "X"
WoW.fire("UPDATE_BINDINGS")
eq(R[B.camp_skinning1].hotkey:GetText(), "", "a camp feature has no binding: no key text")
WoW.auras[U.CAMPFIRE_AURA] = nil
WoW.fire("UNIT_AURA", "player")
WoW.tick()

-- Binding names in the client's language.
WoW.spellNames = { [2550] = "Kochkunst" }
U.LocalizeBindingNames()
eq(_G["BINDING_NAME_" .. U.BindingAction("cooking")], "Kochkunst", "binding names localized")

-- Off: everything cleared, hidden; on again: back.
Settings.SetUtilityEnabled(false)
check(not U.frame:IsShown(), "/gab utility off: hidden")
eq((attrs("cooking")), nil, "  attributes cleared")
SlashCmdList.GLASSACTIONBARS("utility on")
check(U.frame:IsShown(), "/gab utility on: shown")

-- Bindings.xml: a line per binding key and nothing else; shipped.
local xml = io.open("Bindings.xml"):read("*a")
local lines = {}
for key in xml:gmatch('name="CLICK GlassActionBarsUtil_([%w_]+):LeftButton"') do lines[key] = true end
for _, key in ipairs(U.BINDING_KEYS) do check(lines[key], "Bindings.xml has " .. key) end
local n = 0
for key in pairs(lines) do n = n + 1; check(U.BY_KEY[key] ~= nil, "Bindings.xml key is an action: " .. key) end
eq(n, #U.BINDING_KEYS, "Bindings.xml: one line per binding key")
check(io.open("Tools/deploy.ps1"):read("*a"):find('"Bindings.xml"', 1, true), "deploy.ps1 ships Bindings.xml")
check(io.open(".github/workflows/package-check.yml"):read("*a"):find("GlassActionBars/Bindings.xml", 1, true),
    "the package check requires Bindings.xml in the zip")

-- The options page: rows in the player's order, live.
GAB.Options.utilityPage:Show()
local rows = GAB.Options._test.utilityRows
local function y(key) return rows[key].frame._points[#rows[key].frame._points][5] end
check(y("hearthstone") > y("cooking"), "the page: Hearthstone above Cooking")
rows.cooking.up:GetScript("OnClick")(rows.cooking.up)
check(y("cooking") > y("hearthstone"), "  Up moves Cooking above it")
rows.camping.check:SetChecked(false)
rows.camping.check:GetScript("OnClick")(rows.camping.check)
eq(U.IsShown("camping"), false, "  unticking Camping hides the group")

-- The order read directly: each key once.
GAB.db.utility.order = { "cooking", "cooking", "hearthstone" }
local order, count = U.Order(), 0
for _, k in ipairs(order) do if k == "cooking" then count = count + 1 end end
eq(count, 1, "Order(): a duplicated key once")
eq(#order, #U.ORDER_KEYS, "  every key exactly once")

-- Saved settings: cleaned, but a present table stays (the import marker).
local ensure = GAB._test.ensureDefaults
GlassActionBarsDB = { utility = { enabled = "yes", show = { cooking = false, bogus = false, ["provider:roulette"] = false,
    hearthstone = true }, order = { "cooking", "cooking", "bogus", "provider:x" } } }
local u = rawget(ensure(), "utility")
eq(u.enabled, nil, "load: a non-boolean enabled dropped")
eq(u.show.cooking, false, "  a hidden action kept")
eq(u.show.bogus, nil, "  an unknown key dropped")
eq(u.show["provider:roulette"], false, "  a provider key kept before it registers")
eq(u.show.hearthstone, nil, "  only false is stored")
eq(table.concat(u.order, ","), "cooking,provider:x", "  the order deduplicated and cleaned")
GlassActionBarsDB = { utility = {} }
check(type(rawget(ensure(), "utility")) == "table", "an empty utility table stays (Apotheca's import marker)")
GlassActionBarsDB = {}
eq(rawget(ensure(), "utility"), nil, "untouched defaults create no utility table")

done("test_utility")
