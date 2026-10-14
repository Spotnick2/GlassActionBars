-- The bag bar (full glass, like the action buttons) and the micro menu (a
-- glass panel behind Blizzard's own framed icons), #14. No field written on
-- a Blizzard frame, art faded not hidden, re-styled after Blizzard's writers,
-- the icons and the micro buttons left alone.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local function close(a, b) return type(a) == "number" and type(b) == "number" and math.abs(a - b) < 1e-6 end

local BAGS = {}
for _, n in ipairs({ "MainMenuBarBackpackButton", "CharacterBag0Slot", "CharacterBag1Slot", "CharacterBag2Slot",
                     "CharacterBag3Slot", "CharacterReagentBag0Slot", "KeyRingButton" }) do BAGS[#BAGS + 1] = _G[n] end
local FRAMES = { BagsBar, MicroMenu, MicroMenuContainer, CharacterMicroButton }
for _, b in ipairs(BAGS) do FRAMES[#FRAMES + 1] = b end
local function fields(w)
    local t = {}
    for k, v in pairs(w) do if not (type(k) == "string" and k:sub(1, 1) == "_") then t[k] = v end end
    return t
end
local before = {}
for _, f in ipairs(FRAMES) do before[f] = fields(f) end
local iconBefore = {}
for _, b in ipairs(BAGS) do iconBefore[b] = { b.icon:GetAlpha(), #b.icon._points } end

WoW.bagTextures[31] = 133633          -- a bag in the first slot; the others empty
local GAB = loadAddon()
eq(next(GAB.failures), nil, "nothing failed")

for _, f in ipairs(FRAMES) do
    local after = fields(f)
    for k, v in pairs(after) do
        local hooked = WoW.hooked[f] and WoW.hooked[f][k]
        check(hooked or before[f][k] == v, f._name .. ": no field written: " .. tostring(k))
    end
end

-- Bags: full glass.
local rimFile = GAB.MEDIA .. "ButtonRim"
for _, b in ipairs(BAGS) do
    local s = GAB.Buttons.State(b)
    check(s ~= nil, b._name .. " is skinned")
    eq(b.NormalTexture:GetAlpha(), 0, b._name .. ": its gold frame faded")
    check(b.NormalTexture:IsShown(), b._name .. ":   not hidden")
    eq(b.PushedTexture._file, rimFile, b._name .. ": pressed, the glass rim")
    eq(s.g.rim._file, rimFile, b._name .. ": our rim")
    eq(b.icon:GetAlpha(), iconBefore[b][1], b._name .. ": the icon (or empty-slot silhouette) untouched")
    eq(#b.icon._points, iconBefore[b][2], b._name .. ": the icon never moved")
end
eq(GAB.Buttons.State(KeyRingButton).small, true, "the 33 px key ring is the small size")
local function rim(b) return GAB.Buttons.State(b).g.rim:GetAlpha() end
local full, empty = GAB.Buttons.Tune("rim"), GAB.Buttons.Tune("rim") * GAB.Buttons.Tune("empty")
check(close(rim(MainMenuBarBackpackButton), full), "the backpack: full rim")
check(close(rim(CharacterBag0Slot), full), "a slot with a bag: full rim")
check(close(rim(CharacterBag1Slot), empty), "an empty bag slot: the quieter rim")

-- UpdateTextures sets the atlases again (every slot update): faded again, the
-- rim follows the bag.
CharacterBag1Slot.NormalTexture:SetAlpha(1)
WoW.bagTextures[32] = 133634
CharacterBag1Slot:UpdateTextures()
eq(CharacterBag1Slot.NormalTexture:GetAlpha(), 0, "UpdateTextures: the frame faded again")
eq(CharacterBag1Slot.PushedTexture._file, rimFile, "  the pressed look ours again")
eq(CharacterBag1Slot.PushedTexture._blend, "ADD", "  added light again")
check(close(rim(CharacterBag1Slot), full), "  a bag put in: full rim")
WoW.bagTextures[32] = nil
CharacterBag1Slot:UpdateTextures()
check(close(rim(CharacterBag1Slot), empty), "  taken out: the quieter rim")

-- The bar's own art.
eq(BagsBar.BorderArt:GetAlpha(), 0, "the bag bar's frame faded")
check(BagsBar.BorderArt:IsShown(), "  not hidden")
BagsBar:Layout()
local n = 0
for d in BagsBar.HorizontalDividersPool:EnumerateActive() do n = n + 1; eq(d:GetAlpha(), 0, "Layout: a new divider faded") end
eq(n, 5, "the dividers were acquired again")

-- Micro menu: Blizzard's dark panel faded, ours behind the buttons.
eq(MicroMenu.BorderArt:GetAlpha(), 0, "the micro menu's border art faded")
eq(MicroMenu.BackgroundArt:GetAlpha(), 0, "the micro menu's background faded")
check(MicroMenu.BorderArt:IsShown(), "  not hidden")
local panel, g = GAB.Micro._test.panel(), GAB.Micro._test.glass()
check(panel:IsShown(), "our glass panel shows")
eq(panel:GetParent(), UIParent, "  a frame of its own (MicroMenu flattens its children's layers)")
check(panel:GetFrameLevel() < MicroMenu:GetFrameLevel(), "  under the micro menu")
eq(g.top:GetFrameLevel(), panel:GetFrameLevel(), "  its rims too, never over the buttons")
eq(panel._mouse, false, "  takes no clicks")
eq(CharacterMicroButton.Background:GetAlpha(), 1, "the micro buttons' own art untouched")
check(not GAB.Buttons.IsSkinned(CharacterMicroButton), "no glass rim round a framed icon")
GAB.Settings.SetTune("body", 0.5)
check(close(g.tint._color[4], GAB.Glass.STYLE.tint[4] * 0.5), "the panel's body follows /gab tune body")

-- Blizzard moves the micro menu to the override bar or a pet battle: the panel goes; back home, it returns.
MicroMenu:SetParent(OverrideActionBar)
check(not panel:IsShown(), "micro menu away (override bar): no panel")
MicroMenu:SetParent(MicroMenuContainer)
check(panel:IsShown(), "back home: the panel")
MicroMenu:Hide()
check(not panel:IsShown(), "micro menu hidden: no panel")
MicroMenu:Show()
check(panel:IsShown(), "shown again: the panel")
MicroMenu.BackgroundArt:SetAlpha(1)
WoW.fire("EDIT_MODE_LAYOUTS_UPDATED")
eq(MicroMenu.BackgroundArt:GetAlpha(), 0, "an Edit Mode layout change: faded again")

-- Combat: nothing protected touched.
WoW.combat = true
for _, b in ipairs(BAGS) do b:UpdateTextures() end
BagsBar:Layout()
MicroMenu:SetParent(OverrideActionBar)
MicroMenu:SetParent(MicroMenuContainer)
eq(#WoW.violations, 0, "nothing protected changed in combat")
WoW.combat = false

-- The skin off: none of it.
dofile("tests/wow_stubs.lua")
GAB = loadAddon({ db = { skin = false } })
check(not GAB.Buttons.IsSkinned(CharacterBag0Slot), "skin off: no glass on the bags")
eq(BagsBar.BorderArt:GetAlpha(), 1, "  the bag bar's art as it was")
eq(MicroMenu.BorderArt:GetAlpha(), 1, "  the micro menu's art as it was")
eq(GAB.Micro._test.panel(), nil, "  no panel")

done("test_bags_micro")
