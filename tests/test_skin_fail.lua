-- One button that can't be skinned doesn't stop the others; the failure is
-- recorded for /gab failures. And the skin turned off leaves every button as
-- Blizzard made it.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

rawset(ActionButton5, "GetFrameLevel", function() error("boom") end)
local GAB = loadAddon()
check(GAB.failures["skin:ActionButton5"] ~= nil, "the failure is recorded under its button")
check(GAB.Buttons.IsSkinned(ActionButton4), "the button before it is skinned")
check(GAB.Buttons.IsSkinned(ActionButton6), "the button after it is skinned")
check(GAB.Buttons.IsSkinned(StanceButton1), "the other families are skinned")
newChat()
SlashCmdList.GLASSACTIONBARS("failures")
check(chatHas("skin:ActionButton5"), "/gab failures names it")

-- The skin off: nothing touched.
dofile("tests/wow_stubs.lua")
GAB = loadAddon({ db = { skin = false } })
check(not GAB.Buttons.IsSkinned(ActionButton1), "skin off: no glass")
eq(ActionButton1.NormalTexture:GetAlpha(), 1, "  Blizzard's art as it was")
eq(MainActionBar.BorderArt:GetAlpha(), 1, "  the main bar's art as it was")
eq(WoW.hooked[ActionButton1], nil, "  no hook installed")

done("test_skin_fail")
