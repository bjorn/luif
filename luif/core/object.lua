--
-- Object extends Class with the ability to assign an 'id' to an instance
-- and keeps a list of children.
--
-- It also adds a way to send and listen for notifications.
--

local core = require "luif.core"

local Array = core.Array
local Class = core.Class

local sender
local currentEvent
local pendingRemovals

local Object = Class:extend {
    -- Objects may have an id by which they can be found in the hierarchy
    id = false,

    -- The parent of the object. Is set automatically by the parent.
    parent = false,

    -- The children of the object, indexed by index and by their id.
    children = false,

    -- State handling
    state = "",
    states = false,
    transitions = false,
    stateChanged = false, -- function(newState)

    -- Provides a way for classes to check whether they are being deleted when
    -- events may come in due to the deletion of child objects.
    deleting = false,

    -- Event listeners: a table mapping event names to a table of listeners.
    _listeners = false,

    -- A list of connections, when made with Object.connect
    _connections = false,

    -- A set of connection sources with a count of connections for each
    _connectionSources = false,

    -- A map of named timeouts that will be cleared on deletion
    _timeouts = false,

    -- A map of named effects owned by this object that will be automatically
    -- stopped when the object gets deleted or when a new effect with the same
    -- name is started.
    _effects = false,
}

--
-- Constructs a new object.
--
function Object.new(class, self)
    self = Class.new(class, self)

    assert(not self.id or type(self.id) == "string", "Object id must be a string!")

    self.children = self.children or {}
    for i=1,#self.children do
        local child = self.children[i]
        child.parent = self
        if child.id then
            assert(self.children[child.id] == nil, "Duplicate Object id: " .. child.id)
            self.children[child.id] = child
        end
    end

    -- Add children specified "inline"
    for i=1,#self do
        local child = self[i]
        assert(type(child) == "table", "Invalid inline child value")
        Object.insertChild(self, #self.children + 1, child)
    end

    return self
end

--
-- Deleting an object explicitly is needed in some cases. It makes sure any
-- connections to other objects are disconnected.
--
-- Also deletes any children of this object.
--
-- See also Class.delete
--
function Object:delete()
    self.deleting = true

    -- clear timeouts
    if self._timeouts then
        local Update = core.Update
        for name, timeout in pairs(self._timeouts) do
            Update:clearTimeout(timeout)
        end
    end

    -- stop effects
    if self._effects then
        for name, effect in pairs(self._effects) do
            effect:stop()
        end
    end

    -- remove outgoing connections
    if self._connections then
        for i=#self._connections,1,-1 do
            local connection = self._connections[i]
            self:disconnect(connection.event, connection.target)
        end
    end

    -- remove incoming connections
    if self._connectionSources then
        for source in pairs(self._connectionSources) do
            source:disconnect(nil, self)
        end
    end

    assert(not self._connections)

    -- delete in reverse order because children will be removed from the list
    for i=#self.children,1,-1 do
        self.children[i]:delete()
    end
    assert(#self.children == 0)

    -- remove myself from parent object children list
    if self.parent then
        self.parent:removeChild(self)
    end

    return Class.delete(self)
end

--
-- Returns the depth of this object in the object hierarchy.
--
function Object:depth()
    local depth = 0
    local parent = self.parent
    while parent do
        depth = depth + 1
        parent = parent.parent
    end
    return depth
end

--
-- Returns the root object of this object hierarchy.
--
function Object:root()
    local root = self
    while root.parent do
        root = root.parent
    end
    return root
end

--
-- Returns the first node in the hierarchy that is shared between object A and
-- object B. This can be object A or object B itself, or it can be false if
-- there is none. In other cases it is the least common parent.
--
function Object.commonNode(objectA, objectB)
    local depthA = objectA:depth()
    local depthB = objectB:depth()

    -- Make sure to start comparing at a common depth
    while depthA > 0 and depthA > depthB do
        objectA = objectA.parent
        depthA = depthA - 1
    end
    while depthB > 0 and depthB > depthA do
        objectB = objectB.parent
        depthB = depthB - 1
    end

    -- Move upwards until the common parent is found
    while objectA ~= objectB do
        objectA = objectA.parent
        objectB = objectB.parent
    end

    return objectA
end

--
-- Inserts the given child object at the given index.
--
function Object:insertChild(index, child)
    table.insert(self.children, index, child)
    child.parent = self
    if child.id then
        assert(self.children[child.id] == nil, "Duplicate Object id!")
        self.children[child.id] = child
    end
    return child
end

--
-- Adds the given child object to this object.
--
function Object:addChild(child)
    return self:insertChild(#self.children + 1, child)
end

--
-- Adds the given list of objects as children of this object.
--
function Object:addChildren(...)
    for i=1,select('#', ...) do
        self:addChild(select(i, ...))
    end
end

--
-- Removes the given child from the list of children.
--
function Object:removeChild(child)
    -- Iterating backwards because children are deleted in reverse order in
    -- Object.delete, so most commonly the child to be removed is the last
    -- one.
    for i=#self.children,1,-1 do
        if self.children[i] == child then
            table.remove(self.children, i)
            child.parent = false
            if child.id then
                self.children[child.id] = nil
            end
            return
        end
    end
    error("Child not found")
end

--
-- Removes all children.
--
function Object:removeChildren()
    for i=1,#self.children do
        local child = self.children[i]
        child.parent = false
        self.children[i] = nil
        if child.id then
            self.children[child.id] = nil
        end
    end
end

--
-- Replaces the children of this object with the given list of objects.
--
function Object:setChildren(children)
    self.children = children

    for i=1,#self.children do
        local child = self.children[i]
        child.parent = self
        if child.id then
            assert(self.children[child.id] == nil, "Duplicate Object id!")
            self.children[child.id] = child
        end
    end
end

--
-- The children that id lookups and state changes see, as the list and the
-- index of the first one: all children here. A SkinnableItem overrides
-- this to return its content instead of its skin.
--
function Object:contentChildren()
    return self.children, 1
end

--
-- Find an object with the specified id in the hierarchy. Returns false if no
-- such object could be found.
--
function Object:findChild(id)
    local children, first = self:contentChildren()
    local child = children[id]
    if child and (first == 1 or child ~= children[1]) then
        return child
    end
    for i=first,#children do
        child = children[i]:findChild(id)
        if child then
            return child
        end
    end
    return false
end

local function findChildren(object, children, result)
    local list, first = object:contentChildren()
    for i=first,#list do
        local child = list[i]
        local id = child.id
        if id and children[id] ~= nil then
            result[id] = child
        end
        findChildren(child, children, result)
    end
    return result
end

--
-- Finds a set of children in the hierarchy. This function always traverses
-- the entire hierarchy, but it does so only once to find all given children.
--
-- @param children a table where the keys are object ids
-- @param result   the result, with each id associated with a child if found
--                 (defaults to 'children')
--
function Object:findChildren(children, result)
    return findChildren(self, children, result or children)
end

--
-- Same as findChildren, but raises an error when one of the children can't be found.
--
function Object:requireChildren(children, result)
    result = self:findChildren(children, result)
    for id in pairs(children) do
        if type(result[id]) ~= "table" then
            error("Child not found: " .. tostring(id))
        end
    end
    return result
end

--
-- Finds a list of children by their ID in the hierarchy, assigning each to
-- a member variable by the same name.
--
-- Raises an error when one of the children can't be found.
--
function Object:resolveChildren(idArray)
    return self:requireChildren(Array.toSet(idArray), self)
end

local setters = setmetatable({}, {
    __index = function(cache, property)
        local setter =  "set" .. property:gsub("^%l", string.upper)
        rawset(cache, property, setter)
        return setter
    end
})

--
-- Using this method to set a property causes the setter to be used, when
-- available.
--
function Object:set(property, value, ...)
    local setter = self[setters[property]]
    if setter then
        setter(self, value, ...)
    else
        self[property] = value
    end
end

--
-- Using this method to get a property allows subclasses to do special
-- handling (it does not automatically use a getter because most properties
-- do not have (or need) one).
--
function Object:get(property)
    return self[property]
end

--
-- Adds a listener that is called on a certain event.
--
function Object:on(event, callback)
    assert(type(callback) == "function", "function expected as callback")
    assert(self[event] ~= nil, "trying to connect to undocumented event")

    self._listeners = self._listeners or {}

    local listeners = self._listeners[event] or {}
    listeners[#listeners + 1] = callback
    self._listeners[event] = listeners
end

--
-- Removes a listener from the given event.
-- Returns true when the listener was successfully removed.
--
function Object:removeListener(event, callback)
    if self == sender and currentEvent == event then
        -- Avoid modifying listener table while iterating it
        pendingRemovals = pendingRemovals or {}
        pendingRemovals[callback] = event
        return true
    end

    local listeners = self._listeners[event]

    for i=1,#listeners do
        if listeners[i] == callback then
            table.remove(listeners, i)

            -- Clean up tables that we no longer need
            if #listeners == 0 then
                self._listeners[event] = nil
                if not next(self._listeners) then
                    self._listeners = false
                end
            end

            return true
        end
    end
end

--
-- Convenience function for connecting a signal to a member function.
--
-- Connections made this way should be disconnected using Object.disconnect.
-- The connection is automatically disconnected when either this object or the
-- target object is deleted.
--
-- Examples:
--
--   sourceObject:connect("event", targetObject, "member")
--   sourceObject:connect("event", targetObject, targetObject.member)
--
function Object:connect(event, target, member)
    member = (type(member) == "function") and member or target[member]

    assert(target, "No target object given")
    assert(type(event) == "string", "No valid event name given")
    assert(type(member) == "function", "No valid member function given")

    local callback = function(...)
        return member(target, ...)
    end
    self:on(event, callback)

    self._connections = self._connections or {}
    self._connections[#self._connections + 1] = {
        source = self,
        event = event,
        target = target,
        callback = callback
    }

    target._connectionSources = target._connectionSources or {}
    target._connectionSources[self] = (target._connectionSources[self] or 0) + 1
end

--
-- Disconnect signals previously connected using Object.connect.
-- Returns the number of disconnections.
--
-- Examples:
--
--   sourceObject:disconnect(targetObject)          -- Disconnect all connections to targetObject
--   sourceObject:disconnect("event", targetObject) -- Disconnect all connections to targetObject for "event"
--
function Object:disconnect(event, target)
    assert(event or target)
    if target == nil then
        target = event
        event = nil
    end

    if not self._connections then
        return
    end

    local count = 0
    for i=#self._connections,1,-1 do
        local connection = self._connections[i]
        if connection.source == self and
           (not event or connection.event == event) and
           (not target or connection.target == target) then
            assert(connection.source:removeListener(connection.event, connection.callback), "Error while removing listener")
            table.remove(self._connections, i)
            local connectionSources = connection.target._connectionSources
            connectionSources[connection.source] = connectionSources[connection.source] - 1
            if connectionSources[connection.source] == 0 then
                connectionSources[connection.source] = nil
            end
            count = count + 1
        end
    end

    if #self._connections == 0 then
        self._connections = false
    end

    return count
end

--
-- Emits a certain event with arbitrary parameters.
--
function Object:emit(event, ...)
    local previousSender = sender
    local previousEvent = currentEvent
    local previousPendingRemovals = pendingRemovals
    sender = self
    currentEvent = event
    pendingRemovals = nil
    local result

    local eventListeners = self._listeners and self._listeners[event]
    local inlineListener = self[event]

    if inlineListener then
        result = inlineListener(...)
    end
    if eventListeners then
        for i=1,#eventListeners do
            local callback = eventListeners[i]
            if not pendingRemovals or not pendingRemovals[callback] then
                result = callback(...)
            end
        end
    end

    sender = previousSender
    currentEvent = previousEvent

    if pendingRemovals then
        for callback, event in pairs(pendingRemovals) do
            self:removeListener(event, callback)
        end
    end

    pendingRemovals = previousPendingRemovals

    return result
end

function Object:toString()
    return self.id or Class.toString(self)
end

--
-- Returns the sender of the received event.
--
function Object.sender()
    return sender
end

function Object:setTimeout(name, delay, callback)
    self._timeouts = self._timeouts or {}

    -- Clear any timeout with the same name
    local timeout = self._timeouts[name]
    if timeout then
        core.Update:clearTimeout(timeout)
    end

    timeout = core.Update:setTimeout(delay, function() self._timeouts[name] = nil; return callback and callback() end)
    self._timeouts[name] = timeout
    return timeout
end

function Object:clearTimeout(name)
    if self._timeouts then
        core.Update:clearTimeout(self._timeouts[name])
        self._timeouts[name] = nil
    end
end

function Object:hasTimeout(name)
    return self._timeouts and self._timeouts[name]
end

--
-- Starts the given effect, stopping any existing effect with the same name.
-- The effect is automatically stopped when the object is deleted.
--
-- The target of the effect will default to this object.
--
function Object:start(name, effect)
    self._effects = self._effects or setmetatable({}, { __mode = "v" })

    local existingEffect = self._effects[name]
    if existingEffect then
        existingEffect:stop()
    end

    if not effect.target then
        effect:setTarget(self)
    end

    self._effects[name] = effect
    effect:start()
    return effect
end

function Object:stop(name)
    local effect = self._effects and self._effects[name]
    if effect then
        effect:stop()
    end
end

function Object:isRunning(name)
    local effect = self._effects and self._effects[name]
    return effect and effect.running
end

function Object:setState(state, animate)
    if self.state == state then
        return
    end

    animate = (animate == nil) and true or animate

    local oldState = self.state
    self.state = state

    if self.deleting then
        -- Applying state changes is both dangerous and useless
        -- while the object and its children are being deleted.
        return
    end

    -- See if there is a transition matching this state change
    local transitions = self.transitions
    local transition
    if animate and transitions then
        for i=1,#transitions do
            local t = transitions[i]
            if t:matches(oldState, state) then
                transition = t
                break
            end
        end
    end

    -- When no transition was found, use an empty transition
    if not transition then
        self._emptyTransition = self._emptyTransition or core.Transition {}
        transition = self._emptyTransition
    end
    transition:apply(self, oldState, state)

    self:emit("stateChanged", state)
end

return Object
