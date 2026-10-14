-- A step that throws on one button doesn't stop the others, nor the rest of
-- that button's skin: above all its body stays painted and in /gab tune's
-- reach (the owner's report, 2026-10-13: wash 0 and body 0 left a grey fill
-- when a later step threw before the theme registered the body). Failures are
-- recorded for /gab failures. And the skin turned off leaves every button as
-- Blizzard made it.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local function close(a, b) return type(a) == "number" and type(b) == "number" and math.abs(a - b) < 1e-6 end

-- A client that refuses our pressed look on Blizzard's pushed texture.
local refused = 0
local realSlice = nil
for _, prefix in ipairs({ "ActionButton", "MultiBarBottomLeftButton" }) do
    for i = 1, 12 do
        rawset(_G[prefix .. i].PushedTexture, "SetTextureSliceMargins", function() refused = refused + 1; error("refused") end)
    end
end
-- And one button whose level can't be read.
rawset(ActionButton5, "GetFrameLevel", function() error("boom") end)

local GAB = loadAddon()
check(refused > 0, "the client refused the pressed look")
check(GAB.failures["skin:pushed"] ~= nil, "the refusal is recorded")
check(GAB.failures["skin:level:ActionButton5"] ~= nil, "the level failure is recorded under its button")
for _, b in ipairs({ ActionButton1, ActionButton5, MultiBarBottomLeftButton3, StanceButton1 }) do
    local s = GAB.Buttons.State(b)
    check(s ~= nil, b._name .. " is skinned")
    eq(b.NormalTexture:GetAlpha(), 0, b._name .. ": its frame art still faded")
    eq(b.SlotArt:GetAlpha(), 0, b._name .. ": its slot art still faded")
end

-- The body of every button, the refused ones included, follows /gab tune to zero.
GAB.Settings.SetTune("wash", 0)
GAB.Settings.SetTune("body", 0)
for _, b in ipairs({ ActionButton1, ActionButton5, MultiBarBottomLeftButton3, StanceButton1 }) do
    local g = GAB.Buttons.State(b).g
    check(close(g.wash._gradient[3].a, 0), b._name .. ": wash 0 reaches the haze's gradient")
    check(not g.wash:IsShown(), b._name .. ": the haze hidden")
    check(close(g.tint._color[4], 0), b._name .. ": body 0 reaches the tint")
    check(not g.tint:IsShown(), b._name .. ": the tint hidden")
    eq(g.shadow:GetAlpha(), 0, b._name .. ": no shadow")
    eq(g.grain:GetAlpha(), 0, b._name .. ": no grain")
end
newChat()
SlashCmdList.GLASSACTIONBARS("failures")
check(chatHas("skin:level:ActionButton5"), "/gab failures names it")

-- The skin off: nothing touched.
dofile("tests/wow_stubs.lua")
GAB = loadAddon({ db = { skin = false } })
check(not GAB.Buttons.IsSkinned(ActionButton1), "skin off: no glass")
eq(ActionButton1.NormalTexture:GetAlpha(), 1, "  Blizzard's art as it was")
eq(MainActionBar.BorderArt:GetAlpha(), 1, "  the main bar's art as it was")
eq(WoW.hooked[ActionButton1], nil, "  no hook installed")

done("test_skin_fail")
