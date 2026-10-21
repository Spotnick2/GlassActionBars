-- Other addons' buttons on the Utility bar (#52, RegisterButton): off until
-- the player ticks them; an insecure button made the first time one shows,
-- skinned; its click refused while IsEnabled() is false; hotkey, tooltip and
-- dimming; OnHosted once with false, then on each change, never in combat;
-- the saved key of an addon not registered this session kept, unseen.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

WoW.layoutBar(MainActionBar, 500, 100)
WoW.known[3413] = true
WoW.items[6948] = 1
WoW.bindings.PORTALROULETTE_TOGGLE = "CTRL-P"

local hosted, clicks = {}, {}
local enabled, enabledThrows, clickThrows, tipThrows = true, false, false, false
local function hostLog(id) hosted[id] = {}; return function(on) table.insert(hosted[id], on) end end
local roulette = { id = "roulette", label = "Portal Roulette", icon = "Interface\\AddOns\\PortalRoulette\\Media\\Portal",
    binding = "PORTALROULETTE_TOGGLE",
    OnClick = function(b, mouseButton)
        if clickThrows then error("roulette click broke") end
        clicks[#clicks + 1] = { b, mouseButton }
    end,
    tooltip = function(tt)
        if tipThrows then error("roulette tooltip broke") end
        tt:AddLine("Portal Roulette: open the wheel")
    end,
    IsEnabled = function()
        if enabledThrows then error("roulette IsEnabled broke") end
        return enabled
    end,
    OnHosted = hostLog("roulette") }
local mini = { id = "mini", icon = 134400, OnClick = function() end }   -- the required fields only

local GAB = loadAddon({
    db = { utility = { order = { "hearthstone", "provider:ghost", "cooking" }, show = { ["provider:ghost"] = true } } },
    beforeLogin = function(G)
        check(G.RegisterButton(roulette), "Portal Roulette registers before login")
        check(G.RegisterButton(mini), "a minimal provider registers")
    end })
local U, Settings, T = GAB.Utility, GAB.Settings, GAB.Utility._test
WoW.tick()
local function shownKeys()
    local out = {}
    for _, b in ipairs(T.shown()) do out[#out + 1] = T.state[b].key end
    return table.concat(out, ",")
end
local function seq(t)
    local out = {}
    for i, v in ipairs(t) do out[i] = tostring(v) end
    return table.concat(out, ",")
end
local function first(n)
    local o = U.Order()
    return table.concat(o, ",", 1, n)
end

-- Off by default: no button, OnHosted(false) once.
eq(shownKeys(), "hearthstone,cooking", "off by default: only the built-in entries")
eq(U.buttons["provider:roulette"], nil, "  no button made yet")
eq(seq(hosted.roulette), "false", "  OnHosted(false) once after it registered")
local o = U.Order()
eq(o[#o - 1] .. "," .. o[#o], "provider:roulette,provider:mini", "Order(): registered providers appended, in order")
eq(first(3), "hearthstone,provider:ghost,cooking", "  an unregistered saved key kept in its place")
check(U.Registered("provider:roulette") and not U.Registered("provider:ghost"), "  registered vs not")
eq(U.Label("provider:roulette"), "Portal Roulette", "  its label")
eq(U.Label("provider:mini"), "mini", "  the id when it has none")

-- Ticked: built, skinned, shown, hosted.
check(Settings.SetUtilityShown("provider:roulette", true), "tick Portal Roulette")
eq(GAB.db.utility.show["provider:roulette"], true, "  saved as true (off is the default)")
local b = U.buttons["provider:roulette"]
check(b ~= nil and b == _G.GlassActionBarsUtilProvider_roulette, "  its button made, named")
check(b:GetParent() == U.frame, "  on the Utility bar")
eq(b:GetAttribute("type"), nil, "  insecure: no action attributes")
check(GAB.Buttons.IsSkinned(b), "  skinned")
local r = GAB.Buttons.State(b).regions
eq(r.icon._file, roulette.icon, "  its icon")
check(r.icon._masks and #r.icon._masks == 1, "  rounded to the glass")
eq(r.cooldown, nil, "  no cooldown")
eq(shownKeys(), "hearthstone,cooking,provider:roulette", "  shown at its place in the order")
eq(seq(hosted.roulette), "false,true", "  OnHosted(true) once")
eq(r.hotkey:GetText(), "cP", "  its binding's key, short")
U.Reconcile()
eq(#hosted.roulette, 2, "  a rebuild with no change: nothing sent")

-- The minimal provider: no binding, no tooltip, no IsEnabled, no OnHosted.
check(Settings.SetUtilityShown("provider:mini", true), "tick the minimal provider")
local m = U.buttons["provider:mini"]
check(m and m:IsShown(), "  shown")
eq(GAB.Buttons.State(m).regions.hotkey:GetText(), "", "  no binding: no key text")
eq(shownKeys(), "hearthstone,cooking,provider:roulette,provider:mini", "  beside the other one")
eq(next(GAB.failures), nil, "  nothing failed")

-- Clicks: asked IsEnabled each time; errors kept in the provider.
b:GetScript("OnClick")(b, "LeftButton")
eq(#clicks, 1, "a click: OnClick called")
check(clicks[1][1] == b and clicks[1][2] == "LeftButton", "  with the button and the mouse button")
enabled = false
b:GetScript("OnClick")(b, "LeftButton")
eq(#clicks, 1, "IsEnabled() false: refused")
enabled, enabledThrows = true, true
local errs = #WoW.errors
b:GetScript("OnClick")(b, "LeftButton")
eq(#clicks, 1, "IsEnabled() erroring: refused")
eq(#WoW.errors, errs + 1, "  to the error handler")
check(GAB.failures["utility:provider:roulette"] ~= nil, "  and /gab failures")
enabledThrows, clickThrows = false, true
b:GetScript("OnClick")(b, "RightButton")
eq(#WoW.errors, errs + 2, "OnClick erroring: to the error handler, not into the bar")
clickThrows = false
m:GetScript("OnClick")(m, "LeftButton")
eq(#WoW.errors, errs + 2, "  a minimal provider's click: no IsEnabled needed")
GAB.failures = {}

-- The tooltip: the provider fills it, owned and shown by us.
b:GetScript("OnEnter")(b)
check(GameTooltip:IsOwned(b), "hover: the tooltip on the button")
eq(GameTooltip._lines[1], "Portal Roulette: open the wheel", "  filled by the provider")
check(GameTooltip:IsShown(), "  shown")
b:GetScript("OnLeave")(b)
check(not GameTooltip:IsShown(), "  hidden on leave")
tipThrows = true
b:GetScript("OnEnter")(b)
check(GameTooltip:IsShown(), "a tooltip function erroring: still shown, nothing broke")
tipThrows = false
GameTooltip:Hide()
GameTooltip:SetOwner(UIParent)
m:GetScript("OnEnter")(m)
check(not GameTooltip:IsOwned(m), "no tooltip: none shown")
GAB.failures = {}

-- Dimming follows IsEnabled, a frame after combat starts or ends.
enabled = false
WoW.fire("PLAYER_REGEN_DISABLED")
check(not r.icon._desaturated, "combat starting: not dimmed inside the event")
WoW.flushTimers()
check(r.icon._desaturated, "  a frame later: desaturated")
eq(r.icon:GetAlpha(), U.DIM, "  and faded")
enabled = true
WoW.fire("PLAYER_REGEN_ENABLED")
WoW.flushTimers()
check(not r.icon._desaturated, "the fight over: back")
eq(r.icon:GetAlpha(), 1, "  full alpha")

-- Moving: the unseen key keeps its slot.
check(Settings.MoveUtility("cooking", -1), "Cooking up")
eq(first(3), "cooking,provider:ghost,hearthstone", "  past the unregistered key: it stays put")
check(Settings.MoveUtility("provider:roulette", -1), "Portal Roulette up")
local order = U.Order()
local ir, im
for i, k in ipairs(order) do if k == "provider:roulette" then ir = i elseif k == "camping" then im = i end end
eq(ir, im - 1, "  just above the entry before it")
check(not U.Registered("provider:ghost") and GAB.db.utility.order[2] == "provider:ghost", "  the unseen key saved in place")

-- The options page: a row per registered entry, none for the unseen key.
GAB.Options.utilityPage:Show()
local rows = GAB.Options._test.utilityRows
check(rows["provider:roulette"] ~= nil, "the page: a row for Portal Roulette")
eq(rows["provider:ghost"], nil, "  none for the unregistered key")
local content = rows.cooking.frame:GetParent()
eq(content:GetHeight(), (#U.ORDER_KEYS + 2) * GAB.Options.UTILITY_ROW + 16, "  the scroll height counts the rows shown")
local function y(key) return rows[key].frame._points[#rows[key].frame._points][5] end
eq(y("cooking"), 0, "  Cooking first, no gap")
eq(y("hearthstone"), -GAB.Options.UTILITY_ROW, "  Hearthstone next: no gap for the unseen key")
check(rows["provider:roulette"].check:GetChecked(), "  Portal Roulette ticked")
rows["provider:roulette"].check:SetChecked(false)
rows["provider:roulette"].check:GetScript("OnClick")(rows["provider:roulette"].check)
eq(U.IsShown("provider:roulette"), false, "  unticked: off")
eq(GAB.db.utility.show["provider:roulette"], nil, "  nothing stored")
check(not b:IsShown(), "  its button hidden")
eq(seq(hosted.roulette), "false,true,false", "  OnHosted(false)")
Settings.SetUtilityShown("provider:roulette", true)
eq(#hosted.roulette, 4, "ticked again: OnHosted(true)")

-- The bar turned off: hosted false; providers registering while it's off
-- hear false once, one erroring OnHosted not stopping the next.
Settings.SetUtilityEnabled(false)
eq(hosted.roulette[5], false, "the bar off: OnHosted(false)")
local badHosted = { id = "bad", icon = 1, OnClick = function() end, OnHosted = function() error("bad OnHosted") end }
local late = { id = "late", icon = 2, OnClick = function() end, OnHosted = hostLog("late") }
check(GAB.RegisterButton(badHosted) and GAB.RegisterButton(late), "two providers register late")
check(rows["provider:late"] ~= nil and rows["provider:late"].frame:IsShown(), "  the open options page lists it at once")
check(not rows["provider:late"].check:GetChecked(), "  unticked")
eq(content:GetHeight(), (#U.ORDER_KEYS + 4) * GAB.Options.UTILITY_ROW + 16, "  the scroll height grows with it")
WoW.tick()
eq(seq(hosted.late), "false", "  the bar off: OnHosted(false) once")
check(GAB.failures["utility:provider:bad"] ~= nil, "  the erroring one recorded")
Settings.SetUtilityEnabled(true)
eq(seq(hosted.late), "false", "the bar on again: still off by default, nothing new")
eq(hosted.roulette[6], true, "  Portal Roulette back on the bar")
GAB.failures = {}

-- Combat: nothing changes until the fight ends.
for _, btn in pairs(U.buttons) do if not T.state[btn].provider then btn._protected = true end end
U.frame._protected = true
WoW.combat = true
Settings.SetUtilityShown("provider:late", true)
check(U.IsPending(), "ticked in combat: the rebuild waits")
eq(U.buttons["provider:late"], nil, "  no button yet")
eq(#hosted.late, 1, "  no OnHosted in combat")
WoW.combat = false
WoW.fire("PLAYER_REGEN_ENABLED")
check(U.buttons["provider:late"] and U.buttons["provider:late"]:IsShown(), "the fight over: built and shown")
eq(seq(hosted.late), "false,true", "  OnHosted(true) then")
eq(#WoW.violations, 0, "no protected change in combat")
eq(next(GAB.failures), nil, "nothing failed")

done("test_utility_provider")
