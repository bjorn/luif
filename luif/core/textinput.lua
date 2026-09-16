--
-- A text input item. The text, caret and selection live in a
-- core.TextEdit model; the text is shown by a Label and the caret and
-- selection are drawn with Rectangle items (fill nodes).
--

local core = require "luif.core"

local FontDb   = core.FontDb
local TextEdit = core.TextEdit
local Sync     = core.Sync

local Host = core.Host
local Keys = core.Keys
local MouseButton = core.MouseButton

local Update = core.Update

local CARET_BLINK_TIME = 1000
local BULLET = "\226\128\162"   -- U+2022, what an obfuscated label shows

local TextInput = core.Item:extend {
    width = 200,
    height = 40,

    color = core.Color.black,
    highlightColor = 0xFF3399FF,
    font = false,
    fontScale = false,
    readonly = false,

    mouseEnabled = true,
    multiline = true,
    obfuscate = false,

    paddingLeft = 0,
    paddingRight = 0,
    paddingTop = 0,
    paddingBottom = 0,

    numeric = false,
    maxValue = false,
    maxLength = false,

    text = "",

    state = "normal",

    textChange = false,     -- function(text): called when the text changes
    returnPress = false,    -- function(): called when Return is pressed
    specialPress = false,   -- function(key): called with the key name of keys the input does not handle

    edit = false,           -- the core.TextEdit model
    label = false,
    caret = false,

    _selectionRects = false,
    _stateBeforeDisable = "normal",
    _selecting = false,
    _doubleClicking = false,
    _clickAnchor = false,
    _caretTimeout = false,
    _caretVisible = true,
    _measureKey = false,
}

local clipboard = {
    get = function() return Host.get().getClipboard() end,
    set = function(text) Host.get().setClipboard(text) end,
}

-- Measurement matching what the label draws (font, text scale, obfuscation),
-- through the host the label measures with
local function createMeasure(self)
    local function display(s)
        if self.label.obfuscate then
            return BULLET:rep(TextEdit.countChars(s))
        end
        return s
    end

    return {
        getWidth = function(s)
            local label = self.label
            return Sync.host(label).textWidth(label.font, display(s)) * label.textScale
        end,
        getHeight = function()
            local label = self.label
            return Sync.host(label).lineHeight(label.font) * label.textScale
        end,
        wrap = function(s, width)
            local label = self.label
            local _, lines = Sync.host(label).wrapText(label.font, display(s), width / label.textScale)
            if label.obfuscate then
                -- Map the bullet lines back onto the original characters
                local chars, index = TextEdit.splitChars(s), 1
                for i = 1, #lines do
                    local count = TextEdit.countChars(lines[i])
                    lines[i] = table.concat(chars, "", index, index + count - 1)
                    index = index + count
                end
            end
            return lines
        end,
    }
end

-- Copies the item configuration into the model. Fields may be assigned
-- directly by owners (LineEdit sets multiline), so this runs before use.
local function syncModel(self)
    local edit, label = self.edit, self.label
    edit:setMultiline(self.multiline)
    edit:setNumeric(self.numeric)
    edit:setMaxLength(self.maxLength)
    edit:setWrapWidth(self.multiline and label.wrap and (label.wrappingWidth or label.width))

    local key = tostring(label.font) .. "|" .. tostring(label.textScale) .. "|" ..
                tostring(label.obfuscate)
    if key ~= self._measureKey then
        self._measureKey = key
        edit:invalidate()
    end
end

function TextInput.new(class, self)
    self.layout = core.AnchorLayout {}

    local color = self.color or class.color
    local multiline = self.multiline
    if multiline == nil then
        multiline = class.multiline
    end

    self.label = core.Label {
        x = self.paddingLeft or class.paddingLeft,
        y = self.paddingTop or class.paddingTop,
        text = self.text or class.text,
        wrap = multiline and true or false,
        color = color,
        font = self.font or class.font,
        textScale = self.fontScale or class.fontScale or 1,
        obfuscate = self.obfuscate or class.obfuscate,
    }

    self.caret = core.Rectangle {
        width = 1,
        height = 1,
        color = color,
        visible = false,
    }

    self.children = {
        self.label,
        self.caret,
    }

    self = core.Item.new(class, self)

    self._selectionRects = {}
    self.edit = TextEdit {
        text = self.text,
        multiline = self.multiline,
        numeric = self.numeric,
        maxLength = self.maxLength,
        measure = createMeasure(self),
    }
    self.text = self.edit.text

    self:on("resize", function(width, height)
        self:onTextSizeChange()
    end)

    self:onTextSizeChange()

    return self
end

function TextInput:attached()
    self:setCaretPos(0, false)
end

function TextInput:delete()
    if self._caretTimeout then
        Update:clearTimeout(self._caretTimeout)
        self._caretTimeout = false
    end
    core.Item.delete(self)
end

function TextInput:setColor(color)
    self.color = color
    self.label:setColor(color)
    self.caret:setColor(color)
end

function TextInput:setHighlightColor(color)
    self.highlightColor = color
    for i = 1, #self._selectionRects do
        self._selectionRects[i]:setColor(color)
    end
end

function TextInput:setFont(font)
    self.font = font
    self.label:setFont(font)
    self:onTextSizeChange()
end

function TextInput:setText(text)
    self.edit:setText(tostring(text or ""))
    self:onTextChange()
end

function TextInput:setMultiline(multiline)
    self.multiline = multiline and true or false
    self.label:setWrap(self.multiline)
    self:onTextSizeChange()
end

function TextInput:setObfuscate(obfuscate)
    self.obfuscate = obfuscate and true or false
    self.label:setObfuscate(self.obfuscate)
    self:onTextSizeChange()
end

function TextInput:setMaxLength(maxLength)
    self.maxLength = maxLength or false
end

function TextInput:setNumeric(numeric)
    self.numeric = numeric and true or false
end

function TextInput:setReadonly(readonly)
    self.readonly = readonly and true or false
    self:updateCaret()
end

function TextInput:focusGain()
    self:setState("focused")
    self:setCaretVisible(true)
    core.Item.focusGain(self)
end

function TextInput:focusLose()
    self:setState("normal")
    if self._caretTimeout then
        Update:clearTimeout(self._caretTimeout)
        self._caretTimeout = false
    end
    self:moveCaret("End", false)
end

local ignoreKeys = { lshift = true, rshift = true }
for i = 1, 15 do
    ignoreKeys["f" .. i] = true
end

function TextInput:keyPress(event)
    local key = event:key()

    local ctrl = event:controlDown()
    local shift = event:shiftDown()
    local makeCaretVisible = true
    local edit = self.edit

    syncModel(self)

    if key == "delete" and shift and not ctrl then
        -- Cut
        if not self.readonly and edit:cut(clipboard) then
            self:onTextChange()
        end
    elseif key == "delete" then
        if not self.readonly then
            if ctrl and not edit:hasSelection() then
                edit:moveCaret("WordRight", true)
            end
            if edit:deleteForward() then
                self:onTextChange()
            end
        end
    elseif key == "backspace" then
        if not self.readonly then
            if ctrl and not edit:hasSelection() then
                edit:moveCaret("WordLeft", true)
            end
            if edit:deleteBackward() then
                self:onTextChange()
            end
        end
    elseif key == "left" then
        self:moveCaret(ctrl and "WordLeft" or "Left", shift)
    elseif key == "right" then
        self:moveCaret(ctrl and "WordRight" or "Right", shift)
    elseif key == "up" then
        if self.multiline then
            self:moveCaret(ctrl and "ParagraphUp" or "Up", shift)
        else
            self:emit("specialPress", key)
        end
    elseif key == "down" then
        if self.multiline then
            self:moveCaret(ctrl and "ParagraphDown" or "Down", shift)
        else
            self:emit("specialPress", key)
        end
    elseif key == "home" then
        self:moveCaret(ctrl and "Start" or "StartOfLine", shift)
    elseif key == "end" then
        self:moveCaret(ctrl and "End" or "EndOfLine", shift)
    elseif key == "escape" then
        self:emit("specialPress", key)
        self:setFocus(false)
    elseif ctrl and key == "a" then
        self:selectAll()
    elseif ctrl and key == "x" then
        -- Cut
        if not self.readonly and edit:cut(clipboard) then
            self:onTextChange()
        end
    elseif ctrl and (key == "c" or key == "insert") then
        -- Copy
        edit:copy(clipboard)
    elseif (ctrl and key == "v") or (shift and key == "insert") then
        -- Paste
        if not self.readonly and not self.numeric and edit:paste(clipboard) then
            self:onTextChange()
        end
    elseif Keys.isReturn(key) and not self.multiline then
        self:emit("returnPress")
    elseif key == "tab" then
        self:emit("specialPress", key)
    else
        makeCaretVisible = false

        -- Pass on shortcuts and keys that do not edit text
        if ctrl or ignoreKeys[key] then
            event:ignore()
        end
    end

    if makeCaretVisible then
        self:setCaretVisible(true)
    end
end

function TextInput:keyCharacter(event)
    if self.readonly or not self.enabled then
        return
    end

    local text = event:text()
    if not text then
        return
    end

    if text == "\r" or text == "\n" then
        if not self.multiline then
            return
        end
        text = "\n"
    elseif not Keys.isPrintable(text) then
        return
    end

    syncModel(self)
    local edit = self.edit

    if self.numeric then
        if not text:match("^%d+$") then
            return
        end
        local number = tonumber(edit:insertTest(text))
        if self.maxValue and number and number > self.maxValue then
            return
        end
    end

    if edit:insert(text) then
        self:setCaretVisible(true)
        self:onTextChange()
    end
end

function TextInput:mouseEnter(event)
    if self.state == "normal" then
        self:setState("over")
    end
    event:ignore()
end

function TextInput:mouseLeave(event)
    if self.state == "over" then
        self:setState("normal")
    end
    event:ignore()
end

-- Caret position under a point in item coordinates
function TextInput:caretPosAt(x, y)
    syncModel(self)
    local label = self.label
    if not self.multiline then
        y = label.y
    end
    return self.edit:caretPosAt(x - label.x, y - label.y)
end

function TextInput:mousePress(event)
    if event:button() == MouseButton.Middle then
        event:ignore()
        return
    end

    self:setFocus()

    local caretPos = self:caretPosAt(event:x(), event:y())

    self._selecting = event:button() == MouseButton.Left
    local keepAnchor = self._selecting and event:shiftDown()
    self:setCaretPos(caretPos, keepAnchor)
end

function TextInput:mouseRelease(event)
    if event:button() == MouseButton.Middle then
        event:ignore()
        return
    end

    self._doubleClicking = false
    self._selecting = false
end

function TextInput:mouseDoubleClick(event)
    if event:button() ~= MouseButton.Left then
        return
    end

    local caretPos = self:caretPosAt(event:x(), event:y())

    self._doubleClicking = true
    self._selecting = false
    self._clickAnchor = caretPos

    self.edit:selectWordAt(caretPos)
    self:updateCaret()
end

function TextInput:mouseMove(event)
    if self._selecting then
        self:setCaretPos(self:caretPosAt(event:x(), event:y()), true)
    elseif self._doubleClicking then
        self.edit:extendWordSelection(self._clickAnchor, self:caretPosAt(event:x(), event:y()))
        self:updateCaret()
    else
        event:ignore()
    end
end

function TextInput:onTextChange()
    self.text = self.edit.text
    self.label:setText(self.text)

    self:emit("textChange", self.text)
    self:onTextSizeChange()
end

function TextInput:onTextSizeChange()
    syncModel(self)

    if self.multiline then
        local h = self.edit:height() + self.paddingTop + self.paddingBottom
        self:setHeight(math.max(self.minimumHeight, h))
    end
    self:updateCaret()
end

function TextInput:setState(state, animate)
    if self.state == state then
        return
    end

    if not self.enabled then
        self._stateBeforeDisable = state
        return
    end

    core.Item.setState(self, state, animate)
    self:updateCaretVisibility()
end

function TextInput:blinkCaret()
    self._caretTimeout = false
    self:setCaretVisible(not self._caretVisible)
end

function TextInput:ensureCaretVisible()
    syncModel(self)
    local x, y, w, h = self.edit:caretRect()
    self:ensureVisible(x, y, w, h, 2, 2)
end

-- Scrolls the caret into view and places the caret and selection rectangles
function TextInput:updateCaret()
    self:ensureCaretVisible()

    local edit, label = self.edit, self.label
    local ox, oy = label.x, label.y

    local x, y, _, h = edit:caretRect()
    self.caret:setPos(math.floor(ox + x), oy + y)
    self.caret:setSize(1, h)
    self:updateCaretVisibility()

    local rects = edit:selectionRects()
    local pool = self._selectionRects
    for i = #pool + 1, #rects do
        self:addSelectionRect()
    end
    for i = 1, #pool do
        local box, rect = pool[i], rects[i]
        if rect then
            box:setPos(ox + rect.x, oy + rect.y)
            box:setSize(rect.w, rect.h)
            box:setVisible(true)
        else
            box:setVisible(false)
        end
    end
end

-- Adds a pooled selection rectangle, drawn below the label
function TextInput:addSelectionRect()
    local rect = core.Rectangle {
        color = self.highlightColor,
        alpha = 128,
        width = 0,
        height = 0,
        visible = false,
    }
    local pool = self._selectionRects
    pool[#pool + 1] = rect

    -- Children draw in order: before the label, below the text and caret
    local index = core.Array.find(self.children, self.label)
    self:insertChild(index, rect)
    return rect
end

function TextInput:updateCaretVisibility()
    self.caret:setVisible(self.state == "focused" and not self.readonly and
                          self.enabled and self._caretVisible and true or false)
end

function TextInput:setCaretPos(caretPos, keepAnchor)
    syncModel(self)
    self.edit:setCaretPos(caretPos, keepAnchor or false)
    self:updateCaret()
end

function TextInput:moveCaret(operation, keepAnchor)
    syncModel(self)
    self.edit:moveCaret(operation, keepAnchor or false)
    self:updateCaret()
end

function TextInput:setCaretVisible(visible)
    self._caretVisible = visible
    self:updateCaretVisibility()

    -- Restart the caret blink timeout
    if self._caretTimeout then
        Update:clearTimeout(self._caretTimeout)
        self._caretTimeout = false
    end
    if not self.readonly and self.enabled and self.state == "focused" then
        self._caretTimeout = Update:setTimeout(CARET_BLINK_TIME / 2, function()
            self:blinkCaret()
        end)
    end
end

function TextInput:setEnabled(enabled)
    if self.enabled == enabled then
        return
    end

    if self.enabled then
        self:setState("disabled")
    end

    core.Item.setEnabled(self, enabled)

    if self.enabled and self._stateBeforeDisable == "focused" then
        self:focusGain()
    elseif self.enabled then
        self:setState(self._stateBeforeDisable)
    end
    self:updateCaretVisibility()
end

function TextInput:selectAll()
    self:moveCaret("Start", false)
    self:moveCaret("End", true)
end

function TextInput:selectedText()
    return self.edit:selectedText()
end

function TextInput:hasSelection()
    return self.edit:hasSelection()
end

function TextInput:caretPos()
    return self.edit.caret
end

return TextInput
