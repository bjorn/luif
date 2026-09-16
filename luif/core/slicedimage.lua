--
-- Sliced image: a grid of separate textures (for example a large picture
-- cut into pieces), `columns` wide. The grid is not a nine-slice, so every
-- texture is a child image, stretched with the grid when the item has an
-- explicit width or height. The item's own node has no content.
--

local core = require "luif.core"

local Item = core.Item
local Image = core.Image

local Host = core.Host

local SlicedImage = Item:extend {
    textures = false, -- Expects an array of textures
    color = 0xFFFFFFFF,
    visible = true,
    alpha = 255,

    columns = false,

    _images = false,    -- The child image of each texture
}

local function measure(self)
    local rows = #self.textures/self.columns

    local implicitWidth = 0
    for i=1,self.columns do
        local w, h = Host.textureSize(self.textures[i])
        implicitWidth = implicitWidth + w
    end

    local implicitHeight = 0
    for i=1,rows do
        local w, h = Host.textureSize(self.textures[1+(self.columns*(i-1))])
        implicitHeight = implicitHeight + h
    end

    return implicitWidth, implicitHeight
end

-- One child image per texture, placed on the grid stretched to the size.
local function updateGrid(self)
    local textures = self.textures or {}
    local images = self._images
    for i = #images, #textures + 1, -1 do
        self:removeChild(images[i])
        images[i]:delete()
        images[i] = nil
    end
    if #textures == 0 then
        return
    end

    local sliceWidth, sliceHeight = Host.textureSize(textures[1])
    local width, height = self:size()
    local scaleX = self.implicitWidth > 0 and width / self.implicitWidth or 1
    local scaleY = self.implicitHeight > 0 and height / self.implicitHeight or 1
    local tint = self.color or 0xFFFFFFFF

    for i=1,#textures do
        local image = images[i]
        if image then
            image:setTexture(textures[i])
        else
            image = Image { texture = textures[i] }
            images[i] = image
            self:addChild(image)
        end
        local textureWidth, textureHeight = Host.textureSize(textures[i])
        local column = (i-1) % self.columns
        local row = math.floor((i-1) / self.columns)
        image:setPos(column * sliceWidth * scaleX, row * sliceHeight * scaleY)
        image:setSize(textureWidth * scaleX, textureHeight * scaleY)
        image:setColor(tint)
    end
end

function SlicedImage.new(class, self)
    self = Item.new(class, self)
    self._images = {}
    if self.textures then
        local columns = self.columns
        local textureCount = #self.textures
        assert(columns)
        assert(textureCount % columns == 0, "Incorrect amount of textures for SlicedImage.")

        self.implicitWidth, self.implicitHeight = measure(self)
        updateGrid(self)
    end

    return self
end

function SlicedImage:attached()
    assert(self.textures and #self.textures % self.columns == 0, "Incorrect amount of textures for SlicedImage.")
    updateGrid(self)
end

function SlicedImage:setSize(width, height)
    Item.setSize(self, width, height)
    updateGrid(self)
end

function SlicedImage:setTextures(textures)
    assert(textures and #textures % self.columns == 0, "Incorrect amount of textures for SlicedImage.")
    self.textures = textures

    local implicitWidth, implicitHeight = measure(self)
    if self.implicitWidth ~= implicitWidth or self.implicitHeight ~= implicitHeight then
        self.implicitWidth = implicitWidth
        self.implicitHeight = implicitHeight
        self:invalidateParentLayout()
    end

    updateGrid(self)
end

function SlicedImage:setColor(color)
    if self.color == color then
        return
    end

    self.color = color
    local images = self._images
    for i=1,#images do
        images[i]:setColor(color)
    end
end

return SlicedImage
