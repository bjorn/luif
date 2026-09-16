local core = require "luif.core"

local Object        = core.Object

local LayoutManager = Object:extend {
    layoutInvalid = {},
    layoutFinished = false, -- function
    invalidatedLayoutsCount = 0,
}

function LayoutManager:invalidateLayout(layout)
    if self.invalidatedLayoutsCount >= 99999 then
        return  -- An endless layout loop; stop invalidating
    end
    if not self.layoutInvalid[layout] then
        self.layoutInvalid[layout] = true
        self.invalidatedLayoutsCount = self.invalidatedLayoutsCount + 1
    end
end

function LayoutManager:cancelLayout(layout)
    if self.layoutInvalid[layout] then
        self.layoutInvalid[layout] = nil
        self.invalidatedLayoutsCount = self.invalidatedLayoutsCount - 1
    end
end

function LayoutManager:validate()
    -- Updating layouts may invalidate others. That it won't loop infinitely
    -- depends on the stabilization effect of the different layouts.
    while next(self.layoutInvalid) do
        local layoutInvalid = self.layoutInvalid
        self.layoutInvalid = {}

        for layout in pairs(layoutInvalid) do
            layout:update()
            layout.invalid = false
            layout.invalidatedItems = false
        end
    end

    self.invalidatedLayoutsCount = 0
    self:emit("layoutFinished")
end

function LayoutManager:validateLayout(layout)
    if not layout.invalid then
        return
    end

    self:cancelLayout(layout)
    layout:update()
    layout.invalid = false
    layout.invalidatedItems = false
end

return LayoutManager
