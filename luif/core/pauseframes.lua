--
-- Pauses for a specific amount of frames.
--

local core = require "luif.core"

local Effect = core.Effect

local PauseFrames = Effect:extend {
    frames = 1,

    _countedFrames = 0,
}

function PauseFrames:prepare(changes)
    Effect.prepare(self, changes)
    self._countedFrames = 0
end

function PauseFrames:update(deltaTime)
    self._countedFrames = self._countedFrames + 1
    return Effect.update(self, deltaTime)
end

function PauseFrames:isDone()
    return self._countedFrames >= self.frames
end

return PauseFrames
