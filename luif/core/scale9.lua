--
-- The Scale9 item: one image cut into a nine-slice by insets, drawn as one
-- node with slices content. Corners keep their size, edges and the centre
-- stretch.
--
--   core.Scale9 { source = "frame" }     -- insets from TexDb.setSlices("frame", ...)
--   core.Scale9 { texture = tex, insets = { left = 4, top = 4, right = 4, bottom = 4 } }
--

local core = require "luif.core"

local Item = core.Item
local TexDb = core.TexDb
local Sync = core.Sync

local Host = core.Host

local Scale9 = Item:extend {
    source = false,     -- Expects a TexDb name with slices registered
    texture = false,
    insets = false,     -- { left, top, right, bottom } in texture pixels
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

-- Implicit size is the texture size; the minimum size holds the corners
local function measure(self)
    local width, height = Host.textureSize(self.texture)
    local insets = self.insets
    local changed = self.implicitWidth ~= width or self.implicitHeight ~= height
    self.implicitWidth, self.implicitHeight = width, height
    self.minimumWidth = insets.left + insets.right
    self.minimumHeight = insets.top + insets.bottom
    return changed
end

function Scale9.new(class, self)
    self = Item.new(class, self)

    if self.source then
        self.texture, self.insets = fromSource(self.source)
    end

    assert(self.texture and self.insets, "Scale9 requires a source, or a texture and insets")
    measure(self)

    return self
end

function Scale9:pushContent(host, node)
    local insets = self.insets
    host.setSlices(node, self.texture, insets.left, insets.top, insets.right, insets.bottom,
                   self.color or 0xFFFFFFFF, self.grayScale and true or false)
end

function Scale9:setSource(source)
    if self.source == source then
        return
    end

    self.source = source
    self:setTexture(fromSource(source))
end

-- Sets the texture with its insets
function Scale9:setTexture(texture, insets)
    assert(texture and insets, "Scale9:setTexture requires a texture and insets")
    self.texture, self.insets = texture, insets

    if measure(self) then
        self:invalidateParentLayout()
    end

    Sync.propertiesChanged(self)
    Sync.contentChanged(self)
end

function Scale9:setColor(color)
    if self.color == color then
        return
    end

    self.color = color
    Sync.contentChanged(self)
end

function Scale9:setGrayScale(grayScale)
    if self.grayScale == grayScale then
        return
    end

    self.grayScale = grayScale
    Sync.contentChanged(self)
end

return Scale9
