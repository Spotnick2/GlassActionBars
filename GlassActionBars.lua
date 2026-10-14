-- GlassActionBars.lua: bootstrap, saved settings, the settings helpers and the
-- /gab command. Loads last: every module is defined by now.

local ADDON = ...
GlassActionBars = GlassActionBars or {}
local GAB = GlassActionBars
local API = GAB.API
local say = API.Print

-- Account-wide (GlassActionBarsDB). Each feature adds its settings here as it lands.
local DEFAULTS = {
    skin = true,            -- the glass on Blizzard's bars (off: Blizzard's own art, after a /reload)
    theme = "clear",        -- one of GAB.Theme.NAMES
    showHotkeys = true,     -- the key binding text on each button
    showMacroNames = true,  -- a macro's name on its button
    endCaps = false,        -- the main bar's gryphons
}
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
    -- A theme this version doesn't know falls back to the default.
    if db.theme ~= nil and not GAB.Theme.IsValid(db.theme) then db.theme = nil end
    -- /gab tune: only known keys with a number in 0..1 survive.
    if db.tune ~= nil then
        if type(db.tune) ~= "table" then db.tune = nil else
            for k, v in pairs(db.tune) do
                if not GAB.Buttons.TUNE[k] or type(v) ~= "number" or v < 0 or v > 1 then db.tune[k] = nil end
            end
            if next(db.tune) == nil then db.tune = nil end
        end
    end
    setmetatable(db, { __index = DEFAULTS })
    return db
end

-- Every setting goes through here: /gab and the options page.
local Settings = {}
GAB.Settings = Settings

-- False for a name that isn't a theme; the setting is left as it was.
function Settings.SetTheme(name)
    if not GAB.Theme.IsValid(name) then return false end
    GAB.db.theme = name
    GAB.Theme.Refresh()
    return true
end

function Settings.SetShowHotkeys(on)
    GAB.db.showHotkeys = on == true
    GAB.Buttons.RefreshText()
    return true
end

function Settings.SetShowMacroNames(on)
    GAB.db.showMacroNames = on == true
    GAB.Buttons.RefreshText()
    return true
end

function Settings.SetEndCaps(on)
    GAB.db.endCaps = on == true
    GAB.Bars.Refresh()
    return true
end

-- One of the look's numbers (Buttons.TUNE), 0..1, repainted live; nil puts
-- the built-in value back. False for an unknown key or a bad value.
function Settings.SetTune(key, value)
    if not GAB.Buttons.TUNE[key] then return false end
    if value ~= nil and (type(value) ~= "number" or not (value >= 0 and value <= 1)) then return false end
    if value ~= nil then
        GAB.db.tune = rawget(GAB.db, "tune") or {}
        GAB.db.tune[key] = value
    elseif rawget(GAB.db, "tune") then
        GAB.db.tune[key] = nil
        if next(GAB.db.tune) == nil then GAB.db.tune = nil end
    end
    GAB.Buttons.RefreshLook()
    return true
end

-- The skin can't be taken off live: Blizzard set the art we replaced, and
-- only its own code puts it back. Takes effect at the next /reload.
function Settings.SetSkin(on)
    GAB.db.skin = on == true
    return true
end

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
local function onoff(v) return v and "on" or "off" end

local function helpLines()
    local db = GAB.db
    return {
        "/gab theme " .. table.concat(GAB.Theme.NAMES, "/") .. " - the glass (" .. db.theme .. ")",
        "/gab hotkeys on/off - key bindings on the buttons (" .. onoff(db.showHotkeys) .. ")",
        "/gab macros on/off - macro names on the buttons (" .. onoff(db.showMacroNames) .. ")",
        "/gab gryphons on/off - the main bar's end caps (" .. onoff(db.endCaps) .. ")",
        "/gab skin on/off - glass, or Blizzard's own art after a /reload (" .. onoff(db.skin) .. ")",
        "/gab tune [key value|reset] - the glass's numbers, live (rim, empty, dark, wash, body)",
        "/gab options - open the options page",
        "/gab failures - what failed to build or register",
        "/gab version - client build vs the measured one",
    }
end
GAB.HelpLines = helpLines

local ONOFF = { on = true, off = false }

-- /gab <name> on/off for an on/off setting.
local SWITCHES = {
    hotkeys = { Settings.SetShowHotkeys, "key bindings on the buttons" },
    macros = { Settings.SetShowMacroNames, "macro names on the buttons" },
    gryphons = { Settings.SetEndCaps, "the main bar's end caps" },
}

local function slash(msg)
    local cmd, arg = (msg or ""):lower():match("^%s*(%S*)%s*(.-)%s*$")
    if cmd == "theme" then
        if Settings.SetTheme(arg) then say("theme " .. arg)
        else say("/gab theme " .. table.concat(GAB.Theme.NAMES, "/")) end
    elseif SWITCHES[cmd] then
        if ONOFF[arg] == nil then return say("/gab " .. cmd .. " on/off") end
        SWITCHES[cmd][1](ONOFF[arg])
        say(SWITCHES[cmd][2] .. " " .. arg)
    elseif cmd == "skin" then
        if ONOFF[arg] == nil then return say("/gab skin on/off") end
        Settings.SetSkin(ONOFF[arg])
        say("skin " .. arg .. " after a /reload")
    elseif cmd == "tune" then
        local key, value = arg:match("^(%S*)%s*(.-)$")
        if key == "reset" then
            for _, k in ipairs(GAB.Buttons.TUNE_ORDER) do Settings.SetTune(k, nil) end
            say("tune: the built-in values")
        elseif key == "" then
            for _, k in ipairs(GAB.Buttons.TUNE_ORDER) do
                say(("tune %s %.2f - %s"):format(k, GAB.Buttons.Tune(k), GAB.Buttons.TUNE[k][2]))
            end
        elseif GAB.Buttons.TUNE[key] and value == "" then
            say(("tune %s %.2f - %s"):format(key, GAB.Buttons.Tune(key), GAB.Buttons.TUNE[key][2]))
        elseif tonumber(value) and Settings.SetTune(key, tonumber(value)) then
            say(("tune %s %.2f"):format(key, GAB.Buttons.Tune(key)))
        else
            say("/gab tune <" .. table.concat(GAB.Buttons.TUNE_ORDER, "|") .. "> <0..1>, or /gab tune reset")
        end
    elseif cmd == "options" then
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
        start("buttons", GAB.Buttons.Start)
        start("bars", GAB.Bars.Start)
    elseif event == "PLAYER_ENTERING_WORLD" then
        GAB.Theme.Retry()
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
