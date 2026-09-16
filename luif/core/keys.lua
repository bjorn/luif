--
-- Key names. Events carry the key names of the host input feed
-- (host/interface.lua): LOVE KeyConstant names such as "a", "space",
-- "return", "kpenter", "escape", "left", "lshift", "f2" or "kp5", which a
-- non LOVE host maps its key codes onto. This module has the few helpers
-- core needs on top of the names.
--
--   Keys.modifiers.ctrl       { "lctrl", "rctrl" }, also shift, alt and gui
--   Keys.modifierOf[name]     "ctrl" for "lctrl", and so on
--   Keys.isReturn(name)       "return" or "kpenter"
--   Keys.isPrintable(text)    text input that is not a control character
--   Keys.displayName(name)    "Return", "Page Up", "F2", "Keypad 5"
--

local Keys = {}

Keys.modifiers = {
    ctrl  = { "lctrl", "rctrl" },
    shift = { "lshift", "rshift" },
    alt   = { "lalt", "ralt" },
    gui   = { "lgui", "rgui" },
}

Keys.modifierOf = {}
for modifier, names in pairs(Keys.modifiers) do
    for i = 1, #names do
        Keys.modifierOf[names[i]] = modifier
    end
end

function Keys.isModifier(name)
    return Keys.modifierOf[name] ~= nil
end

function Keys.isReturn(name)
    return name == "return" or name == "kpenter"
end

-- True unless the text starts with a control character (below space, or
-- DEL).
function Keys.isPrintable(text)
    local byte = text and text:byte(1)
    return byte ~= nil and byte >= 32 and byte ~= 127
end

-- Readable names of keys whose key name is not readable as it is
local displayNames = {
    ["return"] = "Return", kpenter = "Keypad Enter",
    lshift = "Shift", rshift = "Shift", lctrl = "Ctrl", rctrl = "Ctrl",
    lalt = "Alt", ralt = "Alt", lgui = "Gui", rgui = "Gui",
    capslock = "Caps Lock", numlock = "Num Lock", scrolllock = "Scroll Lock",
    pageup = "Page Up", pagedown = "Page Down", printscreen = "Print Screen",
    ["kp*"] = "Keypad *", ["kp+"] = "Keypad +", ["kp,"] = "Keypad ,", ["kp-"] = "Keypad -",
    ["kp."] = "Keypad .", ["kp/"] = "Keypad /", ["kp="] = "Keypad =",
}
for d = 0, 9 do
    displayNames["kp" .. d] = "Keypad " .. d
end

-- A readable English name for the key; other keys are capitalized.
function Keys.displayName(name)
    name = tostring(name)
    return displayNames[name] or name:sub(1, 1):upper() .. name:sub(2)
end

return Keys
