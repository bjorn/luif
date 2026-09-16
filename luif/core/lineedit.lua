--
-- A text field for single lines only, based on text input
--

local core = require "luif.core"

local LineEdit = core.SkinnableItem:extend {
    skinClass = core.skins.DefaultLineEditSkin,
    obfuscate = false,
    text = "",
    placeholderText = "",
    numeric = false,
    maxLength = false,

    textChange = false,     -- function(text): called when the text changes
    returnPress = false,    -- function(): called when Return is pressed
    specialPress = false,   -- function(key): called for keys the text input passes on, such as tab

    skinParts = { "placeholderLabel", "textInput" },
    state = "normal"
}

function LineEdit.new(class, self)
    self.layout = core.AnchorLayout {}

    self = core.SkinnableItem.new(class, self)

    assert(self.textInput)
    self.paddingRight = self.paddingRight or self.skin.paddingRight or class.paddingRight or 0
    self.paddingBottom = self.paddingBottom or self.skin.paddingBottom or class.paddingBottom or 0

    self.textInput:setNumeric(self.numeric)
    self.textInput:setMaxLength(self.maxLength)
    self.textInput:setMultiline(false)
    self.textInput:setObfuscate(self.obfuscate)
    self.textInput:setClip(true)
    self.textInput:setText(self.text)
    self.textInput.textChange = function(text)
        self.text = text
        if self.placeholderLabel then
            self.placeholderLabel:setVisible(text == "")
        end
        self:emit("textChange", text)
    end
    self.textInput.returnPress = function() self:emit("returnPress") end
    self.textInput.specialPress = function(keyCode) self:emit("specialPress", keyCode) end
    self.textInput.stateChanged = function(newState) self:setState(newState) end

    self.textInput:setColor(self.skin.textColor)
    self:setState(self.state or class.state)
    if self.placeholderLabel then
        self.placeholderLabel:setText(self.placeholderText)
    end

    if not self.enabled then
        self:setEnabled(self.enabled)
    end

    return self
end

function LineEdit:setText(text)
    self.textInput:setText(text)
end

function LineEdit:setPlaceholderText(text)
    self.placeholderText = text
    if self.placeholderLabel then
        self.placeholderLabel:setText(text)
    end
end

-- LineEdit is a focus proxy to its text input
function LineEdit:setFocus(focus)
    self.textInput:setFocus(focus)
end

function LineEdit:hasFocus()
    return self.textInput:hasFocus()
end

function LineEdit:selectAll()
    self.textInput:selectAll()
end

--
-- Scrolls the label horizontally so that the caret stays inside the text
-- input. x is the caret position relative to the label plus textInput.x.
--
function LineEdit:ensureVisible(x, y, w, h, xmargin, ymargin)
    local textInput = self.textInput
    local label = textInput.label

    local left = textInput.paddingLeft
    local width = textInput:size() - left - textInput.paddingRight
    local right = left + width

    x = x - textInput.x

    local labelWidth = math.floor(label:size())
    local newX = label.x

    if labelWidth <= width then
        -- Everything fits, no scrolling needed
        newX = left
    else
        local cursor = x + newX
        if cursor < left then
            newX = left - x
        elseif cursor >= right then
            newX = right - x
        end

        -- Do not leave empty space on the right, e.g. after deleting text
        if newX + labelWidth < right then
            newX = right - labelWidth
        end
    end

    if newX ~= label.x then
        label:setX(newX)
    end
end

function LineEdit:setEnabled(enabled)
    core.SkinnableItem.setEnabled(self, enabled)
    self.textInput:setEnabled(enabled)
end

return LineEdit

