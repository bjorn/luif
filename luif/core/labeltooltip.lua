local core = require "luif.core"

local AnchorLayout  = core.AnchorLayout
local Text          = core.Text
local ToolTip       = core.ToolTip

local LabelToolTip = ToolTip:extend {
    skinClass = core.skins.DefaultLabelToolTipSkin,
    skinParts = {
        "titleLabel",
    }
}

function LabelToolTip.new(class, self)
    assert(type(self.item.toolTip) == "string" or getmetatable(self.item.toolTip) == Text)
    self.layout = AnchorLayout {}
    self = ToolTip.new(class, self)

    self.titleLabel.wrappingWidth = 250
    self.titleLabel:setText(self.item.toolTip)

    self.titleLabel:on("implicitSizeChanged", function(width, height)
        self:setContentSize(width + 15, height + 20)
    end)

    return self
end

return LabelToolTip
