local core = require "luif.core"

local clamp     = core.Math.clamp

local ProgressBar = core.SkinnableItem:extend {
    skinClass = core.skins.DefaultProgressBarSkin,
    skinParts = {
        "background",
        "bar",
        "label",
        "tip",
    },

    labelText = false,
    barSize = false,
    reverseLabel = false,
    value = 0,
    min = 0,
    max = 1,

    _animation = false
}

function ProgressBar.new(class, self)
    self = core.SkinnableItem.new(class, self)

    self.labelText = self.skin and self.skin.labelText or self.labelText or "{1}/{2}"

    if self.skin then
        self.vertical = self.skin.vertical
    end

    if self.bar then
        self.bar:setVisible(false)

        local barWidth, barHeight = self.bar:size()
        local barSize = self.vertical and barHeight or barWidth

        if barSize ~= 0 then
            self.barSize = barSize
        end
    end

    if self.tip then
        self.tip:setVisible(false)
    end

    return self
end

function ProgressBar:refresh()
    if self.bar then
        self.bar:setVisible(self.value ~= self.min)
        local ratio = (self.value - self.min) / (self.max - self.min)
        if self.vertical then
            local height = ratio * (self.barSize or self.height)
            self.bar:setHeight(height)
        else
            local width = ratio * (self.barSize or self.width)
            self.bar:setWidth(width)
        end
    end
    if self.tip then
        self.tip:setVisible(self.value ~= self.min)
        local x = self.bar.x + self.bar.width
        self.tip:setX(x)
    end
    if self.label then
        local value = self.reverseLabel and (self.max - self.value) or self.value
        self.label:setText(self.labelText, value, self.max)
    end
end

function ProgressBar:setValue(value)
    self.value = clamp(value, self.min, self.max)
    self:refresh()
end

function ProgressBar:setRange(min, max)
    assert(min <= max)

    self.min = min
    self.max = max
    self:refresh()
end

function ProgressBar:animate(from, to, duration)
    self:setValue(from)
    self._animation = self:start("animate", core.Animate {
        property = "value",
        to = to,
        duration = duration,
    })
end

function ProgressBar:isAnimating()
    return self._animation and self._animation.running
end

function ProgressBar:stopAnimating()
    self:stop("animate")
end

function ProgressBar:setSize(width, height)
    core.SkinnableItem.setSize(self, width, height)
    self:refresh()
end

return ProgressBar
