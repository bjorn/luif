--
-- The ScaleH3 item: a left end, a stretching middle and a right end, cut
-- from one image by a left and a right inset and drawn as one node with
-- slices content (no top or bottom inset).
--
--   core.ScaleH3 { source = "bar" }      -- left and right from TexDb.setSlices("bar", ...)
--   core.ScaleH3 { texture = tex, insets = { left = 6, right = 6 } }
--

local core = require "luif.core"

local Item = core.Item
local TexDb = core.TexDb
local Sync = core.Sync

local Host = core.Host

local ScaleH3 = Item:extend {
    source = false,     -- Expects a TexDb name with slices registered
    texture = false,
    insets = false,     -- { left, right } in texture pixels
    color = 0xFFFFFFFF,
    visible = true,
    alpha = 255,
    grayScale = false,
}

-- The texture and insets of a TexDb name
local function fromSource(source)
    local insets = TexDb.insets(source)
    assert(insets, "No slices registered for '" .. tostring(source) ..
                   "', call TexDb.setSlices(name, left, top, right, bottom)")
    return TexDb[source], insets
end

function ScaleH3.new(class, self)
    self = Item.new(class, self)

    if self.source then
        self.texture, self.insets = fromSource(self.source)
    end

    assert(self.texture and self.insets, "ScaleH3 requires a source, or a texture and insets")
    self.implicitWidth, self.implicitHeight = Host.textureSize(self.texture)

    return self
end

function ScaleH3:pushContent(host, node)
    local insets = self.insets
    host.setSlices(node, self.texture, insets.left or 0, 0, insets.right or 0, 0,
                   self.color or 0xFFFFFFFF, self.grayScale and true or false)
end

function ScaleH3:setSource(source)
    if self.source == source then
        return
    end

    self.source = source
    self:setTexture(fromSource(source))
end

-- Sets the texture with its insets
function ScaleH3:setTexture(texture, insets)
    assert(texture and insets, "ScaleH3:setTexture requires a texture and insets")
    self.texture, self.insets = texture, insets

    -- This may invalidate the parent layout
    self.implicitWidth, self.implicitHeight = Host.textureSize(texture)
    self:invalidateParentLayout()

    Sync.propertiesChanged(self)
    Sync.contentChanged(self)
end

function ScaleH3:setGrayScale(grayScale)
    if self.grayScale == grayScale then
        return
    end

    self.grayScale = grayScale
    Sync.contentChanged(self)
end

function ScaleH3:setColor(color)
    if self.color == color then
        return
    end

    self.color = color
    Sync.contentChanged(self)
end

return ScaleH3
