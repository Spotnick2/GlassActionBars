-- The bag bar (full glass, like the action buttons; an empty slot the
-- empty-slots look, #50, its greyed icon faded, #57) and the micro menu
-- (Blizzard's dark panel faded; each button's frame cropped off, on glass
-- tiles or one pill, #57), #14. No field written on a Blizzard frame, art
-- faded not hidden, re-styled after Blizzard's writers.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local function close(a, b) return type(a) == "number" and type(b) == "number" and math.abs(a - b) < 1e-6 end

local BAGS = {}
for _, n in ipairs({ "MainMenuBarBackpackButton", "CharacterBag0Slot", "CharacterBag1Slot", "CharacterBag2Slot",
                     "CharacterBag3Slot", "CharacterReagentBag0Slot", "KeyRingButton" }) do BAGS[#BAGS + 1] = _G[n] end
local MICRO = { CharacterMicroButton, SpellbookMicroButton, MainMenuMicroButton }
local FRAMES = { BagsBar, MicroMenu, MicroMenuContainer }
for _, b in ipairs(MICRO) do FRAMES[#FRAMES + 1] = b end
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
check(filled(CharacterBag0Slot), "a slot with a bag: full glass")
check(frosted(CharacterBag1Slot), "an empty bag slot: frosted, like an empty action slot")
check(frosted(CharacterReagentBag0Slot), "the empty reagent bag slot too")
check(frosted(KeyRingButton), "the key ring with no keys (HasKey false): empty too")

-- An empty slot's greyed icon faded (#57); a filled one's left as it was.
eq(MainMenuBarBackpackButton.icon:GetAlpha(), iconBefore[MainMenuBarBackpackButton][1], "the backpack's icon untouched")
eq(CharacterBag0Slot.icon:GetAlpha(), iconBefore[CharacterBag0Slot][1], "a bag's icon untouched")
eq(CharacterBag1Slot.icon:GetAlpha(), 0, "an empty slot's wing faded")
eq(CharacterReagentBag0Slot.icon:GetAlpha(), 0, "  the empty reagent slot's")
eq(KeyRingButton.icon:GetAlpha(), 0, "  the empty key ring's")
check(CharacterBag1Slot.icon:IsShown(), "  faded, not hidden")

-- The key ring follows HasKey; an unreadable answer keeps the last state,
-- filled or empty.
WoW.hasKey = true
KeyRingButton:UpdateTextures()
check(filled(KeyRingButton) and KeyRingButton.icon:GetAlpha() == 1, "keys: the key ring filled, its icon back")
WoW.hasKey = "throw"
KeyRingButton:UpdateTextures()
check(filled(KeyRingButton) and KeyRingButton.icon:GetAlpha() == 1, "  HasKey refused: still filled")
WoW.hasKey = WoW.Secret("HasKey")
KeyRingButton:UpdateTextures()
check(filled(KeyRingButton) and KeyRingButton.icon:GetAlpha() == 1, "  a secret: still filled")
WoW.hasKey = false
KeyRingButton:UpdateTextures()
check(frosted(KeyRingButton) and KeyRingButton.icon:GetAlpha() == 0, "no keys: empty again")
WoW.hasKey = "throw"
KeyRingButton:UpdateTextures()
check(frosted(KeyRingButton) and KeyRingButton.icon:GetAlpha() == 0, "  refused: still empty")
WoW.hasKey = nil
-- Blizzard's own alpha on a filled slot's icon is never overwritten.
CharacterBag0Slot.icon:SetAlpha(0.4)
CharacterBag0Slot:UpdateTextures()
eq(CharacterBag0Slot.icon:GetAlpha(), 0.4, "a filled slot's icon: Blizzard's alpha kept")
CharacterBag0Slot.icon:SetAlpha(1)

-- It follows the empty-slots look (/gab look).
GAB.Settings.SetLook("emptySlots", "faint")
check(close(rim(CharacterBag1Slot), B.Tune("rim") * B.Tune("empty") * B.EMPTY.faint) and socket(CharacterBag1Slot) == 0,
    "faint: the empty bag slot's rim")
check(filled(CharacterBag0Slot), "  the slot with a bag unchanged")
GAB.Settings.SetLook("emptySlots", "hidden")
check(rim(CharacterBag1Slot) == 0 and not B.State(CharacterBag1Slot).g.tint:IsShown(), "hidden: no glass on the empty bag slot")
check(CharacterBag1Slot:IsShown() and #CharacterBag1Slot.icon._points == iconBefore[CharacterBag1Slot][2],
    "  the slot still there (it takes a bag), its icon unmoved")
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
eq(CharacterBag1Slot.icon:GetAlpha(), 1, "  its icon back")
WoW.bagTextures[32] = nil
CharacterBag1Slot:UpdateTextures()
check(frosted(CharacterBag1Slot), "  taken out: frosted again")
eq(CharacterBag1Slot.icon:GetAlpha(), 0, "  its wing faded again")

-- The bar's own art.
eq(BagsBar.BorderArt:GetAlpha(), 0, "the bag bar's frame faded")
check(BagsBar.BorderArt:IsShown(), "  not hidden")
BagsBar:Layout()
local n = 0
for d in BagsBar.HorizontalDividersPool:EnumerateActive() do n = n + 1; eq(d:GetAlpha(), 0, "Layout: a new divider faded") end
eq(n, 5, "the dividers were acquired again")

-- Micro menu: Blizzard's dark panel faded.
eq(MicroMenu.BorderArt:GetAlpha(), 0, "the micro menu's border art faded")
eq(MicroMenu.BackgroundArt:GetAlpha(), 0, "the micro menu's background faded")
check(MicroMenu.BorderArt:IsShown(), "  not hidden")
MicroMenu.BackgroundArt:SetAlpha(1)
WoW.fire("EDIT_MODE_LAYOUTS_UPDATED")
eq(MicroMenu.BackgroundArt:GetAlpha(), 0, "an Edit Mode layout change: faded again")

-- Each micro button on glass (#57), inside the button (they overlap by 5).
local M = GAB.Micro
for _, b in ipairs(MICRO) do
    local s = B.State(b)
    check(s ~= nil, b._name .. ": on glass")
    local p = s and s.body._points[1]
    check(p and p[1] == "TOPLEFT" and p[4] == M.TILE_INSET and p[5] == -M.TILE_INSET, b._name .. ":   inset " .. M.TILE_INSET)
    eq(b.Background:GetAlpha(), 0, b._name .. ": its ButtonBG faded")
    eq(b.PushedBackground:GetAlpha(), 0, b._name .. ":   and the pushed one")
end
local ms = B.State(SpellbookMicroButton)
check(ms.gloss and ms.gloss._points[1][2] == ms.body, "Pearl's reflection on the inset glass, not the whole button")
GAB.Settings.SetLook("press", "ripple")
SpellbookMicroButton:GetScript("OnMouseDown")(SpellbookMicroButton, "LeftButton")
check(ms.ripple and ms.ripple._points[1][2] == ms.body, "  a click's ripple too")
GAB.Settings.SetLook("press", "flash")
eq(CharacterMicroButton.Shadow:GetAlpha(), 0, "the character button's shadow faded")
eq(CharacterMicroButton.PushedShadow:GetAlpha(), 0, "  and its pushed shadow")
-- The bronze frame cropped off every state (session 7: 8%, relative to the atlas).
local function cropped(t)
    local c = t._texcoord
    return c and close(c[1], 0.08) and close(c[2], 0.92) and close(c[3], 0.08) and close(c[4], 0.92)
end
for _, st in ipairs({ "Normal", "Pushed", "Disabled", "Highlight" }) do
    check(cropped(SpellbookMicroButton["Get" .. st .. "Texture"]()), "Spellbook: its " .. st .. " state cropped")
end
check(cropped(SpellbookMicroButton.FlashContent), "  its alert pulse too")
-- Blizzard sets each state again (press, release, enable, the game menu's
-- every second): cropped again after each.
for _, st in ipairs({ "Normal", "Pushed", "Disabled", "Highlight" }) do
    MainMenuMicroButton["Set" .. st .. "Atlas"](MainMenuMicroButton, "UI-HUD-MicroMenu-GameMenu-" .. st)
    check(cropped(MainMenuMicroButton["Get" .. st .. "Texture"]()), "Set" .. st .. "Atlas: cropped again")
end

-- The style: tiles by default; the pill (/gab micro pill, the options page) live.
local pill = M._test.pill()
eq(M.Style(), "tiles", "tiles by default")
check(B.State(SpellbookMicroButton).body:IsShown() and not pill:IsShown(), "  each tile's glass shown, no pill")
SlashCmdList.GLASSACTIONBARS("micro pill")
eq(rawget(GAB.db, "microStyle"), "pill", "/gab micro pill: saved")
check(not B.State(SpellbookMicroButton).body:IsShown() and not B.State(CharacterMicroButton).body:IsShown(), "  the tiles' glass hidden")
check(pill:IsShown(), "  the pill shown")
eq(pill:GetParent(), UIParent, "  a frame of its own (MicroMenu flattens its children's layers)")
check(pill:GetFrameLevel() < MicroMenu:GetFrameLevel(), "  under the micro menu")
check(cropped(SpellbookMicroButton:GetNormalTexture()), "  the frames still cropped")
-- Only while the micro menu is visible and home.
MicroMenu:SetParent(OverrideActionBar)
check(not pill:IsShown(), "micro menu away (override bar): no pill")
MicroMenu:SetParent(MicroMenuContainer)
check(pill:IsShown(), "  back home: the pill")
MicroMenu:Hide()
check(not pill:IsShown(), "  micro menu hidden: no pill")
MicroMenu:Show()
MicroMenuContainer:Hide()
check(not pill:IsShown(), "  its container hidden: no pill")
MicroMenuContainer:Show()
check(pill:IsShown(), "  shown again: the pill")
SlashCmdList.GLASSACTIONBARS("micro bogus")
eq(M.Style(), "pill", "/gab micro bogus: refused")
GAB.Options._test.panel:Show()
local radios = GAB.Options._test.microRadios
check(radios and not radios[1]:GetChecked() and radios[2]:GetChecked(), "the options page: One pill checked")
radios[1]:GetScript("OnClick")(radios[1])
eq(M.Style(), "tiles", "  Glass tiles clicked: tiles")
check(B.State(SpellbookMicroButton).body:IsShown() and not pill:IsShown(), "  the tiles back, no pill")

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
SpellbookMicroButton:SetNormalAtlas("UI-HUD-MicroMenu-SpellbookAbilities-Down")
check(cropped(SpellbookMicroButton:GetNormalTexture()), "in combat: cropped again")
GAB.Settings.SetMicroStyle("pill")
GAB.Settings.SetMicroStyle("tiles")
eq(#WoW.violations, 0, "nothing protected changed in combat")
WoW.combat = false

-- A login in combat: the micro menu waits for the fight to end.
dofile("tests/wow_stubs.lua")
WoW.combat = true
GAB = loadAddon()
check(not GAB.Buttons.IsSkinned(SpellbookMicroButton), "a login in combat: the micro buttons wait")
WoW.combat = false
WoW.fire("PLAYER_REGEN_ENABLED")
check(GAB.Buttons.IsSkinned(SpellbookMicroButton) and cropped(SpellbookMicroButton:GetNormalTexture()), "  built once it ends")
eq(next(GAB.failures), nil, "  nothing failed")

-- An unknown saved style is dropped.
dofile("tests/wow_stubs.lua")
GAB = loadAddon({ db = { microStyle = "bubbles" } })
eq(rawget(GAB.db, "microStyle"), nil, "an unknown micro style dropped")
eq(GAB.Micro.Style(), "tiles", "  tiles")

-- The skin off: none of it.
dofile("tests/wow_stubs.lua")
GAB = loadAddon({ db = { skin = false } })
check(not GAB.Buttons.IsSkinned(CharacterBag0Slot), "skin off: no glass on the bags")
eq(BagsBar.BorderArt:GetAlpha(), 1, "  the bag bar's art as it was")
eq(MicroMenu.BorderArt:GetAlpha(), 1, "  the micro menu's art as it was")
check(not GAB.Buttons.IsSkinned(SpellbookMicroButton), "  no glass on the micro buttons")
eq(SpellbookMicroButton:GetNormalTexture()._texcoord, nil, "  their frames not cropped")

done("test_bags_micro")
