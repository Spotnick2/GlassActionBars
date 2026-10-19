-- The manifest, the pinned build, the event fixture and the embedded material.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local toc = io.open(TOC):read("*a")
check(toc:find("## Interface: 16001", 1, true), "interface 16001 (1.60.1; 11601 is the transposed-digit bug)")
check(toc:find("## Version: @project-version@", 1, true), "packager version token kept")
check(toc:find("## SavedVariables: GlassActionBarsDB", 1, true), "saved variables declared")
check(toc:find("## X-Curse-Project-ID: 1744070", 1, true), "the CurseForge project")
-- Dependencies go provider -> GAB only: GAB never names a provider.
check(not toc:find("## OptionalDeps", 1, true) and not toc:find("## Dependencies", 1, true),
    "no dependency on any other addon")
for _, f in ipairs(tocFiles()) do
    check(io.open(f, "r") ~= nil, "TOC file exists: " .. f)
end
-- The embedded material loads before any of our files: Glass.lua calls
-- LibStub("LibGlass-1.0") at file scope.
eq(tocLines()[1], LIBGLASS_XML, "LibGlass-1.0 loads first")
eq(tocFiles()[1], "Compat.lua", "Compat is the first of our own files")
eq(tocFiles()[#tocFiles()], "GlassActionBars.lua", "the bootstrap loads last")
local seen = {}
for _, f in ipairs(tocFiles()) do
    check(not seen[f], "TOC lists each file once: " .. f)
    seen[f] = true
end

-- Two places that must agree, never derived from each other (porting guide section 0).
loadAddon()
eq(GlassActionBars.MEASURED_ON_BUILD, "1.60.1.70374", "MEASURED_ON_BUILD")

-- The checked-in event list matches the dump, when the dump is here.
if WoW.dumpAvailable then
    local fixture = {}
    for line in io.lines("tests/events-70374.txt") do
        local name = line:match("^([A-Z][A-Z0-9_]+)%s*$")
        if name then fixture[name] = true end
    end
    local missing, extra = 0, 0
    for e in pairs(WoW.KNOWN_EVENTS) do if not fixture[e] then missing = missing + 1 end end
    for e in pairs(fixture) do if not WoW.KNOWN_EVENTS[e] then extra = extra + 1 end end
    eq(missing + extra, 0, "tests/events-70374.txt matches the dump (regenerate it)")
end

-- Every texture the material names ships with the library.
local root = libGlassRoot()
for size, S in pairs(GlassActionBars.Glass.SIZES) do
    for _, key in ipairs({ "mask", "rim", "dark", "shadow" }) do
        local f = root .. "/Media/" .. S[key] .. ".tga"
        check(io.open(f, "rb") ~= nil, size .. " texture exists: " .. f)
    end
end
-- Glass.MEDIA points into the embedded copy, where the packager puts it.
eq(GlassActionBars.Glass.STYLE.thinRim, true, "the clean material (LibGlass r6): thin rims")
eq(GlassActionBars.Glass.STYLE.grain, 0, "  no grain")
eq(GlassActionBars.Glass.MEDIA, "Interface\\AddOns\\GlassActionBars\\Libs\\LibGlass-1.0\\Media\\",
    "MEDIA is the embedded copy's")
eq(GlassActionBars.MEDIA, "Interface\\AddOns\\GlassActionBars\\Media\\", "our own media folder")

-- Our own textures ship, as uncompressed 32-bit TGA (what Tools/make_rim.py writes).
local tga = io.open("Media/ButtonRim.tga", "rb")
check(tga ~= nil, "Media/ButtonRim.tga exists")
if tga then
    local header = tga:read(18)
    tga:close()
    eq(header:byte(3), 2, "  uncompressed truecolour")
    eq(header:byte(13) + 256 * header:byte(14), 32, "  32 wide (body_mask_small's size)")
    eq(header:byte(15) + 256 * header:byte(16), 32, "  32 high")
    eq(header:byte(17), 32, "  32 bits, with alpha")
end

for _, asset in ipairs({ { "ButtonGloss", 64 }, { "ButtonSocketRim", 32 }, { "ButtonSocketShade", 32 } }) do
    local f = io.open("Media/" .. asset[1] .. ".tga", "rb")
    check(f ~= nil, "Pearl asset ships: " .. asset[1])
    if f then
        local h = f:read(18)
        f:close()
        eq(h:byte(3), 2, asset[1] .. ": uncompressed truecolour")
        eq(h:byte(13) + 256 * h:byte(14), asset[2], asset[1] .. ": width")
        eq(h:byte(15) + 256 * h:byte(16), asset[2], asset[1] .. ": height")
        eq(h:byte(17), 32, asset[1] .. ": alpha channel")
    end
end

done("test_toc")
