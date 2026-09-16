--[[

  Lua port of BezierEasing - https://github.com/gre/bezier-easing

  BezierEasing - use bezier curve for transition easing function
  by Gaëtan Renaudeau 2014 to 2015, MIT License

  Credits: is based on Firefox's nsSMILKeySpline.cpp
  Usage:
  local spline = BezierEasing { 0.25, 0.1, 0.25, 1.0 }
  spline:get(x) => returns the easing value | x must be in [0, 1] range

  Copyright (c) 2014 Gaëtan Renaudeau

  Permission is hereby granted, free of charge, to any person obtaining a
  copy of this software and associated documentation files (the "Software"),
  to deal in the Software without restriction, including without limitation
  the rights to use, copy, modify, merge, publish, distribute, sublicense,
  and/or sell copies of the Software, and to permit persons to whom the
  Software is furnished to do so, subject to the following conditions:

  The above copyright notice and this permission notice shall be included in
  all copies or substantial portions of the Software.

  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
  FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
  DEALINGS IN THE SOFTWARE.

--]]

-- These values are established by empiricism with tests (tradeoff: performance VS precision)
local NEWTON_ITERATIONS = 4
local NEWTON_MIN_SLOPE = 0.001
local SUBDIVISION_PRECISION = 0.0000001
local SUBDIVISION_MAX_ITERATIONS = 10

local kSplineTableSize = 11
local kSampleStepSize = 1.0 / (kSplineTableSize - 1.0)

local function A(aA1, aA2) return 1.0 - 3.0 * aA2 + 3.0 * aA1 end
local function B(aA1, aA2) return 3.0 * aA2 - 6.0 * aA1 end
local function C(aA1)      return 3.0 * aA1 end

-- Returns x(t) given t, x1, and x2, or y(t) given t, y1, and y2.
local function calcBezier(aT, aA1, aA2)
  return ((A(aA1, aA2)*aT + B(aA1, aA2))*aT + C(aA1))*aT
end

-- Returns dx/dt given t, x1, and x2, or dy/dt given t, y1, and y2.
local function getSlope(aT, aA1, aA2)
  return 3.0 * A(aA1, aA2)*aT*aT + 2.0 * B(aA1, aA2) * aT + C(aA1)
end

local function binarySubdivide(aX, aA, aB, mX1, mX2)
  local currentX, currentT
  local i = 0
  repeat
    currentT = aA + (aB - aA) / 2.0
    currentX = calcBezier(currentT, mX1, mX2) - aX
    if currentX > 0.0 then
      aB = currentT
    else
      aA = currentT
    end
    i = i + 1
  until not (math.abs(currentX) > SUBDIVISION_PRECISION and i < SUBDIVISION_MAX_ITERATIONS)
  return currentT
end

local function newtonRaphsonIterate(aX, aGuessT, mX1, mX2)
  for i = 0, NEWTON_ITERATIONS - 1 do
    local currentSlope = getSlope(aGuessT, mX1, mX2)
    if currentSlope == 0.0 then return aGuessT end
    local currentX = calcBezier(aGuessT, mX1, mX2) - aX
    aGuessT = aGuessT - currentX / currentSlope
  end
  return aGuessT
end

local BezierEasing = setmetatable({}, {
  __call = function(BezierEasing, ...)
    return BezierEasing.new(...)
  end
})

BezierEasing.__index = BezierEasing

--
-- points is an array of { mX1, mY1, mX2, mY2 }
--
function BezierEasing.new(points, mY1, mX2, mY2)
  if type(points) ~= "table" then
    return BezierEasing.new { points, mY1, mX2, mY2 }
  end

  if not points or #points ~= 4 then
    error("BezierEasing: points must contain 4 values")
  end

  for i = 1, 4 do
    if type(points[i]) ~= "number" then
      error("BezierEasing: points should be numbers.")
    end
  end

  if points[1] < 0 or points[1] > 1 or points[3] < 0 or points[3] > 1 then
    error("BezierEasing x values must be in [0, 1] range.")
  end

  local self = setmetatable({}, BezierEasing)
  local pointsString = table.concat(points, ", ")
  self._str = "BezierEasing(" .. pointsString .. ")"
  self._p = points
  self._mSampleValues = {}
  for i = 0, kSplineTableSize - 1 do
    self._mSampleValues[i] = 0
  end
  self._precomputed = false

  return self
end

function BezierEasing:get(x)
  local mX1 = self._p[1]
  local mY1 = self._p[2]
  local mX2 = self._p[3]
  local mY2 = self._p[4]
  if not self._precomputed then self:_precompute() end
  if mX1 == mY1 and mX2 == mY2 then return x end -- linear
  -- Because numbers are imprecise, we should guarantee the extremes are right.
  if x == 0 then return 0 end
  if x == 1 then return 1 end
  return calcBezier(self:_getTForX(x), mY1, mY2)
end

function BezierEasing:getPoints()
  return self._p
end

function BezierEasing:toString()
  return self._str
end

-- Private part

function BezierEasing:_precompute()
  local mX1 = self._p[1]
  local mY1 = self._p[2]
  local mX2 = self._p[3]
  local mY2 = self._p[4]
  self._precomputed = true
  if mX1 ~= mY1 or mX2 ~= mY2 then
    self:_calcSampleValues()
  end
end

function BezierEasing:_calcSampleValues()
  local mX1 = self._p[1]
  local mX2 = self._p[3]
  for i = 0, kSplineTableSize - 1 do
    self._mSampleValues[i] = calcBezier(i * kSampleStepSize, mX1, mX2)
  end
end

--
-- getTForX chose the fastest heuristic to determine the percentage value precisely from a given X projection.
--
function BezierEasing:_getTForX(aX)
  local mX1 = self._p[1]
  local mX2 = self._p[3]
  local mSampleValues = self._mSampleValues

  local intervalStart = 0.0
  local currentSample = 1
  local lastSample = kSplineTableSize - 1

  while currentSample ~= lastSample and mSampleValues[currentSample] <= aX do
    intervalStart = intervalStart + kSampleStepSize
    currentSample = currentSample + 1
  end
  currentSample = currentSample - 1

  -- Interpolate to provide an initial guess for t
  local dist = (aX - mSampleValues[currentSample]) / (mSampleValues[currentSample+1] - mSampleValues[currentSample])
  local guessForT = intervalStart + dist * kSampleStepSize

  local initialSlope = getSlope(guessForT, mX1, mX2)
  if initialSlope >= NEWTON_MIN_SLOPE then
    return newtonRaphsonIterate(aX, guessForT, mX1, mX2)
  elseif initialSlope == 0.0 then
    return guessForT
  else
    return binarySubdivide(aX, intervalStart, intervalStart + kSampleStepSize, mX1, mX2)
  end
end

BezierEasing.ease      = BezierEasing.new { 0.25, 0.1, 0.25, 1.0 }
BezierEasing.linear    = BezierEasing.new { 0.00, 0.0, 1.00, 1.0 }
BezierEasing.easeIn    = BezierEasing.new { 0.42, 0.0, 1.00, 1.0 }
BezierEasing.easeOut   = BezierEasing.new { 0.00, 0.0, 0.58, 1.0 }
BezierEasing.easeInOut = BezierEasing.new { 0.42, 0.0, 0.58, 1.0 }

-- CSS mapping
BezierEasing.css = {
  ["ease"]        = BezierEasing.ease,
  ["linear"]      = BezierEasing.linear,
  ["ease-in"]     = BezierEasing.easeIn,
  ["ease-out"]    = BezierEasing.easeOut,
  ["ease-in-out"] = BezierEasing.easeInOut
}

return BezierEasing
