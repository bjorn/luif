--
-- Runs the test suite without LOVE:
--
--   luajit tests/run_luajit.lua [test_file.lua ...]
--
-- Test files live in tests/ and report through the API of tests/harness.lua
-- (t.ok, t.eq, t.near, t.raises, t.skip). Without arguments every
-- tests/test_*.lua runs in sorted order. Core's host (core/host.lua) is a
-- recording host (host/recording.lua) that reads files from disk, relative
-- to tests/ like LOVE's filesystem, and sizes textures from their PNG
-- headers. Tests of LOVE only code report skips. Exits with status 0 when
-- every check passed.
--

io.stdout:setvbuf("no")

local function isAbsolute(path)
    return path:sub(1, 1) == "/" or path:match("^%a:[/\\]") ~= nil
end

local dir = (arg and arg[0] or ""):match("^(.*)[/\\][^/\\]*$") or "."
if not isAbsolute(dir) then
    local cwd = os.getenv("PWD")
    if not cwd then
        local pipe = io.popen("pwd")
        cwd = pipe and pipe:read("*l")
        if pipe then pipe:close() end
    end
    if cwd then dir = cwd .. "/" .. dir end
end
local root = dir .. "/.."
package.path = root .. "/?.lua;" .. root .. "/?/init.lua;" .. package.path
package.loaded["tests.root"] = root

local files = {}
if arg and #arg > 0 then
    for i = 1, #arg do files[i] = arg[i] end
else
    local listing = assert(io.popen('ls "' .. dir .. '"'))
    for name in listing:lines() do
        if name:match("^test_.*%.lua$") then
            files[#files + 1] = name
        end
    end
    listing:close()
    table.sort(files)
end

local function readDisk(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local contents = f:read("*a")
    f:close()
    return contents
end

local Recording = require "luif.host.recording"
local host = Recording.new {
    strictTextures = true,
    pngSizes = true,
    screenWidth = 640, screenHeight = 480,   -- the window of tests/conf.lua
    readFile = function(path)
        if not isAbsolute(path) then
            path = dir .. "/" .. path
        end
        return readDisk(path)
    end,
}
require("luif.core.host").set(host)

local Harness = require "tests.harness"
Harness.run(files, function(name) return loadfile(dir .. "/" .. name) end)
os.exit(Harness.finish())
