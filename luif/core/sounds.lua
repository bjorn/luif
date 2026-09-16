--
-- Sound names used by the framework and an optional hook to play them.
--
-- The framework never plays audio itself. An application that wants sounds
-- installs a handler:
--
--   core.Sounds.handler = function(name, parameters) ... end
--
-- Sounds.play returns what the handler returns.
--

local Sounds = {
    UI = {
        Click   = "ui/click",
        Deny    = "ui/deny",
        Hover   = "ui/hover",
        ToolTip = "ui/tooltip",
    },

    handler = false,    -- function(name, parameters)
}

function Sounds.play(name, parameters)
    if name and Sounds.handler then
        return Sounds.handler(name, parameters)
    end
end

return Sounds
