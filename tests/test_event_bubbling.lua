--
-- Mouse events that bubble to a parent carry coordinates in the parent's
-- space, also through a rotated and scaled child and through a skin's
-- offset content area.
--
return function(t)
    local module = require "luif.module"
    local core = module "luif.core"
    local Update = core.Update
    local Screen = core.Screen
    local Pointer = require "luif.core.pointer"
    local InputFeed = require "tests.inputfeed"
    local HostWorld = require "tests.hostworld"
    local Sync = require "luif.core.sync"

    local now = (Update.systemTime() or 0) + 250000
    local function step(frames)
        for _ = 1, frames or 1 do
            now = now + 16
            Update.onUpdate(now, 16)
            Pointer.afterUpdate()
        end
    end

    local adapt, savedScale = Screen.adaptive, Screen.scale
    Screen:setScale(1)
    local feed = InputFeed.attach()
    local click = feed.click

    local ignore = function(_, event) event:ignore() end

    -- A rotated and scaled child ignores the press; its parent records it
    local received = {}
    local child = core.Item {
        x = 40, y = 30, width = 60, height = 20, mouseEnabled = true,
        rotation = 90, scale = 2, transformOriginX = 0.5, transformOriginY = 0.5,
        mousePress = ignore,
    }
    local parent = core.Item {
        x = 100, y = 50, width = 300, height = 300, mouseEnabled = true,
        mousePress = function(_, event) received.x, received.y = event:x(), event:y() end,
        child,
    }
    Sync.addRoot(parent)
    step()

    local px, py = Pointer.toWorld(child, 45, 12)
    local nx, ny = HostWorld.toWorld(Sync.host(child), Sync.node(child), 45, 12)
    -- A host may keep node properties in single precision
    t.ok(math.abs(px - nx) < 1e-3 and math.abs(py - ny) < 1e-3,
         "the core transform of the child matches its node")
    t.eq((Pointer.pick(px, py)), child, "the point picks the transformed child")
    click(px, py)
    t.ok(received.x ~= nil, "the press bubbled to the parent")
    if received.x then
        t.near(received.x, px - 100, 1e-6, "bubbled x is in the parent's space")
        t.near(received.y, py - 50, 1e-6, "bubbled y is in the parent's space")
    end

    -- A child in a skin's content area that starts at (25, 35)
    local OffsetSkin = core.Skin:extend { width = 200, height = 150 }
    function OffsetSkin.new(class, self)
        self.layout = core.AnchorLayout {}
        self.children = {
            core.Item { id = "contentArea", left = 25, top = 35, right = 0, bottom = 0 },
        }
        return core.Skin.new(class, self)
    end

    local skinned = {}
    local panel = core.SkinnableItem {
        x = 500, y = 100, skinClass = OffsetSkin, mouseEnabled = true,
        mousePress = function(_, event) skinned.x, skinned.y = event:x(), event:y() end,
        core.Item { x = 10, y = 10, width = 40, height = 40, mouseEnabled = true,
                      mousePress = ignore },
    }
    Sync.addRoot(panel)
    step(2)

    click(540, 150)
    t.ok(skinned.x ~= nil, "the press bubbled to the skinned item")
    if skinned.x then
        t.near(skinned.x, 40, 1e-6, "bubbled x includes the content area offset")
        t.near(skinned.y, 50, 1e-6, "bubbled y includes the content area offset")
    end

    parent:delete()
    panel:delete()
    feed.detach()
    if adapt then Screen:setAdaptive(true) else Screen:setScale(savedScale) end
end
