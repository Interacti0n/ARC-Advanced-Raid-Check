local ARC = assert(_G.ARC, "ARC_Core.lua must load before ARC_Inspect.lua")
local I = assert(ARC.Internal, "ARC internal API is unavailable")
local GetGroupUnits = I.GetGroupUnits
local GetUnitIdentity = I.GetUnitIdentity

--=============================================================================
-- INSPECT FALLBACK (for players who don't run ARC)
-- Fills in spec and runs the upgrade-aware gear scan. Durability of others is
-- not retrievable through any public API and is intentionally left blank.
--=============================================================================

ARC.inspectUnit = nil
ARC.inspectStartedAt = 0

local function UnitInspectable(unit)
    -- Be defensive: not every one of these APIs is guaranteed to exist, and
    -- Missing optional APIs are tolerated; failed range checks are not.
    if not unit or not UnitExists(unit) then return false end
    if UnitIsPlayer and not UnitIsPlayer(unit) then return false end
    if UnitIsConnected and not UnitIsConnected(unit) then return false end
    if UnitIsVisible and not UnitIsVisible(unit) then return false end
    if CanInspect then
        local ok, result = pcall(CanInspect, unit)
        if not ok or not result then return false end
    end
    return true
end

local function QueueInspectCandidates()
    if not NotifyInspect then return end
    wipe(ARC.inspectQueue)
    local now = GetTime()
    for _, unit in ipairs(GetGroupUnits()) do
        if not UnitIsUnit(unit, "player") and UnitExists(unit) then
            local fullName = GetUnitIdentity(unit)
            local e = fullName and ARC.roster[fullName]
            if e and ((not e.lastGearScan) or (now - e.lastGearScan) > 60) then
                local lastTry = e.lastInspectAttempt or 0
                if (now - lastTry) > ARC.INSPECT_RETRY_GAP and UnitInspectable(unit) then
                    ARC.inspectQueue[#ARC.inspectQueue + 1] = unit
                end
            end
        end
    end
end

local function FinishRequest(request, status, message)
    if ARC.inspectRequest ~= request then return end
    ARC.inspectRequest, ARC.inspectUnit = nil, nil
    -- Inspect state is shared with Blizzard and other addons. Never clear
    -- their cache when ARC finishes, times out or closes its detail window.
    if request.callback then request.callback(request, status, message) end
end

local function SameUnit(request)
    return UnitExists(request.unit) and UnitGUID(request.unit) == request.guid
end

local function ScanRequest(request)
    if not SameUnit(request) or not UnitInspectable(request.unit) then
        FinishRequest(request, "error", "Player changed or left inspect range. Select the same player and refresh.")
        return
    end
    local e = request.entry
    if e.specSource ~= "comm" and GetInspectSpecialization then
        local specID = GetInspectSpecialization(request.unit)
        if specID and specID > 0 and GetSpecializationInfoByID then
            local id, name, _, icon, _, role = GetSpecializationInfoByID(specID)
            if id then
                e.specID, e.specName, e.specIcon, e.specSource = id, name, icon, "inspect"
                e.role = role
            end
        end
    end
    local level = ARC:AnalyzeUnitGear(request.unit, e)
    if ARC.ScanTalents then ARC:ScanTalents(request.unit, e, true) end
    if ARC.ScanSelfBuffs then e.selfBuffs = ARC:ScanSelfBuffs(request.unit, e) end
    if level and (request.kind == "manual" or not e.hasARC) then e.ilvl, e.ilvlApprox = level, true end
    if e.gear and e.gear.scanned and not e.gear.validationPending then
        FinishRequest(request, "complete", "Snapshot captured. Use Refresh after equipment changes.")
    end
end

function ARC:CancelPlayerInspect()
    local request = self.inspectRequest
    if request and request.kind == "manual" then
        FinishRequest(request, "cancelled", "Check cancelled.")
    end
end

function ARC:RequestPlayerInspect(unit, entry, callback)
    if not NotifyInspect or not UnitInspectable(unit) then
        return false, "Player is offline, unavailable or outside inspect range."
    end
    local guid = UnitGUID(unit)
    if not guid or guid ~= entry.guid then return false, "The inspected player changed." end
    local active = self.inspectRequest
    if active then FinishRequest(active, "cancelled", "A new manual check was requested.") end
    self.inspectRequest = {
        kind = "manual", unit = unit, guid = guid, entry = entry,
        queuedAt = GetTime(), callback = callback,
    }
    return true
end

local function TryNextInspect()
    local now = GetTime()
    local request = ARC.inspectRequest
    if not request then
        -- An open Blizzard inspect window has priority over background scans.
        if InspectFrame and InspectFrame:IsShown() then return end
        if now < (ARC.inspectNextAt or 0) then return end
        local unit = table.remove(ARC.inspectQueue, 1)
        if not UnitInspectable(unit) then return end
        local fullName = GetUnitIdentity(unit)
        local e = fullName and ARC.roster[fullName]
        if not e or (e.lastGearScan and now - e.lastGearScan <= 60) then return end
        request = { kind = "raid", unit = unit, guid = UnitGUID(unit), entry = e, queuedAt = now }
        ARC.inspectRequest = request
    end
    if not SameUnit(request) then
        FinishRequest(request, "error", "Player changed. This result will not follow a new target.")
        return
    end
    if request.startedAt then
        if request.ready then ScanRequest(request) end
        if ARC.inspectRequest == request and now - request.startedAt > 6 then
            FinishRequest(request, "error", "Inspect timed out or item data is incomplete. Try Refresh in range.")
        end
        return
    end
    if now - request.queuedAt > 12 then
        FinishRequest(request, "error", "Inspect is busy. Close other inspect tools and try Refresh.")
        return
    end
    if now < (ARC.inspectNextAt or 0) then return end
    if not UnitInspectable(request.unit) then
        FinishRequest(request, "error", "Player is no longer in inspect range.")
        return
    end
    request.startedAt = now
    request.entry.lastInspectAttempt = now
    ARC.inspectUnit, ARC.inspectStartedAt = request.unit, now
    ARC.inspectNextAt = now + 2
    ARC.sendingInspect = true
    local ok = pcall(NotifyInspect, request.unit)
    ARC.sendingInspect = false
    if not ok then FinishRequest(request, "error", "The client refused this inspect request.") end
end

local function OnInspectReady(guid)
    local request = ARC.inspectRequest
    if not request or not request.startedAt or guid ~= request.guid then return end
    request.ready = true
    ScanRequest(request)
end

function ARC:InitInspectHooks()
    if self.inspectHooksReady or not hooksecurefunc or not NotifyInspect then return end
    self.inspectHooksReady = true
    hooksecurefunc("NotifyInspect", function(unit)
        if ARC.sendingInspect then return end
        ARC.inspectNextAt = GetTime() + 2
        local request = ARC.inspectRequest
        if request and UnitGUID(unit) ~= request.guid then
            FinishRequest(request, "error", "Another inspect replaced this request. Try Refresh.")
        end
    end)
    if ClearInspectPlayer then
        hooksecurefunc("ClearInspectPlayer", function()
            local request = ARC.inspectRequest
            if request and request.startedAt then
                FinishRequest(request, "error", "Inspect data was cleared. Select the player and refresh.")
            end
        end)
    end
end

ARC.QueueInspectCandidates = QueueInspectCandidates
ARC.TryNextInspect = TryNextInspect
ARC.OnInspectReady = OnInspectReady
