-- A login in combat (a /reload mid-fight) waits for the fight to end before
-- putting anything on Blizzard's protected buttons.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

WoW.combat = true
local GAB = loadAddon()
check(not GAB.Buttons.IsSkinned(ActionButton1), "nothing skinned in combat")
eq(#WoW.violations, 0, "nothing protected touched")

WoW.combat = false
WoW.fire("PLAYER_REGEN_ENABLED")
check(GAB.Buttons.IsSkinned(ActionButton1), "skinned when the fight ends")
check(GAB.Buttons.IsSkinned(PetActionButton10), "  every family")
eq(next(GAB.failures), nil, "nothing failed")

-- A second fight changes nothing: the skin is built once.
local body = GAB.Buttons._test.skins[ActionButton1].body
WoW.fire("PLAYER_REGEN_ENABLED")
eq(GAB.Buttons._test.skins[ActionButton1].body, body, "built once")

done("test_skin_combat")
