--
-- An animation that allows moving an item along a path.
--

local core = require "luif.core"

local Move = core.Animate:extend {
    -- A path along which to animate. When set, the animation does not
    -- implicitly handle any property changes during a transition.
    path = false,

    properties = {
        "x", "y",

        -- Animating these depends on invalidating the layout, which is
        -- rather more expensive than animating x/y directly.
        "left", "top", "right", "bottom",
        "verticalCenter", "horizontalCenter"
    }
}

function Move.new(class, self)
    return core.Animate.new(class, self)
end

function Move:prepare(changes)
    if self.path then
        assert(self._target, "Path animation needs a target")
        self._changes = false
        self.age = 0
        core.Effect.prepare(self, changes)
    else
        core.Animate.prepare(self, changes)
    end
end

function Move:update(deltaTime)
    local finished, remaining = core.Animate.update(self, deltaTime)

    if self.path then
        self._target:setPos(self.path(self.progress))
    end

    return finished, remaining
end

function Move:reset()
    if self.path then
        self._target:setPos(self.path(0))
    end
    core.Animate.reset(self)
end

return Move
