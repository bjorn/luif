--
-- The LOVE host (luif/love/host.lua): the interface conformance tests, and
-- drawing checks that capture love.graphics calls made by host.render().
--

return function(t)
    if not (love and love.graphics and love.graphics.isCreated()) then
        t.skip("LOVE host tests need love.graphics")
        return
    end

    local Host = require "luif.love.host"
    local Interface = require "luif.host.interface"
    local conformance = require "tests.host_conformance"
    local lg = love.graphics

    local root = love.filesystem.getSource() .. "/.."
    conformance(t, Host.new(), "love", {
        texturePath = root .. "/example/images/button.png",
        readablePath = "conf.lua",
        readableContains = "t.identity",
    })

    local function near(a, b)
        return math.abs(a - b) < 1e-6
    end

    -- Renders the host with the drawing functions wrapped; returns the calls
    -- with their arguments, colour, scissor, shader and, for draw and
    -- rectangle, the screen rectangle { x, y, w, h }.
    local wrapped = { "draw", "rectangle", "print", "printf", "stencil" }
    local function capture(host)
        local calls = {}
        local saved = {}
        for _, name in ipairs(wrapped) do
            local original = lg[name]
            saved[name] = original
            lg[name] = function(...)
                local args = { ... }
                local r, g, b, a = lg.getColor()
                local sx, sy, sw, sh = lg.getScissor()
                local call = {
                    name = name, args = args, color = { r, g, b, a },
                    scissor = sx and { sx, sy, sw, sh } or false, shader = lg.getShader(),
                }
                local x, y, w, h
                if name == "rectangle" then
                    x, y, w, h = args[2], args[3], args[4], args[5]
                elseif name == "draw" then
                    local vw, vh, first
                    if type(args[2]) == "userdata" then
                        local _
                        _, _, vw, vh = args[2]:getViewport()
                        first = 3
                    else
                        vw, vh = args[1]:getDimensions()
                        first = 2
                    end
                    x, y = args[first], args[first + 1]
                    w, h = vw * args[first + 3], vh * args[first + 4]
                end
                if x then
                    local x0, y0 = lg.transformPoint(x, y)
                    local x1, y1 = lg.transformPoint(x + w, y + h)
                    call.rect = { x0, y0, x1 - x0, y1 - y0 }
                end
                calls[#calls + 1] = call
                return original(...)
            end
        end
        local ok, err = pcall(host.render)
        for name, original in pairs(saved) do
            lg[name] = original
        end
        assert(ok, err)
        return calls
    end

    local function only(calls, name)
        local list = {}
        for _, call in ipairs(calls) do
            if call.name == name then list[#list + 1] = call end
        end
        return list
    end

    local function sameRect(rect, x, y, w, h)
        return rect and near(rect[1], x) and near(rect[2], y) and near(rect[3], w) and near(rect[4], h)
    end

    -- Nine-slice: nine quads of one image into the nine rectangles.
    local host = Host.new()
    local tex = host.createTexture(16, 16)
    local region = host.textureRegion(tex, 2, 2, 12, 12)
    local n = host.createNode()
    host.attach(n)
    host.setTransform(n, 100, 50)
    host.setSize(n, 40, 30)
    host.setSlices(n, region, 4, 4, 4, 4)
    local draws = only(capture(host), "draw")
    t.eq(#draws, 9, "a nine-slice node draws nine quads")
    local expected = Interface.sliceRects(12, 12, 4, 4, 4, 4, 40, 30)
    local oneImage, quadsOk, rectsOk, distinct = true, true, true, {}
    for i, call in ipairs(draws) do
        local e = expected[i]
        if call.args[1] ~= tex.image then oneImage = false end
        local qx, qy, qw, qh = call.args[2]:getViewport()
        if qx ~= 2 + e[1] or qy ~= 2 + e[2] or qw ~= e[3] or qh ~= e[4] then quadsOk = false end
        if not sameRect(call.rect, 100 + e[5], 50 + e[6], e[7], e[8]) then rectsOk = false end
        distinct[call.args[2]] = true
    end
    local quadCount = 0
    for _ in pairs(distinct) do quadCount = quadCount + 1 end
    t.ok(oneImage, "all nine quads use the one image")
    t.eq(quadCount, 9, "nine different quads")
    t.ok(quadsOk, "quads cover the slices of the region")
    t.ok(rectsOk, "quads are drawn into the nine rectangles")

    host.setSize(n, 60, 30)
    draws = only(capture(host), "draw")
    t.ok(#draws == 9 and sameRect(draws[5].rect, 104, 54, 52, 22), "the centre follows a new size")
    host.setSlices(n, region, 4, 4, 4, 4, 0x80FFFFFF, true)
    draws = only(capture(host), "draw")
    t.ok(#draws == 9 and draws[1].shader ~= nil and near(draws[1].color[4], 128 / 255),
         "slices honour tint and grayscale")
    t.eq(lg.getShader(), nil, "render resets the shader")

    -- Axis aligned clips use the scissor and intersect.
    host = Host.new()
    local clipper = host.createNode()
    host.attach(clipper)
    host.setTransform(clipper, 10, 20)
    host.setSize(clipper, 50, 40)
    host.setClip(clipper, true)
    local big = host.createNode()
    host.attach(big, clipper)
    host.setTransform(big, -5, -5)
    host.setSize(big, 200, 200)
    host.setFill(big, 0xFFFFFFFF)
    local inner = host.createNode()
    host.attach(inner, clipper)
    host.setTransform(inner, 30, 30)
    host.setSize(inner, 100, 100)
    host.setClip(inner, true)
    local innerFill = host.createNode()
    host.attach(innerFill, inner)
    host.setSize(innerFill, 100, 100)
    host.setFill(innerFill, 0xFFFFFFFF)
    local rects = only(capture(host), "rectangle")
    t.eq(#rects, 2, "two fills drawn inside clips")
    local s1, s2 = rects[1] and rects[1].scissor, rects[2] and rects[2].scissor
    t.ok(s1 and s1[1] == 10 and s1[2] == 20 and s1[3] == 50 and s1[4] == 40,
         "a clipped node scissors to its box")
    t.ok(s2 and s2[1] == 40 and s2[2] == 50 and s2[3] == 20 and s2[4] == 10,
         "a nested clip intersects with its parent's")
    t.eq(lg.getScissor(), nil, "render restores the scissor")

    -- Rotated clips use a stencil.
    host.setTransform(clipper, 10, 20, 0.3)
    local calls = capture(host)
    t.eq(#only(calls, "stencil"), 4,
         "a rotated clip and its nested clip each write and clear a stencil")
    t.eq(#only(calls, "rectangle"), 6, "two stencil rectangles per clip plus the two fills")
    t.eq(lg.getStencilTest(), "always", "render resets the stencil test")

    -- Opacity cascade, draw order, visibility.
    host = Host.new()
    local parent = host.createNode()
    host.attach(parent)
    host.setSize(parent, 10, 10)
    host.setOpacity(parent, 0.5)
    host.setFill(parent, 0xFFFF0000)
    local child = host.createNode()
    host.attach(child, parent)
    host.setSize(child, 10, 10)
    host.setOpacity(child, 0.5)
    host.setFill(child, 0x8000FF00)
    rects = only(capture(host), "rectangle")
    t.eq(#rects, 2, "parent and child fills are drawn")
    t.ok(rects[1] and rects[1].color[1] == 1 and near(rects[1].color[4], 0.5),
         "the parent's content is drawn first with its opacity")
    t.ok(rects[2] and rects[2].color[2] == 1 and near(rects[2].color[4], 0.25 * 128 / 255),
         "the child's opacity multiplies with its parent's and the colour alpha")
    host.setVisible(parent, false)
    t.eq(#capture(host), 0, "an invisible node draws nothing, nor its subtree")
    host.setVisible(parent, true)
    host.setOpacity(parent, 0)
    t.eq(#capture(host), 0, "an opacity 0 node draws nothing, nor its subtree")
    host.setOpacity(parent, 1)
    local sibling = host.createNode()
    host.attach(sibling, parent, child)
    host.setSize(sibling, 10, 10)
    host.setFill(sibling, 0xFF0000FF)
    rects = only(capture(host), "rectangle")
    t.ok(#rects == 3 and rects[2].color[3] == 1 and rects[3].color[2] == 1,
         "children draw in child order")

    -- Images: stretch, flips and grayscale.
    host = Host.new()
    local image = host.createNode()
    host.attach(image)
    host.setTransform(image, 5, 5)
    host.setSize(image, 20, 10)
    local small = host.createTexture(4, 2)
    host.setImage(image, small)
    draws = only(capture(host), "draw")
    t.ok(#draws == 1 and sameRect(draws[1].rect, 5, 5, 20, 10) and draws[1].shader == nil,
         "an image is stretched over the box")
    host.setImage(image, small, 0xFFFFFFFF, true, false, true)
    draws = only(capture(host), "draw")
    t.ok(#draws == 1 and sameRect(draws[1].rect, 25, 5, -20, 10), "flipX mirrors within the box")
    t.ok(draws[1] and draws[1].shader ~= nil, "grayscale images use a shader")

    -- Fill with a border: one fill and four border rectangles inside the box.
    host.setFill(image, 0xFF000000, 0xFFFFFFFF, 2)
    rects = only(capture(host), "rectangle")
    t.eq(#rects, 5, "a bordered fill draws five rectangles")
    t.ok(rects[2] and sameRect(rects[2].rect, 5, 5, 20, 2) and sameRect(rects[5].rect, 23, 7, 2, 6),
         "the border is drawn inside the box")

    -- Text: measurement matches the font, wrap and alignment reach printf.
    local font = host.loadFont { size = 14 }
    local sentence = "The quick brown fox jumps over the lazy dog"
    local widest, lines = host.wrapText(font, sentence, 60)
    local fontWidest, fontLines = font.font:getWrap(sentence, 60)
    t.ok(near(widest, fontWidest) and #lines == #fontLines and #lines > 1,
         "wrapText matches Font:getWrap")
    t.ok(near(host.lineHeight(font), font.font:getHeight() * font.font:getLineHeight()),
         "lineHeight matches the font")
    host.setSize(image, 60, 100)
    host.setText(image, font, sentence, 0xFF000000, "center", true)
    local prints = only(capture(host), "printf")
    t.ok(#prints == 1 and prints[1].args[4] == 60 and prints[1].args[5] == "center",
         "wrapped text is printed with the box width and alignment")
    host.setSize(image, 200, 20)
    host.setText(image, font, "Hi", 0xFF000000, "center")
    prints = only(capture(host), "print")
    t.ok(#prints == 1 and near(prints[1].args[2], (200 - host.textWidth(font, "Hi")) / 2),
         "a single line is aligned within the box width")
    host.setText(image, font, "Hi\nthere", 0xFF000000, "right")
    prints = only(capture(host), "printf")
    local block = host.textWidth(font, "there")
    t.ok(#prints == 1 and near(prints[1].args[2], 200 - block) and prints[1].args[5] == "right",
         "unwrapped lines are aligned against each other within the box")
    host.setText(image, font, { 0xFFFF0000, "red", 0xFF00FF00, "green" }, 0x80FFFFFF)
    prints = only(capture(host), "print")
    t.ok(#prints == 1 and type(prints[1].args[1]) == "table" and near(prints[1].color[4], 128 / 255),
         "colour runs are printed as coloured text with the colour's alpha")
    host.setText(image, host.loadFont { size = 14, shadow = { 1, 1, 0xFF000000 } }, "Hi")
    t.eq(#only(capture(host), "print"), 2, "a shadow font prints a shadow pass first")

    -- Input feed translation.
    local received = {}
    local function recorder(name)
        return function(...)
            local parts = { name }
            for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
            received[#received + 1] = table.concat(parts, " ")
        end
    end
    local sink = {}
    for _, fn in ipairs(Interface.feed) do sink[fn.name] = recorder(fn.name) end
    host.setInputSink(sink)
    local handlers = host.loveHandlers
    handlers.mousereleased(1, 1, 1)
    handlers.mousemoved(3, 4, 1, 1)
    handlers.mousepressed(5, 6, 1, false, 1)
    handlers.mousereleased(7, 8, 1, false, 1)
    handlers.mousepressed(9, 10, 2, false, 1)
    host.releaseLostButtons(function() return false end)
    handlers.wheelmoved(0, -1)
    handlers.keypressed("a", "a", true)
    handlers.keyreleased("a", "a")
    handlers.textinput("")
    handlers.textinput("\195\164")
    handlers.mousefocus(true)
    handlers.mousefocus(false)
    t.eq(table.concat(received, ","),
         "pointerMoved 3 4,pointerPressed 5 6 1,pointerReleased 7 8 1,pointerPressed 9 10 2,"
         .. "pointerReleased 9 10 2,wheel 0 -1,keyPressed a true,keyReleased a,"
         .. "textInput \195\164,pointerLeft",
         "love callbacks become feed calls; lost releases are synthesized")

    -- The LOVE host instance of luif.love, which core draws through.
    local B = require "luif.love"
    t.ok(Interface.check(B.host), "luif.love.host passes the interface check")
    local empty = Host.new()
    t.eq(#empty.topLevel(), 0, "a new LOVE host starts empty")
    t.eq(#capture(empty), 0, "rendering an empty host makes no drawing calls")
end
