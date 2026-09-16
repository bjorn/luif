--
-- Luif, a retained UI framework:
--
--   local luif = require "luif"
--   luif.root:addChild(luif.Button { text = "Hello", click = function() ... end })
--
-- The table has every class and module of luif/core by name (luif.Button,
-- luif.Item, luif.Update, ...), loaded on first use, and:
--
--   luif.root           an item covering the screen with an AnchorLayout,
--                       created on first use; add the UI to it
--   luif.setHost(host)  the host that draws the UI and feeds it input
--                       (luif/host/interface.lua); under LOVE the LOVE host
--                       is set up when luif is required
--   luif.update(dt)     timers, effects, layout and the node flush, with dt
--                       in seconds
--
-- Under LOVE the table also has draw(), the input callbacks and hook() of
-- luif/love/init.lua.
--
-- The folder may live elsewhere, such as lib/luif: require "lib.luif" makes
-- the luif.* modules requirable through that prefix.
--

local name = ... or "luif"
local prefix = name:match("^(.-)luif$") or ""
if prefix ~= "" then
    local searchers = package.loaders or package.searchers
    table.insert(searchers, 2, function(moduleName)
        if moduleName:sub(1, 5) == "luif." then
            return function() return require(prefix .. moduleName) end
        end
    end)
end

local core = require "luif.core"
local Host = core.Host

local luif = {}

function luif.setHost(host)
    Host.set(host)
    core.Pointer.attach(host)
end

function luif.update(dt)
    core.Update.onUpdate(Host.get().time(), dt * 1000)
    core.Pointer.afterUpdate()
end

local root = false

local function createRoot()
    local Update = core.Update
    local Screen = core.Screen
    if Host.current() then
        Screen:update()
    end
    root = core.Item {
        x = 0, y = 0,
        width = Screen.width,
        height = Screen.height,
        layout = core.AnchorLayout {},
    }
    Screen:on("changed", function(_, width, height)
        root:setSize(width, height)
    end)
    core.Sync.addRoot(root)
end

if love and love.graphics then
    local Love = require "luif.love"
    if not Host.current() then
        Host.set(Love.host)
    end
    for _, key in ipairs(Love.functions) do
        luif[key] = Love[key]
    end
end

if prefix ~= "" then
    package.loaded.luif = luif
end

return setmetatable(luif, {
    __index = function(_, key)
        if key == "root" then
            if not root then
                createRoot()
            end
            return root
        end
        return core[key]
    end,
})
