-- ProcData.lua: the proc alerts' effects, per class (#115, docs/PLAN-procs.md).
--
-- Ported from SpellActivationOverlay 3.0.0-forever's effect tables
-- (classes/*.lua, components/item.lua's Revelation), Copyright (c) 2022-2026
-- ennvina, MIT License (see LICENSE, THIRD-PARTY COMPONENTS). Forever's aura
-- effects only: counters (a reactive ability usable) are PR 3. The glow pairs
-- are GAB's own: SAO's aura effects glow no button on Forever.
--
-- One entry per effect:
-- - key: its setting key (procs.off[key]), never shown;
-- - label: the options page's text;
-- - unit, filter: whose auras, as the engine reads them (HELPFUL on the
--   player, HARMFUL on the target: anyone's freeze counts, as in SAO;
--   HARMFUL|PLAYER for mine only);
-- - auras: the filter's spell ids, every alias. Never SAO's display
--   stand-in 5276 for the freeze;
-- - overlays: { texture, position = "LEFT" / "RIGHT" / "TOP", hflip, cw
--   (rotated a quarter turn clockwise), stacks (shown at that many or more),
--   scale, color {r, g, b[, a]} out of 255, outer (pushed out, in short sides;
--   negative pulls in), level (over the container, SAO's draw order: default
--   Procs.LEVEL, 3), pulse };
-- - sound: the proc sound on Added and ApplicationsIncreased (SAO plays it for
--   the effects that pulse);
-- - glow: the cast spell ids whose buttons glow, every rank: no API maps a rank
--   to rank 1 on this client (docs/FOREVER-PROBE.md, run #620). The mage's
--   pairs were checked in game (runs #620-#630); every other class's are taken
--   from SAO's other versions, where the same aura id glows that spell, and
--   are checked as the owner plays the class (the owner, 2026-11-24).
--
-- Textures are client fileDataIDs (SAO's textures/texname.lua), except
-- Eclipse's, shipped as Media/Eclipse_Moon.tga (Tools/make_eclipse.py).
-- Rank ids: SkillLineAbility, build 70959.

GlassActionBars = GlassActionBars or {}
local GAB = GlassActionBars

local ARCANE_MISSILES, FROZEN_FINGERS, GENERIC_ARC_05, HOT_STREAK = 449486, 449489, 450921, 449490
local GENERIC_ARC_02, GENERIC_TOP_01, NATURES_GRACE, SERENDIPITY = 450918, 450923, 450929, 469752
local RAGING_BLOW, WHITE_TIGER, DAYBREAK, HAND_OF_LIGHT, DENOUNCE = 962497, 603339, 459313, 459314, 511469
local FURY_OF_STORMRAGE, NIGHTFALL, IMPACT = 460831, 449492, 457658
local ECLIPSE_MOON = (GAB.MEDIA or "Interface\\AddOns\\GlassActionBars\\Media\\") .. "Eclipse_Moon"

-- Ice Lance's ranks on Forever: SkillLineAbility (build 70959) under the
-- mage's Frost line. Rank 1 is 400640, rank 2 1240044 (seen on the bars at
-- level 34). Both glows were checked in game with these (runs #620-#630).
local ICE_LANCE = { 400640, 1240044, 1240045, 1240046, 1240047, 1312002 }

-- Not yet checked in game (the class's own play): every rank in the
-- class's SkillLineAbility rows.
local SHADOW_BOLT = { 686, 695, 705, 1088, 1106, 7641, 11659, 11660, 11661, 25307 }
local SOUL_FIRE = { 6353, 17924 }
local HOLY_LIGHT = { 635, 639, 647, 1026, 1042, 3472, 10328, 10329, 19968, 19980, 19981, 19982, 25292,
    1313348, 1313349, 1313350, 1313351, 1313352 }
local FLASH_OF_LIGHT = { 19750, 19939, 19940, 19941, 19942, 19943, 19993, 412020,
    1313342, 1313343, 1313344, 1313345, 1313346 }
local AMBUSH = { 8676, 8724, 8725, 11267, 11268, 11269 }

local function join(...)
    local t = {}
    for _, list in ipairs({ ... }) do for _, v in ipairs(list) do t[#t + 1] = v end end
    return t
end

-- A frozen target: SAO's freeze aliases (mage.lua:161-173). Frost Nova
-- (865) was seen to match in game (run #622).
local FREEZE = { 12494, 122, 865, 6131, 10230, 27088, 42917, 3355, 14308, 14309, 33395, 55080,
    44572, 428739, 49203, 83301, 83302, 82691 }

-- Both sides, the right one mirrored (SAO's "Left + Right (Flipped)").
local function sides(spec)
    local l, r = {}, { position = "RIGHT", hflip = true }
    for k, v in pairs(spec) do l[k] = v; r[k] = r[k] or v end
    l.position = "LEFT"
    return l, r
end

-- The Revelation weapon enchant's buff, one id per class (SAO's
-- components/item.lua, CreateRevelationEffect): no pulse, no sound.
local function revelation(aura)
    return { key = "revelation", label = "Revelation (weapon enchant)", unit = "player", filter = "HELPFUL",
        auras = { aura },
        overlays = { sides({ texture = GENERIC_ARC_02, outer = 1, color = { 210, 145, 178 } }) } }
end

GAB.ProcData = {
    MAGE = {
        { key = "missile_barrage", label = "Missile Barrage", unit = "player", filter = "HELPFUL",
          auras = { 400589 }, sound = true,
          overlays = { sides({ texture = ARCANE_MISSILES, outer = 0.32, level = 5, pulse = true }) } },
        { key = "clearcasting", label = "Clearcasting", unit = "player", filter = "HELPFUL",
          auras = { 12536 },
          overlays = { sides({ texture = GENERIC_ARC_05, outer = 0.75, level = 7 }) } },
        { key = "freeze", label = "A frozen target", unit = "target", filter = "HARMFUL",
          auras = FREEZE,
          overlays = { { texture = FROZEN_FINGERS, position = "TOP", cw = true } },
          glow = ICE_LANCE },
        { key = "fingers_of_frost", label = "Fingers of Frost", unit = "player", filter = "HELPFUL",
          auras = { 400670 }, sound = true,
          overlays = { { texture = FROZEN_FINGERS, position = "LEFT", pulse = true },
                       { texture = FROZEN_FINGERS, position = "RIGHT", hflip = true, stacks = 2, pulse = true } },
          glow = ICE_LANCE },
        -- Heating Up: SAO's three layers, kept as a composite (run #591: the
        -- owner couldn't tell it from the top layer alone).
        { key = "heating_up", label = "Heating Up", unit = "player", filter = "HELPFUL",
          auras = { 400625 }, sound = true,
          overlays = {
              { texture = HOT_STREAK, position = "LEFT", scale = 0.5, color = { 200, 200, 200 }, level = 1 },
              { texture = HOT_STREAK, position = "RIGHT", hflip = true, scale = 0.5, color = { 200, 200, 200 }, level = 1 },
              { texture = HOT_STREAK, position = "LEFT", stacks = 2, scale = 0.7, color = { 222, 222, 222 }, level = 2 },
              { texture = HOT_STREAK, position = "RIGHT", hflip = true, stacks = 2, scale = 0.7, color = { 222, 222, 222 }, level = 2 },
              { texture = HOT_STREAK, position = "LEFT", stacks = 3, scale = 0.9, level = 3, pulse = true },
              { texture = HOT_STREAK, position = "RIGHT", hflip = true, stacks = 3, scale = 0.9, level = 3, pulse = true },
          } },
        revelation(1248808),
    },

    DRUID = {
        { key = "natures_grace", label = "Nature's Grace", unit = "player", filter = "HELPFUL",
          auras = { 16886 }, sound = true,
          overlays = { { texture = SERENDIPITY, position = "TOP", scale = 0.7, pulse = true } } },
        -- Eclipse: SAO's four layers, lunar side then solar side, each at
        -- that many stacks or more.
        { key = "eclipse", label = "Eclipse", unit = "player", filter = "HELPFUL",
          auras = { 408255, 441260 },
          overlays = {
              { texture = ECLIPSE_MOON, position = "LEFT", stacks = 1, scale = 0.8, outer = -0.16, level = 4, color = { 255, 255, 255, 192 } },
              { texture = ECLIPSE_MOON, position = "LEFT", stacks = 2, scale = 1.1, outer = -0.16, level = 4 },
              { texture = ECLIPSE_MOON, position = "RIGHT", hflip = true, stacks = 3, scale = 0.8, outer = -0.16, level = 2, color = { 255, 255, 255, 192 } },
              { texture = ECLIPSE_MOON, position = "RIGHT", hflip = true, stacks = 4, scale = 1.1, outer = -0.16, level = 2 },
          } },
        -- Omen of Clarity: one texture in every form (SAO's feral art needs a
        -- stance driver; the plan defers it).
        { key = "omen_of_clarity", label = "Omen of Clarity", unit = "player", filter = "HELPFUL",
          auras = { 16870 }, sound = true,
          overlays = { sides({ texture = NATURES_GRACE, outer = 0.25, pulse = true }) } },
        revelation(1323400),
    },

    HUNTER = {
        { key = "rapid_killing", label = "Rapid Killing", unit = "player", filter = "HELPFUL",
          auras = { 415407 }, sound = true,
          overlays = { sides({ texture = RAGING_BLOW, scale = 1.2, color = { 255, 255, 255, 222 }, level = 1, pulse = true }) } },
        revelation(1323410),
    },

    PALADIN = {
        { key = "infusion_of_light", label = "Infusion of Light", unit = "player", filter = "HELPFUL",
          auras = { 53672, 437063 }, sound = true,
          overlays = { sides({ texture = DAYBREAK, pulse = true }) },
          glow = join(HOLY_LIGHT, FLASH_OF_LIGHT) },
        -- Unsealed Wrath: an Echo of each seal, shown at 3 stacks.
        { key = "unsealed_wrath", label = "Unsealed Wrath", unit = "player", filter = "HELPFUL",
          auras = { 1311703, 1311701, 1311704, 1311705, 1328198, 1328206 }, sound = true,
          overlays = { { texture = DENOUNCE, position = "TOP", stacks = 3, pulse = true } } },
        revelation(1323419),
    },

    PRIEST = {
        -- Martyrdom: its buff on Forever is Focused Casting.
        { key = "martyrdom", label = "Martyrdom", unit = "player", filter = "HELPFUL",
          auras = { 27828 },
          overlays = { sides({ texture = WHITE_TIGER, scale = 1.25, color = { 32, 192, 255 }, level = 5 }) } },
        -- Searing Light: SAO's aura for it is Holy Purpose.
        { key = "searing_light", label = "Searing Light", unit = "player", filter = "HELPFUL",
          auras = { 1284536 }, sound = true,
          overlays = { { texture = HAND_OF_LIGHT, position = "TOP", pulse = true } } },
        revelation(1323377),
    },

    ROGUE = {
        { key = "remorseless", label = "Remorseless Attacks", unit = "player", filter = "HELPFUL",
          auras = { 14143 }, sound = true,
          overlays = { sides({ texture = RAGING_BLOW, scale = 1.2, color = { 255, 255, 255, 222 }, level = 1, pulse = true }) } },
        { key = "cutthroat", label = "Cutthroat", unit = "player", filter = "HELPFUL",
          auras = { 462707 }, sound = true,
          overlays = { sides({ texture = WHITE_TIGER, pulse = true }) },
          glow = AMBUSH },
    },

    SHAMAN = {
        { key = "elemental_focus", label = "Elemental Focus", unit = "player", filter = "HELPFUL",
          auras = { 16246 },
          overlays = { sides({ texture = GENERIC_ARC_05, outer = 0.5 }) } },
        -- My Stormstrike on the target (mine only).
        { key = "stormstrike", label = "Stormstrike on the target", unit = "target", filter = "HARMFUL|PLAYER",
          auras = { 27775, 17364 },
          overlays = { { texture = FURY_OF_STORMRAGE, position = "TOP", scale = 1.28, level = 1, color = { 255, 255, 255, 222 } } } },
        -- Maelstrom Weapon: SAO's five layers, greyer below, each at that
        -- many stacks or more. No pulse, so no sound (SAO's).
        { key = "maelstrom_weapon", label = "Maelstrom Weapon", unit = "player", filter = "HELPFUL",
          auras = { 408505 },
          overlays = {
              { texture = 1028136, position = "TOP", stacks = 1, color = { 128, 128, 128 }, level = 1 },
              { texture = 1028137, position = "TOP", stacks = 2, color = { 160, 160, 160 }, level = 2 },
              { texture = 1028138, position = "TOP", stacks = 3, color = { 192, 192, 192 }, level = 3 },
              { texture = 1028139, position = "TOP", stacks = 4, color = { 224, 224, 224 }, level = 4 },
              { texture = 450927, position = "TOP", stacks = 5, level = 5 },
          } },
        revelation(1323418),
    },

    WARLOCK = {
        { key = "eye_of_kilrogg", label = "Eye of Kilrogg", unit = "player", filter = "HELPFUL",
          auras = { 126 },
          overlays = { { texture = GENERIC_TOP_01, position = "TOP", color = { 64, 255, 64 } } } },
        -- Nightfall: its buff is Shadow Trance.
        { key = "nightfall", label = "Nightfall", unit = "player", filter = "HELPFUL",
          auras = { 17941 }, sound = true,
          overlays = { sides({ texture = NIGHTFALL, pulse = true }) },
          glow = SHADOW_BOLT },
        { key = "decimation", label = "Decimation", unit = "player", filter = "HELPFUL",
          auras = { 440873 }, sound = true,
          overlays = { { texture = IMPACT, position = "TOP", scale = 0.8, pulse = true } },
          glow = SOUL_FIRE },
        revelation(1323392),
    },

    -- WARRIOR: SAO's Forever effects are all counters (PR 3).
}
