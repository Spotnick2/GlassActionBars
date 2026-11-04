-- Every widget method the addon calls must exist on this client, on that
-- widget type: the stub answers any method (a no-op for one it doesn't
-- implement), so a call Forever lacks would otherwise pass silently. The
-- addon is exercised as widely as is cheap, then WowTestKit's
-- Kit.checkMethods checks each recorded "Type:Method" against the pinned
-- build's widget methods.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local GAB = loadAddon()
-- Every event, then a few seconds of frames and timers.
WoW.fireAllRegistered()
for _ = 1, 5 do WoW.tick(); WoW.advance(1) end

-- Every frame under f, depth first.
local function walk(f, fn)
    fn(f)
    for _, c in ipairs(f._children or {}) do walk(c, fn) end
end
-- Hover and click everything clickable on a page: tooltips, checkboxes,
-- radios, the Utility bar's up/down buttons.
local function poke(frame)
    walk(frame, function(w)
        local s = w._scripts
        if s.OnEnter then s.OnEnter(w) end
        if s.OnLeave then s.OnLeave(w) end
        if s.OnClick and (w._type == "Button" or w._type == "CheckButton") and not w._protected then
            s.OnClick(w, "LeftButton", false)
        end
    end)
end

-- The options: the main page and every sub-page (Bar fade, Buttons, Dock, Utility bar).
local O = GAB.Options
O._test.panel:Show()
poke(O._test.panel)
for _, page in ipairs(O._test.pages) do
    local f = page.frame or page
    if f.Show then f:Show() end
    poke(f)
end
WoW.tick()

-- Every slash command.
for _, cmd in ipairs({ "", "failures", "version", "options", "inspect", "inspect hide 1", "inspect restore",
                        "layer rim off", "layer rim on", "tune", "tune rim 0.5", "tune reset", "theme smoked",
                        "theme class", "theme clear", "material", "micro pill", "micro tiles", "gryphons on",
                        "gryphons off", "hotkeys off", "hotkeys on", "macros off", "macros on", "fade",
                        "fade 2 mouseover", "fade 2 off", "dock", "dock utility off", "dock utility 1",
                        "utility off", "utility on", "look", "look soft", "look glass", "follow" }) do
    SlashCmdList.GLASSACTIONBARS(cmd)
    WoW.tick()
end

-- No allow list: every method GAB calls is in the dump's widget walk.
local recorded = Kit.checkMethods()
-- The floor: what the exercise records today (125), rounded down, so it can't quietly shrink.
check(recorded >= 120, "the exercise reached the options pages and commands (" .. recorded .. " recorded)")
done("test_methods")
