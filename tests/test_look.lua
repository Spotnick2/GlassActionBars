-- Button feedback (#34): the hover halo (fading in and out, from where it is),
-- Blizzard's highlight per mode, the press off / flash / ripple (from the
-- pointer, the centre when its place can't be read), the empty-slot glass, the
-- key text left to Blizzard, presets and "custom", the Buttons page, /gab
-- look, saved values cleaned.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local function close(a, b) return type(a) == "number" and type(b) == "number" and math.abs(a - b) < 1e-6 end

local GAB = loadAddon()
local B, Settings = GAB.Buttons, GAB.Settings
eq(next(GAB.failures), nil, "nothing failed")
local b = ActionButton1
local s = B.State(b)
local function scale()
    for _, x in ipairs(GAB.Theme._test.surfaces) do if x.g == s.g then return x.scale() end end
end

-- The Glass preset, the default: Blizzard's glow, the flash, frosted empty slots (owner).
eq(B.Preset(), "glass", "defaults: the Glass preset")
eq(B.Look("emptySlots"), "frosted", "  empty slots frosted by default")
check(close(b.HighlightTexture:GetAlpha(), B.HIGHLIGHT), "  Blizzard's highlight softened (glow)")
eq(s.halo:GetAlpha(), 0, "  the halo made, at rest")
eq(b.PushedTexture:GetAlpha(), 1, "  the pushed rim shown (flash)")

-- Hover: the halo fades in and out, from where it is.
check(Settings.SetLook("hover", "halo"), "hover halo")
eq(b.HighlightTexture:GetAlpha(), 0, "  Blizzard's highlight off")
eq(B.Preset(), "custom", "  no preset matches")
b:GetScript("OnEnter")(b)
WoW.tick(0.05)
check(close(s.halo:GetAlpha(), 0.5), "  half in after 0.05 s (0.1 s in)")
WoW.tick(0.06)
eq(s.halo:GetAlpha(), 1, "  fully in")
b:GetScript("OnLeave")(b)
WoW.tick(0.075)
check(close(s.halo:GetAlpha(), 0.5), "  half out after 0.075 s (0.15 s out)")
b:GetScript("OnEnter")(b)
WoW.tick(0.025)
check(close(s.halo:GetAlpha(), 0.75), "  back in from where it was, not from 0")
WoW.tick(0.1)
b:Hide()
eq(s.halo:GetAlpha(), 0, "  the button hidden: cleared")
b:Show()
WoW.hover[b] = true
Settings.SetLook("hover", "glow")
eq(s.halo:GetAlpha(), 0, "glow: the halo off at once")
check(close(b.HighlightTexture:GetAlpha(), B.HIGHLIGHT), "  Blizzard's highlight back")
Settings.SetLook("hover", "halo")
WoW.tick(0.2)
eq(s.halo:GetAlpha(), 1, "halo turned on under a still pointer: shown")
WoW.hover[b] = nil
Settings.SetLook("hover", "off")
eq(b.HighlightTexture:GetAlpha(), 0, "off: no highlight")
b:GetScript("OnEnter")(b)
WoW.tick(0.2)
eq(s.halo:GetAlpha(), 0, "  and no halo")

-- Press.
Settings.SetLook("press", "off")
eq(b.PushedTexture:GetAlpha(), 0, "press off: no pushed rim")
b:UpdateButtonArt()
eq(b.PushedTexture:GetAlpha(), 0, "  kept after Blizzard's UpdateButtonArt")
Settings.SetLook("press", "flash")
eq(b.PushedTexture:GetAlpha(), 1, "flash: the pushed rim")
b:GetScript("OnMouseDown")(b, "LeftButton")
eq(s.ripple, nil, "  no ripple on a click")
Settings.SetLook("press", "ripple")
b._rect = { 100, 145, 200, 155 }                -- left, right, top, bottom
WoW.cursor = { 110, 160 }
b:GetScript("OnMouseDown")(b, "LeftButton")
check(s.ripple and s.ripple:IsShown(), "ripple: shown on a click")
local p = s.ripple._points[1]
check(p[1] == "CENTER" and p[3] == "BOTTOMLEFT" and close(p[4], 10) and close(p[5], 5), "  centred on the pointer")
eq(b.PushedTexture:GetAlpha(), 1, "  the pushed rim too (key presses flash)")
WoW.tick(0.15)
check(close(s.ripple:GetWidth(), 45 * (0.3 + 1.3 * 0.5)) and close(s.ripple:GetAlpha(), 0.3), "  swelling and fading")
WoW.tick(0.2)
check(not s.ripple:IsShown(), "  gone after 0.3 s")
b._rect = { WoW.Secret("left"), 145, 200, 155 }
b:GetScript("OnMouseDown")(b, "LeftButton")
eq(s.ripple._points[1][3], "CENTER", "  an unreadable place: from the centre")
eq(#s.ripple._masks, 1, "  masked to the button's rounded square")
Settings.SetLook("press", "flash")
check(not s.ripple:IsShown(), "  press changed: cleared")
b._rect = nil

-- Empty slots: the glass of an empty slot, through the theme and the rim (once).
Settings.SetLook("emptySlots", "full")           -- frosted is the default; full is the old look
B.SetOccupied(b, false)
local wash, body = scale()
check(close(wash, B.Tune("wash")) and close(body, B.Tune("body")), "empty, full: the glass as today")
check(close(s.g.rim:GetAlpha(), B.Tune("rim") * B.Tune("empty")), "  the rim as today")
Settings.SetLook("emptySlots", "faint")
wash, body = scale()
check(close(body, B.Tune("body") * 0.25), "faint: the body at a quarter")
check(close(s.g.rim:GetAlpha(), B.Tune("rim") * B.Tune("empty") * 0.25), "  the rim too, once")
Settings.SetLook("emptySlots", "hidden")
check(not s.g.tint:IsShown(), "hidden: no body")
eq(s.g.rim:GetAlpha(), 0, "  no rim")
B.SetOccupied(b, true)
check(s.g.tint:IsShown() and close(s.g.rim:GetAlpha(), B.Tune("rim")), "  filled again: full glass")
Settings.SetLook("emptySlots", "frosted")
local _, _, own = scale()
eq(own, nil, "frosted, on a filled slot: the theme's own glass")
B.SetOccupied(b, false)
wash, body, own = scale()
check(own == B.FROST and body == 1, "frosted, empty: the pale neutral fill in place of the theme's tint")
check(close(s.g.rim:GetAlpha(), B.Tune("rim") * B.Tune("empty") * B.EMPTY.frosted), "  a softer rim")
check(s.g.tint:IsShown(), "  the fill shown")
local c = s.g.tint._color
check(c and close(c[1], B.FROST[1]) and close(c[3], B.FROST[3]) and close(c[4], B.FROST[4]), "  painted in that pale fill")
check(Settings.SetTheme("smoked"), "smoked glass")
_, body, own = scale()
eq(own, nil, "  a frosted empty slot keeps the smoked tint (the theme shows)")
check(close(s.g.tint._color[1], 0.05), "  painted smoked")
Settings.SetTheme("clear")
_, _, own = scale()
eq(own, B.FROST, "clear again: the pale fill")
B.SetOccupied(b, true)
_, _, own = scale()
eq(own, nil, "  filled again: the theme's glass")
local bag = B.State(CharacterBag0Slot)
B.SetOccupied(CharacterBag0Slot, false)
check(close(bag.g.rim:GetAlpha(), B.Tune("rim") * B.Tune("empty")), "a bag slot keeps its own empty look")
Settings.SetLook("emptySlots", "full")

-- Key text stays Blizzard's (moving it above was tried and taken out, session 5).
local hk = b.HotKey
p = hk._points
check(#p == 1 and p[1][1] == "TOPRIGHT" and hk._justifyH == "RIGHT", "the key text where Blizzard put it")
eq(Settings.SetLook("keyPosition", "above"), false, "  no setting moves it")

-- Presets.
check(Settings.SetLookPreset("soft"), "the Soft preset")
eq(B.Preset(), "soft", "  matches")
check(B.Look("hover") == "halo" and B.Look("press") == "ripple" and B.Look("emptySlots") == "frosted", "  all three set")
eq(Settings.SetLookPreset("loud"), false, "an unknown preset refused")
eq(Settings.SetLook("hover", "sparkle"), false, "an unknown choice refused")
eq(Settings.SetLook("glitter", "on"), false, "an unknown key refused")
eq(B.Look("hover"), "halo", "  nothing changed")

-- The Buttons page: presets and rows stay in step.
GAB.Options.lookPage:Show()
local T = GAB.Options._test
check(T.lookPresets[2]:GetChecked(), "the page: Soft checked")
T.lookPresets[3]:GetScript("OnClick")(T.lookPresets[3])
eq(B.Preset(), "minimal", "  Minimal clicked")
check(T.lookRows.hover[1]:GetChecked() and T.lookRows.emptySlots[1]:GetChecked(), "  every row followed it")
T.lookRows.hover[3]:GetScript("OnClick")(T.lookRows.hover[3])
check(not T.lookPresets[3]:GetChecked() and T.lookNow:GetText():find("own mix", 1, true), "  one row changed: your own mix")

-- /gab look.
newChat()
SlashCmdList.GLASSACTIONBARS("look glass")
eq(B.Preset(), "glass", "/gab look glass")
SlashCmdList.GLASSACTIONBARS("look empty half")
eq(B.Look("emptySlots"), "half", "/gab look empty half")
SlashCmdList.GLASSACTIONBARS("look hover sparkle")
check(chatHas("/gab look glass|soft|minimal"), "  a bad choice: the usage")
SlashCmdList.GLASSACTIONBARS("look")
check(chatHas("look: custom"), "/gab look: the current mix")

-- Saved values: an unknown choice dropped.
GlassActionBarsDB = { hover = "sparkle", press = "ripple", emptySlots = 3 }
local db = GAB._test.ensureDefaults()
check(db.look and db.look.hover == nil and db.look.emptySlots == nil and db.look.press == "ripple", "load: bad choices dropped, a good one moved into look")
check(rawget(db, "press") == nil, "  the old top-level key gone")
eq(next(GAB.failures), nil, "nothing failed")

done("test_look")
