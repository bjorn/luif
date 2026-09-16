local core = require "luif.core"
local Object = core.Object

local DragFollowHelper = Object:extend {
    target = false,
    reparentTarget = false,
    _previousParent = false
}

function DragFollowHelper:onDragStart(event)
    event.dataTransfer._helper = {}

    event.dataTransfer._helper.startX, event.dataTransfer._helper.startY = self.target:pos()

    if self.reparentTarget then
        self._previousParent = self.target.parent
        self.target:reparent(self.reparentTarget)
    end

    self.target:translate(event:dx(), event:dy())

    local clickPosX, clickPosY = event:absolutePos()
    local myPosX, myPosY = self.target:absolutePos()

    event.dataTransfer._helper.dx = clickPosX - myPosX
    event.dataTransfer._helper.dy = clickPosY - myPosY
end

function DragFollowHelper:onDrag(event)
    if not event.dataTransfer._helper then
        return
    end

    local myPosX, myPosY = self.target:absolutePos()
    local dragPosX, dragPosY = event:absolutePos()

    self.target:translate(dragPosX - myPosX - event.dataTransfer._helper.dx, dragPosY - myPosY - event.dataTransfer._helper.dy)
end

function DragFollowHelper:resetOnDragEnd(event)
    if not event.dataTransfer._helper then
        return
    end

    if self._previousParent then
        self.target:reparent(self._previousParent)
        self._previousParent = false
    end

    self.target:setPos(event.dataTransfer._helper.startX, event.dataTransfer._helper.startY)
    event.dataTransfer._helper = nil
end

return DragFollowHelper
