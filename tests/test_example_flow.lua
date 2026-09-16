-- End to end flow: input fed to core's pointer through a host feed reaches
-- core items, button states follow over -> down -> over, a toggle
-- selects, a looping Rotate advances and wraps, and a clip = true parent
-- stops clicks outside its rect from reaching a child button.
return function(t)
    local module = require "luif.module"
    local core = module "luif.core"
    local Update = core.Update
    local Screen = core.Screen
    local Pointer = require "luif.core.pointer"
    local Sync = require "luif.core.sync"
    local InputFeed = require "tests.inputfeed"

    -- Simulated clock driving Update.onUpdate in 16 ms frames
    local now = (Update.systemTime() or 0) + 100000
    local function step(frames)
        for _ = 1, frames or 1 do
            now = now + 16
            Update.onUpdate(now, 16)
            Pointer.afterUpdate()
        end
    end

    -- Keep the UI scale fixed so window pixels equal item units
    local adapt, savedScale = Screen.adaptive, Screen.scale
    Screen:setScale(1)

    -- A skin without textures: a rectangle and a label
    local FlatSkin = core.Skin:extend { width = 80, height = 30 }
    function FlatSkin.new(class, self)
        self.layout = core.AnchorLayout {}
        self.children = {
            core.Rectangle { color = 0xFF404040, left = 0, top = 0, right = 0, bottom = 0,
                             states = { over = { color = 0xFF606060 } } },
            core.Label { id = "label", color = 0xFFFFFFFF, wrap = false,
                         horizontalCenter = 0, verticalCenter = 0 },
        }
        self.transitions = {
            core.Transition { core.AnimateColor { duration = 50 } },
        }
        return core.Skin.new(class, self)
    end

    local feed = InputFeed.attach()
    local root = core.Item { x = 300, y = 200, width = 300, height = 250 }
    Sync.addRoot(root)

    local move, release = feed.move, feed.release
    -- Time passes before every press, so none of them is a double click
    local function press(x, y)
        feed.host.advance(1000)
        feed.press(x, y)
    end

    -- Button: window rect 310..390 x 210..240
    local clicks = 0
    local button = core.Button {
        skinClass = FlatSkin, x = 10, y = 10, text = "Go",
        click = function() clicks = clicks + 1 end,
    }
    root:addChild(button)
    step(2)
    t.eq(button.state, "up", "button starts up")

    move(350, 225)
    step()
    t.eq(button.state, "over", "hover gives over")
    press(350, 225)
    step()
    t.eq(button.state, "down", "press gives down")
    t.eq(clicks, 0, "no click on press")
    release(350, 225)
    step(4)
    t.eq(clicks, 1, "click after release inside")
    t.eq(button.state, "over", "release gives over")

    -- Release outside: no click, and leaving drops back to up
    press(350, 225)
    move(500, 400)
    release(500, 400)
    step()
    t.eq(clicks, 1, "no click when released outside")
    t.eq(button.state, "up", "up after leaving")

    -- ToggleButton: window rect 310..390 x 260..290
    local changes = {}
    local toggle = core.ToggleButton {
        skinClass = FlatSkin, x = 10, y = 60, text = "T",
        change = function(selected) changes[#changes + 1] = selected end,
    }
    root:addChild(toggle)
    step()
    move(350, 275)
    press(350, 275)
    release(350, 275)
    step()
    t.eq(toggle.selected, true, "toggle selected after click")
    t.eq(toggle.state, "overAndSelected", "toggle state overAndSelected")
    t.eq(changes[1], true, "change callback with true")
    press(350, 275)
    release(350, 275)
    step()
    t.eq(toggle.selected, false, "toggle unselected after second click")
    t.eq(toggle.state, "over", "toggle state back to over")

    -- Rotate loop: two loops of 100 ms
    local spinner = core.Item { x = 200, y = 10, width = 20, height = 20 }
    root:addChild(spinner)
    local finished = false
    local rotate = core.Rotate { from = 0, to = 360, duration = 100, loops = 2 }
    rotate:on("finish", function() finished = true end)
    spinner:start("spin", rotate)
    step(3)
    local r3 = spinner.rotation
    t.ok(r3 > 0 and r3 < 360, "rotation advances (" .. r3 .. ")")
    local spinnerNode = Sync.host(spinner).inspect(Sync.node(spinner))
    t.near(spinnerNode.rotation, math.rad(r3), 1e-9, "node rotation in radians")
    -- frame 7 lands on 360 and restarts the loop; frame 8 is 16 ms into loop 2
    step(5)
    t.ok(spinner.rotation < r3, "rotation wraps after first loop (" .. spinner.rotation .. ")")
    t.ok(not finished, "still running in second loop")
    step(8)
    t.ok(finished, "finished after two loops")
    t.eq(spinner.rotation, 360, "ends at the target")

    -- Clip: the child button lies at 60..140 inside a 50x50 clipped parent
    local clipped = core.Item { x = 10, y = 120, width = 50, height = 50, clip = true }
    root:addChild(clipped)
    local hidden = 0
    local child = core.Button {
        skinClass = FlatSkin, x = 20, y = 10, text = "C",
        click = function() hidden = hidden + 1 end,
    }
    clipped:addChild(child)
    step()
    -- window x 380 is inside the child's rect (330..410) but outside the clip (310..360)
    move(380, 345)
    press(380, 345)
    release(380, 345)
    step()
    t.eq(hidden, 0, "click outside the clip rect does not reach the child")
    t.ok(child.state == "up", "child not hovered outside the clip")
    move(340, 345)
    press(340, 345)
    release(340, 345)
    step()
    t.eq(hidden, 1, "click inside the clip rect reaches the child")

    move(1000, 1000)
    root:delete()
    step()
    feed.detach()
    if adapt then Screen:setAdaptive(true) else Screen:setScale(savedScale) end
end
