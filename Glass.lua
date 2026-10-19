-- Glass.lua: this addon's instance of the "liquid glass" material.
--
-- The material lives in the embedded library LibGlass-1.0
-- (Libs\LibGlass-1.0, from github.com/Spotnick2/LibGlass through .pkgmeta
-- externals; the TOC loads it first). Material changes are LibGlass PRs, not
-- edits here.
--
-- An instance, not the library itself: its tuning and font registry are
-- Glass Action Bars' own and never touch another glass addon's surfaces.
--
-- Built at PLAYER_LOGIN, not at load (#39): Glass UI's suite theme is asked
-- first (Look.lua), and every addon's ADDON_LOADED has run by then, so the
-- TOC names no other addon. The material: Pearl (r11, the default: kept after the trial,
-- owner 2026-10-19), Clean or Classic. GAB.Glass is a stand-in that reaches
-- the instance once built; nothing reads it before PLAYER_LOGIN.

local ADDON = ...
GlassActionBars = GlassActionBars or {}
local GAB = GlassActionBars
GAB.MEDIA = "Interface\\AddOns\\" .. (ADDON or "GlassActionBars") .. "\\Media\\"
GAB.MATERIALS = { "pearl", "clean", "classic" }

local instance
GAB.Glass = setmetatable({}, {
    __index = function(_, k)
        if not instance then error("Glass Action Bars: the glass is read before it is built", 2) end
        return instance[k]
    end,
})

function GAB.IsMaterial(v)
    for _, m in ipairs(GAB.MATERIALS) do
        if v == m then return true end
    end
    return false
end

-- Build the instance once with `preset`. True; or false and why, the
-- instance then built Clean ("library-too-old": the winning LibGlass has no
-- such preset; "build-failed": New errored otherwise).
function GAB.BuildGlass(preset)
    if instance then return true end
    local lib, minor = LibStub("LibGlass-1.0")
    GAB.GlassMinor = minor
    local ok, made = pcall(lib.New, lib, { preset = preset })
    if ok and made then
        instance, GAB.GlassPreset = made, preset
        return true
    end
    local reason = tostring(made):find("unknown preset", 1, true) and "library-too-old" or "build-failed"
    instance, GAB.GlassPreset = lib:New({ preset = "clean" }), "clean"
    return false, reason
end

function GAB.GlassBuilt() return instance ~= nil end
