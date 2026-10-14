-- GlassActionBars.lua: bootstrap, saved settings, the settings helpers and the
-- /gab command. Loads last: every module is defined by now.

local ADDON = ...
GlassActionBars = GlassActionBars or {}
local GAB = GlassActionBars
local API = GAB.API
local say = API.Print

-- Account-wide (GlassActionBarsDB). Each feature adds its settings here as it lands.
local DEFAULTS = {}
GAB.DEFAULTS = DEFAULTS

-- Only what the player SET is saved: everything else falls through to
-- DEFAULTS, so a changed default reaches everyone. Saved keys equal to the
-- default are dropped. Nothing may REQUIRE a value to have survived
-- (GlassChat's rule).
local function ensureDefaults()
    if type(GlassActionBarsDB) ~= "table" then GlassActionBarsDB = {} end
    local db = GlassActionBarsDB
    for k, v in pairs(DEFAULTS) do
        if db[k] == v then db[k] = nil end
    end
    setmetatable(db, { __index = DEFAULTS })
    return db
end

-- Every setting goes through here: /gab and the options page.
local Settings = {}
GAB.Settings = Settings

-- A dev build, by its version: "dev" from the deploy script, or the
-- packager's token left unreplaced (matched as a pattern, never written whole:
-- the packager would replace it here too). Unreadable is NOT dev.
function GAB.IsDev()
    local v = API.AddOnVersion(ADDON or "GlassActionBars")
    return v ~= nil and (v == "dev" or v:find("@project%-version@") ~= nil)
end

function GAB.VersionText()
    local v = API.AddOnVersion(ADDON or "GlassActionBars")
    if v == nil or v == "" or GAB.IsDev() then return "dev" end
    return v
end

local function failures()
    local any = false
    for key, err in pairs(GAB.failures) do
        any = true
        say(key .. ": " .. err)
    end
    if not any then say("no failures recorded") end
end

-- The command list: /gab help prints it.
local function helpLines()
    return {
        "/gab options - open the options page",
        "/gab failures - what failed to build or register",
        "/gab version - client build vs the measured one",
    }
end
GAB.HelpLines = helpLines

local function slash(msg)
    local cmd = (msg or ""):lower():match("^%s*(%S*)")
    if cmd == "options" then
        if not GAB.Options.Open() then say("Esc > Options > AddOns > Glass Action Bars") end
    elseif cmd == "failures" then
        failures()
    elseif cmd == "version" then
        say("version " .. GAB.VersionText() .. ", client " .. API.ClientBuild()
            .. ", measured on " .. GAB.MEASURED_ON_BUILD)
    else
        for _, line in ipairs(helpLines()) do say(line) end
    end
end

SLASH_GLASSACTIONBARS1 = "/gab"
SLASH_GLASSACTIONBARS2 = "/glassactionbars"
SlashCmdList.GLASSACTIONBARS = slash

local function start(key, fn)
    local ok, err = pcall(fn)
    if not ok then API.Fail(key, err) end
end

local boot = CreateFrame("Frame")
boot:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 == ADDON then GAB.db = ensureDefaults() end
    elseif event == "PLAYER_LOGIN" then
        -- SavedVariables are read here at the latest (porting guide: not at file scope).
        if not GAB.db then GAB.db = ensureDefaults() end
        start("options", GAB.Options.Register)
    elseif event == "PLAYER_ENTERING_WORLD" then
        -- arg1 = isInitialLogin. The build warning asks the developer to
        -- re-measure; a player can't act on it, and /reload never repeats it.
        if arg1 and GAB.IsDev() and API.ClientBuild() ~= GAB.MEASURED_ON_BUILD then
            say("client build " .. API.ClientBuild() .. " differs from the one this addon was measured on ("
                .. GAB.MEASURED_ON_BUILD .. "). Things may misbehave until it is re-checked.")
        end
    end
end)
API.RegisterEvents(boot, { "ADDON_LOADED", "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD" }, "boot")

GAB._test = GAB._test or {}
GAB._test.ensureDefaults = ensureDefaults
GAB._test.DEFAULTS = DEFAULTS
