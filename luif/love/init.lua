--
-- Luif on LOVE: the LOVE host and the callbacks that drive Luif from a game.
-- require "luif" sets the host up and puts these functions on the luif
-- table, so a game uses them from there:
--
--   function love.update(dt) luif.update(dt) end
--   function love.draw() luif.draw() end
--   function love.mousepressed(x, y, button) luif.mousepressed(x, y, button) end
--   ...
--
-- or calls luif.hook() once, after defining its own callbacks.
--
--   Love.host           the LOVE host (luif/love/host.lua) Luif draws through
--   Love.update(dt)     timers, effects, layout and the node flush, dt in seconds
--   Love.draw()         draws the UI
--   Love.mousemoved, mousepressed, mousereleased, wheelmoved, keypressed,
--   keyreleased, textinput, mousefocus
--                       the LOVE callbacks, with LOVE's arguments; they return
--                       true when the UI handled the input: a press on an
--                       item that takes mouse input, the release of a press
--                       the UI took, the wheel over such an item, keys and
--                       text the focused item accepted
--   Love.hook()         installs all of the above as the love callbacks and
--                       chains the callbacks already set: the game updates
--                       first, the UI draws over the game, and input the UI
--                       handled does not reach the game (pointer moves and
--                       focus changes always do)
--
-- The callbacks make the LOVE host the pointer's input source (again, when
-- something else took it) and enable key repeat.
--

local LoveHost = require "luif.love.host"
local core = require "luif.core"

local Host = core.Host

local Love = {
    Host = LoveHost,
    host = LoveHost.new(),
}

local callbacks = {
    "mousemoved", "mousepressed", "mousereleased", "wheelmoved",
    "keypressed", "keyreleased", "textinput", "mousefocus",
}

-- Input that reaches the game even when the UI handled it
local alwaysForward = { mousemoved = true, mousefocus = true }

-- The functions require "luif" puts on the luif table
Love.functions = { "update", "draw", "hook" }
for _, name in ipairs(callbacks) do
    Love.functions[#Love.functions + 1] = name
end

local attached = false

local function attach()
    local Pointer = core.Pointer
    if Pointer.host() ~= Love.host then
        Pointer.attach(Love.host)
    end
    if attached then
        return
    end
    attached = true
    if not Host.current() then
        Host.set(Love.host)
    end
    love.keyboard.setKeyRepeat(true)
end

for _, name in ipairs(callbacks) do
    local handler = Love.host.loveHandlers[name]
    Love[name] = function(...)
        attach()
        return handler(...) and true or false
    end
end

-- Once the frame's input callbacks ran: releases whose release got lost,
-- then timers, effects, layout and the flush, then hover under a still
-- pointer.
function Love.update(dt)
    attach()
    Love.host.releaseLostButtons()
    core.Update.onUpdate(Love.host.time(), dt * 1000)
    core.Pointer.afterUpdate()
end

function Love.draw()
    attach()
    Love.host.render()
end

function Love.hook()
    attach()

    local update, draw = love.update, love.draw
    function love.update(dt)
        if update then update(dt) end
        Love.update(dt)
    end
    function love.draw()
        if draw then draw() end
        Love.draw()
    end

    for _, name in ipairs(callbacks) do
        local previous = love[name]
        local forward = alwaysForward[name]
        love[name] = function(...)
            local handled = Love[name](...)
            if previous and (forward or not handled) then
                return previous(...)
            end
        end
    end
end

return Love
