--
-- The text editing model behind TextInput: text, caret and anchor as
-- codepoint indices (0..len, the number of characters before the caret),
-- the selection being the range between them, and the line layout needed
-- to place a caret and selection rectangles.
--
-- Pure Lua. Measurement comes from a small object supplied by the owner:
--
--   measure = {
--       getWidth = function(s) ... end,       -- width of a string
--       getHeight = function() ... end,       -- line pitch
--       wrap = function(s, width) ... end,    -- string -> array of lines
--   }
--
-- Lines are split at "\n" and, when multiline and wrapWidth is set, by
-- measure.wrap. Each line covers a contiguous range of caret positions
-- (first..last) so that every position belongs to exactly one line.
--

local core = require "luif.core"

local Class = core.Class

-- Matches one UTF-8 encoded codepoint
local CHAR_PATTERN = "[%z\1-\127\194-\244][\128-\191]*"

local floor, max, min = math.floor, math.max, math.min
local concat = table.concat

local function splitChars(text)
    local chars = {}
    for ch in text:gmatch(CHAR_PATTERN) do
        chars[#chars + 1] = ch
    end
    return chars
end

local function countChars(text)
    local count = 0
    for _ in text:gmatch(CHAR_PATTERN) do
        count = count + 1
    end
    return count
end

local function charClass(ch)
    if ch == "\n" then
        return "newline"
    elseif ch:match("^%s") then
        return "space"
    elseif #ch > 1 or ch:match("^%w") then
        return "word"
    end
    return "punct"
end

-- Monospace fallback so the model works without an owner supplied measure
local defaultMeasure = {
    getWidth = function(s) return countChars(s) * 8 end,
    getHeight = function() return 16 end,
    wrap = function(s) return { s } end,
}

local TextEdit = Class:extend {
    text = "",
    multiline = false,
    maxLength = false,
    numeric = false,
    wrapWidth = false,
    measure = false,

    caret = 0,
    anchor = 0,

    _chars = false,
    _lines = false,
    _preferredX = false,    -- x kept while moving Up/Down
    _keepAnchor = false,    -- set while a moveCaret operation runs
}

function TextEdit.new(class, self)
    self = Class.new(class, self)
    self.measure = self.measure or defaultMeasure
    self._chars = splitChars(self.text)
    self.text = concat(self._chars)
    local len = #self._chars
    self.caret = max(0, min(self.caret, len))
    self.anchor = max(0, min(self.anchor, len))
    return self
end

-- String helpers for owners (TextEdit:length() is the method on the model)
TextEdit.countChars = countChars
TextEdit.splitChars = splitChars

-- Layout ------------------------------------------------------------------

local function matchesAt(chars, index, piece, count)
    return concat(chars, "", index, index + count - 1) == piece
end

local function buildLines(self)
    local chars, measure = self._chars, self.measure
    local n = #chars
    local lines = {}
    local wrapWidth = self.multiline and self.wrapWidth
    local pstart = 1

    while true do
        local pend = pstart
        while pend <= n and chars[pend] ~= "\n" do
            pend = pend + 1
        end
        -- chars[pstart .. pend - 1] is the paragraph, chars[pend] its "\n"
        local paragraph = concat(chars, "", pstart, pend - 1)
        local pieces
        if wrapWidth and paragraph ~= "" then
            pieces = measure.wrap(paragraph, wrapWidth)
        end
        if not pieces or #pieces == 0 then
            pieces = { paragraph }
        end

        local firstLine = #lines + 1
        local cursor = pstart
        for i = 1, #pieces do
            local piece = pieces[i]
            local count = countChars(piece)
            if i > 1 and count > 0 then
                -- Skip characters the wrap dropped at the break (spaces)
                local c = cursor
                while c + count - 1 <= pend - 1 do
                    if matchesAt(chars, c, piece, count) then
                        cursor = c
                        break
                    end
                    c = c + 1
                end
            end
            local stop = min(cursor + count - 1, pend - 1)
            lines[#lines + 1] = {
                start = cursor,
                stop = stop,
                first = cursor - 1,
                text = concat(chars, "", cursor, stop),
            }
            cursor = stop + 1
        end

        for i = firstLine, #lines - 1 do
            lines[i].last = lines[i + 1].start - 2
        end
        lines[#lines].last = pend - 1

        if pend > n then
            break
        end
        pstart = pend + 1
    end

    local lineHeight = measure.getHeight()
    for i = 1, #lines do
        lines[i].y = (i - 1) * lineHeight
        lines[i].height = lineHeight
    end
    return lines
end

--
-- Returns the line layout: an array of
-- { start, stop, first, last, text, y, height }, where start..stop are the
-- character indices shown on the line and first..last the caret positions
-- that belong to it.
--
function TextEdit:lines()
    if not self._lines then
        self._lines = buildLines(self)
    end
    return self._lines
end

function TextEdit:lineHeight()
    return self.measure.getHeight()
end

function TextEdit:height()
    return #self:lines() * self.measure.getHeight()
end

function TextEdit:lineIndexAt(pos)
    local lines = self:lines()
    for i = 1, #lines do
        if pos <= lines[i].last then
            return i
        end
    end
    return #lines
end

-- x of a caret position on a line
local function lineX(self, line, pos)
    if pos < line.start then
        return 0
    end
    return self.measure.getWidth(concat(self._chars, "", line.start, pos))
end

-- Nearest caret position on a line for an x offset (binary search)
local function posAtX(self, line, x)
    local lo, hi = line.first, line.last
    if x <= 0 or hi <= lo then
        return lo
    end
    -- largest position whose x is at most x
    while hi - lo > 1 do
        local mid = floor((lo + hi) / 2)
        if lineX(self, line, mid) <= x then
            lo = mid
        else
            hi = mid
        end
    end
    local xlo, xhi = lineX(self, line, lo), lineX(self, line, hi)
    if xhi <= x then
        return hi
    end
    return (x - xlo <= xhi - x) and lo or hi
end

function TextEdit:caretPosAt(x, y)
    local lines = self:lines()
    local index = floor(y / self.measure.getHeight()) + 1
    index = max(1, min(index, #lines))
    return posAtX(self, lines[index], x)
end

-- Returns x, y, w, h of the caret
function TextEdit:caretRect()
    local lines = self:lines()
    local line = lines[self:lineIndexAt(self.caret)]
    return lineX(self, line, self.caret), line.y, 1, line.height
end

-- Returns an array of { x, y, w, h } covering the selection
function TextEdit:selectionRects()
    local rects = {}
    if self.caret == self.anchor then
        return rects
    end
    local s, e = self:selectionRange()
    local lines = self:lines()
    local newlineWidth = self.measure.getWidth(" ")

    for i = 1, #lines do
        local line = lines[i]
        if line.first < e and line.last >= s then
            local x1 = lineX(self, line, max(s, line.first))
            local x2
            if e > line.last then
                x2 = lineX(self, line, line.last) + newlineWidth
            else
                x2 = lineX(self, line, e)
            end
            rects[#rects + 1] = { x = x1, y = line.y, w = x2 - x1, h = line.height }
        end
    end
    return rects
end

-- Selection and caret ------------------------------------------------------

function TextEdit:length()
    return #self._chars
end

function TextEdit:hasSelection()
    return self.caret ~= self.anchor
end

-- Returns the selection as start, stop caret positions (start <= stop)
function TextEdit:selectionRange()
    if self.caret < self.anchor then
        return self.caret, self.anchor
    end
    return self.anchor, self.caret
end

function TextEdit:selectedText()
    local s, e = self:selectionRange()
    return concat(self._chars, "", s + 1, e)
end

function TextEdit:setCaretPos(pos, keepAnchor)
    pos = max(0, min(floor(pos), #self._chars))
    self.caret = pos
    if not keepAnchor then
        self.anchor = pos
    end
    self._preferredX = false
end

function TextEdit:selectAll()
    self.anchor = 0
    self.caret = #self._chars
    self._preferredX = false
end

function TextEdit:select(from, to)
    local len = #self._chars
    self.anchor = max(0, min(from, len))
    self.caret = max(0, min(to, len))
    self._preferredX = false
end

local function classAt(chars, index)
    return charClass(chars[index])
end

local function wordLeft(chars, pos)
    while pos > 0 and classAt(chars, pos) == "space" do
        pos = pos - 1
    end
    if pos > 0 then
        local class = classAt(chars, pos)
        while pos > 0 and classAt(chars, pos) == class do
            pos = pos - 1
        end
    end
    return pos
end

local function wordRight(chars, pos)
    local len = #chars
    if pos < len then
        local class = classAt(chars, pos + 1)
        while pos < len and classAt(chars, pos + 1) == class do
            pos = pos + 1
        end
    end
    while pos < len and classAt(chars, pos + 1) == "space" do
        pos = pos + 1
    end
    return pos
end

local function paragraphStart(chars, pos)
    while pos > 0 and chars[pos] ~= "\n" do
        pos = pos - 1
    end
    return pos
end

local function paragraphEnd(chars, pos)
    local len = #chars
    while pos < len and chars[pos + 1] ~= "\n" do
        pos = pos + 1
    end
    return pos
end

-- Returns first, last caret positions of the word around a position
function TextEdit:wordRangeAt(pos)
    local chars = self._chars
    local len = #chars
    if len == 0 then
        return 0, 0
    end
    pos = max(0, min(pos, len))
    local index = pos < len and pos + 1 or pos
    local class = classAt(chars, index)
    local first, last = index - 1, index
    while first > 0 and classAt(chars, first) == class do
        first = first - 1
    end
    while last < len and classAt(chars, last + 1) == class do
        last = last + 1
    end
    return first, last
end

function TextEdit:selectWordAt(pos)
    local first, last = self:wordRangeAt(pos)
    self:select(first, last)
end

-- Extends a word selection started at anchorPos towards pos, whole words
function TextEdit:extendWordSelection(anchorPos, pos)
    local a1, a2 = self:wordRangeAt(anchorPos)
    local p1, p2 = self:wordRangeAt(pos)
    if pos < anchorPos then
        self:select(a2, p1)
    else
        self:select(a1, p2)
    end
end

local operations = {}

function operations.Left(self, pos)
    if self:hasSelection() and not self._keepAnchor then
        return (self:selectionRange())
    end
    return pos - 1
end

function operations.Right(self, pos)
    if self:hasSelection() and not self._keepAnchor then
        local _, e = self:selectionRange()
        return e
    end
    return pos + 1
end

function operations.WordLeft(self, pos)
    return wordLeft(self._chars, pos)
end

function operations.WordRight(self, pos)
    return wordRight(self._chars, pos)
end

local function verticalMove(self, pos, delta)
    local lines = self:lines()
    local index = self:lineIndexAt(pos)
    local x = self._preferredX or lineX(self, lines[index], pos)
    local target = index + delta
    if target < 1 then
        return 0, x
    elseif target > #lines then
        return #self._chars, x
    end
    return posAtX(self, lines[target], x), x
end

function operations.Up(self, pos)
    return verticalMove(self, pos, -1)
end

function operations.Down(self, pos)
    return verticalMove(self, pos, 1)
end

function operations.ParagraphUp(self, pos)
    local chars = self._chars
    local start = paragraphStart(chars, pos)
    if start == pos and pos > 0 then
        start = paragraphStart(chars, pos - 1)
    end
    return start
end

function operations.ParagraphDown(self, pos)
    local chars = self._chars
    local stop = paragraphEnd(chars, pos)
    if stop == pos and pos < #chars then
        stop = paragraphEnd(chars, pos + 1)
    end
    return stop
end

function operations.Start(self, pos)
    return 0
end

function operations.End(self, pos)
    return #self._chars
end

function operations.StartOfLine(self, pos)
    return self:lines()[self:lineIndexAt(pos)].first
end

function operations.EndOfLine(self, pos)
    return self:lines()[self:lineIndexAt(pos)].last
end

--
-- Moves the caret by a named operation: Left, Right, WordLeft, WordRight,
-- Up, Down, ParagraphUp, ParagraphDown, Start, End, StartOfLine, EndOfLine.
-- With keepAnchor the anchor stays where it is, extending the selection.
--
function TextEdit:moveCaret(operation, keepAnchor)
    local op = operations[operation]
    assert(op, "Unknown caret operation: " .. tostring(operation))
    self._keepAnchor = keepAnchor or false
    local pos, preferredX = op(self, self.caret)
    self._keepAnchor = false
    self:setCaretPos(pos, keepAnchor)
    self._preferredX = preferredX or false
end

-- Editing ------------------------------------------------------------------

local function textChanged(self)
    self.text = concat(self._chars)
    self._lines = false
    self._preferredX = false
end

-- Replaces characters s+1..e by the given array of characters
local function splice(self, s, e, insert)
    local chars = self._chars
    local result = {}
    for i = 1, s do
        result[#result + 1] = chars[i]
    end
    for i = 1, #insert do
        result[#result + 1] = insert[i]
    end
    for i = e + 1, #chars do
        result[#result + 1] = chars[i]
    end
    self._chars = result
    textChanged(self)
end

function TextEdit:setText(text)
    self._chars = splitChars(text or "")
    textChanged(self)
    local len = #self._chars
    self.caret = min(self.caret, len)
    self.anchor = min(self.anchor, len)
end

-- Filters text for insertion and applies maxLength; returns chars, s, e
local function prepareInsert(self, text)
    text = text:gsub("\r\n", "\n"):gsub("\r", "\n")
    if not self.multiline then
        text = text:gsub("\n", " ")
    end
    if self.numeric then
        text = text:gsub("%D", "")
    end
    local insert = splitChars(text)
    local s, e = self:selectionRange()
    if self.maxLength then
        local room = self.maxLength - (#self._chars - (e - s))
        room = max(room, 0)
        while #insert > room do
            insert[#insert] = nil
        end
    end
    return insert, s, e
end

-- Returns what the text would be after insert(text), without changing it
function TextEdit:insertTest(text)
    local insert, s, e = prepareInsert(self, text)
    local chars = self._chars
    return concat(chars, "", 1, s) .. concat(insert) .. concat(chars, "", e + 1, #chars)
end

--
-- Inserts text at the caret, replacing the selection. Newlines are turned
-- into spaces unless multiline, non digits are dropped when numeric, and
-- maxLength is respected. Returns true when the text changed.
--
function TextEdit:insert(text)
    local insert, s, e = prepareInsert(self, text)
    if #insert == 0 then
        return false
    end
    splice(self, s, e, insert)
    self.caret = s + #insert
    self.anchor = self.caret
    return true
end

function TextEdit:deleteRange(s, e)
    if s == e then
        return false
    end
    splice(self, s, e, {})
    self.caret = s
    self.anchor = s
    return true
end

function TextEdit:deleteSelection()
    return self:deleteRange(self:selectionRange())
end

function TextEdit:deleteForward()
    if self:hasSelection() then
        return self:deleteSelection()
    elseif self.caret < #self._chars then
        return self:deleteRange(self.caret, self.caret + 1)
    end
    return false
end

function TextEdit:deleteBackward()
    if self:hasSelection() then
        return self:deleteSelection()
    elseif self.caret > 0 then
        return self:deleteRange(self.caret - 1, self.caret)
    end
    return false
end

-- Clipboard helpers take an object { get = function() end, set = function(s) end }

function TextEdit:copy(clipboard)
    if not self:hasSelection() then
        return false
    end
    clipboard.set(self:selectedText())
    return true
end

function TextEdit:cut(clipboard)
    if self:copy(clipboard) then
        return self:deleteSelection()
    end
    return false
end

function TextEdit:paste(clipboard)
    local text = clipboard.get()
    if type(text) == "string" and text ~= "" then
        return self:insert(text)
    end
    return false
end

-- Configuration ------------------------------------------------------------

function TextEdit:setMeasure(measure)
    self.measure = measure or defaultMeasure
    self._lines = false
    self._preferredX = false
end

function TextEdit:setMultiline(multiline)
    multiline = multiline and true or false
    if self.multiline ~= multiline then
        self.multiline = multiline
        self._lines = false
    end
end

function TextEdit:setWrapWidth(wrapWidth)
    wrapWidth = wrapWidth or false
    if self.wrapWidth ~= wrapWidth then
        self.wrapWidth = wrapWidth
        self._lines = false
    end
end

function TextEdit:setMaxLength(maxLength)
    self.maxLength = maxLength or false
end

function TextEdit:setNumeric(numeric)
    self.numeric = numeric and true or false
end

function TextEdit:invalidate()
    self._lines = false
end

return TextEdit
