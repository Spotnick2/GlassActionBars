-- The Utility bar after a /reload in combat: the named binding targets exist
-- from load, nothing secure changes in combat, and the skin and the first
-- rebuild wait for the fight to end, and so does an undocked bar's saved spot.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

WoW.known[3413] = true
WoW.combat = true
local GAB = loadAddon({ db = { dock = { utility = { bar = false } }, utility = { pos = { x = 300, y = 200 } } } })
local U = GAB.Utility
eq(U.frame._points[1][1], "RIGHT", "undocked, in combat: not moved to the saved spot yet")
for _, b in pairs(U.buttons) do b._protected = true end
WoW.tick()
check(_G.GlassActionBarsUtil_cooking ~= nil, "a /reload in combat: the binding targets exist")
check(not GAB.Buttons.IsSkinned(U.buttons.cooking), "  not skinned in combat")
eq(U.buttons.cooking:GetAttribute("type"), nil, "  no attributes in combat")
eq(#WoW.violations, 0, "  no protected change in combat")
check(U.IsPending(), "  the rebuild pending")
WoW.combat = false
WoW.fire("PLAYER_REGEN_ENABLED")
check(GAB.Buttons.IsSkinned(U.buttons.cooking), "the fight over: skinned")
eq(U.buttons.cooking:GetAttribute("spell"), 3413, "  and built")
local p = U.frame._points[1]
check(p[1] == "BOTTOMLEFT" and p[4] == 300 and p[5] == 200, "  and at its saved spot")
eq(next(GAB.failures), nil, "nothing failed")

done("test_utility_combat")
