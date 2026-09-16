--
-- A bunch of easing functions that can be used for Animate.ease
--
-- 'p' stands for progress and counts from 0 to 1.
--

local core = require "luif.core"

local BezierEasing = core.BezierEasing

local sin = math.sin
local cos = math.cos
local pi = math.pi

local Ease = {}

function Ease.linear(p)     return p end

function Ease.inQuad(p)     return p*p end
function Ease.inCubic(p)    return p*p*p end
function Ease.inQuart(p)    return p^4 end
function Ease.inQuint(p)    return p^5 end

function Ease.outQuad(p)    return 1 - (p - 1)^2 end
function Ease.outCubic(p)   return (p - 1)^3 + 1 end
function Ease.outQuart(p)   return 1 - (p - 1)^4 end
function Ease.outQuint(p)   return (p - 1)^5 + 1 end

function Ease.inOutQuad(p)  return (p < 0.5 and Ease.inQuad(p * 2) or (1 + Ease.outQuad(p * 2 - 1))) / 2 end
function Ease.inOutCubic(p) return (p < 0.5 and Ease.inCubic(p * 2) or (1 + Ease.outCubic(p * 2 - 1))) / 2 end
function Ease.inOutQuart(p) return (p < 0.5 and Ease.inQuart(p * 2) or (1 + Ease.outQuart(p * 2 - 1))) / 2 end
function Ease.inOutQuint(p) return (p < 0.5 and Ease.inQuint(p * 2) or (1 + Ease.outQuint(p * 2 - 1))) / 2 end

function Ease.outInQuad(p)  return (p < 0.5 and Ease.outQuad(p * 2) or (1 + Ease.inQuad(p * 2 - 1))) / 2 end
function Ease.outInCubic(p) return (p < 0.5 and Ease.outCubic(p * 2) or (1 + Ease.inCubic(p * 2 - 1))) / 2 end
function Ease.outInQuart(p) return (p < 0.5 and Ease.outQuart(p * 2) or (1 + Ease.inQuart(p * 2 - 1))) / 2 end
function Ease.outInQuint(p) return (p < 0.5 and Ease.outQuint(p * 2) or (1 + Ease.inQuint(p * 2 - 1))) / 2 end

function Ease.inSine(p)     return 1 - cos(p * pi / 2) end
function Ease.outSine(p)    return sin(p * pi / 2) end
function Ease.inOutSine(p)  return (1 - cos(p * pi)) / 2 end

function Ease.outBack(p)
    local overshoot = 1.70158 -- Overshoots 10 percent
    p = p - 1
    return p * p * ((overshoot + 1) * p + overshoot) + 1
end

function Ease.ease(p)       return BezierEasing.ease:get(p) end
function Ease.easeIn(p)     return BezierEasing.easeIn:get(p) end
function Ease.easeOut(p)    return BezierEasing.easeOut:get(p) end
function Ease.easeInOut(p)  return BezierEasing.easeInOut:get(p) end

-- Function generators that allow passing in parameters

function Ease.createOutBack(overshoot)
    return function(p)
        p = p - 1
        return p * p * ((overshoot + 1) * p + overshoot) + 1
    end
end

function Ease.createBezier(mX1, mY1, mX2, mY2)
    local bezierEasing = BezierEasing { mX1, mY1, mX2, mY2 }
    return function(p)
        return bezierEasing:get(p)
    end
end

return Ease
