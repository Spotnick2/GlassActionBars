-- Procs.lua: the proc alerts (#115, docs/PLAN-procs.md): screen overlays, the
-- button glow and the proc sound, each an option.
--
-- A proc buff can't be read in combat on Forever (a quiet nil, docs/
-- FOREVER-PROBE.md session 10), so no addon code decides a proc is up:
-- Blizzard's aura engine (Blizzard_AuraContainer) shows a slot frame while its
-- aura is up, in combat too, and everything here is parented to such a slot.
--
-- - Overlays: one container per unit (player, target) under UIParent, a slot
--   per (effect, overlay) holding SAO's texture at SAO's geometry. A
--   stack-gated slot puts the texture in an application bar the engine shows
--   at that many stacks or more (Blizzard_CustomAuraButton.lua:430).
-- - Glow: on each button of Action Bars 1-8, one container per unit, each
--   with one slot ("glow") holding Blizzard's proc ring. The slot's filter
--   follows the button's spell (C_ActionBar.GetSpell, plain in combat) on its
--   own Update hook; an unchanged filter isn't written again (both setters
--   rebuild the slot, Blizzard_ManagedAuraContainer.lua:250). Retargeting in
--   combat was measured (run #620); the target containers refresh on
--   PLAYER_TARGET_CHANGED, a frame later, as SAO does.
-- - Sound: C_UnitAuras.AddAuraSound on Added and ApplicationsIncreased, per
--   aura id of an enabled effect that has one; the engine plays it.
-- - Counters (kind = "counter"): a reactive or ready ability, not an aura, so
--   addon code decides it from values Blizzard documents as plain (Counters,
--   below) and shows our own frames: a ring on each button holding a rank of
--   it, its overlays, its sound.
--
-- Everything that builds or changes the alerts waits out combat and a boss's
-- Encounter restriction (Apply queues it). The queue is woken by the
-- restriction's own event (Encounter, Inactive: IsAddOnRestrictionActive
-- always answers false during that event's dispatch) and drained when no
-- fight is on, or by PLAYER_REGEN_ENABLED when the Encounter is off.
-- A button's retarget on a page change isn't an option change: it runs in
-- combat (Phase 0 item 1).
--
-- Never a field on a Blizzard frame: per-button state lives in a weak side
-- table; the containers are our own frames, children of the buttons.

GlassActionBars = GlassActionBars or {}
local GAB = GlassActionBars
local API = GAB.API
local Procs = {}
GAB.Procs = Procs

-- SAO's geometry: a 256 square at 0.8, slots 128 x 256 (short x long) at 0.8.
Procs.SIZE, Procs.LONG, Procs.SHORT = 256 * 0.8, 256 * 0.8, 128 * 0.8
Procs.RING = 1.4               -- the ring's size, times the button's
Procs.LEVEL_UP = 5             -- the glow over the glass (session 10: + 1 and + 5 both draw over it)
Procs.SOUND_FILE = 568016      -- SoundKit 23287, UI_POWER_AURA_GENERIC (SAO's sound), build 71037
Procs.PULSE = { 1.08, 0.9259, 0.5 }   -- SAO's pulse: up, back, seconds each way
Procs.LEVEL = 3                       -- an overlay's level over its container unless the data says (SAO's default)

Procs.FEATURES = { "overlays", "glow", "sound" }
Procs.LOOK = {
    opacity = { 1, { { 1, "Full" }, { 0.75, "75%" }, { 0.5, "Half" } } },
    scale = { 1, { { 0.8, "Small" }, { 1, "Normal" }, { 1.25, "Large" } } },
    offset = { 0, { { 0, "Close (SAO's)" }, { 60, "Wider" }, { 120, "Widest" } } },
}

-- Action Bars 1-8 (Fade.BARS' prefixes): the glow's buttons.
local PREFIXES = { "ActionButton", "MultiBarBottomLeftButton", "MultiBarBottomRightButton", "MultiBarRightButton",
    "MultiBarLeftButton", "MultiBar5Button", "MultiBar6Button", "MultiBar7Button" }

local ENGINE = "Blizzard_AuraContainer"
local POSITIONS = { LEFT = true, RIGHT = true, TOP = true }

local st = {
    started = false,
    sao = false,          -- SpellActivationOverlay loaded at login: the three default to off
    engine = nil,         -- the engine's load: true, or false once refused
    pending = false,      -- an Apply waiting for combat or the Encounter to end
    overlay = {},         -- unit -> container
    frames = {},          -- the overlays' slot frames: { frame, spec, container, holder }
    slots = {},           -- effect key -> { { container, slotKey } }
    glowUnits = {},       -- unit -> true, the units some effect glows from
    built = { overlays = false, glow = false, counters = false, counterOverlays = false, rings = false },
    counterBox = nil,     -- the counters' overlays' frame under UIParent
    counterFrames = {},   -- the counters' overlay frames: { frame, spec, container, key, pulse }
    applied = {},         -- each switch as last applied: what's on screen while a change waits
    sounds = {},          -- "unit:auraId" -> { id1, id2 }
    hooked = {},          -- buttons whose Update is hooked (a hook can't be taken back)
    writes = 0,           -- filter writes, for the tests
}
local side = setmetatable({}, { __mode = "k" })   -- button -> { [unit] = container, key = { [unit] = signature } }

-- ------------------------------------------------------------------
-- Settings: GlassActionBarsDB.procs, only what the player set. The three
-- switches keep nil (the default: on, off with SAO loaded), true and false
-- apart. The look's keys equal to their default aren't saved.

local function saved()
    local db = GAB.db and rawget(GAB.db, "procs")
    return type(db) == "table" and db or nil
end

function Procs.Enabled(feature)
    local db = saved()
    local v = db and db[feature]
    if v ~= nil then return v == true end
    return not st.sao
end

function Procs.Look(key)
    local db = saved()
    local v = db and db[key]
    if v ~= nil then return v end
    return Procs.LOOK[key][1]
end

-- An effect's own default: on, unless its data says default = false (SAO's
-- off-by-default counters).
function Procs.EffectDefault(key)
    for _, e in ipairs(Procs.Effects()) do
        if e.key == key then return e.default ~= false end
    end
    return true
end

-- off[key]: true = unticked, false = ticked (saved only for a default-off
-- effect), nil = the default.
function Procs.EffectOn(key)
    local db = saved()
    if db and type(db.off) == "table" then
        local v = db.off[key]
        if v == true then return false end
        if v == false then return true end
    end
    return Procs.EffectDefault(key)
end

function Procs.ValidLook(key, v)
    local L = Procs.LOOK[key]
    if not L then return false end
    for _, c in ipairs(L[2]) do if c[1] == v then return true end end
    return false
end

-- The saved table pruned in place (GlassActionBars.lua's ensureDefaults).
function Procs.Prune(db)
    if type(db) ~= "table" then return nil end
    for _, f in ipairs(Procs.FEATURES) do
        if db[f] ~= nil and type(db[f]) ~= "boolean" then db[f] = nil end
    end
    for k in pairs(Procs.LOOK) do
        if db[k] ~= nil and (not Procs.ValidLook(k, db[k]) or db[k] == Procs.LOOK[k][1]) then db[k] = nil end
    end
    if db.off ~= nil then
        if type(db.off) ~= "table" then db.off = nil else
            for k, v in pairs(db.off) do
                if type(k) ~= "string" or type(v) ~= "boolean" then db.off[k] = nil end
            end
            if next(db.off) == nil then db.off = nil end
        end
    end
    local known = { off = true }
    for _, f in ipairs(Procs.FEATURES) do known[f] = true end
    for k in pairs(Procs.LOOK) do known[k] = true end
    for k in pairs(db) do if not known[k] then db[k] = nil end end
    return next(db) ~= nil and db or nil
end

-- ------------------------------------------------------------------
-- The player's effects.

local function playerClass()
    local ok, _, class = pcall(UnitClass, "player")
    class = ok and API.Plain(class) or nil
    return type(class) == "string" and class or nil
end

function Procs.Effects()
    local class = playerClass()
    return class and GAB.ProcData and GAB.ProcData[class] or {}
end

local function ofKind(counter)
    local t = {}
    for _, e in ipairs(Procs.Effects()) do
        if (e.kind == "counter") == counter then t[#t + 1] = e end
    end
    return t
end
local function auraEffects() return ofKind(false) end
local function counterEffects() return ofKind(true) end

local function idSet(list)
    local t = {}
    for _, id in ipairs(list) do t[id] = true end
    return t
end

-- unit -> cast spell id -> sorted aura ids of the enabled effects that glow it.
local glowIndex = {}
local function rebuildIndex()
    local sets = {}
    for _, e in ipairs(auraEffects()) do
        if e.glow and Procs.EffectOn(e.key) then
            sets[e.unit] = sets[e.unit] or {}
            for _, spell in ipairs(e.glow) do
                local s = sets[e.unit][spell] or {}
                for _, a in ipairs(e.auras) do s[a] = true end
                sets[e.unit][spell] = s
            end
        end
    end
    glowIndex = {}
    for unit, bySpell in pairs(sets) do
        glowIndex[unit] = {}
        for spell, s in pairs(bySpell) do
            local ids = {}
            for a in pairs(s) do ids[#ids + 1] = a end
            table.sort(ids)
            glowIndex[unit][spell] = { set = s, sig = table.concat(ids, ",") }
        end
    end
end

-- ------------------------------------------------------------------
-- The engine and its containers (the probe's setup, docs/PLAN-procs.md).

local function loadEngine()
    if st.engine ~= nil then return st.engine end
    local isLoaded, load = C_AddOns and C_AddOns.IsAddOnLoaded, C_AddOns and C_AddOns.LoadAddOn
    local ok, loaded = pcall(isLoaded or error, ENGINE)
    if ok and loaded == true then st.engine = true; return true end
    local okL, did, why = pcall(load or error, ENGINE)
    if not okL or did ~= true then
        API.Fail("procs:engine", okL and ("LoadAddOn " .. tostring(why or did)) or did)
        st.engine = false
        return false
    end
    st.engine = true
    return true
end

local function sortOpts(o)
    o.sortMethod = rawget(_G, "AuraContainerSortMethod") and AuraContainerSortMethod.ExpirationOnly or nil
    o.sortDirection = rawget(_G, "AuraContainerSortDirection") and AuraContainerSortDirection.Reverse or nil
    return o
end

-- Made, its unit set, enabled: a container starts disabled, and registers its
-- UNIT_AURA only while enabled and shown (Blizzard_AuraContainer.lua:157).
local function newContainer(parent, unit)
    local c = CreateFrame("AuraContainer", nil, parent, "CustomAuraContainerTemplate")
    c:EnableMouse(false)
    c:SetUnit(unit)
    c:SetEnabled(true)
    return c
end

-- Off: disabled and hidden. On: shown, then enabled (both needed: a hidden
-- container registers nothing even when enabled).
local function setOn(c, on)
    if on then
        c:Show()
        c:SetEnabled(true)
    else
        c:SetEnabled(false)
        c:Hide()
    end
end

-- ------------------------------------------------------------------
-- Overlays.

-- A slot the engine refused: its frame, set up by overlaySlot but never
-- managed, hidden and forgotten. Recorded, and the other slots go on.
local function dropSlot(key, err)
    API.Fail("procs:slot:" .. key, err)
    local kept = {}
    for _, o in ipairs(st.frames) do
        if o.key == key then pcall(o.frame.Hide, o.frame) else kept[#kept + 1] = o end
    end
    st.frames = kept
end

-- SAO's placement (components/auracontainer.lua, setButtonGeometry), with
-- the player's scale; the container grows by the offset (SAO's too).
local function placeOverlay(o)
    local f, spec, c = o.frame, o.spec, o.container
    local s = (spec.scale or 1) * Procs.Look("scale")
    local short, long = Procs.SHORT * s, Procs.LONG * s
    local outer = (spec.outer or 0) * short
    f:ClearAllPoints()
    if spec.position == "LEFT" then
        f:SetPoint("RIGHT", c, "LEFT", -outer, 0)
        f:SetSize(short, long)
    elseif spec.position == "RIGHT" then
        f:SetPoint("LEFT", c, "RIGHT", outer, 0)
        f:SetSize(short, long)
    else
        f:SetPoint("BOTTOM", c, "TOP", 0, 0)
        f:SetSize(long, short)
    end
end

local function texCoords(t, spec)
    if spec.cw then
        t:SetTexCoord(0, 1, 1, 1, 0, 0, 1, 0)    -- SAO's quarter turn clockwise
    elseif spec.hflip then
        t:SetTexCoord(1, 0, 0, 1)
    else
        t:SetTexCoord(0, 1, 0, 1)
    end
end

local function pulse(t)
    local ag = t:CreateAnimationGroup()
    ag:SetLooping("REPEAT")
    for i, k in ipairs({ Procs.PULSE[1], Procs.PULSE[2] }) do
        local a = ag:CreateAnimation("Scale")
        a:SetScale(k, k)
        a:SetDuration(Procs.PULSE[3])
        a:SetSmoothing("IN_OUT")
        a:SetOrder(i)
    end
    ag:Play()
    return ag
end

local function overlaySlot(c, spec, key)
    return function(f)
        f:EnableMouse(false)
        if f.GetIcon and f:GetIcon() then f:GetIcon():Hide() end
        f:SetFrameLevel(c:GetFrameLevel() + (spec.level or Procs.LEVEL))   -- SAO's draw order
        local holder = f
        if (spec.stacks or 1) > 1 then
            holder = CreateFrame("StatusBar", nil, f)
            holder:SetAllPoints(f)
            f:SetApplicationBar(holder, { minApplications = spec.stacks, maxApplications = spec.stacks })
        end
        local t = holder:CreateTexture(nil, "ARTWORK")
        t:SetAllPoints(holder)
        t:SetTexture(spec.texture)
        texCoords(t, spec)
        local col = spec.color
        if col then t:SetVertexColor(col[1] / 255, col[2] / 255, col[3] / 255, (col[4] or 255) / 255) end
        local o = { frame = f, spec = spec, container = c, key = key }
        -- Played once here, as SAO does: no script on the slot frame. The
        -- engine forbids untrusted scripts on it right after this function,
        -- and an OnShow hook made that throw (in play, 2026-11-23: the slot
        -- never registered, its frame left shown).
        if spec.pulse then o.pulse = pulse(t) end
        st.frames[#st.frames + 1] = o
        placeOverlay(o)
    end
end

local function placeContainers()
    local size = Procs.SIZE + Procs.Look("offset")
    for _, c in pairs(st.overlay) do
        c:SetSize(size, size)
        c:SetAlpha(Procs.Look("opacity"))
    end
    if st.counterBox then
        st.counterBox:SetSize(size, size)
        st.counterBox:SetAlpha(Procs.Look("opacity"))
    end
    for _, o in ipairs(st.frames) do placeOverlay(o) end
    for _, o in ipairs(st.counterFrames) do placeOverlay(o) end
end

local function buildOverlays()
    for _, e in ipairs(auraEffects()) do
        if not st.overlay[e.unit] then
            local c = newContainer(UIParent, e.unit)
            c:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
            st.overlay[e.unit] = c
        end
        local c = st.overlay[e.unit]
        st.slots[e.key] = {}
        for i, spec in ipairs(e.overlays) do
            local key = e.key .. ":" .. i
            local ok, err = pcall(c.AddAuraSlot, c, key, e.filter, sortOpts({
                candidateFilters = { includeSpellIDs = idSet(e.auras) }, initializeFrame = overlaySlot(c, spec, key) }))
            if ok then
                st.slots[e.key][#st.slots[e.key] + 1] = { c, key }
            else
                dropSlot(key, err)
            end
        end
    end
    for _, c in pairs(st.overlay) do c:UpdateAllAuras() end
end

local function applyOverlays(on)
    if on and not st.built.overlays then
        st.built.overlays = true   -- once: a failure isn't retried (and duplicated) at each Apply
        buildOverlays()
    end
    if not st.built.overlays then return end
    for key, list in pairs(st.slots) do
        local eOn = Procs.EffectOn(key)
        for _, s in ipairs(list) do s[1]:SetAuraSlotEnabled(s[2], eOn) end
    end
    placeContainers()
    for _, c in pairs(st.overlay) do setOn(c, on) end
end

-- ------------------------------------------------------------------
-- The glow.

local function stockButtons()
    local list = {}
    for _, p in ipairs(PREFIXES) do
        for i = 1, 12 do
            local b = rawget(_G, p .. i)
            if b then list[#list + 1] = b end
        end
    end
    return list
end

local function spellOf(b)
    local get = C_ActionBar and C_ActionBar.GetSpell
    if not get or type(b.action) ~= "number" then return nil end
    local ok, id = pcall(get, b.action)
    if not ok or API.IsSecret(id) or type(id) ~= "number" then return nil end
    return id
end

-- The ring: the probe's recipe (Blizzard's ActionButtonSpellAlertTemplate,
-- its loop played; it restarts after an OnHide by itself, run #622). Its
-- holder is what's shown and hidden.
local function makeRing(holder, w, h)
    local g = CreateFrame("Frame", nil, holder, "ActionButtonSpellAlertTemplate")
    g:SetSize(w * Procs.RING, h * Procs.RING)
    g:SetPoint("CENTER", holder, "CENTER", 0, 0)
    g.animationPlaying = true
    g:Show()
    if g.ProcLoop then g.ProcLoop:Play() end
    return g
end

local function ringSlot(c, w, h)
    return function(f)
        f:EnableMouse(false)
        f:ClearAllPoints()
        f:SetAllPoints(c)
        if f.GetIcon and f:GetIcon() then f:GetIcon():Hide() end
        makeRing(f, w, h)
    end
end

-- A button's Update runs both: the aura glow's retarget and the counter ring.
local retarget, paintRing
local function hookButton(b)
    if st.hooked[b] then return end
    st.hooked[b] = true
    hooksecurefunc(b, "Update", function(self)
        retarget(self)
        paintRing(self)
    end)
end

-- One button's slots follow its spell. A slot back from off gets its filter
-- written and is enabled, even with the same ids as before.
function retarget(b)
    local s = side[b]
    if not s or not st.built.glow or not st.applied.glow then return end
    local spell = spellOf(b)
    for unit in pairs(st.glowUnits) do
        local want = spell and glowIndex[unit] and glowIndex[unit][spell]
        local had = s.key[unit]
        local sig = want and want.sig or nil
        if sig ~= had then
            local c = s[unit]
            local ok = API.Try("procs:retarget", function()
                if want then
                    c:SetAuraSlotCandidateFilters("glow", { includeSpellIDs = want.set })
                    if had == nil then c:SetAuraSlotEnabled("glow", true) end
                else
                    c:SetAuraSlotEnabled("glow", false)
                end
                return true
            end)
            st.writes = st.writes + 1
            if ok then s.key[unit] = sig end
        end
    end
end

local function buildGlow()
    st.glowUnits = {}
    for _, e in ipairs(auraEffects()) do
        if e.glow then st.glowUnits[e.unit] = true end
    end
    st.built.glow = true
    if not next(st.glowUnits) then return end   -- a class with no glow: nothing on its buttons
    local filters = {}
    for _, e in ipairs(auraEffects()) do
        if e.glow then filters[e.unit] = filters[e.unit] or e.filter end
    end
    for _, b in ipairs(stockButtons()) do
        local w, h = b:GetSize()
        local s = { key = {} }
        -- One button's failure is recorded and its containers put away; the
        -- other buttons still get theirs.
        local made = {}
        local ok, err = pcall(function()
            for unit in pairs(st.glowUnits) do
                local c = newContainer(b, unit)
                made[#made + 1] = c
                c:SetAllPoints(b)
                c:SetFrameLevel(b:GetFrameLevel() + Procs.LEVEL_UP)
                -- Made with a real filter (an empty set's meaning isn't ours to
                -- guess), then off until retarget says otherwise.
                local any
                for _, e in ipairs(auraEffects()) do
                    if e.glow and e.unit == unit then any = idSet(e.auras); break end
                end
                c:AddAuraSlot("glow", filters[unit], sortOpts({ initializeFrame = ringSlot(c, w, h),
                    candidateFilters = { includeSpellIDs = any } }))
                c:SetAuraSlotEnabled("glow", false)
                c:UpdateAllAuras()
                s[unit] = c
            end
        end)
        if not ok then
            API.Fail("procs:glow:" .. tostring(b:GetName()), err)
            for _, c in ipairs(made) do pcall(setOn, c, false) end
        else
            side[b] = s
        end
        hookButton(b)
    end
end

local function applyGlow(on)
    if on and not st.built.glow then buildGlow() end
    if not st.built.glow then return end
    for _, s in pairs(side) do
        for unit in pairs(st.glowUnits) do setOn(s[unit], on) end
    end
    if on then
        for b in pairs(side) do retarget(b) end
    end
end

-- A target change: the target containers, a frame later (SAO's).
local function refreshTarget()
    if st.overlay.target and st.applied.overlays then API.Try("procs:target", st.overlay.target.UpdateAllAuras, st.overlay.target) end
    if st.built.glow and st.glowUnits.target and st.applied.glow then
        for _, s in pairs(side) do
            if s.key.target then API.Try("procs:target", s.target.UpdateAllAuras, s.target) end
        end
    end
end

-- ------------------------------------------------------------------
-- The sound.

local function applySounds(on)
    local want = {}
    if on then
        for _, e in ipairs(auraEffects()) do
            if e.sound and Procs.EffectOn(e.key) then
                for _, a in ipairs(e.auras) do want[e.unit .. ":" .. a] = { e.unit, a } end
            end
        end
    end
    -- A removal that throws keeps its id, for the next Apply to retry.
    local remove = C_UnitAuras and C_UnitAuras.RemoveAuraSound
    for k, ids in pairs(st.sounds) do
        if not want[k] then
            local left = {}
            for _, id in ipairs(ids) do
                local ok, err = pcall(remove or error, id)
                if not ok then left[#left + 1] = id; API.Fail("procs:sound", err) end
            end
            st.sounds[k] = #left > 0 and left or nil
        end
    end
    local add = C_UnitAuras and C_UnitAuras.AddAuraSound
    local T = Enum and Enum.UnitAuraSoundTrigger
    for k, w in pairs(want) do
        if not st.sounds[k] then
            local ids = {}
            for i, trig in ipairs({ T and T.Added or 0, T and T.ApplicationsIncreased or 1 }) do
                local ok, id = pcall(add or error, trig, { unitToken = w[1], spellID = w[2], soundFileID = Procs.SOUND_FILE })
                if ok and id ~= nil and not API.IsSecret(id) then
                    ids[#ids + 1] = id
                else
                    API.Fail("procs:sound", ok and ("AddAuraSound refused " .. k .. " trigger " .. i) or id)
                end
            end
            st.sounds[k] = ids
        end
    end
end

-- ------------------------------------------------------------------
-- Counters (PR 3, docs/PLAN-procs.md "Counter effects"): shown while the
-- spell is known, usable and off its real cooldown (SAO's
-- variables/actionusable.lua). Every value read is one Blizzard's API docs
-- (71037) mark plain, checked with issecretvalue anyway: a secret turns the
-- counter off for that pass and is counted for /gab procs, never compared or
-- kept. A combatOnly counter shows in combat only.

Procs.RECHECK = 0.5    -- a waiting counter's re-check when its cooldown's end is unreadable (SAO's)
Procs.MARGIN = 0.05    -- past the cooldown's end, so the re-check doesn't land just before it

local cs = {}          -- counter key -> { e, on (as applied), active, cd, waitAt, frames, reads }
local rings = setmetatable({}, { __mode = "k" })   -- button -> its counter ring's holder
local activeSpells = {}                            -- cast spell id -> true: the ranks of every active counter
local queued = false

local function counter(e)
    local c = cs[e.key]
    if not c then
        c = { e = e, active = false, frames = {}, reads = { plain = 0, secret = 0, unresolved = 0 } }
        cs[e.key] = c
    end
    return c
end

-- A read the docs call plain came back secret: counted for /gab procs.
local function secretRead(c)
    if c then c.reads.secret = c.reads.secret + 1 end
end

-- The highest rank known (the data lists them lowest first).
local function knownRank(e, c)
    local known = C_SpellBook and C_SpellBook.IsSpellKnown
    if not known then return nil end
    for i = #e.spell, 1, -1 do
        local ok, k = pcall(known, e.spell[i])
        if ok and API.IsSecret(k) then secretRead(c)
        elseif ok and k == true then return e.spell[i] end
    end
    return nil
end

-- SAO's: a spell short of rage, energy or focus still shows; short of mana
-- it doesn't. Unreadable: as if it cost mana (not shown on low power).
local manaCost = {}
local function costsMana(id, c)
    if manaCost[id] ~= nil then return manaCost[id] end
    local ok, costs = pcall(C_Spell and C_Spell.GetSpellPowerCost or error, id)
    if ok and API.IsSecret(costs) then secretRead(c); return true end
    if not ok or type(costs) ~= "table" then return true end
    local mana = false
    for _, cost in ipairs(costs) do
        local name = type(cost) == "table" and cost.name
        if API.IsSecret(name) then secretRead(c); return true end
        if name == "MANA" then mana = true end
    end
    manaCost[id] = mana
    return mana
end

-- isActive and isOnGCD are NeverSecret (SpellSharedDocumentation.lua), but
-- isOnGCD is trusted only inside SPELL_UPDATE_COOLDOWN (the same docs): it's
-- classified there and kept (c.cd).
local function noteCooldown(c, id)
    local ok, info = pcall(C_Spell and C_Spell.GetSpellCooldown or error, id)
    if not ok or type(info) ~= "table" then return end
    local active, gcd = info.isActive, info.isOnGCD
    if API.IsSecret(active) or API.IsSecret(gcd) then secretRead(c); c.cd = nil; return end
    if active == false then c.cd = "clear"
    elseif gcd == true then c.cd = "clear"
    elseif gcd == false then c.cd = "cd"
    else c.cd = nil end
end

-- "clear", "cd" or nil (unresolved), and the cooldown's end when readable.
-- A plain isActive false clears it anywhere; an active one asks the duration
-- without the GCD when that's readable, else keeps the event's classification.
-- A secret isActive (documented NeverSecret) is counted; the duration
-- object's own restriction stays merely unresolved.
local function cooldown(c, id)
    local ok, info = pcall(C_Spell and C_Spell.GetSpellCooldown or error, id)
    if not ok or type(info) ~= "table" then return nil end
    if API.IsSecret(info.isActive) then secretRead(c); return nil, nil, true end
    if info.isActive == false then c.cd = "clear"; return "clear" end
    local okD, d = pcall(C_Spell.GetSpellCooldownDuration or error, id, true)
    if okD and d ~= nil and not API.IsSecret(d) then
        local okS, secret = pcall(d.HasSecretValues, d)
        if okS and secret == false then
            local okA, a = pcall(d.IsActive, d)
            if okA and type(a) == "boolean" then
                local okE, endTime = pcall(d.GetEndTime, d)
                return a and "cd" or "clear", okE and type(endTime) == "number" and endTime or nil
            end
        end
    end
    return c.cd
end

local request
-- One re-check per waiting counter, the earliest asked for.
local function wait(c, endTime)
    local now = GetTime()
    local at = endTime and (math.max(endTime, now) + Procs.MARGIN) or (now + Procs.RECHECK)
    if c.waitAt and c.waitAt <= at and c.waitAt > now then return end
    c.waitAt = at
    C_Timer.After(at - now, function()
        if c.waitAt == at then c.waitAt = nil; request() end
    end)
end

local function decide(c)
    local e = c.e
    if not c.on then return false end   -- as applied: a change in combat waits (apply)
    if e.combatOnly and not API.InCombat() then return false end
    local id = knownRank(e, c)
    if not id then return false end
    local ok, usable, noPower = pcall(C_Spell and C_Spell.IsSpellUsable or error, id)
    if not ok then return false end
    if API.IsSecret(usable) or API.IsSecret(noPower) then secretRead(c); return false end
    c.reads.plain = c.reads.plain + 1
    if not (usable == true or (noPower == true and not costsMana(id, c))) then return false end
    local cd, endTime, secret = cooldown(c, id)
    if cd == "clear" then return true end
    if cd == nil and not secret then c.reads.unresolved = c.reads.unresolved + 1 end
    wait(c, endTime)
    return false
end

local function showCounter(c)
    local on = c.active and st.applied.overlays
    for _, o in ipairs(c.frames) do
        if on then
            o.frame:Show()
            if o.pulse then o.pulse:Stop(); o.pulse:Play() end
        else
            o.frame:Hide()
        end
    end
end

function paintRing(b)
    local holder = rings[b]
    if not holder then return end
    local spell = st.applied.glow and spellOf(b)
    if spell and activeSpells[spell] then holder:Show() else holder:Hide() end
end

-- Every counter decided again; what changed is shown, the sound played on a
-- counter turning on (a repaint, applyCounters, changes nothing here).
local function pass()
    queued = false
    if not st.built.counters then return end
    local changed = false
    for _, c in pairs(cs) do
        local was = c.active
        local ok, now = pcall(decide, c)
        if not ok then API.Fail("procs:counter:" .. c.e.key, now) end
        now = ok and now == true
        if now ~= was then
            c.active, changed = now, true
            showCounter(c)
            if now and c.e.sound and st.applied.sound then
                pcall(PlaySoundFile, Procs.SOUND_FILE, "Master")
            end
        end
    end
    if changed then
        activeSpells = {}
        for _, c in pairs(cs) do
            if c.active then for _, id in ipairs(c.e.spell) do activeSpells[id] = true end end
        end
        for b in pairs(rings) do paintRing(b) end
    end
end

-- Coalesced: one pass on the next frame.
function request()
    if queued or not st.built.counters then return end
    queued = true
    C_Timer.After(0, pass)
end

local function buildCounterOverlays()
    local box = CreateFrame("Frame", nil, UIParent)
    box:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    box:EnableMouse(false)
    st.counterBox = box
    for _, e in ipairs(counterEffects()) do
        local c = counter(e)
        for i, spec in ipairs(e.overlays or {}) do
            local f = CreateFrame("Frame", nil, box)
            f:EnableMouse(false)
            f:SetFrameLevel(box:GetFrameLevel() + (spec.level or Procs.LEVEL))
            local t = f:CreateTexture(nil, "ARTWORK")
            t:SetAllPoints(f)
            t:SetTexture(spec.texture)
            texCoords(t, spec)
            local col = spec.color
            if col then t:SetVertexColor(col[1] / 255, col[2] / 255, col[3] / 255, (col[4] or 255) / 255) end
            local o = { frame = f, spec = spec, container = box, key = e.key .. ":" .. i }
            if spec.pulse then o.pulse = pulse(t); o.pulse:Stop() end
            f:Hide()
            c.frames[#c.frames + 1] = o
            st.counterFrames[#st.counterFrames + 1] = o
            placeOverlay(o)
        end
    end
end

-- A ring holder on each button of bars 1-8, hidden; shown by paintRing.
local function buildRings()
    for _, b in ipairs(stockButtons()) do
        local ok, err = pcall(function()
            local w, h = b:GetSize()
            local holder = CreateFrame("Frame", nil, b)
            holder:SetAllPoints(b)
            holder:SetFrameLevel(b:GetFrameLevel() + Procs.LEVEL_UP)
            holder:EnableMouse(false)
            makeRing(holder, w, h)
            holder:Hide()
            rings[b] = holder
        end)
        if not ok then API.Fail("procs:counterglow:" .. tostring(b:GetName()), err) end
        hookButton(b)
    end
end

-- Built (out of combat, once each) only when a counter is on; then every
-- counter shown afresh from the applied switches.
local function applyCounters()
    local list = counterEffects()
    if #list == 0 then return end
    local any = false
    for _, e in ipairs(list) do
        local c = counter(e)
        c.on = Procs.EffectOn(e.key)   -- the passes read this, never the live setting
        any = any or c.on
    end
    if not any and not st.built.counters then return end
    st.built.counters = true
    if st.applied.overlays and not st.built.counterOverlays then
        st.built.counterOverlays = true
        buildCounterOverlays()
        placeContainers()
    end
    if st.applied.glow and not st.built.rings then
        st.built.rings = true
        buildRings()
    end
    if st.counterBox then placeContainers() end
    for _, c in pairs(cs) do showCounter(c) end   -- to the switches as applied now
    for b in pairs(rings) do paintRing(b) end
    request()                                     -- an unticked counter goes out there
end

-- ------------------------------------------------------------------
-- Apply: everything to the settings, or queued.

local function encounterOn()
    local R, E = C_RestrictedActions, Enum and Enum.AddOnRestrictionType
    if not (R and R.IsAddOnRestrictionActive and E and E.Encounter) then return false end
    local ok, on = pcall(R.IsAddOnRestrictionActive, E.Encounter)
    if not ok or API.IsSecret(on) then return true end   -- unreadable: wait, the safe side
    return on == true
end

function Procs.Waiting() return st.pending end

-- The options page's note follows the queue (Options sets this).
Procs.OnQueueChanged = nil
local function setPending(v)
    local was = st.pending
    st.pending = v
    if was ~= v and Procs.OnQueueChanged then API.Try("procs:notice", Procs.OnQueueChanged) end
end

-- askEncounter = false only from the restriction event's handler, where the
-- question always answers false.
local function apply(askEncounter)
    if API.InCombat() or (askEncounter ~= false and encounterOn()) then
        setPending(true)
        return "queued"
    end
    setPending(false)
    local any = false
    for _, f in ipairs(Procs.FEATURES) do any = any or Procs.Enabled(f) end
    if #Procs.Effects() == 0 then return "no effects" end
    -- The engine only for aura effects: a class with counters alone (the
    -- warrior) never loads it, and a refusal leaves its counters working.
    local auras = #auraEffects() > 0
    local engine = auras and (not (any or st.built.overlays or st.built.glow) or loadEngine())
    rebuildIndex()
    -- Applied first, so the glow's own retarget pass (applyGlow) sees it on.
    for _, f in ipairs(Procs.FEATURES) do st.applied[f] = Procs.Enabled(f) end
    if engine then
        API.Try("procs:overlays", applyOverlays, st.applied.overlays)
        API.Try("procs:glow", applyGlow, st.applied.glow)
        API.Try("procs:sound", applySounds, st.applied.sound)
    end
    API.Try("procs:counters", applyCounters)
    if auras and not engine then return "no engine" end
    return "applied"
end

function Procs.Apply()
    if not st.started then return "not started" end
    return apply()
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event, a1, a2)
    API.NoteCombat(event)
    if event == "PLAYER_TARGET_CHANGED" then
        C_Timer.After(0, refreshTarget)
    elseif event == "PLAYER_REGEN_ENABLED" then
        if st.pending then apply() end
    elseif event == "ADDON_RESTRICTION_STATE_CHANGED" then
        -- The payload, never IsAddOnRestrictionActive (false during this
        -- dispatch). Waking isn't applying: apply still waits for a fight.
        local E, S = Enum and Enum.AddOnRestrictionType, Enum and Enum.AddOnRestrictionState
        if st.pending and E and S and a1 == E.Encounter and a2 == S.Inactive then apply(false) end
    end
    if st.built.counters then
        -- isOnGCD is trusted here only: each counter's cooldown classified now.
        if event == "SPELL_UPDATE_COOLDOWN" then
            for _, c in pairs(cs) do
                local id = c.on and knownRank(c.e, c)
                if id then API.Try("procs:cooldown", noteCooldown, c, id) end
            end
        end
        request()
    end
end)

local function saoLoaded()
    local ok, loaded = pcall(C_AddOns and C_AddOns.IsAddOnLoaded or error, "SpellActivationOverlay")
    return ok and loaded == true
end

function Procs.SAOLoaded() return st.sao end

function Procs.Start()
    if st.started then return end
    st.started = true
    st.sao = saoLoaded()
    local names = { "PLAYER_TARGET_CHANGED", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
        "ADDON_RESTRICTION_STATE_CHANGED" }
    if #counterEffects() > 0 then
        for _, n in ipairs({ "SPELL_UPDATE_USABLE", "SPELL_UPDATE_COOLDOWN", "SPELLS_CHANGED",
            "PLAYER_ENTERING_WORLD" }) do names[#names + 1] = n end
    end
    API.RegisterEvents(events, names, "procs")
    apply()
end

-- /gab procs: what each overlay slot reports, read out of combat (a slot
-- frame's IsShown is secret in combat). Every read guarded: a refusal or a
-- secret prints as such.
local function read(f, method, ...)
    local ok, a, b, c, d, e = pcall(f[method], f, ...)
    if not ok then return "error" end
    if API.IsSecret(a) then return "secret" end
    return a, b, c, d, e
end
local function where(f, c)
    local point, rel, relPoint, x, y = read(f, "GetPoint", 1)
    if point == nil or point == "error" or point == "secret" then return tostring(point) end
    local relName = rel == UIParent and "UIParent" or rel == c and "container" or tostring(rel)
    local left, bottom = read(f, "GetLeft"), read(f, "GetBottom")
    local num = function(v) return type(v) == "number" and ("%.0f"):format(v) or tostring(v) end
    return ("%s of %s %s %s,%s; left %s bottom %s"):format(tostring(point), relName, tostring(relPoint), num(x), num(y),
        num(left), num(bottom))
end
function Procs.Report()
    local lines = {}
    local function add(s) lines[#lines + 1] = s end
    add(("procs: overlays %s, glow %s, sound %s, SAO %s, engine %s, waiting %s"):format(tostring(Procs.Enabled("overlays")),
        tostring(Procs.Enabled("glow")), tostring(Procs.Enabled("sound")), tostring(st.sao), tostring(st.engine),
        tostring(st.pending)))
    for unit, c in pairs(st.overlay) do
        add(("%s container: shown %s, alpha %s, %s"):format(unit, tostring(read(c, "IsShown")), tostring(read(c, "GetAlpha")),
            where(c, UIParent)))
    end
    for _, o in ipairs(st.frames) do
        local c, f = o.container, o.frame
        local effect = o.key:match("^(.-):")
        add(("%s: setting %s, engine %s, its frame %s, shown %s, visible %s, at %s"):format(o.key,
            Procs.EffectOn(effect) and "on" or "off", tostring(read(c, "IsAuraSlotEnabled", o.key)),
            read(c, "GetAuraSlotFrame", o.key) == f and "same" or "OTHER", tostring(read(f, "IsShown")),
            tostring(read(f, "IsVisible")), where(f, c)))
    end
    -- Counters: what the reads gave since login (the probe's question,
    -- answered by play: docs/PLAN-procs.md "Counter effects").
    for _, e in ipairs(counterEffects()) do
        local c = cs[e.key]
        local r = c and c.reads or { plain = 0, secret = 0, unresolved = 0 }
        add(("counter %s: setting %s, rank %s, active %s, cooldown %s; reads plain %d, secret %d, unresolved %d"):format(
            e.key, Procs.EffectOn(e.key) and "on" or "off", tostring(knownRank(e) or "none"), tostring(c and c.active or false),
            tostring(c and c.cd or "?"), r.plain, r.secret, r.unresolved))
    end
    return lines
end

Procs._test = { st = st, side = side, retarget = retarget, refreshTarget = refreshTarget,
    counters = cs, rings = rings, pass = pass, active = function() return activeSpells end,
    index = function() return glowIndex end, encounterOn = encounterOn }
