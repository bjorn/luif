--
-- A convenience class for making a rectangle. Also supports a border. The
-- node has fill content: the colour fills the box and the border is drawn
-- inside it.
--

local core = require "luif.core"

local Item = core.Item
local Color = core.Color
local Sync = core.Sync

local Rectangle = Item:extend {
    color = 0xFFFFFFFF,

    borderColor = false,
    borderWidth = 1,
}

function Rectangle.new(class, self)
    self = Item.new(class, self)

    if type(self.color) == "string" then
        self:setColor(self.color)
    end

    return self
end

function Rectangle:pushContent(host, node)
    local border = self.borderColor
    local hasBorder = border and border ~= 0
    host.setFill(node, self.color or 0xFFFFFFFF, hasBorder and border or false,
                 hasBorder and self.borderWidth or 0)
end

function Rectangle:setColor(color)
    if type(color) == "string" then
        color = Color[color]
        assert(type(color) == "number", "unknown color name")
    end
    if self.color == color then
        return
    end

    self.color = color
    Sync.contentChanged(self)
end

function Rectangle:setBorderColor(color)
    if self.borderColor == color then
        return
    end

    self.borderColor = color
    Sync.contentChanged(self)
end

return Rectangle
