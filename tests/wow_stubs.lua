-- wow_stubs.lua: a minimal WoW: Forever mock for Lua 5.1 unit tests.
-- dofile("tests/wow_stubs.lua") FIRST in every test; drive it via the WoW table.
-- GlassMail's stubs (GlassChat's generic part: secrets, events, widgets,
-- strict globals), without the mail windows. The action bars' frames are
-- added as the skin lands.
--
-- What it models, on purpose:
-- - STRICT globals: reading any global it does not define is an error. The
--   stub is the allowlist of APIs verified present in the API dump; defining
--   something Forever lacks is how a missing API survives into a build.
-- - SECRETS as newproxy userdata: arithmetic, ordering, tostring, concat and
--   string.format on one throw. Lua 5.1 cannot make a truth test or == throw,
--   so those two misuses are NOT caught here (only in game / in review).
-- - EVENT names: RegisterEvent throws on a name the API dump does not declare
--   (tests/events-70374.txt when the dump is absent, as on CI).
-- - METHOD calls: every widget method called is recorded (WoW.methodsCalled)
--   so test_methods.lua can check each against the dump's widget methods.

WoW = {}
local DUMP = os.getenv("GAB_API_DUMP") or "C:/Projects/WoW/References/forever-api-1.60.1.70374.md"
WoW.DUMP = DUMP

--------------------------------------------------------------------------------
-- Secrets
--------------------------------------------------------------------------------

local secrets = setmetatable({}, { __mode = "k" })

function WoW.Secret(label)
    local p = newproxy(true)
    local mt = getmetatable(p)
    local function boom() error("secret value touched in Lua: " .. label, 2) end
    for _, k in ipairs({ "__tostring", "__concat", "__add", "__sub", "__mul", "__div", "__mod",
                         "__pow", "__unm", "__lt", "__le", "__len", "__index", "__newindex", "__call" }) do
        mt[k] = boom
    end
    secrets[p] = label
    return p
end

function issecretvalue(v) return secrets[v] ~= nil end

-- Mark an existing value secret for issecretvalue. The client's secrets keep
-- their type (a secret string is still type "string"), which a proxy can't
-- model; use this to reach `type(x) == "string"` branches.
function WoW.MarkSecret(v, label) secrets[v] = label or "marked" end

--------------------------------------------------------------------------------
-- Known events (from the dump when present, else the checked-in fixture)
--------------------------------------------------------------------------------

WoW.KNOWN_EVENTS = {}
WoW.dumpAvailable = false
do
    local f = io.open(DUMP, "r")
    if f then
        local inEvents = false
        for line in f:lines() do
            if line:match("^## Documented events") then inEvents = true
            elseif line:match("^## ") then inEvents = false
            elseif inEvents then
                local name = line:match("^([A-Z][A-Z0-9_]+)%s+%(")
                if name then WoW.KNOWN_EVENTS[name] = true end
            end
        end
        f:close()
        WoW.dumpAvailable = next(WoW.KNOWN_EVENTS) ~= nil
    end
    if not WoW.dumpAvailable then
        -- No dump (CI): the list generated from it, so validation stays
        -- exactly as strict. test_toc fails if the two ever drift.
        local fixture = io.open("tests/events-70374.txt", "r")
        assert(fixture, "tests/events-70374.txt missing: event validation needs the dump or the fixture")
        for line in fixture:lines() do
            local name = line:match("^([A-Z][A-Z0-9_]+)%s*$")
            if name then WoW.KNOWN_EVENTS[name] = true end
        end
        fixture:close()
    end
end

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------

function WoW.reset()
    WoW.cvars = {}
    WoW.frames = {}
    WoW.chat = {}
    WoW.methodsCalled = {}
    WoW.combat = false
    WoW.timers = {}
end

--------------------------------------------------------------------------------
-- Widgets
--------------------------------------------------------------------------------

local Methods = {}   -- shared implementations, by method name

local function record(w, name)
    WoW.methodsCalled[w._type .. ":" .. name] = true
end

local widgetMT = {
    __index = function(w, k)
        if type(k) ~= "string" or not k:match("^%u") then return nil end  -- fields read as nil
        return function(self, ...)
            record(self, k)
            local impl = Methods[k]
            if impl then return impl(self, ...) end
            return nil
        end
    end,
}

local function newWidget(wtype, parent, name)
    return setmetatable({ _type = wtype, _parent = parent, _shown = true, _points = {},
                          _scripts = {}, _events = {},
                          _level = parent and parent._level and (parent._level + 1) or 1,
                          _width = 0, _height = 0, _name = name }, widgetMT)
end
WoW.newWidget = newWidget

function CreateFrame(ftype, name, parent, template)
    local w = newWidget(ftype, parent, name)
    w._template = template
    if ftype == "StatusBar" then w._min, w._max, w._value = 0, 1, 0 end
    -- The template's bar, shown by default as on the client.
    if template == "UIPanelScrollFrameTemplate" then w.ScrollBar = newWidget("Slider", w) end
    -- The radio template's own label (CheckButtonTemplates.xml: parentKey "text").
    if template == "UIRadioButtonTemplate" then w.text = Methods.CreateFontString(w) end
    table.insert(WoW.frames, w)
    if parent then
        parent._children = parent._children or {}
        table.insert(parent._children, w)
    end
    if name then rawset(_G, name, w) end
    return w
end
function Methods.GetChildren(w) return unpack(w._children or {}) end

function Methods.Show(w) w._shown = true; if w._scripts.OnShow then w._scripts.OnShow(w) end end
function Methods.Hide(w)
    local was = w._shown
    w._shown = false
    if was and w._scripts.OnHide then w._scripts.OnHide(w) end
end
function Methods.SetShown(w, v) if v then Methods.Show(w) else Methods.Hide(w) end end
function Methods.IsShown(w) return w._shown end
function Methods.IsVisible(w)
    local p = w
    while p do if not p._shown then return false end; p = p._parent end
    return true
end
function Methods.SetPoint(w, ...) table.insert(w._points, { ... }) end
function Methods.ClearAllPoints(w) w._points = {} end
function Methods.GetPoint(w, i)
    local p = w._points[i or 1]
    if p then return p[1], p[2], p[3], p[4], p[5] end
end
function Methods.SetAllPoints(w, rel) table.insert(w._points, { "ALL", rel }) end
function Methods.SetSize(w, x, y) w._width, w._height = x, y end
function Methods.SetWidth(w, x) w._width = x end
function Methods.SetHeight(w, y) w._height = y end
function Methods.GetWidth(w) return w._width end
function Methods.GetHeight(w) return w._height end
-- Geometry as the client reports it: w._rect = { left, right, top, bottom }
-- in the frame's own units (nil when it has no rect), w._escale its
-- effective scale (1 by default). A test may put a secret in either.
function Methods.GetLeft(w) return w._rect and w._rect[1] end
function Methods.GetRight(w) return w._rect and w._rect[2] end
function Methods.GetTop(w) return w._rect and w._rect[3] end
function Methods.GetBottom(w) return w._rect and w._rect[4] end
function Methods.GetEffectiveScale(w) return w._escale or 1 end
function Methods.SetAlpha(w, a) if not w._gradient then w._alpha = a end end
function Methods.GetAlpha(w) return w._alpha or 1 end
function Methods.GetParent(w) return w._parent end
function Methods.SetParent(w, p) w._parent = p end
function Methods.GetFrameLevel(w) return w._level end
function Methods.SetFrameLevel(w, l) w._level = l end
function Methods.SetFrameStrata(w, s) w._strata = s end
function Methods.GetFrameStrata(w) return w._strata or "MEDIUM" end
function Methods.EnableMouse(w, v) w._mouse = v end
-- The pointer: WoW.hover[frame] = true (or a secret, as IsMouseOver's
-- SecretWhenAnchoringSecret allows) says it is over that frame.
WoW.hover = {}
function Methods.IsMouseOver(w)
    local v = WoW.hover[w]
    if v == nil then return false end
    return v
end
-- A button's enabled state (enabled until told otherwise).
function Methods.Enable(b) b._disabled = false end
function Methods.Disable(b) b._disabled = true end
function Methods.SetEnabled(b, v) b._disabled = not v end
function Methods.IsEnabled(b) return not b._disabled end
function Methods.IsMouseEnabled(w) return w._mouse == true end
function Methods.GetName(w) return w._name end
function Methods.GetDebugName(w) return w._name or ("<" .. w._type .. ">") end
function Methods.IsForbidden(w) return false end

-- Attributes: recorded; like the client, refused on a protected frame in
-- combat.
function Methods.SetAttribute(w, k, v)
    if WoW.combat and w._protected then return end
    w._attrs = w._attrs or {}
    w._attrs[k] = v
end
function Methods.GetAttribute(w, k) return w._attrs and w._attrs[k] end
function Methods.SetScript(w, name, fn) w._scripts[name] = fn end
function Methods.GetScript(w, name) return w._scripts[name] end
function Methods.HookScript(w, name, fn)
    local old = w._scripts[name]
    w._scripts[name] = function(...) if old then old(...) end; fn(...) end
end
function Methods.RegisterEvent(w, e)
    if not WoW.KNOWN_EVENTS[e] then error("Attempt to register unknown event \"" .. e .. "\"", 2) end
    w._events[e] = true
    return true
end
function Methods.UnregisterEvent(w, e) w._events[e] = nil end
function Methods.IsEventRegistered(w, e) return w._events[e] == true end

-- Regions: listed in creation order for GetRegions, as the client lists a
-- frame's textures and font strings.
local function addRegion(w, r)
    w._regions = w._regions or {}
    table.insert(w._regions, r)
    return r
end
function Methods.CreateTexture(w, name, layer, template, sublevel)
    local t = addRegion(w, newWidget("Texture", w, name))
    t._layer, t._sublevel = layer, sublevel
    if name then rawset(_G, name, t) end
    return t
end
function Methods.CreateMaskTexture(w) return newWidget("MaskTexture", w) end
function Methods.CreateFontString(w, name)
    local fs = addRegion(w, newWidget("FontString", w, name))
    if name then rawset(_G, name, fs) end
    return fs
end
function Methods.GetRegions(w) return unpack(w._regions or {}) end
function Methods.GetObjectType(w) return w._type end
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
function Methods.SetTexture(t, file) t._file = file; return true end
function Methods.SetDesaturated(t, on) t._desaturated = on == true end
function Methods.SetColorTexture(t, r, g, b, a) t._color = { r, g, b, a } end
function Methods.SetVertexColor(t, r, g, b, a) t._vertex = { r, g, b, a } end
function Methods.AddMaskTexture(t, m) t._masks = t._masks or {}; table.insert(t._masks, m) end
-- A gradient texture ignores SetAlpha on this client (GlassActionBars'
-- /gab inspect, 2026-10-13: the wash read 1.00 right after SetAlpha(0)), so
-- the stub ignores it too: only the gradient's own colours set its alpha.
function Methods.SetGradient(t, orientation, c1, c2) t._gradient = { orientation, c1, c2 }; t._alpha = nil end
function Methods.SetTextureSliceMargins(t, l, tp, r, b) t._slice = { l, tp, r, b } end
-- Animations: groups record whether they play.
function Methods.CreateAnimationGroup(w) return newWidget("AnimationGroup", w) end
function Methods.CreateAnimation(ag, atype) return newWidget(atype or "Animation", ag) end
function Methods.Play(ag) ag._playing = true end
function Methods.Stop(ag) ag._playing = false end
function Methods.IsPlaying(ag) return ag._playing == true end

-- FontString: the client formats natively and accepts secrets. With any
-- secret argument, keep the arguments unformatted instead of calling
-- string.format (which would throw on the proxy).
-- An EditBox runs its OnTextChanged on SetText, as the client does.
function Methods.SetText(fs, text)
    fs._text = text
    if fs._type == "EditBox" and fs._scripts.OnTextChanged then fs._scripts.OnTextChanged(fs, false) end
end
-- A SimpleHTML colours per text type ("P", "H1", ...), its first argument.
function Methods.SetTextColor(fs, ...)
    if fs._type == "SimpleHTML" then
        local textType, r, g, b, a = ...
        assert(type(textType) == "string", "SimpleHTML:SetTextColor needs a text type first")
        fs._htmlColor = fs._htmlColor or {}
        fs._htmlColor[textType] = { r, g, b, a }
        return
    end
    local r, g, b, a = ...
    fs._textColor = { r, g, b, a }
end
function Methods.GetTextColor(fs, textType)
    local c
    if fs._type == "SimpleHTML" then
        assert(type(textType) == "string", "SimpleHTML:GetTextColor needs a text type")
        c = fs._htmlColor and fs._htmlColor[textType]
    else
        c = fs._textColor
    end
    c = c or { 1, 1, 1, 1 }
    return c[1], c[2], c[3], c[4]
end
function Methods.GetFontObject(fs) return fs._fontObject end
-- An EditBox's selection colour.
function Methods.SetHighlightColor(e, r, g, b, a) e._highlight = { r, g, b, a } end
function Methods.GetHighlightColor(e)
    local c = e._highlight or { 1, 1, 1, 1 }
    return c[1], c[2], c[3], c[4]
end
function Methods.GetText(fs) return fs._text end
function Methods.SetFormattedText(fs, fmt, ...)
    local n = select("#", ...)
    for i = 1, n do
        if secrets[(select(i, ...))] then fs._text = { secretFormat = fmt, n = n }; return end
    end
    fs._text = string.format(fmt, ...)
end
function Methods.SetFont(fs, file, size, flags) fs._font = { file, size, flags }; return true end
function Methods.SetFontObject(fs, obj) fs._fontObject = obj end
function Methods.GetFont(fs)
    local f = fs._font or { "Fonts\FRIZQT__.TTF", 10, "" }
    return f[1], f[2], f[3]
end
function Methods.GetFontString(b) return b._fontString end
-- CheckButton.
function Methods.SetChecked(b, v) b._checked = v and true or false end
function Methods.GetChecked(b) return b._checked == true end
-- StatusBar.
function Methods.SetMinMaxValues(b, lo, hi) b._min, b._max = lo, hi end
function Methods.SetStatusBarColor(b, r, g, bl, a) b._color = { r, g, bl, a } end
function Methods.GetValue(b) return b._value end
function Methods.SetValue(b, v) b._value = v end
function Methods.SetStatusBarTexture(b, file)
    b._fill = b._fill or newWidget("Texture", b)
    b._fill._file = file
    return true
end
function Methods.GetStatusBarTexture(b) return b._fill end

WoW.reset()

--------------------------------------------------------------------------------
-- Globals
--------------------------------------------------------------------------------

UIParent = newWidget("Frame", nil, "UIParent")
UIParent._level = 0

function print(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
    table.insert(WoW.chat, table.concat(parts, " "))
end

SlashCmdList = {}
Enum = { UITextureSliceMode = { Stretched = 0, Tiled = 1 },
    -- Measured by Apotheca on 70291 (its docs/FOREVER-PROBE.md).
    EditModeActionBarSetting = { Orientation = 0, NumRows = 1, NumIcons = 2, IconSize = 3, IconPadding = 4,
        VisibleSetting = 5, HideBarArt = 6, DeprecatedSnapToSide = 7, HideBarScrolling = 8, AlwaysShowButtons = 9 } }
-- Errors handed to the client's error handler (a Lua error popup in game).
WoW.errors = {}
function geterrorhandler() return function(err) table.insert(WoW.errors, err) end end
function CreateColor(r, g, b, a) return { r = r, g = g, b = b, a = a } end
date = os.date
time = os.time
function GetTime() return WoW.now or 0 end
function GetServerTime() return time() end
function GetBuildInfo() return "1.60.1", "70374", "Oct 12 2026", 16001 end
function InCombatLockdown() return WoW.combat == true end
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

-- Quick Keybind mode (Blizzard_QuickKeybind): WoW.quickKeybind.
function KeybindFrames_InQuickKeybindMode() return WoW.quickKeybind == true end

-- The client's secure hook replaces t[name] with a wrapper: the sanctioned way
-- to hook a Blizzard method. WoW.hooked records it, so the "no field written"
-- checks can tell it from a field the addon wrote.
WoW.hooked = {}
function hooksecurefunc(t, name, fn)
    if type(t) == "string" then t, name, fn = _G, t, name end
    WoW.hooked[t] = WoW.hooked[t] or {}
    WoW.hooked[t][name] = true
    local orig = rawget(t, name) or t[name]
    rawset(t, name, function(...)
        local r = { orig(...) }
        fn(...)
        return unpack(r)
    end)
end

-- Timers keep their delay: WoW.flushTimers(upTo) runs those due within upTo
-- seconds (all when nil) and keeps the rest.
C_Timer = { After = function(s, fn) table.insert(WoW.timers, { s = s, fn = fn }) end }
function WoW.flushTimers(upTo)
    local run, keep = {}, {}
    for _, t in ipairs(WoW.timers) do
        if upTo == nil or t.s <= upTo then run[#run + 1] = t else keep[#keep + 1] = t end
    end
    WoW.timers = keep
    for _, t in ipairs(run) do t.fn() end
end

--------------------------------------------------------------------------------
-- GameTooltip: its owner and lines, as text. SetOwner starts it over.
--------------------------------------------------------------------------------

GameTooltip = newWidget("GameTooltip", UIParent, "GameTooltip")
GameTooltip._lines = {}
function Methods.SetOwner(t, owner) t._owner, t._lines = owner, {} end
function Methods.IsOwned(t, f) return t._owner == f end
function Methods.AddLine(t, text) table.insert(t._lines, text) end
function Methods.SetText(t, text, ...)
    if t._type == "GameTooltip" then t._lines = { text } else t._text = text end
end
function Methods.IsTruncated(fs) return fs._truncated == true end
function GameTooltip_Hide() GameTooltip:Hide() end

--------------------------------------------------------------------------------
-- The action bars (Blizzard_ActionBar, loaded before any addon), as the
-- forever branch of wow-ui-source declares them: ActionButtonTemplate's
-- parentKeys (Mainline/ActionButtonTemplate.xml), the mixin methods the skin
-- hooks (copied onto each frame, as Mixin does), and the bars. Buttons are
-- protected: WoW.violations records any change the client would refuse in
-- combat.
--------------------------------------------------------------------------------

WoW.violations = {}
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
    rawset(b, "UpdateButtonArt", function(self)
        self.NormalTexture._file = "UI-HUD-ActionBar-IconFrame"
        self.PushedTexture._file = "UI-HUD-ActionBar-IconFrame-Down"
        self.PushedTexture._blend = nil
        self._artUpdates = (self._artUpdates or 0) + 1
    end)
    return b
end
WoW.actionButton = actionButton
function Methods.SetBlendMode(t, mode) t._blend = mode end

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
function Methods.GetID(w) return w._id or 0 end
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
CharacterMicroButton.Background = Methods.CreateTexture(CharacterMicroButton, nil, "BACKGROUND")
OverrideActionBar = CreateFrame("Frame", "OverrideActionBar", UIParent)

--------------------------------------------------------------------------------
-- Driving
--------------------------------------------------------------------------------

-- Fire an event at every frame registered for it. Errors are NOT caught: a
-- handler that throws fails the test.
function WoW.fire(event, ...)
    for _, w in ipairs(WoW.frames) do
        local handler = w._scripts.OnEvent
        if handler and w._events[event] then handler(w, event, ...) end
    end
end

-- Every event any frame registered, fired once with no payload: strict
-- globals only catch code that actually runs.
function WoW.fireAllRegistered()
    local seen = {}
    for _, w in ipairs(WoW.frames) do
        for e in pairs(w._events) do seen[e] = true end
    end
    for e in pairs(seen) do WoW.fire(e) end
end

-- One rendered frame: the clock (GetTime) moves on by `elapsed`, then OnUpdate
-- runs on every visible frame.
function WoW.tick(elapsed)
    elapsed = elapsed or 0.02
    WoW.now = (WoW.now or 0) + elapsed
    local list = {}
    for _, w in ipairs(WoW.frames) do list[#list + 1] = w end
    for _, w in ipairs(list) do
        local fn = w._scripts.OnUpdate
        if fn and Methods.IsVisible(w) then fn(w, elapsed) end
    end
end


-- Strict globals: any read of an undefined global is an error, except the
-- addon's own globals that are legitimately nil before first assignment.
local allowNil = { GlassActionBars = true, GlassActionBarsDB = true, GABProbeDB = true,
    LibStub = true }
-- Client string alias (in the dump's _G walk); LibStub's version check uses it.
strmatch = string.match
setmetatable(_G, { __index = function(_, k)
    if allowNil[k] then return nil end
    error("read of undefined global '" .. tostring(k) .. "' (not stubbed: is it in the API dump?)", 2)
end })
