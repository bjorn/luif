--
-- A rectangle mainly useful for debugging. It fills its parent by default (when
-- AnchorLayout is used) and has a transparent red color.
--

local core = require "luif.core"

local Rectangle = core.Rectangle

return Rectangle:extend {
    -- 50% transparent red
    color = 0x80FF0000,

    -- Properties for AnchorLayout that make it fill the parent
    left = 0,
    top = 0,
    right = 0,
    bottom = 0,
}
