local core = require "luif.core"

local DefaultTextAreaSkin = core.Skin:extend {
    width = 200,
    height = 40
}

function DefaultTextAreaSkin.new(class, self)
    self.layout = core.AnchorLayout {}

    self.children = {
        core.ScrollArea {
            top = 0, bottom = 0, left = 0, right = 0,
            content = core.TextInput {
                id = "textInput",
                color = core.Color.black,
            },
        },
    }

    return core.Skin.new(class, self)
end

return DefaultTextAreaSkin
