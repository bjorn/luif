--
-- The SDL host (sdl/): the interface conformance tests, and drawing checks
-- that read pixels back from a rendered frame. Runs under luif-sdl
-- (luif-sdl --inspect tests), which exposes app.capture and app.pixel.
--

return function(t)
    local host = package.loaded["luif.sdl"]
    if not host then
        t.skip("SDL host tests need luif-sdl")
        return
    end
    if not host.inspect then
        t.skip("SDL host tests need luif-sdl --inspect")
        return
    end

    local app = require "app"
    local conformance = require "tests.host_conformance"
    local root = package.loaded["tests.root"]

    conformance(t, host, "sdl", {
        texturePath = root .. "/example/images/button.png",
        readablePath = "conf.lua",
        readableContains = "t.identity",
    })

    --
    -- Argument normalization, as Interface.*Content and the LOVE host do it
    --

    do
        local font = host.loadFont { size = 16 }
        t.eq(host.textWidth(font, "\t"), host.textWidth(font, "    "), "sdl: a tab is four spaces wide")
        t.eq(host.textWidth(font, "a\tb"), host.textWidth(font, "a    b"), "sdl: also between letters")
        local _, lines = host.wrapText(font, "aa\tbb", host.textWidth(font, "aa") + 1)
        t.eq(#lines, 2, "sdl: a line wraps at a tab")
        t.eq(host.textWidth(font, "a\1b"), host.textWidth(font, "ab"), "sdl: other control characters take no space")

        local n = host.createNode()
        host.setText(n, font, {})
        local text = host.inspect(n).content.text
        t.ok(type(text) == "table" and #text == 0, "sdl: empty runs inspect as an empty array")
        host.setText(n, font, { 0xFFFF0000, false, nil, 12 })
        text = host.inspect(n).content.text
        t.eq(text[2], "false", "sdl: a run's string is converted like tostring")
        t.eq(text[3], 0xFFFFFFFF, "sdl: a run's colour defaults to white")
        t.eq(text[4], "12", "sdl: a number run becomes a string")
        host.setText(n, font, false)
        t.eq(host.inspect(n).content.text, "", "sdl: false as the text is the empty string")
        host.setText(n, font, "x", nil, false)
        t.eq(host.inspect(n).content.align, "left", "sdl: align false means left")
        t.ok(not pcall(host.setText, n, font, "x", nil, "middle"), "sdl: an unknown alignment raises")

        -- A __tostring that destroys the node must not leave setText writing to it
        local victim = host.createNode()
        local evil = setmetatable({}, { __tostring = function() host.destroyNode(victim) return "gone" end })
        t.ok(not pcall(host.setText, victim, font, { 0xFFFFFFFF, evil }),
             "sdl: setText raises when its node is destroyed during conversion")
        host.destroyNode(n)

        local white = host.createTexture(2, 2, false)
        local w, h = host.textureSize(white)
        t.ok(w == 2 and h == 2, "sdl: createTexture takes false for no pixel function")

        local handle = host.createNode()
        t.ok(handle == math.floor(handle) and host.inspect(handle), "sdl: handles are whole numbers")
        t.ok(not pcall(host.inspect, handle + 0.5), "sdl: a fractional handle is invalid")
        host.destroyNode(handle)
        t.ok(not pcall(host.inspect, handle), "sdl: a destroyed handle is invalid")
        local reused = host.createNode()
        t.ok(reused ~= handle, "sdl: a reused slot gets another handle")
        host.destroyNode(reused)
    end

    -- Text input is on only while the framework says text is being edited
    t.eq(app.textInputActive(), false, "sdl: text input is off without a focused text field")
    host.setTextInput(true, 10, 20, 100, 24)
    t.eq(app.textInputActive(), true, "sdl: setTextInput starts text input")
    host.setTextInput(false)
    t.eq(app.textInputActive(), false, "sdl: and stops it")

    --
    -- Drawing: nodes on an opaque backdrop, read back with app.pixel
    --

    local function node(parent, x, y, width, height)
        local n = host.createNode()
        host.setTransform(n, x, y)
        host.setSize(n, width, height)
        host.attach(n, parent)
        return n
    end

    local function channels(color)
        return math.floor(color / 65536) % 256, math.floor(color / 256) % 256, color % 256
    end

    local function pixelIs(x, y, expected, label, tolerance)
        local r, g, b = channels(app.pixel(x, y))
        local er, eg, eb = channels(expected)
        tolerance = tolerance or 1
        local ok = math.abs(r - er) <= tolerance and math.abs(g - eg) <= tolerance
            and math.abs(b - eb) <= tolerance
        t.ok(ok, ("sdl: %s (%d, %d is %d,%d,%d, expected %d,%d,%d)"):format(label, x, y, r, g, b, er, eg, eb))
    end

    local stage = node(nil, 0, 0, 640, 480)
    host.setFill(stage, 0xFF000000)

    -- Fill, border, opacity cascade, visibility
    local box = node(stage, 10, 10, 40, 40)
    host.setFill(box, 0xFFFF0000, 0xFF00FF00, 2)
    local faded = node(stage, 60, 10, 40, 40)
    host.setOpacity(faded, 0.5)
    local inner = node(faded, 0, 0, 40, 40)
    host.setOpacity(inner, 0.5)
    host.setFill(inner, 0xFFFFFFFF)
    local hidden = node(stage, 110, 10, 40, 40)
    host.setFill(hidden, 0xFFFFFFFF)
    host.setVisible(hidden, false)
    local translucent = node(stage, 160, 10, 40, 40)
    host.setFill(translucent, 0x800000FF)

    -- Clip: the child sticks out of its clipping parent
    local clipper = node(stage, 10, 60, 40, 40)
    host.setClip(clipper, true)
    local wide = node(clipper, -20, 10, 100, 20)
    host.setFill(wide, 0xFFFFFF00)

    -- Rotation by 90 degrees around the centre turns a wide box upright
    local turned = node(stage, 100, 70, 60, 20)
    host.setTransform(turned, 100, 70, math.pi / 2, 1, 30, 10)
    host.setFill(turned, 0xFF00FFFF)

    -- Scale 2 around the top left
    local scaled = node(stage, 200, 60, 10, 10)
    host.setTransform(scaled, 200, 60, 0, 2, 0, 0)
    host.setFill(scaled, 0xFFFF00FF)

    -- Images: a generated texture (left half red, right half blue), tinted,
    -- flipped, a region of it, grayscale, and nearest filtering when stretched
    local halves = host.createTexture(4, 4, function(x) if x < 2 then return 255, 0, 0 end return 0, 0, 255 end)
    host.setTextureFilter("nearest", "nearest", halves)
    local image = node(stage, 10, 120, 40, 40)
    host.setImage(image, halves)
    local flipped = node(stage, 60, 120, 40, 40)
    host.setImage(flipped, halves, nil, true)
    local tinted = node(stage, 110, 120, 40, 40)
    host.setImage(tinted, halves, 0xFF808080)
    local region = node(stage, 160, 120, 40, 40)
    host.setImage(region, host.textureRegion(halves, 2, 0, 2, 4))
    local gray = node(stage, 210, 120, 40, 40)
    host.setImage(gray, halves, nil, false, false, true)

    -- Slices: a white texture with a one pixel black frame keeps the frame
    -- one pixel wide
    local framed = host.createTexture(8, 8, function(x, y)
        if x == 0 or y == 0 or x == 7 or y == 7 then return 0, 0, 0 end
        return 255, 255, 255
    end)
    host.setTextureFilter("nearest", "nearest", framed)
    local slices = node(stage, 10, 170, 60, 40)
    host.setSlices(slices, framed, 1, 1, 1, 1)

    -- Text: some pixels of the label are lit, and only inside its line
    local font = host.loadFont { size = 20 }
    local label = node(stage, 10, 220, 200, 40)
    host.setText(label, font, "MMMM", 0xFFFFFFFF)

    app.capture()

    pixelIs(30, 30, 0xFFFF0000, "fill")
    pixelIs(10, 30, 0xFF00FF00, "border inside the box")
    pixelIs(12, 30, 0xFFFF0000, "border is two wide")
    pixelIs(9, 30, 0xFF000000, "nothing outside the box")
    pixelIs(80, 30, 0xFF404040, "opacity multiplies down the tree", 2)
    pixelIs(130, 30, 0xFF000000, "an invisible node draws nothing")
    pixelIs(180, 30, 0xFF000080, "the alpha byte of a colour is honoured", 2)
    pixelIs(30, 80, 0xFFFFFF00, "a clipped child draws inside the clip")
    pixelIs(5, 80, 0xFF000000, "and not left of it")
    pixelIs(55, 80, 0xFF000000, "nor right of it")
    pixelIs(130, 55, 0xFF00FFFF, "a rotated box covers what was above it")
    pixelIs(105, 80, 0xFF000000, "and no longer its old left end")
    pixelIs(215, 75, 0xFFFF00FF, "a scaled box covers its scaled size")
    pixelIs(222, 75, 0xFF000000, "and nothing beyond")
    pixelIs(20, 140, 0xFFFF0000, "image, left half")
    pixelIs(40, 140, 0xFF0000FF, "image, right half")
    pixelIs(31, 140, 0xFF0000FF, "nearest filtering keeps the edge hard")
    pixelIs(28, 140, 0xFFFF0000, "on both sides")
    pixelIs(70, 140, 0xFF0000FF, "flipX mirrors the image")
    pixelIs(120, 140, 0xFF800000, "tint multiplies the image", 2)
    pixelIs(170, 140, 0xFF0000FF, "a region draws only its part")
    pixelIs(220, 140, 0xFF4C4C4C, "grayscale uses the luma of red", 2)
    pixelIs(240, 140, 0xFF1D1D1D, "and of blue", 2)
    pixelIs(10, 190, 0xFF000000, "slices keep the left edge")
    pixelIs(12, 190, 0xFFFFFFFF, "one pixel wide")
    pixelIs(40, 190, 0xFFFFFFFF, "and stretch the centre")
    pixelIs(69, 190, 0xFF000000, "slices keep the right edge")

    local lit, below = 0, 0
    for y = 220, 259 do
        for x = 10, 120 do
            local r = channels(app.pixel(x, y))
            if r > 128 then
                if y < 220 + host.lineHeight(font) then lit = lit + 1 else below = below + 1 end
            end
        end
    end
    t.ok(lit > 100, "sdl: text lights pixels (" .. lit .. ")")
    t.eq(below, 0, "sdl: and only within its line")

    -- Content survives a size change, and text follows alignment
    host.setText(label, font, "MMMM", 0xFFFFFFFF, "right")
    app.capture()
    local left = 0
    for y = 220, 245 do
        for x = 10, 100 do
            if channels(app.pixel(x, y)) > 128 then left = left + 1 end
        end
    end
    t.eq(left, 0, "sdl: right aligned text leaves the left of the box empty")

    host.destroyNode(stage)
    app.capture()
    local r, g, b = channels(app.pixel(30, 30))
    t.ok(not (r == 255 and g == 0 and b == 0), "sdl: a destroyed subtree is no longer drawn")

    -- The sink: false unregisters as nil does (the conformance tests left
    -- none registered)
    t.ok(pcall(host.setInputSink, false), "sdl: setInputSink takes false")
    t.ok(not pcall(host.setInputSink, 1), "sdl: and rejects what is not a table")
end
