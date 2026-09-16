--
-- The default skin of HorizontalScrollbar, built from generated textures:
-- a shaded track between a left and a right button, and a thumb button.
--

local core = require "luif.core"

local Skin = core.Skin

local TexDb = core.TexDb

local DefaultHorizontalScrollbarSkin = Skin:extend {
    minThumbWidth = 20,
    width = 200,
    height = 19,
}

function DefaultHorizontalScrollbarSkin.new(class, self)
    self.layout = core.AnchorLayout {}
    local size = 19

    self.children = {
        core.Item {
            id = "trackbar",
            layout = core.AnchorLayout {},
            left = size + 1, right = size + 1, top = 0, bottom = 0,
            -- Darker than the default button skin so the thumb stands out
            core.Image {
                texture = TexDb.gradient01,
                color = 0xFF707070,
                left = 0, right = 0, top = 0, bottom = 0,
                states = {
                    disabled = { alpha = 128 },
                },
            },
        },
        core.ThumbButton {
            id = "thumbButton",
            x = size + 1,
            top = 0, bottom = 0,
            width = self.minThumbWidth or class.minThumbWidth,
            text = "",
        },
        core.Button {
            id = "leftButton",
            width = size, height = size,
            left = 0, top = 0,
            text = "<",
            states = {
                disabled = { alpha = 128 },
            },
        },
        core.Button {
            id = "rightButton",
            width = size, height = size,
            right = 0, top = 0,
            text = ">",
            states = {
                disabled = { alpha = 128 },
            },
        },
    }

    return Skin.new(class, self)
end

return DefaultHorizontalScrollbarSkin
