--
-- The item: the one class of the UI tree. Controls, images, text and layout
-- items are all items (core.Item). An item has a position and size for layouts,
-- children, states, input handling and focus, and describes one host node
-- that core/sync.lua keeps while the item is attached.
--
-- Lifetime: Sync.addRoot(item) registers a parentless item as a root and
-- Sync.removeRoot(item) unregisters it. An item is attached (isAttached())
-- while it is a root or its parent is attached, so adding, removing and
-- reparenting attach and detach whole subtrees. core/sync.lua creates,
-- moves and destroys the nodes in its next flush. Subclasses that need to
-- act when they join or leave a root override attached() and detached(),
-- which run after the whole subtree joined or left (children before their
-- parents).
--
-- Setters mark the item dirty (Sync.propertiesChanged, Sync.contentChanged,
-- Sync.childrenChanged); nothing reaches the host before the flush.
--

local core = require "luif.core"

local Host = core.Host
local MouseButton = core.MouseButton
local Object = core.Object
local Sounds = core.Sounds
local Pointer = core.Pointer
local Sync = core.Sync
local LayoutManager = core.LayoutManager
local Event = core.Event

-- A shared table used during drag-and-drop operations
local dragDataTransfer = {}
local dragTarget = nil

local Item = Object:extend {
    x = 0,
    y = 0,
    width = false,
    height = false,

    implicitWidth = 0,
    implicitHeight = 0,

    minimumWidth = 0,
    minimumHeight = 0,
    maximumWidth = math.huge,
    maximumHeight = math.huge,

    heightForWidth = false, -- Tells layouts that the height depends on width

    -- Properties used by AnchorLayout (in addition to x, y and size())
    left = false,
    top = false,
    right = false,
    bottom = false,
    verticalCenter = false,
    horizontalCenter = false,
    aspectRatio = false,

    -- Properties used by VerticalLayout
    marginLeft = 0,
    marginRight = 0,

    states = false,

    focusEnabled = false,
    mouseEnabled = false,
    draggable = false,      -- Implies mouseEnabled = true
    mouseCursor = false,    -- Set in the constructor or with setMouseCursor()

    alpha = 255,
    visible = true,
    enabled = true,
    active = true,
    clip = false,
    rotation = 0,
    scale = 1,
    transformOriginX = 0.5, -- Pivot of rotation and scale, as fractions of the size
    transformOriginY = 0.5,

    layout = false,

    resize = false,         -- function(width, height): item was resized
    move = false,           -- function(x, y): item was moved

    showEffect = false,
    showSound = false,
    hideEffect = false,
    hideSound = false,

    -- Event handlers

    mouseEnter = false,
    mouseLeave = false,
    mousePress = false,
    mouseRelease = false,
    mouseDoubleClick = false,
    mouseMove = false,
    mouseWheel = false,

    keyPress = false,
    keyRelease = false,
    keyCharacter = false,

    dragStart = false,      -- Delivered to source (needs to be draggable)
    drag = false,           -- Delivered to source each time mouse moves
    dragEnter = false,      -- Delivered to target (needs to be mouseEnabled)
    dragLeave = false,      -- Delivered to previous target
    dragOver = false,       -- Delivered to target
    drop = false,           -- Delivered to target
    dragEnd = false,        -- Delivered to source

    -- ToolTip information
    toolTip = false,
    toolTipClass = false,   -- Can be used to override the tool tip class

    -- Private members

    _root = false,          -- the root this item is attached under
    _contentOwner = false,  -- skinnable item whose skin content area this is
                            -- (layout invalidation reaches its layout)

    _hasMouse = false,
    _buttonDown = false,
    _dragging = false,

    _toolTipInstance = false,

    _visible = true,

    _emptyTransition = false,
    _runningTransition = false,
}

function Item.new(class, self)
    self = Object.new(class, self)

    if self.draggable or self.toolTip or self.toolTipClass then
        self.mouseEnabled = true
    end

    if self.layout then
        assert(not self.layout:isClass(), "Class used as layout")
        self.layout.target = self
        self.layout:update()
    end

    self:setShowEffect(self.showEffect)
    self:setHideEffect(self.hideEffect)
    self._visible = self.visible

    return self
end

--
-- Attaching and detaching
--

-- Sets _root on the item and its subtree and collects the items whose
-- attachment changed, children before their parents.
local function rebind(item, root, changed)
    local was = item._root
    item._root = root
    local children = item.children
    for i = 1, #children do
        rebind(children[i], root, changed)
    end
    if (was and true or false) ~= (root and true or false) then
        changed[#changed + 1] = item
    end
end

-- Moves the item and its subtree under root (false: detached) and runs the
-- side effects and hooks of joining or leaving.
local function setRoot(item, root)
    if item._root == root then
        return
    end
    local changed = {}
    rebind(item, root, changed)
    if #changed == 0 then
        return
    end
    Pointer.changed()
    if root then
        for i = 1, #changed do
            Sync.attached(changed[i])
        end
        for i = 1, #changed do
            local it = changed[i]
            if rawget(it, "_root") then
                it:attached()
            end
        end
    else
        for i = 1, #changed do
            local it = changed[i]
            Pointer.forget(it)
            if it._hasMouse then
                it._hasMouse = false
                core.MouseCursorManager:setCursor(false)
            end
            it:destroyToolTip()
        end
        for i = 1, #changed do
            local it = changed[i]
            if rawget(it, "_root") == false then
                it:detached()
            end
        end
    end
end

-- Hook: the item and its subtree joined a root.
function Item:attached()
end

-- Hook: the item and its subtree left their root.
function Item:detached()
end

-- Sync.addRoot and Sync.removeRoot call this: root is the item itself when
-- it became a root, false when its tree is detached.
function Item:_setRoot(root)
    setRoot(self, root)
end

-- Whether the item is in a registered root's tree.
function Item:isAttached()
    return self._root and true or false
end

-- Detaches the item from its tree, keeping its parent. Used before deletion.
function Item:_detach()
    if Sync.isRoot(self) then
        Sync.removeRoot(self)
    elseif self._root then
        Sync.childrenChanged(self.parent)
    end
    setRoot(self, false)
end

function Item:delete()
    self:_detach()

    if Pointer.focused() == self then
        Pointer.setFocused(nil)
    end

    if self == dragTarget then
        dragTarget = nil
    end

    if self._dragging then
        local event = { dataTransfer = dragDataTransfer }

        if dragTarget and dragTarget.dragLeave then
            dragTarget:dragLeave(event)
        end
        if self.dragEnd then
            self:dragEnd(event)
        end

        dragDataTransfer = {}   -- Reset the drag data
    end

    if self._runningTransition then
        self._runningTransition:cancel()
    end

    if self.layout then
        self.layout:delete()
        self.layout = nil
    end

    if self._toolTipInstance then
        self._toolTipInstance:delete()
    end

    local result = Object.delete(self)
    Sync.deleted(self)
    return result
end

--
-- Node description (see core/sync.lua)
--

function Item:describeNode(p)
    local width, height = self:size()
    p.x, p.y = self.x, self.y
    p.rotation = self.rotation ~= 0 and math.rad(self.rotation) or 0
    p.scale = self.scale
    p.originX, p.originY = self.transformOriginX * width, self.transformOriginY * height
    p.width, p.height = width, height
    p.opacity = self.alpha / 255
    p.visible = self._visible
    p.clip = self.clip
end

function Item:pushContent(host, node)
end

-- Geometry that the node and picking follow changed.
local function geometryChanged(self)
    if self._root then
        Sync.propertiesChanged(self)
        Pointer.changed()
    end
end

--
-- Geometry
--

function Item:size()
    return self.width or self.implicitWidth,
           self.height or self.implicitHeight
end

function Item:implicitSize()
    return self.implicitWidth, self.implicitHeight
end

-- Returns the content rect as left, top, right, bottom
function Item:contentRect()
    return 0, 0, self:size()
end

function Item:pos()
    return self.x, self.y
end

function Item:setPos(x, y)
    if self._root and (self.x ~= x or self.y ~= y) then
        Pointer.changed()
    end
    self.x = x
    self.y = y
    Sync.propertiesChanged(self)

    self:emit("move", x, y)
end

function Item:translate(dx, dy)
    self:setPos(self.x + dx, self.y + dy)
end

-- The sum of positions up the parents, ignoring rotation and scale.
function Item:absolutePos()
    local x, y = self.x, self.y
    local parent = self.parent
    while parent do
        x, y = x + parent.x, y + parent.y
        parent = parent.parent
    end
    return x, y
end

function Item:centerPos()
    local width, height = self:size()
    return self.x + width / 2,
           self.y + height / 2
end

function Item:centerOn(x, y)
    local width, height = self:size()
    self:setPos(math.floor(x - width / 2),
                math.floor(y - height / 2))
end

function Item:contains(x, y)
    if x >= 0 and y >= 0 then
        local width, height = self:size()
        return x < width and y < height
    end
    return false
end

function Item:invalidateParentLayout(reason)
    if self.parent then
        self.parent:invalidateLayout(self, reason)
    end
end

function Item:setX(x)
    self:setPos(x, self.y)
end

function Item:setY(y)
    self:setPos(self.x, y)
end

function Item:setSize(width, height)
    if self.width == width and self.height == height then
        return
    end

    self.width, self.height = width, height
    self:invalidateParentLayout()
    self:invalidateLayout()
    width, height = self:size()

    geometryChanged(self)

    self:emit("resize", width, height)
end

function Item:setWidth(width)
    self:setSize(width, self.height)
end

function Item:setHeight(height)
    self:setSize(self.width, height)
end

function Item:setImplicitWidth(width)
    local notify = not self.width and self.implicitWidth ~= width
    if notify then
        self:invalidateParentLayout()
    end
    self.implicitWidth = width
    if notify then
        geometryChanged(self)
        self:emit("resize", self:size())
    end
end

function Item:setImplicitHeight(height)
    local notify = not self.height and self.implicitHeight ~= height
    if notify then
        self:invalidateParentLayout()
    end
    self.implicitHeight = height
    if notify then
        geometryChanged(self)
        self:emit("resize", self:size())
    end
end

function Item:setFixedWidth(width)
    self.minimumWidth = width
    self.maximumWidth = width
    self:setWidth(width)
end

function Item:setFixedHeight(height)
    self.minimumHeight = height
    self.maximumHeight = height
    self:setHeight(height)
end

function Item:setFixedSize(width, height)
    self.minimumWidth = width
    self.maximumWidth = width
    self.minimumHeight = height
    self.maximumHeight = height
    self:setSize(width, height)
end

function Item:setMinimumWidth(width)
    if width < self.minimumWidth then
        self:setWidth(width)
    end
    self.minimumWidth = width
end

function Item:setMinimumHeight(height)
    if height < self.minimumHeight then
        self:setHeight(height)
    end
    self.minimumHeight = height
end

function Item:setMinimumSize(width, height)
    self:setMinimumWidth(width)
    self:setMinimumHeight(height)
end

function Item:setLeft(left)
    self.left = left
    self:invalidateParentLayout()
end

function Item:setTop(top)
    self.top = top
    self:invalidateParentLayout()
end

function Item:setRight(right)
    self.right = right
    self:invalidateParentLayout()
end

function Item:setBottom(bottom)
    self.bottom = bottom
    self:invalidateParentLayout()
end

function Item:setAnchors(left, top, right, bottom)
    self.left = left
    self.top = top
    self.right = right
    self.bottom = bottom
    self:invalidateParentLayout()
end

function Item:setVerticalCenter(verticalCenter)
    self.verticalCenter = verticalCenter
    self:invalidateParentLayout()
end

function Item:setHorizontalCenter(horizontalCenter)
    self.horizontalCenter = horizontalCenter
    self:invalidateParentLayout()
end

-- Override for special width/height handling
function Item:get(property)
    if property == "width" then
        return self.width or self.implicitWidth
    elseif property == "height" then
        return self.height or self.implicitHeight
    end
    return self[property]
end

local function mapToChild(node, child, x, y)
    if child == node then
        return x, y
    end

    x, y = mapToChild(node, child.parent, x, y)
    local scale = child.scale or 1
    return (x - child.x) / scale,
           (y - child.y) / scale
end

-- Maps the given coordinates from this item to the given item
function Item:mapToItem(item, x, y)
    if item == self then
        return x, y
    end

    local commonNode = Object.commonNode(self, item)

    -- Map from self to common parent
    local node = self
    while node ~= commonNode do
        local scale = node.scale or 1
        x = scale * x + node.x
        y = scale * y + node.y
        node = node.parent
    end

    -- Map from common parent down to other item
    return mapToChild(node, item, x, y)
end

-- Maps the given coordinates to this item from the given item
function Item:mapFromItem(item, x, y)
    return item:mapToItem(self, x, y)
end

-- clamps this to a rectangle area (absolute). Rect should be bigger than self. Children are not taken into account.
function Item:clampToRect(rectX, rectY, rectWidth, rectHeight)
    local x, y = self:absolutePos()

    local dx = 0
    local dy = 0

    if x < rectX then
        dx = rectX - x
    else
        local tdx = (rectX + rectWidth) - (x + self.width)
        if tdx < 0 then
            dx = tdx
        end
    end

    if y < rectY then
        dy = rectY - y
    else
        local tdy = (rectY + rectHeight) - (y + self.height)
        if tdy < 0 then
            dy = tdy
        end
    end

    if dx ~= 0 or dy ~= 0 then
        self:translate(dx, dy)
    end

end

--
-- Lets the item know which part of it is being exposed. Used by core.List
-- in combination with virtual layouts (see Layout:isVirtual)
--
function Item:setExposedArea(x, y, width, height)
end

--
-- Visibility and appearance
--

function Item:show(effect)
    self:setVisible(true, effect)
end

function Item:hide(effect)
    self:setVisible(false, effect)
end

local function completeHide(self)
    self._visible = false
    geometryChanged(self)
end

function Item:setVisible(visible, effect)
    visible = visible and true or false
    if self.visible == visible then
        return
    end
    self.visible = visible

    local sound
    if visible then
        effect = effect == nil and self.showEffect or effect
        sound = self.showSound
    else
        effect = effect == nil and self.hideEffect or effect
        sound = self.hideSound
    end

    if effect then
        if not visible then
            effect.finish = function() completeHide(self) end
        end
        self:start("showHide", effect)
    else
        self:stop("showHide")   -- make sure any running effect still stops
    end

    if sound then
        Sounds.play(sound)
    end

    -- Show right away, and hide right away when there is no hide effect
    if visible or not effect then
        self._visible = visible
        geometryChanged(self)
    end

    -- Give up focus when going invisible
    if not visible then
        local focusItem = Pointer.focused()
        if self == focusItem or self:isAncestorOf(focusItem) then
            focusItem:setFocus(false)
        end
    end
end

function Item:isAncestorOf(child)
    while child do
        child = child.parent
        if self == child then
            return true
        end
    end
    return false
end

function Item:setEnabled(enabled)
    enabled = enabled and true or false
    self.enabled = enabled
end

-- Stored only: inactive items are still drawn and picked.
function Item:setActive(active)
    self.active = active
end

function Item:setClip(clip)
    clip = clip and true or false
    if self.clip == clip then
        return
    end

    self.clip = clip
    geometryChanged(self)
end

function Item:setAlpha(alpha)
    if self.alpha == alpha then
        return
    end

    self.alpha = alpha
    geometryChanged(self)
end

function Item:setRotation(rotation)
    if self.rotation == rotation then
        return
    end

    self.rotation = rotation
    geometryChanged(self)
end

function Item:setScale(scale)
    if self.scale == scale then
        return
    end

    self.scale = scale
    geometryChanged(self)
end

function Item:scaledSize()
    local w,h = self:size()
    return w*self.scale, h*self.scale
end

function Item:setTransformOriginX(originX)
    self:setTransformOrigin(originX, self.transformOriginY)
end

function Item:setTransformOriginY(originY)
    self:setTransformOrigin(self.transformOriginX, originY)
end

-- The pivot of rotation and scale as fractions of the size: 0, 0 is the top
-- left, 0.5, 0.5 (the default) the centre and 1, 1 the bottom right.
function Item:setTransformOrigin(originX, originY)
    if self._root and (self.transformOriginX ~= originX or self.transformOriginY ~= originY) then
        Pointer.changed()
    end
    self.transformOriginX = originX
    self.transformOriginY = originY
    Sync.propertiesChanged(self)
end

-- Centres the item on the virtual screen (meant for roots).
function Item:centerOnScreen()
    local screenWidth, screenHeight = core.Update.virtualScreenWidth, core.Update.virtualScreenHeight
    local width, height = self:size()
    self:setPos(math.floor((screenWidth - width) / 2),
                math.floor((screenHeight - height) / 2))
end

--
-- Children
--

-- The item that holds children given to this item with setParent: the item
-- itself, or a skinnable item's content area.
function Item:contentParent()
    return self
end

--
-- Changes the parent of this item. An attached item stays attached (and
-- keeps its node) when the new parent is attached, and is detached
-- otherwise. setParent(false) detaches; Sync.addRoot makes it a root again.
-- A skinnable item's content area takes the children set onto the item.
--
function Item:setParent(parent)
    if parent and parent.skin ~= self then
        parent = parent:contentParent()
    end
    parent = parent or false
    if self.parent == parent then
        return
    end

    local oldParent = self.parent
    local wasRoot = not oldParent and Sync.isRoot(self)
    if oldParent then
        if self._root then
            Sync.childrenChanged(oldParent)
        end
        oldParent:invalidateLayout(self, "remove")
        Object.removeChild(oldParent, self)
    end

    if parent then
        Object.insertChild(parent, #parent.children + 1, self)
        parent:invalidateLayout(self, "add")
        if parent._root then
            Sync.childrenChanged(parent)
        end
    end

    -- A root that moves into an attached tree stays attached: it joins the
    -- new root before it is unregistered
    setRoot(self, parent and parent._root or false)
    if wasRoot then
        Sync.removeRoot(self)
    end
    Pointer.changed()
end

--
-- Changes the parent of this item while keeping the position the same.
-- Does not handle scale and rotation.
--
function Item:reparent(parent)
    if parent and parent.skin ~= self then
        parent = parent:contentParent()
    end
    if self.parent == parent then
        return
    end

    local x, y = self:absolutePos()
    local px, py = 0, 0
    if parent then
        px, py = parent:absolutePos()
    end

    self:setParent(parent)
    self:setPos(x - px, y - py)
end

function Item:setLayout(layout)
    if self.layout == layout then
        return
    end

    if self.layout then
        self.layout:delete()
    end

    self.layout = layout
    if self.layout then
        self.layout.target = self
        self.layout:invalidate()
    end
end

function Item:invalidateLayout(child, reason)
    if self.layout then
        self.layout:invalidate(child, reason)
    end

    -- The item owning a skin content area lays out its content children
    local owner = self._contentOwner
    if owner and owner.contentArea == self then
        owner:invalidateLayout(child, reason)
    end
end

--
-- Convenience function that tries to make sure an item hierarchy is
-- correctly laid out.
--
function Item:validateLayoutRecursively()
    -- Layout this item's layout when it has one
    local layout = self.layout
    if layout then
        LayoutManager:validateLayout(layout)
    end

    -- Layout all children, recursively
    for i=1,#self.children do
        local child = self.children[i]
        if child.validateLayoutRecursively then
            child:validateLayoutRecursively()
        end
    end

    -- Make sure this item's layout is still valid, it may have been
    -- invalidated by children changing size
    if layout then
        LayoutManager:validateLayout(layout)
    end
end

function Item:setShowEffect(effect)
    if self.showEffect then
        self.showEffect:setRunning(false)
    end

    self.showEffect = effect
end

function Item:setHideEffect(effect)
    if self.hideEffect then
        self.hideEffect:setRunning(false)
    end

    self.hideEffect = effect
end

--
-- Moves this item to the end of the list of children of its parent (or of
-- the roots), bringing it on top because it will be the last one drawn.
--
function Item:moveToTop()
    local parent = self.parent
    if parent then
        local children = parent.children
        if self ~= children[#children] then
            table.remove(children, core.Array.find(children, self))
            table.insert(children, self)

            if self._root then
                Sync.childrenChanged(parent)
                Pointer.changed()
            end
        end
    elseif Sync.isRoot(self) and Sync.roots()[#Sync.roots()] ~= self then
        Sync.raiseRoot(self)
        Pointer.changed()
    end
end

--
-- Override that makes sure the layout is invalidated and the child attached.
--
function Item:insertChild(index, child)
    if Sync.isRoot(child) then
        Sync.removeRoot(child)
    end

    Object.insertChild(self, index, child)

    if self._root then
        Sync.childrenChanged(self)
        setRoot(child, self._root)
    end

    self:invalidateLayout(child, "add")
    return child
end

function Item:addChild(child)
    return self:insertChild(#self.children + 1, child)
end

--
-- Override that makes sure the layout is invalidated and the child detached.
--
function Item:removeChild(child)
    if child._root then
        Sync.childrenChanged(self)
        setRoot(child, false)
    end

    Object.removeChild(self, child)

    self:invalidateLayout(child, "remove")
end

function Item:removeChildren()
    local children = self.children
    for i = 1, #children do
        local child = children[i]
        if child._root then
            Sync.childrenChanged(self)
            setRoot(child, false)
        end
    end

    Object.removeChildren(self)
end

function Item:setChildren(children)
    self:removeChildren()

    Object.setChildren(self, children)

    if self._root then
        Sync.childrenChanged(self)
        for i = 1, #children do
            setRoot(children[i], self._root)
        end
    end

    self:invalidateLayout()
end

function Item:deleteChild(child)
    self:removeChild(child)
    child:deleteLater()
end

--
-- Focus: one item has the focus, a reference kept by core.Pointer. Keys go
-- to it while it is attached. A focused item that is detached keeps the
-- focus, and gets keys again when attached, unless the focus moved; deleting
-- it clears the focus.
--

function Item:setFocus(focus)
    focus = focus == nil or focus
    local current = Pointer.focused()

    if focus and self == current then
        return  -- This item already has focus
    end

    if current then
        current:focusLose()
    end

    if focus then
        Pointer.setFocused(self)
        self:focusGain()
    else
        Pointer.setFocused(nil)
    end
end

function Item:hasFocus()
    return Pointer.focused() == self
end

function Item:focusGain()
    local focusScope = self:parentFocusScope()
    if focusScope then
        focusScope:setFocusItem(self)
    end
end

function Item:focusLose()
end

function Item:parentFocusScope()
    local parent = self.parent
    if parent then
        if parent:as(core.FocusScope) then
            return parent
        end
        return parent:parentFocusScope()
    end
end

--
-- Input
--

-- Only mouse enabled items are picked and receive raw events; the events
-- of an item that stops being mouse enabled go to the fallback listener.
function Item:setMouseEnabled(mouseEnabled)
    if self.mouseEnabled == mouseEnabled then
        return
    end

    self.mouseEnabled = mouseEnabled

    if self._root then
        Pointer.changed()
    end

    if not mouseEnabled and self._hasMouse then
        self._hasMouse = false
        core.MouseCursorManager:setCursor(false)
    end
end

function Item:setDraggable(draggable)
    self.draggable = draggable
end

function Item:setMouseCursor(mouseCursor)
    self.mouseCursor = mouseCursor

    if self._hasMouse then
        core.MouseCursorManager:setCursor(mouseCursor)
    end
end

-- setMouseCursorUntilNextLeave() applies a mouse pointer, which is automatically removed on the next "mouseLeave".
-- This is useful, if you want to use a button to start a mouse mode:
-- We want instant feedback for the mouse mode, so we instantly set the changed mouse cursor.
-- Once the mouse has left the button, we want in opposite the standard mouse cursor of the button again.
function Item:setMouseCursorUntilNextLeave(mouseCursor)
    -- mouse cursor until next leave is only used by items that currently have the mouse, else silently ignored
    if not self._hasMouse then
        return
    end
    core.MouseCursorManager:setCursor(mouseCursor or self.mouseCursor)
end

local function systemTimeSeconds()
    return Host.time() / 1000
end

-- Set on the first event or idleTime() call, so loading needs no host
local lastEventTime = false
local nonIdleEvents = {
    mouseRelease = true,
    mousePress = true,
    mouseDoubleClick = true,
    mouseWheel = true,
    keyPress = true,
    keyRelease = true,
    keyCharacter = true,
}

--
-- Returns the idle time in seconds. Mouse movement does not reset idle time.
--
function Item.idleTime()
    if not lastEventTime then
        lastEventTime = systemTimeSeconds()
    end
    return systemTimeSeconds() - lastEventTime
end

function Item.resetIdleTime()
    lastEventTime = systemTimeSeconds()
end

--
-- The pointer's entry point for an event (core/event.lua) delivered to this
-- item: idle time, mouse cursor, drag and drop and tooltips, then event()
-- dispatches to the handler and bubbles. Generally not the function you'll
-- want to override.
--
function Item:handleEvent(event)
    event.source = self

    if nonIdleEvents[event.name] then
        Item.resetIdleTime()
    end

    -- Update the mouse cursor and tooltip
    if event.name == "mouseEnter" then
        self._hasMouse = true
        core.MouseCursorManager:setCursor(self.mouseCursor)
    elseif event.name == "mouseLeave" then
        core.MouseCursorManager:setCursor(false)
        self._hasMouse = false
    end

    if self.draggable then
        event.dataTransfer = dragDataTransfer

        -- Handle drag-n-drop support
        if event.name == "mousePress" then
            if event:button() == MouseButton.Left then
                self._buttonDown = true
            end
        elseif event.name == "mouseMove" then
            if self._buttonDown and not self._dragging then
                if self.dragStart and self:dragStart(event) ~= false then
                    self._dragging = true
                end
            end
            if self._dragging then
                local target = Item.pick()
                if target ~= dragTarget then
                    if dragTarget and dragTarget.dragLeave then
                        dragTarget:dragLeave(event)
                    end
                    if target and target.dragEnter then
                        target:dragEnter(event)
                    end
                    dragTarget = target
                end

                if self.drag then
                    self:drag(event)
                end
                if dragTarget and dragTarget.dragOver then
                    dragTarget:dragOver(event)
                end
            end
        elseif event.name == "mouseRelease" then
            if event:button() == MouseButton.Left then
                self._buttonDown = false
            end
            if self._dragging then
                self._dragging = false
                if dragTarget and dragTarget.drop then
                    dragTarget:drop(event)
                    dragTarget = nil
                end
                if self.dragEnd then
                    self:dragEnd(event)
                end

                dragDataTransfer = {}   -- Reset the drag data
            end
        end
    end

    local accepted = self:event(event)

    if event.name == "mouseMove" then
        if self.toolTip and not self._toolTipInstance then
            if event:dx() ~= 0 or event:dy() ~= 0 then
                local x, y = event:absolutePos()
                local timeout = self.toolTipClass and self.toolTipClass.timeout or 150
                self:setTimeout("toolTipTimeout", timeout, function()
                    self:createToolTip(x, y)
                end)
            end
        end
    elseif event.name == "mouseLeave" then
        self:destroyToolTip()
    end

    return accepted
end

function Item:setToolTip(toolTip)
    if self.toolTip == toolTip then
        return
    end

    self.toolTip = toolTip
    self:updateToolTip()
end

function Item:setToolTipClass(toolTipClass)
    if self.toolTipClass == toolTipClass then
        return
    end

    self.toolTipClass = toolTipClass
    self:destroyToolTip()
end

function Item:createToolTip(x, y)
    if not self._hasMouse or not self.toolTip then
        return
    end

    local toolTipInstance = (self.toolTipClass or core.LabelToolTip) {
        item = self,
        mouseX = x,
        mouseY = y,
        alpha = 0,
        visible = false,
    }
    Sync.addRoot(toolTipInstance)
    toolTipInstance:show(core.Fade {
        from = 0, to = 255,
        duration = 70,
    })

    self._toolTipInstance = toolTipInstance
end

function Item:updateToolTip()
    if self._toolTipInstance then
        if not self.toolTip then
            self:destroyToolTip()
        else
            self._toolTipInstance:update()
        end
    end
end

function Item:destroyToolTip(animate)
    self:clearTimeout("toolTipTimeout")
    if not self._toolTipInstance then
        return
    end

    -- Disown the tool tip instance
    local toolTipInstance = self._toolTipInstance
    toolTipInstance.item = false
    self._toolTipInstance = false

    if animate == nil or animate then
        toolTipInstance:start("destroy", core.Sequence {
            target = toolTipInstance,
            core.Pause { duration = self.toolTipClass and self.toolTipClass.fadeOutPause or 50 },
            core.Fade {
                from = 255, to = 0,
                duration = self.toolTipClass and self.toolTipClass.fadeOutTime or 70
            },
            finish = function()
                toolTipInstance:delete()
            end,
        })
    else
        toolTipInstance:delete()
    end
end

--
-- This function delivers the event, and bubbles it up to parents when it is
-- not handled or ignored.
--
function Item:event(event)
    local handler = self[event.name]
    local accepted

    if handler then
        handler(self, event)
        accepted = event.accepted
    end

    if not accepted and self.parent and event.bubble then
        -- Reset the event back to accepted
        event.accepted = true

        -- Map the mouse coordinates into the parent's space. Going through
        -- the window position accounts for rotation and scale.
        if event.localX and event.localY then
            local parent = self.parent
            if parent._root and event.absX and event.absY then
                event.localX, event.localY = Pointer.toLocal(parent, event.absX, event.absY)
            else
                event.localX = event.localX + self.x
                event.localY = event.localY + self.y
            end
        end

        accepted = self.parent:event(event)
    end

    return accepted
end

--
-- Returns the item currently under the mouse, if any. Only works for items
-- that are mouse-enabled.
--
function Item.pick()
    local item = Pointer.pick(Pointer.position())
    return item
end

--
-- Scrolls the contents of the viewport so that the rectangle at (x,y) is
-- visible, with margins specified in pixels by xmargin and ymargin. If the
-- specified rect cannot be reached, the content is scrolled to the nearest
-- valid position.
--
function Item:ensureVisible(x, y, width, height, xmargin, ymargin)
    width = width or 1
    height = height or 1
    xmargin = xmargin or 50
    ymargin = ymargin or 50

    if not x or not y then
        return
    end

    if self.parent then
        return self.parent:ensureVisible(x + self.x, y + self.y, width, height, xmargin, ymargin)
    end
end

return Item
