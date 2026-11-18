-- A login in combat (a /reload mid-fight) waits for the fight to end before
-- putting anything on Blizzard's protected buttons. LibGlass refuses to build
-- a skin in a fight (r13), so every family waits, the bag bar too (#105).
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

WoW.bagTextures[31] = 133633          -- a bag in the first slot; the others empty
WoW.combat = true
local GAB = loadAddon()
check(not GAB.Buttons.IsSkinned(ActionButton1), "nothing skinned in combat")
check(not GAB.Buttons.IsSkinned(CharacterBag0Slot), "  nor the bag slots")
eq(CharacterBag1Slot.icon:GetAlpha(), 1, "  an empty bag slot's icon left as it is")
eq(#WoW.violations, 0, "nothing protected touched")

WoW.combat = false
WoW.fire("PLAYER_REGEN_ENABLED")
check(GAB.Buttons.IsSkinned(ActionButton1), "skinned when the fight ends")
check(GAB.Buttons.IsSkinned(PetActionButton10), "  every family")
for _, n in ipairs({ "MainMenuBarBackpackButton", "CharacterBag0Slot", "CharacterBag1Slot", "KeyRingButton" }) do
    check(GAB.Buttons.IsSkinned(_G[n]), "  the bag bar: " .. n)
end
eq(GAB.Buttons.State(CharacterBag1Slot).occupied, false, "  an empty bag slot read as empty")
eq(CharacterBag1Slot.icon:GetAlpha(), 0, "  its greyed icon faded")
eq(CharacterBag0Slot.icon:GetAlpha(), 1, "  a bag's icon untouched")
eq(next(GAB.failures), nil, "nothing failed")

-- A second fight changes nothing: the skin is built once.
local body = GAB.Buttons._test.skins[ActionButton1].body
local bagBody = GAB.Buttons.State(CharacterBag0Slot).body
WoW.fire("PLAYER_REGEN_ENABLED")
eq(GAB.Buttons._test.skins[ActionButton1].body, body, "built once")
eq(GAB.Buttons.State(CharacterBag0Slot).body, bagBody, "  the bags too")

done("test_skin_combat")
