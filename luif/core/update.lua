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
-- Update.onUpdate runs timers, effects and layout, then flushes the node
-- changes of the frame (core/sync.lua).
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

    uiScale = 1,
    screenWidth = 1280,
    screenHeight = 720,
    virtualScreenWidth = 1280,
    virtualScreenHeight = 720,
    uiScaleChanged = false,         -- function(scale, virtualScreenWidth, virtualScreenHeight)
    adaptUiScale = false,
    adaptiveWidth = 1920,           -- the adaptive scale fits this virtual size into the window
    adaptiveHeight = 1080,
}

-- core/sync.lua scales root nodes and core/pointer.lua divides input by this
Sync.setScaleSource(function() return Update.uiScale end)

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
    Update:updateUiScale()

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

function Update:setAdaptUiScale(adaptUiScale)
    self.adaptUiScale = adaptUiScale
    self:updateUiScale(true)
end

-- Turns the adaptive scale off and uses the given fixed scale.
function Update:setUiScale(scale)
    self.adaptUiScale = false
    self.uiScale = scale
    self:updateUiScale(true)
end

-- The UI scale is applied in one place: core/sync.lua scales every root node
-- by it and core/pointer.lua divides the input feed by it. Everything else
-- works in virtual units, the window size divided by the scale.

function Update:updateUiScale(force)
    local screenWidth, screenHeight = Host.get().screenSize()
    if not force and self.screenWidth == screenWidth and self.screenHeight == screenHeight then
        return
    end

    local scale = self.uiScale

    if self.adaptUiScale then
        scale = math.min(screenWidth / self.adaptiveWidth,
                         screenHeight / self.adaptiveHeight)
    end

    self.uiScale = scale
    self.screenWidth = screenWidth
    self.screenHeight = screenHeight
    self.virtualScreenWidth = screenWidth / scale
    self.virtualScreenHeight = screenHeight / scale

    self:emit("uiScaleChanged", scale, self.virtualScreenWidth, self.virtualScreenHeight)
end

return Update
