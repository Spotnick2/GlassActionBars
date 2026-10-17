-- Compat.lua: the one place this addon touches client APIs that moved, may be
-- absent, or behave differently on WoW: Forever. Everything else calls through
-- GlassActionBars.API. Nothing is injected into _G.
--
-- GlassMiniMap's Compat.lua (failures, Try, events, version, class colour),
-- trimmed to what the action bars need; lift more from there when needed.

GlassActionBars = GlassActionBars or {}
local GAB = GlassActionBars
local API = {}
GAB.API = API

-- The build the notes in docs/ were measured on. Bump only after re-measuring
-- in game; tests/test_toc.lua pins the same literal.
GAB.MEASURED_ON_BUILD = "1.60.1.70374"

function API.Print(msg)
    print("|cff7fd4ffGlassActionBars|r " .. msg)
end

-- True for a Retail secret value: it may be handed back to the client but
-- never compared, concatenated or truth-tested in Lua.
function API.IsSecret(v)
    return issecretvalue ~= nil and issecretvalue(v) == true
end

-- v, or nil when it is secret.
function API.Plain(v)
    if API.IsSecret(v) then return nil end
    return v
end

function API.ClientBuild()
    local version, build = GetBuildInfo()
    return tostring(version) .. "." .. tostring(build)
end

-- InCombatLockdown() is still false inside the PLAYER_REGEN_DISABLED handler
-- (porting guide). A handler of the combat events passes them here first,
-- then asks InCombat().
local combat = false
function API.NoteCombat(event)
    if event == "PLAYER_REGEN_DISABLED" then combat = true
    elseif event == "PLAYER_REGEN_ENABLED" then combat = false end
end
function API.InCombat() return combat or InCombatLockdown() end

-- The one failure recorder: key -> first error, read by /gab failures.
GAB.failures = GAB.failures or {}
function API.Fail(key, err)
    if GAB.failures[key] ~= nil then return end
    local msg = "(unprintable error)"
    if type(err) == "string" then
        msg = err
    elseif not API.IsSecret(err) then
        local ok, s = pcall(tostring, err)
        if ok and type(s) == "string" then msg = s end
    end
    GAB.failures[key] = msg
end

-- Run fn under pcall; a throw is recorded under `key` and nil is returned.
function API.Try(key, fn, ...)
    local ok, a, b = pcall(fn, ...)
    if ok then return a, b end
    API.Fail(key, a)
    return nil
end

-- RegisterEvent throws on an unknown name and returns false on a refusal.
-- Both count as failure, and every failure is reported: a silently missing
-- handler is the bug this exists to prevent.
function API.RegisterEvent(frame, name, who)
    local ok, registered = pcall(frame.RegisterEvent, frame, name)
    if ok and registered ~= false then return true end
    local why = ok and "refused" or tostring(registered)
    API.Fail("event:" .. name, (who and (who .. ": ") or "") .. why)
    API.Print("|cffff6060could not register|r " .. name .. " (" .. why .. ")")
    return false
end

function API.RegisterEvents(frame, events, who)
    for _, name in ipairs(events) do API.RegisterEvent(frame, name, who) end
end

-- An addon's TOC Version, or nil (absent API, error, secret, not a string).
function API.AddOnVersion(addon)
    local get = C_AddOns and C_AddOns.GetAddOnMetadata
    if not get then return nil end
    local ok, v = pcall(get, addon, "Version")
    if not ok or API.IsSecret(v) or type(v) ~= "string" then return nil end
    return v
end

-- The player's class colour (plain numbers), or nil (GlassPanel's).
function API.ClassColor()
    local ok, _, class = pcall(UnitClass, "player")
    class = ok and API.Plain(class) or nil
    if type(class) ~= "string" then return nil end
    local ok2, c = pcall(C_ClassColor.GetClassColor, class)
    if not ok2 or type(c) ~= "table" then return nil end
    local r, g, b = API.Plain(c.r), API.Plain(c.g), API.Plain(c.b)
    if type(r) ~= "number" or type(g) ~= "number" or type(b) ~= "number" then return nil end
    return r, g, b
end

-- Whether the player knows a spell: true, false, or nil when the client won't
-- say (Apotheca's, measured on 70334: C_SpellBook.IsSpellKnown agrees with
-- IsPlayerSpell on every profession spell; only the current rank is known).
function API.SpellKnown(spellID)
    local ok, known = pcall(C_SpellBook.IsSpellKnown, spellID)
    known = ok and API.Plain(known)
    if type(known) ~= "boolean" then return nil end
    return known
end

-- How many of an item the bags hold; 0 when unreadable.
function API.ItemCount(itemID)
    local ok, n = pcall(C_Item.GetItemCount, itemID)
    n = ok and API.Plain(n)
    return type(n) == "number" and n or 0
end

-- Whether the player has an aura: true, false, or nil (unknown: the read
-- threw, as aura reads have been measured to (Apotheca's probe), or the
-- answer was secret). Nothing is compared before the secret check.
function API.HasPlayerAura(spellID)
    if not (C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID) then return nil end
    local ok, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, spellID)
    if not ok or API.IsSecret(aura) then return nil end
    return aura ~= nil
end

-- A frame from a template, and whether the template really applied: a missing
-- template doesn't throw, it returns a bare frame, so `proof` names a field
-- the template makes (GlassUnitFrames' API.SafeFrame).
function API.SafeFrame(ftype, parent, template, proof)
    local ok, f = pcall(CreateFrame, ftype, nil, parent, template)
    if ok and f then return f, (proof == nil) or f[proof] ~= nil end
    return CreateFrame(ftype, nil, parent), false
end
