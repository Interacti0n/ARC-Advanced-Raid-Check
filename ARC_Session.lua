local ARC = assert(_G.ARC, "ARC_Core.lua must load before ARC_Session.lua")
local I = assert(ARC.Internal, "ARC internal API is unavailable")

local INACTIVE_AFTER = 5
local TRASH_IDLE_END_AFTER = 6
local TRASH_DEAD_END_AFTER = 1
local SESSION_RETENTION = 14 * 24 * 60 * 60
local AUTO_EXIT_GRACE = 30
local MAX_READY_CHECKS = 100
local MAX_PULLS = 200
local MAX_LOOT_RECORDS = 500
local LOOT_DUPLICATE_WINDOW = 1.5
local SESSION_VERSION = 3

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
    if not GetInstanceInfo then return "Unknown", 0, nil, nil end
    local name, instanceType, difficulty, _, _, _, _, instanceID = GetInstanceInfo()
    return name or "Unknown", tonumber(difficulty) or 0, instanceType, instanceID
end

local function RaidInstanceState()
    local inInstance, instanceType
    if IsInInstance then inInstance, instanceType = IsInInstance() end
    local name, difficulty, infoType, instanceID = CurrentLocation()
    instanceType = instanceType or infoType
    if inInstance == nil then inInstance = instanceType == "raid" end
    local isRaid = inInstance and instanceType == "raid"
    local key = instanceID and tostring(instanceID) or (name .. ":" .. tostring(difficulty))
    return isRaid and true or false, key, name, difficulty, instanceID
end

local function UpgradeSession(session)
    if type(session) ~= "table" then return end
    local version = tonumber(session.version) or 1
    if version < 2 then
        session.readyCheckCount = session.readyCheckCount or #(session.readyChecks or {})
        session.readyChecks = nil
        local firstDeaths = {}
        local bossDeaths = {}
        for _, pull in ipairs(session.pulls or {}) do
            for _, death in ipairs(pull.deaths or {}) do
                if death.name then bossDeaths[death.name] = (bossDeaths[death.name] or 0) + 1 end
            end
            if pull.firstDeath and pull.firstDeath.name then
                firstDeaths[pull.firstDeath.name] = (firstDeaths[pull.firstDeath.name] or 0) + 1
            end
        end
        for key, member in pairs(session.members or {}) do
            local shortName = member.name or key
            member.offlineSeconds = member.offlineSeconds or 0
            member.bossDeaths = member.bossDeaths or bossDeaths[shortName] or 0
            member.trashDeaths = member.trashDeaths or 0
            member.otherDeaths = member.otherDeaths or math.max(0, (member.deaths or 0) - member.bossDeaths)
            member.firstDeaths = member.firstDeaths or firstDeaths[shortName] or 0
            member.afkSeconds, member.afkSince = nil, nil
        end
        version = 2
    end
    if version < 3 then
        session.loot = type(session.loot) == "table" and session.loot or {}
        session.lootSerial = tonumber(session.lootSerial) or #session.loot
        version = 3
    end
    if type(session.loot) ~= "table" then session.loot = {} end
    if type(session.lootSerial) ~= "number" then session.lootSerial = #session.loot end
    session.version = math.max(version, SESSION_VERSION)
end

local function PruneSessions()
    ARC_DB.sessions = type(ARC_DB.sessions) == "table" and ARC_DB.sessions or {}
    local cutoff = WallTime() - SESSION_RETENTION
    for index = #ARC_DB.sessions, 1, -1 do
        local session = ARC_DB.sessions[index]
        if type(session) ~= "table" or (session.endedAt and session.endedAt < cutoff) then
            table.remove(ARC_DB.sessions, index)
        else
            UpgradeSession(session)
        end
    end
    table.sort(ARC_DB.sessions, function(a, b)
        return (a.endedAt or a.startedAt or 0) < (b.endedAt or b.startedAt or 0)
    end)
end

local function EnsureMember(session, fullName, unit)
    local member = session.members[fullName]
    if not member then
        local _, shortName = I.GetUnitIdentity(unit)
        member = {
            name = shortName or fullName, fullName = fullName,
            class = unit and select(2, UnitClass(unit)) or nil, joinedAt = WallTime(),
            totalPresent = 0, offlineSeconds = 0, trashEligibleSeconds = 0,
            trashInactiveSeconds = 0, trashLongestInactiveSeconds = 0,
            pulls = 0, deaths = 0, bossDeaths = 0, trashDeaths = 0,
            otherDeaths = 0, firstDeaths = 0,
        }
        session.members[fullName] = member
    end
    return member
end

function ARC:InitSessionTracker()
    PruneSessions()
    if type(ARC_DB.activeSession) == "table" and not ARC_DB.activeSession.endedAt then
        UpgradeSession(ARC_DB.activeSession)
        self.activeSession = ARC_DB.activeSession
        for index = #(self.activeSession.pulls or {}), 1, -1 do
            local pull = self.activeSession.pulls[index]
            if pull.success then
                self.lastLootBoss = { encounterID=pull.encounterID, name=pull.name,
                    difficulty=pull.difficulty, pullIndex=index, at=pull.endedAt, afterTrash=true }
                break
            end
        end
        if ARC_DB.autoSessions then
            local inRaid, key, _, _, instanceID = RaidInstanceState()
            if inRaid then
                self.activeSession.automatic = true
                self.activeSession.instanceKey = self.activeSession.instanceKey or key
                self.activeSession.instanceID = self.activeSession.instanceID or instanceID
            end
        end
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
    if session.automatic and self.autoOutsideSince then return end
    local now, present = WallTime(), {}
    for _, unit in ipairs(I.GetGroupUnits()) do
        if UnitExists(unit) then
            local fullName = I.GetUnitIdentity(unit)
            if fullName then
                present[fullName] = true
                local member = EnsureMember(session, fullName, unit)
                member.lastSeen = now
                if not member.presentSince then member.presentSince = now end
                local online = (not UnitIsConnected) or UnitIsConnected(unit)
                if not online and not member.offlineSince then member.offlineSince = now end
                if online and member.offlineSince then
                    member.offlineSeconds = (member.offlineSeconds or 0) + math.max(0, now - member.offlineSince)
                    member.offlineSince = nil
                end
                if self.trashCombatStartedAt and self.sessionActivity and not self.sessionActivity[fullName] then
                    self.sessionActivity[fullName] = GetTime()
                end
            end
        end
    end
    for fullName, member in pairs(session.members) do
        if member.presentSince and not present[fullName] then
            member.totalPresent = member.totalPresent + math.max(0, now - member.presentSince)
            member.presentSince = nil
        end
        if member.offlineSince and not present[fullName] then
            member.offlineSeconds = (member.offlineSeconds or 0) + math.max(0, now - member.offlineSince)
            member.offlineSince = nil
        end
    end
end

function ARC:StartRaidSession(automatic)
    if self.activeSession then
        print("|cff33ff99ARC:|r a raid session is already active.")
        return false
    end
    if not IsInGroup() and not IsInRaid() then
        print("|cff33ff99ARC:|r join a group or raid before starting a session.")
        return false
    end
    local instance, difficulty, _, instanceID = CurrentLocation()
    local now = WallTime()
    local session = {
        version = SESSION_VERSION, startedAt = now, instance = instance, difficulty = difficulty,
        instanceID = instanceID, automatic = automatic and true or false,
        instanceKey = instanceID and tostring(instanceID) or (instance .. ":" .. tostring(difficulty)),
        members = {}, pulls = {}, readyCheckCount = 0,
        trashCombats = 0, trashCombatSeconds = 0, loot = {}, lootSerial = 0,
    }
    self.activeSession, self.sessionActivity = session, {}
    self.lastLootBoss, self.pendingBonusRoll = nil, nil
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
        if member.offlineSince then
            member.offlineSeconds = (member.offlineSeconds or 0) + math.max(0, now - member.offlineSince)
            member.offlineSince = nil
        end
    end
end

function ARC:EndRaidSession(reason, endedAt)
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
    local now = tonumber(endedAt) or WallTime()
    CloseOpenMemberTimes(session, now)
    if self.ResolveSessionLoot then self:ResolveSessionLoot(session, true) end
    session.endedAt = now
    ARC_DB.sessions[#ARC_DB.sessions + 1] = session
    PruneSessions()
    ARC_DB.activeSession = nil
    self.activeSession, self.sessionActivity, self.currentEncounter = nil, nil, nil
    self.lastLootBoss, self.pendingBonusRoll = nil, nil
    if reason == nil or reason == "manual" then
        local inRaid, key = RaidInstanceState()
        if inRaid then ARC_DB.autoSessionSuppressedKey = key end
    end
    print("|cff33ff99ARC:|r raid session ended and saved.")
    self:RefreshSessionReport(session)
    return true
end

function ARC:UpdateAutoSession()
    if not ARC_DB then return end
    local inRaid, key = RaidInstanceState()
    if not inRaid then ARC_DB.autoSessionSuppressedKey = nil end
    if not ARC_DB.autoSessions then return end
    local now = WallTime()
    if inRaid then
        self.autoOutsideSince = nil
        if ARC_DB.autoSessionSuppressedKey and ARC_DB.autoSessionSuppressedKey ~= key then
            ARC_DB.autoSessionSuppressedKey = nil
        end
        local session = self.activeSession
        if session then
            session.lastInsideAt = now
            if session.automatic and session.instanceKey and session.instanceKey ~= key then
                self:EndRaidSession("automatic", now)
                session = nil
            end
        end
        if not session and ARC_DB.autoSessionSuppressedKey ~= key and (IsInRaid() or IsInGroup()) then
            if self:StartRaidSession(true) then self.activeSession.lastInsideAt = now end
        end
    else
        local session = self.activeSession
        if session and session.automatic then
            if not self.autoOutsideSince then self.autoOutsideSince = GetTime() end
            if GetTime() - self.autoOutsideSince >= AUTO_EXIT_GRACE then
                self:EndRaidSession("automatic", session.lastInsideAt or now)
                self.autoOutsideSince = nil
            end
        else
            self.autoOutsideSince = nil
        end
    end
end

function ARC:GetReportSession(offset)
    offset = math.max(0, tonumber(offset) or 0)
    if self.activeSession then
        if offset == 0 then return self.activeSession end
        return ARC_DB.sessions and ARC_DB.sessions[#ARC_DB.sessions - offset + 1]
    end
    return ARC_DB.sessions and ARC_DB.sessions[#ARC_DB.sessions - offset]
end

local function ReportPosition(session)
    local saved = ARC_DB.sessions or {}
    local total = #saved + (ARC.activeSession and 1 or 0)
    if not session then return 0, total end
    if session == ARC.activeSession then return 1, total end
    local position = ARC.activeSession and 2 or 1
    for index = #saved, 1, -1 do
        if saved[index] == session then return position, total end
        position = position + 1
    end
    return 0, total
end

function ARC:DeleteRaidSession(session)
    if type(session) ~= "table" or session == self.activeSession then return false end
    local sessions = ARC_DB.sessions or {}
    for index = #sessions, 1, -1 do
        if sessions[index] == session then
            table.remove(sessions, index)
            PruneSessions()
            local frame = self.sessionFrame
            if frame then
                while (frame.historyOffset or 0) > 0 and not self:GetReportSession(frame.historyOffset) do
                    frame.historyOffset = frame.historyOffset - 1
                end
                self:RefreshSessionReport()
            end
            print("|cff33ff99ARC:|r saved raid session deleted.")
            return true
        end
    end
    return false
end

function ARC:RequestDeleteRaidSession(session)
    if type(session) ~= "table" or session == self.activeSession then return false end
    if not StaticPopupDialogs or not StaticPopup_Show then return false end
    if not StaticPopupDialogs.ARC_DELETE_SESSION_REPORT then
        StaticPopupDialogs.ARC_DELETE_SESSION_REPORT = {
            text = "Delete this saved ARC session report?\n\n%s",
            button1 = DELETE or "Delete",
            button2 = CANCEL or "Cancel",
            OnAccept = function(_, data)
                ARC:DeleteRaidSession(data or ARC.pendingDeleteSession)
                ARC.pendingDeleteSession = nil
            end,
            OnCancel = function() ARC.pendingDeleteSession = nil end,
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
            preferredIndex = 3,
        }
    end
    self.pendingDeleteSession = session
    local label = string.format("%s - %s", session.instance or "Unknown", DisplayTime(session.startedAt))
    StaticPopup_Show("ARC_DELETE_SESSION_REPORT", label, nil, session)
    return true
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
    self.lastLootBoss = nil
    for _, unit in ipairs(I.GetGroupUnits()) do
        if UnitExists(unit) and ((not UnitIsConnected) or UnitIsConnected(unit)) then
            local fullName = I.GetUnitIdentity(unit)
            local member = fullName and session.members[fullName]
            if member and member.presentSince then member.pulls = (member.pulls or 0) + 1 end
        end
    end
end

function ARC:SessionEncounterEnd(encounterID, encounterName, difficultyID, groupSize, success)
    local pull = self.currentEncounter
    if not self.activeSession or not pull then return end
    pull.endedAt = WallTime()
    pull.duration = math.max(0, GetTime() - (pull.startedUptime or GetTime()))
    pull.success = tonumber(success) == 1
    self.currentEncounter = nil
    if pull.success then
        self.lastLootBoss = {
            encounterID = pull.encounterID, name = pull.name, difficulty = pull.difficulty,
            pullIndex = #self.activeSession.pulls, at = WallTime(),
        }
    else
        self.lastLootBoss = nil
    end
    self:RefreshSessionReport()
end

function ARC:StartTrashCombat(enemyGUID)
    if not self.activeSession or self.currentEncounter or self.trashCombatStartedAt then return end
    local now = GetTime()
    self.trashCombatStartedAt = now
    self.trashLastTick = now
    self.trashLastEvidence = now
    self.trashEnemies = {}
    if enemyGUID then self.trashEnemies[enemyGUID] = true end
    self.trashAllDeadAt = nil
    self.trashPetOwners = {}
    if self.lastLootBoss then self.lastLootBoss.afterTrash = true end
    self.sessionActivity = self.sessionActivity or {}
    self.sessionInactiveCredited = {}
    for _, unit in ipairs(I.GetGroupUnits()) do
        if UnitExists(unit) then
            local fullName = I.GetUnitIdentity(unit)
            if fullName then
                self.sessionActivity[fullName] = now
                local petUnit
                if unit == "player" then
                    petUnit = "pet"
                else
                    local partyIndex = unit:match("^party(%d+)$")
                    local raidIndex = unit:match("^raid(%d+)$")
                    if partyIndex then petUnit = "partypet" .. partyIndex
                    elseif raidIndex then petUnit = "raidpet" .. raidIndex end
                end
                local petGUID = petUnit and UnitExists(petUnit) and UnitGUID(petUnit)
                if petGUID then self.trashPetOwners[petGUID] = fullName end
            end
        end
    end
end

function ARC:EndTrashCombat(endedAt)
    local session = self.activeSession
    if not session or not self.trashCombatStartedAt then return end
    endedAt = tonumber(endedAt) or self.trashLastEvidence or GetTime()
    endedAt = math.max(self.trashCombatStartedAt, endedAt)
    session.trashCombats = session.trashCombats + 1
    session.trashCombatSeconds = session.trashCombatSeconds + (endedAt - self.trashCombatStartedAt)
    self.trashCombatStartedAt, self.trashLastTick, self.trashLastEvidence = nil, nil, nil
    self.trashEnemies, self.trashAllDeadAt, self.trashPetOwners = nil, nil, nil
    self.sessionInactiveCredited = nil
end

function ARC:TickTrashInactivity()
    local session = self.activeSession
    if not session or not self.trashCombatStartedAt or self.currentEncounter then return end
    local wallNow = GetTime()
    -- Only advance to real combat-log evidence. The six-second anti-stuck
    -- grace period must not become fake inactivity after a pack has ended.
    local now = math.min(wallNow, self.trashLastEvidence or wallNow)
    local delta = math.max(0, now - (self.trashLastTick or now))
    self.trashLastTick = now
    for _, unit in ipairs(I.GetGroupUnits()) do
        if UnitExists(unit) and ((not UnitIsConnected) or UnitIsConnected(unit)) and
            ((not UnitIsDeadOrGhost) or not UnitIsDeadOrGhost(unit)) then
            local fullName = I.GetUnitIdentity(unit)
            local member = fullName and session.members[fullName]
            local lastActivity = fullName and self.sessionActivity and self.sessionActivity[fullName]
            if member then
                member.trashEligibleSeconds = (member.trashEligibleSeconds or 0) + delta
            end
            if member and lastActivity and now - lastActivity >= INACTIVE_AFTER then
                self.sessionInactiveCredited = self.sessionInactiveCredited or {}
                if not self.sessionInactiveCredited[fullName] then
                    member.trashInactiveSeconds = (member.trashInactiveSeconds or 0) + (now - lastActivity)
                    self.sessionInactiveCredited[fullName] = true
                else
                    member.trashInactiveSeconds = (member.trashInactiveSeconds or 0) + delta
                end
                member.trashLongestInactiveSeconds = math.max(member.trashLongestInactiveSeconds or 0, now - lastActivity)
            end
        else
            local fullName = UnitExists(unit) and I.GetUnitIdentity(unit)
            if fullName and self.sessionActivity then
                self.sessionActivity[fullName] = now
                if self.sessionInactiveCredited then self.sessionInactiveCredited[fullName] = nil end
            end
        end
    end
    if self.trashAllDeadAt and wallNow - self.trashAllDeadAt >= TRASH_DEAD_END_AFTER then
        self:EndTrashCombat(self.trashAllDeadAt)
    elseif self.trashLastEvidence and wallNow - self.trashLastEvidence >= TRASH_IDLE_END_AFTER then
        self:EndTrashCombat(self.trashLastEvidence)
    end
end

--=============================================================================
-- SESSION LOOT
--=============================================================================

local function ExtractItemLink(text)
    if type(text) ~= "string" then return nil end
    local link = text:match("(|c%x%x%x%x%x%x%x%x|Hitem:[^|]+|h%[.-%]|h|r)") or
        text:match("(|Hitem:[^|]+|h%[.-%]|h)")
    if not link or #link > 220 or link:find("^", 1, true) or link:find("[\r\n]") then return nil end
    return link
end

local function ItemIDFromLink(link)
    return type(link) == "string" and tonumber(link:match("|Hitem:(%-?%d+)")) or nil
end

local function FormatToPattern(formatText)
    if type(formatText) ~= "string" or formatText == "" then return nil end
    local stringToken, numberToken = "\001", "\002"
    local text = formatText:gsub("%%%d+%$s", stringToken):gsub("%%%d+%$d", numberToken)
    text = text:gsub("%%s", stringToken):gsub("%%d", numberToken)
    text = text:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
    text = text:gsub(stringToken, "(.-)"):gsub(numberToken, "(%%d+)")
    return "^" .. text .. "$"
end

local function MatchLootFormat(message, formatText, own, multiple, bonus)
    local pattern = FormatToPattern(formatText)
    if not pattern then return nil end
    local a, b, c = message:match(pattern)
    if not a then return nil end
    if own then
        return { own=true, itemLink=ExtractItemLink(a), quantity=multiple and tonumber(b) or 1, bonus=bonus }
    end
    return { player=a, itemLink=ExtractItemLink(b), quantity=multiple and tonumber(c) or 1, bonus=bonus }
end

local function ParseLootMessage(message, eventSender)
    if type(message) ~= "string" then return nil end
    local formats = {
        { "LOOT_ITEM_BONUS_ROLL_SELF_MULTIPLE", true, true, true },
        { "LOOT_ITEM_BONUS_ROLL_MULTIPLE", false, true, true },
        { "LOOT_ITEM_BONUS_ROLL_SELF", true, false, true },
        { "LOOT_ITEM_BONUS_ROLL", false, false, true },
        { "LOOT_ITEM_SELF_MULTIPLE", true, true, false },
        { "LOOT_ITEM_MULTIPLE", false, true, false },
        { "LOOT_ITEM_PUSHED_SELF_MULTIPLE", true, true, false },
        { "LOOT_ITEM_PUSHED_MULTIPLE", false, true, false },
        { "LOOT_ITEM_SELF", true, false, false },
        { "LOOT_ITEM", false, false, false },
        { "LOOT_ITEM_PUSHED_SELF", true, false, false },
        { "LOOT_ITEM_PUSHED", false, false, false },
    }
    for _, candidate in ipairs(formats) do
        local result = MatchLootFormat(message, _G[candidate[1]], candidate[2], candidate[3], candidate[4])
        if result and result.itemLink then return result end
    end
    local link = ExtractItemLink(message)
    if link and type(eventSender) == "string" and eventSender ~= "" then
        return { player=eventSender, itemLink=link, quantity=1, bonus=false }
    end
end

local function CleanPlayerName(name)
    if type(name) ~= "string" then return nil end
    name = name:match("|Hplayer:([^:|]+)") or name:match("%[([^%]]+)%]") or name
    name = name:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("%s+", "")
    return name ~= "" and name or nil
end

local function FindSessionMember(session, name, own)
    if own then name = I.GetUnitIdentity("player") end
    name = CleanPlayerName(name)
    if not name then return nil end
    local lowered, matched = name:lower(), nil
    for key, member in pairs(session.members or {}) do
        local full = tostring(key):gsub("%s+", ""):lower()
        local short = tostring(member.name or ""):gsub("%s+", ""):lower()
        if full == lowered then return key end
        if short == lowered or full:match("^" .. lowered:gsub("([^%w])", "%%%1") .. "%-") then
            if matched then return nil end
            matched = key
        end
    end
    return matched
end

local function BossContext(session, encounterID, pullIndex)
    encounterID, pullIndex = tonumber(encounterID), tonumber(pullIndex)
    local pull = pullIndex and session.pulls and session.pulls[pullIndex]
    if pull and pull.success and (not encounterID or encounterID == 0 or pull.encounterID == encounterID) then
        return { encounterID=pull.encounterID, name=pull.name, difficulty=pull.difficulty, pullIndex=pullIndex }
    end
    for index = #(session.pulls or {}), 1, -1 do
        pull = session.pulls[index]
        if pull.success and (not encounterID or encounterID == 0 or pull.encounterID == encounterID) then
            return { encounterID=pull.encounterID, name=pull.name, difficulty=pull.difficulty, pullIndex=index }
        end
    end
end

local lootScanTip
local function HasTooltipLabel(text, fallback, ...)
    if text:find(fallback:lower(), 1, true) then return true end
    for index = 1, select("#", ...) do
        local label = select(index, ...)
        if type(label) == "string" and label ~= "" and text:find(label:lower(), 1, true) then return true end
    end
    return false
end

local function TooltipVariant(link)
    if not CreateFrame then return nil, nil end
    if not lootScanTip then
        local ok, tip = pcall(CreateFrame, "GameTooltip", "ARCSessionLootScanTooltip", nil, "GameTooltipTemplate")
        if ok then lootScanTip = tip end
    end
    if not lootScanTip or not lootScanTip.SetHyperlink then return nil, nil end
    if lootScanTip.ClearLines then lootScanTip:ClearLines() end
    if lootScanTip.SetOwner then pcall(lootScanTip.SetOwner, lootScanTip, UIParent, "ANCHOR_NONE") end
    local ok = pcall(lootScanTip.SetHyperlink, lootScanTip, link)
    if not ok then return nil, nil end
    local text = {}
    for index = 1, 20 do
        local line = _G["ARCSessionLootScanTooltipTextLeft" .. index]
        if line and line.GetText then
            local lineOK, value = pcall(line.GetText, line)
            if lineOK and value then text[#text + 1] = value:lower() end
        end
    end
    local joined = table.concat(text, " ")
    local heroic = HasTooltipLabel(joined, "heroic", _G.ITEM_HEROIC, _G.PLAYER_DIFFICULTY2) and true or nil
    local forged
    if HasTooltipLabel(joined, "warforged", _G.ITEM_WARFORGED, _G.WARFORGED) then forged = "Warforged"
    elseif HasTooltipLabel(joined, "thunderforged", _G.ITEM_THUNDERFORGED, _G.THUNDERFORGED) then forged = "Thunderforged" end
    return heroic, forged
end

local function ResolveLootMetadata(entry)
    if not entry.itemLink then return true end
    local itemInfo = type(GetItemInfo) == "function" and { pcall(GetItemInfo, entry.itemLink) } or nil
    if itemInfo and itemInfo[1] and itemInfo[2] then
        entry.itemName = itemInfo[2]
        entry.quality = tonumber(itemInfo[4])
        entry.itemLevel = tonumber(itemInfo[5])
        entry.texture = itemInfo[11]
    end
    if not entry.texture and type(GetItemIcon) == "function" then
        local ok, texture = pcall(GetItemIcon, entry.itemID or entry.itemLink)
        if ok then entry.texture = texture end
    end
    local heroic, forged = TooltipVariant(entry.itemLink)
    if heroic then entry.difficultyTag = "Heroic"
    elseif entry.sourceType == "boss" then
        if entry.difficulty == 5 or entry.difficulty == 6 then entry.difficultyTag = "Heroic"
        elseif entry.difficulty == 7 then entry.difficultyTag = "Raid Finder"
        elseif entry.difficulty == 14 then entry.difficultyTag = "Flexible"
        elseif entry.difficulty == 3 or entry.difficulty == 4 then entry.difficultyTag = "Normal" end
    end
    if forged then entry.forgedTag = forged end
    entry.metadataPending = not entry.itemName or not entry.quality
    return not entry.metadataPending
end

function ARC:ResolveSessionLoot(session, final)
    session = session or self.activeSession
    if not session or type(session.loot) ~= "table" then return end
    for index = #session.loot, 1, -1 do
        local entry = session.loot[index]
        if type(entry) ~= "table" then
            table.remove(session.loot, index)
        elseif entry.itemLink then
            ResolveLootMetadata(entry)
            if entry.epicOnly and ((entry.quality and entry.quality < 4) or (final and not entry.quality)) then
                table.remove(session.loot, index)
            end
        end
    end
end

function ARC:RecordSessionLoot(playerKey, itemLink, quantity, bonus, context, origin)
    local session = self.activeSession
    if not session or not session.members or not session.members[playerKey] then return nil end
    session.loot = type(session.loot) == "table" and session.loot or {}
    if #session.loot >= MAX_LOOT_RECORDS then return nil end
    if itemLink and (not ExtractItemLink(itemLink) or not ItemIDFromLink(itemLink)) then return nil end
    quantity = math.max(1, math.min(99, tonumber(quantity) or 1))
    local now, sourceType = WallTime(), context and "boss" or (bonus and "unknown" or "trash")
    local epicOnly = (not bonus) and (sourceType == "trash" or (context and context.afterTrash))

    -- One player can consume only one bonus roll for a recorded boss kill.
    -- Prefer an eventual item result over an earlier empty/partial result.
    if bonus and context and context.pullIndex then
        for index = #session.loot, 1, -1 do
            local prior = session.loot[index]
            if prior and prior.player == playerKey and prior.pullIndex == context.pullIndex and prior.bonusResult then
                if itemLink and not prior.itemLink then
                    prior.itemLink, prior.itemID, prior.quantity, prior.bonusResult =
                        itemLink, ItemIDFromLink(itemLink), quantity, "item"
                    ResolveLootMetadata(prior)
                end
                return prior
            end
        end
    end

    for index = #session.loot, math.max(1, #session.loot - 20), -1 do
        local prior = session.loot[index]
        local sameReward = prior and ((itemLink and prior.itemLink == itemLink) or
            (not itemLink and not prior.itemLink and prior.bonusResult == bonus))
        if sameReward and prior.player == playerKey and math.abs(now - (prior.at or now)) <= LOOT_DUPLICATE_WINDOW then
            if bonus then prior.bonusResult = bonus end
            if context and prior.sourceType ~= "boss" then
                prior.sourceType, prior.bossName, prior.encounterID, prior.difficulty, prior.pullIndex =
                    "boss", context.name, context.encounterID, context.difficulty, context.pullIndex
            end
            return prior
        end
    end

    session.lootSerial = (tonumber(session.lootSerial) or 0) + 1
    local entry = {
        id=session.lootSerial, at=now, player=playerKey, itemLink=itemLink,
        itemID=ItemIDFromLink(itemLink), quantity=quantity, bonusResult=bonus,
        sourceType=sourceType, origin=origin,
        epicOnly=epicOnly and true or nil,
        bossName=context and context.name or nil, encounterID=context and context.encounterID or nil,
        difficulty=context and context.difficulty or nil, pullIndex=context and context.pullIndex or nil,
    }
    ResolveLootMetadata(entry)
    if entry.epicOnly and entry.quality and entry.quality < 4 then return nil end
    session.loot[#session.loot + 1] = entry
    self:RefreshSessionReport()
    return entry
end

function ARC:SessionChatLoot(message, eventSender)
    local session = self.activeSession
    if not session then return end
    local parsed = ParseLootMessage(message, eventSender)
    if not parsed then return end
    local playerKey = FindSessionMember(session, parsed.player, parsed.own)
    if not playerKey then return end
    local context = self.lastLootBoss
    self:RecordSessionLoot(playerKey, parsed.itemLink, parsed.quantity,
        parsed.bonus and "item" or nil, context, "chat")
end

local function OwnMemberKey(session)
    local own = I.GetUnitIdentity("player")
    return own and FindSessionMember(session, own, false) or nil
end

function ARC:SessionBonusRollStarted()
    if not self.activeSession then return end
    local context = self.lastLootBoss or BossContext(self.activeSession)
    self.pendingBonusRoll = { startedAt=GetTime(), context=context }
end

function ARC:SessionBonusRollFailed()
    self.pendingBonusRoll = nil
end

function ARC:SessionBonusRollResult(...)
    local session, pending = self.activeSession, self.pendingBonusRoll
    if not session or not pending then return end
    local args, itemLink, quantity = { ... }, nil, 1
    for index, value in ipairs(args) do
        local link = ExtractItemLink(value)
        if link then
            itemLink = link
            quantity = tonumber(args[index + 1]) or 1
            break
        end
    end
    local playerKey = OwnMemberKey(session)
    if playerKey then
        local result = itemLink and "item" or "none"
        local entry = self:RecordSessionLoot(playerKey, itemLink, quantity, result, pending.context, "bonus")
        if entry then
            local context = pending.context or {}
            local code = itemLink and "I" or "N"
            local payload = table.concat({ "L1", code, tostring(context.encounterID or 0),
                tostring(context.pullIndex or 0), tostring(quantity), itemLink or "-" }, "^")
            self:SendAddonPayload(payload)
        end
    end
    self.pendingBonusRoll = nil
end

function ARC:HandleSessionLootComm(sender, message)
    local session = self.activeSession
    if not session or type(message) ~= "string" then return end
    local protocol, code, encounterID, pullIndex, quantity, itemLink = strsplit("^", message)
    if protocol ~= "L1" or (code ~= "I" and code ~= "N") then return end
    local playerKey = FindSessionMember(session, sender, false)
    if not playerKey then return end
    local currentMember = false
    for _, unit in ipairs(I.GetGroupUnits()) do
        if UnitExists(unit) and I.GetUnitIdentity(unit) == playerKey then currentMember = true; break end
    end
    if not currentMember then return end
    local context = BossContext(session, encounterID, pullIndex)
    if not context then return end
    if code == "N" then itemLink = nil
    elseif not ExtractItemLink(itemLink) then return end
    self:RecordSessionLoot(playerKey, itemLink, quantity, code == "I" and "item" or "none", context, "comm")
end

local ACTIVE_EVENTS = {
    SWING_DAMAGE=true, RANGE_DAMAGE=true, SPELL_DAMAGE=true, SPELL_PERIODIC_DAMAGE=true,
    DAMAGE_SHIELD=true, SPELL_HEAL=true, SPELL_PERIODIC_HEAL=true,
    SPELL_CAST_SUCCESS=true, SPELL_INTERRUPT=true, SPELL_DISPEL=true, SPELL_STOLEN=true,
}

local TRASH_EVIDENCE_EVENTS = {
    SWING_DAMAGE=true, RANGE_DAMAGE=true, SPELL_DAMAGE=true, SPELL_PERIODIC_DAMAGE=true,
    DAMAGE_SHIELD=true, SWING_MISSED=true, RANGE_MISSED=true, SPELL_MISSED=true,
    SPELL_INTERRUPT=true, SPELL_DISPEL=true, SPELL_STOLEN=true,
}

local function ResolveCombatMember(session, sourceGUID, sourceName)
    local fullName = PlayerKey(sourceName)
    local member = fullName and session.members[fullName]
    if member then return fullName, member, false end
    for key, candidate in pairs(session.members) do
        if candidate.name == sourceName or key == sourceName then return key, candidate, false end
    end
    local ownerName = sourceGUID and ARC.trashPetOwners and ARC.trashPetOwners[sourceGUID]
    if ownerName and session.members[ownerName] then
        return ownerName, session.members[ownerName], true
    end
end

local function HasTrackedEnemy(enemies)
    for _ in pairs(enemies or {}) do return true end
    return false
end

function ARC:SessionCombatLog(...)
    local session = self.activeSession
    if not session then return end
    local _, subevent, _, sourceGUID, sourceName, _, _, destGUID, destName = ...
    local sourceFullName, sourceMember, sourceIsPet = ResolveCombatMember(session, sourceGUID, sourceName)
    local _, destMember = ResolveCombatMember(session, destGUID, destName)

    -- A real exchange between a group member (or their pet) and an external
    -- unit opens/keeps the pack. Combat flags alone are deliberately ignored.
    if not self.currentEncounter and TRASH_EVIDENCE_EVENTS[subevent] then
        local enemyGUID
        if sourceMember and not destMember then enemyGUID = destGUID
        elseif destMember and not sourceMember then enemyGUID = sourceGUID end
        if enemyGUID then
            if not self.trashCombatStartedAt then self:StartTrashCombat(enemyGUID) end
            if self.trashCombatStartedAt then
                self.trashEnemies = self.trashEnemies or {}
                self.trashEnemies[enemyGUID] = true
                self.trashLastEvidence = GetTime()
                self.trashAllDeadAt = nil
            end
        end
    end

    -- Pet events may prove that the pack exists, but never credit the owner as
    -- active. Sending a pet while the player idles must still accrue inactivity.
    if ACTIVE_EVENTS[subevent] and sourceMember and not sourceIsPet and self.trashCombatStartedAt and not self.currentEncounter then
        local fullName, member = sourceFullName, sourceMember
        if fullName and member then
            self.sessionActivity = self.sessionActivity or {}
            self.sessionActivity[fullName] = GetTime()
            if self.sessionInactiveCredited then self.sessionInactiveCredited[fullName] = nil end
        end
    end

    if subevent == "UNIT_DIED" and self.trashCombatStartedAt and destGUID and self.trashEnemies and self.trashEnemies[destGUID] then
        self.trashEnemies[destGUID] = nil
        self.trashLastEvidence = GetTime()
        if not HasTrackedEnemy(self.trashEnemies) then self.trashAllDeadAt = GetTime() end
    end

    if subevent == "UNIT_DIED" and destName then
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
                member.bossDeaths = (member.bossDeaths or 0) + 1
                local pull = self.currentEncounter
                local death = { name = member.name, at = math.max(0, GetTime() - (pull.startedUptime or GetTime())) }
                pull.deaths[#pull.deaths + 1] = death
                if not pull.firstDeath then
                    pull.firstDeath = death
                    member.firstDeaths = (member.firstDeaths or 0) + 1
                end
            elseif self.trashCombatStartedAt then
                member.trashDeaths = (member.trashDeaths or 0) + 1
            else
                member.otherDeaths = (member.otherDeaths or 0) + 1
            end
        end
    end
end

function ARC:SessionReadyCheckFinished()
    local session = self.activeSession
    if not session then return end
    session.readyCheckCount = math.min(MAX_READY_CHECKS, (session.readyCheckCount or #(session.readyChecks or {})) + 1)
end

local function ReadyCheckCount(session)
    return session.readyCheckCount or #(session.readyChecks or {})
end

local function BossKey(pull, fallback)
    local encounterID = tonumber(pull.encounterID)
    if encounterID and encounterID > 0 then return tostring(encounterID) end
    return pull.name or tostring(fallback or "Unknown")
end

local function TrashCombatSeconds(session)
    local seconds = session.trashCombatSeconds or 0
    if session == ARC.activeSession and ARC.trashCombatStartedAt then
        seconds = seconds + math.max(0, (ARC.trashLastEvidence or GetTime()) - ARC.trashCombatStartedAt)
    end
    return seconds
end

local function SessionStats(session)
    local kills, bossSeconds, killedBosses = 0, 0, {}
    for _, pull in ipairs(session.pulls or {}) do
        if pull.success then kills = kills + 1; killedBosses[BossKey(pull)] = true end
        bossSeconds = bossSeconds + (pull.duration or 0)
    end
    local uniqueKills = 0
    for _ in pairs(killedBosses) do uniqueKills = uniqueKills + 1 end
    return kills, uniqueKills, bossSeconds
end

local function MemberMetrics(session, member, ended)
    local sessionLength = math.max(1, ended - (session.startedAt or ended))
    local present = (member.totalPresent or 0) + (member.presentSince and math.max(0, ended - member.presentSince) or 0)
    local offline = (member.offlineSeconds or 0) + (member.offlineSince and math.max(0, ended - member.offlineSince) or 0)
    local eligible = member.trashEligibleSeconds or 0
    local rawInactive = member.trashInactiveSeconds or 0
    local inactive = eligible > 0 and math.min(eligible, rawInactive) or rawInactive
    local inactivePct = eligible > 0 and math.floor((inactive / eligible) * 100 + 0.5) or nil
    local attendancePct = math.min(100, math.floor((present / sessionLength) * 100 + 0.5))
    return present, attendancePct, offline, inactive, inactivePct
end

local function DeathBreakdown(member)
    local total = member.deaths or 0
    local boss, trash = member.bossDeaths or 0, member.trashDeaths or 0
    local other = member.otherDeaths
    if other == nil then other = math.max(0, total - boss - trash) end
    return total, boss, trash, other, member.firstDeaths or 0
end

local function LootSource(entry)
    if entry.sourceType == "boss" then return entry.bossName or "Unknown boss" end
    if entry.sourceType == "trash" then return "Trash" end
    return "Unknown source"
end

local function LootTags(entry)
    local tags = {}
    if entry.difficultyTag then tags[#tags + 1] = entry.difficultyTag end
    if entry.forgedTag then tags[#tags + 1] = entry.forgedTag end
    if entry.bonusResult == "item" then tags[#tags + 1] = "Bonus" end
    if entry.sourceType == "trash" then tags[#tags + 1] = "Epic trash" end
    return table.concat(tags, " / ")
end

local function LootCounts(session, playerKey)
    local boss, bonusItems, bonusEmpty, trash = 0, 0, 0, 0
    for _, entry in ipairs(session.loot or {}) do
        if (not playerKey or entry.player == playerKey) and
            (not entry.epicOnly or (entry.quality and entry.quality >= 4)) then
            if entry.bonusResult == "none" then bonusEmpty = bonusEmpty + 1
            elseif entry.sourceType == "trash" then trash = trash + 1
            else boss = boss + 1 end
            if entry.bonusResult == "item" then bonusItems = bonusItems + 1 end
        end
    end
    return boss, bonusItems, bonusEmpty, trash
end

local function BuildReport(session)
    if not session then return "No raid session recorded yet." end
    ARC:ResolveSessionLoot(session)
    local ended = session.endedAt or WallTime()
    local _, uniqueKills, bossSeconds = SessionStats(session)
    local lines = {
        "ARC RAID SESSION REPORT",
        string.format("%s | difficulty %s | %s", session.instance or "Unknown", session.difficulty or "?", session.endedAt and "FINISHED" or "ACTIVE"),
        string.format("%s - %s | duration %s", DisplayTime(session.startedAt), session.endedAt and DisplayTime(session.endedAt) or "ACTIVE", FormatDuration(ended - (session.startedAt or ended))),
        string.format("Bosses killed: %d | pulls: %d | ready checks: %d", uniqueKills, #(session.pulls or {}), ReadyCheckCount(session)),
        string.format("Boss combat: %s | trash combat: %s", FormatDuration(bossSeconds), FormatDuration(TrashCombatSeconds(session))),
        "", "PLAYERS",
    }
    local members = {}
    for _, member in pairs(session.members or {}) do members[#members + 1] = member end
    table.sort(members, function(a, b) return (a.name or "") < (b.name or "") end)
    for _, member in ipairs(members) do
        local _, attendance, offline, inactive, inactivePct = MemberMetrics(session, member, ended)
        local deaths, bossDeaths, trashDeaths, otherDeaths, firstDeaths = DeathBreakdown(member)
        lines[#lines + 1] = string.format("%s | attendance %d%% | offline %s | trash idle %s%s | pulls %d | deaths %d (boss %d, trash %d, other %d, first %d)",
            member.name or member.fullName, attendance, FormatDuration(offline), FormatDuration(inactive), inactivePct and (" / " .. inactivePct .. "%") or " / -",
            member.pulls or 0, deaths, bossDeaths, trashDeaths, otherDeaths, firstDeaths)
    end
    lines[#lines + 1] = ""
    lines[#lines + 1] = "BOSSES"
    if #(session.pulls or {}) == 0 then lines[#lines + 1] = "No encounter events recorded." end
    for index, pull in ipairs(session.pulls or {}) do
        local death = pull.firstDeath and (" | first death " .. pull.firstDeath.name .. " @ " .. FormatDuration(pull.firstDeath.at)) or ""
        local result = pull.success and "KILL" or (pull.interrupted and "INTERRUPTED" or "WIPE")
        lines[#lines + 1] = string.format("%d. %s | %s | %s%s", index, pull.name or "Unknown", result, FormatDuration(pull.duration or 0), death)
    end
    lines[#lines + 1] = ""
    lines[#lines + 1] = "LOOT"
    local bossLoot, bonusItems, bonusEmpty, trashLoot = LootCounts(session)
    lines[#lines + 1] = string.format("Boss items: %d | bonus items: %d | empty bonus rolls: %d | trash epics: %d",
        bossLoot, bonusItems, bonusEmpty, trashLoot)
    local lootMembers = {}
    for key, member in pairs(session.members or {}) do lootMembers[#lootMembers + 1] = { key=key, member=member } end
    table.sort(lootMembers, function(a, b) return (a.member.name or a.key) < (b.member.name or b.key) end)
    for _, data in ipairs(lootMembers) do
        local key, member = data.key, data.member
        local playerLoot = {}
        for _, entry in ipairs(session.loot or {}) do
            if entry.player == key and (not entry.epicOnly or (entry.quality and entry.quality >= 4)) then
                playerLoot[#playerLoot + 1] = entry
            end
        end
        table.sort(playerLoot, function(a, b) return (a.at or 0) == (b.at or 0) and (a.id or 0) < (b.id or 0) or (a.at or 0) < (b.at or 0) end)
        if #playerLoot > 0 then
            lines[#lines + 1] = member.name or key
            for _, entry in ipairs(playerLoot) do
                local reward = entry.bonusResult == "none" and "Bonus roll - no item" or
                    (entry.itemLink or entry.itemName or ("Item " .. tostring(entry.itemID or "?")))
                local tags = LootTags(entry)
                lines[#lines + 1] = string.format("  %s | %s | %s%s",
                    date and date("%H:%M", entry.at or 0) or tostring(entry.at or "?"), LootSource(entry), reward,
                    tags ~= "" and (" | " .. tags) or "")
            end
        end
    end
    lines[#lines + 1] = ""
    lines[#lines + 1] = string.format("Trash idle is estimated after %ds without personal activity; pet-only activity never credits its owner.", INACTIVE_AFTER)
    return table.concat(lines, "\n")
end

function ARC:GetSessionReportText(session)
    return BuildReport(session or self:GetReportSession())
end

local PLAYER_COLUMNS = {
    { key="name", label="Player", x=0, width=175 },
    { key="attendance", label="Attendance", x=175, width=90 },
    { key="offline", label="Offline", x=265, width=85 },
    { key="inactivePct", label="Trash idle", x=350, width=145 },
    { key="pulls", label="Pulls", x=495, width=65 },
    { key="deaths", label="Deaths", x=560, width=85 },
}

local BOSS_COLUMNS = {
    { label="Boss", x=0, width=220 }, { label="Attempts", x=220, width=80 },
    { label="Result", x=300, width=90 }, { label="Combat time", x=390, width=100 },
    { label="First deaths", x=490, width=155 },
}

local LOOT_COLUMNS = {
    { label="Player", x=0, width=245 }, { label="Boss items", x=245, width=90 },
    { label="Bonus items", x=335, width=100 }, { label="Empty rolls", x=435, width=110 },
    { label="Trash epics", x=545, width=100 },
}

local function SetCell(cell, text, r, g, b)
    cell:SetText(text or "")
    cell:SetTextColor(r or 0.9, g or 0.9, b or 0.9)
end

local function CreateCells(row, columns)
    row.cells = {}
    for index, column in ipairs(columns) do
        local cell = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        cell:SetPoint("LEFT", row, "LEFT", column.x + 4, 0)
        cell:SetWidth(column.width - 8)
        cell:SetJustifyH(index == 1 and "LEFT" or "CENTER")
        row.cells[index] = cell
    end
end

local function EnsureHeader(frame, kind, columns)
    local key = kind .. "Header"
    if frame[key] then return frame[key] end
    local header = CreateFrame("Frame", nil, frame[kind .. "Child"])
    header:SetSize(645, 24)
    header.bg = header:CreateTexture(nil, "BACKGROUND")
    header.bg:SetAllPoints()
    header.bg:SetTexture(1, 1, 1, 0.1)
    header.buttons = {}
    for index, column in ipairs(columns) do
        local button = CreateFrame("Button", nil, header)
        button:SetPoint("TOPLEFT", column.x, 0)
        button:SetSize(column.width, 24)
        local label = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        label:SetAllPoints()
        label:SetJustifyH(index == 1 and "LEFT" or "CENTER")
        label:SetText(column.label)
        button.label = label
        if kind == "players" then
            local sortColumn = column.key
            button:SetScript("OnClick", function()
                local newKey = sortColumn
                if frame.playerSort == newKey then frame.playerSortDesc = not frame.playerSortDesc
                else frame.playerSort, frame.playerSortDesc = newKey, newKey ~= "name" end
                ARC:RefreshSessionReport()
            end)
        end
        header.buttons[index] = button
    end
    frame[key] = header
    return header
end

local function EnsurePlayerRow(frame, index)
    frame.playerRows = frame.playerRows or {}
    local row = frame.playerRows[index]
    if row then return row end
    row = CreateFrame("Frame", nil, frame.playersChild)
    row:SetSize(645, 23)
    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()
    row.bg:SetTexture(1, 1, 1, index % 2 == 0 and 0.045 or 0.02)
    CreateCells(row, PLAYER_COLUMNS)
    local deathHover = CreateFrame("Frame", nil, row)
    deathHover:SetPoint("TOPLEFT", row, "TOPLEFT", 560, 0)
    deathHover:SetSize(85, 23)
    deathHover:EnableMouse(true)
    deathHover:SetScript("OnEnter", function(self)
        local member = self.owner.member
        if not member then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:ClearLines()
        local deaths, bossDeaths, trashDeaths, otherDeaths, firstDeaths = DeathBreakdown(member)
        GameTooltip:AddLine(member.name or member.fullName or "Player", 1, 1, 1)
        GameTooltip:AddLine("Deaths: " .. deaths, 0.9, 0.9, 0.9)
        GameTooltip:AddLine("Boss: " .. bossDeaths, 0.85, 0.85, 0.85)
        GameTooltip:AddLine("Trash: " .. trashDeaths, 0.85, 0.85, 0.85)
        GameTooltip:AddLine("Other / unknown: " .. otherDeaths, 0.85, 0.85, 0.85)
        GameTooltip:AddLine("First deaths: " .. firstDeaths, 0.85, 0.85, 0.85)
        GameTooltip:AddLine("Longest trash idle: " .. FormatDuration(member.trashLongestInactiveSeconds or 0), 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    deathHover:SetScript("OnLeave", function() GameTooltip:Hide() end)
    deathHover.owner = row
    row.deathHover = deathHover
    frame.playerRows[index] = row
    return row
end

local function PlayerValues(session, member, ended)
    local _, attendance, offline, inactive, inactivePct = MemberMetrics(session, member, ended)
    return {
        name = member.name or member.fullName or "?", attendance = attendance,
        offline = offline, inactive = inactive, inactivePct = inactivePct or -1,
        pulls = member.pulls or 0, deaths = member.deaths or 0,
    }
end

local function RenderPlayers(frame, session)
    local header = EnsureHeader(frame, "players", PLAYER_COLUMNS)
    header:ClearAllPoints()
    header:SetPoint("TOPLEFT", 0, 0)
    header:Show()
    local ended = session.endedAt or WallTime()
    local rows = {}
    for _, member in pairs(session.members or {}) do rows[#rows + 1] = { member=member, values=PlayerValues(session, member, ended) } end
    local sortKey, descending = frame.playerSort or "name", frame.playerSortDesc
    for index, button in ipairs(header.buttons or {}) do
        local column = PLAYER_COLUMNS[index]
        button.label:SetText(column.label .. (column.key == sortKey and (descending and " v" or " ^") or ""))
    end
    table.sort(rows, function(a, b)
        local av, bv = a.values[sortKey], b.values[sortKey]
        if av == bv then return a.values.name < b.values.name end
        if descending then return av > bv end
        return av < bv
    end)
    for index, data in ipairs(rows) do
        local row = EnsurePlayerRow(frame, index)
        row.member = data.member
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 0, -(index * 23 + 1))
        local v, classColor = data.values, data.member.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[data.member.class]
        SetCell(row.cells[1], v.name, classColor and classColor.r or 1, classColor and classColor.g or 1, classColor and classColor.b or 1)
        SetCell(row.cells[2], v.attendance .. "%")
        SetCell(row.cells[3], FormatDuration(v.offline))
        if v.inactivePct < 0 then
            SetCell(row.cells[4], v.inactive > 0 and (FormatDuration(v.inactive) .. "  -") or "-")
        elseif v.inactivePct <= 5 then
            SetCell(row.cells[4], FormatDuration(v.inactive) .. "  " .. v.inactivePct .. "%", 0.25, 1, 0.25)
        elseif v.inactivePct <= 30 then
            SetCell(row.cells[4], FormatDuration(v.inactive) .. "  " .. v.inactivePct .. "%", 1, 0.82, 0.15)
        else
            SetCell(row.cells[4], FormatDuration(v.inactive) .. "  " .. v.inactivePct .. "%", 1, 0.2, 0.2)
        end
        SetCell(row.cells[5], tostring(v.pulls))
        SetCell(row.cells[6], tostring(v.deaths))
        row:Show()
    end
    for index = #rows + 1, #(frame.playerRows or {}) do frame.playerRows[index]:Hide() end
    frame.playersChild:SetHeight(math.max(1, (#rows + 1) * 23 + 4))
end

local function AggregateBosses(session)
    local bosses, order = {}, {}
    for index, pull in ipairs(session.pulls or {}) do
        local key = BossKey(pull, index)
        local boss = bosses[key]
        if not boss then
            boss = { key=key, name=pull.name or "Unknown", pulls={}, attempts=0, kills=0, duration=0, firstDeaths={} }
            bosses[key], order[#order + 1] = boss, key
        end
        boss.attempts = boss.attempts + 1
        boss.duration = boss.duration + (pull.duration or 0)
        if pull.success then boss.kills = boss.kills + 1 end
        if pull.firstDeath and pull.firstDeath.name then
            boss.firstDeaths[pull.firstDeath.name] = (boss.firstDeaths[pull.firstDeath.name] or 0) + 1
        end
        boss.pulls[#boss.pulls + 1] = pull
    end
    local result = {}
    for _, key in ipairs(order) do result[#result + 1] = bosses[key] end
    return result
end

local function FirstDeathSummary(counts)
    local values = {}
    for name, count in pairs(counts or {}) do values[#values + 1] = { name=name, count=count } end
    table.sort(values, function(a, b) return a.count == b.count and a.name < b.name or a.count > b.count end)
    local text = {}
    for index = 1, math.min(2, #values) do
        text[#text + 1] = values[index].name .. (values[index].count > 1 and (" x" .. values[index].count) or "")
    end
    return #text > 0 and table.concat(text, ", ") or "-"
end

local function EnsureBossRow(frame, index)
    frame.bossRows = frame.bossRows or {}
    local row = frame.bossRows[index]
    if row then return row end
    row = CreateFrame("Button", nil, frame.bossesChild)
    row:SetSize(645, 23)
    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()
    CreateCells(row, BOSS_COLUMNS)
    row:SetScript("OnClick", function(self)
        if not self.bossKey then return end
        frame.expandedBoss = frame.expandedBoss == self.bossKey and nil or self.bossKey
        ARC:RefreshSessionReport()
    end)
    frame.bossRows[index] = row
    return row
end

local function RenderBosses(frame, session)
    local header = EnsureHeader(frame, "bosses", BOSS_COLUMNS)
    header:ClearAllPoints()
    header:SetPoint("TOPLEFT", 0, 0)
    header:Show()
    local line = 0
    for _, boss in ipairs(AggregateBosses(session)) do
        line = line + 1
        local row = EnsureBossRow(frame, line)
        row.bossKey = boss.key
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 0, -(line * 23 + 1))
        row.bg:SetTexture(1, 1, 1, line % 2 == 0 and 0.05 or 0.025)
        SetCell(row.cells[1], (frame.expandedBoss == boss.key and "- " or "+ ") .. boss.name)
        SetCell(row.cells[2], tostring(boss.attempts))
        SetCell(row.cells[3], boss.kills > 0 and "KILL" or "PROGRESS", boss.kills > 0 and 0.25 or 1, boss.kills > 0 and 1 or 0.82, boss.kills > 0 and 0.25 or 0.15)
        SetCell(row.cells[4], FormatDuration(boss.duration))
        SetCell(row.cells[5], FirstDeathSummary(boss.firstDeaths))
        row:Show()
        if frame.expandedBoss == boss.key then
            for attempt, pull in ipairs(boss.pulls) do
                line = line + 1
                local detail = EnsureBossRow(frame, line)
                detail.bossKey = nil
                detail:ClearAllPoints()
                detail:SetPoint("TOPLEFT", 0, -(line * 23 + 1))
                detail.bg:SetTexture(0.2, 0.6, 1, 0.06)
                SetCell(detail.cells[1], "    #" .. attempt)
                SetCell(detail.cells[2], "")
                SetCell(detail.cells[3], pull.success and "KILL" or (pull.interrupted and "STOPPED" or "WIPE"))
                SetCell(detail.cells[4], FormatDuration(pull.duration or 0))
                local death = pull.firstDeath and (pull.firstDeath.name .. " @ " .. FormatDuration(pull.firstDeath.at)) or "-"
                SetCell(detail.cells[5], death)
                detail:Show()
            end
        end
    end
    for index = line + 1, #(frame.bossRows or {}) do frame.bossRows[index]:Hide() end
    frame.bossesChild:SetHeight(math.max(1, (line + 1) * 23 + 4))
end

local function EnsureLootRow(frame, index)
    frame.lootRows = frame.lootRows or {}
    local row = frame.lootRows[index]
    if row then return row end
    row = CreateFrame("Button", nil, frame.lootChild)
    row:SetSize(645, 23)
    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()
    CreateCells(row, LOOT_COLUMNS)

    row.detailSource = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.detailSource:SetPoint("LEFT", row, "LEFT", 16, 0)
    row.detailSource:SetWidth(174)
    row.detailSource:SetJustifyH("LEFT")
    row.itemButton = CreateFrame("Button", nil, row)
    row.itemButton:SetPoint("LEFT", row, "LEFT", 194, 0)
    row.itemButton:SetSize(20, 20)
    row.itemButton:EnableMouse(true)
    row.itemTexture = row.itemButton:CreateTexture(nil, "ARTWORK")
    row.itemTexture:SetAllPoints()
    row.itemTexture:SetDrawLayer("ARTWORK", 7)
    row.itemTexture:SetAlpha(1)
    row.detailName = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.detailName:SetPoint("LEFT", row, "LEFT", 220, 0)
    row.detailName:SetWidth(294)
    row.detailName:SetJustifyH("LEFT")
    row.detailTags = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.detailTags:SetPoint("LEFT", row, "LEFT", 520, 0)
    row.detailTags:SetWidth(121)
    row.detailTags:SetJustifyH("LEFT")
    row.itemButton:SetScript("OnEnter", function(self)
        if not self.itemLink then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:ClearLines()
        local ok = pcall(GameTooltip.SetHyperlink, GameTooltip, self.itemLink)
        if not ok then GameTooltip:AddLine("Item tooltip unavailable.", 1, 0.78, 0.2) end
        GameTooltip:Show()
    end)
    row.itemButton:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row.itemButton:SetScript("OnClick", function(self)
        if self.itemLink and IsShiftKeyDown and IsShiftKeyDown() and ChatEdit_InsertLink then
            pcall(ChatEdit_InsertLink, self.itemLink)
        end
    end)
    row:SetScript("OnClick", function(self)
        if not self.playerKey then return end
        frame.expandedLootPlayer = frame.expandedLootPlayer == self.playerKey and nil or self.playerKey
        ARC:RefreshSessionReport()
    end)
    frame.lootRows[index] = row
    return row
end

local function SetLootRowMode(row, detail)
    for _, cell in ipairs(row.cells or {}) do I.SetFrameShown(cell, not detail) end
    I.SetFrameShown(row.detailSource, detail)
    I.SetFrameShown(row.itemButton, detail)
    I.SetFrameShown(row.detailName, detail)
    I.SetFrameShown(row.detailTags, detail)
    if not detail then
        row.itemButton.itemLink = nil
        if GameTooltip.IsOwned and GameTooltip:IsOwned(row.itemButton) then GameTooltip:Hide() end
    end
end

local function LootItemName(entry)
    return entry.itemName or (entry.itemLink and entry.itemLink:match("|h%[(.-)%]|h")) or
        (entry.itemID and ("Item " .. entry.itemID)) or "Bonus roll - no item"
end

local function LootItemColor(entry)
    if type(GetItemQualityColor) == "function" and entry.quality then
        local ok, r, g, b = pcall(GetItemQualityColor, entry.quality)
        if ok and r then return r, g, b end
    end
    if entry.quality == 5 then return 1, 0.5, 0 end
    if entry.quality == 4 then return 0.64, 0.21, 0.93 end
    return 0.9, 0.9, 0.9
end

local function RenderLoot(frame, session)
    ARC:ResolveSessionLoot(session)
    local header = EnsureHeader(frame, "loot", LOOT_COLUMNS)
    header:ClearAllPoints()
    header:SetPoint("TOPLEFT", 0, 0)
    header:Show()
    local grouped = {}
    for _, entry in ipairs(session.loot or {}) do
        if not entry.epicOnly or (entry.quality and entry.quality >= 4) then
            grouped[entry.player] = grouped[entry.player] or {}
            grouped[entry.player][#grouped[entry.player] + 1] = entry
        end
    end
    local members = {}
    for key, member in pairs(session.members or {}) do members[#members + 1] = { key=key, member=member } end
    table.sort(members, function(a, b) return (a.member.name or a.key) < (b.member.name or b.key) end)
    local line = 0
    for _, data in ipairs(members) do
        local playerLoot = grouped[data.key] or {}
        table.sort(playerLoot, function(a, b)
            if (a.at or 0) == (b.at or 0) then return (a.id or 0) < (b.id or 0) end
            return (a.at or 0) < (b.at or 0)
        end)
        line = line + 1
        local row = EnsureLootRow(frame, line)
        SetLootRowMode(row, false)
        row.playerKey = data.key
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 0, -(line * 23 + 1))
        row.bg:SetTexture(1, 1, 1, line % 2 == 0 and 0.05 or 0.025)
        local classColor = data.member.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[data.member.class]
        SetCell(row.cells[1], (frame.expandedLootPlayer == data.key and "- " or "+ ") ..
            (data.member.name or data.key), classColor and classColor.r or 1,
            classColor and classColor.g or 1, classColor and classColor.b or 1)
        local boss, bonusItems, bonusEmpty, trash = LootCounts(session, data.key)
        SetCell(row.cells[2], tostring(boss))
        SetCell(row.cells[3], tostring(bonusItems))
        SetCell(row.cells[4], tostring(bonusEmpty))
        SetCell(row.cells[5], tostring(trash))
        row:Show()

        if frame.expandedLootPlayer == data.key then
            for _, entry in ipairs(playerLoot) do
                line = line + 1
                local detail = EnsureLootRow(frame, line)
                SetLootRowMode(detail, true)
                detail.playerKey = nil
                detail:ClearAllPoints()
                detail:SetPoint("TOPLEFT", 0, -(line * 23 + 1))
                detail.bg:SetTexture(0.2, 0.6, 1, 0.05)
                local timeText = date and date("%H:%M", entry.at or 0) or "?"
                SetCell(detail.detailSource, timeText .. "  " .. LootSource(entry), 0.72, 0.82, 1)
                detail.itemButton.itemLink = entry.itemLink
                detail.itemTexture:SetTexture(entry.texture or (entry.itemLink and
                    "Interface\\Icons\\INV_Misc_QuestionMark" or "Interface\\Icons\\INV_Misc_Coin_01"))
                local r, g, b = LootItemColor(entry)
                local name = LootItemName(entry) .. ((entry.quantity or 1) > 1 and (" x" .. entry.quantity) or "")
                SetCell(detail.detailName, name, r, g, b)
                local tags = LootTags(entry)
                if entry.metadataPending then tags = tags ~= "" and (tags .. " / Loading") or "Loading" end
                SetCell(detail.detailTags, tags, 1, 0.82, 0.2)
                detail:Show()
            end
        end
    end
    for index = line + 1, #(frame.lootRows or {}) do
        SetLootRowMode(frame.lootRows[index], false)
        frame.lootRows[index]:Hide()
    end
    frame.lootChild:SetHeight(math.max(1, (line + 1) * 23 + 4))
end

local function BuildSessionFrame()
    local frame = CreateFrame("Frame", "ARCSessionReportFrame", UIParent)
    frame:SetSize(720, 560)
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
    local summary = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    summary:SetPoint("TOPLEFT", 18, -46)
    summary:SetWidth(674)
    summary:SetHeight(54)
    summary:SetJustifyH("LEFT")
    frame.summary = summary

    local function CreateTableScroll(name)
        local scroll = CreateFrame("ScrollFrame", name, frame, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", 18, -132)
        scroll:SetPoint("BOTTOMRIGHT", -34, 52)
        local child = CreateFrame("Frame", nil, scroll)
        child:SetSize(645, 1)
        scroll:SetScrollChild(child)
        return scroll, child
    end
    frame.playersScroll, frame.playersChild = CreateTableScroll("ARCSessionPlayersScroll")
    frame.bossesScroll, frame.bossesChild = CreateTableScroll("ARCSessionBossesScroll")
    frame.lootScroll, frame.lootChild = CreateTableScroll("ARCSessionLootScroll")
    local scroll = CreateFrame("ScrollFrame", "ARCSessionExportScroll", frame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 18, -132)
    scroll:SetPoint("BOTTOMRIGHT", -34, 52)
    local edit = CreateFrame("EditBox", nil, scroll)
    edit:SetWidth(645)
    edit:SetMultiLine(true)
    edit:SetAutoFocus(false)
    edit:SetFontObject(GameFontHighlightSmall)
    edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    scroll:SetScrollChild(edit)
    frame.text = edit
    -- MoP 5.4.8 EditBox has no GetStringHeight method. Measure the report
    -- through a transparent FontString instead; it uses the same width/font
    -- and keeps the EditBox tall enough for the scroll frame.
    local measure = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    measure:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, -132)
    measure:SetWidth(645)
    measure:SetJustifyH("LEFT")
    measure:SetWordWrap(true)
    measure:SetAlpha(0)
    frame.textMeasure = measure

    frame.activeTab = "players"
    frame.tabs = {}
    local function AddTab(key, label, anchor, x)
        local button = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        button:SetSize(92, 22)
        if anchor then button:SetPoint("LEFT", anchor, "RIGHT", x or 6, 0)
        else button:SetPoint("TOPLEFT", 18, -103) end
        button:SetText(label)
        button:SetScript("OnClick", function() frame.activeTab = key; ARC:RefreshSessionReport() end)
        frame.tabs[key] = button
        return button
    end
    local playersTab = AddTab("players", "Players")
    local bossesTab = AddTab("bosses", "Bosses", playersTab, 6)
    local lootTab = AddTab("loot", "Loot", bossesTab, 6)
    local exportTab = AddTab("export", "Export", lootTab, 6)

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
    frame.delete = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.delete:SetSize(110, 22)
    frame.delete:SetPoint("LEFT", frame.refresh, "RIGHT", 8, 0)
    frame.delete:SetText("Delete Report")
    frame.delete:SetScript("OnClick", function()
        ARC:RequestDeleteRaidSession(ARC:GetReportSession(frame.historyOffset))
    end)
    frame.scroll = scroll
    frame.scrolls = { frame.playersScroll, frame.bossesScroll, frame.lootScroll, scroll }
    frame.buttons = { frame.toggle, frame.select, frame.previous, frame.next, frame.refresh, frame.delete,
        playersTab, bossesTab, lootTab, exportTab }
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
        for _, scroll in ipairs(frame.scrolls or {}) do
            local bar = scroll:GetName() and _G[scroll:GetName() .. "ScrollBar"]
            if bar then pcall(S.HandleScrollBar, S, bar) end
        end
    end
end

function ARC:TrySkinSessionUI()
    if self.sessionFrame then SkinSessionFrame(self.sessionFrame) end
end

function ARC:RefreshSessionReport(session)
    local frame = self.sessionFrame
    if not frame then return end
    local selected = session or self:GetReportSession(frame.historyOffset)
    local reportText = self:GetSessionReportText(selected)
    frame.text:SetText(reportText)
    frame.text:SetCursorPosition(0)
    local measuredHeight = 0
    if frame.textMeasure then
        frame.textMeasure:SetText(reportText)
        if frame.textMeasure.GetStringHeight then
            local ok, height = pcall(frame.textMeasure.GetStringHeight, frame.textMeasure)
            if ok and type(height) == "number" then measuredHeight = height end
        end
    end
    frame.text:SetHeight(math.max(450, measuredHeight + 20))
    if selected then
        local ended = selected.endedAt or WallTime()
        local _, uniqueKills, bossSeconds = SessionStats(selected)
        local position, total = ReportPosition(selected)
        local status = selected.endedAt and "FINISHED" or "ACTIVE"
        frame.summary:SetText(string.format("Session %d / %d  |  %s  |  Difficulty %s  |  %s\n%s - %s  |  Duration %s\nBosses %d  |  Pulls %d  |  Ready checks %d  |  Boss %s  |  Trash %s",
            position, total, selected.instance or "Unknown", selected.difficulty or "?", status,
            DisplayTime(selected.startedAt), selected.endedAt and DisplayTime(selected.endedAt) or "now",
            FormatDuration(ended - (selected.startedAt or ended)), uniqueKills, #(selected.pulls or {}),
            ReadyCheckCount(selected), FormatDuration(bossSeconds), FormatDuration(TrashCombatSeconds(selected))))
        RenderPlayers(frame, selected)
        RenderBosses(frame, selected)
        RenderLoot(frame, selected)
    else
        frame.summary:SetText("No raid session recorded yet.")
        if frame.playersHeader then frame.playersHeader:Hide() end
        if frame.bossesHeader then frame.bossesHeader:Hide() end
        if frame.lootHeader then frame.lootHeader:Hide() end
        for _, row in ipairs(frame.playerRows or {}) do row:Hide() end
        for _, row in ipairs(frame.bossRows or {}) do row:Hide() end
        for _, row in ipairs(frame.lootRows or {}) do row:Hide() end
    end
    local tab = frame.activeTab or "players"
    I.SetFrameShown(frame.playersScroll, tab == "players")
    I.SetFrameShown(frame.bossesScroll, tab == "bosses")
    I.SetFrameShown(frame.lootScroll, tab == "loot")
    I.SetFrameShown(frame.scroll, tab == "export")
    I.SetFrameShown(frame.select, tab == "export")
    I.SetFrameShown(frame.delete, selected and selected ~= self.activeSession)
    for key, button in pairs(frame.tabs or {}) do
        if key == tab then button:Disable() else button:Enable() end
    end
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
for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "GROUP_ROSTER_UPDATE", "PLAYER_FLAGS_CHANGED",
    "ENCOUNTER_START", "ENCOUNTER_END", "COMBAT_LOG_EVENT_UNFILTERED", "CHAT_MSG_LOOT" }) do
    tracker:RegisterEvent(event)
end
-- These are native MoP events, but a protected registration keeps unusual
-- private-server client forks from preventing the entire session module load.
for _, event in ipairs({ "BONUS_ROLL_STARTED", "BONUS_ROLL_RESULT", "BONUS_ROLL_FAILED" }) do
    pcall(tracker.RegisterEvent, tracker, event)
end
tracker:SetScript("OnEvent", function(_, event, ...)
    if event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" then
        ARC:UpdateAutoSession()
        ARC:UpdateSessionRoster()
    elseif event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_FLAGS_CHANGED" then
        ARC:UpdateSessionRoster()
        ARC:UpdateAutoSession()
    elseif event == "ENCOUNTER_START" then
        ARC:SessionEncounterStart(...)
    elseif event == "ENCOUNTER_END" then
        ARC:SessionEncounterEnd(...)
    elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
        ARC:SessionCombatLog(...)
    elseif event == "CHAT_MSG_LOOT" then
        ARC:SessionChatLoot(...)
    elseif event == "BONUS_ROLL_STARTED" then
        ARC:SessionBonusRollStarted(...)
    elseif event == "BONUS_ROLL_RESULT" then
        ARC:SessionBonusRollResult(...)
    elseif event == "BONUS_ROLL_FAILED" then
        ARC:SessionBonusRollFailed(...)
    end
end)
tracker:SetScript("OnUpdate", function(_, elapsed)
    tracker.elapsed = (tracker.elapsed or 0) + elapsed
    tracker.rosterElapsed = (tracker.rosterElapsed or 0) + elapsed
    if tracker.elapsed >= 1 then
        tracker.elapsed = 0
        ARC:TickTrashInactivity()
        ARC:UpdateAutoSession()
        ARC:ResolveSessionLoot()
    end
    if tracker.rosterElapsed >= 5 then
        tracker.rosterElapsed = 0
        ARC:UpdateSessionRoster()
    end
end)
