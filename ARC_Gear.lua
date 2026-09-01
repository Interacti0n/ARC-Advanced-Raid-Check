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
    if not GetItemGem then return nil end
    local filled = 0
    for gemIndex = 1, math.max(maximum or 0, 4) do
        local gemName, gemLink = GetItemGem(link, gemIndex)
        if gemName or gemLink then filled = filled + 1 end
    end
    return filled
end

function ARC:AnalyzeUnitGear(unit, entry)
    if not unit or not UnitExists(unit) or not entry then return nil end
    local result = {
        scanned = true, scannedAt = GetTime(), totalSockets = 0, missingGems = 0,
        missingGemSlots = {}, missingEnchants = {}, wrongPrimary = {},
        lowItems = {}, missingItems = {}, itemLevels = {},
    }
    local expectedPrimary = SPEC_PRIMARY[entry.specID]
    local minLevel = (ARC_DB and tonumber(ARC_DB.minItemLevel)) or 450
    local totalLevel, loadedWeight = 0, 0
    local offLink = GetInventoryItemLink(unit, 17)

    for _, slot in ipairs(EQUIPPED_SLOTS) do
        local link = GetInventoryItemLink(unit, slot)
        if link then
            local itemName, _, quality, _, _, _, _, _, equipLoc = GetItemInfo(link)
            local effectiveLevel = ScanEffectiveItemLevel(unit, slot, link)
            result.itemLevels[slot] = effectiveLevel

            local weight = FIXED_AVERAGE_SLOTS[slot] and 1 or 0
            if slot == 16 then
                weight = (equipLoc == "INVTYPE_2HWEAPON" and not offLink) and 2 or 1
            elseif slot == 17 then
                weight = 1
            end
            if effectiveLevel and weight > 0 then
                totalLevel = totalLevel + effectiveLevel * weight
                loadedWeight = loadedWeight + weight
            end

            local label = SLOT_NAMES[slot] or tostring(slot)
            if effectiveLevel and effectiveLevel < minLevel then
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
            local stats = (GetItemStats and GetItemStats(baseItem)) or {}
            local sockets = SocketCount(stats)
            if sockets > 0 then
                local filled = FilledGemCount(link, sockets)
                if filled ~= nil then
                    local missing = math.max(0, sockets - filled)
                    result.totalSockets = result.totalSockets + sockets
                    result.missingGems = result.missingGems + missing
                    if missing > 0 then
                        result.missingGemSlots[#result.missingGemSlots + 1] = label .. " (" .. missing .. ")"
                    end
                end
            end

            if ENCHANT_SLOTS[slot] and (quality or 0) >= 3 and GetEnchantID(link) == 0 then
                result.missingEnchants[#result.missingEnchants + 1] = label
            end

            if expectedPrimary and slot ~= 13 and slot ~= 14 then
                local expected = StatAmount(stats, STAT_KEYS[expectedPrimary])
                local other = 0
                for statName, keys in pairs(STAT_KEYS) do
                    if statName ~= expectedPrimary then other = other + StatAmount(stats, keys) end
                end
                if expected == 0 and other > 0 then
                    result.wrongPrimary[#result.wrongPrimary + 1] = label .. ": " .. (itemName or "item")
                end
            end
        elseif FIXED_AVERAGE_SLOTS[slot] or slot == 16 then
            result.missingItems[#result.missingItems + 1] = SLOT_NAMES[slot] or tostring(slot)
        end
    end

    result.averageItemLevel = loadedWeight > 0 and Round(totalLevel / 16) or nil
    result.expectedPrimary = expectedPrimary
    result.issueCount = result.missingGems + #result.missingEnchants +
        #result.wrongPrimary + #result.lowItems + #result.missingItems
    entry.gear = result
    entry.lastGearScan = result.scannedAt
    return result.averageItemLevel
end

ARC.SPEC_PRIMARY = SPEC_PRIMARY
ARC.GEAR_SLOT_NAMES = SLOT_NAMES
ARC.GEAR_RULES = {
    specPrimary = SPEC_PRIMARY,
    enchantSlots = ENCHANT_SLOTS,
    -- Future server policy can add allowedEnchantsBySpec / allowedGemsBySpec
    -- here without changing inspect, roster or UI code.
}
