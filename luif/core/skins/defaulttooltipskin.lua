local core = require "luif.core"

local Skin = core.Skin

-----------------------------------------------------------

local DefaultToolTipSkin = Skin:extend {
    maxWidth = 250,
}

function DefaultToolTipSkin.new(class, self)
    self.layout = core.AnchorLayout {}

    self.children = {
        core.Scale9 {
            source = "tooltip_box",
            left = 0, right = 0, top = 0, bottom = 0,
        },
        core.Item {
            id = "contentArea",
            left = 8, right = 8,
            top = 6, bottom = 6,
        },
    }

    return Skin.new(class, self)
end

return DefaultToolTipSkin
