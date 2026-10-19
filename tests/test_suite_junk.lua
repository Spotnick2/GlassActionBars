-- A Glass UI GAB can't follow (#39): every malformed suite counts as absent,
-- a throwing Theme leaves GAB on its own look, an old LibGlass without Pearl
-- builds Clean and says why; an empty profile builds Pearl (the default).
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local reports = {}
GlassUI = { Suite = {
    API = 1,
    Theme = function() error("boom") end,
    Report = function(_, state) reports[#reports + 1] = state end,
} }
local GAB = loadAddon({ beforeLogin = function(G)
    -- A winning LibGlass older than r11: no "pearl" preset.
    local lib = LibStub("LibGlass-1.0")
    local new = lib.New
    lib.New = function(self, opts)
        if opts and opts.preset == "pearl" then error('LibGlass-1.0: unknown preset pearl (use "classic" or "clean")') end
        return new(self, opts)
    end
end })
local L = GAB.Look
check(not L.Following(), "Theme throwing: not following")
eq(GAB.GlassPreset, "clean", "an empty profile asks Pearl; the old library has none: Clean")
eq(L._test.failure(), "library-too-old", "  and why")
check(GAB.failures["look:material"] ~= nil, "  said in /gab failures")
local r = reports[#reports]
check(r and r.built == nil and r.reason == nil, "reported: its own look (built nil), no reason (it wasn't told Pearl)")

-- Malformed suites: each counts as absent.
local api = L._test.suiteAPI
local function with(suite) GlassUI = suite; return api() end
eq(with(nil), nil, "no GlassUI: absent")
eq(with({}), nil, "no Suite: absent")
eq(with({ Suite = "x" }), nil, "Suite not a table: absent")
eq(with({ Suite = { API = 2, Theme = print, Report = print } }), nil, "API 2: absent")
eq(with({ Suite = { API = 1, Theme = print } }), nil, "no Report: absent")
check(with({ Suite = { API = 1, Theme = print, Report = print } }) ~= nil, "API 1 with both: spoken")
done("test_suite_junk")
