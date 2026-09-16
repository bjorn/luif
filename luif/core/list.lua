--
-- An item that displays a list of items using a specified delegate. The
-- position of the instantiated delegates is determined by the layout as
-- usual.
--
-- When created, delegates will have an 'index' member which is the index of
-- the data associated with the delegate. Additional automatic properties can
-- be specified using the "property" and/or "properties" attributes.
--
-- When "properties" is true (the default) and the data is a table, all
-- properties of the table are copied into the delegate.
--

local core = require "luif.core"

local Array = core.Array
local Item = core.Item
local VerticalLayout = core.VerticalLayout

local List = Item:extend {
    -- A delegate component will be instantiated for each entry in 'data'
    delegate = false,
    data = false,

    -- When set, each delegate will have the property name given here set to
    -- the value at its index in the list data.
    property = false,

    -- When set to a table, each key/value pair maps one property from a table
    -- entry in 'data' to a property of the delegate. When set to true, all
    -- properties of table entries in 'data' will be copied to the delegate.
    properties = true,

    -- Sets whether this list is allowed to operate in 'virtual' mode. Several
    -- functionalities should be avoided in this mode and it will only really
    -- work if the layout supports it as well.
    --
    -- In 'virtual' mode the list will try to create only as many delegates as
    -- are actually visible. This is useful when dealing with huge amounts of
    -- data.
    virtual = false,

    _delegates = false,
    _virtual = false,
    _firstVisibleDelegate = 1,
    _lastVisibleDelegate = 0,

    _removingChildren = false,      -- array of children being removed
}

function List.new(class, self)
    -- A list defaults to a vertical layout
    self.layout = self.layout == nil and VerticalLayout {} or self.layout

    self = Item.new(class, self)
    self._delegates = {}

    if self.data then
        assert(self.delegate, "List with data needs delegate")
        self:updateDelegates()
    end

    return self
end

local function keysHaveChanged(from, to)
    for k, v in pairs(from) do
        if to[k] ~= v then
            return true
        end
    end
    return false
end

function List:dataDifferent(new)
    local old = self.data
    if not old and not new then
        return false
    end

    local changed = (not old and new) or (old and not new) or #old ~= #new

    if not changed and #new > 0 then
        -- Do a more thorough check
        if type(new[1]) == "table" then
            for i=1,#new do
                local n, o = new[i], old[i]
                changed = keysHaveChanged(n, o) or keysHaveChanged(o, n)
                if changed then
                    break
                end
            end
        else
            for i=1,#new do
                if old[i] ~= new[i] then
                    changed = true
                    break
                end
            end
        end
    end

    return changed
end

-- use with care. can be expensive if data has a lot of entries that are not displayed in delegates
function List:setDataIfDifferent(data)
    if self:dataDifferent(data) then
        self:setData(data)
        return true
    end
    return false
end

--
-- Replaces the data used by this list and recreates all delegates.
--
-- This is potentially inefficient and recreating the delegates can cause
-- state to get lost. In this case, consider using List:updateData or
-- implementing a custom way to update the delegates.
--
function List:setData(data)
    if not self.data and not data then
        return
    end

    self.data = data

    -- Delete all delegates because they are based on old data.
    -- (can't use 'ipairs' because we may be virtual)
    for index, delegate in pairs(self._delegates) do
        self._delegates[index] = nil
        self:deleteChild(delegate)
    end

    self:updateDelegates()

    if self._virtual then
        self.layout:setVirtualChildren(#self.data, self._firstVisibleDelegate, self._lastVisibleDelegate)
    end
end

--
-- Updates any existing delegates with the given data (by calling
-- delegate:updateData(data)), and removes/creates delegates as necessary at
-- the end of the list to match the length of the data.
--
-- WARNING: Does not support virtual mode.
--
function List:updateData(data, appearEffectClass, hideEffectClass)
    assert(not self.virtual)

    self.data = self.data or data and {}

    local oldCount = self.data and #self.data or 0
    local newCount = data and #data or 0
    local updateCount = newCount < oldCount and newCount or oldCount

    for i=1,updateCount do
        local delegate = self._delegates[i]
        delegate.index = i
        self.data[i] = data[i]
        delegate:updateData(data[i])
    end
    for i=updateCount+1,newCount do
        self:appendItem(data[i], appearEffectClass and appearEffectClass {})
    end
    for i=oldCount,updateCount+1,-1 do
        self:removeItem(i, hideEffectClass and hideEffectClass {})
    end
end

--
-- Removes the item at the given index, deleting its delegate.
--
-- Optionally an effect can be passed which is applied to the item being
-- removed. Removal and deletion of the delegate instance is then delayed
-- until the effect has finished.
--
-- WARNING: Does not support virtual mode.
--
function List:removeItem(index, effect)
    assert(not self.virtual)

    local delegate = self._delegates[index]

    if not effect then
        self:deleteChild(delegate)
    else
        self._removingChildren = self._removingChildren or Array {}
        self._removingChildren:append(delegate)
        effect:on("finish", function()
            self:deleteChild(delegate)
            self._removingChildren:removeOne(delegate)
            if #self._removingChildren == 0 then
                self._removingChildren = false
            end
        end)
        delegate:start("list", effect)
    end

    table.remove(self.data, index)
    table.remove(self._delegates, index)

    for i=index,#self._delegates do
        self._delegates[i].index = i
    end

    return delegate
end

--
-- Appends a single item to the data and creates a delegate for it.
--
-- Returns the created delegate.
--
function List:appendItem(item, effect)
    return self:insertItem(self.data and #self.data + 1 or 1, item, effect)
end

--
-- Prepends a single item to the data and creates a delegate for it.
--
-- Returns the created delegate.
--
function List:prependItem(item, effect)
    return self:insertItem(1, item, effect)
end

--
-- Inserts a single item to the data at a specific index and creates a delegate for it.
--
-- Returns the created delegate.
--
function List:insertItem(index, item, effect)
    self.data = self.data or {}
    table.insert(self.data, index, item)

    local delegate

    if self.virtual then
        for i = #self.data - 1, index, -1 do
            self._delegates[i + 1] = self._delegates[i]
        end
        self._delegates[index] = nil
        self:updateDelegates()

        delegate = self._delegates[index]
    else
        delegate = self:createDelegate(item, index)
        table.insert(self._delegates, index, delegate)

        local childIndex = index

        -- Adjust index as necessary to account for delegates pending deletion
        if self._removingChildren then
            local indexes = self._removingChildren:map(function(child)
                return assert(Array.find(self.children, child))
            end):sort()

            for i, removingChildIndex in ipairs(indexes) do
                if removingChildIndex <= childIndex then
                    childIndex = childIndex + 1
                end
            end
        end

        self:insertChild(childIndex, delegate)
    end

    for i=index+1,#self._delegates do
        if self._delegates[i] then
            self._delegates[i].index = i
        end
    end

    if delegate then
        if effect then
            delegate:start("list", effect)
        end
    end

    if self._virtual then
        self.layout:setVirtualChildren(#self.data, self._firstVisibleDelegate, self._lastVisibleDelegate)
    end

    return delegate
end

function List:findItem(item)
    return self.data and Array.find(self.data, item)
end

function List:updateDelegates()
    if not self.data then
        return
    end

    local first, last

    if self._virtual then
        first = self._firstVisibleDelegate
        last = math.min(#self.data, self._lastVisibleDelegate)

        -- Delete any existing but no longer visible delegates
        for index, delegate in pairs(self._delegates) do
            if index < first or index > last then
                self._delegates[index] = nil
                self:deleteChild(delegate)
            end
        end
    else
        first, last = 1, #self.data
    end

    -- Make sure we have a delegate for all visible indexes.
    for i = first, last do
        if not self._delegates[i] then
            local delegate = self:createDelegate(self.data[i], i)
            self._delegates[i] = delegate
            self:insertChild(i - first + 1, delegate)
        end
    end
end

function List:createDelegate(data, index, instance)
    assert(self.delegate, "No delegate set on the list")

    index = index or 0
    local delegateInstance = instance or {}

    delegateInstance.index = index
    if self.property then
        delegateInstance[self.property] = data
    end

    if type(data) == "table" then
        if self.properties == true then
            for k,v in pairs(data) do
                delegateInstance[k] = v
            end
        elseif type(self.properties) == "table" then
            for k,v in pairs(self.properties) do
                delegateInstance[v] = data[k]
            end
        end
    end

    return self.delegate(delegateInstance)
end

function List:delegateForIndex(index)
    return (index < 0 and self.data and self._delegates[#self.data + index + 1]) or self._delegates[index]
end

function List:delegateForItem(item)
    local index = self.data and Array.find(self.data, item)
    return index and self._delegates[index]
end

function List:delegates()
    return self._delegates
end

--
-- See Item.setExposedArea
--
function List:setExposedArea(x, y, width, height)
    -- Only relevant when the layout is virtual
    if not (self.virtual and self.layout and self.layout:isVirtual()) then
        return
    end

    local first, last = self.layout:childrenVisibleInArea(x, y, width, height)
    first = first < 1 and 1 or first

    if self._firstVisibleDelegate == first and self._lastVisibleDelegate == last then
        return
    end

    self._firstVisibleDelegate = first
    self._lastVisibleDelegate = last
    self._virtual = true

    self:updateDelegates()
    self.layout:setVirtualChildren(self.data and #self.data or 0, first, last)
end

return List
