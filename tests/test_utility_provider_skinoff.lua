-- Another addon's Utility button with the glass off (/gab skin off, #52):
-- made, shown and clickable, never skinned.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local clicks = 0
local GAB = loadAddon({
    db = { skin = false, utility = { show = { ["provider:roulette"] = true } } },
    beforeLogin = function(G)
        G.RegisterButton({ id = "roulette", icon = 1, OnClick = function() clicks = clicks + 1 end })
    end })
WoW.tick()
local b = GAB.Utility.buttons["provider:roulette"]
check(b ~= nil and b:IsShown(), "the glass off: the button still made and shown")
check(not GAB.Buttons.IsSkinned(b), "  not skinned")
b:GetScript("OnClick")(b, "LeftButton")
eq(clicks, 1, "  and it clicks")
eq(next(GAB.failures), nil, "nothing failed")

done("test_utility_provider_skinoff")
