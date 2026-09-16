--
-- An effect that executes its child effects in sequence and ends
-- when all child effects have finished.
--

local core = require "luif.core"

local Effect = core.Effect

local Sequence = Effect:extend {
    _index = 0,
}

-- Prepares this effect for animating the property changes
function Sequence:prepare(changes)
    Effect.prepare(self, changes)

    for i=1,#self.children do
        local effect = self.children[i]
        effect:prepare(changes)
    end

    self._index = 1
end

-- Stops and reverts the sequence and its child effects
function Sequence:reset()
    for i=self._index,1,-1 do
        local effect = self.children[i]
        effect:reset()
    end
    Effect.reset(self)
end

function Sequence:update(deltaTime)
    local tick = deltaTime

    -- We'll keep processing until an effect doesn't finish this tick.
    -- Otherwise we lose a whole tick for each effect that finishes instantly.
    while self._index <= #self.children do
        local effect = self.children[self._index]
        local done, remainingTime = effect:update(deltaTime)

        if done then
            effect:finalize()
            deltaTime = remainingTime or deltaTime
            self._index = self._index + 1
        else
            break
        end
    end

    return Effect.update(self, tick, deltaTime)
end

function Sequence:isDone()
    return self._index > #self.children
end

function Sequence:finalize()
    -- Call finalize on remaining children
    if self._index > 0 then
        for i=self._index,#self.children do
            self.children[i]:finalize()
        end
    end
    self._index = 0
end

return Sequence
