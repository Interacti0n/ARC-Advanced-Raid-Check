local ARC = assert(_G.ARC, "ARC_Core.lua must load before ARC_Options.lua")
local I = assert(ARC.Internal, "ARC internal API is unavailable")
local Round = I.Round
local SetFrameShown = I.SetFrameShown

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
        GameTooltip:AddLine("ARC - Advanced Ready Check")
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
    title:SetText("ARC - Advanced Ready Check")

    local subtitle = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    subtitle:SetWidth(500)
    subtitle:SetJustifyH("LEFT")
    subtitle:SetText("Version " .. ARC.VERSION .. "  -  see /arc help for slash commands")

    local autohideCB = CreateFrame("CheckButton", "ARCOptionsAutoHide", panel, "InterfaceOptionsCheckButtonTemplate")
    autohideCB:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", -2, -20)
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

    local ilvlSlider = CreateFrame("Slider", "ARCOptionsMinIlvl", panel, "OptionsSliderTemplate")
    ilvlSlider:SetPoint("TOPLEFT", scaleSlider, "BOTTOMLEFT", 0, -34)
    ilvlSlider:SetWidth(200)
    ilvlSlider:SetMinMaxValues(400, 600)
    ilvlSlider:SetValueStep(1)
    SetSliderLabels(ilvlSlider, "400", "600", "Minimum Item Level")

    local ilvlValueText = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    ilvlValueText:SetPoint("LEFT", ilvlSlider, "RIGHT", 12, 0)
    ilvlSlider:SetScript("OnValueChanged", function(self, value)
        value = Round(value)
        ilvlValueText:SetText(tostring(value))
        if ARC_DB.minItemLevel ~= value then
            ARC_DB.minItemLevel = value
            -- Existing results are re-evaluated on the next inspect pass.
            for _, entry in pairs(ARC.roster) do entry.lastGearScan = nil end
            ARC.selfDirty = true
        end
    end)

    local resetBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    resetBtn:SetSize(160, 22)
    resetBtn:SetPoint("TOPLEFT", ilvlSlider, "BOTTOMLEFT", -6, -28)
    resetBtn:SetText("Reset Window Position")
    resetBtn:SetScript("OnClick", function()
        ARC_DB.point = { "CENTER", "UIParent", "CENTER", 0, 150 }
        if ARC.frame then
            ARC.frame:ClearAllPoints()
            ARC.frame:SetPoint(unpack(ARC_DB.point))
        end
    end)

    local hint = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", resetBtn, "BOTTOMLEFT", 6, -20)
    hint:SetWidth(480)
    hint:SetJustifyH("LEFT")
    hint:SetText("Tip: right-click any player row for Whisper / Inspect / Remind. Hover the Stam/Stat/Crit/Mast column headers to see who's providing each raid buff.")

    panel.refresh = function()
        autohideCB:SetChecked(ARC_DB.autoHide)
        lockCB:SetChecked(ARC_DB.locked)
        minimapCB:SetChecked(not ARC_DB.minimap.hide)
        scaleSlider:SetValue(ARC_DB.scale or 1.0)
        ilvlSlider:SetValue(ARC_DB.minItemLevel or 450)
    end

    if InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(panel)
    end

    ARC.optionsPanel = panel
    return panel
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
