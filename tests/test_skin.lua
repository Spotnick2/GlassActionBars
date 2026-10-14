-- The glass on Blizzard's own buttons: the action bars, stance and pet. No
-- field written onto a Blizzard frame, the stock art faded (never hidden),
-- re-styled after each Blizzard writer, the rim bright on a slot with an
-- action and faint on an empty one, nothing done to a protected frame in
-- combat, and the main bar's own art faded.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local function close(a, b) return type(a) == "number" and type(b) == "number" and math.abs(a - b) < 1e-6 end

-- Every Blizzard frame the skin touches.
local FRAMES = { MainActionBar, StanceBar, PetActionBar }
for _, prefix in ipairs(ActionButtonUtil.ActionBarButtonNames) do
    for i = 1, 12 do FRAMES[#FRAMES + 1] = _G[prefix .. i] end
end
for i = 1, 10 do FRAMES[#FRAMES + 1] = _G["StanceButton" .. i]; FRAMES[#FRAMES + 1] = _G["PetActionButton" .. i] end
eq(#FRAMES, 3 + 96 + 20, "the stubbed frames")

-- Fields, not the stub's own bookkeeping (keys starting with _).
local function fields(w)
    local t = {}
    for k, v in pairs(w) do if not (type(k) == "string" and k:sub(1, 1) == "_") then t[k] = v end end
    return t
end
local before = {}
for _, f in ipairs(FRAMES) do before[f] = fields(f) end

-- A hidden button (an empty slot without "Always show buttons") is skinned like the rest.
ActionButton6:Hide()
WoW.actions[1] = true

local GAB = loadAddon()
local T = GAB.Buttons._test
eq(next(GAB.failures), nil, "nothing failed")

for _, f in ipairs(FRAMES) do
    local after = fields(f)
    local name = f._name
    for k, v in pairs(after) do
        local hooked = WoW.hooked[f] and WoW.hooked[f][k]
        check(hooked or before[f][k] == v, name .. ": no field written: " .. tostring(k))
    end
    for k in pairs(before[f]) do check(after[k] ~= nil, name .. ": no field removed: " .. tostring(k)) end
end

-- Every button is skinned; its stock art faded, not hidden.
local Glass = GAB.Glass
local rimFile = Glass.MEDIA .. Glass.SIZES.thin_small.rim
for _, f in ipairs(FRAMES) do
    if f._type == "CheckButton" then
        local name = f._name
        check(GAB.Buttons.IsSkinned(f), name .. " is skinned")
        for _, key in ipairs({ "NormalTexture", "SlotArt", "SlotBackground" }) do
            eq(f[key]:GetAlpha(), 0, name .. ": " .. key .. " faded")
            check(f[key]:IsShown(), name .. ": " .. key .. " not hidden")
        end
        eq(f.PushedTexture._file, rimFile, name .. ": pressed, the glass rim")
        eq(f.PushedTexture._blend, "ADD", name .. ": pressed, added light")
        eq(f.HighlightTexture:GetAlpha(), GAB.Buttons.HIGHLIGHT, name .. ": hover softened")
        local s = T.skins[f]
        check(s.body:GetFrameLevel() < f:GetFrameLevel(), name .. ": the body under the button")
        check(s.g.top:GetFrameLevel() > f:GetFrameLevel(), name .. ": the rim over the icon")
        check(s.g.top:GetFrameLevel() < f.TextOverlayContainer:GetFrameLevel(), name .. ": the text over the rim")
        eq(s.body._mouse, false, name .. ": the glass takes no clicks")
        eq(#f.icon._points, 0, name .. ": the icon is never moved")
    end
end
eq(T.skins[StanceButton1].small, true, "stance buttons are the small size")
eq(T.skins[ActionButton1].small, false, "action buttons are not")

-- The rim: bright with an action, faint without, kept when unreadable.
local function rim(b) return T.skins[b].g.rim:GetAlpha() end
local full = Glass.STYLE.rimAlpha
check(close(rim(ActionButton1), full), "a slot with an action: full rim")
check(close(rim(ActionButton2), full * GAB.Buttons.EMPTY_RIM), "an empty slot: faint rim")
WoW.actions[2] = true
ActionButton2:Update()
check(close(rim(ActionButton2), full), "Blizzard's Update: the rim follows the slot")
WoW.actions[2] = nil
ActionButton2:Update()
check(close(rim(ActionButton2), full * GAB.Buttons.EMPTY_RIM), "  and back")
WoW.actions[2] = WoW.Secret("HasAction")
ActionButton2:Update()
check(close(rim(ActionButton2), full * GAB.Buttons.EMPTY_RIM), "a secret answer keeps the last state")
WoW.actions[2] = nil

-- UpdateButtonArt sets Blizzard's atlases again: the skin follows it.
ActionButton3.NormalTexture:SetAlpha(1)
ActionButton3:UpdateButtonArt()
eq(ActionButton3.NormalTexture:GetAlpha(), 0, "UpdateButtonArt: the frame art faded again")
eq(ActionButton3.PushedTexture._file, rimFile, "  the pressed look ours again")
eq(ActionButton3.PushedTexture._blend, "ADD", "  added light again")

-- Stance and pet: their bar refreshes every button.
WoW.forms[1] = true
StanceBar:UpdateState()
check(close(rim(StanceButton1), full), "a known form: full rim")
check(close(rim(StanceButton2), full * GAB.Buttons.EMPTY_RIM), "no second form: faint rim")
WoW.petActions[3] = true
PetActionBar:Update()
check(close(rim(PetActionButton3), full), "a pet action: full rim")
check(close(rim(PetActionButton4), full * GAB.Buttons.EMPTY_RIM), "an empty pet slot: faint rim")

-- Text: the glass font, outlined; hotkeys and macro names can be turned off.
local file = Glass.FONTS[Glass.fontKey].file
eq(ActionButton1.HotKey._font[1], file, "the hotkey in the glass font")
eq(ActionButton1.HotKey._font[3], "OUTLINE", "  outlined")
eq(ActionButton1.Count._font[1], file, "the count in the glass font")
ActionButton1:UpdateHotkeys()
eq(ActionButton1.HotKey._font[1], file, "UpdateHotkeys: the glass font again")
GAB.Settings.SetShowHotkeys(false)
eq(ActionButton1.HotKey:GetAlpha(), 0, "hotkeys off")
GAB.Settings.SetShowHotkeys(true)
eq(ActionButton1.HotKey:GetAlpha(), 1, "hotkeys on")
GAB.Settings.SetShowMacroNames(false)
eq(ActionButton1.Name:GetAlpha(), 0, "macro names off")
GAB.Settings.SetShowMacroNames(true)

-- Themes repaint every button's body live.
local tint = T.skins[ActionButton1].g.tint
GAB.Settings.SetTheme("smoked")
check(close(tint._color[4], 0.62), "smoked: the darker body")
GAB.Settings.SetTheme("class")
check(close(tint._color[1], 0.53 * 0.6), "class: the class colour, shaded")
GAB.Settings.SetTheme("clear")
check(close(tint._color[4], Glass.STYLE.tint[4]), "clear: as built")
eq(GAB.Settings.SetTheme("neon"), false, "an unknown theme is refused")
eq(GAB.db.theme, "clear", "  and changes nothing")

-- The main bar's art.
eq(MainActionBar.BorderArt:GetAlpha(), 0, "the main bar's border art faded")
check(MainActionBar.BorderArt:IsShown(), "  not hidden")
for d in MainActionBar.HorizontalDividersPool:EnumerateActive() do eq(d:GetAlpha(), 0, "a divider faded") end
MainActionBar:UpdateDividers()
local n = 0
for d in MainActionBar.HorizontalDividersPool:EnumerateActive() do
    n = n + 1
    eq(d:GetAlpha(), 0, "UpdateDividers: the new divider faded")
end
eq(n, 11, "the dividers were acquired again")
eq(MainActionBar.EndCaps.LeftEndCap.Texture:GetAlpha(), 0, "the gryphons faded by default")
check(MainActionBar.EndCaps.LeftEndCap:GetAlpha() == 1, "  the end cap system itself untouched")
GAB.Settings.SetEndCaps(true)
eq(MainActionBar.EndCaps.RightEndCap.Texture:GetAlpha(), 1, "gryphons on")
GAB.Settings.SetEndCaps(false)
MainActionBar.BorderArt:SetAlpha(1)
WoW.fire("EDIT_MODE_LAYOUTS_UPDATED")
eq(MainActionBar.BorderArt:GetAlpha(), 0, "an Edit Mode layout change: faded again")

-- In combat, Blizzard's writers keep firing; the skin changes nothing protected.
WoW.combat = true
WoW.fire("PLAYER_REGEN_DISABLED")
for _, f in ipairs(FRAMES) do
    if f._type == "CheckButton" then
        f:UpdateButtonArt()
        if f.Update then f:Update() end
    end
end
StanceBar:UpdateState()
PetActionBar:Update()
MainActionBar:UpdateDividers()
WoW.fire("EDIT_MODE_LAYOUTS_UPDATED")
GAB.Settings.SetTheme("smoked")
eq(#WoW.violations, 0, "nothing protected changed in combat: " .. table.concat(WoW.violations, ", "))
WoW.combat = false

done("test_skin")
