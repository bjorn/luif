local core = require "luif.core"

local AnchorLayout = core.AnchorLayout
local Button = core.Button
local Image = core.Image
local Label = core.Label
local Skin = core.Skin

local TexDb  = core.TexDb

local DefaultSliderSkin = Skin:extend {
    width = 170,
    height = 10,
}

function DefaultSliderSkin.new(class, self)
    self.layout = AnchorLayout {}

    self.children = {
        Image {
            id = "trackbar",
            texture = TexDb.gradient01,
            color = 0xFFCCCCCC,
            left = 13, top = 2, right = 13, bottom = 2,

            states = {
                ["disabled"] = { alpha = 128, },
            }
        },
        Image {
            id = "handle",
            width = 10,
            height = 10,
            texture = TexDb.gradient01,
            color = 0xFFFF0000,

            states = {
                ["disabled"] = { alpha = 128, },
            }
        },
        Label {
            id = "valueLabel",
            right = -40,
            verticalCenter = 0,

            states = {
                ["disabled"] = { alpha = 128, },
            },
        },
        Button {
            id = "decrementButton",
            skin = core.skins.DefaultButtonSkin {},
            tickInterval = 100,
            width = 12, height = 12,
            left = 0,
            verticalCenter = 0,
            text = "-",
        },
        Button {
            id = "incrementButton",
            skin = core.skins.DefaultButtonSkin {},
            tickInterval = 100,
            width = 12, height = 12,
            right = 0,
            verticalCenter = 0,
            text = "+",
        },
    }

    return Skin.new(class, self)
end

return DefaultSliderSkin
