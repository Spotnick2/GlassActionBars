-- Inspect.lua: what an action button actually draws, in game.
--
-- The owner's report (2026-10-13): with /gab tune wash 0 and body 0, empty
-- buttons still showed a cloudy grey fill, and reading the code could not
-- say which layer it was. So, measured instead:
--
--   /gab inspect [button]     every texture and font string on the button and
--                             its child frames (ours and Blizzard's), numbered:
--                             who owns it, its key, shown/visible, its alpha and
--                             effective alpha, layer, atlas or file, blend,
--                             vertex colour, size. The visible ones with any
--                             alpha are marked "*". Default: the first visible
--                             empty action button. Saved in
--                             GlassActionBarsDB.inspect for reading off disk.
--   /gab inspect hide <n>     alpha 0 on region n of that button, for a look;
--   /gab inspect show <n>     its alpha back; `inspect restore` all of them.
--   /gab layer <name> off/on  one named layer, on every skinned button at once:
--                             ours (body, tint, wash, shadow, grain, dark, rim,
--                             edge) or Blizzard's (normal, pushed, highlight,
--                             checked, slotArt, slotBackground, border, flash).
--
-- Nothing here is saved as a setting: a /reload undoes every hide. Alphas
-- only, never Hide(); no field is written onto a Blizzard frame.

GlassActionBars = GlassActionBars or {}
local GAB = GlassActionBars
local API = GAB.API
local Inspect = {}
GAB.Inspect = Inspect

local say = API.Print
local last = { button = nil, regions = {} }   -- the last inspection's regions, by number
local hidden = {}                              -- region -> its alpha before a hide

local function num(v)
    v = API.Plain(v)
    if type(v) ~= "number" then return "?" end
    return ("%.2f"):format(v)
end

-- Keys a frame declares for its regions and children (template parentKeys,
-- or ours on the glass table), read only.
local function keysOf(frame, extra)
    local names = {}
    for k, v in pairs(frame) do
        if type(k) == "string" and type(v) == "table" then names[v] = k end
    end
    if extra then for k, v in pairs(extra) do if type(v) == "table" then names[v] = names[v] or k end end end
    return names
end

-- The glass's own regions, named after their g fields.
local function glassNames(s)
    local names = {}
    if not s then return names end
    for _, k in ipairs({ "shadow", "tint", "grain", "wash", "dark", "rim" }) do
        if s.g[k] then names[s.g[k]] = "glass." .. k end
    end
    if s.g.edge then
        for _, k in ipairs({ "top", "glow", "bottom" }) do names[s.g.edge[k]] = "glass.edge." .. k end
    end
    return names
end

local function describe(n, r, owner, key, frameAlpha)
    local t = r:GetObjectType()
    local alpha = API.Plain(r:GetAlpha())
    local eff = (type(alpha) == "number" and type(frameAlpha) == "number") and alpha * frameAlpha or nil
    local visible = r:IsVisible()
    local parts = { ("%2d"):format(n), owner, key or "?", t, visible and "visible" or (r:IsShown() and "shown,parent-hidden" or "hidden"),
        "a=" .. num(alpha), "eff=" .. num(eff) }
    if t == "Texture" then
        local layer, sub = r:GetDrawLayer()
        parts[#parts + 1] = tostring(layer) .. "/" .. tostring(sub)
        local atlas = API.Plain(r:GetAtlas())
        if atlas then parts[#parts + 1] = "atlas=" .. tostring(atlas)
        else
            local ok, path = pcall(r.GetTextureFilePath, r)
            path = ok and API.Plain(path) or nil
            local ok2, id = pcall(r.GetTextureFileID, r)
            id = ok2 and API.Plain(id) or nil
            parts[#parts + 1] = "file=" .. tostring(path or id or "colour")
        end
        local okb, blend = pcall(r.GetBlendMode, r)
        if okb and API.Plain(blend) then parts[#parts + 1] = "blend=" .. tostring(blend) end
        local okc, vr, vg, vb, va = pcall(r.GetVertexColor, r)
        if okc then parts[#parts + 1] = ("vc=%s,%s,%s,%s"):format(num(vr), num(vg), num(vb), num(va)) end
    end
    local okw, w, h = pcall(r.GetSize, r)
    if okw then parts[#parts + 1] = num(w) .. "x" .. num(h) end
    local suspect = visible and type(eff) == "number" and eff > 0.01 and t == "Texture"
    return (suspect and "* " or "  ") .. table.concat(parts, "  ")
end

-- Every region of `frame` and its descendants (depth-limited), numbered.
local function walk(frame, s, out, depth, names, owner)
    local frameAlpha = API.Plain(frame:GetEffectiveAlpha())
    local glass = glassNames(s)
    for _, r in ipairs({ frame:GetRegions() }) do
        local ot = r:GetObjectType()
        if ot == "Texture" or ot == "FontString" then
            out[#out + 1] = { region = r, owner = owner, key = glass[r] or names[r], frameAlpha = frameAlpha }
        end
    end
    if depth <= 0 then return end
    for _, child in ipairs({ frame:GetChildren() }) do
        local childOwner = owner
        if s and (child == s.body or child == s.g.top) then childOwner = "GAB" end
        -- The child's own keys first, then its parent's (the button aliases
        -- HotKey and Count from its text container).
        local childNames = keysOf(child)
        for r, k in pairs(names) do if childNames[r] == nil then childNames[r] = k end end
        walk(child, s, out, depth - 1, childNames, childOwner)
    end
end

-- The first visible action button with nothing in its slot.
local function firstEmpty()
    for _, prefix in ipairs(ActionButtonUtil.ActionBarButtonNames) do
        for i = 1, NUM_ACTIONBAR_BUTTONS do
            local b = _G[prefix .. i]
            if b and b:IsVisible() and GAB.Buttons.READ.action(b) == false then return b end
        end
    end
end

function Inspect.Run(name)
    local b = (name and name ~= "") and _G[name] or firstEmpty()
    if type(b) ~= "table" or not b.GetRegions then return say("inspect: no button " .. tostring(name)) end
    local s = GAB.Buttons.State(b)
    local out = {}
    walk(b, s, out, 3, keysOf(b), "Blizzard")
    last.button, last.regions = b, {}
    local lines = { "inspect " .. tostring(b:GetName()) .. ": skinned " .. tostring(s ~= nil)
        .. ", occupied " .. tostring(s and s.occupied) .. ", level " .. tostring(b:GetFrameLevel())
        .. ", tune wash " .. num(GAB.Buttons.Tune("wash")) .. " body " .. num(GAB.Buttons.Tune("body")) }
    for i, e in ipairs(out) do
        last.regions[i] = e.region
        lines[#lines + 1] = describe(i, e.region, e.owner, e.key, e.frameAlpha)
    end
    local failed = {}
    for key in pairs(GAB.failures) do failed[#failed + 1] = key end
    table.sort(failed)
    lines[#lines + 1] = #failed == 0 and "no failures recorded"
        or ("failures (" .. #failed .. "): " .. table.concat(failed, ", ", 1, math.min(#failed, 12)))
    lines[#lines + 1] = "'*' = visible with alpha; /gab inspect hide <n> to try one"
    for _, l in ipairs(lines) do say(l) end
    GAB.db.inspect = { when = date and date("%Y-%m-%d %H:%M:%S") or "", lines = lines }
end

function Inspect.Hide(n)
    local r = last.regions[n]
    if not r then return say("inspect: no region " .. tostring(n) .. " (run /gab inspect first)") end
    if hidden[r] == nil then hidden[r] = API.Plain(r:GetAlpha()) or 1 end
    r:SetAlpha(0)
    say("inspect: region " .. n .. " hidden (alpha 0) until /gab inspect show " .. n .. " or a /reload")
end

function Inspect.Show(n)
    local r = last.regions[n]
    if not r or hidden[r] == nil then return say("inspect: region " .. tostring(n) .. " isn't hidden") end
    r:SetAlpha(hidden[r])
    hidden[r] = nil
    say("inspect: region " .. n .. " back")
end

function Inspect.Restore()
    for r, a in pairs(hidden) do r:SetAlpha(a) end
    hidden = {}
    say("inspect: every hidden region back")
end

-- /gab layer: one named layer, every skinned button.
local LAYERS = {
    body = function(s) return { s.body } end,
    tint = function(s) return { s.g.tint } end,
    wash = function(s) return { s.g.wash } end,
    shadow = function(s) return { s.g.shadow } end,
    grain = function(s) return { s.g.grain } end,
    dark = function(s) return { s.g.dark } end,
    rim = function(s) return { s.g.rim } end,
    edge = function(s) return s.g.edge and { s.g.edge.top, s.g.edge.glow, s.g.edge.bottom } or {} end,
    normal = function(s) return { s.regions.normal } end,
    pushed = function(s) return { s.regions.pushed } end,
    highlight = function(s) return { s.regions.highlight } end,
    checked = function(s) return { s.button.CheckedTexture } end,
    slotArt = function(s) return { s.regions.slotArt } end,
    slotBackground = function(s) return { s.regions.slotBackground } end,
    border = function(s) return { s.button.Border } end,
    flash = function(s) return { s.button.Flash } end,
}
Inspect.LAYER_NAMES = { "body", "tint", "wash", "shadow", "grain", "dark", "rim", "edge", "normal", "pushed",
    "highlight", "checked", "slotArt", "slotBackground", "border", "flash" }

function Inspect.Layer(name, on)
    local get = LAYERS[name]
    if not get then return false end
    local n = 0
    GAB.Buttons.Each(function(s)
        for _, r in ipairs(get(s)) do
            if r then
                if on then
                    if hidden[r] ~= nil then r:SetAlpha(hidden[r]); hidden[r] = nil; n = n + 1 end
                else
                    if hidden[r] == nil then hidden[r] = API.Plain(r:GetAlpha()) or 1 end
                    r:SetAlpha(0)
                    n = n + 1
                end
            end
        end
    end)
    say("layer " .. name .. (on and " back" or " hidden") .. " on " .. n .. " regions (a /reload undoes it)")
    return true
end

Inspect._test = { last = last, hidden = function() return hidden end }
