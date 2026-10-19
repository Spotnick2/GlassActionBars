-- MicroMenu.lua: the micro menu without Blizzard's dark panel (#14). The micro
-- buttons themselves are left as Blizzard draws them: their bronze frame is
-- drawn into each button's icon atlas ("UI-HUD-MicroMenu-<name>-Up", set
-- again on hover, on every panel open or close, and every second for the game
-- menu button), so a glass rim of ours would be a second frame round a framed
-- icon. The glass panel that stood in for the dark one was taken out at the
-- owner's choice (#50, 2026-10-19): the framed icons sit on the world.
--
-- Forever's micro menu (Blizzard_MicroMenu, Camelot\MainMenuBarMicroMenu.xml):
-- - The dark panel is two regions on MicroMenu itself, BorderArt ("UI-HUD-
--   ActionBar-Frame") and BackgroundArt ("UI-HUD-ActionBar-IconFrame-
--   Background"), never set again by Blizzard: faded once, and again after an
--   Edit Mode layout change.
-- - MicroMenuContainer is the Edit Mode system: never touched.

GlassActionBars = GlassActionBars or {}
local GAB = GlassActionBars
local API = GAB.API
local Micro = {}
GAB.Micro = Micro

function Micro.Refresh()
    if not MicroMenu or GAB.db.skin == false then return end
    for _, key in ipairs({ "BorderArt", "BackgroundArt" }) do
        if MicroMenu[key] then MicroMenu[key]:SetAlpha(0) end
    end
end

local started = false
function Micro.Start()
    if started or GAB.db.skin == false or not MicroMenu then return end
    started = true
    local f = CreateFrame("Frame")
    f:SetScript("OnEvent", function() Micro.Refresh() end)
    API.RegisterEvents(f, { "EDIT_MODE_LAYOUTS_UPDATED" }, "micro")
    Micro.Refresh()
end
