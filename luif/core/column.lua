--
-- An item that positions its children in a column, using the VerticalLayout.
--

local core = require "luif.core"

local Column = core.Item:extend {
    -- An optional space between each item, in pixels
    gap = 0,

    -- Horizontal alignment ("none", "left", "right", "center" or "justify")
    horizontalAlign = "none",
}

function Column.new(class, self)
    self.layout = core.VerticalLayout {
        gap = self.gap or class.gap,
        horizontalAlign = self.horizontalAlign or class.horizontalAlign,
    }
    return core.Item.new(class, self)
end

return Column
