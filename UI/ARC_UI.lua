local ARC = assert(_G.ARC, "Core/ARC_Core.lua must load before UI/ARC_UI.lua")
local I = assert(ARC.Internal, "ARC internal API is unavailable")
local ClassColor = I.ClassColor
local DurabilityColor = I.DurabilityColor
local GetReadyCheckSecondsLeft = I.GetReadyCheckSecondsLeft
local function L(key, ...)
    if ARC.Text then return ARC:Text(key, ...) end
    if select("#", ...) > 0 then
        local ok, value = pcall(string.format, key, ...)
        if ok then return value end
    end
    return key
end
local function D(text)
    return ARC.LocalizeDiagnostic and ARC:LocalizeDiagnostic(text) or L(text)
end

function ARC:GetDisplayRoster()
    if self.demoRoster and self.demoOrder then return self.demoRoster, self.demoOrder end
    return self.roster, self.order
end

function ARC:GetDisplayEntry(fullName)
    local roster = self:GetDisplayRoster()
    return roster and roster[fullName]
end
local function LocalizedList(values)
    local localized = {}
    for index, value in ipairs(values or {}) do localized[index] = D(value) end
    return table.concat(localized, ", ")
end

--=============================================================================
-- UI CONSTRUCTION
--=============================================================================

local ROW_HEIGHT    = 26   -- was 22 - main fix for rows crowding/overlapping
local HEADER_HEIGHT = 26
local FOOTER_HEIGHT = 34
local TOP_OFFSET    = 162  -- ready responses, visible raid setup banner, summary, labels
local FRAME_WIDTH   = 872  -- includes room for the roster scrollbar
local ICON_MISSING  = "Interface\\RaidFrame\\ReadyCheck-NotReady"
local ICON_UNKNOWN  = "Interface\\RaidFrame\\ReadyCheck-Waiting"

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
    local roster, order = ARC:GetDisplayRoster()
    for _, fullName in ipairs(order) do
        local e = roster[fullName]
        local buffName = e and e.auraDataAvailable and e[nameField]
        local sourceName = e and e.auraDataAvailable and e[sourceField]
        local signature = sourceName and (sourceName .. "\031" .. (buffName or ""))
        if signature and not seen[signature] then
            seen[signature] = true
            local sourceEntry = roster[sourceName]
            local displayName = sourceEntry and sourceEntry.name or sourceName
            local r, g, b = ClassColor(sourceEntry and sourceEntry.class)
            lines[#lines + 1] = {
                text = string.format("%s - %s", displayName, buffName), r = r, g = g, b = b,
            }
        elseif buffName and not sourceName and not unknown[buffName] then
            unknown[buffName] = true
            lines[#lines + 1] = {
                text = L("Unknown source - %s", buffName), r = 0.6, g = 0.6, b = 0.6,
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
        GameTooltip:AddLine(L(CATEGORY_TITLES[col.key]), 1, 1, 1)
        local lines = BuildCategorySourceLines(col.key)
        if #lines == 0 then
            GameTooltip:AddLine(L("No source in raid yet"), 0.6, 0.6, 0.6)
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
            fs:SetText(L(col.label))
            fs.localeKey = col.label
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
    tex:SetVertexColor(1, 1, 1, 1)
    tex:SetDesaturated(false)
    tex:SetAlpha(1)
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
    tex:SetVertexColor(1, 1, 1, 1)
    tex:SetDesaturated(false)
    tex:SetAlpha(1)
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
    tex:SetVertexColor(1, 1, 1, 1)
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
    tex:SetVertexColor(1, 1, 1, 1)
    if tex.backdrop then tex.backdrop:Show() end
    tex:SetTexture(ICON_UNKNOWN)
    tex:SetTexCoord(0, 1, 0, 1)
    tex:SetDesaturated(false)
    tex:SetAlpha(0.9)
end

local function SetConsumableIcon(tex, entry, key)
    local status = ARC:GetConsumableStatus(entry, key)
    if status == "unknown" then
        SetUnknownPresenceIcon(tex)
    elseif status == "missing" then
        SetPresenceIcon(tex, false)
    else
        SetPresenceIcon(tex, true, entry[key .. "Icon"])
        if status == "expiring" then tex:SetVertexColor(1, 0.72, 0.12, 1) end
        if status == "wrong" then tex:SetVertexColor(1, 0.25, 0.25, 1) end
    end
end

local function FormatRemaining(seconds)
    seconds = math.max(0, math.floor((seconds or 0) + 0.5))
    if seconds >= 60 then return math.floor(seconds / 60) .. "m" end
    return seconds .. "s"
end

local function GetEntryVisualState(e)
    if e.online == false then return "offline" end
    if e.dead then return "dead" end
    if e.afk then return "afk" end
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
    elseif state == "afk" then
        row.bg:SetVertexColor(1, 0.48, 0.05, 0.2)
        row:SetAlpha(0.9)
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

local function GetBuffTooltipDetailUnsafe(unit, matchName)
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

local function GetBuffTooltipDetail(unit, matchName)
    local ok, detail = pcall(GetBuffTooltipDetailUnsafe, unit, matchName)
    pcall(ARCScanTip.Hide, ARCScanTip)
    return ok and detail or nil
end

function ARC:GetConfirmedIssueTags(e)
    local tags = {}
    local flaskStatus, flaskLeft = self:GetConsumableStatus(e, "flask")
    local foodStatus, foodLeft = self:GetConsumableStatus(e, "food")
    if flaskStatus == "missing" then tags[#tags + 1] = "flask"
    elseif flaskStatus == "wrong" then tags[#tags + 1] = L("wrong main-stat flask")
    elseif flaskStatus == "expiring" then tags[#tags + 1] = "flask <" .. FormatRemaining(flaskLeft) end
    if foodStatus == "missing" then tags[#tags + 1] = "food"
    elseif foodStatus == "expiring" then tags[#tags + 1] = "food <" .. FormatRemaining(foodLeft) end
    if e.gear and e.gear.scanned and (e.gear.issueCount or 0) > 0 then
        tags[#tags + 1] = "gear (" .. e.gear.issueCount .. " issue" .. (e.gear.issueCount == 1 and "" or "s") .. ")"
    end
    if select(2, self:GetTalentStatus(e)) == "bad" then tags[#tags + 1] = "talents" end
    if select(2, self:GetSelfBuffStatus(e)) == "bad" then tags[#tags + 1] = "class readiness" end
    if select(2, self:GetHealthstoneStatus(e)) == "bad" then tags[#tags + 1] = "Healthstone" end
    return tags
end

-- Sends one private, concise list containing confirmed personal issues only.
function ARC:RemindPlayer(e)
    if not e or not e.name then return end
    if e.online == false then
        print("|cff33ff99ARC:|r " .. L("Cannot remind %s while they are offline.", e.name))
        return
    end
    local issues = self:GetConfirmedIssueTags(e)
    if #issues == 0 then
        print("|cff33ff99ARC:|r " .. L("No confirmed personal issues for %s.", e.name))
        return
    end
    local msg = L("ARC reminder: %s. Please fix before pull.", table.concat(issues, ", "))
    SendChatMessage(msg, "WHISPER", nil, e.fullName or e.name)
    print("|cff33ff99ARC:|r " .. L("Reminder sent to %s.", e.name))
end

local ARCRowDropDown = CreateFrame("Frame", "ARCRowDropDown", UIParent, "UIDropDownMenuTemplate")

local function BuildPlayerMenu(e)
    local isSelf = e.unit and UnitIsUnit(e.unit, "player")
    local menu = {
        { text = e.name, isTitle = true, notCheckable = true },
    }
    if not isSelf then
        menu[#menu + 1] = {
            text = L("Whisper"),
            notCheckable = true,
            func = function() ChatFrame_SendTell(e.fullName or e.name, DEFAULT_CHAT_FRAME) end,
        }
        menu[#menu + 1] = {
            text = L("Inspect"),
            notCheckable = true,
            func = function()
                if e.unit and UnitExists(e.unit) then InspectUnit(e.unit) end
            end,
        }
        menu[#menu + 1] = {
            text = L("Remind (confirmed issues)"),
            notCheckable = true,
            func = function() ARC:RemindPlayer(e) end,
        }
    end
    local checkItem = ARC.CreatePlayerCheckMenuItem and ARC:CreatePlayerCheckMenuItem(e.unit, e.fullName)
    if checkItem then menu[#menu + 1] = checkItem end
    menu[#menu + 1] = { text = L("Close menu"), notCheckable = true }
    return menu
end

local function AddGearTooltip(e)
    local gear = e.gear
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(L("Gear check"), 1, 0.82, 0)
    if e.professionsKnown and type(e.professions) == "table" and
        (e.professionSource ~= "comm" or (e.professionAt and GetTime() - e.professionAt <= 120)) then
        local names, catalog = {}, ARC.GEAR_RULES and ARC.GEAR_RULES.professions or {}
        for id in pairs(e.professions) do names[#names + 1] = catalog[id] or tostring(id) end
        table.sort(names)
        GameTooltip:AddLine(L("Professions: %s", #names > 0 and table.concat(names, ", ") or L("none reported")), 0.7, 0.85, 1, true)
    end
    if not gear or not gear.scanned then
        GameTooltip:AddLine(L("Waiting for inspect data"), 0.6, 0.6, 0.6)
        return
    end

    local minLevel = (ARC_DB and ARC_DB.minItemLevel) or 450
    if gear.issueCount == 0 and gear.auditComplete then
        GameTooltip:AddLine(L("No issues found under ARC gear rules"), 0.2, 1, 0.2)
    end
    if gear.missingGems > 0 then
        GameTooltip:AddLine(L("Missing gems: %d (%s)", gear.missingGems,
            LocalizedList(gear.missingGemSlots)), 1, 0.25, 0.25, true)
    end
    if #gear.missingEnchants > 0 then
        GameTooltip:AddLine(L("Missing enchants: %s", LocalizedList(gear.missingEnchants)), 1, 0.25, 0.25, true)
    end
    for _, text in ipairs(gear.badGems or {}) do GameTooltip:AddLine(D(text), 1, 0.35, 0.2, true) end
    for _, text in ipairs(gear.badEnchants or {}) do GameTooltip:AddLine(D(text), 1, 0.35, 0.2, true) end
    for _, text in ipairs(gear.professionIssues or {}) do GameTooltip:AddLine(D(text), 1, 0.35, 0.2, true) end
    for _, text in ipairs(gear.unverified or {}) do GameTooltip:AddLine(L("Unverified: %s", D(text)), 1, 0.78, 0.2, true) end
    if #gear.wrongPrimary > 0 then
        GameTooltip:AddLine(L("Wrong primary stat (expected %s):", gear.expectedPrimary or "?"), 1, 0.35, 0.2)
        for _, text in ipairs(gear.wrongPrimary) do
            GameTooltip:AddLine("  " .. D(text), 1, 0.5, 0.35, true)
        end
    end
    if #gear.lowItems > 0 then
        GameTooltip:AddLine(L("Items below %d:", minLevel), 1, 0.35, 0.2)
        for _, item in ipairs(gear.lowItems) do
            GameTooltip:AddLine(string.format("  %s: %s (iLvl %d)", L(item.label), item.name, item.ilvl), 1, 0.5, 0.35, true)
        end
    end
    if #gear.missingItems > 0 then
        GameTooltip:AddLine(L("Empty required slots: %s", LocalizedList(gear.missingItems)), 1, 0.25, 0.25, true)
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

    local healthHover = CreateFrame("Frame", nil, row)
    healthHover:SetPoint("TOPLEFT", row, "TOPLEFT", 780, 0)
    healthHover:SetSize(50, ROW_HEIGHT)
    healthHover:EnableMouse(true)
    row.healthHover = healthHover
    healthHover:SetScript("OnEnter", function(self)
        local e = row.fullName and ARC:GetDisplayEntry(row.fullName)
        if not e then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("ARC - " .. (e.name or row.fullName), 1, 1, 1)
        GameTooltip:AddLine(L("Version: %s", e.arcVersion or L("Not detected")), 0.8, 0.8, 0.8)
        local tone, data, age = ARC:GetConnectionHealth(e)
        local function metric(label, value, suffix)
            GameTooltip:AddLine(L("%s: %s", L(label), value and (value .. suffix) or L("Unavailable")), 0.8, 0.8, 0.8)
        end
        metric("Home latency", data and data.home, " ms")
        metric("World latency", data and data.world, " ms")
        metric("FPS (averaged)", data and data.fps, "")
        if age then GameTooltip:AddLine(L("Health report: %ds ago", math.floor(age)), 0.8, 0.8, 0.8) end
        if e.lastComm and e.hasARC then
            GameTooltip:AddLine(L("Last ARC message: %ds ago", math.floor(math.max(0, GetTime() - e.lastComm))), 0.8, 0.8, 0.8)
        end
        if age and age > 30 then
            GameTooltip:AddLine(L("Stale report; connection loss is not confirmed."), 1, 0.78, 0.2)
        elseif tone == "unknown" then
            GameTooltip:AddLine(L("Connection data unavailable."), 0.6, 0.6, 0.6)
        end
        GameTooltip:Show()
    end)
    healthHover:SetScript("OnLeave", function() GameTooltip:Hide() end)

    row:EnableMouse(true)
    row:SetScript("OnEnter", function(self)
        if not self.fullName then return end
        local e = ARC:GetDisplayEntry(self.fullName)
        if not e then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(e.name, 1, 1, 1)
        local visualState = GetEntryVisualState(e)
        if visualState == "offline" then
            GameTooltip:AddLine(L("Status: Offline"), 0.55, 0.55, 0.55)
        elseif visualState == "dead" then
            GameTooltip:AddLine(L("Status: Dead or ghost"), 1, 0.25, 0.25)
        elseif visualState == "afk" then
            GameTooltip:AddLine(L("Status: AFK"), 1, 0.58, 0.18)
        elseif visualState == "range" then
            GameTooltip:AddLine(L("Status: Aura/inspect data out of range"), 0.7, 0.7, 0.7)
        elseif visualState == "waiting" then
            GameTooltip:AddLine(L("Status: Waiting for inspect data"), 1, 0.78, 0.2)
        else
            GameTooltip:AddLine(L("Status: Data available"), 0.3, 1, 0.4)
        end
        if e.specName then GameTooltip:AddLine(e.specName, 0.8, 0.8, 1) end
        if e.specSource == "inspect" then
            GameTooltip:AddLine(L("(spec via inspect - may be stale)"), 0.6, 0.6, 0.6)
        elseif e.specSource == "comm" then
            GameTooltip:AddLine(L("(reported by their ARC)"), 0.6, 0.6, 0.6)
        end
        if e.hasARC then
            GameTooltip:AddLine(L("ARC installed%s", e.arcVersion and L(" - version %s", e.arcVersion) or ""), 0.2, 1, 0.7)
            local versionState = ARC:CompareVersions(e.arcVersion, ARC.VERSION)
            if versionState == -1 then
                GameTooltip:AddLine(L("Outdated ARC: update to %s", ARC.VERSION), 1, 0.3, 0.2)
            elseif versionState == 1 then
                GameTooltip:AddLine(L("Newer than this ARC client"), 0.3, 0.8, 1)
            elseif versionState == nil then
                GameTooltip:AddLine(L("Version could not be compared"), 1, 0.78, 0.2)
            end
        else
            GameTooltip:AddLine(L("ARC not detected"), 0.55, 0.55, 0.55)
        end

        if e.lastAuraScan then GameTooltip:AddLine(L("Aura scan: %ds ago", math.floor(math.max(0, GetTime() - e.lastAuraScan))), 0.7, 0.8, 0.9) end
        if e.gear and e.gear.scannedAt then GameTooltip:AddLine(L("Gear scan: %ds ago", math.floor(math.max(0, GetTime() - e.gear.scannedAt))), 0.7, 0.8, 0.9) end
        if e.lastComm and e.hasARC then GameTooltip:AddLine(L("Last ARC message: %ds ago", math.floor(math.max(0, GetTime() - e.lastComm))), 0.7, 0.8, 0.9) end

        if e.flask then
            local flaskName = e.flaskName
            if flaskName then
                local detail = GetBuffTooltipDetail(e.unit, flaskName)
                GameTooltip:AddLine(flaskName .. (detail and (" - " .. detail) or ""), 0.6, 0.9, 1)
            end
            local status, remaining = ARC:GetConsumableStatus(e, "flask")
            if status == "wrong" then
                GameTooltip:AddLine(L("Wrong main-stat flask: %s; expected %s", e.flaskStat, ARC.SPEC_PRIMARY[e.specID]), 1, 0.25, 0.25)
            end
            if remaining then
                GameTooltip:AddLine(L("Flask remaining: %s", FormatRemaining(remaining)), status == "expiring" and 1 or 0.7,
                    status == "expiring" and 0.65 or 0.9, status == "expiring" and 0.15 or 0.7)
            end
        end
        if e.food then
            local foodName = e.foodName
            local detail = foodName and GetBuffTooltipDetail(e.unit, foodName)
            GameTooltip:AddLine(L("Food: %s", detail or foodName or "Well Fed"), 1, 0.82, 0)
            local status, remaining = ARC:GetConsumableStatus(e, "food")
            if remaining then
                GameTooltip:AddLine(L("Food remaining: %s", FormatRemaining(remaining)), status == "expiring" and 1 or 0.7,
                    status == "expiring" and 0.65 or 0.9, status == "expiring" and 0.15 or 0.7)
            end
        end

        local raidBuffs = {}
        if e.staName then raidBuffs[#raidBuffs + 1] = e.staName end
        if e.statName then raidBuffs[#raidBuffs + 1] = e.statName end
        if e.critName then raidBuffs[#raidBuffs + 1] = e.critName end
        if e.mastName then raidBuffs[#raidBuffs + 1] = e.mastName end
        if #raidBuffs > 0 then
            GameTooltip:AddLine(L("Raid buffs: %s", table.concat(raidBuffs, ", ")), 0.7, 0.9, 0.7)
        end

        if e.ilvlApprox then
            GameTooltip:AddLine(L("Item level is an estimate (no ARC on their end)"), 0.6, 0.6, 0.6)
        end
        if e.hasARC and e.durPct then
            GameTooltip:AddLine(L("Durability: %d%% average, %d%% lowest item",
                e.durPct, e.durWorst or e.durPct), 0.8, 0.8, 0.8)
        else
            GameTooltip:AddLine(L("Durability unavailable - the WoW API exposes no remote value or reliable estimate"), 0.6, 0.6, 0.6, true)
        end
        AddGearTooltip(e)
        if ARC.GetTalentStatus then
            local status, tone, details = ARC:GetTalentStatus(e)
            GameTooltip:AddLine(L("Talents: %s", status), 1, 0.82, 0)
            for _, detail in ipairs(details) do GameTooltip:AddLine(D(detail), 1, tone == "bad" and 0.25 or 0.78, 0.2, true) end
        end
        if ARC.GetSelfBuffStatus then
            local status, tone, details = ARC:GetSelfBuffStatus(e)
            GameTooltip:AddLine(L("Self / tank / pet readiness: %s", status), 1, 0.82, 0)
            for _, detail in ipairs(details) do GameTooltip:AddLine(D(detail), 1, tone == "bad" and 0.25 or 0.78, 0.2, true) end
        end
        if ARC.GetHealthstoneStatus then
            local _, tone, detail = ARC:GetHealthstoneStatus(e)
            GameTooltip:AddLine(D(detail), 1, tone == "bad" and 0.25 or 0.78, 0.2, true)
        end
        GameTooltip:AddLine(" ")
        if e.demo then
            GameTooltip:AddLine(L("Temporary demo data"), 0.3, 0.8, 1)
        else
            GameTooltip:AddLine(L("Right-click for options"), 0.5, 0.5, 0.5)
        end
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row:SetScript("OnMouseUp", function(self, button)
        if button ~= "RightButton" then return end
        if not self.fullName then return end
        local e = ARC:GetDisplayEntry(self.fullName)
        if not e then return end
        if e.demo then return end
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

function ARC:GetWindowOpacity()
    local value = tonumber(ARC_DB and ARC_DB.windowOpacity) or 0.7
    return math.max(0.2, math.min(1, value))
end

function ARC:ApplyWindowOpacity(value)
    local alpha = tonumber(value) or self:GetWindowOpacity()
    alpha = math.max(0.2, math.min(1, alpha))
    local f = self.frame
    if not f then return alpha end
    if f.SetBackdropColor then pcall(f.SetBackdropColor, f, 0, 0, 0, alpha) end
    if f.backdrop and f.backdrop ~= f and f.backdrop.SetBackdropColor then
        pcall(f.backdrop.SetBackdropColor, f.backdrop, 0, 0, 0, alpha)
    end
    return alpha
end

function ARC:SetWindowOpacity(value)
    value = tonumber(value)
    if not value then return false end
    value = math.max(0.2, math.min(1, value))
    ARC_DB.windowOpacity = value
    self:ApplyWindowOpacity(value)
    return true
end

local function ApplyDefaultSkin(f)
    if not f.SetBackdrop then return end
    f:SetBackdrop(BACKDROP_INFO)
    f:SetBackdropColor(0, 0, 0, ARC:GetWindowOpacity())
    f:SetBackdropBorderColor(1, 1, 1, 1)   -- fully opaque border
end

local ELVUI_BORDERED_ICONS = { "ready", "role", "spec", "flask", "food", "sta", "stat", "crit", "mast" }

local function ApplyElvUIFont(fontString, E, size)
    if not fontString or not fontString.FontTemplate then return end
    local font = E.media and E.media.normFont
    pcall(fontString.FontTemplate, fontString, font, size)
end

function ARC:SkinRowElvUI(row, E)
    if not row or row.elvuiSkinned then return end
    E = E or self.elvuiEngine
    if not E or not E.media then return end

    -- ElvUI 2.76 creates texture backdrops as child frames. At frame level 0
    -- those frames land on the same level as the row and can cover every icon.
    -- Raise the row first so the generated backdrop sits one level below its
    -- role/spec/buff textures instead of drawing over them.
    if row.GetFrameLevel and row.SetFrameLevel then
        local parent = row.GetParent and row:GetParent()
        local parentLevel = parent and parent.GetFrameLevel and parent:GetFrameLevel() or 0
        if row:GetFrameLevel() <= parentLevel then row:SetFrameLevel(parentLevel + 2) end
    end

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
        -- ElvUI 2.76 implements texture backdrops as child Frames. On this
        -- client those frames render above parent-owned texture regions and
        -- leave only empty black squares visible. Do not frame roster icons;
        -- also hide backdrops created by an earlier skin attempt this session.
        if texture and texture.backdrop then
            texture.backdrop:Hide()
            texture.backdrop = nil
        end
        if texture and texture.SetDrawLayer then texture:SetDrawLayer("OVERLAY", 1) end
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
    if not f then return end
    if f.elvuiSkinned then self:ApplyWindowOpacity(); return end
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
    for _, button in ipairs({ f.announce, f.sessionButton, f.readyYes, f.readyNo }) do
        if S and S.HandleButton then pcall(S.HandleButton, S, button) end
        if button.GetFontString then ApplyElvUIFont(button:GetFontString(), E, 11) end
    end
    if f.rosterScroll and S and S.HandleScrollBar then
        local scrollName = f.rosterScroll:GetName()
        local bar = scrollName and _G[scrollName .. "ScrollBar"]
        if bar then pcall(S.HandleScrollBar, S, bar) end
    end

    for _, row in ipairs(f.rows or {}) do
        self:SkinRowElvUI(row, E)
    end
    self:ApplyWindowOpacity()
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
        print("|cff33ff99ARC:|r " .. L("Could not respond; use the Blizzard ready-check dialog."))
    elseif ReadyCheckFrame then
        ReadyCheckFrame:Hide()
    end
    self:UpdateReadyButtons()
end

local DEMO_POOLS = {
    TANK = {
        {"Ironwall", "WARRIOR", 73, "Protection", "Interface\\Icons\\Ability_Warrior_DefensiveStance"},
        {"Sunshield", "PALADIN", 66, "Protection", "Interface\\Icons\\Spell_Holy_DevotionAura"},
        {"Graveguard", "DEATHKNIGHT", 250, "Blood", "Interface\\Icons\\Spell_Deathknight_BloodPresence"},
        {"Wildguard", "DRUID", 104, "Guardian", "Interface\\Icons\\Ability_Racial_BearForm"},
    },
    HEALER = {
        {"Dawnprayer", "PRIEST", 257, "Holy", "Interface\\Icons\\Spell_Holy_GuardianSpirit"},
        {"Mistbloom", "MONK", 270, "Mistweaver", "Interface\\Icons\\Spell_Monk_Mistweaver_Spec"},
        {"Tidecaller", "SHAMAN", 264, "Restoration", "Interface\\Icons\\Spell_Nature_MagicImmunity"},
        {"Moonmend", "DRUID", 105, "Restoration", "Interface\\Icons\\Spell_Nature_HealingTouch"},
    },
    DAMAGER = {
        {"Emberveil", "MAGE", 63, "Fire", "Interface\\Icons\\Spell_Fire_FireBolt02"},
        {"Nightstep", "ROGUE", 260, "Combat", "Interface\\Icons\\Ability_BackStab"},
        {"Soulbinder", "WARLOCK", 267, "Destruction", "Interface\\Icons\\Spell_Shadow_RainOfFire"},
        {"Arrowfall", "HUNTER", 254, "Marksmanship", "Interface\\Icons\\Ability_Hunter_FocusedAim"},
        {"Stormfury", "SHAMAN", 263, "Enhancement", "Interface\\Icons\\Spell_Shaman_ImprovedReincarnation"},
        {"Frostbane", "DEATHKNIGHT", 251, "Frost", "Interface\\Icons\\Spell_Deathknight_FrostPresence"},
        {"Lightblade", "PALADIN", 70, "Retribution", "Interface\\Icons\\Spell_Holy_AuraOfLight"},
        {"Starfire", "DRUID", 102, "Balance", "Interface\\Icons\\Spell_Nature_StarFall"},
        {"Mindflare", "PRIEST", 258, "Shadow", "Interface\\Icons\\Spell_Shadow_ShadowWordPain"},
        {"Bladestorm", "WARRIOR", 71, "Arms", "Interface\\Icons\\Ability_Warrior_SavageBlow"},
    },
}

local function PickDemoPlayers(pool, count)
    local copy, result = {}, {}
    for index, player in ipairs(pool) do copy[index] = player end
    for index = #copy, 2, -1 do
        local other = math.random(index)
        copy[index], copy[other] = copy[other], copy[index]
    end
    for index = 1, count do result[#result + 1] = copy[index] end
    return result
end

local function EmptyDemoGear(ilvl)
    return {
        scanned = true, auditComplete = true, validationPending = false, issueCount = 0,
        averageItemLevel = ilvl, missingGems = 0, missingGemSlots = {}, missingEnchants = {},
        badGems = {}, badEnchants = {}, professionIssues = {}, unverified = {},
        wrongPrimary = {}, lowItems = {}, missingItems = {},
    }
end

function ARC:CreateDemoRoster()
    local selected = {}
    for _, player in ipairs(PickDemoPlayers(DEMO_POOLS.TANK, 2)) do selected[#selected + 1] = {player, "TANK"} end
    for _, player in ipairs(PickDemoPlayers(DEMO_POOLS.HEALER, 2)) do selected[#selected + 1] = {player, "HEALER"} end
    for _, player in ipairs(PickDemoPlayers(DEMO_POOLS.DAMAGER, 6)) do selected[#selected + 1] = {player, "DAMAGER"} end

    local roster, order, now = {}, {}, GetTime()
    for index, choice in ipairs(selected) do
        local player, role = choice[1], choice[2]
        local key = player[1] .. "-Demo"
        local online, dead, afk = index ~= 10, index == 9, index == 8
        local hasARC = math.random(100) <= 75
        local ilvl = math.random(535, 580)
        local gear = EmptyDemoGear(ilvl)
        if math.random(100) <= 25 then
            gear.issueCount = 1
            gear.lowItems[1] = {label = "Demo slot", name = "Training Item", ilvl = math.random(430, 449)}
        end
        local talentIssue = math.random(100) <= 15
        local selfIssue = math.random(100) <= 15
        local flask, food = math.random(100) > 15, math.random(100) > 18
        local durability = hasARC and math.random(55, 100) or nil
        local ready
        if index ~= 10 then
            ready = math.random(100) <= 78 and "ready" or (math.random(2) == 1 and "notready" or "waiting")
        end
        local e = {
            demo = true, name = player[1], class = player[2], role = role, level = 90,
            guid = "ARC-DEMO-" .. index, online = online, dead = dead, afk = afk,
            auraDataAvailable = online, inspectable = online, ready = ready,
            specID = player[3], specName = player[4], specIcon = player[5], specSource = hasARC and "comm" or "inspect",
            flask = flask, flaskName = flask and "Flask of Demo Power" or nil,
            flaskIcon = "Interface\\Icons\\INV_Alchemy_EndlessFlask_06", flaskExpiresAt = flask and now + math.random(120, 3600) or nil,
            food = food, foodName = food and "Well Fed" or nil,
            foodIcon = "Interface\\Icons\\INV_Misc_Food_100_HardCheese", foodExpiresAt = food and now + math.random(120, 3600) or nil,
            sta = true, staName = "Power Word: Fortitude", staIcon = "Interface\\Icons\\Spell_Holy_WordFortitude",
            stat = true, statName = "Mark of the Wild", statIcon = "Interface\\Icons\\Spell_Nature_Regeneration",
            crit = true, critName = "Arcane Brilliance", critIcon = "Interface\\Icons\\Spell_Holy_MagicalSentry",
            mast = true, mastName = "Blessing of Might", mastIcon = "Interface\\Icons\\Spell_Holy_FistOfJustice",
            ilvl = ilvl, ilvlApprox = not hasARC, durPct = durability,
            durWorst = durability and math.random(35, durability) or nil, hasARC = hasARC,
            arcVersion = hasARC and self.VERSION or nil, lastComm = hasARC and now - math.random(0, 20) or nil,
            gear = gear,
            talents = {source = "self", checkedAt = now, required = 6, complete = true,
                missing = talentIssue and {"Demo tier"} or {}, unknown = {}},
            selfBuffs = {checked = 1, missing = selfIssue and {"Demo self buff"} or {}, problems = {}, unknown = {}},
        }
        if hasARC then
            e.connectionHealth = {at = now - math.random(0, 20), home = math.random(25, 230),
                world = math.random(35, 320), fps = math.random(18, 120)}
        end
        roster[key], order[#order + 1] = e, key
    end
    return roster, order
end

function ARC:LoadDemoRoster()
    self.demoRoster, self.demoOrder = self:CreateDemoRoster()
    self:Show()
    self:Render()
    if self.optionsPanel and self.optionsPanel.refresh then self.optionsPanel.refresh() end
    print("|cff33ff99ARC:|r " .. L("Loaded a temporary random 10-player demo roster."))
end

function ARC:ClearDemoRoster()
    if not self.demoRoster then return false end
    self.demoRoster, self.demoOrder = nil, nil
    if self.optionsPanel and self.optionsPanel.refresh then self.optionsPanel.refresh() end
    if self:IsVisible() then self:Render() end
    return true
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
    title:SetText("ARC - " .. ARC.NAME)
    f.title = title

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)
    close:SetScript("OnClick", function() ARC:Hide() end)
    f.closeButton = close

    f.readyNo = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.readyNo:SetSize(90, 22)
    f.readyNo:SetPoint("TOPRIGHT", -40, -12)
    f.readyNo:SetText(L("Not Ready"))
    f.readyNo:SetScript("OnClick", function() ARC:RespondReadyCheck(false) end)
    f.readyNo:Disable()
    f.readyYes = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.readyYes:SetSize(78, 22)
    f.readyYes:SetPoint("RIGHT", f.readyNo, "LEFT", -6, 0)
    f.readyYes:SetText(L("Ready"))
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
    summary:SetWordWrap(true)
    f.summary = summary

    local scroll = CreateFrame("ScrollFrame", "ARCMainRosterScrollFrame", f, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 8, -TOP_OFFSET)
    scroll:SetPoint("BOTTOMRIGHT", -28, FOOTER_HEIGHT)
    local rowsContainer = CreateFrame("Frame", nil, scroll)
    rowsContainer:SetSize(FRAME_WIDTH - 36, ROW_HEIGHT)
    scroll:SetScrollChild(rowsContainer)
    f.rosterScroll = scroll
    f.rowsContainer = rowsContainer

    f.header = CreateHeader(f)
    f.header:SetPoint("TOPLEFT", 8, -132)

    f.announce = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.announce:SetSize(150, 20)
    f.announce:SetPoint("BOTTOMLEFT", 10, 8)
    f.announce:SetText(L("Announce Missing"))
    f.announce:SetScript("OnClick", function() ARC:AnnounceMissing() end)

    f.sessionButton = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.sessionButton:SetSize(130, 20)
    f.sessionButton:SetPoint("LEFT", f.announce, "RIGHT", 8, 0)
    f.sessionButton:SetText(L("Session Report"))
    f.sessionButton:SetScript("OnClick", function()
        if ARC.ShowSessionReport then ARC:ShowSessionReport() end
    end)

    local hint = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("BOTTOMRIGHT", -10, 10)
    hint:SetText(L("Inspect: %d/%d%s  |  /arc help", 0, 0, ""))
    f.hint = hint

    f.rows = {}
    if ARC.RegisterLocaleRefresh then ARC:RegisterLocaleRefresh(f, function()
        f.readyNo:SetText(L("Not Ready"))
        f.readyYes:SetText(L("Ready"))
        f.announce:SetText(L("Announce Missing"))
        for _, label in ipairs(f.header.labels or {}) do label:SetText(L(label.localeKey)) end
    end) end
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
        return name .. L(" (off)")
    elseif e.dead then
        return name .. L(" (dead)")
    elseif e.afk then
        return name .. L(" (afk)")
    end
    return name
end

-- Builds the "(N seconds remaining)" / "(Finished)" suffix on the title bar.
local function UpdateTitleText()
    local f = ARC.frame
    if not f or not f.title then return end
    local text = "ARC - " .. ARC.NAME
    if ARC.demoRoster then
        text = text .. L(" (DEMO)")
    elseif ARC.readyCheckActive then
        local left = GetReadyCheckSecondsLeft()
        if left == nil then
            text = text .. L(" (in progress)")
        elseif left > 0 then
            text = text .. L(" (%d seconds remaining)", left)
        else
            text = text .. L(" (Finished)")
        end
    elseif ARC.readyCheckFinished then
        text = text .. L(" (Finished)")
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

function ARC:GetPlayerReadinessState(e)
    if not e or e.online == false or e.dead or e.afk then return "bad" end
    if e.ready == "notready" then return "bad" end

    local flaskStatus = self:GetConsumableStatus(e, "flask")
    local foodStatus = self:GetConsumableStatus(e, "food")
    if flaskStatus == "missing" or flaskStatus == "expiring" or flaskStatus == "wrong" or
        foodStatus == "missing" or foodStatus == "expiring" then return "bad" end
    if e.gear and e.gear.scanned and (e.gear.issueCount or 0) > 0 then return "bad" end
    if select(2, self:GetTalentStatus(e)) == "bad" or
        select(2, self:GetSelfBuffStatus(e)) == "bad" or
        select(2, self:GetHealthstoneStatus(e)) == "bad" then return "bad" end

    if self.readyCheckActive and (e.ready == nil or e.ready == "waiting") then return "warn" end
    if flaskStatus == "unknown" or foodStatus == "unknown" then return "warn" end
    if not e.gear or not e.gear.scanned or e.gear.validationPending or not e.gear.auditComplete then return "warn" end
    if select(2, self:GetTalentStatus(e)) == "warn" or
        select(2, self:GetSelfBuffStatus(e)) == "warn" or
        select(2, self:GetHealthstoneStatus(e)) == "warn" then return "warn" end
    return "good"
end

function ARC:GetRaidReadinessVerdict()
    local roster, order = self:GetDisplayRoster()
    local bad, unknown = 0, 0
    for _, name in ipairs(order) do
        local state = self:GetPlayerReadinessState(roster[name])
        if state == "bad" then bad = bad + 1
        elseif state == "warn" then unknown = unknown + 1 end
    end
    if bad > 0 then
        local suffix = unknown > 0 and L("; %d unverified", unknown) or ""
        return L("NOT READY - %d players with confirmed issues%s", bad, suffix), "bad", bad, unknown
    end
    if unknown > 0 then
        return L("CHECK INCOMPLETE - %d players unverified", unknown), "warn", bad, unknown
    end
    if #order == 0 then return L("CHECK INCOMPLETE - roster unavailable"), "warn", 0, 0 end
    return L("READY TO PULL - all verified checks passed"), "good", 0, 0
end

function ARC:Render()
    local f = self.frame
    if not f or not f:IsShown() then return end

    UpdateTitleText()
    self:UpdateReadyButtons()
    if f.sessionButton then
        f.sessionButton:SetText(L(self.IsSessionActive and self:IsSessionActive() and "Session: ACTIVE" or "Session Report"))
    end
    if f.announce then
        if self.demoRoster then f.announce:Disable() else f.announce:Enable() end
    end
    local roster, order = self:GetDisplayRoster()
    local verdictText, verdictTone = self:GetRaidReadinessVerdict()
    local setupText, setupTone
    if self.demoRoster then
        setupText, setupTone = L("DEMO ROSTER - temporary data, not saved"), "neutral"
    else
        setupText, setupTone = self:GetRaidSetupStatus()
    end
    f.raidBanner.label:SetText(verdictText .. "\n" .. setupText)
    local bannerTone = (verdictTone == "bad" or setupTone == "bad") and "bad" or
        ((verdictTone == "warn" or setupTone == "warn") and "warn" or "good")
    if bannerTone == "bad" then
        f.raidBanner.bg:SetVertexColor(0.8, 0.04, 0.04, 0.9)
        f.raidBanner.label:SetTextColor(1, 1, 1)
    elseif bannerTone == "warn" then
        f.raidBanner.bg:SetVertexColor(0.55, 0.34, 0.02, 0.8)
        f.raidBanner.label:SetTextColor(1, 0.9, 0.45)
    else
        f.raidBanner.bg:SetVertexColor(0.08, 0.23, 0.19, 0.65)
        f.raidBanner.label:SetTextColor(0.7, 0.9, 0.8)
    end

    local total, ready, missingFlask, missingFood, gearIssues, arcUsers = 0, 0, 0, 0, 0, 0
    local expiringConsumables, oldArc, inspected, inspectUnavailable = 0, 0, 0, 0
    local talentIssues, selfBuffIssues, stoneIssues = 0, 0, 0

    for i, name in ipairs(order) do
        local e = roster[name]
        local row = self:EnsureRow(i)
        row.fullName = name
        row:Show()

        total = total + 1
        if e.ready == "ready" then ready = ready + 1 end
        local flaskStatus = self:GetConsumableStatus(e, "flask")
        local foodStatus = self:GetConsumableStatus(e, "food")
        if flaskStatus == "missing" or flaskStatus == "wrong" then missingFlask = missingFlask + 1
        elseif flaskStatus == "expiring" then expiringConsumables = expiringConsumables + 1 end
        if foodStatus == "missing" then missingFood = missingFood + 1
        elseif foodStatus == "expiring" then expiringConsumables = expiringConsumables + 1 end
        if e.gear and e.gear.scanned and e.gear.issueCount and e.gear.issueCount > 0 then gearIssues = gearIssues + 1 end
        if e.gear and e.gear.scanned then inspected = inspected + 1
        elseif e.online == false or e.inspectable == false then inspectUnavailable = inspectUnavailable + 1 end
        local versionState = e.hasARC and self:CompareVersions(e.arcVersion, self.VERSION)
        if e.hasARC then
            arcUsers = arcUsers + 1
            if versionState == -1 then oldArc = oldArc + 1 end
        end

        SetReadyIcon(row.ready, e.ready)
        SetRoleIcon(row.role, e.role)

        if e.specIcon then
            row.spec:SetVertexColor(1, 1, 1, 1)
            row.spec:SetDesaturated(false)
            row.spec:SetAlpha(1)
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
            SetConsumableIcon(row.flask, e, "flask")
            SetConsumableIcon(row.food, e, "food")
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

        if not e.hasARC then row.arc:SetText("-")
        elseif versionState == -1 then row.arc:SetText(L("Old"))
        elseif versionState == 1 then row.arc:SetText(L("New"))
        elseif versionState == nil then row.arc:SetText("?")
        else row.arc:SetText(L("Yes")) end
        local talText, talTone = self:GetTalentStatus(e)
        local buffText, buffTone = self:GetSelfBuffStatus(e)
        local stoneText, stoneTone = self:GetHealthstoneStatus(e)
        ReadinessCell(row.tal, talText, talTone)
        ReadinessCell(row.selfBuff, buffText, buffTone)
        ReadinessCell(row.hs, stoneText, stoneTone)
        if talTone == "bad" then talentIssues = talentIssues + 1 end
        if buffTone == "bad" then selfBuffIssues = selfBuffIssues + 1 end
        if stoneTone == "bad" then stoneIssues = stoneIssues + 1 end
        local healthTone = self:GetConnectionHealth(e)
        if healthTone == "bad" then row.arc:SetTextColor(1, 0.25, 0.25)
        elseif healthTone == "warn" then row.arc:SetTextColor(1, 0.78, 0.2)
        elseif healthTone == "good" then row.arc:SetTextColor(0.2, 1, 0.7)
        else row.arc:SetTextColor(0.5, 0.5, 0.5) end
        ApplyRowVisualState(row, e, i)
    end

    for i = #order + 1, #f.rows do
        f.rows[i]:Hide()
    end

    f.summary:SetText(L(
        "|cff55ff55Ready: %d/%d|r  |cffff8888Flask: %d  Food: %d  Soon: %d  Gear: %d  Talents: %d  Self: %d  HS: %d|r  |cff55ffbbARC: %d/%d%s|r",
        ready, total, missingFlask, missingFood, expiringConsumables, gearIssues, talentIssues, selfBuffIssues,
        stoneIssues, arcUsers, total, oldArc > 0 and ("  |cffff5533Old: " .. oldArc .. "|r") or ""
    ))

    -- Longer translations and multi-line setup failures need real space, not
    -- a fixed banner that can hide the last line behind the summary/header.
    local bannerHeight = math.max(48, math.min(120, f.raidBanner.label:GetStringHeight() + 8))
    local summaryHeight = math.max(14, math.min(64, f.summary:GetStringHeight()))
    f.raidBanner:SetHeight(bannerHeight)
    f.summary:ClearAllPoints()
    f.summary:SetPoint("TOPLEFT", 12, -(52 + bannerHeight + 10))
    f.summary:SetPoint("TOPRIGHT", -12, -(52 + bannerHeight + 10))
    local headerY = 52 + bannerHeight + 10 + summaryHeight + 8
    f.header:ClearAllPoints()
    f.header:SetPoint("TOPLEFT", 8, -headerY)
    local topOffset = headerY + HEADER_HEIGHT + 4
    f.rosterScroll:ClearAllPoints()
    f.rosterScroll:SetPoint("TOPLEFT", 8, -topOffset)
    f.rosterScroll:SetPoint("BOTTOMRIGHT", -28, FOOTER_HEIGHT)
    local totalRows = math.max(#order, 1)
    local scale = (ARC_DB and ARC_DB.scale) or 1
    local screenHeight = GetScreenHeight and GetScreenHeight() or 768
    local maxVisibleRows = math.floor(((screenHeight / scale) - topOffset - FOOTER_HEIGHT - 40) / ROW_HEIGHT)
    maxVisibleRows = math.max(6, math.min(25, maxVisibleRows))
    local visibleRows = math.min(totalRows, maxVisibleRows)
    local newHeight = topOffset + FOOTER_HEIGHT + visibleRows * ROW_HEIGHT
    f:SetHeight(newHeight)
    f.rowsContainer:SetHeight(totalRows * ROW_HEIGHT)
    local waiting = math.max(0, total - inspected - inspectUnavailable)
    local suffix = waiting > 0 and (" (waiting " .. waiting .. ")") or
        (inspectUnavailable > 0 and (" (unavailable " .. inspectUnavailable .. ")") or "")
    f.hint:SetText(self.demoRoster and L("Demo roster - no inspect requests") or
        L("Inspect: %d/%d%s  |  /arc help", inspected, total, suffix))
    if self.demoRoster then f.hint:SetTextColor(0.3, 0.8, 1)
    elseif waiting > 0 then f.hint:SetTextColor(1, 0.78, 0.2)
    elseif inspectUnavailable > 0 then f.hint:SetTextColor(0.65, 0.65, 0.65)
    else f.hint:SetTextColor(0.3, 1, 0.5) end
end

--=============================================================================
-- ANNOUNCE MISSING CONSUMABLES
--=============================================================================

function ARC:AnnounceMissing()
    if self.demoRoster then
        print("|cff33ff99ARC:|r " .. L("Demo data cannot be announced to the group."))
        return
    end
    local missing = {}
    local unavailable = 0
    for _, name in ipairs(self.order) do
        local e = self.roster[name]
        if e.online == false or not e.auraDataAvailable then
            unavailable = unavailable + 1
        else
            local tags = {}
            local flaskStatus, flaskLeft = self:GetConsumableStatus(e, "flask")
            local foodStatus, foodLeft = self:GetConsumableStatus(e, "food")
            if flaskStatus == "missing" then tags[#tags + 1] = "flask"
            elseif flaskStatus == "wrong" then tags[#tags + 1] = L("wrong main-stat flask")
            elseif flaskStatus == "expiring" then tags[#tags + 1] = "flask<" .. FormatRemaining(flaskLeft) end
            if foodStatus == "missing" then tags[#tags + 1] = "food"
            elseif foodStatus == "expiring" then tags[#tags + 1] = "food<" .. FormatRemaining(foodLeft) end
            if #tags > 0 then
                missing[#missing + 1] = string.format("%s (%s)", e.name, table.concat(tags, "/"))
            end
        end
    end

    if #missing == 0 then
        local suffix = unavailable > 0 and L(" (%d player(s) could not be verified.)", unavailable) or ""
        print("|cff33ff99ARC:|r " .. L("Everyone with available aura data has flask and food.") .. suffix)
        return
    end
    if unavailable > 0 then
        print("|cff33ff99ARC:|r " .. L("Skipped %d player(s) with unavailable aura data.", unavailable))
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
    if self.demoRoster then
        self:Render()
        return -- Preview must not enqueue inspections or send a live report.
    end
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
