--
-- core/sync.lua: the item tree rendered into a recording host. The flush
-- (no host calls without changes, coalesced setters, batch brackets),
-- attaching and detaching subtrees, draw order following child order, the
-- content of each class with content, node properties, recorded node operations
-- for the default skins, and a render smoke test with the LOVE host.
--
return function(t)
    local module = require "luif.module"
    local core = module "luif.core"
    local Sync = require "luif.core.sync"
    local Update = core.Update
    local Recording = require "luif.host.recording"
    local HostWorld = require "tests.hostworld"
    local TexDb = require "luif.core.texdb"
    local FontDb = require "luif.core.fontdb"

    local function near(a, b)
        return type(a) == "number" and type(b) == "number" and math.abs(a - b) < 1e-6
    end

    local host = Recording.new { glyphWidth = 8, lineHeight = 16 }
    local inspect = host.inspect
    local flush = Sync.flush
    local node = Sync.node

    local function children(item)
        return inspect(node(item)).children
    end
    local function contentOf(n)
        return inspect(n).content
    end
    local function kinds(item)
        local list = {}
        for _, child in ipairs(children(item)) do
            local content = contentOf(child)
            list[#list + 1] = content and content.kind or "none"
        end
        return table.concat(list, " ")
    end
    -- True when the item's node children are the nodes of the given items
    local function childNodes(item, list)
        local kids = children(item)
        if #kids ~= #list then return false end
        for i = 1, #list do
            if kids[i] ~= node(list[i]) then return false end
        end
        return true
    end
    -- Node operations since the last reset, without resources and system calls
    local function nodeOps()
        return host.count("structure") + host.count("properties") + host.count("content")
    end
    local function countNodes(n)
        local count = 1
        for _, child in ipairs(inspect(n).children) do
            count = count + countNodes(child)
        end
        return count
    end
    local function countContent(n)
        local count = contentOf(n) and 1 or 0
        for _, child in ipairs(inspect(n).children) do
            count = count + countContent(child)
        end
        return count
    end

    local created = {}
    local function run()
        local root = core.Item { x = 10, y = 20, width = 400, height = 300 }
        Sync.addRoot(root)
        created[#created + 1] = root
        t.eq(Sync.host(root), host, "a root registered after Sync.setHost lives in that host")
        t.eq(node(root), nil, "a root has no node before the flush")
        host.resetLog()
        flush()
        t.ok(node(root) and inspect(node(root)).topLevel, "the flush makes a root a top level node")
        local rs = inspect(node(root))
        t.ok(rs.x == 10 and rs.y == 20 and rs.width == 400 and rs.height == 300 and not rs.content,
             "an item node has the item's position and size and no content")
        t.ok(host.count("beginBatch") == 1 and host.count("endBatch") == 1, "the flush is one batch")
        local log = host.log()
        t.ok(log[1].op == "beginBatch" and log[#log].op == "endBatch", "the batch brackets every node call")

        --
        -- The flush: nothing without changes, setters coalesce
        --
        host.resetLog()
        flush()
        t.eq(#host.log(), 0, "a flush without changes makes no host calls")
        local now = (Update.systemTime() or 0) + 400000
        Update.onUpdate(now, 16)
        host.resetLog()
        Update.onUpdate(now + 16, 16)
        t.eq(nodeOps(), 0, "a frame without changes makes no node calls")
        t.eq(host.count("beginBatch"), 0, "and opens no batch")

        local mover = core.Item { width = 10, height = 10 }
        root:addChild(mover)
        flush()
        host.resetLog()
        mover:setPos(1, 2)
        mover:setPos(3, 4)
        mover:setSize(20, 20)
        mover:setSize(30, 30)
        mover:setAlpha(10)
        mover:setAlpha(20)
        mover:setRotation(45)
        t.eq(nodeOps(), 0, "setters make no host calls before the flush")
        flush()
        t.eq(host.count("setTransform"), 1, "several transform setters make one setTransform")
        t.eq(host.count("setSize"), 1, "several size setters make one setSize")
        t.eq(host.count("setOpacity"), 1, "several alpha setters make one setOpacity")
        local ms = inspect(node(mover))
        t.ok(ms.x == 3 and ms.y == 4 and ms.width == 30 and near(ms.opacity, 20 / 255),
             "the node has the last values")
        local texts = core.Label { text = "a", wrap = false }
        root:addChild(texts)
        flush()
        host.resetLog()
        texts:setText("b")
        texts:setText("cc")
        texts:setColor(0xFF00FF00)
        t.eq(texts.implicitWidth, 16, "label measuring stays eager")
        flush()
        t.eq(host.count("setText"), 1, "several label setters make one setText")
        t.eq(contentOf(node(texts)).text, "cc", "with the last text")

        --
        -- Attaching and detaching subtrees
        --
        local leaf = core.Image { texture = TexDb.white1x1, width = 5, height = 5 }
        local inner = core.Item { width = 50, height = 50, leaf }
        local sub = core.Item { width = 60, height = 60, inner, core.Label { text = "s" } }
        sub:setPos(5, 6)
        t.ok(not sub:isAttached() and not leaf:isAttached(), "a new subtree is detached")
        host.resetLog()
        root:addChild(sub)
        t.ok(sub:isAttached() and leaf:isAttached(), "adding it to an attached parent attaches the subtree")
        t.eq(nodeOps(), 0, "attaching makes no host calls before the flush")
        flush()
        t.eq(host.count("createNode"), 4, "the flush creates a node per item of the subtree")
        t.eq(host.count("attach"), 4, "and attaches each once")
        t.eq(inspect(node(sub)).x, 5, "setters on a detached item apply when it is attached")
        t.eq(inspect(node(leaf)).parent, node(inner), "nodes follow the item tree")
        local subNode, innerNode = node(sub), node(inner)

        host.resetLog()
        root:removeChild(sub)
        t.ok(not sub:isAttached() and not leaf:isAttached(), "removing detaches the subtree")
        t.eq(nodeOps(), 0, "detaching makes no host calls before the flush")
        flush()
        t.eq(host.count("destroyNode"), 1, "the flush destroys the subtree's top node")
        t.ok(node(sub) == nil and node(inner) == nil and node(leaf) == nil, "and forgets every node in it")
        t.eq(HostWorld.childIndex(host, node(root), subNode), nil, "the destroyed node left its parent")

        root:addChild(sub)
        flush()
        subNode, innerNode = node(sub), node(inner)
        host.resetLog()
        root:removeChild(sub)
        sub:setPos(7, 8)
        root:addChild(sub)
        flush()
        t.eq(host.count("createNode") + host.count("destroyNode"), 0,
             "detached and attached again in one frame keeps the nodes")
        t.ok(node(sub) == subNode and inspect(subNode).x == 7, "and applies changes made meanwhile")

        host.resetLog()
        root:removeChild(sub)
        inner:setParent(root)
        flush()
        t.eq(node(inner), innerNode, "an item moved out of a leaving subtree keeps its node")
        t.eq(inspect(innerNode).parent, node(root), "under its new parent")
        t.eq(host.count("destroyNode"), 1, "the rest of the subtree is destroyed")
        t.eq(host.count("createNode"), 0, "and nothing is created")
        inner:setParent(sub)
        root:addChild(sub)
        flush()
        host.resetLog()
        sub:delete()
        flush()
        t.eq(host.count("destroyNode"), 1, "deleting an attached subtree destroys its nodes")
        t.eq(#children(root), 2, "the root keeps its other children")

        local lonely = core.Item { width = 10, height = 10 }
        root:addChild(lonely)
        t.raises(function() Sync.addRoot(lonely) end, "Sync.addRoot refuses an item with a parent")
        Sync.removeRoot(lonely)
        t.ok(lonely:isAttached() and lonely.parent == root, "Sync.removeRoot does nothing on a child")
        root:removeChild(lonely)
        lonely:delete()

        --
        -- Roots
        --
        local r1 = core.Item { width = 1, height = 1 }
        local r2 = core.Item { width = 1, height = 1 }
        Sync.addRoot(r1)
        Sync.addRoot(r2)
        flush()
        local top = host.topLevel()
        t.ok(top[#top - 1] == node(r1) and top[#top] == node(r2), "roots are top level nodes in order")
        host.resetLog()
        r1:moveToTop()
        flush()
        top = host.topLevel()
        t.ok(top[#top] == node(r1) and host.count("attach") == 1, "moveToTop on a root is one attach")
        Sync.removeRoot(r2)
        t.ok(not r2:isAttached() and not Sync.isRoot(r2), "Sync.removeRoot unregisters and detaches a root")
        flush()
        t.eq(node(r2), nil, "and the flush destroys its nodes")
        local left = 0
        function r1:detached() left = left + 1 end
        r1:setParent(root)
        t.ok(not Sync.isRoot(r1) and r1:isAttached(), "a root given a parent is no root anymore")
        t.eq(left, 0, "and stays attached on the way")
        flush()
        t.eq(inspect(node(r1)).parent, node(root), "its node moves under the parent")
        r1:delete()
        r2:delete()

        --
        -- Draw order is child order
        --
        local box = core.Item { width = 100, height = 100 }
        local first = core.Item { width = 10, height = 10 }
        local image = core.Image { texture = TexDb.white1x1, width = 5, height = 5 }
        box:addChild(first)
        box:addChild(image)
        root:addChild(box)
        flush()
        t.ok(childNodes(box, { first, image }), "an image after a plain item draws after it")
        t.eq(Sync.host(image), host, "children live in their root's host")
        local label = core.Label { text = "x" }
        box:addChild(label)
        local second = core.Item { width = 10, height = 10 }
        box:addChild(second)
        local rect = core.Rectangle { width = 3, height = 3 }
        box:insertChild(1, rect)
        host.resetLog()
        flush()
        t.ok(childNodes(box, { rect, first, image, label, second }),
             "items with and without content interleave in child order")
        t.eq(host.count("attach"), 3, "inserting only attaches the new nodes")
        host.resetLog()
        first:moveToTop()
        flush()
        t.ok(childNodes(box, { rect, image, label, second, first }), "moveToTop moves the node to the end")
        t.eq(host.count("attach"), 1, "with one attach")
        box:removeChild(label)
        t.ok(not label:isAttached(), "removing a child detaches it")
        flush()
        t.eq(#children(box), 4, "and the flush removes its node")
        label:delete()
        box:removeChild(rect)
        rect:delete()

        -- A skinned item: the skin is its first child, its content children
        -- are children of the content area after the area's own children
        local AreaSkin = core.Skin:extend { width = 80, height = 40 }
        function AreaSkin.new(class, self)
            self.layout = core.AnchorLayout {}
            self.children = {
                core.Rectangle { left = 0, top = 0, right = 0, bottom = 0 },
                core.Item { id = "contentArea", left = 4, top = 4, right = 4, bottom = 4,
                              core.Image { texture = TexDb.white1x1 } },
            }
            return core.Skin.new(class, self)
        end
        local ownItem = core.Item { width = 5, height = 5 }
        local ownImage = core.Image { texture = TexDb.white1x1 }
        local skinned = core.SkinnableItem { skinClass = AreaSkin, ownItem, ownImage }
        root:addChild(skinned)
        flush()
        local area = skinned.contentArea
        t.ok(childNodes(skinned, { skinned.skin }), "a skinned item's node holds its skin")
        t.ok(childNodes(area, { area.children[1], ownItem, ownImage }),
             "its children follow the content area's own children")
        t.eq(ownImage.parent, area, "the content area is their parent")
        local extra = core.Rectangle { width = 2, height = 2 }
        extra:setParent(skinned)
        flush()
        t.ok(extra.parent == area and inspect(node(extra)).parent == node(area),
             "setParent onto the item puts the child in the content area")
        local ax, ay = extra:absolutePos()
        local bx, by = area:absolutePos()
        t.ok(ax == bx and ay == by, "absolutePos includes the content area")

        --
        -- Image: box, centre scale and rotation, flips as content flags
        --
        local picture = core.Image {
            texture = TexDb.white1x1, x = 10, y = 20, width = 40, height = 30,
            scale = 2, rotation = 90, flipX = true, color = 0x80FF0000,
        }
        box:addChild(picture)
        flush()
        local s = inspect(node(picture))
        t.ok(s.x == 10 and s.y == 20 and s.width == 40 and s.height == 30, "image node box is its unscaled rect")
        t.ok(s.scale == 2 and s.originX == 20 and s.originY == 15, "image scale is a node scale around the centre")
        t.ok(near(s.rotation, math.pi / 2), "image rotation in radians around the centre")
        t.ok(s.content.kind == "image" and s.content.texture == TexDb.white1x1 and s.content.tint == 0x80FF0000,
             "image content with texture and tint")
        t.ok(s.content.flipX and not s.content.flipY and #s.children == 0, "flipX is a content flag")
        local cx, cy = HostWorld.toWorld(host, node(picture), 20, 15)
        t.ok(near(cx, 10 + 30) and near(cy, 20 + 35), "the centre stays in place under scale and rotation")
        local ex, ey = HostWorld.toWorld(host, node(picture), 40, 15)
        t.ok(near(ex, 40) and near(ey, 55 + 40), "a point on the edge is scaled and rotated around the centre")
        picture:setFlip(false, true)
        flush()
        s = inspect(node(picture))
        t.ok(not s.content.flipX and s.content.flipY, "setFlip changes the content flags")
        picture:setGrayScale(true)
        flush()
        s = inspect(node(picture))
        t.ok(s.content.grayscale and s.content.tint == 0x80FF0000, "grayscale is a flag, the tint stays")
        picture:setRotation(0)
        picture:setTransformOrigin(0, 1)
        flush()
        s = inspect(node(picture))
        t.ok(s.originX == 0 and s.originY == 30 and s.scale == 2, "the transform origin is a fraction of the size")
        picture:setAlpha(51)
        picture:setVisible(false)
        flush()
        s = inspect(node(picture))
        t.ok(near(s.opacity, 0.2) and s.visible == false, "alpha and visibility are node opacity and visibility")

        --
        -- Rectangle: fill content with the border
        --
        local filled = core.Rectangle { color = 0xFF112233, borderColor = 0xFF445566, borderWidth = 2,
                                        x = 1, y = 2, width = 30, height = 20 }
        box:addChild(filled)
        flush()
        s = inspect(node(filled))
        t.ok(s.content.kind == "fill" and s.content.color == 0xFF112233, "rectangle is fill content")
        t.ok(s.content.borderColor == 0xFF445566 and s.content.borderWidth == 2 and #s.children == 0,
             "the border is part of the fill content, in one node")
        t.ok(s.width == 30 and s.height == 20, "the fill covers the node box")
        filled:setBorderColor(false)
        flush()
        s = inspect(node(filled))
        t.ok(s.content.borderColor == false and s.content.borderWidth == 0, "a rectangle without border")

        --
        -- Label: text content, wrap box and alignment
        --
        local wrapped = core.Label { text = "one two three four",
                                     width = 80, align = "center", color = 0xFF00FF00 }
        box:addChild(wrapped)
        flush()
        s = inspect(node(wrapped))
        t.ok(s.content.kind == "text" and s.content.text == "one two three four", "label text content")
        t.ok(s.content.wrap and s.content.align == "center" and s.content.color == 0xFF00FF00,
             "wrap, alignment and colour reach the content")
        t.ok(s.width == 80 and s.height == 32, "the node box is the wrap width and the text height")
        t.ok(wrapped.implicitWidth == 80 and wrapped.implicitHeight == 32,
             "implicit size comes from the host's wrapText and lineHeight")
        wrapped:setTextScale(2)
        flush()
        s = inspect(node(wrapped))
        t.ok(s.scale == 2 and s.width == 40, "the text scale is a node scale, the box is in unscaled font units")
        t.ok(wrapped.implicitWidth == 80 and wrapped.implicitHeight == 128, "scaled implicit size wraps at half the width")
        wrapped:setScale(1.5)
        wrapped:setRotation(30)
        flush()
        local Pointer = require "luif.core.pointer"
        local px, py = Pointer.toWorld(wrapped, 80, 128)
        local qx, qy = HostWorld.toWorld(host, node(wrapped), 40, 64)
        local bx, by = HostWorld.toWorld(host, node(box), 0, 0)
        local ox, oy = Pointer.toWorld(box, 0, 0)
        t.ok(near(px - ox, qx - bx) and near(py - oy, qy - by),
             "a rotated, scaled label with a text scale draws where it is picked")
        t.eq(wrapped.implicitWidth, 80, "the item scale leaves the implicit size alone")
        wrapped:setScale(1)
        wrapped:setRotation(0)
        local single = core.Label { text = "Hi", wrap = false, width = 100, align = "right" }
        box:addChild(single)
        flush()
        s = inspect(node(single))
        t.ok(not s.content.wrap and s.content.align == "right" and s.width == 16,
             "without wrapping the box is the text, so lines align among themselves")
        local colored = core.Label { text = "{color:#ff0000}red{/color} x", wrap = false }
        box:addChild(colored)
        flush()
        s = inspect(node(colored))
        t.ok(type(s.content.text) == "table" and s.content.text[1] == 0xFFFF0000 and s.content.text[2] == "red",
             "colour tags become runs")
        local abbreviated = core.Label { text = "a long text here",
                                         width = 60, abbreviate = true }
        box:addChild(abbreviated)
        flush()
        s = inspect(node(abbreviated))
        t.ok(not s.content.wrap and s.width == 60 and s.content.text:sub(-3) == "\226\128\166",
             "abbreviated text ends in an ellipsis within the box")
        host.resetLog()
        colored:setPos(colored.x, colored.y)
        colored:setColor(colored.color)
        flush()
        t.eq(nodeOps(), 0, "setters that change nothing make no node operations")

        --
        -- Clip, opacity and transform on an item node
        --
        local clipper = core.Item { width = 50, height = 40, clip = true }
        root:addChild(clipper)
        flush()
        s = inspect(node(clipper))
        t.ok(s.clip and s.width == 50 and s.height == 40, "clip is set on the item's node with its size")
        clipper:setSize(60, 45)
        flush()
        s = inspect(node(clipper))
        t.ok(s.clip and s.width == 60 and s.height == 45, "the clip box follows the item size")
        clipper:setClip(false)
        flush()
        t.eq(inspect(node(clipper)).clip, false, "setClip(false) clears the node clip")
        clipper:setAlpha(128)
        clipper:setRotation(45)
        clipper:setScale(1.5)
        clipper:setTransformOrigin(0.5, 0.25)
        flush()
        s = inspect(node(clipper))
        t.ok(near(s.opacity, 128 / 255) and near(s.rotation, math.rad(45)) and s.scale == 1.5
             and s.originX == 30 and s.originY == 11.25, "item alpha, rotation, scale and origin")
        clipper:setVisible(false)
        flush()
        t.eq(inspect(node(clipper)).visible, false, "an invisible item has an invisible node")

        --
        -- Slices, sliced images and lines
        --
        local nine = core.Scale9 { source = "tooltip_box", width = 50, height = 40 }
        box:addChild(nine)
        flush()
        s = inspect(node(nine))
        t.ok(s.content.kind == "slices" and s.content.texture == TexDb.tooltip_box and #s.children == 0,
             "a Scale9 from a TexDb source is one slices node")
        t.ok(s.content.left == 6 and s.content.top == 6 and s.content.right == 6 and s.content.bottom == 6,
             "with the registered insets")
        local three = core.ScaleH3 { source = "tooltip_box", width = 70 }
        box:addChild(three)
        flush()
        s = inspect(node(three))
        t.ok(s.content.kind == "slices" and s.content.left == 6 and s.content.top == 0
             and s.content.right == 6 and s.content.bottom == 0, "a ScaleH3 is slices without top and bottom")
        local grid = core.SlicedImage { textures = { TexDb.white1x1, TexDb.white1x1, TexDb.white1x1,
                                                     TexDb.white1x1 }, columns = 2, scale = 3 }
        box:addChild(grid)
        flush()
        s = inspect(node(grid))
        local p4 = #s.children == 4 and inspect(s.children[4])
        t.ok(not s.content and p4 and p4.x == 1 and p4.y == 1 and p4.width == 1 and p4.content.kind == "image",
             "a SlicedImage draws its grid as child images")
        t.eq(s.scale, 3, "a SlicedImage's scale is its node scale")
        grid:setSize(4, 6)
        flush()
        p4 = inspect(inspect(node(grid)).children[4])
        t.ok(p4.x == 2 and p4.y == 3 and p4.width == 2 and p4.height == 3, "an explicit size stretches the grid")
        local line = core.Line { startX = 10, startY = 10, endX = 10, endY = 110, thickness = 4 }
        box:addChild(line)
        flush()
        s = inspect(node(line))
        t.ok(s.content.kind == "image" and s.width == 100 and s.height == 4 and near(s.rotation, math.pi / 2),
             "a Line is its body, rotated towards the end")
        t.eq(#s.children, 2, "the arrow head and tail are two child images")
        local hx, hy = HostWorld.toWorld(host, s.children[1], 8, 8)
        local lx, ly = HostWorld.toWorld(host, node(box), 10, 110)
        t.ok(near(hx, lx) and near(hy, ly), "the arrow head is centred on the end point")
        line:setEnd(110, 10)
        flush()
        s = inspect(node(line))
        hx, hy = HostWorld.toWorld(host, s.children[1], 8, 8)
        lx, ly = HostWorld.toWorld(host, node(box), 110, 10)
        t.ok(near(hx, lx) and near(hy, ly), "the arrow head follows the end point")
        grid:setTextures({ TexDb.white1x1, TexDb.white1x1 })
        grid:setColor(0xFF00FF00)
        flush()
        s = inspect(node(grid))
        t.ok(#s.children == 2 and #grid.children == 2 and inspect(s.children[2]).content.tint == 0xFF00FF00,
             "a SlicedImage drops surplus images and tints the others")

        --
        -- Default skins: node tree, content and recorded operations
        --
        local function build(name, item, parent)
            flush()
            if parent then
                parent:addChild(item)
            else
                Sync.addRoot(item)
                created[#created + 1] = item
            end
            host.resetLog()
            flush()
            local nodes = countNodes(node(item))
            t.eq(host.count("createNode"), nodes, name .. ": one createNode per node")
            t.eq(host.count("attach"), nodes, name .. ": one attach per node")
            t.eq(host.count("content"), countContent(node(item)), name .. ": one content call per content node")
            t.eq(host.count("destroyNode") + host.count("detach"), 0, name .. ": no nodes destroyed or detached")
            return nodes
        end

        -- DefaultButtonSkin
        local button = core.Button { text = "OK" }
        local nodes = build("Button", button, root)
        t.eq(nodes, 5, "Button: button, skin and three content nodes")
        t.ok(childNodes(button, { button.skin }), "Button: the skin's node is the button's only child")
        t.eq(kinds(button.skin), "image text image", "Button: gradient image, label text and icon image")
        s = inspect(children(button.skin)[1])
        t.ok(s.content.texture == TexDb.gradient01 and s.content.tint == 0xFFCCCCCC, "Button: gradient tint")
        s = inspect(node(button.label))
        t.ok(s.content.text == "OK" and s.content.font == FontDb.Medium and s.content.color == 0xFF000000,
             "Button: label content")
        button:setState("over", false)
        flush()
        t.eq(inspect(children(button.skin)[1]).scale, 1, "Button: the over state keeps the background at its size")
        s = inspect(children(button.skin)[3])
        t.ok(near(s.scale, 1.15) and s.originX == s.width / 2, "Button: the over state scales the icon around its centre")
        host.resetLog()
        Sync.propertiesChanged(button)
        Sync.contentChanged(button.label)
        flush()
        t.eq(host.count("structure") + host.count("properties"), 0,
             "Button: pushing unchanged properties makes no node operations")
        t.eq(host.count("content"), 1, "Button: marked content is pushed again")

        -- DefaultToggleButtonSkin
        local toggle = core.ToggleButton { text = "T" }
        build("ToggleButton", toggle, root)
        t.eq(kinds(toggle.skin), "image image image text", "ToggleButton: background, two icons and label")
        s = inspect(children(toggle.skin)[3])
        t.ok(s.opacity == 0 and near(s.scale, 1 / 1.15), "ToggleButton: the hover icon starts transparent and small")

        -- DefaultScrollAreaSkin
        local rows = {}
        for i = 1, 3 do rows[i] = core.Item { width = 50, height = 20 } end
        local scroll = core.ScrollArea { width = 120, height = 100, content = core.Column { unpack(rows) } }
        build("ScrollArea", scroll, root)
        local skin = scroll.skin
        t.ok(childNodes(skin, { scroll.contentArea, scroll.trackbar, scroll.upButton, scroll.downButton }),
             "ScrollArea: content area, track and buttons in skin order")
        t.ok(inspect(node(scroll.contentArea)).clip, "ScrollArea: the content area clips")
        t.eq(inspect(node(scroll.content)).parent, node(scroll.contentArea),
             "ScrollArea: the content hangs under the content area node")
        t.eq(kinds(scroll.trackbar), "image image", "ScrollArea: track and thumb images")

        -- DefaultLineEditSkin
        local lineEdit = core.LineEdit { width = 150 }
        build("LineEdit", lineEdit, root)
        local kids = children(lineEdit.skin)
        t.ok(#kids == 2 and kids[2] == node(lineEdit.textInput), "LineEdit: frame then text input")
        s = inspect(kids[1])
        t.ok(s.content.kind == "fill" and s.content.color == 0xFF303030 and s.content.borderColor == 0xFF808080
             and s.content.borderWidth == 1, "LineEdit: the bordered frame is one fill node")
        t.eq(kinds(lineEdit.textInput), "text fill", "LineEdit: label text and caret fill")

        -- DefaultLabelToolTipSkin (and DefaultToolTipSkin)
        local tipped = core.Item { width = 20, height = 20, toolTip = "tip" }
        root:addChild(tipped)
        local tip = core.LabelToolTip { item = tipped, mouseX = 5, mouseY = 5 }
        build("LabelToolTip", tip)
        t.ok(inspect(node(tip)).topLevel, "LabelToolTip: a tool tip is a top level node")
        kids = children(tip.skin)
        s = inspect(kids[1])
        t.ok(s.content.kind == "slices" and #s.children == 0 and s.content.texture == TexDb.tooltip_box,
             "LabelToolTip: the box is one nine-slice node")
        t.ok(kids[2] == node(tip.skin.children.contentArea), "LabelToolTip: then the content area")
        s = inspect(node(tip.titleLabel))
        t.ok(s.parent == kids[2] and s.content.text == "tip", "LabelToolTip: the title label in the content area")

        -- DefaultHorizontalScrollbarSkin
        local bar = core.HorizontalScrollbar { width = 200, maxValue = 4 }
        nodes = build("HorizontalScrollbar", bar, root)
        t.ok(childNodes(bar.skin, { bar.trackbar, bar.thumbButton, bar.leftButton, bar.rightButton }),
             "HorizontalScrollbar: track, thumb, left and right buttons")
        t.eq(kinds(bar.trackbar), "image", "HorizontalScrollbar: the track image")
        t.eq(kinds(bar.leftButton.skin), "image text image", "HorizontalScrollbar: buttons use the button skin")
        t.eq(nodes, 2 + 2 + 3 * 5, "HorizontalScrollbar: node count")

        -- Removing a tree releases its nodes
        host.resetLog()
        local scrollNode = node(scroll)
        root:removeChild(scroll)
        flush()
        t.eq(host.count("createNode"), 0, "removing creates no nodes")
        t.ok(not scroll:isAttached() and not scroll.skin:isAttached(), "removed items are detached")
        t.ok(node(scroll) == nil and node(scroll.skin) == nil, "and have no nodes")
        t.eq(HostWorld.childIndex(host, node(root), scrollNode), nil, "the destroyed node left its parent")
        scroll:delete()
    end

    Sync.setHost(host)
    local ok, err = xpcall(run, debug.traceback)
    Sync.setHost(nil)
    for i = #created, 1, -1 do
        created[i]:delete()
    end
    flush()
    t.ok(ok, "sync tests ran: " .. tostring(err))
    t.eq(#host.topLevel(), 0, "deleting the roots empties the recording host")
    t.eq(Sync.host(nil), require("luif.core.host").get(), "Sync.setHost(nil) restores the application host")

    --
    -- Rendering an item tree with the LOVE host: clips, rotation, text and slices
    --
    if not (love and love.graphics and love.graphics.isCreated()) then
        t.skip("rendering with the LOVE host needs love.graphics")
        return
    end
    local Host = require "luif.love.host"
    local loveHost = Host.new()
    Sync.setHost(loveHost)
    local scene = core.Item { x = 20, y = 20, width = 300, height = 200, clip = true,
        core.Scale9 { source = "tooltip_box", width = 100, height = 60 },
        core.Item { x = 50, y = 50, width = 80, height = 80, rotation = 30, clip = true,
            core.Label { text = "{color:#ff0000}clipped{/color} text", width = 60 },
            core.Image { texture = TexDb.gradient01, width = 40, height = 20, flipY = true, scale = 1.5 },
        },
    }
    local built = pcall(function() Sync.addRoot(scene) end)
    Sync.setHost(nil)
    t.ok(built, "an item tree builds for a LOVE host")
    local flushed, flushError = pcall(flush)
    t.ok(flushed and #loveHost.topLevel() == 1, "the flush fills the LOVE host: " .. tostring(flushError))
    local drawn, drawError = pcall(loveHost.render)
    t.ok(drawn, "the LOVE host renders it with scissor and stencil clips: " .. tostring(drawError))
    t.eq(love.graphics.getScissor(), nil, "rendering restores the scissor")
    scene:delete()
    flush()
    t.eq(#loveHost.topLevel(), 0, "deleting the tree empties the host")
end
