--
-- Update manager.
--
-- The "update" event can be used as follows:
--
--   Update:on("update", function(systemTimeMs, frameDurationMs)
--       ...
--   end)
--
-- or:
--
--   Update:connect("update", self, "update")
--
-- Update.onUpdate reads the window size (core/screen.lua), runs timers,
-- effects and layout, then flushes the node changes of the frame
-- (core/sync.lua).
--
-- Another alternative is to use the timeout functions:
--
--   t = Update:setTimeout(1000, function() ... end)
--   Update:clearTimeout(t)
--
--   t = Update:setInterval(1000, function() ... end)
--   Update:clearInterval(t)
--

local core = require "luif.core"

local Array         = core.Array
local Class         = core.Class
local EffectManager = core.EffectManager
local LayoutManager = core.LayoutManager
local Object        = core.Object
local Screen        = core.Screen
local Sync          = core.Sync

local Host          = core.Host

-- Creates an instance, not a subclass!
local Update = Object {
    _timeouts = Array {},
    _pendingCalls = Array {},
    _lastSecond = 0,

    -- prevent assertions when looking for inline event handler
    update = false,                 -- function(systemTimeMs, frameDurationMs)
    everySecond = false,            -- function(systemTimeMs)
}

--
-- Calls the given function at the end of the update.
--
function Update:invokeLater(func)
    self._pendingCalls:append(func)
    return func
end

function Update:cancelInvokeLater(func)
    assert(self._pendingCalls:removeOne(func), "callback not found")
end

local function timeoutLessThan(a, b)
    return a.time < b.time
end

function Update.onUpdate(systemTimeMs, frameDurationMs)
    Screen:update()

    Update._systemTime = systemTimeMs
    Update:emit("update", systemTimeMs, frameDurationMs)

    -- emit a signal every second for time updates
    if Update._lastSecond < (systemTimeMs - 1000) then
        Update:emit("everySecond", systemTimeMs)
        Update._lastSecond = math.floor(systemTimeMs / 1000) * 1000
    end

    -- Call any expired timeouts
    while #Update._timeouts > 0 and Update._timeouts[1].time < systemTimeMs do
        local timeout = Update._timeouts:takeFirst()
        timeout.callback()
        -- An interval is rescheduled from when it was due, so it keeps its
        -- rhythm; intervals missed during a long frame are skipped. It is not
        -- rescheduled when its callback cleared it.
        if timeout.interval and not timeout.cleared then
            local interval = timeout.interval
            if interval > 0 then
                local missed = math.floor((systemTimeMs - timeout.time) / interval)
                timeout.time = timeout.time + (missed + 1) * interval
            else
                timeout.time = systemTimeMs
            end
            Update._timeouts:append(timeout)
            Update._timeouts:sort(timeoutLessThan)
        end
    end

    EffectManager:update(frameDurationMs)
    LayoutManager:validate()

    local pendingCalls = Update._pendingCalls
    for i=1,#pendingCalls do
        pendingCalls[i]()
        pendingCalls[i] = nil
    end
    Class.performDelayedDeletions()

    -- One flush of node changes per frame, after layout
    Sync.flush()
end

function Update.systemTime()
    return Update._systemTime
end

function Update:setTimeout(milliseconds, callback)
    assert(type(milliseconds) == "number", "Invalid timeout duration")
    assert(type(callback) == "function", "Invalid callback function")

    local timeout = {
        time = Host.get().time() + milliseconds,
        callback = callback
    }
    self._timeouts:append(timeout)
    self._timeouts:sort(timeoutLessThan)
    return timeout
end

function Update:setInterval(milliseconds, callback)
    assert(type(milliseconds) == "number", "Invalid timeout duration")
    assert(type(callback) == "function", "Invalid callback function")

    local timeout = {
        time = Host.get().time() + milliseconds,
        callback = callback,
        interval = milliseconds
    }
    self._timeouts:append(timeout)
    self._timeouts:sort(timeoutLessThan)
    return timeout
end

function Update:clearTimeout(timeout)
    if not timeout then
        return
    end
    -- Marked so a running interval callback that clears itself stays cleared
    timeout.cleared = true
    local index = self._timeouts:find(timeout)
    if index then
        self._timeouts:remove(index)
    end
end

function Update:clearInterval(timeout)
    if timeout then
        timeout.interval = false
    end
    Update:clearTimeout(timeout)
end

return Update
