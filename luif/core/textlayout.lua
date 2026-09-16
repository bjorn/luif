--
-- Text layout for labels, measured through a host (host/interface.lua):
-- colour tags, abbreviation with an ellipsis, obfuscation and the size of
-- the laid out text. Plain Lua, so it also runs with the recording host.
--
--   local layout = TextLayout.layout(host, font, text, {
--       color = 0xFFFFFFFF,   -- label colour; tag runs use its RGB as base
--       scale = 1,            -- label text scale; the format width is divided by it
--       limit = false,        -- format width in label units, or false
--       abbreviate = false,   -- with a limit: cut with an ellipsis, do not wrap
--       obfuscate = false,    -- show one bullet per codepoint
--   })
--
-- The result: display (string, or runs { color, string, ... } when the text
-- had colour tags), plain (string), wrap (the host wraps at boxWidth),
-- boxWidth and boxHeight (the node box in unscaled font units: the format
-- width when there is one, otherwise the text's own size) and width and
-- height (the scaled size of the text, the label's implicit size).
--
-- Text handling: {color:#rrggbb}...{/color} runs become colour runs, other
-- {tags} are stripped. With a limit the text wraps to it, unless abbreviate
-- is set; then it is truncated with an ellipsis instead. Without a limit
-- lines break only at "\n".
--

local ceil = math.ceil
local concat = table.concat

local TextLayout = {}

local BULLET = "\226\128\162"    -- U+2022
local ELLIPSIS = "\226\128\166"  -- U+2026

TextLayout.BULLET = BULLET
TextLayout.ELLIPSIS = ELLIPSIS

local WHITE = 0xFFFFFFFF

-- Number of codepoints (bytes that are not continuation bytes).
local function length(s)
    local _, count = s:gsub("[^\128-\191]", "")
    return count
end

TextLayout.length = length

-- The first n codepoints of s.
local function prefix(s, n)
    if n <= 0 then return "" end
    local count = 0
    for pos = 1, #s do
        local byte = s:byte(pos)
        if byte < 128 or byte >= 192 then
            count = count + 1
            if count > n then
                return s:sub(1, pos - 1)
            end
        end
    end
    return s
end

--
-- Parses colour tags. Returns the plain text (all tags removed) and, when
-- colour tags were present, runs { color, string, ... } whose untagged parts
-- use the base colour's RGB, opaque. Returns false as second value otherwise.
--
function TextLayout.parse(text, color)
    if not text:find("{", 1, true) then
        return text, false
    end
    local base = 0xFF000000 + ((color or WHITE) % 4294967296) % 16777216
    local runs, n = {}, 0
    local plain, np = {}, 0
    local stack, depth = {}, 0
    local current = base
    local colored = false
    local pos = 1

    local function append(segment)
        if segment == "" then return end
        np = np + 1
        plain[np] = segment
        runs[n + 1], runs[n + 2] = current, segment
        n = n + 2
    end

    while true do
        local s, e = text:find("%b{}", pos)
        if not s then break end
        append(text:sub(pos, s - 1))
        local tag = text:sub(s + 1, e - 1)
        local hex = tag:match("^color:#(%x%x%x%x%x%x)$")
        if hex then
            depth = depth + 1
            stack[depth] = current
            current = 0xFF000000 + tonumber(hex, 16)
            colored = true
        elseif tag == "/color" and depth > 0 then
            current = stack[depth]
            stack[depth] = nil
            depth = depth - 1
        end
        pos = e + 1
    end
    append(text:sub(pos))

    return concat(plain), colored and runs or false
end

-- One bullet per codepoint.
function TextLayout.obfuscate(text)
    return BULLET:rep(length(text))
end

-- Widest line of a string containing newlines.
local function maxLineWidth(host, font, text)
    local width = 0
    local start = 1
    while true do
        local nl = text:find("\n", start, true)
        local line = nl and text:sub(start, nl - 1) or text:sub(start)
        local w = host.textWidth(font, line)
        if w > width then width = w end
        if not nl then break end
        start = nl + 1
    end
    return width
end

TextLayout.maxLineWidth = maxLineWidth

local function countLines(text)
    local _, newlines = text:gsub("\n", "")
    return newlines + 1
end

-- Cuts runs down to n codepoints and appends the ellipsis in the base colour.
local function truncateRuns(runs, n, base)
    local out, count = {}, 0
    local remaining = n
    for i = 1, #runs, 2 do
        if remaining <= 0 then break end
        local color, segment = runs[i], runs[i + 1]
        local len = length(segment)
        if len > remaining then
            segment = prefix(segment, remaining)
        end
        out[count + 1], out[count + 2] = color, segment
        count = count + 2
        remaining = remaining - len
    end
    out[count + 1], out[count + 2] = base, ELLIPSIS
    return out
end

--
-- The longest prefix of plain (in codepoints) whose width with an ellipsis
-- fits in limit, found by binary search, with the ellipsis appended. Runs
-- are cut the same way when given.
--
function TextLayout.abbreviate(host, font, plain, runs, limit, color)
    local lo, hi = 0, length(plain)
    while lo < hi do
        local mid = ceil((lo + hi) / 2)
        if maxLineWidth(host, font, prefix(plain, mid) .. ELLIPSIS) <= limit then
            lo = mid
        else
            hi = mid - 1
        end
    end
    local shown = prefix(plain, lo) .. ELLIPSIS
    if runs then
        local base = 0xFF000000 + ((color or WHITE) % 4294967296) % 16777216
        return shown, truncateRuns(runs, lo, base)
    end
    return shown, false
end

function TextLayout.layout(host, font, text, options)
    options = options or {}
    local scale = options.scale or 1
    local color = options.color or WHITE
    local plain, runs = TextLayout.parse(tostring(text or ""), color)

    if options.obfuscate then
        plain, runs = TextLayout.obfuscate(plain), false
    end

    local result = {
        display = runs or plain, plain = plain, wrap = false,
        boxWidth = 0, boxHeight = 0, width = 0, height = 0,
    }
    if scale <= 0 then
        -- Nothing is visible; avoid dividing the format width by zero.
        return result
    end

    local limit, wrap = false, false
    if options.limit then
        limit = options.limit / scale
        if options.abbreviate then
            if maxLineWidth(host, font, plain) > limit then
                plain, runs = TextLayout.abbreviate(host, font, plain, runs, limit, color)
            end
        else
            wrap = true
        end
    end

    local lineHeight = host.lineHeight(font)
    local w, h
    if wrap then
        local widest, lines = host.wrapText(font, plain, limit)
        local count = #lines
        if count < 1 then count = 1 end
        w, h = widest, count * lineHeight
    else
        w, h = maxLineWidth(host, font, plain), countLines(plain) * lineHeight
    end

    result.display, result.plain, result.wrap = runs or plain, plain, wrap
    result.boxWidth, result.boxHeight = limit or w, h
    result.width, result.height = w * scale, h * scale
    return result
end

return TextLayout
