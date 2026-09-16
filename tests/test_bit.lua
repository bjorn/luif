--
-- core/bit.lua: the pure Lua fallback gives the results of LuaJIT's bit
-- library, and core/color.lua works on it.
--
return function(t)
    local Bit = require "luif.core.bit"
    local F = Bit.fallback

    t.eq(F.band(0xFF00FF00, 0x0FF0), 0x0F00, "band")
    t.eq(F.band(0xFFFFFFFF, 0xF0F0F0F0, 0xFF00FF00), -268374016, "band of three")
    t.eq(F.bor(0xFF000000, 0), -16777216, "bor gives signed results")
    t.eq(F.bor(1, 2, 4), 7, "bor of three")
    t.eq(F.bxor(0xFF, 0x0F), 0xF0, "bxor")
    t.eq(F.bnot(0), -1, "bnot")
    t.eq(F.lshift(1, 31), -2147483648, "lshift into the sign bit")
    t.eq(F.lshift(0xFF, 16), 0xFF0000, "lshift")
    t.eq(F.rshift(-1, 28), 15, "rshift is logical")
    t.eq(F.rshift(0xFF000000, 24), 255, "rshift of a colour")
    t.eq(F.tobit(0xFFFFFFFF), -1, "tobit")
    t.eq(F.tohex(0xABCDEF, 6), "abcdef", "tohex with digits")
    t.eq(F.tohex(-1), "ffffffff", "tohex of -1")
    t.eq(F.tohex(255, -4), "00FF", "tohex upper case")

    local native = rawget(_G, "bit")
    if native then
        t.eq(Bit.native, true, "the bit library is used when present")
        local values = { 0, 1, -1, 255, 0x7FFFFFFF, 0x80000000, 0xFFFFFFFF, 0xFF808080, 123456789, -98765 }
        local same = true
        for _, a in ipairs(values) do
            for _, b in ipairs(values) do
                same = same and F.band(a, b) == native.band(a, b) and F.bor(a, b) == native.bor(a, b)
                    and F.bxor(a, b) == native.bxor(a, b)
            end
            for n = 0, 31, 7 do
                same = same and F.lshift(a, n) == native.lshift(a, n)
                    and F.rshift(a, n) == native.rshift(a, n)
            end
            same = same and F.bnot(a) == native.bnot(a) and F.tobit(a) == native.tobit(a)
                and F.tohex(a, 6) == native.tohex(a, 6) and F.tohex(a) == native.tohex(a)
        end
        t.ok(same, "the fallback matches the bit library")
    else
        t.eq(Bit.native, false, "the fallback is used without a bit library")
    end

    -- core/color.lua on the fallback, through a loader without the bit global
    local root = require "tests.root"
    local module = require "luif.module"
    local globals = setmetatable({ bit = false }, { __index = _G })
    globals._G = setmetatable({}, { __index = function(_, key)
        if key == "bit" then return nil end
        return _G[key]
    end })
    local loader = module.loader {
        globals = globals,
        readFile = function(path)
            local f = io.open(root .. "/" .. path, "rb")
            if not f then return nil, "missing " .. path end
            local contents = f:read("*a")
            f:close()
            return contents
        end,
    }
    local ok, err = pcall(function()
        t.eq(loader.require("luif.core.bit").native, false, "the loaded copy uses the fallback")
        local Color = require "luif.core.color"
        local FallbackColor = loader.require "luif.core.color"
        t.eq(FallbackColor.rgb(10, 20, 30), Color.rgb(10, 20, 30), "Color.rgb on the fallback")
        t.eq(FallbackColor.rgba(10, 20, 30, 128), Color.rgba(10, 20, 30, 128), "Color.rgba on the fallback")
        local a, b = { FallbackColor.channels(0x80FF4020) }, { Color.channels(0x80FF4020) }
        t.ok(a[1] == b[1] and a[2] == b[2] and a[3] == b[3] and a[4] == b[4],
             "Color.channels on the fallback")
    end)
    t.ok(ok, "colour checks ran: " .. tostring(err))
end
