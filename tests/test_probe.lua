-- GABProbe on ForeverProbe (#32): it loads as a module, its reads (the
-- campfire buff, every helpful aura, the Utility bar, camping cooldowns) are
-- right and secret-safe, the campfire procedure starts, and nothing reaches
-- chat. Local only: CI has no ForeverProbe (FOREVERPROBE_OPTIONAL).
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

loadForeverProbe()
WoW.known[3413] = true
WoW.items[279981] = 1                           -- Basic Campfire Kit
WoW.items[279979] = 2                           -- Camp Chair
WoW.items[279969] = 1                           -- Field Guide
local GAB = loadAddon()
local ns = {}
assert(loadfile("Tools/GABProbe/GABProbe.lua"))("GABProbe", ns)
GABProbeDB = { log = { "an old /gabprobe line" } }   -- the standalone probe's table
WoW.fire("ADDON_LOADED", "GABProbe")
local T = ns._test
local chatBefore = #WoW.chat
local function logHas(pattern)
    for _, line in ipairs(GABProbeDB.log) do if line:find(pattern) then return true end end
    return false
end

eq(GABProbeDB.module, 1, "the standalone probe's saved table replaced")
check(not logHas("old /gabprobe"), "  its old lines gone")
check(logHas("loaded"), "the module loaded and logs")

-- The campfire buff.
eq(T.aura(), false, "away from a fire: the buff absent")
WoW.auras[1283391] = true
eq(T.aura(), true, "by a fire: present")
WoW.auras[1283391] = WoW.Secret("aura")
eq(T.aura(), "secret", "a secret read: said so")
WoW.auras[1283391] = "throw"
eq(T.aura(), nil, "a refused read: nil")

-- Every helpful aura, by id; the Utility bar's own view.
WoW.auras[1283391] = true
WoW.helpful = { { spellId = 1283391, name = "Campfire Nearby", duration = 0 }, WoW.Secret("aura2"),
    { spellId = 25694, name = "Well Fed", duration = 900 } }
WoW.fire("UNIT_AURA", "player")
WoW.tick(); WoW.tick()
local a, ids, near, shown = T.readAll()
eq(a, true, "readAll: the buff")
eq(ids, "1283391 <secret> 25694", "  every helpful aura's id, a secret one guarded")
eq(near, true, "  the Utility bar knows it's by a fire")
check(shown:find("camp_skinning1", 1, true) and shown:find("camp_basic", 1, true), "  its camping buttons shown")
check(logHas("aura 3: id 25694"), "  each aura logged")

-- Shared cooldowns, by a transition from a ready baseline.
local v, detail = T.cooldownVerdict()
eq(v, nil, "no baseline yet: inconclusive")
WoW.itemCooldowns[279979] = { 100, 3600 }        -- the Camp Chair already cooling when brought
eq(T.takeBaseline(), 1, "  one ready feature by the fire")
v, detail = T.cooldownVerdict()
check(v == nil and detail:find("fewer than two"), "  fewer than two ready: inconclusive, though all are cooling")
WoW.itemCooldowns[279979] = nil
eq(T.takeBaseline(), 2, "two ready features: the baseline")
v, detail = T.cooldownVerdict()
check(v == nil and detail:find("none of the ready"), "  nothing placed yet: inconclusive")
WoW.itemCooldowns[279979] = { 100, 3600 }        -- the Camp Chair placed
v, detail = T.cooldownVerdict()
check(v == false and detail:find("independent"), "  only the placed one cooling: independent")
WoW.itemCooldowns[279969] = { 100, WoW.Secret("dur") }
v, detail = T.cooldownVerdict()
check(v == nil and detail:find("unreadable"), "  the other's cooldown secret: inconclusive, not independent")
WoW.items[279969] = 0
WoW.itemCooldowns[279969] = nil
v, detail = T.cooldownVerdict()
check(v == nil and detail:find("unreadable"), "  the other no longer carried: inconclusive")
WoW.items[279969] = 1
WoW.itemCooldowns[279969] = { 100, 3600 }
v, detail = T.cooldownVerdict()
check(v == true and detail:find("shared"), "  both cooling: shared")
WoW.itemCooldowns[279969], WoW.itemCooldowns[279979] = nil, nil

-- Camping cooldowns: features cooling down, kits not counted.
WoW.itemCooldowns[279979] = { 100, 3600 }
local cooling, carried = T.readCamping()
check(cooling == 1 and carried == 2, "one of two features cooling down")
WoW.itemCooldowns[279969] = { 100, 3600 }
WoW.itemCooldowns[279981] = { 100, 3600 }
cooling, carried = T.readCamping()
check(cooling == 2 and carried == 2, "  both: shared (the kit not counted)")
WoW.itemCooldowns[279969] = { 100, WoW.Secret("dur") }
cooling = T.readCamping()
eq(cooling, 1, "  a secret duration isn't counted")
check(logHas("Camp Chair %(279979%) x2: cooldown start 100, duration 3600"), "  each item logged")

-- The commands and the procedure.
SlashCmdList.FOREVERPROBE("gab aura")
SlashCmdList.FOREVERPROBE("gab camping")
SlashCmdList.FOREVERPROBE("steps gab campfire")
local rec = ForeverProbeDB.steps and ForeverProbeDB.steps.records and ForeverProbeDB.steps.records["GABProbe/campfire"]
check(rec and rec.status == "active", "/fp steps gab campfire starts")
SlashCmdList.FOREVERPROBE("steps stop")

-- barmove (#30): the bars read, GAB's follow state logged; the procedure starts.
StanceBar:SetPoint("BOTTOMLEFT", UIParent, "BOTTOM", -300, 120)
StanceBar._rect = { 600, 700, 160, 120 }
SlashCmdList.FOREVERPROBE("gab bars")
check(logHas("StanceBar: shown true") and logHas("left 600"), "/fp gab bars: the stance bar's state and place")
check(logHas("PetActionBar: shown") and logHas("GAB follow: stance bar"), "  the pet bar, and GAB's follow state")
SlashCmdList.FOREVERPROBE("steps gab barmove")
rec = ForeverProbeDB.steps.records["GABProbe/barmove"]
check(rec and rec.status == "active", "/fp steps gab barmove starts")
SlashCmdList.FOREVERPROBE("steps stop")
SlashCmdList.FOREVERPROBE("steps gab look")
rec = ForeverProbeDB.steps.records["GABProbe/look"]
check(rec and rec.status == "active", "/fp steps gab look starts")
SlashCmdList.FOREVERPROBE("steps stop")
-- pearl (#44): the material and the numbers read as it starts.
SlashCmdList.FOREVERPROBE("steps gab pearl")
rec = ForeverProbeDB.steps.records["GABProbe/pearl"]
check(rec and rec.status == "active", "/fp steps gab pearl starts")
check(logHas("pearl") and logHas("gloss 0.08"), "  Pearl built, its gloss read")
SlashCmdList.FOREVERPROBE("steps stop")
-- icons (#46): the Utility bar's size read as it starts.
SlashCmdList.FOREVERPROBE("steps gab icons")
rec = ForeverProbeDB.steps.records["GABProbe/icons"]
check(rec and rec.status == "active", "/fp steps gab icons starts")
check(logHas("iconSize"), "  the Utility bar's size read")
SlashCmdList.FOREVERPROBE("steps stop")
-- dock (#53): the bar's containers beside their buttons, the union, and a
-- docked client's frame beside its buttons, each in UIParent units.
WoW.layoutBar(MainActionBar, 500, 100, { n = 3 })
for i = 1, 3 do
    local r = _G["ActionButton" .. i].container._rect
    _G["ActionButton" .. i]._rect = { r[1] + 3, r[2] - 3, r[3] - 7, r[4] - 7 }   -- buttons 7 lower, 3 inside
end
local cf = CreateFrame("Frame", "ProbeDockClient", UIParent)
cf._width, cf._height = 92, 45
local cb = CreateFrame("Button", "ProbeDockClientButton1", cf)
cb._rect, cb._escale = { 1286, 1376, 200, 110 }, 0.5   -- its own units: half scale
check(GAB.Dock.Register({ id = "probetest", label = "Probe test", frame = cf, Layout = function() end }), "a dock client")
GAB.Settings.SetDock("probetest", "bar", 1)
WoW.tick()
cf._rect = { 643, 735, 100, 55 }
SlashCmdList.FOREVERPROBE("gab dock")
check(logHas('probetest: docked to bar 1 %(MainActionBar%), side "RIGHT"'), "/fp gab dock: the client's dock settings")
check(logHas('container 1 .- L 500.0 R 545.0 T 100.0 B 55.0 .-button "ActionButton1" L 503.0 R 542.0 T 93.0 B 48.0 .-dL 3.0 dT %-7.0'),
    "  each container beside its button, and their offset")
check(logHas("containers' union %(the dock's target%) L 500.0 R 639.0 T 100.0 B 55.0"), "  the dock's target")
check(logHas("buttons' union L 503.0 R 636.0 T 93.0 B 48.0 .-; button row tops 93.0"), "  the buttons' union and rows")
check(logHas('client frame "ProbeDockClient" L 643.0 R 735.0'), "  the client's frame")
check(logHas('client child "ProbeDockClientButton1" Button L 643.0'), "  its shown children")
check(logHas("client buttons' union L 643.0 R 688.0 T 100.0 B 55.0 .-; row tops 100.0"), "  its buttons' union")
-- bagsbar (#55): the bag bar's methods, raw and inherited, and Layout run once.
SlashCmdList.FOREVERPROBE("gab bagsbar")
check(logHas("BagsBar.UpdateDividers: raw function, via frame function, mixin .-, secure true"), "/fp gab bagsbar: UpdateDividers read")
check(logHas("BagsBar.Layout: raw function"), "  Layout read")
check(logHas("BagsBar:Layout%(%) ran"), "  Layout run, and it ran")
-- (The stubs answer any unknown method, so "via frame" stays a function here.)
local saved, savedLayout = rawget(BagsBar, "UpdateDividers"), rawget(BagsBar, "Layout")
BagsBar.UpdateDividers = nil
BagsBar.Layout = function() error("attempt to call a nil value") end
WoW.tainted = { UpdateDividers = "SomeAddon" }
SlashCmdList.FOREVERPROBE("gab bagsbar")
check(logHas('BagsBar.UpdateDividers: raw nil, .-secure false "SomeAddon"'), "  gone and tainted: said so")
check(logHas("BagsBar:Layout%(%) ERROR .-attempt to call a nil value"), "  Layout's error logged")
BagsBar.UpdateDividers, BagsBar.Layout, WoW.tainted = saved, savedLayout, nil
SlashCmdList.FOREVERPROBE("steps gab dock")
rec = ForeverProbeDB.steps.records["GABProbe/dock"]
check(rec and rec.status == "active", "/fp steps gab dock starts")
SlashCmdList.FOREVERPROBE("steps stop")
-- micro (#57): the micro buttons' atlases read, cropped inside the atlas with
-- the Background faded, and put back; the empty bag slots' and key ring's icons faded.
local mtex = CharacterMicroButton:CreateTexture()
rawset(mtex, "GetAtlas", function() return "UI-HUD-MicroMenu-CharacterInfo-Up" end)
rawset(mtex, "SetTexCoord", function(self, ...) self._tc = { ... } end)
rawset(CharacterMicroButton, "GetNormalTexture", function() return mtex end)
C_Texture = { GetAtlasInfo = function(a)
    return { width = 32, height = 40, file = 4567, leftTexCoord = 0.5, rightTexCoord = 0.75, topTexCoord = 0, bottomTexCoord = 0.5 }
end }
SlashCmdList.FOREVERPROBE("gab micro")
check(logHas('"CharacterMicroButton" .-Normal "UI%-HUD%-MicroMenu%-CharacterInfo%-Up" 32x40 file 4567 coords 0.5000 0.7500 0.0000 0.5000'),
    "/fp gab micro: each state's atlas, size and coords")
check(logHas("CharacterBag1Slot shown true, icon .-occupied %(GAB%) false"), "  each bag slot's icon and GAB's occupancy")
T.cropMicro(0.1)()
local tc = mtex._tc
check(tc and math.abs(tc[1] - 0.1) < 1e-9 and math.abs(tc[2] - 0.9) < 1e-9 and math.abs(tc[3] - 0.1) < 1e-9
    and math.abs(tc[4] - 0.9) < 1e-9, "  cropped by 10%, relative to its atlas (run #269)")
eq(CharacterMicroButton.Background:GetAlpha(), 0, "  its background faded")
T.cropMicro(0)()
eq(CharacterMicroButton.Background:GetAlpha(), 1, "  inset 0: the background back")
T.fadeBagIcons("empty")()
eq(CharacterBag1Slot.icon:GetAlpha(), 0, "an empty bag slot's icon faded")
eq(KeyRingButton.icon:GetAlpha(), 0, "  the key ring's too")
eq(MainMenuBarBackpackButton.icon:GetAlpha(), 1, "  the backpack's kept")
T.fadeBagIcons("all")()
eq(CharacterBag1Slot.icon:GetAlpha(), 1, "  back")
C_Texture = nil
-- microfn: each micro button's atlas setters, raw and inherited, and the game
-- menu button's SetNormalAtlas run once.
check(MainMenuMicroButton ~= nil, "(the stubs have the game menu button)")
SlashCmdList.FOREVERPROBE("gab microfn")
check(logHas('"CharacterMicroButton": SetNormalAtlas raw .-, via frame function, metatable .-, secure true'),
    "/fp gab microfn: the character button's setters read")
check(logHas('"MainMenuMicroButton": .-SetHighlightAtlas raw'), "  the game menu button's, to the last setter")
check(logHas("MainMenuMicroButton:SetNormalAtlas%(.-%) ran"), "  its SetNormalAtlas run, and it ran")
local savedSet = rawget(MainMenuMicroButton, "SetNormalAtlas")
rawset(MainMenuMicroButton, "SetNormalAtlas", function() error("attempt to call a nil value") end)
WoW.tainted = { SetNormalAtlas = "SomeAddon" }
SlashCmdList.FOREVERPROBE("gab microfn")
check(logHas('"MainMenuMicroButton": SetNormalAtlas raw function, .-secure false "SomeAddon"'), "  tainted: said so")
check(logHas("MainMenuMicroButton:SetNormalAtlas%(.-%) ERROR .-attempt to call a nil value"), "  its error logged")
rawset(MainMenuMicroButton, "SetNormalAtlas", savedSet)
WoW.tainted = nil
SlashCmdList.FOREVERPROBE("steps gab micro")
rec = ForeverProbeDB.steps.records["GABProbe/micro"]
check(rec and rec.status == "active", "/fp steps gab micro starts")
SlashCmdList.FOREVERPROBE("steps stop")
SlashCmdList.FOREVERPROBE("gab clear")
eq(#GABProbeDB.log, 1, "/fp gab clear empties the log in place (one line left: 'log cleared')")

eq(#WoW.chat, chatBefore, "nothing went to chat")
eq(next(GAB.failures), nil, "nothing failed")
-- feedpet (#65): the pet, every food's CanPetEatItem (secret-safe), the
-- bar's choice; a feed seen by the count; disarmed afterwards.
WoW.known[6991] = true
WoW.pet = { hunter = true, level = 30 }
WoW.bags[0] = { [1] = { itemID = 101, stackCount = 5 }, [2] = { itemID = 102, stackCount = 1 } }
WoW.edible = { [101] = true, [102] = WoW.Secret("can") }
WoW.itemInfo = { [101] = { level = 30, price = 5 } }
WoW.items[101] = 5
local ready, foodId, nEdible = T.readPet()
check(ready == true and foodId == 101 and nEdible == 1, "feedpet: a live hunter pet, food 101, one plainly edible")
check(logHas("item 102.*CanPetEatItem <secret>") or logHas("item 102.*CanPetEatItem"), "  a secret CanPetEatItem logged, not compared")
eq((T.fed()), false, "  not fed yet")
WoW.items[101] = 4
eq((T.fed()), true, "  the count dropped: fed")
eq((T.afterFeed()), true, "  nothing targeting, the button disarmed")
GAB.Utility.buttons.feedpet:SetAttribute("target-bag", 0)
eq((T.afterFeed()), false, "  a target left on the button: fails")
GAB.Utility.buttons.feedpet:SetAttribute("target-bag", nil)
check(GAB.Utility.buttons.feedpet ~= nil, "  the feedpet procedure's button exists")

-- lock (#34): the CVar read, a change seen, a combat write read back, the original put back.
WoW.cvars.lockActionBars = "1"
GAB.Settings.SetUtilityShown("lockbars", true)
WoW.tick()
local v, shown = T.startLock()
check(v == true and shown == true, "lock: locked, the button shown")
eq((T.lockChanged()), false, "  no change yet")
WoW.cvars.lockActionBars = "0"
eq((T.lockChanged()), true, "  a change seen")
T.readLock()
WoW.combat = true
local lockdown, before, ret, after = T.writeInCombat()
check(lockdown == true and before == false and ret == true and after == true, "  the combat write recorded, read back")
WoW.combat = false
T.restoreLock()
eq(WoW.cvars.lockActionBars, "1", "  this run's original value put back")
-- A second run, started unlocked: its own original, not the first run's.
WoW.cvars.lockActionBars = "0"
T.startLock()
eq(select(2, T.restoreLock()), nil, "  a new run forgets the last run's combat write")
check(rawget(_G, "combatWrite") == nil, "  no global written")
WoW.combat = true
T.writeInCombat()
WoW.combat = false
T.restoreLock()
eq(WoW.cvars.lockActionBars, "0", "  a second run puts back its own start (unlocked)")

-- utilitydrag (#86): the test buttons and their gesture guard. The client's
-- order is what the procedure measures; this drives one plausible order
-- (OnMouseDown, the down edge, the up edge, OnMouseUp, then the next frame)
-- with the secure dispatch modelled on SecureActionButton_OnClick.
WoW.cvars.ActionButtonUseKeyDown = "1"
local ok = T.dragSetup()
check(ok == true, "utilitydrag: set up out of combat")
local S, P = T.dragButtons.S, T.dragButtons.P
eq(WoW.overrides[_G.GABProbeDragHost]["SHIFT-F10"], "GABProbeDragS:LeftButton", "  Shift+F10 clicks S")
local function edge(b, mouse, down, key)
    if b:GetScript("PreClick") then b:GetScript("PreClick")(b, mouse, down) end
    if b == S then
        local onDown = WoW.cvars.ActionButtonUseKeyDown == "1"
        if (down and onDown) or (not down and not onDown) then
            if b:GetAttribute("type") == "macro" then GABProbeDragFired("S") end
        end
        b:GetScript("OnClick")(b, mouse, down)
    elseif not down then
        b:GetScript("OnClick")(b, mouse, down)
    end
    if b:GetScript("PostClick") then b:GetScript("PostClick")(b, mouse, down) end
end
local function click(b, mouse)
    mouse = mouse or "LeftButton"
    WoW.mouseDown[mouse] = true
    b:GetScript("OnMouseDown")(b, mouse)
    edge(b, mouse, true)
    WoW.mouseDown[mouse] = nil
    edge(b, mouse, false)
    b:GetScript("OnMouseUp")(b, mouse)
    WoW.flushTimers(0)
end
local function key(b) edge(b, "LeftButton", true); edge(b, "LeftButton", false) end
local function fired() return T.drag.fired.S, T.drag.fired.P, T.drag.drops end
local function spellOnCursor() WoW.cursorInfo = { "spell", 12, "spell", 6991 } end

for _, cv in ipairs({ "1", "0" }) do
    WoW.cvars.ActionButtonUseKeyDown = cv
    local s0, p0, d0 = fired()
    click(S); click(P)
    local s1, p1 = fired()
    check(s1 == s0 + 1 and p1 == p0 + 1, "  [keydown " .. cv .. "] a plain click acts once on each")
    WoW.pickupDown = true
    click(S); click(P)
    local s2, p2 = fired()
    check(s2 == s1 and p2 == p1, "  [keydown " .. cv .. "] a Shift-click acts on neither edge")
    eq(S:GetAttribute("type"), "macro", "  [keydown " .. cv .. "] S's action restored after")
    key(S); key(P)
    local s3, p3 = fired()
    check(s3 == s2 + 1 and p3 == p2 + 1, "  [keydown " .. cv .. "] a Shift key binding still acts")
    WoW.pickupDown = false
    spellOnCursor(); click(S)
    local s4, _, d4 = fired()
    check(s4 == s3 and d4 == d0 + 1 and WoW.cursorInfo == nil, "  [keydown " .. cv .. "] a click with a spell takes it, casts nothing")
    spellOnCursor(); click(P)
    local _, p5, d5 = fired()
    check(p5 == p3 and d5 == d4 + 1, "  [keydown " .. cv .. "] the same on P")
    -- A spellbook drag released on S, then the release click in the same frame.
    spellOnCursor()
    S:GetScript("OnReceiveDrag")(S)
    edge(S, "LeftButton", false)
    WoW.flushTimers(0)
    local s6, _, d6 = fired()
    check(s6 == s4 and d6 == d5 + 1, "  [keydown " .. cv .. "] OnReceiveDrag takes it once, the release casts nothing")
    eq(T.gesture[S], nil, "  [keydown " .. cv .. "] the gesture ended a frame later")
end
-- A pick-up drag: no OnMouseUp after it (session 9), OnDragStop ends the gesture.
WoW.pickupDown = true
WoW.mouseDown.LeftButton = true
S:GetScript("OnMouseDown")(S, "LeftButton"); edge(S, "LeftButton", true)
S:GetScript("OnDragStart")(S, "LeftButton")
WoW.mouseDown.LeftButton, WoW.pickupDown = nil, false
S:GetScript("OnDragStop")(S); WoW.flushTimers(0)
eq(T.gesture[S], nil, "  a drag's gesture ends at OnDragStop")
-- A key binding fires OnMouseDown with the mouse button up: no gesture, it acts.
local k0 = fired()
WoW.pickupDown = true
S:GetScript("OnMouseDown")(S, "LeftButton"); edge(S, "LeftButton", true); edge(S, "LeftButton", false)
S:GetScript("OnMouseUp")(S, "LeftButton"); WoW.flushTimers(0)
WoW.pickupDown = false
eq((fired()), k0 + 1, "  a Shift key binding's OnMouseDown begins nothing, the key acts")
-- Overlap: Shift-left down, Shift up, right click, left up: still nothing.
local s0 = fired()
WoW.cvars.ActionButtonUseKeyDown = "0"
WoW.pickupDown = true
WoW.mouseDown.LeftButton = true
S:GetScript("OnMouseDown")(S, "LeftButton"); edge(S, "LeftButton", true)
WoW.pickupDown = false
click(S, "RightButton")
WoW.mouseDown.LeftButton = nil
edge(S, "LeftButton", false); S:GetScript("OnMouseUp")(S, "LeftButton"); WoW.flushTimers(0)
eq((fired()), s0, "  a right click mid-gesture doesn't let the left release act")
eq(T.gesture[S], nil, "  the gesture ended")
-- In combat: no gesture begins, the click acts.
WoW.combat = true
WoW.pickupDown = true
click(S)
eq((fired()), s0 + 1, "  in combat a Shift-click acts (the stated exception)")
WoW.combat, WoW.pickupDown = false, false
-- Teardown: the keys gone, the setting back.
T.flipKeyDown()
eq(WoW.cvars.ActionButtonUseKeyDown, "1", "  flipped")
check(T.dragTeardown() == true and WoW.overrides[_G.GABProbeDragHost] == nil, "  teardown clears the keys")
eq(WoW.cvars.ActionButtonUseKeyDown, "0", "  and puts the setting back")
check(#WoW.chat == chatBefore, "  nothing in chat")

-- procs (#115): Fingers of Frost's reads, Ice Lance's slot and button, the
-- watcher's tallies, the test glow over the glass, in combat too.
local slots, overlayed = { [3] = 400640, [7] = 116 }, false
slots[5] = WoW.Secret("slot")
rawset(_G, "C_ActionBar", { GetSpell = function(slot) return slots[slot] end })
rawset(_G, "C_Secrets", { GetSpellAuraSecrecy = function(id) return id == 400670 and 0 or 1 end,
    ShouldAurasBeSecret = function() return WoW.combat == true end })
rawset(_G, "C_SpellActivationOverlay", { IsSpellOverlayed = function() return overlayed end })
rawset(_G, "canaccessvalue", function(v) return not issecretvalue(v) end)
WoW.templates.ActionButtonSpellAlertTemplate = function(w)
    w.ProcLoop = { Play = function(s) s.playing = true end, Stop = function(s) s.playing = false end }
end
WoW.spellNames = WoW.spellNames or {}
WoW.spellNames[400640], WoW.spellNames[400670] = "Ice Lance", "Fingers of Frost"
WoW.auras[400670] = nil
C_Spell.GetBaseSpell = function(id) return id == 1240044 and 400640 or id end
local spellBook = rawget(_G, "C_SpellBook")
if not spellBook then spellBook = {}; rawset(_G, "C_SpellBook", spellBook) end
spellBook.FindBaseSpellByID = function() error("not in the book") end
local class, ice, deep = T.procSetup()
check(logHas("spell 1240044 nil, GetBaseSpell 400640, FindBaseSpellByID ERROR"), "  each rank's base spell, by both APIs")
check(T.glowKey(1240044) == "ice" and T.glowKey(1312002) == "ice" and T.glowKey(400640) == "ice",
    "  every Ice Lance rank glows (round 3's first run had rank 2)")
eq(ice, "Ice Lance 400640 in slot 3 on ActionButton3", "procs: Ice Lance found by id, on its stock button")
eq(deep, "Deep Freeze not on a visible bar", "  Deep Freeze absent: said so")
check(logHas("slot 5 spell <secret>"), "  a secret slot logged as such")
check(logHas("aura 400670 \"Fingers of Frost\": secrecy 0, now absent"), "  the buff's secrecy and state")
eq(T.auraState(400670), "absent", "auraState: absent")
WoW.auras[400670] = { applications = 2 }
eq(T.auraState(400670), "present x2", "  present, with stacks")
WoW.auras[400670] = { applications = WoW.Secret("n") }
eq(T.auraState(400670), "present x<secret>", "  only the stacks hidden")
WoW.auras[400670] = WoW.Secret("a")
eq(T.auraState(400670), "secret", "  the aura secret")
WoW.auras[400670] = "throw"
eq(T.auraState(400670), "error", "  a refused read")
WoW.auras[400670] = nil

eq((T.procStart()), "watching", "the watcher starts")
eq((T.procStart()), "already watching", "  once")
eq((T.fightOver()), false, "  the fight step waits for a fight")
WoW.auras[400670] = { applications = 1 }
WoW.fire("UNIT_AURA", "player", { isFullUpdate = false })
check(logHas("aura 400670 absent %-> present x1 %(out%)"), "  a proc is a transition line")
WoW.combat = true
WoW.fire("PLAYER_REGEN_DISABLED")
WoW.auras[400670] = WoW.Secret("a")
WoW.fire("UNIT_AURA", "player", WoW.Secret("info"))
check(logHas("aura 400670 present x1 %-> secret %(inCombat%)"), "  a secret read in combat, said so")
overlayed = true
WoW.fire("UNIT_AURA", "player", WoW.Secret("info"))
check(logHas("IsSpellOverlayed 400640 false %-> true"), "  Blizzard's overlay state for Ice Lance")
check(logHas("Ice Lance's slot in combat reads 400640"), "  the slot read once in combat")
WoW.fire("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", 400640)
WoW.flushTimers(0)
check(logHas("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW 400640"), "  a native glow event logged")
check(logHas("ActionButton3 alert none, shown nil"), "  and Blizzard's alert on that button read")
local linesH = #GABProbeDB.log
WoW.fire("SPELL_ACTIVATION_OVERLAY_HIDE")
eq(#GABProbeDB.log, linesH, "  a spell-less HIDE counted, not logged (nor by the native counter)")
WoW.combat = false
WoW.auras[400670] = nil
WoW.fire("PLAYER_REGEN_ENABLED")
local over, cov0, events, uaIn, uaOut = T.fightOver()
eq(over, true, "  the fight step ends with the fight")
eq(cov0, "coverage: events all, UNIT_AURA registered, blocked listener on", "  every listener on")
check(uaIn == "UNIT_AURA payload in combat: secret 2" and uaOut == "out: accessible 1", "  the payload tallied by combat")
check(events:find("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW 1", 1, true), "  the events counted")
check(events:find("SPELL_ACTIVATION_OVERLAY_HIDE 1", 1, true), "  the spell-less HIDE too")

-- No Ice Lance on the bars: the fight step's poll scans once, not every second.
T.procTeardown()
local savedIce = {}
for k, v in pairs(slots) do if v == 400640 then savedIce[k] = v; slots[k] = 116 end end
local function scans()
    local n = 0
    for _, line in ipairs(GABProbeDB.log) do if line:find("procs: %d+ spell slots") then n = n + 1 end end
    return n
end
local scans0 = scans()
T.fightOver()
T.fightOver()
T.fightOver()
eq(scans() - scans0, 1, "  no Ice Lance found: the fight step scans the bars once")
check(T.showGlow(1) == false and scans() - scans0 == 2, "  the test glow, run by hand, scans again")
check(T.containerGlow() == false and scans() - scans0 == 3, "  the engine's glow too")
T.procTeardown()
for k, v in pairs(savedIce) do slots[k] = v end
T.procSetup()

local level = ActionButton3:GetFrameLevel()
local g1, _, glass = T.showGlow(1)
eq(g1, "glow level " .. (level + 1), "the test glow at the glass's level")
eq(glass, "glass " .. (level + 1), "  the glass's level read from GAB's skin")
local glow = T.procState().glow
check(glow and glow:IsShown() and glow.ProcLoop.playing and glow:GetParent() == ActionButton3, "  shown on Ice Lance, looping")
eq((T.showGlow(5)), "glow level " .. (level + 5), "  then five up")
T.hideGlow()
check(not glow:IsShown() and not glow.ProcLoop.playing, "  hidden")
eq((T.glowInCombat()), false, "the combat glow waits for a fight")
local v0 = #WoW.violations
WoW.combat = true
local shownIn, _, _, _, inCombat, blocked = T.glowInCombat()
check(shownIn == true and glow:IsShown() and inCombat == "in combat true", "  shown in combat")
eq(blocked, "blocked 0", "  nothing blocked")
eq(#WoW.violations, v0, "  no change on a protected frame")
WoW.combat = false
eq((T.procTeardown()), "blocked 0", "teardown: the blocked count")
check(not glow:IsShown() and T.procState().on == nil, "  the glow hidden, the watcher reset")
local lines = #GABProbeDB.log
WoW.fire("UNIT_AURA", "player", {})
eq(#GABProbeDB.log, lines, "  its events unregistered")
SlashCmdList.FOREVERPROBE("steps gab procs")
rec = ForeverProbeDB.steps.records["GABProbe/procs"]
check(rec and rec.status == "active", "/fp steps gab procs starts")
SlashCmdList.FOREVERPROBE("steps stop")
T.procTeardown()

-- procglow: the engine-driven glow. The stub container records its slot's
-- options and makes the slot frame as Blizzard's frame provider does.
local slotOpts
WoW.templates.CustomAuraButtonTemplate = function(w) w:EnableMouse(true) end   -- a button: takes clicks
WoW.templates.CustomAuraContainerTemplate = function(w)
    w:EnableMouse(true)                         -- assume the worst: the probe must turn it off
    rawset(w, "SetUnit", function(self, u) self._unit = u end)
    rawset(w, "SetEnabled", function(self, on) self._enabled = on end)
    rawset(w, "AddAuraSlot", function(self, key, filter, opts)
        slotOpts = { key = key, filter = filter, opts = opts }
        local f = CreateFrame("AuraButton", nil, self, "CustomAuraButtonTemplate")
        if opts.initializeFrame then opts.initializeFrame(f) end
        return f
    end)
end
WoW.combat = true
eq((T.outOfCombat()), false, "procglow: waits for combat to end")
eq((T.containerGlow()), false, "  the container isn't built in combat")
WoW.combat = false
eq((T.outOfCombat()), true, "  then reads the bars and watches")
local built = T.containerGlow()
eq(built, "built", "the engine-driven glow is built")
local P = T.procState()
local c = P.container
check(c and c:GetParent() == ActionButton3 and c._unit == "player" and c._enabled == true, "  a player container on Ice Lance")
check(c:GetFrameLevel() == ActionButton3:GetFrameLevel() + 5 and c:IsMouseEnabled() == false, "  above the glass, clicks through")
check(slotOpts.filter == "HELPFUL" and slotOpts.opts.candidateFilters.includeSpellIDs[400670] == true,
    "  one slot for Fingers of Frost only")
check(P.slot:IsMouseEnabled() == false and P.slotGlow and P.slotGlow:GetParent() == P.slot, "  the slot holds the glow, clicks through")
check(P.slotGlow.animationPlaying == true and P.slotGlow.ProcLoop.playing, "  looping, replayed on each show")
eq((T.containerGlow()), "already built", "  once")
P.slot:Hide()
WoW.fire("UNIT_AURA", "player", {})
check(logHas("glow slot shown/visible nil %-> false/false"), "  whether the slot shows is logged")
T.procTeardown()
check(not c:IsShown() and c._enabled == false, "teardown: the container off and hidden")

-- Stopped through the host (Codex, PR #116): nothing of the run outlives it.
SlashCmdList.FOREVERPROBE("steps gab procs")
eq(T.procState().on, true, "procs started through the host: watching")
T.showGlow(1)
local stale = T.procState().glow
check(stale and stale:IsShown(), "  a test glow on Ice Lance")
SlashCmdList.FOREVERPROBE("steps stop")
check(not stale:IsShown() and T.procState().on == nil and T.procState().glow == nil, "  /fp steps stop: glow hidden, watcher reset")
lines = #GABProbeDB.log
WoW.fire("UNIT_AURA", "player", {})
eq(#GABProbeDB.log, lines, "  its events unregistered")
-- A run left live (no Stop) is torn down when the next one starts.
T.procStart(); T.showGlow(1)
stale = T.procState().glow
SlashCmdList.FOREVERPROBE("steps gab procs")
check(not stale:IsShown() and T.procState().glow ~= stale and T.procState().on == true, "  a new run starts clean")
SlashCmdList.FOREVERPROBE("steps stop")

-- Coverage: a refused subscription isn't a measured "none".
WoW.REFUSED_EVENTS.SPELL_ACTIVATION_OVERLAY_SHOW = true
rawset(T.procFrame, "RegisterUnitEvent", function() return false end)
rawset(T.Probe, "OnBlocked", function() return false end)
local _, unitAura, listening = T.procStart()
eq((T.procStart()), "already watching", "coverage: started")
check(unitAura == false and listening == false, "  UNIT_AURA refused and no blocked listener: reported")
local _, cov = T.procTeardown()
eq(cov, "coverage: events NOT ALL, UNIT_AURA NOT REGISTERED, blocked listener OFF", "  the summary says what wasn't covered")
local passed, why = T.nothingBlocked()
check(passed == false and why:find("unmeasured"), "  'nothing blocked' isn't a pass without the listener")
WoW.REFUSED_EVENTS.SPELL_ACTIVATION_OVERLAY_SHOW = nil
rawset(T.procFrame, "RegisterUnitEvent", nil)
rawset(T.Probe, "OnBlocked", nil)
T.procStart()
_, cov = T.procTeardown()
eq(cov, "coverage: events all, UNIT_AURA registered, blocked listener on", "  all covered")
check(T.nothingBlocked() == true, "  then 'nothing blocked' passes")

-- procs3 (#115, round 3): the plan's design. The stub container records the
-- order of its setup calls, its slots' filters and enabled states, and its
-- UpdateAllAuras calls; a slot frame takes an application bar.
local calls, made = {}, {}
local failSlot, blockInSetup   -- a slot key whose AddAuraSlot throws once; a blocked action fired from setup
WoW.templates.CustomAuraButtonTemplate = function(w)
    w:EnableMouse(true)
    rawset(w, "SetApplicationBar", function(self, bar, o) self._bar = { bar = bar, min = o.minApplications } end)
end
WoW.templates.CustomAuraContainerTemplate = function(w)
    w:EnableMouse(true)
    w._slots, w._order, w._refreshes = {}, {}, 0
    made[#made + 1] = w
    local function note(s) w._order[#w._order + 1] = s end
    rawset(w, "SetUnit", function(self, u) self._unit = u; note("unit") end)
    rawset(w, "SetEnabled", function(self, on) self._enabled = on; note("enabled") end)
    rawset(w, "AddAuraSlot", function(self, key, filter, opts)
        note("slot")
        if failSlot == key then failSlot = nil; error("slot refused") end
        if blockInSetup then blockInSetup = nil; WoW.fire("ADDON_ACTION_BLOCKED", "GABProbe", "AddAuraSlot") end
        local f = CreateFrame("AuraButton", nil, self, "CustomAuraButtonTemplate")
        self._slots[key] = { filter = filter, ids = opts.candidateFilters.includeSpellIDs, enabled = true, frame = f }
        if opts.initializeFrame then opts.initializeFrame(f) end
        return f
    end)
    rawset(w, "SetAuraSlotCandidateFilters", function(self, key, cf)
        assert(self._slots[key], "no slot " .. key)
        self._slots[key].ids = cf.includeSpellIDs
        calls[#calls + 1] = "filter"
    end)
    rawset(w, "SetAuraSlotEnabled", function(self, key, on)
        assert(self._slots[key] and type(on) == "boolean", "slot key and a boolean")
        self._slots[key].enabled = on
        calls[#calls + 1] = on and "enable" or "disable"
    end)
    rawset(w, "UpdateAllAuras", function(self) self._refreshes = self._refreshes + 1 end)
end
local addons = { SpellActivationOverlay = true }
C_AddOns.IsAddOnLoaded = function(name) return addons[name] == true end
C_AddOns.LoadAddOn = function(name) addons[name] = true; return true end
local sounds, removed = {}, {}
local soundRefused, removeThrows = nil, false
C_UnitAuras.AddAuraSound = function(trigger, info)
    if trigger == soundRefused then return nil end
    sounds[#sounds + 1] = { trigger = trigger, info = info }
    return 100 + #sounds
end
C_UnitAuras.RemoveAuraSound = function(id)
    if removeThrows then error("refused") end
    removed[#removed + 1] = id
end
Enum.UnitAuraSoundTrigger = { Added = 0, ApplicationsIncreased = 1, Removed = 2 }
local macroSlot = 9
local macroText = "#showtooltip\n/cast Ice Lance"
-- The client's answer for a macro showing a spell: the spell's id, not the
-- macro's (build 71037, AssistedCombatManager.lua:205).
rawset(_G, "GetActionInfo", function(slot) if slot == macroSlot then return "macro", 400640, "spell" end end)
local actionBar = rawget(_G, "C_ActionBar")
if not actionBar then actionBar = {}; rawset(_G, "C_ActionBar", actionBar) end
actionBar.GetActionText = function(slot) if slot == macroSlot then return "IceAlt" end end
local macroIndex = 1
rawset(_G, "GetMacroIndexByName", function(name) return name == "IceAlt" and macroIndex or 0 end)
rawset(_G, "GetMacroBody", function(id) return id == 1 and macroText or nil end)
slots[5] = nil
slots[macroSlot] = 400640

local ready, why = T.r3ready()
check(ready == false and why:find("SpellActivationOverlay"), "procs3: waits while SAO is loaded")
check(T.r3build() == false and #made == 0, "  and builds nothing")
addons.SpellActivationOverlay = nil
slots[3] = nil
ready, why = T.r3ready()
check(ready == false and why:find("Ice Lance on Action Bar 1") and why:find("another bar"), "  waits for Ice Lance on two bars")
slots[3] = 400640
local others = {}
for _, p in ipairs({ "MultiBarBottomLeftButton", "MultiBarBottomRightButton", "MultiBarRightButton", "MultiBarLeftButton",
    "MultiBar5Button", "MultiBar6Button", "MultiBar7Button" }) do others[#others + 1] = _G[p .. "3"] end
for _, b in ipairs(others) do b:Hide() end
ready, why = T.r3ready()
check(ready == false and why:find("another bar") and not why:find("Action Bar 1"), "  two copies on Action Bar 1 alone aren't enough")
for _, b in ipairs(others) do b:Show() end
ready, why = T.r3ready()
check(ready == false and why:find("Alt macro"), "  waits for the Alt condition in the macro")
macroText = "#showtooltip\n/cast [mod:alt] Frostbolt; Ice Lance"
macroIndex = 0
ready, why = T.r3ready()
check(ready == false and why:find("Alt macro"), "  a macro its name doesn't find: not ready")
macroIndex = 1
WoW.combat = true
check(T.r3ready() == false, "  waits for combat to end")
WoW.combat = false
check(T.r3ready() == true and logHas("macro on ActionButton9 %(slot 9%) shows 400640, Alt condition true %(name \"IceAlt\", macro 1%)"),
    "  ready: Ice Lance on two bars, the macro found by its name and read")

-- A partial build: torn down, and the step fails.
failSlot = "fof2"
local made0 = #made
local okP, _, whyP = T.r3build()
check(okP == false and whyP:find("overlay: .*slot refused"), "partial build: fails with what broke")
local leftOn = 0
for i = made0 + 1, #made do if made[i]:IsShown() or made[i]._enabled ~= false then leftOn = leftOn + 1 end end
eq(leftOn, 0, "  every container made so far disabled and hidden")
check(T.r3state().on == nil and next(T.r3state().side) == nil, "  nothing kept as built")
failSlot = "glow"
made0 = #made
check(T.r3build() == false, "  a button's slot failing fails it too")
leftOn = 0
for i = made0 + 1, #made do if made[i]:IsShown() or made[i]._enabled ~= false then leftOn = leftOn + 1 end end
eq(leftOn, 0, "  its half-made container too")
T.procTeardown()
addons.Blizzard_AuraContainer = nil   -- the full build below loads it again, logged

blockInSetup = true
local ok3, engine, nButtons, overlay, snd = T.r3build()
check(ok3 == true, "procs3: built")
eq(T.procState().blocked, 1, "  the watcher starts first: a blocked action from the build is counted")
eq(engine, "engine: loaded before false, LoadAddOn true nil, after true", "  the engine loaded first, logged")
local R = T.r3state()
local nStock = 0
for b in pairs(R.side) do nStock = nStock + 1 end
eq(nStock, 96, "  a glow on every stock button of bars 1-8")
eq(nButtons, "96 buttons, 16 glowing now", "  Ice Lance's slots on each bar light (the macro's too)")
local s3 = R.side[ActionButton3]
check(s3.player._order[1] == "unit" and s3.player._order[2] == "enabled" and s3.player._order[3] == "slot",
    "  the plan's order: unit, enabled, then the slot")
check(s3.player._refreshes >= 1 and s3.player._unit == "player" and s3.target._unit == "target", "  refreshed; player and target")
local ps, ts = s3.player._slots.glow, s3.target._slots.glow
check(ps.filter == "HELPFUL" and ps.ids[400670] and ps.enabled, "  Ice Lance's player slot: Fingers of Frost, on")
check(ts.filter == "HARMFUL" and ts.ids[122] and ts.ids[5276] == nil and ts.enabled, "  its target slot: the freeze aliases, not 5276")
check(R.side[ActionButton1].player._slots.glow.enabled == false, "  a spell nothing glows: the slot off")
check(s3.player:GetFrameLevel() == ActionButton3:GetFrameLevel() + 5 and s3.player:IsMouseEnabled() == false, "  above the glass, clicks through")
check(ps.frame:IsMouseEnabled() == false, "  the slot frame clicks through")
eq(overlay, "overlay built", "  the screen overlay")
local ov = R.overlay
check(ov._slots.fof1 and ov._slots.fof1.frame._bar == nil, "  left: shown with any charge")
check(ov._slots.fof2 and ov._slots.fof2.frame._bar and ov._slots.fof2.frame._bar.min == 2, "  right: at 2 charges")
check(#sounds == 2 and sounds[1].trigger == 0 and sounds[2].trigger == 1, "  the sound on Added and ApplicationsIncreased")
check(sounds[1].info.soundFileID == 568016 and sounds[1].info.spellID == 400670 and sounds[1].info.unitToken == "player",
    "  the game's file, on Fingers of Frost")
eq(snd, "sounds: Added 101, ApplicationsIncreased 102", "  their ids")
eq(T.r3build(), "already built", "  once")

-- Paging: the button's own Update retargets; an unchanged one isn't written.
calls = {}
slots[3] = 116
ActionButton3:Update()
check(ps.enabled == false and ts.enabled == false and s3.key.player == nil, "the page changes: both slots off")
check(logHas("ActionButton3 player \"ice\" %-> nil %(Update"), "  logged")
local n0 = #calls
ActionButton3:Update()
eq(#calls, n0, "  an unchanged spell isn't written again")
slots[3] = 400640
ActionButton3:Update()
check(ps.enabled and ps.ids[400670] and ts.enabled and ts.ids[122], "  back: filters written, slots on again")
check(calls[#calls] == "enable" and calls[#calls - 1] == "filter", "  the filter, then enabled")
slots[3] = 428739
ActionButton3:Update()
check(ps.enabled and ts.enabled == false, "  Deep Freeze: Fingers of Frost lights it, a frozen target doesn't")
slots[3] = 400640
ActionButton3:Update()

-- Drift: the spell changed with no Update. Logged, not corrected.
slots[3] = 116
T.driftPoll()
check(logHas("DRIFT on ActionButton3: shows 116, filter \"ice\""), "drift: logged")
eq(s3.key.player, "ice", "  not corrected by the poll")
ActionButton3:Update()
T.driftPoll()
check(logHas("drift on ActionButton3 ended after"), "  ended by the Update")
slots[3] = 400640
ActionButton3:Update()

-- A target change refreshes the target glows a frame later.
local r0 = s3.target._refreshes
local r1 = R.side[ActionButton1].target._refreshes
WoW.fire("PLAYER_TARGET_CHANGED")
eq(s3.target._refreshes, r0, "target change: not at once")
WoW.flushTimers(0)
eq(s3.target._refreshes, r0 + 1, "  then refreshed")
eq(R.side[ActionButton1].target._refreshes, r1, "  only where a target glow is on")

-- Off, then on again with no reload.
removeThrows = true
T.r3off()
check(not T.r3offCheck() and #R.sounds == 2, "off: a removal that fails fails the step, the ids kept")
removeThrows = false
local _, offSound = T.r3off()
check(not s3.player:IsShown() and s3.player._enabled == false and not ov:IsShown(), "off: disabled and hidden")
eq(offSound, "sounds removed: 101, 102", "  the sound removed")
check(#R.sounds == 0 and removed[1] == 101 and removed[2] == 102, "  both registrations")
check(T.r3offCheck() == true, "  the step passes")
slots[3] = 116
n0 = #calls
ActionButton3:Update()
eq(#calls, n0, "  nothing written while off")
local onMsg, _, onSound = T.r3on()
eq(onSound, "sounds: Added 103, ApplicationsIncreased 104", "  the sound registered again")
check(#R.sounds == 2 and R.sounds[1] == 103, "  its new ids kept")
check(T.r3onCheck() == true, "  the step passes")
check(s3.player:IsShown() and s3.player._enabled == true and ov:IsShown() and ov._enabled == true, "on: shown and enabled")
eq(onMsg, "on: 193 containers shown and enabled", "  every container")
check(ps.enabled == false, "  and the page change made while off is caught up")
slots[3] = 400640
ActionButton3:Update()
T.r3off()
soundRefused = 1
local _, _, halfSound = T.r3on()
soundRefused = nil
eq(halfSound, "sounds: Added 105, ApplicationsIncreased nil", "on with the second sound refused: logged")
check(not T.r3onCheck() and #R.sounds == 1, "  the step fails")
soundRefused = 1
local _, _, againSound = T.r3on()
eq(againSound, "sounds: Added 105 kept, ApplicationsIncreased nil", "  run again, still refused: Added not registered twice")
check(not T.r3onCheck() and #R.sounds == 1, "  and the step still fails")
soundRefused = nil
_, _, againSound = T.r3on()
eq(againSound, "sounds: Added 105 kept, ApplicationsIncreased 106", "  run again, accepted: only the missing one added")
check(T.r3onCheck() == true and #R.sounds == 2, "  the step passes")
_, _, againSound = T.r3on()
eq(againSound, "sounds: Added 105 kept, ApplicationsIncreased 106 kept", "  a pass run again registers nothing")
check(T.r3onCheck() == true and #R.sounds == 2, "  and still passes")

-- Blink: hidden and shown again, in combat only, no protected change.
T.blink()
eq(R.blinks, 0, "blink: not out of combat")
local v3 = #WoW.violations
WoW.combat = true
T.blink()
check(not s3.player:IsShown() and R.side[ActionButton1].player:IsShown(), "  in combat: the lit buttons' glows hidden")
WoW.flushTimers(0.3)
check(s3.player:IsShown() and R.blinks == 1, "  shown again")
eq(#WoW.violations, v3, "  no change on a protected frame")
WoW.combat = false

-- Heating Up's mock: three layers, or the top one alone.
eq(T.heatingMock(false), "all three layers", "heating mock")
local shown = 0
for _, e in ipairs(R.mock.tex) do if e.t:IsShown() then shown = shown + 1 end end
eq(shown, 6, "  three layers, both sides")
T.heatingMock(true)
shown = 0
for _, e in ipairs(R.mock.tex) do if e.t:IsShown() then shown = shown + 1 end end
eq(shown, 2, "  the top layer alone")

-- Teardown: nothing left.
T.r3end()
check(not s3.player:IsShown() and s3.player._enabled == false and not ov:IsShown() and not R.mock:IsShown(), "teardown: all off")
check(#removed == 6 and removed[5] == 105 and removed[6] == 106, "  the live sounds removed")
check(T.r3state().on == nil and T.procState().on == nil, "  round 3 and the watcher reset")
slots[3] = 116
n0 = #calls
ActionButton3:Update()
eq(#calls, n0, "  the Update hook is inert after teardown")
eq(T.r3state().updates, 0, "  and counts nothing")
slots[3] = 400640
lines = #GABProbeDB.log
WoW.fire("PLAYER_TARGET_CHANGED")
WoW.flushTimers(0)
eq(#GABProbeDB.log, lines, "  the target event unregistered")

-- Stopped through the host: torn down too.
SlashCmdList.FOREVERPROBE("steps gab procs3")
WoW.flushTimers()
T.r3build()
check(T.r3state().on == true, "procs3 through the host: built")
SlashCmdList.FOREVERPROBE("steps stop")
check(T.r3state().on == nil and T.procState().on == nil, "  /fp steps stop: torn down")

-- At a boss: the Encounter restriction out of combat starts the build.
check(T.atBoss() == false, "procboss: waits for the restriction")
local secretOut = true
C_Secrets.ShouldAurasBeSecret = function() return secretOut end
check(T.atBoss() == true, "  on at the boss, out of combat")
rawset(T.Probe, "OnBlocked", function() return false end)
local okN, whyN = T.bossBuild()
check(okN == false and whyN:find("listener") and T.r3state().on == nil, "  no listener: not built")
rawset(T.Probe, "OnBlocked", nil)
blockInSetup = true
local okB, listener = T.bossBuild()
check(okB == true and listener == "listener on" and T.r3state().on == true, "  built with the listener on")
eq(T.procState().blocked, 1, "  a blocked action during the build is counted")
T.r3end()
check(T.nothingBlocked() == false, "  and fails the run")
C_Secrets.ShouldAurasBeSecret = function() return WoW.combat == true end

-- Native proc events, counted per class while the probe is installed.
WoW.fire("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", 400640)
local nat = GABProbeDB.native
local _, cls = UnitClass("player")
check(nat and nat[cls] and nat[cls]["GLOW_SHOW 400640"] >= 1, "native: counted per class and spell")
check(nat[cls]["HIDE nil"] >= 1, "  a spell-less HIDE counted too")
check(logHas("native: .- GLOW_SHOW 400640"), "  logged")
check(#WoW.chat == chatBefore, "  nothing in chat")

done("test_probe")
