--
-- Math utility functions
--

local sin = math.sin
local cos = math.cos
local sqrt = math.sqrt

local Math = {}

function Math.sign(x)
    return x > 0 and 1 or x < 0 and -1 or x == 0 and 0 or x
end

--- Clamps the value between the given minimum and maximum
function Math.clamp(value, min, max)
    return value < min and min or value > max and max or value
end

--- Rotates a 2D point around the origin.
-- @param angle The angle in radians.
function Math.rotate(x, y, angle)
    local cos_angle = cos(angle)
    local sin_angle = sin(angle)
    return x * cos_angle - y * sin_angle,
           y * cos_angle + x * sin_angle
end

function Math.length(vx, vy, vz)
    vz = vz or 0
    return math.sqrt(vx*vx + vy*vy + vz*vz)
end

function Math.normalize(vx, vy, vz)
    vz = vz or 0
    local length = math.sqrt(vx*vx + vy*vy + vz*vz)
    if length > 0 then
        return vx / length, vy / length, vz / length
    end
    return 0, 0, 0
end

-- Warning: this is twice as slow as sqrt(x*x + y*y). Only use when the
-- additional precision is required.
function Math.hypot(x, y)
    x = x < 0 and -x or x
    y = y < 0 and -y or y

    local t = x < y and x or y
    x = x > y and x or y
    t = t / x

    return x * sqrt(1 + t * t)
end

function Math.round(num, idp)
    local mult = idp and 10^idp or 1
    return math.floor(num * mult + 0.5) / mult
end

function Math.lerp(from, to, factor)
    return from + (to - from) * factor
end

return Math
