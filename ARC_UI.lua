local ARC = assert(_G.ARC, "ARC_Core.lua must load before ARC_UI.lua")
local I = assert(ARC.Internal, "ARC internal API is unavailable")
local ClassColor = I.ClassColor
local DurabilityColor = I.DurabilityColor
local GetReadyCheckSecondsLeft = I.GetReadyCheckSecondsLeft

--=============================================================================
-- UI CONSTRUCTION
--=============================================================================

local ROW_HEIGHT    = 26   -- was 22 - main fix for rows crowding/overlapping
local HEADER_HEIGHT = 26
local FOOTER_HEIGHT = 34
local TOP_OFFSET    = 162  -- ready responses, visible raid setup banner, summary, labels
local FRAME_WIDTH   = 850
local ICON_MISSING  = "Interface\\RaidFrame\\ReadyCheck-NotReady"
local ICON_BLANK    = "Interface\\Buttons\\UI-Quickslot2"

-- Single source of truth for column layout. Both the header labels and the
-- row widgets are built from this table, so they can no longer drift out of
-- alignment with each other (that mismatch was the previous version's real
-- "overlapping rows" bug).
local COLS = {
    { key = "ready", label = "",      x = 4,   w = 16,  kind = "icon", iconSize = 14 },
    { key = "role",  label = "",      x = 22,  w = 18,  kind = "icon", iconSize = 18 },
    { key = "spec",  label = "",      x = 42,  w = 18,  kind = "icon", iconSize = 16 },
    { key = "name",  label = "Name",  x = 62,  w = 126, kind = "text", justify = "LEFT" },
    { key = "flask", label = "Flask", x = 190, w = 46,  kind = "icon", iconSize = 20 },
    { key = "food",  label = "Food",  x = 238, w = 46,  kind = "icon", iconSize = 20 },
    { key = "sta",   label = "Stam",  x = 286, w = 42,  kind = "icon", iconSize = 18 },
    { key = "stat",  label = "Stat",  x = 330, w = 42,  kind = "icon", iconSize = 18 },
    { key = "crit",  label = "Crit",  x = 374, w = 42,  kind = "icon", iconSize = 18 },
    { key = "mast",  label = "Mast",  x = 418, w = 42,  kind = "icon", iconSize = 18 },
    { key = "ilvl",  label = "iLvl",  x = 462, w = 52,  kind = "text", justify = "CENTER" },
    { key = "dur",   label = "Dur",   x = 516, w = 52,  kind = "text", justify = "CENTER" },
    { key = "gear",  label = "Gear",  x = 570, w = 52,  kind = "text", justify = "CENTER" },
    { key = "tal",   label = "Talents", x = 624, w = 60, kind = "text", justify = "CENTER" },
    { key = "selfBuff", label = "Self", x = 686, w = 50, kind = "text", justify = "CENTER" },
    { key = "hs",    label = "HS",    x = 738, w = 40,  kind = "text", justify = "CENTER" },
    { key = "arc",   label = "ARC",   x = 780, w = 50,  kind = "text", justify = "CENTER" },
}

--=============================================================================
-- PER-CATEGORY BUFF SOURCE LIST (column-header tooltips)
-- Hovering "Stam"/"Stat"/"Crit"/"Mast" in the header shows exactly which
-- raid members are covering that category and with which buff, instead of
-- just the per-player yes/no icon.
--=============================================================================

local CATEGORY_TITLES = {
    sta  = "Stamina Buff Sources",
    stat = "Stats Buff Sources",
    crit = "Crit Buff Sources",
    mast = "Mastery Buff Sources",
}
local CATEGORY_NAME_FIELD = {
    sta  = "staName",
    stat = "statName",
    crit = "critName",
    mast = "mastName",
}
local CATEGORY_SOURCE_FIELD = {
    sta  = "staSource",
    stat = "statSource",
    crit = "critSource",
    mast = "mastSource",
}

local function BuildCategorySourceLines(key)
    local nameField = CATEGORY_NAME_FIELD[key]
    local sourceField = CATEGORY_SOURCE_FIELD[key]
    local lines = {}
    local seen = {}
    local unknown = {}
    for _, fullName in ipairs(ARC.order) do
        local e = ARC.roster[fullName]
        local buffName = e and e.auraDataAvailable and e[nameField]
        local sourceName = e and e.auraDataAvailable and e[sourceField]
        local signature = sourceName and (sourceName .. "\031" .. (buffName or ""))
        if signature and not seen[signature] then
            seen[signature] = true
            local sourceEntry = ARC.roster[sourceName]
            local displayName = sourceEntry and sourceEntry.name or sourceName
            local r, g, b = ClassColor(sourceEntry and sourceEntry.class)
            lines[#lines + 1] = {
                text = string.format("%s - %s", displayName, buffName), r = r, g = g, b = b,
            }
        elseif buffName and not sourceName and not unknown[buffName] then
            unknown[buffName] = true
            lines[#lines + 1] = {
                text = string.format("Unknown source - %s", buffName), r = 0.6, g = 0.6, b = 0.6,
            }
        end
    end
    table.sort(lines, function(a, b) return a.text < b.text end)
    return lines
end

local function AttachHeaderCategoryTooltip(header, col)
    local hit = CreateFrame("Frame", nil, header)
    hit:SetPoint("TOPLEFT", col.x, 0)
    hit:SetSize(col.w, HEADER_HEIGHT)
    hit:EnableMouse(true)
    hit:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(CATEGORY_TITLES[col.key], 1, 1, 1)
        local lines = BuildCategorySourceLines(col.key)
        if #lines == 0 then
            GameTooltip:AddLine("No source in raid yet", 0.6, 0.6, 0.6)
        else
            for _, line in ipairs(lines) do
                GameTooltip:AddLine(line.text, line.r, line.g, line.b)
            end
        end
        GameTooltip:Show()
    end)
    hit:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

local function CreateHeader(parent)
    local header = CreateFrame("Frame", nil, parent)
    header:SetPoint("TOPLEFT", 8, -6)
    header:SetSize(FRAME_WIDTH - 16, HEADER_HEIGHT)
    header.labels = {}

    for _, col in ipairs(COLS) do
        if col.label ~= "" then
            local fs = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            fs:SetPoint("TOPLEFT", col.x, 0)
            fs:SetWidth(col.w)
            fs:SetJustifyH("CENTER")
            fs:SetText(col.label)
            header.labels[#header.labels + 1] = fs
        end
        if CATEGORY_TITLES[col.key] then
            AttachHeaderCategoryTooltip(header, col)
        end
    end

    local line = header:CreateTexture(nil, "ARTWORK")
    line:SetTexture(1, 1, 1, 1)
    line:SetVertexColor(1, 1, 1, 0.15)
    line:SetPoint("BOTTOMLEFT", 0, -2)
    line:SetPoint("BOTTOMRIGHT", 0, -2)
    line:SetHeight(1)
    header.line = line

    return header
end

local function SetRoleIcon(tex, role)
    if role == "TANK" or role == "HEALER" or role == "DAMAGER" then
        -- This is the atlas used by Blizzard's MoP compact-unit frames. The
        -- old UI-LFG-ICON-ROLES texture has different geometry and appeared
        -- offset/cropped when combined with the small-circle coordinates.
        tex:SetTexture("Interface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES")
        local ok = pcall(function()
            tex:SetTexCoord(GetTexCoordsForRoleSmallCircle(role))
        end)
        if not ok then
            tex:SetTexture(nil)
            tex:Hide()
            if tex.backdrop then tex.backdrop:Hide() end
            return
        end
        tex:Show()
        if tex.backdrop then tex.backdrop:Show() end
    else
        tex:SetTexture(nil)
        tex:Hide()
        if tex.backdrop then tex.backdrop:Hide() end
    end
end

local function SetReadyIcon(tex, status)
    if status == "ready" then
        tex:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
        tex:SetTexCoord(0, 1, 0, 1)
        tex:Show()
        if tex.backdrop then tex.backdrop:Show() end
    elseif status == "notready" then
        tex:SetTexture("Interface\\RaidFrame\\ReadyCheck-NotReady")
        tex:SetTexCoord(0, 1, 0, 1)
        tex:Show()
        if tex.backdrop then tex.backdrop:Show() end
    elseif status == "waiting" then
        tex:SetTexture("Interface\\RaidFrame\\ReadyCheck-Waiting")
        tex:SetTexCoord(0, 1, 0, 1)
        tex:Show()
        if tex.backdrop then tex.backdrop:Show() end
    else
        tex:SetTexture(nil)
        tex:Hide()
        if tex.backdrop then tex.backdrop:Hide() end
    end
end

local function SetPresenceIcon(tex, present, icon)
    if tex.backdrop then tex.backdrop:Show() end
    if present and icon then
        tex:SetTexture(icon)
        tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        tex:SetDesaturated(false)
        tex:SetAlpha(1)
    else
        tex:SetTexture(ICON_MISSING)
        tex:SetTexCoord(0, 1, 0, 1)
        tex:SetDesaturated(false)
        tex:SetAlpha(0.9)
    end
end

local function SetUnknownPresenceIcon(tex)
    if tex.backdrop then tex.backdrop:Show() end
    tex:SetTexture(ICON_BLANK)
    tex:SetTexCoord(0, 1, 0, 1)
    tex:SetDesaturated(true)
    tex:SetAlpha(0.35)
end

local function GetEntryVisualState(e)
    if e.online == false then return "offline" end
    if e.dead then return "dead" end
    if not e.auraDataAvailable or ((not e.gear or not e.gear.scanned) and e.inspectable == false) then
        return "range"
    end
    if not e.gear or not e.gear.scanned or e.gear.validationPending then return "waiting" end
    return "normal"
end

local function ApplyRowVisualState(row, e, index)
    local state = GetEntryVisualState(e)
    row:SetAlpha(1)
    if state == "offline" then
        row.bg:SetVertexColor(0.35, 0.35, 0.35, 0.22)
        row:SetAlpha(0.32)
    elseif state == "dead" then
        row.bg:SetVertexColor(0.9, 0.08, 0.08, 0.22)
        row:SetAlpha(0.88)
    elseif state == "range" then
        row.bg:SetVertexColor(0.55, 0.55, 0.55, 0.13)
        row:SetAlpha(0.68)
    elseif state == "waiting" then
        row.bg:SetVertexColor(1, 0.72, 0.08, 0.16)
        row:SetAlpha(0.92)
    elseif index % 2 == 0 then
        row.bg:SetVertexColor(1, 1, 1, 0.03)
    else
        row.bg:SetVertexColor(1, 1, 1, 0)
    end
end

--=============================================================================
-- TOOLTIP BUFF-TEXT SCANNING
-- Reads the EXACT tooltip text (e.g. "+300 Intellect and 300 Stamina") for a
-- unit's flask/food buff. Only ever called while a tooltip is being shown
-- (i.e. on hover), never during the once-a-second refresh, so it costs
-- nothing the rest of the time.
--=============================================================================

local ARCScanTip = CreateFrame("GameTooltip", "ARCScanTooltip", nil, "GameTooltipTemplate")

local function GetBuffTooltipDetail(unit, matchName)
    if not unit or not matchName or not UnitExists(unit) then return nil end
    for i = 1, 40 do
        local name = UnitBuff(unit, i)
        if not name then break end
        if name == matchName then
            ARCScanTip:SetOwner(UIParent, "ANCHOR_NONE")
            ARCScanTip:ClearLines()
            ARCScanTip:SetUnitBuff(unit, i)
            local detail = nil
            for line = 2, ARCScanTip:NumLines() do
                local fs = _G["ARCScanTooltipTextLeft" .. line]
                local text = fs and fs:GetText()
                if text and text ~= "" then
                    detail = detail and (detail .. " " .. text) or text
                end
            end
            ARCScanTip:Hide()
            return detail
        end
    end
    return nil
end

--=============================================================================
-- RIGHT-CLICK CONTEXT MENU (Whisper / Inspect / Remind)
--=============================================================================

-- Sends a friendly whisper listing only what a player can personally fix
-- (flask/food) - deliberately not the raid-buff categories, since those
-- aren't something an individual player controls by using an item.
function ARC:RemindPlayer(e)
    if not e or not e.name then return end
    if e.online == false or not e.auraDataAvailable then
        print("|cff33ff99ARC:|r Cannot verify " .. e.name .. " while their aura data is unavailable.")
        return
    end
    local missing = {}
    if not e.flask then missing[#missing + 1] = "flask" end
    if not e.food then missing[#missing + 1] = "food" end
    if #missing == 0 then
        print("|cff33ff99ARC:|r " .. e.name .. " already has flask and food.")
        return
    end
    local msg = "Hey, quick heads up from ARC - you're missing " ..
        table.concat(missing, " and ") .. ". Might want to grab that before we pull!"
    SendChatMessage(msg, "WHISPER", nil, e.fullName or e.name)
    print("|cff33ff99ARC:|r Reminder sent to " .. e.name .. ".")
end

local ARCRowDropDown = CreateFrame("Frame", "ARCRowDropDown", UIParent, "UIDropDownMenuTemplate")

local function BuildPlayerMenu(e)
    local isSelf = e.unit and UnitIsUnit(e.unit, "player")
    local menu = {
        { text = e.name, isTitle = true, notCheckable = true },
    }
    if not isSelf then
        menu[#menu + 1] = {
            text = "Whisper",
            notCheckable = true,
            func = function() ChatFrame_SendTell(e.fullName or e.name, DEFAULT_CHAT_FRAME) end,
        }
        menu[#menu + 1] = {
            text = "Inspect",
            notCheckable = true,
            func = function()
                if e.unit and UnitExists(e.unit) then InspectUnit(e.unit) end
            end,
        }
        local checkItem = ARC.CreatePlayerCheckMenuItem and ARC:CreatePlayerCheckMenuItem(e.unit, e.fullName)
        if checkItem then menu[#menu + 1] = checkItem end
        menu[#menu + 1] = {
            text = "Remind (missing consumables)",
            notCheckable = true,
            func = function() ARC:RemindPlayer(e) end,
        }
    end
    menu[#menu + 1] = { text = "Close menu", notCheckable = true }
    return menu
end

local function AddGearTooltip(e)
    local gear = e.gear
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Gear check", 1, 0.82, 0)
    if not gear or not gear.scanned then
        GameTooltip:AddLine("Waiting for inspect data", 0.6, 0.6, 0.6)
        return
    end

    local minLevel = (ARC_DB and ARC_DB.minItemLevel) or 450
    if gear.issueCount == 0 and gear.auditComplete then
        GameTooltip:AddLine("No issues found under ARC gear rules", 0.2, 1, 0.2)
    end
    if gear.missingGems > 0 then
        GameTooltip:AddLine("Missing gems: " .. gear.missingGems .. " (" ..
            table.concat(gear.missingGemSlots, ", ") .. ")", 1, 0.25, 0.25, true)
    end
    if #gear.missingEnchants > 0 then
        GameTooltip:AddLine("Missing enchants: " .. table.concat(gear.missingEnchants, ", "), 1, 0.25, 0.25, true)
    end
    for _, text in ipairs(gear.badGems or {}) do GameTooltip:AddLine(text, 1, 0.35, 0.2, true) end
    for _, text in ipairs(gear.badEnchants or {}) do GameTooltip:AddLine(text, 1, 0.35, 0.2, true) end
    for _, text in ipairs(gear.unverified or {}) do GameTooltip:AddLine("Unverified: " .. text, 1, 0.78, 0.2, true) end
    if #gear.wrongPrimary > 0 then
        GameTooltip:AddLine("Wrong primary stat (expected " .. (gear.expectedPrimary or "?") .. "):", 1, 0.35, 0.2)
        for _, text in ipairs(gear.wrongPrimary) do
            GameTooltip:AddLine("  " .. text, 1, 0.5, 0.35, true)
        end
    end
    if #gear.lowItems > 0 then
        GameTooltip:AddLine("Items below " .. minLevel .. ":", 1, 0.35, 0.2)
        for _, item in ipairs(gear.lowItems) do
            GameTooltip:AddLine(string.format("  %s: %s (iLvl %d)", item.label, item.name, item.ilvl), 1, 0.5, 0.35, true)
        end
    end
    if #gear.missingItems > 0 then
        GameTooltip:AddLine("Empty required slots: " .. table.concat(gear.missingItems, ", "), 1, 0.25, 0.25, true)
    end
end

local function CreateRow(parent, index)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(FRAME_WIDTH - 16, ROW_HEIGHT)

    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()
    row.bg:SetTexture(1, 1, 1, 1)
    if index % 2 == 0 then
        row.bg:SetVertexColor(1, 1, 1, 0.03)
    else
        row.bg:SetVertexColor(1, 1, 1, 0)
    end

    row.highlight = row:CreateTexture(nil, "HIGHLIGHT")
    row.highlight:SetAllPoints()
    row.highlight:SetTexture(1, 1, 1, 0.08)

    row.divider = row:CreateTexture(nil, "ARTWORK")
    row.divider:SetPoint("BOTTOMLEFT", 0, 0)
    row.divider:SetPoint("BOTTOMRIGHT", 0, 0)
    row.divider:SetHeight(1)
    row.divider:SetTexture(1, 1, 1, 0.05)

    row.icons = {}
    row.textFields = {}

    for _, col in ipairs(COLS) do
        if col.kind == "icon" then
            local size = col.iconSize or 16
            local tex = row:CreateTexture(nil, "ARTWORK")
            tex:SetSize(size, size)
            tex:SetPoint("LEFT", col.x + (col.w - size) / 2, 0)
            row[col.key] = tex
            row.icons[col.key] = tex
        else
            local fs = row:CreateFontString(nil, "ARTWORK",
                col.key == "name" and "GameFontNormalSmall" or "GameFontHighlightSmall")
            fs:SetPoint("LEFT", col.x, 0)
            fs:SetWidth(col.w)
            fs:SetJustifyH(col.justify or "CENTER")
            row[col.key] = fs
            row.textFields[#row.textFields + 1] = fs
        end
    end

    row:EnableMouse(true)
    row:SetScript("OnEnter", function(self)
        if not self.fullName then return end
        local e = ARC.roster[self.fullName]
        if not e then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(e.name, 1, 1, 1)
        local visualState = GetEntryVisualState(e)
        if visualState == "offline" then
            GameTooltip:AddLine("Status: Offline", 0.55, 0.55, 0.55)
        elseif visualState == "dead" then
            GameTooltip:AddLine("Status: Dead or ghost", 1, 0.25, 0.25)
        elseif visualState == "range" then
            GameTooltip:AddLine("Status: Aura/inspect data out of range", 0.7, 0.7, 0.7)
        elseif visualState == "waiting" then
            GameTooltip:AddLine("Status: Waiting for inspect data", 1, 0.78, 0.2)
        else
            GameTooltip:AddLine("Status: Data available", 0.3, 1, 0.4)
        end
        if e.specName then GameTooltip:AddLine(e.specName, 0.8, 0.8, 1) end
        if e.specSource == "inspect" then
            GameTooltip:AddLine("(spec via inspect - may be stale)", 0.6, 0.6, 0.6)
        elseif e.specSource == "comm" then
            GameTooltip:AddLine("(reported by their ARC)", 0.6, 0.6, 0.6)
        end
        if e.hasARC then
            GameTooltip:AddLine("ARC installed" .. (e.arcVersion and (" - version " .. e.arcVersion) or ""), 0.2, 1, 0.7)
        else
            GameTooltip:AddLine("ARC not detected", 0.55, 0.55, 0.55)
        end

        if e.flask then
            local flaskName = e.flaskName
            if flaskName then
                local detail = GetBuffTooltipDetail(e.unit, flaskName)
                GameTooltip:AddLine(flaskName .. (detail and (" - " .. detail) or ""), 0.6, 0.9, 1)
            end
        end
        if e.food then
            local foodName = e.foodName
            local detail = foodName and GetBuffTooltipDetail(e.unit, foodName)
            GameTooltip:AddLine("Food: " .. (detail or foodName or "Well Fed"), 1, 0.82, 0)
        end

        local raidBuffs = {}
        if e.staName then raidBuffs[#raidBuffs + 1] = e.staName end
        if e.statName then raidBuffs[#raidBuffs + 1] = e.statName end
        if e.critName then raidBuffs[#raidBuffs + 1] = e.critName end
        if e.mastName then raidBuffs[#raidBuffs + 1] = e.mastName end
        if #raidBuffs > 0 then
            GameTooltip:AddLine("Raid buffs: " .. table.concat(raidBuffs, ", "), 0.7, 0.9, 0.7)
        end

        if e.ilvlApprox then
            GameTooltip:AddLine("Item level is an estimate (no ARC on their end)", 0.6, 0.6, 0.6)
        end
        if e.hasARC and e.durPct then
            GameTooltip:AddLine(string.format("Durability: %d%% average, %d%% lowest item",
                e.durPct, e.durWorst or e.durPct), 0.8, 0.8, 0.8)
        else
            GameTooltip:AddLine("Durability unavailable - the WoW API exposes no remote value or reliable estimate", 0.6, 0.6, 0.6, true)
        end
        AddGearTooltip(e)
        if ARC.GetTalentStatus then
            local status, tone, details = ARC:GetTalentStatus(e)
            GameTooltip:AddLine("Talents: " .. status, 1, 0.82, 0)
            for _, detail in ipairs(details) do GameTooltip:AddLine(detail, 1, tone == "bad" and 0.25 or 0.78, 0.2, true) end
        end
        if ARC.GetSelfBuffStatus then
            local status, tone, details = ARC:GetSelfBuffStatus(e)
            GameTooltip:AddLine("Self / tank / pet readiness: " .. status, 1, 0.82, 0)
            for _, detail in ipairs(details) do GameTooltip:AddLine(detail, 1, tone == "bad" and 0.25 or 0.78, 0.2, true) end
        end
        if ARC.GetHealthstoneStatus then
            local _, tone, detail = ARC:GetHealthstoneStatus(e)
            GameTooltip:AddLine(detail, 1, tone == "bad" and 0.25 or 0.78, 0.2, true)
        end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Right-click for options", 0.5, 0.5, 0.5)
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row:SetScript("OnMouseUp", function(self, button)
        if button ~= "RightButton" then return end
        if not self.fullName then return end
        local e = ARC.roster[self.fullName]
        if not e then return end
        GameTooltip:Hide()
        EasyMenu(BuildPlayerMenu(e), ARCRowDropDown, "cursor", 0, 0, "MENU")
    end)

    return row
end

-- Plain (non-ElvUI) window skin: a solid backdrop at ~70% opacity so the
-- roster is easy to read against any background. This is applied as the
-- baseline every time the frame is built, so the window ALWAYS has a
-- visible background even if ElvUI skinning below fails partway through.
local BACKDROP_INFO = {
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 11, right = 11, top = 11, bottom = 11 },
}

local function ApplyDefaultSkin(f)
    if not f.SetBackdrop then return end
    f:SetBackdrop(BACKDROP_INFO)
    f:SetBackdropColor(0, 0, 0, 0.7)       -- ~70% opaque black background
    f:SetBackdropBorderColor(1, 1, 1, 1)   -- fully opaque border
end

local ELVUI_BORDERED_ICONS = { "role", "spec", "flask", "food", "sta", "stat", "crit", "mast" }

local function ApplyElvUIFont(fontString, E, size)
    if not fontString or not fontString.FontTemplate then return end
    local font = E.media and E.media.normFont
    pcall(fontString.FontTemplate, fontString, font, size)
end

function ARC:SkinRowElvUI(row, E)
    if not row or row.elvuiSkinned then return end
    E = E or self.elvuiEngine
    if not E or not E.media then return end

    local blank = E.media.blankTex or "Interface\\Buttons\\WHITE8X8"
    local border = E.media.bordercolor or { 0, 0, 0 }
    local value = E.media.rgbvaluecolor or { 0.2, 0.8, 1 }

    row.bg:SetTexture(blank)
    row.highlight:SetTexture(blank)
    row.highlight:SetVertexColor(value[1] or 1, value[2] or 1, value[3] or 1, 0.10)
    row.divider:SetTexture(blank)
    row.divider:SetVertexColor(border[1] or 0, border[2] or 0, border[3] or 0, 0.45)

    for _, fontString in ipairs(row.textFields or {}) do
        ApplyElvUIFont(fontString, E, 11)
    end

    for _, key in ipairs(ELVUI_BORDERED_ICONS) do
        local texture = row.icons and row.icons[key]
        if texture and texture.CreateBackdrop and not texture.backdrop then
            pcall(texture.CreateBackdrop, texture, "Default", true)
        end
        if texture and texture.backdrop and texture.backdrop.SetBackdropBorderColor then
            texture.backdrop:SetBackdropBorderColor(border[1] or 0, border[2] or 0, border[3] or 0)
        end
    end

    row.elvuiSkinned = true
end

-- Attempts to skin the ARC window with ElvUI's own Skins module so it
-- matches the rest of the ElvUI-skinned UI. Completely optional and safe if
-- ElvUI isn't installed, or if its Skins API differs on a given fork/version.
--
-- Every optional ElvUI operation is isolated with pcall. A fork missing one
-- button/font helper must not undo a successfully applied main-frame template.
function ARC:TrySkinElvUI()
    local f = ARC.frame
    if not f or f.elvuiSkinned then return end
    if not (IsAddOnLoaded and IsAddOnLoaded("ElvUI")) then return end
    if not ElvUI then return end

    local E = ElvUI[1]
    if not E or not E.GetModule then return end

    local moduleOK, S = pcall(E.GetModule, E, "Skins")
    if not moduleOK then S = nil end

    -- ElvUI 2.76 exposes its frame templates directly through the widget
    -- toolkit. Some later forks additionally provide Skins:HandleFrame, so
    -- retain that as a fallback instead of requiring it.
    local frameOK = false
    if f.SetTemplate then
        frameOK = pcall(f.SetTemplate, f, "Transparent")
    elseif S and S.HandleFrame then
        frameOK = pcall(S.HandleFrame, S, f)
    end
    if not frameOK then
        -- Core skin failed - leave the default ~70%-opacity skin in place
        -- (it's already applied from BuildMainFrame) and try again next
        -- time ARC shows, in case ElvUI just wasn't fully ready yet.
        return
    end

    f.elvuiSkinned = true
    ARC.elvuiActive = true
    ARC.elvuiEngine = E

    if f.header and f.header.SetTemplate then
        pcall(f.header.SetTemplate, f.header, "Default", true)
    end

    local border = E.media and E.media.bordercolor or { 0, 0, 0 }
    local value = E.media and E.media.rgbvaluecolor or { 0.2, 0.8, 1 }
    local blank = E.media and E.media.blankTex or "Interface\\Buttons\\WHITE8X8"
    if f.header and f.header.line then
        f.header.line:SetTexture(blank)
        f.header.line:SetVertexColor(border[1] or 0, border[2] or 0, border[3] or 0, 0.8)
    end

    ApplyElvUIFont(f.title, E, 13)
    if f.title then
        f.title:SetTextColor(value[1] or 1, value[2] or 0.82, value[3] or 0)
    end
    ApplyElvUIFont(f.summary, E, 11)
    if f.raidBanner then ApplyElvUIFont(f.raidBanner.label, E, 12) end
    ApplyElvUIFont(f.hint, E, 10)
    if f.header then
        for _, fontString in ipairs(f.header.labels or {}) do
            ApplyElvUIFont(fontString, E, 11)
            fontString:SetTextColor(value[1] or 1, value[2] or 0.82, value[3] or 0)
        end
    end

    if f.closeButton and S and S.HandleCloseButton then
        pcall(S.HandleCloseButton, S, f.closeButton)
    end
    for _, button in ipairs({ f.announce, f.readyYes, f.readyNo }) do
        if S and S.HandleButton then pcall(S.HandleButton, S, button) end
        if button.GetFontString then ApplyElvUIFont(button:GetFontString(), E, 11) end
    end

    for _, row in ipairs(f.rows or {}) do
        self:SkinRowElvUI(row, E)
    end
end

function ARC:CanRespondReadyCheck()
    if not self.readyCheckActive or self.readyCheckResponded or not ConfirmReadyCheck or not GetReadyCheckStatus then return false end
    if self.readyCheckExpiresAt and GetTime() >= self.readyCheckExpiresAt then return false end
    local seconds = GetReadyCheckSecondsLeft()
    if seconds ~= nil and seconds <= 0 then return false end
    return GetReadyCheckStatus("player") == "waiting"
end

function ARC:UpdateReadyButtons()
    local f = self.frame
    if not f or not f.readyYes then return end
    for _, button in ipairs({ f.readyYes, f.readyNo }) do
        if self:CanRespondReadyCheck() then button:Enable() else button:Disable() end
    end
end

function ARC:RespondReadyCheck(ready)
    if not self:CanRespondReadyCheck() then self:UpdateReadyButtons(); return end
    -- Legacy MoP API uses 1 for ready and nil for not ready (not numeric 0).
    -- Only this hardware-click callback sends a response; never auto-answer.
    self.readyCheckResponded = true
    local ok = pcall(ConfirmReadyCheck, ready and 1 or nil)
    if not ok then
        self.readyCheckResponded = false
        print("|cff33ff99ARC:|r Could not respond; use the Blizzard ready-check dialog.")
    elseif ReadyCheckFrame then
        ReadyCheckFrame:Hide()
    end
    self:UpdateReadyButtons()
end

local function BuildMainFrame()
    -- NOTE: no "BackdropTemplate" here on purpose - that mixin didn't exist
    -- until patch 8.0. On 5.4.8, SetBackdrop is a native Frame method, so a
    -- plain frame is all we need (and passing that template name here would
    -- throw a "Unknown template" error on this client).
    local f = CreateFrame("Frame", "ARCFrame", UIParent)
    f:SetSize(FRAME_WIDTH, 200)
    f:SetFrameStrata("HIGH")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self)
        if not ARC_DB.locked then self:StartMoving() end
    end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relPoint, x, y = self:GetPoint()
        ARC_DB.point = { point, "UIParent", relPoint, x, y }
    end)

    -- Always apply the default ~70%-opacity skin as a baseline. If ElvUI is
    -- loaded, ARC:TrySkinElvUI() (called right after this frame is created)
    -- will visually replace it - but the window is never left without a
    -- background, even for one frame or if ElvUI skinning fails.
    ApplyDefaultSkin(f)

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", 12, -12)
    title:SetWidth(430)
    title:SetJustifyH("LEFT")
    title:SetText("ARC - Ready Check Overview")
    f.title = title

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)
    close:SetScript("OnClick", function() ARC:Hide() end)
    f.closeButton = close

    f.readyNo = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.readyNo:SetSize(90, 22)
    f.readyNo:SetPoint("TOPRIGHT", -40, -12)
    f.readyNo:SetText("Not Ready")
    f.readyNo:SetScript("OnClick", function() ARC:RespondReadyCheck(false) end)
    f.readyNo:Disable()
    f.readyYes = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.readyYes:SetSize(78, 22)
    f.readyYes:SetPoint("RIGHT", f.readyNo, "LEFT", -6, 0)
    f.readyYes:SetText("Ready")
    f.readyYes:SetScript("OnClick", function() ARC:RespondReadyCheck(true) end)
    f.readyYes:Disable()

    local banner = CreateFrame("Button", nil, f)
    banner:SetPoint("TOPLEFT", 12, -52)
    banner:SetPoint("TOPRIGHT", -12, -52)
    banner:SetHeight(48)
    banner.bg = banner:CreateTexture(nil, "BACKGROUND")
    banner.bg:SetAllPoints()
    banner.bg:SetTexture(1, 1, 1, 1)
    banner.label = banner:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    banner.label:SetPoint("TOPLEFT", 8, -4)
    banner.label:SetPoint("BOTTOMRIGHT", -8, 4)
    banner.label:SetJustifyH("LEFT")
    banner.label:SetWordWrap(true)
    banner:SetScript("OnClick", function() ARC:OpenRaidOptions() end)
    f.raidBanner = banner

    local summary = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    summary:SetPoint("TOPLEFT", 12, -110)
    summary:SetPoint("TOPRIGHT", -12, -110)
    summary:SetJustifyH("LEFT")
    f.summary = summary

    local scroll = CreateFrame("Frame", nil, f)
    scroll:SetPoint("TOPLEFT", 8, -TOP_OFFSET)
    scroll:SetPoint("TOPRIGHT", -8, -TOP_OFFSET)
    f.rowsContainer = scroll

    f.header = CreateHeader(f)
    f.header:SetPoint("TOPLEFT", 8, -132)

    f.announce = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.announce:SetSize(150, 20)
    f.announce:SetPoint("BOTTOMLEFT", 10, 8)
    f.announce:SetText("Announce Missing")
    f.announce:SetScript("OnClick", function() ARC:AnnounceMissing() end)

    local hint = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("BOTTOMRIGHT", -10, 10)
    hint:SetText("/arc for help")
    f.hint = hint

    f.rows = {}
    f:Hide()
    return f
end

--=============================================================================
-- RENDERING
--=============================================================================

function ARC:EnsureRow(i)
    local f = self.frame
    local row = f.rows[i]
    if not row then
        row = CreateRow(f.rowsContainer, i)
        row:SetPoint("TOPLEFT", f.rowsContainer, "TOPLEFT", 0, -(i - 1) * ROW_HEIGHT)
        row:SetPoint("TOPRIGHT", f.rowsContainer, "TOPRIGHT", 0, -(i - 1) * ROW_HEIGHT)
        f.rows[i] = row
        if self.elvuiActive then self:SkinRowElvUI(row) end
    end
    return row
end

local function FormatIlvl(e)
    if not e.ilvl or e.ilvl == 0 then return "-" end
    if e.ilvlApprox then return "~" .. e.ilvl end
    return tostring(e.ilvl)
end

local function FormatDur(e)
    if not e.hasARC or not e.durPct then return "N/A" end
    return (e.durWorst or e.durPct) .. "%"
end

local function FormatGear(e)
    if not e.gear or not e.gear.scanned then return "..." end
    if e.gear.issueCount == 0 then return e.gear.auditComplete and "OK" or "?" end
    return "!" .. e.gear.issueCount
end

local function FormatPlayerName(e, fallbackName)
    local name = e.name or fallbackName
    if e.online == false then
        return name .. " (off)"
    elseif e.dead then
        return name .. " (dead)"
    end
    return name
end

-- Builds the "(N seconds remaining)" / "(Finished)" suffix on the title bar.
local function UpdateTitleText()
    local f = ARC.frame
    if not f or not f.title then return end
    local text = "ARC - Ready Check Overview"
    if ARC.readyCheckActive then
        local left = GetReadyCheckSecondsLeft()
        if left == nil then
            text = text .. " (in progress)"
        elseif left > 0 then
            text = text .. string.format(" (%d second%s remaining)", left, left == 1 and "" or "s")
        else
            text = text .. " (Finished)"
        end
    elseif ARC.readyCheckFinished then
        text = text .. " (Finished)"
    end
    f.title:SetText(text)
end

local function ReadinessCell(widget, text, tone)
    widget:SetText(text)
    if text == "-" then widget:SetTextColor(0.55, 0.55, 0.55)
    elseif tone == "bad" then widget:SetTextColor(1, 0.25, 0.25)
    elseif tone == "warn" then widget:SetTextColor(1, 0.78, 0.2)
    else widget:SetTextColor(0.2, 1, 0.2) end
end

function ARC:Render()
    local f = self.frame
    if not f or not f:IsShown() then return end

    UpdateTitleText()
    self:UpdateReadyButtons()
    local setupText, setupTone = self:GetRaidSetupStatus()
    f.raidBanner.label:SetText(setupText)
    if setupTone == "bad" then
        f.raidBanner.bg:SetVertexColor(0.8, 0.04, 0.04, 0.9)
        f.raidBanner.label:SetTextColor(1, 1, 1)
    elseif setupTone == "warn" then
        f.raidBanner.bg:SetVertexColor(0.55, 0.34, 0.02, 0.8)
        f.raidBanner.label:SetTextColor(1, 0.9, 0.45)
    else
        f.raidBanner.bg:SetVertexColor(0.08, 0.23, 0.19, 0.65)
        f.raidBanner.label:SetTextColor(0.7, 0.9, 0.8)
    end

    local total, ready, missingFlask, missingFood, gearIssues, arcUsers = 0, 0, 0, 0, 0, 0
    local talentIssues, selfBuffIssues, stoneIssues = 0, 0, 0

    for i, name in ipairs(self.order) do
        local e = self.roster[name]
        local row = self:EnsureRow(i)
        row.fullName = name
        row:Show()

        total = total + 1
        if e.ready == "ready" then ready = ready + 1 end
        if e.auraDataAvailable and not e.flask then missingFlask = missingFlask + 1 end
        if e.auraDataAvailable and not e.food then missingFood = missingFood + 1 end
        if e.gear and e.gear.scanned and e.gear.issueCount and e.gear.issueCount > 0 then gearIssues = gearIssues + 1 end
        if e.hasARC then arcUsers = arcUsers + 1 end

        SetReadyIcon(row.ready, e.ready)
        SetRoleIcon(row.role, e.role)

        if e.specIcon then
            row.spec:SetTexture(e.specIcon)
            row.spec:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            row.spec:Show()
            if row.spec.backdrop then row.spec.backdrop:Show() end
        else
            row.spec:SetTexture(nil)
            row.spec:Hide()
            if row.spec.backdrop then row.spec.backdrop:Hide() end
        end

        local r, g, b = ClassColor(e.class)
        row.name:SetText(FormatPlayerName(e, name))
        row.name:SetTextColor(r, g, b)

        if e.auraDataAvailable then
            SetPresenceIcon(row.flask, e.flask, e.flaskIcon)
            SetPresenceIcon(row.food, e.food, e.foodIcon)
            SetPresenceIcon(row.sta, e.sta, e.staIcon or (e.sta and "Interface\\Icons\\Spell_Holy_WordFortitude"))
            SetPresenceIcon(row.stat, e.stat, e.statIcon or (e.stat and "Interface\\Icons\\Spell_Magic_GreaterBlessingOfKings"))
            SetPresenceIcon(row.crit, e.crit, e.critIcon or (e.crit and "Interface\\Icons\\Ability_Druid_ChallangingRoar"))
            SetPresenceIcon(row.mast, e.mast, e.mastIcon or (e.mast and "Interface\\Icons\\Ability_Paladin_SheathofLight"))
        else
            SetUnknownPresenceIcon(row.flask)
            SetUnknownPresenceIcon(row.food)
            SetUnknownPresenceIcon(row.sta)
            SetUnknownPresenceIcon(row.stat)
            SetUnknownPresenceIcon(row.crit)
            SetUnknownPresenceIcon(row.mast)
        end

        row.ilvl:SetText(FormatIlvl(e))

        local durText = FormatDur(e)
        row.dur:SetText(durText)
        if e.hasARC and e.durPct then
            row.dur:SetTextColor(DurabilityColor(e.durWorst or e.durPct))
        else
            row.dur:SetTextColor(0.5, 0.5, 0.5)
        end

        row.gear:SetText(FormatGear(e))
        if e.gear and e.gear.auditComplete and e.gear.issueCount == 0 then
            row.gear:SetTextColor(0.2, 1, 0.2)
        elseif e.gear and e.gear.scanned and e.gear.issueCount and e.gear.issueCount > 0 then
            row.gear:SetTextColor(1, 0.25, 0.25)
        elseif e.gear and e.gear.scanned then
            row.gear:SetTextColor(1, 0.78, 0.2)
        else
            row.gear:SetTextColor(0.6, 0.6, 0.6)
        end

        row.arc:SetText(e.hasARC and "Yes" or "-")
        local talText, talTone = self:GetTalentStatus(e)
        local buffText, buffTone = self:GetSelfBuffStatus(e)
        local stoneText, stoneTone = self:GetHealthstoneStatus(e)
        ReadinessCell(row.tal, talText, talTone)
        ReadinessCell(row.selfBuff, buffText, buffTone)
        ReadinessCell(row.hs, stoneText, stoneTone)
        if talTone == "bad" then talentIssues = talentIssues + 1 end
        if buffTone == "bad" then selfBuffIssues = selfBuffIssues + 1 end
        if stoneTone == "bad" then stoneIssues = stoneIssues + 1 end
        row.arc:SetTextColor(e.hasARC and 0.2 or 0.5, e.hasARC and 1 or 0.5, e.hasARC and 0.7 or 0.5)
        ApplyRowVisualState(row, e, i)
    end

    for i = #self.order + 1, #f.rows do
        f.rows[i]:Hide()
    end

    f.summary:SetText(string.format(
        "|cff55ff55Ready: %d/%d|r  |cffff8888Flask: %d  Food: %d  Gear: %d  Talents: %d  Self: %d  HS: %d|r  |cff55ffbbARC: %d/%d|r",
        ready, total, missingFlask, missingFood, gearIssues, talentIssues, selfBuffIssues, stoneIssues, arcUsers, total
    ))

    local newHeight = TOP_OFFSET + FOOTER_HEIGHT + math.max(#self.order, 1) * ROW_HEIGHT
    f:SetHeight(newHeight)
    f.rowsContainer:SetHeight(math.max(#self.order, 1) * ROW_HEIGHT)
end

--=============================================================================
-- ANNOUNCE MISSING CONSUMABLES
--=============================================================================

function ARC:AnnounceMissing()
    local missing = {}
    local unavailable = 0
    for _, name in ipairs(self.order) do
        local e = self.roster[name]
        if e.online == false or not e.auraDataAvailable then
            unavailable = unavailable + 1
        else
            local tags = {}
            if not e.flask then tags[#tags + 1] = "flask" end
            if not e.food then tags[#tags + 1] = "food" end
            if #tags > 0 then
                missing[#missing + 1] = string.format("%s (%s)", e.name, table.concat(tags, "/"))
            end
        end
    end

    if #missing == 0 then
        local suffix = unavailable > 0 and (" (" .. unavailable .. " player(s) could not be verified.)") or ""
        print("|cff33ff99ARC:|r Everyone with available aura data has flask and food." .. suffix)
        return
    end
    if unavailable > 0 then
        print("|cff33ff99ARC:|r Skipped " .. unavailable .. " player(s) with unavailable aura data.")
    end

    local chatType
    if IsInRaid() and (UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")) then
        chatType = "RAID_WARNING"
    elseif IsInRaid() then
        chatType = "RAID"
    elseif IsInGroup() then
        chatType = "PARTY"
    else
        chatType = nil
    end

    -- Raid chat messages have a 255-byte limit. Split a long 25-player report
    -- on player boundaries so it is never truncated in a worst-case roster.
    local lines, prefix = {}, "Missing consumables - "
    local current = prefix
    for _, entry in ipairs(missing) do
        local separator = current == prefix and "" or ", "
        if #current + #separator + #entry > 240 and current ~= prefix then
            lines[#lines + 1] = current
            current = "Missing consumables (cont.) - " .. entry
        else
            current = current .. separator .. entry
        end
    end
    if current ~= prefix then lines[#lines + 1] = current end

    for _, text in ipairs(lines) do
        if chatType then
            SendChatMessage(text, chatType)
        else
            print("|cff33ff99ARC:|r " .. text)
        end
    end
end

--=============================================================================
-- SHOW / HIDE / TOGGLE
--=============================================================================

function ARC:Show()
    if not self.frame then
        self.frame = BuildMainFrame()
        self:TrySkinElvUI()
    end
    local f = self.frame
    f:ClearAllPoints()
    f:SetPoint(unpack(ARC_DB.point))
    f:SetScale(ARC_DB.scale or 1.0)
    f:Show()
    self:RefreshRoster()
    self:Render()
    self:BroadcastSelf(true)
    self.QueueInspectCandidates()
end

function ARC:Hide()
    if self.frame then self.frame:Hide() end
end

function ARC:Toggle()
    if self.frame and self.frame:IsShown() then
        self:Hide()
    else
        self:Show()
    end
end

function ARC:IsVisible()
    return self.frame and self.frame:IsShown()
end
