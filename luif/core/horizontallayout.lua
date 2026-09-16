--
-- A layout that positions its items horizontally.
--

local core = require "luif.core"

local Layout        = core.Layout
local clamp         = core.Math.clamp

local HorizontalLayout = Layout:extend {
    -- An optional space between each item, in pixels
    gap = 0,

    -- Vertical alignment ("none", "top", "bottom", "center" or "justify")
    verticalAlign = "none",
}

function HorizontalLayout:update()
    self.updating = true

    -- Update the implicit height when no explicit one is set
    if not self.target.height then
        local implicitHeight = 0
        local children, first = self.target:contentChildren()
        for i=first,#children do
            local width, height = children[i]:size()
            implicitHeight = implicitHeight < height and height or implicitHeight
        end
        self.target:setImplicitHeight(implicitHeight)
    end

    local targetWidth, targetHeight = self.target:size()
    local currentX = 0

    -- Position and possibly resize children
    local children, first = self.target:contentChildren()
    for i=first,#children do
        local child = children[i]
        local width, height = child:size()

        local y = 0
        if self.verticalAlign == "none" then
            y = child.y
        elseif self.verticalAlign == "bottom" then
            y = targetHeight - height
        elseif self.verticalAlign == "center" then
            y = math.floor((targetHeight - height) / 2)
        elseif self.verticalAlign == "justify" then
            if targetHeight ~= height then
                child:setHeight(clamp(targetHeight, child.minimumHeight, child.maximumHeight))
            end
        end

        child:setPos(currentX, y)

        currentX = currentX + width + self.gap
    end

    local width = currentX > 0 and (currentX - self.gap) or 0
    self.target:setFixedWidth(width)
    self.updating = false
end

function HorizontalLayout:setGap(gap)
    if self.gap ~= gap then
        self.gap = gap
        self:invalidate()
    end
end

return HorizontalLayout
