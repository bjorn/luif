--
-- Bezier helper functions, can be used with core.Move and core.PathLayout
--

local Bezier = {}

function Bezier.line(a, b)
    return function(t)
        local t1 = 1 - t

        return t1 * a[1] + t * b[1],
               t1 * a[2] + t * b[2]
    end
end

function Bezier.quad(a, b, c)
    return function(t)
        local t1 = 1 - t

        local f1 = t1*t1
        local f2 = 2 * t * t1
        local f3 = t*t

        return f1 * a[1] + f2 * b[1] + f3 * c[1],
               f1 * a[2] + f2 * b[2] + f3 * c[2]
    end
end

function Bezier.cubic(a, b, c, d)
    return function(t)
        local t1 = 1 - t

        local f1 = t1*t1*t1
        local f2 = 3 * t * t1*t1
        local f3 = 3 * t*t * t1
        local f4 = t*t*t

        return f1 * a[1] + f2 * b[1] + f3 * c[1] + f4 * d[1],
               f1 * a[2] + f2 * b[2] + f3 * c[2] + f4 * d[2]
    end
end

return Bezier
