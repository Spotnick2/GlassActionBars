-- wow_stubs.lua: GlassActionBars' WoW: Forever mock for Lua 5.1 unit tests.
-- dofile("tests/wow_stubs.lua") FIRST in every test; drive it via the WoW table.
--
-- The mechanics come from WowTestKit (tests/kit.lua loads the commit
-- tests/kit.pin names; its README is the reference): strict globals, secrets,
-- event names checked against the pinned build, widgets that record every
-- method called, protected frames, print (with the stray-"|" check done()
-- fails on), timers, fire / fireAllRegistered / tick. This file adds GAB's
-- own client APIs (the action bars, the bag bar, the micro menu, the Utility
-- bar's spells and items) and replaces a WoW.Methods entry where a test
-- relies on it.

-- WowTestKit #8: a test that loads this file again for a fresh client
-- (test_bags_micro, test_pearl, test_skin_fail) keeps its counts: the kit,
-- with its assertions, is loaded once; a reload rebuilds only the stub core.
if rawget(_G, "Kit") and Kit.counts then
    local strays = WoW.strays
    setmetatable(_G, nil)
    dofile(Kit.ROOT .. "/core/stubs.lua")
    for _, line in ipairs(strays) do table.insert(WoW.strays, line) end
else
    dofile("tests/kit.lua")
end
local Methods = WoW.Methods
local newWidget = WoW.newWidget

-- WowTestKit #9: one rendered frame moves the clock too, as on the client
-- (Fade.lua times its fade-out by GetTime() inside OnUpdate).
local coreTick = WoW.tick
function WoW.tick(elapsed)
    WoW.now = (WoW.now or 0) + (elapsed or 0.02)
    coreTick(elapsed)
end

-- State a test may set, cleared with the core's.
local function resetState() WoW.cvars = {} end
table.insert(WoW.onReset, resetState)
resetState()

--------------------------------------------------------------------------------
-- Templates (WoW.templates: what each adds to the frame CreateFrame makes)
--------------------------------------------------------------------------------

-- The template's bar, shown by default as on the client.
WoW.templates.UIPanelScrollFrameTemplate = function(w) w.ScrollBar = newWidget("Slider", w) end
-- The radio template's own label (CheckButtonTemplates.xml: parentKey "text").
WoW.templates.UIRadioButtonTemplate = function(w) w.text = Methods.CreateFontString(w) end

--------------------------------------------------------------------------------
-- Widget methods: the core's, plus what GAB needs on top
--------------------------------------------------------------------------------

-- WoW.secretShown[frame] = true: IsShown / IsVisible answer a secret
-- (SecretReturnsForAspect Shown). Replaces the core's two (the Fade tests).
WoW.secretShown = {}
local coreIsShown, coreIsVisible = Methods.IsShown, Methods.IsVisible
function Methods.IsShown(w)
    if WoW.secretShown[w] then return WoW.Secret("IsShown") end
    return coreIsShown(w)
end
function Methods.IsVisible(w)
    if WoW.secretShown[w] then return WoW.Secret("IsVisible") end
    return coreIsVisible(w)
end
function Methods.GetNumPoints(w) return #w._points end
-- Geometry as the client reports it: w._rect = { left, right, top, bottom }
-- in the frame's own units (nil when it has no rect), w._escale its
-- effective scale (1 by default). A test may put a secret in either.
function Methods.GetLeft(w) return w._rect and w._rect[1] end
function Methods.GetRight(w) return w._rect and w._rect[2] end
function Methods.GetTop(w) return w._rect and w._rect[3] end
function Methods.GetBottom(w) return w._rect and w._rect[4] end
function Methods.GetEffectiveScale(w) return w._escale or 1 end
function Methods.SetTexCoord(w, ...) w._texcoord = { ... } end
-- Moving: like the client, refused on a protected frame (or one with
-- protected children: the test marks it _protected) in combat.
function Methods.SetMovable(w, v) w._movable = v end
function Methods.StartMoving(w)
    if WoW.combat and w._protected then table.insert(WoW.violations, "StartMoving in combat") return end
    w._moving = true
end
function Methods.StopMovingOrSizing(w)
    if WoW.combat and w._protected then table.insert(WoW.violations, "StopMovingOrSizing in combat") return end
    w._moving = false
end
-- The pointer: WoW.hover[frame] = true (or a secret, as IsMouseOver's
-- SecretWhenAnchoringSecret allows) says it is over that frame.
WoW.hover = {}
function Methods.IsMouseOver(w)
    local v = WoW.hover[w]
    if v == nil then return false end
    return v
end
-- The client's widget hierarchy, as far as the addon asks.
local KIND_OF = { CheckButton = "Button", Button = "Frame", Cooldown = "Frame", StatusBar = "Frame",
    Slider = "Frame", GameTooltip = "Frame", EditBox = "Frame", ScrollFrame = "Frame" }
function Methods.IsObjectType(w, t)
    local k = w._type
    while k do
        if k == t then return true end
        k = KIND_OF[k]
    end
    return false
end
-- A button's state textures: Set*Texture(file) makes one, Get*Texture reads it.
for _, state in ipairs({ "Normal", "Pushed", "Highlight", "Checked", "Disabled" }) do
    local key = "_" .. state:lower() .. "Texture"
    Methods["Set" .. state .. "Texture"] = function(b, file)
        b[key] = b[key] or newWidget("Texture", b)
        b[key]._file = file
    end
    Methods["Get" .. state .. "Texture"] = function(b) return b[key] end
end
-- A cooldown widget: what it was last given.
function Methods.SetCooldown(cd, start, dur) cd._cd = { start, dur } end
function Methods.SetCooldownFromDurationObject(cd, d) cd._cd = { duration = d } end
function Methods.Clear(cd) cd._cd = "cleared" end
function Methods.SetTextureSliceMargins(t, l, tp, r, b) t._slice = { l, tp, r, b } end
function Methods.SetJustifyH(fs, j) fs._justifyH = j end
function Methods.GetJustifyH(fs) return fs._justifyH or "CENTER" end
function Methods.GetFontString(b) return b._fontString end
-- An EditBox's selection colour.
function Methods.SetHighlightColor(e, r, g, b, a) e._highlight = { r, g, b, a } end
function Methods.GetHighlightColor(e)
    local c = e._highlight or { 1, 1, 1, 1 }
    return c[1], c[2], c[3], c[4]
end
function Methods.IsTruncated(fs) return fs._truncated == true end
function Methods.GetID(w) return w._id or 0 end

--------------------------------------------------------------------------------
-- Globals
--------------------------------------------------------------------------------

SlashCmdList = {}
Enum = { UITextureSliceMode = { Stretched = 0, Tiled = 1 },
    -- Measured by Apotheca on 70291 (its docs/FOREVER-PROBE.md).
    EditModeActionBarSetting = { Orientation = 0, NumRows = 1, NumIcons = 2, IconSize = 3, IconPadding = 4,
        VisibleSetting = 5, HideBarArt = 6, DeprecatedSnapToSide = 7, HideBarScrolling = 8, AlwaysShowButtons = 9 } }
-- Spells, items, auras and bindings (the Utility bar), scripted by a test:
-- WoW.known[spellID] = true; WoW.items[itemID] = count; WoW.auras[spellID] =
-- true | a secret | "throw"; WoW.bindings[action] = key; WoW.durations[spellID]
-- = a duration object; WoW.itemCooldowns[itemID] = { start, duration }.
WoW.known, WoW.items, WoW.auras, WoW.bindings, WoW.durations, WoW.itemCooldowns = {}, {}, {}, {}, {}, {}
C_SpellBook = { IsSpellKnown = function(id) return WoW.known[id] == true end }
C_Item = {
    GetItemCount = function(id) return WoW.items[id] or 0 end,
    GetItemIconByID = function(id) return 100000 + id end,
    GetItemSpell = function(id)
        if id == 6948 then return "Hearthstone", 8690 end
        if (WoW.itemSpells or {})[id] then return "Use", WoW.itemSpells[id] end
    end,
    GetItemNameByID = function(id) return (WoW.itemNames or {})[id] end,
}
C_Spell = {
    GetSpellTexture = function(id) return 200000 + id end,
    GetSpellName = function(id) return (WoW.spellNames or {})[id] end,
    GetSpellCooldownDuration = function(id) return WoW.durations[id] end,
}
C_Container = { GetItemCooldown = function(id)
    local c = WoW.itemCooldowns[id]
    if c then return c[1], c[2], 1 end
    return 0, 0, 1
end }
C_UnitAuras = { GetPlayerAuraBySpellID = function(id)
    local a = WoW.auras[id]
    if a == "throw" then error("aura read refused") end
    if a == true then return { spellId = id } end
    return a
end,
    -- The player's helpful auras in order: WoW.helpful[i] = { spellId, name, duration }.
    GetAuraDataByIndex = function(unit, i, filter) return (WoW.helpful or {})[i] end }
function GetBindingKey(action)
    if type(action) ~= "string" then error("Usage: GetBindingKey(\"command\")", 2) end   -- a nil command is a caller bug: made loud (#52)
    return WoW.bindings[action]
end
function IsAltKeyDown() return WoW.altDown == true end
-- The pointer in screen pixels (WoW.cursor = { x, y }; a test may make either secret).
function GetCursorPosition() local c = WoW.cursor or { 0, 0 }; return c[1], c[2] end

-- Errors handed to the client's error handler (a Lua error popup in game).
WoW.errors = {}
function geterrorhandler() return function(err) table.insert(WoW.errors, err) end end
function CreateColor(r, g, b, a) return { r = r, g = g, b = b, a = a } end
date = os.date
time = os.time
function GetServerTime() return time() end
function GetBuildInfo() return "1.60.1", "70374", "Oct 12 2026", 16001 end
-- Everything in the stubs is secure; WoW.tainted[name] = "Addon" says otherwise (GABProbe bagsbar, #55).
function issecurevariable(t, name)
    local by = WoW.tainted and WoW.tainted[name]
    return by == nil, by
end
-- CVars; SetCVar fires CVAR_UPDATE synchronously, as the client documents it.
-- WoW.cvarFail makes SetCVar throw; WoW.cvarRefuse makes it return false
-- and change nothing.
function GetCVar(name) return WoW.cvars[name] end
function SetCVar(name, value)
    if WoW.cvarFail then error("SetCVar refused") end
    if WoW.cvarRefuse then return false end
    WoW.cvars[name] = tostring(value)
    WoW.fire("CVAR_UPDATE", name, tostring(value))
    return true
end

-- The player: GUID, and the name split across UnitName's two returns, one of
-- the two shapes the client has used (AltStable #56).
WoW.playerGUID = "Player-1-AAA"
function UnitGUID(unit) if unit == "player" then return WoW.playerGUID end end
function UnitName(unit) if unit == "player" then return WoW.playerName or "Karuzo", "Morphisto" end end
WoW.playerClass = "WARLOCK"
function UnitClass(unit) if unit == "player" then return "Warlock", WoW.playerClass, 9 end end
C_ClassColor = { GetClassColor = function(class)
    if class == "WARLOCK" then return { r = 0.53, g = 0.53, b = 0.93 } end
end }
function GetRealmName() return "Doomhowl" end

WoW.addonVersion = "dev"
C_AddOns = {
    GetAddOnMetadata = function(name, field) if field == "Version" then return WoW.addonVersion end end,
}

-- The Settings framework (Blizzard_Settings): canvas categories, recorded.
WoW.categories = {}
Settings = {
    RegisterCanvasLayoutCategory = function(frame, name)
        local c = { frame = frame, name = name, id = #WoW.categories + 1 }
        function c:GetID() return self.id end
        table.insert(WoW.categories, c)
        return c
    end,
    RegisterCanvasLayoutSubcategory = function(parent, frame, name)
        local c = Settings.RegisterCanvasLayoutCategory(frame, name)
        c.parent = parent
        return c
    end,
    RegisterAddOnCategory = function(c) c.registered = true end,
    OpenToCategory = function(id) WoW.openedCategory = id end,
}

-- EventRegistry (CallbackRegistryMixin): callbacks by event name, run by
-- WoW.trigger as TriggerEvent runs them, with the owner first.
WoW.callbacks = {}
EventRegistry = {}
function EventRegistry:RegisterCallback(event, fn, owner)
    WoW.callbacks[event] = WoW.callbacks[event] or {}
    table.insert(WoW.callbacks[event], { fn, owner })
end
function WoW.trigger(event, ...)
    for _, c in ipairs(WoW.callbacks[event] or {}) do c[1](c[2], ...) end
end
-- An addon's own event: recorded in WoW.triggered, then run like Blizzard's.
WoW.triggered = {}
function EventRegistry:TriggerEvent(event, ...)
    table.insert(WoW.triggered, { event, ... })
    WoW.trigger(event, ...)
end

-- Quick Keybind mode (Blizzard_QuickKeybind): WoW.quickKeybind.
function KeybindFrames_InQuickKeybindMode() return WoW.quickKeybind == true end

--------------------------------------------------------------------------------
-- GameTooltip: its owner and lines, as text. SetOwner starts it over.
--------------------------------------------------------------------------------

GameTooltip = newWidget("GameTooltip", UIParent, "GameTooltip")
GameTooltip._lines = {}
function Methods.SetOwner(t, owner) t._owner, t._lines = owner, {} end
function Methods.IsOwned(t, f) return t._owner == f end
function Methods.AddLine(t, text) table.insert(t._lines, text) end
local coreSetText = Methods.SetText
function Methods.SetText(t, text, ...)
    if t._type == "GameTooltip" then t._lines = { text } else coreSetText(t, text, ...) end
end
function GameTooltip_Hide() GameTooltip:Hide() end

--------------------------------------------------------------------------------
-- The action bars (Blizzard_ActionBar, loaded before any addon), as the
-- forever branch of wow-ui-source declares them: ActionButtonTemplate's
-- parentKeys (Mainline/ActionButtonTemplate.xml), the mixin methods the skin
-- hooks (copied onto each frame, as Mixin does), and the bars. Buttons are
-- protected. WoW.violations records every change the client would refuse on
-- one in combat (more methods than the core's own refusals, WoW.blocked: a
-- size or a level too), whether or not the core then refuses it.
--------------------------------------------------------------------------------

WoW.violations = {}
-- Blizzard's own secure code may show, hide or move a protected frame in
-- combat; the core refuses it only to addon code. fn runs as Blizzard's, with
-- f's protection lifted (a bar Blizzard hides mid-fight, test_edges).
function WoW.blizzard(f, fn)
    local p = f._protected
    f._protected = nil
    fn()
    f._protected = p
end
for _, m in ipairs({ "SetPoint", "ClearAllPoints", "SetAllPoints", "SetParent", "SetSize", "SetWidth",
                     "SetHeight", "Show", "Hide", "SetShown", "SetFrameLevel", "SetScale", "SetAttribute" }) do
    local impl = Methods[m]
    Methods[m] = function(w, ...)
        if WoW.combat and w._protected then
            table.insert(WoW.violations, (w._name or w._type) .. ":" .. m)
            if m == "SetAttribute" then return end
        end
        if impl then return impl(w, ...) end
    end
end

-- Hand-scripted slot contents: WoW.actions[slot] = true when the slot holds
-- something; WoW.forms[i], WoW.petActions[i] likewise. A secret value is
-- returned as is.
WoW.actions, WoW.forms, WoW.petActions = {}, {}, {}
function HasAction(slot)
    if slot == nil then error("bad argument #1 to 'HasAction'") end
    local v = WoW.actions[slot]
    if issecretvalue(v) then return v end
    return v == true
end
function GetShapeshiftFormInfo(i)
    local v = WoW.forms[i]
    if issecretvalue(v) then return v end
    if v then return 136116, false, true, 5487 end
end
function GetPetActionInfo(i)
    local v = WoW.petActions[i]
    if issecretvalue(v) then return v end
    if v then return "Attack", 132152, false, false, false, false, nil end
end

NUM_ACTIONBAR_BUTTONS = 12
NUM_PET_ACTION_SLOTS = 10
ActionButtonUtil = { ActionBarButtonNames = {
    "ActionButton", "MultiBarBottomLeftButton", "MultiBarBottomRightButton", "MultiBarLeftButton",
    "MultiBarRightButton", "MultiBar5Button", "MultiBar6Button", "MultiBar7Button",
} }

-- An ActionButtonTemplate button. `small`: SmallActionButtonTemplate (30x30).
-- The methods are Blizzard's, shortened: UpdateButtonArt sets the two
-- atlases again (ActionButtonOverrides.lua:2).
local function actionButton(name, parent, small)
    local b = CreateFrame("CheckButton", name, parent)
    b._protected = true
    b._level = (parent and parent._level or 0) + 1
    local side = small and 30 or 45
    b._width, b._height = side, side
    b.icon = Methods.CreateTexture(b, name .. "Icon", "BACKGROUND")
    b.IconMask = Methods.CreateMaskTexture(b)
    b.SlotBackground = Methods.CreateTexture(b, nil, "BACKGROUND")
    b.SlotArt = Methods.CreateTexture(b, nil, "BACKGROUND")
    b.Flash = Methods.CreateTexture(b, name .. "Flash", "ARTWORK")
    b.Name = Methods.CreateFontString(b, name .. "Name")
    b.Border = Methods.CreateTexture(b, name .. "Border", "OVERLAY")
    b.TextOverlayContainer = CreateFrame("Frame", nil, b)
    b.TextOverlayContainer._level = 500
    b.HotKey = Methods.CreateFontString(b.TextOverlayContainer, name .. "HotKey")
    b.Count = Methods.CreateFontString(b.TextOverlayContainer, name .. "Count")
    -- The container's own parentKeys; its OnLoad aliases them onto the button.
    b.TextOverlayContainer.HotKey, b.TextOverlayContainer.Count = b.HotKey, b.Count
    b.cooldown = CreateFrame("Cooldown", name .. "Cooldown", b)
    b.cooldown._level = b._level
    for _, state in ipairs({ "Normal", "Pushed", "Highlight", "Checked" }) do
        Methods["Set" .. state .. "Texture"](b, "atlas:" .. state)
        b[state .. "Texture"] = Methods["Get" .. state .. "Texture"](b)
    end
    -- The template's key text: top right, right-justified; UpdateHotkeys (ActionButton.lua:480)
    -- sizes it to the button and anchors it again (SetPoint, no ClearAllPoints).
    Methods.SetPoint(b.HotKey, "TOPRIGHT", b, "TOPRIGHT", -2, -4)
    Methods.SetSize(b.HotKey, side - 8, 10)
    Methods.SetJustifyH(b.HotKey, "RIGHT")
    rawset(b, "UpdateHotkeys", function(self)
        Methods.SetSize(self.HotKey, self._width - 8, 10)
        Methods.SetPoint(self.HotKey, "TOPRIGHT", self, "TOPRIGHT", -2, -4)
        self._hotkeyUpdates = (self._hotkeyUpdates or 0) + 1
    end)
    rawset(b, "UpdateButtonArt", function(self)
        self.NormalTexture._file = "UI-HUD-ActionBar-IconFrame"
        self.PushedTexture._file = "UI-HUD-ActionBar-IconFrame-Down"
        self.PushedTexture._blend = nil
        self._artUpdates = (self._artUpdates or 0) + 1
    end)
    return b
end
WoW.actionButton = actionButton

local function bar(name)
    local f = CreateFrame("Frame", name, UIParent)
    f._protected = true
    f._level = 50
    return f
end

-- A frame pool (Blizzard_SharedXMLBase/Pools): EnumerateActive iterates its frames.
local function pool(owner)
    local p = { active = {} }
    function p:Acquire()
        local f = CreateFrame("Frame", nil, owner)
        self.active[f] = true
        return f
    end
    function p:ReleaseAll() self.active = {} end
    function p:EnumerateActive() return pairs(self.active) end
    return p
end

-- The main bar: its border art, the end caps (each an Edit Mode system with
-- a texture), the page number, and dividers between its buttons.
MainActionBar = bar("MainActionBar")
MainActionBar.BorderArt = Methods.CreateTexture(MainActionBar, nil, "BACKGROUND")
MainActionBar.EndCaps = CreateFrame("Frame", nil, MainActionBar)
for _, key in ipairs({ "LeftEndCap", "RightEndCap" }) do
    MainActionBar.EndCaps[key] = CreateFrame("Frame", nil, MainActionBar.EndCaps)
    MainActionBar.EndCaps[key].Texture = Methods.CreateTexture(MainActionBar.EndCaps[key], nil, "OVERLAY")
end
MainActionBar.ActionBarPageNumber = CreateFrame("Frame", nil, MainActionBar)
MainActionBar.HorizontalDividersPool = pool(MainActionBar)
MainActionBar.VerticalDividersPool = pool(MainActionBar)
rawset(MainActionBar, "UpdateDividers", function(self)
    self.HorizontalDividersPool:ReleaseAll()
    for _ = 1, 11 do self.HorizontalDividersPool:Acquire() end
end)
MainActionBar:UpdateDividers()

-- Each action bar (ActionBar.lua:14): a container per button (button.container),
-- the laid-out ones in bar.shownButtonContainers, spacers included; its
-- Edit Mode settings through GetSettingValue (bar._settings, plain by
-- default: 100%, padding 2, one horizontal row); UpdateGridLayout and
-- UpdateShownButtons as methods to hook. WoW.layoutBar(bar, ...) gives the
-- containers rects.
local barOf = { ActionButton = MainActionBar }
for _, prefix in ipairs(ActionButtonUtil.ActionBarButtonNames) do
    local parent = barOf[prefix] or bar((prefix:gsub("Button$", "")))
    parent.shownButtonContainers = {}
    parent._settings = { [0] = 0, [1] = 1, [2] = 12, [3] = 100, [4] = 2 }
    rawset(parent, "GetSettingValue", function(self, setting) return self._settings[setting] end)
    rawset(parent, "UpdateGridLayout", function() end)
    rawset(parent, "UpdateShownButtons", function() end)
    for i = 1, NUM_ACTIONBAR_BUTTONS do
        local b = actionButton(prefix .. i, parent)
        b.action = i
        b.index = i
        b.bar = parent
        b.container = CreateFrame("Frame", nil, parent)
        table.insert(parent.shownButtonContainers, b.container)
        rawset(b, "Update", function(self) self._updates = (self._updates or 0) + 1 end)
    end
end

-- Lay a bar's containers out in a grid: `n` slots (the rest not laid out),
-- `stride` per row, 45 + pad each, the first slot's top-left at (x, y),
-- growing right and down (or `up`), in the bar's units at `escale`.
function WoW.layoutBar(b, x, y, opts)
    opts = opts or {}
    local n, stride, pad = opts.n or 12, opts.stride or 12, opts.pad or 2
    local list = {}
    for i, c in ipairs(b.shownButtonContainers._all or b.shownButtonContainers) do
        c._escale = opts.escale or 1
        if i <= n then
            local col, row = (i - 1) % stride, math.floor((i - 1) / stride)
            local l = x + col * (45 + pad)
            local t = opts.up and (y + row * (45 + pad)) or (y - row * (45 + pad))
            c._rect = { l, l + 45, t, t - 45 }
            list[#list + 1] = c
        else
            c._rect = nil
        end
    end
    list._all = b.shownButtonContainers._all or b.shownButtonContainers
    b.shownButtonContainers = list
end

StanceBar = bar("StanceBar")
rawset(StanceBar, "UpdateState", function() end)
for i = 1, 10 do actionButton("StanceButton" .. i, StanceBar, true).index = i end
PetActionBar = bar("PetActionBar")
rawset(PetActionBar, "Update", function() end)
for i = 1, NUM_PET_ACTION_SLOTS do actionButton("PetActionButton" .. i, PetActionBar, true).index = i end
-- Edit Mode systems (EditModeSystemMixin:OnSystemLoad): SetPoint and ClearAllPoints become
-- overrides, the originals saved as the Base methods; ApplySystemAnchor re-anchors.
for _, f in ipairs({ StanceBar, PetActionBar }) do
    rawset(f, "SetPointBase", function(self, ...) Methods.SetPoint(self, ...) end)
    rawset(f, "ClearAllPointsBase", function(self) Methods.ClearAllPoints(self) end)
    rawset(f, "ApplySystemAnchor", function() end)
    -- BreakFrameSnap (a snapped-to bar hid): as Blizzard's, frozen where it is as an
    -- absolute TOPLEFT anchor (the stub keeps the x it had), the snap dropped, and
    -- OnSystemPositionChange: the layout's anchor written (f._layout), the default flag
    -- cleared. f._default: IsInDefaultPosition.
    rawset(f, "BreakFrameSnap", function(self)
        local x = self._points[1] and self._points[1][4] or 0
        local to = rawget(self, "snappedToFrame")
        if to and type(rawget(to, "snappedFrames")) == "table" then to.snappedFrames[self] = nil end
        rawset(self, "snappedToFrame", nil)
        Methods.ClearAllPoints(self)
        Methods.SetPoint(self, "TOPLEFT", UIParent, "TOPLEFT", x, -500)
        self._layout, self._default = { "TOPLEFT", x, -500 }, false
    end)
    rawset(f, "IsInDefaultPosition", function(self) return self._default == true end)
end

-- Edit Mode's manager: it re-stacks the default-position bars when one shows
-- or hides (EditModeManager.lua:598,641), without a grid update.
EditModeManagerFrame = CreateFrame("Frame", "EditModeManagerFrame", UIParent)
rawset(EditModeManagerFrame, "UpdateBottomActionBarPositions", function() end)
rawset(EditModeManagerFrame, "UpdateRightActionBarPositions", function() end)

-- The spell flyout (SpellFlyout.xml): hidden until a flyout button opens it;
-- FlyoutPopupMixin:AttachToButton reparents it to that button (Flyout.lua:218).
SpellFlyout = CreateFrame("Frame", "SpellFlyout", UIParent)
SpellFlyout._shown = false

--------------------------------------------------------------------------------
-- The bag bar (Blizzard_MainMenuBarBagButtons, Shared + Camelot): BagsBar with
-- its BorderArt and divider pools, re-laid out by Layout; the slots are item
-- buttons whose UpdateTextures sets their frame atlases again; a bag slot
-- holds a bag when GetInventoryItemTexture says so (WoW.bags[id]).
--------------------------------------------------------------------------------

BagsBar = bar("BagsBar")
BagsBar._protected = nil
BagsBar.BorderArt = Methods.CreateTexture(BagsBar, nil, "BACKGROUND")
BagsBar.HorizontalDividersPool = pool(BagsBar)
BagsBar.VerticalDividersPool = pool(BagsBar)
rawset(BagsBar, "UpdateDividers", function(self)
    self.HorizontalDividersPool:ReleaseAll()
    for _ = 1, 5 do self.HorizontalDividersPool:Acquire() end
end)
rawset(BagsBar, "Layout", function(self) self:UpdateDividers() end)
BagsBar:Layout()

WoW.bagTextures = {}
function GetInventoryItemTexture(unit, slot) if unit == "player" then return WoW.bagTextures[slot] end end
-- The key ring holds keys: WoW.hasKey (false by default; "throw" refuses, a secret is returned as is).
function HasKey()
    if WoW.hasKey == "throw" then error("HasKey refused") end
    return WoW.hasKey or false
end

local function bagButton(name, id)
    local b = CreateFrame("Button", name, BagsBar)
    b._level = BagsBar._level + 1
    b._width, b._height = 45, 45
    b._id = id
    b.icon = Methods.CreateTexture(b, name .. "IconTexture", "BORDER")
    b.Count = Methods.CreateFontString(b, name .. "Count")
    b.SlotHighlightTexture = Methods.CreateTexture(b, nil, "OVERLAY")
    for _, state in ipairs({ "Normal", "Pushed", "Highlight" }) do
        Methods["Set" .. state .. "Texture"](b, "atlas:" .. state)
        b[state .. "Texture"] = Methods["Get" .. state .. "Texture"](b)
    end
    rawset(b, "UpdateTextures", function(self)
        self.NormalTexture._file = "ui-hud-actionbar-iconframe-bags"
        self.PushedTexture._file = "ui-hud-actionbar-iconframe-bags"
        self.PushedTexture._blend = nil
        self.HighlightTexture._alpha = 0.4
    end)
    return b
end
bagButton("MainMenuBarBackpackButton", 0)
for i = 0, 3 do bagButton("CharacterBag" .. i .. "Slot", 31 + i) end
bagButton("CharacterReagentBag0Slot", 35)
bagButton("KeyRingButton", 0)._width = 33

--------------------------------------------------------------------------------
-- The micro menu (Blizzard_MicroMenu, Camelot): MicroMenuContainer (the Edit
-- Mode system) holding MicroMenu, whose BorderArt and BackgroundArt are the
-- dark panel; Blizzard reparents MicroMenu for the override bar and pet battles.
--------------------------------------------------------------------------------

MicroMenuContainer = CreateFrame("Frame", "MicroMenuContainer", UIParent)
MicroMenu = CreateFrame("Frame", "MicroMenu", MicroMenuContainer)
MicroMenu._level = 51
MicroMenu.BorderArt = Methods.CreateTexture(MicroMenu, nil, "BACKGROUND")
MicroMenu.BackgroundArt = Methods.CreateTexture(MicroMenu, nil, "BACKGROUND")
CharacterMicroButton = CreateFrame("Button", "CharacterMicroButton", MicroMenu)
CharacterMicroButton._width, CharacterMicroButton._height = 32, 40
CharacterMicroButton.Background = Methods.CreateTexture(CharacterMicroButton, nil, "BACKGROUND")
CharacterMicroButton.PushedBackground = Methods.CreateTexture(CharacterMicroButton, nil, "BACKGROUND")
CharacterMicroButton.Shadow = Methods.CreateTexture(CharacterMicroButton, nil, "BORDER")
CharacterMicroButton.PushedShadow = Methods.CreateTexture(CharacterMicroButton, nil, "OVERLAY")
-- A micro button (MainMenuBarMicroButtons.xml): 32 x 40, its four state
-- textures set by atlas through Set<State>Atlas (which, here, also clears the
-- texture's crop, so a crop not applied again shows), ButtonBG behind, and an
-- alert's FlashContent on some.
local function microButton(name, flash)
    local b = CreateFrame("Button", name, MicroMenu)
    b._width, b._height = 32, 40
    for _, st in ipairs({ "Normal", "Pushed", "Disabled", "Highlight" }) do
        local t = Methods.CreateTexture(b, nil, st == "Highlight" and "HIGHLIGHT" or "ARTWORK")
        t._atlas = "UI-HUD-MicroMenu-" .. name .. "-" .. st
        rawset(b, "Get" .. st .. "Texture", function() return t end)
        rawset(b, "Set" .. st .. "Atlas", function(_, atlas) t._atlas = atlas; t._texcoord = nil end)
    end
    b.Background = Methods.CreateTexture(b, nil, "BACKGROUND")
    b.PushedBackground = Methods.CreateTexture(b, nil, "BACKGROUND")
    if flash then b.FlashContent = Methods.CreateTexture(b, nil, "OVERLAY") end
    return b
end
SpellbookMicroButton = microButton("SpellbookMicroButton", true)
MainMenuMicroButton = microButton("MainMenuMicroButton")
OverrideActionBar = CreateFrame("Frame", "OverrideActionBar", UIParent)

-- Strict globals: any read of an undefined global is an error, except the
-- addon's own globals that are legitimately nil before first assignment.
-- LibStub: the embedded library's loader reads _G.LibStub before creating it.
Kit.strict({ GlassActionBars = true, GlassActionBarsDB = true, GABProbeDB = true,
    LibStub = true, ForeverProbe = true, ForeverProbeDB = true })
