local ARC = assert(_G.ARC, "ARC_Core.lua must load before ARC_Localization.lua")

local BASE_LOCALE = "enGB"
local SUPPORTED = { auto=true, enGB=true, enUS=true, skSK=true, csCZ=true }
local CLIENT_ALIASES = { enUS="enGB", enGB="enGB" }

ARC.LOCALE_CHOICES = {
    { code="auto", name="Automatic (game language)" },
    { code="enGB", name="English" },
    { code="skSK", name="Slovenčina" },
    { code="csCZ", name="Čeština" },
}
ARC.Locales = ARC.Locales or {}
ARC.localeRefreshers = ARC.localeRefreshers or {}

function ARC:RegisterLocale(code, values)
    if type(code) ~= "string" or type(values) ~= "table" then return false end
    self.Locales[code] = values
    return true
end

local function EffectiveLocale(preference)
    if preference == "auto" or not SUPPORTED[preference] then
        local client = GetLocale and GetLocale() or BASE_LOCALE
        preference = CLIENT_ALIASES[client] or client
    end
    if preference == "enUS" then preference = "enGB" end
    if preference ~= BASE_LOCALE and not ARC.Locales[preference] then return BASE_LOCALE end
    return preference
end

function ARC:InitializeLocalization()
    if type(ARC_CharDB) ~= "table" then ARC_CharDB = {} end
    if not SUPPORTED[ARC_CharDB.language] then ARC_CharDB.language = "auto" end
    self.localePreference = ARC_CharDB.language
    self.locale = EffectiveLocale(self.localePreference)
end

function ARC:GetLanguage()
    return self.localePreference or "auto", self.locale or BASE_LOCALE
end

function ARC:Text(key, ...)
    local value = key
    local locale = self.locale or BASE_LOCALE
    local translations = self.Locales[locale]
    if translations and translations[key] ~= nil then value = translations[key] end
    if select("#", ...) > 0 then
        local ok, formatted = pcall(string.format, value, ...)
        if ok then return formatted end
    end
    return value
end

-- Gear checks intentionally keep stable English diagnostics in their cached
-- data. Translate them only while rendering so changing language never forces
-- another inspect or mutates a saved/report snapshot.
function ARC:LocalizeDiagnostic(text)
    if type(text) ~= "string" then return text end
    if text:find("\n", 1, true) then
        local lines = {}
        for line in (text .. "\n"):gmatch("(.-)\n") do
            local prefix, body = line:match("^(%- )(.*)$")
            lines[#lines + 1] = prefix and (prefix .. self:LocalizeDiagnostic(body)) or self:LocalizeDiagnostic(line)
        end
        return table.concat(lines, "\n")
    end
    if text:find("; ", 1, true) then
        local parts = {}
        for part in text:gmatch("[^;]+") do
            parts[#parts + 1] = self:LocalizeDiagnostic((part:gsub("^%s+", "")))
        end
        return table.concat(parts, "; ")
    end
    local exact = self:Text(text)
    if exact ~= text then return exact end
    local number = text:match("^Below (%d+) iLvl$")
    if number then return self:Text("Below %d iLvl", tonumber(number)) end
    number = text:match("^(%d+) missing gem%(s%)$")
    if number then return self:Text("%d missing gem(s)", tonumber(number)) end
    number = text:match("^(%d+) gear issue%(s%)$")
    if number then return self:Text("%d gear issue(s)", tonumber(number)) end
    number = text:match("^in (%d+) slot%(s%)$")
    if number then return self:Text("in %d slot(s)", tonumber(number)) end
    local label, count = text:match("^(.+) %((%d+)%)$")
    if label then return self:Text(label) .. " (" .. count .. ")" end
    local value = text:match("^Wrong primary stat %(expected (.+)%)$")
    if value then return self:Text("Wrong primary stat (expected %s)", value) end
    value = text:match("^Empty talent: (.+)$")
    if value then return self:Text("Empty talent: %s", self:LocalizeDiagnostic(value)) end
    value = text:match("^Missing self buff: (.+)$")
    if value then return self:Text("Missing self buff: %s", self:LocalizeDiagnostic(value)) end
    local tier, level = text:match("^Tier (%d+) %(level (%d+)%)$")
    if tier then return self:Text("Tier %d (level %d)", tonumber(tier), tonumber(level)) end
    tier = text:match("^Tier (%d+): level unavailable$")
    if tier then return self:Text("Tier %d: level unavailable", tonumber(tier)) end
    tier = text:match("^Tier (%d+): talent data unavailable$")
    if tier then return self:Text("Tier %d: talent data unavailable", tonumber(tier)) end
    value = text:match("^PvP bonus %((.+)%)$")
    if value then return self:Text("PvP bonus (%s)", value) end
    value = text:match("^profession bonus requires (.+)$")
    if value then return self:Text("profession bonus requires %s", value) end
    value = text:match("^missing (.+) profession bonus$")
    if value then return self:Text("missing %s profession bonus", value) end
    value = text:match("^requires role (.+)$")
    if value then return self:Text("requires role %s", value) end
    value = text:match("^requires (.+)$")
    if value then return self:Text("requires %s", value) end
    local index, name = text:match("^Gem (%d+) %- (.+)$")
    if index then return self:Text("Gem %d - %s", tonumber(index), name) end
    value = text:match("^Enchant %- (.+)$")
    if value then return self:Text("Enchant - %s", value) end
    value = text:match("^Healthstone: (.+) remaining use%(s%), reported by ARC; cooldown not checked$")
    if value then return self:Text("Healthstone: %s remaining use(s), reported by ARC; cooldown not checked", value) end
    local left, right = text:match("^([^:]+): (.+)$")
    if left then return self:Text(left) .. ": " .. self:LocalizeDiagnostic(right) end
    return text
end

function ARC:RegisterLocaleRefresh(owner, callback)
    if type(callback) ~= "function" then return end
    self.localeRefreshers[owner or callback] = callback
end

function ARC:RefreshLocaleUI()
    for _, callback in pairs(self.localeRefreshers) do pcall(callback) end
    if InspectFrame and InspectFrame.arcCheckButton then InspectFrame.arcCheckButton:SetText(self:Text("ARC Check")) end
    if CharacterFrame and CharacterFrame.arcCheckButton then CharacterFrame.arcCheckButton:SetText(self:Text("ARC Check")) end
    if self.IsVisible and self:IsVisible() and self.Render then self:Render() end
    if self.RefreshSessionReport then self:RefreshSessionReport() end
    if self.UpdatePlayerCheck and self.playerCheckFrame and self.playerCheckFrame:IsShown() then
        self:UpdatePlayerCheck()
    end
end

function ARC:SetLanguage(code)
    if not SUPPORTED[code] then return false end
    if type(ARC_CharDB) ~= "table" then ARC_CharDB = {} end
    ARC_CharDB.language = code
    self.localePreference = code
    self.locale = EffectiveLocale(code)
    self:RefreshLocaleUI()
    return true
end

-- English source strings are the canonical fallback. enUS deliberately shares
-- enGB wording so both English clients use one maintained translation.
ARC:RegisterLocale(BASE_LOCALE, {})
