--
-- Live reload on the SDL host:
--
--     luif-sdl --inspect --watch tests/reload <empty scratch directory>
--
-- Run 1 writes a Lua module and an image into the scratch directory, uses
-- them, changes both and asks for a reload. Run 2 checks that modules, images
-- and the scene are fresh while globals survived, changes the module once
-- more and waits for --watch to notice. Run 3 checks that and quits. Exits
-- with status 0 when every check passed.
--

local app = require "app"
local scratch = assert(app.args[1], "pass an empty scratch directory")
local root = app.source .. "/../.."
package.path = root .. "/?.lua;" .. root .. "/?/init.lua;" .. scratch .. "/?.lua;" .. package.path

local luif = require "luif"
local host = package.loaded["luif.sdl"]

-- Globals survive a reload; that is how this script knows which run it is
run = (run or 0) + 1
failures = failures or 0

local function check(ok, label)
    print((ok and "  PASS " or "  FAIL ") .. "run " .. run .. ": " .. label)
    if not ok then failures = failures + 1 end
end

local function write(name, contents)
    local file = assert(io.open(scratch .. "/" .. name, "wb"))
    file:write(contents)
    file:close()
end

-- A BMP of one row of red pixels
local function bmp(width)
    local function u32(n)
        return string.char(n % 256, math.floor(n / 256) % 256, math.floor(n / 65536) % 256, 0)
    end
    local row = ("\0\0\255"):rep(width) .. ("\0"):rep((4 - width * 3 % 4) % 4)
    return "BM" .. u32(54 + #row) .. u32(0) .. u32(54) .. u32(40) .. u32(width) .. u32(1)
        .. "\1\0\24\0" .. u32(0) .. u32(#row) .. u32(2835) .. u32(2835) .. u32(0) .. u32(0) .. row
end

local function finish()
    print(failures == 0 and "reload test passed" or "reload test FAILED")
    app.quit(failures == 0 and 0 or 1)
end

app.watch(scratch)
luif.root:addChild(luif.Label { text = "run " .. run, x = 10, y = 10 })

if run == 1 then
    write("generated.lua", "return 1")
    write("image.bmp", bmp(1))
    check(require("generated") == 1, "the generated module loads")
    check(host.textureSize(assert(host.loadTexture(scratch .. "/image.bmp"))) == 1, "the image loads")
    write("generated.lua", "return 2 -- changed")
    write("image.bmp", bmp(2))
    check(require("generated") == 1, "a loaded module stays as it is")
    check(host.textureSize(host.loadTexture(scratch .. "/image.bmp")) == 1, "and so does a loaded image")
    oldRoot = luif.root
    app.reload()
elseif run == 2 then
    check(require("generated") == 2, "the reload reads Lua modules again")
    check(host.textureSize(assert(host.loadTexture(scratch .. "/image.bmp"))) == 2, "and images")
    check(luif.root ~= oldRoot, "luif itself is loaded afresh")
    luif.update(0)
    check(#host.topLevel() == 1, "the scene holds only what this run made (" .. #host.topLevel() .. ")")
    oldRoot = nil

    -- Now a change on disk alone has to bring run 3
    local waited = 0
    local changed = false
    app.update = function(dt)
        waited = waited + dt
        if not changed and waited > 0.2 then
            changed = true
            write("generated.lua", "return 3 -- changed again")
        elseif waited > 10 then
            check(false, "--watch reloads after a change on disk")
            finish()
        end
    end
else
    check(require("generated") == 3, "--watch reloads after a change on disk")
    finish()
end
