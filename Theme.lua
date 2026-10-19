-- Theme.lua: the three looks of the glass, repainted live on every surface.
--
-- clear   the material as LibGlass built it (cool, light)
-- smoked  AltStable's darker body (its numbers, as GlassPanel and GlassMail use them)
-- class   the clear body tinted by the player's class colour, shaded by
--         classShade: at full strength it reads as painted plastic (AltStable,
--         in game). The class colour may be unreadable early in a login; the
--         surface then stays clear and PLAYER_ENTERING_WORLD paints it again.
--
-- GlassMiniMap's Theme.lua, without its orb kind. Every glass surface this
-- addon builds registers here by its g. Only body regions are touched (tint
-- colour, grain and wash alpha): the rims are the button skin's.

GlassActionBars = GlassActionBars or {}
local GAB = GlassActionBars
local API = GAB.API
local Glass = GAB.Glass
local Theme = {}
GAB.Theme = Theme

Theme.NAMES = { "clear", "smoked", "class" }
Theme.LABELS = { clear = "Clear glass", smoked = "Smoked glass", class = "Class colour glass" }
Theme.PRESETS = {
    clear  = {},
    smoked = { tint = { 0.05, 0.06, 0.08, 0.62 }, wash = 0.14 / 0.18 },
    class  = { classShade = 0.6 },
}

local surfaces = {}
local byG = setmetatable({}, { __mode = "k" })   -- a surface by its glass
Theme.pending = false

function Theme.IsValid(name) return Theme.PRESETS[name] ~= nil end

local function current()
    local name = GAB.db and GAB.db.theme
    return Theme.PRESETS[name] and name or "clear"
end

-- The tint for this theme as r, g, b, a (a nil: the surface's own), or
-- nothing for "as built". Second return: false while the class colour is
-- wanted but unreadable.
local function tintFor(name)
    local p = Theme.PRESETS[name]
    if name == "class" then
        local r, g, b = API.ClassColor()
        if not r then return nil, false end
        return { r * p.classShade, g * p.classShade, b * p.classShade }, true
    end
    return p.tint, true
end

-- A surface's own scale on the theme's wash and body alpha (the buttons'
-- /gab tune), read at every paint.
--
-- The wash is a gradient (LibGlass: clear at the bottom to STYLE.wash white
-- at the top), and on this client a gradient texture ignores SetAlpha:
-- /gab inspect read the wash at alpha 1.00 right after SetAlpha(0) (owner's
-- session, 2026-10-13), where every plain texture reads back what was set.
-- So the wash goes through Glass.SetWash (LibGlass r7, from that finding:
-- LibGlass#47), which paints its gradient and records the peak a disable
-- dims from, and the tint through its colour; each is hidden outright at
-- zero, so nothing is left to draw.
local function paint(s, name, tint)
    local g, p = s.g, Theme.PRESETS[name]
    local wash, body = 1, 1
    if s.scale then wash, body = s.scale() end
    local built = g.tint.glassColor or Glass.STYLE.tint
    local c = tint or built
    local a = (c[4] or built[4]) * body
    Glass.SetSurfaceTint(g, c[1], c[2], c[3], a)
    g.tint:SetShown(a > 0)
    if g.grain then g.grain:SetAlpha(0) end   -- no grain at button size (LibGlass Pill's rule)
    if g.wash then
        Glass.SetWash(g, math.min(1, (Glass.STYLE.wash or 0) * (p.wash or 1) * wash))
    end
end

-- Add a surface and paint it with the current theme. `scale`, optional:
-- a function returning the surface's wash and body factors.
function Theme.Register(g, scale)
    if type(g) ~= "table" or not g.tint then return end
    local s = { g = g, scale = scale }
    surfaces[#surfaces + 1] = s
    byG[g] = s
    local name = current()
    local tint, known = tintFor(name)
    if not known then Theme.pending = true end
    API.Try("theme:paint", paint, s, name, tint)
end

-- Repaint one surface (its scale changed: a button's slot emptied or filled).
function Theme.Repaint(g)
    local s = byG[g]
    if s then API.Try("theme:paint", paint, s, current(), (tintFor(current()))) end
end

-- Repaint every surface. Returns false while the class colour is unreadable.
function Theme.Refresh()
    local name = current()
    local tint, known = tintFor(name)
    for _, s in ipairs(surfaces) do API.Try("theme:paint", paint, s, name, tint) end
    Theme.pending = not known
    return known
end

-- PLAYER_ENTERING_WORLD: the class colour can be read by now.
function Theme.Retry()
    if Theme.pending then Theme.Refresh() end
end

Theme._test = { surfaces = surfaces }
