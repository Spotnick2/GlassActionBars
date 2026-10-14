-- Options.lua: the page in Esc > Options > AddOns, built with the porting
-- guide's measured recipe ("An Options page with sub-pages and an About page"):
-- a plain Frame with .name, hidden at creation (or the first visit is blank),
-- controls built on the first OnShow, every value re-read on every OnShow,
-- registered once at PLAYER_LOGIN from GlassActionBars.lua.
--
-- Each feature adds its own controls here as it lands. Choices are radio
-- groups, not dropdowns (the porting guide's measured recipe). GlassMail's
-- Options.lua, the same helpers.

GlassActionBars = GlassActionBars or {}
local GAB = GlassActionBars
local API = GAB.API
local Options = {}
GAB.Options = Options

local RADIO_ART = "Interface\\Buttons\\UI-RadioButton"   -- 4 cells: normal, checked, highlight, pushed

local panel = CreateFrame("Frame")
panel.name = "Glass Action Bars"
panel:Hide()

local category
local refreshers = {}

local function label(parent, text, font)
    local fs = parent:CreateFontString(nil, "ARTWORK", font or "GameFontHighlight")
    fs:SetText(text)
    return fs
end
Options.label = label

-- A labelled radio button: UIRadioButtonTemplate when the client has it (its
-- own label, rb.text, takes the text), else the client's own radio art and a
-- label of ours.
local function radioButton(parent, text)
    local rb, templated = API.SafeFrame("CheckButton", parent, "UIRadioButtonTemplate", "text")
    if templated then
        rb.text:SetFontObject("GameFontHighlight")
        rb.text:SetText(text)
        return rb
    end
    rb:SetSize(16, 16)
    rb:SetNormalTexture(RADIO_ART)
    rb:GetNormalTexture():SetTexCoord(0, 0.25, 0, 1)
    rb:SetCheckedTexture(RADIO_ART)
    rb:GetCheckedTexture():SetTexCoord(0.25, 0.5, 0, 1)
    rb:SetHighlightTexture(RADIO_ART)
    rb:GetHighlightTexture():SetTexCoord(0.5, 0.75, 0, 1)
    rb:GetHighlightTexture():SetBlendMode("ADD")   -- as the template's (CheckButtonTemplates.xml:18)
    local fs = label(parent, text)
    fs:SetPoint("LEFT", rb, "RIGHT", 4, 0)
    return rb
end

-- An on/off setting under `anchor`: our own label beside the template's box.
function Options.checkbox(parent, anchor, text, get, set)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetSize(24, 24)
    cb:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -4)
    local fs = label(parent, text)
    fs:SetPoint("LEFT", cb, "RIGHT", 4, 0)
    local function sync() cb:SetChecked(get() == true) end
    cb:SetScript("OnClick", function() set(cb:GetChecked() == true); sync() end)
    refreshers[#refreshers + 1] = sync
    return cb
end

-- Mutually exclusive choices, stacked under `anchor`: { {value, text}, ... }.
-- Returns the last button, to anchor what follows. The whole group re-syncs
-- after a click, so a refused choice snaps back. The value lives in our own
-- table, never on the button.
function Options.radios(parent, anchor, options, get, set)
    local group, values = {}, {}
    local function sync()
        local current = get()
        for i, rb in ipairs(group) do rb:SetChecked(values[i] == current) end
    end
    local prev = anchor
    for i, o in ipairs(options) do
        local rb = radioButton(parent, o[2])
        values[i] = o[1]
        rb:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, prev == anchor and -8 or -4)
        rb:SetScript("OnClick", function() set(o[1]); sync() end)
        group[#group + 1] = rb
        prev = rb
    end
    refreshers[#refreshers + 1] = sync
    return prev, group
end

-- Feature sections, in the order they were added: each is a function(panel,
-- anchor) that builds its controls under `anchor` and returns its last one.
local sections = {}
function Options.AddSection(build) sections[#sections + 1] = build end

local function build()
    local title = label(panel, "Glass Action Bars", "GameFontNormalHuge")
    title:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -16)
    local version = label(panel, "", "GameFontDisableSmall")
    version:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
    refreshers[#refreshers + 1] = function()
        version:SetText("Version " .. GAB.VersionText() .. " for World of Warcraft: Forever, by Spotnick")
    end
    local last = version
    for _, section in ipairs(sections) do
        last = API.Try("options:section", section, panel, last) or last
    end
    local hint = label(panel, "Type /gab help for every command.", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", last, "BOTTOMLEFT", 0, -16)
end

panel:SetScript("OnShow", function()
    if not Options.built then
        Options.built = true
        build()
    end
    for _, refresh in ipairs(refreshers) do refresh() end
end)

-- The look: the glass, the text on the buttons, the gryphons, and glass or
-- Blizzard's own art.
Options.AddSection(function(parent, anchor)
    local look = label(parent, "The glass", "GameFontNormal")
    look:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -16)
    local choices = {}
    for _, name in ipairs(GAB.Theme.NAMES) do choices[#choices + 1] = { name, GAB.Theme.LABELS[name] } end
    local last, group = Options.radios(parent, look, choices, function() return GAB.db.theme end,
        GAB.Settings.SetTheme)
    Options._test.themeRadios = group
    local buttons = label(parent, "On the buttons", "GameFontNormal")
    buttons:SetPoint("TOPLEFT", last, "BOTTOMLEFT", 0, -16)
    local hotkeys = Options.checkbox(parent, buttons, "Key bindings",
        function() return GAB.db.showHotkeys end, GAB.Settings.SetShowHotkeys)
    local macros = Options.checkbox(parent, hotkeys, "Macro names",
        function() return GAB.db.showMacroNames end, GAB.Settings.SetShowMacroNames)
    local gryphons = Options.checkbox(parent, macros, "The main bar's gryphons",
        function() return GAB.db.endCaps end, GAB.Settings.SetEndCaps)
    local skin = Options.checkbox(parent, gryphons, "Glass on the action bars (Blizzard's own art when off, after a /reload)",
        function() return GAB.db.skin end, GAB.Settings.SetSkin)
    Options._test.hotkeys, Options._test.macros, Options._test.gryphons, Options._test.skin = hotkeys, macros, gryphons, skin
    return skin
end)

-- Called once at PLAYER_LOGIN by GlassActionBars.lua.
function Options.Register()
    if category or not (Settings and Settings.RegisterCanvasLayoutCategory) then return end
    category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
    Settings.RegisterAddOnCategory(category)
end

-- Open the page; false when the Settings framework can't.
function Options.Open()
    if not (category and Settings and Settings.OpenToCategory) then return false end
    return pcall(Settings.OpenToCategory, category:GetID()) and true or false
end

Options._test = { panel = panel, refreshers = refreshers }
