--
-- The default tool tip skin with a single text label, used by LabelToolTip.
--

local core = require "luif.core"

local DefaultToolTipSkin = core.skins.DefaultToolTipSkin

local DefaultLabelToolTipSkin = DefaultToolTipSkin:extend {}

function DefaultLabelToolTipSkin.new(class, self)
    self = DefaultToolTipSkin.new(class, self)

    self:findChild("contentArea"):addChild(core.Label {
        id = "titleLabel",
        color = core.Color.white,
        wrap = true,
    })

    return self
end

return DefaultLabelToolTipSkin
