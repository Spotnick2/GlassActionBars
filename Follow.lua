-- Follow.lua: the stance and pet bars follow Glass Unit Frames (#30;
-- GlassUI#28 section 5b). GlassUnitFrames (GUF) slides the player and pet
-- frames sideways beside the raid grid and announces it; Blizzard's StanceBar
-- and PetActionBar sit under those frames. GAB moves StanceBar by the
-- player's move (dx) and PetActionBar by the pet's (petDx), horizontally,
-- from each bar's Edit Mode position. No dependency either way: GUF fires an
-- EventRegistry event, GAB listens; without GUF nothing moves.
--
-- How (the porting guide's recipe for an Edit Mode system, measured by
-- GABProbe's `barmove` procedure before this shipped):
--   - Edit Mode's own SetPoint/ClearAllPoints are overrides that do its
--     bookkeeping; the saved originals, SetPointBase/ClearAllPointsBase, move
--     the frame and nothing else. Out of combat, Edit Mode closed.
--   - The Edit Mode layout is never written: the bar's anchor as Blizzard
--     set it is the base, kept in a side table; the bar is put at base + dx.
--   - Blizzard re-anchors the bars (UpdateBottomActionBarPositions,
--     ApplySystemAnchor, a layout applied, Edit Mode closing). After each, a
--     deferred pass compares the bar's anchor with the one read back after
--     our last write (the ownership marker): different means Blizzard placed
--     it, and that anchor becomes the base.
--   - Entering Edit Mode puts an owned bar back to its base, so Edit Mode
--     shows and saves true positions; a bar Blizzard already re-anchored is
--     left as it is.
--   - A bar anchored to the other followed bar (snapped to it in Edit Mode)
--     already moves with it: it is not moved again.
--   - Only a bar with exactly one plain anchor and plain scales is touched.

GlassActionBars = GlassActionBars or {}
local GAB = GlassActionBars
local API = GAB.API
local Follow = {}
GAB.Follow = Follow

Follow.EVENT = "GlassUnitFrames.LayoutChanged"
Follow.BARS = { "StanceBar", "PetActionBar" }   -- moved by dx, by petDx
local TOLERANCE = 0.01

local want = { StanceBar = 0, PetActionBar = 0 }     -- GUF's moves, UIParent units
local base, marker, status = {}, {}, {}               -- by bar name
local editMode, pending, deferred = false, false, false

function Follow.Enabled() return GAB.db == nil or GAB.db.follow ~= false end

-- The bar's one anchor as plain values, or nil.
local function anchor(bar)
    if API.Plain(bar:GetNumPoints()) ~= 1 then return nil end
    local p, rel, rp, x, y = bar:GetPoint(1)
    p, rel, rp, x, y = API.Plain(p), API.Plain(rel), API.Plain(rp), API.Plain(x), API.Plain(y)
    if type(p) ~= "string" or type(rp) ~= "string" or type(x) ~= "number" or type(y) ~= "number" then return nil end
    return { p, rel, rp, x, y }
end

local function same(a, b)
    return a ~= nil and b ~= nil and a[1] == b[1] and a[2] == b[2] and a[3] == b[3]
        and math.abs(a[4] - b[4]) < TOLERANCE and math.abs(a[5] - b[5]) < TOLERANCE
end

-- UIParent units -> the bar's own offset units.
local function ratio(bar)
    local ui, s = API.Plain(UIParent:GetEffectiveScale()), API.Plain(bar:GetEffectiveScale())
    if type(ui) == "number" and type(s) == "number" and ui > 0 and s > 0 then return ui / s end
end

local function write(bar, a)
    bar:ClearAllPointsBase()
    bar:SetPointBase(a[1], a[2], a[3], a[4], a[5])
end

local function canMove(bar)
    return type(bar.SetPointBase) == "function" and type(bar.ClearAllPointsBase) == "function"
end

-- One bar to base + dx (dx 0: base). Out of combat, Edit Mode closed.
local function apply(name, dx)
    local bar = rawget(_G, name)
    if not bar or not canMove(bar) then status[name] = "absent" return end
    local cur = anchor(bar)
    if not cur then status[name] = "unreadable anchor" return end
    if not same(cur, marker[name]) then base[name] = cur end   -- Blizzard placed it: the new base
    local b = base[name]
    for _, other in ipairs(Follow.BARS) do
        if other ~= name and b[2] == rawget(_G, other) then
            if marker[name] then write(bar, b) end
            marker[name] = nil
            status[name] = "anchored to " .. other .. ": moves with it"
            return
        end
    end
    if dx == 0 then
        if marker[name] then write(bar, b) end
        marker[name] = nil
        status[name] = "at its Edit Mode position"
        return
    end
    local r = ratio(bar)
    if not r then status[name] = "unreadable scale" return end
    write(bar, { b[1], b[2], b[3], b[4] + dx * r, b[5] })
    marker[name] = anchor(bar)
    status[name] = ("following (%+g)"):format(dx)
end

-- Every bar to where it should be; in combat or Edit Mode, later.
function Follow.Reconcile()
    if InCombatLockdown() or editMode then
        pending = true
        return
    end
    pending = false
    local on = Follow.Enabled()
    API.Try("follow:StanceBar", apply, "StanceBar", on and want.StanceBar or 0)
    API.Try("follow:PetActionBar", apply, "PetActionBar", on and want.PetActionBar or 0)
end

-- After a Blizzard anchor pass: next frame, never inside its secure pass.
local function defer()
    if deferred then return end
    deferred = true
    C_Timer.After(0, function()
        deferred = false
        Follow.Reconcile()
    end)
end

local function number(v)
    v = API.Plain(v)
    if type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge then return v end
    return 0
end

-- GUF's moves (UIParent units); unlinked = 0. The probe calls this too.
function Follow.SetOffsets(dx, petDx)
    want.StanceBar, want.PetActionBar = number(dx), number(petDx)
    Follow.Reconcile()
end

local function onLayout(_, linked, _, _, _, _, _, _, _, _, dx, petDx)
    if API.Plain(linked) == true then Follow.SetOffsets(dx, petDx) else Follow.SetOffsets(0, 0) end
end

-- GUF's state at world entry: it may have announced before we listened.
local function readGUF()
    local guf = rawget(_G, "GlassUF")
    if not (guf and type(guf.LayoutState) == "function") then return end
    local ok, s = pcall(guf.LayoutState)
    if ok and type(s) == "table" then
        onLayout(nil, s.linked, nil, nil, nil, nil, nil, nil, nil, nil, s.dx, s.petDx)
    end
end

local function enterEditMode()
    editMode = true
    pending = false
    if InCombatLockdown() then return end
    for _, name in ipairs(Follow.BARS) do
        local bar = rawget(_G, name)
        if bar and marker[name] and canMove(bar) then
            if same(anchor(bar), marker[name]) then API.Try("follow:back", write, bar, base[name]) end
            marker[name] = nil
        end
    end
end

-- What each bar is doing, for /gab follow.
function Follow.Status()
    local out = {}
    for _, name in ipairs(Follow.BARS) do out[name] = status[name] or "not moved yet" end
    return out
end

local started = false
function Follow.Start()
    if started then return end
    started = true
    for _, name in ipairs(Follow.BARS) do
        local bar = rawget(_G, name)
        if bar and type(bar.ApplySystemAnchor) == "function" then hooksecurefunc(bar, "ApplySystemAnchor", defer) end
    end
    local manager = rawget(_G, "EditModeManagerFrame")
    if manager and type(manager.UpdateBottomActionBarPositions) == "function" then
        hooksecurefunc(manager, "UpdateBottomActionBarPositions", defer)
    end
    local driver = CreateFrame("Frame")
    driver:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_ENTERING_WORLD" then readGUF()
        elseif event == "PLAYER_REGEN_ENABLED" then
            if pending then Follow.Reconcile() end
        else
            Follow.Reconcile()     -- a scale change: the same base, a new ratio
        end
    end)
    API.RegisterEvents(driver, { "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED", "UI_SCALE_CHANGED",
        "DISPLAY_SIZE_CHANGED" }, "follow")
    if EventRegistry and EventRegistry.RegisterCallback then
        EventRegistry:RegisterCallback(Follow.EVENT, onLayout, Follow)
        EventRegistry:RegisterCallback("EditMode.Enter", enterEditMode, Follow)
        EventRegistry:RegisterCallback("EditMode.Exit", function()
            editMode = false
            defer()
        end, Follow)
    end
end

Follow._test = { base = base, marker = marker, want = want }
