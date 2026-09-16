--
-- HorizontalScrollbar: a range that follows the laid out track, snapping to
-- steps, relative positions, resizing, both buttons following setEnabled, an
-- animated thumb and dragging the thumb with the mouse.
--
return function(t)
    local module = require "luif.module"
    local core = module "luif.core"
    local Update = core.Update
    local Pointer = require "luif.core.pointer"
    local Sync = require "luif.core.sync"
    local InputFeed = require "tests.inputfeed"

    local now = (Update.systemTime() or 0) + 300000
    local function step(frames)
        for _ = 1, frames or 1 do
            now = now + 16
            Update.onUpdate(now, 16)
            Pointer.afterUpdate()
        end
    end

    local adapt, savedScale = Update.adaptUiScale, Update.uiScale
    Update:setUiScale(1)
    local feed = InputFeed.attach()

    local root = core.Item { width = 800, height = 600 }
    Sync.addRoot(root)

    local relative = false
    local bar = core.HorizontalScrollbar {
        x = 50, y = 40, width = 240, maxValue = 5,
        valueChanged = function(changed, value) relative = value end,
    }
    root:addChild(bar)
    step(2)

    local track, thumb = bar.trackbar, bar.thumbButton
    t.eq(track.width, 200, "the track is laid out between the buttons")
    t.eq(thumb.width, 40, "the thumb is one of five steps wide")
    t.eq(bar.minScroll, 20, "the range starts at the track")
    t.eq(bar.maxScroll, 180, "the range ends a thumb width before the track end")
    t.eq(thumb.x, 20, "the thumb starts at the left")

    bar:setRatio(1)
    step(30)
    t.eq(bar.position, 180, "setRatio(1) moves to the end")
    t.eq(thumb.x, 180, "the thumb arrives once the animation finished")
    t.eq(relative, 1, "valueChanged reports a relative position of 1")

    bar:setValue(20 + 40 * 2 + 15, false, true)
    t.eq(bar.position, 100, "snap rounds to the nearest step")
    t.eq(bar:relativePosition(), 0.5, "the middle step is half way")

    bar:increaseScroll()
    t.eq(bar.position, 140, "increaseScroll moves one step")
    step(2)
    t.ok(thumb.x > 100 and thumb.x < 140, "the thumb animates towards it (" .. thumb.x .. ")")
    t.eq(bar.position, 140, "the position is kept while the thumb animates")
    step(30)
    t.eq(thumb.x, 140, "the thumb arrives")

    bar:setWidth(440)
    step(3)
    t.eq(bar.maxScroll, 340, "the range follows a resized track")
    t.eq(bar:relativePosition(), 0.75, "the relative position is kept across a resize")
    t.eq(thumb.x, 260, "the thumb is placed for the new range")

    bar:setEnabled(false)
    t.eq(bar.leftButton.enabled, false, "setEnabled(false) disables the left button")
    t.eq(bar.rightButton.enabled, false, "setEnabled(false) disables the right button")
    bar:setEnabled(true)
    t.eq(bar.rightButton.enabled, true, "setEnabled(true) enables the right button")

    bar:setValue(bar.minScroll, false, false)
    step()
    local ax, ay = thumb:absolutePos()
    local sx, sy = ax + 10, ay + 5
    feed.move(sx, sy)
    feed.host.advance(1000)
    feed.press(sx, sy)
    feed.move(sx + 75, sy)
    t.eq(bar.position, 95, "the thumb follows the pointer while dragging")
    t.eq(thumb.x, 95, "the thumb is under the pointer")
    feed.release(sx + 75, sy)
    step(30)
    t.eq(bar.position, 100, "releasing snaps to the nearest step")

    root:delete()
    feed.detach()
    if adapt then Update:setAdaptUiScale(true) else Update:setUiScale(savedScale) end
end
