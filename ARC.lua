local ADDON_NAME = ...
local ARC = assert(_G.ARC, "ARC_Core.lua must load before ARC.lua")
local I = assert(ARC.Internal, "ARC internal API is unavailable")
local ARC_InitDB = I.ARC_InitDB
local RefreshUnitPublicData = I.RefreshUnitPublicData
local HandleCommMessage = I.HandleCommMessage
local SetFrameShown = I.SetFrameShown

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
eventFrame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
eventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
eventFrame:RegisterEvent("PLAYER_ALIVE")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED") -- combat start = the pull
eventFrame:RegisterEvent("CHAT_MSG_ADDON")
eventFrame:RegisterEvent("INSPECT_READY")

local elapsedAccum = 0

eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        local addon = ...
        if addon == ADDON_NAME then
            ARC_InitDB()
            if RegisterAddonMessagePrefix then
                RegisterAddonMessagePrefix(ARC.COMM_PREFIX)
            elseif C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
                C_ChatInfo.RegisterAddonMessagePrefix(ARC.COMM_PREFIX)
            end
            -- Build these directly so Lua errors reach the normal WoW error
            -- handler instead of silently removing the affected UI.
            ARC:CreateMinimapButton()
            ARC:CreateOptionsPanel()
        elseif addon == "ElvUI" then
            -- Covers the case where ARC's frame already exists and ElvUI
            -- only finishes loading afterward.
            ARC:TrySkinElvUI()
        end

    elseif event == "PLAYER_ENTERING_WORLD" then
        ARC.selfDirty = true
        -- Second chance at ElvUI skinning: some ElvUI forks finish their
        -- own module setup slightly after ADDON_LOADED fires for them.
        ARC:TrySkinElvUI()

    elseif event == "READY_CHECK" then
        local initiator = ...
        ARC.readyCheckActive    = true
        ARC.readyCheckFinished  = false
        ARC.readyCheckInitiator = initiator
        -- Start every entry fresh so old X/check icons from a previous
        -- check don't linger for a tick before the first refresh.
        for _, e in pairs(ARC.roster) do
            e.ready = nil
        end
        ARC:Show()

    elseif event == "READY_CHECK_CONFIRM" then
        local unit = ...
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
        if ARC:IsVisible() then ARC:Render() end

    elseif event == "GROUP_ROSTER_UPDATE" then
        if ARC:IsVisible() then
            ARC:RefreshRoster()
            ARC:Render()
        end
        ARC.selfDirty = true

    elseif event == "UNIT_AURA" then
        local unit = ...
        if unit and (unit == "player" or unit:match("^party%d") or unit:match("^raid%d")) then
            if ARC:IsVisible() then
                RefreshUnitPublicData(unit)
            end
            if unit == "player" then ARC.selfDirty = true end
        end

    elseif event == "PLAYER_EQUIPMENT_CHANGED" or event == "PLAYER_ALIVE" or event == "PLAYER_REGEN_ENABLED" then
        ARC.selfDirty = true
        if event == "PLAYER_EQUIPMENT_CHANGED" then ARC.forceSelfGearScan = true end

    elseif event == "PLAYER_REGEN_DISABLED" then
        -- Entering combat = the pull. Hide immediately rather than waiting
        -- on a timer after the ready check finished.
        if ARC_DB.autoHide and ARC:IsVisible() then
            ARC:Hide()
        end

    elseif event == "PLAYER_SPECIALIZATION_CHANGED" then
        local unit = ...
        if unit == "player" then ARC.selfDirty = true end

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

    if ARC.selfDirty then
        RefreshUnitPublicData("player")
        ARC:BroadcastSelf(false)
    end

    if ARC:IsVisible() then
        ARC:RefreshRoster()
        ARC:Render() -- also refreshes the title's countdown text every second
        ARC.QueueInspectCandidates()
    end

    ARC.TryNextInspect()
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
    elseif msg == "minimap" then
        ARC_DB.minimap.hide = not ARC_DB.minimap.hide
        if ARC.minimapButton then
            SetFrameShown(ARC.minimapButton, not ARC_DB.minimap.hide)
        end
        print("|cff33ff99ARC:|r minimap button is now " .. (ARC_DB.minimap.hide and "OFF" or "ON") .. ".")
    elseif msg == "options" or msg == "config" then
        ARC:OpenOptions()
    elseif msg == "help" then
        print("|cff33ff99ARC commands:|r")
        print("  /arc            - show/hide the window")
        print("  /arc lock       - lock window position")
        print("  /arc unlock     - unlock window position")
        print("  /arc reset      - reset window position")
        print("  /arc autohide   - toggle auto-hide when you enter combat (pull)")
        print("  /arc minimap    - toggle the minimap button")
        print("  /arc options    - open the options panel")
        print("  Right-click a player row for Whisper / Inspect / Remind.")
    else
        print("|cff33ff99ARC:|r unknown command. Try /arc help")
    end
end
