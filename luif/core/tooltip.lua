--
-- A tooltip, being displayed when hovering over the attached item. It is a
-- root placed and sized in virtual units, kept within the virtual screen.
--

local core = require "luif.core"

local Screen            = core.Screen
local SkinnableItem     = core.SkinnableItem
local Sounds            = core.Sounds

local instances = setmetatable({}, { __mode = "k" })

local ToolTip = SkinnableItem:extend {
    timeout = 150,
    mouseEnabled = false,
    item = false,
    showSound = Sounds.UI.ToolTip,

    -- Specifies the absolute position of the tool tip
    mouseX = 0,
    mouseY = 0,

    -- position relative to parent element, overrides absolute position
    relX = false,
    relY = false,

    relHeight = false,
    relWidth = false,

    _anchorX = 0,
    _anchorY = 0,

    relPlacement = "vertical",    -- vertical, horizontal
    relMouseX = 25,
    relMouseY = 25,

    toolTipAlignment = "right",   -- right, left (read only)
}

function ToolTip.new(class, self)
    instances[self] = true
    self = SkinnableItem.new(class, self)

    local absX, absY = self.item:absolutePos()

    local x, y

    if self.relX then
        x = self.relX + absX
    else
        x = self.mouseX
    end

    if self.relY then
        y = self.relY + absY
    else
        y = self.mouseY
    end

    self._anchorX = x
    self._anchorY = y

    self:setPos(x, y)
    return self
end

function ToolTip:attached()
    self:update()
end

function ToolTip:delete()
    instances[self] = nil
    SkinnableItem.delete(self)
end

function ToolTip:setContentSize(width, height)
    SkinnableItem.setContentSize(self, width, height)
    self:update()
end

function ToolTip:update()
    local width, height = self:size()
    width = width * self.scale
    height = height * self.scale

    if not self.item then
        return
    end

    local itemWidth, itemHeight = self.item:size()

    if not self.relX then
        itemWidth = self.relMouseX
    end
    if not self.relY then
        itemHeight = self.relMouseY
    end

    local screenW, screenH = Screen.width, Screen.height
    local x, y
    local maxX = screenW - width
    local maxY = screenH - height
    local alignment = "right"

    if self.relPlacement == "horizontal" then
        if self._anchorX + width + itemWidth < screenW then
            x = self._anchorX + itemWidth + (self.relWidth or 0)
        else
            x = self._anchorX - width
            alignment = "left"
        end
    else
        if self._anchorX + width + itemWidth < screenW then
            x = self._anchorX + (self.relX or 0)
        else
            x = self._anchorX - width + itemWidth + (self.relWidth or 0)
            alignment = "left"
        end
    end

    if self.relPlacement == "horizontal" then
        if self._anchorY + height < screenH then
            y = self._anchorY
        elseif self._anchorY - height > 0 then
            y = self._anchorY - height + itemHeight + (self.relHeight or 0)
        else
            y = screenH - height
        end
    else
        if self._anchorY + height + itemHeight < screenH then
            y = self._anchorY + itemHeight + (self.relHeight or 0)
        elseif self._anchorY - height > 0 then
            y = self._anchorY - height + (self.relY or 0)
        else
            y = screenH - height
        end
    end

    self.toolTipAlignment = alignment
    self:setPos(math.min(x, maxX), math.min(y, maxY))
end

function ToolTip.destroyAllToolTips()
    for toolTip in pairs(instances) do
        if toolTip.item then
            toolTip.item:destroyToolTip(false)
        else
            toolTip:delete()
        end
    end
end

return ToolTip
