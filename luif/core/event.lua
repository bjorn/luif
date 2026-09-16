--
-- The input event. core/pointer.lua builds one per delivery and hands it to
-- Item:handleEvent; handlers read it through the methods below. An event is
-- a plain table of fields with Event as its class:
--
--   name          handler name: mouseEnter, mouseLeave, mousePress,
--                 mouseRelease, mouseDoubleClick, mouseMove, mouseWheel,
--                 keyPress, keyRelease, keyCharacter
--   localX/Y      position in the receiving item's space (updated while the
--                 event bubbles)
--   absX/Y        position in virtual units
--   deltaX/Y      movement since the previous position (mouseMove)
--   mouseButton   1 left, 2 right, 3 middle (core/mousebutton.lua)
--   wheel         wheel steps as the host reports them, positive scrolls up
--   keyName       key name of the host feed ("a", "return", "left", ...)
--   typed         UTF-8 text of keyCharacter
--   autoRepeat    true for a repeated keyPress
--   buttons       set of mouse buttons held when the event was made
--   ctrl, shift, alt, gui   modifiers held when the event was made
--   focus         the item that had the focus
--
--   core.Event { name = "keyPress", keyName = "c", ctrl = true }
--

local core = require "luif.core"

local Class = core.Class
local Keys = core.Keys

local handlerNames = {
    mouseEnter = true,
    mouseLeave = true,
    mousePress = true,
    mouseRelease = true,
    mouseDoubleClick = true,
    mouseMove = true,
    mouseWheel = true,
    keyPress = true,
    keyRelease = true,
    keyCharacter = true,
}

local mouseEvents = {
    mouseEnter = true,
    mouseLeave = true,
    mousePress = true,
    mouseRelease = true,
    mouseMove = true,
    mouseWheel = true,
    mouseDoubleClick = true,
}

local keyEvents = {
    keyPress = true,
    keyRelease = true,
    keyCharacter = true,
}

local noButtons = {}

local Event = Class:extend {
    -- Determines whether the event bubbles up to parent items
    bubble = true,

    -- The item the event was originally delivered to
    source = false,
}

function Event.new(class, self)
    assert(type(self) == "table" and handlerNames[self.name],
           "Unrecognized event: " .. tostring(self and self.name))
    self.accepted = true
    self.buttons = self.buttons or noButtons
    return Class.new(class, self)
end

--
-- Ignoring an event will cause it to bubble up the parent tree. By default
-- events that are handled are accepted.
--
function Event:ignore()
    self.accepted = false
end

function Event:accept()
    self.accepted = true
end

function Event:focusItem()
    return self.focus
end

-- Valid for mouse events
function Event:x()
    return self.localX
end
function Event:y()
    return self.localY
end
function Event:pos()
    return self.localX, self.localY
end
-- Positions and deltas are in virtual units: core/pointer.lua divides the
-- host's window pixels by the UI scale before dispatching.
function Event:absolutePos()
    return self.absX, self.absY
end

-- Valid for mouseMove events
function Event:dx()
    return self.deltaX or 0
end
function Event:dy()
    return self.deltaY or 0
end

-- Valid for mousePress, mouseRelease and mouseDoubleClick events
function Event:button()
    return self.mouseButton
end

-- Valid for mouseWheel events: wheel steps (notches, or fractions of one on
-- precise devices), positive scrolls up
function Event:value()
    return self.wheel
end

-- Valid for keyPress, keyRelease and keyCharacter events: the key name
function Event:key()
    return self.keyName
end

-- Whether the key is one of the given names
function Event:isKey(...)
    local key = self.keyName
    if not key then return false end
    for i = 1, select("#", ...) do
        if key == select(i, ...) then
            return true
        end
    end
    return false
end

function Event:isAutoRepeat()
    return self.autoRepeat or false
end

-- Valid for keyCharacter events: the UTF-8 string that was typed
function Event:text()
    return self.typed
end

-- Whether the button (any button without an argument) was held
function Event:mouseDown(button)
    if button then
        return self.buttons[button] == true
    end
    return next(self.buttons) ~= nil
end

-- Whether the modifier ("ctrl", "shift", "alt" or "gui"; any without an
-- argument) was held
function Event:modifierDown(modifier)
    if modifier then
        return self[modifier] == true
    end
    return self.ctrl == true or self.shift == true or self.alt == true or self.gui == true
end

function Event:controlDown()
    return self.ctrl == true
end

function Event:shiftDown()
    return self.shift == true
end

function Event:altDown()
    return self.alt == true
end

function Event:isMouseEvent()
    return mouseEvents[self.name] == true
end

function Event:isKeyEvent()
    return keyEvents[self.name] == true
end

-- A Text naming the key, so applications can translate the English names.
function Event.keyDisplayName(key)
    return core.Text(Keys.displayName(key))
end

return Event
