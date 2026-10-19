-- Look.lua: the look of the glass (#39; Glass UI's docs/SUITE.md and
-- docs/SUITE-LOOK.md). Two layers:
--   the material  Pearl, Clean or Classic: the LibGlass preset the glass is
--                 built with, once, at PLAYER_LOGIN (a change needs /reload);
--   the look      the tint (GAB's `theme`) and the button feedback (hover,
--                 press, emptySlots), repainted live.
--
-- Glass UI may own both for the suite. A player follows it with Glass UI's
-- "Use Glass UI appearance" switch, read here once per session through
-- GlassUI.Suite.Theme. While following:
--   - the material is the suite's; GAB's own `material` setting stays saved
--     and unused ("set in Glass UI");
--   - each look key is the player's override in GAB (GlassActionBarsDB.look,
--     never pruned) if there is one, else the suite's, updated live by
--     EventRegistry "GlassUI.Suite.LookChanged".
-- Not following (or no Glass UI, or an older one): GAB's own material and
-- look, exactly as before. Nothing changes until the player changes it: the
-- suite's defaults are GAB's own.
--
-- GAB reports what it built and its look to Glass UI (Suite.Report), and
-- names the addons whose buttons wear its skin (SkinButton's owners).

local ADDON = ...
GlassActionBars = GlassActionBars or {}
local GAB = GlassActionBars
local API = GAB.API
local Look = {}
GAB.Look = Look

Look.ADDON = ADDON or "GlassActionBars"
Look.EVENT = "GlassUI.Suite.LookChanged"
Look.KEYS = { "theme", "hover", "press", "emptySlots" }
Look.SUITE_NAME = { theme = "tint", hover = "hover", press = "press", emptySlots = "emptySlots" }
-- GAB's own look: the clear glass and the Glass preset.
Look.DEFAULTS = { theme = "clear", hover = "glow", press = "flash", emptySlots = "frosted" }

local suite             -- GlassUI.Suite when it speaks API 1
local following = false
local suiteLook = {}    -- the suite's values, copied (the payload is read-only)
local built, failure    -- the preset built; why the one asked for wasn't
local tenants, tenantList = {}, {}

function Look.Valid(key, v)
    if key == "theme" then return GAB.Theme.IsValid(v) end
    if Look.DEFAULTS[key] == nil then return false end
    return GAB.Buttons.ValidLook(key, v)
end

local function overrides()
    local t = GAB.db and rawget(GAB.db, "look")
    return type(t) == "table" and t or nil
end

-- The player's own value for a key in GAB (an override while following), or nil.
function Look.Own(key)
    local o = overrides()
    local v = o and o[key]
    if Look.Valid(key, v) then return v end
end

-- The suite's value for a key, while following (nil otherwise).
function Look.SuiteValue(key)
    if following then return suiteLook[key] end
end

-- The value in effect: the player's own, else the suite's, else GAB's default.
function Look.Get(key)
    local v = Look.Own(key)
    if v ~= nil then return v end
    v = Look.SuiteValue(key)
    if v ~= nil then return v end
    return Look.DEFAULTS[key]
end

function Look.Following() return following end

-- The material to build when not following.
function Look.Material()
    local m = GAB.db and GAB.db.material
    return GAB.IsMaterial(m) and m or "pearl"
end

local function copyLook(look)
    for _, k in ipairs(Look.KEYS) do
        local v = type(look) == "table" and look[Look.SUITE_NAME[k]]
        if Look.Valid(k, v) then suiteLook[k] = v else suiteLook[k] = nil end
    end
end

-- Repaint everything live (combat-safe: textures, colours and alphas only).
function Look.Refresh()
    GAB.Theme.Refresh()
    GAB.Buttons.RefreshFeedback()
    Look.Report()
end

local function onLookChanged(_, look)
    copyLook(look)
    API.Try("look:refresh", Look.Refresh)
end

-- Glass UI's suite API, when it speaks version 1 (anything else counts as absent).
local function suiteAPI()
    local G = rawget(_G, "GlassUI")
    if type(G) ~= "table" then return nil end
    local S = rawget(G, "Suite")
    if type(S) ~= "table" or rawget(S, "API") ~= 1 then return nil end
    if type(rawget(S, "Theme")) ~= "function" or type(rawget(S, "Report")) ~= "function" then return nil end
    return S
end

-- At PLAYER_LOGIN, before any glass: decide following once for the session,
-- then build the material. Returns nothing; the glass is built after.
function Look.Start()
    suite = suiteAPI()
    local preset = Look.Material()
    if suite then
        local ok, answer = pcall(suite.Theme, Look.ADDON)
        if ok and type(answer) == "table" and GAB.IsMaterial(answer.preset) then
            following, preset = true, answer.preset
        end
    end
    if following and type(rawget(suite, "Look")) == "function" then
        if EventRegistry and EventRegistry.RegisterCallback then
            EventRegistry:RegisterCallback(Look.EVENT, onLookChanged, Look)
        end
        local ok, look = pcall(suite.Look)
        if ok then copyLook(look) end
    end
    local ok, reason = GAB.BuildGlass(preset)
    built = GAB.GlassPreset
    failure = not ok and reason or nil
    if failure and not following then
        API.Fail("look:material", "the " .. preset .. " glass couldn't be built (" .. failure .. "): Clean instead")
    end
    Look.Report()
end

-- The addons whose buttons wear GAB's skin (SkinButton's owner argument).
function Look.AddTenant(owner)
    if type(owner) ~= "string" or owner == "" or tenants[owner] then return end
    tenants[owner] = true
    tenantList[#tenantList + 1] = owner
    if GAB.GlassBuilt() then Look.Report() end
end

-- What GAB built and shows, for Glass UI's page (plain values only).
function Look.Report()
    if not suite then return end
    local look, own = {}, {}
    for _, k in ipairs(Look.KEYS) do
        look[Look.SUITE_NAME[k]] = Look.Get(k)
        if Look.Own(k) ~= nil then own[Look.SUITE_NAME[k]] = true end
    end
    local copy = {}
    for i, t in ipairs(tenantList) do copy[i] = t end
    local state = {
        api = 1,
        built = following and failure == nil and built or nil,
        reason = following and failure or nil,
        minor = GAB.GlassMinor,
        look = look,
        own = own,
        tenants = copy,
        options = function() GAB.Options.Open() end,
    }
    pcall(suite.Report, Look.ADDON, state)
end

Look._test = { suiteLook = suiteLook, suiteAPI = suiteAPI, failure = function() return failure end }
