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
    material = "pearl",     -- the glass's LibGlass preset (GAB.MATERIALS), after a /reload; unused while following Glass UI
    showHotkeys = true,     -- the key binding text on each button
    showMacroNames = true,  -- a macro's name on its button
    endCaps = false,        -- the main bar's gryphons
    microStyle = "tiles",   -- the micro buttons each on glass, or "pill": one glass pill behind them (#57)
    fadeAlpha = 0,          -- a faded bar's alpha (fade: { [bar frame name] = mode }, absent = no fade)
    follow = true,          -- the stance and pet bars move with Glass Unit Frames' player and pet frames
    -- The look (theme, hover, press, emptySlots) is GlassActionBarsDB.look,
    -- the player's own values, never pruned; its defaults are Look.DEFAULTS.
}
GAB.DEFAULTS = DEFAULTS

-- Only what the player SET is saved: everything else falls through to
-- DEFAULTS, so a changed default reaches everyone. Saved keys equal to the
-- default are dropped. Nothing may REQUIRE a value to have survived
-- (GlassChat's rule).
local function ensureDefaults()
    if type(GlassActionBarsDB) ~= "table" then GlassActionBarsDB = {} end
    local db = GlassActionBarsDB
    -- The look moves into its own table (#39), once and before any prune: the
    -- raw top-level keys, valid ones only, into keys `look` lacks (an existing
    -- entry wins), then the old keys go. Idempotent, no version stamp. A
    -- legacy key equal to a default still moves: the player set it.
    local look = type(rawget(db, "look")) == "table" and rawget(db, "look") or {}
    for _, k in ipairs(GAB.Look.KEYS) do
        local v = rawget(db, k)
        if v ~= nil then
            if look[k] == nil and GAB.Look.Valid(k, v) then look[k] = v end
            db[k] = nil
        end
    end
    for k, v in pairs(look) do
        if not GAB.Look.Valid(k, v) then look[k] = nil end   -- unknown key or choice
    end
    db.look = next(look) ~= nil and look or nil
    for k, v in pairs(DEFAULTS) do
        if db[k] == v then db[k] = nil end
    end
    if db.material ~= nil and not GAB.IsMaterial(db.material) then db.material = nil end
    if db.microStyle ~= nil and not GAB.Micro.IsStyle(db.microStyle) then db.microStyle = nil end
    -- /gab tune: only known keys with a number in 0..1 survive. A key Pearl
    -- sets its own default for (#44) is kept whatever its value: the material
    -- is only known at login (Glass UI's, maybe), so no value is "the default".
    if db.tune ~= nil then
        if type(db.tune) ~= "table" then db.tune = nil else
            for k, v in pairs(db.tune) do
                local known = GAB.Buttons.TUNE[k]
                if not known or type(v) ~= "number" or not (v >= 0 and v <= 1)
                        or (GAB.Buttons.PEARL[k] == nil and v == known[1]) then
                    db.tune[k] = nil   -- unknown, out of range, or the one built-in value
                end
            end
            if next(db.tune) == nil then db.tune = nil end
        end
    end
    -- Bar fade: only known bars with a mode that fades survive.
    if db.fade ~= nil then
        if type(db.fade) ~= "table" then db.fade = nil else
            for k, v in pairs(db.fade) do
                if not GAB.Fade.byName[k] or v == "off" or not GAB.Fade.IsMode(v) then db.fade[k] = nil end
            end
            if next(db.fade) == nil then db.fade = nil end
        end
    end
    -- Dock: per client id (kept for a provider that loads later), only valid keys.
    if db.dock ~= nil then
        if type(db.dock) ~= "table" then db.dock = nil else
            for id, s in pairs(db.dock) do
                if type(id) ~= "string" or type(s) ~= "table" then db.dock[id] = nil else
                    for k, v in pairs(s) do
                        if not GAB.Dock.Valid(k, v) then s[k] = nil end
                    end
                    if next(s) == nil then db.dock[id] = nil end
                end
            end
            if next(db.dock) == nil then db.dock = nil end
        end
    end
    -- Utility bar: a present table stays, even emptied (its absence marks a
    -- profile Apotheca's settings may still be imported into); only valid
    -- entries survive in it.
    if db.utility ~= nil then
        if type(db.utility) ~= "table" then db.utility = nil else
            local u, U = db.utility, GAB.Utility
            if u.enabled ~= nil and type(u.enabled) ~= "boolean" then u.enabled = nil end
            if u.show ~= nil then
                if type(u.show) ~= "table" then u.show = nil else
                    for k, v in pairs(u.show) do
                        -- Only what differs from the default: a built-in entry off, a provider's on.
                        local want = U.ProviderId(k) and true or false
                        if not U.ValidKey(k) or v ~= want then u.show[k] = nil end
                    end
                end
            end
            if u.order ~= nil then
                if type(u.order) ~= "table" then u.order = nil else
                    local clean, seen = {}, {}
                    for _, k in ipairs(u.order) do
                        if U.ValidKey(k) and not seen[k] then clean[#clean + 1] = k; seen[k] = true end
                    end
                    u.order = clean
                end
            end
            for k in pairs(U.LAYOUT) do
                if u[k] ~= nil and not U.ValidLayout(k, u[k]) then u[k] = nil end
            end
            if u.pos ~= nil and not U.ValidPos(u.pos) then u.pos = nil end
        end
    end
    if db.fadeAlpha ~= nil and (type(db.fadeAlpha) ~= "number" or not (db.fadeAlpha >= 0 and db.fadeAlpha <= 1)) then
        db.fadeAlpha = nil
    end
    setmetatable(db, { __index = DEFAULTS })
    return db
end

-- Every setting goes through here: /gab and the options page.
local Settings = {}
GAB.Settings = Settings

-- The player's own look values (an override while following Glass UI).
local function ownLook()
    local t = rawget(GAB.db, "look")
    if type(t) ~= "table" then
        t = {}
        GAB.db.look = t
    end
    return t
end

-- False for a name that isn't a theme; the setting is left as it was.
function Settings.SetTheme(name)
    if not GAB.Theme.IsValid(name) then return false end
    ownLook().theme = name
    GAB.Look.Refresh()
    return true
end

-- Back to Glass UI's value for one look key ("theme", "hover", "press",
-- "emptySlots"; GAB's default when not following): the player's own cleared.
function Settings.ClearLook(key)
    if GAB.Look.DEFAULTS[key] == nil then return false end
    local t = rawget(GAB.db, "look")
    if type(t) == "table" then
        t[key] = nil
        if next(t) == nil then GAB.db.look = nil end
    end
    GAB.Look.Refresh()
    return true
end

-- The glass's material (GAB.MATERIALS), applied at the next /reload. While
-- following Glass UI the material is Glass UI's: refused, and why.
function Settings.SetMaterial(m)
    if GAB.Look.Following() then return false, "set in Glass UI" end
    if not GAB.IsMaterial(m) then return false, "pearl, clean or classic" end
    GAB.db.material = m
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

-- The micro menu's glass (#57): "tiles" or "pill", live. False for another.
function Settings.SetMicroStyle(v)
    if not GAB.Micro.IsStyle(v) then return false end
    GAB.db.microStyle = v
    API.Try("micro:style", GAB.Micro.Sync)
    return true
end

-- One button-feedback setting (Buttons.LOOK's keys and choices), live. False
-- for an unknown key or choice.
function Settings.SetLook(key, value)
    if not GAB.Buttons.ValidLook(key, value) then return false end
    ownLook()[key] = value
    GAB.Look.Refresh()
    return true
end

-- A preset (Buttons.PRESETS): all three at once, as the player's own.
-- "suite": the three back to Glass UI's. False for an unknown one.
function Settings.SetLookPreset(name)
    if name == "suite" then
        local t = rawget(GAB.db, "look")
        if type(t) == "table" then
            for _, k in ipairs(GAB.Buttons.LOOK_ORDER) do t[k] = nil end
            if next(t) == nil then GAB.db.look = nil end
        end
        GAB.Look.Refresh()
        return true
    end
    local p = GAB.Buttons.PRESETS[name]
    if not p then return false end
    local t = ownLook()
    for k, v in pairs(p) do t[k] = v end
    GAB.Look.Refresh()
    return true
end

-- The stance and pet bars follow Glass Unit Frames (off: back to Edit Mode's
-- positions, after combat if in one).
function Settings.SetFollow(on)
    GAB.db.follow = on == true
    GAB.Follow.Reconcile()
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

-- A bar's fade (a Fade.BARS frame name, a Fade.MODES mode), live. False for
-- an unknown bar or mode.
function Settings.SetFade(name, mode)
    if not GAB.Fade.byName[name] or not GAB.Fade.IsMode(mode) then return false end
    local t = rawget(GAB.db, "fade") or {}
    t[name] = mode ~= "off" and mode or nil
    GAB.db.fade = next(t) ~= nil and t or nil
    GAB.Fade.Apply()
    return true
end

-- A faded bar's alpha, 0..1, live.
function Settings.SetFadeAlpha(a)
    if type(a) ~= "number" or not (a >= 0 and a <= 1) then return false end
    GAB.db.fadeAlpha = a ~= DEFAULTS.fadeAlpha and a or nil
    GAB.Fade.Apply()
    return true
end

-- One dock setting of a client (Dock.Valid's keys), applied at the next pass
-- out of combat. False for a bad key or value.
function Settings.SetDock(id, key, value)
    if type(id) ~= "string" or not GAB.Dock.Valid(key, value) then return false end
    local t = rawget(GAB.db, "dock") or {}
    t[id] = t[id] or {}
    -- The size and the rows are separate choices (#48): the rows' current
    -- value (a default, or "off" from before the split) is kept first.
    if key == "match" and t[id].matchRows == nil then t[id].matchRows = GAB.Dock.Setting(id, "matchRows") end
    t[id][key] = value
    GAB.db.dock = t
    GAB.Dock.Request(id)
    return true
end

-- The Utility bar's settings table, created by the first change.
local function utility()
    local u = rawget(GAB.db, "utility")
    if type(u) ~= "table" then
        u = {}
        GAB.db.utility = u
    end
    return u
end

function Settings.SetUtilityEnabled(on)
    utility().enabled = on == true
    GAB.Utility.Reconcile()
    return true
end

-- Show or hide one entry of the bar (an action key, "camping", or another
-- addon's provider:<id>, off by default).
function Settings.SetUtilityShown(key, on)
    if not GAB.Utility.ValidKey(key) then return false end
    local u = utility()
    u.show = u.show or {}
    -- Only what differs from the default is stored.
    if GAB.Utility.ProviderId(key) then
        u.show[key] = on == true or nil
    elseif on == false then u.show[key] = false else u.show[key] = nil end
    GAB.Utility.Reconcile()
    return true
end

-- One of the bar's own layout settings (Utility.LAYOUT's keys), used when it
-- isn't matching a docked bar. False for a bad key or value.
function Settings.SetUtilityLayout(key, value)
    if not GAB.Utility.ValidLayout(key, value) then return false end
    utility()[key] = value
    GAB.Utility.Reconcile()
    return true
end

-- Where the undocked bar sits: its bottom-left corner on UIParent. The
-- Utility bar's drag and undock save it; false for a bad position.
function Settings.SetUtilityPosition(x, y)
    if not GAB.Utility.ValidPos({ x = x, y = y }) then return false end
    utility().pos = { x = x, y = y }
    return true
end

-- Move an entry one place up (-1) or down (1), past the keys of addons not
-- registered this session (unseen, they keep their slot). False at an end.
function Settings.MoveUtility(key, delta)
    local U = GAB.Utility
    local order = U.Order()
    local i
    for n, k in ipairs(order) do if k == key then i = n end end
    local j = i and i + delta
    while j and order[j] and not U.Registered(order[j]) do j = j + delta end
    if not j or j < 1 or j > #order then return false end
    order[i], order[j] = order[j], order[i]
    utility().order = order
    GAB.Utility.Reconcile()
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
        "/gab theme " .. table.concat(GAB.Theme.NAMES, "/") .. "|suite - the glass's tint (" .. GAB.Theme.Current() .. ")",
        "/gab material pearl/clean/classic - the glass itself, after a /reload (" .. (GAB.GlassPreset or "?") .. ")",
        "/gab hotkeys on/off - key bindings on the buttons (" .. onoff(db.showHotkeys) .. ")",
        "/gab macros on/off - macro names on the buttons (" .. onoff(db.showMacroNames) .. ")",
        "/gab gryphons on/off - the main bar's end caps (" .. onoff(db.endCaps) .. ")",
        "/gab micro tiles/pill - the micro menu's glass: each button on glass, or one pill (" .. GAB.Micro.Style() .. ")",
        "/gab skin on/off - glass, or Blizzard's own art after a /reload (" .. onoff(db.skin) .. ")",
        "/gab tune [key value|reset] - the glass's numbers, live (rim, empty, dark, wash, body, frostGrey, frostAlpha, frostRim, gloss, socketShade)",
        "/gab fade [1-8|stance|pet|all off/mouseover/combat] - fade bars until hovered, or out of combat",
        ("/gab fade alpha 0..1 - how faded a faded bar is (%.2f)"):format(db.fadeAlpha),
        "/gab dock [<bar> 1-8|off [side] [align] | <bar> gap 0-32 | <bar> match/rows on/off] - dock a smart bar to an action bar",
        "/gab utility on/off - the Utility bar: Hearthstone, professions, camping (" .. onoff(GAB.Utility.Enabled()) .. ")",
        "/gab follow [on/off] - the stance and pet bars move with Glass Unit Frames (" .. onoff(db.follow) .. ")",
        "/gab look [glass|soft|minimal | hover|press|empty <choice>] - button feedback ("
            .. GAB.Buttons.Preset() .. ")",
        "/gab inspect [button|hide n|show n|restore] - what a button draws, layer by layer",
        "/gab layer <name> off/on - hide one layer on every button, for a look (a /reload undoes it)",
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
        if arg == "suite" and Settings.ClearLook("theme") then say("theme: Glass UI's")
        elseif Settings.SetTheme(arg) then say("theme " .. arg)
        else say("/gab theme " .. table.concat(GAB.Theme.NAMES, "/") .. "/suite") end
    elseif cmd == "material" then
        local ok, why = Settings.SetMaterial(arg)
        if ok then say("material " .. arg .. ", after a /reload")
        else say("/gab material pearl/clean/classic" .. (why and (": " .. why) or "")) end
    elseif cmd == "micro" then
        if Settings.SetMicroStyle(arg) then say("micro menu: " .. arg)
        else say("/gab micro tiles/pill") end
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
        for _, k in ipairs(GAB.Buttons.TUNE_ORDER) do   -- the message is lowercased: frostgrey is frostGrey
            if k:lower() == key then key = k end
        end
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
    elseif cmd == "fade" then
        local key, value = arg:match("^(%S*)%s*(.-)$")
        local Fade = GAB.Fade
        if key == "" then
            for _, b in ipairs(Fade.BARS) do
                say(("fade %s (%s): %s"):format(b[2], b[3], Fade.LABELS[Fade.Mode(b[1])]))
            end
            say(("fade alpha %.2f"):format(GAB.db.fadeAlpha))
        elseif key == "alpha" and tonumber(value) and Settings.SetFadeAlpha(tonumber(value)) then
            say(("fade alpha %.2f"):format(GAB.db.fadeAlpha))
        elseif (key == "all" or Fade.byKey[key]) and Fade.IsMode(value) then
            for _, b in ipairs(Fade.BARS) do
                if key == "all" or b[2] == key then Settings.SetFade(b[1], value) end
            end
            say("fade " .. key .. ": " .. Fade.LABELS[value])
        else
            say("/gab fade <1-8|stance|pet|all> <off|mouseover|combat>, or /gab fade alpha <0..1>")
        end
    elseif cmd == "dock" then
        local Dock = GAB.Dock
        local key, a, b, c = arg:match("^(%S*)%s*(%S*)%s*(%S*)%s*(%S*)")
        local id
        for _, cl in ipairs(Dock.Clients()) do
            if cl.id:lower() == key then id = cl.id end
        end
        local usage = "/gab dock <bar> <1-8|off> [left|right|top|bottom] [start|center|end], "
            .. "/gab dock <bar> gap <0-32>, /gab dock <bar> match on/off (size and spacing), /gab dock <bar> rows on/off"
        if key == "" then
            local list = Dock.Clients()
            if #list == 0 then return say("dock: no smart bars yet") end
            for _, cl in ipairs(list) do
                local S = function(k) return Dock.Setting(cl.id, k) end
                if S("bar") then
                    say(("dock %s (%s): bar %d, %s, %s, gap %g, match %s, rows %s%s"):format(cl.id, cl.label, S("bar"),
                        S("side"):lower(), S("align"):lower(), S("gap"), onoff(S("match")), onoff(S("matchRows")),
                        Dock.IsHosted(cl.id) and "" or " (not placed yet)"))
                else
                    say(("dock %s (%s): not docked"):format(cl.id, cl.label))
                end
            end
        elseif not id then
            say(usage)
        elseif a == "off" then
            Settings.SetDock(id, "bar", false)
            say("dock " .. id .. ": not docked")
        elseif a == "gap" and tonumber(b) and Settings.SetDock(id, "gap", tonumber(b)) then
            say(("dock %s: gap %g"):format(id, tonumber(b)))
        elseif a == "match" and ONOFF[b] ~= nil then
            Settings.SetDock(id, "match", ONOFF[b])
            say("dock " .. id .. ": match " .. b)
        elseif a == "rows" and ONOFF[b] ~= nil then
            Settings.SetDock(id, "matchRows", ONOFF[b])
            say("dock " .. id .. ": rows " .. b)
        elseif tonumber(a) and Dock.Valid("bar", tonumber(a))
            and (b == "" or Dock.Valid("side", b:upper())) and (c == "" or Dock.Valid("align", c:upper())) then
            Settings.SetDock(id, "bar", tonumber(a))
            if b ~= "" then Settings.SetDock(id, "side", b:upper()) end
            if c ~= "" then Settings.SetDock(id, "align", c:upper()) end
            say(("dock %s: bar %d, %s, %s"):format(id, tonumber(a), Dock.Setting(id, "side"):lower(),
                Dock.Setting(id, "align"):lower()))
        else
            say(usage)
        end
    elseif cmd == "utility" then
        if ONOFF[arg] == nil then return say("/gab utility on/off") end
        Settings.SetUtilityEnabled(ONOFF[arg])
        say("Utility bar " .. arg .. (InCombatLockdown() and " (when the fight ends)" or ""))
    elseif cmd == "look" then
        local B = GAB.Buttons
        local key, value = arg:match("^(%S*)%s*(%S*)$")
        local alias = { empty = "emptySlots", hover = "hover", press = "press" }
        if key == "" then
            local parts = {}
            for _, k in ipairs(B.LOOK_ORDER) do parts[#parts + 1] = k .. " " .. B.Look(k) end
            say("look: " .. B.Preset() .. " (" .. table.concat(parts, ", ") .. ")")
        elseif (B.PRESETS[key] or key == "suite") and value == "" then
            Settings.SetLookPreset(key)
            say("look: " .. (key == "suite" and "Glass UI's" or key))
        elseif alias[key] and value == "suite" and Settings.ClearLook(alias[key]) then
            say("look: " .. alias[key] .. " from Glass UI")
        elseif alias[key] and Settings.SetLook(alias[key], value) then
            say("look: " .. alias[key] .. " " .. value)
        else
            say("/gab look glass|soft|minimal|suite, or /gab look hover off|glow|halo|suite, "
                .. "press off|flash|ripple|suite, empty hidden|faint|half|full|frosted|suite")
        end
    elseif cmd == "follow" then
        if arg == "" then
            local s = GAB.Follow.Status()
            say("follow " .. onoff(GAB.db.follow) .. ": stance bar " .. s.StanceBar .. "; pet bar " .. s.PetActionBar)
        elseif ONOFF[arg] == nil then
            say("/gab follow on/off")
        else
            Settings.SetFollow(ONOFF[arg])
            say("follow " .. arg .. (InCombatLockdown() and " (when the fight ends)" or ""))
        end
    elseif cmd == "inspect" then
        local sub, n = arg:match("^(%S*)%s*(.-)$")
        if sub == "hide" and tonumber(n) then GAB.Inspect.Hide(tonumber(n))
        elseif sub == "show" and tonumber(n) then GAB.Inspect.Show(tonumber(n))
        elseif sub == "restore" then GAB.Inspect.Restore()
        else
            -- A button's name keeps its case: read it from the raw message.
            local raw = (msg or ""):match("^%s*%S+%s+(%S+)")
            GAB.Inspect.Run(raw)
        end
    elseif cmd == "layer" then
        local name, state = (msg or ""):match("^%s*%S+%s+(%S+)%s*(%S*)")
        state = state and state:lower()
        if not (name and (state == "on" or state == "off") and GAB.Inspect.Layer(name, state == "on")) then
            say("/gab layer <" .. table.concat(GAB.Inspect.LAYER_NAMES, "|") .. "> off/on")
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
        -- The look first: Glass UI asked, the glass built (Look.lua). Nothing
        -- builds a surface before it.
        start("look", GAB.Look.Start)
        if not GAB.GlassBuilt() then start("glass", function() GAB.BuildGlass("clean") end) end
        start("options", GAB.Options.Register)
        start("buttons", GAB.Buttons.Start)
        start("skin requests", GAB.FlushSkinRequests)   -- providers that asked before the glass existed
        start("bars", GAB.Bars.Start)
        start("bags", GAB.Bags.Start)
        start("micro", GAB.Micro.Start)
        start("fade", GAB.Fade.Start)
        start("dock", GAB.Dock.Start)
        start("follow", GAB.Follow.Start)
        start("utility", GAB.Utility.Start)
        start("edges", GAB.Edges.Start)
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
