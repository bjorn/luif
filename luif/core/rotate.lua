local core = require "luif.core"

local Animate = core.Animate

local Rotate = Animate:extend {
    property = "rotation",
    direction = "numerical",
}

-- These functions modify the 'to' and 'from' values in order to make the
-- animation go into a certain direction.
local directionFunctions = {
    numerical = function(to, from)
        return to, from
    end,

    shortest = function(to, from)
        to = to % 360
        from = from % 360

        -- Determine shortest path on the circle
        local diff = to - from
        if diff > 180 then
            return to, from + 360
        elseif diff < -180 then
            return to, from - 360
        end

        return to, from
    end,

    clockwise = function(to, from)
        to = to % 360
        from = from % 360

        return to, to > from and from or from - 360
    end,

    counterClockwise = function(to, from)
        to = to % 360
        from = from % 360

        return to, to < from and from or from + 360
    end,
}

--
-- Override for custom rotation interpolation.
--
-- The direction decides the way around: "numerical" (the default)
-- interpolates the values as they are, while "shortest", "clockwise" and
-- "counterClockwise" first wrap them to 0..360.
--
function Rotate:interpolate(from, to, progress)
    if progress == 1 then
        return to
    else
        to, from = directionFunctions[self.direction](to, from)
        return from + (to - from) * progress
    end
end

function Rotate:distance(to, from)
    to, from = directionFunctions[self.direction](to, from)
    return math.abs(to - from)
end

return Rotate
