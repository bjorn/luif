--
-- Test helper: node transforms read back from a host with the inspect
-- capability (host/interface.lua), following the interface's transform
-- T(x, y) * T(origin) * R(rotation) * S(scale) * T(-origin).
--
--   local HostWorld = require "tests.hostworld"
--   local wx, wy = HostWorld.toWorld(host, node, lx, ly)
--

local cos, sin = math.cos, math.sin

local HostWorld = {}

-- The window position of a point in the node's local space.
function HostWorld.toWorld(host, node, x, y)
    while node do
        local s = host.inspect(node)
        local ox, oy = s.originX, s.originY
        local c, n = cos(s.rotation), sin(s.rotation)
        local dx, dy = (x - ox) * s.scale, (y - oy) * s.scale
        x = s.x + ox + c * dx - n * dy
        y = s.y + oy + n * dx + c * dy
        node = s.parent
    end
    return x, y
end

-- Index of node among the children of parent, or nil.
function HostWorld.childIndex(host, parent, node)
    local children = host.inspect(parent).children
    for i = 1, #children do
        if children[i] == node then return i end
    end
    return nil
end

return HostWorld
