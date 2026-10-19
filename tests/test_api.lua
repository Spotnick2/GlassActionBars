-- The public provider API (#8, docs/PUBLIC-API.md): the version, RegisterBar
-- through the dock (validation, snapshots, the hosting order, Layout(nil),
-- contents changing), RequestLayout, SkinButton (roles, snapshots, combat),
-- RegisterButton (stored for the Utility bar), errors kept in the provider.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local function close(a, b) return type(a) == "number" and type(b) == "number" and math.abs(a - b) < 1e-6 end
local function fields(w)
    local t = {}
    for k, v in pairs(w) do if not (type(k) == "string" and k:sub(1, 1) == "_") then t[k] = v end end
    return t
end

WoW.layoutBar(MainActionBar, 500, 100)          -- bar 1: 500..1062 x 55..100

-- A provider bar: its frame, a log, and a def; registered from its own files,
-- before Glass Action Bars has logged in.
local function provider(id, extra)
    local f = CreateFrame("Frame", "Prov_" .. id, UIParent)
    f._protected = true
    f._width, f._height = 60, 30
    local log = {}
    local def = {
        id = id, label = "Provider " .. id, frame = f,
        OnHosted = function(on) log[#log + 1] = on and "hosted" or "released" end,
        Layout = function(g)
            log[#log + 1] = g and "layout" or "layout(nil)"
            log.geom = g
        end,
    }
    for k, v in pairs(extra or {}) do def[k] = v end
    return f, log, def
end

local early, earlyLog, earlyDef = provider("early", { default = { bar = 1, side = "UP", gap = 6, matchRows = false } })
local GAB = loadAddon({ beforeLogin = function(G)
    check(G.RegisterBar(earlyDef), "RegisterBar before login: accepted")
end })
eq(GAB.PUBLIC_API_VERSION, 2, "PUBLIC_API_VERSION 2 (#48: geom carries what the player matches)")
eq(next(GAB.failures), nil, "nothing failed")

-- The early provider: docked by its default once logged in; the bad default
-- key dropped, the good ones kept.
WoW.tick()
eq(earlyLog[1], "hosted", "queued before login: hosted after it")
eq(earlyLog[2], "layout", "  then laid out")
eq(GAB.Dock.Setting("early", "side"), "RIGHT", "  an invalid default side dropped")
eq(GAB.Dock.Setting("early", "gap"), 6, "  a valid default gap kept")
eq(GAB.Dock.Setting("early", "matchRows"), false, "  a default matchRows kept (#48)")
check(earlyLog.geom and earlyLog.geom.size and earlyLog.geom.rows == nil, "  so Layout gets the size, not the rows")
local p = early._points[#early._points]
check(p and close(p[4], 1062 + 6), "  placed right of bar 1, 6 apart")

-- Snapshots: the provider's tables changing later changes nothing.
earlyDef.default.bar = 5
earlyDef.default.gap = 20
eq(GAB.Dock.Setting("early", "gap"), 6, "the default copied: the provider changing it changes nothing")
earlyDef.OnHosted = function() error("not this one") end
GAB.Settings.SetDock("early", "bar", false)
WoW.tick()
eq(earlyLog[#earlyLog], "released", "the registered OnHosted is the one called")
eq(next(GAB.failures), nil, "  the replaced one never runs")
GAB.Settings.SetDock("early", "bar", 1)
WoW.tick()

-- Validation: refused with a reason, nothing registered.
local function refused(def, what)
    local ok, why = GAB.RegisterBar(def)
    check(ok == false and type(why) == "string", what .. ": refused (" .. tostring(why) .. ")")
end
local _, _, d = provider("x")
refused("bar", "not a table")
refused({ id = "has space", frame = d.frame, OnHosted = d.OnHosted }, "a bad id")
refused({ id = "utility", frame = d.frame, OnHosted = d.OnHosted }, "the reserved id")
refused({ id = "early", frame = d.frame, OnHosted = d.OnHosted }, "a duplicate id")
refused({ id = "tex", frame = d.frame:CreateTexture(), OnHosted = d.OnHosted }, "a Texture as the frame")
refused({ id = "noframe", OnHosted = d.OnHosted }, "no frame")
refused({ id = "nohost", frame = d.frame }, "no OnHosted")
refused({ id = "badlayout", frame = d.frame, OnHosted = d.OnHosted, Layout = "yes" }, "Layout not a function")
refused({ id = "badlabel", label = 3, frame = d.frame, OnHosted = d.OnHosted }, "a label that isn't a string")
for _, cl in ipairs(GAB.Dock.Clients()) do check(cl.id ~= "tex" and cl.id ~= "nohost", "  none registered") end

-- A valid provider after the refused ones; not docked by default.
local own, ownLog, ownDef = provider("own")
check(GAB.RegisterBar(ownDef), "a valid provider after refused ones")
WoW.tick()
eq(#ownLog, 0, "  not docked by default: no callback")

-- Match off: Layout(nil); its contents change, it relays out and asks again.
GAB.Settings.SetDock("own", "bar", 1)
GAB.Settings.SetDock("own", "side", "LEFT")
GAB.Settings.SetDock("own", "match", false)
GAB.Settings.SetDock("own", "matchRows", false)
WoW.tick()
eq(ownLog[1], "hosted", "docked: hosted")
eq(ownLog[2], "layout(nil)", "  nothing matched: Layout(nil)")
p = own._points[#own._points]
check(close(p[4], 500 - 4 - 60), "  left of bar 1 by its own width")
own._width = 90                                 -- a button appeared
GAB.RequestLayout("own")
WoW.tick()
p = own._points[#own._points]
check(close(p[4], 500 - 4 - 90), "contents changed + RequestLayout: re-placed by the new width")
GAB.Settings.SetDock("own", "match", true)
GAB.Settings.SetDock("own", "matchRows", true)
WoW.tick()
eq(ownLog[#ownLog], "layout", "match on again: the bar's geometry")
check(close(ownLog.geom.size, 45), "  45 at 100%")
GAB.RequestLayout("no such bar")
GAB.RequestLayout(7)
WoW.tick()

-- A provider's error stays its own.
local _, _, badDef = provider("bad", { default = { bar = 1 }, OnHosted = function() error("provider bug") end })
check(GAB.RegisterBar(badDef), "a provider whose OnHosted throws: registered")
WoW.tick()
check(GAB.failures["dock:bad"] ~= nil, "  its error recorded in /gab failures")
check(GAB.Dock.IsHosted("own"), "  the others unaffected")

-- SkinButton.
local btn = CreateFrame("Button", "ProvButton1", own)
btn._protected = true
local regions = { icon = btn:CreateTexture(), hotkey = btn:CreateFontString(), cooldown = CreateFrame("Cooldown", nil, btn),
    pushed = btn:CreateTexture(), extra = btn:CreateTexture() }
local beforeFields = fields(btn)
local ok, why = GAB.SkinButton(own, regions)
check(ok == false and why:find("Button"), "SkinButton on a Frame: refused")
ok, why = GAB.SkinButton(btn, { hotkey = CreateFrame("Frame", nil, btn) })
check(ok == false and why:find("hotkey"), "a Frame as hotkey: refused, saying which")
check(not GAB.Buttons.IsSkinned(btn), "  nothing built")
ok, why = GAB.SkinButton(btn, { pushed = btn:CreateFontString() })
check(ok == false and why:find("pushed"), "a FontString as pushed: refused")
check(GAB.SkinButton(btn, regions), "valid regions: skinned")
local s = GAB.Buttons.State(btn)
eq(s.regions.extra, nil, "  an unknown key dropped")
eq(s.regions.icon, regions.icon, "  the icon kept")
check(s.regions ~= regions, "  a copy of the region map, not the provider's table")
check(GAB.SkinButton(btn, regions), "  a second call: true")
-- The icon rounded to the glass (#46): one mask, on the provider's own frame, over the icon.
local masks = regions.icon._masks
eq(masks and #masks, 1, "  the icon masked, once")
local m = masks and masks[1]
check(m and m:GetParent() == btn, "  the mask on the icon's own frame")
check(m and tostring(m._file):find("ButtonMask") ~= nil, "  the rim's rounded square")
check(m and m._points[1] and m._points[1][1] == "ALL" and m._points[1][2] == regions.icon, "  over the icon")
GAB.SkinButton(btn, regions)
eq(#regions.icon._masks, 1, "  a repeat call adds none")
-- An icon on a provider's child frame, with a mask of its own: ours made on
-- that child, theirs kept.
local btn3 = CreateFrame("Button", "ProvButton3", own)
local holder = CreateFrame("Frame", nil, btn3)
local icon3 = holder:CreateTexture()
local theirs = holder:CreateMaskTexture()
icon3:AddMaskTexture(theirs)
check(GAB.SkinButton(btn3, { icon = icon3 }), "an icon on a child frame: skinned")
eq(#icon3._masks, 2, "  their mask kept, ours added")
check(icon3._masks[1] == theirs and icon3._masks[2]:GetParent() == holder, "  ours on the icon's own frame, not the button")
for k in pairs(fields(btn)) do check(beforeFields[k] ~= nil, "no field written on the provider's button: " .. tostring(k)) end

-- In combat: queued (with a copy), applied when the fight ends.
local btn2 = CreateFrame("Button", "ProvButton2", own)
btn2._protected = true
local r2 = { icon = btn2:CreateTexture(), hotkey = btn2:CreateFontString() }
WoW.combat = true
WoW.fire("PLAYER_REGEN_DISABLED")
check(GAB.SkinButton(btn2, r2), "SkinButton in combat: accepted")
check(not GAB.Buttons.IsSkinned(btn2), "  not built in combat")
eq(r2.icon._masks, nil, "  its icon not masked yet")
r2.icon = nil                                   -- the provider's table changes while queued
eq(#WoW.violations, 0, "  no protected change in combat")
WoW.combat = false
WoW.fire("PLAYER_REGEN_ENABLED")
check(GAB.Buttons.IsSkinned(btn2), "  built when the fight ended")
check(GAB.Buttons.State(btn2).regions.icon ~= nil, "  from the copy taken when it was accepted")
eq(GAB.Buttons.State(btn2).regions.icon._masks and #GAB.Buttons.State(btn2).regions.icon._masks, 1, "  its icon masked too")

-- The glass off: refused.
GAB.db.skin = false
ok, why = GAB.SkinButton(CreateFrame("Button", nil, own), {})
check(ok == false and why:find("skin"), "/gab skin off: SkinButton refused")
GAB.db.skin = nil

-- RegisterButton: validated, stored for the Utility bar, copies out.
local clicked = false
local bdef = { id = "roulette", label = "Portal Roulette", icon = 134400, binding = "PORTALROULETTE_TOGGLE",
    OnClick = function() clicked = true end, tooltip = "Spin", OnHosted = function() error("not yet") end }
check(GAB.RegisterButton(bdef), "RegisterButton: accepted")
local function refusedButton(def, what)
    local okb, whyb = GAB.RegisterButton(def)
    check(okb == false and type(whyb) == "string", what .. ": refused (" .. tostring(whyb) .. ")")
end
refusedButton({ id = "roulette", icon = 1, OnClick = print }, "a duplicate button id")
refusedButton({ id = "noclick", icon = 1 }, "no OnClick")
refusedButton({ id = "noicon", OnClick = print }, "no icon")
refusedButton({ id = "bad id", icon = 1, OnClick = print }, "a bad id")
refusedButton({ id = "badtip", icon = 1, OnClick = print, tooltip = 5 }, "a numeric tooltip")
refusedButton({ id = "badbind", icon = 1, OnClick = print, binding = 5 }, "a numeric binding")
refusedButton({ id = "badenabled", icon = 1, OnClick = print, IsEnabled = true }, "IsEnabled not a function")
local list = GAB.ProvidedButtons()
eq(#list, 1, "one button stored")
eq(list[1].label, "Portal Roulette", "  its label")
list[1].label = "changed"
eq(GAB.ProvidedButtons()[1].label, "Portal Roulette", "  copies out: the stored one unchanged")
bdef.label = "changed too"
eq(GAB.ProvidedButtons()[1].label, "Portal Roulette", "  copied in: the provider's table changing changes nothing")
WoW.tick()
eq(GAB.failures["api:roulette"], nil, "no callback until the Utility bar hosts it")
check(not clicked, "  not clicked")

-- SetButtonEmpty (Apotheca#68): a provider's empty slot gets the empty-slot look.
local pb = CreateFrame("Button", "EmptyTestButton", UIParent)
check(GAB.SkinButton(pb, { icon = pb:CreateTexture() }, "Test"), "a provider button skinned")
local pst = GAB.Buttons.State(pb)
eq(pst.occupied, true, "  it counts as filled until told")
check(GAB.SetButtonEmpty(pb, true), "SetButtonEmpty(true)")
eq(pst.occupied, false, "  empty: the empty-slot look")
check(GAB.SetButtonEmpty(pb, false) and pst.occupied == true, "SetButtonEmpty(false): filled again")
eq(GAB.SetButtonEmpty(pb, "yes"), false, "a non-boolean refused")
eq(GAB.SetButtonEmpty(CreateFrame("Button", "NeverSkinned", UIParent), true), false, "a button never skinned refused")
WoW.combat = true
local qb = CreateFrame("Button", "WaitingButton", UIParent)
check(GAB.SkinButton(qb, { icon = qb:CreateTexture() }), "in combat: the skin waits")
check(GAB.SetButtonEmpty(qb, true), "  SetButtonEmpty on a waiting button: kept")
WoW.combat = false
WoW.fire("PLAYER_REGEN_ENABLED")
check(GAB.Buttons.IsSkinned(qb) and GAB.Buttons.State(qb).occupied == false, "  applied once the skin is built")
-- The provider's own PLAYER_REGEN_ENABLED runs before GAB's: it skins again
-- and answers anew; GAB's flush after it must not bring the older answer back.
WoW.combat = true
local rb = CreateFrame("Button", "RacingButton", UIParent)
check(GAB.SkinButton(rb, { icon = rb:CreateTexture() }), "in combat: another skin waits")
check(GAB.SetButtonEmpty(rb, true), "  kept: empty")
WoW.combat = false
check(GAB.SkinButton(rb, { icon = rb:CreateTexture() }), "out of combat, before GAB's flush: skinned at once")
eq(GAB.Buttons.State(rb).occupied, false, "  the kept answer applied")
check(GAB.SetButtonEmpty(rb, false), "  then filled")
WoW.fire("PLAYER_REGEN_ENABLED")
eq(GAB.Buttons.State(rb).occupied, true, "  GAB's flush after it: still filled, not the older answer")
done("test_api")
