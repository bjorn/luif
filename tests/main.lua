--
-- Test runner for the hosts that run a directory: `love tests` and
-- `luif-sdl --inspect tests` (both headless friendly: LOVE under xvfb, the
-- SDL runner with SDL_VIDEODRIVER=dummy). Runs every tests/test_*.lua in
-- sorted order with the host of the platform as core's host. Each file
-- returns a function(t) that reports through the API of tests/harness.lua.
-- Exits with status 0 when every check passed, 1 otherwise.
--

io.stdout:setvbuf("no")

local app = not love and require "app"
local source = love and love.filesystem.getSource() or app.source
local root = source .. "/.."
package.path = root .. "/?.lua;" .. root .. "/?/init.lua;" .. package.path

package.loaded["tests.root"] = root

-- Required here, Luif makes the host of the platform its host
require "luif"

local Harness = require "tests.harness"

local function isTest(name)
    return name:match("^test_.*%.lua$") ~= nil
end

if love then
    function love.load()
        local files = {}
        for _, name in ipairs(love.filesystem.getDirectoryItems("")) do
            if isTest(name) then
                files[#files + 1] = name
            end
        end
        table.sort(files)
        Harness.run(files, love.filesystem.load)
        love.event.quit(Harness.finish())
    end

    function love.draw()
    end
else
    -- The window of tests/conf.lua
    app.setWindowSize(640, 480)

    local files = {}
    local listing = assert(io.popen('ls "' .. source .. '"'))
    for name in listing:lines() do
        if isTest(name) then
            files[#files + 1] = name
        end
    end
    listing:close()
    table.sort(files)
    Harness.run(files, function(name) return loadfile(source .. "/" .. name) end)
    app.quit(Harness.finish())
end
