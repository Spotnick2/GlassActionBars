-- Buttons.lua: the glass skin on Blizzard's own buttons (docs/PLAN.md, Phase 1).
--
-- One visual builder shared by every family (Build), and a family adapter
-- per family: which of Blizzard's writers to post-hook, and how to read
-- whether a slot holds something.
--
-- The contract (CLAUDE.md): never own an action button, never write a field
-- onto one, never replace one of its methods. Everything here is a method
-- call on a declared region, a hooksecurefunc, or a frame of our own. State
-- lives in `skins`, a weak table keyed by the button.
--
-- What a skinned button looks like:
--   body   our frame one level UNDER the button: the glass body (tint, wash)
--          behind the icon, seen on an empty slot and around the icon's
--          rounded corners
--   rim    the body's g.top raised to one level ABOVE the button: the thin
--          glass rim over the icon's edge. Bright on a slot with an action,
--          faint on an empty one. The icon itself is never moved: the stock
--          cooldowns are anchored inside it.
--   art    Blizzard's frame art (NormalTexture, SlotArt, SlotBackground)
--          faded with SetAlpha(0), never hidden; the pushed texture becomes
--          a bright rim. UpdateButtonArt sets both atlases again, so they are
--          re-applied after it.
-- Left to Blizzard: the checked texture's alpha, the proc glow, the range
-- and usable tints, every cooldown. Secret values stay on its own path.

GlassActionBars = GlassActionBars or {}
local GAB = GlassActionBars
local API = GAB.API
local Glass = GAB.Glass
local Buttons = {}
GAB.Buttons = Buttons

local skins = setmetatable({}, { __mode = "k" })   -- button -> state

Buttons.SIZE = "small"        -- thin_small under the clean preset
Buttons.EMPTY_RIM = 0.35      -- the rim's strength on an empty slot, as a fraction of a full one
Buttons.HIGHLIGHT = 0.4       -- the hover glow, softened as LibGlass's Pill does

local function font()
    local f = Glass.FONTS[Glass.fontKey] or Glass.FONTS.arial
    return f.file, f.bump
end

-- Text: the hotkey (top right) and the count (bottom right) in the glass
-- font, outlined; Blizzard keeps anchoring, colouring and filling them.
local function styleText(s)
    local r = s.regions
    local file, bump = font()
    if r.hotkey then
        r.hotkey:SetFont(file, (s.small and 10 or 12) + bump, "OUTLINE")
        r.hotkey:SetAlpha(GAB.db.showHotkeys and 1 or 0)
    end
    if r.count then r.count:SetFont(file, (s.small and 11 or 14) + bump, "OUTLINE") end
    if r.name then r.name:SetAlpha(GAB.db.showMacroNames and 1 or 0) end
end

local function paintRim(s)
    local f = s.occupied and 1 or Buttons.EMPTY_RIM
    s.g.rim:SetAlpha(Glass.STYLE.rimAlpha * f)
    s.g.dark:SetAlpha(f)
end

-- The body under the button, the rim over it. Run again whenever Blizzard
-- may have changed the button's level.
local function relevel(s)
    local level = s.button:GetFrameLevel()
    s.body:SetFrameLevel(math.max(0, level - 1))
    s.g.top:SetFrameLevel(level + 1)
end

-- Blizzard's frame art faded, the pushed look made ours. Run again after
-- every UpdateButtonArt.
local function styleArt(s)
    local r = s.regions
    for _, key in ipairs({ "normal", "slotArt", "slotBackground" }) do
        if r[key] then r[key]:SetAlpha(0) end
    end
    local p = r.pushed
    if p then
        local S = Glass.SIZES[s.g.size]
        p:SetTexture(Glass.MEDIA .. S.rim)
        p:SetTextureSliceMargins(S.rimMargin, S.rimMargin, S.rimMargin, S.rimMargin)
        p:ClearAllPoints()
        p:SetAllPoints(s.button)
        p:SetVertexColor(1, 1, 1, 1)
        p:SetBlendMode("ADD")
    end
end

-- The glass on one button. `regions` names its parts: icon, cooldown,
-- count, hotkey, name, normal, pushed, highlight, slotArt, slotBackground
-- (any may be absent). Returns the button's state; a second call returns
-- the same one.
function Buttons.Build(button, regions)
    if skins[button] then return skins[button] end
    local body = CreateFrame("Frame", nil, button)
    body:SetAllPoints(button)
    body:EnableMouse(false)
    local g = Glass.Apply(body, Buttons.SIZE)
    g.shadow:SetAlpha(0)   -- it would spill onto the next button (LibGlass Pill's rule)
    g.grain:SetAlpha(0)
    local s = { button = button, body = body, g = g, regions = regions or {}, occupied = true,
                small = button:GetWidth() < 40 }
    skins[button] = s
    relevel(s)
    styleArt(s)
    styleText(s)
    paintRim(s)
    if s.regions.highlight then s.regions.highlight:SetAlpha(Buttons.HIGHLIGHT) end
    GAB.Theme.Register(g)
    return s
end

function Buttons.IsSkinned(button) return skins[button] ~= nil end

-- A nil `occupied` (unreadable: secret, or the reader failed) keeps the last state.
function Buttons.SetOccupied(button, occupied)
    local s = skins[button]
    if not s or occupied == nil then return end
    s.occupied = occupied == true
    paintRim(s)
end

-- Settings changed: hotkeys and macro names shown or not.
function Buttons.RefreshText()
    for _, s in pairs(skins) do API.Try("skin:text", styleText, s) end
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
            if st then API.Try("skin:art", function() styleArt(st); relevel(st) end) end
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

Buttons._test = { skins = skins, styleArt = styleArt }
