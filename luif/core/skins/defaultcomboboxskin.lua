local core = require "luif.core"

local DefaultComboBoxSkin = core.Skin:extend {
    width = 150,
    localize = false,
}

function DefaultComboBoxSkin.new(class, self)
    local localize = self.localize
    if localize == nil then
        localize = class.localize
    end

    local delegate = core.ToggleButton:extend {
        width = self.width or class.width,
        height = self.height or class.height,
        localize = localize,
    }

    self.children = {
        core.ToggleButtonList {
            id = "buttonContainer",
            delegate = delegate,
        },
        core.ToggleButtonList {
            id = "list",
            delegate = delegate,
        },
    }

    return core.Skin.new(class, self)
end

return DefaultComboBoxSkin
