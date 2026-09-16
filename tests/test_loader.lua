--
-- Loading core without require: module.loader with a host's readFile and
-- load, the way an environment without require (Luanti mod security) would.
-- The recording host serves the files from disk. Core loaded like this with
-- only the standard library as globals (no love, io, os, bit, package)
-- reads nothing outside core/, builds an item tree into a host and matches
-- the tree the normally loaded core builds.
--
return function(t)
    local root = require "tests.root"
    local module = require "luif.module"
    local Recording = require "luif.host.recording"
    local Sync = require "luif.core.sync"

    local function readDisk(path)
        local f = io.open(root .. "/" .. path, "rb")
        if not f then return nil, "cannot open " .. path end
        local contents = f:read("*a")
        f:close()
        return contents
    end

    local reads = {}
    local host = Recording.new {
        glyphWidth = 8, lineHeight = 16, strictTextures = true,
        readFile = function(path)
            reads[#reads + 1] = path
            return readDisk(path)
        end,
    }

    -- Only the Lua standard library
    local globals = {}
    for _, name in ipairs {
        "assert", "collectgarbage", "error", "getfenv", "getmetatable", "ipairs", "load",
        "loadstring", "next", "pairs", "pcall", "print", "rawequal", "rawget", "rawset",
        "select", "setfenv", "setmetatable", "tonumber", "tostring", "type", "unpack",
        "xpcall", "_VERSION", "coroutine", "debug", "math", "string", "table",
    } do
        globals[name] = rawget(_G, name)
    end
    globals._G = globals

    local before = {}
    for name in pairs(package.loaded) do before[name] = true end

    local loader = module.loader { readFile = host.readFile, globals = globals }
    t.eq(loader.require "luif.module", loader, "require \"module\" inside loaded files is the loader")

    local ok, err = pcall(function()
        loader.require("luif.core.host").set(host)
    end)
    t.ok(ok, "luif.core.host loads through readFile: " .. tostring(err))
    if not ok then return end

    local loadedCore = loader "luif.core"
    local Class = loader.require "luif.core.class"
    t.eq(loader.require "luif.core.class", Class, "a module is loaded once")
    t.ok(Class ~= require "luif.core.class", "the loaded copy is separate from the required one")
    local readsOfClass = 0
    for _, path in ipairs(reads) do
        if path == "luif/core/class.lua" then readsOfClass = readsOfClass + 1 end
    end
    t.eq(readsOfClass, 1, "and read once")
    t.ok(host.count("readFile") >= 2, "files are read through the host's readFile")
    t.eq(loader.require("luif.core.bit").native, false, "without a bit global core uses the pure Lua bit")
    t.raises(function() loader.require "luif.core.no_such_module" end, "a missing module raises")

    -- Every core module loads with the standard library only
    local names = {}
    local listing = io.popen('ls "' .. root .. '/luif/core" "' .. root .. '/luif/core/skins"')
    local section = "luif.core"
    if listing then
        for line in listing:lines() do
            local heading = line:match("^.*/(luif/core/?[%w]*):$")
            if heading then
                section = heading:gsub("/", ".")
            elseif line:match("%.lua$") then
                names[#names + 1] = section .. "." .. line:gsub("%.lua$", "")
            end
        end
        listing:close()
    end
    if #names > 0 then
        local failures = {}
        for _, name in ipairs(names) do
            local loaded, message = pcall(loader.require, name)
            if not loaded then failures[#failures + 1] = name .. ": " .. tostring(message) end
        end
        t.eq(#failures, 0, "all " .. #names .. " core modules load without love, io, os, bit or "
             .. "package: " .. table.concat(failures, "; "))
    else
        t.skip("cannot list core/")
    end

    local outside = {}
    for _, path in ipairs(reads) do
        if not path:match("^luif/core[/.]") then outside[#outside + 1] = path end
    end
    t.eq(#outside, 0, "nothing outside luif/core/ is read (no LOVE host): " .. table.concat(outside, ", "))

    local added = {}
    for name in pairs(package.loaded) do
        if not before[name] then added[#added + 1] = name end
    end
    t.eq(#added, 0, "the loader leaves package.loaded alone: " .. table.concat(added, ", "))

    -- The loaded core builds the same host scene as the required one
    local function build(core, into)
        local Update = core.Update
        Update:setUiScale(1)
        local panel = core.Item {
            x = 10, y = 20, width = 200, height = 100,
            core.Rectangle { width = 200, height = 100, color = core.Color.rgb(40, 50, 60),
                             borderColor = 0xFF808080 },
            core.Label { text = "{color:#ff8000}Hello{/color} world", x = 8, y = 8 },
            core.Button { text = "OK", x = 20, y = 50 },
        }
        core.Sync.addRoot(panel)
        Update.onUpdate(1000, 16)
        local dump = into.dump()
        panel:delete()
        Update.onUpdate(1016, 16)
        return dump
    end

    local loadedDump
    ok, err = pcall(function() loadedDump = build(loadedCore, host) end)
    t.ok(ok, "an item tree builds and flushes in the loaded core: " .. tostring(err))

    local other = Recording.new { glyphWidth = 8, lineHeight = 16, strictTextures = true }
    Sync.setHost(other)
    local requiredDump
    ok, err = pcall(function() requiredDump = build(module "luif.core", other) end)
    Sync.setHost(nil)
    t.ok(ok, "the same tree builds in the required core: " .. tostring(err))
    if loadedDump and requiredDump then
        local function names(dump) return (dump:gsub("node#%d+", "node")) end
        -- Textures and fonts come from different hosts; their names and sizes match
        t.eq(names(loadedDump), names(requiredDump), "both cores build the same scene")
        t.ok(loadedDump:find("text=\"Hello world\" runs", 1, true) ~= nil, "with colour runs")
    end
end
