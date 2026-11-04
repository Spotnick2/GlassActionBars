-- The lock on the Utility bar (#34): off until ticked (no saved table made
-- before that); an insecure button with no secure attributes; a click out of
-- combat flips lockActionBars both ways, its padlock follows (and follows the
-- Options checkbox through CVAR_UPDATE); in combat it writes nothing and is
-- dimmed; a bound key does nothing while it isn't on the bar; the saved
-- show rule keeps true and drops false for it.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

WoW.layoutBar(MainActionBar, 500, 100)
WoW.cvars.lockActionBars = "1"
local GAB = loadAddon()
local U, Settings = GAB.Utility, GAB.Settings
eq(next(GAB.failures), nil, "nothing failed")
local b = U.buttons.lockbars
local R = U._test.regions
local function rebuild() U.Refresh(); WoW.tick() end
local function onBar()
    for _, x in ipairs(U._test.shown()) do if x == b then return true end end
    return false
end
local function click(btn) b:GetScript("OnClick")(b, btn or "LeftButton", false) end
local function icon() return R[b].icon._file end

check(_G.GlassActionBarsUtil_lockbars == b, "a named button from load")
check(not b:GetAttribute("type"), "  no secure attributes")
eq(U.Order()[#U.ORDER_KEYS - 1], "lockbars", "  last of the actions, before Camping")
eq(_G["BINDING_NAME_" .. U.BindingAction("lockbars")], "Lock Action Bars", "  its binding named")

-- Off by default.
rebuild()
check(not onBar(), "off by default")
eq(rawget(GAB.db, "utility"), nil, "  no saved table made")
click()
eq(WoW.cvars.lockActionBars, "1", "  a bound key while it isn't on the bar: nothing written")

-- Ticked: on the bar, the padlock closed.
Settings.SetUtilityShown("lockbars", true)
WoW.tick()
check(onBar(), "ticked: on the bar")
check(U.frame:IsShown(), "  the bar shown for it alone")
eq(GAB.db.utility.show.lockbars, true, "  saved as true")
check(icon():find("LockClosed$"), "  locked: the closed padlock")
check(not b:GetAttribute("type") and not b:GetAttribute("spell"), "  still no secure attributes")

-- A click flips it both ways; the padlock follows.
click()
eq(WoW.cvars.lockActionBars, "0", "a click unlocks")
check(icon():find("LockOpen$"), "  the open padlock")
click()
eq(WoW.cvars.lockActionBars, "1", "again: locks")
check(icon():find("LockClosed$"), "  closed")
click("RightButton")
eq(WoW.cvars.lockActionBars, "1", "a right click: nothing")

-- The Options checkbox (another writer): CVAR_UPDATE repaints; another CVar's doesn't.
WoW.cvars.lockActionBars = "0"
WoW.fire("CVAR_UPDATE", "someOtherCVar", "1")
check(icon():find("LockClosed$"), "another CVar's update: not repainted")
WoW.fire("CVAR_UPDATE", "lockActionBars", "0")
check(icon():find("LockOpen$"), "lockActionBars changed elsewhere: the padlock follows")

-- An unreadable CVar: no write.
WoW.cvarSecret = true
click()
WoW.cvarSecret = nil
eq(WoW.cvars.lockActionBars, "0", "a secret GetCVarBool: nothing written")

-- The tooltip.
b:GetScript("OnEnter")(b)
local tip = table.concat(GameTooltip._lines, "|")
check(tip:find("Lock Action Bars", 1, true) and tip:find("Unlocked", 1, true) and tip:find("Click to lock", 1, true),
    "the tooltip: its name, the state, what a click does")

-- Combat: nothing written, dimmed; undimmed after.
WoW.combat = true
WoW.fire("PLAYER_REGEN_DISABLED")
WoW.advance(0.1)                                 -- dimmed a frame after combat starts
click()
eq(WoW.cvars.lockActionBars, "0", "in combat: a click writes nothing")
check(R[b].icon:GetAlpha() < 1, "  dimmed")
b:GetScript("OnEnter")(b)
check(table.concat(GameTooltip._lines, "|"):find("Not in combat", 1, true), "  the tooltip says why")
eq(#WoW.violations, 0, "  no protected change")
WoW.combat = false
WoW.fire("PLAYER_REGEN_ENABLED")
WoW.advance(0.1)                                 -- the visual refresh a frame after combat
eq(R[b].icon:GetAlpha(), 1, "after combat: undimmed")

-- Unticked, or the bar off: a bound key writes nothing.
Settings.SetUtilityShown("lockbars", false)
WoW.tick()
check(not onBar(), "unticked: off the bar")
eq(GAB.db.utility.show.lockbars, nil, "  nothing saved for it (off is its default)")
click()
eq(WoW.cvars.lockActionBars, "0", "  a bound key writes nothing")
Settings.SetUtilityShown("lockbars", true)
Settings.SetUtilityEnabled(false)
click()
eq(WoW.cvars.lockActionBars, "0", "the bar off: a bound key writes nothing")
Settings.SetUtilityEnabled(true)
WoW.tick()
click()
eq(WoW.cvars.lockActionBars, "1", "on again: it works")

local attrs = b._attrs
check(attrs == nil, "the lock's button never got an attribute (it isn't secure)")

-- Saved settings: true kept, false dropped for the opt-in key.
local ensure = GAB._test.ensureDefaults
GlassActionBarsDB = { utility = { show = { lockbars = true } } }
eq(rawget(ensure(), "utility").show.lockbars, true, "load: the lock ticked kept")
GlassActionBarsDB = { utility = { show = { lockbars = false } } }
eq(rawget(ensure(), "utility").show.lockbars, nil, "  false dropped: off is its default")

-- The textures ship (Media/*.tga, deploy.ps1 and the package check take every one).
for _, n in ipairs({ "LockClosed", "LockOpen" }) do
    check(io.open("Media/" .. n .. ".tga", "rb") ~= nil, "Media/" .. n .. ".tga exists")
end

done("test_lock")
