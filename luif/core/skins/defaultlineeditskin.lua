--
-- The default LineEdit skin: a dark bordered rectangle behind the text input,
-- drawn without application textures.
--

local core = require "luif.core"

local FontDb = core.FontDb

local DefaultLineEditSkin = core.Skin:extend {
    textColor = core.Color.white,
    width = 200,
    height = 20,
}

function DefaultLineEditSkin.new(class, self)
    self.layout = core.AnchorLayout {}

    self.children = {
        core.Rectangle {
            color = 0xFF303030,
            borderColor = 0xFF808080,
            left = 0, top = 0, right = 0, bottom = 0,
        },
        core.TextInput {
            id = "textInput",
            top = 2, bottom = 2, left = 3, right = 3,
            font = FontDb.Text,
            scale = 1,
        },
    }

    return core.Skin.new(class, self)
end

return DefaultLineEditSkin
