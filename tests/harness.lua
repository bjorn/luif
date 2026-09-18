--
-- The reporting API of the test files (t.ok, t.eq, t.near, t.raises, t.skip)
-- and the loop that runs them, shared by the runners:
--
--   local Harness = require "tests.harness"
--   Harness.run(files, function(name) return loadfile(dir .. "/" .. name) end)
--   local code = Harness.finish()     -- prints the totals; 0 when all passed
--

local Harness = {}

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
Harness.t = t

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

-- Runs the test files in order; load(name) returns the file's chunk, or nil
-- and a message.
function Harness.run(files, load)
    -- Tests run at a fixed UI scale of 1 (window pixels equal virtual units)
    -- unless they set another one
    require("luif.core.screen"):setScale(1)

    for _, name in ipairs(files) do
        print(name)
        local chunk, err = load(name)
        local ok, result
        if chunk then
            ok, result = pcall(chunk)
        end
        if not chunk then
            report(false, "load", err)
        elseif not ok then
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

function Harness.finish()
    print(string.format("%d passed, %d failed, %d skipped", passed, failed, skipped))
    return failed == 0 and 0 or 1
end

return Harness
