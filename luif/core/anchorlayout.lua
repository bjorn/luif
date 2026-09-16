--
-- The AnchorLayout currently requires the target to have a defined size, and
-- will position children inside this space as defined by these members:
--
--   top, left, bottom, right
--   horizontalCenter, verticalCenter
--   x, y, width, height
--   aspectRatio = { width, height } / true (to use implicit dimension)
--

local core = require "luif.core"

local Layout = core.Layout
local Array = core.Array

local clamp = core.Math.clamp
local max = math.max

local AnchorLayout = Layout:extend {
}

function AnchorLayout:measure()
    local childrenWidth, childrenHeight = 0, 0
    local children, first = self.target:contentChildren()
    for i=first,#children do
        local child = children[i]
        local width, height = child:size()
        childrenWidth = max(childrenWidth, width + (child.left or child.x) + (child.right or 0))
        childrenHeight = max(childrenHeight, height + (child.top or child.y) + (child.bottom or 0))
    end
    return childrenWidth, childrenHeight
end

local function refreshItem(child, anchors, right, bottom)
    local x
    local y
    local width, height = child:size()
    local newWidth, newHeight = width, height

    if not anchors.left then
        if anchors.right then
            x = right - anchors.right - width
        else
            x = child.x
        end
    else
        x = anchors.left
        if anchors.right then
            newWidth = right - anchors.right - anchors.left
        end
    end

    if not anchors.top then
        if anchors.bottom then
            y = bottom - anchors.bottom - height
        else
            y = child.y
        end
    else
        y = anchors.top
        if anchors.bottom then
            newHeight = bottom - anchors.bottom - anchors.top
        end
    end

    if anchors.aspectRatio then
        local w, h
        if anchors.aspectRatio == true then
            w, h = child:implicitSize()
        else
            w, h = anchors.aspectRatio[1], anchors.aspectRatio[2]
        end
        local ratio = w / h
        if (newWidth / newHeight) < ratio then
            newHeight = newWidth / ratio
        else
            newWidth = newHeight * ratio
        end
    end

    newWidth = clamp(newWidth, child.minimumWidth, child.maximumWidth)
    newHeight = clamp(newHeight, child.minimumHeight, child.maximumHeight)

    if anchors.horizontalCenter then
        x = math.floor((right - newWidth) / 2) + anchors.horizontalCenter
    end
    if anchors.verticalCenter then
        y = math.floor((bottom - newHeight) / 2) + anchors.verticalCenter
    end

    child:setPos(x, y)
    if newWidth ~= width then
        child:setWidth(newWidth)

        -- Re-do the vertical positioning when it depends on the height
        if child.heightForWidth and newHeight == height then
            local width, height = child:size()
            if anchors.verticalCenter then
                child:setY(math.floor((bottom - height) / 2) + anchors.verticalCenter)
            elseif not anchors.top and anchors.bottom then
                child:setY(bottom - anchors.bottom - height)
            end
        end
    end
    if newHeight ~= height then
        child:setHeight(newHeight)
    end
end

local function refreshItems(items, first, right, bottom)
    for i=first,#items do
        local item = items[i]
        refreshItem(item, item, right, bottom)
    end
end

function AnchorLayout:invalidate(item, reason)
    if reason == "remove" then
        if self.invalidatedItems then
            Array.removeAll(self.invalidatedItems, item)
        end
        return  -- Removal of items does not affect other items
    end
    Layout.invalidate(self, item, reason)
end

function AnchorLayout:update()
    self.updating = true
    local _, _, width, height = self.target:contentRect()

    if self.invalidatedItems then
        refreshItems(self.invalidatedItems, 1, width, height)
    else
        local children, first = self.target:contentChildren()
        refreshItems(children, first, width, height)
    end

    self.updating = false
end

--
-- This function can be used to apply a certain set of anchors manually.
-- When no anchors are passed in, the anchors from the item itself are used.
--
function AnchorLayout.applyAnchors(item, anchors)
    local _, _, width, height = item.parent:contentRect()
    refreshItem(item, anchors or item, width, height)
end

return AnchorLayout
