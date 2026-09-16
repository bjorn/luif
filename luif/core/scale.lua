local core = require "luif.core"

local Animate = core.Animate

local Scale = Animate:extend {
    property = "scale",
}

return Scale
