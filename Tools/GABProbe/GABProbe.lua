-- GABProbe: the throwaway measurement addon for Glass Action Bars (issue: the
-- in-game probe). It answers docs/PLAN.md's Phase 0 questions before the
-- skin is written. Every line it prints also goes to GABProbeDB.log
-- (SavedVariables), so a full client exit leaves the session on disk.
--
-- Run it with /console taintLog 1 (and scriptErrors 1): the hooks it installs
-- are the same kind the skin will install, so a clean taint log here is the
-- first evidence the skin's approach holds.
--
-- Passive, always on (no command needed):
--   W  Blizzard's writers: call counts, in and out of combat, of the methods
--      the skin will post-hook (UpdateButtonArt, Update, SetButtonState,
--      UpdateFlash, UpdateHotkeys on ActionButton1; StanceBar UpdateState;
--      PetActionBar Update; MainActionBar UpdateDividers ...)
--   S  secrets: 1 s into every combat, whether HasAction / btn.action /
--      GetShapeshiftFormInfo / GetPetActionInfo come back secret
--   T  taint: ADDON_ACTION_BLOCKED / _FORBIDDEN, with the function
--
-- Commands (/gabprobe):
--   regions [frame]  the regions and child frames of a button (default: ActionButton1,
--                    StanceButton1, PetActionButton1): parentKey, type, size, alpha, layer, level
--   levels           frame levels on ActionButton1: the button, its cooldowns, the text
--                    container, overlays, and a test frame at button + 1
--   trial <label>    zero the counts under a label: do ONE operation, then `counts`
--   counts           the writer counts since the trial (only those that fired); `counts reset`
--   secret           sample the secrets now
--   alpha on/off     arm the combat alpha test: 1 s into the next combat, SetAlpha(0.4) on
--                    MultiBarBottomLeft (pcall), back to 1 at 3 s; logs any block
--   hearth           Hearthstone's use spell, its cooldown as a duration object and as
--                    numbers, shown on a test cooldown frame; re-applied 1 s into each combat
--   driver           (optional) does RegisterAttributeDriver / RegisterStateDriver work here?
--   log [n]          the last n log lines (default 30); `log clear`

local P = {}
local counts, combatCounts = {}, {}
local inCombat = false
local armAlpha = false
local hearth = nil   -- { frame, cooldown, spellID } once /gabprobe hearth ran

local function plain(v)
    if issecretvalue and issecretvalue(v) then return "<secret>" end
    return tostring(v)
end

local function log(msg)
    msg = tostring(msg)
    print("|cff7fd4ffGABProbe|r " .. msg)
    GABProbeDB = GABProbeDB or {}
    GABProbeDB.log = GABProbeDB.log or {}
    local stamp = date and date("%H:%M:%S") or ""
    table.insert(GABProbeDB.log, stamp .. " " .. msg)
    while #GABProbeDB.log > 2000 do table.remove(GABProbeDB.log, 1) end
end

local function after(s, fn) C_Timer.After(s, function() local ok, err = pcall(fn); if not ok then log("error: " .. tostring(err)) end end) end

--------------------------------------------------------------------------------
-- W: writer counts
--------------------------------------------------------------------------------

local WRITERS = {
    { "ActionButton1", { "UpdateButtonArt", "Update", "SetButtonState", "UpdateFlash", "UpdateHotkeys", "UpdateUsable" } },
    { "MultiBarBottomLeftButton1", { "UpdateButtonArt", "Update" } },
    { "StanceButton1", { "UpdateButtonArt", "SetButtonState" } },
    { "PetActionButton1", { "UpdateButtonArt", "UpdateButtonState", "SetButtonState" } },
    { "StanceBar", { "Update", "UpdateState", "UpdateGridLayout" } },
    { "PetActionBar", { "Update" } },
    { "MainActionBar", { "UpdateDividers", "UpdateEndCaps", "UpdateGridLayout", "UpdateShownButtons" } },
    { "MultiBarBottomLeft", { "UpdateGridLayout", "UpdateShownButtons" } },
}

local function installWriters()
    local n = 0
    for _, w in ipairs(WRITERS) do
        local frame = _G[w[1]]
        if not frame then
            log("W: no " .. w[1])
        else
            for _, m in ipairs(w[2]) do
                if type(frame[m]) == "function" then
                    local key = w[1] .. ":" .. m
                    counts[key], combatCounts[key] = 0, 0
                    hooksecurefunc(frame, m, function()
                        counts[key] = counts[key] + 1
                        if inCombat then combatCounts[key] = combatCounts[key] + 1 end
                    end)
                    n = n + 1
                else
                    log("W: " .. w[1] .. " has no method " .. m)
                end
            end
        end
    end
    log("W: " .. n .. " writers hooked")
end

-- A trial: counts zeroed under a label, one operation, then `counts`, so each
-- count belongs to that one operation. Only the writers that fired print.
local trial = "(no trial)"

local function resetCounts()
    for k in pairs(counts) do counts[k], combatCounts[k] = 0, 0 end
end

local function printCounts()
    local keys = {}
    for k in pairs(counts) do keys[#keys + 1] = k end
    table.sort(keys)
    local any = false
    for _, k in ipairs(keys) do
        if counts[k] > 0 then
            any = true
            log(("W[%s]: %-40s %5d  (in combat %d)"):format(trial, k, counts[k], combatCounts[k]))
        end
    end
    if not any then log("W[" .. trial .. "]: no writer fired") end
end

--------------------------------------------------------------------------------
-- S: secrets
--------------------------------------------------------------------------------

local function sampleSecrets(why)
    local b = ActionButton1
    if b then
        local ok, action = pcall(function() return b.action end)
        local ok2, has = pcall(HasAction, action)
        log(("S[%s]: ActionButton1.action=%s HasAction=%s (%s)"):format(why, ok and plain(action) or "error",
            ok2 and plain(has) or ("error " .. tostring(has)), type(has)))
    end
    local ok3, tex = pcall(GetShapeshiftFormInfo, 1)
    log(("S[%s]: GetShapeshiftFormInfo(1) texture=%s"):format(why, ok3 and plain(tex) or "error"))
    local ok4, name = pcall(GetPetActionInfo, 1)
    log(("S[%s]: GetPetActionInfo(1) name=%s"):format(why, ok4 and plain(name) or "error"))
    local ok5, n = pcall(GetNumShapeshiftForms)
    log(("S[%s]: GetNumShapeshiftForms=%s"):format(why, ok5 and plain(n) or "error"))
end

--------------------------------------------------------------------------------
-- regions / levels
--------------------------------------------------------------------------------

local function describe(key, v)
    local ok, t = pcall(v.GetObjectType, v)
    if not ok then return nil end
    local parts = { key, t }
    pcall(function() parts[#parts + 1] = ("%.1fx%.1f"):format(v:GetWidth(), v:GetHeight()) end)
    pcall(function() parts[#parts + 1] = "alpha " .. plain(v:GetAlpha()) end)
    pcall(function() parts[#parts + 1] = v:IsShown() and "shown" or "hidden" end)
    if v.GetDrawLayer then pcall(function() local l, s = v:GetDrawLayer(); parts[#parts + 1] = "layer " .. tostring(l) .. "/" .. tostring(s) end) end
    if v.GetFrameLevel then pcall(function() parts[#parts + 1] = "level " .. v:GetFrameLevel() end) end
    if v.GetAtlas then pcall(function() local a = v:GetAtlas(); if a then parts[#parts + 1] = "atlas " .. a end end) end
    return table.concat(parts, "  ")
end

local function regions(name)
    local f = _G[name]
    if not f then return log("regions: no " .. name) end
    log("regions of " .. name .. ":")
    local keys = {}
    for k, v in pairs(f) do
        if type(k) == "string" and type(v) == "table" and v.GetObjectType then keys[#keys + 1] = k end
    end
    table.sort(keys)
    for _, k in ipairs(keys) do
        local line = describe(k, f[k])
        if line then log("  " .. line) end
    end
    local unnamed = 0
    for _, r in ipairs({ f:GetRegions() }) do
        local found = false
        for _, k in ipairs(keys) do if f[k] == r then found = true end end
        if not found then unnamed = unnamed + 1 end
    end
    log("  (" .. unnamed .. " regions without a key; " .. select("#", f:GetChildren()) .. " child frames)")
end

local function levels()
    local b = ActionButton1
    if not b then return log("levels: no ActionButton1") end
    log("levels: ActionButton1 " .. b:GetFrameLevel() .. " strata " .. b:GetFrameStrata())
    for _, k in ipairs({ "cooldown", "chargeCooldown", "lossOfControlCooldown", "TextOverlayContainer",
                         "AutoCastOverlay", "SpellActivationAlert", "SpellCastAnimFrame", "TargetReticleAnimFrame",
                         "InterruptDisplay", "CooldownFlash" }) do
        local f = b[k]
        if f and f.GetFrameLevel then log(("  %-24s level %d"):format(k, f:GetFrameLevel())) end
    end
    P.levelProbe = P.levelProbe or CreateFrame("Frame", nil, b)
    P.levelProbe:SetFrameLevel(b:GetFrameLevel() + 1)
    log("  a child set to button + 1: level " .. P.levelProbe:GetFrameLevel())
    P.levelUnder = P.levelUnder or CreateFrame("Frame", nil, b)
    P.levelUnder:SetFrameLevel(math.max(0, b:GetFrameLevel() - 1))
    log("  a child set to button - 1: level " .. P.levelUnder:GetFrameLevel())
end

--------------------------------------------------------------------------------
-- alpha in combat
--------------------------------------------------------------------------------

local function alphaTest()
    local bar = MultiBarBottomLeft
    if not bar then return log("alpha: no MultiBarBottomLeft") end
    local ok, err = pcall(bar.SetAlpha, bar, 0.4)
    log(("alpha: in combat (lockdown %s) SetAlpha(0.4): %s, alpha now %s"):format(tostring(InCombatLockdown()),
        ok and "ok" or ("error " .. tostring(err)), plain(bar:GetAlpha())))
    after(2, function()
        local ok2, err2 = pcall(bar.SetAlpha, bar, 1)
        log(("alpha: SetAlpha(1): %s, alpha now %s"):format(ok2 and "ok" or ("error " .. tostring(err2)), plain(bar:GetAlpha())))
    end)
end

--------------------------------------------------------------------------------
-- Hearthstone cooldown
--------------------------------------------------------------------------------

local HEARTHSTONE = 6948

local function applyHearth(why)
    if not hearth then return end
    local okS, dur = pcall(C_Spell.GetSpellCooldownDuration, hearth.spellID)
    log(("hearth[%s]: GetSpellCooldownDuration(%s): %s, secret %s, type %s"):format(why, tostring(hearth.spellID),
        okS and "ok" or ("error " .. tostring(dur)), tostring(okS and issecretvalue and issecretvalue(dur)), type(dur)))
    if okS and dur ~= nil then
        local ok, err = pcall(hearth.cooldown.SetCooldownFromDurationObject, hearth.cooldown, dur)
        log(("hearth[%s]: SetCooldownFromDurationObject: %s"):format(why, ok and "ok" or ("error " .. tostring(err))))
    end
    local okN, start, duration = pcall(C_Container.GetItemCooldown, HEARTHSTONE)
    log(("hearth[%s]: C_Container.GetItemCooldown: %s start %s duration %s"):format(why, okN and "ok" or "error",
        plain(start), plain(duration)))
end

local function hearthTest()
    local okI, spellName, spellID = pcall(C_Item.GetItemSpell, HEARTHSTONE)
    log(("hearth: C_Item.GetItemSpell(%d): %s name %s id %s"):format(HEARTHSTONE, okI and "ok" or "error",
        plain(spellName), plain(spellID)))
    if not okI or type(spellID) ~= "number" then return end
    if not hearth then
        local f = CreateFrame("Frame", nil, UIParent)
        f:SetSize(40, 40)
        f:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
        local icon = f:CreateTexture(nil, "ARTWORK")
        icon:SetAllPoints(f)
        local okT, tex = pcall(C_Item.GetItemIconByID, HEARTHSTONE)
        if okT and tex then icon:SetTexture(tex) else icon:SetColorTexture(0.2, 0.2, 0.3, 1) end
        local cd = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
        cd:SetAllPoints(f)
        hearth = { frame = f, cooldown = cd }
    end
    hearth.spellID = spellID
    applyHearth("now")
    log("hearth: the test icon is above the screen's centre; use the Hearthstone, then fight, and compare its swipe")
end

--------------------------------------------------------------------------------
-- state drivers (optional)
--------------------------------------------------------------------------------

local function driverTest()
    local a = CreateFrame("Frame", nil, UIParent, "SecureHandlerAttributeTemplate")
    a:SetScript("OnAttributeChanged", function(_, k, v) if k == "state-probe" then log("driver: attribute driver -> " .. plain(v)) end end)
    local okA, errA = pcall(RegisterAttributeDriver, a, "state-probe", "[combat] in; out")
    log("driver: RegisterAttributeDriver: " .. (okA and "ok" or ("error " .. tostring(errA))) .. ", now " .. plain(a:GetAttribute("state-probe")))
    local s = CreateFrame("Frame", nil, UIParent, "SecureHandlerStateTemplate")
    local okS, errS = pcall(function()
        s:SetAttribute("_onstate-probe", [[ self:SetAttribute("seen", newstate) ]])
        RegisterStateDriver(s, "probe", "[combat] in; out")
    end)
    log("driver: RegisterStateDriver: " .. (okS and "ok" or ("error " .. tostring(errS))))
    after(0.5, function() log("driver: the state snippet saw " .. plain(s:GetAttribute("seen")) .. " (nil = it never ran)") end)
    P.driverState = s
    log("driver: enter combat; the attribute driver should log 'in', and /gabprobe driver again reads the snippet")
end

--------------------------------------------------------------------------------
-- Events and commands
--------------------------------------------------------------------------------

local ev = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_LOGIN", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "ADDON_ACTION_BLOCKED",
                     "ADDON_ACTION_FORBIDDEN" }) do
    local ok, err = pcall(ev.RegisterEvent, ev, e)
    if not ok then print("GABProbe: could not register " .. e .. ": " .. tostring(err)) end
end
ev:SetScript("OnEvent", function(_, event, a1, a2)
    if event == "PLAYER_LOGIN" then
        GABProbeDB = GABProbeDB or {}
        GABProbeDB.log = GABProbeDB.log or {}
        local v, b = GetBuildInfo()
        log("session start, client " .. tostring(v) .. "." .. tostring(b))
        installWriters()
        sampleSecrets("login")
    elseif event == "PLAYER_REGEN_DISABLED" then
        inCombat = true
        log("combat start")
        after(1, function()
            sampleSecrets("combat")
            if armAlpha then alphaTest() end
            applyHearth("combat")
        end)
    elseif event == "PLAYER_REGEN_ENABLED" then
        inCombat = false
        log("combat end")
        printCounts()
    else
        log("T: " .. event .. " " .. tostring(a1) .. " " .. tostring(a2))
    end
end)

local function help()
    for _, l in ipairs({ "regions [frame]", "levels", "trial <label>", "counts [reset]", "secret", "alpha on/off", "hearth",
                         "driver (optional)", "log [n|clear]" }) do
        log("/gabprobe " .. l)
    end
end

SLASH_GABPROBE1 = "/gabprobe"
SlashCmdList.GABPROBE = function(msg)
    local cmd, arg = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
    cmd = cmd:lower()
    local ok, err = pcall(function()
        if cmd == "regions" then
            if arg ~= "" then regions(arg) else
                for _, n in ipairs({ "ActionButton1", "StanceButton1", "PetActionButton1" }) do regions(n) end
            end
        elseif cmd == "levels" then levels()
        elseif cmd == "trial" then
            trial = arg ~= "" and arg or "unnamed"
            resetCounts()
            log("trial: " .. trial .. " (counts zeroed; do the one operation, then /gabprobe counts)")
        elseif cmd == "counts" then
            if arg == "reset" then
                resetCounts()
                log("counts reset")
            else printCounts() end
        elseif cmd == "secret" then sampleSecrets("now")
        elseif cmd == "alpha" then
            armAlpha = arg ~= "off"
            log("alpha test " .. (armAlpha and "armed for the next combat" or "off"))
        elseif cmd == "hearth" then hearthTest()
        elseif cmd == "driver" then
            if P.driverState then
                log("driver: the state snippet saw " .. plain(P.driverState:GetAttribute("seen")))
            else driverTest() end
        elseif cmd == "log" then
            if arg == "clear" then GABProbeDB.log = {}; return print("GABProbe: log cleared") end
            local n = tonumber(arg) or 30
            local l = GABProbeDB.log or {}
            for i = math.max(1, #l - n + 1), #l do print(l[i]) end
        else help() end
    end)
    if not ok then log("error: " .. tostring(err)) end
end
