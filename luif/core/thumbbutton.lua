--
-- A Button which can be moved while pressed. Main purpose: Scrollbar thumb
--

local core = require "luif.core"

local Button = core.Button

local ThumbButton = Button:extend {
    -- mouse enter and leave are only emitted when the button is not pressed.
    -- This ensures the same state of the button, even when leaving the button area (otherwise e.g. a scrollbar would feel weird)
    stayPressedOnLeave = true,

    -- Callback functions
    moveMouse = false,     -- function(x,y): mouse move
}

function ThumbButton:mouseMove(event)
    if self._mousePressed then
        local x, y = event:absolutePos()
        self:emit("moveMouse", x, y)
    end
end

return ThumbButton
