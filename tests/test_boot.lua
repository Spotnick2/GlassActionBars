-- Loading, saved settings, the options page and /gab.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local GAB = loadAddon({ db = { stale = true } })
check(GAB.db ~= nil, "settings are set up at ADDON_LOADED")
eq(GlassActionBarsDB, GAB.db, "the saved table is the live one")
eq(GlassActionBarsDB.stale, true, "an unknown saved key is kept (nothing may require it)")
check(next(GAB.failures) == nil, "nothing failed to start")

-- A saved key equal to its default is dropped; the default still reads through.
GAB._test.DEFAULTS.probeKey = 7
GlassActionBarsDB = { probeKey = 7 }
local db = GAB._test.ensureDefaults()
eq(rawget(db, "probeKey"), nil, "a saved default is dropped")
eq(db.probeKey, 7, "  and still reads through")
GAB._test.DEFAULTS.probeKey = nil

-- Not a table (a corrupt or absent save) starts over.
GlassActionBarsDB = "junk"
check(type(GAB._test.ensureDefaults()) == "table", "a corrupt save starts over")

-- The options page: registered once at login, built on first show.
eq(#WoW.categories, 3, "the options page and its sub-pages")
eq(WoW.categories[1].name, "Glass Action Bars", "  named after the addon")
check(WoW.categories[1].registered, "  registered as an AddOn page")
eq(WoW.categories[2].name, "Bar fade", "  the Bar fade sub-page")
eq(WoW.categories[2].parent, WoW.categories[1], "  under ours")
eq(WoW.categories[3].name, "Dock", "  the Dock sub-page")
eq(WoW.categories[3].parent, WoW.categories[1], "  under ours")
GAB.Options._test.panel:Show()
check(GAB.Options.built, "the page builds on first show")
check(GAB.Options.Open(), "/gab options opens it")

-- /gab: help by default, and every command answers.
newChat()
SlashCmdList.GLASSACTIONBARS("")
check(chatHas("/gab options"), "help lists the commands")
for _, cmd in ipairs({ "failures", "version", "options", "nonsense" }) do
    newChat()
    SlashCmdList.GLASSACTIONBARS(cmd)
    check(#newChat() >= 0, "/gab " .. cmd .. " runs")
end
SlashCmdList.GLASSACTIONBARS("version")
check(chatHas("measured on 1.60.1.70374"), "/gab version names the measured build")

-- A dev build on another client build warns once, at initial login only.
newChat()
WoW.fire("PLAYER_ENTERING_WORLD", true, false)
check(not chatHas("differs from the one"), "no warning on the measured build")
local real = GetBuildInfo
GetBuildInfo = function() return "1.60.1", "79999", "x", 16001 end
WoW.fire("PLAYER_ENTERING_WORLD", false, false)
check(not chatHas("differs from the one"), "no warning on a /reload")
WoW.fire("PLAYER_ENTERING_WORLD", true, false)
check(chatHas("differs from the one"), "a warning at login on another build")
GetBuildInfo = real

done("test_boot")
