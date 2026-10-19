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
        if a == nil then break end
        if secret(a) then
            say("aura " .. i .. ": <secret>")
            ids[#ids + 1] = "<secret>"
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
-- Returns how many carried features (not kits) are cooling down, and how many
-- are carried.
local function readCamping()
    local U = utility()
    if not U then say("Glass Action Bars isn't loaded: no camping list") return 0, 0 end
    local cooling, carried = 0, 0
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
                if not secret(dur) and type(dur) == "number" and dur > 1.5 then cooling = cooling + 1 end
            end
        end
    end
    say(("camp features carried: %d, cooling down: %d"):format(carried, cooling))
    return cooling, carried
end

Probe:Command("aura", function() readAll() end, "the campfire buff, every helpful aura, the Utility bar")
Probe:Command("camping", function() readCamping() end, "every carried camping item and its cooldown")
Probe:Command("clear", function() Probe:ClearLog(); say("log cleared") end, "empty the saved log")

Probe:Steps("campfire", {
    title = "The campfire buff and camping cooldowns (#9)",
    { text = "Carry two or more different camp features (Camp Chair, Fish Bowl...) and a campfire kit if you "
        .. "have one. Stand away from any campfire, then press Read.", button = "Read", run = readAll,
      check = function() return aura() == false, "the buff is absent away from a fire" end },
    { text = "Go to a campfire (light your kit, or walk to any campfire) and stand next to it. This step "
        .. "completes when buff " .. AURA .. " shows. If it doesn't within a minute by the fire, press Done.",
      wait = function() return aura() == true, "buff " .. AURA .. " not on you yet" end, timeout = 300 },
    { text = "Reading every buff on you, the Utility bar and your camping items, by the fire.", auto = true,
      run = function()
          local a, ids, near, shown = readAll()
          readCamping()
          return a, ids, near, shown
      end,
      check = function() return aura() == true, "buff " .. AURA .. " by the fire" end },
    { text = "Does the Utility bar show your camp features now?", ask = true, screenshot = "Utility bar by the fire" },
    { text = "Place one camp feature (from the bar or your bags), then press Read.", button = "Read",
      run = readCamping,
      check = function()
          local cooling, carried = readCamping()
          if carried < 2 then return false, "only " .. carried .. " feature carried: can't tell" end
          return cooling == carried, cooling .. " of " .. carried .. " features cooling down (all = shared)"
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

local boot = CreateFrame("Frame")
Probe:RegisterEvents(boot, { "ADDON_LOADED" })
boot:SetScript("OnEvent", function(_, _, name)
    if name ~= ADDON then return end
    Probe:Ready()
    -- The standalone probe's saved table had another shape: start afresh.
    if type(GABProbeDB) ~= "table" or GABProbeDB.module ~= 1 then GABProbeDB = { module = 1 } end
    if type(GABProbeDB.log) ~= "table" then GABProbeDB.log = {} end
    Probe:UseLog(GABProbeDB.log, MAX_LOG)
    GABProbeDB.loads = (GABProbeDB.loads or 0) + 1
    say("loaded (" .. GABProbeDB.loads .. " loads). /fp steps gab campfire, or /fp gab for the commands")
end)

NS._test = { Probe = Probe, aura = aura, readAll = readAll, readCamping = readCamping }
