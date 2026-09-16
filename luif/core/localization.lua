--
-- Minimal localization: a string table with identity fallback, plus the
-- plural helper core.Text uses.
--
-- Usage:
--
--   core.Localization.load { ok = "OK", cancel = "Abbrechen" }
--   core.Localization.localize("cancel")  --> "Abbrechen"
--   core.Localization.localize("Hello")   --> "Hello" (unknown ids pass through)
--

local Localization = {
    strings = {},
}

local language = "en"

function Localization.localize(id)
    local text = Localization.strings[id]
    if text == nil then
        return id
    end
    return text
end

-- Merges a table of id -> string into the string table
function Localization.load(strings, newLanguage)
    for id, text in pairs(strings) do
        Localization.strings[id] = text
    end
    if newLanguage then
        language = newLanguage
    end
end

function Localization.clear()
    Localization.strings = {}
end

function Localization.language()
    return language
end

function Localization.setLanguage(newLanguage)
    language = newLanguage
end

-- Index of the plural form in a "{p one other}" tag, counted from 0. Replace
-- it for languages with other plural rules.
function Localization.pluralForm(quantity)
    return quantity == 1 and 0 or 1
end

return Localization
