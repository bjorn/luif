--
-- Test runner: `love tests` (headless friendly, run under xvfb when there
-- is no display). Runs every tests/test_*.lua in sorted order. Each file
-- returns a function(t) that reports through t.ok, t.eq, t.near, t.raises
-- and t.skip. Exits with status 0 when every check passed, 1 otherwise.
--

io.stdout:setvbuf("no")

local root = love.filesystem.getSource() .. "/.."
package.path = root .. "/?.lua;" .. root .. "/?/init.lua;" .. package.path

package.loaded["tests.root"] = root

-- Required under LOVE, Luif makes the LOVE host its host
require "luif"

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
    local ok, err = pcall(fn)
    return report(not ok, label or "raises", "no error raised")
end

function t.skip(label)
    skipped = skipped + 1
    print("  SKIP " .. label)
end

local function runFile(name)
    print(name)
    local chunk, err = love.filesystem.load(name)
    if not chunk then
        report(false, "load", err)
        return
    end
    local ok, result = pcall(chunk)
    if not ok then
        report(false, "load", tostring(result))
        return
    end
    if type(result) ~= "function" then
        report(false, "shape", "file must return a function(t)")
        return
    end
    local ran, trace = xpcall(function() result(t) end, debug.traceback)
    if not ran then
        report(false, "error", tostring(trace))
    end
end

function love.load()
    local files = {}
    for _, name in ipairs(love.filesystem.getDirectoryItems("")) do
        if name:match("^test_.*%.lua$") then
            files[#files + 1] = name
        end
    end
    table.sort(files)

    -- Tests run at a fixed UI scale of 1 (window pixels equal virtual
    -- units) unless they set another one
    require("luif.core.screen"):setScale(1)

    for _, name in ipairs(files) do
        runFile(name)
    end

    print(string.format("%d passed, %d failed, %d skipped", passed, failed, skipped))
    love.event.quit(failed == 0 and 0 or 1)
end

function love.draw()
end
