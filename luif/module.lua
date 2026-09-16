--
-- A Module provides a way to namespace a bunch of files and requires them on
-- demand. Example usage:
--
--  local module = require "luif.module"
--
--  local core = module "luif.core"
--  local widgets = module "ui.widgets"
--
--  local panel = core.Item {
--      ...
--      widgets.ColorPicker {
--          ...
--      }
--  }
--
--
-- It even supports on-demand creation of sub-modules, based on whether the
-- name starts with upper case or lower case. Example:
--
--  local ui = module "ui"
--  local picker = ui.widgets.ColorPicker { ... }
--
--
-- As with 'require', the module tables are cached.
--
-- Loading: by default a module is loaded with the global require. For
-- environments without a usable require (for example Luanti mods under mod
-- security), a loader reads files itself:
--
--   local loader = module.loader { readFile = host.readFile, root = "ui/" }
--   local core = loader "luif.core"
--   local Class = loader.require "luif.core.class"
--
-- A reading loader maps "luif.core.class" to root .. "luif/core/class.lua", reads it
-- with readFile(path) -> contents or nil, message, compiles it with load and
-- runs it once, with an environment whose require is loader.require (every
-- other global comes from _G). Inside such files, require "luif.module" returns
-- the loader itself. options.preload maps module names to values that are
-- returned without reading a file, and options.globals replaces _G as the
-- table the files' other globals come from. module.require is the default
-- loader's require, which is the global require.
--
-- This file uses only the Lua standard library, so an application can load
-- it with dofile or load(readFile("luif/module.lua")) as well.
--

local loadString = loadstring or load

local function newLoader(options)
    options = options or {}
    local readFile = options.readFile
    local root = options.root or ""

    local loader = {}
    local moduleMT = {}
    local cache = {}

    local function module(path)
        assert(type(path) == "string", "Invalid module path")
        if not cache[path] then
            cache[path] = setmetatable({ _path = path }, moduleMT)
        end
        return cache[path]
    end

    local requireModule

    if readFile then
        local loaded = {}
        local loading = {}
        local env = setmetatable({}, { __index = options.globals or _G })

        for name, value in pairs(options.preload or {}) do
            loaded[name] = value
        end

        function requireModule(name)
            local value = loaded[name]
            if value ~= nil then
                return value
            end
            if name == "luif.module" then
                return loader
            end
            if loading[name] then
                error("loop loading module '" .. name .. "'", 2)
            end
            local base = root .. name:gsub("%.", "/")
            local path = base .. ".lua"
            local source, message = readFile(path)
            if not source then
                -- A package is a directory with an init.lua
                local initSource = readFile(base .. "/init.lua")
                if initSource then
                    source, path = initSource, base .. "/init.lua"
                end
            end
            if not source then
                error("module '" .. name .. "' not found: " .. tostring(message), 2)
            end
            local chunk, err
            if setfenv then
                chunk, err = loadString(source, "@" .. path)
                if chunk then setfenv(chunk, env) end
            else
                chunk, err = load(source, "@" .. path, "t", env)
            end
            if not chunk then
                error(err, 2)
            end
            loading[name] = true
            local ok, result = pcall(chunk, name)
            loading[name] = nil
            if not ok then
                error(result, 0)
            end
            if result == nil then
                result = true
            end
            loaded[name] = result
            return result
        end

        env.require = requireModule
    else
        requireModule = require
    end

    loader.require = requireModule
    loader.loader = newLoader

    function moduleMT.__index(table, key)
        local path = rawget(table, "_path")
        path = (#path > 0) and (path .. "." .. key:lower()) or key:lower()

        local value = key:match("^%l") and module(path) or requireModule(path)
        if value == true then
            error("Nothing returned from '".. path .."'")
        end
        rawset(table, key, value)
        return value
    end

    function moduleMT.__newindex(table, key, value)
        error("Can't write to a module")
    end

    return setmetatable(loader, {
        __call = function(_, path)
            return module(path)
        end,
    })
end

return newLoader()
