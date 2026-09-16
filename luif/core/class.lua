--
-- Class is the base class of anything that follows this OOP mechanism.
-- Usage example:
--
--
-- CREATING A DERIVED CLASS
--
--      local Human = Class:extend {
--          name = "Anonymous",
--          weight = 0,
--      }
--
--      function Human:say(text)
--          print(self.name .. " says: " .. text)
--      end
--
--
-- INSTANTIATING AN OBJECT
--
--      local jim = Human {
--          name = "Jim Jimmalot",
--          weight = 85,
--      }
--
--      jim:say("Hi!")
--
--
-- OR SETTING PROPERTIES LATER
--
--      jim = Human {}
--      jim.name = "Jim Jimmalot"
--      jim.weight = 85
--

local core = require "luif.core"

local Debug = core.Debug
local dbg, dbgprint = Debug.dbg, Debug.dbgprint

local enableClassDebugging = false

local Class = {}

--
-- Turns the given table into an instance of this class.
--
function Class:new(instance)
    assert(instance, "No instance table provided")
    assert(rawget(self, "__call"), "Trying to instantiate an instance")
    return setmetatable(instance, self)
end

local function callConstructor(class, ...)
    return class:new(...)
end

Class.__index = Class
Class.__call = callConstructor
Class.parent = false

local deleted_mt = {
    __index = function(deleted, key)
        local msg = "Trying to lookup key in deleted instance \"" .. deleted.name .. "\": " .. tostring(key)
        if enableClassDebugging then
            msg = msg .. "\nDeletion " .. deleted.traceback
        end
        error(msg)
    end,
    __newindex = function(deleted, key)
        local msg = "Trying to write new key in deleted instance \"" .. deleted.name .. "\": " .. tostring(key)
        if enableClassDebugging then
            msg = msg .. "\nDeletion " .. deleted.traceback
        end
        error(msg)
    end,
}

--
-- Erases an instance by clearing it and replacing its metatable. Attempts to
-- still use the class will generally result in an error.
--
-- Normally there is no need to call this function because you can rely on the
-- garbage collector, but some classes may extend this function and rely on it
-- being called.
--
-- See also Object.delete
--
function Class:delete()
    assert(not rawget(self, "__call"), "Trying to delete a class")
    local name = self:toString()
    for key in pairs(self) do
        self[key] = nil
    end
    self.name = name
    dbg(function()
        if enableClassDebugging then
            self.traceback = debug.traceback()
        end
    end)
    return setmetatable(self, deleted_mt)
end

local scheduledForDelete = {}

--
-- Does a delayed deletion of this instance. The instance will be deleted at
-- the end of the current update, or at the end of the next when there is
-- currently no update.
--
function Class:deleteLater()
    scheduledForDelete[self] = true
end

function Class.performDelayedDeletions()
    if next(scheduledForDelete) then
        for instance in pairs(scheduledForDelete) do
            instance:delete()
        end
        scheduledForDelete = {}
    end
end

--
-- It turns 'subclass' into a subclass of 'class', and prepares it to be
-- used as metatable for instances of 'subclass'.
--
function Class:extend(subclass)
    subclass.__index = subclass
    subclass.__call = callConstructor
    return setmetatable(subclass, self)
end

--
-- Returns this object when it is an instance of the given class, and nil
-- otherwise.
--
function Class:as(class)
    local meta = getmetatable(self)
    while meta do
        if meta == class then
            return self
        end
        meta = getmetatable(meta)
    end
    return nil
end

--
-- Returns the class of an instance. In the case of a class, this will return
-- the superclass.
--
function Class:class()
    return getmetatable(self)
end

function Class:isClass()
    return rawget(self, "__call") or false
end

--
-- Returns the superclass of an instance or class. Can be used to forward a
-- call to the superclass without knowing what it is. Example:
--
--     MyClass:super().method(self, ...)
--
-- Note: Don't use self:super() when calling a superclass method, since it
-- will always return the superclass of the instance rather than the
-- superclass of your class.
--
function Class:super()
    return getmetatable(rawget(self, "__index") or getmetatable(self))
end

--
-- Convenience function to log a message from an instance.
--
function Class:log(...)
    local name = self:toString()
    dbg(function()
        if rawget(_G, "debug") then
            local func = debug.getinfo(2, "n").name
            if func then
                name = name .. ":" .. func
            end
        end
    end)

    dbgprint("Class:log", name .. "\t", ...)
end

local instances

function Class:toString()
    local info = instances and instances[self]
    local table = tostring(self)
    return info and (info.class .. "[" .. table:sub(8) .. "]") or table
end

function Class:locationCreated()
    local info = instances and instances[self]
    return info and info.origin or ""
end

-- Records the class and creation place of every new instance
local function setDebugHooks()
    instances = setmetatable({}, { __mode = "k" })

    local function onCall(event)
        local func = debug.getinfo(2, "n").name

        -- Check whether a new object is being created
        if func == "new" then
            local class = debug.getinfo(3, "n").name
            if class == "new" then
                return -- This is not the top-level call to 'new'
            end

            local info = debug.getinfo(4, "Sl")
            if info.what == "tail" then
                return -- This is not the top-level call to 'new'
            end

            local origin = info.short_src .. " (" .. info.currentline .. ")"
            local _,instance = debug.getlocal(2, 2)

            if type(instance) ~= "table" then
                return  -- Probably a custom 'new' override
            end

            instances[instance] = {
                class = class or "unknown", -- Not all expressions have a name
                origin = origin,
            }
        end
    end

    debug.sethook(onCall, "c")
end

function Class.printStatistics()
    if not instances then
        dbgprint("Class", "Class debugging not enabled")
        return
    end

    collectgarbage()

    local counter = {}
    for instance,info in pairs(instances) do
        counter[info.class] = (counter[info.class] or 0) + 1
    end

    local result = {}
    local total = 0
    for class,count in pairs(counter) do
        result[#result + 1] = { class = class, count = count }
        total = total + count
    end

    table.sort(result, function(a,b) return a.count > b.count end)

    local separator = string.rep("-", 50)
    dbgprint("Class", separator)
    dbgprint("Class", total .. " instances")
    dbgprint("Class", separator)
    for _,r in ipairs(result) do
        dbgprint("Class", r.count, "\t", r.class)
    end
    dbgprint("Class", separator)
end

-- Class debugging uses a debug hook, which conflicts with debuggers,
-- profilers and coverage tools. Set enableClassDebugging to use it.
dbg(function()
    if enableClassDebugging and rawget(_G, "debug") then
        setDebugHooks()
    end
end)

return Class
