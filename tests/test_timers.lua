--
-- Update intervals keep their rhythm, skip slots missed in a long frame and
-- can clear themselves from their callback.
--
return function(t)
    local module = require "luif.module"
    local core = module "luif.core"
    local Update = core.Update
    local Host = require "luif.core.host"

    -- The application host with a clock the test controls
    local realHost = Host.get()
    local now = (Update.systemTime() or 0) + 500000
    Host.set(setmetatable({ time = function() return now end }, { __index = realHost }))

    local function step(frames, ms)
        ms = ms or 16
        for _ = 1, frames do
            now = now + ms
            Update.onUpdate(now, ms)
        end
    end

    local ok, err = pcall(function()
        step(1)

        local count = 0
        local interval = Update:setInterval(100, function() count = count + 1 end)
        local start = now
        while now < start + 1008 do
            step(1)
        end
        Update:clearInterval(interval)
        t.eq(count, 10, "a 100 ms interval fires ten times in a second of 16 ms frames")

        count = 0
        interval = Update:setInterval(100, function() count = count + 1 end)
        step(1, 550)
        t.eq(count, 1, "one call after a 550 ms frame")
        step(1, 40)
        t.eq(count, 1, "the next call waits for its slot")
        step(1, 20)
        t.eq(count, 2, "and comes on the original rhythm")
        Update:clearInterval(interval)

        count = 0
        local selfClearing
        selfClearing = Update:setInterval(50, function()
            count = count + 1
            Update:clearInterval(selfClearing)
        end)
        step(40)
        t.eq(count, 1, "an interval cleared from its own callback fires once")

        Update:clearTimeout(false)
        Update:clearInterval(nil)
        t.ok(true, "clearing false or nil does not raise")
    end)

    Host.set(realHost)
    t.ok(ok, "timer checks ran: " .. tostring(err))
end
