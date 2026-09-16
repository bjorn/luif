--
-- Picking in core/pointer.lua: rotated and scaled items, transform
-- origins, nested scale, clipping, invisible and alpha 0 items, sibling
-- and root order, skinned content areas, and the generation counter that
-- limits re-picking under a still pointer. Positions are cross-checked
-- against the items' host nodes (after a flush), which is what draws.
--
return function(t)
    local module = require "luif.module"
    local core = module "luif.core"
    local Pointer = require "luif.core.pointer"
    local InputFeed = require "tests.inputfeed"
    local HostWorld = require "tests.hostworld"
    local Sync = require "luif.core.sync"

    local function near(a, b)
        return math.abs(a - b) < 1e-6
    end

    local created = {}
    local function root(props)
        local item = core.Item(props)
        Sync.addRoot(item)
        created[#created + 1] = item
        return item
    end

    -- The core transform agrees with the item's node
    local function sameAsNode(item, label)
        Sync.flush()
        local ok = true
        for _, p in ipairs { { 0, 0 }, { 13, 7 }, { -5, 21 } } do
            local cx, cy = Pointer.toWorld(item, p[1], p[2])
            local nx, ny = HostWorld.toWorld(Sync.host(item), Sync.node(item), p[1], p[2])
            ok = ok and near(cx, nx) and near(cy, ny)
        end
        t.ok(ok, label .. ": core transform matches the node")
    end

    -- Rotation by 90 degrees around the item's top left: local (lx, ly) is
    -- at window (100 - ly, 100 + lx).
    local rot = root { x = 100, y = 100, width = 50, height = 20, rotation = 90, mouseEnabled = true,
                       transformOriginX = 0, transformOriginY = 0 }
    local hit, lx, ly = Pointer.pick(100 - 19.5, 100 + 49.5)
    t.eq(hit, rot, "rotated item picked")
    t.ok(near(lx, 49.5) and near(ly, 19.5), "rotated local coordinates")
    t.eq((Pointer.pick(100, 100)), rot, "rotated corner (0, 0)")
    t.eq((Pointer.pick(100, 149.9)), rot, "rotated corner (49.9, 0)")
    t.eq((Pointer.pick(80.1, 100)), rot, "rotated corner (0, 19.9)")
    t.eq((Pointer.pick(80.1, 149.9)), rot, "rotated corner (49.9, 19.9)")
    t.eq((Pointer.pick(90, 150.5)), nil, "rotated: past the far edge misses")
    t.eq((Pointer.pick(100.5, 110)), nil, "rotated: outside the unrotated rect misses")
    local wx, wy = Pointer.toWorld(rot, 50, 20)
    t.ok(near(wx, 80) and near(wy, 150), "toWorld of the rotated corner")
    local bx, by = Pointer.toLocal(rot, wx, wy)
    t.ok(near(bx, 50) and near(by, 20), "toLocal round trip")
    sameAsNode(rot, "rotated")

    -- Rotated and scaled around a transform origin
    local spun = root {
        x = 300, y = 100, width = 40, height = 20, mouseEnabled = true,
        rotation = 30, scale = 1.5, transformOriginX = 0.5, transformOriginY = 0.5,
    }
    sameAsNode(spun, "rotated and scaled")
    local fixedX, fixedY = Pointer.toWorld(spun, 20, 10)
    t.ok(near(fixedX, 320) and near(fixedY, 110), "the transform origin stays in place")
    local allInside = true
    for _, p in ipairs { { 1, 1 }, { 39, 19 }, { 20, 10 }, { 2, 18 } } do
        local px, py = Pointer.toWorld(spun, p[1], p[2])
        hit, lx, ly = Pointer.pick(px, py)
        allInside = allInside and hit == spun and near(lx, p[1]) and near(ly, p[2])
    end
    t.ok(allInside, "points inside the rotated, scaled box pick it with their local position")
    local outX, outY = Pointer.toWorld(spun, 42, 10)
    t.eq((Pointer.pick(outX, outY)), nil, "a point just past its edge misses")

    -- Nested scale: parent at (10, 400) scale 2, child at (5, 5); a child
    -- local point is at window (20 + 2 lx, 410 + 2 ly).
    local scaled = root { x = 10, y = 400, width = 100, height = 100, scale = 2, mouseEnabled = true,
                          transformOriginX = 0, transformOriginY = 0 }
    local small = core.Item { x = 5, y = 5, width = 10, height = 10, mouseEnabled = true }
    scaled:addChild(small)
    hit, lx, ly = Pointer.pick(25, 417)
    t.eq(hit, small, "nested scale: child picked")
    t.ok(near(lx, 2.5) and near(ly, 3.5), "nested scale: child local coordinates")
    hit, lx, ly = Pointer.pick(41, 430)
    t.eq(hit, scaled, "nested scale: parent picked outside the child")
    t.ok(near(lx, 15.5) and near(ly, 15), "nested scale: parent local coordinates")
    sameAsNode(small, "nested scale")

    -- Clip: the child sticks out of its parent; outside the parent's box it
    -- is not picked while the parent clips.
    local clipper = root { x = 500, y = 0, width = 50, height = 50, clip = true }
    local sticking = core.Item { x = 40, y = 40, width = 30, height = 30, mouseEnabled = true }
    clipper:addChild(sticking)
    t.eq((Pointer.pick(545, 45)), sticking, "clip: child inside the clip box")
    t.eq((Pointer.pick(560, 60)), nil, "clip: child outside the clip box is not picked")
    clipper:setClip(false)
    t.eq((Pointer.pick(560, 60)), sticking, "no clip: child outside the box is picked")
    clipper:setClip(true)

    -- A clip follows its item's rotation
    local turned = root { x = 700, y = 300, width = 40, height = 40, rotation = 45,
                          transformOriginX = 0.5, transformOriginY = 0.5, clip = true }
    local wide = core.Item { x = -40, y = 15, width = 120, height = 10, mouseEnabled = true }
    turned:addChild(wide)
    local cx, cy = Pointer.toWorld(wide, 60, 5)
    t.eq((Pointer.pick(cx, cy)), wide, "rotated clip: child picked inside the rotated box")
    local ex, ey = Pointer.toWorld(wide, 110, 5)
    t.eq((Pointer.pick(ex, ey)), nil, "rotated clip: child cut off outside the rotated box")

    -- Invisible and alpha 0 items and their subtrees are skipped
    sticking:setAlpha(0)
    t.eq((Pointer.pick(545, 45)), nil, "alpha 0 item is not picked")
    sticking:setAlpha(255)
    clipper:setVisible(false)
    t.eq((Pointer.pick(545, 45)), nil, "child of an invisible item is not picked")
    clipper:setVisible(true)
    clipper:setAlpha(0)
    t.eq((Pointer.pick(545, 45)), nil, "child of an alpha 0 item is not picked")
    clipper:setAlpha(128)
    t.eq((Pointer.pick(545, 45)), sticking, "translucent parent still picks")
    sticking:setMouseEnabled(false)
    t.eq((Pointer.pick(545, 45)), nil, "an item that is not mouse enabled is passed through")
    sticking:setMouseEnabled(true)

    -- Sibling order: the last child is on top, moveToTop brings one there
    local stack = root { x = 800, y = 0, width = 100, height = 100 }
    local below = core.Item { width = 20, height = 20, mouseEnabled = true }
    local above = core.Item { width = 20, height = 20, mouseEnabled = true }
    stack:addChild(below)
    stack:addChild(above)
    t.eq((Pointer.pick(810, 10)), above, "the last child is on top")
    below:moveToTop()
    t.eq((Pointer.pick(810, 10)), below, "moveToTop puts a child on top")

    -- Root order: later roots are on top, moveToTop re-appends a root
    local r1 = root { x = 950, y = 0, width = 20, height = 20, mouseEnabled = true }
    local r2 = root { x = 950, y = 0, width = 20, height = 20, mouseEnabled = true }
    t.eq((Pointer.pick(960, 10)), r2, "the later root is on top")
    r1:moveToTop()
    t.eq((Pointer.pick(960, 10)), r1, "moveToTop re-appends a root")
    local roots = Pointer.roots()
    t.eq(roots[#roots], r1, "the root list ends with the moved root")

    -- A skinned item: children sit in the skin's content area at (25, 35),
    -- above the skin's own parts.
    local OffsetSkin = core.Skin:extend { width = 200, height = 150 }
    function OffsetSkin.new(class, self)
        self.layout = core.AnchorLayout {}
        self.children = {
            core.Item { id = "frame", left = 0, top = 0, right = 0, bottom = 0, mouseEnabled = true },
            core.Item { id = "contentArea", left = 25, top = 35, right = 0, bottom = 0 },
        }
        return core.Skin.new(class, self)
    end
    local content = core.Item { x = 10, y = 10, width = 40, height = 40, mouseEnabled = true }
    local panel = core.SkinnableItem { x = 500, y = 500, skinClass = OffsetSkin, mouseEnabled = true, content }
    Sync.addRoot(panel)
    created[#created + 1] = panel
    panel:validateLayoutRecursively()
    hit, lx, ly = Pointer.pick(540, 550)
    t.eq(hit, content, "content child picked in the content area")
    t.ok(near(lx, 5) and near(ly, 5), "content child local position includes the content offset")
    t.eq((Pointer.pick(505, 505)), panel.skin.children.frame, "the skin is above the item's own box")
    sameAsNode(content, "content child")
    content:moveToTop()
    sameAsNode(content, "content child after moveToTop")

    -- Generation counter: a still pointer is re-picked after the update only
    -- when geometry changed.
    local feed = InputFeed.attach()
    local entered, left = 0, 0
    local target = root {
        x = 100, y = 700, width = 40, height = 40, mouseEnabled = true,
        mouseEnter = function() entered = entered + 1 end,
        mouseLeave = function() left = left + 1 end,
    }
    feed.move(110, 710)
    t.eq(entered, 1, "moving onto the item enters it")
    local picks = Pointer.picks()
    Pointer.afterUpdate()
    Pointer.afterUpdate()
    t.eq(Pointer.picks(), picks, "no re-pick after an update without changes")
    local generation = Pointer.generation()
    target:setPos(100, 700)
    target:setSize(40, 40)
    target:setRotation(0)
    target:setScale(1)
    target:setTransformOrigin(0.5, 0.5)
    target:setAlpha(255)
    target:setVisible(true)
    target:setMouseEnabled(true)
    target:setClip(false)
    t.eq(Pointer.generation(), generation, "setters that change nothing keep the generation")
    Pointer.afterUpdate()
    t.eq(Pointer.picks(), picks, "still no re-pick")
    target:setPos(200, 700)
    Pointer.afterUpdate()
    t.eq(Pointer.picks(), picks + 1, "moving the item under the still pointer re-picks once")
    t.eq(left, 1, "the item that moved away is left")
    Pointer.afterUpdate()
    t.eq(Pointer.picks(), picks + 1, "and not again on the next update")
    target:setPos(100, 700)
    Pointer.afterUpdate()
    t.eq(entered, 2, "moving it back under the pointer enters it again")
    feed.detach()

    for i = #created, 1, -1 do
        created[i]:delete()
    end
    Sync.flush()
end
