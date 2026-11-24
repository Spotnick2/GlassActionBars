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

-- Every control on a page re-read (a change in one moves others: a preset).
function Options.RefreshPage(frame)
    for _, page in ipairs(pages) do
        if page.frame == frame then
            for _, refresh in ipairs(page.refreshers) do refresh() end
        end
    end
end

-- The look: the glass, the text on the buttons, the gryphons, and glass or
-- Blizzard's own art.
Options.AddSection(function(parent, anchor)
    local Look = GAB.Look
    local look = label(parent, "The glass", "GameFontNormal")
    look:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -16)
    -- While following Glass UI, a first choice follows its tint (#39): it is
    -- selected whenever the player hasn't set their own (by source, not value).
    local following = Look.Following()
    local choices = {}
    if following then choices[1] = { "suite", "Glass UI" } end
    for _, name in ipairs(GAB.Theme.NAMES) do choices[#choices + 1] = { name, GAB.Theme.LABELS[name] } end
    local last, group = Options.radios(parent, look, choices, function()
        if following and Look.Own("theme") == nil then return "suite" end
        return GAB.Theme.Current()
    end, function(v)
        if v == "suite" then GAB.Settings.ClearLook("theme") else GAB.Settings.SetTheme(v) end
    end)
    if following and group[1].text then
        building[#building + 1] = function()
            group[1].text:SetText("Glass UI (" .. (GAB.Theme.LABELS[Look.SuiteValue("theme") or "clear"] or "?") .. ")")
        end
    end
    Options._test.themeRadios = group
    -- The material (LibGlass's preset), built at login: a change waits for a
    -- /reload. Glass UI's while following.
    local material = label(parent, "The glass itself (after a /reload)")
    material:SetPoint("TOPLEFT", last, "BOTTOMLEFT", 0, -12)
    if following then
        local note = label(parent, "", "GameFontHighlightSmall")
        note:SetPoint("LEFT", material, "LEFT", 240, 0)
        building[#building + 1] = function()
            note:SetText("Glass UI's: " .. tostring(GAB.GlassPreset) .. " (set in Glass UI)")
        end
        Options._test.materialNote = note
    else
        local _, mgroup = Options.radios(parent, material,
            { { "pearl", "Pearl" }, { "clean", "Clean" }, { "classic", "Classic" } },
            Look.Material, GAB.Settings.SetMaterial, { 240, 90 })
        Options._test.materialRadios = mgroup
    end
    last = material
    -- The micro menu (#57): each button on glass, or one pill behind them.
    local micro = label(parent, "The micro menu")
    micro:SetPoint("TOPLEFT", last, "BOTTOMLEFT", 0, -12)
    local _, microGroup = Options.radios(parent, micro,
        { { "tiles", GAB.Micro.LABELS.tiles }, { "pill", GAB.Micro.LABELS.pill } },
        GAB.Micro.Style, GAB.Settings.SetMicroStyle, { 240, 120 })
    Options._test.microRadios = microGroup
    last = micro
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

-- With Glass Unit Frames (#30): the stance and pet bars follow its frames.
Options.AddSection(function(parent, anchor)
    local head = label(parent, "With Glass Unit Frames", "GameFontNormal")
    head:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -16)
    local follow = Options.checkbox(parent, head, "Move the stance and pet bars with its player and pet frames",
        function() return GAB.db.follow end, GAB.Settings.SetFollow)
    Options._test.follow = follow
    return follow
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

-- Buttons (#34): how a button answers the pointer and a click, and how an
-- empty slot shows; a preset sets all three, and the page says when they
-- match none.
Options.LOOK_ROWS = {
    { "hover", "When pointed at", { { "off", "Off" }, { "glow", "Glow" }, { "halo", "Halo" } } },
    { "press", "When clicked", { { "off", "Off" }, { "flash", "Flash" }, { "ripple", "Ripple (on a click)" } } },
    { "emptySlots", "Empty slots", { { "hidden", "Hidden" }, { "faint", "Faint" }, { "half", "Half" }, { "full", "Full" },
        { "frosted", "Frosted" } } },
}
Options.LOOK_PRESETS = { { "glass", "Glass" }, { "soft", "Soft" }, { "minimal", "Minimal" } }
-- The radio columns: five choices fit the page (Frosted overflowed at 150/110).
Options.LOOK_ACROSS = { 130, 90 }
Options.lookPage = Options.AddPage("Buttons", function(page, title)
    local B = GAB.Buttons
    local note = label(page, "How the buttons answer the pointer and a click, and how empty slots show. A preset "
        .. "sets them all. The ripple answers a mouse click; a key press flashes.",
        "GameFontHighlightSmall")
    note:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    note:SetPoint("RIGHT", page, "RIGHT", -16, 0)
    note:SetJustifyH("LEFT")
    -- While following Glass UI (#39), each row's first choice follows the
    -- suite, selected by source: whenever the player hasn't set their own.
    local Look = GAB.Look
    local following = Look.Following()
    local across = following and { 130, 80 } or Options.LOOK_ACROSS
    local function withSuite(list)
        if not following then return list end
        local out = { { "suite", "Glass UI" } }
        for _, c in ipairs(list) do out[#out + 1] = c end
        return out
    end
    local function allSuite()
        for _, k in ipairs(B.LOOK_ORDER) do
            if Look.Own(k) ~= nil then return false end
        end
        return true
    end
    local head = label(page, "Preset")
    head:SetPoint("TOPLEFT", note, "BOTTOMLEFT", 0, -16)
    local presetChoices = withSuite(Options.LOOK_PRESETS)
    local _, presets = Options.radios(page, head, presetChoices, function()
        if following and allSuite() then return "suite" end
        return B.Preset()
    end, function(name)
        GAB.Settings.SetLookPreset(name)
        Options.RefreshPage(page)
    end, across)
    local now = label(page, "", "GameFontHighlightSmall")
    now:SetPoint("LEFT", head, "LEFT", across[1] + #presetChoices * across[2], 0)
    building[#building + 1] = function()
        now:SetText(B.Preset() == "custom" and not (following and allSuite()) and "now: your own mix" or "")
    end
    Options._test.lookPresets, Options._test.lookNow, Options._test.lookRows = presets, now, {}
    local last = head
    for i, r in ipairs(Options.LOOK_ROWS) do
        local name = label(page, r[2])
        name:SetPoint("TOPLEFT", last, "BOTTOMLEFT", 0, i == 1 and -20 or -12)
        local _, group = Options.radios(page, name, withSuite(r[3]), function()
            if following and Look.Own(r[1]) == nil then return "suite" end
            return B.Look(r[1])
        end, function(v)
            if v == "suite" then GAB.Settings.ClearLook(r[1]) else GAB.Settings.SetLook(r[1], v) end
            Options.RefreshPage(page)
        end, across)
        Options._test.lookRows[r[1]] = group
        last = name
    end
    if following then
        local suiteNow = label(page, "", "GameFontHighlightSmall")
        suiteNow:SetPoint("TOPLEFT", last, "BOTTOMLEFT", 0, -16)
        building[#building + 1] = function()
            local parts = {}
            for _, k in ipairs(B.LOOK_ORDER) do parts[#parts + 1] = tostring(Look.SuiteValue(k) or Look.DEFAULTS[k]) end
            suiteNow:SetText("Glass UI's look now: " .. table.concat(parts, ", ") .. ". Set it in Glass UI.")
        end
        Options._test.lookSuiteNow = suiteNow
    end
end)

-- A scrolling area filling a page below `anchor`: the Settings canvas is a
-- fixed size and supplies no scrolling. GlassUnitFrames' measured recipe:
-- UIPanelScrollFrameTemplate, the mouse wheel without it, the bar shown only
-- when there is a range. Returns the scroll child (set its height as content
-- is added) and a 1x1 frame at its top-left to anchor the first control to.
function Options.scrollArea(page, anchor)
    local scroll = CreateFrame("ScrollFrame", nil, page, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -8)
    scroll:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -26, 8)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(560, 1)
    scroll:SetScrollChild(content)
    if not scroll.ScrollBar then
        scroll:EnableMouseWheel(true)
        scroll:SetScript("OnMouseWheel", function(self, delta)
            local range = API.Plain(self:GetVerticalScrollRange()) or 0
            local v = API.Plain(self:GetVerticalScroll()) or 0
            self:SetVerticalScroll(math.max(0, math.min(range, v - delta * 40)))
        end)
    else
        scroll:HookScript("OnScrollRangeChanged", function(self, _, yrange)
            self.ScrollBar:SetShown((API.Plain(yrange) or API.Plain(self:GetVerticalScrollRange()) or 0) > 0)
        end)
    end
    scroll:SetScript("OnSizeChanged", function(_, w)
        w = API.Plain(w)
        if type(w) == "number" and w > 0 then content:SetWidth(w) end
    end)
    local top = CreateFrame("Frame", nil, content)
    top:SetSize(1, 1)
    top:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
    return content, top
end

-- Dock (#7): a section per registered smart bar, added on the first show
-- after it registers (a provider may load after the page was first opened).
local SIDE_LABELS = { LEFT = "Left", RIGHT = "Right", TOP = "Top", BOTTOM = "Bottom" }
local ALIGN_LABELS = { START = "Start", CENTER = "Center", END = "End" }
-- A section's height: its heading, four rows of radios and the checkbox, with
-- the space above the next one. Generous: a little slack only adds scroll.
Options.DOCK_SECTION_HEIGHT = 218   -- a section, two checkboxes (#48) included
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
    -- The sections scroll: any number of providers may register (Codex review of #24).
    local content, top = Options.scrollArea(page, note)
    local sections, last, built = {}, top, 0
    Options._test.dockSections, Options._test.dockContent = sections, content

    local function row(parent, anchor, text, choices, id, key, across)
        local name = label(parent, text)
        name:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -10)
        local _, group = Options.radios(parent, name, choices, function() return Dock.Setting(id, key) end,
            function(v) GAB.Settings.SetDock(id, key, v) end, across)
        return name, group
    end

    local function section(cl)
        local id = cl.id
        local f = CreateFrame("Frame", nil, content)
        f:SetSize(1, 1)
        f:SetPoint("TOPLEFT", last, "BOTTOMLEFT", 0, built == 0 and -4 or -16)
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
        s.match = Options.checkbox(f, r4, "Match the bar's button size and spacing",
            function() return Dock.Setting(id, "match") end, function(on) GAB.Settings.SetDock(id, "match", on) end)
        s.matchRows = Options.checkbox(f, s.match, "Match the bar's rows and direction",
            function() return Dock.Setting(id, "matchRows") end, function(on) GAB.Settings.SetDock(id, "matchRows", on) end)
        last = s.matchRows
        built = built + 1
        content:SetHeight(built * Options.DOCK_SECTION_HEIGHT + 16)   -- the scroll range follows
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

-- The Utility bar (#9): on or off, then each entry (the actions and the
-- Camping group) with a show checkbox and up/down buttons, in the player's
-- order. The rows are re-anchored on every show, so a move shows at once.
Options.UTILITY_ROW = 26
Options.UTILITY_LAYOUT = {
    { "orientation", "Direction", { { "HORIZONTAL", "Horizontal" }, { "VERTICAL", "Vertical" } } },
    { "rows", "Rows (columns when vertical)", { { 1, "1" }, { 2, "2" }, { 3, "3" }, { 4, "4" } } },
    { "iconSize", "Button size", { { 30, "30" }, { 36, "36" }, { 40, "40" }, { 45, "45" } } },
    { "iconPadding", "Spacing", { { 0, "0" }, { 2, "2" }, { 4, "4" }, { 6, "6" } } },
}
-- A bar's own layout radios (bar n), under `anchor`; returns the last row's
-- name and { key -> radio group }.
local function utilityLayout(page, anchor, n)
    local last, groups = anchor, {}
    for _, r in ipairs(Options.UTILITY_LAYOUT) do
        local name = label(page, r[2])
        name:SetPoint("TOPLEFT", last, "BOTTOMLEFT", 0, -10)
        local _, group = Options.radios(page, name, r[3], function() return GAB.Utility.LayoutSetting(r[1], n) end,
            function(v) GAB.Settings.SetUtilityLayout(r[1], v, n) end, { 200, 90 })
        groups[r[1]] = group
        last = name
    end
    return last, groups
end

Options.utilityPage = Options.AddPage("Utility bar", function(page, title)
    local U = GAB.Utility
    local enabled = Options.checkbox(page, title, "Show the Utility bar",
        function() return U.Enabled() end, function(on) GAB.Settings.SetUtilityEnabled(on) end)
    local note = label(page, "A button shows only when the character can use it: a profession it knows, an item in "
        .. "its bags. Campfire kits show whenever carried, the other camping items only near a campfire. Key "
        .. "bindings: Esc > Options > Keybindings > Glass Action Bars. Docking: the Dock page. Hold Alt and drag "
        .. "the bar to put it anywhere: that undocks it, and the spot is shared by every character. Buttons from "
        .. "other addons start unticked, and their key bindings stay in that addon's section. Drag a spell from "
        .. "your spellbook onto the bar to add it (it shows on the characters that know it). Hold Shift (the Pick "
        .. "Up Action key) and drag a button to move it, to the other bar, or off the bar to take it off. "
        .. "A second bar: the Utility bar 2 page.",
        "GameFontHighlightSmall")
    note:SetPoint("TOPLEFT", enabled, "BOTTOMLEFT", 0, -8)
    note:SetPoint("RIGHT", page, "RIGHT", -16, 0)
    note:SetJustifyH("LEFT")
    -- Its own layout: undocked, or docked with Match off.
    local head = label(page, "Layout (undocked, or when Match is off on the Dock page)", "GameFontNormal")
    head:SetPoint("TOPLEFT", note, "BOTTOMLEFT", 0, -12)
    local last
    last, Options._test.utilityLayout = utilityLayout(page, head, 1)
    local content, top = Options.scrollArea(page, last)
    local rows, sync = {}, nil
    -- Each bar's heading in the list (#86).
    local heads = {}
    for n = 1, U.BARS do
        heads[n] = label(content, n == 1 and "Utility bar" or "Utility bar " .. n, "GameFontNormal")
    end
    -- A row per entry, made the first time it is listed (another addon's
    -- button registers at login, after this page may exist).
    local function makeRow(key)
        local r = CreateFrame("Frame", nil, content)
        r:SetSize(420, Options.UTILITY_ROW)
        local cb = CreateFrame("CheckButton", nil, r, "UICheckButtonTemplate")
        cb:SetSize(24, 24)
        cb:SetPoint("LEFT", r, "LEFT", 0, 0)
        local text = label(r, U.Label(key))
        text:SetPoint("LEFT", cb, "RIGHT", 4, 0)
        cb:SetScript("OnClick", function() GAB.Settings.SetUtilityShown(key, cb:GetChecked() == true); sync() end)
        local moves = {}
        for i, m in ipairs({ { -1, "Up" }, { 1, "Down" } }) do
            local b = CreateFrame("Button", nil, r, "UIPanelButtonTemplate")
            b:SetSize(52, 20)
            b:SetText(m[2])
            b:SetPoint("LEFT", r, "LEFT", 300 + (i - 1) * 56, 0)
            b:SetScript("OnClick", function() GAB.Settings.MoveUtility(key, m[1]); sync() end)
            moves[i] = b
        end
        -- The other bar (#86): the button names where it goes.
        local move = CreateFrame("Button", nil, r, "UIPanelButtonTemplate")
        move:SetSize(52, 20)
        move:SetPoint("LEFT", r, "LEFT", 300 + 2 * 56, 0)
        move:SetScript("OnClick", function() GAB.Settings.SetUtilityBar(key, 3 - U.BarOf(key)); sync() end)
        local remove
        if U.SpellId(key) then   -- a dropped spell (#86)
            remove = CreateFrame("Button", nil, r, "UIPanelButtonTemplate")
            remove:SetSize(70, 20)
            remove:SetText("Remove")
            remove:SetPoint("LEFT", r, "LEFT", 300 + 3 * 56, 0)
            remove:SetScript("OnClick", function() GAB.Settings.RemoveUtility(key); sync() end)
        end
        rows[key] = { frame = r, check = cb, up = moves[1], down = moves[2], bar = move, remove = remove, text = text }
        return rows[key]
    end
    -- The entries registered this session, bar by bar under its heading, in
    -- order, with no gap for the others. Every row hidden first: a removed
    -- spell's key is gone from the order.
    sync = function()
        for _, row in pairs(rows) do row.frame:Hide() end
        local y = 0
        for n = 1, U.BARS do
            if n > 1 then y = y + 8 end
            heads[n]:ClearAllPoints()
            heads[n]:SetPoint("TOPLEFT", top, "TOPLEFT", 0, -y - 4)
            y = y + Options.UTILITY_ROW
            for _, key in ipairs(U.Order()) do
                if U.Registered(key) and U.BarOf(key) == n then
                    local row = rows[key] or makeRow(key)
                    row.frame:ClearAllPoints()
                    row.frame:SetPoint("TOPLEFT", top, "TOPLEFT", 0, -y)
                    row.frame:Show()
                    row.check:SetChecked(U.IsShown(key))
                    row.bar:SetText(n == 1 and "Bar 2" or "Bar 1")
                    if U.SpellId(key) then row.text:SetText(U.Label(key)) end   -- a name not loaded at first
                    y = y + Options.UTILITY_ROW
                end
            end
        end
        content:SetHeight(y + 16)
    end
    sync()
    building[#building + 1] = sync
    Options._test.utilityRows = rows
    Options._test.utilityHeads = heads
end)

-- The second Utility bar (#86): on or off, and its own layout. Its entries
-- are on the Utility bar page.
Options.utility2Page = Options.AddPage("Utility bar 2", function(page, title)
    local enabled = Options.checkbox(page, title, "Show Utility bar 2",
        function() return GAB.Utility.Enabled(2) end, function(on) GAB.Settings.SetUtilityEnabled(on, 2) end)
    local note = label(page, "A second bar for anything the Utility bar shows: a class's own spells, Feed Pet, a "
        .. "column beside your action bars. Hold Shift and drag a button from the first bar onto it, drop a spell "
        .. "from your spellbook on it, or use the Bar 2 buttons on the Utility bar page. Turned off, its buttons "
        .. "show nowhere. Docking: the Dock page. Hold Alt and drag it to put it anywhere.", "GameFontHighlightSmall")
    note:SetPoint("TOPLEFT", enabled, "BOTTOMLEFT", 0, -8)
    note:SetPoint("RIGHT", page, "RIGHT", -16, 0)
    note:SetJustifyH("LEFT")
    local head = label(page, "Layout (undocked, or when Match is off on the Dock page)", "GameFontNormal")
    head:SetPoint("TOPLEFT", note, "BOTTOMLEFT", 0, -12)
    local _, groups = utilityLayout(page, head, 2)
    Options._test.utility2Layout = groups
    Options._test.utility2Enabled = enabled
end)

-- Proc alerts (#115): the three switches, the overlays' look, and each effect
-- of the player's class.
Options.PROC_SWITCHES = {
    { "overlays", "Screen overlays while a proc is up" },
    { "glow", "Glow on the action button of the spell to press" },
    { "sound", "A sound when a proc comes" },
}
Options.PROC_LOOK = { { "opacity", "Overlay opacity" }, { "scale", "Overlay size" }, { "offset", "Overlay spacing" } }
Options.procsPage = Options.AddPage("Proc alerts", function(page, title)
    local Procs = GAB.Procs
    local note = label(page, "", "GameFontHighlightSmall")
    note:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    note:SetPoint("RIGHT", page, "RIGHT", -16, 0)
    note:SetJustifyH("LEFT")
    building[#building + 1] = function()
        local t = "Blizzard's own proc art, shown by the game's aura engine, in combat too. A glow fades with its "
            .. "bar when the bar fades."
        if Procs.SAOLoaded() then
            t = t .. " SpellActivationOverlay is loaded, so these start off: tick them to use GAB's instead, and "
                .. "turn SpellActivationOverlay off in the AddOns list."
        end
        if Procs.Waiting() then t = t .. " |cffffd100A change waits for the fight or the boss encounter to end.|r" end
        note:SetText(t)
    end
    local last = note
    Options._test.procSwitches = {}
    for i, s in ipairs(Options.PROC_SWITCHES) do
        local cb = Options.checkbox(page, last, s[2], function() return Procs.Enabled(s[1]) end,
            function(on) GAB.Settings.SetProc(s[1], on) end)
        if i == 1 then cb:SetPoint("TOPLEFT", last, "BOTTOMLEFT", 0, -12) end
        Options._test.procSwitches[s[1]] = cb
        last = cb
    end
    Options._test.procLook = {}
    for i, r in ipairs(Options.PROC_LOOK) do
        local name = label(page, r[2])
        name:SetPoint("TOPLEFT", last, "BOTTOMLEFT", 0, i == 1 and -16 or -10)
        local _, group = Options.radios(page, name, Procs.LOOK[r[1]][2], function() return Procs.Look(r[1]) end,
            function(v) GAB.Settings.SetProcLook(r[1], v) end, { 140, 120 })
        Options._test.procLook[r[1]] = group
        last = name
    end
    local effects = Procs.Effects()
    local head = label(page, #effects > 0 and "Your class's alerts" or "Your class has no proc alerts yet.", "GameFontNormal")
    head:SetPoint("TOPLEFT", last, "BOTTOMLEFT", 0, -20)
    last = head
    Options._test.procEffects = {}
    for _, e in ipairs(effects) do
        local cb = Options.checkbox(page, last, e.label, function() return Procs.EffectOn(e.key) end,
            function(on) GAB.Settings.SetProcEffect(e.key, on) end)
        Options._test.procEffects[e.key] = cb
        last = cb
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
