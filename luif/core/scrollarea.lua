--
-- An item with a vertical scrollbar that displays scrollable content
--

local core = require "luif.core"

local MouseButton = core.MouseButton
local Math = core.Math

local Update = core.Update

local ScrollArea = core.SkinnableItem:extend {
    mouseEnabled = true,
    mousePressed = false,
    stepSize = false,
    snap = false,
    animate = true, -- animate scrolling
    keepAtBottom = false,
    resizeToContent = false,

    mouseOffset = 0,
    minScroll = 0,
    maxScroll = 0,
    position = 0,

    content = false,
    contentAnimation = false,
    contentY = 0,
    thumb = false,
    thumbAnimation = false,

    valueChanged = false, -- function(actuallyChanged, relativePosition)

    verticalScrollbarVisibility = "auto", -- { auto, visible, invisible }
    verticalButtonVisibility = "visible", -- { auto, visible, invisible }

    state = "normal",

    skinClass = core.skins.DefaultScrollAreaSkin,
    skinParts = { "contentArea", "upButton", "downButton", "trackbar", "thumb" },

    _pressedButton = false,
    _timeout = false,
    _timeoutCount = 0,
}

function ScrollArea.new(class, self)
    -- A dummy layout to determine when to refresh the content size
    self.layout = core.Layout {
        invalidate = function(layout, item)
            if item == self.content then
                self:refreshContentSize()
            end
        end,
    }

    if not self.content then
        if #self > 0 then
            self.content = core.Array.takeFirst(self)
        else
            self.content = core.Item {}
        end
    end

    self.children = {
        self.content,
    }

    self = core.SkinnableItem.new(class, self)

    if self.resizeToContent then
        self.content:on("resize", function(width, height)
            self:setContentWidth(width)
            self:refreshContentSize(false)
        end)
    else
        self.contentArea:on("resize", function(width, height)
            self.content:setWidth(width)
            self:refreshContentSize(false)
        end)
    end
    -- init animations
    self.contentY = self.content.y
    self.content:setExposedArea(0, -self.contentY, self:size())
    self.contentAnimation = core.Animate { target = self, property = "contentY", to = self.contentY, ease = core.Ease.outCubic, duration = 300 }
    if self.thumb then
        self.thumbAnimation = core.Animate { target = self.thumb, property = "y", to = self.thumb.y, ease = core.Ease.outCubic, duration = 300 }
    end

    self:on("resize", function(w, h)
        self.content:setExposedArea(0, -self.contentY, w, h)
    end)

    -- buttons
    if self.upButton then
        self.upButton:setEnabled(self.enabled)
        self.upButton:on("press", function()
            self:scrollUp()
            self:startTimeout(self.upButton)
        end)
        self.upButton:on("release", function()
            self:stopTimeout()
        end)
    end
    if self.downButton then
        self.downButton:setEnabled(self.enabled)
        self.downButton:on("press", function()
            self:scrollDown()
            self:startTimeout(self.downButton)
        end)
        self.downButton:on("release", function()
            self:stopTimeout()
        end)
    end
    if self.trackbar then
        local oldSetSize = self.trackbar.setSize
        self.trackbar.setSize = function(_, width, height)
            local change = self.trackbar.height ~= height
            oldSetSize(self.trackbar, width, height)
            if change then
                self:updateThumbHeight()
                self:updateThumbPosition()
            end
        end
    end

    if self.thumb and self.thumb:as(core.ThumbButton) then
        self.thumb:on("moveMouse", function(x,y) self:onMoveMouse(x,y) end)
        self.thumb:on("press", function() self:onThumbPress() end)
        self.thumb:on("release", function() self:onThumbRelease() end)
    end

    return self
end

function ScrollArea:setContent(content)
    self:deleteChild(self.content)
    self.content = content
    self:addChild(content)
end

function ScrollArea:refreshContentSize(smooth)
    local _, contentHeight = self.content:size()
    local _, contentAreaHeight = self.contentArea:size()

    if self.keepAtBottom then
        self.maxScroll = contentHeight - contentAreaHeight
        self.minScroll = math.min(0, self.maxScroll)
    else
        self.maxScroll = math.max(0, contentHeight - contentAreaHeight)
        self.minScroll = 0
    end

    self:updateThumbHeight()

    if self.keepAtBottom and not self.mousePressed then
        self:setValue(self.maxScroll, smooth)
    else
        self.position = math.min(self.maxScroll, self.position)
        self:updateContentPosition(false)
        self:updateThumbPosition(false)
    end

    self:setEnabled(self.maxScroll > 0)
end

function ScrollArea:setEnabled(enabled)
    core.SkinnableItem.setEnabled(self, enabled)

    if self.upButton then
        self.upButton:setEnabled(enabled)
    end
    if self.downButton then
        self.downButton:setEnabled(enabled)
    end

    if not self.enabled then
        self:setState("disabled")
    elseif self.state == "disabled" then
        self:setState("normal")
    end
end

function ScrollArea:mousePress(event)
    if not self.enabled or event:button() ~= MouseButton.Left then
        event:ignore()
        return
    end

    -- not in bar
    if (event:x() < self.trackbar.x) or (event:x() > self.trackbar.x + self.trackbar.width) then
        event:ignore()
        return
    end

    local thumb = self.thumb
    local y = event:y() - self.trackbar.y

    -- clicked on thumb
    if( (y > thumb.y) and (y < thumb.y + thumb.height)) then
        self.mouseOffset = y - thumb.y
        self.mousePressed = true
        return
    end

    -- clicked on bar
    if y < thumb.y then
        self:scrollUp(self.trackbar.height - 20)
    else
        self:scrollDown(self.trackbar.height - 20)
    end
end

-- by thumb
function ScrollArea:onThumbPress()
    if not self.enabled then
        return
    end

    local _, my = core.Pointer.position()
    local thumb = self.thumb
    local y = my - self.trackbar.y

    self.mouseOffset = y - thumb.y
    self.mousePressed = true
end

function ScrollArea:mouseDoubleClick(event)
    return self:mousePress(event)
end

function ScrollArea:mouseRelease(event)
    if not self.mousePressed or event:button() ~= MouseButton.Left then
        event:ignore()
        return
    end

    self.mousePressed = false
end

function ScrollArea:onThumbRelease()
    self.mousePressed = false
end

function ScrollArea:mouseMove(event)
    if not self.mousePressed or not self.enabled then
        event:ignore()
        return
    end

    self:setThumbPosition(event:y() - self.mouseOffset)
end

function ScrollArea:onMoveMouse(x,y)
    if not self.mousePressed or not self.enabled then
        return
    end
    self:setThumbPosition(y - self.mouseOffset)
end

function ScrollArea:mouseWheel(event)
    if event:value() > 0 then
        self:scrollUp()
    else
        self:scrollDown()
    end
end

function ScrollArea:setVerticalScrollbarVisibility(visibility)
    self.verticalScrollbarVisibility = visibility
    self:updateThumbHeight()
end

function ScrollArea:setVerticalButtonVisibility(visibility)
    self.verticalButtonVisibility = visibility
    self:updateThumbHeight()
end

function ScrollArea:updateThumbHeight()
    local contentWidth, contentHeight = self.content:size()
    local width, height = self:size()
    local trackWidth, trackHeight = self.trackbar:size()

    local pages = math.max(1, contentHeight / height)
    local h = math.max(self.skin.minThumbHeight or 10, trackHeight / pages)
    self.thumb:setHeight(h)

    if self.verticalScrollbarVisibility == "auto" then
        self.thumb:setVisible(pages > 1)
        self.trackbar:setVisible(pages > 1)
    elseif self.verticalScrollbarVisibility == "visible" then
        self.thumb:setVisible(true)
        self.trackbar:setVisible(true)
    elseif self.verticalScrollbarVisibility == "invisible" then
        self.thumb:setVisible(false)
        self.trackbar:setVisible(false)
    end
    if self.upButton and self.downButton then
        if self.verticalButtonVisibility == "auto" then
            self.upButton:setVisible(pages > 1)
            self.downButton:setVisible(pages > 1)
        elseif self.verticalButtonVisibility == "visible" then
            self.upButton:setVisible(true)
            self.downButton:setVisible(true)
        elseif self.verticalButtonVisibility == "invisible" then
            self.upButton:setVisible(false)
            self.downButton:setVisible(false)
        end
    end
end

function ScrollArea:updateThumbPosition(smooth)
    smooth = self.animate and ((smooth==nil) or smooth)

    local width, height = self.trackbar:size()
    local thumbWidth, thumbHeight = self.thumb:size()
    local ratio = (self.maxScroll==0) and 0 or self.position / self.maxScroll
    local y = ratio * (height - thumbHeight)

    if smooth then
        self.thumbAnimation.to = y
        self.thumbAnimation:setDuration(300)
        self:start("thumb", self.thumbAnimation)
    else
        self:stop("thumb")
        self.thumb:setY(y)
    end
end

function ScrollArea:setThumbPosition(value)
    local ratio = (value - self.trackbar.y) / (self.trackbar.height - self.thumb.height)
    self:setValue(ratio * self.maxScroll, false)
end

function ScrollArea:updateContentPosition(smooth)
    smooth = self.animate and ((smooth==nil) or smooth)

    local to = math.floor(-self.position)

    if smooth then
        self.contentAnimation.to = to
        self.contentAnimation:setDuration(300)
        -- Started through Object:start so that delete stops it
        self:start("content", self.contentAnimation)
    else
        self:stop("content")
        self:setContentY(to)
    end
end

function ScrollArea:startTimeout(button)
    self:stopTimeout()
    self._pressedButton = button
    self._timeout = Update:setTimeout(300, function() self:timeout() end)
end

function ScrollArea:stopTimeout()
    Update:clearTimeout(self._timeout)
    self._timeout = false
    self._timeoutCount = 0
end

function ScrollArea:timeout()
    self._timeoutCount = self._timeoutCount + 1

    -- Only apply value change when the button is still down
    if self._pressedButton == self.upButton then
        if self.upButton.state == "down" then
            self:scrollUp()
        end
    elseif self._pressedButton == self.downButton then
        if self.downButton.state == "down" then
            self:scrollDown()
        end
    end

    -- Reschedule the timeout
    self._timeout = Update:setTimeout(100, function() self:timeout() end)
end

function ScrollArea:setRatio(ratio)
    self:setValue(ratio * self.maxScroll)
end

function ScrollArea:setValue(value, smooth)
    smooth = (smooth==nil) or smooth
    local position = Math.clamp(value, self.minScroll, self.maxScroll)
    if self.snap then
        local stepSize = self.stepSize or 1
        position = position - (position % stepSize)
    end
    if self.position ~= position then
        self.position = position

        self:updateContentPosition(smooth)
        if self.thumb then
            self:updateThumbPosition(smooth)
        end
        self:emit("valueChanged", true, self.position / self.maxScroll)
    else
        self:emit("valueChanged", false, self.position / self.maxScroll)
    end
end

function ScrollArea:scrollUp(amount)
    amount = amount or self.stepSize or 30
    self:setValue(self.position - amount)
end

function ScrollArea:scrollDown(amount)
    amount = amount or self.stepSize or 30
    self:setValue(self.position + amount)
end

function ScrollArea:ensureVisible(x, y, width, height, xmargin, ymargin)
    local w, h = self:size()
    local offset = 0

    -- item is below visible area
    if y + height > h then
        offset = y + height - h + ymargin
    end

    -- item is above visible area
    if y < 0 then
        offset = y - ymargin
    end

    if offset ~= 0 then
        self:setValue(self.position + offset, false)
    end

    if self.parent then
        return self.parent:ensureVisible(x + self.x,
                                         y + self.y - offset,
                                         width, height, xmargin, ymargin)
    end
end

function ScrollArea:setContentY(y)
    if self.contentY == y then
        return
    end

    self.contentY = y
    self.content:setY(y)

    local exposedX, exposedY = 0, -y
    local exposedWidth, exposedHeight = self:size()

    local contentArea = self.contentArea
    if contentArea then
        local marginTop = contentArea.top or 0
        local marginLeft = contentArea.left or 0
        local marginRight = contentArea.right or 0
        local marginBottom = contentArea.bottom or 0

        exposedX = exposedX - marginLeft
        exposedY = exposedY - marginTop
        exposedWidth = exposedWidth + marginLeft + marginRight
        exposedHeight = exposedHeight + marginTop + marginBottom
    end

    self.content:setExposedArea(exposedX, exposedY, exposedWidth, exposedHeight)
end

return ScrollArea
