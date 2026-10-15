-- Fade.lua: bar fade (#10). A bar set to fade sits at the faded alpha until
-- something needs it: the pointer, its flyout, a drag, Edit Mode, the
-- spellbook, Quick Keybind mode, or (in "combat" mode) a fight.
--
-- Bartender4's fadeout (Bar.lua: ControlFadeOut, MouseIsOverBar), on
-- Blizzard's own bars. The one write is SetAlpha on the bar frame itself:
-- not protected, measured working in combat lockdown (docs/FOREVER-PROBE.md
-- Q5), and no Blizzard code writes these bars' alpha (Edit Mode's own
-- visibility setting uses Show/Hide). No Show/Hide, state driver, attribute,
-- parent or geometry change, so nothing waits for combat to end. A bar
-- set back to "off" gets SetAlpha(1) once and is never touched again.
--
-- Reasons a fading bar is shown, read every POLL seconds:
-- - the pointer over the bar; for the main bar also over its page arrows
--   (ActionBarPageNumber sits outside the bar's rectangle). IsMouseOver is
--   SecretWhenAnchoringSecret: a secret answer counts as over (bar shown);
-- - SpellFlyout open from one of the bar's buttons (it is reparented to
--   the button: Flyout.lua, AttachToButton);
-- - something on the cursor to drop: ACTIONBAR_SHOWGRID..HIDEGRID, and the
--   pet bar's own PET_BAR_SHOWGRID..HIDEGRID, kept apart so one family's
--   hide never clears the other's;
-- - Edit Mode (EventRegistry EditMode.Enter..Exit), Quick Keybind mode, the
--   spellbook or professions book: each shows the grids directly, with no
--   grid event (ActionButtonUtil.ShowAllActionButtonGrids,
--   Blizzard_PlayerSpellsFrame.lua:53, Blizzard_ProfessionsBook.lua:36);
-- - "combat" mode and in combat.
--
-- Timing: a reveal snaps to 1 when a poll finds a reason; fade-out begins
-- DELAY seconds after the poll that found none, and runs linearly over OUT
-- seconds, a step every rendered frame.

GlassActionBars = GlassActionBars or {}
local GAB = GlassActionBars
local API = GAB.API
local Fade = {}
GAB.Fade = Fade

Fade.POLL, Fade.DELAY, Fade.OUT = 0.1, 0.25, 0.2

Fade.MODES = { "off", "mouseover", "combat" }
Fade.LABELS = { off = "No fade", mouseover = "Fade unless hovered", combat = "Fade out of combat" }
local isMode = { off = true, mouseover = true, combat = true }
function Fade.IsMode(m) return isMode[m] == true end

-- Edit Mode's Action Bar 1-8, then stance and pet: frame name (saved), the
-- /gab key, the label, the button prefix and count.
Fade.BARS = {
    { "MainActionBar", "1", "Action Bar 1", "ActionButton", 12 },
    { "MultiBarBottomLeft", "2", "Action Bar 2", "MultiBarBottomLeftButton", 12 },
    { "MultiBarBottomRight", "3", "Action Bar 3", "MultiBarBottomRightButton", 12 },
    { "MultiBarRight", "4", "Action Bar 4", "MultiBarRightButton", 12 },
    { "MultiBarLeft", "5", "Action Bar 5", "MultiBarLeftButton", 12 },
    { "MultiBar5", "6", "Action Bar 6", "MultiBar5Button", 12 },
    { "MultiBar6", "7", "Action Bar 7", "MultiBar6Button", 12 },
    { "MultiBar7", "8", "Action Bar 8", "MultiBar7Button", 12 },
    { "StanceBar", "stance", "Stance bar", "StanceButton", 10 },
    { "PetActionBar", "pet", "Pet bar", "PetActionButton", 10 },
}
Fade.byName, Fade.byKey = {}, {}
for _, b in ipairs(Fade.BARS) do Fade.byName[b[1]], Fade.byKey[b[2]] = b, b end

local owner = {}     -- button -> its bar frame (flyouts), built at Start
local state = {}     -- bar frame -> { mode, alpha (last written), since (no reason since) }
local grid = { action = false, pet = false }
local editMode = false
local driver
local sincePoll = 0

-- The saved mode for a bar frame name.
function Fade.Mode(name)
    local t = GAB.db and rawget(GAB.db, "fade")
    return (t and t[name]) or "off"
end

-- IsShown / IsVisible may be secret (SecretReturnsForAspect Shown): an
-- unreadable answer counts as shown, so the bar stays opaque rather than
-- vanishing under a pointer the fade can't see.
local function shown(f, method)
    local v = f[method](f)
    if API.IsSecret(v) then return true end
    return v == true
end

local function over(f)
    if not f or not shown(f, "IsVisible") then return false end
    local v = f:IsMouseOver()
    if API.IsSecret(v) then return true end
    return v == true
end

-- Reasons that show every fading bar.
local function everyBar()
    if grid.action or grid.pet or editMode then return true end
    local quick = rawget(_G, "KeybindFrames_InQuickKeybindMode")
    if quick then
        local q = quick()
        if API.IsSecret(q) or q then return true end
    end
    for _, name in ipairs({ "PlayerSpellsFrame", "ProfessionsBookFrame" }) do
        local f = rawget(_G, name)   -- load on demand: nil until opened once
        if f and shown(f, "IsShown") then return true end
    end
    return false
end

local function wanted(bar, s, all)
    if all then return true end
    if s.mode == "combat" and API.InCombat() then return true end
    if over(bar) then return true end
    if bar == rawget(_G, "MainActionBar") and over(bar.ActionBarPageNumber) then return true end
    local fly = rawget(_G, "SpellFlyout")
    return fly ~= nil and shown(fly, "IsShown") and owner[fly:GetParent()] == bar
end

local function write(bar, s, a)
    if s.alpha ~= a then
        s.alpha = a
        bar:SetAlpha(a)
    end
end

local function step(_, elapsed)
    local now = GetTime()
    sincePoll = sincePoll + elapsed
    local poll = sincePoll >= Fade.POLL
    if poll then sincePoll = 0 end
    local all = poll and everyBar()
    local low = GAB.db.fadeAlpha
    for bar, s in pairs(state) do
        if poll then
            if wanted(bar, s, all) then
                s.since = nil
                write(bar, s, 1)
            elseif not s.since then
                s.since = now
            end
        end
        if s.since and now - s.since >= Fade.DELAY then
            local t = math.min(1, (now - s.since - Fade.DELAY) / Fade.OUT)
            write(bar, s, 1 + (low - 1) * t)
        end
    end
end

-- Match the bars to the saved modes: start fading the new ones, give the
-- dropped ones full alpha once. The driver runs only while a bar fades.
function Fade.Apply()
    if not driver then return end
    for _, b in ipairs(Fade.BARS) do
        local bar = rawget(_G, b[1])
        local mode = Fade.Mode(b[1])
        if bar and mode ~= "off" then
            state[bar] = state[bar] or {}
            state[bar].mode = mode
        elseif bar and state[bar] then
            state[bar] = nil
            bar:SetAlpha(1)
        end
    end
    sincePoll = Fade.POLL   -- the next frame polls
    driver:SetScript("OnUpdate", next(state) and step or nil)
end

local started = false
function Fade.Start()
    if started then return end
    started = true
    for _, b in ipairs(Fade.BARS) do
        local bar = rawget(_G, b[1])
        for i = 1, b[5] do
            local button = rawget(_G, b[4] .. i)
            if bar and button then owner[button] = bar end
        end
    end
    driver = CreateFrame("Frame")
    driver:SetScript("OnEvent", function(_, event)
        if event == "ACTIONBAR_SHOWGRID" then grid.action = true
        elseif event == "ACTIONBAR_HIDEGRID" then grid.action = false
        elseif event == "PET_BAR_SHOWGRID" then grid.pet = true
        elseif event == "PET_BAR_HIDEGRID" then grid.pet = false
        else API.NoteCombat(event) end
    end)
    API.RegisterEvents(driver, { "ACTIONBAR_SHOWGRID", "ACTIONBAR_HIDEGRID", "PET_BAR_SHOWGRID", "PET_BAR_HIDEGRID",
        "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" }, "fade")
    if EventRegistry and EventRegistry.RegisterCallback then
        EventRegistry:RegisterCallback("EditMode.Enter", function() editMode = true end, Fade)
        EventRegistry:RegisterCallback("EditMode.Exit", function() editMode = false end, Fade)
    end
    Fade.Apply()
end

Fade._test = { state = state, owner = owner, grid = grid, driver = function() return driver end }
