-- Bars.lua: the main bar's own art, faded under glass (docs/PLAN.md, Phase 1).
--
-- MainActionBar.BorderArt (the frame behind the main bar), the dividers
-- between its buttons, and the end caps' gryphons (kept on request). All
-- with SetAlpha(0) on regions and pooled frames, never Hide(), never a
-- reparent: MainActionBar and the end caps are Edit Mode systems.
--
-- The dividers come from frame pools that MainActionBar:UpdateDividers
-- releases and acquires again on every layout change, so it is post-hooked.
-- The end caps are Edit Mode systems of their own on Forever (Camelot's
-- MainMenuBarEndCaps); only their textures are faded, so their Edit Mode
-- selection still works.

GlassActionBars = GlassActionBars or {}
local GAB = GlassActionBars
local API = GAB.API
local Bars = {}
GAB.Bars = Bars

local function fadeDividers()
    local bar = MainActionBar
    for _, key in ipairs({ "HorizontalDividersPool", "VerticalDividersPool" }) do
        local pool = bar[key]
        if pool and pool.EnumerateActive then
            for divider in pool:EnumerateActive() do divider:SetAlpha(0) end
        end
    end
end

local function paintEndCaps()
    local caps = MainActionBar.EndCaps
    if not caps then return end
    local a = GAB.db.endCaps and 1 or 0
    for _, key in ipairs({ "LeftEndCap", "RightEndCap" }) do
        local cap = caps[key]
        if cap and cap.Texture then cap.Texture:SetAlpha(a) end
    end
end

-- Everything again: at start, after an Edit Mode layout change, and when the
-- end-caps setting changes.
function Bars.Refresh()
    if not MainActionBar or GAB.db.skin == false then return end
    if MainActionBar.BorderArt then MainActionBar.BorderArt:SetAlpha(0) end
    API.Try("bars:dividers", fadeDividers)
    API.Try("bars:endcaps", paintEndCaps)
end

local started = false
function Bars.Start()
    if started or GAB.db.skin == false or not MainActionBar then return end
    started = true
    if type(MainActionBar.UpdateDividers) == "function" then
        hooksecurefunc(MainActionBar, "UpdateDividers", function() API.Try("bars:dividers", fadeDividers) end)
    end
    local f = CreateFrame("Frame")
    f:SetScript("OnEvent", function() Bars.Refresh() end)
    API.RegisterEvents(f, { "EDIT_MODE_LAYOUTS_UPDATED" }, "bars")
    Bars.Refresh()
end
