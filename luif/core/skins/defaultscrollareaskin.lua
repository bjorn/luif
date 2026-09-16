local core = require "luif.core"

local Skin = core.Skin

local TexDb  = core.TexDb

-----------------------------------------------------------

local DefaultScrollAreaSkin = Skin:extend {
    minThumbHeight = 20,
}

function DefaultScrollAreaSkin.new(class, self)
    self.layout = core.AnchorLayout {}
    local size = 19
    self.barWidth = size

    self.children = {
        core.Item {
            id = "contentArea",
            clip = true,
            top = 0, bottom = 0, left = 0, right = size + 1,
        },
        core.Item {
            id = "trackbar",
            layout = core.AnchorLayout { },
            right = 1, top = size + 1, bottom = size + 1,
            width = size,
            core.Image {
                top = 0, bottom = 0,
                texture = TexDb.gradient01,
                color = 0xFFCCCCCC,
                width = size,

                states = {
                    ["disabled"] = { alpha = 128, },
                }
            },
            core.Image {
                id = "thumb",
                texture = TexDb.gradient01,
                color = 0xFF99FFFF,
                width = size,

                states = {
                    ["disabled"] = { alpha = 128, },
                }
            },
        },
        core.Button {
            id = "upButton",
            color = 0xFFCCCCCC,
            width = size, height = size,
            text = "^",
            right = 1,
            top = 1,
            states = {
                ["disabled"] = { alpha = 128, },
            }
        },
        core.Button {
            id = "downButton",
            color = 0xFFCCCCCC,
            width = size, height = size,
            text = "v",
            right = 1,
            bottom = 1,
            states = {
                ["disabled"] = { alpha = 128, },
            }
        },
    }

    return Skin.new(class, self)
end

return DefaultScrollAreaSkin
