--
-- The mouse cursor manager just keeps track of which current mouse cursor
-- should be displayed.
--

local core = require "luif.core"
local Host = core.Host

-- Cursor names are those of host/interface.lua ("arrow", "hand", "ibeam", ...)
local defaultCursor = "arrow"

local MouseCursorManager = core.Object:extend {
    cursor = defaultCursor,

    _cursorStack = core.Array {},
    _cursorStackAsserted = false,
    _cursorStackMax = 30,
}

local function updateCursor(manager)
    Host.get().setCursor(#manager._cursorStack > 0 and manager._cursorStack:last()
                  or manager.cursor or defaultCursor)
end

--
-- Pushes the given mouse cursor on the stack, making it the currently
-- displayed cursor.
--
-- Must eventually be followed by a call to remove.
--
-- Maximum depth defined in _cursorStackMax. Stack can hold more, but if it exceeds _cursorStackMax,
-- a single assert is shown, to warn a long time before a stack overflow happens.
--
function MouseCursorManager:push(cursor)
    self._cursorStack:append(cursor)
    if not self._cursorStackAsserted and #self._cursorStack > self._cursorStackMax then
        self._cursorStackAsserted = true
        assert(false, "Cursor Stack exceeded " .. self._cursorStackMax .. " Entries. Please check your code for missing \"MouseCursorManager:remove()\" entries")
    end

    updateCursor(self)
end

--
-- Removes the given mouse cursor from the stack.
--
function MouseCursorManager:remove(cursor)
    local index = assert(self._cursorStack:findLast(cursor), "No such cursor found")
    self._cursorStack:remove(index)
    updateCursor(self)
end

function MouseCursorManager:setCursor(cursor)
    cursor = cursor or defaultCursor

    if self.cursor ~= cursor then
        self.cursor = cursor

        if #self._cursorStack == 0 then
            updateCursor(self)
        end
    end
end

return MouseCursorManager
