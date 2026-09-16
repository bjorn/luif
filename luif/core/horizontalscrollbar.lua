--
-- A horizontal scrollbar: a thumb button on a track, usually between a left
-- and a right button. The position is the thumb's x within the scrollbar and
-- runs from minScroll to maxScroll, which follow the laid out track. With
-- snap, the thumb rests on one of maxValue evenly spaced steps.
--

local core = require "luif.core"
local MouseButton = core.MouseButton

local Math = core.Math

local HorizontalScrollbar = core.SkinnableItem:extend {
    mouseEnabled = true,
    mousePressed = false,
    mouseOffset = 0,
    minScroll = 0,
    maxScroll = 0,
    valueChanged = false, -- function(actuallyChanged, relativePosition)
    thumbAnimation = false,
    animate = true,     -- animate the thumb when scrolling with buttons or the wheel
    stepSize = 1,
    maxValue = 10,
    snap = true,
    position = 0,
    skinClass = core.skins.DefaultHorizontalScrollbarSkin,
    skinParts = { "trackbar", "thumbButton", "rightButton", "leftButton" },
}

function HorizontalScrollbar.new(class, self)
    self = core.SkinnableItem.new(class, self)

    assert(self.trackbar and self.thumbButton,
           "a HorizontalScrollbar skin needs a trackbar and a thumbButton")

    self.thumbAnimation = core.Animate {
        target = self.thumbButton, property = "x", to = self.thumbButton.x,
        ease = core.Ease.outCubic, duration = 300,
    }

    if self.thumbButton:as(core.ThumbButton) then
        self.thumbButton:on("moveMouse", function(x,y) self:onMoveMouse(x,y) end)
        self.thumbButton:on("press", function() self:onThumbPress() end)
        self.thumbButton:on("release", function() self:onThumbRelease() end)
    end

    if self.leftButton then
        self.leftButton:setEnabled(self.enabled)
        self.leftButton:on("press", function()
            self:decreaseScroll()
        end)
    end

    if self.rightButton then
        self.rightButton:setEnabled(self.enabled)
        self.rightButton:on("press", function()
            self:increaseScroll()
        end)
    end

    -- The track only gets its final geometry from the skin's layout
    local function trackChanged()
        self:updateThumbWidth()
        self:updateThumbPosition(false)
    end
    self.trackbar:on("resize", trackChanged)
    self.trackbar:on("move", trackChanged)

    self:updateThumbWidth()
    self:updateThumbPosition(false)

    return self
end

function HorizontalScrollbar:setEnabled(enabled)
    core.SkinnableItem.setEnabled(self, enabled)

    if self.leftButton then
        self.leftButton:setEnabled(enabled)
    end
    if self.rightButton then
        self.rightButton:setEnabled(enabled)
    end

    if not self.enabled then
        self:setState("disabled")
    elseif self.state == "disabled" then
        self:setState("normal")
    end
end

function HorizontalScrollbar:mousePress(event)
end

-- The drag offset is kept in virtual units, the units in which the thumb
-- reports mouse moves.
function HorizontalScrollbar:onThumbPress()
    if not self.enabled then
        return
    end

    local mx = core.Pointer.position()
    self.mouseOffset = mx - self.thumbButton.x
    self.mousePressed = true
end

function HorizontalScrollbar:mouseDoubleClick(event)
    return self:mousePress(event)
end

function HorizontalScrollbar:mouseRelease(event)
    if not self.mousePressed or event:button() ~= MouseButton.Left then
        event:ignore()
        return
    end

    self.mousePressed = false
end

function HorizontalScrollbar:onThumbRelease()
    self.mousePressed = false
    if self.snap then
        self:setValue(self.position, true, true)
    end
end

function HorizontalScrollbar:mouseMove(event)
    if not self.mousePressed or not self.enabled then
        event:ignore()
        return
    end

    local x = event:absolutePos()
    self:setThumbPosition(x - self.mouseOffset)
end

function HorizontalScrollbar:onMoveMouse(x, y)
    if not self.mousePressed or not self.enabled then
        return
    end
    self:setThumbPosition(x - self.mouseOffset)
end

function HorizontalScrollbar:mouseWheel(event)
    if event:value() > 0 then
        self:increaseScroll()
    else
        self:decreaseScroll()
    end
end

-- The position as a fraction of the range, from 0 to 1
function HorizontalScrollbar:relativePosition()
    local range = self.maxScroll - self.minScroll
    return range > 0 and (self.position - self.minScroll) / range or 0
end

-- The distance between two snap steps
function HorizontalScrollbar:segmentWidth()
    return (self.maxScroll - self.minScroll) / math.max(1, self.maxValue - 1)
end

-- Recomputes the range from the track and the thumb, keeping the relative
-- position.
function HorizontalScrollbar:updateRange()
    local ratio = self:relativePosition()
    self.minScroll = self.trackbar.x
    self.maxScroll = math.max(self.minScroll,
                              self.trackbar.x + self.trackbar.width - self.thumbButton.width)
    self.position = self.minScroll + ratio * (self.maxScroll - self.minScroll)
end

function HorizontalScrollbar:updateThumbPosition(smooth)
    smooth = self.animate and ((smooth == nil) or smooth)

    local x = self.position

    if smooth then
        self.thumbAnimation.to = x
        self.thumbAnimation:setDuration(300)
        self:start("thumb", self.thumbAnimation)
    else
        self:stop("thumb")
        self.thumbButton:setX(x)
    end
end

function HorizontalScrollbar:updateThumbWidth()
    local trackWidth = self.trackbar:size()

    local w = math.max(self.skin.minThumbWidth or 10, trackWidth / self.maxValue)
    self.thumbButton:setWidth(w)

    self:updateRange()
end

function HorizontalScrollbar:setThumbPosition(value)
    self:setValue(value, false, false)
end

function HorizontalScrollbar:setRatio(ratio)
    self:setValue(self.minScroll + ratio * (self.maxScroll - self.minScroll))
end

function HorizontalScrollbar:setValue(value, smooth, snap)
    smooth = (smooth == nil) or smooth

    local position = value
    if snap then
        local segment = self:segmentWidth()
        if segment > 0 then
            local steps = math.floor((value - self.minScroll) / segment + 0.5)
            position = self.minScroll + steps * segment
        end
    end
    position = Math.clamp(position, self.minScroll, self.maxScroll)

    local changed = self.position ~= position
    if changed then
        self.position = position
        self:updateThumbPosition(smooth)
    end
    self:emit("valueChanged", changed, self:relativePosition())
end

function HorizontalScrollbar:setStepSize(value)
    if self.stepSize == value then
        return
    end

    self.stepSize = value

    self:updateThumbWidth()
    self:updateThumbPosition()
end

function HorizontalScrollbar:setMaxValue(value)
    if self.maxValue == value then
        return
    end

    self.maxValue = value

    self:updateThumbWidth()
    self:updateThumbPosition()
end

function HorizontalScrollbar:increaseScroll(amount)
    amount = amount or self:segmentWidth()

    self:setValue(self.position + amount * self.stepSize, true, false)
end

function HorizontalScrollbar:decreaseScroll(amount)
    amount = amount or self:segmentWidth()

    self:setValue(self.position - amount * self.stepSize, true, false)
end

return HorizontalScrollbar
