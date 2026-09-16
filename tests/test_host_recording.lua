--
-- The recording host (host/recording.lua) and the helpers of
-- host/interface.lua. Plain Lua: also runs without LOVE through
-- `luajit tests/run_luajit.lua`.
--

return function(t)
    local Interface = require "luif.host.interface"
    local Recording = require "luif.host.recording"
    local conformance = require "tests.host_conformance"

    conformance(t, Recording.new {
        strictTextures = true,
        textureSizes = { ["images/button.png"] = { 32, 16 } },
        files = { ["conf.lua"] = "t.identity = \"luif_tests\"" },
    }, "recording", {
        texturePath = "images/button.png",
        readablePath = "conf.lua",
        readableContains = "t.identity",
    })

    local host = Recording.new {
        glyphWidth = 10, lineHeight = 20,
        textureSizes = { button = { 32, 16 } },
    }

    -- The log
    local root = host.createNode()
    local child = host.createNode()
    host.attach(root)
    host.attach(child, root)
    host.setTransform(child, 10, 20)
    host.setSize(child, 30, 40)
    t.eq(host.count(), 6, "every call is logged")
    t.eq(host.count("structure"), 4, "count by group")
    t.eq(host.count("setSize"), 1, "count by function")
    local lines = host.logLines("structure")
    t.eq(lines[1], "createNode", "logLines without arguments")
    t.eq(lines[3], "attach node#1", "logLines with a node")
    t.eq(lines[4], "attach node#2 node#1", "logLines with two nodes")
    t.eq(host.logLines("properties")[1], "setTransform node#2 10 20", "logLines with numbers")
    t.eq(host.log()[6].op, "setSize", "log entries carry the function name")
    t.eq(host.log()[6].group, "properties", "log entries carry the group")
    host.inspect(child)
    host.topLevel()
    host.dump()
    t.eq(host.count(), 6, "inspection and helpers are not logged")
    host.resetLog()
    t.eq(host.count(), 0, "resetLog clears the log")

    -- Textures
    local tex = host.loadTexture("images/button.png")
    local w, h = host.textureSize(tex)
    t.ok(w == 32 and h == 16, "texture size from the size table by base name")
    w, h = host.textureSize(host.loadTexture("images/other.png"))
    t.ok(w == 16 and h == 16, "default texture size")
    t.eq(host.loadTexture("images/button.png"), tex, "loadTexture caches per path")
    local strict = Recording.new { strictTextures = true }
    local missing, message = strict.loadTexture("x.png")
    t.ok(missing == nil and type(message) == "string", "strict textures fail for unknown paths")
    t.eq(host.logLines("resources")[1], "loadTexture \"images/button.png\"", "logLines with strings")

    -- Dump
    host.setSlices(child, tex, 4, 4, 4, 4)
    host.setOpacity(child, 0.5)
    host.setClip(child, true)
    local label = host.createNode()
    host.attach(label, child)
    host.setText(label, host.loadFont { size = 14, name = "Text" }, "Hi", 0xFF000000, "center", true)
    t.eq(host.dump(),
         "node#1 pos=0,0 size=0x0\n"
         .. "  node#2 pos=10,20 size=30x40 opacity=0.5 clip slices=button insets=4,4,4,4 tint=FFFFFFFF\n"
         .. "    node#3 pos=0,0 size=0x0 text=\"Hi\" font=Text:14 color=FF000000 align=center wrap",
         "dump of the whole scene")
    host.setTransform(label, 1, 2, 0.5, 2, 3, 4)
    host.setVisible(label, false)
    host.setImage(label, host.textureRegion(tex, 0, 0, 8, 8), nil, true)
    t.eq(host.dump(label),
         "node#3 pos=1,2 size=0x0 rotation=0.5 scale=2 origin=3,4 hidden image=button@0,0+8x8 tint=FFFFFFFF flipX",
         "dump of a subtree with a transform and a region image")
    host.setFill(label, nil, 0xFFFFFFFF, 2)
    t.ok(host.dump(label):find("fill=none border=FFFFFFFF/2", 1, true) ~= nil, "dump of a border fill")
    host.setText(label, host.loadFont { size = 14, name = "Text" }, { 0xFFFF0000, "a", 0xFF00FF00, "b" })
    t.ok(host.dump(label):find("text=\"ab\" runs", 1, true) ~= nil, "dump of colour runs")

    -- Text metrics
    local font = host.loadFont {}
    t.eq(host.textWidth(font, "abc"), 30, "text width is glyphWidth per codepoint")
    t.eq(host.textWidth(font, "p\195\164ss"), 40, "text width counts codepoints, not bytes")
    t.eq(host.lineHeight(font), 20, "lineHeight option")
    local widest, wrapped = host.wrapText(font, "aa bb cc", 50)
    t.ok(#wrapped == 2 and wrapped[1] == "aa bb" and wrapped[2] == "cc" and widest == 50,
         "greedy wrap at spaces")
    widest, wrapped = host.wrapText(font, "toolongword x", 30)
    t.ok(#wrapped == 2 and wrapped[1] == "toolongword" and widest == 110,
         "words longer than the width are not split")
    widest, wrapped = host.wrapText(font, "a\n\nb", 100)
    t.ok(#wrapped == 3 and wrapped[2] == "", "empty lines are kept")
    widest, wrapped = host.wrapText(font, "", 100)
    t.ok(widest == 0 and #wrapped == 0, "empty text has no lines")

    -- System
    host.setTime(1000)
    t.eq(host.time(), 1000, "setTime")
    host.advance(16)
    t.eq(host.time(), 1016, "advance")
    host.setScreenSize(800, 600)
    w, h = host.screenSize()
    t.ok(w == 800 and h == 600, "setScreenSize")
    host.setCursor("hand")
    t.eq(host.cursor(), "hand", "setCursor stores the cursor")
    host.setCursor("bogus")
    t.eq(host.cursor(), "arrow", "unknown cursors select the arrow")
    local reader = Recording.new { readFile = function(path) if path == "x" then return "y" end end }
    t.eq(reader.readFile("x"), "y", "readFile falls back to the readFile option")

    -- Input feed
    local received = {}
    host.setInputSink {
        pointerPressed = function(x, y, button)
            received[#received + 1] = string.format("press %d %d %d", x, y, button)
        end,
        keyPressed = function(key, isRepeat)
            received[#received + 1] = "key " .. key .. " " .. tostring(isRepeat)
        end,
    }
    host.feed("pointerPressed", 5, 6, 1)
    host.feed("pointerMoved", 7, 8)
    host.feed("keyPressed", "a", false)
    t.eq(table.concat(received, ","), "press 5 6 1,key a false", "feed calls the sink, skipping missing functions")
    local px, py = host.pointerPosition()
    t.ok(px == 7 and py == 8, "feed tracks the pointer position")
    t.eq(host.isKeyDown("a"), true, "feed tracks held keys")
    host.feed("keyReleased", "a")
    t.eq(host.isKeyDown("a"), false, "released keys are up")
    t.raises(function() host.feed("mouseMoved", 1, 2) end, "unknown feed names raise")

    -- Batches
    host.beginBatch()
    t.raises(host.beginBatch, "batches do not nest")
    host.endBatch()
    t.raises(host.endBatch, "endBatch without beginBatch raises")

    -- Capability overrides
    local plain = Recording.new { capabilities = { rotatedClip = false, batch = false } }
    local caps = Interface.capabilities(plain)
    t.ok(not caps.rotatedClip and not caps.batch and caps.inspect, "capability overrides")
    t.eq(plain.beginBatch, nil, "a host without batch has no batch functions")
    t.ok(Interface.check(plain), "a host without optional capabilities passes the check")

    -- Interface.check
    local broken = { capabilities = function() return { batch = true, teleport = true } end }
    local ok, problems = Interface.check(broken)
    local text = table.concat(problems, "\n")
    t.eq(ok, false, "check fails for a broken host")
    t.ok(text:find("missing structure function createNode", 1, true) ~= nil, "check reports missing functions")
    t.ok(text:find("capability batch claimed without function beginBatch", 1, true) ~= nil,
         "check reports claimed capabilities without functions")
    t.ok(text:find("unknown capability teleport", 1, true) ~= nil, "check reports unknown capabilities")

    local documented = true
    for _, group in ipairs(Interface.groups) do
        for _, fn in ipairs(group.functions) do
            if type(fn.params) ~= "string" or type(fn.required) ~= "boolean" then
                documented = false
            end
            if not fn.required and not fn.capability then
                documented = false
            end
        end
    end
    t.ok(documented, "every function has params, a required flag, and optional ones a capability")

    -- Colours
    t.eq(Interface.color(-16777216), 0xFF000000, "negative colours are normalized")
    t.eq(Interface.color(nil, 0xFFFFFFFF), 0xFFFFFFFF, "nil colours take the default")
    local r, g, b, a = Interface.unpackColor(0x80FF4000)
    t.ok(r == 1 and math.abs(g - 64 / 255) < 1e-9 and b == 0 and math.abs(a - 128 / 255) < 1e-9,
         "unpackColor")

    -- Nine-slice geometry
    local function same(rect, expected)
        for i = 1, 8 do
            if math.abs(rect[i] - expected[i]) > 1e-9 then return false end
        end
        return true
    end
    local rects = Interface.sliceRects(12, 12, 4, 4, 4, 4, 40, 30)
    t.ok(same(rects[1], { 0, 0, 4, 4, 0, 0, 4, 4 }), "slice 1: top left corner keeps its size")
    t.ok(same(rects[2], { 4, 0, 4, 4, 4, 0, 32, 4 }), "slice 2: top edge stretches horizontally")
    t.ok(same(rects[5], { 4, 4, 4, 4, 4, 4, 32, 22 }), "slice 5: centre stretches both ways")
    t.ok(same(rects[6], { 8, 4, 4, 4, 36, 4, 4, 22 }), "slice 6: right edge stretches vertically")
    t.ok(same(rects[9], { 8, 8, 4, 4, 36, 26, 4, 4 }), "slice 9: bottom right corner")
    rects = Interface.sliceRects(12, 12, 4, 4, 4, 4, 4, 30)
    t.ok(same(rects[1], { 0, 0, 4, 4, 0, 0, 2, 4 }) and same(rects[2], { 4, 0, 4, 4, 2, 0, 0, 4 })
         and same(rects[3], { 8, 0, 4, 4, 2, 0, 2, 4 }),
         "a box narrower than the insets shrinks the corners and empties the middle")
end
