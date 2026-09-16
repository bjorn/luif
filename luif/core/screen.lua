--
-- The screen: its size in virtual units and the UI scale.
--
-- Items are laid out in virtual units, the window size divided by the UI
-- scale. The scale is applied in one place: core/sync.lua scales every root
-- node by it and core/pointer.lua divides the input feed by it.
--
--   Screen.width, Screen.height    the virtual screen size
--   Screen.scale                   the UI scale
--   Screen.windowWidth/Height      the window size in pixels, from the host
--   Screen:setScale(scale)         a fixed scale
--   Screen:setAdaptive(true)       a scale that fits adaptiveWidth by
--                                  adaptiveHeight (1920 by 1080) into the
--                                  window
--   Screen:update(force)           reads the window size from the host and
--                                  recomputes; Update.onUpdate calls it
--                                  every frame
--   Screen:on("changed", function(scale, width, height) ... end)
--

local core = require "luif.core"

local Host   = core.Host
local Object = core.Object

-- Creates an instance, not a subclass
local Screen = Object {
    width = 1280,
    height = 720,
    scale = 1,
    windowWidth = 1280,
    windowHeight = 720,
    adaptive = false,
    adaptiveWidth = 1920,
    adaptiveHeight = 1080,

    changed = false,    -- function(scale, width, height)
}

-- Uses the given fixed scale and turns the adaptive scale off.
function Screen:setScale(scale)
    self.adaptive = false
    self.scale = scale
    self:update(true)
end

function Screen:setAdaptive(adaptive)
    self.adaptive = adaptive and true or false
    self:update(true)
end

function Screen:update(force)
    local windowWidth, windowHeight = Host.get().screenSize()
    if not force and self.windowWidth == windowWidth and self.windowHeight == windowHeight then
        return
    end

    local scale = self.scale
    if self.adaptive then
        scale = math.min(windowWidth / self.adaptiveWidth,
                         windowHeight / self.adaptiveHeight)
    end

    self.scale = scale
    self.windowWidth, self.windowHeight = windowWidth, windowHeight
    self.width, self.height = windowWidth / scale, windowHeight / scale

    self:emit("changed", scale, self.width, self.height)
end

return Screen
