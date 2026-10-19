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
-- Also barmove (#30), look (#34), pearl (#44), icons (#46), dock (#53) and micro (#57): /fp steps gab <name>.
-- Commands: /fp gab aura, camping, bars, dock, bagsbar, micro, clear.

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
local editModeShown
local function moved()
    if editModeShown() then return false, "Edit Mode is still open: close it, then Retry" end
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

function editModeShown()
    local f = rawget(_G, "EditModeManagerFrame")
    local v = f and f:IsShown()
    return not secret(v) and v == true
end

local L0, L1 = {}, {}   -- the bars' places at the start; the saved layout's
local function near(a, b) return a ~= nil and b ~= nil and math.abs(a - b) <= 1 end
-- (A bar hidden now is skipped: Edit Mode shows bars that are hidden outside it.)
local function atPlaces(places)
    local now, parts, ok = lefts(), {}, true
    for _, name in ipairs(BARS) do
        if places[name] and now[name] then
            parts[#parts + 1] = ("%s %s vs %s"):format(name, Show(now[name]), Show(places[name]))
            ok = ok and near(now[name], places[name])
        end
    end
    return ok, table.concat(parts, ", ")
end

-- Each bar's one anchor as text (shown or not), to compare across a /reload.
local function anchors()
    local t = {}
    for _, name in ipairs(BARS) do
        local bar = rawget(_G, name)
        local n = bar and bar:GetNumPoints()
        if n ~= nil and not secret(n) and n == 1 then
            local p, rel, rp, x, y = bar:GetPoint(1)
            if not (secret(p) or secret(rel) or secret(rp) or secret(x) or secret(y)) then
                local relName = type(rel) == "table" and rel.GetName and rel:GetName() or tostring(rel)
                t[name] = ("%s %s %s %.1f %.1f"):format(tostring(p), tostring(relName), tostring(rp), x, y)
            end
        end
    end
    return t
end

local function sameAnchors(saved)
    local now, parts, ok, any = anchors(), {}, true, false
    for name, a in pairs(saved) do
        any = true
        parts[#parts + 1] = name .. ": " .. tostring(now[name]) .. " vs " .. a
        ok = ok and now[name] == a
    end
    return ok and any, table.concat(parts, "; ")
end

Probe:Command("bars", function() readBars() end, "the stance and pet bars: anchors, scale, GAB's follow state")

Probe:Steps("barmove", {
    rev = 3,
    title = "The stance and pet bars follow Glass Unit Frames (#30)",
    { text = "Use a character with its pet out, and a stance bar if it has one. Turn off Glass Unit Frames' link "
        .. "(or don't load GUF). Type /console taintLog 1, then press Reload now.", reload = true },
    { text = "Reading both bars.", auto = true,
      run = readBars,
      check = function() return follow() ~= nil, "GAB's Follow loaded" end },
    { text = "Press Move: GAB moves the stance and pet bars " .. MOVE .. " to the right, as Glass Unit Frames would.",
      button = "Move", run = function() L0 = lefts(); follow().SetOffsets(MOVE, MOVE); return readBars() end,
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
          GABProbeDB.barmoveSaved = anchors()
          return ok, text
      end },
    { text = "Press Reload now.", reload = true },
    { text = "Reading the bars after the reload: they should be at the saved layout's places.", auto = true,
      run = readBars,
      check = function() return sameAnchors(type(GABProbeDB.barmoveSaved) == "table" and GABProbeDB.barmoveSaved or {}) end },
    { text = "Type /reload (or press Reload now) to save the results.", reload = true },
})

-- ------------------------------------------------------------------
-- look (#34): the button feedback in game, the Soft preset: the halo on a
-- hovered button, the ripple on a click, the flash on a key press, the key
-- text above the buttons, faint empty slots; on every family, in a fight.
-- ------------------------------------------------------------------

local function buttons() local g = rawget(_G, "GlassActionBars"); return g and g.Buttons end
local function settings() local g = rawget(_G, "GlassActionBars"); return g and g.Settings end

-- A skinned button under the pointer, and its halo's alpha.
local function hovered()
    local B, found = buttons(), nil
    if not B then return nil end
    B.Each(function(s)
        local v = s.button:IsMouseOver()
        if not found and not secret(v) and v == true and s.button:IsVisible() == true then found = s end
    end)
    return found
end

local lookFights, lookMark = 0, nil
Probe:Steps("look", {
    title = "Button feedback, the Soft preset (#34)",
    { text = "Press Soft: GAB switches to its Soft look (halo, ripple, faint empty slots).",
      button = "Soft", run = function() settings().SetLookPreset("soft"); return buttons().Preset() end,
      check = function() return buttons().Preset() == "soft", "the Soft preset" end,
      screenshot = "the Soft look" },
    { text = "Point at an action button with something on it and keep the pointer there.",
      wait = function()
          local s = hovered()
          if not s then return false, "no button under the pointer" end
          return s.halo and s.halo:GetAlpha() > 0.9, "halo alpha " .. Show(s.halo and s.halo:GetAlpha())
      end, timeout = 120, screenshot = "the halo" },
    { text = "Did a warm halo fade in round the button, and fade out when you moved away?", ask = true },
    { text = "Click an action button with the mouse (out of combat). Did a soft circle swell from the pointer and fade?",
      ask = true },
    { text = "Press one of your action bar key bindings. Did that button flash?", ask = true },
    { text = "Are the empty slots faint, and the bag slots unchanged?", ask = true },
    { text = "Do the stance or pet buttons and the Utility bar show the same halo and ripple?", ask = true },
    { text = "Fight something: point at buttons, click them and press their keys in the fight. This step completes "
        .. "when the fight is over.",
      wait = function()
          lookMark = lookMark or lookFights
          return lookFights > lookMark and not InCombatLockdown(), "waiting for a fight to start and end"
      end, timeout = 900 },
    { text = "In the fight, did the halo, ripple and flash work, with nothing saying an action was blocked?",
      ask = true },
    { text = "Press Glass to go back to today's look, or Skip to keep Soft.", button = "Glass",
      run = function() settings().SetLookPreset("glass"); return buttons().Preset() end },
    { text = "Press Reload now to save the results.", reload = true },
})

-- ------------------------------------------------------------------
-- pearl (#44): Pearl's face in game. The reflection sits on the rim's frame,
-- over the cooldown sweep like the rim: is a cooldown still readable under it
-- (Pearl's gloss against 0)? A proc glow is a child of the button at our level
-- (ActionButtonSpellAlerts), its order against the reflection unmeasured: the
-- same pair of shots. The recessed empty socket, and the 30 px buttons.
-- ------------------------------------------------------------------

local function gab() return rawget(_G, "GlassActionBars") end
local function tunes()
    local out = {}
    for _, k in ipairs(buttons().TUNE_ORDER) do out[#out + 1] = k .. " " .. Show(buttons().Tune(k)) end
    return table.concat(out, ", ")
end
local savedGloss

Probe:Steps("pearl", {
    title = "Pearl's face: the reflection and the socket (#44)",
    { text = "Reading the material and the glass's numbers.", auto = true,
      run = function()
          local t = rawget(gab().db, "tune")
          savedGloss = type(t) == "table" and t.gloss or nil
          return gab().GlassPreset, tunes()
      end,
      check = function() return gab().GlassPreset == "pearl", "Pearl built (else: Glass UI's material, or /gab material pearl and reload)" end },
    { text = "Your own /gab tune numbers win over Pearl's. Press Reset to clear them and see Pearl's, or Skip to keep yours.",
      button = "Reset", run = function()
          for _, k in ipairs(buttons().TUNE_ORDER) do settings().SetTune(k, nil) end
          savedGloss = nil
          return tunes()
      end },
    { text = "Look at an empty slot: a grey tile with a dark top edge and a light bottom lip, no raised rim?",
      ask = true, screenshot = "empty sockets and filled buttons" },
    { text = "Filled buttons: a soft reflection over the top of each icon, the icon still clear?", ask = true },
    { text = "Use an ability or item with a cooldown of 20 s or more, then press Shot while it shows.",
      button = "Shot", run = function() settings().SetTune("gloss", buttons().PEARL.gloss); return "gloss " .. Show(buttons().Tune("gloss")) end,
      screenshot = "a cooldown under the reflection" },
    { text = "Press No gloss (while it still shows): the same view without the reflection.",
      button = "No gloss", run = function() settings().SetTune("gloss", 0); return "gloss 0" end,
      screenshot = "a cooldown without the reflection" },
    { text = "Was the cooldown sweep as easy to read with the reflection as without it?", ask = true },
    { text = "If your class has a proc that makes a button glow (else Skip both), get it to glow, then press Shot while it shows.",
      button = "Shot", run = function() settings().SetTune("gloss", buttons().PEARL.gloss); return "gloss " .. Show(buttons().Tune("gloss")) end,
      screenshot = "a proc glow under the reflection" },
    { text = "Press No gloss (while it still shows): the same view without the reflection.",
      button = "No gloss", run = function() settings().SetTune("gloss", 0); return "gloss 0" end,
      screenshot = "a proc glow without the reflection" },
    { text = "Was the proc glow as bright with the reflection as without it (Not sure if you skipped it)?", ask = true },
    { text = "Press Gloss for Pearl's reflection while you look at the rest.", button = "Gloss",
      run = function() settings().SetTune("gloss", buttons().PEARL.gloss); return "gloss " .. Show(buttons().Tune("gloss")) end },
    { text = "An out-of-range or unusable icon, a checked (active) button, the key and count text, and a stun "
        .. "or silence if one came your way: all still plain under the reflection?", ask = true },
    { text = "The stance or pet buttons (the small ones): the reflection, the empty socket, the pet's autocast "
        .. "ring, all right at that size?", ask = true, screenshot = "the small buttons" },
    { text = "Putting your own reflection setting back.", auto = true,
      run = function() settings().SetTune("gloss", savedGloss); return "gloss " .. Show(buttons().Tune("gloss")) end },
    { text = "Press Reload now to save the results.", reload = true },
})

-- ------------------------------------------------------------------
-- icons (#46): the Utility bar's and a provider's icons rounded by a mask
-- stretched over the icon (its corner grows with the size), the rim sliced
-- (its corner fixed): do they agree at 16, 32, 45 and 64? A cooldown's
-- square swipe over a rounded icon. Undocked Utility bar: its own size.
-- ------------------------------------------------------------------

local savedSize
local function utilitySize(v)
    return function()
        if v then settings().SetUtilityLayout("iconSize", v) else
            local u = rawget(gab().db, "utility")
            if type(u) == "table" then u.iconSize = savedSize end
            gab().Utility.Reconcile()
        end
        return "iconSize " .. Show(gab().Utility.LayoutSetting("iconSize"))
    end
end

local iconSteps = {
    title = "Rounded icons on the Utility bar and Apotheca (#46)",
    { text = "Reading the Utility bar's size.", auto = true,
      run = function()
          local u = rawget(gab().db, "utility")
          savedSize = type(u) == "table" and u.iconSize or nil
          return "iconSize " .. Show(gab().Utility.LayoutSetting("iconSize")), "dock " .. Show(gab().Dock.Setting("utility", "bar"))
      end,
      check = function() return gab().Dock.Setting("utility", "bar") == false, "the Utility bar undocked (else it takes the bar's size)" end },
}
for _, size in ipairs({ 16, 32, 45, 64 }) do
    iconSteps[#iconSteps + 1] = { text = "Press Size " .. size .. ": the Utility bar's icons at " .. size
        .. ". Are the icon's corners inside the rim's, with no square corner and no gap?", button = "Size " .. size,
        run = utilitySize(size), screenshot = "Utility icons at " .. size }
    iconSteps[#iconSteps + 1] = { text = "At " .. size .. ": the icon's corners follow the rim?", ask = true }
end
for _, step in ipairs({
    { text = "Putting your Utility bar's size back.", auto = true, run = utilitySize(nil) },
    { text = "Use your Hearthstone (or anything on the Utility bar with a cooldown), then press Shot.", button = "Shot",
      run = function() return "shot" end, screenshot = "a cooldown over a rounded icon" },
    { text = "Is the cooldown's square swipe acceptable over the rounded icon?", ask = true },
    { text = "Apotheca's buttons: rounded icons, no square corners past the rim?", ask = true,
      screenshot = "Apotheca's icons" },
    { text = "Press Reload now to save the results.", reload = true },
}) do iconSteps[#iconSteps + 1] = step end
Probe:Steps("icons", iconSteps)

-- ------------------------------------------------------------------
-- dock (#53): a docked bar sits ~7 px off the target bar's rows. Dock.lua
-- places by the union of the bar's shownButtonContainers; this logs, in
-- UIParent units, the bar, each shown container beside its button, that
-- union, and each docked client's frame beside its shown buttons, so the
-- offset can be pinned on one of them.
-- ------------------------------------------------------------------

local function plain(v) if not secret(v) and type(v) == "number" then return v end end

-- A frame's rect in UIParent units, { l, r, t, b }, or nil (unreadable).
local function rectOf(f)
    if not f then return nil end
    local ok, s, l, r, t, b = pcall(function() return f:GetEffectiveScale(), f:GetLeft(), f:GetRight(), f:GetTop(), f:GetBottom() end)
    local ui = plain(UIParent:GetEffectiveScale())
    s, l, r, t, b = plain(s), plain(l), plain(r), plain(t), plain(b)
    if not (ok and ui and s and l and r and t and b) then return nil end
    local k = s / ui
    return { l * k, r * k, t * k, b * k }
end

local function fmt(r)
    if not r then return "unreadable" end
    return ("L %.1f R %.1f T %.1f B %.1f (%.1f x %.1f)"):format(r[1], r[2], r[3], r[4], r[2] - r[1], r[3] - r[4])
end

local function grow(u, r)
    if not r then return u end
    if not u then return { r[1], r[2], r[3], r[4] } end
    return { math.min(u[1], r[1]), math.max(u[2], r[2]), math.max(u[3], r[3]), math.min(u[4], r[4]) }
end

-- Distinct row tops, rounded to 0.1, high to low: "T1 / T2 ...".
local function rowTops(rects)
    local seen, tops = {}, {}
    for _, r in ipairs(rects) do
        local t = math.floor(r[3] * 10 + 0.5) / 10
        if not seen[t] then seen[t] = true; tops[#tops + 1] = t end
    end
    table.sort(tops, function(a, b) return a > b end)
    for i, t in ipairs(tops) do tops[i] = ("%.1f"):format(t) end
    return table.concat(tops, " / ")
end

-- One docked client against its bar. Returns a one-line summary.
local function readClient(id)
    local D = gab().Dock
    local n = D.Setting(id, "bar")
    if not n then say(id .. ": not docked") return id .. " not docked" end
    local names = D.BARS[n]
    local bar = rawget(_G, names[1])
    say(("%s: docked to bar %d (%s), side %s, align %s, gap %s, match %s, rows %s, hosted %s"):format(id, n, names[1],
        Show(D.Setting(id, "side")), Show(D.Setting(id, "align")), Show(D.Setting(id, "gap")),
        Show(D.Setting(id, "match")), Show(D.Setting(id, "matchRows")), Show(D.IsHosted(id))))
    say("  bar frame " .. fmt(rectOf(bar)))
    local buttons, btnRects = nil, {}
    local list = bar and bar.shownButtonContainers
    for i, c in ipairs(type(list) == "table" and list or {}) do
        local cr = rectOf(c)
        local cname = Show(c.GetName and c:GetName())
        -- The container's own button (ActionBar.lua:30: its child, centred, with .container).
        local btn
        for j = 1, 12 do
            local b = rawget(_G, names[2] .. j)
            if b and (b.container == c or b:GetParent() == c) then btn = b break end
        end
        local br = rectOf(btn)
        if br then buttons = grow(buttons, br); btnRects[#btnRects + 1] = br end
        local d = (cr and br) and ("  dL %.1f dT %.1f"):format(br[1] - cr[1], br[3] - cr[3]) or ""
        say(("  container %d %s %s; button %s %s%s"):format(i, cname, fmt(cr), Show(btn and btn:GetName()), fmt(br), d))
    end
    local union = D.TargetRect(n)
    local ur = union and { union.left, union.right, union.top, union.bottom }
    say("  containers' union (the dock's target) " .. fmt(ur))
    say("  buttons' union " .. fmt(buttons) .. "; button row tops " .. rowTops(btnRects))
    local frame   -- Dock.Frames() is in Dock.Clients() order
    for i, c in ipairs(D.Clients()) do if c.id == id then frame = D.Frames()[i] end end
    local g = frame and D.Geometry(n, frame)
    if g then say(("  geometry (client units): size %.2f padding %.2f rows %s orientation %s"):format(g.size, g.padding, Show(g.rows), Show(g.orientation))) end
    local fr = rectOf(frame)
    say("  client frame " .. Show(frame and frame:GetName()) .. " " .. fmt(fr))
    -- Every shown child logged; the buttons' union is what lines up with the bar.
    local kids, kidRects = nil, {}
    for _, k in ipairs(frame and { frame:GetChildren() } or {}) do
        if k:IsShown() == true then
            local kr, kind = rectOf(k), k:GetObjectType()
            say(("  client child %s %s %s"):format(Show(k:GetName()), kind, fmt(kr)))
            if kr and (kind == "Button" or kind == "CheckButton") then kids = grow(kids, kr); kidRects[#kidRects + 1] = kr end
        end
    end
    say("  client buttons' union " .. fmt(kids) .. "; row tops " .. rowTops(kidRects))
    local summary = id .. ": target " .. fmt(ur) .. "; buttons " .. fmt(buttons) .. "; client " .. fmt(fr)
        .. "; client buttons " .. fmt(kids)
    if buttons and kids then
        summary = summary .. ("; client buttons top - bar buttons top %.1f, client left - bar buttons right %.1f"):format(kids[3] - buttons[3], kids[1] - buttons[2])
    end
    return summary
end

local function readDock()
    local D = gab() and gab().Dock
    if not D then say("Glass Action Bars isn't loaded") return "no GAB" end
    say(("UIParent scale %s"):format(Show(UIParent:GetEffectiveScale())))
    local out = {}
    for _, c in ipairs(D.Clients()) do out[#out + 1] = readClient(c.id) end
    if #out == 0 then say("no dock clients registered") end
    return table.concat(out, " || ")
end

local function anyDocked()
    local D = gab() and gab().Dock
    for _, c in ipairs(D and D.Clients() or {}) do
        if D.Setting(c.id, "bar") and D.IsHosted(c.id) then return true end
    end
    return false, "nothing docked yet"
end

Probe:Command("dock", function() readDock() end, "each docked bar against its target: containers, buttons, frames")

-- bagsbar (#55): BagsBar:Layout (re-run on every cursor change) called a nil
-- UpdateDividers. What the bar's methods are now, raw and inherited, who
-- tainted them, and Layout run once under pcall (out of combat: it moves the
-- bag buttons).
local function readBagsBar()
    local bar, mixin = rawget(_G, "BagsBar"), rawget(_G, "BagsBarMixin")
    if not bar then say("no BagsBar") return "no BagsBar" end
    local out = {}
    for _, m in ipairs({ "UpdateDividers", "Layout", "IsHorizontal", "ShouldShowExpandToggle" }) do
        local secure, taint = issecurevariable(bar, m)
        local line = ("%s: raw %s, via frame %s, mixin %s, secure %s %s"):format(m, type(rawget(bar, m)), type(bar[m]),
            type(mixin and mixin[m]), Show(secure), Show(taint))
        say("BagsBar." .. line)
        out[#out + 1] = line
    end
    say("BagsBar.useDividers " .. Show(bar.useDividers) .. ", the same mixin function: "
        .. Show(mixin ~= nil and rawget(bar, "IsHorizontal") == mixin.IsHorizontal))
    if InCombatLockdown() then say("in combat: Layout not run") return table.concat(out, "; ") end
    local ok, err = pcall(bar.Layout, bar)
    say("BagsBar:Layout() " .. (ok and "ran" or ("ERROR " .. tostring(err))))
    out[#out + 1] = ok and "Layout ran" or ("Layout ERROR " .. tostring(err))
    return table.concat(out, "; ")
end
Probe:Command("bagsbar", function() readBagsBar() end, "the bag bar's methods and a Layout run (#55)")

Probe:Steps("dock", {
    title = "A docked bar against the action bar's rows (#53)",
    { text = "Dock Apotheca (or the Utility bar) to Action Bar 1 the way you saw the offset, with Edit Mode "
        .. "closed. This step completes when something is docked.",
      wait = anyDocked, timeout = 300 },
    { text = "Reading the bar, its containers and buttons, and each docked bar.", auto = true, run = readDock,
      screenshot = "docked bars" },
    { text = "Does the docked bar line up with the action bar's rows and edge? (Note what's off, and by how much.)",
      ask = true },
    { text = "The bag bar error (#55): pick up an item from your bags and put it back, then press Read.",
      button = "Read", run = readBagsBar },
    { text = "Press Reload now to save the results.", reload = true },
})



-- ------------------------------------------------------------------
-- micro (#57): the micro buttons' bronze frame is in their state atlases
-- (UI-HUD-MicroMenu-<name>-Up/-Down/-Disabled/-Mouseover), behind them a
-- Background (ButtonBG); the empty bag slots and the key ring show a greyed
-- icon. Logged: each atlas's size and coords, each bag slot's icon. Tried, in
-- memory only (a /reload undoes it): each state texture cropped by an inset
-- inside its atlas, the Background faded; the bag slots' icons faded. Blizzard
-- sets the atlases again on hover and on state changes, so the pointer stays
-- off the micro menu for the shots.
-- ------------------------------------------------------------------

local MICRO_STATES = { "GetNormalTexture", "GetPushedTexture", "GetDisabledTexture", "GetHighlightTexture" }

local function microButtons()
    local out = {}
    local menu = rawget(_G, "MicroMenu")
    for _, b in ipairs(menu and { menu:GetChildren() } or {}) do
        if b.GetNormalTexture and b:GetNormalTexture() then out[#out + 1] = b end
    end
    return out
end

local function atlasInfo(atlas)
    local T = rawget(_G, "C_Texture")
    if not (atlas and T and T.GetAtlasInfo) then return nil end
    local ok, info = pcall(T.GetAtlasInfo, atlas)
    if ok and type(info) == "table" then return info end
end

local function readMicro()
    local n = 0
    for _, b in ipairs(microButtons()) do
        n = n + 1
        local parts = {}
        for _, getter in ipairs(MICRO_STATES) do
            local tex = b[getter](b)
            local atlas = tex and tex.GetAtlas and tex:GetAtlas()
            local info = atlasInfo(atlas)
            parts[#parts + 1] = ("%s %s%s"):format(getter:sub(4, -8), Show(atlas), info and (" %sx%s file %s coords %.4f %.4f %.4f %.4f"):format(
                Show(info.width), Show(info.height), Show(info.file or info.filename), info.leftTexCoord or 0, info.rightTexCoord or 0,
                info.topTexCoord or 0, info.bottomTexCoord or 0) or "")
        end
        local bg = type(b.Background) == "table" and b.Background or nil
        say(("%s %sx%s; %s; Background %s"):format(Show(b:GetName()), Show(b:GetWidth()), Show(b:GetHeight()),
            table.concat(parts, "; "), Show(bg and bg.GetAtlas and bg:GetAtlas())))
    end
    local hasKey = rawget(_G, "HasKey")
    say("HasKey() " .. Show(hasKey and select(2, pcall(hasKey))))
    local B = gab() and gab().Bags
    for _, name in ipairs(B and B.BUTTONS or {}) do
        local b = rawget(_G, name)
        local icon = b and b.icon
        if icon then
            local r, g, bl, a = icon:GetVertexColor()
            say(("%s shown %s, icon %s atlas %s, alpha %s, desaturated %s, colour %s %s %s, occupied (GAB) %s"):format(name,
                Show(b:IsShown()), Show(icon:GetTexture()), Show(icon.GetAtlas and icon:GetAtlas()), Show(icon:GetAlpha()),
                Show(icon.IsDesaturated and icon:IsDesaturated()), Show(r), Show(g), Show(bl), Show(B.occupied(b))))
        end
    end
    return n .. " micro buttons"
end

-- Crop every micro button's state textures by `k` of their atlas on each side,
-- the Background faded (k = 0: Blizzard's own, the Background shown).
local function cropMicro(k)
    return function()
        for _, b in ipairs(microButtons()) do
            for _, getter in ipairs(MICRO_STATES) do
                local tex = b[getter](b)
                local info = tex and atlasInfo(tex.GetAtlas and tex:GetAtlas())
                if info and info.leftTexCoord then
                    local l, r, t, bt = info.leftTexCoord, info.rightTexCoord, info.topTexCoord, info.bottomTexCoord
                    local dx, dy = (r - l) * k, (bt - t) * k
                    tex:SetTexCoord(l + dx, r - dx, t + dy, bt - dy)
                end
            end
            if type(b.Background) == "table" then b.Background:SetAlpha(k > 0 and 0 or 1) end
            if type(b.PushedBackground) == "table" then b.PushedBackground:SetAlpha(k > 0 and 0 or 1) end
        end
        return "inset " .. k
    end
end

-- The bag slots' icons: faded on an empty slot (GAB's occupied false) and on
-- the key ring (`all`: every icon), or back to 1.
local function fadeBagIcons(mode)
    return function()
        local B, n = gab().Bags, 0
        for _, name in ipairs(B.BUTTONS) do
            local b = rawget(_G, name)
            if b and b.icon then
                local fade = mode == "empty" and (B.occupied(b) == false or b == rawget(_G, "KeyRingButton"))
                b.icon:SetAlpha(fade and 0 or 1)
                if fade then n = n + 1 end
            end
        end
        return mode .. ": " .. n .. " icons faded"
    end
end

local microSteps = {
    title = "Micro buttons and empty bag slots without Blizzard's art (#57)",
    { text = "Reading the micro buttons' atlases and the bag slots' icons.", auto = true, run = readMicro },
}
for _, k in ipairs({ 0.08, 0.12, 0.16, 0.20 }) do
    microSteps[#microSteps + 1] = { text = "Keep the pointer away from the micro menu and press Crop " .. k
        .. ": each micro button cut by " .. (k * 100) .. "% on every side, its background faded.", button = "Crop " .. k,
        run = cropMicro(k), screenshot = "micro buttons cropped " .. k }
    microSteps[#microSteps + 1] = { text = "At " .. k .. ": is the bronze frame gone, with the symbol whole?", ask = true }
end
for _, step in ipairs({
    { text = "Press Fade: the empty bag slots' and the key ring's icons faded.", button = "Fade",
      run = fadeBagIcons("empty"), screenshot = "bag icons faded" },
    { text = "Better without those icons (the slot still takes a bag and opens on click)?", ask = true },
    { text = "Press Reload now: it puts Blizzard's art back and saves the results.", reload = true },
}) do microSteps[#microSteps + 1] = step end
Probe:Steps("micro", microSteps)
Probe:Command("micro", function() readMicro() end, "the micro buttons' atlases and the bag slots' icons (#57)")

local boot = CreateFrame("Frame")
Probe:RegisterEvents(boot, { "ADDON_LOADED", "PLAYER_REGEN_ENABLED" })
boot:SetScript("OnEvent", function(_, event, name)
    if event == "PLAYER_REGEN_ENABLED" then
        fights, lookFights = fights + 1, lookFights + 1
        return
    end
    if name ~= ADDON then return end
    Probe:Ready()
    -- The standalone probe's saved table had another shape: start afresh.
    if type(GABProbeDB) ~= "table" or GABProbeDB.module ~= 1 then GABProbeDB = { module = 1 } end
    if type(GABProbeDB.log) ~= "table" then GABProbeDB.log = {} end
    Probe:UseLog(GABProbeDB.log, MAX_LOG)
    GABProbeDB.loads = (GABProbeDB.loads or 0) + 1
    say("loaded (" .. GABProbeDB.loads .. " loads). /fp steps gab campfire, or /fp gab for the commands")
end)

NS._test = { Probe = Probe, aura = aura, readAll = readAll, readCamping = readCamping, cropMicro = cropMicro, fadeBagIcons = fadeBagIcons,
    takeBaseline = takeBaseline, cooldownVerdict = cooldownVerdict }
