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
SlashCmdList.FOREVERPROBE("gab clear")
eq(#GABProbeDB.log, 1, "/fp gab clear empties the log in place (one line left: 'log cleared')")

eq(#WoW.chat, chatBefore, "nothing went to chat")
eq(next(GAB.failures), nil, "nothing failed")
done("test_probe")
