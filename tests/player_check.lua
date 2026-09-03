-- Run from the addon root with Lua 5.1+, or fengari tests/player_check.lua.
-- Strict WoW-widget/API stubs: this exercises Lua control flow, not rendering.
unpack = unpack or table.unpack
local now, notifyCount, clearCount = 100, 0, 0
local cold, linkPending, missing, noItems, specMissing = false, false, false, false, false
local gearOverrides, gemOverrides, gemCold = {}, {}, false
local defaultEnchants = { [3] = 0, [5] = 4419, [7] = 4825, [8] = 4429, [9] = 4414, [10] = 4433, [15] = 4423, [16] = 4442 }
local readyStatus, readyTimeLeft, responseCount, responseValue = "waiting", 30, 0, nil
local alice = { guid = "A", name = "Alice", online = true, visible = true }
local bob = { guid = "B", name = "Bob", online = true, visible = true }
local units = { player = { guid = "SELF", name = "Me", online = true, visible = true }, target = alice, other = bob }
local methods = {}
local function object(kind, name, parent)
    local obj = setmetatable({ kind = kind, widgetName = name, parent = parent, scripts = {}, shown = true }, { __index = methods })
    if name then _G[name] = obj end
    return obj
end
function methods:GetName() return self.widgetName end
function methods:CreateTexture(name) return object("Texture", name, self) end
function methods:CreateFontString(name) return object("FontString", name, self) end
function methods:SetText(text) self.text = tostring(text or "") end
function methods:GetText() return self.text end
function methods:GetStringHeight() local _, count = (self.text or ""):gsub("\n", ""); return (count + 1) * 13 end
function methods:SetSize(w, h) self.width, self.height = w, h end
function methods:SetWidth(w) self.width = w end
function methods:SetHeight(h) self.height = h end
function methods:SetTexture(...) self.texture = { ... } end
function methods:SetScript(event, fn) self.scripts[event] = fn end
function methods:HookScript(event, fn)
    local prior = self.scripts[event]
    self.scripts[event] = function(...) if prior then prior(...) end; fn(...) end
end
function methods:Hide()
    local shown = self.shown
    self.shown = false
    if shown and self.scripts.OnHide then self.scripts.OnHide(self) end
end
function methods:Show()
    local shown = self.shown
    self.shown = true
    if not shown and self.scripts.OnShow then self.scripts.OnShow(self) end
end
function methods:IsShown() return self.shown end
function methods:Disable() self.disabled = true end
function methods:Enable() self.disabled = false end
function methods:SetChecked(value) self.checked = value end
function methods:GetChecked() return self.checked end
function methods:SetValue(value) self.value = value end
function methods:GetFontString() self.fontString = self.fontString or object("FontString"); return self.fontString end
function methods:NumLines() return 0 end
function methods:SetVerticalScroll(value) self.scrollOffset = value end
function methods:SetScrollChild(child) self.scrollChild = child end
for _, name in ipairs({ "SetPoint", "ClearAllPoints", "SetFrameStrata", "SetFrameLevel", "SetClampedToScreen", "SetMovable", "EnableMouse", "RegisterForDrag", "RegisterForClicks", "StartMoving", "StopMovingOrSizing", "SetBackdrop", "SetBackdropColor", "SetBackdropBorderColor", "SetJustifyH", "SetTextColor", "SetVertexColor", "SetAlpha", "SetTexCoord", "SetDesaturated", "SetOwner", "ClearLines", "SetInventoryItem", "SetAllPoints", "SetHighlightTexture", "RegisterEvent", "SetMinMaxValues", "SetValueStep", "SetScale", "AddLine", "SetUnitBuff" }) do
    methods[name] = function() end
end
for _, name in ipairs({ "SetMultiLine", "SetFontObject", "SetFocus", "HighlightText", "SetCursorPosition" }) do methods[name] = function() end end
for _, name in ipairs({ "SetAutoFocus", "SetNumeric", "SetMaxLetters", "ClearFocus" }) do methods[name] = function() end end
function methods:ClearAllPoints() self.points = {} end
function methods:SetPoint(...)
    self.points = self.points or {}
    self.points[#self.points + 1] = { ... }
end
function methods:SetWordWrap(value) self.wordWrap = value end
function methods:SetTextColor(...) self.textColor = { ... } end
function methods:SetVertexColor(...) self.vertexColor = { ... } end
function methods:SetOwner(owner, anchor) self.owner, self.anchor = owner, anchor end
function methods:IsOwned(owner) return self.owner == owner end
function methods:SetHyperlink(link) self.hyperlink = link; self.tooltipLines = {} end
function methods:ClearLines() self.tooltipLines = {} end
function methods:AddLine(text) self.tooltipLines = self.tooltipLines or {}; self.tooltipLines[#self.tooltipLines + 1] = text end
function CreateFrame(kind, name, parent, template)
    local frame = object(kind, name, parent)
    if template == "UIPanelScrollFrameTemplate" then object("Slider", name .. "ScrollBar", frame) end
    return frame
end
UIParent = CreateFrame("Frame", "UIParent")
Minimap = CreateFrame("Frame", "Minimap")
GameTooltip = CreateFrame("GameTooltip", "GameTooltip")
UISpecialFrames, SlashCmdList = {}, {}
RAID_CLASS_COLORS = { MAGE = { r = 0.4, g = 0.8, b = 1 } }
function GetTime() return now end
function time() return 1700000000 + math.floor(now) end
function GetReadyCheckStatus() return readyStatus end
function GetReadyCheckTimeLeft() return readyTimeLeft end
function ConfirmReadyCheck(value)
    responseCount, responseValue = responseCount + 1, value
    readyStatus = value == 1 and "ready" or "notready"
end
function UnitExists(unit) return units[unit] ~= nil end
function UnitGUID(unit) return units[unit] and units[unit].guid end
function UnitFullName(unit) return units[unit] and units[unit].name, units[unit] and units[unit].realm or "Realm" end
UnitName = UnitFullName
function GetRealmName() return "Realm" end
local talentMissing, talentCold = {}, false
function UnitClass(unit) return "Mage", units[unit] and units[unit].class or "MAGE", 8 end
function UnitLevel(unit) return units[unit] and units[unit].level or 90 end
function GetTalentInfo(index, inspect, group, unit, classID)
    assert(index >= 1 and index <= 18 and (inspect == true or inspect == false), "Use legacy MoP talent signature")
    assert(group == nil and type(unit) == "string" and classID == 8)
    if talentCold then return nil end
    local tier, column = math.floor((index - 1) / 3) + 1, (index - 1) % 3 + 1
    return "Talent " .. index, "icon", tier, column, column == 1 and not talentMissing[tier], true
end
function UnitIsPlayer(unit) return UnitExists(unit) and units[unit].isPlayer ~= false end
function UnitIsConnected(unit) return units[unit] and units[unit].online end
function UnitIsVisible(unit) return units[unit] and units[unit].visible end
function UnitIsUnit(a, b) return UnitGUID(a) ~= nil and UnitGUID(a) == UnitGUID(b) end
function UnitIsDeadOrGhost(unit) return units[unit] and units[unit].dead or false end
function UnitIsAFK(unit) return units[unit] and units[unit].afk or false end
function UnitGroupRolesAssigned() return "DAMAGER" end
function UnitBuff(unit, index)
    if index == 1 then return "Flask of the Warm Sun", nil, "flask", 0, nil, 3600, 3700, unit, nil, nil, 105691 end
    if index == 2 then return "Well Fed", nil, "food", 0, nil, 3600, 3700, unit, nil, nil, 104264 end
    if index == 3 then return "Mage Armor", nil, "armor", 0, nil, 0, 0, unit, nil, nil, 6117 end
end
function CanInspect(unit) return UnitIsVisible(unit) and UnitIsConnected(unit) end
function GetInspectSpecialization() return specMissing and 0 or 62 end
function GetSpecialization() return 1 end
function GetSpecializationInfoByID(id) return id, "Arcane", nil, "spec", nil, "DAMAGER" end
function GetSpecializationInfo() return GetSpecializationInfoByID(62) end
function GetAverageItemLevel() return 500, 500 end
function GetInventoryItemDurability() return nil end
function GetTexCoordsForRoleSmallCircle() return 0, 1, 0, 1 end
function GetGuildInfo() return "Test Guild" end
function IsInRaid() return false end
function IsInGroup() return false end
function GetNumGroupMembers() return 1 end
function wipe(t) for k in pairs(t) do t[k] = nil end end
function strsplit(separator, text)
    local values, start = {}, 1
    while true do
        local pos = text:find(separator, start, true)
        values[#values + 1] = text:sub(start, pos and pos - 1 or #text)
        if not pos then break end
        start = pos + #separator
    end
    return unpack(values)
end
function GetInventoryItemLink(unit, slot)
    local item = gearOverrides[slot] or {}
    if noItems or (slot == 17 and not item.equipped) or (missing and slot == 11) or (linkPending and slot == 1) then return nil end
    local enchant = item.enchant
    if enchant == nil then enchant = defaultEnchants[slot] or 0 end
    local gems = item.gems or (slot == 1 and { 76694 } or {})
    local fields = { "item", 1000 + slot, enchant }
    -- Deliberately use enchantment-like fields, not gem item IDs.
    for index = 1, 4 do fields[#fields + 1] = gems[index] and gems[index] > 0 and (4600 + index) or 0 end
    return table.concat(fields, ":") .. ":0:0:0:0:0"
end
function GetInventoryItemTexture(unit, slot)
    if noItems or slot == 17 or (missing and slot == 11) then return nil end
    return "item-icon"
end
function GetItemInfo(link)
    local id = tonumber(link:match("item:(%d+)"))
    if id > 2000 then
        local gem = gemOverrides[id] or (ARC.GEAR_RULES and ARC.GEAR_RULES.gems[id])
        if not gem or gemCold then return nil end
        return gem.name, link, gem.quality, gem.level or 90, 1, "Gem", "Red", 1, ""
    end
    if cold and id == 1001 then return nil end
    local item = gearOverrides[id - 1000] or {}
    return "Item " .. id, link, item.quality or 4, item.level or (id == 1001 and 440 or 500), 90, "Armor", "Cloth", 1,
        item.equipLoc or (id == 1016 and "INVTYPE_2HWEAPON" or "INVTYPE_HEAD")
end
function GetItemStats(link)
    local id = tonumber(link:match("item:(%d+)"))
    if id > 2000 then return (gemOverrides[id] or {}).liveStats end
    if cold and id == 1001 then return nil end
    return (gearOverrides[id - 1000] or {}).stats or { ITEM_MOD_INTELLECT_SHORT = 100, EMPTY_SOCKET_RED = id == 1001 and 2 or 0 }
end
function GetItemGem(link, index)
    if gemCold then return nil end
    local slot = tonumber(link:match("item:(%d+)")) - 1000
    local gems = (gearOverrides[slot] or {}).gems or (slot == 1 and { 76694 } or {})
    local id = gems[index]
    if id and id > 0 then
        local gem = gemOverrides[id] or ARC.GEAR_RULES.gems[id]
        return gem and gem.name, "item:" .. id
    end
end
function NotifyInspect() notifyCount = notifyCount + 1 end
function ClearInspectPlayer() clearCount = clearCount + 1 end
function hooksecurefunc(name, hook)
    local original = assert(_G[name], name)
    _G[name] = function(...) original(...); hook(...) end
end
function IsAddOnLoaded(name) return name == "ElvUI" and ElvUI ~= nil end

local popupItems, rowMenu, popupCloseCount = {}, nil, 0
UIDROPDOWNMENU_MENU_LEVEL = 1
function UIDropDownMenu_AddButton(info, level)
    assert(level == 1)
    popupItems[#popupItems + 1] = info
end
function UnitPopup_ShowMenu(dropdown, which, unit, name)
    popupItems = {}
    dropdown.which, dropdown.unit, dropdown.name = which, unit, name
    if UIDROPDOWNMENU_MENU_LEVEL == 1 then
        UIDropDownMenu_AddButton({ text = "Blizzard entry" }, 1)
    end
end
function CloseDropDownMenus() popupCloseCount = popupCloseCount + 1 end
function EasyMenu(menu) rowMenu = menu end

-- Use the shipping manifest so missing entries/order errors cannot be hidden
-- by a separate, hand-maintained list of modules in the test harness.
local staleTOC = arg and arg[1] == "--stale-toc"
local files, seen, tocVersion = {}, {}
local tocText
if io.open then
    local toc = assert(io.open("ARC.toc", "r"))
    tocText = toc:read("*a")
    toc:close()
else
    -- Fengari omits file I/O; its developer command supplies the same TOC.
    tocText = assert(os.getenv("ARC_TEST_TOC"), "Set ARC_TEST_TOC to the contents of ARC.toc when using Fengari")
end
for line in (tocText .. "\n"):gmatch("(.-)\n") do
    local file = line:match("^%s*(.-)%s*$")
    tocVersion = file:match("^## Version:%s*(.+)$") or tocVersion
    if file ~= "" and file:sub(1, 1) ~= "#" then
        assert(not seen[file], "Duplicate TOC entry: " .. file)
        files[#files + 1], seen[file] = file, true
    end
end
assert(files[1] == "ARC_Core.lua" and files[#files] == "ARC.lua", "Invalid TOC load order")
assert(seen["ARC_PlayerCheck.lua"], "Player check must be included in ARC.toc")
for _, file in ipairs(files) do
    if not staleTOC or (file ~= "ARC_PlayerCheck.lua" and file ~= "ARC_Session.lua") then
        assert(loadfile(file))("ARC")
    end
end
assert(ARC.VERSION == tocVersion, "Core and TOC versions must agree")
assert(ARC.NAME == "Advanced Raid Check" and tocText:find(ARC.NAME, 1, true), "Core and TOC display names must agree")
assert(tocText:find("## SavedVariables: ARC_DB", 1, true) and ARC.COMM_PREFIX == "ARC1", "Rename must preserve saved settings and wire compatibility")
local originalPrint, warnings = print, {}
if staleTOC then print = function(message) warnings[#warnings + 1] = message end end
ARCEventFrame.scripts.OnEvent(ARCEventFrame, "ADDON_LOADED", "ARC")
assert(ARC.inspectHooksReady)
assert(InspectFrame == nil, "Load-on-demand inspector must not be forced open")
if staleTOC then
    assert(not ARC.ShowPlayerCheck and not ARC.AttachInspectCheckButton and not ARC.UpdatePlayerCheck)
    assert(not ARC.ShowSessionReport and not ARC.StartRaidSession, "Cached TOC must safely omit the new session module")
    assert(#warnings == 1 and warnings[1]:find("Fully exit WoW", 1, true))
    assert(ARC.minimapButton and ARC.optionsPanel, "Missing detail module must not break initialization")
    InspectFrame = CreateFrame("Frame", "InspectFrame")
    for index = 1, 3 do
        ARCEventFrame.scripts.OnEvent(ARCEventFrame, "ADDON_LOADED", "Blizzard_InspectUI")
        ARCEventFrame.scripts.OnEvent(ARCEventFrame, "PLAYER_ENTERING_WORLD")
        ARCEventFrame.scripts.OnUpdate(ARCEventFrame, 1.1)
    end
    assert(#warnings == 1 and not InspectFrame.arcCheckButton, "Events/ticks must not spam or expose a broken button")
    SlashCmdList.ARC("check")
    assert(#warnings == 2 and not ARC.playerCheckFrame and not ARC.inspectRequest)
    assert(warnings[2]:find("ARC_PlayerCheck.lua", 1, true), "Explicit check must explain why it cannot open")
    SlashCmdList.ARC("session")
    assert(not ARC.sessionFrame, "Missing session module must leave its command harmless")
    SlashCmdList.ARC("")
    assert(ARC:IsVisible(), "Raid window must still work")
    ARC:Hide()
    ARC.minimapButton.scripts.OnClick(ARC.minimapButton, "LeftButton")
    assert(ARC:IsVisible(), "Minimap must still work")
    ARCEventFrame.scripts.OnEvent(ARCEventFrame, "READY_CHECK", "SomeoneElse", 30)
    ARCEventFrame.scripts.OnUpdate(ARCEventFrame, 1.1)
    assert(ARC.readyCheckActive and not ARC.frame.readyYes.disabled)
    ARC.frame.readyYes.scripts.OnClick(ARC.frame.readyYes)
    assert(responseCount == 1 and responseValue == 1, "Ready-check responses must still work")
    assert(#warnings == 2, "Background handling must not repeat the module warning")
    print = originalPrint
    print("Passed stale-TOC regression checks: startup, events, updates, slash, minimap and raid ready check")
    return
end
InspectFrame = CreateFrame("Frame", "InspectFrame")
InspectFrame:SetSize(338, 424)
InspectFrameTitleText = InspectFrame:CreateFontString("InspectFrameTitleText")
InspectFrameTitleText:SetText("A very long player name and realm")
InspectFrame:Hide()
function InspectFrame_Show(unit)
    InspectFrame:Hide()
    NotifyInspect(unit)
    InspectFrame.unit = unit
    InspectFrame:Show()
end
ARCEventFrame.scripts.OnEvent(ARCEventFrame, "ADDON_LOADED", "Blizzard_InspectUI")
local button = assert(InspectFrame.arcCheckButton)
ARC:AttachInspectCheckButton()
assert(InspectFrame.arcCheckButton == button, "Must not duplicate button")

local function step(seconds)
    now = now + (seconds or 3)
    ARC.TryNextInspect()
    ARC:UpdatePlayerCheck()
end
local function start()
    if ARC.playerCheckFrame then ARC.playerCheckFrame:Hide() end
    now = now + 20
    units.target = alice
    alice.online, alice.visible = true, true
    cold, linkPending, missing, noItems, specMissing = false, false, false, false, false
    gearOverrides, gemOverrides, gemCold = {}, {}, false
    talentMissing, talentCold = {}, false
    wipe(ARC.roster); wipe(ARC.inspectQueue)
    InspectFrame_Show("target")
    button.scripts.OnClick(button)
    return ARC.playerCheckFrame
end
local function contents(frame)
    local lines = {}
    for i = 1, frame.lineCount do lines[#lines + 1] = frame.lines[i].label.text .. ": " .. frame.lines[i].value.text end
    return table.concat(lines, "\n")
end
local passed = 0
local function test(name, fn)
    fn(); passed = passed + 1; print("PASS " .. name)
end

test("inspect check is inside the header with space reserved for title and Close", function()
    start()
    local anchor = button.points[1]
    assert(button.parent == InspectFrame and button.width == 74 and button.height == 18)
    assert(#button.points == 1 and anchor[1] == "TOPRIGHT" and anchor[2] == InspectFrame)
    assert(anchor[3] == "TOPRIGHT" and anchor[4] == -30 and anchor[5] == -5)
    local title = InspectFrameTitleText
    assert(#title.points == 2 and title.points[1][4] == 70)
    assert(title.points[2][2] == button and title.points[2][3] == "LEFT" and title.points[2][4] == -6)
    assert(title.wordWrap == false and title:GetText() == "A very long player name and realm")
    -- The right edge of the title is 6px before the button; both stay above gear.
    assert(338 - 30 - button.width - 6 > 70 and 5 + button.height < 30)
    button:ClearAllPoints(); title:ClearAllPoints()
    InspectFrame_Show("other")
    assert(#button.points == 1 and #title.points == 2 and InspectFrame.arcCheckGUID == "B")
    ARC:AttachInspectCheckButton(); assert(InspectFrame.arcCheckButton == button)
end)

test("inspect header supports TitleText forks and a missing title widget", function()
    local title = InspectFrameTitleText
    InspectFrameTitleText = nil
    InspectFrame.TitleText = title
    start(); assert(title.points[2][2] == button)
    InspectFrame.TitleText = nil
    start(); assert(button.points[1][3] == "TOPRIGHT")
    InspectFrameTitleText = title
end)

test("non-group report shows ordered identity and only problem slots", function()
    local f = start()
    assert(f.busy and not f.entry.gear)
    step()
    ARC.OnInspectReady("wrong-guid")
    assert(f.busy and not f.entry.gear)
    ARC.OnInspectReady("A")
    assert(not f.busy and f.entry.gear.scanned and next(ARC.roster) == nil)
    assert(f.entry.gear.averageItemLevel == 496 and #f.entry.gear.slots == 16)
    assert(f.entry.gear.missingGems == 1 and #f.entry.gear.missingEnchants == 1)
    assert(f.entry.gear.issueCount == 3 and not f.entry.durPct)
    local text = contents(f)
    for _, value in ipairs({ "Alice-Realm", "PLAYER", "GEAR CHECK", "Head:", "Shoulder:", "Below 450", "Missing enchant", "1 missing gem" }) do
        assert(text:find(value, 1, true), value)
    end
    for _, value in ipairs({ "Flask of the Warm Sun", "Well Fed", "Off hand:", "Chest:", "Missing gems:", "UNVERIFIED" }) do
        assert(not text:find(value, 1, true), "Healthy/unneeded detail leaked: " .. value)
    end
    assert(text:find("PLAYER") < text:find("GEAR CHECK"))
    assert(f.scroll.scrollChild == f.content and f.entry.gear.auditComplete)
    assert(clearCount == 0)
end)
test("item cache retries without a second network request", function()
    local f = start(); cold = true; step()
    local calls = notifyCount
    ARC.OnInspectReady("A")
    assert(f.busy and not f.entry.gear.scanned and not f.entry.gear.averageItemLevel)
    cold = false; step(1)
    assert(not f.busy and f.entry.gear.scanned and notifyCount == calls)
end)
test("texture without link is pending, not an empty slot", function()
    local f = start(); linkPending = true; step(); ARC.OnInspectReady("A")
    assert(f.busy and not f.entry.gear.scanned and #f.entry.gear.missingItems == 0)
    linkPending = false; step(1); assert(f.entry.gear.scanned)
end)
test("true empty required slot is reported", function()
    local f = start(); missing = true; step(); ARC.OnInspectReady("A")
    assert(f.entry.gear.scanned and f.entry.gear.missingItems[1] == "Ring 1")
end)
test("completely unavailable equipment cannot pass", function()
    local f = start(); noItems = true; step(); ARC.OnInspectReady("A"); step(7)
    assert(not f.busy and not f.entry.gear.scanned)
    assert(contents(f):find("Empty-looking slots are not confirmed", 1, true))
end)
test("unknown spec is not presented as verified primary stats", function()
    local f = start(); specMissing = true; step(); ARC.OnInspectReady("A")
    assert(f.entry.gear.scanned and not f.entry.gear.expectedPrimary)
    assert(contents(f):find("not evaluated", 1, true))
end)
test("target change during request rejects old result", function()
    local f = start(); step(); units.target = bob; ARC.OnInspectReady("A")
    assert(not f.busy and not f.entry.gear and f.entry.guid == "A")
end)
test("target change before sending does not inspect a different player", function()
    local f = start(); local calls = notifyCount; units.target = bob; step()
    assert(not f.busy and notifyCount == calls and not f.entry.gear)
end)
test("completed snapshot never follows a new target", function()
    local f = start(); step(); ARC.OnInspectReady("A")
    local snapshot = f.entry.gear
    units.target = bob; step(1)
    assert(f.message:find("unavailable") and f.entry.gear == snapshot)
    local calls = notifyCount
    f.refresh.scripts.OnClick(f.refresh)
    assert(notifyCount == calls and f.entry.guid == "A")
    button.scripts.OnClick(button)
    assert(f.entry.guid == "A", "Stale inspector button must not check Bob")
end)
test("manual check interrupts raid but does not clear Blizzard cache", function()
    local f = start(); step(); ARC.OnInspectReady("A"); f:Hide(); InspectFrame:Hide()
    ARC.roster["Bob-Realm"] = { unit = "other" }
    ARC.inspectQueue = { "other" }; step()
    assert(ARC.inspectRequest.kind == "raid")
    ARC:ShowPlayerCheck("target")
    assert(ARC.inspectRequest.kind == "manual" and clearCount == 0)
end)
test("external addon inspect cancels active request safely", function()
    local f = start(); step(); NotifyInspect("other"); ARC.OnInspectReady("A")
    assert(not f.busy and not f.entry.gear and not ARC.inspectRequest)
end)
test("external addon replacing a queued manual check is respected", function()
    local f = start(); NotifyInspect("other"); local calls = notifyCount; step()
    assert(not f.busy and notifyCount == calls and not f.entry.gear)
end)
test("external cache clear cancels active request", function()
    local f = start(); step(); ClearInspectPlayer(); ARC.OnInspectReady("A")
    assert(not f.busy and not f.entry.gear)
end)
test("timeout is bounded and permits refresh", function()
    local f = start(); step(); step(7)
    assert(not f.busy and not f.refresh.disabled and f.message:find("timed out"))
end)
test("out-of-range request is not sent", function()
    local f = start(); f:Hide(); alice.visible = false
    local calls = notifyCount
    ARC:ShowPlayerCheck("target"); step()
    assert(not f.busy and notifyCount == calls and not f.entry.gear)
end)
test("offline player request is not sent", function()
    local f = start(); f:Hide(); alice.online = false
    local calls = notifyCount; ARC:ShowPlayerCheck("target"); step()
    assert(not f.busy and notifyCount == calls)
end)
test("late events before the retry is sent are ignored", function()
    local f = start(); step(); step(7)
    ARC:ShowPlayerCheck("target"); ARC.OnInspectReady("A")
    assert(f.busy and not f.entry.gear)
    step(); ARC.OnInspectReady("A"); assert(f.entry.gear.scanned)
end)
test("closing detail cancels its request and ignores late events", function()
    local f = start(); step(); local clears = clearCount
    f:Hide(); ARC.OnInspectReady("A")
    assert(not ARC.inspectRequest and not f.entry.gear and clearCount == clears)
end)
test("open Blizzard inspector pauses background queue", function()
    start(); ARC.playerCheckFrame:Hide()
    ARC.roster["Bob-Realm"] = { unit = "other" }
    ARC.inspectQueue = { "other" }; local calls = notifyCount; step()
    assert(notifyCount == calls and not ARC.inspectRequest)
end)
test("slash command and real event handlers work without an open inspector", function()
    local f = start(); f:Hide(); InspectFrame:Hide(); now = now + 3
    SlashCmdList.ARC("check")
    ARCEventFrame.scripts.OnUpdate(ARCEventFrame, 1.1)
    assert(ARC.inspectRequest and ARC.inspectRequest.startedAt)
    ARCEventFrame.scripts.OnEvent(ARCEventFrame, "INSPECT_READY", "A")
    assert(not f.busy and f.entry.gear.scanned)
end)
test("new inspect window replaces snapshot with the explicitly chosen player", function()
    local f = start(); step()
    InspectFrame_Show("other"); button.scripts.OnClick(button)
    assert(f.entry.guid == "B" and f.busy)
    step(); ARC.OnInspectReady("A"); assert(f.busy)
    ARC.OnInspectReady("B"); assert(not f.busy and f.entry.gear.scanned)
end)
test("standalone and ElvUI widget branches both load", function()
    local f = start(); assert(not f.arcSkinned); f:Hide()
    methods.SetTemplate = function(self, template) self.appliedTemplate = template end
    methods.FontTemplate = function(self, font, size) self.appliedFont = font end
    methods.CreateBackdrop = function(self) self.backdrop = CreateFrame("Frame", nil, self.parent) end
    local S = {
        HandleButton = function(_, b) b.skinned = true end,
        HandleCloseButton = function() end,
        HandleScrollBar = function(_, b) b.skinned = true end,
    }
    ElvUI = { { media = { normFont = "ElvUIFont", blankTex = "blank", bordercolor = { 0, 0, 0 }, rgbvaluecolor = { 0, 1, 1 } }, GetModule = function() return S end } }
    f = start(); step(); ARC.OnInspectReady("A")
    assert(f.arcSkinned and f.appliedTemplate == "Transparent" and f.refresh.skinned)
    assert(f.lines[1].value.appliedFont == "ElvUIFont")
    ARC:Show()
    assert(ARC.frame.elvuiSkinned and ARC.frame.rows[1].elvuiSkinned)
    assert(ARC.frame.readyYes.skinned and ARC.frame.readyNo.skinned)
    assert(ARC.frame.sessionButton.skinned)
    assert(ARCMainRosterScrollFrameScrollBar.skinned)
end)
local function readyEvent(event, ...)
    ARCEventFrame.scripts.OnEvent(ARCEventFrame, event, ...)
end
local function beginReady()
    readyStatus, readyTimeLeft = "waiting", 30
    readyEvent("READY_CHECK", "SomeoneElse", 30)
end
test("manual mode never opens a hidden window or auto-answers", function()
    ARC:Hide(); local calls = responseCount
    assert(ARC_DB.manualMode == false)
    SlashCmdList.ARC("manual on"); beginReady()
    assert(ARC_DB.manualMode and ARCOptionsManual:GetChecked())
    assert(not ARC:IsVisible() and ARC.readyCheckActive and responseCount == calls)
    SlashCmdList.ARC("")
    assert(ARC:IsVisible() and not ARC.frame.readyYes.disabled)
    beginReady(); assert(ARC:IsVisible(), "Manual mode must not close an already-open window")
end)
test("manual mode commands, options and saved setting agree", function()
    SlashCmdList.ARC("manual off"); assert(not ARC_DB.manualMode)
    SlashCmdList.ARC("manual"); assert(ARC_DB.manualMode)
    SlashCmdList.ARC("manual invalid"); assert(ARC_DB.manualMode)
    ARC.Internal.ARC_InitDB(); assert(ARC_DB.manualMode)
    ARCOptionsManual:SetChecked(false); ARCOptionsManual.scripts.OnClick(ARCOptionsManual)
    assert(not ARC_DB.manualMode)
    ARC:Hide(); beginReady(); assert(ARC:IsVisible())
end)
test("minimap still opens ARC in manual mode without sending a response", function()
    ARC:SetManualMode(true); ARC:Hide(); local calls = responseCount
    ARC.minimapButton.scripts.OnClick(ARC.minimapButton, "LeftButton")
    assert(ARC:IsVisible() and responseCount == calls)
    ARC:SetManualMode(false)
end)
test("Ready sends 1 exactly once and dismisses the stock dialog", function()
    ReadyCheckFrame = CreateFrame("Frame", "ReadyCheckFrame")
    beginReady(); local calls = responseCount
    ARC.frame.readyYes.scripts.OnClick(ARC.frame.readyYes)
    assert(responseCount == calls + 1 and responseValue == 1 and not ReadyCheckFrame:IsShown())
    assert(ARC.frame.readyYes.disabled and ARC.frame.readyNo.disabled)
    ARC.frame.readyNo.scripts.OnClick(ARC.frame.readyNo)
    assert(responseCount == calls + 1)
end)
test("Not Ready uses the legacy nil argument", function()
    beginReady(); local calls = responseCount
    ARC.frame.readyNo.scripts.OnClick(ARC.frame.readyNo)
    assert(responseCount == calls + 1 and responseValue == nil and readyStatus == "notready")
end)
test("finished, expired and already-answered checks disable responses", function()
    beginReady(); readyEvent("READY_CHECK_FINISHED"); local calls = responseCount
    ARC.frame.readyYes.scripts.OnClick(ARC.frame.readyYes); assert(responseCount == calls)
    beginReady(); readyTimeLeft = 0; ARC:Render(); assert(ARC.frame.readyYes.disabled)
    beginReady(); readyStatus = "ready"; ARC:Render(); assert(ARC.frame.readyYes.disabled)
    beginReady(); readyEvent("READY_CHECK_CONFIRM", "player"); assert(ARC.frame.readyYes.disabled)
end)
test("event deadline protects clients with no ready-check timer API", function()
    local timer = GetReadyCheckTimeLeft; GetReadyCheckTimeLeft = nil
    beginReady(); now = now + 31; ARC:Render(); assert(ARC.frame.readyYes.disabled)
    GetReadyCheckTimeLeft = timer
end)
test("failed response keeps the stock dialog available", function()
    local confirm = ConfirmReadyCheck
    ConfirmReadyCheck = function() error("API blocked") end
    beginReady(); ReadyCheckFrame:Show()
    ARC.frame.readyYes.scripts.OnClick(ARC.frame.readyYes)
    assert(not ARC.readyCheckResponded and ReadyCheckFrame:IsShown())
    ConfirmReadyCheck = confirm
end)
test("exact item-level entry applies only on Enter or Apply", function()
    ARC.optionsPanel.refresh()
    assert(ARCOptionsMinIlvl.kind == "EditBox")
    ARCOptionsMinIlvl:SetText("456")
    assert(ARC_DB.minItemLevel == 450)
    ARCOptionsMinIlvl.scripts.OnEnterPressed(ARCOptionsMinIlvl)
    assert(ARC_DB.minItemLevel == 456 and ARC.forceSelfGearScan)
    for _, e in pairs(ARC.roster) do assert(not e.lastGearScan and not e.gear) end
    ARCOptionsMinIlvl:SetText("457")
    ARCOptionsMinIlvlApply.scripts.OnClick(ARCOptionsMinIlvlApply)
    assert(ARC_DB.minItemLevel == 457)
end)
test("invalid input preserves the saved threshold and Escape cancels edits", function()
    for _, value in ipairs({ "", "abc", "399", "601", "450.5", "-1" }) do
        ARCOptionsMinIlvl:SetText(value)
        ARCOptionsMinIlvlApply.scripts.OnClick(ARCOptionsMinIlvlApply)
        assert(ARC_DB.minItemLevel == 457, value)
    end
    ARCOptionsMinIlvl:SetText("555")
    ARCOptionsMinIlvl.scripts.OnEscapePressed(ARCOptionsMinIlvl)
    assert(ARCOptionsMinIlvl:GetText() == "457" and ARC_DB.minItemLevel == 457)
    assert(ARC:SetMinimumItemLevel("400")); assert(ARC:SetMinimumItemLevel("600"))
    assert(ARC:SetMinimumItemLevel("450"))
end)
local function policyScan(overrides, specID, class, role)
    gearOverrides = overrides or {}
    local entry = { specID = specID or 62, class = class or "MAGE", role = role or "DAMAGER" }
    ARC:AnalyzeUnitGear("target", entry)
    return entry.gear
end
local function cleanGear()
    return { [1] = { level = 500, gems = { 76694, 76694 } }, [3] = { enchant = 4806 } }
end

test("a clean report hides all item rows and zero counters", function()
    local f = start(); gearOverrides = cleanGear(); step(); ARC.OnInspectReady("A")
    local text = contents(f)
    assert(f.entry.gear.auditComplete and f.entry.gear.issueCount == 0)
    assert(text:find("No gear issues found", 1, true))
    assert(not text:find("Head:", 1, true) and not text:find("UNVERIFIED", 1, true))
    assert(not text:find("READINESS", 1, true) and not text:find("Missing enchants:", 1, true))
    local visible = 0
    for _, row in ipairs(f.lines) do if row:IsShown() then visible = visible + 1 end end
    assert(visible == f.lineCount, "Rows reused from an older report must be hidden")
end)
test("rare, Perfect, profession and legendary MoP gems are accepted", function()
    start()
    for _, id in ipairs({ 76694, 76628, 83150, 89882, 76885, 95347, 77542, 76699 }) do
        local gear = policyScan({ [1] = { gems = { id, id } } })
        assert(#gear.badGems == 0 and #gear.unverified == 0, "Unexpected rejection: " .. id)
    end
end)
test("green quality and old expansion gems fail even with useful stats", function()
    start()
    gemOverrides[76564] = { name = "Brilliant Pandarian Garnet", quality = 2, level = 90 }
    gemOverrides[52207] = { name = "Brilliant Inferno Ruby", quality = 3, level = 85 }
    local gear = policyScan({ [1] = { gems = { 76564, 52207 } } })
    assert(#gear.badGems == 2 and gear.badGems[1]:find("below rare", 1, true))
    assert(gear.badGems[2]:find("older than", 1, true))
end)
test("wrong primary gems and hybrid PvP gems have distinct reasons", function()
    start()
    local gear = policyScan({ [1] = { gems = { 76696, 76685 } } })
    assert(#gear.badGems == 2)
    assert(gear.badGems[1]:find("expected INT", 1, true))
    assert(gear.badGems[2]:find("PvP bonus", 1, true))
end)
test("green PvP gems are not hidden by the quality failure", function()
    start()
    gemOverrides[76503] = { name = "Stormy Lapis Lazuli", quality = 2, level = 90,
        liveStats = { ITEM_MOD_PVP_POWER_SHORT = 120 } }
    local gear = policyScan({ [1] = { gems = { 76503 } } })
    assert(#gear.badGems == 1 and gear.badGems[1]:find("below rare", 1, true))
    assert(gear.badGems[1]:find("PvP bonus", 1, true))
end)
test("PvP meta effects and wrong legendary proc are rejected", function()
    start()
    for _, id in ipairs({ 76890, 76891, 76892, 76893, 76894, 95348 }) do
        local gear = policyScan({ [1] = { gems = { id } } })
        assert(#gear.badGems == 1 and gear.badGems[1]:find("PvP bonus", 1, true), id)
    end
    local gear = policyScan({ [1] = { gems = { 95346 } } })
    assert(gear.badGems[1]:find("different type of spec", 1, true))
    gear = policyScan({ [1] = { gems = { 95345 } } })
    assert(gear.badGems[1]:find("requires role HEALER", 1, true))
end)
test("gems in extra sockets are audited even when base sockets are absent", function()
    start()
    local gear = policyScan({ [6] = { gems = { 76685 }, enchant = 99999 } })
    assert(#gear.badGems == 1 and gear.badGems[1]:find("Waist:", 1, true))
    assert(#gear.unverified == 0 and #gear.badEnchants == 0, "Buckle is not a stat enchant")
end)
test("cold gem data retries locally without losing equipped item level", function()
    local f = start(); gemCold = true; step(); local calls = notifyCount; ARC.OnInspectReady("A")
    local gear = f.entry.gear
    assert(f.busy and gear.scanned and gear.averageItemLevel == 496 and gear.validationPending)
    assert(not gear.auditComplete and gear.missingGems == 1 and #gear.badGems == 0)
    assert(contents(f):find("UNVERIFIED", 1, true))
    gemCold = false; step(1)
    assert(not f.busy and f.entry.gear.auditComplete and notifyCount == calls)
end)
test("unavailable gem API yields an explicit unknown, not a pass", function()
    start(); local api = GetItemGem; GetItemGem = nil
    local gear = policyScan(cleanGear())
    GetItemGem = api
    assert(gear.scanned and not gear.validationPending and not gear.auditComplete)
    assert(gear.issueCount == 0 and #gear.unverified == 2)
end)
test("unknown custom gem or enchant cannot produce a green OK", function()
    local f = start()
    gemOverrides[99999] = { name = "Custom Gem", quality = 4, level = 90 }
    gearOverrides = cleanGear(); gearOverrides[1].gems = { 99999, 76694 }; gearOverrides[9] = { enchant = 9999 }
    step(); ARC.OnInspectReady("A")
    assert(not f.busy and not f.entry.gear.auditComplete and f.entry.gear.issueCount == 0)
    assert(#f.entry.gear.unverified == 2 and contents(f):find("UNVERIFIED", 1, true))
    assert(not contents(f):find("No gear issues found", 1, true))
    ARC:Show()
    local selfEntry = ARC.roster["Me-Realm"]
    assert(selfEntry and not selfEntry.gear.auditComplete)
    assert(ARC.frame.rows[1].gear:GetText() == "?")
end)
test("top tier, lower rank and wrong-stat enchants are distinguished", function()
    start()
    local gear = policyScan({ [3] = { enchant = 4806 }, [7] = { enchant = 4825 }, [16] = { enchant = 4442 } })
    assert(#gear.badEnchants == 0)
    gear = policyScan({ [3] = { enchant = 4909 }, [7] = { enchant = 5003 }, [16] = { enchant = 4441 } })
    assert(#gear.badEnchants == 3 and gear.badEnchants[1]:find("below the approved", 1, true))
    gear = policyScan({ [9] = { enchant = 4415 }, [16] = { enchant = 4444 } })
    assert(#gear.badEnchants == 2 and gear.badEnchants[1]:find("expected INT", 1, true))
end)
test("all-stat enchants and physical adaptive procs are not false positives", function()
    start()
    local gear = policyScan({ [5] = { enchant = 4419 } })
    assert(#gear.badEnchants == 0)
    gear = policyScan({ [16] = { enchant = 4444 } }, 103, "DRUID")
    for _, issue in ipairs(gear.badEnchants) do assert(not issue:find("Main hand:", 1, true)) end
end)
test("PvP enchants fail, but PvE-equivalent cosmetic variants pass", function()
    start()
    local gear = policyScan({ [5] = { enchant = 4417 }, [16] = { enchant = 5035 } })
    assert(#gear.badEnchants == 2 and gear.badEnchants[1]:find("PvP-oriented", 1, true))
    gear = policyScan({ [16] = { enchant = 5124 } })
    assert(#gear.badEnchants == 0)
end)
test("profession top enchants and ring enchants are supported", function()
    start()
    for _, pair in ipairs({ {3,4915}, {7,4895}, {9,4877}, {15,4892}, {11,4360}, {12,4360} }) do
        local gear = policyScan({ [pair[1]] = { enchant = pair[2] } })
        assert(#gear.badEnchants == 0 and #gear.unverified == 0, pair[2])
    end
    local gear = policyScan({ [11] = { enchant = 0 }, [12] = { enchant = 0 } })
    assert(#gear.missingEnchants == 1, "Only default shoulder is missing; rings are optional")
end)
test("runeforges stay valid for death knights, not for other classes", function()
    start()
    local gear = policyScan({ [16] = { enchant = 3368 } }, 251, "DEATHKNIGHT")
    for _, issue in ipairs(gear.badEnchants) do assert(not issue:find("Main hand:", 1, true)) end
    gear = policyScan({ [16] = { enchant = 3368 } })
    assert(#gear.badEnchants == 1 and gear.badEnchants[1]:find("requires DEATHKNIGHT", 1, true))
end)
test("hunter scopes, caster offhands and shields use their own rules", function()
    start()
    local gear = policyScan({ [16] = { enchant = 4699, equipLoc = "INVTYPE_RANGED" } }, 253, "HUNTER")
    assert(gear.averageItemLevel == 496, "Hunter ranged weapon must occupy two average-ilvl slots")
    for _, issue in ipairs(gear.badEnchants) do assert(not issue:find("Main hand:", 1, true)) end
    gear = policyScan({ [17] = { equipped = true, enchant = 4434, equipLoc = "INVTYPE_HOLDABLE" } })
    assert(#gear.badEnchants == 0)
    gear = policyScan({ [17] = { equipped = true, enchant = 4442, equipLoc = "INVTYPE_HOLDABLE" } })
    assert(#gear.badEnchants == 1 and gear.badEnchants[1]:find("different item type", 1, true))
end)
test("many findings stay scrollable and readiness stays separate", function()
    local f = start()
    for _, slot in ipairs({ 1,2,3,5,6,7,8,9,10,11,12,13,14,15,16 }) do
        gearOverrides[slot] = { gems = { 76685, 76696 }, level = 440 }
    end
    f.entry.buffs.flask, f.entry.buffs.food = false, false
    step(); ARC.OnInspectReady("A")
    local text = contents(f)
    assert(f.content.height > 620 and text:find("READINESS", 1, true))
    assert(text:find("GEAR CHECK") < text:find("READINESS"))
end)
test("self specialization changes invalidate cached gem and enchant checks", function()
    start(); ARC.forceSelfGearScan = false; ARC.selfDirty = false
    ARCEventFrame.scripts.OnEvent(ARCEventFrame, "PLAYER_SPECIALIZATION_CHANGED", "player")
    assert(ARC.forceSelfGearScan and ARC.selfDirty)
end)

local function menuStart()
    local f = start()
    f:Hide(); InspectFrame:Hide()
    UIDROPDOWNMENU_MENU_LEVEL = 1
    units.focus, units.mouseover, units.party1 = nil, nil, nil
    return f
end
local function popup(which, unit, name, server)
    UnitPopup_ShowMenu({ server = server }, which, unit, name)
    for _, item in ipairs(popupItems) do
        if item.text == "ARC Check" then return item end
    end
end

test("player context menu appends a lazy check and completes the selected player", function()
    local f = menuStart()
    local calls, closes = notifyCount, popupCloseCount
    local item = assert(popup("PLAYER", "target"))
    assert(#popupItems == 2 and popupItems[1].text == "Blizzard entry")
    assert(not item.disabled and item.notCheckable and item.tooltipOnButton)
    assert(not f:IsShown() and notifyCount == calls, "Opening a menu must not inspect")
    item.func()
    assert(f:IsShown() and f.entry.guid == "A" and popupCloseCount == closes + 1)
    step(); ARC.OnInspectReady("A")
    assert(not f.busy and f.entry.gear.scanned)
end)

test("context menu installs once and supports party, raid, target and focus", function()
    menuStart()
    ARC:InitPlayerCheckMenu(); ARC:InitPlayerCheckMenu()
    ARCEventFrame.scripts.OnEvent(ARCEventFrame, "PLAYER_ENTERING_WORLD")
    units.party1 = alice
    for _, which in ipairs({ "PARTY", "RAID_PLAYER", "RAID", "TARGET", "FOCUS" }) do
        assert(popup(which, "party1") and #popupItems == 2, which)
    end
    units.party1 = nil
end)

test("submenus, self, pets, NPCs and missing units do not offer checks", function()
    menuStart()
    UIDROPDOWNMENU_MENU_LEVEL = 2
    assert(not popup("PLAYER", "target") and #popupItems == 0)
    UIDROPDOWNMENU_MENU_LEVEL = 1
    assert(not popup("SELF", "player"))
    assert(not popup("PLAYER", "player"))
    assert(not popup("PET", "target"))
    alice.isPlayer = false
    assert(not popup("TARGET", "target"))
    alice.isPlayer = nil
    assert(not popup("PLAYER", "missing", "Alice-Realm"), "No fallback from a missing explicit unit")
end)

test("offline and out-of-range players have disabled and revalidated menu checks", function()
    local f = menuStart()
    local calls = notifyCount
    for _, field in ipairs({ "online", "visible" }) do
        alice[field] = false
        local item = assert(popup("PLAYER", "target"))
        assert(item.disabled)
        item.func()
        assert(not f:IsShown() and notifyCount == calls)
        alice[field] = true
    end
    local api = CanInspect
    CanInspect = function() error("unavailable API") end
    assert(popup("PLAYER", "target").disabled)
    CanInspect = api
    local item = assert(popup("PLAYER", "target"))
    alice.visible = false
    item.func()
    assert(not f:IsShown() and notifyCount == calls)
    alice.visible = true
end)

test("menu clicks never inspect a replacement target or alter the saved report", function()
    local f = menuStart()
    local entry, calls = f.entry, notifyCount
    local item = assert(popup("PLAYER", "target"))
    units.target = bob
    item.func()
    assert(not f:IsShown() and f.entry == entry and notifyCount == calls)
    units.target = alice
end)

test("menu identity survives dropdown reuse when the original player is still known", function()
    local f = menuStart()
    local dropdown = {}
    UnitPopup_ShowMenu(dropdown, "PLAYER", "target")
    local item = popupItems[2]
    units.focus, units.target = alice, bob
    UnitPopup_ShowMenu(dropdown, "PLAYER", "target")
    item.func()
    assert(f:IsShown() and f.entry.guid == "A" and f.entry.unit == "focus")
    step(); ARC.OnInspectReady("A")
    assert(not f.busy and f.entry.gear.scanned)
    units.focus, units.target = nil, alice
end)

test("name-only menus require an exact known player and realm", function()
    menuStart()
    assert(popup("FRIEND", nil, "Alice-Realm"))
    assert(popup("FRIEND", nil, "Alice"))
    assert(popup("CHAT_ROSTER", nil, "Alice", "Realm"))
    assert(not popup("FRIEND", nil, "Unknown"))
    assert(not popup("FRIEND_OFFLINE", nil, "Offline-Realm"))
    assert(not popup("FRIEND", nil, "Alice-OtherRealm"))
    assert(not popup("BN_FRIEND", nil, "Alice-Realm"))
    alice.realm = "Other Realm"
    assert(not popup("FRIEND", nil, "Alice"), "Unqualified names are local-realm only")
    assert(popup("FRIEND", nil, "Alice", "OtherRealm"))
    assert(popup("CHAT_ROSTER", nil, "Alice-OtherRealm"))
    alice.realm = nil
end)

test("name-only menus can resolve party units but reject ambiguous identities", function()
    menuStart()
    local api = ARC.Internal.GetGroupUnits
    ARC.Internal.GetGroupUnits = function() return { "player", "party1" } end
    units.target, units.party1 = bob, alice
    assert(popup("FRIEND", nil, "Alice-Realm"))
    units.focus = { guid = "IMPOSTOR", name = "Alice", online = true, visible = true }
    assert(not popup("FRIEND", nil, "Alice-Realm"))
    units.focus, units.party1, units.target = nil, nil, alice
    ARC.Internal.GetGroupUnits = api
end)

test("ARC row menu keeps existing actions and pins ARC Check to the row player", function()
    local f = menuStart()
    ARC:Show()
    local row = ARC:EnsureRow(2)
    local entry = { unit = "target", name = "Alice", fullName = "Alice-Realm" }
    ARC.roster[entry.fullName], row.fullName = entry, entry.fullName
    row.scripts.OnMouseUp(row, "RightButton")
    local actions = {}
    for _, item in ipairs(rowMenu) do actions[item.text] = item end
    assert(actions.Whisper and actions.Inspect and actions["Remind (confirmed issues)"])
    local item = assert(actions["ARC Check"])
    entry.unit = "other"
    item.func()
    assert(f:IsShown() and f.entry.guid == "A")
    f:Hide()
    row.scripts.OnMouseUp(row, "RightButton")
    for _, action in ipairs(rowMenu) do assert(action.text ~= "ARC Check", "Reject recycled row unit") end
    ARC:Hide()
end)

test("missing optional player-check module leaves row menu usable", function()
    menuStart(); ARC:Show()
    local row = ARC:EnsureRow(2)
    row.fullName = "Alice-Realm"
    ARC.roster[row.fullName] = { unit = "target", name = "Alice", fullName = row.fullName }
    local builder = ARC.CreatePlayerCheckMenuItem
    ARC.CreatePlayerCheckMenuItem = nil
    row.scripts.OnMouseUp(row, "RightButton")
    assert(#rowMenu == 5 and rowMenu[2].text == "Whisper")
    ARC.CreatePlayerCheckMenuItem = builder
    ARC:Hide()
end)
local function withGlobals(replacements, fn)
    local old = {}
    for key, value in pairs(replacements) do old[key] = _G[key]; _G[key] = value end
    local ok, reason = pcall(fn)
    for key in pairs(replacements) do _G[key] = old[key] end
    assert(ok, reason)
end

test("empty talents are errors in the report and raid columns, not glyphs", function()
    local f = start()
    talentMissing = { [2] = true, [6] = true }
    step(); ARC.OnInspectReady("A")
    assert(f.entry.talents.code == "101110" and #f.entry.talents.missing == 2)
    assert(contents(f):find("Empty available talent slots", 1, true))
    assert(contents(f):find("Tier 6 (level 90)", 1, true))
    ARC:Show()
    local row = ARC.frame.rows[1]
    assert(row.tal:GetText() == "!2" and row.tal.textColor[2] == 0.25)
    assert(ARC.frame.summary:GetText():find("Talents: 1", 1, true))
    ARC:Hide()
end)

test("talents only require unlocked tiers, including death knight unlock levels", function()
    start(); talentMissing = { [2] = true, [3] = true, [4] = true, [5] = true, [6] = true }
    units.player.level = 30
    local entry = {}
    ARC:ScanTalents("player", entry, false)
    assert(entry.talents.code == "10xxxx" and #entry.talents.missing == 1)
    units.player.class, units.player.level = "DEATHKNIGHT", 56
    ARC:ScanTalents("player", entry, false)
    assert(entry.talents.code == "1xxxxx" and entry.talents.required == 1)
    units.player.level = 55
    ARC:ScanTalents("player", entry, false)
    assert(ARC:GetTalentStatus(entry) == "-")
    units.player.class, units.player.level = nil, nil
end)

test("uncached, mismatched and unsupported talents cannot pass or report empty tiers", function()
    start()
    local entry = {}
    ARC:ScanTalents("target", entry, false)
    assert(not entry.talents.complete and #entry.talents.missing == 0)
    talentCold = true; ARC:ScanTalents("target", entry, true)
    assert(not entry.talents.complete and #entry.talents.missing == 0)
    talentCold, specMissing = false, true
    ARC:ScanTalents("target", entry, true)
    assert(not entry.talents.complete and #entry.talents.missing == 0)
    specMissing = false
    withGlobals({ GetTalentInfo = function() error("wrong API") end }, function()
        ARC:ScanTalents("target", entry, true)
        assert(ARC:GetTalentStatus(entry) == "?")
    end)
    withGlobals({ GetTalentInfo = function() return "Talent", "icon", 1, 1, true end }, function()
        ARC:ScanTalents("target", entry, true)
        assert(not entry.talents.complete and #entry.talents.missing == 0)
    end)
end)

test("all six empty talent tiers are detected only after a matched inspect", function()
    local f = start()
    for tier = 1, 6 do talentMissing[tier] = true end
    step(); ARC.OnInspectReady("B")
    assert(not f.entry.talents)
    ARC.OnInspectReady("A")
    assert(f.entry.talents.complete and #f.entry.talents.missing == 6)
end)

test("expired talent reports become unknown and respec events invalidate them", function()
    start()
    local entry = { talents = ARC:DecodeTalents("111111", "MAGE", 90, "comm") }
    assert(ARC:GetTalentStatus(entry) == "OK")
    now = now + 66
    assert(ARC:GetTalentStatus(entry) == "?")
    ARC.roster["Alice-Realm"] = { talents = entry.talents, specID = 62, lastGearScan = now }
    ARCEventFrame.scripts.OnEvent(ARCEventFrame, "PLAYER_SPECIALIZATION_CHANGED", "target")
    assert(not ARC.roster["Alice-Realm"].talents and not ARC.roster["Alice-Realm"].lastGearScan)
    ARC.selfDirty = false
    ARCEventFrame.scripts.OnEvent(ARCEventFrame, "PLAYER_TALENT_UPDATE")
    assert(ARC.selfDirty)
end)

local function buffEntry(class, ids, spec)
    if spec == nil then spec = ({ MAGE=62, PALADIN=70, WARRIOR=71, DRUID=102, DEATHKNIGHT=251, MONK=269 })[class] end
    local entry = { class = class, level = 90, specID = spec, online = true, buffs = { auras = {}, auraNames = {} } }
    for _, id in ipairs(ids or {}) do entry.buffs.auras[id] = true end
    return entry
end

test("rogue, priest, mage and paladin alternatives satisfy self-buff presence", function()
    start()
    for class, ids in pairs({ ROGUE = {2823,8679}, PRIEST = {588,73413}, MAGE = {6117,7302,30482}, PALADIN = {20154,20165,31801,20164} }) do
        local entry = buffEntry(class)
        assert(#ARC:ScanSelfBuffs("target", entry).missing == 1, class)
        for _, id in ipairs(ids) do
            entry = buffEntry(class, { id })
            entry.selfBuffs = ARC:ScanSelfBuffs("target", entry)
            assert(ARC:GetSelfBuffStatus(entry) == "OK", class .. " " .. id)
        end
    end
end)

test("self buffs use visible auras and suppress failures on unavailable/dead units", function()
    start()
    for _, kind in ipairs({ "offline", "dead", "unavailable" }) do
        local entry = buffEntry("PRIEST")
        if kind == "offline" then entry.online = false
        elseif kind == "dead" then entry.dead = true
        else entry.buffs = nil end
        entry.selfBuffs = ARC:ScanSelfBuffs("target", entry)
        assert(#entry.selfBuffs.missing == 0 and ARC:GetSelfBuffStatus(entry) == "?")
    end
    local entry = buffEntry("PRIEST"); entry.level = 30
    entry.selfBuffs = ARC:ScanSelfBuffs("target", entry)
    assert(ARC:GetSelfBuffStatus(entry) == "-")
    entry = buffEntry("WARRIOR")
    entry.selfBuffs = ARC:ScanSelfBuffs("target", entry)
    assert(ARC:GetSelfBuffStatus(entry) == "-", "Do not require combat stances or proc buffs")
end)

test("self buff localization and English fallback work when aura IDs differ", function()
    start()
    local entry = buffEntry("PRIEST")
    entry.buffs.auraNames["Inner Will"] = true
    assert(#ARC:ScanSelfBuffs("target", entry).missing == 0)
    entry.buffs.auraNames = { ["Localized armor"] = true }
    withGlobals({ GetSpellInfo = function(id) if id == 588 then return "Localized armor" end end }, function()
        assert(#ARC:ScanSelfBuffs("target", entry).missing == 0)
    end)
end)

test("shaman shields are spec-aware and imbues need a fresh self report", function()
    start()
    for spec, id in pairs({ [262]=324, [263]=324, [264]=52127 }) do
        local entry = buffEntry("SHAMAN", { id }, spec)
        entry.selfBuffs = ARC:ScanSelfBuffs("target", entry)
        assert(#entry.selfBuffs.missing == 0 and #entry.selfBuffs.unknown == 1)
        entry.weaponBuffs, entry.weaponBuffAt = "1x", now
        entry.selfBuffs = ARC:ScanSelfBuffs("target", entry)
        assert(ARC:GetSelfBuffStatus(entry) == "OK")
        entry.weaponBuffs = "00"
        entry.selfBuffs = ARC:ScanSelfBuffs("target", entry)
        assert(#entry.selfBuffs.missing == 2)
        entry.weaponBuffAt = now - 31
        entry.selfBuffs = ARC:ScanSelfBuffs("target", entry)
        assert(#entry.selfBuffs.missing == 0 and #entry.selfBuffs.unknown == 1)
    end
    local entry = buffEntry("SHAMAN", { 324 }, 264)
    assert(ARC:ScanSelfBuffs("target", entry).missing[1] == "Water Shield")
    entry.specID = nil
    assert(#ARC:ScanSelfBuffs("target", entry).missing == 0)
end)

test("legacy weapon enchant tuple reads off-hand at position four, not five", function()
    start(); units.player.class = "SHAMAN"
    gearOverrides[17] = { equipped = true, equipLoc = "INVTYPE_WEAPONOFFHAND" }
    withGlobals({ GetWeaponEnchantInfo = function() return nil, 0, 0, true, 60000, 0 end }, function()
        assert(ARC:ReadSelfWeaponBuffs() == "01")
    end)
    withGlobals({ GetWeaponEnchantInfo = function() return true, 60000, 0, nil, 0, 0 end }, function()
        assert(ARC:ReadSelfWeaponBuffs() == "10")
        gearOverrides[17].equipLoc = "INVTYPE_SHIELD"
        assert(ARC:ReadSelfWeaponBuffs() == "1x", "Shields do not require an imbue")
    end)
    withGlobals({ GetWeaponEnchantInfo = function() error("unavailable") end }, function()
        assert(ARC:ReadSelfWeaponBuffs() == "??")
    end)
    units.player.class = nil
    assert(ARC:ReadSelfWeaponBuffs() == "xx")
end)

test("Symbiosis is required only with an online non-druid in the same group", function()
    start()
    local entry = buffEntry("DRUID")
    assert(#ARC:ScanSelfBuffs("target", entry).missing == 0, "Unknown solo city player")
    units.party1, alice.class = alice, "DRUID"
    withGlobals({ IsInGroup = function() return true end, GetNumGroupMembers = function() return 2 end }, function()
        assert(ARC:ScanSelfBuffs("party1", entry).missing[1] == "Symbiosis")
        entry.buffs.auras[110309] = true
        assert(#ARC:ScanSelfBuffs("party1", entry).missing == 0)
        entry.buffs.auras[110309] = nil
        units.player.class = "DRUID"
        assert(#ARC:ScanSelfBuffs("party1", entry).missing == 0)
        units.player.class, units.player.online = nil, false
        assert(#ARC:ScanSelfBuffs("party1", entry).missing == 0)
        units.player.online = true
    end)
    units.party1, alice.class = nil, nil
end)

test("talent and weapon reports are sender-bound, bounded and backwards compatible", function()
    start(); units.party1, alice.class = alice, "SHAMAN"
    withGlobals({ IsInGroup = function() return true end, GetNumGroupMembers = function() return 2 end }, function()
        ARC.Internal.HandleCommMessage("Alice-Realm", "1.5.0^ForgedName-Realm^262^500^100^100^R1^101111^01")
        local entry = assert(ARC.roster["Alice-Realm"])
        assert(not ARC.roster["ForgedName-Realm"] and entry.talents.code == "101111" and entry.weaponBuffs == "01")
        assert(#entry.talents.missing == 1 and entry.weaponBuffAt == now)
        ARC.Internal.HandleCommMessage("Bob-Realm", "1.5.0^Alice-Realm^262^500^100^100^R1^000000^00")
        assert(entry.talents.code == "101111", "Non-member reports ignored")
        ARC.Internal.HandleCommMessage("Alice-Realm", "1.5.0^Alice-Realm^262^500^100^100^R1^broken^999")
        assert(not entry.weaponBuffs and entry.talents.code == "101111")
        ARC.Internal.HandleCommMessage("Alice-Realm", "1.4.0^Alice-Realm^262^500^100^100")
        assert(entry.ilvl == 500 and not entry.weaponBuffs)
        local time = entry.lastComm
        ARC.Internal.HandleCommMessage("Alice-Realm", string.rep("x", 256))
        assert(entry.lastComm == time)
    end)
    units.party1, alice.class = nil, nil
end)

test("closed ARC sends periodic readiness reports while preserving the two-second limit", function()
    menuStart(); ARC:Hide()
    local messages = {}
    withGlobals({ IsInGroup = function() return true end, GetNumGroupMembers = function() return 1 end,
        SendAddonMessage = function(prefix, message, channel)
            assert(prefix == "ARC1" and channel == "PARTY" and #message <= 255)
            messages[#messages + 1] = message
        end }, function()
        ARC.selfDirty, ARC.lastSelfBroadcast = false, now
        now = now + 15
        ARCEventFrame.scripts.OnUpdate(ARCEventFrame, 1.1)
        assert(#messages == 1 and messages[1]:find("^R1^111111^xx", 1, true))
        ARC.selfDirty = true
        ARCEventFrame.scripts.OnUpdate(ARCEventFrame, 1.1)
        assert(#messages == 1 and ARC.selfDirty)
        now = now + 2
        ARCEventFrame.scripts.OnUpdate(ARCEventFrame, 1.1)
        assert(#messages == 2 and not ARC:IsVisible())
    end)
end)

test("raid setup starts unconfigured, persists choices and never changes game settings", function()
    start()
    ARC_DB.raidSetup = { enabled = true, difficulty = 0, loot = "any" }
    withGlobals({ IsInRaid = function() return true end,
        GetInstanceInfo = function() return "City", "none", 0 end,
        GetRaidDifficultyID = function() return 3 end, GetLootMethod = function() return "group" end }, function()
        local text, tone = ARC:GetRaidSetupStatus()
        assert(tone == "warn" and text:find("NOT CONFIGURED", 1, true))
        ARC_DB.raidSetup.difficulty = 3
        text, tone = ARC:GetRaidSetupStatus()
        assert(tone == "good" and text:find("selected checks only", 1, true))
        ARC_DB.raidSetup.difficulty, ARC_DB.raidSetup.loot = 0, "group"
        text, tone = ARC:GetRaidSetupStatus()
        assert(tone == "good" and text:find("selected checks only", 1, true))
    end)
    ARC.Internal.ARC_InitDB()
    assert(ARC_DB.raidSetup.loot == "group")
    ARC_DB.raidSetup = { enabled = true, difficulty = 999, loot = "invalid" }
    ARC.Internal.ARC_InitDB()
    assert(ARC_DB.raidSetup.difficulty == 0 and ARC_DB.raidSetup.loot == "any")
end)

test("raid mismatch checks mode/size and loot, not invited player count", function()
    start(); ARC_DB.raidSetup = { enabled = true, difficulty = 5, loot = "master" }
    withGlobals({ IsInRaid = function() return true end, GetNumGroupMembers = function() return 12 end,
        GetInstanceInfo = function() return "City", "none", 0 end,
        GetRaidDifficultyID = function() return 4 end, GetLootMethod = function() return "group" end }, function()
        local text, tone = ARC:GetRaidSetupStatus()
        assert(tone == "bad" and text:find("25 Normal -> expected 10 Heroic", 1, true))
        assert(text:find("Group Loot -> expected Master Loot", 1, true))
        ARC_DB.raidSetup.difficulty, ARC_DB.raidSetup.loot = 4, "group"
        assert(select(2, ARC:GetRaidSetupStatus()) == "good")
    end)
end)

test("inside raids the instance difficulty overrides selected mode; missing data is unknown", function()
    start(); ARC_DB.raidSetup = { enabled = true, difficulty = 5, loot = "master" }
    local actual = 3
    withGlobals({ IsInRaid = function() return true end,
        GetInstanceInfo = function() return "Raid", "raid", actual end,
        GetRaidDifficultyID = function() return 5 end, GetLootMethod = function() return "master" end }, function()
        assert(select(2, ARC:GetRaidSetupStatus()) == "bad")
        actual = nil
        assert(select(2, ARC:GetRaidSetupStatus()) == "warn", "Do not fall back to selected difficulty in an unloaded instance")
        actual = 5
        assert(select(2, ARC:GetRaidSetupStatus()) == "good")
    end)
end)

test("unavailable or unknown loot is unverified, not a false match or mismatch", function()
    start(); ARC_DB.raidSetup = { enabled = true, difficulty = 5, loot = "master" }
    local loot
    withGlobals({ IsInRaid = function() return true end,
        GetInstanceInfo = function() return "Raid", "raid", 5 end,
        GetLootMethod = function() return loot end }, function()
        assert(select(2, ARC:GetRaidSetupStatus()) == "warn")
        loot = "unsupported"
        assert(select(2, ARC:GetRaidSetupStatus()) == "warn")
        ARC_DB.raidSetup.difficulty = 6
        local text, tone = ARC:GetRaidSetupStatus()
        assert(tone == "bad" and text:find("loot mode unavailable", 1, true))
    end)
end)

test("raid setup is neutral when disabled, solo or in a PvP instance", function()
    start(); ARC_DB.raidSetup = { enabled = true, difficulty = 5, loot = "master" }
    assert(select(2, ARC:GetRaidSetupStatus()) == "neutral")
    withGlobals({ IsInRaid = function() return true end, GetInstanceInfo = function() return "BG", "pvp", 0 end }, function()
        assert(select(2, ARC:GetRaidSetupStatus()) == "neutral")
        ARC_DB.raidSetup.enabled = false
        assert(ARC:GetRaidSetupStatus():find("OFF", 1, true))
    end)
end)

test("raid options and slash command update saved expectations and labels", function()
    start(); ARC_DB.raidSetup = { enabled = true, difficulty = 0, loot = "any" }
    SlashCmdList.ARC("raid")
    local panel = assert(ARC.raidOptionsPanel)
    assert(panel.parent == "ARC")
    panel.mode.scripts.OnClick(panel.mode)
    for _, item in ipairs(rowMenu) do if item.text == "25 Heroic" then item.func() end end
    assert(ARC_DB.raidSetup.difficulty == 6 and panel.mode:GetText():find("25 Heroic", 1, true))
    panel.loot.scripts.OnClick(panel.loot)
    for _, item in ipairs(rowMenu) do if item.text == "Master Loot" then item.func() end end
    assert(ARC_DB.raidSetup.loot == "master")
    ARCRaidSetupEnabled:SetChecked(false)
    ARCRaidSetupEnabled.scripts.OnClick(ARCRaidSetupEnabled)
    assert(not ARC_DB.raidSetup.enabled)
    assert(ARC:CreateRaidOptions() == panel)
end)

test("raid setup banner is red on mismatch, updates on events and opens options", function()
    start(); ARC:Show()
    ARC_DB.raidSetup = { enabled = true, difficulty = 5, loot = "master" }
    local loot = "group"
    withGlobals({ IsInRaid = function() return true end, GetInstanceInfo = function() return "Raid", "raid", 5 end,
        GetLootMethod = function() return loot end }, function()
        ARC:Render()
        local banner = ARC.frame.raidBanner
        assert(banner.bg.vertexColor[1] == 0.8 and banner.label:GetText():find("MISMATCH", 1, true))
        assert(banner.points[1][3] == -52 and banner.height == 48 and ARC.frame.width == 872)
        loot = "master"
        ARCEventFrame.scripts.OnEvent(ARCEventFrame, "PARTY_LOOT_METHOD_CHANGED")
        assert(banner.label:GetText():find("Raid setup OK", 1, true), "Setup status remains visible below readiness")
        local opened = false
        withGlobals({ InterfaceOptionsFrame_OpenToCategory = function(panel) opened = panel == ARC.raidOptionsPanel end }, function()
            banner.scripts.OnClick(banner)
            assert(opened)
        end)
    end)
    ARC:Hide()
end)

test("self-buff findings render directly in the standalone report and raid summary", function()
    local f = start(); alice.class = "PRIEST"
    ARC:ShowPlayerCheck("target", "A")
    step(); ARC.OnInspectReady("A")
    assert(contents(f):find("Missing self buff: Inner Fire / Inner Will", 1, true))
    units.player.class = "PRIEST"
    ARC:Show()
    assert(ARC.frame.rows[1].selfBuff:GetText() == "!1")
    assert(ARC.frame.summary:GetText():find("Self: 1", 1, true))
    units.player.class, alice.class = nil, nil
    ARC:Hide()
end)
test("Protection paladins require RF and non-Protection paladins must remove it", function()
    start()
    local entry = buffEntry("PALADIN", {20165}, 66)
    assert(ARC:ScanSelfBuffs("target", entry).missing[1] == "Righteous Fury")
    entry.buffs.auras[25780] = true
    entry.selfBuffs = ARC:ScanSelfBuffs("target", entry)
    assert(ARC:GetSelfBuffStatus(entry) == "OK")
    for _, spec in ipairs({65,70}) do
        entry.specID, entry.role = spec, "TANK" -- actual spec, not a manually assigned role
        entry.selfBuffs = ARC:ScanSelfBuffs("target", entry)
        assert(#entry.selfBuffs.problems == 1 and select(2, ARC:GetSelfBuffStatus(entry)) == "bad")
    end
    entry.specID = nil
    entry.selfBuffs = ARC:ScanSelfBuffs("target", entry)
    assert(#entry.selfBuffs.problems == 0 and #entry.selfBuffs.unknown > 0)
end)

test("all tank form profiles accept visible positives and owner-confirmed negatives", function()
    start()
    for _, profile in ipairs({ {"DEATHKNIGHT",250,48263}, {"WARRIOR",73,71}, {"DRUID",104,5487}, {"MONK",268,115069} }) do
        local entry = buffEntry(profile[1], {}, profile[2])
        entry.selfBuffs = ARC:ScanSelfBuffs("target", entry)
        assert(#entry.selfBuffs.missing == 0 and #entry.selfBuffs.unknown > 0, "Hidden form aura is not negative proof")
        entry.preparation = { form = "0", specID = profile[2], checkedAt = now }
        entry.selfBuffs = ARC:ScanSelfBuffs("target", entry)
        assert(#entry.selfBuffs.missing == 1 and select(2, ARC:GetSelfBuffStatus(entry)) == "bad")
        entry.preparation.form = "1"
        entry.selfBuffs = ARC:ScanSelfBuffs("target", entry)
        assert(ARC:GetSelfBuffStatus(entry) == "OK")
        entry.preparation = nil; entry.buffs.auras[profile[3]] = true
        entry.selfBuffs = ARC:ScanSelfBuffs("target", entry)
        assert(ARC:GetSelfBuffStatus(entry) == "OK", "Visible correct aura also works without ARC")
    end
end)

test("native MoP stance API, expiry and changed-spec form reports remain safe", function()
    start()
    local entry = buffEntry("WARRIOR", {}, 73)
    local active = false
    withGlobals({ GetNumShapeshiftForms = function() return 2 end,
        GetShapeshiftFormInfo = function(index) return "icon", index == 1 and "Battle Stance" or "Defensive Stance", active, true end }, function()
        assert(ARC:ReadTankForm(entry) == "0")
        active = true; assert(ARC:ReadTankForm(entry) == "1")
    end)
    assert(ARC:ReadTankForm(entry) == "?")
    entry.preparation = { checkedAt = now - 31, form = "0", specID = 73 }
    assert(#ARC:ScanSelfBuffs("target", entry).missing == 0)
    entry.preparation.checkedAt, entry.preparation.specID = now, 250
    assert(#ARC:ScanSelfBuffs("target", entry).missing == 0)
    entry.preparation.specID, entry.dead = 73, true
    assert(#ARC:ScanSelfBuffs("target", entry).missing == 0)
end)

test("remote missing pets stay unknown without owner reports; visible dead pets fail", function()
    start()
    local entry = buffEntry("HUNTER", {}, 253)
    entry.selfBuffs = ARC:ScanSelfBuffs("target", entry)
    assert(#entry.selfBuffs.problems == 0 and #entry.selfBuffs.unknown > 0)
    entry.preparation = { pet="0", checkedAt=now }
    assert(ARC:ScanSelfBuffs("target", entry).problems[1]:find("missing", 1, true))
    units.targetpet = { guid="PET-A", visible=true, dead=true }
    assert(ARC:ScanSelfBuffs("target", entry).problems[1]:find("dead", 1, true))
    units.targetpet.dead = false
    assert(#ARC:ScanSelfBuffs("target", entry).problems == 0, "Live pet overrides old absence report")
    units.targetpet = nil
    entry.preparation.checkedAt = now - 31
    assert(#ARC:ScanSelfBuffs("target", entry).problems == 0)
end)

test("own pets and party/raid tokens are resolved without confusing owner or vehicle", function()
    start()
    local entry = buffEntry("HUNTER", {}, 253)
    assert(ARC:GetPetState("player", entry) == "0")
    withGlobals({ IsMounted = function() return true end }, function()
        assert(ARC:GetPetState("player", entry) == "?")
    end)
    units.party1, units.raid1 = alice, alice
    units.partypet1 = { guid="PARTY-PET", visible=true }
    units.raidpet1 = { guid="RAID-PET", visible=true }
    assert(select(2, ARC:GetPetState("party1", entry)) == "PARTY-PET")
    assert(select(2, ARC:GetPetState("raid1", entry)) == "RAID-PET")
    withGlobals({ UnitHasVehicleUI = function() return true end }, function()
        assert(ARC:GetPetState("raid1", entry) == "?")
    end)
    units.party1, units.raid1, units.partypet1, units.raidpet1 = nil, nil, nil, nil
end)

test("Frost mage and Unholy DK need permanent pets, other specs do not", function()
    start()
    for _, data in ipairs({ {"MAGE",64,63,{6117}}, {"DEATHKNIGHT",252,251,{}} }) do
        local entry = buffEntry(data[1], data[4], data[2])
        entry.preparation = { pet="0", checkedAt=now }
        assert(#ARC:ScanSelfBuffs("target", entry).problems == 1)
        entry.specID = data[3]
        assert(#ARC:ScanSelfBuffs("target", entry).problems == 0)
    end
end)

test("Growl autocast is found in the pet spellbook even off the action bar", function()
    start(); units.pet = { guid="PET-A", visible=true }
    local enabled = true
    withGlobals({ HasPetSpells = function() return 3 end,
        GetSpellBookItemInfo = function(index, book) assert(book == "pet"); return "SPELL", index == 2 and 2649 or 100 end,
        GetSpellAutocast = function(index, book) assert(index == 2 and book == "pet"); return true, enabled end }, function()
        assert(ARC:ReadHunterGrowl() == "1")
        enabled = nil; assert(ARC:ReadHunterGrowl() == "0")
        enabled = false; assert(ARC:ReadHunterGrowl() == "0")
        enabled = 0; assert(ARC:ReadHunterGrowl() == "0")
    end)
    units.pet = nil
end)

test("Growl action-bar fallback is conservative for missing or broken APIs", function()
    start(); units.pet = { guid="PET-A", visible=true }
    withGlobals({ GetPetActionInfo = function(index)
        if index == 7 then return "Growl", nil, "icon", false, false, true, true end
    end }, function() assert(ARC:ReadHunterGrowl() == "1") end)
    withGlobals({ GetPetActionInfo = function() return "Attack", nil, "icon", true, true, nil, nil end }, function()
        assert(ARC:ReadHunterGrowl() == "?", "No Growl on bar is not autocast OFF")
    end)
    withGlobals({ HasPetSpells = function() error("API unavailable") end }, function()
        assert(ARC:ReadHunterGrowl() == "?")
    end)
    units.pet = nil
end)

test("hunter warnings require fresh Growl state for the same pet GUID", function()
    start()
    local entry = buffEntry("HUNTER", {}, 253)
    units.targetpet = { guid="PET-NEW", visible=true }
    entry.preparation = { pet="1", petGUID="PET-OLD", growl="1", checkedAt=now }
    local result = ARC:ScanSelfBuffs("target", entry)
    assert(#result.problems == 0 and #result.unknown == 1)
    entry.preparation.petGUID = "PET-NEW"
    result = ARC:ScanSelfBuffs("target", entry)
    assert(result.problems[1]:find("Growl autocast is ON", 1, true))
    entry.preparation.growl = "0"
    entry.selfBuffs = ARC:ScanSelfBuffs("target", entry)
    assert(ARC:GetSelfBuffStatus(entry) == "OK")
    units.targetpet = nil
end)

test("warlock Sacrifice needs the selected talent AND active buff; other builds need pets", function()
    start()
    local entry = buffEntry("WARLOCK", {}, 267)
    entry.sacrifice = { state="1", checkedAt=now, specID=267 }
    entry.preparation = { pet="0", checkedAt=now }
    local result = ARC:ScanSelfBuffs("target", entry)
    assert(result.missing[1] == "Grimoire of Sacrifice buff" and #result.problems == 0)
    entry.buffs.auras[108503] = true
    entry.selfBuffs = ARC:ScanSelfBuffs("target", entry)
    assert(ARC:GetSelfBuffStatus(entry) == "OK")
    entry.sacrifice.state = "0"
    result = ARC:ScanSelfBuffs("target", entry)
    assert(#result.problems == 1, "A leftover buff cannot exempt a non-Sacrifice build")
    entry.preparation.pet = "1"
    entry.selfBuffs = ARC:ScanSelfBuffs("target", entry)
    assert(ARC:GetSelfBuffStatus(entry) == "OK")
    entry.sacrifice.checkedAt = now - 66
    result = ARC:ScanSelfBuffs("target", entry)
    assert(#result.unknown == 1 and #result.problems == 0)
    entry.sacrifice.checkedAt, entry.sacrifice.specID = now, 265
    assert(#ARC:ScanSelfBuffs("target", entry).unknown == 1)
end)

test("legacy warlock talent index 15 is captured only from complete tier-five data", function()
    start(); alice.class = "WARLOCK"
    local entry = buffEntry("WARLOCK", {}, 267)
    withGlobals({ GetTalentInfo = function(index)
        local tier, column = math.floor((index-1)/3)+1, (index-1)%3+1
        return "Talent", "icon", tier, column, (tier == 5 and column == 3) or (tier ~= 5 and column == 1), true
    end }, function()
        ARC:ScanTalents("target", entry, true)
        assert(entry.sacrifice.state == "1" and ARC:GetSacrificeState(entry) == "1")
    end)
    ARC:ScanTalents("target", entry, true)
    assert(entry.sacrifice.state == "0")
    talentCold = true; ARC:ScanTalents("target", entry, true)
    assert(entry.sacrifice.state == "?")
    alice.class = nil
end)

test("Healthstone count excludes bank and uses charges instead of item count", function()
    start()
    local count, charges = 1, 3
    withGlobals({ GetItemCount = function(id, bank, useCharges)
        assert(id == 5512 and bank == false)
        if useCharges then return charges end
        return count
    end }, function()
        assert(ARC:ReadHealthstone() == "3")
        charges = 1; assert(ARC:ReadHealthstone() == "1")
        charges = 0; assert(ARC:ReadHealthstone() == "0")
        charges = nil; assert(ARC:ReadHealthstone() == "p")
        count = 0; assert(ARC:ReadHealthstone() == "0")
    end)
    assert(ARC:ReadHealthstone() == "?")
end)

test("Healthstones require a group supplier and current ARC data; no-ARC is unknown", function()
    start()
    local entry = { unit="target", guid="A", online=true, preparation={ healthstone="0", checkedAt=now } }
    assert(ARC:GetHealthstoneStatus(entry) == "-")
    units.party1, units.player.class = alice, "WARLOCK"
    withGlobals({ IsInGroup = function() return true end, GetNumGroupMembers = function() return 2 end }, function()
        assert(ARC:GetHealthstoneStatus(entry) == "!0")
        entry.preparation.healthstone = "3"
        assert(ARC:GetHealthstoneStatus(entry) == "3")
        entry.preparation.healthstone = "p"
        assert(ARC:GetHealthstoneStatus(entry) == "?")
        entry.preparation.checkedAt = now - 31
        assert(ARC:GetHealthstoneStatus(entry) == "?")
        entry.preparation = nil
        assert(ARC:GetHealthstoneStatus(entry) == "?")
        units.player.class = nil
        assert(ARC:GetHealthstoneStatus(entry) == "-")
    end)
    units.party1, units.player.class = nil, nil
end)

test("P1 preparation extension is validated and older R1 peers retain compatibility", function()
    start(); units.party1, alice.class = alice, "WARLOCK"
    withGlobals({ IsInGroup = function() return true end, GetNumGroupMembers = function() return 2 end }, function()
        local message = "1.5.0^Alice-Realm^267^500^100^100^R1^111111^xx^P1^0^?^1^3^-^?"
        ARC.Internal.HandleCommMessage("Alice-Realm", message)
        local entry = ARC.roster["Alice-Realm"]
        assert(entry.preparation.healthstone == "3" and ARC:GetSacrificeState(entry) == "1")
        assert(entry.talents.code == "111111")
        ARC.Internal.HandleCommMessage("Alice-Realm", "1.5.0^Alice-Realm^267^500^100^100^R1^111111^xx")
        assert(not entry.preparation and entry.talents.complete and entry.weaponBuffs == "xx")
        assert(not ARC:DecodePreparation("1", "0", "3", "-", "?", 253), "Present pets need a GUID")
        assert(not ARC:DecodePreparation("0", "0", "9", "-", "?", 253))
        assert(not ARC:DecodePreparation("1", "0", "3", "|Hbad", "?", 253))
        assert(not ARC:DecodePreparation("1", "0", "3", "PET", "invalid", 253))
        local prep = ARC:DecodePreparation("1", "0", "3", "PET", "0", 73)
        assert(prep.petGUID == "PET" and prep.form == "0" and prep.specID == 73)
    end)
    units.party1, alice.class = nil, nil
end)

test("pet, bag and stance events mark self reports dirty without automatic game actions", function()
    menuStart(); ARC:Hide()
    for _, event in ipairs({ "PET_BAR_UPDATE", "BAG_UPDATE", "UPDATE_SHAPESHIFT_FORM", "UNIT_PET" }) do
        ARC.selfDirty = false
        ARCEventFrame.scripts.OnEvent(ARCEventFrame, event, "player")
        assert(ARC.selfDirty and not ARC:IsVisible())
    end
end)

test("Healthstone column and report show confirmed missing items in red", function()
    start(); ARC:Show()
    units.party1, units.player.class = alice, "WARLOCK"
    withGlobals({ IsInGroup = function() return true end, GetNumGroupMembers = function() return 2 end,
        GetItemCount = function() return 0 end }, function()
        ARC:RefreshRoster()
        local entry = ARC.roster["Alice-Realm"]
        entry.preparation = { pet="0", healthstone="0", checkedAt=now }
        entry.lastComm = now
        ARC:Render()
        assert(ARC.frame.summary:GetText():find("HS: 2", 1, true))
        local row
        for _, candidate in ipairs(ARC.frame.rows) do if candidate.fullName == "Alice-Realm" then row = candidate end end
        assert(row.hs:GetText() == "!0" and row.hs.textColor[2] == 0.25)
        ARC:ShowPlayerCheck("target", "A")
        assert(contents(ARC.playerCheckFrame):find("Healthstone missing", 1, true))
    end)
    units.party1, units.player.class = nil, nil
    ARC:Hide()
end)
test("outgoing P1 reports round-trip real pet, Sacrifice, charge and form fields", function()
    menuStart(); ARC:Hide()
    for _, profile in ipairs({ {"HUNTER",253}, {"WARLOCK",267}, {"WARRIOR",73} }) do
        units.player.class = profile[1]
        units.pet = profile[1] == "HUNTER" and { guid="PET-SELF", visible=true } or nil
        local message
        withGlobals({ IsInGroup = function() return true end, GetNumGroupMembers = function() return 1 end,
            GetSpecializationInfo = function() return profile[2], "Spec", nil, "icon", nil, "DAMAGER" end,
            GetItemCount = function(_, bank, charges) assert(bank == false); return charges and 3 or 1 end,
            GetTalentInfo = function(index)
                local tier, column = math.floor((index-1)/3)+1, (index-1)%3+1
                return "Talent", "icon", tier, column, column == (tier == 5 and 3 or 1), true
            end,
            HasPetSpells = function() return 1 end,
            GetSpellBookItemInfo = function() return "SPELL", 2649 end,
            GetSpellAutocast = function() return true, true end,
            GetNumShapeshiftForms = function() return 1 end,
            GetShapeshiftFormInfo = function() return "icon", "Defensive Stance", false, true end,
            SendAddonMessage = function(_, payload) message = payload end }, function()
            ARC.selfDirty, ARC.lastSelfBroadcast = true, now - 3
            ARCEventFrame.scripts.OnUpdate(ARCEventFrame, 1.1)
            assert(message and #message <= 255)
            local fields = { strsplit("^", message) }
            assert(#fields == 16 and fields[7] == "R1" and fields[10] == "P1" and fields[14] == "3")
            local entry = assert(ARC.roster["Me-Realm"])
            entry.preparation, entry.sacrifice = nil, nil
            ARC.Internal.HandleCommMessage("Me-Realm", message)
            local prep = assert(entry.preparation)
            assert(prep.healthstone == "3" and prep.specID == profile[2])
            if profile[1] == "HUNTER" then
                assert(prep.pet == "1" and prep.petGUID == "PET-SELF" and prep.growl == "1")
            elseif profile[1] == "WARLOCK" then
                assert(prep.pet == "0" and ARC:GetSacrificeState(entry) == "1")
            else assert(prep.form == "0") end
        end)
    end
    units.pet, units.player.class = nil, nil
end)

test("malformed P1 cannot install Sacrifice evidence and Healthstone snapshots stay GUID-bound", function()
    start(); units.party1, alice.class = alice, "WARLOCK"
    withGlobals({ IsInGroup = function() return true end, GetNumGroupMembers = function() return 2 end }, function()
        ARC.Internal.HandleCommMessage("Alice-Realm", "1.5.0^Alice-Realm^267^500^100^100^R1^111111^xx^P1^0^?^1^9^-^?")
        local entry = ARC.roster["Alice-Realm"]
        assert(not entry.preparation and not entry.sacrifice)
        local snapshot = { unit="target", guid="A", online=true, preparation={ healthstone="0", checkedAt=now } }
        assert(ARC:GetHealthstoneStatus(snapshot) == "!0")
        units.target = bob
        assert(ARC:GetHealthstoneStatus(snapshot) == "-", "Changed target cannot reuse a group member's bags")
        units.target = alice
        snapshot.preparation.healthstone = nil
        assert(ARC:GetHealthstoneStatus(snapshot) == "?")
    end)
    units.party1, alice.class = nil, nil
end)
local function firstItemRow(frame)
    for index = 1, frame.lineCount do
        local row = frame.lines[index]
        if row.itemIcon and row.itemIcon:IsShown() and row.itemIcon.itemLink then return row end
    end
    error("Expected an item icon in the problem report")
end

test("problem item icons use captured textures and full links, never the current target", function()
    local frame = start(); step(); ARC.OnInspectReady("A")
    local row = firstItemRow(frame)
    local icon, link = row.itemIcon, row.itemIcon.itemLink
    assert(icon.texture.texture[1] == "item-icon")
    assert(row.value.points[1][2] == 168 and row.value.width == 414 and row.height >= 40)
    assert(icon.points[1][2] == 132 and icon.width == 28 and icon.height == 28)
    local requests = notifyCount
    units.target = bob
    icon.scripts.OnEnter(icon)
    assert(GameTooltip:IsShown() and GameTooltip:IsOwned(icon) and GameTooltip.hyperlink == link)
    assert(notifyCount == requests, "Hover must not send inspect requests")
    ARC:UpdatePlayerCheck()
    assert(GameTooltip:IsShown(), "Unchanged snapshot refresh should not flicker the tooltip")
    icon.scripts.OnLeave(icon)
    assert(not GameTooltip:IsShown())
    units.target = alice
    -- Preserve all item-instance fields, not only the base item ID.
    for _, item in ipairs(frame.entry.gear.slots) do
        if item.link == link then item.link = link .. ":4"; item.icon = "captured-instance-icon"; break end
    end
    ARC:UpdatePlayerCheck()
    icon.scripts.OnEnter(icon)
    assert(GameTooltip.hyperlink == link .. ":4" and icon.texture.texture[1] == "captured-instance-icon")
    frame:Hide()
    assert(not GameTooltip:IsShown(), "Closing the report must dismiss its tooltip")
end)

test("reused, empty and hidden report rows remove stale item icons and tooltip ownership", function()
    local frame = start(); step(); ARC.OnInspectReady("A")
    local row = firstItemRow(frame)
    local icon = row.itemIcon
    icon.scripts.OnEnter(icon)
    for _, item in ipairs(frame.entry.gear.slots) do
        if item.link == icon.itemLink then item.empty = true; item.issues = { "Empty required slot" }; break end
    end
    ARC:UpdatePlayerCheck()
    assert(not icon:IsShown() and not icon.itemLink and not GameTooltip:IsShown())
    assert(row.value.points[1][2] == 132 and row.value.width == 450)
    for _, item in ipairs(frame.entry.gear.slots) do item.issues = {} end
    frame.entry.gear.issueCount = 0
    ARC:UpdatePlayerCheck()
    for _, old in ipairs(frame.lines) do
        assert(not old.itemIcon or (not old.itemIcon:IsShown() and not old.itemIcon.itemLink))
    end
    -- An unrelated tooltip must not be hidden when the report closes.
    GameTooltip:SetOwner(UIParent, "ANCHOR_RIGHT"); GameTooltip:Show()
    frame:Hide()
    assert(GameTooltip:IsShown())
    GameTooltip:Hide()
end)

test("item tooltip failures and missing icons degrade safely", function()
    local frame = start(); step(); ARC.OnInspectReady("A")
    local row = firstItemRow(frame)
    for _, item in ipairs(frame.entry.gear.slots) do if item.link == row.itemIcon.itemLink then item.icon = nil end end
    ARC:UpdatePlayerCheck()
    assert(row.itemIcon.texture.texture[1] == "Interface\\Icons\\INV_Misc_QuestionMark")
    local old = GameTooltip.SetHyperlink
    GameTooltip.SetHyperlink = function() error("Item data not available") end
    row.itemIcon.scripts.OnEnter(row.itemIcon)
    GameTooltip.SetHyperlink = old
    assert(GameTooltip:IsShown() and GameTooltip.tooltipLines[1]:find("unavailable", 1, true))
    row.itemIcon.scripts.OnLeave(row.itemIcon)
    assert(not GameTooltip:IsShown())
end)

test("Talents label and row tooltip omit the old glyph parenthesis", function()
    start(); ARC:Show()
    local row = ARC.frame.rows[1]
    GameTooltip:ClearLines()
    row.scripts.OnEnter(row)
    local text = table.concat(GameTooltip.tooltipLines, "\n")
    assert(text:find("Talents:", 1, true) and not text:find("available tiers only", 1, true) and not text:find("no glyph check", 1, true))
    assert(ARC.frame.summary:GetText():find("Talents:", 1, true))
    assert(row.tal.width == 60 and row.selfBuff.points[1][2] == 686)
    local foundHeader = false
    for _, label in ipairs(ARC.frame.header.labels) do
        assert(label:GetText() ~= "Tal")
        if label:GetText() == "Talents" then foundHeader = true; assert(label.width == 60) end
    end
    assert(foundHeader)
    ARC:Hide(); GameTooltip:Hide()
end)
test("raid branding preserves slash commands, minimap actions, settings and countdown", function()
    start()
    local db = ARC_DB
    ARC.readyCheckActive, ARC.readyCheckFinished = false, false
    ARC:Show()
    assert(ARC.frame.title:GetText() == "ARC - Advanced Raid Check")
    assert(SLASH_ARC1 == "/arc" and ARC_DB == db)
    GameTooltip:ClearLines()
    ARC.minimapButton.scripts.OnEnter(ARC.minimapButton)
    assert(GameTooltip.tooltipLines[1] == "ARC - Advanced Raid Check")
    ARC.readyCheckActive, ARC.readyCheckExpiresAt, readyTimeLeft = true, now + 13, 13
    ARC:Render()
    assert(ARC.frame.title:GetText() == "ARC - Advanced Raid Check (13 seconds remaining)")
    ARC.readyCheckActive, ARC.readyCheckFinished = false, true
    ARC:Render()
    assert(ARC.frame.title:GetText() == "ARC - Advanced Raid Check (Finished)")
    ARC.readyCheckFinished, readyTimeLeft = false, 30
    ARC:Hide(); GameTooltip:Hide()
end)

test("25-player roster is scrollable and capped to the screen height", function()
    local saved = {}
    for i = 1, 25 do
        local key = "raid" .. i
        saved[key] = units[key]
        units[key] = { guid = "R" .. i, name = "Raider" .. i, online = true, visible = true }
    end
    ARC:Hide(); wipe(ARC.roster)
    withGlobals({ IsInRaid = function() return true end, IsInGroup = function() return true end,
        GetNumGroupMembers = function() return 25 end, GetScreenHeight = function() return 768 end }, function()
        ARC:Show()
        assert(ARC.frame.rosterScroll.scrollChild == ARC.frame.rowsContainer)
        assert(ARC.frame.rowsContainer.height == 25 * 26)
        assert(ARC.frame.height <= 728 and ARC.frame.height < 162 + 34 + 25 * 26)
        assert(ARC.frame.hint:GetText():find("Inspect:", 1, true))
    end)
    ARC:Hide(); wipe(ARC.roster)
    for i = 1, 25 do units["raid" .. i] = saved["raid" .. i] end
end)

test("one-second updates use status refresh with a five-second full-scan fallback", function()
    menuStart(); ARC:Show()
    local scans, original = 0, UnitBuff
    ARC.selfDirty, ARC.lastSelfBroadcast = false, now
    withGlobals({ UnitBuff = function(...) scans = scans + 1; return original(...) end }, function()
        for _ = 1, 4 do ARCEventFrame.scripts.OnUpdate(ARCEventFrame, 1.1) end
    end)
    assert(scans <= 4, "Four ticks must perform at most one full aura scan, not four")
    ARC:Hide()
end)

test("expiring consumables are yellow, counted and included in confirmed reminders", function()
    menuStart(); ARC:Show()
    local entry = ARC.roster["Me-Realm"]
    entry.flask, entry.flaskIcon, entry.flaskExpiresAt = true, "flask", now + 240
    entry.food, entry.foodIcon, entry.foodExpiresAt = true, "food", now + 3600
    entry.auraDataAvailable, entry.online = true, true
    entry.gear = { scanned = true, auditComplete = true, issueCount = 2 }
    ARC:Render()
    local row = ARC.frame.rows[1]
    assert(row.flask.vertexColor[1] == 1 and row.flask.vertexColor[2] == 0.72)
    assert(ARC.frame.summary:GetText():find("Soon: 1", 1, true))
    local whisper
    withGlobals({ SendChatMessage = function(message, channel, _, target)
        whisper = { message, channel, target }
    end }, function() ARC:RemindPlayer(entry) end)
    assert(whisper and whisper[1]:find("flask <4m", 1, true) and whisper[1]:find("gear (2 issues)", 1, true))
    assert(whisper[2] == "WHISPER" and whisper[3] == "Me-Realm")
    ARC:Hide()
end)

test("ARC versions compare numerically and outdated peers are visible", function()
    assert(ARC:CompareVersions("1.5.9", "1.6.0") == -1)
    assert(ARC:CompareVersions("1.6.0", "1.6.0") == 0)
    assert(ARC:CompareVersions("1.10.0", "1.6.0") == 1)
    assert(ARC:CompareVersions("custom", "1.6.0") == nil)
    menuStart(); ARC:Show()
    local entry = ARC.roster["Me-Realm"]
    entry.arcVersion = "1.5.0"
    ARC:Render()
    assert(ARC.frame.rows[1].arc:GetText() == "Old")
    assert(ARC.frame.summary:GetText():find("Old: 1", 1, true))
    ARC:Hide()
end)

test("AFK state updates immediately and is a confirmed raid blocker", function()
    menuStart(); ARC:Show()
    units.player.afk = true
    ARCEventFrame.scripts.OnEvent(ARCEventFrame, "PLAYER_FLAGS_CHANGED", "player")
    local row = ARC.frame.rows[1]
    assert(row.name:GetText():find("(afk)", 1, true))
    assert(row.bg.vertexColor[1] == 1 and row.bg.vertexColor[2] == 0.48)
    assert(ARC.frame.raidBanner.label:GetText():find("NOT READY", 1, true))
    units.player.afk = false
    ARCEventFrame.scripts.OnEvent(ARCEventFrame, "PLAYER_FLAGS_CHANGED", "player")
    assert(not row.name:GetText():find("(afk)", 1, true))
    ARC:Hide()
end)

test("raid verdict separates confirmed failures from unverified data", function()
    menuStart(); ARC:Show()
    local entry = ARC.roster["Me-Realm"]
    entry.online, entry.dead, entry.afk = true, false, false
    entry.gear = { scanned = true, auditComplete = true, issueCount = 0 }
    entry.auraDataAvailable = false
    local text, tone = ARC:GetRaidReadinessVerdict()
    assert(tone == "warn" and text:find("CHECK INCOMPLETE", 1, true))
    entry.online = false
    text, tone = ARC:GetRaidReadinessVerdict()
    assert(tone == "bad" and text:find("confirmed issues", 1, true))
    ARC:Hide()
end)

test("raid sessions track attendance, exact AFK flags, strict trash inactivity and boss pulls", function()
    menuStart(); ARC:Hide()
    ARC.activeSession, ARC_DB.activeSession, ARC.sessionActivity = nil, nil, nil
    ARC_DB.sessions = {}
    units.party1 = alice
    alice.afk, alice.dead, alice.online, alice.visible = false, false, true, true
    withGlobals({ IsInGroup = function() return true end, GetNumGroupMembers = function() return 2 end,
        GetInstanceInfo = function() return "Siege of Orgrimmar", "raid", 5 end }, function()
        assert(ARC:StartRaidSession())
        local session = ARC.activeSession
        local member = assert(session.members["Alice-Realm"])

        alice.afk = true
        ARCSessionEventFrame.scripts.OnEvent(ARCSessionEventFrame, "PLAYER_FLAGS_CHANGED", "party1")
        now = now + 7
        alice.afk = false
        ARCSessionEventFrame.scripts.OnEvent(ARCSessionEventFrame, "PLAYER_FLAGS_CHANGED", "party1")
        assert(member.afkSeconds == 7)

        ARC:StartTrashCombat()
        for _ = 1, 12 do now = now + 1; ARCSessionEventFrame.scripts.OnUpdate(ARCSessionEventFrame, 1.1) end
        assert(member.trashInactiveSeconds == 12, "Crossing 10s must retroactively include the first ten seconds")
        ARC:SessionCombatLog(now, "SPELL_CAST_SUCCESS", false, "A", "Alice", 0, 0, nil, nil)
        for _ = 1, 5 do now = now + 1; ARCSessionEventFrame.scripts.OnUpdate(ARCSessionEventFrame, 1.1) end
        assert(member.trashInactiveSeconds == 12, "Activity resets the inactivity timer")
        for _ = 1, 6 do now = now + 1; ARCSessionEventFrame.scripts.OnUpdate(ARCSessionEventFrame, 1.1) end
        assert(member.trashInactiveSeconds == 23)
        ARC:EndTrashCombat()

        ARC:SessionEncounterStart(715, "Sha of Pride", 5, 10)
        now = now + 25
        ARC:SessionCombatLog(now, "UNIT_DIED", false, nil, nil, 0, 0, "A", "Alice")
        ARC:SessionEncounterEnd(715, "Sha of Pride", 5, 10, 1)
        assert(session.pulls[1].success and session.pulls[1].firstDeath.name == "Alice" and member.deaths == 1)

        ARC:RefreshRoster()
        ARC.roster["Alice-Realm"].ready = "notready"
        ARC:SessionReadyCheckFinished()
        assert(#session.readyChecks == 1 and session.readyChecks[1].notReady == 1)
        assert(ARC:EndRaidSession() and #ARC_DB.sessions == 1)
        local report = ARC:GetSessionReportText()
        assert(report:find("Siege of Orgrimmar", 1, true) and report:find("Sha of Pride - KILL", 1, true))
        assert(report:find("AFK flag 7s", 1, true) and report:find("trash inactive ~23s", 1, true))
        assert(report:find("time after 10s", 1, true))
        ARC:ShowSessionReport()
        assert(ARC.sessionFrame:IsShown() and ARC.sessionFrame.text:GetText():find("ARC RAID SESSION REPORT", 1, true))
        ARC.sessionFrame:Hide()
        ARC.sessionFrame.text.GetStringHeight = false
        ARC_DB.sessions = {}
        ARC:ShowSessionReport()
        assert(ARC.sessionFrame.text:GetText() == "No raid session recorded yet.")
        assert(ARC.sessionFrame.text.height == 450)
        ARC.sessionFrame:Hide()
    end)
    units.party1, alice.afk = nil, nil
    ARC_DB.sessions = {}
end)
print("Passed " .. passed .. " ARC regression tests")
