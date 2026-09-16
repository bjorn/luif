local core = require "luif.core"

local EffectManager = core.EffectManager
local Object = core.Object

local Effect = Object:extend {
    running = false,
    loops = 1, -- Set to "infinite" for infinite looping

    -- The target of the effect. Inherited by child effects.
    target = false,

    -- The duration of the effect. Inherited by child effects.
    duration = false,

    -- Event handlers
    finish = false, -- Called when the effect is finished (but not when the
                    -- effect is stopped before it finished)

    paused = false,

    -- Private members

    -- The actual target used internally. Normally mirrors 'target' but can
    -- be a target of a parent effect when 'target' is not set.
    _target = false,

    -- The actual duration used internally. Normally mirrors 'duration' but
    -- can be the duration of a parent effect when 'duration' is not set.
    _duration = 0,
}

local function applyTargetToChildren(effect, target)
    for i=1,#effect.children do
        local child = effect.children[i]
        if not child.target then
            child._target = target
            applyTargetToChildren(child, target)
        end
    end
end

local function applyDurationToChildren(effect, duration)
    for i=1,#effect.children do
        local child = effect.children[i]
        if not child.duration then
            child._duration = duration
            applyDurationToChildren(child, duration)
        end
    end
end

function Effect.new(class, self)
    self = Object.new(class, self)
    if self.target then
        self._target = self.target
        applyTargetToChildren(self, self.target)
    end
    if self.duration then
        self._duration = self.duration
        applyDurationToChildren(self, self.duration)
    end
    return self
end

-- Starts the effect. Does nothing when the effect is already running.
--
-- 'changes' is an optional parameter requesting the effect to perform a list
-- of changes. Changes performed by this effect will be removed from that
-- list. This mechanism is used by transitions.
--
function Effect:start(changes)
    self:setRunning(true, changes)
end

-- Stops the effect. Does nothing when the effect is not running.
function Effect:stop()
    self:setRunning(false)
end

-- Restarts the effect.
function Effect:restart()
    if self.running then
        self:finalize()
        self:prepare()
    else
        self:start()
    end
end

function Effect:stopLooping()
    self._loops = 1
end

function Effect:setRunning(running, changes)
    assert(not self.parent or not self.parent:as(Effect), "Can't change running state of child effect")
    if self.running == running then
        return
    end

    self.running = running

    if running then
        self:prepare(changes)
        EffectManager:add(self)
    else
        EffectManager:remove(self)
        self:finalize()
    end
end

function Effect:setPaused(paused)
    self.paused = paused
end

--
-- Sets the target of this effect. Applies the target recursively to the
-- children, unless they already have a target set.
--
function Effect:setTarget(target)
    assert(type(target) == "table", "Invalid target")
    self.target = target
    self._target = target
    applyTargetToChildren(self, target)
end

--
-- Sets the duration of this effect. Applies the duration recursively to the
-- children, unless they already have a duration set.
--
function Effect:setDuration(duration)
    assert(type(duration) == "number", "Invalid duration")
    self.duration = duration
    self._duration = duration
    applyDurationToChildren(self, duration)
end

-- Prepares this effect for running. After this call, the 'update' method will
-- be called repeatedly, until it returns true. Finally, the 'finalize' method
-- is called.
--
-- 'changes' is optional, it is used when the effect is asked to perform the
-- changes for a particular transition.
--
function Effect:prepare(changes)
    self._loops = self.loops
end

-- Stops and reverts the effect
function Effect:reset()
    if not self.parent or not self.parent:as(Effect) then
        self:stop()
        self:finalize()
    end
end

-- Advances the effect by the given time delta. Subclasses call this at the
-- end of their update and pass the time left over once they finished.
-- Returns whether the effect is finished and the time left over. A looping
-- effect starts its next loop with the time left over, so loops keep their
-- rhythm.
function Effect:update(deltaTime, remaining)
    local done = self:isDone()
    if done then
        local loops = self._loops
        if loops == "infinite" or loops > 1 then
            self:finalize()
            self:prepare()
            if loops ~= "infinite" then
                self._loops = loops - 1
            end
            -- A loop that took no time gets no more time this update
            if remaining and remaining > 0 and remaining < deltaTime then
                return self:update(remaining)
            end
            return false
        end
    end
    return done, remaining
end

function Effect:isDone()
    return true
end

-- Called after the effect is done and before the 'finish' signal is emitted.
function Effect:finalize()
end

return Effect
