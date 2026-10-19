-- Without Glass UI (#39): GAB's own material and look, as before. Pearl is
-- the default on trial; a saved Clean is kept; the material can be set (for
-- the next /reload); no "Glass UI" choices; nothing reported; SkinButton's
-- owner kept without a report to send.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local GAB = loadAddon({ db = { material = "clean", look = { theme = "smoked" } } })
local L, Settings = GAB.Look, GAB.Settings
eq(next(GAB.failures), nil, "nothing failed")
check(not L.Following(), "no Glass UI: not following")
eq(GAB.GlassPreset, "clean", "a saved Clean material kept")
eq(GAB.Theme.Current(), "smoked", "GAB's own tint")
eq(GAB.Buttons.Look("emptySlots"), "frosted", "GAB's own defaults for the rest")
check(Settings.SetMaterial("pearl") and GAB.db.material == "pearl", "the material set, for the next /reload")
local ok = Settings.SetMaterial("glossy")
eq(ok, false, "  an unknown material refused")
GAB.Options._test.panel:Show()
local T = GAB.Options._test
eq(#T.themeRadios, 3, "the glass: three tints, no Glass UI choice")
check(T.materialRadios and T.materialRadios[1]:GetChecked(), "  the material radios, Pearl checked")
GAB.Options.lookPage:Show()
eq(#T.lookRows.hover, 3, "Buttons page: no Glass UI choice")
local b = CreateFrame("Button", "ProviderButton1", UIParent)
check(GAB.SkinButton(b, { icon = b:CreateTexture() }, "Apotheca") and GAB.Buttons.IsSkinned(b), "SkinButton with an owner, no Glass UI: skinned")
eq(GAB.SkinButton(b, nil, 42), false, "  an owner that isn't a name: refused")
GlassActionBarsDB = { look = { hover = "sparkle", bogus = 1, press = "ripple" } }
local look = rawget(GAB._test.ensureDefaults(), "look")
check(look.hover == nil and look.bogus == nil and look.press == "ripple", "load: bad look entries dropped, good ones kept")
done("test_suite_absent")
