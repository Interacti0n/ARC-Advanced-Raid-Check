local ADDON_NAME = ...
local ARC = assert(_G.ARC, "ARC_Core.lua must load before ARC.lua")
local I = assert(ARC.Internal, "ARC internal API is unavailable")
local ARC_InitDB = I.ARC_InitDB
local RefreshUnitPublicData = I.RefreshUnitPublicData
local HandleCommMessage = I.HandleCommMessage
local SetFrameShown = I.SetFrameShown

-- A MoP /reload can reuse the TOC cached at client startup. After an update
-- that adds a file, the old modules can reload without the new player check.
-- Keep the raid UI working, but make the unavailable feature explicit.
local playerCheckWarningShown = false
local function HasPlayerCheck(notify, repeatWarning)
    if type(ARC.AttachInspectCheckButton) == "function" and
        type(ARC.ShowPlayerCheck) == "function" and
        type(ARC.UpdatePlayerCheck) == "function" then
        return true
    end
    if notify and (repeatWarning or not playerCheckWarningShown) then
        playerCheckWarningShown = true
        print("|cffffcc00ARC:|r Player check module is not loaded (ARC_PlayerCheck.lua). " ..
            "Fully exit WoW and start it again; /reload is not enough after adding addon files. " ..
            "If this persists, reinstall the complete ARC update and check earlier Lua errors.")
    end
    return false
end

--=============================================================================
-- EVENT HANDLING
--=============================================================================

local eventFrame = CreateFrame("Frame", "ARCEventFrame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("READY_CHECK")
eventFrame:RegisterEvent("READY_CHECK_CONFIRM")
eventFrame:RegisterEvent("READY_CHECK_FINISHED")
eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
eventFrame:RegisterEvent("UNIT_AURA")
eventFrame:RegisterEvent("PLAYER_FLAGS_CHANGED")
eventFrame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
eventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
eventFrame:RegisterEvent("PLAYER_TALENT_UPDATE")
eventFrame:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED")
eventFrame:RegisterEvent("PLAYER_LEVEL_UP")
eventFrame:RegisterEvent("UNIT_PET")
eventFrame:RegisterEvent("PET_BAR_UPDATE")
eventFrame:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
eventFrame:RegisterEvent("BAG_UPDATE")
eventFrame:RegisterEvent("PARTY_LOOT_METHOD_CHANGED")
eventFrame:RegisterEvent("PLAYER_DIFFICULTY_CHANGED")
eventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
eventFrame:RegisterEvent("PLAYER_ALIVE")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED") -- combat start = the pull
eventFrame:RegisterEvent("CHAT_MSG_ADDON")
eventFrame:RegisterEvent("INSPECT_READY")

local elapsedAccum, fullRefreshAccum = 0, 0

eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        local addon = ...
        if addon == ADDON_NAME then
            ARC_InitDB()
            if ARC.InitSessionTracker then ARC:InitSessionTracker() end
            if RegisterAddonMessagePrefix then
                RegisterAddonMessagePrefix(ARC.COMM_PREFIX)
            elseif C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
                C_ChatInfo.RegisterAddonMessagePrefix(ARC.COMM_PREFIX)
            end
            -- Build these directly so Lua errors reach the normal WoW error
            -- handler instead of silently removing the affected UI.
            ARC:CreateMinimapButton()
            ARC:CreateOptionsPanel()
            ARC:InitInspectHooks()
            if HasPlayerCheck(true) then ARC:AttachInspectCheckButton() end
            if ARC.InitPlayerCheckMenu then ARC:InitPlayerCheckMenu() end
        elseif addon == "Blizzard_InspectUI" then
            if HasPlayerCheck(true) then ARC:AttachInspectCheckButton() end
        elseif addon == "ElvUI" then
            -- Covers the case where ARC's frame already exists and ElvUI
            -- only finishes loading afterward.
            ARC:TrySkinElvUI()
            if ARC.TrySkinSessionUI then ARC:TrySkinSessionUI() end
        end

    elseif event == "PLAYER_ENTERING_WORLD" then
        ARC.selfDirty = true
        -- Second chance at ElvUI skinning: some ElvUI forks finish their
        -- own module setup slightly after ADDON_LOADED fires for them.
        ARC:TrySkinElvUI()
        if HasPlayerCheck(true) then ARC:AttachInspectCheckButton() end
        if ARC.InitPlayerCheckMenu then ARC:InitPlayerCheckMenu() end

    elseif event == "READY_CHECK" then
        local initiator, duration = ...
        ARC.readyCheckActive    = true
        ARC.readyCheckResponded = false
        duration = tonumber(duration)
        ARC.readyCheckExpiresAt = duration and duration > 0 and (GetTime() + duration) or nil
        ARC.readyCheckFinished  = false
        ARC.readyCheckInitiator = initiator
        -- Start every entry fresh so old X/check icons from a previous
        -- check don't linger for a tick before the first refresh.
        for _, e in pairs(ARC.roster) do
            e.ready = nil
        end
        if ARC_DB.manualMode then
            ARC:RefreshRoster()
            if ARC:IsVisible() then ARC:Render() end
        else
            ARC:Show()
        end

    elseif event == "READY_CHECK_CONFIRM" then
        local unit = ...
        if unit and UnitIsUnit(unit, "player") then ARC.readyCheckResponded = true end
        RefreshUnitPublicData(unit)
        ARC:Render()

    elseif event == "READY_CHECK_FINISHED" then
        ARC.readyCheckActive   = false
        ARC.readyCheckFinished = true
        -- Freeze results: anyone who never answered (still "waiting"/nil)
        -- is locked in as "not ready" (X icon) so the outcome stays visible
        -- and legible until the raid pulls.
        for _, e in pairs(ARC.roster) do
            if e.ready == "waiting" or e.ready == nil then
                e.ready = "notready"
            end
        end
        if ARC.SessionReadyCheckFinished then ARC:SessionReadyCheckFinished() end
        if ARC:IsVisible() then ARC:Render() end

    elseif event == "GROUP_ROSTER_UPDATE" then
        if ARC:IsVisible() then
            ARC:RefreshRoster()
            fullRefreshAccum = 0
            ARC:Render()
        end
        ARC.selfDirty = true

    elseif event == "UNIT_AURA" then
        local unit = ...
        if unit and (unit == "player" or unit:match("^party%d") or unit:match("^raid%d")) then
            if ARC:IsVisible() then
                RefreshUnitPublicData(unit)
                ARC:Render()
            end
            if unit == "player" then ARC.selfDirty = true end
        end

    elseif event == "PLAYER_FLAGS_CHANGED" then
        local unit = ...
        if unit and (unit == "player" or unit:match("^party%d") or unit:match("^raid%d")) and ARC:IsVisible() then
            ARC:RefreshRosterStatus()
            ARC:Render()
        end

    elseif event == "PLAYER_EQUIPMENT_CHANGED" or event == "PLAYER_ALIVE" or event == "PLAYER_REGEN_ENABLED" then
        ARC.selfDirty = true
        if event == "PLAYER_REGEN_ENABLED" and ARC.EndTrashCombat then ARC:EndTrashCombat() end
        if event == "PLAYER_EQUIPMENT_CHANGED" then ARC.forceSelfGearScan = true end

    elseif event == "PLAYER_REGEN_DISABLED" then
        if ARC.StartTrashCombat then ARC:StartTrashCombat() end
        -- Entering combat = the pull. Hide immediately rather than waiting
        -- on a timer after the ready check finished.
        if ARC_DB.autoHide and ARC:IsVisible() then
            ARC:Hide()
        end

    elseif event == "PLAYER_SPECIALIZATION_CHANGED" then
        local unit = ...
        if unit == "player" then ARC.selfDirty = true; ARC.forceSelfGearScan = true end
        if unit and UnitExists(unit) then
            local key = I.GetUnitIdentity(unit)
            local e = key and ARC.roster[key]
            if e then e.talents, e.lastGearScan, e.specID, e.specSource, e.sacrifice = nil, nil, nil, nil, nil end
        end

    elseif event == "PLAYER_TALENT_UPDATE" or event == "ACTIVE_TALENT_GROUP_CHANGED" or event == "PLAYER_LEVEL_UP" then
        ARC.selfDirty = true
        if event == "ACTIVE_TALENT_GROUP_CHANGED" then ARC.forceSelfGearScan = true end

    elseif event == "PET_BAR_UPDATE" or event == "BAG_UPDATE" or event == "UPDATE_SHAPESHIFT_FORM" then
        ARC.selfDirty = true

    elseif event == "UNIT_PET" then
        local unit = ...
        if unit and UnitIsUnit(unit, "player") then ARC.selfDirty = true end
        if ARC:IsVisible() and unit and UnitExists(unit) then
            RefreshUnitPublicData(unit)
            ARC:Render()
        end

    elseif event == "PARTY_LOOT_METHOD_CHANGED" or event == "PLAYER_DIFFICULTY_CHANGED" or event == "ZONE_CHANGED_NEW_AREA" then
        if ARC:IsVisible() then ARC:Render() end

    elseif event == "CHAT_MSG_ADDON" then
        local prefix, msg, _, sender = ...
        if prefix == ARC.COMM_PREFIX then
            HandleCommMessage(sender, msg)
            if ARC:IsVisible() then ARC:Render() end
        end

    elseif event == "INSPECT_READY" then
        local guid = ...
        ARC.OnInspectReady(guid)
    end
end)

eventFrame:SetScript("OnUpdate", function(self, elapsed)
    elapsedAccum = elapsedAccum + elapsed
    if elapsedAccum < ARC.REFRESH_EVERY then return end
    elapsedAccum = 0

    -- Weapon imbues do not reliably generate UNIT_AURA. Refresh our readiness
    -- report even with the window closed; expiry bounds remote imbue trust.
    if (IsInGroup() or IsInRaid()) and GetTime() - ARC.lastSelfBroadcast >= 15 then ARC.selfDirty = true end
    if ARC.selfDirty then
        RefreshUnitPublicData("player")
        ARC:BroadcastSelf(false)
    end

    if ARC:IsVisible() then
        fullRefreshAccum = fullRefreshAccum + ARC.REFRESH_EVERY
        if fullRefreshAccum >= ARC.FULL_REFRESH_EVERY then
            ARC:RefreshRoster()
            fullRefreshAccum = 0
        else
            ARC:RefreshRosterStatus()
        end
        ARC:Render() -- also refreshes the title's countdown text every second
        ARC.QueueInspectCandidates()
    end

    ARC.TryNextInspect()
    if HasPlayerCheck(false) then ARC:UpdatePlayerCheck() end
end)

--=============================================================================
-- SLASH COMMANDS
--=============================================================================

local function Trim(s)
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

SLASH_ARC1 = "/arc"
SlashCmdList["ARC"] = function(rawMsg)
    local msg = Trim((rawMsg or ""):lower())

    if msg == "" then
        ARC:Toggle()
    elseif msg == "raid" then
        ARC:OpenRaidOptions()
    elseif msg == "lock" then
        ARC_DB.locked = true
        print("|cff33ff99ARC:|r window locked.")
    elseif msg == "unlock" then
        ARC_DB.locked = false
        print("|cff33ff99ARC:|r window unlocked.")
    elseif msg == "reset" then
        ARC_DB.point = { "CENTER", "UIParent", "CENTER", 0, 150 }
        if ARC.frame then
            ARC.frame:ClearAllPoints()
            ARC.frame:SetPoint(unpack(ARC_DB.point))
        end
        print("|cff33ff99ARC:|r position reset.")
    elseif msg == "autohide" then
        ARC_DB.autoHide = not ARC_DB.autoHide
        print("|cff33ff99ARC:|r auto-hide on pull is now " .. (ARC_DB.autoHide and "ON" or "OFF") .. ".")
    elseif msg == "manual" or msg:match("^manual%s") then
        local value = msg:match("^manual%s+(.+)$")
        if value and value ~= "on" and value ~= "off" then
            print("|cff33ff99ARC:|r Usage: /arc manual [on|off]")
            return
        end
        local enabled = not ARC_DB.manualMode
        if value then enabled = value == "on" end
        ARC:SetManualMode(enabled)
        print("|cff33ff99ARC:|r manual opening mode is " .. (enabled and "ON" or "OFF") .. ".")
    elseif msg == "minimap" then
        ARC_DB.minimap.hide = not ARC_DB.minimap.hide
        if ARC.minimapButton then
            SetFrameShown(ARC.minimapButton, not ARC_DB.minimap.hide)
        end
        print("|cff33ff99ARC:|r minimap button is now " .. (ARC_DB.minimap.hide and "OFF" or "ON") .. ".")
    elseif msg == "options" or msg == "config" then
        ARC:OpenOptions()
    elseif msg == "check" then
        if HasPlayerCheck(true, true) then ARC:ShowPlayerCheck("target") end
    elseif msg == "session" or msg == "report" then
        if ARC.ShowSessionReport then ARC:ShowSessionReport() end
    elseif msg == "session start" then
        if ARC.StartRaidSession then ARC:StartRaidSession() end
    elseif msg == "session end" then
        if ARC.EndRaidSession then ARC:EndRaidSession() end
    elseif msg == "help" then
        print("|cff33ff99ARC commands:|r")
        print("  /arc            - show/hide the window")
        print("  /arc lock       - lock window position")
        print("  /arc unlock     - unlock window position")
        print("  /arc reset      - reset window position")
        print("  /arc autohide   - toggle auto-hide when you enter combat (pull)")
        print("  /arc manual [on|off] - toggle or set manual-only window opening")
        print("  /arc minimap    - toggle the minimap button")
        print("  /arc options    - open the options panel")
        print("  /arc check      - player overview and PvE gear problems (no group required)")
        print("  /arc session [start|end] - raid attendance, pulls, AFK and trash inactivity report")
        print("  Right-click a player portrait or ARC row for ARC Check.")
        print("  /arc raid - expected raid mode/size and loot method; also click the setup banner.")
        print("  Talents = empty available talents; Self = missing class buffs. ? means unverified.")
        print("  Self also checks tank stances/RF and pets/Sacrifice/Growl. HS = reported Healthstone uses; ? = unknown.")
        print("  ARC rows also offer Whisper / Inspect / Remind.")
        print("  Ready / Not Ready at the top answer your active ready check.")
        print("  Minimum item level: type 400-600 in Options; save with Enter or Apply.")
        print("  Gear checks: MoP rare+ gems, enchant tier, primary stats and PvP bonuses.")
        print("  Yellow Unverified / ? means unknown data, not a passed gear check.")
    else
        print("|cff33ff99ARC:|r unknown command. Try /arc help")
    end
end
