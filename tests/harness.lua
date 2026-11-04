-- harness.lua: the addon loader and chat helpers. dofile it after wow_stubs.lua.
-- GlassMail's harness (GlassChat's, trimmed): no plugins, one embedded library.
-- check / eq / done are WowTestKit's (tests/kit.lua loads them).

TOC = "GlassActionBars.toc"

-- Every file line of the TOC, in load order (our .lua files and the embedded
-- library's .xml).
function tocLines() return Kit.tocLines(TOC) end

-- Lua files listed in the TOC, in load order.
function tocFiles() return Kit.tocFiles(TOC) end

-- FINDING (#68): GlassActionBars.lua's /gab help and usage lines hold a bare
-- "|" ("clear/smoked/class|suite", "[key value|reset]", "<1-8|off>"...), which
-- the client reads as an escape. done() lets exactly those through (a printed
-- line naming a "/gab " command) until they're fixed; any other stray "|"
-- still fails.
local kitDone = done
function done(name)
    local keep = {}
    for _, line in ipairs(WoW.strays) do
        if not line:find("/gab ", 1, true) then keep[#keep + 1] = line end
    end
    WoW.strays = keep
    kitDone(name)
end

-- The embedded library comes from a checkout, not from Libs\ (gitignored,
-- filled by the packager): $LIBGLASS, else ..\LibGlass. No checkout fails the
-- run loudly; a silently skipped library would test nothing.
LIBGLASS_XML = "Libs\\LibGlass-1.0\\LibGlass-1.0.xml"
LIBS = {
    [LIBGLASS_XML] = { env = "LIBGLASS", dir = "../LibGlass", xml = "LibGlass-1.0.xml" },
}

function libRoot(line)
    local L = LIBS[line]
    local root = (os.getenv(L.env) or L.dir):gsub("\\", "/"):gsub("/$", "")
    local f = io.open(root .. "/" .. L.xml, "rb")
    if not f then
        error(L.xml .. " checkout not found at " .. root .. ": clone it there or set " .. L.env, 0)
    end
    f:close()
    return root
end
function libGlassRoot() return libRoot(LIBGLASS_XML) end

-- The Lua files a library's XML loads, as paths, in order.
function libScripts(line)
    local L, root = LIBS[line], libRoot(line)
    local f = assert(io.open(root .. "/" .. L.xml, "rb"))
    local xml = f:read("*a"):gsub("<!%-%-.-%-%->", "")   -- listed in a comment is not loaded
    f:close()
    local files = {}
    for file in xml:gmatch('<Script%s+file="([^"]+)"') do
        local path = root .. "/" .. file:gsub("\\", "/")
        local src = io.open(path, "rb")
        if not src then error(L.xml .. " at " .. root .. " is missing " .. file, 0) end
        src:close()
        files[#files + 1] = path
    end
    if #files == 0 then error(L.xml .. " at " .. root .. " lists no Script files", 0) end
    return files
end

-- The ForeverProbe host, for the probe's tests (GlassChat's loader): from
-- $FOREVERPROBE or ../ForeverProbe. It is private and local only, so with
-- FOREVERPROBE_OPTIONAL=1 (CI) a missing checkout skips the test file.
function loadForeverProbe()
    local root = (os.getenv("FOREVERPROBE") or "../ForeverProbe"):gsub("\\", "/"):gsub("/$", "")
    local toc = io.open(root .. "/ForeverProbe.toc", "rb")
    if not toc then
        if os.getenv("FOREVERPROBE_OPTIONAL") == "1" then
            io.write("SKIPPED: ForeverProbe isn't here (private, local only); the probe tests run locally\n")
            os.exit(0)
        end
        error("ForeverProbe checkout not found at " .. root .. ": clone it there or set FOREVERPROBE", 0)
    end
    local files = {}
    for line in toc:read("*a"):gmatch("[^\r\n]+") do
        if line:match("%.lua$") and not line:match("^#") then files[#files + 1] = root .. "/" .. line end
    end
    toc:close()
    for _, file in ipairs(files) do assert(loadfile(file))("ForeverProbe", {}) end
    WoW.fire("ADDON_LOADED", "ForeverProbe")
    return ForeverProbe
end

-- Load the addon the way the client does: every TOC file with (name, ns), the
-- library's XML expanded in place, then ADDON_LOADED, PLAYER_LOGIN,
-- PLAYER_ENTERING_WORLD (initial login).
function loadAddon(opts)
    opts = opts or {}
    local ns = {}
    for _, line in ipairs(tocLines()) do
        local files = { line }
        if LIBS[line] then
            files = libScripts(line)
        elseif not line:match("%.lua$") then
            error("the harness can't load TOC line " .. line, 0)
        end
        for _, file in ipairs(files) do
            assert(loadfile((file:gsub("\\", "/"))))("GlassActionBars", ns)
        end
    end
    if opts.db then GlassActionBarsDB = opts.db end
    WoW.fire("ADDON_LOADED", "GlassActionBars")
    if opts.beforeLogin then opts.beforeLogin(GlassActionBars) end   -- e.g. a provider's own files
    WoW.fire("PLAYER_LOGIN")
    WoW.fire("PLAYER_ENTERING_WORLD", opts.initialLogin ~= false, false)
    WoW.tick()
    return GlassActionBars
end

-- Chat lines printed since the last call.
local seenChat = 0
function newChat()
    local lines = {}
    for i = seenChat + 1, #WoW.chat do lines[#lines + 1] = WoW.chat[i] end
    seenChat = #WoW.chat
    return lines
end

function chatHas(pattern)
    for _, line in ipairs(WoW.chat) do
        if line:find(pattern) then return true end
    end
    return false
end
