--
-- A full screen item that is kept on top of everything else. Used for
-- popups (ComboBox) and dragged items (DragManager).
--
-- By default the layer is a root covering the virtual screen; it is resized
-- on uiScaleChanged and, like every root, scaled by core/sync.lua. An
-- application can put the layer into its own tree with
-- TopLayer.setRoot(root), which then also sizes it.
--

local core = require "luif.core"
local Sync = core.Sync

local TopLayer = {}

local layer = false
local root = false

local function fitScreen(_, virtualWidth, virtualHeight)
    if layer then
        layer:setSize(virtualWidth, virtualHeight)
    end
end

local function createLayer()
    local Update = core.Update

    layer = core.Item {
        id = "TopLayer",
        x = 0, y = 0,
        width = Update.virtualScreenWidth,
        height = Update.virtualScreenHeight,
    }

    Update:on("uiScaleChanged", fitScreen)

    if root then
        root:addChild(layer)
    else
        Sync.addRoot(layer)
    end
end

-- Returns the layer, creating it on first use, and moves it to the top
function TopLayer.instance()
    if not layer then
        createLayer()
    end
    layer:moveToTop()
    return layer
end

-- Parents the layer under the given item (or makes it a root when false)
function TopLayer.setRoot(item)
    root = item or false
    if layer then
        layer:setParent(root)
        fitScreen(nil, core.Update.virtualScreenWidth, core.Update.virtualScreenHeight)
        if not root and not layer:isAttached() then
            Sync.addRoot(layer)
        end
    end
end

function TopLayer.root()
    return root
end

return TopLayer
