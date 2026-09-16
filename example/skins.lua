--
-- Skins for the example, built on the Source of Tales PNGs in example/images.
--
-- The pattern shown here: textures are swapped per state (strings and
-- handles are applied instantly), numbers and colours are animated. A
-- Transition's Animate must therefore be restricted to numeric properties
-- with a 'properties' list, otherwise it claims the texture change as well
-- and asserts on "can't interpolate non-numbers".
--

local core = require "luif.core"

local TexDb  = core.TexDb
local FontDb = core.FontDb

local skins = {}

-- Big 270x70 button. Four PNG states, label colour and scale animated.
local BigButtonSkin = core.Skin:extend { width = 270, height = 70 }

function BigButtonSkin.new(class, self)
    self.layout = core.AnchorLayout {}
    self.children = {
        core.Image {
            texture = TexDb.bigbutton,
            left = 0, top = 0, right = 0, bottom = 0,
            states = {
                over     = { texture = TexDb.bigbutton_hovered },
                down     = { texture = TexDb.bigbutton_pressed },
                disabled = { texture = TexDb.bigbutton_disabled },
            },
        },
        core.Label {
            id = "label",
            font = FontDb.Medium,
            color = 0xFF5A2E00,
            wrap = false,
            horizontalCenter = 0, verticalCenter = -1,
            states = {
                over     = { color = 0xFFFFFFFF, scale = 1.1 },
                down     = { color = 0xFFFFFFFF, scale = 1.02 },
                disabled = { alpha = 128 },
            },
        },
    }
    self.transitions = {
        core.Transition {
            to = { "up", "over" },
            core.AnimateColor { duration = 150 },
            core.Animate { duration = 150, properties = { "scale", "alpha" }, ease = "outCubic" },
        },
    }
    return core.Skin.new(class, self)
end

skins.BigButtonSkin = BigButtonSkin

-- Compact 67x30 text button (dialogs and the top bar).
local CompactButtonSkin = core.Skin:extend { width = 67, height = 30 }

function CompactButtonSkin.new(class, self)
    self.layout = core.AnchorLayout {}
    self.children = {
        core.Image {
            texture = TexDb.scroll_button,
            left = 0, top = 0, right = 0, bottom = 0,
            states = {
                over     = { texture = TexDb.scroll_button_focused },
                down     = { texture = TexDb.scroll_button_pressed },
                disabled = { alpha = 128 },
            },
        },
        core.Label {
            id = "label",
            color = 0xFF3A2410,
            wrap = false,
            horizontalCenter = 0, verticalCenter = -1,
            states = {
                over = { color = 0xFF000000 },
                down = { color = 0xFF000000 },
            },
        },
    }
    self.transitions = {
        core.Transition {
            core.AnimateColor { duration = 100 },
            core.Animate { duration = 100, properties = { "alpha" } },
        },
    }
    return core.Skin.new(class, self)
end

skins.CompactButtonSkin = CompactButtonSkin

-- Small 26x24 icon button. The icon is set through Button.iconSource.
local SmallButtonSkin = core.Skin:extend { width = 26, height = 24 }

function SmallButtonSkin.new(class, self)
    self.layout = core.AnchorLayout {}
    self.children = {
        core.Image {
            texture = TexDb.button,
            left = 0, top = 0, right = 0, bottom = 0,
            states = {
                over     = { texture = TexDb.buttonhi },
                down     = { texture = TexDb.buttonpress },
                disabled = { texture = TexDb.button_disabled },
            },
        },
        core.Image {
            id = "iconImage",
            texture = TexDb.empty,
            horizontalCenter = 0, verticalCenter = 0,
            states = {
                over     = { scale = 1.15 },
                down     = { scale = 0.9 },
                disabled = { alpha = 110 },
            },
        },
    }
    self.transitions = {
        core.Transition {
            to = { "up", "over" },
            core.Animate { duration = 120, properties = { "scale", "alpha" }, ease = "outCubic" },
        },
    }
    return core.Skin.new(class, self)
end

skins.SmallButtonSkin = SmallButtonSkin

-- 32x32 round toggle. Selected states swap to the pressed PNG, hovering
-- tints the image through AnimateColor.
local RoundToggleSkin = core.Skin:extend { width = 32, height = 32 }

function RoundToggleSkin.new(class, self)
    local hoverTint = 0xFFBFE0FF
    self.layout = core.AnchorLayout {}
    self.children = {
        core.Image {
            texture = TexDb.roundbutton,
            left = 0, top = 0, right = 0, bottom = 0,
            states = {
                over            = { color = hoverTint },
                down            = { texture = TexDb.roundbutton_pressed },
                upAndSelected   = { texture = TexDb.roundbutton_pressed },
                overAndSelected = { texture = TexDb.roundbutton_pressed, color = hoverTint },
                downAndSelected = { texture = TexDb.roundbutton_pressed, color = 0xFF90B8E0 },
                disabled        = { alpha = 128 },
            },
        },
    }
    self.transitions = {
        core.Transition {
            core.AnimateColor { duration = 120 },
            core.Animate { duration = 120, properties = { "alpha" } },
        },
    }
    return core.Skin.new(class, self)
end

skins.RoundToggleSkin = RoundToggleSkin

-- 34x63 tab with an icon. Unselected tabs are darkened by their tint, the
-- selected tab shows the wood at full brightness with a slightly larger icon.
local TabSkin = core.Skin:extend { width = 34, height = 63 }

function TabSkin.new(class, self)
    local selected = { color = 0xFFFFFFFF }
    local selectedIcon = { alpha = 255, scale = 1.15 }
    self.layout = core.AnchorLayout {}
    self.children = {
        core.Image {
            texture = TexDb.tab,
            color = 0xFF7A7A80,
            left = 0, top = 0, right = 0, bottom = 0,
            states = {
                over            = { color = 0xFFB0B0B8 },
                down            = selected,
                upAndSelected   = selected,
                overAndSelected = selected,
                downAndSelected = selected,
            },
        },
        core.Image {
            id = "iconImage",
            texture = TexDb.empty,
            alpha = 150,
            horizontalCenter = 0, verticalCenter = 0,
            states = {
                over            = { alpha = 220 },
                down            = selectedIcon,
                upAndSelected   = selectedIcon,
                overAndSelected = selectedIcon,
                downAndSelected = selectedIcon,
            },
        },
    }
    self.transitions = {
        core.Transition {
            core.AnimateColor { duration = 150 },
            core.Animate { duration = 150, properties = { "alpha", "scale" }, ease = "outCubic" },
        },
    }
    return core.Skin.new(class, self)
end

skins.TabSkin = TabSkin

-- Flat row button for the scroll area; the width comes from the Button.
local RowSkin = core.Skin:extend { width = 180, height = 28 }

function RowSkin.new(class, self)
    self.layout = core.AnchorLayout {}
    self.children = {
        core.Rectangle {
            color = 0xFF3A3D4A,
            left = 0, top = 0, right = 0, bottom = 0,
            states = {
                over     = { color = 0xFF555A70 },
                down     = { color = 0xFF2A2C36 },
                disabled = { alpha = 128 },
            },
        },
        core.Label {
            id = "label",
            color = 0xFFEEEEEE,
            wrap = false,
            left = 10, verticalCenter = 0,
        },
    }
    self.transitions = {
        core.Transition {
            to = { "up", "over" },
            core.AnimateColor { duration = 100 },
        },
    }
    return core.Skin.new(class, self)
end

skins.RowSkin = RowSkin

-- Slim scroll area: a clipped content area and a thin track with a thumb.
-- The up and down buttons are optional skin parts and left out.
local ScrollAreaSkin = core.Skin:extend {}

function ScrollAreaSkin.new(class, self)
    local size = 8
    self.layout = core.AnchorLayout {}
    self.barWidth = size
    self.children = {
        core.Item {
            id = "contentArea",
            clip = true,
            left = 0, top = 0, bottom = 0, right = size + 4,
        },
        core.Item {
            id = "trackbar",
            layout = core.AnchorLayout {},
            right = 0, top = 0, bottom = 0,
            width = size,
            core.Rectangle {
                color = 0xFF22242C,
                left = 0, top = 0, right = 0, bottom = 0,
            },
            core.Rectangle {
                id = "thumb",
                color = 0xFF7C8296,
                width = size,
                states = {
                    disabled = { alpha = 128 },
                },
            },
        },
    }
    return core.Skin.new(class, self)
end

skins.ScrollAreaSkin = ScrollAreaSkin

-- Line edit: a dark field with a placeholder that is hidden once there is
-- text. The field brightens on hover and focus.
local LineEditSkin = core.Skin:extend { textColor = 0xFFE8E8E8, width = 300, height = 30 }

function LineEditSkin.new(class, self)
    self.layout = core.AnchorLayout {}
    self.children = {
        core.Rectangle {
            color = 0xFF1E2028,
            borderColor = 0xFF5A5F70,
            left = 0, top = 0, right = 0, bottom = 0,
            states = {
                over     = { color = 0xFF242733 },
                focused  = { color = 0xFF2A2E3C },
                disabled = { alpha = 128 },
            },
        },
        core.Label {
            id = "placeholderLabel",
            text = "", wrap = false,
            color = 0xFF6C7184,
            left = 8, verticalCenter = 0,
        },
        core.TextInput {
            id = "textInput",
            left = 8, right = 8, top = 6, bottom = 6,
        },
    }
    self.transitions = {
        core.Transition {
            core.AnimateColor { duration = 120 },
        },
    }
    return core.Skin.new(class, self)
end

skins.LineEditSkin = LineEditSkin

-- Tool tip: a dark bordered box around the titleLabel that LabelToolTip fills.
local ToolTipSkin = core.Skin:extend { width = 60, height = 30 }

function ToolTipSkin.new(class, self)
    self.layout = core.AnchorLayout {}
    self.children = {
        core.Rectangle {
            color = 0xF01A1C24,
            borderColor = 0xFF5A5F70,
            left = 0, top = 0, right = 0, bottom = 0,
        },
        core.Item {
            id = "contentArea",
            left = 8, top = 5, right = 8, bottom = 5,
            core.Label {
                id = "titleLabel",
                color = 0xFFE8E8E8,
            },
        },
    }
    return core.Skin.new(class, self)
end

skins.ToolTipSkin = ToolTipSkin

-- LabelToolTip with the skin above
skins.ToolTip = core.LabelToolTip:extend { skinClass = ToolTipSkin }

return skins
