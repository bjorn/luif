--
-- Of all objects added to this group, only one is allowed to be selected.
-- This is enforced by automatically deselecting a currently selected object
-- when another gets selected.
--
-- All objects should have a "change(selected, user)" signal.
--
-- This class is automatically used by:
--
--  core.ButtonGroup
--  core.ToggleButtonList
--

local core = require "luif.core"

local ExclusiveGroup = core.Object:extend {
    current = false,        -- The currently selected element

    currentChanged = false, -- function(object, user)
}

function ExclusiveGroup.new(class, self)
    self.changeHandler = function(selected, user)
        if selected then
            self:setSelectedObject(core.Object.sender(), nil, user)
        elseif user then
            self:setSelectedObject(false, nil, user)
        end
    end
    return core.Object.new(class, self)
end

function ExclusiveGroup:bindSelectable(selectable)
    selectable:on("change", self.changeHandler)
    if selectable.selected and not self.current then
        self.current = selectable
    end
end

function ExclusiveGroup:unbindSelectable(selectable)
    selectable:removeListener("change", self.changeHandler)
    if self.current == selectable then
        self:setSelectedObject(false)
    end
end

function ExclusiveGroup:setSelectedObject(object, animate, user)
    if self.current == object then
        return
    end

    if self.current then
        self.current:setSelected(false, animate)
    end

    self.current = object
    self:emit("currentChanged", object, user)
end

return ExclusiveGroup
