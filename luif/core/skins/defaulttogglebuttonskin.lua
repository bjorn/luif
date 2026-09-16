local core = require "luif.core"

local AnchorLayout = core.AnchorLayout
local Image  = core.Image
local Label  = core.Label
local Skin = core.Skin

local TexDb  = core.TexDb
local FontDb = core.FontDb

local ICON_SCALE = 1.15

local DefaultToggleButtonSkin = Skin:extend {
    width = 100,
    height = 30,

    baseColor = 0xFFFFFFFF,
    selectedColor = 0xFFFF6666,
}

function DefaultToggleButtonSkin.new(class, self)
    local baseColor = self.baseColor or class.baseColor
    local selectedColor = self.selectedColor or class.selectedColor

    local normalColor = core.Color.blend(0xFF000000, baseColor, 0.8)
    local downColor = core.Color.blend(0xFF000000, baseColor, 0.667)
    local overAndSelectedColor = core.Color.blend(0xFFFFFFFF, selectedColor, 0.5)
    local downAndSelectedColor = core.Color.blend(0xFFAAAAAA, selectedColor, 0.5)

    self.layout = AnchorLayout {}
    self.children = {
        Image {
            texture = TexDb.gradient01,
            color = normalColor,
            left = 0, top = 0, right = 0, bottom = 0,

            states = {
                ["over"] = { color = baseColor },
                ["down"] = { color = downColor },
                ["upAndSelected"] = { color = selectedColor },
                ["overAndSelected"] = { color = overAndSelectedColor },
                ["downAndSelected"] = { color = downAndSelectedColor },
                ["disabled"] = { alpha = 128, },
            }
        },

        -- Icon placeholders
        core.Image {
            id = "iconImage",
            texture = TexDb.empty,
            horizontalCenter = 1,
            verticalCenter = 1,
            states = {
                ["over"]            = { scale = ICON_SCALE },
                ["down"]            = { scale = ICON_SCALE },
                ["upAndSelected"]   = { scale = ICON_SCALE },
                ["overAndSelected"] = { scale = ICON_SCALE },
                ["downAndSelected"] = { scale = ICON_SCALE },
                ["disabled"]        = { color = 0xAAffffff },
            },
        },
        core.Image {
            id = "hoverIconImage",
            texture = TexDb.empty,
            horizontalCenter = 1,
            verticalCenter = 1,
            alpha = 0,
            scale = 1 / ICON_SCALE,
            states = {
                ["over"]            = { scale = 1, alpha = 255 },
                ["down"]            = { scale = 1, alpha = 255 },
                ["upAndSelected"]   = { scale = 1, alpha = 255 },
                ["overAndSelected"] = { scale = 1, alpha = 255 },
                ["downAndSelected"] = { scale = 1, alpha = 255 },
            },
        },

        Label {
            id = "label",
            color = 0xFF000000,
            font = FontDb.Medium,
            verticalCenter = 0,
            horizontalCenter = 0,
            states = {
                ["disabled"] = { alpha = 128, },
            },
        },
    }

    self.transitions = {
        core.Transition {
            to = { "up", "over" },
            core.Animate { duration = 100, properties = { "scale", "alpha" }, },
            core.AnimateColor { duration = 100, },
        }
    }

    return Skin.new(class, self)
end

return DefaultToggleButtonSkin
