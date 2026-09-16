local core = require "luif.core"

local Object = core.Object
local Array = core.Array
local LayoutManager = core.LayoutManager

local Layout = Object:extend {
    target = false,

    invalid = false,
    invalidatedItems = false,

    updating = false,
}

function Layout:delete()
    if self.invalid then
        LayoutManager:cancelLayout(self)
    end
    Object.delete(self)
end

-- Invalidates this layout. Optionally passes the item that caused the
-- invalidation.
--
-- Used reasons are nil, "add" and "remove". This is used by some layouts
-- (like AnchorLayout) to avoid unnecessary updating.
--
function Layout:invalidate(item, reason)
    assert(not item or (type(item) == "table"))
    assert(self.target, "Can't invalidate layout without target")

    -- Don't invalidate as a result of our own changes
    if self.updating then
        return
    end

    if not self.invalid then
        LayoutManager:invalidateLayout(self)
        self.invalid = true

        if item and reason ~= "remove" then
            assert(type(item) == "table")
            self.invalidatedItems = { item }
        end
    elseif item and self.invalidatedItems then
        assert(type(item) == "table")
        if reason == "remove" then
            Array.removeAll(self.invalidatedItems, item)
        else
            self.invalidatedItems[#self.invalidatedItems + 1] = item
        end
    else
        self.invalidatedItems = false
    end
end

-- Measures the space the children take and returns the width, height
-- Could be used for determining an item's implicit size
function Layout:measure()
    return 0, 0
end

-- Update the layout.
function Layout:update()
end

--
-- Returns whether this layout is capable of determining which children would
-- be visible in a certain area and layouting only these children.
--
function Layout:isVirtual()
    return false
end

--
-- Returns the first and the last index of the children visible in the given
-- area.
--
function Layout:childrenVisibleInArea(x, y, width, height)
    return 1, 0
end

--
-- Sets the amount of virtual children as well as the first and last visible
-- child. This is meant to be used for virtual layouts where only a subsequence
-- of the full list of potential children is actually added.
--
function Layout:setVirtualChildren(count, first, last)
end

return Layout
