-- Pearl's button face: state transitions, retained choices, and live combat
-- repainting. Rendering/cooldown order is deliberately an in-game check.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local function close(a, b) return type(a) == "number" and math.abs(a - b) < 1e-6 end
local GAB = loadAddon({ db = { tune = { frostGrey = 0.9, rim = 0.85 } } })
local B, Settings = GAB.Buttons, GAB.Settings
local b = ActionButton1
local s = B.State(b)
eq(GAB.GlassPreset, "pearl", "default material")
local saved = GAB.db.tune or {}
eq(saved.frostGrey, 0.9, "explicit old-default grey survives login")
eq(saved.rim, 0.85, "explicit old-default rim survives login")
SlashCmdList.GLASSACTIONBARS("tune reset")
eq(B.Tune("frostGrey"), 0.40, "reset selects Pearl grey")
eq(B.Tune("frostAlpha"), 0.22, "reset selects Pearl opacity")
check(s.socketRim:GetAlpha() > 0 and s.g.rim:GetAlpha() == 0, "empty: only the recessed rim")
check(s.socketShade:GetAlpha() > 0 and s.gloss:GetAlpha() == 0, "empty: upper shade, no icon shine")
-- On the rim's frame, one level over the button (a fixed order over the icon),
-- under the key and count text; masked to the rounded square, under the rim.
eq(s.gloss:GetParent(), s.g.top, "the reflection is on the rim's frame")
check(s.g.top:GetFrameLevel() > b:GetFrameLevel(), "  over the button's level")
check(s.g.top:GetFrameLevel() < b.TextOverlayContainer:GetFrameLevel(), "  under the key/count text")
check(s.gloss._masks and #s.gloss._masks == 1, "  masked to the rounded square")
eq(s.gloss._layer, "ARTWORK", "  under the rim (OVERLAY)")
eq(s.socketRim:GetParent(), s.g.top, "the socket too")
local c = s.g.tint._color
check(close(c[1], c[2]) and close(c[2], c[3]), "Pearl empty fill is neutral")

B.SetOccupied(b, true)
check(s.g.rim:GetAlpha() > 0 and s.socketRim:GetAlpha() == 0 and s.socketShade:GetAlpha() == 0,
    "filled: recessed edges disappear")
check(close(s.gloss:GetAlpha(), 0.08), "filled: upper reflection")
local file = b.icon._file
local points = #b.icon._points
WoW.combat = true
Settings.SetTune("gloss", 0)
eq(s.gloss:GetAlpha(), 0, "live zero removes reflection")
Settings.SetTune("gloss", 0.12)
eq(s.gloss:GetAlpha(), 0.12, "live reflection in combat")
B.SetOccupied(b, false)
Settings.SetLook("emptySlots", "hidden")
check(s.socketRim:GetAlpha() == 0 and s.socketShade:GetAlpha() == 0 and s.gloss:GetAlpha() == 0,
    "hidden empty slot: no Pearl layers left")
check(not s.g.tint:IsShown(), "hidden empty slot: no fill")
Settings.SetLook("emptySlots", "frosted")
check(s.socketRim:GetAlpha() > 0, "frosted restores socket")
eq(#WoW.violations, 0, "no protected operation in combat")
eq(b.icon._file, file, "icon artwork unchanged")
eq(#b.icon._points, points, "icon anchoring unchanged")
WoW.combat = false
Settings.SetTheme("class")
check(s.g.tint._color[1] ~= s.g.tint._color[3], "class tint preserved")
check(s.socketRim:GetAlpha() > 0, "tint choice retains socket geometry")
local bag = B.State(CharacterBag0Slot)
B.SetOccupied(CharacterBag0Slot, false)
eq(bag.socketRim:GetAlpha(), 0, "keepEmpty family does not become a frosted socket")
eq(next(GAB.failures), nil, "no recorded skin failures")

-- Existing materials keep the original colour offsets and no new face.
for _, material in ipairs({ "clean", "classic" }) do
    dofile("tests/wow_stubs.lua")
    GAB = loadAddon({ db = { material = material } })
    B = GAB.Buttons
    local old = B.State(ActionButton1)
    eq(old.gloss, nil, material .. ": no Pearl face")
    eq(B.Tune("rim"), 0.85, material .. ": old rim")
    eq(B.Tune("frostAlpha"), 0.08, material .. ": old fill")
    local frost = B.Frost()
    check(close(frost[1], 0.9) and close(frost[2], 0.91) and close(frost[3], 0.94), material .. ": old tint")
end

-- The reflection's shape (Media/ButtonGloss, Tools/make_rim.py): a soft
-- highlight under the top edge, strongest in the middle, fading smoothly. Not
-- the rejected band (an even cap down to 30% with a sharp edge: a grey slab on
-- dark icons, owner 2026-10-19), nor a haze across the whole width.
local f = io.open("Media/ButtonGloss.tga", "rb")
local tga = f and f:read("*a")
if f then f:close() end
check(tga ~= nil, "ButtonGloss ships")
if tga then
    local n = tga:byte(13) + 256 * tga:byte(14)
    local function alpha(row, col)   -- 0..1 at pixel row (0 top) and col, of the bottom-up BGRA rows
        return tga:byte(18 + ((n - 1 - row) * n + col) * 4 + 4) / 255
    end
    local mid, strong, steepest, lowest = math.floor(n / 2), 0, 0, 0
    for row = 0, n - 1 do
        for col = 0, n - 1 do
            local a = alpha(row, col)
            if a > 0.5 then strong = strong + 1 end
            if a > 0 then lowest = row end
        end
        if row > 0 then steepest = math.max(steepest, math.abs(alpha(row, mid) - alpha(row - 1, mid))) end
    end
    check(alpha(2, mid) > 0.8, "  strongest under the top edge, in the middle")
    check(strong / (n * n) < 0.12, "  near-white over a small area only (no cap)")
    check(steepest < 0.15, "  a smooth fade, no horizontal edge")
    check(lowest < n * 0.35, "  gone well before the middle")
    check(alpha(math.floor(n * 0.15), math.floor(n * 0.15)) < alpha(math.floor(n * 0.15), mid) / 2,
        "  tapering to the sides along an arc (a curved face)")
end

done("test_pearl")
