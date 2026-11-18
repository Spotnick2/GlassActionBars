-- Buttons.lua: the glass skin on Blizzard's own buttons (docs/PLAN.md, Phase 1).
--
-- The skin itself is LibGlass's (r13, Glass.Button: LibGlass#46, moved there
-- from here so Apotheca#41 can wear it too). What stays here is GAB's: the
-- family adapters (which of Blizzard's writers to post-hook, and how to read
-- whether a slot holds something), the look the skin reads (Look.lua, the
-- theme's tint, /gab tune's saved numbers, the hotkey and macro-name
-- settings), and the presets.
--
-- The contract (CLAUDE.md): never own an action button, never write a field
-- onto one, never replace one of its methods. Glass.Button keeps that: a
-- frame of its own under the button and one over it, method calls on the
-- regions named here, HookScript on OnEnter / OnLeave / OnHide /
-- OnMouseDown, its state in a weak table. Ours lives in `skins`, the
-- library's handle by button.
--
-- What a skinned button looks like:
--   body   one level UNDER the button: the glass body (tint, wash) behind
--          the icon, seen on an empty slot and around the icon's corners
--   rim    one level ABOVE the button: the thin glass rim over the icon's
--          edge, bright on a slot with an action, faint on an empty one
--          (Pearl: a recessed socket on a frosted empty one, a reflection on
--          a filled one). The icon is never moved: the stock cooldowns are
--          anchored inside it.
--   art    Blizzard's frame art (NormalTexture, SlotArt, SlotBackground)
--          faded with SetAlpha(0), never hidden; the pushed texture becomes
--          a bright rim. UpdateButtonArt sets both atlases again, so they are
--          re-applied after it (Glass.RestyleButton, allowed in combat).
-- Left to Blizzard: the checked texture's alpha, the proc glow, the range
-- and usable tints, every cooldown. Secret values stay on its own path.

GlassActionBars = GlassActionBars or {}
local GAB = GlassActionBars
local API = GAB.API
local Glass = GAB.Glass   -- the instance, reached once built (PLAYER_LOGIN)
local Buttons = {}
GAB.Buttons = Buttons

-- The library itself, for what doesn't depend on the material: it is loaded
-- by now (the TOC's first line), the instance isn't until PLAYER_LOGIN, and
-- the saved look is checked at ADDON_LOADED.
local LIB = LibStub("LibGlass-1.0")

local skins = setmetatable({}, { __mode = "k" })   -- button -> LibGlass's skin

-- The look's numbers, tuned live in game with /gab tune (saved in
-- GlassActionBarsDB.tune). Their defaults are the library's, by the material
-- (Glass.ButtonDefault: Pearl has its own); these are /gab tune's words.
Buttons.TUNE = {
    rim = "the rim's alpha on a slot with an action (near-full at 1)",
    empty = "the rim on an empty slot, as a fraction of a full one",
    dark = "the dark inner line under the rim",
    wash = "the body's top-down haze, as a fraction of the theme's",
    body = "the body's tint alpha, as a fraction of the theme's",
    frostGrey = "the frosted empty slot's fill: 0 black, 1 white",
    frostAlpha = "the frosted empty slot's fill strength",
    frostRim = "the frosted empty slot's rim, as a fraction of an empty slot's",
    gloss = "Pearl: the reflection over a filled slot's icon",
    socketShade = "Pearl: a frosted empty slot's dark upper inset",
}
Buttons.TUNE_ORDER = { "rim", "empty", "dark", "wash", "body", "frostGrey", "frostAlpha", "frostRim", "gloss", "socketShade" }

-- The built-in value for this material. After PLAYER_LOGIN only.
function Buttons.TuneDefault(key)
    return Glass.ButtonDefault(key)
end

-- The player's saved number, or nil (the skin then takes the default).
local function savedTune(key)
    local saved = GAB.db and type(GAB.db.tune) == "table" and GAB.db.tune[key]
    if type(saved) == "number" then return saved end
    return nil
end

function Buttons.Tune(key)
    local v = savedTune(key)
    if v ~= nil then return v end
    return Buttons.TuneDefault(key)
end

-- Button feedback (#34, from the owner's Final Fantasy XIV reference): how a
-- button answers the pointer and a press, and how an empty slot shows. Each
-- is a setting (GlassActionBarsDB, the keys below); a preset sets all three.
-- Glass is the default: Blizzard's glow, the flash, frosted empty slots.
-- (Key text moved above the buttons was tried and taken out: on stacked bars
-- it sat on the row above, session 5.) The choices are the library's.
Buttons.LOOK = LIB.BUTTON.LOOK
Buttons.LOOK_ORDER = { "hover", "press", "emptySlots" }
Buttons.PRESETS = {
    glass = { hover = "glow", press = "flash", emptySlots = "frosted" },
    soft = { hover = "halo", press = "ripple", emptySlots = "frosted" },
    minimal = { hover = "off", press = "flash", emptySlots = "hidden" },
}
Buttons.PRESET_ORDER = { "glass", "soft", "minimal" }

function Buttons.ValidLook(key, v)
    for _, x in ipairs(Buttons.LOOK[key] or {}) do
        if x == v then return true end
    end
    return false
end

-- The value in effect: the player's, else Glass UI's while following, else
-- the Glass preset's (Look.lua).
local function look(key)
    return GAB.Look.Get(key)
end
Buttons.Look = look

-- The preset the three settings match, or "custom".
function Buttons.Preset()
    for _, name in ipairs(Buttons.PRESET_ORDER) do
        local all = true
        for _, k in ipairs(Buttons.LOOK_ORDER) do
            if look(k) ~= Buttons.PRESETS[name][k] then all = false end
        end
        if all then return name end
    end
    return "custom"
end

-- The look as the skin asks for it, each time it paints or a hook fires.
-- The tint: the theme's colour, nil for clear glass (the material as built,
-- where a frosted empty slot shows its own fill) and for the class colour
-- not readable yet (Theme.Retry paints again).
local function skinLook(key)
    if key == "hover" or key == "press" or key == "emptySlots" then return look(key) end
    if key == "tint" then return (GAB.Theme.ButtonTint()) end
    if key == "tintWash" then return select(2, GAB.Theme.ButtonTint()) end
    if key == "showHotkey" then return GAB.db.showHotkeys and true or false end
    if key == "showName" then return GAB.db.showMacroNames and true or false end
    return nil
end

-- GAB's region names, as Glass.Button takes them: Blizzard's frame art
-- under `fade`; the cooldown is never the skin's (an unknown role throws).
local ROLES = { icon = true, pushed = true, highlight = true, hotkey = true, count = true, name = true }
local FADES = { normal = true, slotArt = true, slotBackground = true }

local function libRegions(regions)
    local out, fade = {}, nil
    for key, r in pairs(regions or {}) do
        if ROLES[key] then
            out[key] = r
        elseif FADES[key] then
            fade = fade or {}
            fade[key] = r
        end
    end
    out.fade = fade
    return out
end
Buttons.LibRegions = libRegions

-- The glass on one button. `regions` names its parts: icon, cooldown,
-- count, hotkey, name, normal, pushed, highlight, slotArt, slotBackground
-- (any may be absent). `opts.maskIcon`: round the icon to the glass's shape
-- (#46), for icons that aren't Blizzard's (theirs have the template's
-- IconMask). `opts.inset`: the glass that many units inside the button on
-- each side (the micro buttons overlap, #57). Out of combat (the library
-- refuses a build in one). Returns the skin, or nil and why ("combat";
-- "skinned": another addon's glass holds the button); a second call returns
-- the same skin. Each step that fails is recorded for /gab failures under
-- skin:<step>:<button>.
function Buttons.Build(button, regions, opts)
    if skins[button] then return skins[button] end
    local name = API.Plain(button:GetName()) or "?"
    local s, why = Glass.Button(button, libRegions(regions), {
        look = skinLook,
        tune = savedTune,
        onError = function(step, msg) API.Fail("skin:" .. step .. ":" .. name, msg) end,
        maskIcon = opts and opts.maskIcon and true or nil,
        inset = opts and tonumber(opts.inset) or nil,
    })
    if not s then
        API.Fail("skin:build:" .. name, why)
        return nil, why
    end
    skins[button] = s
    return s
end

function Buttons.IsSkinned(button) return skins[button] ~= nil end

-- Blizzard set a skinned button's art again (a family's own writer, e.g. the
-- bag slots' UpdateTextures, or UpdateButtonArt): fade it and take the
-- pressed look back. Safe in combat.
function Buttons.Restyle(button)
    local s = skins[button]
    if s then API.Try("skin:art", Glass.RestyleButton, s) end
end

-- A skinned button's skin (LibGlass's handle: button, body, g, regions,
-- occupied, small, failures), read-only, for Inspect.lua; and every one in turn.
function Buttons.State(button) return skins[button] end
function Buttons.Each(fn) for _, s in pairs(skins) do fn(s) end end

-- A nil `occupied` (unreadable: secret, or the reader failed) keeps the last state.
function Buttons.SetOccupied(button, occupied)
    local s = skins[button]
    if not s or occupied == nil or API.IsSecret(occupied) then return end
    API.Try("skin:empty", Glass.SetButtonEmpty, s, occupied ~= true)
end

-- Every button repainted: the look, a tune, the theme or a text setting
-- changed. Colours, alphas and fonts only, safe in combat (Glass UI's
-- LookChanged may come in a fight). Theme.Refresh calls it.
function Buttons.Refresh()
    if GAB.GlassBuilt() then API.Try("skin:refresh", Glass.RefreshButtons) end
end
Buttons.RefreshFeedback = Buttons.Refresh
Buttons.RefreshText = Buttons.Refresh

-- /gab tune: a number changed. The buttons, and GAB's other surfaces (the
-- micro menu's pill reads the wash and body tunes).
function Buttons.RefreshLook()
    GAB.Theme.Refresh()
end

--------------------------------------------------------------------------------
-- Family adapters
--------------------------------------------------------------------------------

-- The parts of a button made from ActionButtonTemplate (the action, stance
-- and pet buttons all are). Template parentKeys, read, never written.
local function stockRegions(b)
    return {
        icon = b.icon, cooldown = b.cooldown, count = b.Count, hotkey = b.HotKey, name = b.Name,
        normal = b.NormalTexture or b:GetNormalTexture(), pushed = b.PushedTexture or b:GetPushedTexture(),
        highlight = b.HighlightTexture or b:GetHighlightTexture(),
        slotArt = b.SlotArt, slotBackground = b.SlotBackground,
    }
end

-- Whether a slot holds something: true, false, or nil when it can't be read.
local function truth(ok, v)
    if not ok or API.IsSecret(v) then return nil end
    return v ~= nil and v ~= false
end
local READ = {
    action = function(b) return truth(pcall(HasAction, b.action)) end,
    stance = function(b) return truth(pcall(GetShapeshiftFormInfo, b.index or b:GetID())) end,
    pet = function(b) return truth(pcall(GetPetActionInfo, b.index or b:GetID())) end,
}
Buttons.READ = READ

local function skinStock(button)
    local s = Buttons.Build(button, stockRegions(button))
    if type(button.UpdateButtonArt) == "function" then
        hooksecurefunc(button, "UpdateButtonArt", function(self)
            local st = skins[self]
            if st then API.Try("skin:art", Glass.RestyleButton, st) end
        end)
    end
    return s
end

local function eachButton(prefix, n, fn)
    for i = 1, n do
        local b = _G[prefix .. i]
        if b and not skins[b] then API.Try("skin:" .. prefix .. i, fn, b) end
    end
end

-- Action buttons: the main bar and the seven extra bars. Each button's own
-- Update says when its slot changed. (UpdateHotkeys sets the hotkey's text,
-- size and anchor, never its font, so the font set once holds.)
local function skinActionBars()
    local function onUpdate(self) Buttons.SetOccupied(self, READ.action(self)) end
    for _, prefix in ipairs(ActionButtonUtil.ActionBarButtonNames) do
        eachButton(prefix, NUM_ACTIONBAR_BUTTONS, function(b)
            skinStock(b)
            if type(b.Update) == "function" then hooksecurefunc(b, "Update", onUpdate) end
            onUpdate(b)
        end)
    end
end

-- Stance and pet buttons: their bar refreshes them all at once
-- (StanceBar:UpdateState, PetActionBar:Update), so the bar is hooked.
local function skinFamily(prefix, n, bar, method, read)
    local list = {}
    eachButton(prefix, n, function(b)
        skinStock(b)
        list[#list + 1] = b
    end)
    local function refresh()
        for _, b in ipairs(list) do Buttons.SetOccupied(b, read(b)) end
    end
    if bar and type(bar[method]) == "function" then hooksecurefunc(bar, method, refresh) end
    refresh()
end

local started = false
local function skinAll()
    if started then return end
    started = true
    API.Try("skin:action", skinActionBars)
    API.Try("skin:stance", skinFamily, "StanceButton", 10, StanceBar, "UpdateState", READ.stance)
    API.Try("skin:pet", skinFamily, "PetActionButton", NUM_PET_ACTION_SLOTS, PetActionBar, "Update", READ.pet)
end

-- At PLAYER_LOGIN. Our frames go on Blizzard's protected buttons, so a login
-- in combat (a /reload mid-fight) waits for the fight to end.
local waiter
function Buttons.Start()
    if GAB.db.skin == false then return end
    if not API.InCombat() then return skinAll() end
    if waiter then return end
    waiter = CreateFrame("Frame")
    waiter:SetScript("OnEvent", function(self, event)
        API.NoteCombat(event)
        if API.InCombat() then return end
        self:UnregisterAllEvents()
        skinAll()
    end)
    API.RegisterEvents(waiter, { "PLAYER_REGEN_ENABLED" }, "skin")
end

Buttons._test = { skins = skins }
