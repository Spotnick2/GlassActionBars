-- Bar fade (#10): a fading bar at the faded alpha until a reason shows it
-- (pointer, page arrows, flyout, drag grids, Edit Mode, Quick Keybind, the
-- spellbook, a fight in "combat" mode); the timing contract (reveal snaps,
-- fade-out after DELAY over OUT); SetAlpha on the bar only, never on a bar
-- set to "off"; the settings, /gab fade and the Bar fade sub-page.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local function close(a, b) return type(a) == "number" and type(b) == "number" and math.abs(a - b) < 1e-6 end

local BL, BR, MAIN = MultiBarBottomLeft, MultiBarBottomRight, MainActionBar
local BARS = { MAIN, BL, BR, MultiBarRight, MultiBarLeft, MultiBar5, MultiBar6, MultiBar7, StanceBar, PetActionBar }

-- SetAlpha calls per bar.
local writes = {}
local function count(bar) return writes[bar] or 0 end
for _, bar in ipairs(BARS) do
    rawset(bar, "SetAlpha", function(self, a)
        writes[self] = (writes[self] or 0) + 1
        self._alpha = a
    end)
end
local function fields(w)
    local t = {}
    for k, v in pairs(w) do if not (type(k) == "string" and k:sub(1, 1) == "_") then t[k] = v end end
    return t
end
local before = {}
for _, bar in ipairs(BARS) do before[bar] = fields(bar) end

-- Run `seconds` of frames of `dt` each.
local function run(seconds, dt)
    dt = dt or 0.01
    for _ = 1, math.floor(seconds / dt + 0.5) do WoW.tick(dt) end
end

-- A reveal is detected within one poll; the poll's phase is arbitrary, so
-- allow a full poll and a frame.
local function poll() run(0.12) end

local GAB = loadAddon()
local Fade, Settings = GAB.Fade, GAB.Settings
eq(next(GAB.failures), nil, "nothing failed")

-- Nothing fades by default: no bar written, the driver idle.
run(1)
for _, bar in ipairs(BARS) do eq(count(bar), 0, "no fade set: " .. bar:GetName() .. " never written") end
eq(Fade._test.driver():GetScript("OnUpdate"), nil, "  the driver idle")

-- Mouseover: fades DELAY after the first poll that found no reason, over OUT.
check(Settings.SetFade("MultiBarBottomLeft", "mouseover"), "SetFade mouseover")
check(Fade._test.driver():GetScript("OnUpdate") ~= nil, "  the driver runs")
WoW.tick(0.01)                                 -- the poll: no reason, the clock starts
run(Fade.DELAY - 0.02)
check(BL._alpha == nil or BL._alpha == 1, "  still opaque just before DELAY")
run(0.01 + Fade.OUT / 2)
check(BL._alpha > 0.3 and BL._alpha < 0.7, "  halfway through the fade-out (" .. tostring(BL._alpha) .. ")")
run(Fade.OUT)
eq(BL._alpha, 0, "  faded to fadeAlpha 0")
eq(count(BR), 0, "  another bar untouched")
for _, b in ipairs({ "ActionButton1", "MultiBarBottomLeftButton1" }) do
    eq(_G[b]._alpha, nil, "  no SetAlpha on button " .. b)
end

-- The pointer: a reveal snaps to 1 within one poll.
WoW.hover[BL] = true
poll()
eq(BL._alpha, 1, "hovered: snaps to 1 within a poll")
WoW.hover[BL] = nil
run(Fade.DELAY - 0.02)
eq(BL._alpha, 1, "  left: still 1 until DELAY has passed")
run(Fade.POLL + 0.05)   -- the fade began 0.03-0.14 s ago (of OUT = 0.2)
check(BL._alpha < 1 and BL._alpha > 0, "  then fading (" .. tostring(BL._alpha) .. ")")
WoW.hover[BL] = true                           -- back mid-fade
poll()
eq(BL._alpha, 1, "  back mid-fade: snaps to 1")
WoW.hover[BL] = nil
poll()
WoW.tick(5)                                    -- one long frame
eq(BL._alpha, 0, "a long frame lands on fadeAlpha, not past it")

-- A secret IsMouseOver counts as over: the bar stays opaque.
WoW.hover[BL] = WoW.Secret("IsMouseOver")
poll()
eq(BL._alpha, 1, "a secret hover keeps the bar opaque")
WoW.hover[BL] = nil
run(1)
eq(BL._alpha, 0, "  and it fades once the hover is plain")

-- The main bar's page arrows sit outside its rectangle.
Settings.SetFade("MainActionBar", "mouseover")
run(1)
eq(MAIN._alpha, 0, "main bar faded")
WoW.hover[MAIN.ActionBarPageNumber] = true
poll()
eq(MAIN._alpha, 1, "  the page arrows hovered: shown")
WoW.hover[MAIN.ActionBarPageNumber] = nil
run(1)

-- A flyout open from one of the bar's buttons keeps that bar shown, not another.
Settings.SetFade("MultiBarBottomRight", "mouseover")
run(1)
SpellFlyout:SetParent(MultiBarBottomLeftButton3)
SpellFlyout:Show()
poll()
eq(BL._alpha, 1, "flyout from a bottom-left button: bottom-left shown")
eq(BR._alpha, 0, "  bottom-right stays faded")
SpellFlyout:Hide()
run(1)
eq(BL._alpha, 0, "  closed: faded again")

-- Drag grids: either family shows every fading bar until both have ended.
WoW.fire("ACTIONBAR_SHOWGRID")
poll()
check(BL._alpha == 1 and BR._alpha == 1 and MAIN._alpha == 1, "ACTIONBAR_SHOWGRID shows every fading bar")
WoW.fire("PET_BAR_SHOWGRID")
WoW.fire("ACTIONBAR_HIDEGRID")
run(1)
eq(BL._alpha, 1, "  the pet grid still up: still shown")
WoW.fire("PET_BAR_HIDEGRID")
run(1)
eq(BL._alpha, 0, "  both grids down: faded")

-- Edit Mode, Quick Keybind mode, the spellbook and professions book.
WoW.trigger("EditMode.Enter")
poll()
eq(BL._alpha, 1, "Edit Mode open: shown")
WoW.quickKeybind = true
WoW.trigger("EditMode.Exit")
run(1)
eq(BL._alpha, 1, "  Edit Mode closed, Quick Keybind still on: shown")
WoW.quickKeybind = false
run(1)
eq(BL._alpha, 0, "  both off: faded")
local book = CreateFrame("Frame", "PlayerSpellsFrame", UIParent)   -- loads on demand
poll()
eq(BL._alpha, 1, "the spellbook open: shown, no drag needed")
local prof = CreateFrame("Frame", "ProfessionsBookFrame", UIParent)
book:Hide()
run(1)
eq(BL._alpha, 1, "  spellbook closed, professions book open: shown")
prof:Hide()
run(1)
eq(BL._alpha, 0, "  both closed: faded")

-- An unreadable IsShown / IsVisible (SecretReturnsForAspect Shown) counts as
-- shown, and nothing truth-tests the secret itself.
WoW.secretShown[book] = true
poll()
eq(BL._alpha, 1, "a secret IsShown on the spellbook counts as open")
WoW.secretShown[book] = nil
run(1)
eq(BL._alpha, 0, "  plain again: faded")
SpellFlyout:SetParent(MultiBarBottomLeftButton3)
WoW.secretShown[SpellFlyout] = true
poll()
eq(BL._alpha, 1, "a secret IsShown on the flyout counts as open")
WoW.secretShown[SpellFlyout] = nil
run(1)
WoW.secretShown[BL] = true
WoW.hover[BL] = true
poll()
eq(BL._alpha, 1, "a secret IsVisible still lets the pointer show the bar")
WoW.hover[BL] = nil
run(1)
eq(BL._alpha, 0, "  and fade it")
WoW.secretShown[BL] = nil

-- "combat": opaque in a fight, faded out of one unless hovered.
Settings.SetFade("MultiBarBottomRight", "combat")
run(1)
eq(BR._alpha, 0, "combat mode, out of combat: faded")
WoW.hover[BR] = true
poll()
eq(BR._alpha, 1, "  hovered out of combat: shown")
WoW.hover[BR] = nil
run(1)
WoW.combat = true
WoW.fire("PLAYER_REGEN_DISABLED")
poll()
eq(BR._alpha, 1, "  in combat: shown")
eq(BL._alpha, 0, "  a mouseover bar stays faded in combat")
run(2)
eq(BR._alpha, 1, "  for the whole fight")
WoW.combat = false
WoW.fire("PLAYER_REGEN_ENABLED")
run(1)
eq(BR._alpha, 0, "  the fight over: faded")

-- The faded alpha, live.
check(Settings.SetFadeAlpha(0.25), "SetFadeAlpha 0.25")
poll()
check(close(BL._alpha, 0.25) and close(BR._alpha, 0.25), "  faded bars go to 0.25")
eq(GlassActionBarsDB.fadeAlpha, 0.25, "  saved")
eq(Settings.SetFadeAlpha(2), false, "  out of range refused")

-- Off: one SetAlpha(1), then never again; the driver stops with the last bar.
local n = count(BL)
Settings.SetFade("MultiBarBottomLeft", "off")
eq(count(BL), n + 1, "off: one write")
eq(BL._alpha, 1, "  of 1")
WoW.hover[BL] = true
run(1)
WoW.hover[BL] = nil
run(1)
eq(count(BL), n + 1, "  and never again")
Settings.SetFade("MultiBarBottomRight", "off")
Settings.SetFade("MainActionBar", "off")
eq(Fade._test.driver():GetScript("OnUpdate"), nil, "no bar fades: the driver idle")
eq(GlassActionBarsDB.fade, nil, "  nothing fading saved")
eq(Settings.SetFade("Minimap", "mouseover"), false, "an unknown bar refused")
eq(Settings.SetFade("MultiBarBottomLeft", "sometimes"), false, "an unknown mode refused")

-- No field written on any bar but the test's own spy.
for _, bar in ipairs(BARS) do
    local after = fields(bar)
    for k in pairs(after) do
        check(before[bar][k] ~= nil, bar:GetName() .. ": no new field " .. tostring(k))
    end
end

-- /gab fade.
newChat()
SlashCmdList.GLASSACTIONBARS("fade 2 mouseover")
eq(Fade.Mode("MultiBarBottomLeft"), "mouseover", "/gab fade 2 mouseover")
SlashCmdList.GLASSACTIONBARS("fade pet combat")
eq(Fade.Mode("PetActionBar"), "combat", "/gab fade pet combat")
SlashCmdList.GLASSACTIONBARS("fade alpha 0.5")
eq(GAB.db.fadeAlpha, 0.5, "/gab fade alpha 0.5")
SlashCmdList.GLASSACTIONBARS("fade 9 mouseover")
check(chatHas("/gab fade <1%-8|stance|pet|all>"), "a bad bar: the usage line")
SlashCmdList.GLASSACTIONBARS("fade all off")
for _, b in ipairs(Fade.BARS) do eq(Fade.Mode(b[1]), "off", "/gab fade all off: " .. b[1]) end
newChat()
SlashCmdList.GLASSACTIONBARS("fade")
eq(#newChat(), #Fade.BARS + 1, "/gab fade lists every bar and the alpha")

-- The sub-page, opened directly after a /gab change, shows the new values.
SlashCmdList.GLASSACTIONBARS("fade 3 combat")
SlashCmdList.GLASSACTIONBARS("fade alpha 0.25")
GAB.Options.fadePage:Show()
local row = GAB.Options._test.fadeRows.MultiBarBottomRight
check(row and row[3]:GetChecked() and not row[1]:GetChecked(), "sub-page: bar 3 shows Fade out of combat")
check(GAB.Options._test.fadeAlpha[2]:GetChecked(), "  the alpha shows Faint")
GAB.Options.fadePage:Hide()
SlashCmdList.GLASSACTIONBARS("fade 3 off")
GAB.Options.fadePage:Show()
check(row[1]:GetChecked() and not row[3]:GetChecked(), "  shown again after a change: No fade")
row[2]:GetScript("OnClick")(row[2])
eq(Fade.Mode("MultiBarBottomRight"), "mouseover", "  a click sets the mode")

-- Saved settings are cleaned at load.
local db = GAB._test.ensureDefaults
GlassActionBarsDB = { fade = { MultiBarBottomLeft = "mouseover", Minimap = "mouseover", MultiBar5 = "off",
    MultiBar6 = "always" }, fadeAlpha = 7 }
local clean = db()
eq(rawget(clean, "fade").MultiBarBottomLeft, "mouseover", "load: a known bar and mode kept")
eq(rawget(clean, "fade").Minimap, nil, "  an unknown bar dropped")
eq(rawget(clean, "fade").MultiBar5, nil, "  off dropped (it is the absence)")
eq(rawget(clean, "fade").MultiBar6, nil, "  an unknown mode dropped")
eq(rawget(clean, "fadeAlpha"), nil, "  an out-of-range alpha dropped")
GlassActionBarsDB = { fade = "yes" }
eq(rawget(db(), "fade"), nil, "  a fade that isn't a table dropped")

done("test_fade")
