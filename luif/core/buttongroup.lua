--
-- Of all Button instances added to this group, only one is allowed to be
-- selected by automatically deselecting a currently selected button when
-- another gets selected.
--

local core = require "luif.core"

local Button            = core.Button
local ExclusiveGroup    = core.ExclusiveGroup
local Item              = core.Item

local ButtonGroup = Item:extend {
    selectedButtonChanged = false,  -- function(button)

    exclusiveGroup = false,
}

function ButtonGroup.new(class, self)
    self = Item.new(class, self)
    self.exclusiveGroup = self.exclusiveGroup or ExclusiveGroup {}

    -- Listen for changes to the 'selected' property for Button childs
    for i=1,#self.children do
        local button = self.children[i]:as(Button)
        if button then
            self.exclusiveGroup:bindSelectable(button)
        end
    end

    self.exclusiveGroup:on("currentChanged", function(object)
        if not object or object.parent == self then
            self:emit("selectedButtonChanged", object)
        end
    end)

    return self
end

function ButtonGroup:selectedButton()
    return self.exclusiveGroup.current
end

function ButtonGroup:clearSelection(animate)
    self.exclusiveGroup:setSelectedObject(false, animate)
end

function ButtonGroup:insertChild(index, child)
    Item.insertChild(self, index, child)

    if child:as(Button) then
        self.exclusiveGroup:bindSelectable(child)
    end

    return child
end

return ButtonGroup
