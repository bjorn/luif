--
-- A multi-line text field that supports scrolling
--

local core = require "luif.core"

local TextArea = core.SkinnableItem:extend {
    text = "",
    readonly = false,
    skinClass = core.skins.DefaultTextAreaSkin,
    skinParts = { "textInput" },

    paddingRight = false,
    paddingBottom = false,

    textChange = false, --function(text)
    specialPress = false, --function(key)
}

function TextArea.new(class, self)
    self = core.SkinnableItem.new(class, self)

    assert(self.textInput)
    self.paddingRight = self.paddingRight or self.skin.paddingRight or class.paddingRight or 0
    self.paddingBottom = self.paddingBottom or self.skin.paddingBottom or class.paddingBottom or 0

    self.textInput:setReadonly(self.readonly or class.readonly)
    self.textInput:setMultiline(true)
    self.textInput:setText(self.text)
    self.textInput.textChange = function(text)
        self.text = text
        if self.textChange then
            self.textChange(text)
        end
    end
    self.textInput.specialPress = function(key) self:emit("specialPress", key) end

    local function applySize(width, height)
        local textInput = self.textInput
        textInput.label:setWidth(width - self.paddingRight - textInput.paddingLeft -
                                 textInput.paddingRight)
        textInput:setMinimumSize(width - self.paddingRight, height - self.paddingBottom)
        textInput:onTextSizeChange()
    end

    self:on("resize", applySize)
    applySize(self:size())

    return self
end

function TextArea:setText(text)
    self.text = text
    self.textInput:setText(text)
end

function TextArea:selectAll()
    self.textInput:selectAll()
end

function TextArea:setFocus(focus)
    self.textInput:setFocus(focus)
end

return TextArea
