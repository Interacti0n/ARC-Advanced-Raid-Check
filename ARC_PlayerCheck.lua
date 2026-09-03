local ARC = assert(_G.ARC, "ARC_Core.lua must load before ARC_PlayerCheck.lua")
local I = assert(ARC.Internal, "ARC internal API is unavailable")

-- This window owns a snapshot, never an ARC.roster entry. A recycled unit
-- token (for example 'target') must not silently change the displayed player.
local WIDTH, HEIGHT, CONTENT_WIDTH = 640, 620, 590
local COLORS = {
    normal = { 0.9, 0.9, 0.9 }, good = { 0.3, 1, 0.45 },
    warn = { 1, 0.78, 0.2 }, bad = { 1, 0.35, 0.3 },
}
local ROLE_NAMES = { TANK = "Tank", HEALER = "Healer", DAMAGER = "DPS", NONE = "Unknown" }

local function ResolveUnit(entry)
    if not entry then return nil end
    local units = { entry.unit, "target", "mouseover", "focus" }
    if InspectFrame and InspectFrame.unit then units[#units + 1] = InspectFrame.unit end
    for _, unit in ipairs(units) do
        if unit and UnitExists(unit) and UnitGUID(unit) == entry.guid then return unit end
    end
end

local function ElvSkin(frame)
    if not frame or frame.arcSkinned or not ElvUI or not ElvUI[1] then return end
    local E = ElvUI[1]
    if not E.media or not frame.SetTemplate then return end
    if not pcall(frame.SetTemplate, frame, "Transparent") then return end
    frame.arcSkinned = true
    local S
    if E.GetModule then
        local ok, skins = pcall(E.GetModule, E, "Skins")
        if ok then S = skins end
    end
    for _, button in ipairs(frame.buttons or {}) do
        if S and S.HandleButton then pcall(S.HandleButton, S, button) end
    end
    if frame.closeButton and S and S.HandleCloseButton then
        pcall(S.HandleCloseButton, S, frame.closeButton)
    end
    if frame.scroll and S and S.HandleScrollBar then
        local bar = _G[frame.scroll:GetName() .. "ScrollBar"]
        if bar then pcall(S.HandleScrollBar, S, bar) end
    end
    for _, font in ipairs(frame.fonts or {}) do
        if font.FontTemplate then pcall(font.FontTemplate, font, E.media.normFont, 12) end
    end
    for _, row in ipairs(frame.lines or {}) do
        for _, font in ipairs({ row.label, row.value }) do
            if font.FontTemplate then pcall(font.FontTemplate, font, E.media.normFont, 12) end
        end
    end
end

local function HideItemTooltip(icon)
    if icon and GameTooltip:IsOwned(icon) then GameTooltip:Hide() end
end

local function SetItemIcon(row, item)
    local link = item and not item.empty and item.link or nil
    local icon = row.itemIcon
    if icon and icon.itemLink ~= link then HideItemTooltip(icon) end
    if not link then
        if icon then icon.itemLink = nil; icon:Hide() end
        return false
    end
    if not icon then
        icon = CreateFrame("Frame", nil, row)
        icon:SetSize(28, 28)
        icon:SetPoint("TOPLEFT", 132, -4)
        icon:EnableMouse(true)
        icon:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
        icon:SetBackdropColor(0, 0, 0, 1)
        icon:SetBackdropBorderColor(0.65, 0.2, 0.16, 1)
        icon.texture = icon:CreateTexture(nil, "ARTWORK")
        icon.texture:SetPoint("TOPLEFT", 1, -1)
        icon.texture:SetPoint("BOTTOMRIGHT", -1, 1)
        icon.texture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        icon:SetScript("OnEnter", function(self)
            if not self.itemLink then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            -- The full captured link retains gems, enchant and upgrade data.
            -- Never read the current target/slot: this report is a snapshot.
            local ok = pcall(GameTooltip.SetHyperlink, GameTooltip, self.itemLink)
            if not ok then
                GameTooltip:ClearLines()
                GameTooltip:AddLine("Item tooltip unavailable - refresh the check when item data is loaded.", 1, 0.78, 0.2, true)
            end
            GameTooltip:Show()
        end)
        icon:SetScript("OnLeave", HideItemTooltip)
        icon:SetScript("OnHide", HideItemTooltip)
        row:SetScript("OnHide", function(self) HideItemTooltip(self.itemIcon) end)
        row.itemIcon = icon
    end
    icon.itemLink = link
    icon.texture:SetTexture(item.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
    icon:Show()
    return true
end

local function AddLine(frame, label, text, tone, item)
    local index = frame.lineCount + 1
    frame.lineCount = index
    local row = frame.lines[index]
    if not row then
        row = CreateFrame("Frame", nil, frame.content)
        row:SetWidth(CONTENT_WIDTH)
        row.label = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.label:SetPoint("TOPLEFT", 0, -4)
        row.label:SetWidth(124)
        row.label:SetJustifyH("LEFT")
        row.value = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.value:SetPoint("TOPLEFT", 132, -4)
        row.value:SetWidth(CONTENT_WIDTH - 140)
        row.value:SetJustifyH("LEFT")
        row.bg = row:CreateTexture(nil, "BACKGROUND")
        row.bg:SetAllPoints()
        row.bg:SetTexture(1, 1, 1, index % 2 == 0 and 0.04 or 0)
        frame.lines[index] = row
        local E = frame.arcSkinned and ElvUI and ElvUI[1]
        if E then
            for _, font in ipairs({ row.label, row.value }) do
                if font.FontTemplate then pcall(font.FontTemplate, font, E.media.normFont, 12) end
            end
        end
    end
    row.bg:SetTexture(1, 1, 1, index % 2 == 0 and 0.04 or 0)
    row.label:SetTextColor(1, 0.82, 0)
    row.label:SetText(label)
    local hasIcon = SetItemIcon(row, item)
    row.value:ClearAllPoints()
    row.value:SetPoint("TOPLEFT", hasIcon and 168 or 132, -4)
    row.value:SetWidth(CONTENT_WIDTH - (hasIcon and 176 or 140))
    row.value:SetText(text or "Unknown")
    row.value:SetTextColor(unpack(COLORS[tone or "normal"]))
    local height = math.max(row.label:GetStringHeight(), row.value:GetStringHeight(), hasIcon and 28 or 16) + 12
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", 0, -frame.lineOffset)
    row:SetHeight(height)
    row:Show()
    frame.lineOffset = frame.lineOffset + height
end

local function AddSection(frame, title, summary, tone)
    if frame.lineCount > 0 then frame.lineOffset = frame.lineOffset + 8 end
    AddLine(frame, title, summary or "", tone)
    local row = frame.lines[frame.lineCount]
    row.bg:SetTexture(0.12, 0.27, 0.32, 0.75)
    row.label:SetTextColor(0.4, 1, 0.8)
end

local function RenderDetail(frame)
    local entry = frame.entry
    if not entry then return end
    frame.lineCount, frame.lineOffset = 0, 0
    frame.status:SetText(frame.message or "Waiting for inspect data...")
    local gear = entry.gear
    local complete = gear and gear.scanned
    local name = entry.fullName .. (entry.online == false and " (off)" or entry.dead and " (dead)" or "")
    AddSection(frame, "PLAYER")
    AddLine(frame, "Name", name)
    AddLine(frame, "Class / level", (entry.className or "Unknown") .. " / " .. (entry.level or "?"))
    AddLine(frame, "Spec / role", (entry.specName or "Unavailable") .. " / " .. (ROLE_NAMES[entry.role] or "Unknown"))
    if entry.guild then AddLine(frame, "Guild", entry.guild) end
    local threshold = gear and gear.minItemLevel or (ARC_DB and ARC_DB.minItemLevel) or 450
    AddLine(frame, "Equipped iLvl", (complete and ("~" .. tostring(gear.averageItemLevel)) or "Loading") ..
        "   |   Minimum per item: " .. threshold)

    local problemSlots = 0
    if gear then
        for _, item in ipairs(gear.slots or {}) do
            if not item.pending and (not item.empty or complete) and #item.issues > 0 then
                problemSlots = problemSlots + 1
            end
        end
    end
    local summary, tone
    if not complete then
        summary, tone = "Incomplete equipment data - no final verdict", "warn"
    elseif gear.issueCount > 0 then
        summary, tone = gear.issueCount .. " issue(s) in " .. problemSlots .. " slot(s)", "bad"
        if not gear.auditComplete then summary = summary .. "; some checks unverified" end
    elseif not gear.auditComplete then
        summary, tone = "No confirmed issues; some checks are unverified", "warn"
    else
        summary, tone = "No gear issues found under ARC PvE rules", "good"
    end
    AddSection(frame, "GEAR CHECK", summary, tone)

    if problemSlots > 0 then
        for _, item in ipairs(gear.slots) do
            if not item.pending and (not item.empty or complete) and #item.issues > 0 then
                local text = item.empty and "Empty required slot" or
                    ((item.name or "Item") .. " (iLvl " .. tostring(item.ilvl or "?") .. ")")
                if not item.empty then text = text .. "\n- " .. table.concat(item.issues, "\n- ") end
                AddLine(frame, item.label, text, "bad", item)
            end
        end
    end

    if not complete or (gear.unverified and #gear.unverified > 0) then
        AddSection(frame, "UNVERIFIED", "Not counted as a passed check", "warn")
        if not complete then
            local pending = gear and #gear.pendingSlots > 0 and table.concat(gear.pendingSlots, ", ") or "Equipment"
            AddLine(frame, "Item data", pending .. ": waiting for complete inspect data. Empty-looking slots are not confirmed.", "warn")
        end
        if gear then
            for _, message in ipairs(gear.unverified or {}) do AddLine(frame, "Check", message, "warn") end
        end
    end

    if ARC.GetTalentStatus then
        local status, talentTone, details = ARC:GetTalentStatus(entry)
        if status ~= "OK" and status ~= "-" then
            AddSection(frame, "TALENTS", talentTone == "bad" and "Empty available talent slots" or "Unverified talent data", talentTone)
            for _, detail in ipairs(details) do AddLine(frame, "Talent", detail, talentTone) end
        end
    end
    if ARC.GetSelfBuffStatus then
        local status, buffTone, details = ARC:GetSelfBuffStatus(entry)
        if status ~= "OK" and status ~= "-" then
            AddSection(frame, "SELF / TANK / PET", "Snapshot of class readiness", buffTone)
            for _, detail in ipairs(details) do AddLine(frame, "Self buff", detail, buffTone) end
        end
    end

    -- Consumables in a city are only a snapshot, separate from the gear verdict.
    local buffs, readiness = entry.buffs, {}
    if buffs and not buffs.flask then readiness[#readiness + 1] = { "Flask", "Not active at check" } end
    if buffs and not buffs.food then readiness[#readiness + 1] = { "Food", "Not active at check" } end
    if buffs and buffs.flask and buffs.flaskExpiresAt and buffs.flaskExpiresAt - GetTime() <= ARC.CONSUMABLE_WARN_SECONDS then
        readiness[#readiness + 1] = { "Flask", math.max(0, math.ceil((buffs.flaskExpiresAt - GetTime()) / 60)) .. "m remaining" }
    end
    if buffs and buffs.food and buffs.foodExpiresAt and buffs.foodExpiresAt - GetTime() <= ARC.CONSUMABLE_WARN_SECONDS then
        readiness[#readiness + 1] = { "Food", math.max(0, math.ceil((buffs.foodExpiresAt - GetTime()) / 60)) .. "m remaining" }
    end
    local durability = entry.durWorst or entry.durPct
    if durability and durability < 100 then
        readiness[#readiness + 1] = { "Repair", durability .. "% lowest durability (last ARC group report)" }
    end
    if ARC.GetHealthstoneStatus then
        local stone, stoneTone, detail = ARC:GetHealthstoneStatus(entry)
        if stoneTone == "bad" or stoneTone == "warn" then readiness[#readiness + 1] = { "Healthstone", detail, stoneTone } end
    end
    if #readiness > 0 then
        AddSection(frame, "READINESS", "Snapshot only; separate from gear issues", "warn")
        for _, row in ipairs(readiness) do AddLine(frame, row[1], row[2], row[3] or "warn") end
    end
    for index = frame.lineCount + 1, #frame.lines do
        SetItemIcon(frame.lines[index], nil)
        frame.lines[index]:Hide()
    end
    frame.content:SetHeight(math.max(frame.lineOffset, 1))
end
local function BuildDetailFrame()
    local f = CreateFrame("Frame", "ARCPlayerCheckFrame", UIParent)
    f:SetSize(WIDTH, HEIGHT)
    if InspectFrame and InspectFrame:IsShown() then
        f:SetPoint("TOPLEFT", InspectFrame, "TOPRIGHT", 12, 0)
    else
        f:SetPoint("CENTER")
    end
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    f:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 16, edgeSize = 16, insets = { left = 4, right = 4, top = 4, bottom = 4 } })
    f:SetBackdropColor(0, 0, 0, 0.9)
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 14, -12)
    title:SetText("ARC - PvE gear check")
    f.status = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.status:SetPoint("TOPLEFT", 14, -38)
    f.status:SetWidth(WIDTH - 28)
    f.status:SetJustifyH("LEFT")
    f.status:SetTextColor(1, 0.78, 0.2)
    f.scroll = CreateFrame("ScrollFrame", "ARCPlayerCheckScrollFrame", f, "UIPanelScrollFrameTemplate")
    f.scroll:SetPoint("TOPLEFT", 14, -82)
    f.scroll:SetPoint("BOTTOMRIGHT", -34, 48)
    f.content = CreateFrame("Frame", nil, f.scroll)
    f.content:SetSize(CONTENT_WIDTH, 1)
    f.scroll:SetScrollChild(f.content)
    f.lines = {}
    f.closeButton = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    f.closeButton:SetPoint("TOPRIGHT", -3, -3)
    f.closeButton:SetScript("OnClick", function() f:Hide() end)
    f.refresh = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.refresh:SetSize(120, 22)
    f.refresh:SetPoint("BOTTOMLEFT", 14, 14)
    f.refresh:SetText("Refresh")
    f.refresh:SetScript("OnClick", function()
        local unit = ResolveUnit(f.entry)
        if unit then
            ARC:ShowPlayerCheck(unit, f.entry.guid)
        else
            f.message = "Select the same player again before refreshing. The displayed snapshot is unchanged."
            RenderDetail(f)
        end
    end)
    f.fonts, f.buttons = { title, f.status, f.refresh:GetFontString() }, { f.refresh }
    f:SetScript("OnHide", function(self)
        for _, row in ipairs(self.lines) do HideItemTooltip(row.itemIcon) end
        self.session, self.busy = nil, false
        ARC:CancelPlayerInspect()
    end)
    if UISpecialFrames then UISpecialFrames[#UISpecialFrames + 1] = "ARCPlayerCheckFrame" end
    ElvSkin(f)
    return f
end

function ARC:ShowPlayerCheck(unit, expectedGUID)
    if not unit or not UnitExists(unit) or (UnitIsPlayer and not UnitIsPlayer(unit)) then
        print("|cff33ff99ARC:|r Select an inspectable player first.")
        return
    end
    local guid = UnitGUID(unit)
    if not guid or (expectedGUID and guid ~= expectedGUID) then
        print("|cff33ff99ARC:|r The inspected player changed. Reopen their inspect window.")
        return
    end
    if UnitIsUnit(unit, "player") then
        print("|cff33ff99ARC:|r Use /arc for your own gear check.")
        return
    end
    local fullName, name = I.GetUnitIdentity(unit)
    local className, class = UnitClass(unit)
    local entry = { guid = guid, unit = unit, name = name, fullName = fullName, className = className, class = class,
        level = UnitLevel(unit), online = not UnitIsConnected or UnitIsConnected(unit),
        dead = UnitIsDeadOrGhost and UnitIsDeadOrGhost(unit), guild = GetGuildInfo and GetGuildInfo(unit) }
    if entry.online and (not UnitIsVisible or UnitIsVisible(unit)) then entry.buffs = I.ScanUnitBuffs(unit) end
    local peer = self.roster[fullName]
    if peer and peer.lastComm and GetTime() - peer.lastComm < 120 and peer.unit and UnitGUID(peer.unit) == guid then
        entry.arcVersion, entry.durPct, entry.durWorst = peer.arcVersion, peer.durPct, peer.durWorst
        entry.weaponBuffs, entry.weaponBuffAt = peer.weaponBuffs, peer.weaponBuffAt
        entry.preparation, entry.sacrifice = peer.preparation, peer.sacrifice
    end
    if self.ScanSelfBuffs then entry.selfBuffs = self:ScanSelfBuffs(unit, entry) end
    local f = self.playerCheckFrame
    if not f then f = BuildDetailFrame(); self.playerCheckFrame = f end
    ElvSkin(f)
    f.session = {}
    local session = f.session
    f.entry, f.busy, f.capturedAt = entry, true, nil
    f.message = "Waiting for inspect and item data..."
    f.refresh:Disable()
    f:Show()
    f.scroll:SetVerticalScroll(0)
    local ok, reason = self:RequestPlayerInspect(unit, entry, function(request, status, message)
        if f.session ~= session then return end
        f.busy = false
        f.refresh:Enable()
        f.message = message
        if status == "complete" then f.capturedAt = GetTime() end
        RenderDetail(f)
    end)
    if not ok then f.busy = false; f.refresh:Enable(); f.message = reason end
    RenderDetail(f)
end

function ARC:UpdatePlayerCheck()
    local f = self.playerCheckFrame
    if not f or not f:IsShown() or not f.entry then return end
    if f.capturedAt then
        local unit = ResolveUnit(f.entry)
        local available = unit ~= nil
        if available and CanInspect then
            local ok, result = pcall(CanInspect, unit)
            available = ok and result
        end
        local age = math.floor(GetTime() - f.capturedAt)
        f.message = (available and "Snapshot" or "Player unavailable - saved snapshot") .. " (" .. age .. "s old). Refresh to update."
        if f.entry.gear and f.entry.gear.minItemLevel ~= ARC_DB.minItemLevel then
            f.message = "Minimum iLvl changed - Refresh to apply it. " .. f.message
        end
    elseif f.busy then
        local request = self.inspectRequest
        f.message = request and request.ready and "Inspect received; waiting for complete item data..." or "Waiting for inspect response..."
    end
    RenderDetail(f)
end

local function IsOtherPlayer(unit)
    return type(unit) == "string" and UnitExists(unit) and UnitIsPlayer and
        UnitIsPlayer(unit) and not UnitIsUnit(unit, "player")
end

local function CanCheckMenuUnit(unit)
    if not IsOtherPlayer(unit) then return false end
    if UnitIsConnected and not UnitIsConnected(unit) then return false end
    if UnitIsVisible and not UnitIsVisible(unit) then return false end
    if CanInspect then
        local ok, canInspect = pcall(CanInspect, unit)
        if not ok or not canInspect then return false end
    end
    return true
end

local function MenuIdentity(name)
    return type(name) == "string" and name:gsub("%s+", ""):lower() or nil
end

-- Both the ARC row menu and Blizzard/ElvUI unit menus use this entry. Capture
-- values, not the mutable dropdown/roster table or whichever target is current.
function ARC:CreatePlayerCheckMenuItem(unit, expectedFullName)
    if not IsOtherPlayer(unit) then return nil end
    local fullName = I.GetUnitIdentity(unit)
    if expectedFullName and MenuIdentity(fullName) ~= MenuIdentity(expectedFullName) then return nil end
    local guid = UnitGUID(unit)
    if not guid then return nil end
    local selected = { unit = unit, guid = guid }
    return {
        text = "ARC Check", notCheckable = true,
        disabled = not CanCheckMenuUnit(unit), tooltipOnButton = true,
        tooltipTitle = "ARC Check",
        tooltipText = "PvE gear check. Requires this player to be online and in inspect range.",
        func = function()
            if CloseDropDownMenus then CloseDropDownMenus() end
            local current = ResolveUnit(selected)
            if not current or not CanCheckMenuUnit(current) then
                print("|cff33ff99ARC:|r That player changed or is outside inspect range. Reopen their menu nearby.")
                return
            end
            ARC:ShowPlayerCheck(current, guid)
        end,
    }
end

local PLAYER_POPUPS = {
    PLAYER = true, PARTY = true, RAID_PLAYER = true, RAID = true,
    TARGET = true, FOCUS = true, FRIEND = true, FRIEND_OFFLINE = true, CHAT_ROSTER = true,
}

local function ResolvePopupUnit(dropdown, unit, name)
    -- An explicit unit must never silently fall back to another named target.
    if unit ~= nil then return IsOtherPlayer(unit) and unit or nil end
    name = name or (dropdown and dropdown.name)
    if type(name) ~= "string" or name == "" then return nil end
    if not name:find("-", 1, true) then
        local realm = dropdown and dropdown.server
        if not realm or realm == "" then realm = GetRealmName and GetRealmName() end
        if not realm or realm == "" then return nil end
        name = name .. "-" .. realm
    end
    local wanted = MenuIdentity(name)
    local candidates = { "target", "focus", "mouseover" }
    for _, token in ipairs(I.GetGroupUnits()) do candidates[#candidates + 1] = token end
    local match, guid
    for _, token in ipairs(candidates) do
        if IsOtherPlayer(token) and MenuIdentity(I.GetUnitIdentity(token)) == wanted then
            local currentGUID = UnitGUID(token)
            if guid and currentGUID ~= guid then return nil end
            match, guid = token, currentGUID
        end
    end
    return match
end

function ARC:InitPlayerCheckMenu()
    if self.playerCheckMenuHooked or not hooksecurefunc or not UnitPopup_ShowMenu or not UIDropDownMenu_AddButton then return end
    -- Append only to the first level of player menus. Do not alter Blizzard's
    -- shared UnitPopupMenus/UnitPopupButtons or replace their secure functions.
    hooksecurefunc("UnitPopup_ShowMenu", function(dropdown, which, unit, name)
        if (UIDROPDOWNMENU_MENU_LEVEL or 1) ~= 1 or not PLAYER_POPUPS[which] then return end
        local resolved = ResolvePopupUnit(dropdown, unit, name)
        local item = resolved and ARC:CreatePlayerCheckMenuItem(resolved)
        if item then UIDropDownMenu_AddButton(item, 1) end
    end)
    self.playerCheckMenuHooked = true
end

function ARC:AttachInspectCheckButton()
    if not InspectFrame or InspectFrame.arcCheckButton then return end
    local frame = InspectFrame
    local button = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    button:SetSize(74, 18)
    button:SetText("ARC Check")
    frame.arcCheckButton = button
    local function LayoutHeader()
        -- Inside the title bar, leaving the rightmost 30px for Close and the
        -- leftmost 70px for Blizzard's portrait. ElvUI keeps these frame bounds.
        button:ClearAllPoints()
        button:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -30, -5)
        local title = frame.TitleText or InspectFrameTitleText
        if title then
            title:ClearAllPoints()
            title:SetPoint("LEFT", frame, "TOPLEFT", 70, -14)
            title:SetPoint("RIGHT", button, "LEFT", -6, 0)
            title:SetJustifyH("LEFT")
            if title.SetWordWrap then title:SetWordWrap(false) end
        end
    end
    local function CapturePlayer()
        local unit = frame.unit
        frame.arcCheckGUID = unit and UnitGUID(unit) or nil
        LayoutHeader()
    end
    frame:HookScript("OnShow", CapturePlayer)
    if InspectFrame_Show and hooksecurefunc then
        hooksecurefunc("InspectFrame_Show", CapturePlayer)
    end
    if frame:IsShown() then CapturePlayer() end
    button:SetScript("OnClick", function()
        if not frame.arcCheckGUID then return end
        ARC:ShowPlayerCheck(frame.unit, frame.arcCheckGUID)
    end)
    local E = ElvUI and ElvUI[1]
    if E and E.GetModule then
        local ok, S = pcall(E.GetModule, E, "Skins")
        if ok and S and S.HandleButton then pcall(S.HandleButton, S, button) end
    end
    LayoutHeader()
end
