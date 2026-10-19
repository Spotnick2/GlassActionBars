-- Bags.lua: the glass on the bag bar (#14): the backpack, the four bag slots,
-- the reagent bag and the key ring, with the same body and rim as the action
-- buttons (Buttons.Build); the bar's own frame art and dividers faded.
--
-- Forever's bag bar is Camelot's (Blizzard_MainMenuBarBagButtons: the Shared
-- and Camelot files; the Mainline ones are excluded). Facts it rests on:
-- - Each slot's frame is its NormalTexture (atlas "ui-hud-actionbar-iconframe-
--   bags"; the reagent bag "UI-HUD-ActionBar-IconFrame"), set again, with the
--   pushed and highlight atlases, by the button's own UpdateTextures
--   (Camelot\MainMenuBarBagButtons.lua:9-41), which runs on every slot update.
--   That is the hook.
-- - The empty slot's silhouette is the slot's icon, not its frame: it stays,
--   even when the empty-slots look hides the slot's glass.
-- - ItemButtonMixin replaces the button's own SetAlpha (it fades the icon and
--   count only), so nothing here calls SetAlpha on a bag button: only on its
--   regions.
-- - BagsBar.BorderArt (atlas "UI-HUD-ActionBar-Frame") is never set again;
--   its dividers come from frame pools that BagsBar:UpdateDividers releases
--   and acquires on every Layout. BagsBar is an Edit Mode system: SetAlpha on
--   regions and pooled frames only, never Hide, never a reparent.

GlassActionBars = GlassActionBars or {}
local GAB = GlassActionBars
local API = GAB.API
local Bags = {}
GAB.Bags = Bags

Bags.BUTTONS = { "MainMenuBarBackpackButton", "CharacterBag0Slot", "CharacterBag1Slot", "CharacterBag2Slot",
    "CharacterBag3Slot", "CharacterReagentBag0Slot", "KeyRingButton" }

-- A bag slot holds a bag (Blizzard's own HasBagEquipped test); the backpack
-- and the key ring always hold theirs. Nil when unreadable: the rim stays.
local function occupied(b)
    if b == MainMenuBarBackpackButton or b == KeyRingButton then return true end
    local ok, tex = pcall(GetInventoryItemTexture, "player", b:GetID())
    if not ok or API.IsSecret(tex) then return nil end
    return tex ~= nil
end
Bags.occupied = occupied

local function regionsOf(b)
    return {
        icon = b.icon, count = b.Count,
        normal = b.NormalTexture or b:GetNormalTexture(), pushed = b.PushedTexture or b:GetPushedTexture(),
        highlight = b.HighlightTexture or b:GetHighlightTexture(),
    }
end

local function fadeDividers()
    for _, key in ipairs({ "HorizontalDividersPool", "VerticalDividersPool" }) do
        local pool = BagsBar[key]
        if pool and pool.EnumerateActive then
            for divider in pool:EnumerateActive() do divider:SetAlpha(0) end
        end
    end
end

function Bags.Refresh()
    if not BagsBar or GAB.db.skin == false then return end
    if BagsBar.BorderArt then BagsBar.BorderArt:SetAlpha(0) end
    API.Try("bags:dividers", fadeDividers)
end

local started = false
function Bags.Start()
    if started or GAB.db.skin == false or not BagsBar then return end
    started = true
    for _, name in ipairs(Bags.BUTTONS) do
        local b = _G[name]
        if b and not GAB.Buttons.IsSkinned(b) then
            API.Try("bags:" .. name, function()
                -- An empty bag slot takes the empty-slots look, like an empty action slot (#50).
                GAB.Buttons.Build(b, regionsOf(b))
                if type(b.UpdateTextures) == "function" then
                    hooksecurefunc(b, "UpdateTextures", function(self)
                        GAB.Buttons.Restyle(self)
                        GAB.Buttons.SetOccupied(self, occupied(self))
                    end)
                end
                GAB.Buttons.SetOccupied(b, occupied(b))
            end)
        end
    end
    for _, method in ipairs({ "Layout", "UpdateDividers" }) do
        if type(BagsBar[method]) == "function" then
            hooksecurefunc(BagsBar, method, function() API.Try("bags:dividers", fadeDividers) end)
        end
    end
    local f = CreateFrame("Frame")
    f:SetScript("OnEvent", function() Bags.Refresh() end)
    API.RegisterEvents(f, { "EDIT_MODE_LAYOUTS_UPDATED" }, "bags")
    Bags.Refresh()
end
