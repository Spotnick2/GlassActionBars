-- Dock.lua: smart bars docked to a stock action bar (#7). A client (the
-- Utility bar, #9; a provider's bar through the API, #8) is placed beside
-- one of Edit Mode's Action Bars 1-8, on a side, aligned, with a gap, and
-- optionally laid out to match its size, padding, rows and orientation.
--
-- The target is the union of the bar's laid-out button containers
-- (bar.shownButtonContainers, ActionBar.lua:202-217: spacers included), so
-- multi-row, vertical and reversed bars dock right. The client is anchored to
-- UIParent, never to a Blizzard frame, in its own units. Every read that
-- feeds arithmetic or a test (edges, effective scales, settings, the
-- client's size, IsVisible) goes through API.Plain first: GetLeft & co. are
-- SecretWhenAnchoringSecret, IsVisible SecretReturnsForAspect Shown.
--
-- Every pass calls the client's Layout: with the bar's geometry when
-- matching, with nil ("your own geometry") otherwise. A hosted client gives
-- up its position, never the arranging of its own contents.
--
-- A target that is missing, hidden or without a rect is unavailable: a
-- docked client keeps its last placement, one never placed stays where its
-- provider put it and is never told it is hosted. The first placement is a
-- transaction: OnHosted(true), Layout, place, then hosted; anything short of
-- that hands the frame back with OnHosted(false).
--
-- Smart bars hold secure buttons, so passes run out of combat only: a
-- request in combat waits for PLAYER_REGEN_ENABLED. Requests are coalesced
-- into one pass on the next frame. Edit Mode's sliders fire no event: while
-- it is open every client is re-placed every POLL seconds.

GlassActionBars = GlassActionBars or {}
local GAB = GlassActionBars
local API = GAB.API
local Dock = {}
GAB.Dock = Dock

Dock.POLL = 0.2
Dock.SIDES = { "LEFT", "RIGHT", "TOP", "BOTTOM" }
Dock.ALIGNS = { "START", "CENTER", "END" }
Dock.GAPS = { 0, 2, 4, 8 }
Dock.MAX_GAP = 32
Dock.DEFAULT = { bar = false, side = "RIGHT", align = "CENTER", gap = 4, match = true }
local BUTTON = 45   -- a stock action button's width at 100%

-- Edit Mode's Action Bar 1-8: the bar frame and its buttons' prefix.
Dock.BARS = {
    { "MainActionBar", "ActionButton" }, { "MultiBarBottomLeft", "MultiBarBottomLeftButton" },
    { "MultiBarBottomRight", "MultiBarBottomRightButton" }, { "MultiBarRight", "MultiBarRightButton" },
    { "MultiBarLeft", "MultiBarLeftButton" }, { "MultiBar5", "MultiBar5Button" },
    { "MultiBar6", "MultiBar6Button" }, { "MultiBar7", "MultiBar7Button" },
}

local isSide, isAlign = {}, {}
for _, s in ipairs(Dock.SIDES) do isSide[s] = true end
for _, a in ipairs(Dock.ALIGNS) do isAlign[a] = true end

-- A valid value for a dock setting.
function Dock.Valid(key, v)
    if key == "bar" then return v == false or (type(v) == "number" and Dock.BARS[v] ~= nil) end
    if key == "side" then return isSide[v] == true end
    if key == "align" then return isAlign[v] == true end
    if key == "gap" then return type(v) == "number" and v >= 0 and v <= Dock.MAX_GAP end
    if key == "match" then return type(v) == "boolean" end
    return false
end

local clients, order = {}, {}   -- id -> { def, hosted, inLayout }; ids in registration order
local dirty = {}
local driver, editMode, sincePoll = nil, false, 0

-- A setting: the player's, else the client's default, else Dock.DEFAULT.
function Dock.Setting(id, key)
    local t = GAB.db and rawget(GAB.db, "dock")
    local s = t and t[id]
    if type(s) == "table" and s[key] ~= nil then return s[key] end
    local c = clients[id]
    local d = c and c.def.default
    if type(d) == "table" and d[key] ~= nil and Dock.Valid(key, d[key]) then return d[key] end
    return Dock.DEFAULT[key]
end

local function num(v)
    v = API.Plain(v)
    if type(v) == "number" then return v end
end

-- Run a client callback: errors go to the client's error handler and to
-- /gab failures, never into the pass. True when it returned.
local function call(c, name, ...)
    local fn = c.def[name]
    if type(fn) ~= "function" then return true end
    local args, n = { ... }, select("#", ...)
    local err
    local ok = xpcall(function() return fn(unpack(args, 1, n)) end, function(e)
        err = e
        geterrorhandler()(e)
    end)
    if not ok then API.Fail("dock:" .. c.def.id, err) end
    return ok
end

-- The target's rectangle in UIParent units, or nil when unavailable.
local function targetRect(n)
    local b = Dock.BARS[n]
    local bar = b and rawget(_G, b[1])
    if not bar or API.Plain(bar:IsVisible()) ~= true then return nil end
    local ui = num(UIParent:GetEffectiveScale())
    local list = bar.shownButtonContainers
    if not ui or ui <= 0 or type(list) ~= "table" then return nil end
    local r
    for _, c in ipairs(list) do
        local s = num(c:GetEffectiveScale())
        local cl, cr, ct, cb = num(c:GetLeft()), num(c:GetRight()), num(c:GetTop()), num(c:GetBottom())
        if s and cl and cr and ct and cb then
            local k = s / ui
            cl, cr, ct, cb = cl * k, cr * k, ct * k, cb * k
            if not r then r = { left = cl, right = cr, top = ct, bottom = cb } else
                r.left, r.right = math.min(r.left, cl), math.max(r.right, cr)
                r.top, r.bottom = math.max(r.top, ct), math.min(r.bottom, cb)
            end
        end
    end
    return r
end
Dock.TargetRect = targetRect

-- The target's geometry in the client frame's units: size and padding
-- scaled, rows and orientation raw. Nil when anything is unreadable
-- (Apotheca's ActionBarLayout, measured on 70291: GetSettingValue is plain;
-- a button stays 45 wide and its effective scale carries the icon size).
local function geometry(n, frame)
    local b = Dock.BARS[n]
    local bar = rawget(_G, b[1])
    local s = Enum and Enum.EditModeActionBarSetting
    if not (bar and type(bar.GetSettingValue) == "function" and s) then return nil end
    -- A refusal (pcall false) leaves its message in `size`: not a number.
    local _, size, pad, rows, orient = pcall(function()
        return bar:GetSettingValue(s.IconSize), bar:GetSettingValue(s.IconPadding),
            bar:GetSettingValue(s.NumRows), bar:GetSettingValue(s.Orientation)
    end)
    size, pad, rows, orient = num(size), num(pad), num(rows), num(orient)
    local ui, fs = num(UIParent:GetEffectiveScale()), num(frame:GetEffectiveScale())
    if not (size and pad and rows and orient and ui and fs) or size <= 0 or ui <= 0 or fs <= 0 then return nil end
    local button = rawget(_G, b[2] .. "1")
    local base, bs = button and num(button:GetWidth()), button and num(button:GetEffectiveScale())
    local factor
    if base and bs then
        factor = bs / ui
    else
        local barScale = num(bar:GetEffectiveScale())
        if not barScale then return nil end
        base, factor = BUTTON, size / 100 * barScale / ui
    end
    local ratio = ui / fs
    return { size = base * factor * ratio, padding = pad * factor * ratio, rows = rows, orientation = orient }
end
Dock.Geometry = geometry

-- Put the client beside the rect. False when its size or scale is unreadable.
local function place(c, rect)
    local f, id = c.def.frame, c.def.id
    local ui, fs = num(UIParent:GetEffectiveScale()), num(f:GetEffectiveScale())
    local w, h = num(f:GetWidth()), num(f:GetHeight())
    if not (ui and fs and w and h) or ui <= 0 or fs <= 0 then return false end
    local k = fs / ui                       -- the frame's units -> UIParent's
    w, h = w * k, h * k
    local side, align, gap = Dock.Setting(id, "side"), Dock.Setting(id, "align"), Dock.Setting(id, "gap")
    local x, y                              -- the bottom-left corner, UIParent units
    if side == "LEFT" or side == "RIGHT" then
        x = side == "RIGHT" and rect.right + gap or rect.left - gap - w
        if align == "START" then y = rect.top - h
        elseif align == "END" then y = rect.bottom
        else y = (rect.top + rect.bottom - h) / 2 end
    else
        y = side == "TOP" and rect.top + gap or rect.bottom - gap - h
        if align == "START" then x = rect.left
        elseif align == "END" then x = rect.right - w
        else x = (rect.left + rect.right - w) / 2 end
    end
    f:ClearAllPoints()
    f:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", x / k, y / k)
    return true
end

local function release(c)
    if c.hosted then
        c.hosted = false
        call(c, "OnHosted", false)
    end
end

-- One client's pass (out of combat).
local function pass(id)
    local c = clients[id]
    if not c then return end
    if c.removed then
        release(c)
        clients[id] = nil
        return
    end
    local n = Dock.Setting(id, "bar")
    if not n then return release(c) end
    local rect = targetRect(n)
    if not rect then return end              -- unavailable: nothing moves
    local first = not c.hosted
    local ok = true
    if first then ok = call(c, "OnHosted", true) end
    -- Every pass lays the client out: the bar's geometry when matching, nil
    -- ("your own geometry") when not matching or unreadable. A hosted client
    -- gives up its position, never the arranging of its own contents.
    if ok then
        local g = Dock.Setting(id, "match") and geometry(n, c.def.frame) or nil
        c.inLayout = true
        ok = call(c, "Layout", g)
        c.inLayout = false
    end
    if ok then
        local placed, res = pcall(place, c, rect)
        if not placed then API.Fail("dock:" .. id, res) end
        ok = placed and res
    end
    if first then
        if ok then c.hosted = true else call(c, "OnHosted", false) end
    end
end

local function flush()
    if InCombatLockdown() then return false end
    local ids = {}
    for id in pairs(dirty) do ids[#ids + 1] = id end
    for k in pairs(dirty) do dirty[k] = nil end
    table.sort(ids)
    for _, id in ipairs(ids) do pass(id) end
    return true
end

local function onUpdate(_, elapsed)
    if editMode then
        sincePoll = sincePoll + elapsed
        if sincePoll >= Dock.POLL then
            sincePoll = 0
            for id in pairs(clients) do dirty[id] = true end
        end
    end
    if next(dirty) and not flush() then
        driver:SetScript("OnUpdate", nil)    -- in combat: PLAYER_REGEN_ENABLED re-arms
        return
    end
    -- A request made during the pass (a client's callback) runs next frame.
    if not editMode and not next(dirty) then driver:SetScript("OnUpdate", nil) end
end

local function arm()
    if driver and (next(dirty) or editMode) then driver:SetScript("OnUpdate", onUpdate) end
end

-- Mark a client (nil: every client) for a pass on the next frame.
function Dock.Request(id)
    if id ~= nil then
        if clients[id] then dirty[id] = true end
    else
        for k in pairs(clients) do dirty[k] = true end
    end
    arm()
end

-- A client asking to be laid out again (its buttons changed). Ignored from
-- inside its own Layout: no recursion.
function Dock.RequestLayout(id)
    local c = clients[id]
    if c and not c.inLayout then Dock.Request(id) end
end

-- def = { id, label, frame, Layout(geom), OnHosted(isHosted), default }.
-- False for a bad definition or a duplicate id.
function Dock.Register(def)
    if type(def) ~= "table" or type(def.id) ~= "string" or not def.id:match("^[%w_]+$") or clients[def.id]
        or type(def.frame) ~= "table" then
        return false
    end
    clients[def.id] = { def = def }
    order[#order + 1] = def.id
    Dock.Request(def.id)
    return true
end

-- The client is let go (OnHosted(false)) at the next pass out of combat.
function Dock.Unregister(id)
    local c = clients[id]
    if not c then return false end
    c.removed = true
    for i, v in ipairs(order) do if v == id then table.remove(order, i) break end end
    Dock.Request(id)
    return true
end

-- Registered clients, in registration order: { id, label }.
function Dock.Clients()
    local out = {}
    for _, id in ipairs(order) do
        local c = clients[id]
        if c and not c.removed then out[#out + 1] = { id = id, label = c.def.label or id } end
    end
    return out
end

function Dock.IsHosted(id) return clients[id] ~= nil and clients[id].hosted == true end

local started = false
function Dock.Start()
    if started then return end
    started = true
    driver = CreateFrame("Frame")
    local function all() Dock.Request() end
    for _, b in ipairs(Dock.BARS) do
        local bar = rawget(_G, b[1])
        if bar then
            for _, m in ipairs({ "UpdateGridLayout", "UpdateShownButtons" }) do
                if type(bar[m]) == "function" then hooksecurefunc(bar, m, all) end
            end
            bar:HookScript("OnShow", all)
        end
    end
    local manager = rawget(_G, "EditModeManagerFrame")
    if manager then
        for _, m in ipairs({ "UpdateBottomActionBarPositions", "UpdateRightActionBarPositions" }) do
            if type(manager[m]) == "function" then hooksecurefunc(manager, m, all) end
        end
    end
    driver:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_REGEN_ENABLED" then arm() else all() end
    end)
    API.RegisterEvents(driver, { "PLAYER_ENTERING_WORLD", "EDIT_MODE_LAYOUTS_UPDATED", "UI_SCALE_CHANGED",
        "DISPLAY_SIZE_CHANGED", "PLAYER_REGEN_ENABLED" }, "dock")
    if EventRegistry and EventRegistry.RegisterCallback then
        EventRegistry:RegisterCallback("EditMode.Enter", function() editMode = true; sincePoll = 0; arm() end, Dock)
        EventRegistry:RegisterCallback("EditMode.Exit", function() editMode = false; all() end, Dock)
    end
    arm()
end

Dock._test = { clients = clients, dirty = dirty, driver = function() return driver end }
