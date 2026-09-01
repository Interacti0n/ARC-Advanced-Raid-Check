--[[===========================================================================
ARC - Advanced Ready Check
World of Warcraft: Mists of Pandaria (client 5.4.8, Interface 50400)

WHAT THIS ADDON DOES
  - Opens a panel automatically when a Ready Check is initiated.
  - Also opens/closes on demand via /arc.
  - Lists every player in your party/raid (5-25) with:
      Ready status, Role, Specialization, Name, Flask, Food, four raid-buff
      categories (Stamina / Stats / Crit / Mastery), item level, durability,
      gems, enchants and primary-stat gear suitability.
  - Refreshes about once a second while visible, so buffs/consumables you
    can already see on other players (flask, food, raid buffs) update
    "live" - no need to reopen the window.

HOW IT GETS ITS DATA (please read - this explains the limits of the WoW API)
  - Ready status, role, and every buff (flask/food/raid buffs) are read
    directly off each unit with UnitBuff()/GetReadyCheckStatus()/
    UnitGroupRolesAssigned(). This works for EVERY group member, whether or
    not they run ARC, because aura/role/ready data is always visible to
    group members.
  - Durability of OTHER players is not exposed by the WoW API. Accurate
    durability therefore requires the other player's ARC client to report it.
    Item level and gear details can be estimated through live inspection; ARC
    reads the upgraded level displayed in each inspected item's tooltip. So:
      * If the other player also has ARC installed, their client reports
        its own (100% accurate) item level and durability over the hidden
        addon-message channel, and you'll see real numbers.
      * If they do NOT have ARC, ARC tries a live /inspect as a fallback
        to estimate item level (shown with a leading "~"); durability for
        non-ARC players simply cannot be retrieved and shows as "N/A".
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
  /arc minimap    - toggle the minimap button
  /arc options    - open the Interface Options panel
  /arc help       - list commands

FILES
  ARC.toc             metadata and load order
  ARC_Core.lua        database, roster, buffs and communication
  ARC_Gear.lua        item level, gems, enchants and stat rules
  ARC_Inspect.lua     inspect fallback
  ARC_UI.lua          main window and rendering
  ARC_Options.lua     minimap button and settings
  ARC.lua             events and slash commands
  README.md           installation and usage guide
  changelog.txt       release history

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

ARC.VERSION       = "1.3.2"
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
    if type(d.minItemLevel) ~= "number" then d.minItemLevel = 450 end
    if type(d.minimap) ~= "table" then d.minimap = {} end
    if d.minimap.hide == nil then d.minimap.hide = false end
    if type(d.minimap.angle) ~= "number" then d.minimap.angle = 200 end
end

--=============================================================================
-- STATIC DATA: buffs we look for on every unit. Spell IDs are locale-neutral;
-- the English names remain as a compatibility fallback for private-server
-- cores which omit or rewrite the spellID returned by UnitBuff().
--=============================================================================

-- Any "Flask of ..." buff. Matching the name prefix means we don't have to
-- keep a huge, ever-changing list of flask spell IDs.
local FLASK_NAME_PATTERN = "^Flask"

local FLASK_SPELL_IDS = {
    [105689] = true, -- Flask of Spring Blossoms
    [105691] = true, -- Flask of the Warm Sun
    [105693] = true, -- Flask of Falling Leaves
    [105694] = true, -- Flask of the Earth
    [105696] = true, -- Flask of Winter's Bite
    [127230] = true, -- Crystal of Insanity
}

-- MoP food buffs all apply a generically named "Well Fed" effect.
local FOOD_BUFF_NAME = "Well Fed"
local FOOD_SPELL_IDS = {
    [104264] = true, [104267] = true, [104269] = true,
    [104271] = true, [104273] = true, [104275] = true, [104277] = true,
    [105284] = true, [105285] = true, [105286] = true,
    [125106] = true, [125107] = true, [125108] = true,
    [125109] = true, [125110] = true, [125111] = true,
    [126533] = true, [126534] = true, [126535] = true,
    [126536] = true, [126537] = true, [126538] = true,
}

local function BuildLocalizedSpellNames(ids, fallbackName)
    local names = {}
    if fallbackName then names[fallbackName] = true end
    if GetSpellInfo then
        for spellID in pairs(ids) do
            local localizedName = GetSpellInfo(spellID)
            if localizedName then names[localizedName] = true end
        end
    end
    return names
end

local FLASK_NAMES = BuildLocalizedSpellNames(FLASK_SPELL_IDS)
local FOOD_BUFF_NAMES = BuildLocalizedSpellNames(FOOD_SPELL_IDS, FOOD_BUFF_NAME)

-- MoP consolidated raid buff categories (5.x). One source of each is enough;
-- we simply flag "present / not present" per category.
local STAMINA_BUFFS = {
    ["Power Word: Fortitude"] = true,
    ["Blood Pact"]            = true,
    ["Commanding Shout"]      = true,
    ["Qiraji Fortitude"]      = true,
}
local STAMINA_BUFF_IDS = { [21562] = true, [6307] = true, [469] = true, [90364] = true }
local STATS_BUFFS = {
    ["Mark of the Wild"]      = true,
    ["Gift of the Wild"]      = true,
    ["Legacy of the Emperor"] = true,
    ["Blessing of Kings"]     = true,
    ["Embrace of the Shale Spider"] = true,
}
local STATS_BUFF_IDS = { [1126] = true, [20217] = true, [115921] = true, [90363] = true }
local CRIT_BUFFS = {
    ["Leader of the Pack"]        = true,
    ["Legacy of the White Tiger"] = true,
    ["Terrifying Roar"]           = true,
    ["Bellowing Roar"]            = true,
    ["Fearless Roar"]             = true,
    ["Furious Howl"]              = true,
    ["Still Water"]               = true,
}
local CRIT_BUFF_IDS = {
    [17007] = true, [116781] = true, [90309] = true, [126373] = true,
    [24604] = true, [126309] = true,
}
local MASTERY_BUFFS = {
    ["Blessing of Might"]     = true,
    ["Grace of Air Totem"]    = true,
    ["Grace of Air"]          = true,
    ["Roar of Courage"]       = true,
    ["Spirit Beast Blessing"] = true,
}
local MASTERY_BUFF_IDS = { [19740] = true, [116956] = true, [93435] = true, [128997] = true }

--=============================================================================
-- STATE
--=============================================================================

-- ARC.roster[fullName] = {
--   name, class, unit, role, ready,
--   specID, specName, specIcon, specSource ("self"|"comm"|"inspect"),
--   ilvl, ilvlApprox, durPct, hasARC, lastComm, lastInspectAttempt,
--   flask, flaskName, flaskIcon, food, foodName, foodIcon, sta, stat, crit, mast,
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

-- Canonical identity keeps same-named players from different realms separate.
-- Some 5.4 private-server cores do not implement UnitFullName(), so retain a
-- UnitName()/GetRealmName() fallback.
local function NormalizeFullName(name)
    if not name then return nil end
    return (name:gsub("%s+", ""))
end

local function GetUnitIdentity(unit)
    local name, realm
    if UnitFullName then name, realm = UnitFullName(unit) end
    if not name then name, realm = UnitName(unit) end
    if not name then return nil, nil end
    if not realm or realm == "" then realm = GetRealmName and GetRealmName() or nil end
    local fullName = name
    if realm and realm ~= "" then fullName = name .. "-" .. realm end
    return NormalizeFullName(fullName), name
end

local function SetFrameShown(frame, shown)
    if shown then frame:Show() else frame:Hide() end
end

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
        flask = false, flaskName = nil, flaskIcon = nil,
        food  = false, foodName  = nil, foodIcon  = nil,
        -- For the four raid-buff categories we also keep the exact buff
        -- name that matched (staName/statName/critName/mastName), so the
        -- column-header "source list" tooltip and the per-row tooltip can
        -- show exactly which buff (and therefore which class) is covering
        -- that category, not just a yes/no icon.
        sta = false, staName  = nil, staIcon = nil,
        stat = false, statName = nil, statIcon = nil,
        crit = false, critName = nil, critIcon = nil,
        mast = false, mastName = nil, mastIcon = nil,
        staSource = nil, statSource = nil, critSource = nil, mastSource = nil,
    }
    for i = 1, 40 do
        local name, _, icon, _, _, _, _, caster, _, _, spellID = UnitBuff(unit, i)
        if not name then break end
        local source = caster and GetUnitIdentity(caster) or nil
        if (not out.flask) and (FLASK_SPELL_IDS[spellID] or FLASK_NAMES[name] or name:find(FLASK_NAME_PATTERN)) then
            out.flask, out.flaskName, out.flaskIcon = true, name, icon
        elseif (not out.food) and (FOOD_SPELL_IDS[spellID] or FOOD_BUFF_NAMES[name]) then
            out.food, out.foodName, out.foodIcon = true, name, icon
        elseif (not out.sta) and (STAMINA_BUFF_IDS[spellID] or STAMINA_BUFFS[name]) then
            out.sta, out.staName, out.staIcon, out.staSource = true, name, icon, source
        elseif (not out.stat) and (STATS_BUFF_IDS[spellID] or STATS_BUFFS[name]) then
            out.stat, out.statName, out.statIcon, out.statSource = true, name, icon, source
        elseif (not out.crit) and (CRIT_BUFF_IDS[spellID] or CRIT_BUFFS[name]) then
            out.crit, out.critName, out.critIcon, out.critSource = true, name, icon, source
        elseif (not out.mast) and (MASTERY_BUFF_IDS[spellID] or MASTERY_BUFFS[name]) then
            out.mast, out.mastName, out.mastIcon, out.mastSource = true, name, icon, source
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

local function GetOrCreateEntry(fullName)
    local e = ARC.roster[fullName]
    if not e then
        e = {}
        ARC.roster[fullName] = e
    end
    return e
end

-- Pull everything that's freely readable for one unit (works for anyone,
-- ARC or not) and merge it into the roster entry.
local function RefreshUnitPublicData(unit)
    if not UnitExists(unit) then return end
    local fullName, name = GetUnitIdentity(unit)
    if not fullName then return end
    local e = GetOrCreateEntry(fullName)

    e.name  = name
    e.fullName = fullName
    e.unit  = unit
    e.class = select(2, UnitClass(unit))
    e.role  = UnitGroupRolesAssigned(unit) -- "TANK" | "HEALER" | "DAMAGER" | "NONE"
    local isSelf = UnitIsUnit(unit, "player")
    e.online = (not UnitIsConnected) or UnitIsConnected(unit)
    e.dead = UnitIsDeadOrGhost and UnitIsDeadOrGhost(unit) or false
    local visible = (not UnitIsVisible) or UnitIsVisible(unit)
    e.auraDataAvailable = e.online and visible
    if isSelf then
        e.inspectable = true
    elseif CanInspect then
        local ok, canInspect = pcall(CanInspect, unit)
        e.inspectable = ok and canInspect and true or false
    else
        e.inspectable = visible
    end

    -- Ready-check status is only ever (re)read from the API while a check is
    -- actively running. Once READY_CHECK_FINISHED fires we freeze whatever
    -- each entry's `ready` field holds (see that event handler below) so the
    -- icons stay put instead of reverting to blank when Blizzard clears its
    -- own internal ready-check state.
    if ARC.readyCheckActive then
        e.ready = GetReadyCheckStatus(unit)
        -- Safety net: the initiator should show as "ready" immediately, even
        -- if there's a one-tick race before the API reflects it.
        if ARC.readyCheckInitiator and e.ready == nil then
            local initiator = NormalizeFullName(ARC.readyCheckInitiator)
            if initiator == fullName or initiator == name then e.ready = "ready" end
        end
    end

    if e.auraDataAvailable then
        local buffs = ScanUnitBuffs(unit)
        e.flask, e.flaskName, e.flaskIcon = buffs.flask, buffs.flaskName, buffs.flaskIcon
        e.food,  e.foodName,  e.foodIcon  = buffs.food,  buffs.foodName,  buffs.foodIcon
        e.sta, e.stat, e.crit, e.mast = buffs.sta, buffs.stat, buffs.crit, buffs.mast
        e.staName, e.statName, e.critName, e.mastName =
            buffs.staName, buffs.statName, buffs.critName, buffs.mastName
        e.staIcon, e.statIcon, e.critIcon, e.mastIcon =
            buffs.staIcon, buffs.statIcon, buffs.critIcon, buffs.mastIcon
        e.staSource, e.statSource, e.critSource, e.mastSource =
            buffs.staSource, buffs.statSource, buffs.critSource, buffs.mastSource
        e.lastAuraScan = GetTime()
    end

    if isSelf then
        local id, sname, icon, role = GetSelfSpec()
        e.specID, e.specName, e.specIcon, e.specSource = id, sname, icon, "self"
        local avgAll, avgEquipped = GetAverageItemLevel()
        e.ilvl, e.ilvlApprox = Round(avgEquipped or avgAll), false
        e.durPct, e.durWorst = GetSelfDurability()
        e.hasARC = true
        e.arcVersion = ARC.VERSION
        e.lastComm = GetTime()
        if ARC.AnalyzeUnitGear then
            local upgradedLevel = e.gear and e.gear.averageItemLevel
            if ARC.forceSelfGearScan or not e.lastGearScan or (GetTime() - e.lastGearScan) > 60 then
                upgradedLevel = ARC:AnalyzeUnitGear(unit, e)
                ARC.forceSelfGearScan = false
            end
            if upgradedLevel then e.ilvl = upgradedLevel end
        end
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
        local n = UnitExists(unit) and GetUnitIdentity(unit)
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
    local selfKey = GetUnitIdentity("player")
    local selfEntry = selfKey and ARC.roster[selfKey]
    local upgradedLevel = selfEntry and selfEntry.gear and selfEntry.gear.averageItemLevel
    local durAvg, durWorst = GetSelfDurability()
    -- fields separated by ^ ; keep it short, addon messages cap at 255 chars
    local parts = {
        ARC.VERSION,
        (GetUnitIdentity("player")) or "?",
        tostring(id or 0),
        tostring(upgradedLevel or Round(avgEquipped or avgAll) or 0),
        tostring(durAvg or -1),
        tostring(durWorst or -1),
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

local function FindGroupEntryBySender(sender)
    sender = NormalizeFullName(sender)
    if not sender then return nil end
    for _, unit in ipairs(GetGroupUnits()) do
        if UnitExists(unit) then
            local fullName, shortName = GetUnitIdentity(unit)
            if sender == fullName or (not sender:find("%-") and sender == shortName) then
                RefreshUnitPublicData(unit)
                return fullName and ARC.roster[fullName] or nil
            end
        end
    end
    return nil
end

local function HandleCommMessage(sender, msg)
    local ver, name, specID, ilvl, dur, durWorst = strsplit("^", msg)
    if not ver or not name then return end
    -- Attribute data to the client-authenticated sender, never to the name
    -- supplied inside the payload, and ignore reports from outside the group.
    local e = FindGroupEntryBySender(sender)
    if not e then return end
    e.hasARC   = true
    e.arcVersion = ver
    e.lastComm = GetTime()
    specID = tonumber(specID)
    if specID and specID > 0 and GetSpecializationInfoByID then
        local id, sname, _, icon, _, role = GetSpecializationInfoByID(specID)
        if id then
            e.specID, e.specName, e.specIcon, e.specSource = id, sname, icon, "comm"
        end
    end
    ilvl = tonumber(ilvl)
    if ilvl and ilvl > 0 and ilvl < 10000 then
        e.ilvl, e.ilvlApprox = ilvl, false
    end
    dur = tonumber(dur)
    if dur and dur >= 0 and dur <= 100 then
        e.durPct = dur
    end
    durWorst = tonumber(durWorst)
    if durWorst and durWorst >= 0 and durWorst <= 100 then
        e.durWorst = durWorst
    else
        e.durWorst = nil -- compatibility with ARC versions that report only average durability
    end
end

-- Private cross-file API. Public addon methods remain on ARC; this table only
-- connects the implementation modules without leaking helpers into _G.
ARC.Internal = {
    ARC_InitDB = ARC_InitDB,
    ClassColor = ClassColor,
    Round = Round,
    DurabilityColor = DurabilityColor,
    GetReadyCheckSecondsLeft = GetReadyCheckSecondsLeft,
    GetUnitIdentity = GetUnitIdentity,
    SetFrameShown = SetFrameShown,
    GetGroupUnits = GetGroupUnits,
    GetOrCreateEntry = GetOrCreateEntry,
    RefreshUnitPublicData = RefreshUnitPublicData,
    HandleCommMessage = HandleCommMessage,
}
