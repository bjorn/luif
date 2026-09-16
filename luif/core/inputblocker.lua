--
-- An item that blocks all input events while visible.
--

local core = require "luif.core"

local FocusScope = core.FocusScope

local InputBlocker = FocusScope:extend {
    mouseEnabled = true,
    visible = false,

    -- Properties for AnchorLayout that make it fill the parent
    left = 0,
    top = 0,
    right = 0,
    bottom = 0,
}

function InputBlocker:event(event)
    return true
end

function InputBlocker:setVisible(visible, ...)
    FocusScope.setVisible(self, visible, ...)
    self:setActive(visible)
    self:setFocus(visible)
end

return InputBlocker
