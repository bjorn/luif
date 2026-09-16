--
-- A skinnable item: the base of most controls.
--
-- The skin is the item's first child. When the skin has an item with id
-- "contentArea" (self.contentArea), that item is a real container: the
-- item's content children are its children, so each child's parent is the
-- item that positions it. Without a content area the content children are
-- the item's children after the skin.
--
-- addChild, insertChild, removeChild, removeChildren, setChildren and
-- setParent onto the item work on the content: they go to the content area
-- when there is one. Indexes count content children only. item.children is
-- the real list (the skin first); contentChildren() returns the content as
-- the list and the index of its first entry, and is what id lookups
-- (findChild, findChildren), state changes and the item's layout use. The
-- content area's own children (added by the skin) count as content.
--
-- Skin parts are resolved by id inside the skin when the item is built,
-- before any content moves in. States set on the item are applied to its
-- content by its own transition and forwarded once to the skin, whose walk
-- stops at the content area.
--

local core = require "luif.core"

local Item          = core.Item
local Object        = core.Object
local LayoutManager = core.LayoutManager

local SkinnableItem = Item:extend {
    skinParts = {},
    skin = false,
    skinClass = false,

    contentArea = false,
}

function SkinnableItem.new(class, self)
    -- Create the skin when only its class was specified
    if not self.skin then
        local skinClass = self.skinClass or class.skinClass
        if skinClass then
            self.skin = skinClass {}
        end
    end

    -- Make sure the size is specified before calling the Item constructor,
    -- and that the skin size matches our size.
    self.width = self.width or class.width or (self.skin and self.skin.width or false)
    self.height = self.height or class.height or (self.skin and self.skin.height or false)

    self = Item.new(class, self)

    local skin = self.skin
    if not skin then
        return self
    end

    -- Resolve skin parts
    local parts = {}
    for i, name in ipairs(self.skinParts) do
        parts[name] = false
        self[name] = false
    end
    skin:findChildren(parts, self)

    local area = skin:findChild("contentArea")
    self.contentArea = area
    skin:setSize(self.width, self.height)

    -- The skin becomes the first child and the content moves into the
    -- content area
    local content = self.children
    self.children = {}
    Object.insertChild(self, 1, skin)

    if area then
        area._contentOwner = self

        -- Relayout whenever the content item is resized
        area:on("resize", function(width, height)
            if self.layout then
                self.layout:invalidate()
            end
        end)
    end

    for i = 1, #content do
        local child = content[i]
        child.parent = false
        if area then
            area:insertChild(#area.children + 1, child)
        else
            Object.insertChild(self, #self.children + 1, child)
        end
    end

    return self
end

-- The content: the content area's children, or the children after the skin.
function SkinnableItem:contentChildren()
    local area = self.contentArea
    if area then
        return area.children, 1
    end
    local children = self.children
    local skin = self.skin
    if skin and children[1] == skin then
        return children, 2
    end
    return children, 1
end

-- Children set with setParent go into the content area when there is one.
function SkinnableItem:contentParent()
    return self.contentArea or self
end

function SkinnableItem:insertChild(index, child)
    local area = self.contentArea
    if area then
        return area:insertChild(index, child)
    end
    local skin = self.skin
    if skin and child ~= skin and self.children[1] == skin then
        index = index + 1
    end
    return Item.insertChild(self, index, child)
end

function SkinnableItem:addChild(child)
    local children, first = self:contentChildren()
    return self:insertChild(#children - first + 2, child)
end

function SkinnableItem:removeChild(child)
    local area = self.contentArea
    if area and child.parent == area then
        return area:removeChild(child)
    end
    if child == self.skin then
        -- Only happens while deleting: the skin takes the content area along
        self.contentArea = false
        self.skin = false
    end
    return Item.removeChild(self, child)
end

function SkinnableItem:removeChildren()
    local area = self.contentArea
    if area then
        return area:removeChildren()
    end
    local children, first = self:contentChildren()
    for i = #children, first, -1 do
        Item.removeChild(self, children[i])
    end
end

function SkinnableItem:setChildren(children)
    self:removeChildren()
    for i = 1, #children do
        self:addChild(children[i])
    end
end

function SkinnableItem:contentRect()
    if self.contentArea then
        -- Make sure the layout of the skin has been updated
        if self.skin and self.skin.layout then
            LayoutManager:validateLayout(self.skin.layout)
        end

        local absX, absY = self:absolutePos()
        local contentAbsX, contentAbsY = self.contentArea:absolutePos()
        local width, height = self.contentArea:size()
        return contentAbsX - absX, contentAbsY - absY, width, height
    end
    return Item.contentRect(self)
end

function SkinnableItem:setSize(width, height)
    Item.setSize(self, width, height)

    if self.skin then
        self.skin:setSize(width, height)
    end
end

-- Override to apply the state also to the skin
function SkinnableItem:setState(state, animate)
    if self.state == state then
        return
    end

    Item.setState(self, state, animate)

    if self.skin then
        self.skin:setState(state, animate)
    end
end

-- Attempts to set the size of the content area by setting the size of the
-- skinnable item while taking into account the margins of the content area.
function SkinnableItem:setContentSize(width, height)
    local contentArea = self.contentArea
    if contentArea then
        width = width + (contentArea.left or 0) + (contentArea.right or 0)
        height = height + (contentArea.top or 0) + (contentArea.bottom or 0)
    end
    self:setSize(math.max(self.minimumWidth, width),
                 math.max(self.minimumHeight, height))
end

function SkinnableItem:setContentWidth(width)
    local contentArea = self.contentArea
    if contentArea then
        width = width + (contentArea.left or 0) + (contentArea.right or 0)
    end
    self:setWidth(math.max(self.minimumWidth, width))
end

-- Attempts to set the height of the content area by setting the height of the
-- skinnable item while taking into account the margins of the content area.
function SkinnableItem:setContentHeight(height)
    local contentArea = self.contentArea
    if contentArea then
        height = height + (contentArea.top or 0) + (contentArea.bottom or 0)
    end
    self:setHeight(math.max(self.minimumHeight, height))
end

return SkinnableItem
