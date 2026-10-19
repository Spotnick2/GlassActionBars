-- API.lua: the public provider API (#8). The contract is docs/PUBLIC-API.md.
--
-- Other addons (Apotheca, 123, Portal Roulette) dock their bars beside an
-- action bar (RegisterBar, through the dock: Dock.lua), put their buttons in
-- glass (SkinButton), and offer a button for the Utility bar
-- (RegisterButton; hosted by the Utility bar, #9).
--
-- What keeps it stable (AltStable's PublicAPI.lua rules):
-- - PUBLIC_API_VERSION changes on any incompatible change; a provider checks
--   it with ==. (GlassActionBars.API is the client adapter, Compat.lua: hence
--   the longer name.)
-- - Inputs are snapshotted: a definition or region map is copied, field by
--   allowed field, when accepted; the provider's own table changing later
--   changes nothing. Nothing hands out a live internal table.
-- - Every object is checked against its role before anything is built, and
--   a refusal says why. A provider's callback runs under xpcall (Dock.lua):
--   its error stays its own.

GlassActionBars = GlassActionBars or {}
local GAB = GlassActionBars
local API = GAB.API

GAB.PUBLIC_API_VERSION = 1

local RESERVED = { utility = true }   -- the native Utility bar's dock id

-- The object's widget type, or nil when it isn't a widget.
local function kind(obj)
    if type(obj) ~= "table" or type(obj.GetObjectType) ~= "function" then return nil end
    local ok, t = pcall(obj.GetObjectType, obj)
    t = ok and API.Plain(t)
    return type(t) == "string" and t or nil
end

-- True when obj is a widget of type t or derived from it (Button from Frame).
local function isA(obj, t)
    if not kind(obj) or type(obj.IsObjectType) ~= "function" then return false end
    local ok, yes = pcall(obj.IsObjectType, obj, t)
    return ok and API.Plain(yes) == true
end

local function validId(id)
    return type(id) == "string" and id:match("^[%w_]+$") ~= nil
end

-- A smart bar docked beside an action bar. def = { id, label?, frame,
-- OnHosted(isHosted), Layout(geom)?, default? }. True, or false and why.
function GAB.RegisterBar(def)
    if type(def) ~= "table" then return false, "the definition must be a table" end
    if not validId(def.id) then return false, "id must be letters, digits and _" end
    if RESERVED[def.id] then return false, "id '" .. def.id .. "' is reserved" end
    if def.label ~= nil and type(def.label) ~= "string" then return false, "label must be a string" end
    if not isA(def.frame, "Frame") then return false, "frame must be a frame" end
    if type(def.OnHosted) ~= "function" then return false, "OnHosted must be a function" end
    if def.Layout ~= nil and type(def.Layout) ~= "function" then return false, "Layout must be a function" end
    local default
    if type(def.default) == "table" then
        default = {}
        for _, k in ipairs({ "bar", "side", "align", "gap", "match" }) do
            if GAB.Dock.Valid(k, def.default[k]) then default[k] = def.default[k] end
        end
    end
    local ok = GAB.Dock.Register({ id = def.id, label = def.label or def.id, frame = def.frame,
        OnHosted = def.OnHosted, Layout = def.Layout, default = default })
    if not ok then return false, "id '" .. def.id .. "' is already registered" end
    return true
end

-- A registered bar's contents changed: re-place it (coalesced; ignored from
-- inside its own Layout).
function GAB.RequestLayout(id)
    if validId(id) then GAB.Dock.RequestLayout(id) end
end

-- The glass on a provider's button. regions: icon, normal, pushed,
-- highlight (Textures), hotkey, count, name (FontStrings), cooldown (a
-- Cooldown); others are dropped. `owner`, optional: the calling addon's
-- name, reported to Glass UI as a tenant wearing GAB's look (#39). It waits,
-- region copy and owner kept, for GAB's glass to be built (PLAYER_LOGIN) and
-- for a fight to end; the skin setting is read again when it runs.
local ROLES = { icon = "Texture", normal = "Texture", pushed = "Texture", highlight = "Texture",
    hotkey = "FontString", count = "FontString", name = "FontString", cooldown = "Cooldown" }
local ROUND = { maskIcon = true }   -- a provider's icon rounded to the glass (#46)
local pending = {}       -- button -> its region copy, until the glass is built and out of combat
local waiter

-- The waiting requests, once the glass is built and out of combat.
function GAB.FlushSkinRequests()
    if InCombatLockdown() or not GAB.GlassBuilt() then return end
    for button, regions in pairs(pending) do
        pending[button] = nil
        if GAB.db.skin ~= false and not GAB.Buttons.IsSkinned(button) then
            API.Try("api:skin", GAB.Buttons.Build, button, regions, ROUND)
        end
    end
end

function GAB.SkinButton(button, regions, owner)
    if not isA(button, "Button") then return false, "button must be a Button" end
    if regions ~= nil and type(regions) ~= "table" then return false, "regions must be a table" end
    if owner ~= nil and (type(owner) ~= "string" or owner == "") then return false, "owner must be a name" end
    local copy = {}
    for key, role in pairs(ROLES) do
        local r = regions and regions[key]
        if r ~= nil then
            if kind(r) ~= role then return false, key .. " must be a " .. role end
            copy[key] = r
        end
    end
    if GAB.db and GAB.db.skin == false then return false, "the glass is off (/gab skin)" end
    if owner then GAB.Look.AddTenant(owner) end
    if GAB.Buttons.IsSkinned(button) then return true end
    if InCombatLockdown() or not GAB.GlassBuilt() then
        pending[button] = copy
        if not waiter then
            waiter = CreateFrame("Frame")
            waiter:SetScript("OnEvent", GAB.FlushSkinRequests)
            API.RegisterEvents(waiter, { "PLAYER_REGEN_ENABLED" }, "api")
        end
        return true
    end
    API.Try("api:skin", GAB.Buttons.Build, button, copy, ROUND)
    return GAB.Buttons.IsSkinned(button)
end

-- A button for the Utility bar. def = { id, label?, icon, OnClick(button,
-- mouseButton), binding?, tooltip?, IsEnabled?, OnHosted? }. Stored here; the
-- Utility bar (#9) builds and hosts it. True, or false and why.
local provided, providedOrder = {}, {}
function GAB.RegisterButton(def)
    if type(def) ~= "table" then return false, "the definition must be a table" end
    if not validId(def.id) then return false, "id must be letters, digits and _" end
    if provided[def.id] then return false, "id '" .. def.id .. "' is already registered" end
    if def.label ~= nil and type(def.label) ~= "string" then return false, "label must be a string" end
    if type(def.icon) ~= "number" and type(def.icon) ~= "string" then return false, "icon must be a file ID or path" end
    if type(def.OnClick) ~= "function" then return false, "OnClick must be a function" end
    if def.binding ~= nil and type(def.binding) ~= "string" then return false, "binding must be a string" end
    if def.tooltip ~= nil and type(def.tooltip) ~= "string" and type(def.tooltip) ~= "function" then
        return false, "tooltip must be a string or a function"
    end
    for _, k in ipairs({ "IsEnabled", "OnHosted" }) do
        if def[k] ~= nil and type(def[k]) ~= "function" then return false, k .. " must be a function" end
    end
    provided[def.id] = { id = def.id, label = def.label or def.id, icon = def.icon, OnClick = def.OnClick,
        binding = def.binding, tooltip = def.tooltip, IsEnabled = def.IsEnabled, OnHosted = def.OnHosted }
    providedOrder[#providedOrder + 1] = def.id
    return true
end

-- Where the bars at the screen's sides end (#37, Edges.lua): { left, right,
-- width } in UIParent units, a fresh table; nil before the first measure.
-- Changes are announced on EventRegistry as "GlassActionBars.EdgesChanged".
function GAB.EdgeState()
    return GAB.Edges.State()
end

-- Internal, for the Utility bar: the registered buttons, in order, as copies.
function GAB.ProvidedButtons()
    local out = {}
    for _, id in ipairs(providedOrder) do
        local copy = {}
        for k, v in pairs(provided[id]) do copy[k] = v end
        out[#out + 1] = copy
    end
    return out
end

GAB._test = GAB._test or {}
GAB._test.apiPending = pending
