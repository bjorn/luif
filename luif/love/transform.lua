--
-- Transform and clip helpers of the LOVE host (luif/love/host.lua). Node
-- records need the fields x, y, rotation, scale, ox and oy.
--
-- A node's transform relative to its parent is
-- T(x, y) * T(ox, oy) * R(rotation) * S(scale) * T(-ox, -oy). Transforms are
-- similarities represented by four numbers (a, b, tx, ty) meaning
-- world = (a * lx - b * ly + tx, b * lx + a * ly + ty), so they compose and
-- invert without allocating.
--

local cos, sin, floor, ceil, abs = math.cos, math.sin, math.floor, math.ceil, math.abs

local EPS = 1e-6
local SNAP = 1e-12

local Transform = {}

-- The node's own transform relative to its parent. Near zero sine and
-- cosine are snapped so right angle rotations stay exact (cos(pi / 2) is
-- about 6e-17, which would push points on a rectangle edge outside).
function Transform.localTransform(node)
    local s, r = node.scale, node.rotation
    local a, b
    if r == 0 then
        a, b = s, 0
    else
        local c, n = cos(r), sin(r)
        if abs(c) < SNAP then c = 0 end
        if abs(n) < SNAP then n = 0 end
        a, b = s * c, s * n
    end
    local ox, oy = node.ox, node.oy
    return a, b, node.x + ox - (a * ox - b * oy), node.y + oy - (b * ox + a * oy)
end

-- parent (A, B, TX, TY) followed by child (a, b, tx, ty).
function Transform.compose(A, B, TX, TY, a, b, tx, ty)
    return A * a - B * b, A * b + B * a, A * tx - B * ty + TX, B * tx + A * ty + TY
end

-- Applies the node's transform to the love.graphics transform stack.
function Transform.apply(lg, node)
    local ox, oy = node.ox, node.oy
    lg.translate(node.x + ox, node.y + oy)
    if node.rotation ~= 0 then lg.rotate(node.rotation) end
    if node.scale ~= 1 then lg.scale(node.scale) end
    if ox ~= 0 or oy ~= 0 then lg.translate(-ox, -oy) end
end

local stencilDepth = 0
local stencilX, stencilY, stencilW, stencilH = 0, 0, 0, 0

local function stencilRect()
    love.graphics.rectangle("fill", stencilX, stencilY, stencilW, stencilH)
end

--
-- Starts clipping to the local rectangle (x, y, w, h) under the current
-- love.graphics transform. a and b are the rotation and scale part of the
-- accumulated transform: when the rectangle stays axis aligned the scissor
-- is intersected, otherwise a stencil is used. Returns the state popClip
-- needs: mode (1 scissor, 2 stencil) and the previous scissor.
--
function Transform.pushClip(lg, a, b, x, y, w, h)
    if abs(a) < EPS or abs(b) < EPS then
        local sx, sy, sw, sh = lg.getScissor()
        local x0, y0 = lg.transformPoint(x, y)
        local x1, y1 = lg.transformPoint(x + w, y + h)
        if x1 < x0 then x0, x1 = x1, x0 end
        if y1 < y0 then y0, y1 = y1, y0 end
        x0, y0 = floor(x0), floor(y0)
        lg.intersectScissor(x0, y0, ceil(x1) - x0, ceil(y1) - y0)
        return 1, sx, sy, sw, sh
    end
    stencilX, stencilY, stencilW, stencilH = x, y, w, h
    lg.stencil(stencilRect, "increment", 1, true)
    stencilDepth = stencilDepth + 1
    lg.setStencilTest("gequal", stencilDepth)
    return 2
end

-- Ends the clip started by pushClip with the same rectangle.
function Transform.popClip(lg, mode, sx, sy, sw, sh, x, y, w, h)
    if mode == 1 then
        if sx then
            lg.setScissor(sx, sy, sw, sh)
        else
            lg.setScissor()
        end
    elseif mode == 2 then
        stencilX, stencilY, stencilW, stencilH = x, y, w, h
        lg.stencil(stencilRect, "decrement", 1, true)
        stencilDepth = stencilDepth - 1
        if stencilDepth > 0 then
            lg.setStencilTest("gequal", stencilDepth)
        else
            lg.setStencilTest()
        end
    end
end

return Transform
