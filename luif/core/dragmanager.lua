--
-- The drag manager keeps track of which item is currently attached to
-- the mouse.
-- The dragged item needs a tryApply() and cancelDragging() function.
-- The item's offsetX and offsetY are in virtual units.
--

local core = require "luif.core"

-- Lua 5.1 and LuaJIT have unpack, later versions table.unpack
local unpack = unpack or table.unpack

local DragManager = core.Object:extend {
    active = false,

    dragStart = false,  -- function(dragType)
    dragEnd = false,    -- function(dragType)
}

function DragManager:update()
    local x, y = core.Pointer.position()
    DragManager.active:setPos(x + DragManager.active.offsetX,
                              y + DragManager.active.offsetY)
end

function DragManager:startDragging(item, ...)
    local topLayer = core.TopLayer.instance()

    if DragManager.active then
        topLayer:removeChild(DragManager.active)
    else
        core.Update:connect("update", DragManager, DragManager.update)
    end

    item.offsetX = item.offsetX or 0
    item.offsetY = item.offsetY or 0

    item:start("appear", core.Scale {
        from = 0, to = 1,
        ease = core.Ease.outBack,
    })

    DragManager.originalParent = item.parent
    item:reparent(topLayer)
    DragManager.active = item
    DragManager:emit("dragStart", ...)
    DragManager.transferData = { ... }
end

function DragManager:cancelDragging()
    if not DragManager.active then
        return
    end

    local keepItem = DragManager.active:cancelDragging()
    if not keepItem then
        local topLayer = core.TopLayer.instance()
        topLayer:removeChild(DragManager.active)
        DragManager.active:delete()
    end
    DragManager.active = false
    DragManager:emit("dragEnd", unpack(DragManager.transferData))
    core.Update:disconnect("update", DragManager)
end

function DragManager:tryApply(...)
    if not DragManager.active then
        return
    end

    if DragManager.active:tryApply(...) then
        self:cancelDragging()
    end
end

function DragManager:isActive()
    return DragManager.active
end

return DragManager
