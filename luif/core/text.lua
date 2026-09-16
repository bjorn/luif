--
-- Text is a string id plus arguments for string substitution. The id is
-- looked up in core.Localization whenever the text is shown, so a Text can
-- be created before the strings of a language are loaded.
--
-- Rules: {1} (localized argument), {1:U} (upper case), {1:p} (plain),
-- {1:d.2} (number format), plural forms {p one other} and {color:...}.
-- Applications add their own to Text.substitutionRules and
-- Text.grammarRules.
--

local core = require "luif.core"

local Class     = core.Class
local Color     = core.Color
local Localization = core.Localization
local bit       = core.Bit

local Text = Class:extend {
    id = "",
    params = {},
}

function Text.localize(text)
    return Localization.localize(text)
end

function Text.new(class, text, ...)
    local self
    if type(text) == "string" then
        self = { id = text, params = {...} }
    elseif type(text) == "table" then
        local params = {}
        for _, parameter in ipairs(text.params) do
            params[#params + 1] = parameter
        end
        for _, parameter in ipairs({...}) do
            params[#params + 1] = parameter
        end
        self = { id = text.id, params = params }
    else
        assert(false)
    end
    return Class.new(class, self)
end

local argNum
local argTable
local emptyTable = {}

local function appendArguments(text, args)
    for _, argument in ipairs(args) do
        text.params[#text.params + 1] = argument
    end
end

Text.substitutionRules = {
    -- default rules tries to localize the substitution
    -- default rule supports passing of another argument, e.g. {1<2} will pass
    -- argument 2 to the string while processing
    -- or several: {1<2,4} will pass arguments 2 and 4 to the string
    -- also works with static data, e.g. passing gender: {1<f}
    default = function(index, params)
        local text = argTable[index]
        local t = type(text)
        local extraArguments

        if params then
            local doSubst, _, passedArguments = string.find(params, "^<([0-9a-zA-Z,]+)")
            if doSubst then
                extraArguments = {}
                for match in string.gmatch(passedArguments, "([^,]+)") do
                    local index = tonumber(match)
                    extraArguments[#extraArguments + 1] = type(index) ~= "number" and match or argTable[index]
                end
            end
        end

        if extraArguments then
            if t == "string" then
                return Text(text, unpack(extraArguments)):get()
            elseif t == "table" then
                appendArguments(text, extraArguments)
                return text:get()
            else
                return text
            end
        end

        if t == "table" then
            return text:get()
        elseif t == "string" then
            return Text.substitute(nil, Text.localize(text))
        else
            return text
        end
    end,

    -- Put the parameter in upper case
    U = function(index)
        return string.upper(Text.substitutionRules.default(index))
    end,

    -- plain text that doesn't need localization (e.g. user names)
    p = function(index)
        return argTable[index]
    end,

    -- format argument as float, e.g. {1:d.4} yields 3.1416
    d = function(index, params)
        local value = argTable[index]
        if type(value) ~= "number" then
            return "NumberError"
        else
            return string.format("%" .. params .. "f", value)
        end
    end,
}

local function firstValidArgument(condition)
    local value
    for _, argument in ipairs(argTable) do
        value = condition(argument)
        if value then
            return value
        end
    end
end

-- Split a string on spaces, with support for quoting.
local function split(s)
    local pos = 1

    return function()
        pos = string.find(s, "[^%s]", pos)            -- skip whitespace
        if not pos then
            return                                  -- nothing else than whitespace found
        end

        local c = string.sub(s, pos, pos)

        if c == "'" then                            -- does it start with a quote?
            local first = pos
            while true do                           -- find ending quote
                pos = pos + 1

                local endQuote = string.find(s, "'", pos, true)
                if not endQuote then
                    return "PluralError: mismatched quote"
                end

                pos = endQuote + 1
                c = string.sub(s, pos, pos)

                if c ~= "'" then
                    return string.gsub(string.sub(s, first + 1, pos - 2), "''", "'")
                end
            end
        else
            local _, last, capture = string.find(s, "^([^%s']+)", pos)
            pos = last + 1
            return capture
        end
    end
end

local grammarRules = {
    -- unknown tags are left as they are
    nothing = function(index, params)
        return nil
    end,

    -- plural forms, picked by Localization.pluralForm
    p = function(index, params)
        local quantity = tonumber(argTable[index])

        if not quantity or type(quantity) ~= "number" then
            quantity = firstValidArgument(function(argument) return type(tonumber(argument)) == "number" and tonumber(argument) end)
            quantity = quantity or 1
        end

        local form = Localization.pluralForm(quantity)
        local i = 0
        for sub in split(params) do
            if form == i then
                return sub
            end
            i = i + 1
        end
        return "PluralError: missing plural form " .. tostring(form)
    end,

    -- substitute color strings with hex codes
    color = function(index, params)
        local val
        if string.sub(params,1,1) == "#" then
            -- color as hex code
            val = params
        elseif type(Color[params]) == "number" then
            -- color by string name
            val = bit.band(Color[params], 0xFFFFFF)
            val = "#" .. bit.tohex(val, 6)
        else
            -- color as parameter
            local color = argTable[index] or Color.white
            if type(color) ~= "number" then
                color = Color.white
            end
            val = "#" .. bit.tohex(color, 6)
        end
        return "{color:".. val .."}"
    end,
}

function Text.argument(index)
    return argTable[index]
end

-- The arguments of the text being substituted
function Text.arguments()
    return argTable
end

-- The first value condition(argument) returns for the arguments, or nil
function Text.firstArgument(condition)
    return firstValidArgument(condition)
end

-- Grammar rules by name: function(index, params) -> replacement or nil
Text.grammarRules = grammarRules

-- applied substitution rules
-- {#}      - simple substitution, using argument number #
-- {#:d}    - convert argument # to decimal
-- {#:d.$}  - format argument # as float with precision $
-- {#:p}    - plain text

-- other tags are left as they are
local function apply(var)
    -- parse arg index
    local index, subRule, params = string.match(var, "^{(%d+):?(%a*)(.*)}$")
    local func

    if index then
        -- parameter substitution
        func = Text.substitutionRules[subRule] or Text.substitutionRules.default
        index = tonumber(index)
        argNum = argNum + 1
    else
        -- grammar rules, optionally taking a parameter index
        local grammarRule
        grammarRule, index, params = string.match(var, "^{(%a+):?(%d*) ?(.*)}$")
        func = grammarRules[grammarRule] or grammarRules.nothing
        index = tonumber(index) or argNum > 0 and argNum or 1
    end

    -- apply appropriate substitution rule
    return func(index, params)
end

function Text:substitute(text)
    -- remember previous values (in case of nesting)
    local oldArgNum = argNum
    local oldArgTable = argTable
    argNum = 0
    argTable = self and self.params or emptyTable

    local original
    local substitution = text
    repeat
        original = substitution
        substitution = string.gsub(original, "%b{}", apply)
    until original == substitution

    -- reset to previous values
    argNum = oldArgNum
    argTable = oldArgTable
    return substitution
end

function Text:stripTags(text)
    return string.gsub(text, "{[^}]*}", "")
end

function Text:colorize(text, color)
    return "{color:#" .. bit.tohex(color, 6) .. "}" .. text .. "{/color}"
end

function Text.equal(a, b)
    if a.id ~= b.id then
        return false
    end

    if #a.params ~= #b.params then
        return false
    end

    for i, parameter in ipairs(a.params) do
        if parameter ~= b.params[i] then
            return false
        end
    end

    return true
end

function Text:get()
    return Text.substitute(self, Text.localize(self.id))
end

return Text
