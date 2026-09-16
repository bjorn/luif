--
-- Default skins that must work without application textures, and control
-- level behaviour: tool tip, LineEdit and HorizontalScrollbar
-- defaults, TextInput class level multiline, Scale9 texture swaps, a double
-- click on Button and ScrollArea, and deleting a scrolling ScrollArea.
--

return function(t)
    local module = require "luif.module"
    local core = module "luif.core"
    local Update = core.Update
    local Host = require "luif.core.host"
    local Sync = require "luif.core.sync"
    local Pointer = require "luif.core.pointer"
    local InputFeed = require "tests.inputfeed"

    local now = (Update.systemTime() or 0) + 200000
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

    local root = core.Item { x = 0, y = 0, width = 800, height = 600 }
    Sync.addRoot(root)

    -- Scale9 swapped to a texture with larger insets lays out with it and
    -- stays one slices node.
    local function square(size)
        return Host.get().createTexture(size, size)
    end
    local frame = core.Scale9 { texture = square(12), insets = { left = 4, top = 4, right = 4, bottom = 4 },
                                width = 40, height = 40 }
    root:addChild(frame)
    step()
    frame:setTexture(square(24), { left = 8, top = 8, right = 8, bottom = 8 })
    Sync.flush()
    local frameState = Sync.host(frame).inspect(Sync.node(frame))
    local slices = frameState.content
    t.ok(slices.kind == "slices" and #frameState.children == 0, "Scale9 with a new texture is one slices node")
    t.ok(slices.left == 8 and slices.top == 8 and slices.right == 8 and slices.bottom == 8,
         "Scale9 slices with the new insets")
    t.ok(frameState.width == 40 and frameState.height == 40, "Scale9 keeps its explicit size")
    t.ok(frame.implicitWidth == 24 and frame.minimumWidth == 16 and frame.minimumHeight == 16,
         "Scale9 implicit and minimum size follow the new texture")

    -- An item with a tool tip but no toolTipClass uses LabelToolTip and
    -- its default skin
    local tipped = core.Item { x = 10, y = 400, width = 50, height = 20, toolTip = "tip" }
    root:addChild(tipped)
    step()
    tipped._hasMouse = true
    local ok, err = pcall(tipped.createToolTip, tipped, 15, 405)
    t.ok(ok, "default tool tip is created: " .. tostring(err))
    local tip = tipped._toolTipInstance
    t.ok(tip and tip.titleLabel ~= nil, "default tool tip has a title label")
    step(10)
    if tip then
        local tw, th = tip:size()
        t.ok(tw > 15 and th > 20, "default tool tip is sized around its text")
        local label = tip.titleLabel
        local node = Sync.node(label)
        local content = node and Sync.host(label).inspect(node).content
        t.eq(content and content.text, "tip", "default tool tip text")
    end
    tipped._hasMouse = false
    tipped:destroyToolTip()
    step(10)

    -- LineEdit with its default skin
    local lineEdit
    ok, err = pcall(function()
        lineEdit = core.LineEdit { x = 10, y = 440 }
        root:addChild(lineEdit)
    end)
    t.ok(ok, "LineEdit builds with its default skin: " .. tostring(err))
    if lineEdit then
        step()
        lineEdit:setText("hello")
        t.eq(lineEdit.textInput.text, "hello", "default LineEdit takes text")
        t.eq(lineEdit.textInput.multiline, false, "default LineEdit is single line")
    end

    -- HorizontalScrollbar with its default skin
    local bar
    ok, err = pcall(function()
        bar = core.HorizontalScrollbar { x = 10, y = 480, width = 200, maxValue = 4 }
        root:addChild(bar)
    end)
    t.ok(ok, "HorizontalScrollbar builds with its default skin: " .. tostring(err))
    if bar then
        step()
        t.ok(bar.trackbar and bar.thumbButton and bar.leftButton and bar.rightButton,
             "HorizontalScrollbar skin parts")
        local before = bar.position
        bar:increaseScroll()
        step(30)
        t.ok(bar.position > before, "HorizontalScrollbar scrolls right (" .. bar.position .. ")")
    end

    -- A TextInput subclass that declares multiline = false does not wrap
    local SingleLine = core.TextInput:extend { multiline = false }
    local single = SingleLine { x = 10, y = 520, width = 60, height = 20,
                                text = string.rep("word ", 20) }
    root:addChild(single)
    step()
    t.eq(single.label.wrap, false, "class level multiline = false disables label wrap")
    t.eq(#single.edit:lines(), 1, "model has one line")
    local _, labelHeight = single.label:implicitSize()
    t.ok(labelHeight < 2 * Sync.host(single.label).lineHeight(single.label.font),
         "label is one line high (" .. labelHeight .. ")")

    -- Double clicks: the second press arrives as a double click, which Button
    -- and ScrollArea turn into exactly one more press
    -- presses is 1 for a fresh press, 2 for the second press of a double click
    local function click(x, y, presses)
        if presses == 1 then
            feed.host.advance(1000)
        else
            feed.host.advance(100)
        end
        feed.move(x, y)
        feed.press(x, y)
        feed.release(x, y)
    end

    local presses, clicks = 0, 0
    local button = core.Button { x = 300, y = 10, width = 100, height = 30,
                                 text = "Double",
                                 press = function() presses = presses + 1 end,
                                 click = function() clicks = clicks + 1 end }
    root:addChild(button)
    step()
    click(350, 25, 1)
    click(350, 25, 2)
    step()
    t.eq(presses, 2, "double click presses the button twice")
    t.eq(clicks, 2, "double click clicks the button twice")

    local rows = {}
    for i = 1, 20 do
        rows[i] = core.Item { width = 80, height = 30 }
    end
    local scroll = core.ScrollArea { x = 300, y = 100, width = 120, height = 150,
                                     content = core.Column { unpack(rows) } }
    root:addChild(scroll)
    step(3)
    local downPresses = 0
    scroll.downButton:on("press", function() downPresses = downPresses + 1 end)
    local timeoutsBefore = #Update._timeouts
    local bx, by = scroll.downButton:absolutePos()
    local bw, bh = scroll.downButton:size()
    click(bx + bw / 2, by + bh / 2, 1)
    click(bx + bw / 2, by + bh / 2, 2)
    step(3)
    t.eq(downPresses, 2, "double click on the down arrow is two presses")
    t.eq(#Update._timeouts, timeoutsBefore, "no repeat timeout left behind")

    -- The scroll animation is still running: deleting must stop it
    feed.move(2000, 2000)
    root:delete()
    local stepped, stepError = pcall(step, 3)
    t.ok(stepped, "deleting a scrolling ScrollArea stops its animation: " .. tostring(stepError))
    feed.detach()
    if adapt then Update:setAdaptUiScale(true) else Update:setUiScale(savedScale) end
end
