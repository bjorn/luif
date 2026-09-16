--
-- An effect that just calls a function. The function gets the deltaTime as
-- parameter and can return 'false' to avoid finishing the effect.
--

local core = require "luif.core"

local Action = core.Effect:extend {
    script = function(deltaTime) end,
    undoScript = function() end,
    _done = false,
}

function Action:update(deltaTime)
    self._done = self.script(deltaTime) ~= false
    return core.Effect.update(self, deltaTime)
end

function Action:isDone()
    return self._done
end

-- Stops the action and calls the undo script
function Action:reset()
    self.undoScript()
    core.Effect.reset(self)
end

function Action:finalize()
    self._done = false
end

return Action
