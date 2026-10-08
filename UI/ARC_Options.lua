local ARC = assert(_G.ARC, "Core/ARC_Core.lua must load before UI/ARC_Options.lua")
local I = assert(ARC.Internal, "ARC internal API is unavailable")
local Round = I.Round
local SetFrameShown = I.SetFrameShown
local function L(key, ...)
    if ARC.Text then return ARC:Text(key, ...) end
    if select("#", ...) > 0 then
        local ok, value = pcall(string.format, key, ...)
        if ok then return value end
    end
    return key
end

function ARC:SetManualMode(enabled)
    ARC_DB.manualMode = enabled and true or false
    if ARCOptionsManual then ARCOptionsManual:SetChecked(ARC_DB.manualMode) end
end

function ARC:SetMinimumItemLevel(text)
    local value = tonumber(text)
    if not value or value < 400 or value > 600 or value ~= math.floor(value) then
        return false, L("Enter a whole number from 400 to 600.")
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
        GameTooltip:AddLine(L("Left-click: show/hide window"), 0.8, 0.8, 0.8)
        GameTooltip:AddLine(L("Right-click: options"), 0.8, 0.8, 0.8)
        GameTooltip:AddLine(L("Drag: move this button"), 0.8, 0.8, 0.8)
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

local function SkinOptionsPanelElvUI(panel)
    if not panel or panel.elvuiSkinned or not (IsAddOnLoaded and IsAddOnLoaded("ElvUI")) or not ElvUI or not ElvUI[1] then return end
    local E = ElvUI[1]
    if not E.GetModule then return end
    local ok, skins = pcall(E.GetModule, E, "Skins")
    if not ok or not skins then return end
    for _, button in ipairs(panel.skinButtons or {}) do
        if skins.HandleButton then pcall(skins.HandleButton, skins, button) end
    end
    for _, checkbox in ipairs(panel.skinCheckBoxes or {}) do
        if skins.HandleCheckBox then pcall(skins.HandleCheckBox, skins, checkbox) end
    end
    for _, input in ipairs(panel.skinEditBoxes or {}) do
        if skins.HandleEditBox then pcall(skins.HandleEditBox, skins, input) end
    end
    for _, slider in ipairs(panel.skinSliders or {}) do
        if skins.HandleSliderFrame then pcall(skins.HandleSliderFrame, skins, slider)
        elseif skins.HandleSlider then pcall(skins.HandleSlider, skins, slider) end
    end
    if panel.scroll and skins.HandleScrollBar then
        local bar = _G[panel.scroll:GetName() .. "ScrollBar"]
        if bar then pcall(skins.HandleScrollBar, skins, bar) end
    end
    panel.elvuiSkinned = true
end

function ARC:TrySkinOptionsElvUI()
    SkinOptionsPanelElvUI(self.optionsPanel)
    SkinOptionsPanelElvUI(self.raidOptionsPanel)
end

function ARC:CreateOptionsPanel()
    local panel = CreateFrame("Frame", "ARCOptionsPanel", UIParent)
    panel.name = "ARC"
    local scroll = CreateFrame("ScrollFrame", "ARCOptionsScroll", panel, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 0, 0)
    scroll:SetPoint("BOTTOMRIGHT", -30, 0)
    local content = CreateFrame("Frame", "ARCOptionsContent", scroll)
    content:SetSize(520, 920)
    scroll:SetScrollChild(content)
    panel.scroll = scroll

    local title = content:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("ARC - " .. ARC.NAME)

    local subtitle = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    subtitle:SetWidth(500)
    subtitle:SetJustifyH("LEFT")
    local languageLabel = content:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    languageLabel:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", 0, -18)
    local languageButton = CreateFrame("Button", "ARCOptionsLanguage", content, "UIPanelButtonTemplate")
    languageButton:SetSize(220, 24)
    languageButton:SetPoint("TOPLEFT", languageLabel, "BOTTOMLEFT", -2, -6)
    local languageMenu = CreateFrame("Frame", "ARCOptionsLanguageMenu", content, "UIDropDownMenuTemplate")
    local function LanguageName(code)
        for _, choice in ipairs(ARC.LOCALE_CHOICES or {}) do
            if choice.code == code then return L(choice.name) end
        end
        return code
    end
    languageButton:SetScript("OnClick", function(self)
        if not ARC.GetLanguage or not ARC.SetLanguage then return end
        local menu = {}
        local selected = ARC:GetLanguage()
        for _, choice in ipairs(ARC.LOCALE_CHOICES or {}) do
            local code = choice.code
            menu[#menu + 1] = {
                text = L(choice.name), checked = selected == code,
                func = function()
                    ARC:SetLanguage(code)
                    if CloseDropDownMenus then CloseDropDownMenus() end
                end,
            }
        end
        EasyMenu(menu, languageMenu, self, 0, 0, "MENU")
    end)

    local manualCB = CreateFrame("CheckButton", "ARCOptionsManual", content, "InterfaceOptionsCheckButtonTemplate")
    manualCB:SetPoint("TOPLEFT", languageButton, "BOTTOMLEFT", 0, -12)
    manualCB:SetScript("OnClick", function(self) ARC:SetManualMode(self:GetChecked()) end)

    local autohideCB = CreateFrame("CheckButton", "ARCOptionsAutoHide", content, "InterfaceOptionsCheckButtonTemplate")
    autohideCB:SetPoint("TOPLEFT", manualCB, "BOTTOMLEFT", 0, -4)
    autohideCB:SetScript("OnClick", function(self)
        ARC_DB.autoHide = self:GetChecked() and true or false
    end)

    local lockCB = CreateFrame("CheckButton", "ARCOptionsLock", content, "InterfaceOptionsCheckButtonTemplate")
    lockCB:SetPoint("TOPLEFT", autohideCB, "BOTTOMLEFT", 0, -4)
    lockCB:SetScript("OnClick", function(self)
        ARC_DB.locked = self:GetChecked() and true or false
    end)

    local minimapCB = CreateFrame("CheckButton", "ARCOptionsMinimap", content, "InterfaceOptionsCheckButtonTemplate")
    minimapCB:SetPoint("TOPLEFT", lockCB, "BOTTOMLEFT", 0, -4)
    minimapCB:SetScript("OnClick", function(self)
        ARC_DB.minimap.hide = not self:GetChecked()
        if ARC.minimapButton then
            SetFrameShown(ARC.minimapButton, not ARC_DB.minimap.hide)
        end
    end)

    local autoSessionCB = CreateFrame("CheckButton", "ARCOptionsAutoSessions", content, "InterfaceOptionsCheckButtonTemplate")
    autoSessionCB:SetPoint("TOPLEFT", minimapCB, "BOTTOMLEFT", 0, -4)
    autoSessionCB:SetScript("OnClick", function(self)
        ARC_DB.autoSessions = self:GetChecked() and true or false
        if not ARC_DB.autoSessions and ARC.activeSession and ARC.activeSession.automatic and ARC.EndRaidSession then
            ARC:EndRaidSession("settings")
        end
        if ARC.UpdateAutoSession then ARC:UpdateAutoSession() end
    end)

    local scaleSlider = CreateFrame("Slider", "ARCOptionsScale", content, "OptionsSliderTemplate")
    scaleSlider:SetPoint("TOPLEFT", autoSessionCB, "BOTTOMLEFT", 6, -28)
    scaleSlider:SetWidth(200)
    scaleSlider:SetMinMaxValues(0.6, 1.5)
    scaleSlider:SetValueStep(0.05)
    SetSliderLabels(scaleSlider, "0.6", "1.5", L("Window Scale"))

    local scaleValueText = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    scaleValueText:SetPoint("LEFT", scaleSlider, "RIGHT", 12, 0)

    scaleSlider:SetScript("OnValueChanged", function(self, value)
        value = Round(value * 20) / 20 -- snap to 0.05 steps
        ARC_DB.scale = value
        if ARC.frame then ARC.frame:SetScale(value) end
        if ARC:IsVisible() then ARC:Render() end
        scaleValueText:SetText(string.format("%.2f", value))
    end)

    local opacitySlider = CreateFrame("Slider", "ARCOptionsOpacity", content, "OptionsSliderTemplate")
    opacitySlider:SetPoint("LEFT", scaleSlider, "RIGHT", 82, 0)
    opacitySlider:SetWidth(180)
    opacitySlider:SetMinMaxValues(20, 100)
    opacitySlider:SetValueStep(5)
    if opacitySlider.SetObeyStepOnDrag then opacitySlider:SetObeyStepOnDrag(true) end
    SetSliderLabels(opacitySlider, "20%", "100%", L("Window Opacity"))

    local opacityValueText = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    opacityValueText:SetPoint("LEFT", opacitySlider, "RIGHT", 10, 0)
    opacitySlider:SetScript("OnValueChanged", function(_, value)
        local percent = math.max(20, math.min(100, Round(tonumber(value) or 70)))
        ARC:SetWindowOpacity(percent / 100)
        opacityValueText:SetText(percent .. "%")
    end)

    local ilvlLabel = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    ilvlLabel:SetPoint("TOPLEFT", scaleSlider, "BOTTOMLEFT", 0, -30)
    local ilvlInput = CreateFrame("EditBox", "ARCOptionsMinIlvl", content, "InputBoxTemplate")
    ilvlInput:SetSize(80, 22)
    ilvlInput:SetPoint("TOPLEFT", ilvlLabel, "BOTTOMLEFT", 4, -8)
    ilvlInput:SetAutoFocus(false)
    ilvlInput:SetNumeric(true)
    ilvlInput:SetMaxLetters(3)
    local ilvlApply = CreateFrame("Button", "ARCOptionsMinIlvlApply", content, "UIPanelButtonTemplate")
    ilvlApply:SetSize(70, 22)
    ilvlApply:SetPoint("LEFT", ilvlInput, "RIGHT", 12, 0)
    local ilvlMessage = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    ilvlMessage:SetPoint("TOPLEFT", ilvlInput, "BOTTOMLEFT", -4, -8)
    local function ApplyItemLevel()
        local ok, reason = ARC:SetMinimumItemLevel(ilvlInput:GetText())
        if ok then
            ilvlInput:SetText(tostring(ARC_DB.minItemLevel))
            ilvlInput:ClearFocus()
            ilvlMessage:SetText(L("Saved: %d", ARC_DB.minItemLevel))
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
        ilvlMessage:SetText(L("Unchanged: %d", ARC_DB.minItemLevel))
        ilvlMessage:SetTextColor(0.9, 0.9, 0.9)
    end)

    local resetBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    resetBtn:SetSize(160, 22)
    resetBtn:SetPoint("TOPLEFT", ilvlMessage, "BOTTOMLEFT", -6, -16)
    resetBtn:SetScript("OnClick", function()
        ARC_DB.point = { "CENTER", "UIParent", "CENTER", 0, 150 }
        if ARC.frame then
            ARC.frame:ClearAllPoints()
            ARC.frame:SetPoint(unpack(ARC_DB.point))
        end
    end)

    local raidBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    raidBtn:SetSize(160, 22)
    raidBtn:SetPoint("LEFT", resetBtn, "RIGHT", 12, 0)
    raidBtn:SetScript("OnClick", function() ARC:OpenRaidOptions() end)

    local sessionBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    sessionBtn:SetSize(130, 22)
    sessionBtn:SetPoint("LEFT", raidBtn, "RIGHT", 12, 0)
    sessionBtn:SetScript("OnClick", function()
        if ARC.ShowSessionReport then ARC:ShowSessionReport() end
    end)

    local demoBtn = CreateFrame("Button", "ARCOptionsDemoRoster", content, "UIPanelButtonTemplate")
    demoBtn:SetSize(180, 22)
    demoBtn:SetPoint("TOPLEFT", resetBtn, "BOTTOMLEFT", 0, -12)
    demoBtn:SetScript("OnClick", function()
        if ARC.demoRoster then
            ARC:ClearDemoRoster()
            ARC:Show()
        else
            ARC:LoadDemoRoster()
        end
        if panel.refresh then panel.refresh() end
        if InterfaceOptionsFrame and InterfaceOptionsFrame.Hide then InterfaceOptionsFrame:Hide() end
    end)

    local hint = content:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", demoBtn, "BOTTOMLEFT", 6, -16)
    hint:SetWidth(480)
    hint:SetJustifyH("LEFT")
    -- The outer frame remains the registered category; controls are created
    -- directly on the scroll child, including FontStrings on older clients.
    local function Place(widget, x, y)
        widget:ClearAllPoints()
        widget:SetPoint("TOPLEFT", content, "TOPLEFT", x, -y)
    end
    local sections = {}
    local function Section(key, y)
        local label = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        Place(label, 16, y)
        sections[#sections + 1] = {label=label, key=key}
    end
    Section("General", 70)
    Place(languageLabel, 16, 94); Place(languageButton, 16, 112)
    Place(manualCB, 16, 145); Place(autohideCB, 16, 175)
    Section("Appearance", 216)
    Place(lockCB, 16, 240); Place(minimapCB, 16, 268)
    Place(scaleSlider, 22, 329)
    Section("Raid checks", 376)
    Place(ilvlLabel, 16, 405); Place(ilvlInput, 20, 430)
    Place(ilvlMessage, 16, 462)
    Section("Session tracking", 504)
    Place(autoSessionCB, 16, 532)
    local trashInputs = {}
    for index, key in ipairs({ "joinGrace", "activeGap", "reviveGrace" }) do
        local x = 16 + (index - 1) * 164
        local label = content:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
        Place(label, x, 574); label:SetWidth(154); label:SetJustifyH("LEFT"); label:SetWordWrap(true)
        local input = CreateFrame("EditBox", "ARCOptionsTrash" .. key, content, "InputBoxTemplate")
        input:SetSize(70, 22); Place(input, x + 4, 612)
        input:SetAutoFocus(false); input:SetNumeric(true); input:SetMaxLetters(3)
        trashInputs[key] = input
        sections[#sections + 1] = {label=label, key=({joinGrace="Join grace (seconds)", activeGap="Activity gap (seconds)", reviveGrace="Revival grace (seconds)"})[key]}
    end
    local trashApply = CreateFrame("Button", "ARCOptionsTrashApply", content, "UIPanelButtonTemplate")
    trashApply:SetSize(75, 22); Place(trashApply, 430, 612)
    local trashMessage = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    Place(trashMessage, 16, 646); trashMessage:SetWidth(490); trashMessage:SetJustifyH("LEFT"); trashMessage:SetWordWrap(true)
    local function ResetTrashInputs()
        for key, input in pairs(trashInputs) do input:SetText(tostring(ARC_DB.trashSettings[key])); input:ClearFocus() end
    end
    local function ApplyTrashSettings()
        local values = {}
        for key, input in pairs(trashInputs) do
            local value = tonumber(input:GetText())
            local min, max = key == "reviveGrace" and 0 or 1, key == "reviveGrace" and 120 or 60
            if not value or value ~= math.floor(value) or value < min or value > max then
                trashMessage:SetText(L("Join/activity: 1-60s; revival: 0-120s. No changes saved."))
                trashMessage:SetTextColor(1, 0.35, 0.3)
                return
            end
            values[key] = value
        end
        for key, value in pairs(values) do ARC_DB.trashSettings[key] = value end
        ResetTrashInputs()
        trashMessage:SetText(L("Saved for the next session. The current session keeps its original limits."))
        trashMessage:SetTextColor(0.3, 1, 0.3)
    end
    trashApply:SetScript("OnClick", ApplyTrashSettings)
    for _, input in pairs(trashInputs) do
        input:SetScript("OnEnterPressed", ApplyTrashSettings)
        input:SetScript("OnEscapePressed", ResetTrashInputs)
    end
    Place(resetBtn, 16, 696); Place(demoBtn, 16, 734); Place(hint, 16, 774)
    local function RefreshText()
        for _, section in ipairs(sections) do section.label:SetText(L(section.key)) end
        trashApply:SetText(L("Apply"))
        subtitle:SetText(L("Version %s  -  see /arc help for slash commands", ARC.VERSION))
        languageLabel:SetText(L("Language"))
        local preference = ARC.GetLanguage and ARC:GetLanguage() or "auto"
        languageButton:SetText(LanguageName(preference))
        SetCheckButtonText(manualCB, L("Manual opening only (do not open ARC on ready checks)"))
        SetCheckButtonText(autohideCB, L("Auto-hide when you enter combat (the pull)"))
        SetCheckButtonText(lockCB, L("Lock window position (disable dragging)"))
        SetCheckButtonText(minimapCB, L("Show minimap button"))
        SetCheckButtonText(autoSessionCB, L("Automatically track sessions inside raid instances"))
        SetSliderLabels(scaleSlider, "0.6", "1.5", L("Window Scale"))
        SetSliderLabels(opacitySlider, "20%", "100%", L("Window Opacity"))
        ilvlLabel:SetText(L("Minimum Item Level"))
        ilvlApply:SetText(L("Apply"))
        resetBtn:SetText(L("Reset Window Position"))
        raidBtn:SetText(L("Raid Setup Checks"))
        sessionBtn:SetText(L("Session Report"))
        demoBtn:SetText(L(ARC.demoRoster and "Exit Demo Roster" or "Load Random 10-player Demo"))
        hint:SetText(L("Tip: right-click a player row for Whisper / Inspect / ARC Check / Remind. Session Report tracks attendance, pulls, deaths and estimated trash inactivity. Talents = empty talents; Self = class/tank/pet checks; HS = Healthstone uses; ? = unverified."))
    end

    panel.refresh = function()
        ResetTrashInputs()
        trashMessage:SetText(L("Defaults: 15s / 7s / 30s. Changes apply to new sessions only."))
        trashMessage:SetTextColor(0.9, 0.9, 0.9)
        manualCB:SetChecked(ARC_DB.manualMode)
        autohideCB:SetChecked(ARC_DB.autoHide)
        lockCB:SetChecked(ARC_DB.locked)
        minimapCB:SetChecked(not ARC_DB.minimap.hide)
        autoSessionCB:SetChecked(ARC_DB.autoSessions)
        scaleSlider:SetValue(ARC_DB.scale or 1.0)
        local opacityPercent = math.floor((ARC_DB.windowOpacity or 0.7) * 100 + 0.5)
        opacitySlider:SetValue(opacityPercent)
        opacityValueText:SetText(opacityPercent .. "%")
        ilvlInput:SetText(tostring(ARC_DB.minItemLevel or 450))
        ilvlInput:ClearFocus()
        ilvlMessage:SetText(L("400-600. Enter or Apply to save; Escape to cancel."))
        ilvlMessage:SetTextColor(0.9, 0.9, 0.9)
        RefreshText()
    end

    if InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(panel)
    end

    ARC.optionsPanel = panel
    panel.skinButtons = { languageButton, ilvlApply, resetBtn, raidBtn, sessionBtn, demoBtn, trashApply }
    panel.skinCheckBoxes = { manualCB, autohideCB, lockCB, minimapCB, autoSessionCB }
    panel.skinEditBoxes = { ilvlInput, trashInputs.joinGrace, trashInputs.activeGap, trashInputs.reviveGrace }
    panel.skinSliders = { scaleSlider, opacitySlider }
    self:TrySkinOptionsElvUI()
    if ARC.RegisterLocaleRefresh then ARC:RegisterLocaleRefresh(panel, panel.refresh) end
    panel.refresh()
    return panel
end

function ARC:CreateRaidOptions()
    if self.raidOptionsPanel then return self.raidOptionsPanel end
    local panel = CreateFrame("Frame", "ARCRaidOptionsPanel", UIParent)
    panel.name, panel.parent = L("Raid setup"), "ARC"
    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    local explanation = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    explanation:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -12)
    explanation:SetWidth(480)
    explanation:SetJustifyH("LEFT")
    local enabled = CreateFrame("CheckButton", "ARCRaidSetupEnabled", panel, "InterfaceOptionsCheckButtonTemplate")
    enabled:SetPoint("TOPLEFT", explanation, "BOTTOMLEFT", -2, -16)
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
                menu[#menu + 1] = { text = L(labels[value]), checked = ARC_DB.raidSetup[field] == value,
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
    local function RefreshRaidText()
        panel.name = L("Raid setup")
        title:SetText(L("ARC - Expected Raid Setup"))
        explanation:SetText(L("Choose your expected raid mode (including size) and loot method. A mismatch makes the ARC banner RED. These checks never change the actual raid settings or send chat. Changes here save immediately."))
        SetCheckButtonText(enabled, L("Check raid setup"))
        note:SetText(L("Inside a raid, ARC checks the actual instance difficulty. Outside it, ARC checks the selected raid difficulty. 10/25 is the mode's capacity, not the number of players currently invited. Not checked skips only that setting; unavailable data never passes."))
    end
    panel.refresh = function()
        enabled:SetChecked(ARC_DB.raidSetup.enabled)
        panel.mode:SetText(L("Mode / size: %s", L(ARC.RAID_DIFFICULTIES[ARC_DB.raidSetup.difficulty])))
        panel.loot:SetText(L("Loot: %s", L(ARC.LOOT_METHODS[ARC_DB.raidSetup.loot])))
        RefreshRaidText()
    end
    if InterfaceOptions_AddCategory then InterfaceOptions_AddCategory(panel) end
    panel.refresh()
    if ARC.RegisterLocaleRefresh then ARC:RegisterLocaleRefresh(panel, panel.refresh) end
    self.raidOptionsPanel = panel
    panel.skinButtons = { panel.mode, panel.loot }
    panel.skinCheckBoxes = { enabled }
    self:TrySkinOptionsElvUI()
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
    self:TrySkinOptionsElvUI()
    if InterfaceOptionsFrame_OpenToCategory then
        InterfaceOptionsFrame_OpenToCategory(self.optionsPanel)
        InterfaceOptionsFrame_OpenToCategory(self.optionsPanel) -- Blizzard's classic double-call quirk
    end
end
