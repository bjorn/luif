local core = require "luif.core"

local Animate = core.Animate
local Color = core.Color

local AnimateColor = Animate:extend {
    property = "color",
}

-- Override for custom color interpolation
function AnimateColor:interpolate(from, to, progress)
    return progress == 1 and to or Color.blend(from, to, progress)
end

return AnimateColor
