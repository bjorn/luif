--
-- The UI scale applied once: core/sync.lua scales root nodes and
-- core/pointer.lua divides the window pixels of the feed by the same scale,
-- so node transforms below the roots, event coordinates and deltas,
-- tooltips and thumb drags are all in virtual units. Runs with a recording
-- host at scales 0.5 and 1.5.
--
return function(t)
    local module = require "luif.module"
    local core = module "luif.core"
    local AppHost = require "luif.core.host"
    local Update = core.Update
    local Sync = require "luif.core.sync"
    local Pointer = require "luif.core.pointer"
    local TopLayer = require "luif.core.toplayer"
    local Recording = require "luif.host.recording"
    local HostWorld = require "tests.hostworld"
    local InputFeed = require "tests.inputfeed"

    local function near(a, b)
        return type(a) == "number" and type(b) == "number" and math.abs(a - b) < 1e-6
    end

    local adapt, savedScale = Update.adaptUiScale, Update.uiScale
    local host = Recording.new { glyphWidth = 8, lineHeight = 16 }
    Sync.setHost(host)
    local feed = InputFeed.attach()

    local now = math.max(Update.systemTime() or 0, AppHost.get().time()) + 600000
    local function step(frames)
        for _ = 1, frames or 1 do
            now = now + 16
            Update.onUpdate(now, 16)
            Pointer.afterUpdate()
        end
    end

    local created = {}
    local function root(props)
        local item = core.Item(props)
        Sync.addRoot(item)
        created[#created + 1] = item
        return item
    end

    --
    -- Node transforms, picking and event coordinates
    --
    for _, scale in ipairs { 0.5, 1.5 } do
        local at = " at " .. scale
        Update:setUiScale(scale)

        local log = {}
        local function record(name)
            return function(self, event)
                local ax, ay = event:absolutePos()
                log[#log + 1] = {
                    name = name, x = event:x(), y = event:y(), ax = ax, ay = ay,
                    dx = event:dx(), dy = event:dy(),
                }
            end
        end
        local child = core.Item {
            x = 100, y = 50, width = 80, height = 40, mouseEnabled = true,
            mousePress = record("press"), mouseMove = record("move"),
            mouseRelease = record("release"), mouseWheel = record("wheel"),
        }
        local base = root { x = 40, y = 30, width = 400, height = 300, child }
        local turned = root {
            x = 300, y = 200, width = 60, height = 40, rotation = 30, scale = 1.2,
            transformOriginX = 0.5, transformOriginY = 0.5,
        }
        step()

        local r = host.inspect(Sync.node(base))
        local rx, ry = HostWorld.toWorld(host, Sync.node(base), 0, 0)
        t.ok(near(rx, 40 * scale) and near(ry, 30 * scale) and near(r.scale, scale),
             "the root node carries the UI scale" .. at)
        t.eq(base.scale, 1, "the root item keeps its own scale" .. at)
        local c = host.inspect(Sync.node(child))
        t.ok(c.x == 100 and c.y == 50 and c.scale == 1, "a child node stays in virtual units" .. at)

        local agrees = true
        for _, p in ipairs { { 0, 0 }, { 13, 7 }, { 60, 40 } } do
            local cx, cy = Pointer.toWorld(turned, p[1], p[2])
            local nx, ny = HostWorld.toWorld(host, Sync.node(turned), p[1], p[2])
            agrees = agrees and near(nx, cx * scale) and near(ny, cy * scale)
        end
        t.ok(agrees, "a rotated, scaled root with an origin draws at scale times its virtual position" .. at)

        -- A click at window pixels hits the child with virtual coordinates
        local wx, wy = (40 + 100 + 10) * scale, (30 + 50 + 5) * scale
        feed.click(wx, wy)
        local press = log[#log - 1]
        t.ok(press and press.name == "press" and near(press.x, 10) and near(press.y, 5),
             "a click at window pixels hits the item in local units" .. at)
        t.ok(press and near(press.ax, 150) and near(press.ay, 85), "its absolute position is virtual" .. at)
        local px, py = Pointer.position()
        t.ok(near(px, 150) and near(py, 85), "Pointer.position() is virtual" .. at)
        t.eq((Pointer.pick(150, 85)), child, "Pointer.pick takes virtual units" .. at)
        local tx, ty = Pointer.toWindow(150, 85)
        t.ok(near(tx, wx) and near(ty, wy), "Pointer.toWindow converts back" .. at)

        -- Move and drag deltas
        log = {}
        feed.move(wx + 20 * scale, wy + 10 * scale)
        local move = log[#log]
        t.ok(move and near(move.dx, 20) and near(move.dy, 10), "move deltas are virtual" .. at)

        log = {}
        feed.host.advance(1000)
        feed.press(wx, wy)
        feed.move(wx + 150 * scale, wy + 30 * scale)
        local drag = log[#log]
        t.ok(drag and drag.name == "move" and near(drag.dx, 150) and near(drag.dy, 30)
                 and near(drag.x, 160) and near(drag.y, 35),
             "a captured drag outside the item has virtual deltas and positions" .. at)
        feed.release(wx + 150 * scale, wy + 30 * scale)

        log = {}
        feed.move(wx, wy)
        feed.host.feed("wheel", 0, 1)
        local wheel = log[#log]
        t.ok(wheel and wheel.name == "wheel" and near(wheel.ax, 150) and near(wheel.x, 10),
             "the wheel goes to the item under the pointer with virtual coordinates" .. at)

        base:delete()
        turned:delete()
        step()
    end

    --
    -- Tooltips at 1.5
    --
    Update:setUiScale(1.5)
    local vw, vh = Update.virtualScreenWidth, Update.virtualScreenHeight
    local topLeft = core.Item { x = 20, y = 20, width = 60, height = 30, mouseEnabled = true,
                                  toolTip = "Near the top left" }
    local bottomRight = core.Item { x = vw - 30, y = vh - 20, width = 25, height = 15,
                                      mouseEnabled = true, toolTip = "Near the bottom right corner" }
    local tipRoot = root { width = vw, height = vh, topLeft, bottomRight }
    step()

    local function hover(item, vx, vy)
        feed.move(0, 0)
        step()
        feed.move((vx - 1) * 1.5, vy * 1.5)
        feed.move(vx * 1.5, vy * 1.5)
        step(3)
        return item._toolTipInstance
    end

    local tip = hover(topLeft, 50, 35)
    t.ok(tip, "hovering creates a tooltip")
    if tip then
        t.eq(tip.scale, 1, "the tooltip has no scale of its own")
        t.ok(near(tip.x, 50) and near(tip.y, 35 + 25),
             "the tooltip is placed below the pointer in virtual units")
        local n = host.inspect(Sync.node(tip))
        local nx, ny = HostWorld.toWorld(host, Sync.node(tip), 0, 0)
        t.ok(near(nx, tip.x * 1.5) and near(ny, tip.y * 1.5) and near(n.scale, 1.5),
             "its root node is scaled like every root")
    end

    tip = hover(bottomRight, vw - 20, vh - 10)
    t.ok(tip, "hovering near the corner creates a tooltip")
    if tip then
        local width, height = tip:size()
        t.ok(width > 25 and height > 15, "the tooltip has a size")
        t.ok(tip.x >= 0 and tip.y >= 0 and tip.x + width <= vw + 1e-6 and tip.y + height <= vh + 1e-6,
             "the tooltip stays on the virtual screen")
        local sw, sh = AppHost.get().screenSize()
        local ex, ey = HostWorld.toWorld(host, Sync.node(tip), width, height)
        t.ok(ex <= sw + 1e-6 and ey <= sh + 1e-6,
             "and on the window")
    end
    feed.move(0, 0)
    core.ToolTip.destroyAllToolTips()
    tipRoot:delete()
    step()

    --
    -- Thumb drags at 1.5
    --
    local ThumbScrollSkin = core.Skin:extend {}
    function ThumbScrollSkin.new(class, self)
        self.layout = core.AnchorLayout {}
        self.children = {
            core.Item { id = "contentArea", clip = true, left = 0, top = 0, bottom = 0, right = 12 },
            core.Item {
                id = "trackbar", right = 0, top = 0, bottom = 0, width = 10,
                core.ThumbButton { id = "thumb", width = 10, height = 20 },
            },
        }
        return core.Skin.new(class, self)
    end

    local area = core.ScrollArea {
        skinClass = ThumbScrollSkin, animate = false,
        x = 50, y = 40, width = 200, height = 100,
        content = core.Item { width = 180, height = 600 },
    }
    local areaRoot = root { x = 10, y = 10, width = 400, height = 300, area }
    step(3)
    local thumb = area.thumb
    t.ok(thumb and thumb:as(core.ThumbButton) and thumb.y == 0, "the scroll area thumb starts at the top")
    local ax, ay = thumb:absolutePos()
    local sx, sy = ax + 5, ay + 5
    feed.move(sx * 1.5, sy * 1.5)
    feed.host.advance(1000)
    feed.press(sx * 1.5, sy * 1.5)
    feed.move(sx * 1.5, (sy + 30) * 1.5)
    t.ok(near(thumb.y, 30), "the ScrollArea thumb follows the pointer (" .. thumb.y .. ")")
    step()
    local _, nodeY = HostWorld.toWorld(host, Sync.node(thumb), 0, 0)
    t.ok(near(nodeY, (ay + 30) * 1.5), "and its node stays under the pointer")
    feed.release(sx * 1.5, (sy + 30) * 1.5)
    areaRoot:delete()
    step()

    local barRoot = root { width = 800, height = 600 }
    local bar = core.HorizontalScrollbar { x = 50, y = 40, width = 240, maxValue = 5 }
    barRoot:addChild(bar)
    step(2)
    bar:setValue(bar.minScroll, false, false)
    step()
    local bx, by = bar.thumbButton:absolutePos()
    bx, by = bx + 10, by + 5
    feed.move(bx * 1.5, by * 1.5)
    feed.host.advance(1000)
    feed.press(bx * 1.5, by * 1.5)
    feed.move((bx + 75) * 1.5, by * 1.5)
    t.ok(near(bar.position, 95) and near(bar.thumbButton.x, 95),
         "the HorizontalScrollbar thumb follows the pointer (" .. bar.position .. ")")
    feed.release((bx + 75) * 1.5, by * 1.5)
    barRoot:delete()
    step()

    --
    -- Changing the scale
    --
    Update:setUiScale(1)
    local entered = {}
    local left = core.Item { x = 0, y = 0, width = 100, height = 100, mouseEnabled = true,
                               mouseEnter = function() entered[#entered + 1] = "left" end }
    local right = core.Item { x = 100, y = 0, width = 100, height = 100, mouseEnabled = true,
                                mouseEnter = function() entered[#entered + 1] = "right" end }
    local pair = root { x = 0, y = 0, width = 200, height = 100, left, right }
    step()
    feed.move(150, 50)
    t.eq(Pointer.hovered(), right, "the right item is hovered at scale 1")
    step()
    host.resetLog()
    Sync.flush()
    t.eq(#host.log(), 0, "a flush without changes makes no host calls")

    Update:setUiScale(2)
    local layer = TopLayer.instance()
    t.ok(layer.scale == 1 and near(layer.width, Update.virtualScreenWidth)
             and near(layer.height, Update.virtualScreenHeight),
         "the top layer covers the virtual screen without a scale of its own")
    host.resetLog()
    Sync.flush()
    local pn = host.inspect(Sync.node(pair))
    t.ok(near(pn.scale, 2) and host.count("setTransform") >= 1,
         "the next flush re-pushes the root transform")
    t.eq(host.inspect(Sync.node(right)).x, 100, "child nodes are not touched")
    Pointer.afterUpdate()
    t.eq(Pointer.hovered(), left, "hover is re-picked under the still pointer")
    t.eq(entered[#entered], "left", "with mouseEnter")
    host.resetLog()
    Sync.flush()
    Pointer.afterUpdate()
    t.eq(#host.log(), 0, "the frame after makes no host calls")

    pair:delete()
    step()
    feed.detach()
    Sync.setHost(nil)
    if adapt then Update:setAdaptUiScale(true) else Update:setUiScale(savedScale) end
end
