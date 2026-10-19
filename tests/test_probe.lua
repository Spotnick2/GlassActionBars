-- GABProbe on ForeverProbe (#32): it loads as a module, its reads (the
-- campfire buff, every helpful aura, the Utility bar, camping cooldowns) are
-- right and secret-safe, the campfire procedure starts, and nothing reaches
-- chat. Local only: CI has no ForeverProbe (FOREVERPROBE_OPTIONAL).
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

loadForeverProbe()
WoW.known[3413] = true
WoW.items[279981] = 1                           -- Basic Campfire Kit
WoW.items[279979] = 2                           -- Camp Chair
WoW.items[279969] = 1                           -- Field Guide
local GAB = loadAddon()
local ns = {}
assert(loadfile("Tools/GABProbe/GABProbe.lua"))("GABProbe", ns)
GABProbeDB = { log = { "an old /gabprobe line" } }   -- the standalone probe's table
WoW.fire("ADDON_LOADED", "GABProbe")
local T = ns._test
local chatBefore = #WoW.chat
local function logHas(pattern)
    for _, line in ipairs(GABProbeDB.log) do if line:find(pattern) then return true end end
    return false
end

eq(GABProbeDB.module, 1, "the standalone probe's saved table replaced")
check(not logHas("old /gabprobe"), "  its old lines gone")
check(logHas("loaded"), "the module loaded and logs")

-- The campfire buff.
eq(T.aura(), false, "away from a fire: the buff absent")
WoW.auras[1283391] = true
eq(T.aura(), true, "by a fire: present")
WoW.auras[1283391] = WoW.Secret("aura")
eq(T.aura(), "secret", "a secret read: said so")
WoW.auras[1283391] = "throw"
eq(T.aura(), nil, "a refused read: nil")

-- Every helpful aura, by id; the Utility bar's own view.
WoW.auras[1283391] = true
WoW.helpful = { { spellId = 1283391, name = "Campfire Nearby", duration = 0 }, WoW.Secret("aura2"),
    { spellId = 25694, name = "Well Fed", duration = 900 } }
WoW.fire("UNIT_AURA", "player")
WoW.tick(); WoW.tick()
local a, ids, near, shown = T.readAll()
eq(a, true, "readAll: the buff")
eq(ids, "1283391 <secret> 25694", "  every helpful aura's id, a secret one guarded")
eq(near, true, "  the Utility bar knows it's by a fire")
check(shown:find("camp_skinning1", 1, true) and shown:find("camp_basic", 1, true), "  its camping buttons shown")
check(logHas("aura 3: id 25694"), "  each aura logged")

-- Shared cooldowns, by a transition from a ready baseline.
local v, detail = T.cooldownVerdict()
eq(v, nil, "no baseline yet: inconclusive")
WoW.itemCooldowns[279979] = { 100, 3600 }        -- the Camp Chair already cooling when brought
eq(T.takeBaseline(), 1, "  one ready feature by the fire")
v, detail = T.cooldownVerdict()
check(v == nil and detail:find("fewer than two"), "  fewer than two ready: inconclusive, though all are cooling")
WoW.itemCooldowns[279979] = nil
eq(T.takeBaseline(), 2, "two ready features: the baseline")
v, detail = T.cooldownVerdict()
check(v == nil and detail:find("none of the ready"), "  nothing placed yet: inconclusive")
WoW.itemCooldowns[279979] = { 100, 3600 }        -- the Camp Chair placed
v, detail = T.cooldownVerdict()
check(v == false and detail:find("independent"), "  only the placed one cooling: independent")
WoW.itemCooldowns[279969] = { 100, WoW.Secret("dur") }
v, detail = T.cooldownVerdict()
check(v == nil and detail:find("unreadable"), "  the other's cooldown secret: inconclusive, not independent")
WoW.items[279969] = 0
WoW.itemCooldowns[279969] = nil
v, detail = T.cooldownVerdict()
check(v == nil and detail:find("unreadable"), "  the other no longer carried: inconclusive")
WoW.items[279969] = 1
WoW.itemCooldowns[279969] = { 100, 3600 }
v, detail = T.cooldownVerdict()
check(v == true and detail:find("shared"), "  both cooling: shared")
WoW.itemCooldowns[279969], WoW.itemCooldowns[279979] = nil, nil

-- Camping cooldowns: features cooling down, kits not counted.
WoW.itemCooldowns[279979] = { 100, 3600 }
local cooling, carried = T.readCamping()
check(cooling == 1 and carried == 2, "one of two features cooling down")
WoW.itemCooldowns[279969] = { 100, 3600 }
WoW.itemCooldowns[279981] = { 100, 3600 }
cooling, carried = T.readCamping()
check(cooling == 2 and carried == 2, "  both: shared (the kit not counted)")
WoW.itemCooldowns[279969] = { 100, WoW.Secret("dur") }
cooling = T.readCamping()
eq(cooling, 1, "  a secret duration isn't counted")
check(logHas("Camp Chair %(279979%) x2: cooldown start 100, duration 3600"), "  each item logged")

-- The commands and the procedure.
SlashCmdList.FOREVERPROBE("gab aura")
SlashCmdList.FOREVERPROBE("gab camping")
SlashCmdList.FOREVERPROBE("steps gab campfire")
local rec = ForeverProbeDB.steps and ForeverProbeDB.steps.records and ForeverProbeDB.steps.records["GABProbe/campfire"]
check(rec and rec.status == "active", "/fp steps gab campfire starts")
SlashCmdList.FOREVERPROBE("steps stop")

-- barmove (#30): the bars read, GAB's follow state logged; the procedure starts.
StanceBar:SetPoint("BOTTOMLEFT", UIParent, "BOTTOM", -300, 120)
StanceBar._rect = { 600, 700, 160, 120 }
SlashCmdList.FOREVERPROBE("gab bars")
check(logHas("StanceBar: shown true") and logHas("left 600"), "/fp gab bars: the stance bar's state and place")
check(logHas("PetActionBar: shown") and logHas("GAB follow: stance bar"), "  the pet bar, and GAB's follow state")
SlashCmdList.FOREVERPROBE("steps gab barmove")
rec = ForeverProbeDB.steps.records["GABProbe/barmove"]
check(rec and rec.status == "active", "/fp steps gab barmove starts")
SlashCmdList.FOREVERPROBE("steps stop")
SlashCmdList.FOREVERPROBE("steps gab look")
rec = ForeverProbeDB.steps.records["GABProbe/look"]
check(rec and rec.status == "active", "/fp steps gab look starts")
SlashCmdList.FOREVERPROBE("steps stop")
-- pearl (#44): the material and the numbers read as it starts.
SlashCmdList.FOREVERPROBE("steps gab pearl")
rec = ForeverProbeDB.steps.records["GABProbe/pearl"]
check(rec and rec.status == "active", "/fp steps gab pearl starts")
check(logHas("pearl") and logHas("gloss 0.08"), "  Pearl built, its gloss read")
SlashCmdList.FOREVERPROBE("steps stop")
-- icons (#46): the Utility bar's size read as it starts.
SlashCmdList.FOREVERPROBE("steps gab icons")
rec = ForeverProbeDB.steps.records["GABProbe/icons"]
check(rec and rec.status == "active", "/fp steps gab icons starts")
check(logHas("iconSize"), "  the Utility bar's size read")
SlashCmdList.FOREVERPROBE("steps stop")
-- dock (#53): the bar's containers beside their buttons, the union, and a
-- docked client's frame beside its buttons, each in UIParent units.
WoW.layoutBar(MainActionBar, 500, 100, { n = 3 })
for i = 1, 3 do
    local r = _G["ActionButton" .. i].container._rect
    _G["ActionButton" .. i]._rect = { r[1] + 3, r[2] - 3, r[3] - 7, r[4] - 7 }   -- buttons 7 lower, 3 inside
end
local cf = CreateFrame("Frame", "ProbeDockClient", UIParent)
cf._width, cf._height = 92, 45
local cb = CreateFrame("Button", "ProbeDockClientButton1", cf)
cb._rect, cb._escale = { 1286, 1376, 200, 110 }, 0.5   -- its own units: half scale
check(GAB.Dock.Register({ id = "probetest", label = "Probe test", frame = cf, Layout = function() end }), "a dock client")
GAB.Settings.SetDock("probetest", "bar", 1)
WoW.tick()
cf._rect = { 643, 735, 100, 55 }
SlashCmdList.FOREVERPROBE("gab dock")
check(logHas('probetest: docked to bar 1 %(MainActionBar%), side "RIGHT"'), "/fp gab dock: the client's dock settings")
check(logHas('container 1 .- L 500.0 R 545.0 T 100.0 B 55.0 .-button "ActionButton1" L 503.0 R 542.0 T 93.0 B 48.0 .-dL 3.0 dT %-7.0'),
    "  each container beside its button, and their offset")
check(logHas("containers' union %(the dock's target%) L 500.0 R 639.0 T 100.0 B 55.0"), "  the dock's target")
check(logHas("buttons' union L 503.0 R 636.0 T 93.0 B 48.0 .-; button row tops 93.0"), "  the buttons' union and rows")
check(logHas('client frame "ProbeDockClient" L 643.0 R 735.0'), "  the client's frame")
check(logHas('client child "ProbeDockClientButton1" Button L 643.0'), "  its shown children")
check(logHas("client buttons' union L 643.0 R 688.0 T 100.0 B 55.0 .-; row tops 100.0"), "  its buttons' union")
-- bagsbar (#55): the bag bar's methods, raw and inherited, and Layout run once.
SlashCmdList.FOREVERPROBE("gab bagsbar")
check(logHas("BagsBar.UpdateDividers: raw function, via frame function, mixin .-, secure true"), "/fp gab bagsbar: UpdateDividers read")
check(logHas("BagsBar.Layout: raw function"), "  Layout read")
check(logHas("BagsBar:Layout%(%) ran"), "  Layout run, and it ran")
-- (The stubs answer any unknown method, so "via frame" stays a function here.)
local saved, savedLayout = rawget(BagsBar, "UpdateDividers"), rawget(BagsBar, "Layout")
BagsBar.UpdateDividers = nil
BagsBar.Layout = function() error("attempt to call a nil value") end
WoW.tainted = { UpdateDividers = "SomeAddon" }
SlashCmdList.FOREVERPROBE("gab bagsbar")
check(logHas('BagsBar.UpdateDividers: raw nil, .-secure false "SomeAddon"'), "  gone and tainted: said so")
check(logHas("BagsBar:Layout%(%) ERROR .-attempt to call a nil value"), "  Layout's error logged")
BagsBar.UpdateDividers, BagsBar.Layout, WoW.tainted = saved, savedLayout, nil
SlashCmdList.FOREVERPROBE("steps gab dock")
rec = ForeverProbeDB.steps.records["GABProbe/dock"]
check(rec and rec.status == "active", "/fp steps gab dock starts")
SlashCmdList.FOREVERPROBE("steps stop")
-- micro (#57): the micro buttons' atlases read, cropped inside the atlas with
-- the Background faded, and put back; the empty bag slots' and key ring's icons faded.
local mtex = CharacterMicroButton:CreateTexture()
rawset(mtex, "GetAtlas", function() return "UI-HUD-MicroMenu-CharacterInfo-Up" end)
rawset(mtex, "SetTexCoord", function(self, ...) self._tc = { ... } end)
rawset(CharacterMicroButton, "GetNormalTexture", function() return mtex end)
C_Texture = { GetAtlasInfo = function(a)
    return { width = 32, height = 40, file = 4567, leftTexCoord = 0.5, rightTexCoord = 0.75, topTexCoord = 0, bottomTexCoord = 0.5 }
end }
SlashCmdList.FOREVERPROBE("gab micro")
check(logHas('"CharacterMicroButton" .-Normal "UI%-HUD%-MicroMenu%-CharacterInfo%-Up" 32x40 file 4567 coords 0.5000 0.7500 0.0000 0.5000'),
    "/fp gab micro: each state's atlas, size and coords")
check(logHas("CharacterBag1Slot shown true, icon .-occupied %(GAB%) false"), "  each bag slot's icon and GAB's occupancy")
T.cropMicro(0.1)()
local tc = mtex._tc
check(tc and math.abs(tc[1] - 0.525) < 1e-9 and math.abs(tc[2] - 0.725) < 1e-9 and math.abs(tc[3] - 0.05) < 1e-9
    and math.abs(tc[4] - 0.45) < 1e-9, "  cropped by 10% inside its atlas")
eq(CharacterMicroButton.Background:GetAlpha(), 0, "  its background faded")
T.cropMicro(0)()
eq(CharacterMicroButton.Background:GetAlpha(), 1, "  inset 0: the background back")
T.fadeBagIcons("empty")()
eq(CharacterBag1Slot.icon:GetAlpha(), 0, "an empty bag slot's icon faded")
eq(KeyRingButton.icon:GetAlpha(), 0, "  the key ring's too")
eq(MainMenuBarBackpackButton.icon:GetAlpha(), 1, "  the backpack's kept")
T.fadeBagIcons("all")()
eq(CharacterBag1Slot.icon:GetAlpha(), 1, "  back")
C_Texture = nil
SlashCmdList.FOREVERPROBE("steps gab micro")
rec = ForeverProbeDB.steps.records["GABProbe/micro"]
check(rec and rec.status == "active", "/fp steps gab micro starts")
SlashCmdList.FOREVERPROBE("steps stop")
SlashCmdList.FOREVERPROBE("gab clear")
eq(#GABProbeDB.log, 1, "/fp gab clear empties the log in place (one line left: 'log cleared')")

eq(#WoW.chat, chatBefore, "nothing went to chat")
eq(next(GAB.failures), nil, "nothing failed")
done("test_probe")
