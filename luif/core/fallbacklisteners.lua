--
-- Maintains a stack of fallback listeners.
-- Handles all the events that were not accepted by items.
--
-- A fallback listener is a table that conforms to the following policy:
--
-- T:event(event) : true <consumed> | false <pass on>
--
-- The 'Item' class conforms to this interface and provides an additional
-- set of convenience methods to which the different events are dispatched.
--

local core = require "luif.core"

local Array = core.Array
local Class = core.Class
local Pointer = core.Pointer

local stack = Array {}

local FallbackListeners = Class:extend {
}

function FallbackListeners.push(listener)
    assert(type(listener) == "table")
    assert(type(listener.event) == "function", "no 'event' member present")

    stack[#stack + 1] = listener
end

--
-- To be used when you want to make sure you're the last listener to get the event, after any
-- already active listeners.
--
function FallbackListeners.pushBottom(listener)
    assert(type(listener) == "table")
    assert(type(listener.event) == "function", "no 'event' member present")

    table.insert(stack, 1, listener)
end

function FallbackListeners.remove(listener)
    for i = #stack,1,-1 do
        if stack[i] == listener then
            stack:remove(i)
            return
        end
    end
    error("listener not found")
end

function FallbackListeners.clear()
    stack:clear()
end

local function handleEvent(event)

    if event:isAutoRepeat() then
        return  -- auto-repeated events don't go to fallback listeners
    end

    -- Since this is the fallback event listener, the event should not bubble
    -- up the item hierarchy. This has already happened.
    event.bubble = false

    for i = #stack,1,-1 do
        local listener = stack[i]
        if listener:event(event) then
            break
        end

        -- Reset the event back to accepted
        event.accepted = true
    end
end

Pointer.setFallback(handleEvent)

return FallbackListeners
