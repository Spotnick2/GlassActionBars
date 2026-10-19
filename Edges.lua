-- Edges.lua: the bars at the screen's sides, for the suite (#37; Glass UI's
-- docs/GROUP-LAYOUT.md section 5c). GlassRaidFrames puts its grid at the
-- screen's left side; vertical action bars there would sit under it. GAB
-- announces where the bars at each side end, GRF keeps clear: no dependency
-- either way.
--
--   GlassActionBars.EdgeState() -> { left, right, width } (UIParent units from
--     the bottom-left): left = the right edge of the bars at the screen's left
--     (0 when none), right = the left edge of those at its right (width when
--     none). Nil before the first measure.
--   EventRegistry "GlassActionBars.EdgesChanged" (left, right, width): out of
--     combat, when a value moved more than half a unit from the last one
--     announced. Consumers apply the latest values each time.
--
-- Which bars count: Action Bars 1-8 (their laid-out buttons, as the dock
-- reads them) and every dock client (the Utility bar, provider bars; docked
-- or free), when visible and taller than wide (a horizontal bar near a
-- corner doesn't push the grid). On each side, walking out from the screen's
-- edge: a bar counts when it starts within MARGIN of the edge or of the bars
-- already counted (a stack: the owner's MultiBar5 at 2-42 and MultiBar6 at
-- 46-87 both count). The inner edge only grows; the first gap wider than
-- MARGIN ends the walk. A rect with any unreadable value is skipped, never
-- guessed.

GlassActionBars = GlassActionBars or {}
local GAB = GlassActionBars
local API = GAB.API
local Edges = {}
GAB.Edges = Edges

Edges.EVENT = "GlassActionBars.EdgesChanged"
Edges.MARGIN = 40
Edges.TOLERANCE = 0.5

local published            -- the last values announced: { left, right, width }
local wanted, pending = false, false

local function num(v)
    v = API.Plain(v)
    if type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge then return v end
end

-- A frame's rectangle in UIParent units, or nil (hidden, or anything unreadable).
local function rectOf(frame)
    if API.Plain(frame:IsVisible()) ~= true then return nil end
    local s, ui = num(frame:GetEffectiveScale()), num(UIParent:GetEffectiveScale())
    local l, r, t, b = num(frame:GetLeft()), num(frame:GetRight()), num(frame:GetTop()), num(frame:GetBottom())
    if not (s and ui and l and r and t and b) or s <= 0 or ui <= 0 then return nil end
    local k = s / ui
    return { left = l * k, right = r * k, top = t * k, bottom = b * k }
end
Edges.RectOf = rectOf

-- The vertical bars on screen.
local function candidates()
    local out = {}
    local function add(r)
        if r and (r.top - r.bottom) > (r.right - r.left) then out[#out + 1] = r end
    end
    for n = 1, #GAB.Dock.BARS do add(GAB.Dock.TargetRect(n, true)) end
    for _, f in ipairs(GAB.Dock.Frames()) do add(rectOf(f)) end
    return out
end

-- The inner edges, from the screen's edges outwards.
function Edges.Measure()
    local width = num(UIParent:GetWidth())
    if not width or width <= 0 then return nil end
    local list = candidates()
    local left = 0
    table.sort(list, function(a, b) return a.left < b.left end)
    for _, r in ipairs(list) do
        if r.left > left + Edges.MARGIN then break end
        left = math.max(left, r.right)
    end
    local right = width
    table.sort(list, function(a, b) return a.right > b.right end)
    for _, r in ipairs(list) do
        if r.right < right - Edges.MARGIN then break end
        right = math.min(right, r.left)
    end
    return { left = left, right = right, width = width }
end

local function moved(a, b)
    return math.abs(a.left - b.left) > Edges.TOLERANCE or math.abs(a.right - b.right) > Edges.TOLERANCE
        or math.abs(a.width - b.width) > Edges.TOLERANCE
end

-- Measure and, on a change, announce. Out of combat only.
local function update()
    if InCombatLockdown() then
        pending = true
        return
    end
    pending = false
    local now = Edges.Measure()
    if not now or (published and not moved(now, published)) then return end
    published = now
    if EventRegistry and EventRegistry.TriggerEvent then
        EventRegistry:TriggerEvent(Edges.EVENT, now.left, now.right, now.width)
    end
end

-- The last values announced, as a fresh table (nil before the first).
function Edges.State()
    if not published then return nil end
    return { left = published.left, right = published.right, width = published.width }
end

local driver = CreateFrame("Frame")
local function onUpdate()
    driver:SetScript("OnUpdate", nil)
    if wanted then
        wanted = false
        API.Try("edges:update", update)
    end
end

-- A measure on the next frame (coalesced).
function Edges.Request()
    wanted = true
    driver:SetScript("OnUpdate", onUpdate)
end

-- A frame whose showing and hiding move the edges.
local watched = setmetatable({}, { __mode = "k" })
function Edges.Watch(frame)
    if type(frame) ~= "table" or watched[frame] or type(frame.HookScript) ~= "function" then return end
    watched[frame] = true
    frame:HookScript("OnShow", Edges.Request)
    frame:HookScript("OnHide", Edges.Request)
end

local started = false
function Edges.Start()
    if started then return end
    started = true
    for _, b in ipairs(GAB.Dock.BARS) do
        local bar = rawget(_G, b[1])
        if bar then Edges.Watch(bar) end
    end
    for _, f in ipairs(GAB.Dock.Frames()) do Edges.Watch(f) end
    driver:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_REGEN_ENABLED" then
            if pending then Edges.Request() end
        else
            Edges.Request()
        end
    end)
    API.RegisterEvents(driver, { "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED", "EDIT_MODE_LAYOUTS_UPDATED",
        "UI_SCALE_CHANGED", "DISPLAY_SIZE_CHANGED" }, "edges")
    if EventRegistry and EventRegistry.RegisterCallback then
        EventRegistry:RegisterCallback("EditMode.Exit", Edges.Request, Edges)
    end
    Edges.Request()
end

Edges._test = { published = function() return published end }
