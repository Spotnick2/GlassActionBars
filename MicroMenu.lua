-- MicroMenu.lua: a glass panel behind the micro menu (#14), in place of
-- Blizzard's dark one. The micro buttons themselves are left as Blizzard
-- draws them: their bronze frame is drawn into each button's icon atlas
-- ("UI-HUD-MicroMenu-<name>-Up", set again on hover, on every panel open or
-- close, and every second for the game menu button), so a glass rim of ours
-- would be a second frame round a framed icon. Owner's choice (2026-10-14):
-- a subtle panel, the icons and every button state as they are; cropped
-- icons on glass may come later, once the action bars are settled.
--
-- Forever's micro menu (Blizzard_MicroMenu, Camelot\MainMenuBarMicroMenu.xml):
-- - The dark panel is two regions on MicroMenu itself, BorderArt ("UI-HUD-
--   ActionBar-Frame") and BackgroundArt ("UI-HUD-ActionBar-IconFrame-
--   Background"), never set again by Blizzard: faded once.
-- - MicroMenu flattens its render layers (flattenRenderLayers), so a frame of
--   ours inside it would be sorted into the buttons' layers. The panel is a
--   frame of its own instead, one level under MicroMenu, anchored to it, its
--   rims kept at its own level so they never draw over the buttons.
-- - Blizzard moves MicroMenu to the override bar and the pet battle UI
--   (OverrideMicroMenuPosition) and back (ResetMicroMenuPosition): the panel
--   shows only while MicroMenu is shown and home in MicroMenuContainer.
-- - MicroMenuContainer is the Edit Mode system: never touched.

GlassActionBars = GlassActionBars or {}
local GAB = GlassActionBars
local API = GAB.API
local Glass = GAB.Glass
local Micro = {}
GAB.Micro = Micro

Micro.INSET = 4      -- the panel's reach beyond the buttons, px

local panel, g

local function home()
    return MicroMenu:IsShown() and MicroMenu:GetParent() == MicroMenuContainer
end

-- The panel's look: the buttons' body (their /gab tune wash and body) and
-- LibGlass's own thin rim, as built: quieter than the buttons' ButtonRim.
local function sync()
    if not panel then return end
    local level = math.max(0, (API.Plain(MicroMenu:GetFrameLevel()) or 1) - 1)
    panel:SetFrameStrata(MicroMenu:GetFrameStrata())
    panel:SetFrameLevel(level)
    g.top:SetFrameLevel(level)
    panel:SetShown(home())
end

function Micro.Refresh()
    if not MicroMenu or GAB.db.skin == false then return end
    for _, key in ipairs({ "BorderArt", "BackgroundArt" }) do
        if MicroMenu[key] then MicroMenu[key]:SetAlpha(0) end
    end
    API.Try("micro:panel", sync)
end

local started = false
function Micro.Start()
    if started or GAB.db.skin == false or not MicroMenu or not MicroMenuContainer then return end
    started = true
    panel = CreateFrame("Frame", nil, UIParent)
    panel:EnableMouse(false)
    panel:SetPoint("TOPLEFT", MicroMenu, "TOPLEFT", -Micro.INSET, Micro.INSET)
    panel:SetPoint("BOTTOMRIGHT", MicroMenu, "BOTTOMRIGHT", Micro.INSET, -Micro.INSET)
    g = Glass.Apply(panel, "small")
    g.shadow:SetAlpha(0)
    g.grain:SetAlpha(0)
    GAB.Theme.Register(g, function() return GAB.Buttons.Tune("wash"), GAB.Buttons.Tune("body") end)
    hooksecurefunc(MicroMenu, "SetParent", function() API.Try("micro:panel", sync) end)
    MicroMenu:HookScript("OnShow", function() API.Try("micro:panel", sync) end)
    MicroMenu:HookScript("OnHide", function() API.Try("micro:panel", sync) end)
    local f = CreateFrame("Frame")
    f:SetScript("OnEvent", function() Micro.Refresh() end)
    API.RegisterEvents(f, { "EDIT_MODE_LAYOUTS_UPDATED" }, "micro")
    Micro.Refresh()
end

Micro._test = { panel = function() return panel end, glass = function() return g end }
