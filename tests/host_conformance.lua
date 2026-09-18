--
-- Conformance tests for the retained host interface (host/interface.lua),
-- run against every host. Plain Lua; pass a fresh host that supports the
-- inspect capability:
--
--   require("tests.host_conformance")(t, host, "label", {
--       texturePath = path,        -- a texture loadTexture can load
--       readablePath = path,       -- a file readFile can read ...
--       readableContains = text,   -- ... containing this text
--   })
--

local Interface = require "luif.host.interface"

return function(t, host, label, fixtures)
    fixtures = fixtures or {}

    local function L(text)
        return label .. ": " .. text
    end

    --
    -- Shape and capabilities
    --

    local ok, problems = Interface.check(host)
    t.ok(ok, L("Interface.check (" .. table.concat(problems or {}, "; ") .. ")"))

    local caps = Interface.capabilities(host)
    local reported = true
    for _, cap in ipairs(Interface.capabilityList) do
        if type(caps[cap.name]) ~= "boolean" then reported = false end
    end
    t.ok(reported, L("every capability is reported as a boolean"))
    t.eq(type(host.capabilities()), "table", L("capabilities() returns a table"))

    if not caps.inspect then
        t.skip(L("no inspect capability, structure and content checks skipped"))
        return
    end
    local inspect = host.inspect

    local names = {}
    local function node(name)
        local n = host.createNode()
        names[n] = name
        return n
    end
    -- Nodes made elsewhere (a host shared with other tests) are left out
    local function order(list)
        local parts = {}
        for i = 1, #list do parts[#parts + 1] = names[list[i]] end
        return table.concat(parts, " ")
    end
    local function childOrder(n)
        return order(inspect(n).children)
    end
    local function topOrder()
        return order(host.topLevel())
    end

    --
    -- Structure
    --

    local a = node("a")
    local s = inspect(a)
    t.ok(s.parent == nil and not s.topLevel and not s.inScene, L("a new node is detached"))
    t.eq(#s.children, 0, L("a new node has no children"))
    t.ok(s.x == 0 and s.y == 0 and s.rotation == 0 and s.scale == 1
         and s.originX == 0 and s.originY == 0, L("a new node has the identity transform"))
    t.ok(s.width == 0 and s.height == 0, L("a new node has size 0 x 0"))
    t.ok(s.opacity == 1 and s.visible == true and s.clip == false,
         L("a new node is opaque, visible and not clipping"))
    t.eq(s.content, false, L("a new node has no content"))
    t.eq(topOrder(), "", L("a new node is not top level"))

    local b = node("b")
    host.attach(a)
    host.attach(b)
    t.eq(topOrder(), "a b", L("attach without parent appends to the top level"))
    s = inspect(a)
    t.ok(s.parent == nil and s.topLevel and s.inScene, L("a top level node is in the scene"))

    local p = node("p")
    host.attach(p, nil, a)
    t.eq(topOrder(), "p a b", L("attach at the top level before nextSibling"))

    local c0, c1, c2, c3 = node("c0"), node("c1"), node("c2"), node("c3")
    host.attach(c1, p)
    host.attach(c3, p)
    host.attach(c2, p, c3)
    t.eq(childOrder(p), "c1 c2 c3", L("attach before nextSibling"))
    host.attach(c0, p, c1)
    t.eq(childOrder(p), "c0 c1 c2 c3", L("attach before the first child"))
    s = inspect(c2)
    t.ok(s.parent == p and s.inScene and not s.topLevel, L("an attached child knows its parent"))

    host.attach(c3, p, c0)
    t.eq(childOrder(p), "c3 c0 c1 c2", L("attaching an attached node moves it"))
    host.attach(c3, p)
    t.eq(childOrder(p), "c0 c1 c2 c3", L("attaching without nextSibling moves to the end"))
    host.attach(c1, a)
    t.eq(childOrder(p), "c0 c2 c3", L("reparenting removes the node from the old parent"))
    t.eq(childOrder(a), "c1", L("reparenting appends to the new parent"))
    host.attach(b, p, c2)
    t.eq(topOrder(), "p a", L("a top level node attached under a parent leaves the top level"))
    t.eq(childOrder(p), "c0 b c2 c3", L("and is inserted before nextSibling"))

    t.raises(function() host.attach(p, p) end, L("attaching a node under itself raises"))
    t.raises(function() host.attach(p, c2) end, L("attaching a node under its subtree raises"))
    t.raises(function() host.attach(c0, p, c1) end, L("a nextSibling of another parent raises"))
    t.raises(function() host.attach(c0, p, c0) end, L("nextSibling equal to the node raises"))
    t.eq(childOrder(p), "c0 b c2 c3", L("failed attaches leave the tree unchanged"))
    t.eq(topOrder(), "p a", L("failed attaches leave the top level unchanged"))

    local g = node("g")
    host.attach(g, c2)
    host.setTransform(c2, 5, 6)
    host.setSize(c2, 7, 8)
    host.setFill(c2, 0xFF00FF00)
    host.detach(c2)
    t.eq(childOrder(p), "c0 b c3", L("detach removes the node from its parent"))
    s = inspect(c2)
    t.ok(s.parent == nil and not s.topLevel and not s.inScene, L("a detached node has no parent"))
    t.eq(childOrder(c2), "g", L("a detached node keeps its children"))
    t.ok(inspect(g).parent == c2 and not inspect(g).inScene,
         L("the subtree of a detached node is out of the scene"))
    t.ok(s.x == 5 and s.y == 6 and s.width == 7 and s.height == 8,
         L("a detached node keeps its properties"))
    t.ok(s.content and s.content.kind == "fill" and s.content.color == 0xFF00FF00,
         L("a detached node keeps its content"))
    t.ok(pcall(host.detach, c2), L("detaching a detached node does nothing"))
    host.attach(c2, p, c3)
    t.eq(childOrder(p), "c0 b c2 c3", L("a detached node can be attached again"))
    t.ok(inspect(g).inScene, L("re-attaching brings the subtree back into the scene"))
    host.detach(a)
    t.eq(topOrder(), "p", L("detach removes a top level node"))
    host.attach(a)
    t.eq(topOrder(), "p a", L("a detached top level node can be attached again"))

    host.destroyNode(p)
    t.eq(topOrder(), "a", L("destroyNode removes the node from the top level"))
    t.raises(function() host.setSize(p, 1, 1) end, L("a destroyed node cannot be used"))
    t.raises(function() host.setSize(g, 1, 1) end, L("a grandchild of a destroyed node is destroyed"))
    t.raises(function() host.attach(c0, a) end, L("a destroyed child cannot be attached"))
    t.raises(function() host.attach(a, c3) end, L("a destroyed node cannot be a parent"))
    t.eq(childOrder(a), "c1", L("nodes outside the destroyed subtree are unaffected"))
    host.destroyNode(c1)
    t.eq(childOrder(a), "", L("destroying a child removes it from its parent"))
    local loose = node("loose")
    host.destroyNode(loose)
    t.raises(function() host.attach(loose) end, L("a detached node can be destroyed"))

    --
    -- Properties
    --

    local n = node("n")
    host.setTransform(n, 10, 20, 0.5, 2, 3, 4)
    s = inspect(n)
    t.ok(s.x == 10 and s.y == 20 and s.rotation == 0.5 and s.scale == 2
         and s.originX == 3 and s.originY == 4, L("setTransform stores every value"))
    host.setTransform(n, 1, 2)
    s = inspect(n)
    t.ok(s.x == 1 and s.y == 2 and s.rotation == 0 and s.scale == 1
         and s.originX == 0 and s.originY == 0, L("setTransform defaults"))
    host.setSize(n, 30.5, 40)
    host.setOpacity(n, 0.25)
    host.setVisible(n, false)
    host.setClip(n, true)
    s = inspect(n)
    t.ok(s.width == 30.5 and s.height == 40, L("setSize"))
    t.eq(s.opacity, 0.25, L("setOpacity"))
    t.ok(s.visible == false and s.clip == true, L("setVisible and setClip"))
    host.setVisible(n, true)
    host.setClip(n, false)
    s = inspect(n)
    t.ok(s.visible == true and s.clip == false, L("setVisible and setClip back"))

    --
    -- Resources used by content
    --

    local tex = host.createTexture(8, 4)
    local tw, th = host.textureSize(tex)
    t.ok(tw == 8 and th == 4, L("createTexture and textureSize"))
    local region = host.textureRegion(tex, 2, 1, 4, 3)
    tw, th = host.textureSize(region)
    t.ok(tw == 4 and th == 3, L("textureRegion size"))
    tw, th = host.textureSize(host.textureRegion(region, 1, 1, 2, 2))
    t.ok(tw == 2 and th == 2, L("region of a region"))
    local font = host.loadFont { size = 12 }
    t.eq(host.loadFont { size = 12 }, font, L("loadFont returns the same handle for equal specs"))

    if fixtures.texturePath then
        local loaded = host.loadTexture(fixtures.texturePath)
        t.ok(loaded ~= nil, L("loadTexture loads an existing texture"))
        t.eq(host.loadTexture(fixtures.texturePath), loaded, L("loadTexture caches per path"))
        local lw, lh = host.textureSize(loaded)
        t.ok(lw > 0 and lh > 0, L("a loaded texture has a size"))
    end
    local missing, message = host.loadTexture("no/such/texture.png")
    t.ok(missing == nil and type(message) == "string", L("loadTexture of a missing file returns nil and a message"))

    --
    -- Content
    --

    host.setImage(n, tex, 0x80FF0000, true, false)
    local c = inspect(n).content
    t.ok(c and c.kind == "image" and c.texture == tex and c.tint == 0x80FF0000
         and c.flipX == true and c.flipY == false and c.grayscale == false,
         L("setImage stores texture, tint and flips"))
    host.setImage(n, region)
    c = inspect(n).content
    t.ok(c.texture == region and c.tint == 0xFFFFFFFF and not c.flipX and not c.flipY,
         L("setImage defaults"))
    host.setImage(n, tex, -1, false, true, true)
    c = inspect(n).content
    t.ok(c.tint == 0xFFFFFFFF and c.flipY == true and c.grayscale == true,
         L("negative int32 colours are normalized; flipY and grayscale"))

    host.setSlices(n, tex, 1, 2, 3, 1)
    c = inspect(n).content
    t.ok(c.kind == "slices" and c.texture == tex and c.left == 1 and c.top == 2
         and c.right == 3 and c.bottom == 1 and c.tint == 0xFFFFFFFF and c.grayscale == false,
         L("setSlices replaces the image and stores insets"))

    host.setText(n, font, "Hello", 0xFF000000, "center", true)
    c = inspect(n).content
    t.ok(c.kind == "text" and c.font == font and c.text == "Hello" and c.color == 0xFF000000
         and c.align == "center" and c.wrap == true, L("setText stores font, text, colour, alignment and wrap"))
    host.setText(n, font, 42)
    c = inspect(n).content
    t.ok(c.text == "42" and c.color == 0xFFFFFFFF and c.align == "left" and c.wrap == false,
         L("setText defaults"))
    local runs = { 0xFFFF0000, "red", 0xFF00FF00, "green" }
    host.setText(n, font, runs, 0x80FFFFFF)
    c = inspect(n).content
    t.ok(type(c.text) == "table" and #c.text == 4 and c.text[1] == 0xFFFF0000
         and c.text[2] == "red" and c.text[3] == 0xFF00FF00 and c.text[4] == "green",
         L("setText stores colour runs"))
    runs[2] = "changed"
    t.eq(inspect(n).content.text[2], "red", L("the host keeps its own copy of the runs"))
    t.raises(function() host.setText(n, font, "x", nil, "middle") end,
             L("setText rejects unknown alignments"))

    host.setFill(n, 0xFF112233, 0xFFFFFFFF, 2)
    c = inspect(n).content
    t.ok(c.kind == "fill" and c.color == 0xFF112233 and c.borderColor == 0xFFFFFFFF
         and c.borderWidth == 2, L("setFill with a border"))
    host.setFill(n, nil, 0xFF000000)
    c = inspect(n).content
    t.ok(c.color == false and c.borderColor == 0xFF000000 and c.borderWidth == 1,
         L("setFill with only a border defaults to width 1"))
    host.setFill(n, 0xFF112233)
    c = inspect(n).content
    t.ok(c.color == 0xFF112233 and c.borderColor == false and c.borderWidth == 0,
         L("setFill without a border"))

    host.setTransform(n, 3, 4)
    host.setSize(n, 5, 6)
    host.attach(n)
    host.detach(n)
    t.eq(inspect(n).content.kind, "fill", L("content survives property and structure changes"))
    host.clearContent(n)
    t.eq(inspect(n).content, false, L("clearContent removes the content"))
    t.ok(pcall(host.clearContent, n), L("clearContent without content does nothing"))

    --
    -- Text metrics
    --

    t.eq(host.textWidth(font, ""), 0, L("empty text has width 0"))
    t.ok(host.textWidth(font, "Hello") > host.textWidth(font, "He"), L("longer text is wider"))
    t.ok(host.lineHeight(font) > 0, L("lineHeight is positive"))
    local sentence = "The quick brown fox jumps over the lazy dog"
    local limit = host.textWidth(font, "quick brown")
    local widest, lines = host.wrapText(font, sentence, limit)
    t.ok(#lines > 1, L("wrapText breaks a long sentence"))
    t.ok(widest <= limit + 1e-6, L("wrapped lines fit the width"))
    local joined = table.concat(lines, " "):gsub("%s+", " "):gsub("^ ", ""):gsub(" $", "")
    t.eq(joined, sentence, L("wrapped lines keep every word in order"))
    widest, lines = host.wrapText(font, sentence, 1e6)
    t.eq(#lines, 1, L("text that fits stays on one line"))
    t.near(widest, host.textWidth(font, sentence), 1e-6, L("the widest of one line is its textWidth"))
    widest, lines = host.wrapText(font, "one\ntwo", 1e6)
    t.eq(#lines, 2, L("wrapText breaks at newlines"))

    --
    -- System and input
    --

    local t1 = host.time()
    local t2 = host.time()
    t.ok(type(t1) == "number" and t2 >= t1, L("time is a non-decreasing number"))
    local sw, sh = host.screenSize()
    t.ok(type(sw) == "number" and type(sh) == "number", L("screenSize returns two numbers"))
    host.setClipboard("host clipboard")
    t.eq(host.getClipboard(), "host clipboard", L("clipboard round trip"))
    t.ok(pcall(host.setCursor, "hand") and pcall(host.setCursor, nil)
         and pcall(host.setCursor, "bogus"), L("setCursor accepts names, nil and unknown names"))
    if fixtures.readablePath then
        local contents = host.readFile(fixtures.readablePath)
        t.ok(type(contents) == "string" and contents:find(fixtures.readableContains, 1, true) ~= nil,
             L("readFile reads a file"))
    end
    local none, why = host.readFile("no/such/file.txt")
    t.ok(none == nil and why ~= nil, L("readFile of a missing file returns nil and a message"))
    t.ok(pcall(host.setInputSink, {}) and pcall(host.setInputSink, nil), L("setInputSink"))

    if caps.batch then
        t.ok(pcall(host.beginBatch) and pcall(host.endBatch), L("beginBatch and endBatch"))
    end
    if caps.pointerPosition then
        local px, py = host.pointerPosition()
        t.ok(type(px) == "number" and type(py) == "number", L("pointerPosition returns two numbers"))
    end
    if caps.keyState then
        t.eq(type(host.isKeyDown("a")), "boolean", L("isKeyDown returns a boolean"))
    end
end
