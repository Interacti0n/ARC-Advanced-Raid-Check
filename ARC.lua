--[[===========================================================================
ARC - Advanced Ready Check
World of Warcraft: Mists of Pandaria (client 5.4.8, Interface 50408)

WHAT THIS ADDON DOES
  - Opens a panel automatically when a Ready Check is initiated.
  - Also opens/closes on demand via /arc.
  - Lists every player in your party/raid (5-25) with:
      Ready status, Role, Specialization, Name, Flask, Food, four raid-buff
      categories (Stamina / Stats / Crit / Mastery), item level, durability.
  - Refreshes about once a second while visible, so buffs/consumables you
    can already see on other players (flask, food, raid buffs) update
    "live" - no need to reopen the window.

v1.1.0 CHANGES
  - Header/row columns now share ONE layout table, so labels and content
    always line up (this also fixes the "rows overlapping" look - it was
    really a header/row misalignment plus a too-tight ROW_HEIGHT).
  - Full-length column labels: "Flask", "Food", "Stam", "Stat", "Crit", "Mast".
  - Mouseover tooltip now shows the EXACT flask/food buff text (e.g. the
    real "+300 Intellect and 300 Stamina" line), scanned live off a hidden
    tooltip only when you hover a row (no extra per-second overhead).
  - Window title shows a live ready-check countdown, e.g.
    "ARC - Ready Check Overview (13 seconds remaining)", and switches to
    "(Finished)" once the check ends.
  - The initiator of a ready check is forced to show the "ready" check icon
    immediately; everyone else shows "?" (waiting) until they respond, and
    anyone still unanswered when the check ends is locked to the "X"
    (not ready) icon so results stay visible.
  - The window no longer auto-closes a few seconds after the ready check
    ends. Instead it hides the moment you enter combat (PLAYER_REGEN_DISABLED,
    i.e. the pull), controlled by the same /arc autohide toggle (default ON).
  - Optional ElvUI skinning: if ElvUI is loaded, ARC reskins its frame,
    close button, and "Announce Missing" button using ElvUI's own Skins
    module, so it matches your ElvUI look automatically.

HOW IT GETS ITS DATA (please read - this explains the limits of the WoW API)
  - Ready status, role, and every buff (flask/food/raid buffs) are read
    directly off each unit with UnitBuff()/GetReadyCheckStatus()/
    UnitGroupRolesAssigned(). This works for EVERY group member, whether or
    not they run ARC, because aura/role/ready data is always visible to
    group members.
  - Item level and durability of OTHER players are NOT exposed by the WoW
    API at all (Blizzard removed remote-durability access years ago, and
    there is no reliable "inspect item level" call in this client that
    accounts for reforging/upgrades). The only accurate way to get this
    data is for the other player's own client to tell you. So:
      * If the other player also has ARC installed, their client reports
        its own (100% accurate) item level and durability over the hidden
        addon-message channel, and you'll see real numbers.
      * If they do NOT have ARC, ARC tries a live /inspect as a fallback
        to estimate item level (shown with a leading "~"); durability for
        non-ARC players simply cannot be retrieved and shows as "-".
  - Specialization for yourself is instant. For others, ARC uses the same
    /inspect fallback (or the addon-message report if they run ARC too).

  This is exactly how "real" raid-check tools of this era work, and it's
  why installing ARC on more raid members makes everyone's numbers better.

SLASH COMMANDS
  /arc            - toggle the window
  /arc lock       - lock the window in place (no dragging)
  /arc unlock     - unlock the window
  /arc reset      - reset window position
  /arc autohide   - toggle auto-hide when you enter combat (the pull)
  /arc help       - list commands

FILES
  ARC.toc
  ARC.lua   (this file)

OPTIONAL: if you also run ElvUI, add this line to ARC.toc so ElvUI is
guaranteed to load before ARC (not strictly required - ARC will re-skin
itself the moment it detects ElvUI either way, but this avoids a one-frame
flash of the default Blizzard skin):
  ## OptionalDeps: ElvUI
===========================================================================]]

local ADDON_NAME = ...
-- ARC is a plain Lua table used as our namespace (holds roster data and all
-- of our methods like ARC:Show()/ARC:Hide()). It is deliberately NOT a
-- Frame object, so our own Show/Hide/IsVisible methods can't collide with
-- (and get silently shadowed by) the real Frame widget API. Event handling
-- happens on a separate, invisible frame further below.
local ARC = {}
_G.ARC = ARC

ARC.VERSION       = "1.1.0"
ARC.COMM_PREFIX   = "ARC1"                 -- <= 16 chars, addon message prefix
ARC.REFRESH_EVERY = 1.0                    -- seconds between live refreshes
ARC.BROADCAST_MIN_GAP = 2.0                -- don't self-broadcast more often than this
ARC.INSPECT_RETRY_GAP = 12.0               -- seconds before retrying a failed inspect

--=============================================================================
-- SAVED VARIABLES / DEFAULTS
--=============================================================================

local function ARC_InitDB()
    ARC_DB = ARC_DB or {}
    local d = ARC_DB
    if d.point == nil then d.point = { "CENTER", "UIParent", "CENTER", 0, 150 } end
    if d.locked == nil then d.locked = false end
    if d.autoHide == nil then d.autoHide = true end -- hide automatically on pull (PLAYER_REGEN_DISABLED)
    if d.scale == nil then d.scale = 1.0 end
end

--=============================================================================
-- STATIC DATA: buffs we look for on every unit
-- NOTE: matching is done by the English (enUS/enGB) aura name shown in the
-- tooltip. If you play on a non-English client, translate the strings in
-- these tables to match what UnitBuff() returns on your client.
--=============================================================================

-- Any "Flask of ..." buff. Matching the name prefix means we don't have to
-- keep a huge, ever-changing list of flask spell IDs.
local FLASK_NAME_PATTERN = "^Flask"

-- MoP food buffs all apply a generically named "Well Fed" effect.
local FOOD_BUFF_NAME = "Well Fed"

-- MoP consolidated raid buff categories (5.x). One source of each is enough;
-- we simply flag "present / not present" per category.
local STAMINA_BUFFS = {
    ["Power Word: Fortitude"] = true,
    ["Blood Pact"]            = true,
    ["Commanding Shout"]      = true,
    ["Qiraji Fortitude"]      = true,
    ["Embrace of the Shale Spider"] = true,
}
local STATS_BUFFS = {
    ["Mark of the Wild"]      = true,
    ["Gift of the Wild"]      = true,
    ["Legacy of the Emperor"] = true,
    ["Blessing of Kings"]     = true,
}
local CRIT_BUFFS = {
    ["Leader of the Pack"]        = true,
    ["Legacy of the White Tiger"] = true,
    ["Terrifying Roar"]           = true,
    ["Bellowing Roar"]            = true,
    ["Fearless Roar"]             = true,
    ["Furious Howl"]              = true,
    ["Still Water"]               = true,
}
local MASTERY_BUFFS = {
    ["Blessing of Might"]     = true,
    ["Grace of Air Totem"]    = true,
    ["Grace of Air"]          = true,
    ["Roar of Courage"]       = true,
    ["Spirit Beast Blessing"] = true,
}

-- Fallback generic icons when nothing is found so the column isn't blank.
local ICON_MISSING = "Interface\\RaidFrame\\ReadyCheck-NotReady"
local ICON_BLANK   = "Interface\\Buttons\\UI-Quickslot2" -- faint empty slot look

--=============================================================================
-- STATE
--=============================================================================

-- ARC.roster[fullName] = {
--   name, class, unit, role, ready,
--   specID, specName, specIcon, specSource ("self"|"comm"|"inspect"),
--   ilvl, ilvlApprox, durPct, hasARC, lastComm, lastInspectAttempt,
--   flask, flaskIcon, food, foodIcon, sta, stat, crit, mast,
-- }
ARC.roster = {}
ARC.order  = {}              -- ordered list of fullNames for display
ARC.inspectQueue = {}
ARC.lastSelfBroadcast = 0
ARC.selfDirty = true
ARC.readyCheckActive   = false   -- true only while a check is actively counting down
ARC.readyCheckFinished = false   -- true after a check has ended (until the next one starts)
ARC.readyCheckInitiator = nil    -- name of whoever started the current/last check
ARC.elvuiActive = false

--=============================================================================
-- SMALL HELPERS
--=============================================================================

-- NOTE: 5.4.8 predates connected/cross-realm raid grouping, so a raid member's
-- plain UnitName() is always unique within your own group - no realm suffix
-- bookkeeping needed here.

local function ClassColor(class)
    local c = (class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]) or nil
    if c then return c.r, c.g, c.b end
    return 1, 1, 1
end

local function Round(n)
    if not n then return nil end
    return math.floor(n + 0.5)
end

local function DurabilityColor(pct)
    if not pct then return 0.6, 0.6, 0.6 end
    if pct >= 80 then return 0.1, 0.9, 0.1
    elseif pct >= 50 then return 1, 0.85, 0.1
    else return 1, 0.15, 0.15 end
end

-- Seconds left in the current ready check, or nil if unknown (API missing
-- on this server core) / no check active.
local function GetReadyCheckSecondsLeft()
    if not GetReadyCheckTimeLeft then return nil end
    local t = GetReadyCheckTimeLeft()
    if not t then return nil end
    return math.max(0, math.ceil(t))
end

--=============================================================================
-- SELF DATA COLLECTION (always fully accurate - no inspection needed)
--=============================================================================

-- Durability across all equippable slots that report a value.
local function GetSelfDurability()
    local sumCur, sumMax = 0, 0
    local worst = 100
    local any = false
    for slot = 1, 19 do
        local cur, max = GetInventoryItemDurability(slot)
        if cur and max and max > 0 then
            any = true
            sumCur = sumCur + cur
            sumMax = sumMax + max
            local pct = (cur / max) * 100
            if pct < worst then worst = pct end
        end
    end
    if not any then return nil, nil end
    local avg = (sumCur / sumMax) * 100
    return Round(avg), Round(worst)
end

local function GetSelfSpec()
    local specIndex = GetSpecialization and GetSpecialization()
    if not specIndex or specIndex < 1 then return nil, nil, nil end
    local id, name, _, icon, _, role = GetSpecializationInfo(specIndex)
    return id, name, icon, role
end

local function ScanUnitBuffs(unit)
    local out = {
        flask = false, flaskIcon = nil,
        food  = false, foodIcon  = nil,
        sta = false, stat = false, crit = false, mast = false,
    }
    for i = 1, 40 do
        local name, _, icon = UnitBuff(unit, i)
        if not name then break end
        if (not out.flask) and name:find(FLASK_NAME_PATTERN) then
            out.flask, out.flaskIcon = true, icon
        elseif (not out.food) and name == FOOD_BUFF_NAME then
            out.food, out.foodIcon = true, icon
        elseif (not out.sta) and STAMINA_BUFFS[name] then
            out.sta = true
        elseif (not out.stat) and STATS_BUFFS[name] then
            out.stat = true
        elseif (not out.crit) and CRIT_BUFFS[name] then
            out.crit = true
        elseif (not out.mast) and MASTERY_BUFFS[name] then
            out.mast = true
        end
    end
    return out
end

--=============================================================================
-- ROSTER BUILDING
--=============================================================================

local function GetGroupUnits()
    local units = {}
    if IsInRaid() then
        local n = GetNumGroupMembers()
        for i = 1, n do units[#units + 1] = "raid" .. i end
    elseif IsInGroup() then
        units[#units + 1] = "player"
        local n = GetNumGroupMembers()
        for i = 1, (n - 1) do units[#units + 1] = "party" .. i end
    else
        units[#units + 1] = "player"
    end
    return units
end

local function GetOrCreateEntry(name)
    local e = ARC.roster[name]
    if not e then
        e = {}
        ARC.roster[name] = e
    end
    return e
end

-- Pull everything that's freely readable for one unit (works for anyone,
-- ARC or not) and merge it into the roster entry.
local function RefreshUnitPublicData(unit)
    if not UnitExists(unit) then return end
    local name = UnitName(unit)
    if not name then return end
    local e = GetOrCreateEntry(name)

    e.name  = name
    e.unit  = unit
    e.class = select(2, UnitClass(unit))
    e.role  = UnitGroupRolesAssigned(unit) -- "TANK" | "HEALER" | "DAMAGER" | "NONE"

    -- Ready-check status is only ever (re)read from the API while a check is
    -- actively running. Once READY_CHECK_FINISHED fires we freeze whatever
    -- each entry's `ready` field holds (see that event handler below) so the
    -- icons stay put instead of reverting to blank when Blizzard clears its
    -- own internal ready-check state.
    if ARC.readyCheckActive then
        e.ready = GetReadyCheckStatus(unit)
        -- Safety net: the initiator should show as "ready" immediately, even
        -- if there's a one-tick race before the API reflects it.
        if ARC.readyCheckInitiator and name == ARC.readyCheckInitiator and e.ready == nil then
            e.ready = "ready"
        end
    end

    local buffs = ScanUnitBuffs(unit)
    e.flask, e.flaskIcon = buffs.flask, buffs.flaskIcon
    e.food,  e.foodIcon  = buffs.food,  buffs.foodIcon
    e.sta, e.stat, e.crit, e.mast = buffs.sta, buffs.stat, buffs.crit, buffs.mast

    if UnitIsUnit(unit, "player") then
        local id, sname, icon, role = GetSelfSpec()
        e.specID, e.specName, e.specIcon, e.specSource = id, sname, icon, "self"
        local avgAll, avgEquipped = GetAverageItemLevel()
        e.ilvl, e.ilvlApprox = Round(avgEquipped or avgAll), false
        e.durPct = select(1, GetSelfDurability())
        e.hasARC = true
        e.lastComm = GetTime()
    end
end

local function RebuildOrder()
    local order = {}
    for name in pairs(ARC.roster) do order[#order + 1] = name end

    local rolePriority = { TANK = 1, HEALER = 2, DAMAGER = 3, NONE = 4 }
    table.sort(order, function(a, b)
        local ea, eb = ARC.roster[a], ARC.roster[b]
        local ra = rolePriority[ea.role] or 5
        local rb = rolePriority[eb.role] or 5
        if ra ~= rb then return ra < rb end
        return a < b
    end)
    ARC.order = order
end

-- Drop anyone no longer in the group.
local function PruneRoster()
    local present = {}
    for _, unit in ipairs(GetGroupUnits()) do
        local n = UnitExists(unit) and UnitName(unit)
        if n then present[n] = true end
    end
    for name in pairs(ARC.roster) do
        if not present[name] then ARC.roster[name] = nil end
    end
end

function ARC:RefreshRoster()
    PruneRoster()
    for _, unit in ipairs(GetGroupUnits()) do
        RefreshUnitPublicData(unit)
    end
    RebuildOrder()
end

--=============================================================================
-- ADDON COMMS  (report OUR OWN accurate ilvl/durability/spec to the raid)
--=============================================================================

local function BuildSelfPayload()
    local id, sname, icon = GetSelfSpec()
    local avgAll, avgEquipped = GetAverageItemLevel()
    local durAvg = select(1, GetSelfDurability())
    -- fields separated by ^ ; keep it short, addon messages cap at 255 chars
    local parts = {
        ARC.VERSION,
        UnitName("player") or "?",
        tostring(id or 0),
        tostring(Round(avgEquipped or avgAll) or 0),
        tostring(durAvg or -1),
    }
    return table.concat(parts, "^")
end

function ARC:BroadcastSelf(force)
    if not (IsInGroup() or IsInRaid()) then return end
    local now = GetTime()
    if (not force) and (now - ARC.lastSelfBroadcast < ARC.BROADCAST_MIN_GAP) then
        ARC.selfDirty = true
        return
    end
    local chatType = IsInRaid() and "RAID" or "PARTY"
    local msg = BuildSelfPayload()
    if C_ChatInfo and C_ChatInfo.SendAddonMessage then
        C_ChatInfo.SendAddonMessage(ARC.COMM_PREFIX, msg, chatType)
    elseif SendAddonMessage then
        SendAddonMessage(ARC.COMM_PREFIX, msg, chatType)
    end
    ARC.lastSelfBroadcast = now
    ARC.selfDirty = false
end

local function HandleCommMessage(sender, msg)
    local ver, name, specID, ilvl, dur = strsplit("^", msg)
    if not name then return end
    local e = GetOrCreateEntry(name)
    e.hasARC   = true
    e.lastComm = GetTime()
    specID = tonumber(specID)
    if specID and specID > 0 and GetSpecializationInfoByID then
        local id, sname, _, icon, _, role = GetSpecializationInfoByID(specID)
        if id then
            e.specID, e.specName, e.specIcon, e.specSource = id, sname, icon, "comm"
        end
    end
    ilvl = tonumber(ilvl)
    if ilvl and ilvl > 0 then
        e.ilvl, e.ilvlApprox = ilvl, false
    end
    dur = tonumber(dur)
    if dur and dur >= 0 then
        e.durPct = dur
    end
end

--=============================================================================
-- INSPECT FALLBACK (for players who don't run ARC)
-- Only fills in spec + an ESTIMATED item level. Durability of others is not
-- retrievable through any public API and is intentionally left blank.
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
            local name = UnitName(unit)
            local e = name and ARC.roster[name]
            if e and not e.hasARC then
                local lastTry = e.lastInspectAttempt or 0
                if (now - lastTry) > ARC.INSPECT_RETRY_GAP and UnitInspectable(unit) then
                    ARC.inspectQueue[#ARC.inspectQueue + 1] = unit
                end
            end
        end
    end
end

local function EstimateItemLevelFromLinks(unit)
    local total, count = 0, 0
    for slot = 1, 18 do
        if slot ~= 4 then -- skip shirt (slot 4), it has no item level
            local link = GetInventoryItemLink(unit, slot)
            if link then
                local ilvl = select(4, GetItemInfo(link))
                if ilvl and ilvl > 0 then
                    total = total + ilvl
                    count = count + 1
                end
            end
        end
    end
    if count == 0 then return nil end
    return Round(total / count)
end

local function TryNextInspect()
    if ARC.inspectUnit then
        -- currently waiting on one; give it up to 2s then move on
        if GetTime() - ARC.inspectStartedAt > 2.0 then
            ARC.inspectUnit = nil
        else
            return
        end
    end
    local unit = table.remove(ARC.inspectQueue, 1)
    if not unit or not UnitExists(unit) then return end
    local name = UnitName(unit)
    local e = name and GetOrCreateEntry(name)
    if e then e.lastInspectAttempt = GetTime() end
    ARC.inspectUnit = unit
    ARC.inspectStartedAt = GetTime()
    NotifyInspect(unit)
end

local function OnInspectReady(guid)
    local unit = ARC.inspectUnit
    if not unit or not UnitExists(unit) then ARC.inspectUnit = nil; return end
    if UnitGUID(unit) ~= guid then return end
    local name = UnitName(unit)
    local e = name and GetOrCreateEntry(name)
    if e and not e.hasARC then
        if GetInspectSpecialization then
            local specID = GetInspectSpecialization(unit)
            if specID and specID > 0 and GetSpecializationInfoByID then
                local id, sname, _, icon, _, role = GetSpecializationInfoByID(specID)
                if id then
                    e.specID, e.specName, e.specIcon, e.specSource = id, sname, icon, "inspect"
                end
            end
        end
        local est = EstimateItemLevelFromLinks(unit)
        if est then
            e.ilvl, e.ilvlApprox = est, true
        end
    end
    ARC.inspectUnit = nil
    if ClearInspectPlayer then ClearInspectPlayer() end
end

--=============================================================================
-- UI CONSTRUCTION
--=============================================================================

local ROW_HEIGHT    = 26   -- was 22 - main fix for rows crowding/overlapping
local HEADER_HEIGHT = 26
local FOOTER_HEIGHT = 34
local TOP_OFFSET    = 80   -- distance from frame top down to the row list
local FRAME_WIDTH   = 600  -- widened to fit full-length column labels

-- Single source of truth for column layout. Both the header labels and the
-- row widgets are built from this table, so they can no longer drift out of
-- alignment with each other (that mismatch was the previous version's real
-- "overlapping rows" bug).
local COLS = {
    { key = "ready", label = "",      x = 4,   w = 16,  kind = "icon", iconSize = 14 },
    { key = "role",  label = "",      x = 22,  w = 18,  kind = "icon", iconSize = 16 },
    { key = "spec",  label = "",      x = 42,  w = 18,  kind = "icon", iconSize = 16 },
    { key = "name",  label = "Name",  x = 62,  w = 126, kind = "text", justify = "LEFT" },
    { key = "flask", label = "Flask", x = 190, w = 46,  kind = "icon", iconSize = 20 },
    { key = "food",  label = "Food",  x = 238, w = 46,  kind = "icon", iconSize = 20 },
    { key = "sta",   label = "Stam",  x = 286, w = 42,  kind = "icon", iconSize = 18 },
    { key = "stat",  label = "Stat",  x = 330, w = 42,  kind = "icon", iconSize = 18 },
    { key = "crit",  label = "Crit",  x = 374, w = 42,  kind = "icon", iconSize = 18 },
    { key = "mast",  label = "Mast",  x = 418, w = 42,  kind = "icon", iconSize = 18 },
    { key = "ilvl",  label = "iLvl",  x = 462, w = 52,  kind = "text", justify = "CENTER" },
    { key = "dur",   label = "Dur",   x = 516, w = 52,  kind = "text", justify = "CENTER" },
}

local function CreateHeader(parent)
    local header = CreateFrame("Frame", nil, parent)
    header:SetPoint("TOPLEFT", 8, -6)
    header:SetSize(FRAME_WIDTH - 16, HEADER_HEIGHT)

    for _, col in ipairs(COLS) do
        if col.label ~= "" then
            local fs = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            fs:SetPoint("TOPLEFT", col.x, 0)
            fs:SetWidth(col.w)
            fs:SetJustifyH("CENTER")
            fs:SetText(col.label)
        end
    end

    local line = header:CreateTexture(nil, "ARTWORK")
    line:SetTexture(1, 1, 1, 1)
    line:SetVertexColor(1, 1, 1, 0.15)
    line:SetPoint("BOTTOMLEFT", 0, -2)
    line:SetPoint("BOTTOMRIGHT", 0, -2)
    line:SetHeight(1)

    return header
end

local function SetRoleIcon(tex, role)
    if role == "TANK" or role == "HEALER" or role == "DAMAGER" then
        tex:SetTexture("Interface\\LFGFrame\\UI-LFG-ICON-ROLES")
        local ok = pcall(function()
            tex:SetTexCoord(GetTexCoordsForRoleSmallCircle(role))
        end)
        if not ok then
            tex:SetTexture(nil)
        end
        tex:Show()
    else
        tex:SetTexture(nil)
        tex:Hide()
    end
end

local function SetReadyIcon(tex, status)
    if status == "ready" then
        tex:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
        tex:SetTexCoord(0, 1, 0, 1)
        tex:Show()
    elseif status == "notready" then
        tex:SetTexture("Interface\\RaidFrame\\ReadyCheck-NotReady")
        tex:SetTexCoord(0, 1, 0, 1)
        tex:Show()
    elseif status == "waiting" then
        tex:SetTexture("Interface\\RaidFrame\\ReadyCheck-Waiting")
        tex:SetTexCoord(0, 1, 0, 1)
        tex:Show()
    else
        tex:SetTexture(nil)
        tex:Hide()
    end
end

local function SetPresenceIcon(tex, present, icon)
    if present and icon then
        tex:SetTexture(icon)
        tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        tex:SetDesaturated(false)
        tex:SetAlpha(1)
    else
        tex:SetTexture(ICON_MISSING)
        tex:SetTexCoord(0, 1, 0, 1)
        tex:SetAlpha(0.9)
    end
end

--=============================================================================
-- TOOLTIP BUFF-TEXT SCANNING
-- Reads the EXACT tooltip text (e.g. "+300 Intellect and 300 Stamina") for a
-- unit's flask/food buff. Only ever called while a tooltip is being shown
-- (i.e. on hover), never during the once-a-second refresh, so it costs
-- nothing the rest of the time.
--=============================================================================

local ARCScanTip = CreateFrame("GameTooltip", "ARCScanTooltip", nil, "GameTooltipTemplate")

local function GetBuffTooltipDetail(unit, matchName)
    if not unit or not matchName or not UnitExists(unit) then return nil end
    for i = 1, 40 do
        local name = UnitBuff(unit, i)
        if not name then break end
        if name == matchName then
            ARCScanTip:SetOwner(UIParent, "ANCHOR_NONE")
            ARCScanTip:ClearLines()
            ARCScanTip:SetUnitBuff(unit, i)
            local detail = nil
            for line = 2, ARCScanTip:NumLines() do
                local fs = _G["ARCScanTooltipTextLeft" .. line]
                local text = fs and fs:GetText()
                if text and text ~= "" then
                    detail = detail and (detail .. " " .. text) or text
                end
            end
            ARCScanTip:Hide()
            return detail
        end
    end
    return nil
end

-- Finds the exact "Flask of ..." name currently on a unit (there's only one
-- flask category so the first match is it).
local function FindFlaskName(unit)
    if not unit or not UnitExists(unit) then return nil end
    for i = 1, 40 do
        local name = UnitBuff(unit, i)
        if not name then break end
        if name:find(FLASK_NAME_PATTERN) then return name end
    end
    return nil
end

local function CreateRow(parent, index)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(FRAME_WIDTH - 16, ROW_HEIGHT)

    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()
    row.bg:SetTexture(1, 1, 1, 1)
    if index % 2 == 0 then
        row.bg:SetVertexColor(1, 1, 1, 0.03)
    else
        row.bg:SetVertexColor(1, 1, 1, 0)
    end

    for _, col in ipairs(COLS) do
        if col.kind == "icon" then
            local size = col.iconSize or 16
            local tex = row:CreateTexture(nil, "ARTWORK")
            tex:SetSize(size, size)
            tex:SetPoint("LEFT", col.x + (col.w - size) / 2, 0)
            row[col.key] = tex
        else
            local fs = row:CreateFontString(nil, "ARTWORK",
                col.key == "name" and "GameFontNormalSmall" or "GameFontHighlightSmall")
            fs:SetPoint("LEFT", col.x, 0)
            fs:SetWidth(col.w)
            fs:SetJustifyH(col.justify or "CENTER")
            row[col.key] = fs
        end
    end

    row:EnableMouse(true)
    row:SetScript("OnEnter", function(self)
        if not self.fullName then return end
        local e = ARC.roster[self.fullName]
        if not e then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(e.name, 1, 1, 1)
        if e.specName then GameTooltip:AddLine(e.specName, 0.8, 0.8, 1) end
        if e.specSource == "inspect" then
            GameTooltip:AddLine("(spec via inspect - may be stale)", 0.6, 0.6, 0.6)
        elseif e.specSource == "comm" then
            GameTooltip:AddLine("(reported by their ARC)", 0.6, 0.6, 0.6)
        end

        if e.flask then
            local flaskName = FindFlaskName(e.unit)
            if flaskName then
                local detail = GetBuffTooltipDetail(e.unit, flaskName)
                GameTooltip:AddLine(flaskName .. (detail and (" - " .. detail) or ""), 0.6, 0.9, 1)
            end
        end
        if e.food then
            local detail = GetBuffTooltipDetail(e.unit, FOOD_BUFF_NAME)
            GameTooltip:AddLine("Food: " .. (detail or "Well Fed"), 1, 0.82, 0)
        end

        if e.ilvlApprox then
            GameTooltip:AddLine("Item level is an estimate (no ARC on their end)", 0.6, 0.6, 0.6)
        end
        if not e.hasARC then
            GameTooltip:AddLine("Durability unavailable - player is not running ARC", 0.6, 0.6, 0.6)
        end
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)

    return row
end

-- Plain (non-ElvUI) window skin: a solid backdrop at ~70% opacity so the
-- roster is easy to read against any background. This is applied as the
-- baseline every time the frame is built, so the window ALWAYS has a
-- visible background even if ElvUI skinning below fails partway through.
local BACKDROP_INFO = {
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 11, right = 11, top = 11, bottom = 11 },
}

local function ApplyDefaultSkin(f)
    if not f.SetBackdrop then return end
    f:SetBackdrop(BACKDROP_INFO)
    f:SetBackdropColor(0, 0, 0, 0.7)       -- ~70% opaque black background
    f:SetBackdropBorderColor(1, 1, 1, 1)   -- fully opaque border
end

-- Attempts to skin the ARC window with ElvUI's own Skins module so it
-- matches the rest of the ElvUI-skinned UI. Completely optional and safe if
-- ElvUI isn't installed, or if its Skins API differs on a given fork/version
-- (wrapped in pcall so a mismatch never breaks ARC itself). Crucially, this
-- never strips the default backdrop before ElvUI's own skin is confirmed to
-- have applied successfully - if the pcall fails for any reason, the window
-- falls back to the default ~70%-opacity skin instead of being left blank.
local function ARC_TrySkinElvUI()
    local f = ARC.frame
    if not f or f.elvuiSkinned then return end
    if not (IsAddOnLoaded and IsAddOnLoaded("ElvUI")) then return end
    if not ElvUI then return end

    local ok = pcall(function()
        local E = unpack(ElvUI)
        local S = E:GetModule("Skins")

        S:HandleFrame(f, true) -- ElvUI manages its own backdrop internally

        if f.closeButton then
            S:HandleCloseButton(f.closeButton)
        end
        if f.announce then
            S:HandleButton(f.announce)
        end

        ARC.elvuiActive = true
    end)

    if ok then
        f.elvuiSkinned = true
    else
        -- ElvUI skinning failed (different Skins API on this server's fork,
        -- etc.) - make sure the window still has a visible background.
        ApplyDefaultSkin(f)
    end
end

local function BuildMainFrame()
    -- NOTE: no "BackdropTemplate" here on purpose - that mixin didn't exist
    -- until patch 8.0. On 5.4.8, SetBackdrop is a native Frame method, so a
    -- plain frame is all we need (and passing that template name here would
    -- throw a "Unknown template" error on this client).
    local f = CreateFrame("Frame", "ARCFrame", UIParent)
    f:SetSize(FRAME_WIDTH, 200)
    f:SetFrameStrata("HIGH")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self)
        if not ARC_DB.locked then self:StartMoving() end
    end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relPoint, x, y = self:GetPoint()
        ARC_DB.point = { point, "UIParent", relPoint, x, y }
    end)

    -- Always apply the default ~70%-opacity skin as a baseline. If ElvUI is
    -- loaded, ARC_TrySkinElvUI() (called right after this frame is created)
    -- will visually replace it - but the window is never left without a
    -- background, even for one frame or if ElvUI skinning fails.
    ApplyDefaultSkin(f)

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", 0, -12)
    title:SetText("ARC - Ready Check Overview")
    f.title = title

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)
    close:SetScript("OnClick", function() ARC:Hide() end)
    f.closeButton = close

    local summary = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    summary:SetPoint("TOPLEFT", 12, -30)
    summary:SetPoint("TOPRIGHT", -12, -30)
    summary:SetJustifyH("LEFT")
    f.summary = summary

    local scroll = CreateFrame("Frame", nil, f)
    scroll:SetPoint("TOPLEFT", 8, -TOP_OFFSET)
    scroll:SetPoint("TOPRIGHT", -8, -TOP_OFFSET)
    f.rowsContainer = scroll

    f.header = CreateHeader(f)
    f.header:SetPoint("TOPLEFT", 8, -50)

    f.announce = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.announce:SetSize(150, 20)
    f.announce:SetPoint("BOTTOMLEFT", 10, 8)
    f.announce:SetText("Announce Missing")
    f.announce:SetScript("OnClick", function() ARC:AnnounceMissing() end)

    local hint = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("BOTTOMRIGHT", -10, 10)
    hint:SetText("/arc for help")
    f.hint = hint

    f.rows = {}
    f:Hide()
    return f
end

--=============================================================================
-- RENDERING
--=============================================================================

function ARC:EnsureRow(i)
    local f = self.frame
    local row = f.rows[i]
    if not row then
        row = CreateRow(f.rowsContainer, i)
        row:SetPoint("TOPLEFT", f.rowsContainer, "TOPLEFT", 0, -(i - 1) * ROW_HEIGHT)
        row:SetPoint("TOPRIGHT", f.rowsContainer, "TOPRIGHT", 0, -(i - 1) * ROW_HEIGHT)
        f.rows[i] = row
    end
    return row
end

local function FormatIlvl(e)
    if not e.ilvl or e.ilvl == 0 then return "-" end
    if e.ilvlApprox then return "~" .. e.ilvl end
    return tostring(e.ilvl)
end

local function FormatDur(e)
    if not e.hasARC or not e.durPct then return "-" end
    return e.durPct .. "%"
end

-- Builds the "(N seconds remaining)" / "(Finished)" suffix on the title bar.
local function UpdateTitleText()
    local f = ARC.frame
    if not f or not f.title then return end
    local text = "ARC - Ready Check Overview"
    if ARC.readyCheckActive then
        local left = GetReadyCheckSecondsLeft()
        if left == nil then
            text = text .. " (in progress)"
        elseif left > 0 then
            text = text .. string.format(" (%d second%s remaining)", left, left == 1 and "" or "s")
        else
            text = text .. " (Finished)"
        end
    elseif ARC.readyCheckFinished then
        text = text .. " (Finished)"
    end
    f.title:SetText(text)
end

function ARC:Render()
    local f = self.frame
    if not f or not f:IsShown() then return end

    UpdateTitleText()

    local total, ready, missingFlask, missingFood = 0, 0, 0, 0

    for i, name in ipairs(self.order) do
        local e = self.roster[name]
        local row = self:EnsureRow(i)
        row.fullName = name
        row:Show()

        total = total + 1
        if e.ready == "ready" then ready = ready + 1 end
        if not e.flask then missingFlask = missingFlask + 1 end
        if not e.food then missingFood = missingFood + 1 end

        SetReadyIcon(row.ready, e.ready)
        SetRoleIcon(row.role, e.role)

        if e.specIcon then
            row.spec:SetTexture(e.specIcon)
            row.spec:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            row.spec:Show()
        else
            row.spec:SetTexture(nil)
            row.spec:Hide()
        end

        local r, g, b = ClassColor(e.class)
        row.name:SetText(e.name or name)
        row.name:SetTextColor(r, g, b)

        SetPresenceIcon(row.flask, e.flask, e.flaskIcon)
        SetPresenceIcon(row.food, e.food, e.foodIcon)
        SetPresenceIcon(row.sta, e.sta, e.sta and "Interface\\Icons\\Spell_Holy_WordFortitude")
        SetPresenceIcon(row.stat, e.stat, e.stat and "Interface\\Icons\\Spell_Magic_GreaterBlessingOfKings")
        SetPresenceIcon(row.crit, e.crit, e.crit and "Interface\\Icons\\Ability_Druid_ChallangingRoar")
        SetPresenceIcon(row.mast, e.mast, e.mast and "Interface\\Icons\\Ability_Paladin_SheathofLight")

        row.ilvl:SetText(FormatIlvl(e))

        local durText = FormatDur(e)
        row.dur:SetText(durText)
        if e.hasARC and e.durPct then
            row.dur:SetTextColor(DurabilityColor(e.durPct))
        else
            row.dur:SetTextColor(0.5, 0.5, 0.5)
        end
    end

    for i = #self.order + 1, #f.rows do
        f.rows[i]:Hide()
    end

    f.summary:SetText(string.format(
        "|cff55ff55Ready: %d/%d|r    |cffff8888Missing Flask: %d|r    |cffff8888Missing Food: %d|r",
        ready, total, missingFlask, missingFood
    ))

    local newHeight = TOP_OFFSET + FOOTER_HEIGHT + math.max(#self.order, 1) * ROW_HEIGHT
    f:SetHeight(newHeight)
    f.rowsContainer:SetHeight(math.max(#self.order, 1) * ROW_HEIGHT)
end

--=============================================================================
-- ANNOUNCE MISSING CONSUMABLES
--=============================================================================

function ARC:AnnounceMissing()
    local missing = {}
    for _, name in ipairs(self.order) do
        local e = self.roster[name]
        local tags = {}
        if not e.flask then tags[#tags + 1] = "flask" end
        if not e.food then tags[#tags + 1] = "food" end
        if #tags > 0 then
            missing[#missing + 1] = string.format("%s (%s)", e.name, table.concat(tags, "/"))
        end
    end

    if #missing == 0 then
        print("|cff33ff99ARC:|r Everyone has flask and food. Nice.")
        return
    end

    local chatType
    if IsInRaid() and (UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")) then
        chatType = "RAID_WARNING"
    elseif IsInRaid() then
        chatType = "RAID"
    elseif IsInGroup() then
        chatType = "PARTY"
    else
        chatType = nil
    end

    local text = "Missing consumables - " .. table.concat(missing, ", ")
    if chatType then
        SendChatMessage(text, chatType)
    else
        print("|cff33ff99ARC:|r " .. text)
    end
end

--=============================================================================
-- SHOW / HIDE / TOGGLE
--=============================================================================

function ARC:Show()
    if not self.frame then
        self.frame = BuildMainFrame()
        ARC_TrySkinElvUI()
    end
    local f = self.frame
    f:ClearAllPoints()
    f:SetPoint(unpack(ARC_DB.point))
    f:SetScale(ARC_DB.scale or 1.0)
    f:Show()
    self:RefreshRoster()
    self:Render()
    self:BroadcastSelf(true)
    QueueInspectCandidates()
end

function ARC:Hide()
    if self.frame then self.frame:Hide() end
end

function ARC:Toggle()
    if self.frame and self.frame:IsShown() then
        self:Hide()
    else
        self:Show()
    end
end

function ARC:IsVisible()
    return self.frame and self.frame:IsShown()
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
        elseif addon == "ElvUI" then
            -- Covers the (uncommon) case where ARC's frame already exists
            -- and ElvUI only finishes loading afterward.
            ARC_TrySkinElvUI()
        end

    elseif event == "PLAYER_ENTERING_WORLD" then
        ARC.selfDirty = true

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
        OnInspectReady(guid)
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
        QueueInspectCandidates()
    end

    TryNextInspect()
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
    elseif msg == "help" then
        print("|cff33ff99ARC commands:|r")
        print("  /arc            - show/hide the window")
        print("  /arc lock       - lock window position")
        print("  /arc unlock     - unlock window position")
        print("  /arc reset      - reset window position")
        print("  /arc autohide   - toggle auto-hide when you enter combat (pull)")
    else
        print("|cff33ff99ARC:|r unknown command. Try /arc help")
    end
end
