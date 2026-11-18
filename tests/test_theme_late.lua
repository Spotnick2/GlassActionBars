-- The class theme with the class colour not readable at login: the buttons
-- are painted as built, then in the class colour once PLAYER_ENTERING_WORLD
-- comes with it readable (Theme.Retry). The buttons are LibGlass's skins and
-- register no Theme surface, so the retry can't rest on Theme.pending alone (#105).
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local function close(a, b) return type(a) == "number" and type(b) == "number" and math.abs(a - b) < 1e-6 end

WoW.playerClass = nil                      -- UnitClass has no class yet
WoW.actions[1] = true                      -- a filled slot (an empty frosted one shows its own fill)
local GAB = loadAddon({ db = { look = { theme = "class" } } })
local s = GAB.Buttons.State(ActionButton1)
check(s ~= nil, "skinned")
local built = s.g.tint.glassColor or GAB.Glass.STYLE.tint
check(close(s.g.tint._color[1], built[1]), "class colour unreadable: the glass as built")
-- The known difference from GAB's own builder (accepted on LibGlass#46): an
-- empty frosted slot shows the frost fill meanwhile (GAB's showed the glass
-- as built), since LibGlass takes "no tint" for clear glass.
local e = GAB.Buttons.State(ActionButton2)
local frost = PARITY.frost(GAB)
check(close(e.g.tint._color[1], frost[1]) and close(e.g.tint._color[4], frost[4]), "  an empty frosted slot meanwhile: the frost fill")

-- No other surface waiting (the micro menu's pill set pending at its own paint):
-- the buttons alone must bring the retry.
GAB.Theme.pending = false
WoW.playerClass = "WARLOCK"
WoW.fire("PLAYER_ENTERING_WORLD", false, true)
check(close(s.g.tint._color[1], 0.53 * 0.6), "PLAYER_ENTERING_WORLD with it readable: the class colour, shaded")
eq(next(GAB.failures), nil, "nothing failed")

done("test_theme_late")
