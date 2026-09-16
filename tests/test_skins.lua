--
-- Skins as ordinary children: the skin is a SkinnableItem's first child,
-- content children live in the skin's content area, child calls on the
-- item forward there, id lookups keep skin parts and content apart,
-- states apply once, layouts still size the skin and place the content,
-- the host scene has the item tree's shape, input reaches the item in its
-- own space, and deleting releases every node.
--
return function(t)
    local module = require "luif.module"
    local core = module "luif.core"
    local Sync = require "luif.core.sync"
    local Update = core.Update
    local Screen = core.Screen
    local Pointer = require "luif.core.pointer"
    local LayoutManager = require "luif.core.layoutmanager"
    local Recording = require "luif.host.recording"
    local InputFeed = require "tests.inputfeed"

    local host = Recording.new { glyphWidth = 8, lineHeight = 16 }
    local inspect = host.inspect
    local flush = Sync.flush
    local node = Sync.node

    local now = (Update.systemTime() or 0) + 600000
    local function step(frames)
        for _ = 1, frames or 1 do
            now = now + 16
            Update.onUpdate(now, 16)
            Pointer.afterUpdate()
        end
    end

    -- A skin with a frame part, a label part and a content area at (10, 20)
    local PanelSkin = core.Skin:extend { width = 200, height = 120 }
    function PanelSkin.new(class, self)
        self.layout = core.AnchorLayout {}
        self.children = {
            core.Rectangle { id = "frame", left = 0, top = 0, right = 0, bottom = 0 },
            core.Label { id = "label", text = "part", wrap = false },
            core.Item { id = "contentArea", left = 10, top = 20, right = 10, bottom = 10 },
        }
        return core.Skin.new(class, self)
    end
    local Panel = core.SkinnableItem:extend {
        skinClass = PanelSkin,
        skinParts = { "frame", "label" },
    }

    -- A skin without a content area
    local PlainSkin = core.Skin:extend { width = 60, height = 30 }
    function PlainSkin.new(class, self)
        self.layout = core.AnchorLayout {}
        self.children = {
            core.Rectangle { id = "frame", left = 0, top = 0, right = 0, bottom = 0 },
        }
        return core.Skin.new(class, self)
    end

    -- True when the node tree under the item's node has the item tree's shape
    local function sameShape(item)
        local n = node(item)
        if not n then return false, "no node for " .. item:toString() end
        local kids = inspect(n).children
        local children = item.children
        if not kids or #kids ~= #children then
            return false, "node count differs from child count under " .. item:toString()
        end
        for i = 1, #children do
            local child = children[i]
            if kids[i] ~= node(child) then
                return false, "child " .. i .. " of " .. item:toString()
            end
            if inspect(kids[i]).parent ~= n then
                return false, "node parent of " .. child:toString()
            end
            local ok, why = sameShape(child)
            if not ok then return false, why end
        end
        return true
    end

    local created = {}
    local function run()
        local root = core.Item { width = 800, height = 600 }
        Sync.addRoot(root)
        created[#created + 1] = root

        --
        -- Structure
        --
        local a = core.Item { id = "a", width = 10, height = 10 }
        local b = core.Item { id = "b", width = 10, height = 10 }
        local panel = Panel { x = 100, y = 50, a, b }
        local skin, area = panel.skin, panel.contentArea
        t.eq(panel.children[1], skin, "the skin is the first child")
        t.eq(#panel.children, 1, "with a content area the skin is the only child")
        t.eq(skin.parent, panel, "the skin's parent is the item")
        t.ok(area and area.parent == skin, "the content area is in the skin")
        t.ok(a.parent == area and b.parent == area and area.children[1] == a and area.children[2] == b,
             "inline children move into the content area in order")
        t.ok(panel.frame and panel.label and panel.frame.parent == skin, "skin parts are resolved")
        local list, first = panel:contentChildren()
        t.ok(list == area.children and first == 1, "contentChildren is the content area's list")

        root:addChild(panel)
        local plain = core.SkinnableItem { skinClass = PlainSkin, core.Item { id = "p" } }
        root:addChild(plain)
        t.eq(plain.children[1], plain.skin, "without a content area the skin is also first")
        list, first = plain:contentChildren()
        t.ok(first == 2 and list[2].id == "p" and list[2].parent == plain,
             "and the content follows it as direct children")

        --
        -- Forwarding
        --
        local c = core.Item { id = "c" }
        panel:addChild(c)
        t.ok(c.parent == area and area.children[3] == c, "addChild appends to the content area")
        local d = core.Item { id = "d" }
        panel:insertChild(1, d)
        t.ok(d.parent == area and area.children[1] == d, "insertChild indexes the content")
        panel:removeChild(d)
        t.ok(not d.parent and area.children[1] == a, "removeChild removes from the content area")
        d:setParent(panel)
        t.ok(d.parent == area and area.children[#area.children] == d, "setParent onto the item uses the content area")
        a:moveToTop()
        t.eq(area.children[#area.children], a, "moveToTop moves a content child to the top of the content")
        t.eq(panel.children[1], skin, "and leaves the skin in place")
        d:setParent(false)

        local q = core.Item { id = "q" }
        plain:insertChild(1, q)
        t.ok(plain.children[1] == plain.skin and plain.children[2] == q,
             "without a content area insertChild counts after the skin")
        local r = core.Item { id = "r" }
        plain:addChild(r)
        t.eq(plain.children[#plain.children], r, "and addChild appends")
        plain:removeChildren()
        t.ok(#plain.children == 1 and plain.children[1] == plain.skin, "removeChildren keeps the skin")
        plain:setChildren { q, r }
        t.ok(#plain.children == 3 and plain.children[3] == r, "setChildren adds after the skin")
        d:delete()

        --
        -- Id lookups
        --
        local clash = core.Item { id = "label" }
        panel:addChild(clash)
        t.eq(panel:findChild("label"), clash, "findChild finds content, not the skin part with that id")
        t.eq(panel.label.parent, skin, "the skin part keeps its id")
        t.eq(panel:findChild("frame"), false, "skin parts are not found through the item")
        t.eq(root:findChild("frame"), false, "nor through its ancestors")
        local found = panel:findChildren { label = false, c = false }
        t.ok(found.label == clash and found.c == c, "findChildren searches the content too")
        panel:removeChild(clash)
        clash:delete()

        --
        -- States apply once
        --
        local counts = {}
        local function counter(name)
            return function(item, value)
                counts[name] = (counts[name] or 0) + 1
                item.alpha = value
            end
        end
        local Counted = core.Item:extend {}
        local stateful = Counted { states = { hot = { alpha = 100 } } }
        stateful.setAlpha = counter("content")
        local StatePanel = core.SkinnableItem:extend {}
        local StateSkin = core.Skin:extend { width = 50, height = 50 }
        function StateSkin.new(class, self)
            local part = Counted { states = { hot = { alpha = 120 } } }
            part.setAlpha = counter("part")
            local areaChild = Counted { states = { hot = { alpha = 140 } } }
            areaChild.setAlpha = counter("area child")
            self.children = {
                part,
                core.Item { id = "contentArea", areaChild },
            }
            return core.Skin.new(class, self)
        end
        local statePanel = StatePanel { skinClass = StateSkin, stateful }
        local holder = core.Item { statePanel }
        root:addChild(holder)
        statePanel:setState("hot", false)
        t.eq(counts.content, 1, "a content child's state applies once")
        t.eq(counts.part, 1, "a skin part's state applies once")
        t.eq(counts["area child"], 1, "a content area child's state applies once")
        statePanel:setState("", false)
        t.ok(counts.content == 2 and counts.part == 2, "reverting applies once as well")
        counts = {}
        holder:setState("hot", false)
        t.eq(counts.content, 1, "an ancestor's state reaches the content once")
        t.eq(counts.part, nil, "but not the skin")

        --
        -- Layout: the skin follows the item, content children follow
        -- the item's layout within the content area
        --
        local anchored = core.Item { left = 0, right = 0, top = 0, height = 5 }
        local laid = Panel { layout = core.AnchorLayout {}, width = 200, height = 120, anchored }
        root:addChild(laid)
        LayoutManager:validateLayout(laid.layout)
        laid:validateLayoutRecursively()
        local sw, sh = laid.skin:size()
        t.ok(sw == 200 and sh == 120, "the skin has the item's size")
        t.eq(anchored:size(), 180, "an anchored content child fills the content area width")
        laid:setSize(300, 150)
        laid:validateLayoutRecursively()
        sw = laid.skin:size()
        t.ok(sw == 300 and laid.contentArea:size() == 280 and anchored:size() == 280,
             "resizing the item resizes skin, content area and content")
        local invalidated = 0
        local watched = core.SkinnableItem { skinClass = PanelSkin,
            layout = core.Layout { invalidate = function() invalidated = invalidated + 1 end } }
        local grow = core.Item { width = 5, height = 5 }
        watched:addChild(grow)
        invalidated = 0
        grow:setSize(10, 10)
        t.ok(invalidated > 0, "a content child's resize invalidates the item's layout")

        --
        -- The host scene has the item tree's shape
        --
        flush()
        local ok, why = sameShape(root)
        t.ok(ok, "node tree equals item tree for skinned items: " .. tostring(why))
        t.eq(inspect(node(a)).parent, node(area), "a content child's node is in the content area's node")
        t.eq(inspect(node(skin)).parent, node(panel), "the skin's node is in the item's node")
        panel:addChild(core.Item {})
        a:moveToTop()
        flush()
        ok, why = sameShape(panel)
        t.ok(ok, "and after adding and moving content: " .. tostring(why))

        --
        -- Deleting a skinned item with content releases all nodes
        --
        local before = #host.topLevel()
        host.resetLog()
        local nodes = 0
        local function countNodes(n)
            nodes = nodes + 1
            for _, kid in ipairs(inspect(n).children) do countNodes(kid) end
        end
        countNodes(node(panel))
        local panelNode = node(panel)
        panel:delete()
        flush()
        t.eq(host.count("destroyNode"), 1, "deleting destroys the item's node subtree once")
        t.eq(node(a), nil, "content children have no nodes left")
        t.ok(nodes > 5 and #host.topLevel() == before, "the host keeps only the other trees")
        local present = false
        for _, kid in ipairs(inspect(node(root)).children) do
            if kid == panelNode then present = true end
        end
        t.ok(not present, "the item's node left its parent")
    end

    Sync.setHost(host)
    local ok, err = xpcall(run, debug.traceback)
    Sync.setHost(nil)
    for i = #created, 1, -1 do
        created[i]:delete()
    end
    flush()
    t.ok(ok, "skin tests ran: " .. tostring(err))
    t.eq(#host.topLevel(), 0, "deleting the roots empties the recording host")

    --
    -- Input through a skinned item: picking goes through skin and content
    -- area, bubbling delivers coordinates in each receiver's space
    --
    local adapt, savedScale = Screen.adaptive, Screen.scale
    Screen:setScale(1)
    local feed = InputFeed.attach()
    local received = {}
    local ignore = function(_, event) event:ignore() end
    local inner = core.Item { x = 5, y = 6, width = 30, height = 30, mouseEnabled = true,
                                mousePress = ignore }
    local panel = Panel {
        x = 300, y = 200, mouseEnabled = true,
        mousePress = function(self, event)
            received.x, received.y, received.source = event:x(), event:y(), event.source
        end,
        inner,
    }
    Sync.addRoot(panel)
    panel:validateLayoutRecursively()
    step(2)
    local hit, lx, ly = Pointer.pick(300 + 10 + 5 + 3, 200 + 20 + 6 + 4)
    t.eq(hit, inner, "a content child is picked through skin and content area")
    t.ok(lx == 3 and ly == 4, "with its own local position")
    local wx, wy = Pointer.toWorld(inner, 0, 0)
    local ax, ay = inner:absolutePos()
    t.ok(wx == 315 and wy == 226 and ax == wx and ay == wy, "absolutePos and the world transform agree")
    feed.click(318, 230)
    t.eq(received.source, inner, "the press bubbled from the content child")
    t.ok(received.x == 18 and received.y == 30, "and arrived in the item's space")
    panel:delete()
    flush()
    feed.detach()
    if adapt then Screen:setAdaptive(true) else Screen:setScale(savedScale) end
end
