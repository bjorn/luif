--
-- The ScaleV3 item: a top end, a stretching middle and a bottom end, cut
-- from one image by a top and a bottom inset and drawn as one node with
-- slices content (no left or right inset).
--
--   core.ScaleV3 { source = "column" }   -- top and bottom from TexDb.setSlices("column", ...)
--   core.ScaleV3 { texture = tex, insets = { top = 6, bottom = 6 } }
--

local core = require "luif.core"

local Item = core.Item
local TexDb = core.TexDb
local Sync = core.Sync

local Host = core.Host

local ScaleV3 = Item:extend {
    source = false,     -- Expects a TexDb name with slices registered
    texture = false,
    insets = false,     -- { top, bottom } in texture pixels
    color = 0xFFFFFFFF,
    visible = true,
    alpha = 255,
}

-- The texture and insets of a TexDb name
local function fromSource(source)
    local insets = TexDb.insets(source)
    assert(insets, "No slices registered for '" .. tostring(source) ..
                   "', call TexDb.setSlices(name, left, top, right, bottom)")
    return TexDb[source], insets
end

function ScaleV3.new(class, self)
    self = Item.new(class, self)

    if self.source then
        self.texture, self.insets = fromSource(self.source)
    end

    assert(self.texture and self.insets, "ScaleV3 requires a source, or a texture and insets")
    self.implicitWidth, self.implicitHeight = Host.textureSize(self.texture)

    return self
end

function ScaleV3:pushContent(host, node)
    local insets = self.insets
    host.setSlices(node, self.texture, 0, insets.top or 0, 0, insets.bottom or 0,
                   self.color or 0xFFFFFFFF, false)
end

function ScaleV3:setSource(source)
    if self.source == source then
        return
    end

    self.source = source
    self:setTexture(fromSource(source))
end

-- Sets the texture with its insets
function ScaleV3:setTexture(texture, insets)
    assert(texture and insets, "ScaleV3:setTexture requires a texture and insets")
    self.texture, self.insets = texture, insets

    -- This may invalidate the parent layout
    self.implicitWidth, self.implicitHeight = Host.textureSize(texture)
    self:invalidateParentLayout()

    Sync.propertiesChanged(self)
    Sync.contentChanged(self)
end

function ScaleV3:setColor(color)
    if self.color == color then
        return
    end

    self.color = color
    Sync.contentChanged(self)
end

return ScaleV3
