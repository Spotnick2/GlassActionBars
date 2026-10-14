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

local function paint(g, name, tint)
    local p = Theme.PRESETS[name]
    if tint then
        Glass.SetSurfaceTint(g, tint[1], tint[2], tint[3], tint[4])
    else
        Glass.SetSurfaceTint(g)
    end
    if g.grain then g.grain:SetAlpha(0) end   -- no grain at button size (LibGlass Pill's rule)
    if g.wash then g.wash:SetAlpha(p.wash or 1) end
end

-- Add a surface and paint it with the current theme.
function Theme.Register(g)
    if type(g) ~= "table" or not g.tint then return end
    surfaces[#surfaces + 1] = g
    local name = current()
    local tint, known = tintFor(name)
    if not known then Theme.pending = true end
    API.Try("theme:paint", paint, g, name, tint)
end

-- Repaint every surface. Returns false while the class colour is unreadable.
function Theme.Refresh()
    local name = current()
    local tint, known = tintFor(name)
    for _, g in ipairs(surfaces) do API.Try("theme:paint", paint, g, name, tint) end
    Theme.pending = not known
    return known
end

-- PLAYER_ENTERING_WORLD: the class colour can be read by now.
function Theme.Retry()
    if Theme.pending then Theme.Refresh() end
end

Theme._test = { surfaces = surfaces }
