--
-- An item that positions its children in a row, using the HorizontalLayout.
--

local core = require "luif.core"

local Row = core.Item:extend {
    -- An optional space between each item, in pixels
    gap = 0,

    -- Vertical alignment ("none", "top", "bottom", "center" or "justify")
    verticalAlign = "none",
}

function Row.new(class, self)
    self.layout = core.HorizontalLayout {
        gap = self.gap or class.gap,
        verticalAlign = self.verticalAlign or class.verticalAlign,
    }
    return core.Item.new(class, self)
end

function Row:setGap(gap)
    self.gap = gap
    self.layout:setGap(gap)
end

return Row
