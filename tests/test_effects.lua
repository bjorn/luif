--
-- Effect timing: time left over when an effect finishes goes to the next
-- step of a sequence and to the next loop, so loops keep their rhythm.
--
return function(t)
    local core = require "luif.core"
    local EffectManager = core.EffectManager

    local function run(steps, dt)
        for _ = 1, steps do
            EffectManager:update(dt)
        end
    end

    local spun = core.Item {}
    spun:start("spin", core.Rotate { from = 0, to = 360, duration = 100, loops = "infinite" })
    run(4, 30)
    t.near(spun.rotation, 72, 1e-9, "a looping effect starts its next loop with the time left over")
    spun:stop("spin")

    local counted = core.Item {}
    counted:start("spin", core.Rotate { from = 0, to = 360, duration = 100, loops = 2 })
    run(7, 30)
    t.near(counted.rotation, 360, 1e-9, "a counted loop ends on time")
    counted:stop("spin")

    local stepped = core.Item {}
    stepped:start("steps", core.Sequence {
        core.Parallel { core.Scale { from = 1, to = 2, duration = 50 } },
        core.Move { properties = { "x" }, from = 0, to = 100, duration = 100 },
    })
    run(2, 30)
    t.near(stepped.x, 10, 1e-9, "the step after a parallel gets the time the parallel left over")
    stepped:stop("steps")

    local bounced = core.Item {}
    bounced:start("bounce", core.Sequence { loops = "infinite",
        core.Move { properties = { "x" }, from = 0, to = 100, duration = 45 },
        core.Parallel {
            core.Move { properties = { "x" }, from = 100, to = 0, duration = 45 },
            core.Pause { duration = 30 },
        },
    })
    run(9, 20)
    t.near(bounced.x, 0, 1e-9, "a looping sequence is back at its start after whole loops")
    run(1, 20)
    t.near(bounced.x, 100 * 20 / 45, 1e-9, "and continues with the time left over")
    bounced:stop("bounce")
end
