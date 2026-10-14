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
--   S  secrets: 1 s into every combat (skipped if it ended), whether HasAction /
--      C_ActionBar.HasAction / GetShapeshiftFormInfo / GetPetActionInfo come back
--      secret, each on a slot that was OCCUPIED when picked ("not sampled" else)
--   T  taint: ADDON_ACTION_BLOCKED / _FORBIDDEN, with the function
--
-- Commands (/gabprobe):
--   regions [frame]  the regions of a button and its child frames, 3 deep, by key path
--                    (default: ActionButton1, StanceButton1, PetActionButton1): type, size,
--                    alpha, layer, atlas, level
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

-- What to sample: an OCCUPIED slot of each family, chosen out of combat
-- (login, and in the PLAYER_REGEN_DISABLED handler, which runs before the
-- lockdown). An empty slot's false/nil says nothing about whether the reader
-- returns secrets for a filled one (Codex's review on #11), so a family with
-- nothing to sample is logged as "not sampled", never as "no secret".
local BAR_PREFIXES = { "ActionButton", "MultiBarBottomLeftButton", "MultiBarBottomRightButton", "MultiBarLeftButton",
    "MultiBarRightButton", "MultiBar5Button", "MultiBar6Button", "MultiBar7Button" }
local picks = {}

local function pickSamples()
    local old = picks
    picks = {}
    local sawSecret = false
    for _, prefix in ipairs(BAR_PREFIXES) do
        for i = 1, 12 do
            local b = _G[prefix .. i]
            local ok, action = pcall(function() return b and b.action end)
            if ok and type(action) == "number" then
                local okh, has = pcall(HasAction, action)
                if okh and issecretvalue and issecretvalue(has) then sawSecret = true
                elseif okh and has == true then picks.action = { name = prefix .. i, slot = action }; break end
            end
        end
        if picks.action then break end
    end
    -- Answers already secret when picking: keep the earlier, plainly occupied pick.
    if not picks.action and sawSecret then picks.action = old.action end
    -- Every answer is checked for a secret BEFORE it is compared: a comparison
    -- on a secret throws, and this runs in the PLAYER_REGEN_DISABLED handler,
    -- where a throw would lose the whole fight's samples (Codex, #11). A
    -- secret answer keeps the earlier, plainly picked slot.
    local okn, n = pcall(GetNumShapeshiftForms)
    if okn and issecretvalue and issecretvalue(n) then picks.stance = old.stance
    elseif okn and type(n) == "number" and n > 0 then picks.stance = 1 end
    local petSecret = false
    for i = 1, 10 do
        local okp, name = pcall(GetPetActionInfo, i)
        if okp and issecretvalue and issecretvalue(name) then petSecret = true
        elseif okp and name ~= nil then picks.pet = i; break end
    end
    if not picks.pet and petSecret then picks.pet = old.pet end
end

local function secretText(ok, v)
    if not ok then return "error " .. tostring(v) end
    if issecretvalue and issecretvalue(v) then return "SECRET" end
    return "plain " .. tostring(v)
end

local function sampleSecrets(why)
    if picks.action then
        local a = picks.action
        local ok, has = pcall(HasAction, a.slot)
        log(("S[%s]: action %s (slot %d, occupied when picked): HasAction %s"):format(why, a.name, a.slot, secretText(ok, has)))
        if C_ActionBar and C_ActionBar.HasAction then
            local ok2, has2 = pcall(C_ActionBar.HasAction, a.slot)
            log(("S[%s]:   C_ActionBar.HasAction %s"):format(why, secretText(ok2, has2)))
        end
    else
        log(("S[%s]: action: not sampled (no slot with an action)"):format(why))
    end
    if picks.stance then
        local ok, tex = pcall(GetShapeshiftFormInfo, picks.stance)
        log(("S[%s]: stance 1: GetShapeshiftFormInfo texture %s"):format(why, secretText(ok, tex)))
    else
        log(("S[%s]: stance: not sampled (no form or stance)"):format(why))
    end
    if picks.pet then
        local ok, name = pcall(GetPetActionInfo, picks.pet)
        log(("S[%s]: pet slot %d: GetPetActionInfo name %s"):format(why, picks.pet, secretText(ok, name)))
    else
        log(("S[%s]: pet: not sampled (no pet action)"):format(why))
    end
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

-- Every region of a button and of its child frames, with the path of keys
-- that reaches it (HotKey and Count live in TextOverlayContainer; overlays in
-- other children): Codex's review on #11.
local function regionsOf(f, path, depth)
    local named = {}
    for k, v in pairs(f) do
        if type(k) == "string" and type(v) == "table" then named[v] = k end
    end
    local unnamed = 0
    for _, r in ipairs({ f:GetRegions() }) do
        if named[r] then
            local line = describe(path .. named[r], r)
            if line then log("  " .. line) end
        else
            unnamed = unnamed + 1
            local line = describe(path .. "<region>", r)
            if line then log("  " .. line) end
        end
    end
    if depth <= 0 then return end
    for _, child in ipairs({ f:GetChildren() }) do
        local key = named[child] or "<frame>"
        local line = describe(path .. key, child)
        if line then log("  " .. line) end
        regionsOf(child, path .. key .. ".", depth - 1)
    end
end

local function regions(name)
    local f = _G[name]
    if not f then return log("regions: no " .. name) end
    log("regions of " .. name .. " (and its child frames, 3 deep):")
    regionsOf(f, "", 3)
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
-- RegisterEvent throws on an unknown name and returns false on a refusal
-- (porting guide): both are reported, or a measurement would silently be
-- missing (Codex, #11). Logged at login, once the saved log exists.
local registerFailures = {}
for _, e in ipairs({ "PLAYER_LOGIN", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "ADDON_ACTION_BLOCKED",
                     "ADDON_ACTION_FORBIDDEN" }) do
    local ok, registered = pcall(ev.RegisterEvent, ev, e)
    if not ok or registered == false then
        local why = ok and "refused" or tostring(registered)
        registerFailures[#registerFailures + 1] = e .. " (" .. why .. ")"
        print("GABProbe: could not register " .. e .. ": " .. why)
    end
end
ev:SetScript("OnEvent", function(_, event, a1, a2)
    if event == "PLAYER_LOGIN" then
        GABProbeDB = GABProbeDB or {}
        GABProbeDB.log = GABProbeDB.log or {}
        local v, b = GetBuildInfo()
        log("session start, client " .. tostring(v) .. "." .. tostring(b))
        for _, f in ipairs(registerFailures) do log("could not register " .. f .. ": its measurement is missing") end
        installWriters()
        pickSamples()
        sampleSecrets("login")
    elseif event == "PLAYER_REGEN_DISABLED" then
        inCombat = true
        log("combat start")
        pickSamples()   -- still out of lockdown here: choose occupied slots
        after(1, function()
            -- A fight that ended within the second would make these out-of-combat
            -- reads, labelled "combat" (Codex's review on #11): skip them.
            if not InCombatLockdown() then
                return log("combat ended within 1 s: the combat samples were skipped")
            end
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
        elseif cmd == "secret" then
            if not InCombatLockdown() then pickSamples() end
            sampleSecrets(InCombatLockdown() and "now, combat" or "now")
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
