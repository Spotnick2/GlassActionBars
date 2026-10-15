-- The dock (#7): a smart bar placed beside an action bar from the union of
-- its laid-out containers, in UIParent units, anchored to UIParent in the
-- client's own units; geometry matched (lengths scaled, counts raw); the
-- first placement as a transaction; unavailable targets; combat deferral;
-- coalescing; the Edit Mode poll; secrets; settings, /gab dock, the page.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local function close(a, b) return type(a) == "number" and type(b) == "number" and math.abs(a - b) < 1e-6 end

local MAIN, BL = MainActionBar, MultiBarBottomLeft
-- Bar 1: one row of 12 at (500, 100): 500..1062 x 55..100.
WoW.layoutBar(MAIN, 500, 100)
WoW.layoutBar(BL, 500, 200)

local function fields(w)
    local t = {}
    for k, v in pairs(w) do if not (type(k) == "string" and k:sub(1, 1) == "_") then t[k] = v end end
    return t
end
local WATCH = { MAIN, BL, EditModeManagerFrame, ActionButton1 }
for _, c in ipairs(MAIN.shownButtonContainers) do WATCH[#WATCH + 1] = c end
local before = {}
for _, f in ipairs(WATCH) do before[f] = fields(f) end

local GAB = loadAddon()
local Dock, Settings = GAB.Dock, GAB.Settings
eq(next(GAB.failures), nil, "nothing failed")

-- A client: a protected frame (it holds secure buttons) whose Layout sizes it
-- two buttons wide from the geometry, logging every callback.
local function client(id, opts)
    opts = opts or {}
    local f = CreateFrame("Frame", "Test_" .. id, UIParent)
    f._protected = true
    f._width, f._height = 100, 45
    local log = {}
    local def = {
        id = id, label = "Test " .. id, frame = f, default = opts.default,
        OnHosted = function(on)
            log[#log + 1] = on and "hosted" or "released"
            if opts.hostedThrows and on then error("OnHosted broke") end
        end,
        Layout = function(g)
            log[#log + 1] = g and "layout" or "layout(nil)"
            log.geom = g
            if opts.layoutThrows then error("Layout broke") end
            if opts.relayout then Dock.RequestLayout(id) end
            if g then f._width, f._height = g.size * 2 + g.padding, g.size end   -- nil: its own size
        end,
    }
    check(Dock.Register(def), "register " .. id)
    return f, log, def
end
local function at(f)
    local p = f._points[#f._points]
    if not p then return nil end
    return p[4], p[5], p[1], p[2]
end
local function count(log, what)
    local n = 0
    for _, v in ipairs(log) do if v == what then n = n + 1 end end
    return n
end

-- Registered after world entry, not docked by default: left alone.
local A, logA = client("alpha")
WoW.tick()
eq(#logA, 0, "not docked: no callback")
eq(at(A), nil, "  not moved")

-- Docked to bar 1: hosted once, before the first Layout; matched; placed
-- right of the bar, centred, 4 apart, anchored to UIParent.
Settings.SetDock("alpha", "bar", 1)
WoW.tick()
eq(logA[1], "hosted", "docked: OnHosted(true) first")
eq(logA[2], "layout", "  then Layout")
check(close(logA.geom.size, 45) and close(logA.geom.padding, 2), "  geometry: 45 and 2 at 100%")
eq(logA.geom.rows, 1, "  one row")
eq(logA.geom.orientation, 0, "  horizontal")
local x, y, point, rel = at(A)
eq(point, "BOTTOMLEFT", "  anchored by its bottom-left")
eq(rel, UIParent, "  to UIParent, never a Blizzard bar")
check(close(x, 1066) and close(y, 55), ("  right of the bar, centred: %s, %s"):format(tostring(x), tostring(y)))
check(Dock.IsHosted("alpha"), "  hosted")
Dock.Request("alpha")
WoW.tick()
eq(count(logA, "hosted"), 1, "  OnHosted(true) only once, though placed again")

-- Sides and alignments (the client is 92 x 45).
local cases = {
    { "LEFT", "START", 404, 55 }, { "LEFT", "END", 404, 55 }, { "RIGHT", "START", 1066, 55 },
    { "TOP", "START", 500, 104 }, { "TOP", "END", 970, 104 }, { "TOP", "CENTER", 735, 104 },
    { "BOTTOM", "CENTER", 735, 6 },
}
for _, c in ipairs(cases) do
    Settings.SetDock("alpha", "side", c[1])
    Settings.SetDock("alpha", "align", c[2])
    WoW.tick()
    x, y = at(A)
    check(close(x, c[3]) and close(y, c[4]), ("%s %s: %s, %s (want %d, %d)"):format(c[1], c[2], tostring(x),
        tostring(y), c[3], c[4]))
end
-- Centred on a bar taller than the client (match off, 20 high): 67.5.
Settings.SetDock("alpha", "side", "RIGHT")
Settings.SetDock("alpha", "align", "CENTER")
Settings.SetDock("alpha", "match", false)
A._height = 20
WoW.tick()
x, y = at(A)
check(close(y, 67.5), "centred on the bar's middle: " .. tostring(y))
Settings.SetDock("alpha", "match", true)
Settings.SetDock("alpha", "side", "RIGHT")
Settings.SetDock("alpha", "align", "START")
Settings.SetDock("alpha", "gap", 8)
WoW.tick()
x = at(A)
check(close(x, 1070), "gap 8")

-- The rect: two rows, spacers, growth upward, a scaled bar.
WoW.layoutBar(MAIN, 500, 100, { stride = 6 })
local r = Dock.TargetRect(1)
check(close(r.right, 780) and close(r.bottom, 8), "two rows of 6: 500..780 x 8..100")
WoW.layoutBar(MAIN, 500, 100, { n = 8 })
r = Dock.TargetRect(1)
check(close(r.right, 500 + 8 * 47 - 2), "8 laid out (spacers count, the rest don't)")
WoW.layoutBar(MAIN, 500, 100, { stride = 6, up = true })
r = Dock.TargetRect(1)
check(close(r.top, 147) and close(r.bottom, 55), "growing up: 55..147")
WoW.layoutBar(MAIN, 1000, 200, { escale = 0.5 })
r = Dock.TargetRect(1)
check(close(r.left, 500) and close(r.top, 100), "a bar at half scale: UIParent units")
WoW.layoutBar(MAIN, 500, 100)

-- A scaled client, a vertical two-row bar: lengths scaled, counts raw.
MAIN._settings[0], MAIN._settings[1] = 1, 2
A._escale = 2
MAIN:UpdateGridLayout()                        -- the hook requests a pass
WoW.tick()
check(close(logA.geom.size, 22.5) and close(logA.geom.padding, 1), "client at scale 2: size 22.5, padding 1")
eq(logA.geom.rows, 2, "  rows raw")
eq(logA.geom.orientation, 1, "  orientation raw")
x, y = at(A)
check(close(x, 1070 / 2), "  placed in its own units")
A._escale = nil
MAIN._settings[0], MAIN._settings[1] = 0, 1

-- Match off: Layout(nil), the client's own geometry (it still arranges its contents).
local layouts, own = count(logA, "layout"), count(logA, "layout(nil)")
Settings.SetDock("alpha", "match", false)
WoW.tick()
eq(count(logA, "layout"), layouts, "match off: no matched geometry")
eq(count(logA, "layout(nil)"), own + 1, "  Layout(nil) instead")
Settings.SetDock("alpha", "match", true)
WoW.tick()

-- Coalescing: many requests in a frame, one pass; RequestLayout from inside
-- Layout is ignored.
layouts = count(logA, "layout")
Dock.Request(); Dock.Request("alpha"); MAIN:UpdateShownButtons(); EditModeManagerFrame:UpdateBottomActionBarPositions()
WoW.tick()
eq(count(logA, "layout"), layouts + 1, "four requests, one pass")
local R, logR = client("relayout", { relayout = true, default = { bar = 1 } })
WoW.tick()
WoW.tick()
eq(count(logR, "layout"), 1, "RequestLayout from inside Layout: no second pass")

-- Re-stacking without a grid update (UpdateBottomActionBarPositions) moves the dock.
WoW.layoutBar(MAIN, 600, 100)
EditModeManagerFrame:UpdateBottomActionBarPositions()
WoW.tick()
x = at(A)
check(close(x, 600 + 562 + 8), "the manager re-stacked the bars: the dock follows")
WoW.layoutBar(MAIN, 500, 100)
EditModeManagerFrame:UpdateRightActionBarPositions()
WoW.tick()

-- Unavailable target: never placed -> no OnHosted; shown later -> placed.
BL:Hide()
local B, logB = client("beta", { default = { bar = 2 } })
WoW.tick()
eq(#logB, 0, "hidden target: never told it is hosted")
eq(at(B), nil, "  not moved")
BL:Show()                                      -- the OnShow hook retries
WoW.tick()
eq(logB[1], "hosted", "  the target shown: hosted")
check(at(B) ~= nil, "  and placed")
-- Placed, then hidden: stays put, still hosted.
local bx, by = at(B)
BL:Hide()
WoW.layoutBar(BL, 0, 0)
Dock.Request()
WoW.tick()
local bx2, by2 = at(B)
check(bx2 == bx and by2 == by and Dock.IsHosted("beta"), "target hidden: stays put, still hosted")
BL:Show()
WoW.layoutBar(BL, 500, 200)

-- Combat: nothing moves (no protected change); PLAYER_REGEN_ENABLED applies it.
WoW.combat = true
WoW.fire("PLAYER_REGEN_DISABLED")
Settings.SetDock("alpha", "gap", 2)
WoW.tick()
WoW.tick()
x = at(A)
check(close(x, 1070), "in combat: not moved")
eq(#WoW.violations, 0, "  no protected change in combat")
WoW.combat = false
WoW.fire("PLAYER_REGEN_ENABLED")
WoW.tick()
x = at(A)
check(close(x, 1064), "  out of combat: applied")

-- Edit Mode: polled while open, nothing after it closes.
WoW.trigger("EditMode.Enter")
WoW.layoutBar(MAIN, 520, 100)                  -- a slider: no event
for _ = 1, 15 do WoW.tick(0.02) end
x = at(A)
check(close(x, 520 + 562 + 2), "Edit Mode open: polled")
WoW.trigger("EditMode.Exit")
WoW.tick()
eq(Dock._test.driver():GetScript("OnUpdate"), nil, "  closed: the driver idle")
WoW.layoutBar(MAIN, 500, 100)
for _ = 1, 15 do WoW.tick(0.02) end
x = at(A)
check(close(x, 520 + 562 + 2), "  no poll after it closed")
Dock.Request()
WoW.tick()

-- First placement fails: handed back, not hosted, recorded; others still placed.
local C, logC = client("gamma", { hostedThrows = true, default = { bar = 1 } })
local D, logD = client("delta", { layoutThrows = true, default = { bar = 1 } })
local E, logE = client("epsilon", { default = { bar = 1 } })
WoW.tick()
eq(logC[1], "hosted", "OnHosted(true) threw")
eq(logC[2], "released", "  OnHosted(false) follows")
check(not Dock.IsHosted("gamma") and at(C) == nil, "  not hosted, not moved")
check(GAB.failures["dock:gamma"] ~= nil, "  recorded in /gab failures")
check(#WoW.errors > 0, "  shown to the error handler")
eq(logD[#logD], "released", "Layout threw: released")
check(not Dock.IsHosted("delta"), "  not hosted")
check(Dock.IsHosted("epsilon") and at(E) ~= nil, "another client still placed")
-- A later failure on a hosted client keeps it hosted.
logE.geom = nil
local defE
for id, c in pairs(Dock._test.clients) do if id == "epsilon" then defE = c.def end end
defE.Layout = function() error("later") end
Dock.Request("epsilon")
WoW.tick()
check(Dock.IsHosted("epsilon"), "a later Layout failure: still hosted")

-- Secrets.
local F, logF = client("zeta")
F._width = WoW.Secret("GetWidth")
Settings.SetDock("zeta", "match", false)
Settings.SetDock("zeta", "bar", 1)
WoW.tick()
eq(logF[1], "hosted", "secret client width: OnHosted(true)")
eq(logF[#logF], "released", "  then handed back")
check(not Dock.IsHosted("zeta"), "  not hosted")
eq(GAB.failures["dock:zeta"], nil, "  a skip, not a failure")
-- A refused GetSettingValue: no Layout, still placed.
rawset(MAIN, "GetSettingValue", function() error("refused") end)
layouts = count(logA, "layout")
Dock.Request("alpha")
WoW.tick()
eq(count(logA, "layout"), layouts, "a refused GetSettingValue: no matched geometry")
eq(logA[#logA], "layout(nil)", "  Layout(nil): its own geometry")
rawset(MAIN, "GetSettingValue", nil)
rawset(MAIN, "GetSettingValue", function(self, s) return self._settings[s] end)
F._width = 100
rawset(BL, "IsVisible", function() return WoW.Secret("IsVisible") end)
local G, logG = client("eta", { default = { bar = 2 } })
WoW.tick()
eq(#logG, 0, "secret IsVisible on the target: unavailable")
rawset(BL, "IsVisible", nil)
WoW.tick()
MAIN.shownButtonContainers[12]._rect = { WoW.Secret("GetLeft"), 2000, 100, 55 }
r = Dock.TargetRect(1)
check(close(r.right, 500 + 11 * 47 - 2), "a container with a secret edge is left out")
WoW.layoutBar(MAIN, 500, 100)
MAIN._settings[3] = WoW.Secret("IconSize")
layouts = count(logA, "layout")
Dock.Request("alpha")
WoW.tick()
eq(count(logA, "layout"), layouts, "a secret setting: no matched geometry")
eq(logA[#logA], "layout(nil)", "  Layout(nil): its own geometry")
MAIN._settings[3] = 100
UIParent._escale = WoW.Secret("GetEffectiveScale")
eq(Dock.TargetRect(1), nil, "a secret UIParent scale: unavailable")
UIParent._escale = nil

-- Undock and unregister: OnHosted(false) once.
Settings.SetDock("alpha", "bar", false)
WoW.tick()
eq(logA[#logA], "released", "undocked: OnHosted(false)")
check(not Dock.IsHosted("alpha"), "  not hosted")
check(Dock.Unregister("epsilon"), "unregister")
WoW.tick()
for _, cl in ipairs(Dock.Clients()) do check(cl.id ~= "epsilon", "  gone from the list") end

-- Registration: bad ids and duplicates refused.
eq(Dock.Register({ id = "beta", frame = CreateFrame("Frame") }), false, "a duplicate id refused")
eq(Dock.Register({ id = "has space", frame = CreateFrame("Frame") }), false, "a bad id refused")
eq(Dock.Register({ id = "noframe" }), false, "no frame refused")

-- No field written on a Blizzard frame.
for _, f in ipairs(WATCH) do
    for k in pairs(fields(f)) do
        check(before[f][k] ~= nil, (f:GetName() or "container") .. ": no new field " .. tostring(k))
    end
end

-- /gab dock.
newChat()
SlashCmdList.GLASSACTIONBARS("dock beta 3 top end")
eq(Dock.Setting("beta", "bar"), 3, "/gab dock beta 3 top end")
eq(Dock.Setting("beta", "side"), "TOP", "  side")
eq(Dock.Setting("beta", "align"), "END", "  align")
SlashCmdList.GLASSACTIONBARS("dock beta gap 6")
eq(Dock.Setting("beta", "gap"), 6, "/gab dock beta gap 6")
SlashCmdList.GLASSACTIONBARS("dock beta match off")
eq(Dock.Setting("beta", "match"), false, "/gab dock beta match off")
SlashCmdList.GLASSACTIONBARS("dock beta off")
eq(Dock.Setting("beta", "bar"), false, "/gab dock beta off")
newChat()
SlashCmdList.GLASSACTIONBARS("dock nobody 1")
check(chatHas("/gab dock <bar>"), "an unknown bar: the usage line")
SlashCmdList.GLASSACTIONBARS("dock beta 9")
newChat()
SlashCmdList.GLASSACTIONBARS("dock")
check(#newChat() >= 2, "/gab dock lists the smart bars")

-- The Dock page: a section per client, added when one registers later.
GAB.Options.dockPage:Show()
local sections = GAB.Options._test.dockSections
check(sections.beta ~= nil, "the page: a section for beta")
check(sections.beta.gapText:GetText() == "now 6", "  a gap of 6 shows as 'now 6'")
check(not sections.beta.gap[1]:GetChecked() and not sections.beta.gap[4]:GetChecked(), "  no preset checked for 6")
GAB.Options.dockPage:Hide()
client("late")
GAB.Options.dockPage:Show()
check(sections.late ~= nil, "a client registered after the page was built: its section on the next show")
sections.late.bar[3]:GetScript("OnClick")(sections.late.bar[3])
eq(Dock.Setting("late", "bar"), 2, "  a click docks it to bar 2")

-- Saved settings are cleaned at load (unknown ids kept for a later provider).
GlassActionBarsDB = { dock = { later = { bar = 4, side = "UP", gap = 99, match = "yes" }, junk = "x", empty = {} } }
local db = GAB._test.ensureDefaults()
local d = rawget(db, "dock")
eq(d.later.bar, 4, "load: a valid key kept, for an id not registered yet")
eq(d.later.side, nil, "  a bad side dropped")
eq(d.later.gap, nil, "  a gap out of range dropped")
eq(d.later.match, nil, "  a non-boolean match dropped")
eq(d.junk, nil, "  a non-table dropped")
eq(d.empty, nil, "  an empty table dropped")

done("test_dock")
