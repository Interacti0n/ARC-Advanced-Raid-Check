local ARC = assert(_G.ARC, "ARC_Core.lua must load before ARC_Session.lua")
local I = assert(ARC.Internal, "ARC internal API is unavailable")

local INACTIVE_AFTER = 10
local MAX_SESSIONS = 10
local MAX_READY_CHECKS = 100
local MAX_PULLS = 200

local function WallTime()
    return time and time() or math.floor(GetTime())
end

local function FormatDuration(seconds)
    seconds = math.max(0, math.floor(seconds or 0))
    local hours = math.floor(seconds / 3600)
    local minutes = math.floor((seconds % 3600) / 60)
    local secs = seconds % 60
    if hours > 0 then return string.format("%dh %02dm", hours, minutes) end
    if minutes > 0 then return string.format("%dm %02ds", minutes, secs) end
    return secs .. "s"
end

local function DisplayTime(value)
    if date and value then return date("%Y-%m-%d %H:%M", value) end
    return tostring(value or "?")
end

local function PlayerKey(name)
    if not name then return nil end
    local base, realm = name:match("^([^%-]+)%-(.+)$")
    if not base then return name end
    realm = realm:gsub("%s+", "")
    local ownRealm = GetRealmName and (GetRealmName() or ""):gsub("%s+", "") or ""
    return realm == ownRealm and (base .. "-" .. realm) or (base .. "-" .. realm)
end

local function CurrentLocation()
    if not GetInstanceInfo then return "Unknown", 0 end
    local name, _, difficulty = GetInstanceInfo()
    return name or "Unknown", tonumber(difficulty) or 0
end

local function EnsureMember(session, fullName, unit)
    local member = session.members[fullName]
    if not member then
        local _, shortName = I.GetUnitIdentity(unit)
        member = {
            name = shortName or fullName, fullName = fullName,
            class = unit and select(2, UnitClass(unit)) or nil,
            joinedAt = WallTime(), totalPresent = 0, afkSeconds = 0,
            trashInactiveSeconds = 0, trashActivityEvents = 0, pulls = 0,
        }
        session.members[fullName] = member
    end
    return member
end

function ARC:InitSessionTracker()
    ARC_DB.sessions = type(ARC_DB.sessions) == "table" and ARC_DB.sessions or {}
    while #ARC_DB.sessions > MAX_SESSIONS do table.remove(ARC_DB.sessions, 1) end
    if type(ARC_DB.activeSession) == "table" and not ARC_DB.activeSession.endedAt then
        self.activeSession = ARC_DB.activeSession
        self.sessionActivity = {}
        self:UpdateSessionRoster()
        print("|cff33ff99ARC:|r resumed the active raid session after reload.")
    end
end

function ARC:IsSessionActive()
    return self.activeSession ~= nil
end

function ARC:UpdateSessionRoster()
    local session = self.activeSession
    if not session then return end
    local now, present = WallTime(), {}
    for _, unit in ipairs(I.GetGroupUnits()) do
        if UnitExists(unit) then
            local fullName = I.GetUnitIdentity(unit)
            if fullName then
                present[fullName] = true
                local member = EnsureMember(session, fullName, unit)
                member.lastSeen = now
                if not member.presentSince then member.presentSince = now end
                if self.trashCombatStartedAt and self.sessionActivity and not self.sessionActivity[fullName] then
                    self.sessionActivity[fullName] = GetTime()
                end
                local afk = UnitIsAFK and UnitIsAFK(unit) or false
                if afk and not member.afkSince then member.afkSince = now end
                if not afk and member.afkSince then
                    member.afkSeconds = member.afkSeconds + math.max(0, now - member.afkSince)
                    member.afkSince = nil
                end
            end
        end
    end
    for fullName, member in pairs(session.members) do
        if member.presentSince and not present[fullName] then
            member.totalPresent = member.totalPresent + math.max(0, now - member.presentSince)
            member.presentSince = nil
        end
        if member.afkSince and not present[fullName] then
            member.afkSeconds = member.afkSeconds + math.max(0, now - member.afkSince)
            member.afkSince = nil
        end
    end
end

function ARC:StartRaidSession()
    if self.activeSession then
        print("|cff33ff99ARC:|r a raid session is already active.")
        return false
    end
    if not IsInGroup() and not IsInRaid() then
        print("|cff33ff99ARC:|r join a group or raid before starting a session.")
        return false
    end
    local instance, difficulty = CurrentLocation()
    local now = WallTime()
    local session = {
        version = 1, startedAt = now, instance = instance, difficulty = difficulty,
        members = {}, pulls = {}, readyChecks = {}, deaths = {},
        trashCombats = 0, trashCombatSeconds = 0,
    }
    self.activeSession, self.sessionActivity = session, {}
    ARC_DB.activeSession = session
    self:UpdateSessionRoster()
    print("|cff33ff99ARC:|r raid session started: " .. instance .. ".")
    self:RefreshSessionReport()
    return true
end

local function CloseOpenMemberTimes(session, now)
    for _, member in pairs(session.members) do
        if member.presentSince then
            member.totalPresent = member.totalPresent + math.max(0, now - member.presentSince)
            member.presentSince = nil
        end
        if member.afkSince then
            member.afkSeconds = member.afkSeconds + math.max(0, now - member.afkSince)
            member.afkSince = nil
        end
    end
end

function ARC:EndRaidSession()
    local session = self.activeSession
    if not session then
        print("|cff33ff99ARC:|r no raid session is active.")
        return false
    end
    if self.trashCombatStartedAt then self:EndTrashCombat() end
    if self.currentEncounter then
        self.currentEncounter.endedAt = WallTime()
        self.currentEncounter.duration = math.max(0, GetTime() - (self.currentEncounter.startedUptime or GetTime()))
        self.currentEncounter.success = false
        self.currentEncounter.interrupted = true
        self.currentEncounter = nil
    end
    local now = WallTime()
    CloseOpenMemberTimes(session, now)
    session.endedAt = now
    ARC_DB.sessions[#ARC_DB.sessions + 1] = session
    while #ARC_DB.sessions > MAX_SESSIONS do table.remove(ARC_DB.sessions, 1) end
    ARC_DB.activeSession = nil
    self.activeSession, self.sessionActivity, self.currentEncounter = nil, nil, nil
    print("|cff33ff99ARC:|r raid session ended and saved.")
    self:RefreshSessionReport(session)
    return true
end

function ARC:GetReportSession(offset)
    offset = math.max(0, tonumber(offset) or 0)
    if self.activeSession then
        if offset == 0 then return self.activeSession end
        return ARC_DB.sessions and ARC_DB.sessions[#ARC_DB.sessions - offset + 1]
    end
    return ARC_DB.sessions and ARC_DB.sessions[#ARC_DB.sessions - offset]
end

function ARC:SessionEncounterStart(encounterID, encounterName, difficultyID, groupSize)
    local session = self.activeSession
    if not session or #session.pulls >= MAX_PULLS then return end
    if self.trashCombatStartedAt then self:EndTrashCombat() end
    local pull = {
        encounterID = tonumber(encounterID) or 0, name = encounterName or "Unknown boss",
        difficulty = tonumber(difficultyID) or 0, groupSize = tonumber(groupSize) or 0,
        startedAt = WallTime(), startedUptime = GetTime(), deaths = {},
    }
    session.pulls[#session.pulls + 1] = pull
    self.currentEncounter = pull
    for _, member in pairs(session.members) do
        if member.presentSince then member.pulls = member.pulls + 1 end
    end
end

function ARC:SessionEncounterEnd(encounterID, encounterName, difficultyID, groupSize, success)
    local pull = self.currentEncounter
    if not self.activeSession or not pull then return end
    pull.endedAt = WallTime()
    pull.duration = math.max(0, GetTime() - (pull.startedUptime or GetTime()))
    pull.success = tonumber(success) == 1
    self.currentEncounter = nil
    self:RefreshSessionReport()
end

function ARC:StartTrashCombat()
    if not self.activeSession or self.currentEncounter or self.trashCombatStartedAt then return end
    self.trashCombatStartedAt = GetTime()
    self.trashLastTick = GetTime()
    self.sessionActivity = self.sessionActivity or {}
    self.sessionInactiveCredited = {}
    for _, unit in ipairs(I.GetGroupUnits()) do
        if UnitExists(unit) then
            local fullName = I.GetUnitIdentity(unit)
            if fullName then self.sessionActivity[fullName] = GetTime() end
        end
    end
end

function ARC:EndTrashCombat()
    local session = self.activeSession
    if not session or not self.trashCombatStartedAt then return end
    session.trashCombats = session.trashCombats + 1
    session.trashCombatSeconds = session.trashCombatSeconds + math.max(0, GetTime() - self.trashCombatStartedAt)
    self.trashCombatStartedAt, self.trashLastTick, self.sessionInactiveCredited = nil, nil, nil
end

function ARC:TickTrashInactivity()
    local session = self.activeSession
    if not session or not self.trashCombatStartedAt or self.currentEncounter then return end
    local now = GetTime()
    local delta = math.max(0, math.min(2, now - (self.trashLastTick or now)))
    self.trashLastTick = now
    for _, unit in ipairs(I.GetGroupUnits()) do
        if UnitExists(unit) and ((not UnitIsConnected) or UnitIsConnected(unit)) and
            ((not UnitIsDeadOrGhost) or not UnitIsDeadOrGhost(unit)) then
            local fullName = I.GetUnitIdentity(unit)
            local member = fullName and session.members[fullName]
            local lastActivity = fullName and self.sessionActivity and self.sessionActivity[fullName]
            if member and lastActivity and now - lastActivity >= INACTIVE_AFTER then
                self.sessionInactiveCredited = self.sessionInactiveCredited or {}
                if not self.sessionInactiveCredited[fullName] then
                    member.trashInactiveSeconds = member.trashInactiveSeconds + (now - lastActivity)
                    self.sessionInactiveCredited[fullName] = true
                else
                    member.trashInactiveSeconds = member.trashInactiveSeconds + delta
                end
            end
        end
    end
end

local ACTIVE_EVENTS = {
    SWING_DAMAGE=true, RANGE_DAMAGE=true, SPELL_DAMAGE=true, SPELL_PERIODIC_DAMAGE=true,
    DAMAGE_SHIELD=true, SPELL_HEAL=true, SPELL_PERIODIC_HEAL=true,
    SPELL_CAST_SUCCESS=true, SPELL_INTERRUPT=true, SPELL_DISPEL=true, SPELL_STOLEN=true,
}

local function PetUnitForOwner(unit)
    if unit == "player" then return "pet" end
    local partyIndex = unit:match("^party(%d+)$")
    if partyIndex then return "partypet" .. partyIndex end
    local raidIndex = unit:match("^raid(%d+)$")
    if raidIndex then return "raidpet" .. raidIndex end
end

local function ResolveCombatMember(session, sourceGUID, sourceName)
    local fullName = PlayerKey(sourceName)
    local member = fullName and session.members[fullName]
    if member then return fullName, member end
    for key, candidate in pairs(session.members) do
        if candidate.name == sourceName or key == sourceName then return key, candidate end
    end
    if sourceGUID then
        for _, unit in ipairs(I.GetGroupUnits()) do
            local petUnit = PetUnitForOwner(unit)
            if petUnit and UnitExists(petUnit) and UnitGUID(petUnit) == sourceGUID then
                local ownerName = I.GetUnitIdentity(unit)
                if ownerName and session.members[ownerName] then return ownerName, session.members[ownerName] end
            end
        end
    end
end

function ARC:SessionCombatLog(...)
    local session = self.activeSession
    if not session then return end
    local _, subevent, _, sourceGUID, sourceName, _, _, destGUID, destName = ...
    if ACTIVE_EVENTS[subevent] and sourceName and self.trashCombatStartedAt and not self.currentEncounter then
        local fullName, member = ResolveCombatMember(session, sourceGUID, sourceName)
        if member then
            self.sessionActivity = self.sessionActivity or {}
            self.sessionActivity[fullName] = GetTime()
            if self.sessionInactiveCredited then self.sessionInactiveCredited[fullName] = nil end
            member.trashActivityEvents = member.trashActivityEvents + 1
        end
    elseif subevent == "UNIT_DIED" and destName then
        local fullName, member = PlayerKey(destName), nil
        member = fullName and session.members[fullName]
        if not member then
            for key, candidate in pairs(session.members) do
                if candidate.name == destName or key == destName then fullName, member = key, candidate; break end
            end
        end
        if member then
            member.deaths = (member.deaths or 0) + 1
            if self.currentEncounter then
                local pull = self.currentEncounter
                local death = { name = member.name, at = math.max(0, GetTime() - (pull.startedUptime or GetTime())) }
                pull.deaths[#pull.deaths + 1] = death
                if not pull.firstDeath then pull.firstDeath = death end
            end
        end
    end
end

function ARC:SessionReadyCheckFinished()
    local session = self.activeSession
    if not session or #session.readyChecks >= MAX_READY_CHECKS then return end
    local snapshot = { at = WallTime(), issues = {}, ready = 0, notReady = 0, waiting = 0 }
    for _, fullName in ipairs(self.order) do
        local e = self.roster[fullName]
        local issues = self.GetConfirmedIssueTags and self:GetConfirmedIssueTags(e) or {}
        if e.online == false then issues[#issues + 1] = "offline"
        elseif e.dead then issues[#issues + 1] = "dead"
        elseif e.afk then issues[#issues + 1] = "AFK" end
        if e.ready == "ready" then snapshot.ready = snapshot.ready + 1
        elseif e.ready == "notready" then
            snapshot.notReady = snapshot.notReady + 1
            issues[#issues + 1] = "not ready"
        else snapshot.waiting = snapshot.waiting + 1 end
        if #issues > 0 then snapshot.issues[#snapshot.issues + 1] = e.name .. ": " .. table.concat(issues, ", ") end
    end
    session.readyChecks[#session.readyChecks + 1] = snapshot
end

local function BuildReport(session)
    if not session then return "No raid session recorded yet." end
    local ended = session.endedAt or WallTime()
    local lines = {
        "ARC RAID SESSION REPORT",
        string.format("%s | difficulty %s", session.instance or "Unknown", session.difficulty or "?"),
        string.format("%s - %s%s", DisplayTime(session.startedAt), session.endedAt and DisplayTime(session.endedAt) or "ACTIVE",
            session.endedAt and "" or " (live)"),
        string.format("Duration: %s", FormatDuration(ended - (session.startedAt or ended))),
        "",
    }
    local kills, bossSeconds = 0, 0
    for _, pull in ipairs(session.pulls or {}) do
        if pull.success then kills = kills + 1 end
        bossSeconds = bossSeconds + (pull.duration or 0)
    end
    lines[#lines + 1] = string.format("Pulls: %d | kills: %d | boss combat: %s", #(session.pulls or {}), kills, FormatDuration(bossSeconds))
    lines[#lines + 1] = string.format("Trash combats: %d | trash combat: %s", session.trashCombats or 0, FormatDuration(session.trashCombatSeconds or 0))
    local combatSeconds = bossSeconds + (session.trashCombatSeconds or 0)
    lines[#lines + 1] = string.format("Tracked combat: %s | between combat: ~%s", FormatDuration(combatSeconds),
        FormatDuration(math.max(0, ended - (session.startedAt or ended) - combatSeconds)))
    lines[#lines + 1] = string.format("Ready checks: %d", #(session.readyChecks or {}))
    lines[#lines + 1] = ""
    lines[#lines + 1] = "BOSSES"
    if #(session.pulls or {}) == 0 then lines[#lines + 1] = "No encounter events recorded." end
    for index, pull in ipairs(session.pulls or {}) do
        local death = pull.firstDeath and (" | first death: " .. pull.firstDeath.name .. " @ " .. FormatDuration(pull.firstDeath.at)) or ""
        local result = pull.success and "KILL" or (pull.interrupted and "session ended mid-pull" or "wipe")
        lines[#lines + 1] = string.format("%d. %s - %s (%s)%s", index, pull.name or "Unknown", result,
            FormatDuration(pull.duration or 0), death)
    end
    lines[#lines + 1] = ""
    lines[#lines + 1] = "ATTENDANCE / ACTIVITY"
    local members = {}
    for _, member in pairs(session.members or {}) do members[#members + 1] = member end
    table.sort(members, function(a, b) return (a.name or "") < (b.name or "") end)
    for _, member in ipairs(members) do
        local present = (member.totalPresent or 0) + (member.presentSince and math.max(0, ended - member.presentSince) or 0)
        local afk = (member.afkSeconds or 0) + (member.afkSince and math.max(0, ended - member.afkSince) or 0)
        local sessionLength = math.max(1, ended - (session.startedAt or ended))
        lines[#lines + 1] = string.format("%s - present %s (%d%%) | AFK flag %s | trash inactive ~%s | pulls %d | deaths %d",
            member.name or member.fullName, FormatDuration(present), math.min(100, math.floor((present / sessionLength) * 100 + 0.5)), FormatDuration(afk),
            FormatDuration(member.trashInactiveSeconds or 0), member.pulls or 0, member.deaths or 0)
    end
    lines[#lines + 1] = ""
    lines[#lines + 1] = "READY CHECK ISSUES"
    local anyIssues = false
    for index, check in ipairs(session.readyChecks or {}) do
        if #(check.issues or {}) > 0 then
            anyIssues = true
            lines[#lines + 1] = string.format("Check %d (%d ready/%d not ready/%d waiting)", index, check.ready or 0, check.notReady or 0, check.waiting or 0)
            for _, issue in ipairs(check.issues) do lines[#lines + 1] = "  " .. issue end
        end
    end
    if not anyIssues then lines[#lines + 1] = "No confirmed issues recorded." end
    lines[#lines + 1] = ""
    lines[#lines + 1] = "Trash inactivity is an estimate: time after 10s without damage, healing, interrupt, dispel or successful casts during trash combat."
    return table.concat(lines, "\n")
end

function ARC:GetSessionReportText(session)
    return BuildReport(session or self:GetReportSession())
end

local function BuildSessionFrame()
    local frame = CreateFrame("Frame", "ARCSessionReportFrame", UIParent)
    frame:SetSize(720, 540)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("HIGH")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    if frame.SetBackdrop then
        frame:SetBackdrop({ bgFile="Interface\\DialogFrame\\UI-DialogBox-Background", edgeFile="Interface\\DialogFrame\\UI-DialogBox-Border", edgeSize=24,
            insets={left=8,right=8,top=8,bottom=8} })
        frame:SetBackdropColor(0, 0, 0, 0.9)
    end
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 18, -16)
    title:SetText("ARC - Raid Session Report")
    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)
    frame.closeButton = close
    local scroll = CreateFrame("ScrollFrame", "ARCSessionReportScroll", frame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 18, -48)
    scroll:SetPoint("BOTTOMRIGHT", -34, 52)
    local edit = CreateFrame("EditBox", nil, scroll)
    edit:SetWidth(650)
    edit:SetMultiLine(true)
    edit:SetAutoFocus(false)
    edit:SetFontObject(GameFontHighlightSmall)
    edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    scroll:SetScrollChild(edit)
    frame.text = edit
    frame.toggle = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.toggle:SetSize(130, 22)
    frame.toggle:SetPoint("BOTTOMLEFT", 18, 18)
    frame.toggle:SetScript("OnClick", function()
        if ARC:IsSessionActive() then ARC:EndRaidSession() else ARC:StartRaidSession() end
        frame.historyOffset = 0
        ARC:RefreshSessionReport()
    end)
    frame.select = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.select:SetSize(150, 22)
    frame.select:SetPoint("LEFT", frame.toggle, "RIGHT", 10, 0)
    frame.select:SetText("Select All for Copy")
    frame.select:SetScript("OnClick", function() edit:SetFocus(); edit:HighlightText() end)
    frame.previous = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.previous:SetSize(76, 22)
    frame.previous:SetPoint("LEFT", frame.select, "RIGHT", 10, 0)
    frame.previous:SetText("Previous")
    frame.previous:SetScript("OnClick", function()
        local nextOffset = (frame.historyOffset or 0) + 1
        if ARC:GetReportSession(nextOffset) then frame.historyOffset = nextOffset; ARC:RefreshSessionReport() end
    end)
    frame.next = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.next:SetSize(62, 22)
    frame.next:SetPoint("LEFT", frame.previous, "RIGHT", 8, 0)
    frame.next:SetText("Next")
    frame.next:SetScript("OnClick", function()
        frame.historyOffset = math.max(0, (frame.historyOffset or 0) - 1)
        ARC:RefreshSessionReport()
    end)
    frame.refresh = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.refresh:SetSize(70, 22)
    frame.refresh:SetPoint("LEFT", frame.next, "RIGHT", 8, 0)
    frame.refresh:SetText("Refresh")
    frame.refresh:SetScript("OnClick", function() ARC:RefreshSessionReport() end)
    frame.scroll = scroll
    frame.buttons = { frame.toggle, frame.select, frame.previous, frame.next, frame.refresh }
    frame.historyOffset = 0
    frame:Hide()
    return frame
end

local function SkinSessionFrame(frame)
    if not frame or frame.arcSkinned or not (IsAddOnLoaded and IsAddOnLoaded("ElvUI")) or not ElvUI or not ElvUI[1] then return end
    local E = ElvUI[1]
    if not frame.SetTemplate or not pcall(frame.SetTemplate, frame, "Transparent") then return end
    frame.arcSkinned = true
    local S
    if E.GetModule then
        local ok, skins = pcall(E.GetModule, E, "Skins")
        if ok then S = skins end
    end
    for _, button in ipairs(frame.buttons or {}) do
        if S and S.HandleButton then pcall(S.HandleButton, S, button) end
    end
    if S and S.HandleCloseButton then pcall(S.HandleCloseButton, S, frame.closeButton) end
    if S and S.HandleScrollBar then
        local bar = _G[frame.scroll:GetName() .. "ScrollBar"]
        if bar then pcall(S.HandleScrollBar, S, bar) end
    end
end

function ARC:TrySkinSessionUI()
    if self.sessionFrame then SkinSessionFrame(self.sessionFrame) end
end

function ARC:RefreshSessionReport(session)
    local frame = self.sessionFrame
    if not frame then return end
    frame.text:SetText(self:GetSessionReportText(session or self:GetReportSession(frame.historyOffset)))
    frame.text:SetCursorPosition(0)
    frame.text:SetHeight(math.max(450, frame.text:GetStringHeight() + 20))
    frame.toggle:SetText(self:IsSessionActive() and "End Session" or "Start Session")
    local offset = frame.historyOffset or 0
    if offset > 0 then frame.next:Enable() else frame.next:Disable() end
    if self:GetReportSession(offset + 1) then frame.previous:Enable() else frame.previous:Disable() end
end

function ARC:ShowSessionReport()
    if not self.sessionFrame then self.sessionFrame = BuildSessionFrame() end
    SkinSessionFrame(self.sessionFrame)
    self:RefreshSessionReport()
    self.sessionFrame:Show()
end

local tracker = CreateFrame("Frame", "ARCSessionEventFrame")
for _, event in ipairs({ "GROUP_ROSTER_UPDATE", "PLAYER_FLAGS_CHANGED", "ENCOUNTER_START", "ENCOUNTER_END", "COMBAT_LOG_EVENT_UNFILTERED" }) do
    tracker:RegisterEvent(event)
end
tracker:SetScript("OnEvent", function(_, event, ...)
    if event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_FLAGS_CHANGED" then
        ARC:UpdateSessionRoster()
    elseif event == "ENCOUNTER_START" then
        ARC:SessionEncounterStart(...)
    elseif event == "ENCOUNTER_END" then
        ARC:SessionEncounterEnd(...)
    elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
        ARC:SessionCombatLog(...)
    end
end)
tracker:SetScript("OnUpdate", function(_, elapsed)
    tracker.elapsed = (tracker.elapsed or 0) + elapsed
    if tracker.elapsed >= 1 then
        tracker.elapsed = 0
        ARC:TickTrashInactivity()
    end
end)
