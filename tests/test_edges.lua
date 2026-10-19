-- The screen's edges for the suite (#37): the owner's two left bars as one
-- stack, a horizontal bar ignored, a right-side stack, the 40-unit gap (and
-- exactly 40), overlaps never shrinking the edge, hidden bars and an
-- unreadable outer button skipped, a free Utility bar counted, the event out
-- of combat only and only past half a unit from the last one announced,
-- EdgeState a fresh copy.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local function close(a, b) return type(a) == "number" and type(b) == "number" and math.abs(a - b) < 1e-6 end
UIParent._width = 2133
-- The owner's layout: MultiBar5 (bar 6) at the very left, MultiBar6 (bar 7) beside it, vertical.
WoW.layoutBar(MultiBar5, 2, 900, { stride = 1 })        -- 2..47
WoW.layoutBar(MultiBar6, 51, 900, { stride = 1 })       -- 51..96
local GAB = loadAddon()
local E = GAB.Edges
WoW.tick(); WoW.tick()
eq(next(GAB.failures), nil, "nothing failed")
local function last() return WoW.triggered[#WoW.triggered] end
local function settle() WoW.tick(); WoW.tick() end

local s = GAB.EdgeState()
check(s and close(s.left, 96) and close(s.right, 2133) and close(s.width, 2133), "the owner's two left bars: left = 96")
local ev = last()
check(ev and ev[1] == "GlassActionBars.EdgesChanged" and close(ev[2], 96) and close(ev[3], 2133), "  announced")
s.left = 0
eq(GAB.EdgeState().left, 96, "  EdgeState: a fresh copy each call")
local fired = #WoW.triggered

-- A horizontal bar near a corner: ignored. Nothing changed: no event.
WoW.layoutBar(MultiBarBottomLeft, 0, 200)
E.Request(); settle()
eq(#WoW.triggered, fired, "a horizontal bar at the corner: ignored, no event")

-- A bar nested inside the stack (at half scale: 60..82.5) never shrinks it.
WoW.layoutBar(MultiBar7, 120, 1400, { stride = 1, n = 3, escale = 0.5 })
E.Request(); settle()
eq(GAB.EdgeState().left, 96, "a bar nested in the stack: the edge stays")
WoW.layoutBar(MultiBar7, 3000, 700, { stride = 1, n = 0 }) -- gone

-- The right side: a stack from the screen's right edge.
WoW.layoutBar(MultiBarRight, 2086, 900, { stride = 1 })    -- 2086..2131
WoW.layoutBar(MultiBarLeft, 2037, 900, { stride = 1 })     -- 2037..2082
E.Request(); settle()
check(close(GAB.EdgeState().right, 2037), "the right side: a stack of two, right = 2037")
check(close(last()[3], 2037) and #WoW.triggered == fired + 1, "  announced once")

-- The gap: more than 40 ends the walk; exactly 40 still counts.
WoW.layoutBar(MultiBar6, 88, 900, { stride = 1 })        -- 47 -> 88: a gap of 41
E.Request(); settle()
check(close(GAB.EdgeState().left, 47), "a gap of 41: the second bar not counted")
WoW.layoutBar(MultiBar6, 87, 900, { stride = 1 })        -- a gap of exactly 40
E.Request(); settle()
check(close(GAB.EdgeState().left, 132), "a gap of exactly 40: counted")
WoW.layoutBar(MultiBar6, 51, 900, { stride = 1 })
E.Request(); settle()

-- Hidden: the bar's own OnHide asks for a measure.
MultiBar5:Hide(); settle()
check(close(GAB.EdgeState().left, 0), "MultiBar5 hidden: MultiBar6 alone isn't within 40 of the edge")
MultiBar5:Show(); settle()
check(close(GAB.EdgeState().left, 96), "  shown again")

-- An unreadable outer button: the bar skipped, not reported short.
local c1 = MultiBar5.shownButtonContainers[1]
local keep = c1._rect
c1._rect = { WoW.Secret("left"), keep[2], keep[3], keep[4] }
E.Request(); settle()
check(close(GAB.EdgeState().left, 0), "a secret edge on MultiBar5: skipped (not guessed)")
c1._rect = keep
E.Request(); settle()

-- A free Utility bar (a dock client) at the right edge counts.
MultiBarRight:Hide(); MultiBarLeft:Hide(); settle()
check(close(GAB.EdgeState().right, 2133), "the right bars hidden: right = width")
local U = GAB.Utility.frame
U:Show()
U._rect = { 2100, 2130, 600, 400 }
GAB.Settings.SetDock("utility", "bar", false)
GAB.Dock.Request("utility"); settle()
check(close(GAB.EdgeState().right, 2100), "a free Utility bar at the right edge: counted")
U:Hide(); settle()
check(close(GAB.EdgeState().right, 2133), "  hidden: its OnHide measures again")

-- A provider's bar registered later is watched too.
local pf = CreateFrame("Frame", "ProviderBar", UIParent)
pf._rect = { 2090, 2130, 700, 500 }
check(GAB.RegisterBar({ id = "prov", label = "Provider", frame = pf, OnHosted = function() end }), "a provider registers")
settle()
check(close(GAB.EdgeState().right, 2090), "  its free bar at the right edge: counted")
pf:Hide(); settle()
check(close(GAB.EdgeState().right, 2133), "  hidden: its OnHide measures again")

-- Combat: never announced in a fight; after it.
fired = #WoW.triggered
WoW.combat = true
MultiBar5:Hide(); settle()
eq(#WoW.triggered, fired, "in combat: no event")
WoW.combat = false
WoW.fire("PLAYER_REGEN_ENABLED"); settle()
check(#WoW.triggered == fired + 1 and close(last()[2], 0), "  announced when the fight ends")
MultiBar5:Show(); settle()

-- Half a unit: small moves add up against the last value announced.
fired = #WoW.triggered
WoW.layoutBar(MultiBar6, 51.3, 900, { stride = 1 })
E.Request(); settle()
eq(#WoW.triggered, fired, "0.3 units: no event")
WoW.layoutBar(MultiBar6, 51.6, 900, { stride = 1 })
E.Request(); settle()
check(#WoW.triggered == fired + 1 and close(last()[2], 96.6), "  0.6 from the last announced: announced")

-- A Dock pass asks for a measure.
WoW.layoutBar(MultiBar6, 60, 900, { stride = 1 })
GAB.Dock.Request(); settle()
check(close(GAB.EdgeState().left, 105), "after a dock pass: measured")
eq(next(GAB.failures), nil, "nothing failed")

done("test_edges")
