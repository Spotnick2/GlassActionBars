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
-- Feed Pet (#65): a hunter's button, shown with a live hunter pet out and
-- food it eats in the bags. Blizzard's secure path: type "spell", 6991, and
-- target-bag / target-slot, which OnActionButtonClick uses after the action
-- whenever a spell awaits an item (SecureTemplates.lua), whatever the action
-- was, none included. So the button is DISARMED at rest: the release's
-- PreClick (out of combat, useOnKeyDown false) chooses the food again,
-- checks, and arms it, type last; PostClick disarms, and so do every
-- Reconcile and both combat edges. The food: GlassPearls' order (its pet
-- care pearl, #38), so both feed the same.
--
-- The lock (#34, key lockbars): off until the player ticks it; an insecure
-- button that flips the "Lock Action Bars" CVar (lockActionBars) out of
-- combat, its padlock open or closed with it. Not through Settings.SetValue:
-- that runs the setting's Lua callbacks on our stack, while Blizzard's
-- accessor reads the CVar fresh at each drag. In combat it does nothing
-- (dimmed) until GABProbe's lock procedure measures a combat write.
--
-- Other addons' buttons (GlassActionBars.RegisterButton, #52): key
-- provider:<id>, off until the player ticks it; an insecure button made the
-- first time it shows, its click asking the provider's IsEnabled each time.
-- The provider hears OnHosted(true/false) when its button joins or leaves the
-- enabled bar (once with false after it registers, if not shown).
--
-- Spells dropped on the bar (#86): key spell:<id>, in the saved order (being
-- there is the entry), shown on the characters that know that rank; a secure
-- GlassActionBarsUtilSpell_<id> made the first time one shows, armed with the
-- spell's plain name (#133): the highest known rank, lowered by the client for
-- a low-level target, where the ID would force the dropped rank. A spell of a
-- built-in entry turns that entry on instead. Editing on the bar: drop a
-- spell on a button (or click one with a spell on the cursor), Shift-drag
-- (Blizzard's Pick Up Action key) a button along the bar or off it. A press
-- that places or picks up never acts (the gesture, below).
--
-- Placement is the dock's (client "utility", Dock.lua): docked right of Action
-- Bar 1 by default. Layout(geom) lays the buttons out with the bar's geometry,
-- or the bar's own (LAYOUT, Apotheca's keys) when geom is nil. Alt-drag moves
-- the bar anywhere: the drag undocks it at its start (so no dock pass moves
-- it mid-drag) and the drop saves the spot; undocked, the bar sits there.
--
-- A second bar (#86): off until turned on, client "utility2", docked left of
-- Action Bar 1. Any entry can be on either bar (utility.bar[key] = 2); its
-- button moves to that bar's frame at the rebuild. Turned off, a bar's
-- entries show nowhere. An enabled bar with nothing on it keeps one empty
-- slot, a place to drop a spell or drag a button to.

GlassActionBars = GlassActionBars or {}
local GAB = GlassActionBars
local API = GAB.API
local Utility = {}
GAB.Utility = Utility

Utility.PREFIX = "GlassActionBarsUtil_"
Utility.PROVIDER_PREFIX = "GlassActionBarsUtilProvider_"
Utility.DIM = 0.4   -- a provider button's icon while its IsEnabled() is false
Utility.HEARTHSTONE = 6948
Utility.CAMPFIRE_AURA = 1283391   -- "Campfire Nearby" (Wowhead; to confirm in game)
Utility.FEED_PET = 6991
Utility.FOOD_BAND = 10            -- food within this many levels of the pet: the cheapest (GlassPearls')
Utility.SIZE, Utility.PADDING = 36, 4
Utility.DOCK = { bar = 1, side = "RIGHT", align = "END", gap = 4, match = true }
-- The second bar (#86): off until turned on, docked left of Action Bar 1.
Utility.DOCK2 = { bar = 1, side = "LEFT", align = "END", gap = 4, match = true }
Utility.BARS = 2
-- The bar's own layout (undocked, or docked without matching): Apotheca's
-- setting keys, so its import is a copy. VERTICAL: `rows` counts columns.
Utility.LAYOUT = { orientation = "HORIZONTAL", rows = 1, iconSize = Utility.SIZE, iconPadding = Utility.PADDING }
local LAYOUT_RANGE = { rows = { 1, 12 }, iconSize = { 16, 64 }, iconPadding = { 0, 16 } }

-- Apotheca's actions, in their default order. `spells`: candidate IDs,
-- highest rank first (only one is known at a time). `measured`: on 70334
-- (Apotheca's FOREVER-PROBE.md); the rest are Vanilla's IDs, carried forward.
Utility.ACTIONS = {
    { key = "hearthstone", label = "Hearthstone", item = 6948, measured = true },
    { key = "feedpet", label = "Feed Pet", spells = { 6991 }, feed = true },   -- #65, not Apotheca's
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
    -- Herbalism's and Skinning's camp-feature spells (#90), not their gathering
    -- casts (a herb or a corpse as the target): learned with the skill
    -- (SkillLineAbility, acquire 2, 70938), like Fishing's Bait and Tackle.
    -- Mining has none (#92): its entry, a gathering cast, was taken out.
    { key = "skinning", label = "Tanning", spells = { 1278068 }, measured = true },
    { key = "herbalism", label = "Gardening", spells = { 1278062 }, measured = true },
    { key = "smelting", label = "Smelting", spells = { 2656 } },
    { key = "poisons", label = "Poisons", spells = { 2842 } },
    { key = "disenchant", label = "Disenchant", spells = { 13262 }, measured = true },
    { key = "findherbs", label = "Find Herbs", spells = { 2383 } },
    { key = "findminerals", label = "Find Minerals", spells = { 2580 } },
    { key = "picklock", label = "Pick Lock", spells = { 1804 } },
    { key = "comprehend", label = "Comprehend Scroll", spells = { 1296017 } },   -- #76, a mage's (trainer, level 6)
    { key = "lockbars", label = "Lock action bars", lock = true, optIn = true },   -- #34, off by default
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
-- A built-in entry's spells (every rank): a drop of one is that entry.
local BUILTIN_SPELL = {}
for _, a in ipairs(Utility.ACTIONS) do
    for _, id in ipairs(a.spells or {}) do BUILTIN_SPELL[id] = a.key end
end

-- The keys of the player's order: the actions, then the Camping group.
Utility.ORDER_KEYS = {}
for _, a in ipairs(Utility.ACTIONS) do Utility.ORDER_KEYS[#Utility.ORDER_KEYS + 1] = a.key end
Utility.ORDER_KEYS[#Utility.ORDER_KEYS + 1] = "camping"
local isOrderKey = {}
for _, k in ipairs(Utility.ORDER_KEYS) do isOrderKey[k] = true end

-- A key the saved settings may hold: an order key, or a provider's button
-- (provider:<id>, kept even before that provider registers; #9's PR 2).
function Utility.ValidKey(k)
    return type(k) == "string" and (isOrderKey[k] or k:match("^provider:[%w_]+$") ~= nil
        or Utility.SpellId(k) ~= nil)
end

-- A provider key's id, else nil.
function Utility.ProviderId(k)
    return type(k) == "string" and k:match("^provider:([%w_]+)$") or nil
end

-- A dropped spell's key (#86): spell:<id>. Its ID, else nil.
Utility.SPELL_PREFIX = "GlassActionBarsUtilSpell_"
Utility.MAX_SPELLS = 40
function Utility.SpellId(k)
    local id = type(k) == "string" and k:match("^spell:(%d+)$")
    id = id and tonumber(id)
    return id and id > 0 and id < 2147483648 and id or nil
end

-- The dropped spells' keys in an order.
function Utility.SpellCount(order)
    local n = 0
    for _, k in ipairs(order) do if Utility.SpellId(k) then n = n + 1 end end
    return n
end

-- A key off until the player turns it on: a provider's, or an opt-in action (the lock).
function Utility.OptIn(k)
    if Utility.ProviderId(k) then return true end
    return BY_KEY[k] ~= nil and BY_KEY[k].optIn == true
end

-- The registered definition behind a provider key (nil: not registered
-- this session, e.g. an alt without that addon).
local function providerDef(k)
    local id = Utility.ProviderId(k)
    return id and GAB.ProvidedButton(id) or nil
end

-- A key with something behind it this session: every built-in key, a
-- provider's once it registered.
function Utility.Registered(k)
    if Utility.ProviderId(k) then return providerDef(k) ~= nil end
    -- A dropped spell: this character knows that rank (a lower rank stays
    -- known after training: FOREVER-PROBE session 9); another class's keeps its slot.
    local id = Utility.SpellId(k)
    if id then return API.SpellKnown(id) == true end
    return isOrderKey[k] == true
end

-- A spell's plain name (no rank), else nil.
function Utility.SpellName(id)
    local ok, name = pcall(C_Spell.GetSpellName, id)
    name = ok and API.Plain(name)
    return type(name) == "string" and name ~= "" and name or nil
end

-- The entry's name in Options. A dropped spell's has no rank: it casts by
-- name (#133).
function Utility.Label(k)
    if k == "camping" then return "Camping items" end
    local def = providerDef(k)
    if def then return def.label end
    local id = Utility.SpellId(k)
    if id then return Utility.SpellName(id) or ("Spell " .. id) end
    return BY_KEY[k] and BY_KEY[k].label or k
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

-- Bar n's own settings: bar 1's are the utility table's own keys
-- (Apotheca's import keys), bar 2's its `second` table; else nil.
local function barSettings(n)
    local s = saved()
    if (n or 1) == 1 then return s end
    return s and type(s.second) == "table" and s.second or nil
end

-- Bar n (default 1) is on: bar 1 unless turned off, bar 2 once turned on.
function Utility.Enabled(n)
    local s = barSettings(n)
    if s and s.enabled ~= nil then return s.enabled == true end
    return (n or 1) == 1
end

-- The bar an order key is on (#86): 2 when assigned there, else 1.
function Utility.BarOf(key)
    local s = saved()
    return s and type(s.bar) == "table" and s.bar[key] == 2 and 2 or 1
end

-- A built-in entry shows unless turned off; a provider's or an opt-in one
-- only once turned on.
function Utility.IsShown(key)
    local s = saved()
    local v
    if s and type(s.show) == "table" then v = s.show[key] end
    if Utility.OptIn(key) then return v == true end
    return v ~= false
end

-- A valid value for one of LAYOUT's keys.
function Utility.ValidLayout(key, v)
    if key == "orientation" then return v == "HORIZONTAL" or v == "VERTICAL" end
    local r = LAYOUT_RANGE[key]
    return r ~= nil and type(v) == "number" and v >= r[1] and v <= r[2] and (key ~= "rows" or v % 1 == 0)
end

-- One of bar n's (default 1) own layout settings.
function Utility.LayoutSetting(key, n)
    local s = barSettings(n)
    if s and Utility.ValidLayout(key, s[key]) then return s[key] end
    return Utility.LAYOUT[key]
end

-- A saved position: the bottom-left corner, finite UIParent offsets.
local function finite(v) return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge end
function Utility.ValidPos(p)
    return type(p) == "table" and finite(p.x) and finite(p.y)
end

-- The saved order (valid keys, once each: a provider's kept even when it
-- isn't registered this session), then any built-in key it lacks, then any
-- registered provider it lacks.
function Utility.Order()
    local s, out, seen = saved(), {}, {}
    for _, k in ipairs(s and type(s.order) == "table" and s.order or {}) do
        if Utility.ValidKey(k) and not seen[k] then out[#out + 1] = k; seen[k] = true end
    end
    for _, k in ipairs(Utility.ORDER_KEYS) do
        if not seen[k] then out[#out + 1] = k; seen[k] = true end
    end
    for _, def in ipairs(GAB.ProvidedButtons()) do
        local k = "provider:" .. def.id
        if not seen[k] then out[#out + 1] = k; seen[k] = true end
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

-- A yes/no read: true or false when plain, nil when it threw, was secret or
-- wasn't a boolean (GetCursorInfo's "nothing" is its nil: see CanFeed).
local function flag(fn, ...)
    local ok, v = pcall(fn, ...)
    if not ok or API.IsSecret(v) or type(v) ~= "boolean" then return nil end
    return v
end

-- A live hunter pet out, plainly (HasPetUI's second return: a hunter's pet,
-- not a warlock's; it says nothing of death).
function Utility.PetReady()
    if flag(UnitExists, "pet") ~= true or flag(UnitIsDead, "pet") ~= false then return false end
    local ok, _, isHunter = pcall(HasPetUI)
    return ok and not API.IsSecret(isHunter) and isHunter == true
end

-- The food in bags 0-4 the pet eats, GlassPearls' order: within FOOD_BAND
-- levels of the pet the cheapest first, else the highest item level; ties by
-- bag and slot. { bag, slot, id, count (that item in all the bags) } or nil.
-- An item not in the cache yet is asked for once; GET_ITEM_INFO_RECEIVED
-- rebuilds the bar.
local foodWaiting = {}
local function plainNumber(v) v = API.Plain(v); return type(v) == "number" and v or nil end
function Utility.FoodChoice()
    local list, totals, edible = {}, {}, {}
    for bag = 0, 4 do
        local ok, n = pcall(C_Container.GetContainerNumSlots, bag)
        n = ok and plainNumber(n) or 0
        for slot = 1, n do
            local ok2, info = pcall(C_Container.GetContainerItemInfo, bag, slot)
            if ok2 and not API.IsSecret(info) and type(info) == "table" then
                local id, count, locked = plainNumber(info.itemID), plainNumber(info.stackCount), API.Plain(info.isLocked)
                if id and count then
                    if edible[id] == nil then edible[id] = flag(C_PetInfo.CanPetEatItem, id) == true end
                    if edible[id] then
                        totals[id] = (totals[id] or 0) + count
                        local ok3, name, _, _, level, _, _, _, _, _, _, price = pcall(C_Item.GetItemInfo, id)
                        level, price = ok3 and plainNumber(level), ok3 and plainNumber(price)
                        if not (ok3 and API.Plain(name) ~= nil and level and price) then
                            if not foodWaiting[id] then
                                foodWaiting[id] = true
                                pcall(C_Item.RequestLoadItemDataByID, id)
                            end
                        elseif locked == false then
                            list[#list + 1] = { bag = bag, slot = slot, id = id, level = level, price = price }
                        end
                    end
                end
            end
        end
    end
    if #list == 0 then return nil end
    local okLevel, petLevel = pcall(UnitLevel, "pet")
    petLevel = okLevel and plainNumber(petLevel) or nil
    local floor = petLevel and petLevel > 0 and petLevel - Utility.FOOD_BAND or nil
    for _, c in ipairs(list) do c.within = floor ~= nil and c.level >= floor end
    table.sort(list, function(a, b)
        if a.within ~= b.within then return a.within end
        if a.within then
            if a.price ~= b.price then return a.price < b.price end
        elseif a.level ~= b.level then
            return a.level > b.level
        end
        if a.bag ~= b.bag then return a.bag < b.bag end
        return a.slot < b.slot
    end)
    local c = list[1]
    return { bag = c.bag, slot = c.slot, id = c.id, count = totals[c.id] }
end

-- A food we asked the cache for arrived: true once per item.
function Utility.FoodArrived(id)
    if API.IsSecret(id) or type(id) ~= "number" or not foodWaiting[id] then return false end
    foodWaiting[id] = nil
    return true
end

-- The ordered list of { key, kind = "spell"|"item"|"provider", value } bar
-- n (default 1) shows.
function Utility.Collect(n)
    local list = {}
    n = n or 1
    for _, key in ipairs(Utility.Order()) do
        if Utility.BarOf(key) == n and Utility.IsShown(key) and Utility.Registered(key) then
            if Utility.ProviderId(key) then
                list[#list + 1] = { key = key, kind = "provider", value = Utility.ProviderId(key) }
            elseif Utility.SpellId(key) then
                list[#list + 1] = { key = key, kind = "spell", value = Utility.SpellId(key), byName = true }
            elseif key == "camping" then
                for _, a in ipairs(Utility.CAMPING) do
                    if API.ItemCount(a.item) > 0 and (a.kit or campfire) then
                        list[#list + 1] = { key = a.key, kind = "item", value = a.item }
                    end
                end
            else
                local a = BY_KEY[key]
                if a.lock then
                    list[#list + 1] = { key = key, kind = "lock" }
                elseif a.feed then
                    local food = Utility.KnownSpell(a) and Utility.PetReady() and Utility.FoodChoice()
                    if food then list[#list + 1] = { key = key, kind = "feed", value = Utility.FEED_PET, food = food } end
                elseif a.item then
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
-- The bars and their buttons (made at load: binding targets exist early)
-- ------------------------------------------------------------------

-- One table per bar (#86): its frame, the Alt mover, the buttons it shows,
-- its layout, its dock state and its drag. Bar 1 is #9's Utility bar: frame
-- GlassActionBarsUtilityFrame, dock client "utility", its settings
-- GlassActionBarsDB.utility's own keys (Apotheca's import).
local bars = {}
Utility.bars = bars
local DEFAULT_POINT = { { "RIGHT", "RIGHT", -150, 0 }, { "RIGHT", "RIGHT", -150, -60 } }

local function newBar(n)
    local f = CreateFrame("Frame", "GlassActionBarsUtilityFrame" .. (n == 1 and "" or n), UIParent)
    f:SetSize(Utility.SIZE, Utility.SIZE)
    local p = DEFAULT_POINT[n]
    f:SetPoint(p[1], UIParent, p[2], p[3], p[4])
    f:SetFrameStrata("MEDIUM")
    f:SetMovable(true)            -- before the secure children exist
    f:SetClampedToScreen(true)
    f:Hide()
    bars[n] = { index = n, frame = f, dockId = n == 1 and "utility" or "utility" .. n,
        shown = {}, geom = nil, cols = 1, hosted = false,
        dragging = false, stopPending = false, dropPos = nil, posPending = false }
    return bars[n]
end
for n = 1, Utility.BARS do newBar(n) end
Utility.frame = bars[1].frame

local buttons, regions, state = {}, {}, {}   -- key -> button; button -> regions; button -> { kind, value, key, bar }
Utility.buttons = buttons

-- ------------------------------------------------------------------
-- The lock (#34): the "Lock Action Bars" CVar
-- ------------------------------------------------------------------

Utility.LOCK_CVAR = "lockActionBars"

-- Whether the action bars are locked: true, false, or nil when unreadable.
function Utility.BarsLocked()
    local ok, v = pcall(C_CVar.GetCVarBool, Utility.LOCK_CVAR)
    if not ok or API.IsSecret(v) or type(v) ~= "boolean" then return nil end
    return v
end

-- Blizzard's own name for the setting, else ours.
function Utility.LockLabel()
    local t = rawget(_G, "LOCK_ACTIONBAR_TEXT")
    if type(t) == "string" and not API.IsSecret(t) and t ~= "" then return t end
    return "Lock Action Bars"
end

-- On the bar, out of combat, a left click: the other state. Its binding
-- does nothing while the lock isn't on the bar (state kind cleared).
local function lockClick(self, mouseButton)
    if mouseButton ~= "LeftButton" or InCombatLockdown() then return end
    local s = state[self]
    if not (s and s.kind == "lock") then return end
    local locked = Utility.BarsLocked()
    if locked == nil then return end
    pcall(C_CVar.SetCVar, Utility.LOCK_CVAR, locked and "0" or "1")
    Utility.RefreshVisuals()
end

local function tooltip(self)
    local s = state[self]
    if not s or not s.kind then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    if s.kind == "lock" then
        local locked = Utility.BarsLocked()
        GameTooltip:SetText(Utility.LockLabel())
        if locked ~= nil then GameTooltip:AddLine(locked and "Locked" or "Unlocked", 1, 1, 1) end
        if InCombatLockdown() then
            GameTooltip:AddLine("Not in combat", 1, 0.3, 0.3)
        elseif locked ~= nil then
            GameTooltip:AddLine(locked and "Click to unlock" or "Click to lock", 0.6, 0.8, 1)
        end
        GameTooltip:Show()
        return
    end
    if s.kind == "item" then GameTooltip:SetItemByID(s.value) else GameTooltip:SetSpellByID(s.value) end
    if s.kind == "feed" and s.food then
        local ok, name = pcall(C_Item.GetItemNameByID, s.food.id)
        name = ok and API.Plain(name)
        if type(name) ~= "string" or name == "" then name = "item " .. s.food.id end
        GameTooltip:AddLine(("Feeds: %s (%d)"):format(name, s.food.count), 1, 1, 1)
    end
    GameTooltip:Show()
end

-- ------------------------------------------------------------------
-- Feed Pet's click (#65): armed only for the release that feeds
-- ------------------------------------------------------------------

local FEED_ATTRS = { "type", "spell", "target-bag", "target-slot" }

-- Out of combat only: in lockdown the attributes can't change (the
-- PLAYER_REGEN_ENABLED disarm covers that).
function Utility.DisarmFeed()
    local b = buttons.feedpet
    if not b or InCombatLockdown() then return end
    for _, k in ipairs(FEED_ATTRS) do b:SetAttribute(k, nil) end
end

-- May the click feed `food` now? true, or false and why. Every read plain:
-- anything unknown refuses. No spell may be waiting for an item, by the two
-- tests the secure click itself uses, or it would take our food.
function Utility.CanFeed(food)
    if not food then return false, "no food" end
    if not Utility.PetReady() then return false, "no live hunter pet" end
    local ok, kind = pcall(GetCursorInfo)
    if not ok or API.IsSecret(kind) or kind ~= nil then return false, "the cursor holds something" end
    if flag(SpellIsTargeting) ~= false then return false, "a spell is waiting for a target" end
    if flag(SpellCanTargetItem) ~= false or flag(SpellCanTargetItemID) ~= false then
        return false, "a spell is waiting for an item"
    end
    if flag(C_Spell.IsSpellUsable, Utility.FEED_PET) ~= true then return false, "Feed Pet can't be cast now" end
    return true
end

local function feedPreClick(self, mouseButton, down)
    if InCombatLockdown() then return end
    Utility.DisarmFeed()
    if down or mouseButton ~= "LeftButton" then return end
    local s = state[self]
    if not (s and s.kind == "feed") then return end   -- not on the bar: its binding does nothing
    local food = Utility.FoodChoice()                 -- again now: the stack may have moved
    if not Utility.CanFeed(food) then return end
    self:SetAttribute("target-bag", food.bag)
    self:SetAttribute("target-slot", food.slot)
    self:SetAttribute("spell", Utility.FEED_PET)
    self:SetAttribute("type", "spell")                -- last: armed only now
end

local function feedPostClick(_, _, down)
    if down then return end
    Utility.DisarmFeed()
end

-- ------------------------------------------------------------------
-- Editing the bar on the bar (#86): one gesture per mouse press
-- ------------------------------------------------------------------

-- A press with anything on the cursor places it ("place"); one with the
-- pick-up modifier (Blizzard's PICKUPACTION, Shift by default) may start a
-- reorder drag ("pickup"). Neither acts on either edge. Measured on 70938
-- (docs/FOREVER-PROBE.md session 9): OnMouseDown comes before the down
-- edge's PreClick, and OnMouseUp before the up edge's; a CLICK binding fires
-- them too, with IsMouseButtonDown false, so a key press begins nothing;
-- after OnDragStart no OnMouseUp or up edge comes, so OnDragStop ends a
-- gesture too; a spellbook drop is OnReceiveDrag alone. A gesture ends a
-- frame after its own button's release (that release's click is in the same
-- dispatch), and only that: a second mouse button's press or release leaves
-- it. Secure buttons: PreClick strips the action, PostClick restores it from
-- state, out of combat only (a press whose fight starts before its release
-- may act: the stated exception).
local gesture = {}   -- button -> { mouse = <button or false>, kind = "place" | "pickup" }
local ACTION_ATTRS = { "type", "spell", "item", "target-bag", "target-slot" }

-- The cursor holds something (anything unreadable counts as something).
local function cursorHolds()
    local ok, kind = pcall(GetCursorInfo)
    return not ok or API.IsSecret(kind) or kind ~= nil
end

local function endGesture(b, g)
    C_Timer.After(0, function()
        if gesture[b] == g then gesture[b] = nil end
    end)
end

local function gestureDown(self, mouse)
    if gesture[self] or InCombatLockdown() or not state[self].kind then return end
    if flag(IsMouseButtonDown, mouse) ~= true then return end   -- a key binding's press
    local kind
    if cursorHolds() then
        kind = "place"
    elseif flag(IsModifiedClick, "PICKUPACTION") == true then
        kind = "pickup"
    end
    if kind then gesture[self] = { mouse = mouse, kind = kind } end
end

local function gestureUp(self, mouse)
    local g = gesture[self]
    if g and g.mouse == mouse then endGesture(self, g) end
end

-- A spellbook drag released here: taken at once; a click in the same
-- dispatch (none measured) is still suppressed.
local function onReceiveDrag(self)
    local g = gesture[self]
    local fresh = g == nil
    if fresh then
        g = { mouse = false, kind = "place" }
        gesture[self] = g
    end
    Utility.DropOn(self)
    if fresh then endGesture(self, g) end
end

local function onDragStart(self)
    local g = gesture[self]
    if g and g.kind == "pickup" and not InCombatLockdown() then Utility.StartReorder(self) end
end

local function onDragStop(self)
    Utility.FinishReorder(self)
    local g = gesture[self]
    if g then endGesture(self, g) end
end

local function securePreClick(self, mouseButton, down)
    if gesture[self] then
        if not InCombatLockdown() then
            for _, k in ipairs(ACTION_ATTRS) do self:SetAttribute(k, nil) end
        end
        return
    end
    if state[self].key == "feedpet" then feedPreClick(self, mouseButton, down) end
end

local function securePostClick(self, mouseButton, down)
    local g = gesture[self]
    if g then
        if not InCombatLockdown() then Utility.Arm(self) end
        -- After the secure dispatch: the rebuild can't re-arm this press.
        if g.kind == "place" and not down then Utility.DropOn(self) end
        return
    end
    if state[self].key == "feedpet" then feedPostClick(self, mouseButton, down) end
end

-- An insecure button's click (the lock, a provider's): a gesture's does nothing but place.
local function guarded(fn)
    return function(self, ...)
        local g = gesture[self]
        if g then
            if g.kind == "place" then Utility.DropOn(self) end
            return
        end
        return fn(self, ...)
    end
end

local function addEditing(b, secure)
    b:RegisterForDrag("LeftButton")
    b:SetScript("OnMouseDown", gestureDown)
    b:SetScript("OnMouseUp", gestureUp)
    b:SetScript("OnReceiveDrag", onReceiveDrag)
    b:SetScript("OnDragStart", onDragStart)
    b:SetScript("OnDragStop", onDragStop)
    if secure then
        b:SetScript("PreClick", securePreClick)
        b:SetScript("PostClick", securePostClick)
    end
end

-- A button's own regions (the template has none); `cooldown` for ours only.
local function addRegions(b, cooldown)
    local r = {}
    r.icon = b:CreateTexture(nil, "BACKGROUND")
    r.icon:SetAllPoints(b)
    r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)   -- the icon's baked border off, as Blizzard's mask does (#46)
    if cooldown then
        r.cooldown = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
        r.cooldown:SetAllPoints(b)
    end
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
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:Hide()
    return r
end

local function makeButton(key)
    local b = CreateFrame("Button", Utility.PREFIX .. key, bars[1].frame, "SecureActionButtonTemplate")
    b:SetSize(Utility.SIZE, Utility.SIZE)
    -- Both edges: the client acts on the one ActionButtonUseKeyDown picks,
    -- once (Apotheca, measured for clicks and CLICK bindings).
    b:RegisterForClicks("AnyUp", "AnyDown")
    local r = addRegions(b, true)
    b:SetScript("OnEnter", tooltip)
    -- Feed Pet's PreClick / PostClick run inside the editing ones.
    if BY_KEY[key].feed then b:SetAttribute("useOnKeyDown", false) end   -- the release acts, for clicks and the binding
    addEditing(b, true)
    buttons[key], regions[b], state[b] = b, r, { key = key, bar = bars[1] }
end

-- The lock's button: insecure (no secure action), no cooldown.
local function makeLockButton(key)
    local b = CreateFrame("Button", Utility.PREFIX .. key, bars[1].frame)
    b:SetSize(Utility.SIZE, Utility.SIZE)
    b:RegisterForClicks("AnyUp")
    local r = addRegions(b, false)
    b:SetScript("OnClick", guarded(lockClick))
    b:SetScript("OnEnter", tooltip)
    addEditing(b, false)
    buttons[key], regions[b], state[b] = b, r, { key = key, insecure = true, bar = bars[1] }
end
for _, a in ipairs(Utility.ACTIONS) do
    if a.lock then makeLockButton(a.key) else makeButton(a.key) end
end
for _, a in ipairs(Utility.CAMPING) do makeButton(a.key) end

-- A provider's callback: errors go to the client's error handler and to
-- /gab failures, never into the bar (the Dock's shape). ok, then its result.
local function callProvider(def, name, ...)
    local fn = def[name]
    local args, n = { ... }, select("#", ...)
    local err
    local ok, v = xpcall(function() return fn(unpack(args, 1, n)) end, function(e)
        err = e
        geterrorhandler()(e)
    end)
    if not ok then API.Fail("utility:provider:" .. def.id, err) end
    return ok, v
end

-- Its IsEnabled(): none is enabled; false, or an error, refuses.
local function providerEnabled(def)
    if not def.IsEnabled then return true end
    local ok, v = callProvider(def, "IsEnabled")
    return ok and v ~= false
end

local function providerOf(b)
    local s = state[b]
    return s and s.kind == "provider" and GAB.ProvidedButton(s.value) or nil
end

local function providerClick(self, mouseButton)
    local def = providerOf(self)
    if def and providerEnabled(def) then callProvider(def, "OnClick", self, mouseButton) end
end

local function providerTooltip(self)
    local def = providerOf(self)
    if not (def and def.tooltip) then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    if type(def.tooltip) == "string" then
        GameTooltip:SetText(def.tooltip)
    else
        callProvider(def, "tooltip", GameTooltip)
    end
    GameTooltip:Show()
end

-- An insecure button for a provider's key, made the first time it shows
-- (Reconcile: out of combat), skinned at once when the bar's own are.
local skinned = false
local function makeProviderButton(key)
    local b = CreateFrame("Button", Utility.PROVIDER_PREFIX .. Utility.ProviderId(key), bars[1].frame)
    b:SetSize(Utility.SIZE, Utility.SIZE)
    b:RegisterForClicks("AnyUp")
    local r = addRegions(b, false)
    b:SetScript("OnClick", guarded(providerClick))
    b:SetScript("OnEnter", providerTooltip)
    addEditing(b, false)
    buttons[key], regions[b], state[b] = b, r, { key = key, provider = true, bar = bars[1] }
    if skinned then API.Try("utility:skin", GAB.Buttons.Build, b, r, { maskIcon = true }) end
    return b
end

-- A dropped spell's secure button, made the first time it shows (Reconcile:
-- out of combat), like the built-ins'. No ':' in its name: a CLICK binding
-- splits on it.
local function makeSpellButton(key)
    local b = CreateFrame("Button", Utility.SPELL_PREFIX .. Utility.SpellId(key), bars[1].frame, "SecureActionButtonTemplate")
    b:SetSize(Utility.SIZE, Utility.SIZE)
    b:RegisterForClicks("AnyUp", "AnyDown")
    local r = addRegions(b, true)
    b:SetScript("OnEnter", tooltip)
    addEditing(b, true)
    buttons[key], regions[b], state[b] = b, r, { key = key, bar = bars[1] }
    if skinned then API.Try("utility:skin", GAB.Buttons.Build, b, r, { maskIcon = true }) end
    return b
end

-- An enabled bar with nothing to show keeps one empty slot (#86), a place to
-- drop a spell on or drag a button to: insecure, no action, never a gesture.
-- Not in `buttons`: it stands for no key. Skinned, it is the glass's empty
-- slot; unskinned, Blizzard's empty slot art.
local EMPTY_SLOT = "Interface\\Buttons\\UI-EmptySlot-Disabled"
local function makePlaceholder(bar)
    local b = CreateFrame("Button", "GlassActionBarsUtilDrop" .. bar.index, bar.frame)
    b:SetSize(Utility.SIZE, Utility.SIZE)
    b:RegisterForClicks("AnyUp")
    local r = addRegions(b, false)
    r.icon:SetTexture(EMPTY_SLOT)
    b:SetScript("OnReceiveDrag", function(self) Utility.DropOn(self) end)
    b:SetScript("OnClick", function(self) if cursorHolds() then Utility.DropOn(self) end end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(bar.index == 1 and "Utility bar" or "Utility bar " .. bar.index)
        GameTooltip:AddLine("Drop a spell from your spellbook here, or hold Shift and drag a button here.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    regions[b], state[b] = r, { placeholder = true, bar = bar }
    bar.placeholder = b
end
for _, bar in ipairs(bars) do makePlaceholder(bar) end

-- The placeholder's glass: the empty slot's, its art faded under it.
local function skinPlaceholder(bar)
    local b = bar.placeholder
    API.Try("utility:skin", GAB.Buttons.Build, b, regions[b], { maskIcon = true })
    GAB.Buttons.SetOccupied(b, false)
    regions[b].icon:SetAlpha(0)
end

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
    if s.kind == "spell" or s.kind == "feed" then return spellCooldown(cd, s.value) end
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
        if s.kind == "lock" then
            local r, locked = regions[b], Utility.BarsLocked()
            r.icon:SetTexture(GAB.MEDIA .. (locked == false and "LockOpen" or "LockClosed"))
            local fight = InCombatLockdown()
            r.icon:SetDesaturated(fight)
            r.icon:SetAlpha(fight and Utility.DIM or 1)
            r.count:SetText("")
            r.hotkey:SetText(Utility.ShortKey(GetBindingKey(Utility.BindingAction(s.key))))
        elseif s.kind == "provider" then
            local def, r = GAB.ProvidedButton(s.value), regions[b]
            if def then
                r.hotkey:SetText(def.binding and Utility.ShortKey(GetBindingKey(def.binding)) or "")
                local on = providerEnabled(def)
                r.icon:SetDesaturated(not on)
                r.icon:SetAlpha(on and 1 or Utility.DIM)
            end
        elseif s.kind then
            API.Try("utility:cooldown", Utility.ApplyCooldown, b)
            local r = regions[b]
            r.hotkey:SetText(isBound[s.key] and Utility.ShortKey(GetBindingKey(Utility.BindingAction(s.key))) or "")
            local camping = BY_KEY[s.key] and BY_KEY[s.key].item and s.key ~= "hearthstone"
            if s.kind == "feed" then
                r.count:SetText(s.food and tostring(s.food.count) or "")   -- the food's, as of the last rebuild
            else
                r.count:SetText(camping and tostring(API.ItemCount(s.value)) or "")
            end
        end
    end
end

-- ------------------------------------------------------------------
-- Layout (the dock's callbacks) and the rebuild
-- ------------------------------------------------------------------

local function arrange(bar)
    local g, n, f = bar.geom, bar.index, bar.frame
    -- Each part the bar's when the dock gives it (the player matches it), else our own.
    local size = g and g.size or Utility.LayoutSetting("iconSize", n)
    local pad = g and g.padding or Utility.LayoutSetting("iconPadding", n)
    local rows = math.max(1, g and g.rows or Utility.LayoutSetting("rows", n))
    local vertical
    if g and g.orientation then vertical = g.orientation == 1 else vertical = Utility.LayoutSetting("orientation", n) == "VERTICAL" end
    local list = bar.shown
    local count = #list
    if count == 0 then f:SetSize(size, size) return end
    local cols
    if vertical then
        cols = math.min(rows, count)
        rows = math.ceil(count / cols)
    else
        cols = math.ceil(count / rows)
        rows = math.min(rows, count)
    end
    bar.cols = cols   -- the bar's flow, for a drop's side
    f:SetSize(cols * size + (cols - 1) * pad, rows * size + (rows - 1) * pad)
    for i, b in ipairs(list) do
        local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
        b:SetSize(size, size)
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", f, "TOPLEFT", col * (size + pad), -row * (size + pad))
    end
end

-- ------------------------------------------------------------------
-- Drops and the reorder drag (#86)
-- ------------------------------------------------------------------

-- The order key a shown button stands for: a camping item's is the group's.
local function orderKey(key) return key:match("^camp_") and "camping" or key end
Utility.OrderKeyOf = orderKey

local function plainNumbers(...)
    for i = 1, select("#", ...) do
        local v = select(i, ...)
        if API.IsSecret(v) or type(v) ~= "number" then return false end
    end
    return true
end

-- The pointer in screen pixels, else nil.
local function pointer()
    local ok, x, y = pcall(GetCursorPosition)
    if ok and plainNumbers(x, y) then return x, y end
end

-- A frame's centre and half sizes in screen pixels, else nil.
local function screenRect(f)
    local x, y = f:GetCenter()
    local w, h, s = f:GetWidth(), f:GetHeight(), f:GetEffectiveScale()
    if not plainNumbers(x, y, w, h, s) then return nil end
    return x * s, y * s, w * s / 2, h * s / 2
end

-- Whether the pointer is on b's trailing half along its bar's flow (left to
-- right in a row, downwards in a single column).
local function trailing(b)
    local px, py = pointer()
    local cx, cy = screenRect(b)
    if not (px and cx) then return false end
    if state[b].bar.cols > 1 then return px > cx end
    return py < cy
end

local function shownIndex(b)
    for n, x in ipairs(state[b].bar.shown) do if x == b then return n end end
end

-- The key a drop on b (its leading or trailing half) goes before; nil: last
-- (an empty bar's placeholder too).
local function beforeKey(b, after)
    if state[b].placeholder then return nil end
    local mine = orderKey(state[b].key)
    if not after then return mine end
    local list = state[b].bar.shown
    for j = (shownIndex(b) or #list) + 1, #list do
        local k = orderKey(state[list[j]].key)
        if k ~= mine then return k end
    end
    return nil
end

-- Refusals as Blizzard's own (the red text at the top), when it's there.
function Utility.Refuse(why)
    local f = rawget(_G, "UIErrorsFrame")
    if f and f.AddMessage then pcall(f.AddMessage, f, "Utility bar: " .. why, 1, 0.1, 0.1) end
end

-- The spell on the cursor: its ID when the cursor plainly holds a spell
-- ("spell", book slot, bank, ID: measured on 70938), else nil.
function Utility.CursorSpell()
    local ok, kind, _, _, id = pcall(GetCursorInfo)
    if not ok or API.IsSecret(kind) or kind ~= "spell" then return nil end
    if API.IsSecret(id) or type(id) ~= "number" then return nil end
    return id
end

-- The key a dropped spell becomes: a built-in entry's (any of its ranks), or
-- its own spell:<id>. Else nil and why.
function Utility.DropKey(id)
    if API.SpellKnown(id) ~= true then return nil, "not a spell this character knows" end
    if flag(C_Spell.IsSpellPassive, id) ~= false then return nil, "a passive spell can't go on the bar" end
    return BUILTIN_SPELL[id] or ("spell:" .. id)
end

-- The cursor's contents dropped on b: a spell joins the bar there and the
-- cursor is cleared; anything else stays on the cursor. Out of combat only.
function Utility.DropOn(b)
    if InCombatLockdown() or not cursorHolds() then return false end
    local id = Utility.CursorSpell()
    if not id then
        Utility.Refuse("only spells can be added")
        return false
    end
    local ok, why = GAB.Settings.AddUtilitySpell(id, beforeKey(b, trailing(b)), state[b].bar.index)
    if ok then ClearCursor() else Utility.Refuse(why) end
    return ok
end

-- The reorder drag: our own ghost of the icon and a marker between the
-- buttons; nothing on the real cursor (the Hearthstone, the camping group, a
-- provider's button and the lock have no cursor form).
local reorder = nil   -- { button, key }
local ghost = CreateFrame("Frame", nil, UIParent)
ghost:SetFrameStrata("TOOLTIP")
ghost:SetAlpha(0.75)
ghost:Hide()
local ghostIcon = ghost:CreateTexture(nil, "ARTWORK")
ghostIcon:SetAllPoints()
ghostIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
local marker = CreateFrame("Frame", nil, UIParent)
marker:SetFrameStrata("TOOLTIP")
marker:Hide()
local markerLine = marker:CreateTexture(nil, "OVERLAY")
markerLine:SetAllPoints()
markerLine:SetColorTexture(0.5, 0.83, 1, 0.9)

-- Where a drop would land: the shown button nearest the pointer and whether
-- after it; nil when the pointer is off every bar (a bar's rect plus half a
-- button). A moved button takes the target's slot (#88): after it when moving
-- forward, before it when moving back, whichever half (in a grid, "after the
-- row's last button" is the next row's first slot, where it came from). A
-- spell from the spellbook has no slot: after on the target's trailing half.
local function dropTarget()
    local px, py = pointer()
    if not px then return nil end
    local best, bestD
    for _, bar in ipairs(bars) do
        local list = bar.shown
        local fx, fy, fw, fh = screenRect(bar.frame)
        if fx and #list > 0 then
            local _, _, bw, bh = screenRect(list[1])
            bw, bh = bw or 0, bh or 0
            if math.abs(px - fx) <= fw + bw and math.abs(py - fy) <= fh + bh then
                for _, b in ipairs(list) do
                    local cx, cy = screenRect(b)
                    if cx then
                        local d = (px - cx) ^ 2 + (py - cy) ^ 2
                        if not bestD or d < bestD then best, bestD = b, d end
                    end
                end
            end
        end
    end
    if not best then return nil end
    if reorder and state[reorder.button].bar == state[best].bar then
        local from, to = shownIndex(reorder.button), shownIndex(best)
        return best, from ~= nil and to > from
    end
    return best, trailing(best)
end

local function placeMarker()
    local b, after = dropTarget()
    if not b then marker:Hide() return end
    local cx, cy, hw, hh = screenRect(b)
    local s = API.Plain(UIParent:GetEffectiveScale())
    if not (cx and plainNumbers(s)) then marker:Hide() return end
    marker:ClearAllPoints()
    if state[b].bar.cols > 1 then
        marker:SetSize(3, hh * 2 / s)
        marker:SetPoint("CENTER", UIParent, "BOTTOMLEFT", (cx + (after and hw or -hw)) / s, cy / s)
    else
        marker:SetSize(hw * 2 / s, 3)
        marker:SetPoint("CENTER", UIParent, "BOTTOMLEFT", cx / s, (cy + (after and -hh or hh)) / s)
    end
    marker:Show()
end

local function followPointer()
    local px, py = pointer()
    local s = API.Plain(UIParent:GetEffectiveScale())
    if px and plainNumbers(s) then
        ghost:ClearAllPoints()
        ghost:SetPoint("CENTER", UIParent, "BOTTOMLEFT", px / s, py / s)
    end
    placeMarker()
end

function Utility.StartReorder(b)
    if InCombatLockdown() or not state[b].kind then return end
    reorder = { button = b, key = orderKey(state[b].key) }
    ghostIcon:SetTexture(regions[b].icon:GetTexture())
    local _, _, hw, hh = screenRect(b)
    local s = API.Plain(UIParent:GetEffectiveScale())
    if hw and plainNumbers(s) then ghost:SetSize(hw * 2 / s, hh * 2 / s) else ghost:SetSize(Utility.SIZE, Utility.SIZE) end
    followPointer()
    ghost:Show()
    ghost:SetScript("OnUpdate", followPointer)
end

-- The drag drops nothing (a fight began, a bar hid).
function Utility.CancelReorder()
    reorder = nil
    ghost:SetScript("OnUpdate", nil)
    ghost:Hide()
    marker:Hide()
end

-- The release: over a bar, the entry goes there (the other bar's included);
-- off the bars, it comes off (a dropped spell leaves the order, anything else
-- is unticked, back from Options).
function Utility.FinishReorder(b)
    local r = reorder
    if not r or r.button ~= b then return end
    local target, after = dropTarget()
    Utility.CancelReorder()
    if InCombatLockdown() then return end
    if target then
        local before = beforeKey(target, after)
        local to = state[target].bar
        if to ~= state[b].bar or before ~= r.key then GAB.Settings.PlaceUtility(r.key, before, to.index) end
    else
        GAB.Settings.RemoveUtility(r.key)
    end
end

-- The undocked spot: the saved one, else the bar's default point.
local function savedPos(bar)
    local s = barSettings(bar.index)
    return s and Utility.ValidPos(s.pos) and s.pos or nil
end
local function placeAt(bar, x, y)
    bar.frame:ClearAllPoints()
    bar.frame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", x, y)
    GAB.Edges.Request()   -- placed by hand: the screen edges may have moved
end
local function restorePos(bar)
    local p = savedPos(bar)
    if p then placeAt(bar, p.x, p.y) else
        local d = DEFAULT_POINT[bar.index]
        bar.frame:ClearAllPoints()
        bar.frame:SetPoint(d[1], UIParent, d[2], d[3], d[4])
    end
end

-- The frame's bottom-left corner, saved and anchored there; false when
-- unreadable (the frame stays as it is).
local function saveHere(bar)
    local x, y = API.Plain(bar.frame:GetLeft()), API.Plain(bar.frame:GetBottom())
    if not GAB.Settings.SetUtilityPosition(x, y, bar.index) then return false end
    placeAt(bar, x, y)
    return true
end

-- The dock's Layout(geom) for bar n (default 1): the bar's geometry, or nil for our own.
function Utility.Layout(geom, n)
    local bar = bars[n or 1]
    bar.geom = geom
    arrange(bar)
end

-- Undocked by the player (or a first placement failed): our own geometry, at
-- the saved spot; undocking with none saves where the dock had it. Never
-- during a drag: the drop places it.
function Utility.OnHosted(isHosted, n)
    local bar = bars[n or 1]
    if isHosted then bar.hosted = true return end
    local was = bar.hosted
    bar.hosted, bar.geom = false, nil
    if InCombatLockdown() then return end
    arrange(bar)
    if bar.dragging then return end
    if savedPos(bar) then restorePos(bar)
    elseif was and GAB.Dock.Setting(bar.dockId, "bar") == false then saveHere(bar) end
end

-- Dragging (Apotheca's, measured there): no StartMoving or
-- StopMovingOrSizing in combat on a frame that parents secure buttons.
-- PLAYER_REGEN_DISABLED stops a drag before lockdown; if lockdown is already
-- on, the stop waits for the fight's end, the overlay staying up to keep
-- clicks off the buttons, and the bar goes where combat caught it.
local function stopDrag(bar)
    if not bar.dragging then return end
    local f = bar.frame
    if InCombatLockdown() then
        if not bar.stopPending then
            bar.dropPos = { x = API.Plain(f:GetLeft()), y = API.Plain(f:GetBottom()) }
        end
        bar.stopPending = true
        return
    end
    f:StopMovingOrSizing()
    local p = bar.dropPos
    bar.dragging, bar.stopPending, bar.dropPos = false, false, nil
    if p then
        if GAB.Settings.SetUtilityPosition(p.x, p.y, bar.index) then placeAt(bar, p.x, p.y) else restorePos(bar) end
    elseif not saveHere(bar) then
        restorePos(bar)
    end
end

-- The overlay: shown while Alt is held over a bar out of combat; it takes
-- the drag and keeps clicks off the secure buttons under it. Polled while
-- Alt is down (no event says the pointer reached the bar), up or dragging.
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

-- One bar's overlay; true while it still needs the poll.
local function updateBarMover(bar)
    local mover, f = bar.mover, bar.frame
    if bar.dragging then
        if bar.stopPending then
            if not InCombatLockdown() then stopDrag(bar); mover:Hide() end
        elseif not IsAltKeyDown() or InCombatLockdown() then
            stopDrag(bar)
            if not bar.stopPending then mover:Hide() end
        end
    elseif IsAltKeyDown() and not InCombatLockdown() and API.Plain(f:IsVisible()) == true
            and API.Plain(f:IsMouseOver()) == true then
        mover:Show()
    else
        mover:Hide()
    end
    return bar.dragging or mover:IsShown()
end

function updateMover()
    local busy = IsAltKeyDown()
    for _, bar in ipairs(bars) do
        if updateBarMover(bar) then busy = true end
    end
    poller:SetScript("OnUpdate", busy and poll or nil)
end
Utility.UpdateMover = updateMover

local function makeMover(bar)
    local f = bar.frame
    local mover = CreateFrame("Frame", nil, f)
    mover:SetAllPoints(f)
    mover:SetFrameStrata("DIALOG")
    mover:EnableMouse(true)
    mover:RegisterForDrag("LeftButton")
    mover:Hide()
    local bg = mover:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.5, 0.83, 1, 0.35)
    local text = mover:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    text:SetPoint("CENTER")
    text:SetText("Drag")
    mover:SetScript("OnDragStart", function()
        if InCombatLockdown() or not IsAltKeyDown() then return end
        -- Undock first: a dock pass never moves the bar under the pointer.
        if GAB.Dock.Setting(bar.dockId, "bar") ~= false then GAB.Settings.SetDock(bar.dockId, "bar", false) end
        bar.dragging = true
        f:StartMoving()
    end)
    mover:SetScript("OnDragStop", function()
        stopDrag(bar)
        updateMover()
    end)
    -- Never leave the frame on the pointer (in combat this only marks the stop).
    f:SetScript("OnHide", function()
        stopDrag(bar)
        updateMover()
        Utility.CancelReorder()
    end)
    bar.mover = mover
end
for _, bar in ipairs(bars) do makeMover(bar) end

-- A shown button's action from its state (items and spells; Feed Pet stays
-- disarmed at rest, the lock and providers have none). Out of combat.
function Utility.Arm(b)
    local s = state[b]
    if s.provider or s.insecure or InCombatLockdown() then return end
    if s.kind == "item" then
        b:SetAttribute("type", "item")
        b:SetAttribute("spell", nil)
        b:SetAttribute("item", "item:" .. s.value)
    elseif s.kind == "spell" then
        b:SetAttribute("type", "spell")
        b:SetAttribute("item", nil)
        -- A dropped spell by its plain name (#133); the ID when it has none.
        b:SetAttribute("spell", s.byName and Utility.SpellName(s.value) or s.value)
    end
end

local function clear(b)
    if not (state[b].provider or state[b].insecure) then
        b:SetAttribute("type", nil)
        b:SetAttribute("spell", nil)
        b:SetAttribute("item", nil)
        b:SetAttribute("target-bag", nil)
        b:SetAttribute("target-slot", nil)
    end
    state[b].kind, state[b].value, state[b].food, state[b].byName = nil, nil, nil, nil
    b:Hide()
end

-- Each registered provider told whether its button is on the enabled bar:
-- the first time, and on each change (`on`: the ids shown now).
local hostedSent = {}
local function notifyHosted(on)
    for _, copy in ipairs(GAB.ProvidedButtons()) do
        local now = on[copy.id] == true
        if hostedSent[copy.id] ~= now then
            hostedSent[copy.id] = now
            local def = GAB.ProvidedButton(copy.id)
            if def.OnHosted then callProvider(def, "OnHosted", now) end
        end
    end
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
    for _, bar in ipairs(bars) do
        if API.Plain(bar.frame:GetFrameLevel()) ~= want then
            bar.frame:SetFrameLevel(want)
            for _, b in pairs(buttons) do   -- the glass follows the new level
                if state[b].bar == bar then GAB.Buttons.Restyle(b) end
            end
            GAB.Buttons.Restyle(bar.placeholder)
        end
    end
end
Utility.Raise = raise

local pending = false
local started = false

-- One entry's button, ready on `bar`: made the first time (a dropped spell's,
-- a provider's), moved to this bar's frame when it was on the other one.
local function buttonFor(e, bar)
    local b = buttons[e.key] or (Utility.SpellId(e.key) and makeSpellButton(e.key)) or makeProviderButton(e.key)
    if state[b].bar ~= bar then
        b:SetParent(bar.frame)
        state[b].bar = bar
        GAB.Buttons.Restyle(b)   -- the glass follows the new parent's level
    end
    if e.kind == "provider" then
        regions[b].icon:SetTexture(GAB.ProvidedButton(e.value).icon)
    elseif e.kind == "lock" then
        -- No attributes: an insecure button. Its padlock: RefreshVisuals.
    elseif e.kind == "item" then
        local ok, icon = pcall(C_Item.GetItemIconByID, e.value)
        regions[b].icon:SetTexture(ok and API.Plain(icon) or "Interface\\Icons\\INV_Misc_QuestionMark")
    else
        -- A spell, or Feed Pet (disarmed above: only its click arms it).
        local ok, icon = pcall(C_Spell.GetSpellTexture, e.value)
        regions[b].icon:SetTexture(ok and API.Plain(icon) or "Interface\\Icons\\INV_Misc_QuestionMark")
    end
    state[b].kind, state[b].value, state[b].food, state[b].byName = e.kind, e.value, e.food, e.byName
    Utility.Arm(b)
    b:Show()
    return b
end

function Utility.Reconcile()
    if InCombatLockdown() then
        pending = true
        return
    end
    pending = false
    Utility.DisarmFeed()   -- never left armed by a click that didn't finish
    API.Try("utility:raise", raise)
    local active, on = {}, {}
    for _, bar in ipairs(bars) do
        local list = {}
        if Utility.Enabled(bar.index) then
            for _, e in ipairs(Utility.Collect(bar.index)) do
                local b = buttonFor(e, bar)
                if e.kind == "provider" then on[e.value] = true end
                active[b] = true
                list[#list + 1] = b
            end
        end
        -- An enabled bar with nothing on it: its empty slot, a place to drop on.
        local empty = #list == 0 and Utility.Enabled(bar.index)
        if empty then list[1] = bar.placeholder end
        bar.placeholder:SetShown(empty)
        bar.shown = list
        arrange(bar)
        bar.frame:SetShown(#list > 0)
        GAB.Dock.RequestLayout(bar.dockId)
    end
    for _, b in pairs(buttons) do
        if not active[b] then clear(b) end
    end
    Utility.RefreshVisuals()
    notifyHosted(on)
end

function Utility.IsPending() return pending end

-- A provider registered (API.lua): its button and OnHosted come with the next
-- rebuild once the bar has started (Start's own rebuild covers the rest); its
-- row on the options page at once, even with the page open (a page not built
-- yet has nothing to refresh).
function Utility.ProviderRegistered()
    if started then Utility.Refresh() end
    if GAB.Options then GAB.Options.RefreshPage(GAB.Options.utilityPage) end
end

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
        if a.lock then
            name = Utility.LockLabel()
        elseif a.item then
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

local function skin()
    if skinned or GAB.db.skin == false then return end
    skinned = true
    for _, b in pairs(buttons) do
        API.Try("utility:skin", GAB.Buttons.Build, b, regions[b], { maskIcon = true })
    end
    for _, bar in ipairs(bars) do skinPlaceholder(bar) end
end

local BAR_LABELS, BAR_DOCKS = { "Utility bar", "Utility bar 2" }, { Utility.DOCK, Utility.DOCK2 }

function Utility.Start()
    if started then return end
    started = true
    if not InCombatLockdown() then skin() end
    for _, bar in ipairs(bars) do
        local n = bar.index
        GAB.Dock.Register({ id = bar.dockId, label = BAR_LABELS[n], frame = bar.frame, default = BAR_DOCKS[n],
            Layout = function(geom) Utility.Layout(geom, n) end,
            OnHosted = function(isHosted) Utility.OnHosted(isHosted, n) end })
    end
    Utility.LocalizeBindingNames()
    Utility.ReadCampfire()
    -- The saved spot until a dock pass places the bar (its target may be
    -- unavailable on this character); a /reload in combat waits for the fight.
    for _, bar in ipairs(bars) do
        if savedPos(bar) then
            if InCombatLockdown() then bar.posPending = true else restorePos(bar) end
        end
    end
    local petDead = flag(UnitIsDead, "pet")
    driver:SetScript("OnEvent", function(_, event, arg1)
        if event == "PLAYER_REGEN_ENABLED" or event == "PLAYER_REGEN_DISABLED" then
            -- A provider's IsEnabled may follow combat: asked again a frame
            -- later (InCombatLockdown is still false inside REGEN_DISABLED).
            C_Timer.After(0, function() API.Try("utility:visuals", Utility.RefreshVisuals) end)
        end
        if event == "PLAYER_REGEN_ENABLED" then
            -- An interrupted drag ends first (updateMover), before a rebuild can resize or hide the frame.
            updateMover()
            for _, bar in ipairs(bars) do
                if bar.posPending then
                    bar.posPending = false
                    if not bar.hosted then restorePos(bar) end
                end
            end
            skin()
            Utility.DisarmFeed()   -- whatever a fight interrupted
            -- A combat read may have been unknown: a change found now rebuilds too.
            if Utility.ReadCampfire() or pending then Utility.Reconcile() end
        elseif event == "PLAYER_REGEN_DISABLED" then
            -- The last moment before lockdown: a drag stops cleanly, where it is.
            for _, bar in ipairs(bars) do
                if bar.dragging and not InCombatLockdown() then stopDrag(bar) end
            end
            Utility.CancelReorder()
            Utility.DisarmFeed()
            updateMover()
        elseif event == "MODIFIER_STATE_CHANGED" then
            updateMover()
        elseif event == "UNIT_AURA" then
            if arg1 == "player" and Utility.ReadCampfire() then Utility.Refresh() end
        elseif event == "UNIT_PET" then
            if arg1 == "player" then Utility.Refresh() end
        elseif event == "UNIT_LEVEL" then
            if arg1 == "pet" then Utility.Refresh() end   -- the food band
        elseif event == "UNIT_HEALTH" then
            -- The pet died or came back: no rebuild (a bag scan) on every health tick.
            if arg1 == "pet" then
                local d = flag(UnitIsDead, "pet")
                if d ~= nil and d ~= petDead then petDead = d; Utility.Refresh() end
            end
        elseif event == "BAG_UPDATE_COOLDOWN" or event == "SPELL_UPDATE_COOLDOWN" or event == "UPDATE_BINDINGS" then
            Utility.RefreshVisuals()
        elseif event == "CVAR_UPDATE" then
            if not API.IsSecret(arg1) and arg1 == Utility.LOCK_CVAR then Utility.RefreshVisuals() end
        elseif event == "GET_ITEM_INFO_RECEIVED" then
            if namesPending then Utility.LocalizeBindingNames() end
            if Utility.FoodArrived(arg1) then Utility.Refresh() end
        else
            if event == "SPELLS_CHANGED" and namesPending then Utility.LocalizeBindingNames() end
            Utility.Refresh()
        end
    end)
    API.RegisterEvents(driver, { "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED",
        "MODIFIER_STATE_CHANGED", "SPELLS_CHANGED",
        "SKILL_LINES_CHANGED", "LEARNED_SPELL_IN_SKILL_LINE", "BAG_UPDATE_DELAYED", "UNIT_AURA",
        "BAG_UPDATE_COOLDOWN", "SPELL_UPDATE_COOLDOWN", "UPDATE_BINDINGS", "GET_ITEM_INFO_RECEIVED",
        "UNIT_PET", "UNIT_LEVEL", "UNIT_HEALTH", "CVAR_UPDATE" }, "utility")
    Utility.Refresh()
end

local bar1 = bars[1]
Utility._test = { regions = regions, state = state, frame = bar1.frame,
    shown = function() return bar1.shown end, geom = function() return bar1.geom end,
    setCampfire = function(v) campfire = v end, mover = bar1.mover, poller = poller,
    dragging = function() return bar1.dragging, bar1.stopPending end,
    gesture = gesture, ghost = ghost, marker = marker, reorder = function() return reorder end,
    lastCols = function() return bar1.cols end, bars = bars }
