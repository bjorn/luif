local core = require "luif.core"

local DefaultProgressBarSkin = core.Skin:extend {
    width = 130,
    height = 20,
}

function DefaultProgressBarSkin.new(class, self)
    self.layout = core.AnchorLayout{}

    self.children = {
        core.Rectangle {
            top = 0, bottom = 0,
            left = 0, right = 0,
            id = "background",
            color = core.Color.steelBlue,
        },
        core.Rectangle {
            id = "bar",
            top = 0, bottom = 0,
        },
        core.Label {
            id = "label",
            horizontalCenter = 0,
            verticalCenter = 0,
            color = core.Color.black,
        },
    }

    return core.Skin.new(class, self)
end

return DefaultProgressBarSkin
