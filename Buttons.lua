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
Buttons.HIGHLIGHT = 0.4       -- the hover glow, softened as LibGlass's Pill does

-- The look's numbers, tuned live in game with /gab tune (saved in
-- GlassActionBarsDB.tune), then baked in here. The first pass read as
-- frosted tiles with no outline and a heavy dark frame round the icons; these
-- are the owner's tuned values (2026-10-13) on our own rim texture: a nearly
-- clear body and a crisp light rim, the empty slots' at three quarters.
Buttons.TUNE = {
    rim = { 0.85, "the rim's alpha on a slot with an action (ButtonRim, near-full at 1)" },
    empty = { 0.75, "the rim on an empty slot, as a fraction of a full one" },
    dark = { 0.15, "the dark inner line under the rim" },
    wash = { 0.04, "the body's top-down haze, as a fraction of the theme's" },
    body = { 0.25, "the body's tint alpha, as a fraction of the theme's" },
    -- The frosted empty slot (#34), dialled in game against the owner's reference.
    frostGrey = { 0.9, "the frosted empty slot's fill: 0 black, 1 white" },
    frostAlpha = { 0.08, "the frosted empty slot's fill strength" },
    frostRim = { 0.35, "the frosted empty slot's rim, as a fraction of an empty slot's" },
    -- Pearl's face (#44); nothing draws them on Clean and Classic.
    gloss = { 0, "Pearl: the reflection over a filled slot's icon" },
    socketShade = { 0, "Pearl: a frosted empty slot's dark upper inset" },
}
Buttons.TUNE_ORDER = { "rim", "empty", "dark", "wash", "body", "frostGrey", "frostAlpha", "frostRim", "gloss", "socketShade" }

-- Pearl's own defaults (#44, the owner's FFXIV reference, 2026-10-19), by the
-- material built at login (Look.lua); Clean and Classic keep TUNE's. A saved
-- /gab tune wins over both. The gloss was chosen in game (0.16 and 0.22 tried;
-- 0.08 kept with the soft highlight).
Buttons.PEARL = { rim = 0.70, dark = 0.20, frostGrey = 0.40, frostAlpha = 0.22,
                  frostRim = 0.60, gloss = 0.08, socketShade = 0.18 }

function Buttons.TuneDefault(key)
    if GAB.GlassPreset == "pearl" and Buttons.PEARL[key] ~= nil then return Buttons.PEARL[key] end
    return Buttons.TUNE[key][1]
end

function Buttons.Tune(key)
    local saved = GAB.db and type(GAB.db.tune) == "table" and GAB.db.tune[key]
    if type(saved) == "number" then return saved end
    return Buttons.TuneDefault(key)
end

-- Button feedback (#34, from the owner's Final Fantasy XIV reference): how a
-- button answers the pointer and a press, and how an empty slot shows. Each
-- is a setting (GlassActionBarsDB, the keys below); a preset sets all three.
-- Glass is the default: Blizzard's glow, the flash, frosted empty slots. (Key text moved above the buttons was tried and
-- taken out: on stacked bars it sat on the row above, session 5.)
Buttons.LOOK = {
    hover = { "off", "glow", "halo" },             -- glow: Blizzard's highlight, softened
    press = { "off", "flash", "ripple" },          -- flash: the pushed rim; ripple: plus a ripple on a click
    emptySlots = { "hidden", "faint", "half", "full", "frosted" },
}
Buttons.LOOK_ORDER = { "hover", "press", "emptySlots" }
Buttons.PRESETS = {
    glass = { hover = "glow", press = "flash", emptySlots = "frosted" },
    soft = { hover = "halo", press = "ripple", emptySlots = "frosted" },
    minimal = { hover = "off", press = "flash", emptySlots = "hidden" },
}
Buttons.PRESET_ORDER = { "glass", "soft", "minimal" }
Buttons.EMPTY = { hidden = 0, faint = 0.25, half = 0.5, full = 1 }   -- an empty slot's glass (frosted: the frostRim tune)
-- Frosted (the reference's empty slots, owner 2026-10-19): a pale neutral fill
-- in place of the theme's tint, so the slot reads as a light tile over any
-- background, its rim softer (the factor above).
-- The fill: a cool near-neutral grey (frostGrey, its blue a little higher)
-- at frostAlpha (8% after the owner's first look: 16% was too strong).
function Buttons.Frost()
    local g = Buttons.Tune("frostGrey")
    if GAB.GlassPreset == "pearl" then return { g, g, g, Buttons.Tune("frostAlpha") } end
    return { g, math.min(1, g + 0.01), math.min(1, g + 0.04), Buttons.Tune("frostAlpha") }
end
-- The halo: Media/ButtonHalo (Tools/make_rim.py), 16 px of padding round the
-- button's boundary, 9-sliced at 24; a warm white; the reference's ~0.1 s in.
Buttons.HALO = { file = "ButtonHalo", pad = 16, margin = 24, color = { 1, 0.94, 0.8 }, fadeIn = 0.1, fadeOut = 0.15 }
Buttons.RIPPLE = { file = "ButtonRipple", mask = "ButtonMask", duration = 0.3, from = 0.3, to = 1.6, alpha = 0.6 }

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

-- An empty slot's glass, as a factor (1 on a slot with an action).
local function emptyFactor(s)
    if s.occupied then return 1 end
    local mode = look("emptySlots")
    if mode == "frosted" then return Buttons.Tune("frostRim") end
    return Buttons.EMPTY[mode]
end

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

-- The rim, and Pearl's face (#44): a frosted empty slot shows the recessed
-- socket instead of the raised rim, a filled one the reflection.
local function paintRim(s)
    local f = s.occupied and 1 or Buttons.Tune("empty") * emptyFactor(s)
    local recessed = s.socketRim and not s.occupied and look("emptySlots") == "frosted"
    s.g.rim:SetAlpha(recessed and 0 or Buttons.Tune("rim") * f)
    s.g.dark:SetAlpha(recessed and 0 or Buttons.Tune("dark") * f)
    if s.socketRim then
        s.socketRim:SetAlpha(recessed and Buttons.Tune("rim") * f or 0)
        s.socketShade:SetAlpha(recessed and Buttons.Tune("socketShade") * emptyFactor(s) or 0)
        s.gloss:SetAlpha(s.occupied and Buttons.Tune("gloss") or 0)
    end
end

-- Hover and press effects run on one driver, its OnUpdate set only while a
-- halo fades or a ripple swells. Everything here is on our own regions.
local driver = CreateFrame("Frame")
local fading, rippling = {}, {}   -- state -> the halo's target alpha; state -> the ripple's elapsed time

local function step(_, elapsed)
    for s, target in pairs(fading) do
        local a = s.halo:GetAlpha()
        local d = elapsed / (target > a and Buttons.HALO.fadeIn or Buttons.HALO.fadeOut)
        a = target > a and math.min(target, a + d) or math.max(target, a - d)
        s.halo:SetAlpha(a)
        if a == target then fading[s] = nil end
    end
    local R = Buttons.RIPPLE
    for s, t in pairs(rippling) do
        t = t + elapsed
        local p = math.min(1, t / R.duration)
        local size = s.rippleBase * (R.from + (R.to - R.from) * p)
        s.ripple:SetSize(size, size)
        s.ripple:SetAlpha(R.alpha * (1 - p))
        if p >= 1 then
            rippling[s] = nil
            s.ripple:Hide()
        else
            rippling[s] = t
        end
    end
    if not next(fading) and not next(rippling) then driver:SetScript("OnUpdate", nil) end
end

local function fadeTo(s, target)
    if not s.halo or (fading[s] == nil and s.halo:GetAlpha() == target) then return end
    fading[s] = target
    driver:SetScript("OnUpdate", step)
end

local function clearEffects(s)
    fading[s], rippling[s] = nil, nil
    if s.halo then s.halo:SetAlpha(0) end
    if s.ripple then s.ripple:Hide() end
end

-- Blizzard's highlight: softened for glow, off when the halo (or nothing) answers.
local function applyHighlight(s)
    local h = s.regions.highlight
    if h then h:SetAlpha(look("hover") == "glow" and Buttons.HIGHLIGHT or 0) end
end

local function makeHalo(s)
    local H = Buttons.HALO
    local t = s.g.top:CreateTexture(nil, "ARTWORK", nil, 7)
    t:SetTexture(GAB.MEDIA .. H.file)
    t:SetTextureSliceMargins(H.margin, H.margin, H.margin, H.margin)
    local modes = Enum and Enum.UITextureSliceMode
    t:SetTextureSliceMode((modes and modes.Stretched) or 0)
    t:SetPoint("TOPLEFT", s.body, "TOPLEFT", -H.pad, H.pad)
    t:SetPoint("BOTTOMRIGHT", s.body, "BOTTOMRIGHT", H.pad, -H.pad)
    t:SetVertexColor(H.color[1], H.color[2], H.color[3], 1)
    t:SetBlendMode("ADD")
    t:SetAlpha(0)
    s.halo = t
end

-- A click: the ripple from the pointer, inside the glass's rounded square
-- (the body: the button, or inside it for an inset skin). One ripple per
-- button, made on its first click.
local function ripple(s)
    if look("press") ~= "ripple" then return end
    local b, R = s.body, Buttons.RIPPLE
    if not s.ripple then
        local mask = s.g.top:CreateMaskTexture()
        mask:SetTexture(GAB.MEDIA .. R.mask, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        mask:SetAllPoints(b)
        local t = s.g.top:CreateTexture(nil, "OVERLAY")
        t:SetTexture(GAB.MEDIA .. R.file)
        t:SetBlendMode("ADD")
        t:AddMaskTexture(mask)
        t:Hide()
        s.ripple = t
    end
    local w = API.Plain(b:GetWidth())
    s.rippleBase = type(w) == "number" and w > 0 and w or 36
    local x, y = GetCursorPosition()
    x, y = API.Plain(x), API.Plain(y)
    local es, l, bt = API.Plain(b:GetEffectiveScale()), API.Plain(b:GetLeft()), API.Plain(b:GetBottom())
    s.ripple:ClearAllPoints()
    if type(x) == "number" and type(y) == "number" and type(es) == "number" and es > 0
            and type(l) == "number" and type(bt) == "number" then
        s.ripple:SetPoint("CENTER", b, "BOTTOMLEFT", x / es - l, y / es - bt)
    else
        s.ripple:SetPoint("CENTER", b, "CENTER")
    end
    s.ripple:SetSize(s.rippleBase * R.from, s.rippleBase * R.from)
    s.ripple:SetAlpha(R.alpha)
    s.ripple:Show()
    rippling[s] = 0
    driver:SetScript("OnUpdate", step)
end

-- The pointer and a click, on the button's own scripts (HookScript: Blizzard's
-- handlers run first and untouched). Read the setting when they fire.
local function hookFeedback(s)
    local b = s.button
    b:HookScript("OnEnter", function() if look("hover") == "halo" then fadeTo(s, 1) end end)
    b:HookScript("OnLeave", function() fadeTo(s, 0) end)
    b:HookScript("OnHide", function() clearEffects(s) end)
    b:HookScript("OnMouseDown", function() API.Try("skin:ripple", ripple, s) end)
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
-- Our own rim (Tools/make_rim.py): LibGlass's thin rim peaks at 86/255, too
-- faint once the body went clear. Same geometry as body_mask_small (32 px,
-- radius 7, slice margins 8); a crisp line, brightest along the top, quiet at
-- the bottom, near-full alpha at its brightest for /gab tune's headroom.
Buttons.RIM = "ButtonRim"
Buttons.RIM_MARGIN = 8

local function rimTexture(t)
    t:SetTexture(GAB.MEDIA .. Buttons.RIM)
    t:SetTextureSliceMargins(Buttons.RIM_MARGIN, Buttons.RIM_MARGIN, Buttons.RIM_MARGIN, Buttons.RIM_MARGIN)
    local modes = Enum and Enum.UITextureSliceMode
    t:SetTextureSliceMode((modes and modes.Stretched) or 0)
end

-- Pearl's face (#44, the owner's FFXIV reference; Tools/make_rim.py): on a
-- filled slot a reflection over the icon's upper part, on a frosted empty one
-- a recessed socket (a lit lower lip, a dark upper inset) in place of the
-- raised rim. Pearl only, built once; paintRim sets their alphas. All on the
-- rim's frame, one level over the button: a fixed order, over the icon and,
-- like the rim, over the cooldown sweep (the trade: a 16% sheen on it; the
-- button's own level would have no order measured against the cooldowns).
-- /gab tune gloss 0 takes the reflection off.
local function makePearlFace(s)
    if GAB.GlassPreset ~= "pearl" then return end
    local mask = s.g.top:CreateMaskTexture()   -- the rounded square, as the ripple's
    mask:SetTexture(GAB.MEDIA .. Buttons.RIPPLE.mask, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetAllPoints(s.body)
    local gloss = s.g.top:CreateTexture(nil, "ARTWORK", nil, 0)   -- under the rim (OVERLAY) and the halo
    gloss:SetAllPoints(s.body)
    gloss:SetTexture(GAB.MEDIA .. "ButtonGloss")
    gloss:AddMaskTexture(mask)
    gloss:SetAlpha(0)
    local function edge(file, sub, r, g, b)
        local t = s.g.top:CreateTexture(nil, "OVERLAY", nil, sub)
        t:SetAllPoints(s.g.top)
        t:SetTexture(GAB.MEDIA .. file)
        t:SetTextureSliceMargins(Buttons.RIM_MARGIN, Buttons.RIM_MARGIN, Buttons.RIM_MARGIN, Buttons.RIM_MARGIN)
        local modes = Enum and Enum.UITextureSliceMode
        t:SetTextureSliceMode((modes and modes.Stretched) or 0)
        t:SetVertexColor(r, g, b, 1)
        t:SetAlpha(0)
        return t
    end
    s.gloss = gloss
    s.socketRim = edge("ButtonSocketRim", 6, 1, 1, 1)       -- the rim's sublayer
    s.socketShade = edge("ButtonSocketShade", 4, 0, 0, 0)   -- the inner line's
end

-- A provider's or the Utility bar's icon, rounded like the rim (#46): a mask
-- on the icon's own frame (never a Blizzard one: their icons aren't passed),
-- the rim's rounded square, as the ripple's.
local function maskIcon(icon)
    local mask = icon:GetParent():CreateMaskTexture()
    mask:SetTexture(GAB.MEDIA .. Buttons.RIPPLE.mask, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetAllPoints(icon)
    icon:AddMaskTexture(mask)
end

-- The pressed look's alpha: the live part (a region's alpha only, safe in combat).
local function pushedAlpha(s)
    local p = s.regions.pushed
    if p then p:SetAlpha(look("press") == "off" and 0 or 1) end
end

-- The pressed look's setup: texture and anchors on a protected button's
-- region, at Build and after Blizzard's UpdateButtonArt only, never from the
-- live refresh (Glass UI's look may change in combat: SUITE-LOOK.md).
local function stylePushed(s)
    local p = s.regions.pushed
    if not p then return end
    rimTexture(p)
    p:ClearAllPoints()
    p:SetAllPoints(s.button)
    p:SetVertexColor(1, 1, 1, 1)
    p:SetBlendMode("ADD")
    pushedAlpha(s)
end

-- The fades first, each on its own, then the pressed look: one refusal
-- never leaves the rest undone.
local function styleArt(s)
    local r = s.regions
    for _, key in ipairs({ "normal", "slotArt", "slotBackground" }) do
        if r[key] then API.Try("skin:fade:" .. key, r[key].SetAlpha, r[key], 0) end
    end
    API.Try("skin:pushed", stylePushed, s)
end

-- The glass on one button. `regions` names its parts: icon, cooldown,
-- count, hotkey, name, normal, pushed, highlight, slotArt, slotBackground
-- (any may be absent). `opts.maskIcon`: round the icon to the glass's shape
-- (#46), for icons that aren't Blizzard's (theirs have the template's
-- IconMask). `opts.inset`: the glass that many units inside the button on
-- each side (the micro buttons overlap, #57); its reflection and ripple
-- follow it. Returns the button's state; a second call returns the same one.
function Buttons.Build(button, regions, opts)
    if skins[button] then return skins[button] end
    local body = CreateFrame("Frame", nil, button)
    local inset = opts and tonumber(opts.inset)
    if inset then
        body:SetPoint("TOPLEFT", button, "TOPLEFT", inset, -inset)
        body:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -inset, inset)
    else
        body:SetAllPoints(button)
    end
    body:EnableMouse(false)
    local g = Glass.Apply(body, Buttons.SIZE)
    g.shadow:SetAlpha(0)   -- it would spill onto the next button (LibGlass Pill's rule)
    g.grain:SetAlpha(0)
    rimTexture(g.rim)      -- our rim on the surface's own rim region (ours to retexture)
    local s = { button = button, body = body, g = g, regions = regions or {}, occupied = true,
                small = (API.Plain(button:GetWidth()) or 45) < 40 }
    skins[button] = s
    API.Try("skin:pearl", makePearlFace, s)
    if opts and opts.maskIcon and s.regions.icon then API.Try("skin:mask", maskIcon, s.regions.icon) end
    -- The body's paint first, and every later step on its own: a step that
    -- throws on the client (a region method Blizzard's art refuses) must not
    -- leave the body unpainted and out of /gab tune's reach. A failure is
    -- recorded per step and button for /gab failures. (The owner's grey fill,
    -- 2026-10-13, turned out to be the wash's gradient ignoring SetAlpha: see
    -- Theme.lua's paint.)
    GAB.Theme.Register(g, function()
        -- Frosted replaces only the clear glass's colour: smoked and class
        -- glass keep their tint, so the theme still shows (owner, 2026-10-19).
        if not s.occupied and look("emptySlots") == "frosted" and GAB.Theme.Current() == "clear" then
            return Buttons.Tune("wash"), 1, Buttons.Frost()   -- the fill's own alpha, unscaled
        end
        local f = emptyFactor(s)
        return Buttons.Tune("wash") * f, Buttons.Tune("body") * f
    end)
    local name = API.Plain(button:GetName()) or "?"
    API.Try("skin:rim:" .. name, paintRim, s)
    API.Try("skin:level:" .. name, relevel, s)
    API.Try("skin:art:" .. name, styleArt, s)
    API.Try("skin:text:" .. name, styleText, s)
    API.Try("skin:highlight:" .. name, applyHighlight, s)
    API.Try("skin:halo:" .. name, makeHalo, s)
    API.Try("skin:feedback:" .. name, hookFeedback, s)
    return s
end

function Buttons.IsSkinned(button) return skins[button] ~= nil end

-- Blizzard set a skinned button's art again (a family's own writer, e.g. the
-- bag slots' UpdateTextures): fade it and take the pressed look back.
function Buttons.Restyle(button)
    local s = skins[button]
    if s then API.Try("skin:art", function() styleArt(s); relevel(s) end) end
end

-- A skinned button's state ({ button, body, g, regions, occupied, small }),
-- read-only, for Inspect.lua; and every one in turn.
function Buttons.State(button) return skins[button] end
function Buttons.Each(fn) for _, s in pairs(skins) do fn(s) end end

-- A nil `occupied` (unreadable: secret, or the reader failed) keeps the last state.
function Buttons.SetOccupied(button, occupied)
    local s = skins[button]
    if not s or occupied == nil then return end
    local was = s.occupied
    s.occupied = occupied == true
    paintRim(s)
    -- The body's paint carries the empty-slots factor.
    if was ~= s.occupied then GAB.Theme.Repaint(s.g) end
end

-- The feedback settings changed: every button's highlight, halo, pressed
-- look and empty glass, at once. Colours and alphas only, safe in combat
-- (Glass UI's LookChanged may come in a fight).
function Buttons.RefreshFeedback()
    for _, s in pairs(skins) do
        API.Try("skin:feedback", function()
            applyHighlight(s)
            if look("hover") ~= "halo" then
                fading[s] = nil
                if s.halo then s.halo:SetAlpha(0) end
            elseif API.Plain(s.button:IsMouseOver()) == true then
                fadeTo(s, 1)   -- turned on under a still pointer
            end
            if look("press") ~= "ripple" and s.ripple then
                rippling[s] = nil
                s.ripple:Hide()
            end
            pushedAlpha(s)
            paintRim(s)
            GAB.Theme.Repaint(s.g)
        end)
    end
end

-- Settings changed: hotkeys and macro names shown or not.
function Buttons.RefreshText()
    for _, s in pairs(skins) do API.Try("skin:text", styleText, s) end
end

-- /gab tune: a number changed, repaint every button.
function Buttons.RefreshLook()
    for _, s in pairs(skins) do API.Try("skin:rim", paintRim, s) end
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

Buttons._test = { skins = skins, styleArt = styleArt, fading = fading, rippling = rippling }
