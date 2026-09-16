--
-- The image: one node with image content, stretched over the item's
-- size. Flips and grayscale are content flags.
--

local core = require "luif.core"

local Item = core.Item

local TexDb = core.TexDb
local Color = core.Color
local Sync = core.Sync

local Host = core.Host

local Image = Item:extend {
    source = false,     -- Expects a base name for looking up in TexDb
    texture = TexDb.empty,
    color = 0xFFFFFFFF,
    visible = true,
    alpha = 255,
    flipX = false,
    flipY = false,
    grayScale = false,
}

function Image.new(class, self)
    self = Item.new(class, self)

    if self.source then
        self.texture = TexDb[self.source]
    end

    assert(self.texture, "Image requires a texture!")

    local color = self.color or class.color
    if type(color) == "string" then
        self:setColor(color)
    end

    self.implicitWidth, self.implicitHeight = Host.textureSize(self.texture)

    return self
end

function Image:pushContent(host, node)
    host.setImage(node, self.texture, self.color or 0xFFFFFFFF, self.flipX and true or false,
                  self.flipY and true or false, self.grayScale and true or false)
end

function Image:setSource(source)
    if self.source == source then
        return
    end

    self.source = source
    self:setTexture(TexDb[source])
end

function Image:setTexture(texture)
    if self.texture == texture then
        return
    end

    self.texture = texture

    -- This may invalidate the parent layout
    self.implicitWidth, self.implicitHeight = Host.textureSize(self.texture)
    self:invalidateParentLayout()

    Sync.propertiesChanged(self)
    Sync.contentChanged(self)
end

function Image:setGrayScale(grayScale)
    if self.grayScale == grayScale then
        return
    end

    self.grayScale = grayScale
    Sync.contentChanged(self)
end

function Image:setColor(color)
    if type(color) == "string" then
        color = Color[color]
        assert(type(color) == "number", "unknown color name")
    end
    if self.color == color then
        return
    end

    self.color = color
    Sync.contentChanged(self)
end

function Image:setFlip(flipX, flipY)
    if self.flipX == flipX and self.flipY == flipY then
        return
    end

    self.flipX = flipX
    self.flipY = flipY
    Sync.contentChanged(self)
end

function Image:setFlipX(flipX)
    self:setFlip(flipX, self.flipY)
end

function Image:setFlipY(flipY)
    self:setFlip(self.flipX, flipY)
end

function Image:toString()
    return Item.toString(self) .. " [" .. (TexDb.nameOf[self.texture] or "unknown") .. "]"
end

return Image
