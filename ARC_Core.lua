--[[===========================================================================
ARC - Advanced Raid Check
World of Warcraft: Mists of Pandaria (client 5.4.8, Interface 50400)

WHAT THIS ADDON DOES
  - Opens a panel when a Ready Check is initiated (unless manual mode is on).
  - Also opens/closes on demand via /arc.
  - Lists every player in your party/raid (5-25) with:
      Ready status, Role, Specialization, Name, Flask, Food, four raid-buff
      categories (Stamina / Stats / Crit / Mastery), item level, durability,
      gems, enchants and primary-stat gear suitability.
  - Refreshes fast-changing status every second. Aura events update affected
    players immediately and a five-second full pass protects against missing
    private-server events.
  - Can record opt-in raid sessions: attendance, pulls, ready snapshots, AFK
    flags, first deaths and estimated inactivity during trash combat.

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
  /arc manual [on|off] - toggle or set manual-only opening
  /arc minimap    - toggle the minimap button
  /arc options    - open the Interface Options panel
  /arc check      - detailed check of the targeted non-group player
  /arc session [start|end] - open, start or finish a raid session report
  /arc help       - list commands

FILES
  ARC.toc             metadata and load order
  ARC_Core.lua        database, roster, buffs and communication
  ARC_Gear.lua        item level, gems, enchants and stat rules
  ARC_Inspect.lua     inspect fallback
  ARC_Session.lua     raid-session attendance, encounters and activity report
  ARC_UI.lua          main window and rendering
  ARC_PlayerCheck.lua inspect button and standalone player report
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

ARC.VERSION       = "1.6.1"
ARC.NAME          = "Advanced Raid Check"
ARC.COMM_PREFIX   = "ARC1"                 -- <= 16 chars, addon message prefix
ARC.REFRESH_EVERY = 1.0                    -- seconds between live refreshes
ARC.FULL_REFRESH_EVERY = 5.0               -- expensive aura/gear fallback scan
ARC.CONSUMABLE_WARN_SECONDS = 300          -- warn when flask/food has <= 5 min left
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
    if d.manualMode == nil then d.manualMode = false end
    if d.scale == nil then d.scale = 1.0 end
    if type(d.minItemLevel) ~= "number" or d.minItemLevel < 400 or d.minItemLevel > 600 or d.minItemLevel ~= math.floor(d.minItemLevel) then d.minItemLevel = 450 end
    if type(d.minimap) ~= "table" then d.minimap = {} end
    if d.minimap.hide == nil then d.minimap.hide = false end
    if type(d.minimap.angle) ~= "number" then d.minimap.angle = 200 end
    if type(d.raidSetup) ~= "table" then d.raidSetup = {} end
    if type(d.raidSetup.enabled) ~= "boolean" then d.raidSetup.enabled = true end
    if not ({ [0]=true, [3]=true, [4]=true, [5]=true, [6]=true, [7]=true, [14]=true })[d.raidSetup.difficulty] then d.raidSetup.difficulty = 0 end
    if not ({ any=true, freeforall=true, roundrobin=true, master=true, group=true, needbeforegreed=true })[d.raidSetup.loot] then d.raidSetup.loot = "any" end
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
    ["Furious Growl"]             = true, -- private-server name used for the hunter pet crit aura
    ["Still Water"]               = true,
    ["Arcane Brilliance"]         = true,
    ["Dalaran Brilliance"]        = true,
}
local CRIT_BUFF_IDS = {
    [17007] = true, [116781] = true, [90309] = true, [126373] = true,
    [24604] = true, [126309] = true, [1459] = true, [61316] = true,
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
        auras = {}, auraNames = {},
        flask = false, flaskName = nil, flaskIcon = nil, flaskExpiresAt = nil,
        food  = false, foodName  = nil, foodIcon  = nil, foodExpiresAt = nil,
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
        local name, _, icon, _, _, duration, expiresAt, caster, _, _, spellID = UnitBuff(unit, i)
        if not name then break end
        if spellID then out.auras[spellID] = true end
        out.auraNames[name] = true
        local source = caster and GetUnitIdentity(caster) or nil
        if (not out.flask) and (FLASK_SPELL_IDS[spellID] or FLASK_NAMES[name] or name:find(FLASK_NAME_PATTERN)) then
            out.flask, out.flaskName, out.flaskIcon = true, name, icon
            if duration and duration > 0 and expiresAt and expiresAt > 0 then out.flaskExpiresAt = expiresAt end
        elseif (not out.food) and (FOOD_SPELL_IDS[spellID] or FOOD_BUFF_NAMES[name]) then
            out.food, out.foodName, out.foodIcon = true, name, icon
            if duration and duration > 0 and expiresAt and expiresAt > 0 then out.foodExpiresAt = expiresAt end
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
    e.level = UnitLevel(unit)
    e.class = select(2, UnitClass(unit))
    e.role  = UnitGroupRolesAssigned(unit) -- "TANK" | "HEALER" | "DAMAGER" | "NONE"
    local isSelf = UnitIsUnit(unit, "player")
    e.online = (not UnitIsConnected) or UnitIsConnected(unit)
    e.dead = UnitIsDeadOrGhost and UnitIsDeadOrGhost(unit) or false
    e.afk = UnitIsAFK and UnitIsAFK(unit) or false
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
        e.buffs = buffs
        e.flask, e.flaskName, e.flaskIcon, e.flaskExpiresAt =
            buffs.flask, buffs.flaskName, buffs.flaskIcon, buffs.flaskExpiresAt
        e.food, e.foodName, e.foodIcon, e.foodExpiresAt =
            buffs.food, buffs.foodName, buffs.foodIcon, buffs.foodExpiresAt
        e.sta, e.stat, e.crit, e.mast = buffs.sta, buffs.stat, buffs.crit, buffs.mast
        e.staName, e.statName, e.critName, e.mastName =
            buffs.staName, buffs.statName, buffs.critName, buffs.mastName
        e.staIcon, e.statIcon, e.critIcon, e.mastIcon =
            buffs.staIcon, buffs.statIcon, buffs.critIcon, buffs.mastIcon
        e.staSource, e.statSource, e.critSource, e.mastSource =
            buffs.staSource, buffs.statSource, buffs.critSource, buffs.mastSource
        e.lastAuraScan = GetTime()
    else
        e.buffs = nil
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
        if ARC.ScanTalents then ARC:ScanTalents(unit, e, false) end
        if ARC.ReadSelfWeaponBuffs then e.weaponBuffs, e.weaponBuffAt = ARC:ReadSelfWeaponBuffs(), GetTime() end
        if ARC.ReadSelfPreparation then e.preparation = ARC:ReadSelfPreparation(e) end
        if ARC.AnalyzeUnitGear then
            local upgradedLevel = e.gear and e.gear.averageItemLevel
            if ARC.forceSelfGearScan or (e.gear and e.gear.validationPending) or not e.lastGearScan or (GetTime() - e.lastGearScan) > 60 then
                upgradedLevel = ARC:AnalyzeUnitGear(unit, e)
                ARC.forceSelfGearScan = false
            end
            if upgradedLevel then e.ilvl = upgradedLevel end
        end
    end
    if ARC.ScanSelfBuffs then e.selfBuffs = ARC:ScanSelfBuffs(unit, e) end
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

-- Lightweight pass used every second. Expensive aura, talent and gear reads
-- are event-driven and retain a slower full-scan fallback for private servers.
function ARC:RefreshRosterStatus()
    local needsFullRefresh = false
    for _, unit in ipairs(GetGroupUnits()) do
        if UnitExists(unit) then
            local fullName, name = GetUnitIdentity(unit)
            local e = fullName and self.roster[fullName]
            if not e then
                needsFullRefresh = true
            else
                e.unit = unit
                e.role = UnitGroupRolesAssigned(unit)
                e.online = (not UnitIsConnected) or UnitIsConnected(unit)
                e.dead = UnitIsDeadOrGhost and UnitIsDeadOrGhost(unit) or false
                e.afk = UnitIsAFK and UnitIsAFK(unit) or false
                local visible = (not UnitIsVisible) or UnitIsVisible(unit)
                e.auraDataAvailable = e.online and visible
                if UnitIsUnit(unit, "player") then
                    e.inspectable = true
                elseif CanInspect then
                    local ok, canInspect = pcall(CanInspect, unit)
                    e.inspectable = ok and canInspect and true or false
                else
                    e.inspectable = visible
                end
                if self.readyCheckActive then
                    e.ready = GetReadyCheckStatus(unit)
                    if self.readyCheckInitiator and e.ready == nil then
                        local initiator = NormalizeFullName(self.readyCheckInitiator)
                        if initiator == fullName or initiator == name then e.ready = "ready" end
                    end
                end
            end
        end
    end
    if needsFullRefresh then self:RefreshRoster() end
end

function ARC:GetConsumableStatus(entry, key)
    if not entry or entry.online == false or not entry.auraDataAvailable then return "unknown" end
    if not entry[key] then return "missing", 0 end
    local expiresAt = entry[key .. "ExpiresAt"]
    if expiresAt and expiresAt > 0 then
        local remaining = math.max(0, expiresAt - GetTime())
        if remaining <= self.CONSUMABLE_WARN_SECONDS then return "expiring", remaining end
        return "present", remaining
    end
    return "present"
end

function ARC:CompareVersions(left, right)
    local function Parse(value)
        if type(value) ~= "string" then return nil end
        local major, minor, patch = value:match("^(%d+)%.(%d+)%.(%d+)$")
        if not major then return nil end
        return tonumber(major), tonumber(minor), tonumber(patch)
    end
    local la, lb, lc = Parse(left)
    local ra, rb, rc = Parse(right)
    if not la or not ra then return nil end
    if la ~= ra then return la < ra and -1 or 1 end
    if lb ~= rb then return lb < rb and -1 or 1 end
    if lc ~= rc then return lc < rc and -1 or 1 end
    return 0
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
    local prep = selfEntry and selfEntry.preparation or {}
    -- fields separated by ^ ; keep it short, addon messages cap at 255 chars
    local parts = {
        ARC.VERSION,
        (GetUnitIdentity("player")) or "?",
        tostring(id or 0),
        tostring(upgradedLevel or Round(avgEquipped or avgAll) or 0),
        tostring(durAvg or -1),
        tostring(durWorst or -1),
        "R1", -- optional, backwards-compatible readiness extension
        selfEntry and selfEntry.talents and selfEntry.talents.code or "??????",
        ARC.ReadSelfWeaponBuffs and ARC:ReadSelfWeaponBuffs() or "??",
        "P1", prep.pet or "?", prep.growl or "?",
        selfEntry and selfEntry.sacrifice and selfEntry.sacrifice.state or "?",
        prep.healthstone or "?", prep.petGUID or "-", prep.form or "?",
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
    if type(msg) ~= "string" or #msg > 255 then return end
    local ver, name, specID, ilvl, dur, durWorst, extension, talentCode, weaponCode,
        prepVersion, petCode, growlCode, sacrificeCode, stoneCode, petGUID, formCode = strsplit("^", msg)
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
            if e.specID ~= id then e.talents, e.lastGearScan, e.sacrifice = nil, nil, nil end
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
    if extension == "R1" and ARC.DecodeTalents then
        local talents = ARC:DecodeTalents(talentCode, e.class, e.level, "comm")
        if talents then e.talents = talents end
        if type(weaponCode) == "string" and #weaponCode == 2 and not weaponCode:find("[^01x?]") then
            e.weaponBuffs, e.weaponBuffAt = weaponCode, GetTime()
        else
            e.weaponBuffs, e.weaponBuffAt = nil, nil
        end
    else
        e.weaponBuffs, e.weaponBuffAt = nil, nil
    end
    e.preparation = nil
    if extension == "R1" and prepVersion == "P1" and ARC.DecodePreparation then
        e.preparation = ARC:DecodePreparation(petCode, growlCode, stoneCode, petGUID, formCode, tonumber(specID))
        if e.preparation and (sacrificeCode == "0" or sacrificeCode == "1" or sacrificeCode == "?") and e.class == "WARLOCK" then
            e.sacrifice = { state = sacrificeCode, checkedAt = GetTime(), specID = tonumber(specID) }
        end
    end
    if ARC.ScanSelfBuffs then e.selfBuffs = ARC:ScanSelfBuffs(e.unit, e) end
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
    ScanUnitBuffs = ScanUnitBuffs,
}

-- Readiness checks deliberately live in an existing TOC module: in-session
-- updates on 5.4.8 must not lose these methods to a cached old file list.
local function TalentLevels(class)
    if CLASS_TALENT_LEVELS and (CLASS_TALENT_LEVELS[class] or CLASS_TALENT_LEVELS.DEFAULT) then
        return CLASS_TALENT_LEVELS[class] or CLASS_TALENT_LEVELS.DEFAULT
    end
    return class == "DEATHKNIGHT" and { 56, 57, 58, 60, 75, 90 } or { 15, 30, 45, 60, 75, 90 }
end

function ARC:DecodeTalents(code, class, level, source)
    if type(code) ~= "string" or #code ~= 6 or code:find("[^01x?]") then return nil end
    local out = { code = code, missing = {}, unknown = {}, checkedAt = GetTime(), source = source, selected = 0, required = 0 }
    local levels = TalentLevels(class)
    for tier = 1, 6 do
        local mark = code:sub(tier, tier)
        if not level or level < 1 or not levels then
            out.unknown[#out.unknown + 1] = "Tier " .. tier .. ": level unavailable"
        elseif level >= levels[tier] then
            out.required = out.required + 1
            if mark == "1" then out.selected = out.selected + 1
            elseif mark == "0" then out.missing[#out.missing + 1] = "Tier " .. tier .. " (level " .. levels[tier] .. ")"
            else out.unknown[#out.unknown + 1] = "Tier " .. tier .. ": talent data unavailable" end
        end
    end
    out.complete = #out.unknown == 0
    return out
end

function ARC:ScanTalents(unit, entry, inspectReady)
    local inspect = not UnitIsUnit(unit, "player")
    local _, class, classID = UnitClass(unit)
    local level, levels = UnitLevel(unit), TalentLevels(class)
    local code = {}
    local sacrifice = "?"
    -- A remote all-empty static talent catalog is not proof of an empty build.
    -- Require our GUID-matched INSPECT_READY and a loaded inspected spec first.
    local ready = GetTalentInfo and (not inspect or (inspectReady and GetInspectSpecialization and (GetInspectSpecialization(unit) or 0) > 0))
    for tier = 1, 6 do
        local mark = "?"
        if level and level > 0 and levels and level < levels[tier] then
            mark = "x"
        elseif ready and level and level > 0 then
            local selected, selectedColumn, valid = 0, nil, true
            for column = 1, 3 do
                -- Original MoP API, NOT the modern (tier, column, group) API.
                local ok, name, _, actualTier, actualColumn, chosen = pcall(GetTalentInfo, (tier - 1) * 3 + column, inspect, nil, unit, classID)
                if not ok or not name or actualTier ~= tier or actualColumn ~= column then valid = false end
                if chosen then selected = selected + 1; selectedColumn = column end
            end
            if valid and selected <= 1 then mark = selected == 1 and "1" or "0" end
            if class == "WARLOCK" and tier == 5 and valid and selected <= 1 then
                sacrifice = selectedColumn == 3 and "1" or "0"
            end
        end
        code[tier] = mark
    end
    entry.talents = self:DecodeTalents(table.concat(code), class, level, inspect and "inspect" or "self")
    if class == "WARLOCK" then entry.sacrifice = { state = sacrifice, checkedAt = GetTime(), specID = entry.specID } end
    return entry.talents
end

function ARC:GetTalentStatus(entry)
    local talents = entry.talents
    if not talents or (talents.source ~= "self" and GetTime() - talents.checkedAt > 65) then
        return "?", "warn", { "Talents: waiting for current inspect/ARC data" }
    end
    local details = {}
    for _, missing in ipairs(talents.missing) do details[#details + 1] = "Empty talent: " .. missing end
    for _, unknown in ipairs(talents.unknown) do details[#details + 1] = unknown end
    if #talents.missing > 0 then return "!" .. #talents.missing, "bad", details end
    if not talents.complete then return "?", "warn", details end
    return talents.required == 0 and "-" or "OK", "good", details
end

-- MoP temporary weapon enchants return three values per hand. There is no
-- enchant ID here and no remote-unit argument. Do not use the modern tuple.
function ARC:ReadSelfWeaponBuffs()
    local _, class = UnitClass("player")
    if class ~= "SHAMAN" then return "xx" end
    if not GetWeaponEnchantInfo then return "??" end
    local ok, main, mainMS, _, off, offMS = pcall(GetWeaponEnchantInfo)
    if not ok then return "??" end
    local function Hand(slot, present, remaining)
        local link = GetInventoryItemLink("player", slot)
        if not link then return GetInventoryItemTexture("player", slot) and "?" or "x" end
        local _, _, _, _, _, _, _, _, equipLoc = GetItemInfo(link)
        if not equipLoc then return "?" end
        if equipLoc == "INVTYPE_SHIELD" or equipLoc == "INVTYPE_HOLDABLE" then return "x" end
        return present and (not remaining or remaining > 0) and "1" or "0"
    end
    return Hand(16, main, mainMS) .. Hand(17, off, offMS)
end

local SELF_BUFF_RULES = {
    ROGUE = { { label = "Lethal poison (Deadly / Wound)", ids = { 2823, 8679 }, names = { "Deadly Poison", "Wound Poison" } } },
    PRIEST = { { label = "Inner Fire / Inner Will", ids = { 588, 73413 }, names = { "Inner Fire", "Inner Will" } } },
    MAGE = { { label = "Mage / Frost / Molten Armor", ids = { 6117, 7302, 30482 }, names = { "Mage Armor", "Frost Armor", "Molten Armor" } } },
    PALADIN = { { label = "Seal", ids = { 20154, 20165, 31801, 20164 }, names = { "Seal of Righteousness", "Seal of Insight", "Seal of Truth", "Seal of Justice" } } },
}
local SHAMAN_SHIELDS = {
    [262] = { label = "Lightning Shield", ids = { 324 }, names = { "Lightning Shield" } },
    [263] = { label = "Lightning Shield", ids = { 324 }, names = { "Lightning Shield" } },
    [264] = { label = "Water Shield", ids = { 52127 }, names = { "Water Shield" } },
}
local SYMBIOSIS = { label = "Symbiosis", ids = { 110309 }, names = { "Symbiosis" } }
local SACRIFICE = { label = "Grimoire of Sacrifice buff", ids = { 108503 }, names = { "Grimoire of Sacrifice" } }
local RIGHTEOUS_FURY = { label = "Righteous Fury", ids = { 25780 }, names = { "Righteous Fury" } }
local TANK_BUFFS = {
    [66] = RIGHTEOUS_FURY,
    [250] = { label = "Blood Presence", form = true, ids = { 48263 }, names = { "Blood Presence" } },
    [73] = { label = "Defensive Stance", form = true, ids = { 71 }, names = { "Defensive Stance" } },
    [104] = { label = "Bear Form", form = true, ids = { 5487 }, names = { "Bear Form" } },
    [268] = { label = "Stance of the Sturdy Ox", form = true, ids = { 115069 }, names = { "Stance of the Sturdy Ox" } },
}
local TANK_CLASSES = { PALADIN=true, DEATHKNIGHT=true, WARRIOR=true, DRUID=true, MONK=true }

local function AuraPresent(entry, rule)
    local buffs = entry.buffs
    if entry.online == false or entry.dead or not buffs or not buffs.auras or not buffs.auraNames then return nil end
    for _, id in ipairs(rule.ids) do
        if buffs.auras[id] then return true end
        local localized = GetSpellInfo and GetSpellInfo(id)
        if localized and buffs.auraNames[localized] then return true end
    end
    for _, name in ipairs(rule.names) do if buffs.auraNames[name] then return true end end
    return false
end

local function PetUnit(unit)
    if UnitIsUnit(unit, "player") then return "pet" end
    local index = unit and unit:match("^party(%d+)$")
    if index then return "partypet" .. index end
    index = unit and unit:match("^raid(%d+)$")
    if index then return "raidpet" .. index end
    if unit == "target" or unit == "focus" or unit == "mouseover" then return unit .. "pet" end
end

local function FreshPreparation(entry)
    local prep = entry.preparation
    return prep and GetTime() - prep.checkedAt <= 30 and prep or nil
end

function ARC:GetPetState(unit, entry)
    if entry.online == false or entry.dead or (UnitHasVehicleUI and UnitHasVehicleUI(unit)) then return "?" end
    local pet = PetUnit(unit)
    if pet and UnitExists(pet) then
        if not UnitGUID(pet) then return "?" end
        if UnitIsVisible and not UnitIsVisible(pet) then return "?" end
        if not UnitIsDeadOrGhost then return "?" end
        return UnitIsDeadOrGhost(pet) and "d" or "1", UnitGUID(pet)
    end
    if UnitIsUnit(unit, "player") then
        if IsMounted and IsMounted() then return "?" end
        return "0"
    end
    -- A remote pet can simply be out of sight. Only its owner can confirm
    -- absence; the raid/inspect client must not infer it from UnitExists=false.
    local prep = FreshPreparation(entry)
    if prep then return prep.pet, prep.petGUID end
    return "?"
end

function ARC:GetSacrificeState(entry)
    local value = entry.sacrifice
    if not value or not entry.specID or value.specID ~= entry.specID or GetTime() - value.checkedAt > 65 then return "?" end
    return value.state
end

function ARC:ReadHunterGrowl()
    if not UnitExists("pet") or (UnitHasVehicleUI and UnitHasVehicleUI("player")) then return "?" end
    local growl = GetSpellInfo and GetSpellInfo(2649) or "Growl"
    local function AutoState(allowed, enabled)
        if allowed ~= true and allowed ~= 1 then return "?" end
        if enabled == true or enabled == 1 then return "1" end
        if enabled == nil or enabled == false or enabled == 0 then return "0" end
        return "?"
    end
    -- Inspect the whole pet spellbook so Growl need not be on its action bar.
    if HasPetSpells and GetSpellBookItemInfo and GetSpellAutocast then
        local ok, count = pcall(HasPetSpells)
        if ok and type(count) == "number" and count >= 1 and count <= 200 then
            for index = 1, count do
                local found, _, id = pcall(GetSpellBookItemInfo, index, BOOKTYPE_PET or "pet")
                local nameOK, name
                if GetSpellBookItemName then nameOK, name = pcall(GetSpellBookItemName, index, BOOKTYPE_PET or "pet") end
                if (found and id == 2649) or (nameOK and name == growl) then
                    local read, allowed, enabled = pcall(GetSpellAutocast, index, BOOKTYPE_PET or "pet")
                    if read then return AutoState(allowed, enabled) end
                end
            end
        end
    end
    if GetPetActionInfo then
        for index = 1, 10 do
            local ok, name, _, _, isToken, _, allowed, enabled = pcall(GetPetActionInfo, index)
            if ok and not isToken and name == growl then return AutoState(allowed, enabled) end
        end
    end
    return "?" -- Not found is NOT proof that autocast is disabled.
end

function ARC:ReadTankForm(entry)
    local rule = TANK_BUFFS[entry.specID]
    if not rule or not rule.form then return "?" end
    if entry.dead or (IsMounted and IsMounted()) or (UnitHasVehicleUI and UnitHasVehicleUI("player")) then return "?" end
    if AuraPresent(entry, rule) then return "1" end
    if not GetNumShapeshiftForms or not GetShapeshiftFormInfo then return "?" end
    local ok, count = pcall(GetNumShapeshiftForms)
    if not ok or type(count) ~= "number" or count < 1 or count > 20 then return "?" end
    local expected = GetSpellInfo and GetSpellInfo(rule.ids[1]) or rule.names[1]
    for index = 1, count do
        -- Original MoP returns texture, NAME, active, castable (not modern shape).
        local read, _, name, active = pcall(GetShapeshiftFormInfo, index)
        if read and name == expected then
            if active == true or active == 1 then return "1" end
            if active == nil or active == false or active == 0 then return "0" end
            return "?"
        end
    end
    return "?"
end

function ARC:ReadHealthstone()
    if not GetItemCount then return "?" end
    local ok, count = pcall(GetItemCount, 5512, false, false)
    if not ok or type(count) ~= "number" or count < 0 then return "?" end
    if count == 0 then return "0" end
    local chargesOK, charges = pcall(GetItemCount, 5512, false, true)
    if not chargesOK or type(charges) ~= "number" or charges < 0 or charges > 3 or charges ~= math.floor(charges) then return "p" end
    return tostring(charges)
end

function ARC:ReadSelfPreparation(entry)
    local pet, guid = self:GetPetState("player", entry)
    return { pet = pet, petGUID = guid, growl = entry.class == "HUNTER" and pet == "1" and self:ReadHunterGrowl() or "?",
        healthstone = self:ReadHealthstone(), form = self:ReadTankForm(entry), specID = entry.specID, checkedAt = GetTime() }
end

function ARC:DecodePreparation(pet, growl, stone, guid, form, specID)
    if type(pet) ~= "string" or not ({ ["0"]=true, ["1"]=true, d=true, ["?"]=true })[pet] or
        type(growl) ~= "string" or not ({ ["0"]=true, ["1"]=true, ["?"]=true })[growl] or
        type(stone) ~= "string" or #stone ~= 1 or not stone:match("^[0123p?]$") or
        type(guid) ~= "string" or #guid > 80 or not guid:match("^[%w%-]+$") or
        not (form == "0" or form == "1" or form == "?") then return nil end
    if (pet == "1" or pet == "d") and guid == "-" then return nil end
    return { pet = pet, growl = growl, healthstone = stone, petGUID = guid ~= "-" and guid or nil, form = form, specID = specID, checkedAt = GetTime() }
end

function ARC:GetHealthstoneStatus(entry)
    -- Don't demand a conjured item from a solo city player or a raid with no
    -- warlock able to supply it. Inspect cannot read someone else's bags.
    local grouped, supplier = false, false
    if IsInGroup() or IsInRaid() then
        for _, unit in ipairs(GetGroupUnits()) do
            if UnitExists(unit) then
                if entry.unit and UnitIsUnit(unit, entry.unit) and (not entry.guid or UnitGUID(unit) == entry.guid) then grouped = true end
                if select(2, UnitClass(unit)) == "WARLOCK" and (not UnitIsConnected or UnitIsConnected(unit)) then supplier = true end
            end
        end
    end
    if not grouped or not supplier then return "-", "neutral", "Healthstone: no applicable group/warlock supplier" end
    -- Inspect cannot read another player's bags. Do not let the absence of ARC
    -- turn a private-data check into a warning that blocks the raid verdict.
    if not entry.hasARC then
        return "OK", "good", "Healthstone check skipped: this player does not report through ARC"
    end
    local prep = FreshPreparation(entry)
    if entry.online == false or entry.dead or not prep or not prep.healthstone or prep.healthstone == "?" then
        return "OK", "good", "Healthstone check skipped: no current ARC bag report"
    end
    if prep.healthstone == "0" then return "!0", "bad", "Healthstone missing from bags (or fully consumed)" end
    if prep.healthstone == "p" then return "OK", "good", "Healthstone present; remaining charges could not be verified" end
    return prep.healthstone, "good", "Healthstone: " .. prep.healthstone .. " remaining use(s), reported by ARC; cooldown not checked"
end

function ARC:ScanSelfBuffs(unit, entry)
    local out = { missing = {}, problems = {}, unknown = {}, checked = 0 }
    local rules = SELF_BUFF_RULES[entry.class] or {}
    local level = entry.level or UnitLevel(unit)
    -- Raid-readiness policy targets level 90; avoid flagging unlearned spells
    -- on levelling characters. Their talents are still checked by unlock level.
    if not level or level < 1 then out.unknown[1] = "Self buffs: level unavailable"; return out end
    if level < 90 then out.skipped = true; return out end
    local isSelf = unit and UnitIsUnit(unit, "player")
    if not isSelf and not entry.hasARC then
        -- Remote aura lists are inconsistent on several MoP private-server
        -- cores (notably paladin seals). Without an owner ARC report, skip the
        -- complete Self policy instead of producing a false error or warning.
        out.skippedNoARC = true
        return out
    end
    local function Check(rule)
        out.checked = out.checked + 1
        local present = AuraPresent(entry, rule)
        if rule.form and not present then
            local prep = FreshPreparation(entry)
            -- Hidden stance auras are not reliable negative evidence remotely.
            present = nil
            if entry.online ~= false and not entry.dead and prep and prep.specID == entry.specID then
                if prep.form == "1" then present = true elseif prep.form == "0" then present = false end
            end
        end
        if present == nil then
            out.unknown[#out.unknown + 1] = rule.label .. (rule.form and ": need visible aura or current owner ARC stance report" or ": aura data unavailable")
        elseif not present then out.missing[#out.missing + 1] = rule.label end
    end
    for _, rule in ipairs(rules) do Check(rule) end
    if entry.class == "SHAMAN" then
        local shield = SHAMAN_SHIELDS[entry.specID]
        if shield then Check(shield) else out.unknown[#out.unknown + 1] = "Shaman shield: specialization unavailable" end
        if entry.online == false or entry.dead or not entry.weaponBuffAt or GetTime() - entry.weaponBuffAt > 30 then
            out.unknown[#out.unknown + 1] = "Weapon imbues: need a current report from this player's ARC"
        else
            for hand = 1, 2 do
                local mark = (entry.weaponBuffs or "??"):sub(hand, hand)
                local label = hand == 1 and "Main-hand weapon imbue" or "Off-hand weapon imbue"
                if mark == "0" then out.missing[#out.missing + 1] = label end
                if mark == "?" or mark == "" then out.unknown[#out.unknown + 1] = label .. ": unavailable" end
                if mark == "0" or mark == "1" then out.checked = out.checked + 1 end
            end
        end
    elseif entry.class == "DRUID" then
        -- Symbiosis needs a non-druid in the same group. Do not demand it of a
        -- random solo player in the city or a group made entirely of druids.
        local grouped, partner = false, false
        for _, groupUnit in ipairs(GetGroupUnits()) do
            if UnitIsUnit(groupUnit, unit) then grouped = true end
            if UnitExists(groupUnit) and (not UnitIsConnected or UnitIsConnected(groupUnit)) and select(2, UnitClass(groupUnit)) ~= "DRUID" then partner = true end
        end
        if grouped and partner then Check(SYMBIOSIS) end
    end
    if TANK_CLASSES[entry.class] and not entry.specID then
        out.unknown[#out.unknown + 1] = "Tank stance/presence: specialization unavailable"
    elseif TANK_CLASSES[entry.class] and TANK_BUFFS[entry.specID] then
        Check(TANK_BUFFS[entry.specID])
    elseif entry.class == "PALADIN" then
        out.checked = out.checked + 1
        local fury = AuraPresent(entry, RIGHTEOUS_FURY)
        if fury == nil then out.unknown[#out.unknown + 1] = "Righteous Fury: aura data unavailable"
        elseif fury then out.problems[#out.problems + 1] = "Righteous Fury active on a non-Protection paladin" end
    end

    local needsPet = entry.class == "HUNTER" or (entry.class == "MAGE" and entry.specID == 64) or (entry.class == "DEATHKNIGHT" and entry.specID == 252)
    if entry.class == "WARLOCK" then
        local sacrifice = self:GetSacrificeState(entry)
        if sacrifice == "?" then
            out.unknown[#out.unknown + 1] = "Warlock pet/Sacrifice: talent choice unavailable"
        elseif sacrifice == "1" then
            Check(SACRIFICE) -- talent selected alone is not sufficient
        else
            needsPet = true
        end
    elseif entry.class == "MAGE" and not entry.specID then
        out.unknown[#out.unknown + 1] = "Water Elemental: specialization unavailable"
    end
    if needsPet then
        out.checked = out.checked + 1
        local state, guid = self:GetPetState(unit, entry)
        if state == "0" then out.problems[#out.problems + 1] = "Required permanent pet is missing"
        elseif state == "d" then out.problems[#out.problems + 1] = "Required permanent pet is dead"
        elseif state ~= "1" then out.unknown[#out.unknown + 1] = "Pet: unavailable; absence needs a current owner ARC report" end
        if entry.class == "HUNTER" and state == "1" then
            local prep = FreshPreparation(entry)
            if not prep or prep.petGUID ~= guid or prep.growl == "?" then
                out.unknown[#out.unknown + 1] = "Growl autocast: need a current ARC report for this pet"
            elseif prep.growl == "1" then
                out.problems[#out.problems + 1] = "Hunter pet Growl autocast is ON - disable it for the raid"
            end
        end
    end
    return out
end

function ARC:GetSelfBuffStatus(entry)
    local buffs = entry.selfBuffs
    if not buffs then return "?", "warn", { "Self buffs: data unavailable" } end
    if buffs.skippedNoARC then
        return "OK", "good", { "Self checks skipped: this player does not report through ARC" }
    end
    local details = {}
    for _, missing in ipairs(buffs.missing) do details[#details + 1] = "Missing self buff: " .. missing end
    for _, problem in ipairs(buffs.problems or {}) do details[#details + 1] = problem end
    for _, unknown in ipairs(buffs.unknown) do details[#details + 1] = unknown end
    local issues = #buffs.missing + #(buffs.problems or {})
    if issues > 0 then return "!" .. issues, "bad", details end
    if #buffs.unknown > 0 then return "?", "warn", details end
    return buffs.checked > 0 and "OK" or "-", "good", details
end

ARC.RAID_DIFFICULTIES = { [0] = "Not checked", [3] = "10 Normal", [4] = "25 Normal", [5] = "10 Heroic", [6] = "25 Heroic", [7] = "Raid Finder", [14] = "Flexible" }
ARC.LOOT_METHODS = { any = "Not checked", freeforall = "Free for All", roundrobin = "Round Robin", master = "Master Loot", group = "Group Loot", needbeforegreed = "Need Before Greed" }

function ARC:GetRaidSetupStatus()
    local settings = ARC_DB.raidSetup
    if not settings.enabled then return "Raid setup check OFF - click to configure", "neutral" end
    if not IsInRaid() then return "Raid setup: not in a raid - click to configure", "neutral" end
    local _, instanceType, instanceDifficulty = nil, nil, nil
    if GetInstanceInfo then _, instanceType, instanceDifficulty = GetInstanceInfo() end
    if instanceType == "pvp" or instanceType == "arena" then return "Raid setup: PvP instance - PvE checks skipped", "neutral" end
    local difficulty
    if instanceType == "raid" then difficulty = instanceDifficulty
    elseif instanceType then difficulty = GetRaidDifficultyID and GetRaidDifficultyID() end
    local loot = GetLootMethod and GetLootMethod()
    local problems, unknown = {}, {}
    if settings.difficulty ~= 0 then
        if not difficulty or difficulty == 0 then unknown[#unknown + 1] = "difficulty unavailable"
        elseif difficulty ~= settings.difficulty then
            problems[#problems + 1] = "Mode: " .. (self.RAID_DIFFICULTIES[difficulty] or tostring(difficulty)) .. " -> expected " .. self.RAID_DIFFICULTIES[settings.difficulty]
        end
    end
    if settings.loot ~= "any" then
        if not loot or not self.LOOT_METHODS[loot] or loot == "any" then unknown[#unknown + 1] = "loot mode unavailable"
        elseif loot ~= settings.loot then problems[#problems + 1] = "Loot: " .. (self.LOOT_METHODS[loot] or loot) .. " -> expected " .. self.LOOT_METHODS[settings.loot] end
    end
    if #problems > 0 then return "! RAID SETUP MISMATCH\n" .. table.concat(problems, "  |  ") .. (#unknown > 0 and ("  |  " .. table.concat(unknown, ", ")) or ""), "bad" end
    if #unknown > 0 then return "RAID SETUP UNVERIFIED\n" .. table.concat(unknown, "  |  "), "warn" end
    if settings.difficulty == 0 and settings.loot == "any" then return "RAID SETUP NOT CONFIGURED\nClick here to choose the expected raid mode and loot method", "warn" end
    return "Raid setup OK" .. ((settings.difficulty == 0 or settings.loot == "any") and " (selected checks only)" or "") ..
        "\n" .. (self.RAID_DIFFICULTIES[difficulty] or "Unknown mode") .. "  |  " .. (self.LOOT_METHODS[loot] or "Unknown loot") .. "  |  Click to configure", "good"
end
