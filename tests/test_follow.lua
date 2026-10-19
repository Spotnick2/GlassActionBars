-- The stance and pet bars follow Glass Unit Frames (#30): GUF's state at
-- login and its event; the offset in the bar's own units; Blizzard's
-- re-anchoring adopted as the new base, never doubled; Edit Mode entry puts an
-- owned bar back (and leaves one Blizzard re-anchored); a bar snapped to the
-- other moves with it; combat waits, the latest state wins; a scale change;
-- the setting; nothing moves without GUF's word.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local function close(a, b) return type(a) == "number" and type(b) == "number" and math.abs(a - b) < 1e-6 end
local function x(bar) return bar._points[1] and bar._points[1][4] end
local function settle() WoW.flushTimers(); WoW.flushTimers() end
local function announce(linked, dx, petDx)
    WoW.trigger("GlassUnitFrames.LayoutChanged", linked, 10, 20, 30, 40, 50, 60, 70, 80, dx, petDx)
end
local function reanchor(bar, px)                -- Blizzard's own pass
    bar:ClearAllPoints()
    bar:SetPoint("BOTTOMLEFT", UIParent, "BOTTOM", px, 120)
    EditModeManagerFrame:UpdateBottomActionBarPositions()
end

-- As Blizzard placed them (default position, both relative to UIParent).
StanceBar:SetPoint("BOTTOMLEFT", UIParent, "BOTTOM", -300, 120)
PetActionBar:SetPoint("BOTTOMLEFT", UIParent, "BOTTOM", 50, 120)
StanceBar._escale, PetActionBar._escale = 0.8, 0.8    -- UIParent 1: a move of d is d * 1.25 in bar units
GlassUF = { LayoutState = function() return { linked = true, dx = 40, petDx = 40 } end }
local GAB = loadAddon()
local F, Settings = GAB.Follow, GAB.Settings
eq(next(GAB.failures), nil, "nothing failed")
check(close(x(StanceBar), -300 + 50) and close(x(PetActionBar), 50 + 50), "GUF's state at login: both moved, in bar units")
eq(StanceBar._points[1][1], "BOTTOMLEFT", "  the anchor kept, only x moved")
eq(StanceBar._points[1][5], 120, "  its height kept")

-- The event: each bar by its own move.
announce(true, 100, 0)
check(close(x(StanceBar), -300 + 125), "dx 100: the stance bar")
check(close(x(PetActionBar), 50), "  petDx 0 (the pet frame saved absolute): the pet bar back")
announce(true, 100, 100)
check(close(x(PetActionBar), 50 + 125), "petDx 100: the pet bar")

-- Blizzard re-anchors: the new base; a pass that skipped the bar changes nothing.
reanchor(StanceBar, -320)
settle()
check(close(x(StanceBar), -320 + 125), "Blizzard re-anchored the stance bar: its new place is the base")
EditModeManagerFrame:UpdateBottomActionBarPositions()
settle()
EditModeManagerFrame:UpdateBottomActionBarPositions()
settle()
check(close(x(StanceBar), -320 + 125), "  passes that skipped it: not moved twice")
StanceBar.ApplySystemAnchor(StanceBar)           -- the hooked instance method
settle()
check(close(x(StanceBar), -320 + 125), "  ApplySystemAnchor without a re-anchor: the same")

-- A scale change: the same base, the new ratio; fractional offsets stay owned.
StanceBar._escale, PetActionBar._escale = 0.7, 0.7
WoW.fire("UI_SCALE_CHANGED")
check(close(x(StanceBar), -320 + 100 / 0.7), "UI scale changed: re-applied with the new ratio")
EditModeManagerFrame:UpdateBottomActionBarPositions()
settle()
check(close(x(StanceBar), -320 + 100 / 0.7), "  a fractional offset is still ours: not doubled")

-- Edit Mode: an owned bar goes back; nothing moves while it's open; it re-pins after.
WoW.trigger("EditMode.Enter")
check(close(x(StanceBar), -320) and close(x(PetActionBar), 50), "Edit Mode opened: both back at their Edit Mode positions")
announce(true, 50, 50)
check(close(x(StanceBar), -320), "  a move announced while it's open waits")
WoW.trigger("EditMode.Exit")
settle()
check(close(x(StanceBar), -320 + 50 / 0.7), "Edit Mode closed: following again, with the latest move")
-- Blizzard re-anchored it before EditMode.Enter: kept, not put back to the stale base.
StanceBar:ClearAllPoints()
StanceBar:SetPoint("BOTTOMLEFT", UIParent, "BOTTOM", -340, 120)
WoW.trigger("EditMode.Enter")
check(close(x(StanceBar), -340), "Blizzard placed it as Edit Mode opened: left where Blizzard put it")
WoW.trigger("EditMode.Exit")
settle()
check(close(x(StanceBar), -340 + 50 / 0.7), "  and it becomes the base")

-- Snaps (Codex review of #35). The player snapped the stance bar to the pet
-- bar: neither moves, so dismissing the pet (Blizzard breaks the snap and
-- freezes the stance bar where it is) can't put a shifted place in the layout.
rawset(StanceBar, "snappedToFrame", PetActionBar)
rawset(PetActionBar, "snappedFrames", { [StanceBar] = true })
StanceBar:ClearAllPoints()
StanceBar:SetPoint("LEFT", PetActionBar, "RIGHT", 5, 0)
EditModeManagerFrame:UpdateBottomActionBarPositions()
settle()
eq(x(StanceBar), 5, "the stance bar snapped to the pet bar: stays")
check(close(x(PetActionBar), 50), "  the pet bar, with a bar snapped to it: put back, stays")
check(F.Status().PetActionBar:find("snapped to it", 1, true), "  /gab follow says why (pet bar)")
check(F.Status().StanceBar:find("snapped to PetActionBar", 1, true), "  and why (stance bar)")
StanceBar.BreakFrameSnap(StanceBar)              -- the pet dismissed: Blizzard freezes the stance bar
rawset(StanceBar, "snappedToFrame", nil)
rawset(PetActionBar, "snappedFrames", nil)
eq(x(StanceBar), 5, "  the frozen stance bar holds no shift")
settle()
eq(StanceBar._points[1][1], "TOPLEFT", "  and once free, it follows from the frozen place")
check(close(x(StanceBar), 5 + 50 / 0.7), "    (by dx)")
-- A default-position bar is snapped to Action Bar 1 by Blizzard's stacking: it follows,
-- and a freeze (Action Bar 1 hidden) never doubles the shift.
reanchor(StanceBar, -340)
reanchor(PetActionBar, 50)
settle()
rawset(PetActionBar, "snappedToFrame", MainActionBar)
PetActionBar._default = true
EditModeManagerFrame:UpdateBottomActionBarPositions()
settle()
check(close(x(PetActionBar), 50 + 50 / 0.7), "a default pet bar stacked on Action Bar 1: follows")
PetActionBar.BreakFrameSnap(PetActionBar)        -- Action Bar 1 hid: frozen where we had it
settle()
check(close(x(PetActionBar), 50 + 50 / 0.7), "  frozen there: our shift taken off the new base, not doubled")
announce(true, 0, 0)
check(close(x(PetActionBar), 50), "  and back to the unshifted place")
announce(true, 50, 50)
PetActionBar.BreakFrameSnap(PetActionBar)        -- frozen while ours, then Blizzard re-stacks before our pass
reanchor(PetActionBar, 60)
settle()
check(close(x(PetActionBar), 60 + 50 / 0.7), "  re-stacked after a freeze: a fresh base, nothing taken off")
-- The player snapped the pet bar to another bar (not default): stays.
PetActionBar._default = false
announce(true, 50, 50)
check(close(x(PetActionBar), 60), "the pet bar snapped by the player to Action Bar 1: put back, stays")
rawset(PetActionBar, "snappedToFrame", nil)
reanchor(PetActionBar, 50)
settle()

-- Combat: nothing moves; after it, the latest state.
WoW.combat = true
announce(true, 80, 80)
announce(true, 0, 0)
eq(#WoW.violations, 0, "in combat: no protected move")
check(close(x(StanceBar), -340 + 50 / 0.7), "  the bars stay")
WoW.combat = false
WoW.fire("PLAYER_REGEN_ENABLED")
check(close(x(StanceBar), -340) and close(x(PetActionBar), 50), "after combat: the latest (unlinked) state")

-- The setting.
announce(true, 30, 30)
Settings.SetFollow(false)
check(close(x(StanceBar), -340) and close(x(PetActionBar), 50), "follow off: back")
Settings.SetFollow(true)
check(close(x(StanceBar), -340 + 30 / 0.7), "  on: following again")
announce(false, 30, 30)
check(close(x(StanceBar), -340), "unlinked: back, whatever dx says")

-- Two anchors: not ours to move.
StanceBar:SetPoint("TOP", UIParent, "TOP", 0, 0)
announce(true, 30, 30)
eq(#StanceBar._points, 2, "two anchors: untouched")
check(F.Status().StanceBar:find("unreadable", 1, true), "  and said so")
StanceBar:ClearAllPoints()
StanceBar:SetPoint("BOTTOMLEFT", UIParent, "BOTTOM", -300, 120)

-- A secret or nonsense move counts as none.
announce(true, WoW.Secret("dx"), 0 / 0)
check(close(x(StanceBar), -300) and close(x(PetActionBar), 50), "a secret or NaN move: none")

-- /gab follow.
newChat()
SlashCmdList.GLASSACTIONBARS("follow")
check(chatHas("stance bar"), "/gab follow: each bar's state")
SlashCmdList.GLASSACTIONBARS("follow off")
eq(GAB.db.follow, false, "/gab follow off")
eq(next(GAB.failures), nil, "nothing failed")

done("test_follow")
