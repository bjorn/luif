local core = require "luif.core"

local Animate = core.Animate

local Fade = Animate:extend {
    property = "alpha",
}

return Fade
