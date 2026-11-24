-- ProcData.lua: the proc alerts' effects, per class (#115, docs/PLAN-procs.md).
--
-- Ported from SpellActivationOverlay 3.0.0-forever's effect table
-- (classes/mage.lua), Copyright (c) 2022-2026 ennvina, MIT License (see
-- LICENSE, THIRD-PARTY COMPONENTS). Forever's effects only. The glow pairs are
-- GAB's own: SAO's aura effects glow no button on Forever.
--
-- One entry per effect:
-- - key: its setting key (procs.off[key]), never shown;
-- - label: the options page's text;
-- - unit, filter: whose auras, as the engine reads them (HELPFUL on the
--   player, HARMFUL on the target: anyone's freeze counts, as in SAO);
-- - auras: the filter's spell ids, every alias. Never SAO's display
--   stand-in 5276 for the freeze;
-- - overlays: { position = "LEFT" / "RIGHT" / "TOP", hflip, cw (rotated a
--   quarter turn clockwise), stacks (shown at that many or more), scale,
--   color {r, g, b} out of 255, outer (pushed out, in short sides), pulse };
-- - sound: the proc sound on Added and ApplicationsIncreased (SAO plays it for
--   the effects that pulse);
-- - glow: the cast spell ids whose buttons glow, every rank: no API maps a rank
--   to rank 1 on this client (docs/FOREVER-PROBE.md, run #620). Only pairs
--   checked in game ship.
--
-- Textures are client fileDataIDs (SAO's textures/texname.lua).

GlassActionBars = GlassActionBars or {}
local GAB = GlassActionBars

local ARCANE_MISSILES, FROZEN_FINGERS, GENERIC_ARC_05, HOT_STREAK = 449486, 449489, 450921, 449490

-- Ice Lance's ranks on Forever: SkillLineAbility (build 70959) under the
-- mage's Frost line. Rank 1 is 400640, rank 2 1240044 (seen on the bars at
-- level 34). Both glows were checked in game with these (runs #620-#630).
local ICE_LANCE = { 400640, 1240044, 1240045, 1240046, 1240047, 1312002 }

-- A frozen target: SAO's freeze aliases (mage.lua:161-173). Frost Nova
-- (865) was seen to match in game (run #622).
local FREEZE = { 12494, 122, 865, 6131, 10230, 27088, 42917, 3355, 14308, 14309, 33395, 55080,
    44572, 428739, 49203, 83301, 83302, 82691 }

GAB.ProcData = {
    MAGE = {
        { key = "missile_barrage", label = "Missile Barrage", unit = "player", filter = "HELPFUL",
          auras = { 400589 }, sound = true,
          overlays = { { texture = ARCANE_MISSILES, position = "LEFT", outer = 0.32, pulse = true },
                       { texture = ARCANE_MISSILES, position = "RIGHT", hflip = true, outer = 0.32, pulse = true } } },
        { key = "clearcasting", label = "Clearcasting", unit = "player", filter = "HELPFUL",
          auras = { 12536 },
          overlays = { { texture = GENERIC_ARC_05, position = "LEFT", outer = 0.75 },
                       { texture = GENERIC_ARC_05, position = "RIGHT", hflip = true, outer = 0.75 } } },
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
              { texture = HOT_STREAK, position = "LEFT", scale = 0.5, color = { 200, 200, 200 } },
              { texture = HOT_STREAK, position = "RIGHT", hflip = true, scale = 0.5, color = { 200, 200, 200 } },
              { texture = HOT_STREAK, position = "LEFT", stacks = 2, scale = 0.7, color = { 222, 222, 222 } },
              { texture = HOT_STREAK, position = "RIGHT", hflip = true, stacks = 2, scale = 0.7, color = { 222, 222, 222 } },
              { texture = HOT_STREAK, position = "LEFT", stacks = 3, scale = 0.9, pulse = true },
              { texture = HOT_STREAK, position = "RIGHT", hflip = true, stacks = 3, scale = 0.9, pulse = true },
          } },
    },
}
