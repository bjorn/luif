--
-- A box that contains a list of core.ToggleButton delegates from which
-- only one value can be chosen. When inactive, only the currently selected
-- item is shown, otherwise the whole list is presented.
--

local core = require "luif.core"

------------------------------------------------------------------------------

local ComboBox = core.SkinnableItem:extend {
    -- Function called when the selected delegate changes
    change = false,
    _open = false,
    property = core.ToggleButtonList.property,
    properties = core.ToggleButtonList.properties,
    overlay = false,

    skinParts = {
        "list",
        "buttonContainer",
        "background",
    },
    skinClass = core.skins.DefaultComboBoxSkin,
}

function ComboBox.new(class, self)
    if not self.skin then
        local skinClass = self.skinClass or class.skinClass
        if skinClass then
            self.skin = skinClass {}
        end
    end

    self = core.SkinnableItem.new(class, self)

    self.list.property = self.property
    self.list.properties = self.properties
    self.list.change = function(selected)
        self:setSelectedDelegate(selected)
    end
    self.list:setData(self.data)

    self.buttonContainer.property = self.property
    self.buttonContainer.properties = self.properties

    self:setButtonProperties(#self.data > 0 and self.data[1] or false)

    self.list:reparent()
    if self.background then
        self.background:reparent()
    else
        self.background = core.Item {}
    end

    core.LayoutManager:connect("layoutFinished", self, self.onLayoutFinished)
    self.button:setEnabled(self.enabled)

    for _, delegate in pairs(self:delegates()) do
        if delegate.id == self.selected then
            self:setSelectedDelegate(delegate, true)
        end
    end

    return self
end

function ComboBox:setButtonProperties(data)
    self.buttonContainer:setData({data})
    local button = self.buttonContainer:delegateForIndex(1)
    button.mouseRelease = function()
        self:toggle()
    end
    self.button = button
end

function ComboBox:onLayoutFinished()
    if not self.overlay then
        return
    end

    local x, y = self.button:absolutePos()
    y = y + self.button.height
    self.list:setPos(x,y)
end

function ComboBox:detached()
    if self.overlay then
        self.overlay.parent:removeChild(self.overlay)
        self.overlay = false
    end
end

function ComboBox:setEnabled(enabled)
    if self._open then
        self:toggle()
    end
    self.enabled = enabled
    self.button:setEnabled(enabled)
end

function ComboBox:showList()
    local x, y = self:absolutePos()
    y = y + self.button.height
    self.list:setPos(x, y)
    self.list:setData(self.data)

    core.LayoutManager:validateLayout(self.list.layout)
    self.background:setPos(x, y)
    self.background:setSize(self.list:size())

    self.pickRect = core.Item {
        layout = core.AnchorLayout {},
        left = 0, right = 0,
        top = 0, bottom = 0,
        mouseEnabled = true,
        mousePress = function(event) self:toggle() end,
    }
    local topLayer = core.TopLayer.instance()

    self.overlay = core.Item {
        layout = core.AnchorLayout {},
        left = 0, right = 0,
        top = 0, bottom = 0,
        self.pickRect,
        self.background,
        self.list,
    }

    topLayer:addChild(self.overlay)
end

function ComboBox:setData(data)
    self.data = data
    self.list:setData(data)
end

function ComboBox:toggle()
    if not self.enabled then return end
    if self._open then
        self.overlay.parent:removeChild(self.overlay)
        self.overlay = false
        self._open = false
    else
        self:showList()
        self._open = true
    end
end

function ComboBox:createDelegate(index)
    local delegate = core.ToggleButtonList.createDelegate(self, index)
    return delegate
end

function ComboBox:setSelectedDelegate(button, silent)
    if button then
        self:setButtonProperties(self.list.data[button.index])
        if self._open then
            self:toggle()
        end
        if not silent then
            self:emit("change", button)
        end
    end
end

function ComboBox:setSelectedIndex(index)
    self.list:delegateForIndex(index):setSelected(true)
end

function ComboBox:delegates()
    return self.list:delegates()
end

return ComboBox
