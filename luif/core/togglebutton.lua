--
-- A button that can be selected and unselected by clicking it.
--
-- Exclusive behavior can be achieved with core.ExclusiveGroup.
--

local core = require "luif.core"

local Button = core.Button
local DefaultToggleButtonSkin = core.skins.DefaultToggleButtonSkin

local ToggleButton = Button:extend {
    selectable = true,
    skinClass = DefaultToggleButtonSkin,
}

return ToggleButton
