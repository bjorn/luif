local core = require "luif.core"

local TexDb  = core.TexDb

local DefaultWindowSkin = core.Skin:extend {
    mouseEnabled = true,
}

function DefaultWindowSkin.new(class, self)
    self.layout = core.AnchorLayout {}
    self.children = {
        core.Item {
            id = "rear",
            layout = core.AnchorLayout {},
            top = 0, bottom = 0,
            left = 0, right = 0,
        },

        core.Item {
            layout = core.AnchorLayout {},
            top = 0, bottom = 0,
            left = 0, right = 0,

            core.Rectangle {
                color = 0xEE666666,
                borderColor = core.Color.black,
                alpha = 210,
                top = 32, left = 0, right = 0, bottom = 0,
            },
        },

        core.Item {
            id = "titleBar",
            layout = core.AnchorLayout {},
            height = 32, left = 0, right = 0, top = 0,

            core.Rectangle {
                color = core.Color.black,
                alpha = 220,
                height = 32,
                top = 0, left = 0, right = 0, bottom = 0,
            },
            core.Label {
                id = "titleLabel",
                top = 6, left = 6,
                textScale = 1.2,
            },

            -- Simple single-image skin as default close button
            core.Button {
                id = "closeButton",

                width = 20,
                height = 20,

                top = 6,
                right = 6,

                skin = core.Skin {
                    layout = core.AnchorLayout {},
                    core.Image {
                        texture = TexDb.close_button,
                        horizontalCenter = 0,
                        verticalCenter = 0,
                        states = {
                            ["over"] = { color = 0xffffbbbb },
                            ["down"] = { color = 0xffff0000 },
                        }
                    },
                    label = false,
                    iconImage = false,
                    hoverIconImage = false,
                }
            },
        },

        core.Item {
            id = "resizeHandle",
            width = 20, height = 20,
            right = 0,
            bottom = 0,
            layout = core.AnchorLayout {},

            core.FillRect { color = core.Color.black, alpha = 192, },
        },

        core.Item {
            id = "contentArea",
            left = 10, top = 42, right = 10, bottom = 10,
        },
    }
    return core.Skin.new(class, self)
end

return DefaultWindowSkin
