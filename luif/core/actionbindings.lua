--
-- Maps key names (the host feed's names, see core/keys.lua) to abstract
-- actions, used by Button to react to the keyboard. Only "Activate" is bound
-- by default.
--

local ActionBindings = {}

local bindings = {
    space = "Activate",
    ["return"] = "Activate",
    kpenter = "Activate",
}

-- Returns the action bound to the key name, or false
function ActionBindings.mapKeyPress(key)
    return bindings[key] or false
end

-- Binds an action to a key name; pass false to remove the binding
function ActionBindings.setBinding(key, action)
    bindings[key] = action or nil
end

return ActionBindings
