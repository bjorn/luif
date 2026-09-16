--
-- Helper class that represents a focus scope. Active focus scopes form
-- a stack of fallback listeners.
--

local core = require "luif.core"

local Item = core.Item
local FallbackListeners = core.FallbackListeners

local FocusScope = Item:extend {
    focusItem = false,
    active = false,
}

function FocusScope.new(class, self)
    self = Item.new(class, self)
    if self.active then
        if self.focusItem then
            self.focusItem:setFocus()
        end
        FallbackListeners.push(self)
    end
    return self
end

function FocusScope:delete()
    if self.active then
        FallbackListeners.remove(self)
    end
    Item.delete(self)
end

function FocusScope:setFocusItem(item)
    self.focusItem = item
end

function FocusScope:activate()
    self:setActive(true)
end

function FocusScope:deactivate()
    self:setActive(false)
end

function FocusScope:setActive(active)
    active = active and true or false

    if self.active == active then
        return
    end

    Item.setActive(self, active)

    if active then
        if self.focusItem then
            self.focusItem:setFocus()
        end
        FallbackListeners.push(self)
    else
        FallbackListeners.remove(self)
    end
end

return FocusScope
