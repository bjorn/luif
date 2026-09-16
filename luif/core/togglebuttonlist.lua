--
-- A special kind of list meant to be used with core.ToggleButton as delegate,
-- or with anything else that has 'setSelected' and a 'change' signal.
--
-- Makes sure only one button can be selected at a time.
--

local core = require "luif.core"

local ToggleButtonList = core.List:extend {
    delegate = core.ToggleButton,

    -- Function called when the selected delegate changes
    change = false,                 -- function(delegate, user)

    -- This version also works for 'virtual' lists where not all delegates
    -- are being created.
    selectedIndexChanged = false,   -- function(index, user)

    exclusiveGroup = false,
    selectedIndex = false,
}

function ToggleButtonList.new(class, self)
    self.exclusiveGroup = self.exclusiveGroup or core.ExclusiveGroup {}

    self.exclusiveGroup:connect("currentChanged", self, function(self, object, user)
        local index, indexChanged

        object = object and object.parent == self and object
        if object then
            index = object.index
            indexChanged = index ~= self.selectedIndex
            self.selectedIndex = index
        end

        self:emit("change", object or false, user)
        if indexChanged then
            self:emit("selectedIndexChanged", index, user)
        end
    end)

    return core.List.new(class, self)
end

function ToggleButtonList:createDelegate(data, index)
    return core.List.createDelegate(self, data, index, {
        selected = index == self.selectedIndex,
        exclusiveGroup = self.exclusiveGroup
    })
end

function ToggleButtonList:selectedDelegate()
    return self.exclusiveGroup.current
end

function ToggleButtonList:clearSelection()
    self.selectedIndex = false
    self.exclusiveGroup:setSelectedObject(false)
    self:emit("selectedIndexChanged", false)
end

function ToggleButtonList:setData(data)
    self:clearSelection()
    core.List.setData(self, data)
end

function ToggleButtonList:setSelectedIndex(index)
    if self.selectedIndex == index then
        return
    end

    self.selectedIndex = index

    local delegate = self:delegateForIndex(index)
    if delegate then
        delegate:setSelected(true)
    end

    self:emit("selectedIndexChanged", index)
end

return ToggleButtonList
