local ARC = assert(_G.ARC, "ARC_Core.lua must load before ARC_Options.lua")
local I = assert(ARC.Internal, "ARC internal API is unavailable")
local Round = I.Round
local SetFrameShown = I.SetFrameShown

function ARC:SetManualMode(enabled)
    ARC_DB.manualMode = enabled and true or false
    if ARCOptionsManual then ARCOptionsManual:SetChecked(ARC_DB.manualMode) end
end

function ARC:SetMinimumItemLevel(text)
    local value = tonumber(text)
    if not value or value < 400 or value > 600 or value ~= math.floor(value) then
        return false, "Enter a whole number from 400 to 600."
    end
    if ARC_DB.minItemLevel ~= value then
        ARC_DB.minItemLevel = value
        for _, entry in pairs(self.roster) do
            entry.lastGearScan, entry.gear = nil, nil
        end
        self.forceSelfGearScan, self.selfDirty = true, true
    end
    return true
end

--=============================================================================
-- MINIMAP BUTTON
-- A small, self-contained minimap button - deliberately built with plain
-- Frame/Button API rather than LibDBIcon/LibDataBroker. This sandbox has no
-- network access, so I can't fetch and verify real library source against
-- your client; hand-rolling it avoids embedding unverified library code and
-- keeps ARC a drop-in two-file addon with zero external dependencies. If
-- you'd rather use LibDBIcon (e.g. to match other addons' minimap buttons
-- in a "minimap button bag"), let me know and supply the library files (or
-- confirm another addon already embeds them) and I'll wire ARC into that
-- instead - just say the word.
--=============================================================================

local function UpdateMinimapButtonPosition(btn)
    local angle = math.rad(ARC_DB.minimap.angle or 200)
    local radius = 80
    local x, y = math.cos(angle) * radius, math.sin(angle) * radius
    btn:ClearAllPoints()
    btn:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

function ARC:CreateMinimapButton()
    local btn = CreateFrame("Button", "ARCMinimapButton", Minimap)
    btn:SetSize(31, 31)
    btn:SetFrameStrata("MEDIUM")
    btn:SetFrameLevel(8)
    btn:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    btn:RegisterForDrag("LeftButton")

    local overlay = btn:CreateTexture(nil, "OVERLAY")
    overlay:SetSize(53, 53)
    overlay:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    overlay:SetPoint("TOPLEFT", 0, 0)

    local bg = btn:CreateTexture(nil, "BACKGROUND")
    bg:SetSize(20, 20)
    bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    bg:SetPoint("CENTER", 0, 0)

    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetSize(19, 19)
    icon:SetTexture("Interface\\Icons\\INV_Misc_GroupLooking") -- swap this line for any icon you prefer
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    icon:SetPoint("CENTER", 1, 1)
    btn.icon = icon

    btn:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function(self)
            local mx, my = Minimap:GetCenter()
            local px, py = GetCursorPosition()
            local scale = Minimap:GetEffectiveScale()
            px, py = px / scale, py / scale
            ARC_DB.minimap.angle = math.deg(math.atan2(py - my, px - mx))
            UpdateMinimapButtonPosition(self)
        end)
    end)
    btn:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
    end)

    btn:SetScript("OnClick", function(self, button)
        if button == "LeftButton" then
            ARC:Toggle()
        elseif button == "RightButton" then
            ARC:OpenOptions()
        end
    end)

    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("ARC - " .. ARC.NAME)
        GameTooltip:AddLine("Left-click: show/hide window", 0.8, 0.8, 0.8)
        GameTooltip:AddLine("Right-click: options", 0.8, 0.8, 0.8)
        GameTooltip:AddLine("Drag: move this button", 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    UpdateMinimapButtonPosition(btn)
    SetFrameShown(btn, not ARC_DB.minimap.hide)

    ARC.minimapButton = btn
    return btn
end

--=============================================================================
-- OPTIONS PANEL (Interface Options)
--=============================================================================

local function SetCheckButtonText(cb, text)
    local fs = cb.Text or (cb:GetName() and _G[cb:GetName() .. "Text"])
    if fs then fs:SetText(text) end
end

local function SetSliderLabels(slider, low, high, text)
    local name = slider:GetName()
    local lowFS  = slider.Low  or (name and _G[name .. "Low"])
    local highFS = slider.High or (name and _G[name .. "High"])
    local textFS = slider.Text or (name and _G[name .. "Text"])
    if lowFS then lowFS:SetText(low) end
    if highFS then highFS:SetText(high) end
    if textFS then textFS:SetText(text) end
end

function ARC:CreateOptionsPanel()
    local panel = CreateFrame("Frame", "ARCOptionsPanel", UIParent)
    panel.name = "ARC"

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("ARC - " .. ARC.NAME)

    local subtitle = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    subtitle:SetWidth(500)
    subtitle:SetJustifyH("LEFT")
    subtitle:SetText("Version " .. ARC.VERSION .. "  -  see /arc help for slash commands")

    local manualCB = CreateFrame("CheckButton", "ARCOptionsManual", panel, "InterfaceOptionsCheckButtonTemplate")
    manualCB:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", -2, -20)
    SetCheckButtonText(manualCB, "Manual opening only (do not open ARC on ready checks)")
    manualCB:SetScript("OnClick", function(self) ARC:SetManualMode(self:GetChecked()) end)

    local autohideCB = CreateFrame("CheckButton", "ARCOptionsAutoHide", panel, "InterfaceOptionsCheckButtonTemplate")
    autohideCB:SetPoint("TOPLEFT", manualCB, "BOTTOMLEFT", 0, -4)
    SetCheckButtonText(autohideCB, "Auto-hide when you enter combat (the pull)")
    autohideCB:SetScript("OnClick", function(self)
        ARC_DB.autoHide = self:GetChecked() and true or false
    end)

    local lockCB = CreateFrame("CheckButton", "ARCOptionsLock", panel, "InterfaceOptionsCheckButtonTemplate")
    lockCB:SetPoint("TOPLEFT", autohideCB, "BOTTOMLEFT", 0, -4)
    SetCheckButtonText(lockCB, "Lock window position (disable dragging)")
    lockCB:SetScript("OnClick", function(self)
        ARC_DB.locked = self:GetChecked() and true or false
    end)

    local minimapCB = CreateFrame("CheckButton", "ARCOptionsMinimap", panel, "InterfaceOptionsCheckButtonTemplate")
    minimapCB:SetPoint("TOPLEFT", lockCB, "BOTTOMLEFT", 0, -4)
    SetCheckButtonText(minimapCB, "Show minimap button")
    minimapCB:SetScript("OnClick", function(self)
        ARC_DB.minimap.hide = not self:GetChecked()
        if ARC.minimapButton then
            SetFrameShown(ARC.minimapButton, not ARC_DB.minimap.hide)
        end
    end)

    local scaleSlider = CreateFrame("Slider", "ARCOptionsScale", panel, "OptionsSliderTemplate")
    scaleSlider:SetPoint("TOPLEFT", minimapCB, "BOTTOMLEFT", 6, -28)
    scaleSlider:SetWidth(200)
    scaleSlider:SetMinMaxValues(0.6, 1.5)
    scaleSlider:SetValueStep(0.05)
    SetSliderLabels(scaleSlider, "0.6", "1.5", "Window Scale")

    local scaleValueText = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    scaleValueText:SetPoint("LEFT", scaleSlider, "RIGHT", 12, 0)

    scaleSlider:SetScript("OnValueChanged", function(self, value)
        value = Round(value * 20) / 20 -- snap to 0.05 steps
        ARC_DB.scale = value
        if ARC.frame then ARC.frame:SetScale(value) end
        scaleValueText:SetText(string.format("%.2f", value))
    end)

    local ilvlLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    ilvlLabel:SetPoint("TOPLEFT", scaleSlider, "BOTTOMLEFT", 0, -30)
    ilvlLabel:SetText("Minimum Item Level")
    local ilvlInput = CreateFrame("EditBox", "ARCOptionsMinIlvl", panel, "InputBoxTemplate")
    ilvlInput:SetSize(80, 22)
    ilvlInput:SetPoint("TOPLEFT", ilvlLabel, "BOTTOMLEFT", 4, -8)
    ilvlInput:SetAutoFocus(false)
    ilvlInput:SetNumeric(true)
    ilvlInput:SetMaxLetters(3)
    local ilvlApply = CreateFrame("Button", "ARCOptionsMinIlvlApply", panel, "UIPanelButtonTemplate")
    ilvlApply:SetSize(70, 22)
    ilvlApply:SetPoint("LEFT", ilvlInput, "RIGHT", 12, 0)
    ilvlApply:SetText("Apply")
    local ilvlMessage = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    ilvlMessage:SetPoint("TOPLEFT", ilvlInput, "BOTTOMLEFT", -4, -8)
    ilvlMessage:SetText("400-600. Enter or Apply to save; Escape to cancel.")
    local function ApplyItemLevel()
        local ok, reason = ARC:SetMinimumItemLevel(ilvlInput:GetText())
        if ok then
            ilvlInput:SetText(tostring(ARC_DB.minItemLevel))
            ilvlInput:ClearFocus()
            ilvlMessage:SetText("Saved: " .. ARC_DB.minItemLevel)
        else
            ilvlMessage:SetText(reason)
        end
        ilvlMessage:SetTextColor(ok and 0.3 or 1, ok and 1 or 0.35, 0.3)
    end
    ilvlInput:SetScript("OnEnterPressed", ApplyItemLevel)
    ilvlApply:SetScript("OnClick", ApplyItemLevel)
    ilvlInput:SetScript("OnEscapePressed", function(self)
        self:SetText(tostring(ARC_DB.minItemLevel))
        self:ClearFocus()
        ilvlMessage:SetText("Unchanged: " .. ARC_DB.minItemLevel)
        ilvlMessage:SetTextColor(0.9, 0.9, 0.9)
    end)

    local resetBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    resetBtn:SetSize(160, 22)
    resetBtn:SetPoint("TOPLEFT", ilvlMessage, "BOTTOMLEFT", -6, -16)
    resetBtn:SetText("Reset Window Position")
    resetBtn:SetScript("OnClick", function()
        ARC_DB.point = { "CENTER", "UIParent", "CENTER", 0, 150 }
        if ARC.frame then
            ARC.frame:ClearAllPoints()
            ARC.frame:SetPoint(unpack(ARC_DB.point))
        end
    end)

    local raidBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    raidBtn:SetSize(160, 22)
    raidBtn:SetPoint("LEFT", resetBtn, "RIGHT", 12, 0)
    raidBtn:SetText("Raid Setup Checks")
    raidBtn:SetScript("OnClick", function() ARC:OpenRaidOptions() end)

    local hint = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", resetBtn, "BOTTOMLEFT", 6, -20)
    hint:SetWidth(480)
    hint:SetJustifyH("LEFT")
    hint:SetText("Tip: right-click a player row for Whisper / Inspect / ARC Check / Remind. Click the raid setup banner to choose expected settings. Talents = empty talents; Self = class/tank/pet checks; HS = Healthstone uses; ? = unverified.")

    panel.refresh = function()
        manualCB:SetChecked(ARC_DB.manualMode)
        autohideCB:SetChecked(ARC_DB.autoHide)
        lockCB:SetChecked(ARC_DB.locked)
        minimapCB:SetChecked(not ARC_DB.minimap.hide)
        scaleSlider:SetValue(ARC_DB.scale or 1.0)
        ilvlInput:SetText(tostring(ARC_DB.minItemLevel or 450))
        ilvlInput:ClearFocus()
        ilvlMessage:SetText("400-600. Enter or Apply to save; Escape to cancel.")
        ilvlMessage:SetTextColor(0.9, 0.9, 0.9)
    end

    if InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(panel)
    end

    ARC.optionsPanel = panel
    return panel
end

function ARC:CreateRaidOptions()
    if self.raidOptionsPanel then return self.raidOptionsPanel end
    local panel = CreateFrame("Frame", "ARCRaidOptionsPanel", UIParent)
    panel.name, panel.parent = "Raid setup", "ARC"
    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("ARC - Expected Raid Setup")
    local explanation = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    explanation:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -12)
    explanation:SetWidth(480)
    explanation:SetJustifyH("LEFT")
    explanation:SetText("Choose your expected raid mode (including size) and loot method. A mismatch makes the ARC banner RED. These checks never change the actual raid settings or send chat. Changes here save immediately.")
    local enabled = CreateFrame("CheckButton", "ARCRaidSetupEnabled", panel, "InterfaceOptionsCheckButtonTemplate")
    enabled:SetPoint("TOPLEFT", explanation, "BOTTOMLEFT", -2, -16)
    SetCheckButtonText(enabled, "Check raid setup")
    enabled:SetScript("OnClick", function(self)
        ARC_DB.raidSetup.enabled = self:GetChecked() and true or false
        ARC:Render()
    end)
    local dropdown = CreateFrame("Frame", "ARCRaidSetupDropdown", panel, "UIDropDownMenuTemplate")
    local function Choice(name, field, labels, values, previous)
        local button = CreateFrame("Button", name, panel, "UIPanelButtonTemplate")
        button:SetSize(310, 26)
        button:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 2, -16)
        button:SetScript("OnClick", function(self)
            local menu = {}
            for _, value in ipairs(values) do
                local chosen = value
                menu[#menu + 1] = { text = labels[value], checked = ARC_DB.raidSetup[field] == value,
                    func = function()
                        ARC_DB.raidSetup[field] = chosen
                        if CloseDropDownMenus then CloseDropDownMenus() end
                        panel.refresh(); ARC:Render()
                    end }
            end
            EasyMenu(menu, dropdown, self, 0, 0, "MENU")
        end)
        return button
    end
    panel.mode = Choice("ARCRaidSetupMode", "difficulty", ARC.RAID_DIFFICULTIES, { 0,3,4,5,6,7,14 }, enabled)
    panel.loot = Choice("ARCRaidSetupLoot", "loot", ARC.LOOT_METHODS, { "any","master","group","needbeforegreed","freeforall","roundrobin" }, panel.mode)
    local note = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    note:SetPoint("TOPLEFT", panel.loot, "BOTTOMLEFT", 0, -18)
    note:SetWidth(480)
    note:SetJustifyH("LEFT")
    note:SetText("Inside a raid, ARC checks the actual instance difficulty. Outside it, ARC checks the selected raid difficulty. 10/25 is the mode's capacity, not the number of players currently invited. Not checked skips only that setting; unavailable data never passes.")
    panel.refresh = function()
        enabled:SetChecked(ARC_DB.raidSetup.enabled)
        panel.mode:SetText("Mode / size: " .. ARC.RAID_DIFFICULTIES[ARC_DB.raidSetup.difficulty])
        panel.loot:SetText("Loot: " .. ARC.LOOT_METHODS[ARC_DB.raidSetup.loot])
    end
    if InterfaceOptions_AddCategory then InterfaceOptions_AddCategory(panel) end
    panel.refresh()
    self.raidOptionsPanel = panel
    return panel
end

function ARC:OpenRaidOptions()
    local panel = self:CreateRaidOptions()
    if InterfaceOptionsFrame_OpenToCategory then
        InterfaceOptionsFrame_OpenToCategory(panel)
        InterfaceOptionsFrame_OpenToCategory(panel)
    end
end

function ARC:OpenOptions()
    if not self.optionsPanel then
        self.optionsPanel = self:CreateOptionsPanel()
    end
    if InterfaceOptionsFrame_OpenToCategory then
        InterfaceOptionsFrame_OpenToCategory(self.optionsPanel)
        InterfaceOptionsFrame_OpenToCategory(self.optionsPanel) -- Blizzard's classic double-call quirk
    end
end
