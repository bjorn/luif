--
-- Test helper: feeds input to core.Pointer through a recording host, the
-- way a host would, with a clock the test controls.
--
--   local feed = require("tests.inputfeed").attach()
--   feed.move(x, y); feed.press(x, y); feed.release(x, y)
--   feed.click(x, y)      -- time passes first, so it is never a double click
--   feed.key("return")    -- press and release
--   feed.host.advance(ms)
--   feed.detach()         -- restores the host the pointer had before
--

local Recording = require "luif.host.recording"
local Pointer = require "luif.core.pointer"

local InputFeed = {}

function InputFeed.attach(options)
    local previous = Pointer.host()
    local host = Recording.new(options)
    Pointer.reset()
    Pointer.attach(host)

    local feed = { host = host }

    function feed.move(x, y)
        host.feed("pointerMoved", x, y)
    end

    function feed.press(x, y, button)
        host.feed("pointerPressed", x, y, button or 1)
    end

    function feed.release(x, y, button)
        host.feed("pointerReleased", x, y, button or 1)
    end

    function feed.click(x, y, button)
        host.advance(1000)
        feed.move(x, y)
        feed.press(x, y, button)
        feed.release(x, y, button)
    end

    function feed.key(name)
        host.feed("keyPressed", name, false)
        host.feed("keyReleased", name)
    end

    function feed.detach()
        Pointer.reset()
        Pointer.attach(previous)
    end

    return feed
end

return InputFeed
