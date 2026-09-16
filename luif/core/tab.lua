--
-- A button that behaves like a tab.
--
-- Exclusive behavior can be achieved with core.ExclusiveGroup.
--

local core = require "luif.core"

local Button = core.Button
local DefaultToggleButtonSkin = core.skins.DefaultToggleButtonSkin

local Tab = Button:extend {
    selectable = true,
    selectOnPress = true,
    sticky = true,
    skinClass = DefaultToggleButtonSkin,
}

return Tab
