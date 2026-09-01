local ARC = assert(_G.ARC, "ARC_Core.lua must load before ARC_Inspect.lua")
local I = assert(ARC.Internal, "ARC internal API is unavailable")
local GetGroupUnits = I.GetGroupUnits
local GetUnitIdentity = I.GetUnitIdentity
local GetOrCreateEntry = I.GetOrCreateEntry

--=============================================================================
-- INSPECT FALLBACK (for players who don't run ARC)
-- Fills in spec and runs the upgrade-aware gear scan. Durability of others is
-- not retrievable through any public API and is intentionally left blank.
--=============================================================================

ARC.inspectUnit = nil
ARC.inspectStartedAt = 0

local function UnitInspectable(unit)
    -- Be defensive: not every one of these APIs is guaranteed to exist, and
    -- a wrong/missing check should never hard-disable the feature - worst
    -- case NotifyInspect just times out after 2s and we move on.
    if UnitIsVisible and not UnitIsVisible(unit) then return false end
    if CanInspect then
        local ok, result = pcall(CanInspect, unit)
        if ok and result == false then return false end
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

local function TryNextInspect()
    if ARC.inspectUnit then
        -- currently waiting on one; give it up to 2s then move on
        if GetTime() - ARC.inspectStartedAt > 2.0 then
            ARC.inspectUnit = nil
            if ClearInspectPlayer then ClearInspectPlayer() end
        else
            return
        end
    end
    local unit = table.remove(ARC.inspectQueue, 1)
    if not unit or not UnitExists(unit) then return end
    local fullName = GetUnitIdentity(unit)
    local e = fullName and GetOrCreateEntry(fullName)
    if e then e.lastInspectAttempt = GetTime() end
    ARC.inspectUnit = unit
    ARC.inspectStartedAt = GetTime()
    NotifyInspect(unit)
end

local function OnInspectReady(guid)
    local unit = ARC.inspectUnit
    if not unit or not UnitExists(unit) then ARC.inspectUnit = nil; return end
    if UnitGUID(unit) ~= guid then return end
    local fullName = GetUnitIdentity(unit)
    local e = fullName and GetOrCreateEntry(fullName)
    if e then
        if e.specSource ~= "comm" and GetInspectSpecialization then
            local specID = GetInspectSpecialization(unit)
            if specID and specID > 0 and GetSpecializationInfoByID then
                local id, sname, _, icon, _, role = GetSpecializationInfoByID(specID)
                if id then
                    e.specID, e.specName, e.specIcon, e.specSource = id, sname, icon, "inspect"
                end
            end
        end
        local est = ARC:AnalyzeUnitGear(unit, e)
        if est then
            -- ARC reports remain authoritative; inspect is the fallback.
            if not e.hasARC then e.ilvl, e.ilvlApprox = est, true end
        end
    end
    ARC.inspectUnit = nil
    if ClearInspectPlayer then ClearInspectPlayer() end
end

ARC.QueueInspectCandidates = QueueInspectCandidates
ARC.TryNextInspect = TryNextInspect
ARC.OnInspectReady = OnInspectReady
