--
-- A layout that places child items in a grid.
--

local core = require "luif.core"

-- Lua 5.1 and LuaJIT have unpack, later versions table.unpack
local unpack = unpack or table.unpack

local min, ceil, floor = math.min, math.ceil, math.floor

-- The target's content children as a list starting at 1
local function contentList(target)
    local children, first = target:contentChildren()
    if first == 1 then
        return children
    end
    return { unpack(children, first) }
end

local GridLayout = core.Layout:extend {
    columns = false,
    rows = false,

    -- An optional space between each item, in pixels
    gap = 0,

    -- Optional fixed dimensions of the items (required for virtual layout)
    itemWidth = false,
    itemHeight = false,

    -- Horizontal alignment ("left", "right", or "center")
    -- Only valid in non-virtual implementation!
    horizontalAlign = "left",

    _virtualChildrenCount = false,
    _childrenOffset = 0,
}

function GridLayout.new(class, self)
    self = core.Layout.new(class, self)

    if not self.columns and not self.rows then
        self.columns = 4
    end
    if self.columns and self.rows then
        self.rows = false
    end

    return self
end

function GridLayout:setHorizontalAlign(align)
    assert( type(align) == "string" )
    self.horizontalAlign = align
    self:update()
end

-- fill row first, then move to next
function GridLayout:fillByRow(columns, rows, columnWidths, rowHeights)
    local children = contentList(self.target)
    if self._virtualChildrenCount then
        for i = 1, #children do
            local child = children[i]
            local virtualIndex = i + self._childrenOffset
            local x = (virtualIndex-1) % columns * self.itemWidth
            local y = floor((virtualIndex-1) / columns) * self.itemHeight
            child:setPos(x, y)
        end
    else
        local hlOffsetX = 0

        -- change offset if alignment is right or center
        if self.horizontalAlign ~= "left" then
            local columnWidth = self.itemWidth
            if not columnWidth then
                columnWidth = columnWidths[1] + self.gap
            end
            local childrenLastRow = #children % columns
            if childrenLastRow ~= 0 then
                hlOffsetX = (columns - childrenLastRow) * columnWidth
                if self.horizontalAlign == "center" then
                    hlOffsetX = floor(hlOffsetX / 2.0)
                end
            end
        end

        local currentX, currentY = 0, 0
        for row=1,rows do
            currentX = row == rows and hlOffsetX or 0
            for column=1,columns do
                local i = column + (row - 1) * columns
                if i <= #children then
                    children[i]:setPos(currentX, currentY)
                    currentX = currentX + (self.itemWidth or columnWidths[column]) + self.gap
                end
            end
            currentY = currentY + (self.itemHeight or rowHeights[row]) + self.gap
        end
    end
end

-- fill column first, then move to next
function GridLayout:fillByColumn(columns, rows, columnWidths, rowHeights)
    local children = contentList(self.target)
    local currentX, currentY = 0, 0
    for column=1,columns do
        currentY = 0
        for row=1,rows do
            local i = row + (column - 1) * rows
            if i <= #children then
                children[i]:setPos(currentX, currentY)
                currentY = currentY + (self.itemHeight or rowHeights[row]) + self.gap
            end
        end
        currentX = currentX + (self.itemWidth or columnWidths[column]) + self.gap
    end
end

function GridLayout:update()
    self.updating = true

    local children = contentList(self.target)
    local childCount = self._virtualChildrenCount or #children
    local columns = self.columns or ceil(childCount / self.rows)
    local rows = self.rows or ceil(childCount / self.columns)

    local rowHeights, columnWidths

    local minWidth = 0
    local minHeight = 0

    -- Determine the height of each row
    if not self.itemHeight then
        rowHeights = {}
        for row=1,rows do
            local rowHeight = 0
            for i = 1 + (row - 1) * columns, min(row * columns, childCount) do
                local width, height = children[i]:size()
                rowHeight = rowHeight < height and height or rowHeight
            end

            rowHeights[row] = rowHeight
            if rowHeight > 0 then
                minHeight = minHeight + rowHeight + self.gap
            end
        end
    else
        minHeight = (self.itemHeight + self.gap) * min(rows, childCount)
    end

    -- Determine the width of each column
    if not self.itemWidth then
        columnWidths = {}
        for column=1,columns do
            local columnWidth = 0
            for i = column, min(column + (rows - 1) * columns, childCount), columns do
                local width, height = children[i]:size()
                columnWidth = columnWidth < width and width or columnWidth
            end

            columnWidths[column] = columnWidth
            if columnWidth > 0 then
                minWidth = minWidth + columnWidth + self.gap
            end
        end
    else
        minWidth = (self.itemWidth + self.gap) * min(columns, childCount)
    end

    -- Position the children
    if self.columns then
        self:fillByRow(columns, rows, columnWidths, rowHeights)
    else
        self:fillByColumn(columns, rows, columnWidths, rowHeights)
    end

    minWidth = minWidth > 0 and (minWidth - self.gap) or 0
    minHeight = minHeight > 0 and (minHeight - self.gap) or 0
    self.target:setFixedSize(minWidth, minHeight)
    self.updating = false
end

--
-- GridLayout is virtual when the size of its items is predefined.
-- Also, currently it is only supported when using a fixed number of columns.
--
function GridLayout:isVirtual()
    return self.itemWidth and self.itemHeight and self.columns
end

--
-- See Layout.childrenVisibleInArea
--
function GridLayout:childrenVisibleInArea(x, y, width, height)
    local itemWidth, itemHeight, columns = self.itemWidth, self.itemHeight, self.columns

    local gridStartX = floor(x / itemWidth) + 1
    local gridEndX = min(ceil((x + width) / itemWidth), columns)
    local gridStartY = floor(y / itemHeight) + 1
    local gridEndY = ceil((y + height) / itemHeight)

    local first = gridStartX + (gridStartY-1) * columns
    local last = gridEndX + (gridEndY-1) * columns

    return first, last
end

--
-- See Layout.setVirtualChildren
--
function GridLayout:setVirtualChildren(count, first, last)
    if self._virtualChildrenCount == count and self._childrenOffset == first - 1 then
        return
    end

    self._virtualChildrenCount = count
    self._childrenOffset = first - 1

    if self.updating then
        -- Visible virtual children changed as a result of this layout updating.
        -- This kind of thing is normally ignored to protect against infinite
        -- loops, and we need to be careful not to have that happen here.
        -- It should be enough just to reposition the children, which is unlikely
        -- to result in recursion.
        local rows = ceil(count / self.columns)
        self:fillByRow(self.columns, rows)
    else
        self:invalidate()
    end
end

return GridLayout
