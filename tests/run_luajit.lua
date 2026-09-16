--
-- Runs the test suite without LOVE:
--
--   luajit tests/run_luajit.lua [test_file.lua ...]
--
-- Test files live in tests/ and use the same reporting API as tests/main.lua
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

local passed, failed, skipped = 0, 0, 0

local function report(ok, label, detail)
    if ok then
        passed = passed + 1
        print("  PASS " .. label)
    else
        failed = failed + 1
        print("  FAIL " .. label .. (detail and (": " .. detail) or ""))
    end
    return ok
end

local t = {}

function t.ok(cond, label)
    return report(cond and true or false, label or "ok")
end

function t.eq(actual, expected, label)
    return report(actual == expected, label or "eq",
                  "expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

function t.near(a, b, eps, label)
    eps = eps or 1e-6
    local ok = type(a) == "number" and type(b) == "number" and math.abs(a - b) <= eps
    return report(ok, label or "near",
                  "expected " .. tostring(b) .. " within " .. eps .. ", got " .. tostring(a))
end

function t.raises(fn, label)
    local ok = pcall(fn)
    return report(not ok, label or "raises", "no error raised")
end

function t.skip(label)
    skipped = skipped + 1
    print("  SKIP " .. label)
end

-- Tests run at a fixed UI scale of 1 (window pixels equal virtual units)
-- unless they set another one
require("luif.core.screen"):setScale(1)

for _, name in ipairs(files) do
    print(name)
    local chunk, err = loadfile(dir .. "/" .. name)
    if not chunk then
        report(false, "load", err)
    else
        local ok, result = pcall(chunk)
        if not ok then
            report(false, "load", tostring(result))
        elseif type(result) ~= "function" then
            report(false, "shape", "file must return a function(t)")
        else
            local ran, trace = xpcall(function() result(t) end, debug.traceback)
            if not ran then
                report(false, "error", tostring(trace))
            end
        end
    end
end

print(string.format("%d passed, %d failed, %d skipped", passed, failed, skipped))
os.exit(failed == 0 and 0 or 1)
