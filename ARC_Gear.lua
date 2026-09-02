local ARC = assert(_G.ARC, "ARC_Core.lua must load before ARC_Gear.lua")
local I = assert(ARC.Internal, "ARC internal API is unavailable")
local Round = I.Round

-- Gear rules are intentionally kept in this module so server-specific policy
-- (required enchants, minimum item level, spec stat rules) is easy to update.
local EQUIPPED_SLOTS = { 1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17 }
local FIXED_AVERAGE_SLOTS = {
    [1] = true, [2] = true, [3] = true, [5] = true, [6] = true,
    [7] = true, [8] = true, [9] = true, [10] = true, [11] = true,
    [12] = true, [13] = true, [14] = true, [15] = true,
}
local ENCHANT_SLOTS = {
    [3] = true, [5] = true, [7] = true, [8] = true,
    [9] = true, [10] = true, [15] = true, [16] = true, [17] = true,
}
local SLOT_NAMES = {
    [1] = "Head", [2] = "Neck", [3] = "Shoulder", [5] = "Chest",
    [6] = "Waist", [7] = "Legs", [8] = "Feet", [9] = "Wrist",
    [10] = "Hands", [11] = "Ring 1", [12] = "Ring 2",
    [13] = "Trinket 1", [14] = "Trinket 2", [15] = "Back",
    [16] = "Main hand", [17] = "Off hand",
}

-- MoP specialization IDs and their expected primary attribute.
local SPEC_PRIMARY = {
    [250] = "STR", [251] = "STR", [252] = "STR",
    [102] = "INT", [103] = "AGI", [104] = "AGI", [105] = "INT",
    [253] = "AGI", [254] = "AGI", [255] = "AGI",
    [62] = "INT", [63] = "INT", [64] = "INT",
    [268] = "AGI", [269] = "AGI", [270] = "INT",
    [65] = "INT", [66] = "STR", [70] = "STR",
    [256] = "INT", [257] = "INT", [258] = "INT",
    [259] = "AGI", [260] = "AGI", [261] = "AGI",
    [262] = "INT", [263] = "AGI", [264] = "INT",
    [265] = "INT", [266] = "INT", [267] = "INT",
    [71] = "STR", [72] = "STR", [73] = "STR",
}

-- Compact MoP catalog adapted from WoWSims (MIT); see docs/GEAR_RULES.md.
--[[
MIT License

Copyright (c) 2022 wowsims team

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
]]
-- Snapshot: 970d5cc4c8a3c7db0559020b481aaceda5c523f2. IDs are items for gems, effects for enchants.
-- These tables describe stats/tier, not a best-in-slot simulator.
local GEM_RULE_DATA = {
    [76570] = { name = "Perfect Rigid Lapis Lazuli", quality = 3, stats = { HIT = 320 } },
    [76571] = { name = "Perfect Stormy Lapis Lazuli", quality = 3, stats = { PVP = 160 } },
    [76572] = { name = "Perfect Sparkling Lapis Lazuli", quality = 3, stats = { SPI = 320 } },
    [76573] = { name = "Perfect Solid Lapis Lazuli", quality = 3, stats = { STA = 240 } },
    [76574] = { name = "Perfect Misty Alexandrite", quality = 3, stats = { CRIT = 160, SPI = 160 } },
    [76575] = { name = "Perfect Piercing Alexandrite", quality = 3, stats = { CRIT = 160, HIT = 160 } },
    [76576] = { name = "Perfect Lightning Alexandrite", quality = 3, stats = { HASTE = 160, HIT = 160 } },
    [76577] = { name = "Perfect Sensei's Alexandrite", quality = 3, stats = { HIT = 160, MASTERY = 160 } },
    [76578] = { name = "Perfect Effulgent Alexandrite", quality = 3, stats = { MASTERY = 160, PVP = 80 } },
    [76579] = { name = "Perfect Zen Alexandrite", quality = 3, stats = { MASTERY = 160, SPI = 160 } },
    [76580] = { name = "Perfect Balanced Alexandrite", quality = 3, stats = { HIT = 160, RESIL = 80 } },
    [76581] = { name = "Perfect Vivid Alexandrite", quality = 3, stats = { PVP = 80, RESIL = 80 } },
    [76582] = { name = "Perfect Turbid Alexandrite", quality = 3, stats = { RESIL = 80, SPI = 160 } },
    [76583] = { name = "Perfect Radiant Alexandrite", quality = 3, stats = { CRIT = 160, PVP = 80 } },
    [76584] = { name = "Perfect Shattered Alexandrite", quality = 3, stats = { HASTE = 160, PVP = 80 } },
    [76585] = { name = "Perfect Energized Alexandrite", quality = 3, stats = { HASTE = 160, SPI = 160 } },
    [76586] = { name = "Perfect Jagged Alexandrite", quality = 3, stats = { CRIT = 160, STA = 120 } },
    [76587] = { name = "Perfect Regal Alexandrite", quality = 3, stats = { DODGE = 160, STA = 120 } },
    [76588] = { name = "Perfect Forceful Alexandrite", quality = 3, stats = { HASTE = 160, STA = 120 } },
    [76589] = { name = "Perfect Confounded Alexandrite", quality = 3, stats = { HIT = 160, STA = 120 } },
    [76590] = { name = "Perfect Puissant Alexandrite", quality = 3, stats = { MASTERY = 160, STA = 120 } },
    [76591] = { name = "Perfect Steady Alexandrite", quality = 3, stats = { RESIL = 80, STA = 120 } },
    [76592] = { name = "Perfect Deadly Tiger Opal", quality = 3, stats = { AGI = 80, CRIT = 160 } },
    [76593] = { name = "Perfect Crafty Tiger Opal", quality = 3, stats = { CRIT = 160, EXP = 160 } },
    [76594] = { name = "Perfect Potent Tiger Opal", quality = 3, stats = { CRIT = 160, INT = 80 } },
    [76595] = { name = "Perfect Inscribed Tiger Opal", quality = 3, stats = { CRIT = 160, STR = 80 } },
    [76596] = { name = "Perfect Polished Tiger Opal", quality = 3, stats = { AGI = 80, DODGE = 160 } },
    [76597] = { name = "Perfect Resolute Tiger Opal", quality = 3, stats = { DODGE = 160, EXP = 160 } },
    [76598] = { name = "Perfect Stalwart Tiger Opal", quality = 3, stats = { DODGE = 160, PARRY = 160 } },
    [76599] = { name = "Perfect Champion's Tiger Opal", quality = 3, stats = { DODGE = 160, STR = 80 } },
    [76600] = { name = "Perfect Deft Tiger Opal", quality = 3, stats = { AGI = 80, HASTE = 160 } },
    [76601] = { name = "Perfect Wicked Tiger Opal", quality = 3, stats = { EXP = 160, HASTE = 160 } },
    [76602] = { name = "Perfect Reckless Tiger Opal", quality = 3, stats = { HASTE = 160, INT = 80 } },
    [76603] = { name = "Perfect Fierce Tiger Opal", quality = 3, stats = { HASTE = 160, STR = 80 } },
    [76604] = { name = "Perfect Adept Tiger Opal", quality = 3, stats = { AGI = 80, MASTERY = 160 } },
    [76605] = { name = "Perfect Keen Tiger Opal", quality = 3, stats = { EXP = 160, MASTERY = 160 } },
    [76606] = { name = "Perfect Artful Tiger Opal", quality = 3, stats = { INT = 80, MASTERY = 160 } },
    [76607] = { name = "Perfect Fine Tiger Opal", quality = 3, stats = { MASTERY = 160, PARRY = 160 } },
    [76608] = { name = "Perfect Skillful Tiger Opal", quality = 3, stats = { MASTERY = 160, STR = 80 } },
    [76609] = { name = "Perfect Lucent Tiger Opal", quality = 3, stats = { AGI = 80, RESIL = 80 } },
    [76610] = { name = "Perfect Tenuous Tiger Opal", quality = 3, stats = { EXP = 160, RESIL = 80 } },
    [76611] = { name = "Perfect Willful Tiger Opal", quality = 3, stats = { INT = 80, RESIL = 80 } },
    [76612] = { name = "Perfect Splendid Tiger Opal", quality = 3, stats = { PARRY = 160, RESIL = 80 } },
    [76613] = { name = "Perfect Resplendent Tiger Opal", quality = 3, stats = { RESIL = 80, STR = 80 } },
    [76614] = { name = "Perfect Glinting Roguestone", quality = 3, stats = { AGI = 80, HIT = 160 } },
    [76615] = { name = "Perfect Accurate Roguestone", quality = 3, stats = { EXP = 160, HIT = 160 } },
    [76616] = { name = "Perfect Veiled Roguestone", quality = 3, stats = { HIT = 160, INT = 80 } },
    [76617] = { name = "Perfect Retaliating Roguestone", quality = 3, stats = { HIT = 160, PARRY = 160 } },
    [76618] = { name = "Perfect Etched Roguestone", quality = 3, stats = { HIT = 160, STR = 80 } },
    [76619] = { name = "Perfect Mysterious Roguestone", quality = 3, stats = { INT = 80, PVP = 80 } },
    [76620] = { name = "Perfect Purified Roguestone", quality = 3, stats = { INT = 80, SPI = 160 } },
    [76621] = { name = "Perfect Shifting Roguestone", quality = 3, stats = { AGI = 80, STA = 120 } },
    [76622] = { name = "Perfect Guardian's Roguestone", quality = 3, stats = { EXP = 160, STA = 120 } },
    [76623] = { name = "Perfect Timeless Roguestone", quality = 3, stats = { INT = 80, STA = 120 } },
    [76624] = { name = "Perfect Defender's Roguestone", quality = 3, stats = { PARRY = 160, STA = 120 } },
    [76625] = { name = "Perfect Sovereign Roguestone", quality = 3, stats = { STA = 120, STR = 80 } },
    [76626] = { name = "Perfect Delicate Pandarian Garnet", quality = 3, stats = { AGI = 160 } },
    [76627] = { name = "Perfect Precise Pandarian Garnet", quality = 3, stats = { EXP = 320 } },
    [76628] = { name = "Perfect Brilliant Pandarian Garnet", quality = 3, stats = { INT = 160 } },
    [76629] = { name = "Perfect Flashing Pandarian Garnet", quality = 3, stats = { PARRY = 320 } },
    [76630] = { name = "Perfect Bold Pandarian Garnet", quality = 3, stats = { STR = 160 } },
    [76631] = { name = "Perfect Smooth Sunstone", quality = 3, stats = { CRIT = 320 } },
    [76632] = { name = "Perfect Subtle Sunstone", quality = 3, stats = { DODGE = 320 } },
    [76633] = { name = "Perfect Quick Sunstone", quality = 3, stats = { HASTE = 320 } },
    [76634] = { name = "Perfect Fractured Sunstone", quality = 3, stats = { MASTERY = 320 } },
    [76635] = { name = "Perfect Mystic Sunstone", quality = 3, stats = { RESIL = 160 } },
    [76636] = { name = "Rigid River's Heart", quality = 3, stats = { HIT = 320 } },
    [76637] = { name = "Stormy River's Heart", quality = 3, stats = { PVP = 160 } },
    [76638] = { name = "Sparkling River's Heart", quality = 3, stats = { SPI = 320 } },
    [76639] = { name = "Solid River's Heart", quality = 3, stats = { STA = 240 } },
    [76640] = { name = "Misty Wild Jade", quality = 3, stats = { CRIT = 160, SPI = 160 } },
    [76641] = { name = "Piercing Wild Jade", quality = 3, stats = { CRIT = 160, HIT = 160 } },
    [76642] = { name = "Lightning Wild Jade", quality = 3, stats = { HASTE = 160, HIT = 160 } },
    [76643] = { name = "Sensei's Wild Jade", quality = 3, stats = { HIT = 160, MASTERY = 160 } },
    [76644] = { name = "Effulgent Wild Jade", quality = 3, stats = { MASTERY = 160, PVP = 80 } },
    [76645] = { name = "Zen Wild Jade", quality = 3, stats = { MASTERY = 160, SPI = 160 } },
    [76646] = { name = "Balanced Wild Jade", quality = 3, stats = { HIT = 160, RESIL = 80 } },
    [76647] = { name = "Vivid Wild Jade", quality = 3, stats = { PVP = 80, RESIL = 80 } },
    [76648] = { name = "Turbid Wild Jade", quality = 3, stats = { RESIL = 80, SPI = 160 } },
    [76649] = { name = "Radiant Wild Jade", quality = 3, stats = { CRIT = 160, PVP = 80 } },
    [76650] = { name = "Shattered Wild Jade", quality = 3, stats = { HASTE = 160, PVP = 80 } },
    [76651] = { name = "Energized Wild Jade", quality = 3, stats = { HASTE = 160, SPI = 160 } },
    [76652] = { name = "Jagged Wild Jade", quality = 3, stats = { CRIT = 160, STA = 120 } },
    [76653] = { name = "Regal Wild Jade", quality = 3, stats = { DODGE = 160, STA = 120 } },
    [76654] = { name = "Forceful Wild Jade", quality = 3, stats = { HASTE = 160, STA = 120 } },
    [76656] = { name = "Puissant Wild Jade", quality = 3, stats = { MASTERY = 160, STA = 120 } },
    [76657] = { name = "Steady Wild Jade", quality = 3, stats = { RESIL = 80, STA = 120 } },
    [76658] = { name = "Deadly Vermilion Onyx", quality = 3, stats = { AGI = 80, CRIT = 160 } },
    [76659] = { name = "Crafty Vermilion Onyx", quality = 3, stats = { CRIT = 160, EXP = 160 } },
    [76660] = { name = "Potent Vermilion Onyx", quality = 3, stats = { CRIT = 160, INT = 80 } },
    [76661] = { name = "Inscribed Vermilion Onyx", quality = 3, stats = { CRIT = 160, STR = 80 } },
    [76662] = { name = "Polished Vermilion Onyx", quality = 3, stats = { AGI = 80, DODGE = 160 } },
    [76663] = { name = "Resolute Vermilion Onyx", quality = 3, stats = { DODGE = 160, EXP = 160 } },
    [76664] = { name = "Stalwart Vermilion Onyx", quality = 3, stats = { DODGE = 160, PARRY = 160 } },
    [76665] = { name = "Champion's Vermilion Onyx", quality = 3, stats = { DODGE = 160, STR = 80 } },
    [76666] = { name = "Deft Vermilion Onyx", quality = 3, stats = { AGI = 80, HASTE = 160 } },
    [76667] = { name = "Wicked Vermilion Onyx", quality = 3, stats = { EXP = 160, HASTE = 160 } },
    [76668] = { name = "Reckless Vermilion Onyx", quality = 3, stats = { HASTE = 160, INT = 80 } },
    [76669] = { name = "Fierce Vermilion Onyx", quality = 3, stats = { HASTE = 160, STR = 80 } },
    [76670] = { name = "Adept Vermilion Onyx", quality = 3, stats = { AGI = 80, MASTERY = 160 } },
    [76671] = { name = "Keen Vermilion Onyx", quality = 3, stats = { EXP = 160, MASTERY = 160 } },
    [76672] = { name = "Artful Vermilion Onyx", quality = 3, stats = { INT = 80, MASTERY = 160 } },
    [76673] = { name = "Fine Vermilion Onyx", quality = 3, stats = { MASTERY = 160, PARRY = 160 } },
    [76674] = { name = "Skillful Vermilion Onyx", quality = 3, stats = { MASTERY = 160, STR = 80 } },
    [76675] = { name = "Lucent Vermilion Onyx", quality = 3, stats = { AGI = 80, RESIL = 80 } },
    [76676] = { name = "Tenuous Vermilion Onyx", quality = 3, stats = { EXP = 160, RESIL = 80 } },
    [76677] = { name = "Willful Vermilion Onyx", quality = 3, stats = { INT = 80, RESIL = 80 } },
    [76678] = { name = "Splendid Vermilion Onyx", quality = 3, stats = { PARRY = 160, RESIL = 80 } },
    [76679] = { name = "Resplendent Vermilion Onyx", quality = 3, stats = { RESIL = 80, STR = 80 } },
    [76680] = { name = "Glinting Imperial Amethyst", quality = 3, stats = { AGI = 80, HIT = 160 } },
    [76681] = { name = "Accurate Imperial Amethyst", quality = 3, stats = { EXP = 160, HIT = 160 } },
    [76682] = { name = "Veiled Imperial Amethyst", quality = 3, stats = { HIT = 160, INT = 80 } },
    [76683] = { name = "Retaliating Imperial Amethyst", quality = 3, stats = { HIT = 160, PARRY = 160 } },
    [76684] = { name = "Etched Imperial Amethyst", quality = 3, stats = { HIT = 160, STR = 80 } },
    [76685] = { name = "Mysterious Imperial Amethyst", quality = 3, stats = { INT = 80, PVP = 80 } },
    [76686] = { name = "Purified Imperial Amethyst", quality = 3, stats = { INT = 80, SPI = 160 } },
    [76687] = { name = "Shifting Imperial Amethyst", quality = 3, stats = { AGI = 80, STA = 120 } },
    [76688] = { name = "Guardian's Imperial Amethyst", quality = 3, stats = { EXP = 160, STA = 120 } },
    [76689] = { name = "Timeless Imperial Amethyst", quality = 3, stats = { INT = 80, STA = 120 } },
    [76690] = { name = "Defender's Imperial Amethyst", quality = 3, stats = { PARRY = 160, STA = 120 } },
    [76691] = { name = "Sovereign Imperial Amethyst", quality = 3, stats = { STA = 120, STR = 80 } },
    [76692] = { name = "Delicate Primordial Ruby", quality = 3, stats = { AGI = 160 } },
    [76693] = { name = "Precise Primordial Ruby", quality = 3, stats = { EXP = 320 } },
    [76694] = { name = "Brilliant Primordial Ruby", quality = 3, stats = { INT = 160 } },
    [76695] = { name = "Flashing Primordial Ruby", quality = 3, stats = { PARRY = 320 } },
    [76696] = { name = "Bold Primordial Ruby", quality = 3, stats = { STR = 160 } },
    [76697] = { name = "Smooth Sun's Radiance", quality = 3, stats = { CRIT = 320 } },
    [76698] = { name = "Subtle Sun's Radiance", quality = 3, stats = { DODGE = 320 } },
    [76699] = { name = "Quick Sun's Radiance", quality = 3, stats = { HASTE = 320 } },
    [76700] = { name = "Fractured Sun's Radiance", quality = 3, stats = { MASTERY = 320 } },
    [76701] = { name = "Mystic Sun's Radiance", quality = 3, stats = { RESIL = 160 } },
    [76879] = { name = "Ember Primal Diamond", quality = 3, stats = { INT = 216 } },
    [76884] = { name = "Agile Primal Diamond", quality = 3, stats = { AGI = 216 } },
    [76885] = { name = "Burning Primal Diamond", quality = 3, stats = { INT = 216 } },
    [76886] = { name = "Reverberating Primal Diamond", quality = 3, stats = { STR = 216 } },
    [76887] = { name = "Fleet Primal Diamond", quality = 3, stats = { MASTERY = 432 } },
    [76888] = { name = "Revitalizing Primal Diamond", quality = 3, stats = { SPI = 432 } },
    [76890] = { name = "Destructive Primal Diamond", quality = 3, stats = { CRIT = 432 }, pvp = "spell reflection" },
    [76891] = { name = "Powerful Primal Diamond", quality = 3, stats = { STA = 324 }, pvp = "stun reduction" },
    [76892] = { name = "Enigmatic Primal Diamond", quality = 3, stats = { CRIT = 432 }, pvp = "snare/root reduction" },
    [76893] = { name = "Impassive Primal Diamond", quality = 3, stats = { CRIT = 432 }, pvp = "fear reduction" },
    [76894] = { name = "Forlorn Primal Diamond", quality = 3, stats = { INT = 216 }, pvp = "silence reduction" },
    [76895] = { name = "Austere Primal Diamond", quality = 3, stats = { STA = 324 } },
    [76896] = { name = "Eternal Primal Diamond", quality = 3, stats = { DODGE = 432 } },
    [76897] = { name = "Effulgent Primal Diamond", quality = 3, stats = { STA = 324 } },
    [77540] = { name = "Subtle Tinker's Gear", quality = 3, stats = { DODGE = 600 } },
    [77541] = { name = "Smooth Tinker's Gear", quality = 3, stats = { CRIT = 600 } },
    [77542] = { name = "Quick Tinker's Gear", quality = 3, stats = { HASTE = 600 } },
    [77543] = { name = "Precise Tinker's Gear", quality = 3, stats = { EXP = 600 } },
    [77544] = { name = "Flashing Tinker's Gear", quality = 3, stats = { PARRY = 600 } },
    [77545] = { name = "Rigid Tinker's Gear", quality = 3, stats = { HIT = 600 } },
    [77546] = { name = "Sparkling Tinker's Gear", quality = 3, stats = { SPI = 600 } },
    [77547] = { name = "Fractured Tinker's Gear", quality = 3, stats = { MASTERY = 600 } },
    [83141] = { name = "Bold Serpent's Eye", quality = 4, stats = { STR = 320 } },
    [83142] = { name = "Quick Serpent's Eye", quality = 4, stats = { HASTE = 480 } },
    [83143] = { name = "Fractured Serpent's Eye", quality = 4, stats = { MASTERY = 480 } },
    [83144] = { name = "Rigid Serpent's Eye", quality = 4, stats = { HIT = 480 } },
    [83145] = { name = "Subtle Serpent's Eye", quality = 4, stats = { DODGE = 480 } },
    [83146] = { name = "Smooth Serpent's Eye", quality = 4, stats = { CRIT = 480 } },
    [83147] = { name = "Precise Serpent's Eye", quality = 4, stats = { EXP = 480 } },
    [83148] = { name = "Solid Serpent's Eye", quality = 4, stats = { STA = 480 } },
    [83149] = { name = "Sparkling Serpent's Eye", quality = 4, stats = { SPI = 480 } },
    [83150] = { name = "Brilliant Serpent's Eye", quality = 4, stats = { INT = 320 } },
    [83151] = { name = "Delicate Serpent's Eye", quality = 4, stats = { AGI = 320 } },
    [83152] = { name = "Flashing Serpent's Eye", quality = 4, stats = { PARRY = 480 } },
    [89674] = { name = "Tense Imperial Amethyst", quality = 3, stats = { PVP = 80, STR = 80 } },
    [89676] = { name = "Perfect Tense Roguestone", quality = 3, stats = { PVP = 80, STR = 80 } },
    [89679] = { name = "Perfect Assassin's Roguestone", quality = 3, stats = { AGI = 80, PVP = 80 } },
    [89680] = { name = "Assassin's Imperial Amethyst", quality = 3, stats = { AGI = 80, PVP = 80 } },
    [89873] = { name = "Crystallized Dread", quality = 5, stats = { AGI = 500 } },
    [89881] = { name = "Crystallized Terror", quality = 5, stats = { STR = 500 } },
    [89882] = { name = "Crystallized Horror", quality = 5, stats = { INT = 500 } },
    [93404] = { name = "Resplendent Serpent's Eye", quality = 4, stats = { RESIL = 160, STR = 160 } },
    [93405] = { name = "Lucent Serpent's Eye", quality = 4, stats = { AGI = 160, RESIL = 160 } },
    [93406] = { name = "Willful Serpent's Eye", quality = 4, stats = { INT = 160, RESIL = 160 } },
    [93408] = { name = "Tense Serpent's Eye", quality = 4, stats = { PVP = 160, STR = 160 } },
    [93409] = { name = "Assassin's Serpent's Eye", quality = 4, stats = { AGI = 160, PVP = 160 } },
    [93410] = { name = "Mysterious Serpent's Eye", quality = 4, stats = { INT = 160, PVP = 160 } },
    [93705] = { name = "Nimble Wild Jade", quality = 3, stats = { DODGE = 160, HIT = 160 } },
    [93707] = { name = "Perfect Nimble Alexandrite", quality = 3, stats = { DODGE = 160, HIT = 160 } },
    [95344] = { name = "Indomitable Primal Diamond", quality = 5, stats = { STA = 324 }, role = "TANK" },
    [95345] = { name = "Courageous Primal Diamond", quality = 5, stats = { INT = 324 }, role = "HEALER" },
    [95346] = { name = "Capacitive Primal Diamond", quality = 5, stats = { CRIT = 324 }, primary = "PHYSICAL" },
    [95347] = { name = "Sinister Primal Diamond", quality = 5, stats = { CRIT = 324 }, primary = "INT" },
    [95348] = { name = "Tyrannical Primal Diamond", quality = 4, stats = { PVP = 665, RESIL = 775 } },
    [98056] = { name = "Crystallized Horror", quality = 5, stats = { INT = 500 } },
}

local ENCHANT_RULE_DATA = {
    [36] = { name = "Enchant: Fiery Blaze", stats = {  }, top = false, slot = 16, kind = "weapon" },
    [37] = { name = "Weapon Chain", stats = {  }, top = false, slot = 16, kind = "weapon" },
    [43] = { name = "Iron Shield Spike", stats = {  }, top = false },
    [44] = { name = "Enchant Chest - Minor Absorption", stats = {  }, top = false, slot = 5 },
    [463] = { name = "Mithril Shield Spike", stats = {  }, top = false },
    [464] = { name = "Mithril Spurs", stats = {  }, top = false, slot = 8 },
    [803] = { name = "Enchant Weapon - Fiery Weapon", stats = {  }, top = false, slot = 16, kind = "weapon" },
    [844] = { name = "Enchant Gloves - Mining", stats = {  }, top = false, slot = 10 },
    [845] = { name = "Enchant Gloves - Herbalism", stats = {  }, top = false, slot = 10 },
    [846] = { name = "Eternium Fishing Line", stats = {  }, top = false, slot = 16, kind = "weapon" },
    [865] = { name = "Enchant Gloves - Skinning", stats = {  }, top = false, slot = 10 },
    [906] = { name = "Enchant Gloves - Advanced Mining", stats = {  }, top = false, slot = 10 },
    [909] = { name = "Enchant Gloves - Advanced Herbalism", stats = {  }, top = false, slot = 10 },
    [910] = { name = "Enchant Cloak - Stealth", stats = { AGI = 8, DODGE = 8 }, top = false, slot = 15 },
    [911] = { name = "Enchant Boots - Minor Speed", stats = {  }, top = false, slot = 8 },
    [912] = { name = "Enchant Weapon - Demonslaying", stats = {  }, top = false, slot = 16, kind = "weapon" },
    [926] = { name = "Enchant Shield - Frost Resistance", stats = {  }, top = false, slot = 16, kind = "shield" },
    [930] = { name = "Enchant Gloves - Riding Skill", stats = {  }, top = false, slot = 10 },
    [1593] = { name = "Enchant Bracer - Assault", stats = { AP = 24, RAP = 24 }, top = false, slot = 9 },
    [1704] = { name = "Thorium Shield Spike", stats = {  }, top = false },
    [1894] = { name = "Enchant Weapon - Icy Chill", stats = {  }, top = false, slot = 16, kind = "weapon" },
    [1898] = { name = "Enchant Weapon - Lifestealing", stats = {  }, top = false, slot = 16, kind = "weapon" },
    [1899] = { name = "Enchant Weapon - Unholy Weapon", stats = {  }, top = false, slot = 16, kind = "weapon" },
    [1900] = { name = "Enchant Weapon - Crusader", stats = {  }, top = false, slot = 16, kind = "weapon" },
    [2564] = { name = "Enchant Gloves - Superior Agility", stats = { AGI = 15 }, top = false, slot = 10 },
    [2567] = { name = "Enchant Weapon - Mighty Spirit", stats = { SPI = 20 }, top = false, slot = 16, kind = "weapon" },
    [2603] = { name = "Enchant Gloves - Fishing", stats = {  }, top = false, slot = 10 },
    [2613] = { name = "Enchant Gloves - Threat", stats = {  }, top = false, slot = 10 },
    [2619] = { name = "Enchant Cloak - Greater Fire Resistance", stats = {  }, top = false, slot = 15 },
    [2620] = { name = "Enchant Cloak - Greater Nature Resistance", stats = {  }, top = false, slot = 15 },
    [2621] = { name = "Enchant Cloak - Subtlety", stats = {  }, top = false, slot = 15 },
    [2673] = { name = "Enchant Weapon - Mongoose", stats = {  }, top = false, slot = 16, kind = "weapon" },
    [2674] = { name = "Enchant Weapon - Spellsurge", stats = {  }, top = false, slot = 16, kind = "weapon" },
    [2675] = { name = "Enchant Weapon - Battlemaster", stats = {  }, top = false, slot = 16, kind = "weapon" },
    [3228] = { name = "Enchant Bracer - Template", stats = { AP = 34, RAP = 34 }, top = false, slot = 9 },
    [3229] = { name = "Enchant Shield - Resistance", stats = { RESIL = 12 }, top = false, slot = 16, kind = "shield", pvp = true },
    [3238] = { name = "Enchant Gloves - Gatherer", stats = {  }, top = false, slot = 10 },
    [3239] = { name = "Enchant Weapon - Icebreaker", stats = {  }, top = false, slot = 16, kind = "weapon" },
    [3241] = { name = "Enchant Weapon - Lifeward", stats = {  }, top = false, slot = 16, kind = "weapon" },
    [3251] = { name = "Enchant Weapon - Giant Slayer", stats = {  }, top = false, slot = 16, kind = "weapon" },
    [3269] = { name = "Truesilver Fishing Line", stats = {  }, top = false, slot = 16, kind = "weapon" },
    [3273] = { name = "Enchant Weapon - Deathfrost", stats = {  }, top = false, slot = 16, kind = "weapon" },
    [3289] = { name = "Riding Crop", stats = {  }, top = false, slot = 16, kind = "weapon" },
    [3315] = { name = "Carrot on a Stick", stats = {  }, top = false, slot = 16, kind = "weapon" },
    [3365] = { name = "Rune of Swordshattering", stats = {  }, top = true, slot = 16, kind = "weapon", class = "DEATHKNIGHT" },
    [3366] = { name = "Rune of Lichbane", stats = {  }, top = true, slot = 16, kind = "weapon", class = "DEATHKNIGHT" },
    [3367] = { name = "Rune of Spellshattering", stats = {  }, top = true, slot = 16, kind = "weapon", class = "DEATHKNIGHT" },
    [3368] = { name = "Rune of the Fallen Crusader", stats = {  }, top = true, slot = 16, kind = "weapon", class = "DEATHKNIGHT" },
    [3369] = { name = "Rune of Cinderglacier", stats = {  }, top = true, slot = 16, kind = "weapon", class = "DEATHKNIGHT" },
    [3370] = { name = "Rune of Razorice", stats = {  }, top = true, slot = 16, kind = "weapon", class = "DEATHKNIGHT" },
    [3594] = { name = "Rune of Swordbreaking", stats = {  }, top = true, slot = 16, kind = "weapon", class = "DEATHKNIGHT" },
    [3595] = { name = "Rune of Spellbreaking", stats = {  }, top = true, slot = 16, kind = "weapon", class = "DEATHKNIGHT" },
    [3599] = { name = "EMP Generator", stats = {  }, top = false, slot = 6 },
    [3601] = { name = "Frag Belt", stats = {  }, top = false, slot = 6 },
    [3603] = { name = "Hand-Mounted Pyro Rocket", stats = {  }, top = false, slot = 10 },
    [3604] = { name = "Hyperspeed Accelerators", stats = {  }, top = false, slot = 10 },
    [3605] = { name = "Flexweave Underlay", stats = {  }, top = false, slot = 15 },
    [3722] = { name = "Lightweave Embroidery (Rank 1)", stats = {  }, top = false, slot = 15 },
    [3728] = { name = "Darkglow Embroidery (Rank 1)", stats = {  }, top = false, slot = 15 },
    [3730] = { name = "Swordguard Embroidery (Rank 1)", stats = {  }, top = false, slot = 15 },
    [3748] = { name = "Titanium Shield Spike", stats = {  }, top = false },
    [3789] = { name = "Enchant Weapon - Berserking", stats = {  }, top = false, slot = 16, kind = "weapon" },
    [3790] = { name = "Enchant Weapon - Black Magic", stats = {  }, top = false, slot = 16, kind = "weapon" },
    [3847] = { name = "Rune of the Stoneskin Gargoyle", stats = {  }, top = true, slot = 16, kind = "weapon", class = "DEATHKNIGHT" },
    [3860] = { name = "Reticulated Armor Webbing", stats = {  }, top = false, slot = 10 },
    [3869] = { name = "Enchant Weapon - Blade Ward", stats = {  }, top = false, slot = 16, kind = "weapon" },
    [3870] = { name = "Enchant Weapon - Blood Draining", stats = {  }, top = false, slot = 16, kind = "weapon" },
    [3883] = { name = "Rune of the Nerubian Carapace", stats = {  }, top = true, slot = 16, kind = "weapon", class = "DEATHKNIGHT" },
    [4061] = { name = "Enchant Gloves - Mastery", stats = { MASTERY = 50 }, top = false, slot = 10 },
    [4062] = { name = "Enchant Boots - Earthen Vitality", stats = { STA = 30 }, top = false, slot = 8 },
    [4063] = { name = "Enchant Chest - Mighty Stats", stats = { AGI = 15, INT = 15, SPI = 15, STA = 15, STR = 15 }, top = false, slot = 5 },
    [4064] = { name = "Enchant Cloak - Lesser Power", stats = { PVP = 56 }, top = false, slot = 15, pvp = true },
    [4065] = { name = "Enchant Bracer - Speed", stats = { HASTE = 50 }, top = false, slot = 9 },
    [4066] = { name = "Enchant Weapon - Mending", stats = {  }, top = false, slot = 16, kind = "weapon" },
    [4067] = { name = "Enchant Weapon - Avalanche", stats = {  }, top = false, slot = 16, kind = "weapon" },
    [4068] = { name = "Enchant Gloves - Haste", stats = { HASTE = 50 }, top = false, slot = 10 },
    [4069] = { name = "Enchant Boots - Haste", stats = { HASTE = 50 }, top = false, slot = 8 },
    [4070] = { name = "Enchant Chest - Stamina", stats = { STA = 55 }, top = false, slot = 5 },
    [4071] = { name = "Enchant Bracer - Critical Strike", stats = { CRIT = 50 }, top = false, slot = 9 },
    [4072] = { name = "Enchant Cloak - Intellect", stats = { INT = 30 }, top = false, slot = 15 },
    [4073] = { name = "Enchant Shield - Protection", stats = { STA = 16 }, top = false, slot = 16, kind = "shield" },
    [4074] = { name = "Enchant Weapon - Elemental Slayer", stats = {  }, top = false, slot = 16, kind = "weapon" },
    [4075] = { name = "Enchant Gloves - Exceptional Strength", stats = { STR = 35 }, top = false, slot = 10 },
    [4076] = { name = "Enchant Boots - Major Agility", stats = { AGI = 35 }, top = false, slot = 8 },
    [4077] = { name = "Enchant Chest - Mighty Resilience", stats = { RESIL = 40 }, top = false, slot = 5, pvp = true },
    [4078] = { name = "Enchant Ring - Strength", stats = { STR = 40 }, top = false, slot = 11 },
    [4079] = { name = "Enchant Ring - Agility", stats = { AGI = 40 }, top = false, slot = 11 },
    [4080] = { name = "Enchant Ring - Intellect", stats = { INT = 40 }, top = false, slot = 11 },
    [4081] = { name = "Enchant Ring - Stamina", stats = { STA = 60 }, top = false, slot = 11 },
    [4082] = { name = "Enchant Gloves - Greater Expertise", stats = { EXP = 50 }, top = false, slot = 10 },
    [4083] = { name = "Enchant Weapon - Hurricane", stats = {  }, top = false, slot = 16, kind = "weapon" },
    [4084] = { name = "Enchant Weapon - Heartsong", stats = {  }, top = false, slot = 16, kind = "weapon" },
    [4085] = { name = "Enchant Shield - Mastery", stats = { MASTERY = 50 }, top = false, slot = 16, kind = "shield" },
    [4086] = { name = "Enchant Bracer - Superior Dodge", stats = { DODGE = 50 }, top = false, slot = 9 },
    [4087] = { name = "Enchant Cloak - Critical Strike", stats = { CRIT = 50 }, top = false, slot = 15 },
    [4088] = { name = "Enchant Chest - Exceptional Spirit", stats = { SPI = 40 }, top = false, slot = 5 },
    [4089] = { name = "Enchant Bracer - Precision", stats = { HIT = 50 }, top = false, slot = 9 },
    [4090] = { name = "Enchant Cloak - Protection", stats = { STA = 30 }, top = false, slot = 15 },
    [4091] = { name = "Enchant Off-Hand - Superior Intellect", stats = { INT = 40 }, top = false, slot = 16, kind = "offhand" },
    [4092] = { name = "Enchant Boots - Precision", stats = { HIT = 50 }, top = false, slot = 8 },
    [4093] = { name = "Enchant Bracer - Exceptional Spirit", stats = { SPI = 50 }, top = false, slot = 9 },
    [4094] = { name = "Enchant Boots - Mastery", stats = { MASTERY = 50 }, top = false, slot = 8 },
    [4095] = { name = "Enchant Bracer - Greater Expertise", stats = { EXP = 50 }, top = false, slot = 9 },
    [4096] = { name = "Enchant Cloak - Greater Intellect", stats = { INT = 50 }, top = false, slot = 15 },
    [4097] = { name = "Enchant Weapon - Power Torrent", stats = {  }, top = false, slot = 16, kind = "weapon" },
    [4098] = { name = "Enchant Weapon - Windwalk", stats = {  }, top = false, slot = 16, kind = "weapon" },
    [4099] = { name = "Enchant Weapon - Landslide", stats = {  }, top = false, slot = 16, kind = "weapon" },
    [4100] = { name = "Enchant Cloak - Greater Critical Strike", stats = { CRIT = 65 }, top = false, slot = 15 },
    [4101] = { name = "Enchant Bracer - Greater Critical Strike", stats = { CRIT = 65 }, top = false, slot = 9 },
    [4102] = { name = "Enchant Chest - Peerless Stats", stats = { AGI = 20, INT = 20, SPI = 20, STA = 20, STR = 20 }, top = false, slot = 5 },
    [4103] = { name = "Enchant Chest - Greater Stamina", stats = { STA = 75 }, top = false, slot = 5 },
    [4104] = { name = "Enchant Boots - Lavawalker", stats = { MASTERY = 35 }, top = false, slot = 8 },
    [4105] = { name = "Enchant Boots - Assassin's Step", stats = { AGI = 25 }, top = false, slot = 8 },
    [4106] = { name = "Enchant Gloves - Mighty Strength", stats = { STR = 50 }, top = false, slot = 10 },
    [4107] = { name = "Enchant Gloves - Greater Mastery", stats = { MASTERY = 65 }, top = false, slot = 10 },
    [4108] = { name = "Enchant Bracer - Greater Speed", stats = { HASTE = 65 }, top = false, slot = 9 },
    [4109] = { name = "Ghostly Spellthread", stats = { INT = 55, SPI = 45 }, top = false, slot = 7 },
    [4110] = { name = "Powerful Ghostly Spellthread", stats = { INT = 95, SPI = 55 }, top = false, slot = 7 },
    [4111] = { name = "Enchanted Spellthread", stats = { INT = 55, STA = 65 }, top = false, slot = 7 },
    [4112] = { name = "Powerful Enchanted Spellthread", stats = { INT = 95, STA = 80 }, top = false, slot = 7 },
    [4113] = { name = "Master's Spellthread (Rank 2)", stats = { INT = 95, STA = 80 }, top = false, slot = 7 },
    [4114] = { name = "Sanctified Spellthread (Rank 2)", stats = { INT = 95, SPI = 55 }, top = false, slot = 7 },
    [4115] = { name = "Lightweave Embroidery (Rank 2)", stats = {  }, top = false, slot = 15 },
    [4116] = { name = "Darkglow Embroidery (Rank 2)", stats = {  }, top = false, slot = 15 },
    [4118] = { name = "Swordguard Embroidery (Rank 2)", stats = {  }, top = false, slot = 15 },
    [4120] = { name = "Savage Armor Kit", stats = { STA = 36 }, top = false, slot = 3 },
    [4121] = { name = "Heavy Savage Armor Kit", stats = { STA = 44 }, top = false, slot = 3 },
    [4124] = { name = "Twilight Leg Armor", stats = { AGI = 45, STA = 85 }, top = false, slot = 7 },
    [4126] = { name = "Dragonscale Leg Armor", stats = { AP = 190, CRIT = 55, RAP = 190 }, top = false, slot = 7 },
    [4127] = { name = "Charscale Leg Armor", stats = { AGI = 55, STA = 145 }, top = false, slot = 7 },
    [4175] = { name = "Gnomish X-Ray Scope", stats = {  }, top = false, slot = 16, kind = "ranged" },
    [4179] = { name = "Synapse Springs (Mark I)", stats = {  }, top = false, slot = 10 },
    [4180] = { name = "Quickflip Deflection Plates", stats = {  }, top = false, slot = 10 },
    [4181] = { name = "Tazik Shocker", stats = {  }, top = false, slot = 10 },
    [4187] = { name = "Invisibility Field", stats = {  }, top = false, slot = 6 },
    [4188] = { name = "Grounded Plasma Shield", stats = {  }, top = false, slot = 6 },
    [4189] = { name = "Fur Lining - Stamina (Rank 2)", stats = { STA = 195 }, top = false, slot = 9 },
    [4190] = { name = "Fur Lining - Agility (Rank 2)", stats = { AGI = 130 }, top = false, slot = 9 },
    [4191] = { name = "Fur Lining - Strength (Rank 2)", stats = { STR = 130 }, top = false, slot = 9 },
    [4192] = { name = "Fur Lining - Intellect (Rank 2)", stats = { INT = 130 }, top = false, slot = 9 },
    [4193] = { name = "Swiftsteel Inscription", stats = { AGI = 130, MASTERY = 25 }, top = false, slot = 3 },
    [4194] = { name = "Lionsmane Inscription", stats = { CRIT = 25, STR = 130 }, top = false, slot = 3 },
    [4195] = { name = "Inscription of the Earth Prince", stats = { DODGE = 25, STA = 195 }, top = false, slot = 3 },
    [4196] = { name = "Felfire Inscription", stats = { HASTE = 25, INT = 130 }, top = false, slot = 3 },
    [4197] = { name = "Inscription of Unbreakable Quartz", stats = { DODGE = 20, STA = 45 }, top = false, slot = 3 },
    [4198] = { name = "Greater Inscription of Unbreakable Quartz", stats = { DODGE = 25, STA = 75 }, top = false, slot = 3 },
    [4199] = { name = "Inscription of Charged Lodestone", stats = { HASTE = 20, INT = 30 }, top = false, slot = 3 },
    [4200] = { name = "Greater Inscription of Charged Lodestone", stats = { HASTE = 25, INT = 50 }, top = false, slot = 3 },
    [4201] = { name = "Inscription of Jagged Stone", stats = { CRIT = 20, STR = 30 }, top = false, slot = 3 },
    [4202] = { name = "Greater Inscription of Jagged Stone", stats = { CRIT = 25, STR = 50 }, top = false, slot = 3 },
    [4204] = { name = "Greater Inscription of Shattered Crystal", stats = { AGI = 50, MASTERY = 25 }, top = false, slot = 3 },
    [4205] = { name = "Inscription of Shattered Crystal", stats = { AGI = 30, MASTERY = 20 }, top = false, slot = 3 },
    [4214] = { name = "Cardboard Assassin", stats = {  }, top = false, slot = 6 },
    [4215] = { name = "Elementium Shield Spike", stats = {  }, top = false },
    [4216] = { name = "Pyrium Shield Spike", stats = {  }, top = false },
    [4217] = { name = "Pyrium Weapon Chain", stats = { HIT = 40 }, top = false, slot = 16, kind = "weapon" },
    [4222] = { name = "Mind Amplification Dish", stats = {  }, top = false, slot = 6 },
    [4223] = { name = "Nitro Boosts", stats = {  }, top = false, slot = 6 },
    [4227] = { name = "Enchant 2H Weapon - Mighty Agility", stats = { AGI = 130 }, top = false, slot = 16, kind = "weapon" },
    [4248] = { name = "Greater Inscription of Vicious Intellect", stats = { INT = 50, RESIL = 25 }, top = false, slot = 3, pvp = true },
    [4249] = { name = "Greater Inscription of Vicious Strength", stats = { RESIL = 25, STR = 50 }, top = false, slot = 3, pvp = true },
    [4250] = { name = "Greater Inscription of Vicious Agility", stats = { AGI = 50, RESIL = 25 }, top = false, slot = 3, pvp = true },
    [4256] = { name = "Enchant Bracer - Major Strength", stats = { STR = 50 }, top = false, slot = 9 },
    [4257] = { name = "Enchant Bracer - Mighty Intellect", stats = { INT = 50 }, top = false, slot = 9 },
    [4258] = { name = "Enchant Bracer - Agility", stats = { AGI = 50 }, top = false, slot = 9 },
    [4259] = { name = "Reinforced Fishing Line", stats = {  }, top = false, slot = 16, kind = "weapon" },
    [4267] = { name = "Flintlocke's Woodchucker", stats = {  }, top = false, slot = 16, kind = "ranged" },
    [4270] = { name = "Drakehide Leg Armor", stats = { DODGE = 55, STA = 145 }, top = false, slot = 7 },
    [4359] = { name = "Enchant Ring - Greater Agility", stats = { AGI = 160 }, top = true, slot = 11 },
    [4360] = { name = "Enchant Ring - Greater Intellect", stats = { INT = 160 }, top = true, slot = 11 },
    [4361] = { name = "Enchant Ring - Greater Stamina", stats = { STA = 240 }, top = true, slot = 11 },
    [4411] = { name = "Enchant Bracer - Mastery", stats = { MASTERY = 170 }, top = true, slot = 9 },
    [4412] = { name = "Enchant Bracer - Major Dodge", stats = { DODGE = 170 }, top = true, slot = 9 },
    [4414] = { name = "Enchant Bracer - Super Intellect", stats = { INT = 180 }, top = true, slot = 9 },
    [4415] = { name = "Enchant Bracer - Exceptional Strength", stats = { STR = 180 }, top = true, slot = 9 },
    [4416] = { name = "Enchant Bracer - Greater Agility", stats = { AGI = 180 }, top = true, slot = 9 },
    [4417] = { name = "Enchant Chest - Super Resilience", stats = { RESIL = 200 }, top = false, slot = 5, pvp = true },
    [4418] = { name = "Enchant Chest - Mighty Spirit", stats = { SPI = 200 }, top = true, slot = 5 },
    [4419] = { name = "Enchant Chest - Glorious Stats", stats = { AGI = 80, INT = 80, SPI = 80, STA = 80, STR = 80 }, top = true, slot = 5 },
    [4420] = { name = "Enchant Chest - Superior Stamina", stats = { STA = 300 }, top = true, slot = 5 },
    [4421] = { name = "Enchant Cloak - Accuracy", stats = { HIT = 180 }, top = true, slot = 15 },
    [4422] = { name = "Enchant Cloak - Greater Protection", stats = { STA = 200 }, top = true, slot = 15 },
    [4423] = { name = "Enchant Cloak - Superior Intellect", stats = { INT = 180 }, top = true, slot = 15 },
    [4424] = { name = "Enchant Cloak - Superior Critical Strike", stats = { CRIT = 180 }, top = true, slot = 15 },
    [4426] = { name = "Enchant Boots - Greater Haste", stats = { HASTE = 175 }, top = true, slot = 8 },
    [4427] = { name = "Enchant Boots - Greater Precision", stats = { HIT = 175 }, top = true, slot = 8 },
    [4428] = { name = "Enchant Boots - Blurred Speed", stats = { AGI = 140 }, top = true, slot = 8 },
    [4429] = { name = "Enchant Boots - Pandaren's Step", stats = { MASTERY = 140 }, top = true, slot = 8 },
    [4430] = { name = "Enchant Gloves - Greater Haste", stats = { HASTE = 170 }, top = true, slot = 10 },
    [4431] = { name = "Enchant Gloves - Superior Expertise", stats = { EXP = 170 }, top = true, slot = 10 },
    [4432] = { name = "Enchant Gloves - Super Strength", stats = { STR = 170 }, top = true, slot = 10 },
    [4433] = { name = "Enchant Gloves - Superior Mastery", stats = { MASTERY = 170 }, top = true, slot = 10 },
    [4434] = { name = "Enchant Off-Hand - Major Intellect", stats = { INT = 165 }, top = true, slot = 16, kind = "offhand" },
    [4441] = { name = "Enchant Weapon - Windsong", stats = {  }, top = false, slot = 16, kind = "weapon" },
    [4442] = { name = "Enchant Weapon - Jade Spirit", stats = { INT = 1650 }, top = true, slot = 16, kind = "weapon" },
    [4443] = { name = "Enchant Weapon - Elemental Force", stats = {  }, top = false, slot = 16, kind = "weapon" },
    [4444] = { name = "Enchant Weapon - Dancing Steel", stats = { AGI = 1650, STR = 1650 }, top = true, slot = 16, kind = "weapon" },
    [4445] = { name = "Enchant Weapon - Colossus", stats = {  }, top = false, slot = 16, kind = "weapon" },
    [4446] = { name = "Enchant Weapon - River's Song", stats = { DODGE = 1650 }, top = true, slot = 16, kind = "weapon", role = "TANK" },
    [4697] = { name = "Phase Fingers", stats = {  }, top = false, slot = 10 },
    [4698] = { name = "Incendiary Fireworks Launcher", stats = {  }, top = false, slot = 10 },
    [4699] = { name = "Lord Blastington's Scope of Doom", stats = { AGI = 1800 }, top = true, slot = 16, kind = "ranged" },
    [4700] = { name = "Mirror Scope", stats = {  }, top = false, slot = 16, kind = "ranged" },
    [4719] = { name = "Inscription", stats = { CRIT = 25, STR = 130 }, top = false, slot = 3 },
    [4732] = { name = "Enchant Gloves - Angler", stats = {  }, top = false, slot = 10 },
    [4750] = { name = "Spinal Healing Injector", stats = {  }, top = false, slot = 6 },
    [4803] = { name = "Greater Tiger Fang Inscription", stats = { CRIT = 100, STR = 200 }, top = true, slot = 3 },
    [4804] = { name = "Greater Tiger Claw Inscription", stats = { AGI = 200, CRIT = 100 }, top = true, slot = 3 },
    [4805] = { name = "Greater Ox Horn Inscription", stats = { DODGE = 100, STA = 300 }, top = true, slot = 3 },
    [4806] = { name = "Greater Crane Wing Inscription", stats = { CRIT = 100, INT = 200 }, top = true, slot = 3 },
    [4807] = { name = "Enchant Ring - Greater Strength", stats = { STR = 160 }, top = true, slot = 11 },
    [4822] = { name = "Shadowleather Leg Armor", stats = { AGI = 285, CRIT = 165 }, top = true, slot = 7 },
    [4823] = { name = "Angerhide Leg Armor", stats = { CRIT = 165, STR = 285 }, top = true, slot = 7 },
    [4824] = { name = "Ironscale Leg Armor", stats = { DODGE = 165, STA = 430 }, top = true, slot = 7 },
    [4825] = { name = "Greater Cerulean Spellthread", stats = { CRIT = 165, INT = 285 }, top = true, slot = 7 },
    [4826] = { name = "Greater Pearlescent Spellthread", stats = { INT = 285, SPI = 165 }, top = true, slot = 7 },
    [4869] = { name = "Sha Armor Kit", stats = { STA = 150 }, top = false, slot = 3 },
    [4870] = { name = "Toughened Leg Armor", stats = { DODGE = 100, STA = 250 }, top = false, slot = 7 },
    [4871] = { name = "Sha-Touched Leg Armor", stats = { AGI = 170, CRIT = 100 }, top = false, slot = 7 },
    [4872] = { name = "Brutal Leg Armor", stats = { CRIT = 100, STR = 170 }, top = false, slot = 7 },
    [4875] = { name = "Fur Lining - Agility (Rank 3)", stats = { AGI = 500 }, top = true, slot = 9 },
    [4877] = { name = "Fur Lining - Intellect (Rank 3)", stats = { INT = 500 }, top = true, slot = 9 },
    [4878] = { name = "Fur Lining - Stamina (Rank 3)", stats = { STA = 750 }, top = true, slot = 9 },
    [4879] = { name = "Fur Lining - Strength (Rank 3)", stats = { STR = 500 }, top = true, slot = 9 },
    [4880] = { name = "Primal Leg Reinforcements (Rank 3)", stats = { AGI = 285, CRIT = 165 }, top = true, slot = 7 },
    [4881] = { name = "Draconic Leg Reinforcements (Rank 3)", stats = { CRIT = 165, STR = 285 }, top = true, slot = 7 },
    [4882] = { name = "Heavy Leg Reinforcements (Rank 3)", stats = { DODGE = 165, STA = 430 }, top = true, slot = 7 },
    [4883] = { name = "Primal Leg Reinforcements (Rank 2)", stats = { AGI = 95, CRIT = 55 }, top = false, slot = 7 },
    [4884] = { name = "Heavy Leg Reinforcements (Rank 2)", stats = { DODGE = 55, STA = 143 }, top = false, slot = 7 },
    [4885] = { name = "Draconic Leg Reinforcements (Rank 2)", stats = { CRIT = 55, STR = 95 }, top = false, slot = 7 },
    [4892] = { name = "Lightweave Embroidery (Rank 3)", stats = { INT = 2000 }, top = true, slot = 15 },
    [4893] = { name = "Darkglow Embroidery (Rank 3)", stats = { SPI = 3000 }, top = true, slot = 15 },
    [4894] = { name = "Swordguard Embroidery (Rank 3)", stats = { AP = 4000 }, top = true, slot = 15 },
    [4895] = { name = "Master's Spellthread (Rank 3)", stats = { CRIT = 165, INT = 285 }, top = true, slot = 7 },
    [4896] = { name = "Sanctified Spellthread (Rank 3)", stats = { INT = 285, SPI = 165 }, top = true, slot = 7 },
    [4897] = { name = "Goblin Glider", stats = {  }, top = false, slot = 15 },
    [4898] = { name = "Synapse Springs (Mark II)", stats = {  }, top = false, slot = 10 },
    [4907] = { name = "Tiger Fang Inscription", stats = { CRIT = 80, STR = 120 }, top = false, slot = 3 },
    [4908] = { name = "Tiger Claw Inscription", stats = { AGI = 120, CRIT = 80 }, top = false, slot = 3 },
    [4909] = { name = "Crane Wing Inscription", stats = { CRIT = 80, INT = 120 }, top = false, slot = 3 },
    [4910] = { name = "Ox Horn Inscription", stats = { DODGE = 80, STA = 180 }, top = false, slot = 3 },
    [4912] = { name = "Secret Ox Horn Inscription", stats = { DODGE = 100, STA = 780 }, top = true, slot = 3 },
    [4913] = { name = "Secret Tiger Fang Inscription", stats = { CRIT = 100, STR = 520 }, top = true, slot = 3 },
    [4914] = { name = "Secret Tiger Claw Inscription", stats = { AGI = 520, CRIT = 100 }, top = true, slot = 3 },
    [4915] = { name = "Secret Crane Wing Inscription", stats = { CRIT = 100, INT = 520 }, top = true, slot = 3 },
    [4918] = { name = "Living Steel Weapon Chain", stats = { EXP = 200 }, top = false, slot = 16, kind = "weapon", pvp = "disarm reduction" },
    [4993] = { name = "Enchant Shield - Greater Parry", stats = { PARRY = 170 }, top = true, slot = 16, kind = "shield" },
    [5000] = { name = "Watergliding Jets", stats = {  }, top = false, slot = 6 },
    [5001] = { name = "Ghost Iron Shield Spike", stats = {  }, top = false },
    [5003] = { name = "Cerulean Spellthread", stats = { CRIT = 100, INT = 170 }, top = false, slot = 7 },
    [5004] = { name = "Pearlescent Spellthread", stats = { INT = 170, SPI = 100 }, top = false, slot = 7 },
    [5035] = { name = "Enchant Weapon - Glorious Tyranny", stats = { PVP = 600 }, top = false, slot = 16, kind = "weapon", pvp = true },
    [5124] = { name = "Enchant Weapon - Spirit of Conquest", stats = { INT = 1650 }, top = true, slot = 16, kind = "weapon" },
    [5125] = { name = "Enchant Weapon - Bloody Dancing Steel", stats = { AGI = 1650, STR = 1650 }, top = true, slot = 16, kind = "weapon" },
}

local STAT_KEYS = {
    STR = { "ITEM_MOD_STRENGTH_SHORT", "ITEM_MOD_STRENGTH" },
    AGI = { "ITEM_MOD_AGILITY_SHORT", "ITEM_MOD_AGILITY" },
    INT = { "ITEM_MOD_INTELLECT_SHORT", "ITEM_MOD_INTELLECT" },
}
local SOCKET_KEYS = {
    "EMPTY_SOCKET_RED", "EMPTY_SOCKET_YELLOW", "EMPTY_SOCKET_BLUE",
    "EMPTY_SOCKET_META", "EMPTY_SOCKET_PRISMATIC", "EMPTY_SOCKET_COGWHEEL",
    "EMPTY_SOCKET_HYDRAULIC",
}

-- Upgrade IDs used by MoP item links. Tooltip scanning below is preferred;
-- this table is a fallback for server cores whose hidden tooltip is incomplete.
local UPGRADE_DELTA = {
    [445] = 0, [446] = 4, [447] = 8,
    [451] = 0, [452] = 8,
    [453] = 0, [454] = 4, [455] = 8,
    [456] = 0, [457] = 8,
    [458] = 0, [459] = 4, [460] = 8, [461] = 12, [462] = 16,
    [465] = 0, [466] = 4, [467] = 8,
    [468] = 0, [469] = 4, [470] = 8, [471] = 12, [472] = 16,
    [491] = 0, [492] = 4, [493] = 8, [494] = 0, [495] = 4,
    [496] = 8, [497] = 12, [498] = 16, [504] = 12, [505] = 16,
    [506] = 20, [507] = 24,
}

local GearScanTip = CreateFrame("GameTooltip", "ARCGearScanTooltip", nil, "GameTooltipTemplate")
local function EscapePattern(text)
    return (text:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1"))
end
local ITEM_LEVEL_PATTERN
if ITEM_LEVEL then
    ITEM_LEVEL_PATTERN = EscapePattern(ITEM_LEVEL):gsub("%%%%d", "(%%d+)")
else
    ITEM_LEVEL_PATTERN = "Item Level (%d+)"
end

local function ParseItemFields(link)
    if type(link) ~= "string" then return nil end
    local itemString = link:match("item:[%-?%d:]+")
    if not itemString then return nil end
    return { strsplit(":", itemString) }
end

local function GetEnchantID(link)
    local fields = ParseItemFields(link)
    return fields and tonumber(fields[3]) or 0 -- item:ITEM_ID:ENCHANT_ID
end

local function GetUpgradeDelta(link)
    local fields = ParseItemFields(link)
    local upgradeID = fields and tonumber(fields[12]) -- 11th field after "item:"
    return (upgradeID and UPGRADE_DELTA[upgradeID]) or 0
end

local function ScanEffectiveItemLevel(unit, slot, link)
    GearScanTip:SetOwner(UIParent, "ANCHOR_NONE")
    GearScanTip:ClearLines()
    GearScanTip:SetInventoryItem(unit, slot)
    for line = 2, GearScanTip:NumLines() do
        local fs = _G["ARCGearScanTooltipTextLeft" .. line]
        local text = fs and fs:GetText()
        local level = text and tonumber(text:match(ITEM_LEVEL_PATTERN))
        if level then
            GearScanTip:Hide()
            return level
        end
    end
    GearScanTip:Hide()
    local baseLevel = link and select(4, GetItemInfo(link))
    return baseLevel and (baseLevel + GetUpgradeDelta(link)) or nil
end

local function StatAmount(stats, keyList)
    local total = 0
    for _, keyName in ipairs(keyList) do
        local localized = _G[keyName]
        local value = stats[keyName]
        if value == nil and localized then value = stats[localized] end
        total = total + (tonumber(value) or 0)
    end
    return total
end

local function SocketCount(stats)
    local total = 0
    for _, keyName in ipairs(SOCKET_KEYS) do
        local localized = _G[keyName]
        local value = stats[keyName]
        if value == nil and localized then value = stats[localized] end
        total = total + (tonumber(value) or 0)
    end
    return total
end

local function FilledGemCount(link, maximum)
    -- Nonzero gem fields prove a filled socket even when gem names are cold.
    -- On legacy clients these fields can be enchantment IDs, not item IDs;
    -- resolve the actual gem item with GetItemGem before checking its policy.
    local fields = ParseItemFields(link)
    if fields then
        local filled = 0
        for field = 4, 7 do
            if (tonumber(fields[field]) or 0) > 0 then filled = filled + 1 end
        end
        return filled
    end
    if not GetItemGem then return nil end
    local filled = 0
    for gemIndex = 1, math.max(maximum or 0, 4) do
        local gemName, gemLink = GetItemGem(link, gemIndex)
        if gemName or gemLink then filled = filled + 1 end
    end
    return filled
end

local function ValidationWarning(result, detail, message, pending)
    detail.warnings[#detail.warnings + 1] = message
    result.unverified[#result.unverified + 1] = detail.label .. ": " .. message
    if pending then result.validationPending = true end
end

local function StatProblem(stats, expected)
    if not expected then return nil end
    local other = (stats.STR or 0) + (stats.AGI or 0) + (stats.INT or 0) - (stats[expected] or 0)
    if other > 0 and (stats[expected] or 0) == 0 then return "wrong primary stat; expected " .. expected end
    if expected == "INT" and ((stats.AP or 0) > 0 or (stats.RAP or 0) > 0) then return "attack power on an INT spec" end
    if expected ~= "INT" and (stats.SP or 0) > 0 then return "spell power on a physical spec" end
end

local function CheckGemPolicy(result, detail, link, entry, expected)
    local fields = ParseItemFields(link)
    if not fields then
        ValidationWarning(result, detail, "Gem fields unavailable")
        return
    end
    for index = 1, 4 do
        if (tonumber(fields[index + 3]) or 0) > 0 then
            local gemName, gemLink
            if GetItemGem then gemName, gemLink = GetItemGem(link, index) end
            local gemID = gemLink and tonumber(gemLink:match("item:(%d+)"))
            local rule = gemID and GEM_RULE_DATA[gemID]
            local infoName, _, quality, level
            if gemLink then infoName, _, quality, level = GetItemInfo(gemLink) end
            gemName = gemName or infoName or (rule and rule.name) or ("gem #" .. index)
            local reasons = {}
            if rule then
                if (quality or rule.quality) < 3 then reasons[#reasons + 1] = "below rare (blue) quality" end
                if rule.pvp or (rule.stats.PVP or 0) > 0 or (rule.stats.RESIL or 0) > 0 then
                    reasons[#reasons + 1] = "PvP bonus" .. (type(rule.pvp) == "string" and (" (" .. rule.pvp .. ")") or " (resilience / PvP power)")
                end
                local problem = StatProblem(rule.stats, expected)
                if problem then reasons[#reasons + 1] = problem end
                if expected and rule.primary and ((rule.primary == "PHYSICAL" and expected == "INT") or
                    (rule.primary == "INT" and expected ~= "INT")) then
                    reasons[#reasons + 1] = "meta proc for a different type of spec"
                end
                if rule.role and entry.role and entry.role ~= "NONE" then
                    if entry.role ~= rule.role then reasons[#reasons + 1] = "meta proc requires role " .. rule.role end
                elseif rule.role then
                    ValidationWarning(result, detail, gemName .. ": role unavailable")
                end
            elseif gemID and infoName and quality and level then
                if quality < 3 then reasons[#reasons + 1] = "below rare (blue) quality" end
                if level < 90 then reasons[#reasons + 1] = "older than the MoP level-90 gem tier" end
                local live = GetItemStats and GetItemStats(gemLink)
                if live then
                    local stats = {}
                    for stat, keys in pairs(STAT_KEYS) do stats[stat] = StatAmount(live, keys) end
                    local problem = StatProblem(stats, expected)
                    if problem then reasons[#reasons + 1] = problem end
                    if StatAmount(live, { "ITEM_MOD_RESILIENCE_RATING_SHORT", "ITEM_MOD_RESILIENCE_RATING",
                        "ITEM_MOD_PVP_POWER_SHORT", "ITEM_MOD_PVP_POWER" }) > 0 then
                        reasons[#reasons + 1] = "PvP bonus (resilience / PvP power)"
                    end
                end
                if #reasons == 0 then ValidationWarning(result, detail, gemName .. " (#" .. gemID .. "): unknown gem policy") end
            else
                ValidationWarning(result, detail, "Gem " .. index .. ": data unavailable", GetItemGem ~= nil)
            end
            if #reasons > 0 then
                local text = "Gem " .. index .. " - " .. gemName .. ": " .. table.concat(reasons, "; ")
                detail.issues[#detail.issues + 1] = text
                result.badGems[#result.badGems + 1] = detail.label .. ": " .. text
            end
        end
    end
end

local function CheckEnchantPolicy(result, detail, link, entry, expected, equipLoc, quality)
    local id = GetEnchantID(link)
    local required = ENCHANT_SLOTS[detail.slot] and (quality or 0) >= 3
    detail.enchant = "Not required by ARC rules"
    -- Belt buckles and extra sockets are not permanent stat enchants. Rings
    -- remain optional because another player's profession is not inspectable.
    if not ENCHANT_SLOTS[detail.slot] and detail.slot ~= 11 and detail.slot ~= 12 then return end
    if id == 0 then
        if required then
            detail.enchant = "Missing"
            detail.issues[#detail.issues + 1] = "Missing enchant"
            result.missingEnchants[#result.missingEnchants + 1] = detail.label
        end
        return
    end
    local rule = ENCHANT_RULE_DATA[id]
    detail.enchant = rule and rule.name or ("Enchant #" .. id)
    if not rule then
        ValidationWarning(result, detail, "Unknown enchant #" .. id .. "; top tier and stats not verified")
        return
    end
    local reasons = {}
    if rule.pvp then reasons[#reasons + 1] = "PvP-oriented bonus" end
    if not rule.top then reasons[#reasons + 1] = "below the approved top MoP raid tier" end
    local problem = StatProblem(rule.stats, expected)
    if problem then reasons[#reasons + 1] = problem end
    local actualSlot = detail.slot == 12 and 11 or detail.slot == 17 and 16 or detail.slot
    if rule.slot and rule.slot ~= actualSlot then reasons[#reasons + 1] = "wrong equipment slot" end
    local ranged = equipLoc == "INVTYPE_RANGED" or equipLoc == "INVTYPE_RANGEDRIGHT"
    -- Wands use caster enchants; the ranged scope requirement is for hunters.
    if rule.kind == "ranged" and (not ranged or entry.class ~= "HUNTER") then
        reasons[#reasons + 1] = "scope requires a hunter ranged weapon"
    elseif rule.kind == "shield" and equipLoc ~= "INVTYPE_SHIELD" then
        reasons[#reasons + 1] = "shield enchant on a different item type"
    elseif rule.kind == "offhand" and equipLoc ~= "INVTYPE_HOLDABLE" and equipLoc ~= "INVTYPE_SHIELD" then
        reasons[#reasons + 1] = "off-hand enchant on a different item type"
    elseif rule.kind == "weapon" and (equipLoc == "INVTYPE_SHIELD" or equipLoc == "INVTYPE_HOLDABLE" or
        (ranged and entry.class == "HUNTER")) then
        reasons[#reasons + 1] = "weapon enchant on a different item type"
    end
    if rule.class then
        if not entry.class then ValidationWarning(result, detail, detail.enchant .. ": class unavailable")
        elseif entry.class ~= rule.class then reasons[#reasons + 1] = "requires " .. rule.class end
    end
    if rule.role and entry.role and entry.role ~= "NONE" then
        if entry.role ~= rule.role then reasons[#reasons + 1] = "requires role " .. rule.role end
    elseif rule.role then ValidationWarning(result, detail, detail.enchant .. ": role unavailable") end
    if #reasons > 0 then
        local text = "Enchant - " .. detail.enchant .. ": " .. table.concat(reasons, "; ")
        detail.issues[#detail.issues + 1] = text
        result.badEnchants[#result.badEnchants + 1] = detail.label .. ": " .. text
    end
end

function ARC:AnalyzeUnitGear(unit, entry)
    if not unit or not UnitExists(unit) or not entry then return nil end
    local result = {
        scanned = true, scannedAt = GetTime(), totalSockets = 0, missingGems = 0,
        missingGemSlots = {}, missingEnchants = {}, wrongPrimary = {},
        lowItems = {}, missingItems = {}, itemLevels = {},
        slots = {}, pendingSlots = {}, badGems = {}, badEnchants = {}, unverified = {},
        minItemLevel = (ARC_DB and tonumber(ARC_DB.minItemLevel)) or 450,
    }
    local expectedPrimary = SPEC_PRIMARY[entry.specID]
    local minLevel = (ARC_DB and tonumber(ARC_DB.minItemLevel)) or 450
    local totalLevel, loadedWeight = 0, 0
    local offLink = GetInventoryItemLink(unit, 17)
    local itemCount = 0

    for _, slot in ipairs(EQUIPPED_SLOTS) do
        local link = GetInventoryItemLink(unit, slot)
        local detail = { slot = slot, label = SLOT_NAMES[slot], link = link, issues = {}, warnings = {} }
        result.slots[#result.slots + 1] = detail
        if link then
            itemCount = itemCount + 1
            local itemName, _, quality, _, _, _, _, _, equipLoc, itemIcon = GetItemInfo(link)
            local effectiveLevel = ScanEffectiveItemLevel(unit, slot, link)
            result.itemLevels[slot] = effectiveLevel
            detail.name, detail.ilvl = itemName, effectiveLevel
            detail.icon = itemIcon or (GetInventoryItemTexture and GetInventoryItemTexture(unit, slot))
            detail.pending = not itemName or not effectiveLevel or not equipLoc

            local weight = FIXED_AVERAGE_SLOTS[slot] and 1 or 0
            if slot == 16 then
                local hunterRanged = entry.class == "HUNTER" and
                    (equipLoc == "INVTYPE_RANGED" or equipLoc == "INVTYPE_RANGEDRIGHT")
                weight = ((equipLoc == "INVTYPE_2HWEAPON" or hunterRanged) and not offLink) and 2 or 1
            elseif slot == 17 then
                weight = 1
            end
            if effectiveLevel and weight > 0 then
                totalLevel = totalLevel + effectiveLevel * weight
                loadedWeight = loadedWeight + weight
            end

            local label = SLOT_NAMES[slot] or tostring(slot)
            if effectiveLevel and effectiveLevel < minLevel then
                detail.issues[#detail.issues + 1] = "Below " .. minLevel .. " iLvl"
                result.lowItems[#result.lowItems + 1] = {
                    slot = slot, label = label, name = itemName or link, ilvl = effectiveLevel,
                }
            end

            -- Read sockets/primary attributes from the base item so inserted
            -- gem stats cannot make an incorrect item appear spec-correct and
            -- filled sockets do not disappear from the socket count.
            local fields = ParseItemFields(link)
            local itemID = fields and tonumber(fields[2])
            local baseItem = itemID and ("item:" .. itemID) or link
            local stats = GetItemStats and GetItemStats(baseItem)
            if not stats or not GetItemInfo(baseItem) then detail.pending = true end
            stats = stats or {}
            local sockets = SocketCount(stats)
            local filled = FilledGemCount(link, sockets)
            -- Include inserted gems in added sockets (belt buckle, profession
            -- sockets) even when base-item stats do not describe those sockets.
            sockets = math.max(sockets, filled or 0)
            if sockets > 0 then
                if filled ~= nil then
                    detail.gems = math.min(filled, sockets) .. "/" .. sockets
                    local missing = math.max(0, sockets - filled)
                    result.totalSockets = result.totalSockets + sockets
                    result.missingGems = result.missingGems + missing
                    if missing > 0 then
                        detail.issues[#detail.issues + 1] = missing .. " missing gem(s)"
                        result.missingGemSlots[#result.missingGemSlots + 1] = label .. " (" .. missing .. ")"
                    end
                end
            else
                detail.gems = "No sockets"
            end

            CheckGemPolicy(result, detail, link, entry, expectedPrimary)
            CheckEnchantPolicy(result, detail, link, entry, expectedPrimary, equipLoc, quality)

            if expectedPrimary and slot ~= 13 and slot ~= 14 then
                local expected = StatAmount(stats, STAT_KEYS[expectedPrimary])
                local other = 0
                for statName, keys in pairs(STAT_KEYS) do
                    if statName ~= expectedPrimary then other = other + StatAmount(stats, keys) end
                end
                if expected == 0 and other > 0 then
                    detail.issues[#detail.issues + 1] = "Wrong primary stat (expected " .. expectedPrimary .. ")"
                    result.wrongPrimary[#result.wrongPrimary + 1] = label .. ": " .. (itemName or "item")
                end
            end
        else
            -- A texture without an item link means equipment is still loading,
            -- not an empty slot. Only evaluate empties after a valid inspect.
            detail.pending = GetInventoryItemTexture and GetInventoryItemTexture(unit, slot) ~= nil
            detail.empty = not detail.pending
            if detail.empty and (FIXED_AVERAGE_SLOTS[slot] or slot == 16) then
                detail.issues[1] = "Empty required slot"
                result.missingItems[#result.missingItems + 1] = SLOT_NAMES[slot] or tostring(slot)
            end
        end
        if detail.pending then result.pendingSlots[#result.pendingSlots + 1] = detail.label end
    end

    result.scanned = #result.pendingSlots == 0 and itemCount > 0
    result.averageItemLevel = result.scanned and loadedWeight > 0 and Round(totalLevel / 16) or nil
    result.expectedPrimary = expectedPrimary
    if not expectedPrimary then result.unverified[#result.unverified + 1] = "Spec unavailable - primary-stat suitability not evaluated" end
    result.auditComplete = result.scanned and #result.unverified == 0
    result.issueCount = result.missingGems + #result.missingEnchants +
        #result.wrongPrimary + #result.lowItems + #result.missingItems + #result.badGems + #result.badEnchants
    entry.gear = result
    if result.scanned and not result.validationPending then entry.lastGearScan = result.scannedAt end
    return result.averageItemLevel
end

ARC.SPEC_PRIMARY = SPEC_PRIMARY
ARC.GEAR_SLOT_NAMES = SLOT_NAMES
ARC.GEAR_RULES = {
    specPrimary = SPEC_PRIMARY,
    enchantSlots = ENCHANT_SLOTS,
    gems = GEM_RULE_DATA,
    enchants = ENCHANT_RULE_DATA,
}
