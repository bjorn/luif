--
-- An effect that executes its child effects in parallel and ends only
-- when all child effects have finished.
--

local core = require "luif.core"

local Effect = core.Effect

local Parallel = Effect:extend {
    _activeEffects = false,
}

-- Prepares this effect for animating the property changes
function Parallel:prepare(changes)
    Effect.prepare(self, changes)

    self._activeEffects = {}

    for i=1,#self.children do
        local effect = self.children[i]
        effect:prepare(changes)
        self._activeEffects[i] = effect
    end
end

-- When the last effects finish, the time left over is that of the one that
-- finished last.
function Parallel:update(deltaTime)
    local remaining = deltaTime
    for i=#self._activeEffects,1,-1 do
        local effect = self._activeEffects[i]
        local done, left = effect:update(deltaTime)
        if done then
            effect:finalize()
            table.remove(self._activeEffects, i)
            remaining = math.min(remaining, left or deltaTime)
        end
    end
    return Effect.update(self, deltaTime, remaining)
end

-- Stops and reverts the parallel and its child effects
function Parallel:reset()
    for i=1,#self.children do
        self.children[i]:reset()
    end
    Effect.reset(self)
end

function Parallel:isDone()
    return #self._activeEffects == 0
end

function Parallel:finalize()
    if self._activeEffects then
        for i=1,#self._activeEffects do
            self._activeEffects[i]:finalize()
        end
    end
    self._activeEffects = false
end

return Parallel
