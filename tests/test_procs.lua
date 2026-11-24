-- Proc alerts (#115, docs/PLAN-procs.md): the overlays, the button glow and
-- the sound, built from the mage's data; each button's filter following its
-- spell (in combat too), the target refresh, the switches off and on, the
-- queue for combat and a boss's Encounter restriction, the saved settings,
-- SpellActivationOverlay's default, and nothing written on Blizzard frames.
-- The engine's own decisions (a slot shown while its aura is up) belong to
-- the live client: docs/FOREVER-PROBE.md session 10.

local ICE_LANCE, FROSTBOLT = 1240044, 116
local GAB

-- A fresh client: stubs, then the addon loaded as `class`.
local function fresh(opts)
    opts = opts or {}
    dofile("tests/wow_stubs.lua")
    dofile("tests/harness.lua")
    GlassActionBars, GlassActionBarsDB = nil, nil   -- a new client: no addon table, no saved settings
    WoW.playerClass = opts.class or "MAGE"
    if opts.sao then WoW.loaded.SpellActivationOverlay = true end
    WoW.refuseLoad = opts.refuseLoad
    WoW.slotThrows = opts.slotThrows
    WoW.actionSpells[3] = ICE_LANCE
    WoW.actionSpells[7] = FROSTBOLT
    GAB = loadAddon({ db = opts.db })
    return GAB.Procs
end

local function count(t) local n = 0; for _ in pairs(t) do n = n + 1 end; return n end
local function slotsOn(c)
    local n = 0
    for _, s in pairs(c._slots) do if s.enabled then n = n + 1 end end
    return n
end
-- A button's own fields; Update is left out: hooksecurefunc wraps it (the
-- client's own mechanism, the plan's hook), which writes nothing of ours.
local function fields(w)
    local t = {}
    for k, v in pairs(w) do
        if not (type(k) == "string" and k:sub(1, 1) == "_") and k ~= "Update" then t[k] = v end
    end
    return t
end
local function sameFields(a, b)
    for k, v in pairs(a) do if b[k] ~= v then return false end end
    for k, v in pairs(b) do if a[k] ~= v then return false end end
    return true
end

-- A class with no aura effects (the warrior's are all counters, PR 3):
-- nothing built, the page says so.
local P = fresh({ class = "WARRIOR" })
eq(#WoW.containers, 0, "a class with no effects: no container")
eq(next(WoW.auraSounds), nil, "  no sound")
GAB.Options.procsPage:Show()
eq(count(GAB.Options._test.procEffects), 0, "  no effect on the page")

-- The engine refused: recorded, nothing built.
P = fresh({ refuseLoad = "MISSING" })
eq(#WoW.containers, 0, "the engine refused: no container")
check(GAB.failures["procs:engine"] and GAB.failures["procs:engine"]:find("MISSING"), "  recorded through API.Fail")

-- A mage, SpellActivationOverlay off: all three on by default.
P = fresh()
local T = P._test
eq(next(GAB.failures), nil, "a mage: nothing failed")
check(WoW.loaded.Blizzard_AuraContainer == true and T.st.engine == true, "  the engine loaded first")
check(P.Enabled("overlays") and P.Enabled("glow") and P.Enabled("sound"), "  overlays, glow and sound on by default")
eq(rawget(GAB.db, "procs"), nil, "  nothing saved")

-- Overlays: a container per unit under UIParent, a slot per (effect, overlay).
local OP, OT = T.st.overlay.player, T.st.overlay.target
check(OP and OT and OP:GetParent() == UIParent and OT:GetParent() == UIParent, "overlays: a player and a target container")
check(OP._unit == "player" and OT._unit == "target" and OP._enabled and OT._enabled and OP:IsShown(), "  their units, enabled, shown")
check(OP:IsMouseEnabled() == false and OT:IsMouseEnabled() == false, "  click-through")
eq(count(OP._slots), 14, "  14 player slots: barrage 2, clearcasting 2, Fingers 2, Heating Up 6, Revelation 2")
eq(count(OT._slots), 1, "  one target slot: the freeze")
local fz = OT._slots["freeze:1"]
check(fz.filter == "HARMFUL" and fz.ids[865] and fz.ids[5276] == nil, "  the freeze: harmful, its aliases, not SAO's stand-in")
local fof1, fof2 = OP._slots["fingers_of_frost:1"], OP._slots["fingers_of_frost:2"]
check(fof1.filter == "HELPFUL" and fof1.ids[400670] and fof1.frame._bar == nil, "  Fingers left: any charge")
check(fof2.frame._bar and fof2.frame._bar.min == 2, "  Fingers right: at 2 charges, in an application bar")
eq(OP._slots["heating_up:1"].frame._bar, nil, "  Heating Up's first layer: any stack")
check(OP._slots["heating_up:5"].frame._bar.min == 3, "  its top layer at 3")
check(fof1.frame:IsMouseEnabled() == false, "  a slot frame clicks through")
local p = fof1.frame._points[1]
check(p[1] == "RIGHT" and p[2] == OP and p[3] == "LEFT", "  left: right edge on the container's left")
check(math.abs(fof1.frame._width - 102.4) < 0.01 and math.abs(fof1.frame._height - 204.8) < 0.01, "  SAO's 128 x 256 at 0.8")
local top = fz.frame._points[1]
check(top[1] == "BOTTOM" and top[3] == "TOP" and fz.frame._width > fz.frame._height, "  the freeze above, lying")
local mb = OP._slots["missile_barrage:1"].frame._points[1]
check(math.abs(mb[4] + 0.32 * 102.4) < 0.01, "  Missile Barrage pushed out by SAO's outer")
check(math.abs(OP._width - 204.8) < 0.01 and OP:GetAlpha() == 1, "  the container SAO's size, opaque")
local lvl = OP:GetFrameLevel()
eq(OP._slots["missile_barrage:1"].frame:GetFrameLevel() - lvl, 5, "  SAO's draw levels: Missile Barrage at 5")
eq(OP._slots["clearcasting:1"].frame:GetFrameLevel() - lvl, 7, "  Clearcasting at 7, over it")
eq(fof1.frame:GetFrameLevel() - lvl, 3, "  Fingers of Frost at the default 3")
local rv = OP._slots["revelation:2"]
local rvt = rv.frame._regions[1]
check(rv.ids[1248808] and rvt._vertex and math.abs(rvt._vertex[2] - 145 / 255) < 1e-6 and rvt._vertex[4] == 1,
    "  Revelation: the mage's enchant buff, SAO's pink, opaque")

-- The glow: every stock button of bars 1-8, a player and a target container.
local s3 = T.side[ActionButton3]
check(s3 and s3.player and s3.target, "glow: Action Bar 1's button 3 has both")
eq(count(T.side), 96, "  every button of bars 1-8")
check(s3.player:GetParent() == ActionButton3 and s3.player:GetFrameLevel() == ActionButton3:GetFrameLevel() + 5,
    "  a child of the button, over the glass")
check(s3.player:IsMouseEnabled() == false, "  click-through")
local gp, gt = s3.player._slots.glow, s3.target._slots.glow
check(gp.enabled and gp.filter == "HELPFUL" and gp.ids[400670] and count(gp.ids) == 1, "  Ice Lance's player slot: Fingers of Frost")
check(gt.enabled and gt.filter == "HARMFUL" and gt.ids[865] and gt.ids[5276] == nil, "  its target slot: the freeze")
local s7 = T.side[ActionButton7]
check(s7.player._slots.glow.enabled == false and s7.target._slots.glow.enabled == false, "  Frostbolt: both off")
check(T.side[MultiBarBottomLeftButton3].player._slots.glow.enabled, "  a second Ice Lance on another bar glows too")
check(gp.frame:IsMouseEnabled() == false, "  the slot frame clicks through")

-- Paging: the button's own Update retargets; an unchanged spell isn't written.
local w0 = WoW.slotWrites
WoW.actionSpells[3] = FROSTBOLT
ActionButton3:Update()
check(gp.enabled == false and gt.enabled == false, "paging away: both slots off")
local w1 = WoW.slotWrites
ActionButton3:Update()
eq(WoW.slotWrites, w1, "  an unchanged spell isn't written again")
check(w1 > w0, "  the change was written")
WoW.actionSpells[3] = ICE_LANCE
WoW.combat = true
local v0 = #WoW.violations
ActionButton3:Update()
check(gp.enabled and gt.enabled and gp.ids[400670], "  back to Ice Lance, in combat: on again with its filter")
eq(#WoW.violations, v0, "  no protected change")
WoW.actionSpells[3] = WoW.Secret("slot")
ActionButton3:Update()
check(gp.enabled == false, "  a secret spell: off")
WoW.actionSpells[3] = ICE_LANCE
ActionButton3:Update()
WoW.combat = false

-- The target: its containers refreshed a frame later.
local rt, rp, ro = s3.target._refreshes, s3.player._refreshes, OT._refreshes
local r7 = s7.target._refreshes
WoW.fire("PLAYER_TARGET_CHANGED")
eq(s3.target._refreshes, rt, "target change: nothing this frame")
WoW.flushTimers(0)
eq(s3.target._refreshes, rt + 1, "  a glowing button's target container refreshed")
eq(OT._refreshes, ro + 1, "  the target overlay too")
eq(s3.player._refreshes, rp, "  not the player's")
eq(s7.target._refreshes, r7, "  nor a button with nothing to glow")

-- The sound: on Added and ApplicationsIncreased, the effects that have one.
local function soundsFor(id)
    local t = {}
    for _, s in pairs(WoW.auraSounds) do if s.info.spellID == id then t[#t + 1] = s end end
    return t
end
eq(count(WoW.auraSounds), 6, "sound: two triggers each for Missile Barrage, Fingers of Frost, Heating Up")
local fs = soundsFor(400670)
check(#fs == 2 and fs[1].info.soundFileID == 568016 and fs[1].info.unitToken == "player", "  the game's file, on the player")
check((fs[1].trigger == 0 and fs[2].trigger == 1) or (fs[1].trigger == 1 and fs[2].trigger == 0), "  Added and ApplicationsIncreased")
eq(#soundsFor(865), 0, "  none for the freeze")

-- An effect off: its slots, its glow and its sound go; the others stay.
local Settings = GAB.Settings
check(Settings.SetProcEffect("fingers_of_frost", false), "effect off: Fingers of Frost")
check(fof1.enabled == false and fof2.enabled == false, "  its overlay slots off")
check(gp.enabled == false and gt.enabled, "  Ice Lance's player slot off, the freeze still on")
eq(#soundsFor(400670), 0, "  its sound removed")
check(OP._slots["clearcasting:1"].enabled, "  another effect untouched")
check(GAB.db.procs.off.fingers_of_frost == true, "  saved")
check(Settings.SetProcEffect("fingers_of_frost", true), "  back on")
check(fof1.enabled and gp.enabled and gp.ids[400670] and #soundsFor(400670) == 2, "  slots, glow and sound back")
eq(rawget(GAB.db, "procs"), nil, "  nothing left saved")
check(Settings.SetProcEffect("hot_streak", false) == false, "  an unknown effect: refused")

-- Each switch off, then on: disabled and hidden, then shown and enabled.
check(Settings.SetProc("overlays", false), "overlays off")
check(not OP:IsShown() and OP._enabled == false and not OT:IsShown() and OT._enabled == false, "  both containers off")
check(Settings.SetProc("overlays", true), "  on again")
check(OP:IsShown() and OP._enabled and OT:IsShown() and OT._enabled, "  shown and enabled")
check(Settings.SetProc("glow", false), "glow off")
local off = 0
for _, s in pairs(T.side) do if s.player:IsShown() or s.player._enabled or s.target:IsShown() then off = off + 1 end end
eq(off, 0, "  every button's containers off")
WoW.actionSpells[7] = ICE_LANCE
ActionButton7:Update()
eq(s7.player._slots.glow.enabled, false, "  a page change while off writes nothing")
check(Settings.SetProc("glow", true), "  on again")
check(s3.player:IsShown() and s3.player._enabled and s7.player._slots.glow.enabled, "  shown, enabled, and retargeted")
WoW.actionSpells[7] = FROSTBOLT
ActionButton7:Update()
check(Settings.SetProc("sound", false) and next(WoW.auraSounds) == nil, "sound off: every registration removed")
check(Settings.SetProc("sound", true) and count(WoW.auraSounds) == 6, "  on again: back")
check(Settings.SetProc("bogus", true) == false and Settings.SetProc("glow", "yes") == false, "  a bad switch refused")

-- The look: opacity, size, spacing; a default isn't saved.
check(Settings.SetProcLook("opacity", 0.5) and OP:GetAlpha() == 0.5, "look: opacity on the containers")
check(Settings.SetProcLook("scale", 1.25) and math.abs(fof1.frame._width - 128) < 0.01, "  size: the slots")
check(Settings.SetProcLook("offset", 60) and math.abs(OP._width - 264.8) < 0.01, "  spacing: the container")
check(Settings.SetProcLook("scale", 0.9) == false, "  a value not offered: refused")
Settings.SetProcLook("opacity", 1); Settings.SetProcLook("scale", 1); Settings.SetProcLook("offset", 0)
local pl = rawget(GAB.db, "procs")
check(pl.opacity == nil and pl.scale == nil and pl.offset == nil, "  defaults not saved")
check(pl.overlays == true and pl.glow == true and pl.sound == true, "  the switches set back on: saved as explicit trues")

-- In combat a change waits for the fight's end.
WoW.combat = true
WoW.fire("PLAYER_REGEN_DISABLED")
Settings.SetProc("overlays", false)
check(OP:IsShown() and P.Waiting(), "combat: a change waits")
eq(GAB.db.procs.overlays, false, "  saved already")
WoW.combat = false
WoW.fire("PLAYER_REGEN_ENABLED")
check(not OP:IsShown() and not P.Waiting(), "  applied when it ends")
Settings.SetProc("overlays", true)

-- While a change waits, the alerts still on screen keep following: a page
-- change retargets the glow, a target change refreshes the target containers
-- (Codex, PR #124: Frostbolt could inherit Ice Lance's ring).
WoW.combat = true
WoW.fire("PLAYER_REGEN_DISABLED")
Settings.SetProc("glow", false)
Settings.SetProc("overlays", false)
check(P.Waiting() and s3.player:IsShown() and OP:IsShown(), "queued off: the glow and overlays still on screen")
WoW.actionSpells[3] = FROSTBOLT
ActionButton3:Update()
check(gp.enabled == false and gt.enabled == false, "  paging away still clears the ring")
WoW.actionSpells[3] = ICE_LANCE
ActionButton3:Update()
check(gp.enabled and gt.enabled, "  and paging back lights it")
rt, ro = s3.target._refreshes, OT._refreshes
WoW.fire("PLAYER_TARGET_CHANGED")
WoW.flushTimers(0)
check(s3.target._refreshes == rt + 1 and OT._refreshes == ro + 1, "  a target change still refreshes both")
WoW.combat = false
WoW.fire("PLAYER_REGEN_ENABLED")
check(not s3.player:IsShown() and not OP:IsShown() and not P.Waiting(), "  applied when the fight ends")
WoW.actionSpells[3] = FROSTBOLT
ActionButton3:Update()
check(gp.enabled, "  then a page change while off writes nothing")
Settings.SetProc("glow", true)
Settings.SetProc("overlays", true)
WoW.actionSpells[3] = ICE_LANCE
ActionButton3:Update()

-- At a boss: the Encounter restriction holds it. Only its own Inactive wakes
-- it, read from the payload (the question answers false during that event).
local R, S = Enum.AddOnRestrictionType, Enum.AddOnRestrictionState
local function held() return OP:IsShown() and P.Waiting() end
WoW.encounter = true
Settings.SetProc("overlays", false)
check(held(), "encounter: a change waits")
WoW.fire("ADDON_RESTRICTION_STATE_CHANGED", R.Combat, S.Inactive)
check(held(), "  another type's Inactive: still waiting")
WoW.fire("ADDON_RESTRICTION_STATE_CHANGED", R.Encounter, S.Activating)
WoW.fire("ADDON_RESTRICTION_STATE_CHANGED", R.Encounter, S.Active)
check(held(), "  Activating and Active: still waiting")
WoW.fire("ADDON_RESTRICTION_STATE_CHANGED", R.Encounter, S.Inactive)   -- WoW.encounter still true: not asked
check(not OP:IsShown() and not P.Waiting(), "  Encounter Inactive out of combat: applied")
WoW.encounter = false
Settings.SetProc("overlays", true)

WoW.encounter = true
Settings.SetProc("overlays", false)
WoW.combat = true
WoW.fire("PLAYER_REGEN_DISABLED")
WoW.fire("ADDON_RESTRICTION_STATE_CHANGED", R.Encounter, S.Inactive)
check(held(), "Encounter Inactive in combat: waits for the fight")
WoW.encounter, WoW.combat = false, false
WoW.fire("PLAYER_REGEN_ENABLED")
check(not OP:IsShown() and not P.Waiting(), "  applied at the fight's end")
Settings.SetProc("overlays", true)

WoW.encounter = true
Settings.SetProc("overlays", false)
WoW.combat = true
WoW.fire("PLAYER_REGEN_DISABLED")
WoW.combat = false
WoW.fire("PLAYER_REGEN_ENABLED")
check(held(), "a fight's end with the Encounter still on: waits")
WoW.encounter = false
WoW.fire("ADDON_RESTRICTION_STATE_CHANGED", R.Encounter, S.Inactive)
check(not OP:IsShown() and not P.Waiting(), "  applied when it ends")
Settings.SetProc("overlays", true)

-- The options page: the switches, the look and the class's effects.
local O = GAB.Options
O.procsPage:Show()
local ot = O._test
check(ot.procSwitches.overlays:GetChecked() and ot.procSwitches.glow:GetChecked(), "page: the switches read")
eq(count(ot.procEffects), 6, "  the mage's six effects")
ot.procEffects.clearcasting:SetChecked(false)
ot.procEffects.clearcasting:GetScript("OnClick")(ot.procEffects.clearcasting)
check(GAB.db.procs.off.clearcasting and not OP._slots["clearcasting:1"].enabled, "  an effect unticked from the page")
ot.procSwitches.sound:SetChecked(false)
ot.procSwitches.sound:GetScript("OnClick")(ot.procSwitches.sound)
check(GAB.db.procs.sound == false and next(WoW.auraSounds) == nil, "  the sound unticked from the page")
-- The note follows the queue while the page is open (Codex, PR #124).
local function noteWaits() return (ot.procNote:GetText() or ""):find("waits") ~= nil end
check(not noteWaits(), "  the note: nothing waiting")
WoW.combat = true
WoW.fire("PLAYER_REGEN_DISABLED")
ot.procSwitches.sound:SetChecked(true)
ot.procSwitches.sound:GetScript("OnClick")(ot.procSwitches.sound)
check(noteWaits(), "  a change queued from the open page: the note says it waits")
WoW.combat = false
WoW.fire("PLAYER_REGEN_ENABLED")
check(not noteWaits() and count(WoW.auraSounds) == 6, "  applied at the fight's end: the note clears")

-- /gab procs: a line per overlay slot, our setting beside the engine's.
local chat0 = #WoW.chat
SlashCmdList.GLASSACTIONBARS("procs")
local report = table.concat(WoW.chat, "\n", chat0 + 1)
check(report:find("player container: shown true, alpha 1, CENTER of UIParent CENTER 0,0") and report:find("target container: shown true"),
    "/gab procs: the containers, where they are")
check(report:find("clearcasting:1: setting off, engine false, its frame same"), "  an unticked effect: off in both")
check(report:find("fingers_of_frost:2: setting on, engine true, its frame same, shown %a+, visible %a+, at LEFT of container RIGHT 0,0"),
    "  a ticked one: on, shown or not, where it's anchored")
local lines = 0
for _ in report:gmatch("setting %a+, engine") do lines = lines + 1 end
eq(lines, 15, "  all 15 slots")

-- Nothing written on a Blizzard frame, no protected change.
eq(#WoW.violations, 0, "no protected change in the whole run")

-- A slot the engine refuses (as an OnShow hook made it, in play): recorded,
-- its half-made frame hidden, the other slots built, and no retry at the
-- next change (each retry left another frame shown).
P = fresh({ slotThrows = { ["missile_barrage:1"] = 1 } })
check(GAB.failures["procs:slot:missile_barrage:1"] and GAB.failures["procs:slot:missile_barrage:1"]:find("refused"),
    "a refused slot: recorded")
local orphan = WoW.slotFrames[1]
check(orphan.key == "missile_barrage:1" and not orphan.frame:IsShown(), "  its frame hidden")
OP = P._test.st.overlay.player
check(count(OP._slots) == 13 and OP._slots["missile_barrage:2"] and P._test.st.overlay.target, "  the other slots built")
for _, o in ipairs(P._test.st.frames) do check(o.key ~= "missile_barrage:1", "  and forgotten") end
local made = #WoW.slotFrames
GAB.Settings.SetProcLook("opacity", 0.5)
GAB.Settings.SetProc("overlays", false)
GAB.Settings.SetProc("overlays", true)
eq(#WoW.slotFrames, made, "  no rebuild at later changes")

-- A glow slot refused on one button: that button's containers off, the others built.
P = fresh({ slotThrows = { glow = 1 } })
local gk
for k in pairs(GAB.failures) do if k:find("^procs:glow:") then gk = k end end
check(gk == "procs:glow:ActionButton1", "a refused glow: recorded for its button (" .. tostring(gk) .. ")")
eq(count(P._test.side), 95, "  the 95 other buttons built")
local leftOn = 0
for _, c in ipairs(WoW.containers) do
    if c:GetParent() == ActionButton1 and (c:IsShown() or c._enabled) then leftOn = leftOn + 1 end
end
eq(leftOn, 0, "  its containers disabled and hidden")
check(P._test.side[ActionButton3].player._slots.glow.enabled, "  Ice Lance still glows elsewhere")

-- Saved: nil, true and false kept apart; junk pruned.
local db = { procs = { overlays = true, glow = false, sound = "x", opacity = 1, scale = 1.25, offset = 7,
    off = { freeze = true, junk = 1 }, other = 3 } }
P = fresh({ db = db })
local pd = rawget(GAB.db, "procs")
check(pd.overlays == true and pd.glow == false and pd.sound == nil, "saved: an explicit true and false kept, junk gone")
check(pd.opacity == nil and pd.scale == 1.25 and pd.offset == nil, "  a default look dropped, a valid one kept, a bad one gone")
check(pd.off.freeze == true and pd.off.junk == nil and pd.other == nil, "  an effect off kept; junk gone")
eq(count(P._test.side), 0, "  glow off: no button container built")
check(P._test.st.overlay.target._slots["freeze:1"].enabled == false, "  the freeze's slot off")

-- SpellActivationOverlay loaded: all three default to off; nothing built.
P = fresh({ sao = true })
local before = fields(ActionButton3)
check(not P.Enabled("overlays") and not P.Enabled("glow") and not P.Enabled("sound"), "SAO loaded: all three off by default")
eq(#WoW.containers, 0, "  nothing built")
eq(next(WoW.auraSounds), nil, "  no sound")
GAB.Settings.SetProc("glow", true)
check(P.Enabled("glow") and count(P._test.side) == 96 and not P._test.st.overlay.player, "  ticked: the glow alone built")
eq(GAB.db.procs.glow, true, "  an explicit true saved")
check(sameFields(before, fields(ActionButton3)), "  the glow's build writes nothing on a Blizzard button")

-- Every class's data: the shape the engine needs.
local TOKENS = { DRUID = true, HUNTER = true, MAGE = true, PALADIN = true, PRIEST = true, ROGUE = true,
    SHAMAN = true, WARLOCK = true, WARRIOR = true }
local UNIT_OF = { HELPFUL = "player", HARMFUL = "target", ["HARMFUL|PLAYER"] = "target" }
local POSITIONS = { LEFT = true, RIGHT = true, TOP = true }
local function isId(v) return type(v) == "number" and v > 0 and v == math.floor(v) end
local bad = {}
local function flag(class, key, why) bad[#bad + 1] = class .. "." .. tostring(key) .. ": " .. why end
local classes = {}
for class, effects in pairs(GAB.ProcData) do
    classes[#classes + 1] = class
    if not TOKENS[class] then flag(class, "", "not a class token") end
    local keys = {}
    for _, e in ipairs(effects) do
        local k = e.key
        if type(k) ~= "string" or keys[k] then flag(class, k, "key missing or repeated") end
        keys[k or ""] = true
        if type(e.label) ~= "string" then flag(class, k, "no label") end
        if UNIT_OF[e.filter] == nil or UNIT_OF[e.filter] ~= e.unit then flag(class, k, "unit and filter don't match") end
        if #e.auras == 0 then flag(class, k, "no aura") end
        for _, id in ipairs(e.auras) do
            if not isId(id) or id == 5276 then flag(class, k, "aura " .. tostring(id)) end
        end
        for _, id in ipairs(e.glow or {}) do if not isId(id) then flag(class, k, "glow " .. tostring(id)) end end
        if #e.overlays == 0 then flag(class, k, "no overlay") end
        local pulses = false
        for i, o in ipairs(e.overlays) do
            pulses = pulses or o.pulse == true
            if not POSITIONS[o.position] then flag(class, k, i .. ": position " .. tostring(o.position)) end
            -- SAO's Forever art faces inward: every right side is its left mirrored.
            if o.position == "RIGHT" and not o.hflip then flag(class, k, i .. ": right side not mirrored") end
            local t = o.texture
            if type(t) == "string" then
                local rel = t:match("^Interface\\AddOns\\GlassActionBars\\(Media\\[%w_]+)$")
                local f = rel and io.open(rel:gsub("\\", "/") .. ".tga", "rb")
                if f then f:close() else flag(class, k, i .. ": texture not shipped: " .. t) end
            elseif not isId(t) then
                flag(class, k, i .. ": texture " .. tostring(t))
            end
            if o.stacks ~= nil and not (isId(o.stacks) and o.stacks >= 1) then flag(class, k, i .. ": stacks") end
            if o.color then
                local n = #o.color
                if n < 3 or n > 4 then flag(class, k, i .. ": color size") end
                for _, v in ipairs(o.color) do if type(v) ~= "number" or v < 0 or v > 255 then flag(class, k, i .. ": color") end end
            end
        end
        -- SAO's rule: the sound goes with the pulse.
        if (e.sound == true) ~= pulses then flag(class, k, "sound without a pulse, or a pulse without a sound") end
    end
end
eq(table.concat(bad, "; "), "", "data: every class's effects well formed")

-- Independent of the table: one known aura per class stays in that class
-- alone, and no aura id is in two classes (Codex, PR #125).
local SIGNATURE = { MAGE = 400670, WARLOCK = 17941, HUNTER = 415407, PALADIN = 53672, PRIEST = 27828,
    ROGUE = 462707, SHAMAN = 408505, DRUID = 408255 }
local owner, shared, misplaced = {}, {}, {}
for class, effects in pairs(GAB.ProcData) do
    for _, e in ipairs(effects) do
        for _, a in ipairs(e.auras) do
            if owner[a] and owner[a] ~= class then shared[#shared + 1] = a end
            owner[a] = class
        end
    end
end
for class, a in pairs(SIGNATURE) do
    if owner[a] ~= class then misplaced[#misplaced + 1] = class .. " " .. a .. " in " .. tostring(owner[a]) end
end
eq(table.concat(shared, ", "), "", "  no aura id in two classes")
eq(table.concat(misplaced, "; "), "", "  each class's known aura in that class alone")
check(#classes == 8 and GAB.ProcData.WARRIOR == nil, "  eight classes; the warrior's are counters (PR 3)")
table.sort(classes)

-- Each class gets its own effects and nothing else: every slot built, no
-- other class's aura in a filter, its effects alone on the page.
for _, class in ipairs(classes) do
    P = fresh({ class = class })
    local own, want = {}, 0
    for _, e in ipairs(GAB.ProcData[class]) do
        for _, a in ipairs(e.auras) do own[a] = true end
        want = want + #e.overlays
    end
    local built, stray = 0, 0
    local function scan(c)
        for _, s in pairs(c._slots) do
            for id in pairs(s.ids or {}) do if not own[id] then stray = stray + 1 end end
        end
    end
    for _, c in pairs(P._test.st.overlay) do
        for _ in pairs(c._slots) do built = built + 1 end
        scan(c)
    end
    for _, s in pairs(P._test.side) do
        if s.player then scan(s.player) end
        if s.target then scan(s.target) end
    end
    eq(next(GAB.failures), nil, class .. ": nothing failed")
    eq(built, want, "  every overlay slot built")
    eq(stray, 0, "  no other class's aura in a filter")
    GAB.Options.procsPage:Show()
    eq(count(GAB.Options._test.procEffects), #GAB.ProcData[class], "  its effects alone on the page")
end

-- A warlock's glow: Shadow Bolt lights on Nightfall; Ice Lance doesn't.
P = fresh({ class = "WARLOCK" })
WoW.actionSpells[5] = 686
ActionButton5:Update()
local w5 = P._test.side[ActionButton5]
check(w5.player._slots.glow.enabled and w5.player._slots.glow.ids[17941], "warlock: Shadow Bolt glows on Shadow Trance")
check(P._test.side[ActionButton3].player._slots.glow.enabled == false and P._test.side[ActionButton3].target == nil,
    "  Ice Lance: nothing, and no target container (no target glow)")
-- And a mage's Shadow Bolt stays dark.
P = fresh()
WoW.actionSpells[5] = 686
ActionButton5:Update()
check(P._test.side[ActionButton5].player._slots.glow.enabled == false, "a mage's Shadow Bolt: no glow")

-- A colour's own alpha (Rapid Killing's 222); the shaman's mine-only target debuff.
P = fresh({ class = "HUNTER" })
local rk = P._test.st.overlay.player._slots["rapid_killing:1"].frame._regions[1]
check(rk._vertex and math.abs(rk._vertex[4] - 222 / 255) < 1e-6, "hunter: Rapid Killing at SAO's alpha")
P = fresh({ class = "SHAMAN" })
local ss = P._test.st.overlay.target._slots["stormstrike:1"]
check(ss.filter == "HARMFUL|PLAYER" and ss.ids[27775], "shaman: Stormstrike on the target, mine only")
P = fresh({ class = "DRUID" })
local ec = P._test.st.overlay.player._slots["eclipse:1"].frame._regions[1]
eq(ec:GetTexture(), GAB.MEDIA .. "Eclipse_Moon", "druid: Eclipse's shipped texture")

done("test_procs")
