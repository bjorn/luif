--
-- Bit operations for core: the bit library when the runtime has one (LuaJIT,
-- LOVE), otherwise a pure Lua fallback with the same results. Operands are
-- taken modulo 2^32 and results are signed 32 bit numbers, as with LuaJIT's
-- bit library.
--
--   local bit = core.Bit
--   bit.band(a, b, ...), bit.bor(a, b, ...), bit.bxor(a, b, ...), bit.bnot(a)
--   bit.lshift(a, n), bit.rshift(a, n), bit.tobit(a), bit.tohex(a, digits)
--
-- Bit.fallback is the pure Lua implementation, for tests.
--

local floor = math.floor

local TWO32 = 4294967296
local TWO31 = 2147483648

local Fallback = {}

local function unsigned(a)
    return floor(a) % TWO32
end

function Fallback.tobit(a)
    a = unsigned(a)
    if a >= TWO31 then
        return a - TWO32
    end
    return a
end

local tobit = Fallback.tobit

-- Combines two unsigned 32 bit numbers bit by bit; op(x, y) works on 0 or 1.
local function combine(a, b, op)
    local result, place = 0, 1
    for _ = 1, 32 do
        local x, y = a % 2, b % 2
        result = result + op(x, y) * place
        a, b = (a - x) / 2, (b - y) / 2
        place = place * 2
    end
    return result
end

local function andBit(x, y) return x * y end
local function orBit(x, y) return (x + y > 0) and 1 or 0 end
local function xorBit(x, y) return (x + y) % 2 end

local function fold(op, a, ...)
    local result = unsigned(a)
    for i = 1, select("#", ...) do
        result = combine(result, unsigned((select(i, ...))), op)
    end
    return tobit(result)
end

function Fallback.band(...) return fold(andBit, ...) end
function Fallback.bor(...) return fold(orBit, ...) end
function Fallback.bxor(...) return fold(xorBit, ...) end

function Fallback.bnot(a)
    return tobit(TWO32 - 1 - unsigned(a))
end

function Fallback.lshift(a, n)
    n = floor(n) % 32
    return tobit(unsigned(a) * 2 ^ n)
end

function Fallback.rshift(a, n)
    n = floor(n) % 32
    return tobit(floor(unsigned(a) / 2 ^ n))
end

-- Lower case hexadecimal of the low digits * 4 bits; negative digits give
-- upper case, like LuaJIT. Default 8 digits.
function Fallback.tohex(a, digits)
    digits = digits or 8
    local upper = digits < 0
    if upper then digits = -digits end
    if digits > 8 then digits = 8 end
    local value = unsigned(a) % (2 ^ (4 * digits))
    local s = string.format(upper and "%0" .. digits .. "X" or "%0" .. digits .. "x", value)
    return s
end

local native = rawget(_G, "bit")

local Bit = {}
Bit.fallback = Fallback
Bit.native = native and true or false

for name, fn in pairs(Fallback) do
    Bit[name] = native and native[name] or fn
end

return Bit
