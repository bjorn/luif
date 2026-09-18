--
-- A slider that allows to change a value bound by a range.
--
local core = require "luif.core"
local MouseButton = core.MouseButton
local SkinnableItem   = core.SkinnableItem
local DefaultSliderSkin = core.skins.DefaultSliderSkin

local Math              = core.Math

local Sounds            = core.Sounds

local Slider = SkinnableItem:extend {
    value = 0,
    minimum = 0,
    maximum = 100,

    skinClass = DefaultSliderSkin,

    mouseEnabled = true,
    mousePressed = false,
    decimals = 0,

    clickSound = Sounds.UI.Click,
    releaseSound = false,

    change = false, -- function(value, user): the value is changed
                    -- ('user' is true when changed by user, rather than code)

    state = "normal",
    skinParts = { "trackbar", "handle", "valueLabel", "incrementButton", "decrementButton" },

    tickInterval = 50,

    _handleOffset = 0,
    _handleHasValueLabel = false,
    _labelContainer = false,

}

function Slider.new(class, self)
    self = SkinnableItem.new(class, self)

    assert(self.trackbar, "Slider requires trackbar skin part")

    self.value = Math.clamp(self.value, self.minimum, self.maximum)

    if self.incrementButton then
        self.incrementButton.clickSound = self.clickSound
        self.incrementButton:setEnabled(self.enabled)
        self.incrementButton:on("press", function()
            self:increment()
            self.handle:setState("down")
        end)
        self.incrementButton:on("release", function()
            self:playReleaseSound()
            self.handle:setState("up")
        end)
        self.incrementButton.tick = function()
            self:increment()
        end
        self.incrementButton.tickInterval = self.tickInterval
    end
    if self.decrementButton then
        self.decrementButton.clickSound = self.clickSound
        self.decrementButton:setEnabled(self.enabled)
        self.decrementButton:on("press", function()
            self:decrement()
            self.handle:setState("down")
        end)
        self.decrementButton:on("release", function()
            self:playReleaseSound()
            self.handle:setState("up")
        end)
        self.decrementButton.tick = function()
            self:decrement()
        end
        self.decrementButton.tickInterval = self.tickInterval
    end

    if not self.enabled then
        self:setState("disabled")
    end

    if self.handle:as(core.ThumbButton) then
        self.handle.clickSound = self.clickSound
        self.handle:on("moveMouse", function(x,y)
            local selfX = self:absolutePos()
            self:updateValue(x-selfX)
        end)
        self.handle:connect("release", self, self.playReleaseSound)
    end

    if self.handle.skin and self.handle.skin.valueLabel then
        self.valueLabel = self.handle.skin.valueLabel
        if self.handle.skin.labelContainer then
            self._labelContainer = self.handle.skin.labelContainer
        end
        self._handleHasValueLabel = true
    end

    if self._handleHasValueLabel then
        if self._labelContainer then
            self._labelContainer.showEffect = core.Fade { duration = 500, to = 255, ease = core.Ease.outCubic }
            self._labelContainer.hideEffect = core.Fade { duration = 500, to = 0, ease = core.Ease.outCubic }
            self._labelContainer:setVisible(false)
        else
            self.valueLabel:setVisible(false)
        end
    end

    self:updateHandlePosition()
    self:updateValueLabel()

    return self
end

function Slider:setEnabled(enabled)
    SkinnableItem.setEnabled(self, enabled)

    if self.incrementButton then
        self.incrementButton:setEnabled(enabled)
    end
    if self.decrementButton then
        self.decrementButton:setEnabled(enabled)
    end

    if not self.enabled then
        self:setState("disabled")
    elseif self.state == "disabled" then
        self:setState("normal")
    end
end

function Slider:setSize(width, height)
    SkinnableItem.setSize(self, width, height)
    self:updateHandlePosition()
end

function Slider:setValue(value, user)
    value = Math.clamp(value, self.minimum, self.maximum)

    local eq = self.value == value

    self.value = value
    self:updateHandlePosition()

    if not eq then
        self:updateValueLabel()
        self:emit('change', self.value, user)
    end
end

function Slider:setMaximum(maximum)
    self.maximum = maximum
    self:setValue(self.value)
end

function Slider:setMinimum(minimum)
    self.minimum = minimum
    self:setValue(self.value)
end

function Slider:setHandleTransitions(transitionsHandle)
    if self.handle.skin then
        self.handle.skin.transitions = transitionsHandle
    end
end

function Slider:setDecrementButtonTransitions(transitionsDecrementButton)
    if self.decrementButton and self.decrementButton.skin then
        self.decrementButton.skin.transitions = transitionsDecrementButton
    end
end

function Slider:setIncrementButtonTransitions(transitionsIncrementButton)
    if self.incrementButton and self.incrementButton.skin then
        self.incrementButton.skin.transitions = transitionsIncrementButton
    end
end

function Slider:setClickSound(clickSound)
    self.clickSound = clickSound

    if self.incrementButton then
        self.incrementButton.clickSound = self.clickSound
    end
    if self.decrementButton then
        self.decrementButton.clickSound = self.clickSound
    end
    if self.handle:as(core.ThumbButton) then
        self.handle.clickSound = self.clickSound
    end
end

function Slider:setReleaseSound(releaseSound)
    self.releaseSound = releaseSound
end

function Slider:mousePress(event)
    if not self.enabled or event:button() ~= MouseButton.Left then
        event:ignore()
        return
    end
    self.mousePressed = true
    self:updateValue(event:x())
    self.handle:setState("down")
end

function Slider:mouseRelease(event)
    if not self.enabled or event:button() ~= MouseButton.Left then
        event:ignore()
        return
    end

    self.mousePressed = false
    self.handle:setState("up")

    self:playReleaseSound()
end

function Slider:mouseMove(event)
    if not self.mousePressed or not self.enabled then
        event:ignore()
        return
    end

    self:updateValue(event:x())
end

function Slider:updateValue(x)
    local width, height = self.trackbar:size()
    local ratio = (x - self.trackbar.x) / width
    local value = self.minimum + ratio * (self.maximum - self.minimum)

    -- Round to shown decimal
    local precisionFactor = 10 ^ (tonumber(self.decimals) or 0)
    value = math.floor(value * precisionFactor + 0.5) / precisionFactor

    self:setValue(value, true)
end

function Slider:updateHandlePosition()
    local width, height = self.trackbar:size()
    local handleWidth, handleHeight = self.handle:size()
    local steps = self.maximum - self.minimum
    local ratio = steps == 0 and 0 or (self.value - self.minimum) / steps

    self.handle:setPos(self.trackbar.x + math.floor(ratio * width) - handleWidth/2, self.handle.y)
end

function Slider:updateValueLabel()
    if self.valueLabel then
        self.valueLabel:setText(string.format("%." .. (tonumber(self.decimals) or 0) .. "f", self.value))
    end
end

function Slider:tryGetValueFromLabel()
    return self.valueLabel and tonumber(self.valueLabel.text) or false
end

function Slider:increment()
    local amount = 1 / 10 ^ (tonumber(self.decimals) or 0)
    self:setValue(self.value + amount, true)
end

function Slider:decrement()
    local amount = 1 / 10 ^ (tonumber(self.decimals) or 0)
    self:setValue(self.value - amount, true)
end

function Slider:mouseEnter(event)
    if self.state == "normal" then
        self:setState("over")
    end
    if self._labelContainer then
        self._labelContainer:setVisible(true)
    elseif self._handleHasValueLabel then
        self.valueLabel:setVisible(true)
    end
end

function Slider:mouseLeave(event)
    if self.state == "over" then
        self:setState("normal")
    end
    if self._labelContainer then
        self._labelContainer:setVisible(false)
    elseif self._handleHasValueLabel then
        self.valueLabel:setVisible(false)
    end
end

function Slider:playReleaseSound()
    if self.releaseSound then
        Sounds.play(self.releaseSound)
    end
end

return Slider
