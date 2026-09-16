--
-- An effect that plays a sound through core.Sounds.
--

local core = require "luif.core"

local Action = core.Action
local Sounds = core.Sounds

local Play = Action:extend {
    sound = false,
    parameters = false,
}

function Play.new(class, self)
    self.script = function(deltaTime)
        if self.sound then
            Sounds.play(self.sound, self.parameters or nil)
        end
    end

    return Action.new(class, self)
end

return Play
