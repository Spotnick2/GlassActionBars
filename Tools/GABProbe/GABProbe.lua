-- GABProbe: the throwaway measurement module for Glass Action Bars, on
-- ForeverProbe (/fp gab). Born a module again (#32): the standalone v0.1.0
-- probe (/gabprobe: regions, writers, secrets, levels, bar alpha, the
-- Hearthstone) is in git history before this file; its still-open checks
-- (stance secrets, active-pet slots, per-operation hook trials) come back here
-- when an issue needs them.
--
-- The campfire procedure (#9), /fp steps gab campfire:
--   - whether aura CAMPFIRE_AURA (1283391, Wowhead's "Campfire Nearby") is the
--     buff a campfire gives: read away from and next to a fire, with every
--     helpful aura on the player listed by id next to it, in case it isn't;
--   - whether the Utility bar adds and drops the camp features with it;
--   - whether camp features share one cooldown: every carried camping item's
--     cooldown, read before and after placing one.
-- Commands: /fp gab aura, /fp gab camping, /fp gab clear.

local ADDON, NS = ...
local MAX_LOG = 3000
local AURA = 1283391

local Probe = ForeverProbe:Module("GABProbe", { api = 1, cmd = "gab" })
local Show = Probe.Show

local function say(msg) Probe:Say(msg) end
local function secret(v) return issecretvalue ~= nil and issecretvalue(v) end

-- Glass Action Bars' Utility bar, when it's loaded.
local function utility()
    local gab = rawget(_G, "GlassActionBars")
    return gab and gab.Utility
end

-- The campfire buff: true, false, "secret", or nil when the read failed.
local function aura()
    local ok, a = Probe:Try("GetPlayerAuraBySpellID", C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID, AURA)
    if not ok then return nil end
    if secret(a) then return "secret" end
    return a ~= nil
end

-- Every helpful aura on the player, one line each; their ids as one string.
local function listAuras()
    local ids = {}
    for i = 1, 80 do
        local ok, a = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL")
        if not ok then say("aura " .. i .. ": ERROR " .. tostring(a)) break end
        -- Secret first: comparing a secret with nil throws on the client.
        if secret(a) then
            say("aura " .. i .. ": <secret>")
            ids[#ids + 1] = "<secret>"
        elseif a == nil then
            break
        else
            say(("aura %d: id %s, %s, duration %s"):format(i, Show(a.spellId), Show(a.name), Show(a.duration)))
            ids[#ids + 1] = Show(a.spellId, true)
        end
    end
    return table.concat(ids, " ")
end

-- What the Utility bar thinks and shows: its campfire state, and the camping
-- buttons on screen.
local function barState()
    local U = utility()
    if not U then say("Glass Action Bars isn't loaded: no Utility bar to read") return "no GAB" end
    local shown = {}
    for _, a in ipairs(U.CAMPING) do
        local b = rawget(_G, U.PREFIX .. a.key)
        if b and b:IsShown() == true then shown[#shown + 1] = a.key end
    end
    local near = U.NearCampfire and U.NearCampfire()
    say("Utility bar: near a campfire " .. Show(near) .. "; camping buttons shown: "
        .. (#shown > 0 and table.concat(shown, ", ") or "none"))
    return near, table.concat(shown, ",")
end

local function readAll()
    local a = aura()
    say("campfire buff " .. AURA .. ": " .. Show(a))
    local ids = listAuras()
    local near, shown = barState()
    return a, ids, near, shown
end

-- Every carried camping item: count, cooldown (start, duration), use spell.
-- Returns how many carried features (not kits) are cooling down, how many are
-- carried, the ready ones' keys (a list) and the cooling ones' (a set). A
-- secret duration is neither.
local function readCamping()
    local U = utility()
    if not U then say("Glass Action Bars isn't loaded: no camping list") return 0, 0, {}, {} end
    local cooling, carried, ready, coolingKeys = 0, 0, {}, {}
    for _, a in ipairs(U.CAMPING) do
        local ok, n = pcall(C_Item.GetItemCount, a.item)
        n = ok and not secret(n) and n or 0
        if n > 0 then
            local _, start, dur = pcall(C_Container.GetItemCooldown, a.item)
            local _, _, spell = pcall(C_Item.GetItemSpell, a.item)
            say(("%s (%d) x%d: cooldown start %s, duration %s; use spell %s"):format(a.label, a.item, n,
                Show(start), Show(dur), Show(spell)))
            if not a.kit then
                carried = carried + 1
                if not secret(dur) and type(dur) == "number" then
                    if dur > 1.5 then
                        cooling = cooling + 1
                        coolingKeys[a.key] = true
                    else
                        ready[#ready + 1] = a.key
                    end
                end
            end
        end
    end
    say(("camp features carried: %d, cooling down: %d"):format(carried, cooling))
    return cooling, carried, ready, coolingKeys
end

-- Shared cooldowns, by a transition: the features ready by the fire (the
-- baseline), then which of them cool down once one is placed. True: all of
-- them (shared); false: only some (independent); nil: not measurable.
local baseline
local function takeBaseline()
    baseline = select(3, readCamping())
    say("ready camp features (the baseline): " .. (#baseline > 0 and table.concat(baseline, ", ") or "none"))
    return #baseline
end

local function cooldownVerdict()
    local _, _, readyNow, coolingKeys = readCamping()
    if not baseline or #baseline < 2 then
        return nil, "inconclusive: fewer than two ready features by the fire"
    end
    local isReady = {}
    for _, k in ipairs(readyNow) do isReady[k] = true end
    -- Every baseline feature must read plainly as cooling or ready: one
    -- unreadable (secret, refused, no longer carried) could be either.
    local started = 0
    for _, k in ipairs(baseline) do
        if coolingKeys[k] then started = started + 1
        elseif not isReady[k] then return nil, "inconclusive: " .. k .. "'s cooldown unreadable after placing" end
    end
    if started == 0 then return nil, "inconclusive: none of the ready features is cooling (was one placed?)" end
    if started == #baseline then return true, "shared: all " .. started .. " ready features started cooling" end
    return false, "independent: " .. started .. " of " .. #baseline .. " ready features cooling"
end

Probe:Command("aura", function() readAll() end, "the campfire buff, every helpful aura, the Utility bar")
Probe:Command("camping", function() readCamping() end, "every carried camping item and its cooldown")
Probe:Command("clear", function() Probe:ClearLog(); say("log cleared") end, "empty the saved log")

Probe:Steps("campfire", {
    title = "The campfire buff and camping cooldowns (#9)",
    { text = "Carry two or more different camp features (Camp Chair, Fish Bowl...) that aren't cooling down, "
        .. "and a campfire kit if you have one. Stand away from any campfire, then press Read.",
      button = "Read", run = readAll,
      check = function() return aura() == false, "the buff is absent away from a fire" end },
    { text = "Go to a campfire (light your kit, or walk to any campfire) and stand next to it. This step "
        .. "completes when buff " .. AURA .. " shows. If it doesn't within a minute by the fire, press Done.",
      wait = function() return aura() == true, "buff " .. AURA .. " not on you yet" end, timeout = 300 },
    { text = "Reading every buff on you, the Utility bar and your camping items, by the fire.", auto = true,
      run = function()
          local a, ids, near, shown = readAll()
          return a, ids, near, shown, takeBaseline()
      end,
      check = function() return aura() == true, "buff " .. AURA .. " by the fire" end },
    { text = "Does the Utility bar show your camp features now?", ask = true, screenshot = "Utility bar by the fire" },
    { text = "Place one camp feature (from the bar or your bags), then press Read.", button = "Read",
      -- The result says shared, independent or inconclusive; PASS = a conclusive measurement.
      run = cooldownVerdict,
      check = function()
          local v, detail = cooldownVerdict()
          return v ~= nil, detail
      end },
    { text = "Walk away from the campfire. This step completes when the buff is gone.",
      wait = function() return aura() == false, "buff " .. AURA .. " still on you" end, timeout = 300 },
    { text = "Reading again, away from the fire.", auto = true, run = readAll,
      check = function()
          local U = utility()
          return aura() == false and not (U and U.NearCampfire()), "the buff gone, and the bar knows"
      end },
    { text = "Did the camp features leave the Utility bar (a campfire kit stays)?", ask = true,
      screenshot = "Utility bar away from the fire" },
    { text = "Press Reload now (or type /reload) to save the results.", reload = true },
})

-- ------------------------------------------------------------------
-- barmove (#30): GAB's Follow.lua moves the stance and pet bars as Glass
-- Unit Frames would (Follow.SetOffsets, a made-up move), and this measures
-- where the bars really are, across Edit Mode, a pet summon, a fight, a UI
-- scale change, an edited and a cancelled layout and a /reload. The host logs
-- ADDON_ACTION_BLOCKED; Logs\taint.log is read from disk afterwards.
-- ------------------------------------------------------------------

local MOVE = 120
local BARS = { "StanceBar", "PetActionBar" }
local follow = function() local g = rawget(_G, "GlassActionBars"); return g and g.Follow end
local fights, fightMark = 0, nil   -- fights ended; the count when the fight step began

-- A bar's left edge in UIParent units, or nil (absent, hidden, secret).
local function left(name)
    local bar = rawget(_G, name)
    if not bar then return nil end
    local v = bar:IsVisible()
    if secret(v) or v ~= true then return nil end
    local l, s, ui = bar:GetLeft(), bar:GetEffectiveScale(), UIParent:GetEffectiveScale()
    if secret(l) or secret(s) or secret(ui) or type(l) ~= "number" then return nil end
    return l * s / ui
end

local function readBars()
    local out = {}
    for _, name in ipairs(BARS) do
        local bar = rawget(_G, name)
        if not bar then say(name .. ": absent") else
            local _, base = Probe:Try(name .. ".IsShownBase", bar.IsShownBase, bar)
            local _, default = Probe:Try(name .. ".IsInDefaultPosition", bar.IsInDefaultPosition, bar)
            local n = bar:GetNumPoints()
            local p, rel, rp, x, y = bar:GetPoint(1)
            local relName = type(rel) == "table" and not secret(rel) and rel.GetName and rel:GetName() or rel
            say(("%s: shown %s, shownBase %s, visible %s, default position %s, %s point(s): %s %s %s %s %s; "
                .. "left %s, scale %s, effective %s"):format(name, Show(bar:IsShown()), Show(base),
                Show(bar:IsVisible()), Show(default), Show(n), Show(p), Show(relName), Show(rp), Show(x), Show(y),
                Show(left(name)), Show(bar:GetScale()), Show(bar:GetEffectiveScale())))
            out[#out + 1] = name .. (left(name) and "" or " (not shown)")
        end
    end
    local F = follow()
    if F then
        local s = F.Status()
        say("GAB follow: stance bar " .. s.StanceBar .. "; pet bar " .. s.PetActionBar)
    else
        say("GAB's Follow isn't loaded")
    end
    return table.concat(out, ", ")
end

local function lefts()
    local t = {}
    for _, name in ipairs(BARS) do t[name] = left(name) end
    return t
end

-- How far each shown bar really is from its Edit Mode position: read it,
-- put the bars back, read again, move them again. Out of combat.
local function displacement()
    local F = follow()
    if not F then return nil, "GAB's Follow isn't loaded" end
    local cur = lefts()
    F.SetOffsets(0, 0)
    local back = lefts()
    F.SetOffsets(MOVE, MOVE)
    local d, parts = {}, {}
    for _, name in ipairs(BARS) do
        if cur[name] and back[name] then
            d[name] = cur[name] - back[name]
            parts[#parts + 1] = ("%s %+.1f"):format(name, d[name])
        end
    end
    return d, table.concat(parts, ", ")
end

-- Every shown bar MOVE from its place (a bar snapped to the other one is skipped).
local function moved()
    local d, text = displacement()
    if not d then return false, text end
    local F, any = follow(), false
    for _, name in ipairs(BARS) do
        if d[name] then
            any = true
            local snapped = F.Status()[name]:find("anchored to", 1, true)
            if not snapped and math.abs(d[name] - MOVE) > 1 then return false, text end
        end
    end
    if not any then return false, "no bar shown" end
    return true, text
end

local function editModeShown()
    local f = rawget(_G, "EditModeManagerFrame")
    local v = f and f:IsShown()
    return not secret(v) and v == true
end

local L0, L1 = {}, {}   -- the bars' places at the start; the saved layout's
local function near(a, b) return a ~= nil and b ~= nil and math.abs(a - b) <= 1 end
local function atPlaces(places)
    local now, parts, ok = lefts(), {}, true
    for _, name in ipairs(BARS) do
        if places[name] then
            parts[#parts + 1] = ("%s %s vs %s"):format(name, Show(now[name]), Show(places[name]))
            ok = ok and near(now[name], places[name])
        end
    end
    return ok, table.concat(parts, ", ")
end

Probe:Command("bars", function() readBars() end, "the stance and pet bars: anchors, scale, GAB's follow state")

Probe:Steps("barmove", {
    title = "The stance and pet bars follow Glass Unit Frames (#30)",
    { text = "Use a character with its pet out, and a stance bar if it has one. Turn off Glass Unit Frames' link "
        .. "(or don't load GUF). Type /console taintLog 1, then press Reload now.", reload = true },
    { text = "Reading both bars.", auto = true,
      run = function() local r = readBars(); L0 = lefts(); return r end,
      check = function() return follow() ~= nil and next(lefts()) ~= nil, "GAB's Follow loaded, a bar shown" end },
    { text = "Press Move: GAB moves the stance and pet bars " .. MOVE .. " to the right, as Glass Unit Frames would.",
      button = "Move", run = function() follow().SetOffsets(MOVE, MOVE); return readBars() end, check = moved,
      screenshot = "bars moved" },
    { text = "Did the bars move right, buttons and glass together, nothing left behind?", ask = true },
    { text = "Open Edit Mode (Esc > Edit Mode).", wait = function() return editModeShown(), "Edit Mode not open" end,
      timeout = 300, check = function() return atPlaces(L0) end },
    { text = "Close Edit Mode without changing anything.",
      wait = function() return not editModeShown(), "Edit Mode still open" end, timeout = 300, check = moved },
    { text = "Dismiss your pet, then summon it again (out of combat). Press Next once it's back.", check = moved },
    { text = "Fight something. In the fight, click pet bar buttons and a stance, press their key bindings, and "
        .. "dismiss and summon the pet if you can. This step completes when the fight is over.",
      wait = function()
          fightMark = fightMark or fights
          return fights > fightMark and not InCombatLockdown(), "waiting for a fight to start and end"
      end,
      timeout = 900, check = moved },
    { text = "During the fight, did anything say an action was blocked, or did a pet or stance button not work?",
      ask = true },
    { text = "Change the UI scale a little (Esc > Options > Graphics > UI Scale), then press Next.", check = moved,
      screenshot = "after a UI scale change" },
    { text = "Open Edit Mode again.", wait = function() return editModeShown(), "Edit Mode not open" end,
      timeout = 300 },
    { text = "Move the pet bar (or the stance bar) somewhere else, press Save, and close Edit Mode.",
      wait = function() return not editModeShown(), "Edit Mode still open" end, timeout = 600, check = moved },
    { text = "Open Edit Mode once more.", wait = function() return editModeShown(), "Edit Mode not open" end,
      timeout = 300,
      check = function() L1 = lefts(); return next(L1) ~= nil, "the saved places recorded" end },
    { text = "Move the bar again, then close Edit Mode WITHOUT saving (discard the change).",
      wait = function() return not editModeShown(), "Edit Mode still open" end, timeout = 600,
      check = function()
          local ok, text = moved()
          local places = {}
          for name, l in pairs(L1) do places[name] = l + MOVE end
          local at, where = atPlaces(places)
          return ok and at, text .. "; " .. where
      end },
    { text = "Press Put back: the bars return to their Edit Mode places.", button = "Put back",
      run = function() follow().SetOffsets(0, 0); return readBars() end,
      check = function()
          local ok, text = atPlaces(L1)
          GABProbeDB.barmoveSaved = lefts()
          return ok, text
      end },
    { text = "Press Reload now.", reload = true },
    { text = "Reading the bars after the reload: they should be at the saved layout's places.", auto = true,
      run = readBars,
      check = function() return atPlaces(type(GABProbeDB.barmoveSaved) == "table" and GABProbeDB.barmoveSaved or {}) end },
    { text = "Type /reload (or press Reload now) to save the results.", reload = true },
})

local boot = CreateFrame("Frame")
Probe:RegisterEvents(boot, { "ADDON_LOADED", "PLAYER_REGEN_ENABLED" })
boot:SetScript("OnEvent", function(_, event, name)
    if event == "PLAYER_REGEN_ENABLED" then fights = fights + 1 return end
    if name ~= ADDON then return end
    Probe:Ready()
    -- The standalone probe's saved table had another shape: start afresh.
    if type(GABProbeDB) ~= "table" or GABProbeDB.module ~= 1 then GABProbeDB = { module = 1 } end
    if type(GABProbeDB.log) ~= "table" then GABProbeDB.log = {} end
    Probe:UseLog(GABProbeDB.log, MAX_LOG)
    GABProbeDB.loads = (GABProbeDB.loads or 0) + 1
    say("loaded (" .. GABProbeDB.loads .. " loads). /fp steps gab campfire, or /fp gab for the commands")
end)

NS._test = { Probe = Probe, aura = aura, readAll = readAll, readCamping = readCamping,
    takeBaseline = takeBaseline, cooldownVerdict = cooldownVerdict }
