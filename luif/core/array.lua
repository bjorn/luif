--
-- Makes the Array helper methods usable as method calls when instantiated for example like:
--
--  array = core.Array {}
--  array = core.Array(someArrayData)
--
--  array:contains("foo")
--
-- Or just use:
--
--  array = {}
--  Array.contains(array, "foo")
--

local core = require "luif.core"

local Class = core.Class

local Array = Class:extend {
    -- Include the functions from the 'table' library for convenience
    concat = table.concat,
    insert = table.insert,
    remove = table.remove,
    maxn = table.maxn,
}

function Array:clear()
    for i=1,#self do
        self[i] = nil
    end
end

function Array:contains(value)
    for i=1,#self do
        if self[i] == value then
            return true
        end
    end
    return false
end

function Array:find(value)
    for i=1,#self do
        if self[i] == value then
            return i
        end
    end
    return false
end

function Array:findLast(value)
    for i=#self,1,-1 do
        if self[i] == value then
            return i
        end
    end
    return false
end

function Array:all(condition)
    return not Array.findIf(self, function(value) return not condition(value) end)
end

function Array:any(condition)
    return Array.findIf(self, condition) and true
end

function Array:findIf(condition)
    for i=1,#self do
        local value = self[i]
        if condition(value) then
            return i, value
        end
    end
    return false
end

function Array:findLastIf(condition)
    for i=#self,1,-1 do
        local value = self[i]
        if condition(value) then
            return i, value
        end
    end
    return false
end

--
-- Returns a table containing all array elements which satisfy the condition
--
function Array:where(condition)
    local result = {}
    local count = 0
    for i=1,#self do
        local value = self[i]
        if condition(value) then
            count = count + 1
            result[count] = value
        end
    end
    return Array.new(result)
end

function Array:equals(array)
    local size = #self
    if size ~= #array then
        return false
    end
    for i=1,size do
        if self[i] ~= array[i] then
            return false
        end
    end
    return true
end

function Array:prepend(value)
    table.insert(self, 1, value)
end

function Array:append(value)
    self[#self + 1] = value
end

function Array:appendUnique(value)
    local size = #self
    for i=1,size do
        if self[i] == value then
            return
        end
    end
    self[size + 1] = value
end

function Array:join(array)
    local size = #self
    for i=1,#array do
        self[size + i] = array[i]
    end
    return self
end

function Array:first()
    return self[1]
end

function Array:removeFirst()
    table.remove(self, 1)
end

function Array:takeFirst()
    return table.remove(self, 1)
end

function Array:last()
    return self[#self]
end

function Array:removeLast()
    self[#self] = nil
end

function Array:takeLast()
    return table.remove(self)
end

function Array:removeOne(value)
    for i=1,#self do
        if self[i] == value then
            table.remove(self, i)
            return true
        end
    end
    return false
end

-- This is mainly for use with metatables, does not preserve order
function Array:swapRemove(index)
    local count = #self
    if index ~= count then
        self[index] = self[count]
    end
    self[count] = nil
end

function Array:groupBy(selector)
    if type(selector) ~= "function" then
        local property = selector
        selector = function(x) return x[property] end
    end
    local result = {}
    for i=1,#self do
        local value = self[i]
        local group = selector(value)
        assert(group ~= nil, "invalid group")
        if not result[group] then
            result[group] = {}
        end
        Array.append(result[group], value)
    end
    return result
end

function Array:removeAll(value)
    for i=#self,1,-1 do
        if self[i] == value then
            table.remove(self, i)
        end
    end
end

function Array:map(func)
    local mapped = {}
    for i=1,#self do
        mapped[i] = func(self[i])
    end
    return Array.new(mapped)
end

function Array:reduce(seed, func)
    for i=1,#self do
        seed = func(seed, self[i])
    end
    return seed
end

-- Overridden because it's often useful to return the table as well
function Array:sort(comp)
    table.sort(self, comp)
    return self
end

function Array:shuffle()
    -- Swap each element with a random other element
    local len = #self
    for i=1,len do
        local j = math.random(len)
        self[i], self[j] = self[j], self[i]
    end
    return self
end

function Array:reverse()
    local len = #self
    for i=1,len/2 do
        local j = len - i + 1
        self[i], self[j] = self[j], self[i]
    end
    return self
end

function Array:filter(func)
    local len = #self

    -- assign nil to elements to be removed
    for i=1,len do
        if not func(self[i]) then
            self[i] = nil
        end
    end

    -- compact the result
    local j = 0
    for i=1,len do
        if self[i] ~= nil then
            j = j + 1
            self[j] = self[i]
        end
    end
    for i=j+1,len do
        self[i] = nil
    end

    return self
end

function Array:countIf(func)
    local count = 0
    for i=1,#self do
        if func(self[i]) then
            count = count + 1
        end
    end
    return count
end

function Array:apply(func)
    for i=1,#self do
        self[i] = func(self[i])
    end
    return self
end

function Array:foreach(func)
    for i=1,#self do
        func(self[i])
    end
end

function Array:toSet()
    local set = {}
    for i=1,#self do
        set[self[i]] = true
    end
    return set
end

function Array:setLength(length, filler)
    filler = filler or false
    local oldLength = #self

    for i=oldLength+1,length do
        self[i] = filler
    end
    for i=length+1,oldLength do
        self[i] = nil
    end

    return self
end

function Array:truncate(length)
    for i=length+1,#self do
        self[i] = nil
    end
    return self
end

function Array:clone()
    local clone = {}
    for i=1,#self do
        clone[i] = self[i]
    end
    return Array.new(clone)
end

function Array:toString()
    local tmp = {}
    for i=1,#self do
        tmp[i] = tostring(self[i])
    end
    return "[ " .. table.concat(tmp, ", ") .. " ]"
end

return Array
