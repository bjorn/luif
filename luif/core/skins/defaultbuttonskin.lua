local core = require "luif.core"

local TexDb  = core.TexDb
local FontDb = core.FontDb

local DefaultButtonSkin = core.Skin:extend {}

local ICON_SCALE = 1.15

function DefaultButtonSkin.new(class, self)
    self.layout = core.AnchorLayout {}
    self.width = 100
    self.height = 30

    self.children = {
        core.Image {
            texture = TexDb.gradient01,
            color = 0xFFCCCCCC,
            left = 0, top = 0, right = 0, bottom = 0,

            states = {
                ["over"] = {
                    color = 0xFF96e3ff,
                },
                ["down"] = {
                    color = 0xFF527c8c,
                },
                ["disabled"] = { alpha = 128, },
            }
        },
        core.Label {
            id = "label",
            color = 0xFF000000,
            font = FontDb.Medium,
            verticalCenter = 0,
            horizontalCenter = 0,

            states = {
                ["disabled"] = { alpha = 128, },
            }
        },
        core.Image {
            id = "iconImage",
            texture = TexDb.empty,
            verticalCenter = 0,
            horizontalCenter = 0,

            states = {
                ["over"] = {
                    scale = ICON_SCALE,
                },
                ["down"] = {
                    scale = ICON_SCALE,
                },
                ["disabled"] = { alpha = 128, },
            }
        },
    }

    self.transitions = {
        core.Transition {
            to = { "up", "upAndSelected" },
            core.AnimateColor { duration = 200 },
            core.Animate { duration = 200, ease = core.Ease.outCubic }
        },
        core.Transition {
            to = { "over", "overAndSelected" },
            core.AnimateColor { duration = 100 },
            core.Animate { duration = 100, ease = core.Ease.outCubic }
        }
    }

    return core.Skin.new(class, self)
end

return DefaultButtonSkin
