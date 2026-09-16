--
-- A layout that positions its items vertically.
--

local core = require "luif.core"

local Layout = core.Layout
local clamp = core.Math.clamp

local ceil, floor = math.ceil, math.floor

local VerticalLayout = Layout:extend {
    -- An optional space between each item, in pixels
    gap = 0,

    -- Horizontal alignment ("none", "left", "right", "center" or "justify")
    horizontalAlign = "none",

    itemHeight = false,

    _virtualChildrenCount = false,
    _childrenOffset = 0,
}

function VerticalLayout:positionChildren()
    local targetWidth, targetHeight = self.target:size()
    local currentY = self.itemHeight and self._childrenOffset * (self.itemHeight + self.gap) or 0

    -- Position and possibly resize children
    local children, first = self.target:contentChildren()
    for i=first,#children do
        local child = children[i]
        local width, height = child:size()

        local marginLeft = child.marginLeft or 0
        local marginRight = child.marginRight or 0

        local x = marginLeft
        if self.horizontalAlign == "none" then
            x = child.x
        elseif self.horizontalAlign == "right" then
            x = targetWidth - width - marginRight
        elseif self.horizontalAlign == "center" then
            x = floor((targetWidth - width) / 2) + marginLeft - marginRight
        elseif self.horizontalAlign == "justify" then
            local childWidth = targetWidth - marginLeft - marginRight
            if childWidth ~= width then
                child:setWidth(clamp(childWidth, child.minimumWidth, child.maximumWidth))
                if child.heightForWidth then
                    width, height = child:size()
                end
            end
        end

        child:setPos(x, currentY)

        currentY = currentY + height + self.gap
    end

    return currentY
end

function VerticalLayout:update()
    self.updating = true

    -- Update the implicit width when no explicit one is set
    if not self.target.width then
        local implicitWidth = 0
        local children, first = self.target:contentChildren()
        for i=first,#children do
            local width, height = children[i]:size()
            implicitWidth = implicitWidth < width and width or implicitWidth
        end
        self.target:setImplicitWidth(implicitWidth)
    end

    local lastY = self:positionChildren()

    local height
    if self._virtualChildrenCount then
        height = self._virtualChildrenCount * (self.itemHeight + self.gap) - self.gap
    else
        height = lastY > 0 and (lastY - self.gap) or 0
    end

    self.target:setFixedHeight(height)
    self.updating = false
end

--
-- VerticalLayout can be virtual when the itemHeight has been set.
--
function VerticalLayout:isVirtual()
    return self.itemHeight
end

--
-- See Layout.childrenVisibleInArea
--
function VerticalLayout:childrenVisibleInArea(x, y, width, height)
    local rowHeight = self.itemHeight + self.gap

    local first = floor(y / rowHeight) + 1
    local last = ceil((y + height) / rowHeight)

    return first, last
end

--
-- See Layout.setVirtualChildren
--
function VerticalLayout:setVirtualChildren(count, first, last)
    if self._virtualChildrenCount == count and self._childrenOffset == first - 1 then
        return
    end

    self._virtualChildrenCount = count
    self._childrenOffset = first - 1

    if self.updating then
        -- Visible virtual children changed as a result of this layout updating.
        -- This kind of thing is normally ignored to protect against infinite
        -- loops, and we need to be careful not to have that happen here.
        -- It should be enough just to reposition the children, which is unlikely
        -- to result in recursion.
        self:positionChildren()
    else
        self:invalidate()
    end
end

return VerticalLayout
