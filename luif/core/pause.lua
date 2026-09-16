--
-- Pauses for a specific duration.
--

local core = require "luif.core"

local Effect = core.Effect

local Pause = Effect:extend {
    age = 0,
    _duration = 250,
}

function Pause:prepare(changes)
    Effect.prepare(self, changes)
    self.age = 0
end

function Pause:update(deltaTime)
    self.age = self.age + deltaTime
    return Effect.update(self, deltaTime, self.age - self._duration)
end

function Pause:isDone()
    return self.age >= self._duration
end

return Pause
