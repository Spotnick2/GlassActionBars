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
local building = refreshers   -- the refresh list of the page being built

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
    building[#building + 1] = sync
    return cb
end

-- Mutually exclusive choices, stacked under `anchor`: { {value, text}, ... }.
-- Returns the last button, to anchor what follows. The whole group re-syncs
-- after a click, so a refused choice snaps back. The value lives in our own
-- table, never on the button. `across` = { x, step }: in a row instead, the
-- first `x` px right of the anchor's left edge, then every `step` px.
function Options.radios(parent, anchor, options, get, set, across)
    local group, values = {}, {}
    local function sync()
        local current = get()
        for i, rb in ipairs(group) do rb:SetChecked(values[i] == current) end
    end
    local prev = anchor
    for i, o in ipairs(options) do
        local rb = radioButton(parent, o[2])
        values[i] = o[1]
        if across then
            rb:SetPoint("LEFT", anchor, "LEFT", across[1] + (i - 1) * across[2], 0)
        else
            rb:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, prev == anchor and -8 or -4)
        end
        rb:SetScript("OnClick", function() set(o[1]); sync() end)
        group[#group + 1] = rb
        prev = rb
    end
    building[#building + 1] = sync
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
        building = refreshers
        build()
    end
    for _, refresh in ipairs(refreshers) do refresh() end
end)

-- Sub-pages under ours in the AddOns list, each with its own build-once and
-- refresh-on-every-show (the porting guide's recipe: hidden at creation).
-- `build(page, title)` builds its controls under the page's title.
local pages = {}
function Options.AddPage(name, build)
    local page = { frame = CreateFrame("Frame"), refreshers = {} }
    page.frame.name = name
    page.frame:Hide()
    page.frame:SetScript("OnShow", function()
        building = page.refreshers   -- a refresher may build controls (the Dock page's new sections)
        if not page.built then
            page.built = true
            local title = label(page.frame, name, "GameFontNormalHuge")
            title:SetPoint("TOPLEFT", page.frame, "TOPLEFT", 16, -16)
            API.Try("options:page", build, page.frame, title)
        end
        for _, refresh in ipairs(page.refreshers) do refresh() end
    end)
    pages[#pages + 1] = page
    return page.frame
end

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

-- Bar fade (#10): a row per bar, then how faded a faded bar is.
Options.FADE_ALPHAS = { { 0, "Hidden" }, { 0.25, "Faint" }, { 0.5, "Half" } }
Options.fadePage = Options.AddPage("Bar fade", function(page, title)
    local note = label(page, "A faded bar comes back under the pointer, while you drag something to it, in Edit Mode, "
        .. "with the spellbook open, and (out-of-combat fade) in a fight. Blizzard's own bar visibility "
        .. "settings still apply.", "GameFontHighlightSmall")
    note:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    note:SetPoint("RIGHT", page, "RIGHT", -16, 0)
    note:SetJustifyH("LEFT")
    local choices = {}
    for _, m in ipairs(GAB.Fade.MODES) do choices[#choices + 1] = { m, GAB.Fade.LABELS[m] } end
    local last = note
    Options._test.fadeRows = {}
    for i, b in ipairs(GAB.Fade.BARS) do
        local name = label(page, b[3])
        name:SetPoint("TOPLEFT", last, "BOTTOMLEFT", 0, i == 1 and -16 or -10)
        local _, group = Options.radios(page, name, choices, function() return GAB.Fade.Mode(b[1]) end,
            function(mode) GAB.Settings.SetFade(b[1], mode) end, { 120, 150 })
        Options._test.fadeRows[b[1]] = group
        last = name
    end
    local how = label(page, "A faded bar is", "GameFontNormal")
    how:SetPoint("TOPLEFT", last, "BOTTOMLEFT", 0, -20)
    local _, group = Options.radios(page, how, Options.FADE_ALPHAS, function() return GAB.db.fadeAlpha end,
        GAB.Settings.SetFadeAlpha)
    Options._test.fadeAlpha = group
end)

-- Dock (#7): a section per registered smart bar, added on the first show
-- after it registers (a provider may load after the page was first opened).
local SIDE_LABELS = { LEFT = "Left", RIGHT = "Right", TOP = "Top", BOTTOM = "Bottom" }
local ALIGN_LABELS = { START = "Start", CENTER = "Center", END = "End" }
Options.dockPage = Options.AddPage("Dock", function(page, title)
    local Dock = GAB.Dock
    local note = label(page, "A smart bar docks beside one of Edit Mode's Action Bars 1-8 and follows it when the "
        .. "bar moves or changes size. Changes made in combat apply when the fight ends.", "GameFontHighlightSmall")
    note:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    note:SetPoint("RIGHT", page, "RIGHT", -16, 0)
    note:SetJustifyH("LEFT")
    local empty = label(page, "No smart bars yet: the Utility bar and addons that dock their bars appear here.",
        "GameFontDisable")
    empty:SetPoint("TOPLEFT", note, "BOTTOMLEFT", 0, -16)
    local sections, last = {}, note
    Options._test.dockSections = sections

    local function row(parent, anchor, text, choices, id, key, across)
        local name = label(parent, text)
        name:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -10)
        local _, group = Options.radios(parent, name, choices, function() return Dock.Setting(id, key) end,
            function(v) GAB.Settings.SetDock(id, key, v) end, across)
        return name, group
    end

    local function section(cl)
        local id = cl.id
        local f = CreateFrame("Frame", nil, page)
        f:SetSize(1, 1)
        f:SetPoint("TOPLEFT", last, "BOTTOMLEFT", 0, -16)
        local head = label(f, cl.label, "GameFontNormal")
        head:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
        local s = { frame = f }
        local bars = { { false, "Off" } }
        for i = 1, #Dock.BARS do bars[#bars + 1] = { i, tostring(i) } end
        local r1; r1, s.bar = row(f, head, "Docked to", bars, id, "bar", { 100, 50 })
        local sides = {}
        for _, v in ipairs(Dock.SIDES) do sides[#sides + 1] = { v, SIDE_LABELS[v] } end
        local r2; r2, s.side = row(f, r1, "Side", sides, id, "side", { 100, 80 })
        local aligns = {}
        for _, v in ipairs(Dock.ALIGNS) do aligns[#aligns + 1] = { v, ALIGN_LABELS[v] } end
        local r3; r3, s.align = row(f, r2, "Alignment", aligns, id, "align", { 100, 80 })
        local gaps = {}
        for _, v in ipairs(Dock.GAPS) do gaps[#gaps + 1] = { v, tostring(v) } end
        local r4; r4, s.gap = row(f, r3, "Gap", gaps, id, "gap", { 100, 50 })
        s.gapText = label(f, "", "GameFontHighlightSmall")
        s.gapText:SetPoint("LEFT", r4, "LEFT", 100 + #gaps * 50 + 10, 0)
        building[#building + 1] = function() s.gapText:SetText(("now %g"):format(Dock.Setting(id, "gap"))) end
        s.match = Options.checkbox(f, r4, "Match the bar's button size, spacing and rows",
            function() return Dock.Setting(id, "match") end, function(on) GAB.Settings.SetDock(id, "match", on) end)
        last = s.match
        return s
    end

    building[#building + 1] = function()
        local list, seen = Dock.Clients(), {}
        for _, cl in ipairs(list) do
            seen[cl.id] = true
            sections[cl.id] = sections[cl.id] or section(cl)
            sections[cl.id].frame:Show()
        end
        for id, s in pairs(sections) do
            if not seen[id] then s.frame:Hide() end
        end
        empty:SetShown(#list == 0)
    end
end)

-- Called once at PLAYER_LOGIN by GlassActionBars.lua.
function Options.Register()
    if category or not (Settings and Settings.RegisterCanvasLayoutCategory) then return end
    category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
    Settings.RegisterAddOnCategory(category)
    -- Gnomesweeper's measured order: the main page added, then its sub-pages.
    if Settings.RegisterCanvasLayoutSubcategory then
        for _, page in ipairs(pages) do
            local ok, err = pcall(Settings.RegisterCanvasLayoutSubcategory, category, page.frame, page.frame.name)
            if not ok then API.Fail("options:" .. page.frame.name, err) end
        end
    end
end

-- Open the page; false when the Settings framework can't.
function Options.Open()
    if not (category and Settings and Settings.OpenToCategory) then return false end
    return pcall(Settings.OpenToCategory, category:GetID()) and true or false
end

Options._test = { panel = panel, refreshers = refreshers, pages = pages }
