--
-- A helper class for making a line from any point to any point.
--
-- The item is the line's body: its position, size and rotation follow from
-- the points, so it should not be positioned using a layout. It starts at
-- the start point (after the start offset), is rotated towards the end point
-- around the middle of its start edge (its transform origin) and has the
-- line texture as image content. The arrow head and the mirrored arrow tail
-- are two child images, centred on the end and the start of the body.
--

local core = require "luif.core"

local Item = core.Item
local Image = core.Image
local Pointer = core.Pointer
local Sync = core.Sync

local TexDb = core.TexDb

local Host = core.Host

local Line = Item:extend {
    texture = TexDb.line,
    arrowHead = TexDb.arrowhead,
    arrowHeadWidth = false,
    arrowHeadHeight = false,
    arrowTail = TexDb.empty,
    arrowTailWidth = false,
    arrowTailHeight = false,
    color = 0xFFFFFFFF,
    visible = true,
    alpha = 255,

    thickness = 8,
    transformOriginX = 0,
    transformOriginY = 0.5,

    startX = 0,
    startY = 0,
    startOffset = 0,    -- Distance to the start point
    endX = 0,
    endY = 0,
    endOffset = 0,      -- Distance to the end point

    _arrowHeadWidth = false,
    _arrowHeadHeight = false,
    _arrowTailWidth = false,
    _arrowTailHeight = false,

    _head = false,      -- The arrow head image
    _tail = false,      -- The arrow tail image
}

-- The start of the body after the offsets, its length and the angle
local function geometry(self)
    local startX, startY = self.startX, self.startY
    local endX, endY = self.endX, self.endY

    local dx = endX - startX
    local dy = endY - startY
    local length = math.sqrt(dx*dx + dy*dy)
    local angle = math.atan2(dy, dx)

    local totalOffset = self.endOffset + self.startOffset
    if totalOffset ~= 0 then
        startX = startX + dx * (self.startOffset / length)
        startY = startY + dy * (self.startOffset / length)
        length = length - totalOffset
    end

    return startX, startY, length, angle
end

-- Places the arrow head and tail images on the ends of the body.
local function updateEnds(self)
    local length = self.width
    local thickness = self.thickness
    local tint = self.color or 0xFFFFFFFF

    local headWidth = self.arrowHeadWidth or self._arrowHeadWidth
    local headHeight = self.arrowHeadHeight or self._arrowHeadHeight
    local tailWidth = self.arrowTailWidth or self._arrowTailWidth
    local tailHeight = self.arrowTailHeight or self._arrowTailHeight

    local head, tail = self._head, self._tail
    head:setTexture(self.arrowHead)
    head:setPos(length - headWidth / 2, (thickness - headHeight) / 2)
    head:setSize(headWidth, headHeight)
    head:setColor(tint)
    tail:setTexture(self.arrowTail)
    tail:setPos(-tailWidth / 2, (thickness - tailHeight) / 2)
    tail:setSize(tailWidth, tailHeight)
    tail:setColor(tint)
end

-- Position, size and rotation follow the points.
local function updateGeometry(self)
    local startX, startY, length, angle = geometry(self)
    local thickness = self.thickness
    self.x, self.y = startX, startY - thickness / 2
    self.width, self.height = length, thickness
    self.rotation = math.deg(angle)
    if self._root then
        Pointer.changed()
    end
    Sync.propertiesChanged(self)
    updateEnds(self)
end

function Line.new(class, self)
    self = Item.new(class, self)
    self.arrowHead = self.arrowHead or TexDb.empty

    self._arrowHeadWidth, self._arrowHeadHeight = Host.textureSize(self.arrowHead)
    self._arrowTailWidth, self._arrowTailHeight = Host.textureSize(self.arrowTail)

    self._head = Image { texture = self.arrowHead }
    self._tail = Image { texture = self.arrowTail, flipX = true }
    self:addChild(self._head)
    self:addChild(self._tail)
    updateGeometry(self)

    return self
end

function Line:pushContent(host, node)
    host.setImage(node, self.texture, self.color or 0xFFFFFFFF, false, false, false)
end

function Line:setTexture(texture)
    if self.texture == texture then
        return
    end

    self.texture = texture
    Sync.contentChanged(self)
end

function Line:setArrowHead(texture)
    texture = texture or TexDb.empty
    if self.arrowHead == texture then
        return
    end

    self.arrowHead = texture
    self._arrowHeadWidth, self._arrowHeadHeight = Host.textureSize(texture)
    updateEnds(self)
end

function Line:setArrowTail(texture)
    texture = texture or TexDb.empty
    if self.arrowTail == texture then
        return
    end

    self.arrowTail = texture
    self._arrowTailWidth, self._arrowTailHeight = Host.textureSize(texture)
    updateEnds(self)
end

-- One function to set all three line textures at once, which is faster than
-- changing each of them individually when they all change.
function Line:setTextures(texture, arrowHead, arrowTail)
    texture = texture or TexDb.empty
    arrowHead = arrowHead or TexDb.empty
    arrowTail = arrowTail or TexDb.empty

    if self.texture == texture and self.arrowHead == arrowHead and self.arrowTail == arrowTail then
        return
    end

    self:setTexture(texture)
    self.arrowHead = arrowHead
    self.arrowTail = arrowTail

    self._arrowHeadWidth, self._arrowHeadHeight = Host.textureSize(arrowHead)
    self._arrowTailWidth, self._arrowTailHeight = Host.textureSize(arrowTail)

    updateEnds(self)
end

function Line:setColor(color)
    if self.color == color then
        return
    end

    self.color = color
    Sync.contentChanged(self)
    updateEnds(self)
end

function Line:setThickness(thickness)
    if self.thickness == thickness then
        return
    end
    self.thickness = thickness
    updateGeometry(self)
end

function Line:setStart(x, y)
    self.startX, self.startY = x, y
    updateGeometry(self)
end

function Line:setEnd(x, y)
    self.endX, self.endY = x, y
    updateGeometry(self)
end

function Line:setPoints(startX, startY, endX, endY)
    self.startX, self.startY = startX, startY
    self.endX, self.endY = endX, endY
    updateGeometry(self)
end

function Line:setStartOffset(offset)
    if self.startOffset ~= offset then
        self.startOffset = offset
        updateGeometry(self)
    end
end

function Line:setEndOffset(offset)
    if self.endOffset ~= offset then
        self.endOffset = offset
        updateGeometry(self)
    end
end

function Line:length()
    local dx = self.endX - self.startX
    local dy = self.endY - self.startY
    return math.sqrt(dx*dx + dy*dy)
end

function Line:angle()
    local dx = self.endX - self.startX
    local dy = self.endY - self.startY
    return math.deg(math.atan2(dy, dx))
end

function Line:distanceTo(x, y)
    local startX, startY = self.startX, self.startY
    local endX, endY = self.endX, self.endY

    local dx = startX - endX
    local dy = startY - endY
    local length = math.sqrt(dx*dx + dy*dy)

    local toStartX = startX - x
    local toStartY = startY - y

    if length > 0 then
        local dot = (toStartX * dx + toStartY * dy) / length

        -- Calculate distance to start or end point when appropriate
        if dot < 0 then
            return math.sqrt(toStartX * toStartX + toStartY * toStartY)
        elseif dot > length then
            local toEndX = x - endX
            local toEndY = y - endY
            return math.sqrt(toEndX * toEndX + toEndY * toEndY)
        end

        return math.abs(toStartX * dy - toStartY * dx) / length
    end

    -- Fall back on distance to starting point
    return math.sqrt(toStartX * toStartX + toStartY * toStartY)
end

function Line:middle()
    return (self.startX + self.endX) / 2,
           (self.startY + self.endY) / 2
end

return Line
