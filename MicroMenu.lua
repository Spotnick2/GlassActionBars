-- MicroMenu.lua: the micro menu on glass (#14, #57). Blizzard's dark panel
-- faded; each micro button's bronze frame cropped off its symbol; then the
-- player's style (GlassActionBarsDB.microStyle): "tiles", each button on GAB's
-- glass (Buttons.Build, inset), or "pill", one glass pill behind the menu
-- (GlassMiniMap's coordinates pill). Both are built once; a switch is live.
--
-- Forever's micro menu (Blizzard_MicroMenu, Mainline\MainMenuBarMicroButtons.*,
-- Camelot\MainMenuBarMicroMenu.xml; measured in docs/FOREVER-PROBE.md session 7):
-- - The dark panel is two regions on MicroMenu itself, BorderArt and
--   BackgroundArt, never set again by Blizzard: faded once, and again after
--   an Edit Mode layout change.
-- - A button's states are atlases (UI-HUD-MicroMenu-<name>-Up/-Down/-Disabled/
--   -Mouseover) with the bronze frame inside. SetTexCoord on an atlas texture
--   is relative to the atlas: CROP on every side takes the frame off and keeps
--   every symbol whole (0.20 clips). Blizzard sets them again through
--   SetNormalAtlas / SetPushedAtlas / SetDisabledAtlas / SetHighlightAtlas (at
--   load, on press and release, on enable, every second for the game menu
--   button): cropped again after each. FlashContent (an alert's pulse) holds the
--   Mouseover atlas too, set in XML only.
-- - Background / PushedBackground (ButtonBG) behind each button, and the
--   character button's Shadow / PushedShadow: Blizzard only shows and hides
--   them, so faded once.
-- - The buttons overlap by 5 (MicroMenuTemplate's child padding -5): the
--   tiles sit INSET inside each button.
-- - MicroMenu flattens its children's render layers: the pill is a frame of
--   its own under UIParent, one level under MicroMenu, shown only while
--   MicroMenu is visible and home in MicroMenuContainer (Blizzard moves it to
--   the override bar and pet battles).
-- - Feedback: Blizzard's own mouseover and down symbols stay (the highlight
--   carries the symbol while the normal texture is hidden on hover); with
--   tiles, GAB's halo and ripple are added. /gab look hover/press don't
--   suppress Blizzard's micro states.
-- - MicroMenuContainer is the Edit Mode system: never touched.

GlassActionBars = GlassActionBars or {}
local GAB = GlassActionBars
local API = GAB.API
local Glass = GAB.Glass
local Micro = {}
GAB.Micro = Micro

Micro.CROP = 0.08     -- of each state atlas, on every side (session 7)
Micro.TILE_INSET = 3  -- the tile inside each 32 x 40 button (they overlap by 5)
Micro.PILL_INSET = 4  -- the pill's reach beyond the buttons
Micro.STYLES = { "tiles", "pill" }
Micro.LABELS = { tiles = "Glass tiles", pill = "One pill" }

local STATES = { "GetNormalTexture", "GetPushedTexture", "GetDisabledTexture", "GetHighlightTexture" }
local SETTERS = { "SetNormalAtlas", "SetPushedAtlas", "SetDisabledAtlas", "SetHighlightAtlas" }
local BACKS = { "Background", "PushedBackground", "Shadow", "PushedShadow" }

local pill, pillGlass
local buttons = {}    -- the micro buttons we dressed, in order
local started = false

function Micro.IsStyle(v)
    for _, s in ipairs(Micro.STYLES) do if s == v then return true end end
    return false
end

function Micro.Style()
    local v = GAB.db and GAB.db.microStyle
    return Micro.IsStyle(v) and v or "tiles"
end

-- The micro buttons: MicroMenu's children with state textures, and the
-- character button (a portrait, no state textures).
local function microButtons()
    local out = {}
    for _, b in ipairs({ MicroMenu:GetChildren() }) do
        if b.GetNormalTexture and b:GetNormalTexture() then out[#out + 1] = b end
    end
    if CharacterMicroButton and CharacterMicroButton:GetParent() == MicroMenu then
        local seen = false
        for _, b in ipairs(out) do if b == CharacterMicroButton then seen = true end end
        if not seen then table.insert(out, 1, CharacterMicroButton) end
    end
    return out
end

local function crop(b)
    local k = Micro.CROP
    for _, getter in ipairs(STATES) do
        local tex = b[getter] and b[getter](b)
        if tex then tex:SetTexCoord(k, 1 - k, k, 1 - k) end
    end
    local flash = rawget(b, "FlashContent")
    if type(flash) == "table" and flash.SetTexCoord then flash:SetTexCoord(k, 1 - k, k, 1 - k) end
end

local function fadeBacks(b)
    for _, key in ipairs(BACKS) do
        local r = rawget(b, key)
        if type(r) == "table" and r.SetAlpha then r:SetAlpha(0) end
    end
end

local function home()
    return API.Plain(MicroMenu:IsVisible()) == true and MicroMenu:GetParent() == MicroMenuContainer
end

-- The style shown: each tile's glass (GAB's own body frame) or the pill.
local function sync()
    local tiles = Micro.Style() == "tiles"
    for _, b in ipairs(buttons) do
        local s = GAB.Buttons.State(b)
        if s then s.body:SetShown(tiles) end
    end
    if pill then
        local level = math.max(0, (API.Plain(MicroMenu:GetFrameLevel()) or 1) - 1)
        pill:SetFrameStrata(MicroMenu:GetFrameStrata())
        pill:SetFrameLevel(level)
        pillGlass.top:SetFrameLevel(level)
        pill:SetShown(not tiles and home())
    end
end
Micro.Sync = sync

function Micro.Refresh()
    if not MicroMenu or GAB.db.skin == false then return end
    for _, key in ipairs({ "BorderArt", "BackgroundArt" }) do
        if MicroMenu[key] then MicroMenu[key]:SetAlpha(0) end
    end
    for _, b in ipairs(buttons) do
        API.Try("micro:art", function() crop(b); fadeBacks(b) end)
    end
    API.Try("micro:style", sync)
end

local function build()
    pill = CreateFrame("Frame", nil, UIParent)
    pill:EnableMouse(false)
    pill:SetPoint("TOPLEFT", MicroMenu, "TOPLEFT", -Micro.PILL_INSET, Micro.PILL_INSET)
    pill:SetPoint("BOTTOMRIGHT", MicroMenu, "BOTTOMRIGHT", Micro.PILL_INSET, -Micro.PILL_INSET)
    pillGlass = Glass.Apply(pill, "small")
    pillGlass.shadow:SetAlpha(0)
    pillGlass.grain:SetAlpha(0)
    GAB.Theme.Register(pillGlass, function() return GAB.Buttons.Tune("wash"), GAB.Buttons.Tune("body") end)
    for _, b in ipairs(microButtons()) do
        API.Try("micro:" .. (API.Plain(b:GetName()) or "?"), function()
            GAB.Buttons.Build(b, {}, { inset = Micro.TILE_INSET })
            for _, setter in ipairs(SETTERS) do
                if type(b[setter]) == "function" then
                    hooksecurefunc(b, setter, function(self) API.Try("micro:crop", crop, self) end)
                end
            end
            buttons[#buttons + 1] = b
        end)
    end
    local resync = function() API.Try("micro:style", sync) end
    hooksecurefunc(MicroMenu, "SetParent", resync)
    MicroMenu:HookScript("OnShow", resync)
    MicroMenu:HookScript("OnHide", resync)
    MicroMenuContainer:HookScript("OnShow", resync)
    MicroMenuContainer:HookScript("OnHide", resync)
    local f = CreateFrame("Frame")
    f:SetScript("OnEvent", function() Micro.Refresh() end)
    API.RegisterEvents(f, { "EDIT_MODE_LAYOUTS_UPDATED" }, "micro")
    Micro.Refresh()
end

-- At login; a login in combat waits for the fight to end (the frames are
-- built out of combat, like the action buttons').
function Micro.Start()
    if started or GAB.db.skin == false or not MicroMenu or not MicroMenuContainer then return end
    if InCombatLockdown() then
        local w = CreateFrame("Frame")
        w:SetScript("OnEvent", function(self)
            self:UnregisterAllEvents()
            API.Try("micro", Micro.Start)
        end)
        API.RegisterEvents(w, { "PLAYER_REGEN_ENABLED" }, "micro")
        return
    end
    started = true
    build()
end

Micro._test = { pill = function() return pill end, glass = function() return pillGlass end,
    buttons = function() return buttons end }
