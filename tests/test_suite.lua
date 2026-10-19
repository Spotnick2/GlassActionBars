-- Following Glass UI's suite (#39; Glass UI's docs/SUITE.md, SUITE-LOOK.md):
-- the material it names built at login, its look applied and then changed
-- live, the player's overrides in GlassActionBarsDB.look winning (legacy
-- top-level keys moved in, defaults included), "Glass UI" clearing them, the
-- material refused while following, SkinButton waiting for the glass with its
-- owner reported as a tenant, the report, and the options by source.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local reports = {}
local suiteLook = { tint = "smoked", hover = "halo", press = "ripple", emptySlots = "faint" }
GlassUI = { Suite = {
    API = 1,
    Theme = function(addon) return { name = "pearl", preset = "pearl" } end,
    Report = function(addon, state) reports[#reports + 1] = { addon = addon, state = state } end,
    Look = function()
        local t = {}
        for k, v in pairs(suiteLook) do t[k] = v end
        return t
    end,
} }
local function lastReport() return reports[#reports] and reports[#reports].state end

-- The player set theme and hover before (a default among them): they move into `look`.
local early
local GAB = loadAddon({ db = { theme = "clear", hover = "glow", material = "classic" }, beforeLogin = function(G)
    local b = CreateFrame("Button", "ApothecaButton1", UIParent)
    local icon = b:CreateTexture()
    early = { G.SkinButton(b, { icon = icon }, "Apotheca") }
    early.skinned = G.Buttons.IsSkinned(b)
    early.button = b
end })
local L, Settings, B = GAB.Look, GAB.Settings, GAB.Buttons
eq(next(GAB.failures), nil, "nothing failed")

-- The material: Glass UI's, whatever GAB's own says.
eq(GAB.GlassPreset, "pearl", "following: Glass UI's material built (GAB's own classic kept, unused)")
eq(GAB.db.material, "classic", "  GAB's own material still saved")
check(L.Following(), "  following")
local ok, why = Settings.SetMaterial("clean")
check(not ok and why == "set in Glass UI" and GAB.db.material == "classic", "  setting the material in GAB: refused")

-- SkinButton before the glass existed: waited, then built at login, its owner a tenant.
check(early[1] == true and not early.skinned, "a skin request before login: accepted and waiting")
check(B.IsSkinned(early.button), "  built once the glass existed")

-- The legacy keys moved into look, the defaults among them; the old keys gone.
local look = rawget(GAB.db, "look")
check(look and look.theme == "clear" and look.hover == "glow", "legacy theme and hover moved into look (defaults too)")
eq(rawget(GAB.db, "theme"), nil, "  the old top-level key gone")

-- The effective look: overrides first, then the suite's.
eq(GAB.Theme.Current(), "clear", "the player's own tint (an override) wins over the suite's smoked")
eq(B.Look("hover"), "glow", "  their own hover too")
eq(B.Look("press"), "ripple", "  press: the suite's")
eq(B.Look("emptySlots"), "faint", "  empty slots: the suite's")

-- The report.
local r = lastReport()
check(r and r.api == 1 and r.built == "pearl" and r.minor ~= nil, "reported: api 1, built pearl, LibGlass's minor")
check(r.look.tint == "clear" and r.look.hover == "glow" and r.look.press == "ripple" and r.look.emptySlots == "faint",
    "  the effective look, under Glass UI's names")
check(r.own.tint and r.own.hover and not r.own.press and not r.own.emptySlots, "  the overridden keys")
check(#r.tenants == 1 and r.tenants[1] == "Apotheca", "  the tenant: Apotheca")
check(type(r.options) == "function", "  a way to open GAB's options")

-- Glass UI's look changes live.
WoW.trigger("GlassUI.Suite.LookChanged", { tint = "class", hover = "off", press = "flash", emptySlots = "hidden" })
eq(B.Look("press"), "flash", "LookChanged: press followed")
eq(B.Look("emptySlots"), "hidden", "  empty slots followed")
eq(B.Look("hover"), "glow", "  the override kept")
eq(ActionButton1.PushedTexture:GetAlpha(), 1, "  repainted")
eq(lastReport().look.press, "flash", "  and reported")
WoW.trigger("GlassUI.Suite.LookChanged", { tint = "neon", hover = "sparkle" })
eq(B.Look("emptySlots"), "frosted", "an unknown or missing value: GAB's own default")
eq(L.SuiteValue("theme"), nil, "  an unknown tint not taken")

-- In combat: colours and alphas only, nothing moved on a protected button.
for _, b in ipairs({ ActionButton1, ActionButton2 }) do b._protected = true; b.PushedTexture._protected = true end   -- a protected button's region: no geometry in combat
WoW.combat = true
local before = #WoW.violations
WoW.trigger("GlassUI.Suite.LookChanged", { tint = "smoked", hover = "halo", press = "off", emptySlots = "faint" })
eq(#WoW.violations, before, "LookChanged in combat: no protected change")
eq(ActionButton1.PushedTexture:GetAlpha(), 0, "  press off applied")
WoW.combat = false

-- Clearing an override: back to Glass UI's.
check(Settings.ClearLook("theme"), "theme back to Glass UI's")
eq(GAB.Theme.Current(), "smoked", "  the suite's smoked")
check(not lastReport().own.tint, "  no longer reported as its own")
Settings.SetLook("press", "ripple")
eq(B.Look("press"), "ripple", "an override set in GAB")
check(Settings.SetLookPreset("suite"), "the preset row's Glass UI")
check(B.Look("hover") == "halo" and B.Look("press") == "off", "  all three feedback keys back to the suite's")

-- An override equal to GAB's default survives a reload (never pruned).
Settings.SetLook("hover", "glow")
GlassActionBarsDB = GAB.db
local db = GAB._test.ensureDefaults()
eq(rawget(db, "look").hover, "glow", "an override equal to GAB's default survives the load's prune")

-- The options: "Glass UI" choices, selected by source.
GAB.Options._test.panel:Show()
local T = GAB.Options._test
check(T.themeRadios[1]:GetChecked(), "the glass: Glass UI selected (no own tint)")
check(T.themeRadios[1].text:GetText():find("Smoked", 1, true), "  labelled with the suite's tint")
check(T.materialNote and T.materialNote:GetText():find("set in Glass UI", 1, true), "  the material: set in Glass UI")
GAB.Options.lookPage:Show()
check(not T.lookRows.hover[1]:GetChecked() and T.lookRows.hover[3]:GetChecked(), "Buttons page: hover is GAB's own (glow)")
check(T.lookRows.press[1]:GetChecked(), "  press: Glass UI")
T.lookRows.hover[1]:GetScript("OnClick")(T.lookRows.hover[1])
eq(L.Own("hover"), nil, "  clicking Glass UI clears the override")
check(T.lookPresets[1]:GetChecked(), "  the preset row: Glass UI, all three from the suite")
eq(next(GAB.failures), nil, "nothing failed")

done("test_suite")
