--
-- Self-test for the example, enabled with LUIF_SELFTEST=1. Clicks through
-- both screens and the dialogs by feeding input to core's pointer (the sink
-- the host feeds), prints one line per check and quits with exit code 0 when
-- every check passed, 1 otherwise. With LUIF_SCENE=scaled the same clicks run
-- in a 1000x600 window at the adaptive UI scale.
--

local core = require "luif.core"
local platform = require "platform"

local Pointer = core.Pointer
local Screen = core.Screen

local feed = Pointer.sink

return function(ctx)
    local app, dialog, root = ctx.app, ctx.dialog, ctx.root
    local failures, now = 0, 0

    local function check(ok, label)
        print((ok and "PASS " or "FAIL ") .. label)
        if not ok then
            failures = failures + 1
        end
    end

    local function wait(ms)
        local deadline = now + ms
        while now < deadline do
            coroutine.yield()
        end
    end

    -- Virtual position of an item's centre
    local function center(item)
        local x, y = item:absolutePos()
        local width, height = item:size()
        return x + width / 2, y + height / 2
    end

    -- The feed takes window pixels: the one place virtual positions are
    -- converted
    local function moveTo(x, y)
        feed.pointerMoved(Pointer.toWindow(x, y))
    end

    local function clickAt(x, y)
        moveTo(x, y)
        coroutine.yield()
        local wx, wy = Pointer.toWindow(x, y)
        feed.pointerPressed(wx, wy, 1)
        feed.pointerReleased(wx, wy, 1)
        wait(50)
    end

    local function click(item)
        clickAt(center(item))
    end

    local function key(name)
        feed.keyPressed(name, false)
        feed.keyReleased(name)
        wait(50)
    end

    local function find(id)
        return assert(root:findChild(id), "no item with id " .. id)
    end

    local function dialogTitle()
        return dialog:isOpen() and dialog._options and dialog._options.title
    end

    local script = coroutine.create(function()
        wait(300)
        check(app.state == "title", "starts on the title screen")

        if ctx.scaled then
            local width, height = platform.windowSize()
            check(width == 1000 and height == 600 and Screen.adaptive,
                  "the window is 1000x600 with the adaptive scale")
            check(math.abs(Screen.width - 1920) < 1e-6,
                  "the virtual screen is 1920 wide")
            check(root.width == Screen.width and root.scale == 1,
                  "the root covers the virtual screen without a scale of its own")
        end

        click(find("enterButton"))
        wait(900)
        check(app.state == "demo", "Enter the demo switches the state")
        check(ctx.demoPage.x == 0 and ctx.titlePage.alpha == 0, "the page transition finished")

        local start = find("startButton")
        click(start)
        check(ctx.counter.text == "Clicks: 1", "Start counts a click")

        -- Hover Start from elsewhere so its tooltip shows below the pointer
        moveTo(8, 8)
        wait(100)
        local mx, my = center(start)
        moveTo(mx - 2, my)
        coroutine.yield()
        moveTo(mx, my)
        wait(400)
        local tip = start._toolTipInstance
        local tipWidth, tipHeight = 0, 0
        if tip then
            tipWidth, tipHeight = tip:size()
        end
        check(tip and tip.scale == 1 and math.abs(tip.x - mx) < 1e-6
                  and math.abs(tip.y - (my + 25)) < 1e-6,
              "Start's tooltip is placed below the pointer in virtual units")
        check(tip and tip.x >= 0 and tip.y >= 0
                  and tip.x + tipWidth <= Screen.width
                  and tip.y + tipHeight <= Screen.height,
              "the tooltip is on the screen")
        moveTo(8, 8)
        wait(300)

        click(find("resetButton"))
        wait(400)
        check(dialogTitle() == "Reset", "Reset opens a dialog")
        local layer = dialog.parent
        check(layer and dialog.width == Screen.width
                  and layer.width == Screen.width,
              "the dialog covers the virtual screen")
        click(start)
        check(ctx.counter.text == "Clicks: 1", "the dialog blocks clicks underneath")
        click(dialog.confirmButton)
        wait(300)
        check(not dialog:isOpen(), "confirming closes the dialog")
        check(ctx.counter.text == "Clicks: 0", "confirming resets the counters")

        key("escape")
        wait(900)
        check(app.state == "title", "Escape returns to the title screen")

        click(find("aboutButton"))
        wait(400)
        check(dialogTitle() == "About", "About opens a dialog")
        click(find("quitButton"))
        check(dialogTitle() == "About", "menu buttons are blocked while it is open")

        key("escape")
        wait(300)
        check(not dialog:isOpen(), "Escape closes the dialog")
        check(app.state == "title" and not dialog:isOpen(),
              "that Escape does not reach the screen")

        key("escape")
        wait(400)
        check(dialogTitle() == "Quit", "Escape on the title screen asks to quit")
        click(dialog.cancelButton)
        wait(300)
        check(not dialog:isOpen(), "Stay closes the dialog")

        key("return")
        wait(900)
        check(app.state == "demo", "Return enters the demo")
    end)

    local finished = false

    return function(dt)
        if finished then
            return
        end
        now = now + dt * 1000

        local ok, err = coroutine.resume(script)
        if not ok then
            print("FAIL script error: " .. tostring(err))
            failures = failures + 1
        end

        if coroutine.status(script) == "dead" then
            finished = true
            print(failures == 0 and "selftest passed" or ("selftest failed: " .. failures .. " checks"))
            platform.quit(failures == 0 and 0 or 1)
        end
    end
end
