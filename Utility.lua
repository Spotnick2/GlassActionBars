-- Utility.lua: the Utility bar (#9), Apotheca's profession bar moved into
-- Glass Action Bars, plus the camping items.
--
-- What it shows, in the player's order: the Hearthstone, Cooking, First Aid,
-- Fishing, the primary professions' windows and their action spells, and one
-- "Camping" group. A profession's button shows when the character knows it;
-- an item's while the bags hold one. Camping (the issue's owner rules): a
-- Campfire Kit shows whenever carried; every other camping feature also needs
-- the "near a campfire" aura (CAMPFIRE_AURA; Wowhead's "Campfire Nearby",
-- confirmed in game before release).
--
-- The buttons are secure (SecureActionButtonTemplate), one per action,
-- created at load and named GlassActionBarsUtil_<key> so a saved key binding
-- (Bindings.xml: CLICK bindings) always has a target. An action off,
-- unavailable or on a disabled bar has its attributes cleared: a hidden
-- button still fires its binding (Apotheca, measured). The template has no
-- visuals: each button makes its own icon, cooldown, count, hotkey, pushed
-- and highlight, skinned with Buttons.Build at login.
--
-- Combat: secure buttons can't be shown, hidden, re-attributed or moved, so
-- every rebuild waits for PLAYER_REGEN_ENABLED. Walking into or away from a
-- camp in combat changes the bar when the fight ends.
--
-- Placement is the dock's (client "utility", Dock.lua): docked right of Action
-- Bar 1 by default. Layout(geom) lays the buttons out with the bar's geometry,
-- or the bar's own (LAYOUT, Apotheca's keys) when geom is nil. Alt-drag moves
-- the bar anywhere: the drag undocks it at its start (so no dock pass moves
-- it mid-drag) and the drop saves the spot; undocked, the bar sits there.

GlassActionBars = GlassActionBars or {}
local GAB = GlassActionBars
local API = GAB.API
local Utility = {}
GAB.Utility = Utility

Utility.PREFIX = "GlassActionBarsUtil_"
Utility.HEARTHSTONE = 6948
Utility.CAMPFIRE_AURA = 1283391   -- "Campfire Nearby" (Wowhead; to confirm in game)
Utility.SIZE, Utility.PADDING = 36, 4
Utility.DOCK = { bar = 1, side = "RIGHT", align = "END", gap = 4, match = true }
-- The bar's own layout (undocked, or docked without matching): Apotheca's
-- setting keys, so its import is a copy. VERTICAL: `rows` counts columns.
Utility.LAYOUT = { orientation = "HORIZONTAL", rows = 1, iconSize = Utility.SIZE, iconPadding = Utility.PADDING }
local LAYOUT_RANGE = { rows = { 1, 12 }, iconSize = { 16, 64 }, iconPadding = { 0, 16 } }

-- Apotheca's actions, in their default order. `spells`: candidate IDs,
-- highest rank first (only one is known at a time). `measured`: on 70334
-- (Apotheca's FOREVER-PROBE.md); the rest are Vanilla's IDs, carried forward.
Utility.ACTIONS = {
    { key = "hearthstone", label = "Hearthstone", item = 6948, measured = true },
    { key = "cooking", label = "Cooking", spells = { 18260, 3413, 3102, 2550 }, measured = true },
    { key = "firstaid", label = "First Aid", spells = { 10846, 7924, 3274, 3273 }, measured = true },
    { key = "fishing", label = "Fishing", spells = { 18248, 7732, 7731, 7620 }, measured = true },
    { key = "baittackle", label = "Bait and Tackle", spells = { 1278067 }, measured = true },
    { key = "alchemy", label = "Alchemy", spells = { 11611, 3464, 3101, 2259 } },
    { key = "blacksmithing", label = "Blacksmithing", spells = { 9785, 3538, 3100, 2018 } },
    { key = "enchanting", label = "Enchanting", spells = { 13920, 7413, 7412, 7411 }, measured = true },
    { key = "engineering", label = "Engineering", spells = { 12656, 4038, 4037, 4036 } },
    { key = "leatherworking", label = "Leatherworking", spells = { 10662, 3811, 3104, 2108 }, measured = true },
    { key = "tailoring", label = "Tailoring", spells = { 12180, 3910, 3909, 3908 }, measured = true },
    { key = "skinning", label = "Skinning", spells = { 10768, 8618, 8617, 8613 }, measured = true },
    { key = "mining", label = "Mining", spells = { 10248, 3564, 2576, 2575 } },
    { key = "herbalism", label = "Herbalism", spells = { 11993, 3570, 2368, 2366 } },
    { key = "smelting", label = "Smelting", spells = { 2656 } },
    { key = "poisons", label = "Poisons", spells = { 2842 } },
    { key = "disenchant", label = "Disenchant", spells = { 13262 }, measured = true },
    { key = "findherbs", label = "Find Herbs", spells = { 2383 } },
    { key = "findminerals", label = "Find Minerals", spells = { 2580 } },
    { key = "picklock", label = "Pick Lock", spells = { 1804 } },
}

-- The camping items: the authoritative list (Wowhead's Forever guide, #9).
-- Kits need no aura; every feature needs the campfire aura. The Iron Oven
-- (spell 1263067) has no known item ID yet.
Utility.CAMPING = {
    { key = "camp_basic", label = "Basic Campfire Kit", item = 279981, kit = true },
    { key = "camp_journeyman", label = "Journeyman Campfire Kit", item = 279961, kit = true },
    { key = "camp_expert", label = "Expert Campfire Kit", item = 279974, kit = true },
}
for _, p in ipairs({
    { "alchemy", { 279956, "Mana Well" }, { 279970, "Fermenter" }, { 279990, "Alchemy Laboratory" } },
    { "blacksmithing", { 279944, "Sharpening Wheel" }, { 279988, "Anvil" }, { 279955, "Master Forge" } },
    { "enchanting", { 279976, "Enchanted Lute" }, { 279985, "Arcane Salvager" }, { 279987, "Arcane Forge" } },
    { "engineering", { 279950, "Reagent Bot" }, { 279949, "Repair Bot" }, { 279989, "Anarchist's Workbench" } },
    { "herbalism", { 279962, "Incense Candle" }, { 279964, "Greenhouse" }, { 279947, "Seed Hybridizer" } },
    { "leatherworking", { 279978, "Camp Tent" }, { 279941, "Tanning Rack" }, { 279945, "Sewing Machine" } },
    { "mining", { 279960, "Lodestone" }, { 279948, "Rock Garden" }, { 279952, "Molten Foundry" } },
    { "skinning", { 279979, "Camp Chair" }, { 279969, "Field Guide" }, { 279938, "Trapper's Workbench" } },
    { "tailoring", { 279972, "Faction Banner" }, { 279943, "Spinning Wheel" }, { 279959, "Loom" } },
    { "firstaid", { 279968, "First Aid Kit" }, { 279940, "Toxin Study" }, { 279951, "Plague Doctor's Laboratory" } },
    { "fishing", { 279967, "Fish Bowl" }, { 279965, "Fishing Rack" }, { 279966, "Fishing Hut" } },
    { "cooking", { 279957, "Cookie's Feast" } },
}) do
    for tier = 2, #p do
        local item = p[tier]
        Utility.CAMPING[#Utility.CAMPING + 1] = { key = "camp_" .. p[1] .. (tier - 1), label = item[2], item = item[1] }
    end
end

local BY_KEY = {}
for _, a in ipairs(Utility.ACTIONS) do BY_KEY[a.key] = a end
for _, a in ipairs(Utility.CAMPING) do BY_KEY[a.key] = a end
Utility.BY_KEY = BY_KEY

-- The keys of the player's order: the actions, then the Camping group.
Utility.ORDER_KEYS = {}
for _, a in ipairs(Utility.ACTIONS) do Utility.ORDER_KEYS[#Utility.ORDER_KEYS + 1] = a.key end
Utility.ORDER_KEYS[#Utility.ORDER_KEYS + 1] = "camping"
local isOrderKey = {}
for _, k in ipairs(Utility.ORDER_KEYS) do isOrderKey[k] = true end

-- A key the saved settings may hold: an order key, or a provider's button
-- (provider:<id>, kept even before that provider registers; #9's PR 2).
function Utility.ValidKey(k)
    return type(k) == "string" and (isOrderKey[k] or k:match("^provider:[%w_]+$") ~= nil)
end

-- Key bindings: every action, and each Campfire Kit (Bindings.xml lists them).
Utility.BINDING_KEYS = {}
for _, a in ipairs(Utility.ACTIONS) do Utility.BINDING_KEYS[#Utility.BINDING_KEYS + 1] = a.key end
for _, a in ipairs(Utility.CAMPING) do
    if a.kit then Utility.BINDING_KEYS[#Utility.BINDING_KEYS + 1] = a.key end
end
function Utility.BindingAction(key) return "CLICK " .. Utility.PREFIX .. key .. ":LeftButton" end
local isBound = {}
for _, key in ipairs(Utility.BINDING_KEYS) do
    isBound[key] = true
    _G["BINDING_NAME_" .. Utility.BindingAction(key)] = BY_KEY[key].label
end

-- ------------------------------------------------------------------
-- Settings (GlassActionBarsDB.utility: created by the first change only)
-- ------------------------------------------------------------------

local function saved()
    local t = GAB.db and rawget(GAB.db, "utility")
    return type(t) == "table" and t or nil
end

function Utility.Enabled()
    local s = saved()
    if s and s.enabled ~= nil then return s.enabled == true end
    return true
end

function Utility.IsShown(key)
    local s = saved()
    return not (s and type(s.show) == "table" and s.show[key] == false)
end

-- A valid value for one of LAYOUT's keys.
function Utility.ValidLayout(key, v)
    if key == "orientation" then return v == "HORIZONTAL" or v == "VERTICAL" end
    local r = LAYOUT_RANGE[key]
    return r ~= nil and type(v) == "number" and v >= r[1] and v <= r[2] and (key ~= "rows" or v % 1 == 0)
end

function Utility.LayoutSetting(key)
    local s = saved()
    if s and Utility.ValidLayout(key, s[key]) then return s[key] end
    return Utility.LAYOUT[key]
end

-- A saved position: the bottom-left corner, finite UIParent offsets.
local function finite(v) return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge end
function Utility.ValidPos(p)
    return type(p) == "table" and finite(p.x) and finite(p.y)
end

-- The saved order (known keys, once each), then any key it lacks.
function Utility.Order()
    local s, out, seen = saved(), {}, {}
    for _, k in ipairs(s and type(s.order) == "table" and s.order or {}) do
        if isOrderKey[k] and not seen[k] then out[#out + 1] = k; seen[k] = true end
    end
    for _, k in ipairs(Utility.ORDER_KEYS) do
        if not seen[k] then out[#out + 1] = k end
    end
    return out
end

-- ------------------------------------------------------------------
-- What the character has
-- ------------------------------------------------------------------

function Utility.KnownSpell(action)
    for _, id in ipairs(action.spells or {}) do
        if API.SpellKnown(id) == true then return id end
    end
end

-- The campfire aura's last plain state: unknown (secret, or the read threw)
-- keeps it; it starts absent.
local campfire = false
function Utility.ReadCampfire()
    local v = API.HasPlayerAura(Utility.CAMPFIRE_AURA)
    if v ~= nil and v ~= campfire then
        campfire = v
        return true
    end
    return false
end
function Utility.NearCampfire() return campfire end

-- The ordered list of { key, kind = "spell"|"item", value } to show.
function Utility.Collect()
    local list = {}
    for _, key in ipairs(Utility.Order()) do
        if Utility.IsShown(key) then
            if key == "camping" then
                for _, a in ipairs(Utility.CAMPING) do
                    if API.ItemCount(a.item) > 0 and (a.kit or campfire) then
                        list[#list + 1] = { key = a.key, kind = "item", value = a.item }
                    end
                end
            else
                local a = BY_KEY[key]
                if a.item then
                    if API.ItemCount(a.item) > 0 then list[#list + 1] = { key = key, kind = "item", value = a.item } end
                else
                    local id = Utility.KnownSpell(a)
                    if id then list[#list + 1] = { key = key, kind = "spell", value = id } end
                end
            end
        end
    end
    return list
end

-- ------------------------------------------------------------------
-- The frame and its buttons (made at load: binding targets exist early)
-- ------------------------------------------------------------------

local frame = CreateFrame("Frame", "GlassActionBarsUtilityFrame", UIParent)
frame:SetSize(Utility.SIZE, Utility.SIZE)
frame:SetPoint("RIGHT", UIParent, "RIGHT", -150, 0)
frame:SetFrameStrata("MEDIUM")
frame:SetMovable(true)            -- before the secure children exist
frame:SetClampedToScreen(true)
frame:Hide()
Utility.frame = frame

local buttons, regions, state = {}, {}, {}   -- key -> button; button -> regions; button -> { kind, value, key }
Utility.buttons = buttons

local function tooltip(self)
    local s = state[self]
    if not s or not s.kind then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    if s.kind == "item" then GameTooltip:SetItemByID(s.value) else GameTooltip:SetSpellByID(s.value) end
    GameTooltip:Show()
end

local function makeButton(key)
    local b = CreateFrame("Button", Utility.PREFIX .. key, frame, "SecureActionButtonTemplate")
    b:SetSize(Utility.SIZE, Utility.SIZE)
    -- Both edges: the client acts on the one ActionButtonUseKeyDown picks,
    -- once (Apotheca, measured for clicks and CLICK bindings).
    b:RegisterForClicks("AnyUp", "AnyDown")
    local r = {}
    r.icon = b:CreateTexture(nil, "BACKGROUND")
    r.icon:SetAllPoints(b)
    r.cooldown = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
    r.cooldown:SetAllPoints(b)
    b:SetPushedTexture("Interface\\Buttons\\UI-Quickslot-Depress")
    r.pushed = b:GetPushedTexture()
    b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square")
    r.highlight = b:GetHighlightTexture()
    -- The text over the cooldown and the glass rim (button + 1).
    local over = CreateFrame("Frame", nil, b)
    over:SetAllPoints(b)
    over:SetFrameLevel(b:GetFrameLevel() + 5)
    r.count = over:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    r.count:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -2, 2)
    r.hotkey = over:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmallGray")
    r.hotkey:SetPoint("TOPRIGHT", b, "TOPRIGHT", -2, -3)
    b:SetScript("OnEnter", tooltip)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:Hide()
    buttons[key], regions[b], state[b] = b, r, { key = key }
end
for _, a in ipairs(Utility.ACTIONS) do makeButton(a.key) end
for _, a in ipairs(Utility.CAMPING) do makeButton(a.key) end

-- ------------------------------------------------------------------
-- Visuals: cooldowns, key text, counts (no secure change: safe in combat)
-- ------------------------------------------------------------------

-- 123's ApplySpellCooldown: a duration object straight to the widget; nil clears.
local function spellCooldown(cd, spellID)
    local ok, d = pcall(C_Spell.GetSpellCooldownDuration, spellID)
    if not ok then return end
    if not API.IsSecret(d) and d == nil then cd:Clear() return end
    pcall(cd.SetCooldownFromDurationObject, cd, d)
end

-- 123's ApplyItemCooldown: start and duration straight to the widget, never compared.
local function itemCooldown(cd, itemID)
    local ok, start, dur = pcall(C_Container.GetItemCooldown, itemID)
    if not ok then return end
    if API.IsSecret(start) or API.IsSecret(dur) then pcall(cd.SetCooldown, cd, start, dur) return end
    if type(start) ~= "number" or type(dur) ~= "number" then cd:Clear() return end
    cd:SetCooldown(start, dur)
end

-- The Hearthstone through its use spell's duration object (the probe's Q6:
-- 8690, plain in combat); every other item through GetItemCooldown, the one
-- path not yet shown wrong for camping's shared hour.
function Utility.ApplyCooldown(b)
    local s, cd = state[b], regions[b].cooldown
    if s.kind == "spell" then return spellCooldown(cd, s.value) end
    if s.value == Utility.HEARTHSTONE then
        local ok, _, spellID = pcall(C_Item.GetItemSpell, s.value)
        spellID = ok and API.Plain(spellID)
        if type(spellID) == "number" then return spellCooldown(cd, spellID) end
    end
    itemCooldown(cd, s.value)
end

-- A bound key as an action bar shows it: CTRL-SHIFT-F becomes csF (Apotheca's).
local SHORT_KEYS = { { "CTRL%-", "c" }, { "SHIFT%-", "s" }, { "ALT%-", "a" }, { "NUMPAD", "N" },
    { "MOUSEWHEELUP", "MwU" }, { "MOUSEWHEELDOWN", "MwD" }, { "BUTTON", "M" } }
function Utility.ShortKey(key)
    if type(key) ~= "string" then return "" end
    for _, r in ipairs(SHORT_KEYS) do key = key:gsub(r[1], r[2]) end
    return key
end

function Utility.RefreshVisuals()
    for b, s in pairs(state) do
        if s.kind then
            API.Try("utility:cooldown", Utility.ApplyCooldown, b)
            local r = regions[b]
            r.hotkey:SetText(isBound[s.key] and Utility.ShortKey(GetBindingKey(Utility.BindingAction(s.key))) or "")
            local camping = BY_KEY[s.key] and BY_KEY[s.key].item and s.key ~= "hearthstone"
            r.count:SetText(camping and tostring(API.ItemCount(s.value)) or "")
        end
    end
end

-- ------------------------------------------------------------------
-- Layout (the dock's callbacks) and the rebuild
-- ------------------------------------------------------------------

local shownList, lastGeom = {}, nil

local function arrange()
    local g = lastGeom
    -- Each part the bar's when the dock gives it (the player matches it), else our own.
    local size = g and g.size or Utility.LayoutSetting("iconSize")
    local pad = g and g.padding or Utility.LayoutSetting("iconPadding")
    local rows = math.max(1, g and g.rows or Utility.LayoutSetting("rows"))
    local vertical
    if g and g.orientation then vertical = g.orientation == 1 else vertical = Utility.LayoutSetting("orientation") == "VERTICAL" end
    local n = #shownList
    if n == 0 then frame:SetSize(size, size) return end
    local cols
    if vertical then
        cols = math.min(rows, n)
        rows = math.ceil(n / cols)
    else
        cols = math.ceil(n / rows)
        rows = math.min(rows, n)
    end
    frame:SetSize(cols * size + (cols - 1) * pad, rows * size + (rows - 1) * pad)
    for i, b in ipairs(shownList) do
        local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
        b:SetSize(size, size)
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", frame, "TOPLEFT", col * (size + pad), -row * (size + pad))
    end
end

-- The dock's Layout(geom): the bar's geometry, or nil for our own.
function Utility.Layout(geom)
    lastGeom = geom
    arrange()
end

-- The undocked spot: the saved one, else the default point.
local function savedPos()
    local s = saved()
    return s and Utility.ValidPos(s.pos) and s.pos or nil
end
local function placeAt(x, y)
    frame:ClearAllPoints()
    frame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", x, y)
    GAB.Edges.Request()   -- placed by hand: the screen edges may have moved
end
local function restorePos()
    local p = savedPos()
    if p then placeAt(p.x, p.y) else
        frame:ClearAllPoints()
        frame:SetPoint("RIGHT", UIParent, "RIGHT", -150, 0)
    end
end

-- The frame's bottom-left corner, saved and anchored there; false when
-- unreadable (the frame stays as it is).
local function saveHere()
    local x, y = API.Plain(frame:GetLeft()), API.Plain(frame:GetBottom())
    if not GAB.Settings.SetUtilityPosition(x, y) then return false end
    placeAt(x, y)
    return true
end

-- Dragging (Apotheca's, measured there): no StartMoving or
-- StopMovingOrSizing in combat on a frame that parents secure buttons.
-- PLAYER_REGEN_DISABLED stops a drag before lockdown; if lockdown is already
-- on, the stop waits for the fight's end, the overlay staying up to keep
-- clicks off the buttons, and the bar goes where combat caught it.
local dragging, stopPending, dropPos = false, false, nil
local hosted = false

-- Undocked by the player (or a first placement failed): our own geometry, at
-- the saved spot; undocking with none saves where the dock had it. Never
-- during a drag: the drop places it.
function Utility.OnHosted(isHosted)
    if isHosted then hosted = true return end
    local was = hosted
    hosted, lastGeom = false, nil
    if InCombatLockdown() then return end
    arrange()
    if dragging then return end
    if savedPos() then restorePos()
    elseif was and GAB.Dock.Setting("utility", "bar") == false then saveHere() end
end

local function stopDrag()
    if not dragging then return end
    if InCombatLockdown() then
        if not stopPending then
            dropPos = { x = API.Plain(frame:GetLeft()), y = API.Plain(frame:GetBottom()) }
        end
        stopPending = true
        return
    end
    frame:StopMovingOrSizing()
    local p = dropPos
    dragging, stopPending, dropPos = false, false, nil
    if p then
        if GAB.Settings.SetUtilityPosition(p.x, p.y) then placeAt(p.x, p.y) else restorePos() end
    elseif not saveHere() then
        restorePos()
    end
end

-- The overlay: shown while Alt is held over the bar out of combat; it takes
-- the drag and keeps clicks off the secure buttons under it. Polled while
-- Alt is down (no event says the pointer reached the bar), up or dragging.
local mover = CreateFrame("Frame", nil, frame)
mover:SetAllPoints(frame)
mover:SetFrameStrata("DIALOG")
mover:EnableMouse(true)
mover:RegisterForDrag("LeftButton")
mover:Hide()
do
    local bg = mover:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.5, 0.83, 1, 0.35)
    local text = mover:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    text:SetPoint("CENTER")
    text:SetText("Drag")
end

local poller = CreateFrame("Frame")
local updateMover
local sincePoll = 0
local function poll(_, elapsed)
    sincePoll = sincePoll + elapsed
    if sincePoll >= 0.05 then
        sincePoll = 0
        updateMover()
    end
end

function updateMover()
    if dragging then
        if stopPending then
            if not InCombatLockdown() then stopDrag(); mover:Hide() end
        elseif not IsAltKeyDown() or InCombatLockdown() then
            stopDrag()
            if not stopPending then mover:Hide() end
        end
    elseif IsAltKeyDown() and not InCombatLockdown() and API.Plain(frame:IsVisible()) == true
            and API.Plain(frame:IsMouseOver()) == true then
        mover:Show()
    else
        mover:Hide()
    end
    poller:SetScript("OnUpdate", (dragging or mover:IsShown() or IsAltKeyDown()) and poll or nil)
end
Utility.UpdateMover = updateMover

mover:SetScript("OnDragStart", function()
    if InCombatLockdown() or not IsAltKeyDown() then return end
    -- Undock first: a dock pass never moves the bar under the pointer.
    if GAB.Dock.Setting("utility", "bar") ~= false then GAB.Settings.SetDock("utility", "bar", false) end
    dragging = true
    frame:StartMoving()
end)
mover:SetScript("OnDragStop", function()
    stopDrag()
    updateMover()
end)
-- Never leave the frame on the pointer (in combat this only marks the stop).
frame:SetScript("OnHide", function()
    stopDrag()
    updateMover()
end)

local function clear(b)
    b:SetAttribute("type", nil)
    b:SetAttribute("spell", nil)
    b:SetAttribute("item", nil)
    state[b].kind, state[b].value = nil, nil
    b:Hide()
end

-- Over the stock action buttons: docked beside a bar, the bar may overlap
-- another one (a 4-column bar's third row, in the owner's layout), and a
-- stock button above ours took its clicks and tooltips. A button you can see
-- is a button you can click. Out of combat only (it parents secure buttons).
local function raise()
    local top = 0
    for _, b in ipairs(GAB.Dock.BARS) do
        for i = 1, 12 do
            local button = rawget(_G, b[2] .. i)
            local level = button and API.Plain(button:GetFrameLevel())
            if type(level) == "number" and level > top then top = level end
        end
    end
    local want = top + 2
    if API.Plain(frame:GetFrameLevel()) == want then return end
    frame:SetFrameLevel(want)
    for _, b in pairs(buttons) do GAB.Buttons.Restyle(b) end   -- the glass follows the new level
end
Utility.Raise = raise

local pending, cleared = false, false
function Utility.Reconcile()
    if InCombatLockdown() then
        pending = true
        return
    end
    pending = false
    API.Try("utility:raise", raise)
    if not Utility.Enabled() then
        if not cleared then
            for _, b in pairs(buttons) do clear(b) end
            cleared = true
        end
        shownList = {}
        frame:Hide()
        return
    end
    cleared = false
    local active, list = {}, {}
    for _, e in ipairs(Utility.Collect()) do
        local b = buttons[e.key]
        b:SetAttribute("type", e.kind)
        if e.kind == "item" then
            b:SetAttribute("spell", nil)
            b:SetAttribute("item", "item:" .. e.value)
            local ok, icon = pcall(C_Item.GetItemIconByID, e.value)
            regions[b].icon:SetTexture(ok and API.Plain(icon) or "Interface\\Icons\\INV_Misc_QuestionMark")
        else
            b:SetAttribute("item", nil)
            b:SetAttribute("spell", e.value)
            local ok, icon = pcall(C_Spell.GetSpellTexture, e.value)
            regions[b].icon:SetTexture(ok and API.Plain(icon) or "Interface\\Icons\\INV_Misc_QuestionMark")
        end
        state[b].kind, state[b].value = e.kind, e.value
        b:Show()
        active[b] = true
        list[#list + 1] = b
    end
    for _, b in pairs(buttons) do
        if not active[b] then clear(b) end
    end
    shownList = list
    arrange()
    frame:SetShown(#list > 0)
    Utility.RefreshVisuals()
    GAB.Dock.RequestLayout("utility")
end

function Utility.IsPending() return pending end

-- ------------------------------------------------------------------
-- Binding names, events, start
-- ------------------------------------------------------------------

-- The binding labels in the client's language once it can name them; a
-- name not ready yet is retried on GET_ITEM_INFO_RECEIVED / SPELLS_CHANGED.
local namesPending = true
function Utility.LocalizeBindingNames()
    local missing = false
    for _, key in ipairs(Utility.BINDING_KEYS) do
        local a, name = BY_KEY[key], nil
        if a.item then
            local ok, n = pcall(C_Item.GetItemNameByID, a.item)
            name = ok and API.Plain(n)
        else
            local ok, n = pcall(C_Spell.GetSpellName, a.spells[#a.spells])
            name = ok and API.Plain(n)
        end
        if type(name) == "string" and name ~= "" then
            _G["BINDING_NAME_" .. Utility.BindingAction(key)] = name
        else
            missing = true
        end
    end
    namesPending = missing
end

local driver = CreateFrame("Frame")
local wanted = false
local function onUpdate()
    driver:SetScript("OnUpdate", nil)
    if wanted then
        wanted = false
        Utility.Reconcile()
    end
end

-- A rebuild on the next frame: coalesces bursts (SPELLS_CHANGED, UNIT_AURA).
function Utility.Refresh()
    wanted = true
    driver:SetScript("OnUpdate", onUpdate)
end

local skinned = false
local function skin()
    if skinned or GAB.db.skin == false then return end
    skinned = true
    for _, b in pairs(buttons) do
        API.Try("utility:skin", GAB.Buttons.Build, b, regions[b])
    end
end

local started = false
function Utility.Start()
    if started then return end
    started = true
    if not InCombatLockdown() then skin() end
    GAB.Dock.Register({ id = "utility", label = "Utility bar", frame = frame, default = Utility.DOCK,
        Layout = Utility.Layout, OnHosted = Utility.OnHosted })
    Utility.LocalizeBindingNames()
    Utility.ReadCampfire()
    -- The saved spot until a dock pass places the bar (its target may be
    -- unavailable on this character); a /reload in combat waits for the fight.
    local posPending = false
    if savedPos() then
        if InCombatLockdown() then posPending = true else restorePos() end
    end
    driver:SetScript("OnEvent", function(_, event, unit)
        if event == "PLAYER_REGEN_ENABLED" then
            -- An interrupted drag ends first (updateMover), before a rebuild can resize or hide the frame.
            updateMover()
            if posPending then
                posPending = false
                if not hosted then restorePos() end
            end
            skin()
            -- A combat read may have been unknown: a change found now rebuilds too.
            if Utility.ReadCampfire() or pending then Utility.Reconcile() end
        elseif event == "PLAYER_REGEN_DISABLED" then
            -- The last moment before lockdown: a drag stops cleanly, where it is.
            if dragging and not InCombatLockdown() then stopDrag() end
            updateMover()
        elseif event == "MODIFIER_STATE_CHANGED" then
            updateMover()
        elseif event == "UNIT_AURA" then
            if unit == "player" and Utility.ReadCampfire() then Utility.Refresh() end
        elseif event == "BAG_UPDATE_COOLDOWN" or event == "SPELL_UPDATE_COOLDOWN" or event == "UPDATE_BINDINGS" then
            Utility.RefreshVisuals()
        elseif event == "GET_ITEM_INFO_RECEIVED" then
            if namesPending then Utility.LocalizeBindingNames() end
        else
            if event == "SPELLS_CHANGED" and namesPending then Utility.LocalizeBindingNames() end
            Utility.Refresh()
        end
    end)
    API.RegisterEvents(driver, { "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED",
        "MODIFIER_STATE_CHANGED", "SPELLS_CHANGED",
        "SKILL_LINES_CHANGED", "LEARNED_SPELL_IN_SKILL_LINE", "BAG_UPDATE_DELAYED", "UNIT_AURA",
        "BAG_UPDATE_COOLDOWN", "SPELL_UPDATE_COOLDOWN", "UPDATE_BINDINGS", "GET_ITEM_INFO_RECEIVED" }, "utility")
    Utility.Refresh()
end

Utility._test = { regions = regions, state = state, frame = frame,
    shown = function() return shownList end, geom = function() return lastGeom end,
    setCampfire = function(v) campfire = v end, mover = mover, poller = poller,
    dragging = function() return dragging, stopPending end }
