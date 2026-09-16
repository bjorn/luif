-- Event delivery of core/pointer.lua on core items, fed through a
-- recording host: hover, capture, wheel, double click, key routing,
-- key names, modifiers, fallback, deleted items, the pointer leaving the
-- window, and the LOVE host's callbacks with lost releases.
return function(t)
    local module = require "luif.module"
    local core = module "luif.core"
    local Pointer = require "luif.core.pointer"
    local Sync = require "luif.core.sync"
    local Keys = require "luif.core.keys"
    local MouseButton = require "luif.core.mousebutton"
    local InputFeed = require "tests.inputfeed"

    local log = {}
    local function pop()
        return table.remove(log, 1)
    end
    local function expect(node, name, label)
        local entry = pop()
        t.ok(entry ~= nil and entry.node == node and entry.name == name,
             label .. " (" .. (entry and (entry.node .. " " .. entry.name) or "nothing") .. ")")
        return entry and entry.event or core.Event { name = "mouseMove" }
    end
    local function drained(label)
        t.eq(#log, 0, label .. ": no extra events")
        log = {}
    end

    local accept = { outer = true, inner = true }
    local function recorder(name)
        return function(self, event)
            log[#log + 1] = { node = name, name = event.name, event = event }
            return accept[name]
        end
    end

    -- outer covers window 10..210, inner covers 60..110
    local outer = core.Item { x = 10, y = 10, width = 200, height = 200, mouseEnabled = true }
    local inner = core.Item { x = 50, y = 50, width = 50, height = 50, mouseEnabled = true }
    outer.handleEvent = recorder("outer")
    inner.handleEvent = recorder("inner")
    outer:addChild(inner)
    Sync.addRoot(outer)

    local fallbacks = {}
    local previousFallback = Pointer.fallback()
    Pointer.setFallback(function(event) fallbacks[#fallbacks + 1] = event end)
    local feed = InputFeed.attach()
    local host = feed.host

    -- hover and move; the delta is taken from the previous position (0, 0)
    feed.move(70, 70)
    expect("inner", "mouseEnter", "enter inner")
    local data = expect("inner", "mouseMove", "move inner")
    t.eq(data:x(), 10, "local x"); t.eq(data:y(), 10, "local y")
    t.eq((data:absolutePos()), 70, "absolute x"); t.eq(data:dx(), 70, "dx"); t.eq(data:dy(), 70, "dy")
    t.eq(data:mouseDown(), false, "no buttons held")
    t.eq(Pointer.hovered(), inner, "hover item")
    drained("hover")

    feed.move(20, 20)
    expect("inner", "mouseLeave", "leave inner")
    expect("outer", "mouseEnter", "enter outer")
    data = expect("outer", "mouseMove", "move outer")
    t.eq(data:x(), 10, "outer local x")
    t.eq(data:dx(), -50, "dx of the second move")
    drained("hover change")

    -- press captures, moves and release go to the pressed item
    feed.press(70, 70, 1)
    expect("outer", "mouseLeave", "leave outer on press")
    expect("inner", "mouseEnter", "enter inner on press")
    data = expect("inner", "mousePress", "press inner")
    t.eq(data:button(), MouseButton.Left, "button")
    t.ok(data:mouseDown(MouseButton.Left) and not data:mouseDown(MouseButton.Right), "the left button is held")
    t.eq(Pointer.captured(), inner, "capture item")
    drained("press")

    feed.move(300, 300)
    expect("inner", "mouseLeave", "leave follows the real hit")
    data = expect("inner", "mouseMove", "move captured")
    t.eq(data:x(), 240, "captured local x")
    t.eq(Pointer.hovered(), nil, "nothing hovered")
    t.eq(select(1, Pointer.position()), 300, "position follows the feed")
    drained("captured move")

    -- the wheel is not captured: outside every item it reaches the fallback
    fallbacks = {}
    host.feed("wheel", 0, 1)
    t.eq(#log, 0, "wheel during capture skips the pressed item")
    t.eq(#fallbacks, 1, "wheel during capture goes to the hit (none)")

    feed.release(300, 300, 1)
    data = expect("inner", "mouseRelease", "release captured")
    t.eq(data:mouseDown(), false, "no button held on release")
    t.eq(Pointer.captured(), nil, "capture ended")
    drained("release")

    -- wheel: nothing under the pointer goes to the fallback as a fresh table
    fallbacks = {}
    host.feed("wheel", 0, -1)
    t.eq(#log, 0, "wheel outside hits no item")
    t.eq(#fallbacks, 1, "wheel reached the fallback")
    local fevent = fallbacks[1]
    t.eq(fevent and fevent.name, "mouseWheel", "fallback event name")
    t.eq(fevent and fevent:value(), -1, "wheel value")

    feed.move(20, 20)
    expect("outer", "mouseEnter", "enter outer for wheel")
    expect("outer", "mouseMove", "move outer for wheel")
    host.feed("wheel", 0, 1)
    data = expect("outer", "mouseWheel", "wheel on outer")
    t.eq(data:value(), 1, "wheel value positive")
    drained("wheel")

    -- rejected events reach the fallback as a fresh copy
    fallbacks = {}
    accept.outer = false
    feed.move(21, 21)
    local entry = pop()
    t.ok(entry and entry.node == "outer" and entry.name == "mouseMove", "rejected move")
    t.eq(#fallbacks, 1, "fallback got the rejected move")
    local copy = fallbacks[1]
    t.ok(copy ~= nil and copy ~= entry.event, "fallback event is fresh")
    t.eq(copy and copy:x(), entry.event:x(), "copy keeps x")
    t.eq(copy and copy.bubble, true, "copy is a new Event")
    accept.outer = true
    drained("rejected")

    -- double click: a second press soon after at the same place replaces
    -- the press
    host.advance(1000)
    feed.press(70, 70, 1)
    expect("outer", "mouseLeave", "leave outer for dblclk")
    expect("inner", "mouseEnter", "enter inner for dblclk")
    expect("inner", "mousePress", "first press")
    feed.release(70, 70, 1)
    expect("inner", "mouseRelease", "first release")
    host.advance(100)
    feed.press(70, 70, 1)
    data = expect("inner", "mouseDoubleClick", "double click instead of the second press")
    t.eq(data:button(), MouseButton.Left, "double click button")
    t.eq(Pointer.captured(), inner, "double click captures")
    feed.release(70, 70, 1)
    expect("inner", "mouseRelease", "second release")
    drained("double click")

    -- an unaccepted double click becomes a press; only the press falls back
    accept.inner = false
    feed.press(70, 70, 1)
    expect("inner", "mousePress", "third press is a press")
    feed.release(70, 70, 1)
    expect("inner", "mouseRelease", "release after third press")
    fallbacks = {}
    feed.press(70, 70, 1)
    expect("inner", "mouseDoubleClick", "rejected double click")
    expect("inner", "mousePress", "press delivered after the rejected double click")
    t.eq(#fallbacks, 1, "only the press reached the fallback")
    t.eq(fallbacks[1] and fallbacks[1].name, "mousePress", "fallback got the press")
    feed.release(70, 70, 1)
    expect("inner", "mouseRelease", "release after rejected double click")
    accept.inner = true
    drained("rejected double click")

    -- presses too far apart in time or place, or of another button, are
    -- not double clicks
    host.advance(1000)
    feed.press(70, 70, 1)
    feed.release(70, 70, 1)
    log = {}
    host.advance(Pointer.doubleClickTime)
    feed.press(70, 70, 1)
    expect("inner", "mousePress", "a press after the double click time is a press")
    feed.release(70, 70, 1)
    expect("inner", "mouseRelease", "release after the double click time")
    feed.press(70, 70, 2)
    expect("inner", "mousePress", "another button does not continue a double click")
    feed.release(70, 70, 2)
    expect("inner", "mouseRelease", "release of the other button")
    local farX = 70 + Pointer.doubleClickRadius + 1
    feed.move(farX, 70)
    expect("inner", "mouseMove", "move within inner")
    feed.press(farX, 70, 1)
    expect("inner", "mousePress", "a press beyond the double click radius is a press")
    feed.release(farX, 70, 1)
    expect("inner", "mouseRelease", "release beyond the radius")
    drained("not double clicks")

    -- a release without a press is not delivered
    fallbacks = {}
    feed.release(70, 70, 1)
    t.eq(#fallbacks, 0, "unpaired release reaches no fallback")
    t.eq(#log, 0, "unpaired release reaches no item")
    log = {}

    -- keys go to the focused item, else to the fallback
    inner:setFocus()
    t.eq(Pointer.focused(), inner, "focus is tracked by the pointer")
    host.feed("keyPressed", "a", false)
    data = expect("inner", "keyPress", "key to focus")
    t.eq(data:key(), "a", "key name")
    t.eq(data:focusItem(), inner, "focus item")
    t.eq(data:isAutoRepeat(), false, "no repeat")
    host.feed("keyPressed", "a", true)
    data = expect("inner", "keyPress", "repeated key")
    t.eq(data:isAutoRepeat(), true, "repeat flag")
    host.feed("keyReleased", "a")
    expect("inner", "keyRelease", "key up")
    host.feed("textInput", "é")
    data = expect("inner", "keyCharacter", "text input")
    t.eq(data:text(), "é", "keyCharacter text")
    t.eq(data:key(), nil, "text input has no key")
    host.feed("keyPressed", "return", false)
    data = expect("inner", "keyPress", "return down")
    t.eq(data:key(), "return", "return key")
    data = expect("inner", "keyCharacter", "synthesized return char")
    t.eq(data:text(), "\n", "return text")
    host.feed("keyReleased", "return")
    expect("inner", "keyRelease", "return up")
    host.feed("keyPressed", "unknownkey", false)
    data = expect("inner", "keyPress", "unmapped key")
    t.eq(data:key(), "unknownkey", "any key name reaches the item")
    host.feed("keyPressed", "f2", false)
    t.eq(expect("inner", "keyPress", "function key"):key(), "f2", "f2 key name")
    host.feed("keyPressed", "kp5", false)
    t.eq(expect("inner", "keyPress", "keypad key"):key(), "kp5", "kp5 key name")
    host.feed("keyPressed", "kpenter", false)
    t.ok(expect("inner", "keyPress", "keypad enter"):isKey("return", "kpenter"), "kpenter key name")
    t.eq(expect("inner", "keyCharacter", "keypad enter types a newline"):text(), "\n", "kpenter text")
    t.eq(Keys.isReturn("kpenter"), true, "kpenter is a return key")
    drained("keys")

    -- modifiers held through the feed show up in the events
    host.feed("keyPressed", "lctrl", false)
    data = expect("inner", "keyPress", "control down")
    t.eq(data:key(), "lctrl", "left control key name")
    host.feed("keyPressed", "c", false)
    local event = expect("inner", "keyPress", "c with control")
    t.ok(event:controlDown(), "controlDown while lctrl is held")
    t.ok(event:modifierDown("ctrl") and not event:modifierDown("alt"), "modifierDown")
    t.ok(not event:shiftDown(), "shift is not down")
    t.eq(Pointer.modifierDown("ctrl"), true, "Pointer.modifierDown")
    host.feed("keyReleased", "lctrl")
    expect("inner", "keyRelease", "control up")
    host.feed("keyPressed", "c", false)
    data = expect("inner", "keyPress", "c without control")
    t.ok(not data:controlDown(), "control released")
    host.feed("keyPressed", "rshift", false)
    expect("inner", "keyPress", "right shift down")
    host.feed("keyPressed", "x", false)
    t.ok(expect("inner", "keyPress", "x with shift"):shiftDown(), "shiftDown while rshift is held")
    host.feed("keyReleased", "rshift")
    expect("inner", "keyRelease", "right shift up")
    drained("modifiers")

    inner:setFocus(false)
    fallbacks = {}
    host.feed("keyPressed", "b", false)
    t.eq(#log, 0, "no focus: no item")
    t.eq(#fallbacks, 1, "no focus: fallback")

    -- hover is re-picked after update when an item moved under the pointer
    feed.move(20, 20)
    expect("inner", "mouseLeave", "leave inner before layout change")
    expect("outer", "mouseEnter", "enter outer before layout change")
    expect("outer", "mouseMove", "move outer before layout change")
    inner:setPos(0, 0)
    Pointer.afterUpdate()
    expect("outer", "mouseLeave", "leave outer after update")
    expect("inner", "mouseEnter", "enter inner after update")
    drained("afterUpdate")
    inner:setPos(50, 50)
    Pointer.afterUpdate()
    expect("inner", "mouseLeave", "leave inner after moving back")
    expect("outer", "mouseEnter", "enter outer after moving back")
    drained("afterUpdate back")

    -- the pointer leaving the window ends the hover; a layout change does
    -- not bring it back, the next move does
    host.feed("pointerLeft")
    expect("outer", "mouseLeave", "leave on pointerLeft")
    t.eq(Pointer.hovered(), nil, "nothing hovered outside the window")
    inner:setPos(0, 0)
    Pointer.afterUpdate()
    inner:setPos(50, 50)
    Pointer.afterUpdate()
    fallbacks = {}
    host.feed("wheel", 0, 1)
    t.eq(#fallbacks, 1, "the wheel outside the window reaches only the fallback")
    drained("no re-enter while outside")
    feed.move(20, 20)
    expect("outer", "mouseEnter", "enter again after pointerLeft")
    expect("outer", "mouseMove", "move after pointerLeft")
    drained("pointerLeft")

    -- deleting the hovered and captured item must not break the next event
    host.advance(1000)
    feed.press(70, 70, 1)
    expect("outer", "mouseLeave", "leave outer before delete")
    expect("inner", "mouseEnter", "enter inner before delete")
    expect("inner", "mousePress", "press inner before delete")
    t.eq(Pointer.captured(), inner, "inner captured before delete")
    inner:delete()
    t.eq(Pointer.hovered(), nil, "deleting forgets the hover")
    local ok, err = pcall(feed.move, 71, 71)
    t.ok(ok, "move after delete does not raise: " .. tostring(err))
    expect("outer", "mouseEnter", "enter outer after delete")
    expect("outer", "mouseMove", "move after delete goes to the hit item")
    ok, err = pcall(feed.release, 71, 71, 1)
    t.ok(ok, "release after delete does not raise: " .. tostring(err))
    expect("outer", "mouseRelease", "release after delete")
    t.eq(Pointer.captured(), nil, "capture cleared after delete")
    drained("delete")

    -- an item that deletes itself while handling a double click it does
    -- not accept: the press that follows must not reach the deleted item
    local selfDeleting = core.Item { x = 400, y = 400, width = 20, height = 20, mouseEnabled = true }
    local presses = 0
    selfDeleting.handleEvent = function(self, event)
        if event.name == "mouseDoubleClick" then
            self:delete()
            return false
        end
        if event.name == "mousePress" then presses = presses + 1 end
        return true
    end
    Sync.addRoot(selfDeleting)
    host.advance(1000)
    feed.click(410, 410)
    t.eq(presses, 1, "the first press reaches the item")
    fallbacks = {}
    host.advance(10)
    ok, err = pcall(function()
        feed.press(410, 410)
        feed.release(410, 410)
    end)
    t.ok(ok, "deleting an item in its double click handler is safe: " .. tostring(err))
    t.eq(fallbacks[1] and fallbacks[1].name, "mousePress", "the press after the deletion falls back")
    t.eq(fallbacks[2] and fallbacks[2].name, "mouseRelease", "and so does the release")
    t.eq(Pointer.captured(), nil, "nothing captured after the release")
    log = {}

    outer:delete()
    ok = pcall(feed.move, 72, 72)
    t.ok(ok, "move after deleting everything does not raise")
    feed.detach()

    -- luif.hook() makes the LOVE callbacks feed the pointer: it chains a
    -- callback that was already set, and lost releases are synthesized after
    -- a frame's callbacks.
    if love and love.keyboard then
        local luif = require "luif"
        local Love = require "luif.love"
        local names = { "update", "draw", "mousemoved", "mousepressed", "mousereleased",
                        "wheelmoved", "keypressed", "keyreleased", "textinput", "mousefocus" }
        local saved = {}
        for _, name in ipairs(names) do saved[name] = love[name] end
        local seen = false
        love.textinput = function(text) seen = text end
        fallbacks = {}
        luif.hook()
        t.eq(Pointer.host(), Love.host, "hook makes the pointer the LOVE host's sink")
        love.textinput("z")
        t.eq(seen, "z", "hook chains callbacks already set")
        t.eq(#fallbacks, 1, "the host handler fed the text input through the pointer")
        t.eq(love.keyboard.hasKeyRepeat(), true, "hook enables key repeat")

        local node = core.Item { width = 100, height = 100, mouseEnabled = true }
        local ups = 0
        node.handleEvent = function(self, event)
            if event.name == "mouseRelease" then ups = ups + 1 end
            return true
        end
        Sync.addRoot(node)
        Pointer.reset()
        local released = function() return false end
        love.mousepressed(50, 50, 1, false, 1)
        love.mousemoved(51, 50, 1, 0)
        love.mousereleased(51, 50, 1, false, 1)
        Love.host.releaseLostButtons(released)
        t.eq(ups, 1, "press, move, release in one frame releases once")
        ups = 0
        love.mousepressed(50, 50, 1, false, 1)
        love.mousemoved(52, 50, 1, 0)
        t.eq(ups, 0, "no release before the frame's callbacks are done")
        Love.host.releaseLostButtons(released)
        t.eq(ups, 1, "lost release delivered after the frame")
        t.eq(Pointer.captured(), nil, "lost release ends the capture")
        love.mousereleased(52, 50, 1, false, 1)
        t.eq(ups, 1, "late real release is not delivered again")
        node:delete()
        Pointer.reset()
        for _, name in ipairs(names) do love[name] = saved[name] end
    else
        t.skip("the LOVE host's love callbacks need LOVE")
    end

    Pointer.setFallback(previousFallback)
end
