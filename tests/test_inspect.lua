-- /gab inspect and /gab layer: the in-game layer inspector. It lists what a
-- button draws (ours and Blizzard's), hides one region or one named layer for
-- a look, and gives every alpha back.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

WoW.actions[1] = true
local GAB = loadAddon()
local slash = SlashCmdList.GLASSACTIONBARS

newChat()
slash("inspect")
check(chatHas("inspect ActionButton2: skinned true, occupied false"), "the first empty button by default")
check(chatHas("GAB  glass%.tint"), "our tint is listed, named")
check(chatHas("GAB  glass%.rim"), "our rim is listed, named")
check(chatHas("Blizzard  SlotArt"), "Blizzard's slot art is listed, by its key")
check(chatHas("Blizzard  HotKey"), "  and the text in its child frame")
local saved = GlassActionBarsDB.inspect
check(saved and #saved.lines > 10, "the report is saved for reading off disk")

newChat()
slash("inspect ActionButton1")
check(chatHas("inspect ActionButton1: skinned true, occupied true"), "a named button")

-- Hide one region, then show it again.
local T = GAB.Inspect._test
local n, slotArt
for i, r in pairs(T.last.regions) do if r == ActionButton1.SlotArt then n, slotArt = i, r end end
check(n ~= nil, "SlotArt has a number")
local rimRegion = GAB.Buttons.State(ActionButton1).g.rim
local m
for i, r in pairs(T.last.regions) do if r == rimRegion then m = i end end
local before = rimRegion:GetAlpha()
slash("inspect hide " .. m)
eq(rimRegion:GetAlpha(), 0, "inspect hide: alpha 0")
check(rimRegion:IsShown(), "  never hidden")
slash("inspect show " .. m)
eq(rimRegion:GetAlpha(), before, "inspect show: the alpha back")

-- One named layer, on every button.
local tint2 = GAB.Buttons.State(MultiBar7Button12).g.tint
local was = tint2:GetAlpha()
slash("layer tint off")
eq(tint2:GetAlpha(), 0, "layer tint off: every button")
eq(GAB.Buttons.State(PetActionButton1).g.tint:GetAlpha(), 0, "  every family")
slash("layer tint on")
eq(tint2:GetAlpha(), was, "layer tint on: back")
slash("layer rim off")
slash("inspect restore")
eq(rimRegion:GetAlpha(), before, "inspect restore: every hidden region back")
newChat()
slash("layer nonsense off")
check(chatHas("/gab layer <body|tint"), "an unknown layer: the usage")

-- Nothing is saved as a setting.
eq(rawget(GlassActionBarsDB, "tune"), nil, "no setting changed")
eq(#WoW.violations, 0, "nothing protected touched")

done("test_inspect")
