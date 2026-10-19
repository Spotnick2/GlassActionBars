-- The bag bar (full glass, like the action buttons; an empty slot the
-- empty-slots look, #50) and the micro menu (Blizzard's dark panel faded, no
-- panel of ours, #50), #14. No field written on a Blizzard frame, art faded
-- not hidden, re-styled after Blizzard's writers, the icons and the micro
-- buttons left alone.
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
local B = GAB.Buttons
local function rim(b) return B.State(b).g.rim:GetAlpha() end
local function socket(b) return B.State(b).socketRim:GetAlpha() end
local function frosted(b)   -- Pearl's recessed socket, in the pale fill
    local s, frost = B.State(b), B.Frost()
    local c = s.g.tint._color
    return rim(b) == 0 and close(socket(b), B.Tune("rim") * B.Tune("empty") * B.Tune("frostRim"))
        and s.g.tint:IsShown() and close(c[1], frost[1]) and close(c[4], frost[4])
end
local function filled(b)
    local s = B.State(b)
    return close(rim(b), B.Tune("rim")) and socket(b) == 0
        and close(s.g.tint._color[4], GAB.Glass.STYLE.tint[4] * B.Tune("body"))
end
eq(B.Look("emptySlots"), "frosted", "empty slots frosted by default")
check(filled(MainMenuBarBackpackButton), "the backpack: full glass")
check(filled(KeyRingButton), "the key ring: full glass")
check(filled(CharacterBag0Slot), "a slot with a bag: full glass")
check(frosted(CharacterBag1Slot), "an empty bag slot: frosted, like an empty action slot")
check(frosted(CharacterReagentBag0Slot), "the empty reagent bag slot too")

-- It follows the empty-slots look (/gab look).
GAB.Settings.SetLook("emptySlots", "faint")
check(close(rim(CharacterBag1Slot), B.Tune("rim") * B.Tune("empty") * B.EMPTY.faint) and socket(CharacterBag1Slot) == 0,
    "faint: the empty bag slot's rim")
check(filled(CharacterBag0Slot), "  the slot with a bag unchanged")
GAB.Settings.SetLook("emptySlots", "hidden")
check(rim(CharacterBag1Slot) == 0 and not B.State(CharacterBag1Slot).g.tint:IsShown(), "hidden: no glass on the empty bag slot")
check(CharacterBag1Slot.icon:IsShown() and CharacterBag1Slot.icon:GetAlpha() == iconBefore[CharacterBag1Slot][1]
    and #CharacterBag1Slot.icon._points == iconBefore[CharacterBag1Slot][2], "  its silhouette (the icon) still shows, unmoved")
GAB.Settings.SetLook("emptySlots", "frosted")
check(frosted(CharacterBag1Slot), "frosted again")

-- UpdateTextures sets the atlases again (every slot update): faded again, the
-- rim follows the bag.
CharacterBag1Slot.NormalTexture:SetAlpha(1)
WoW.bagTextures[32] = 133634
CharacterBag1Slot:UpdateTextures()
eq(CharacterBag1Slot.NormalTexture:GetAlpha(), 0, "UpdateTextures: the frame faded again")
eq(CharacterBag1Slot.PushedTexture._file, rimFile, "  the pressed look ours again")
eq(CharacterBag1Slot.PushedTexture._blend, "ADD", "  added light again")
check(filled(CharacterBag1Slot), "  a bag put in: full glass")
WoW.bagTextures[32] = nil
CharacterBag1Slot:UpdateTextures()
check(frosted(CharacterBag1Slot), "  taken out: frosted again")

-- The bar's own art.
eq(BagsBar.BorderArt:GetAlpha(), 0, "the bag bar's frame faded")
check(BagsBar.BorderArt:IsShown(), "  not hidden")
BagsBar:Layout()
local n = 0
for d in BagsBar.HorizontalDividersPool:EnumerateActive() do n = n + 1; eq(d:GetAlpha(), 0, "Layout: a new divider faded") end
eq(n, 5, "the dividers were acquired again")

-- Micro menu: Blizzard's dark panel faded, and no panel of ours (#50).
eq(MicroMenu.BorderArt:GetAlpha(), 0, "the micro menu's border art faded")
eq(MicroMenu.BackgroundArt:GetAlpha(), 0, "the micro menu's background faded")
check(MicroMenu.BorderArt:IsShown(), "  not hidden")
local onMicro = 0
for _, f in ipairs(WoW.frames) do
    for _, p in ipairs(f._points) do if p[2] == MicroMenu then onMicro = onMicro + 1 end end
end
eq(onMicro, 0, "no glass panel behind the micro menu (nothing anchored to it)")
eq(CharacterMicroButton.Background:GetAlpha(), 1, "the micro buttons' own art untouched")
check(not GAB.Buttons.IsSkinned(CharacterMicroButton), "no glass rim round a framed icon")
MicroMenu.BackgroundArt:SetAlpha(1)
WoW.fire("EDIT_MODE_LAYOUTS_UPDATED")
eq(MicroMenu.BackgroundArt:GetAlpha(), 0, "an Edit Mode layout change: faded again")

-- Combat: a bag put in and taken out repaints the slot's own glass, and
-- nothing protected is touched.
WoW.combat = true
for _, b in ipairs(BAGS) do b:UpdateTextures() end
WoW.bagTextures[33] = 133635
CharacterBag2Slot:UpdateTextures()
check(filled(CharacterBag2Slot), "in combat: a bag put in, full glass")
WoW.bagTextures[33] = nil
CharacterBag2Slot:UpdateTextures()
check(frosted(CharacterBag2Slot), "  taken out, frosted again")
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

done("test_bags_micro")
