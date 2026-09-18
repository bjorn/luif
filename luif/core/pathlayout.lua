--
-- A layout that puts child items along a path. Expects to be used with
-- core.Bezier.
--

local core = require "luif.core"

-- Lua 5.1 and LuaJIT have unpack, later versions table.unpack
local unpack = unpack or table.unpack

local PathLayout = core.Layout:extend {
    path = false,

    -- The space between items, as fraction of the path. If set to 'false',
    -- the space will depend on the amount of items.
    gap = false,
}

function PathLayout.new(class, self)
    assert(self.path, "Path layout needs a path")
    return core.Layout.new(class, self)
end

function PathLayout:update()
    local children, first = self.target:contentChildren()
    if first ~= 1 then
        children = { unpack(children, first) }
    end
    local childCount = #children

    if childCount == 0 then
        return
    end

    local gap = self.gap
    if not gap and childCount > 1 then
        gap = 1 / (childCount - 1)
    end

    self.updating = true

    for i=1,childCount do
        local child = children[i]
        local width, height = child:size()

        local x, y = self.path((i - 1) * gap)

        child:setPos(x, y)
    end

    self.updating = false
end

return PathLayout
