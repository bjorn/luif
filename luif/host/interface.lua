--
-- The retained host interface. A host (such as the LOVE host in luif/love/)
-- keeps a scene of nodes and renders it on its own; the
-- framework only changes that scene when something changed. This module is
-- the contract, as data, plus a few plain Lua helpers every host shares.
-- It never touches love, io or os, so it loads under plain LuaJIT.
--
-- Hosts in this repository:
--   luif/love/host.lua     the LOVE host (renders with love.graphics)
--   sdl/                   the SDL3 host, in C++ (renders with an SDL_Renderer)
--   host/recording.lua     plain Lua; stores node state and logs every call
--
-- A host is a table of plain functions (host.createNode(), not methods).
-- An application gives core its host once with luif.setHost(host);
-- core takes every platform service (time, screen size, clipboard, cursor,
-- textures, fonts, text measuring, file reading) from it.
--
-- Conventions
--
--   Handles     nodes, textures and fonts are opaque host values with stable
--               identity; the framework may use them as table keys.
--   Numbers     a host may keep node properties in single precision.
--   Units       positions and sizes are in the parent node's units. Top level
--               nodes are in window pixels, and so are input positions and
--               screenSize(). A UI scale is a scale on a root node
--               (core/sync.lua applies Screen.scale there).
--   Axes        origin top left, y down, rotations in radians, clockwise on
--               screen.
--   Colours     packed 0xAARRGGBB numbers. Negative int32 values are accepted
--               and mean the same bits. The alpha byte is honoured.
--   Opacity     0..1, multiplies down the tree (opacity cascade). A node with
--               effective opacity 0 draws nothing, nor does its subtree.
--   Visibility  an invisible node draws neither its content nor its subtree.
--   Transform   a node's local transform is
--                   T(x, y) * T(originX, originY) * R(rotation) * S(scale)
--                       * T(-originX, -originY)
--               and its world transform is parentWorld * local.
--   Size        the node's box is (0, 0, width, height) in local units. Content
--               fills the box, and clipping uses it.
--   Clip        a clipping node clips its content and its whole subtree to its
--               transformed box. Nested clips intersect. Hosts without the
--               rotatedClip capability clip to the box's axis aligned bounds.
--   Content     at most one per node: image, slices (nine-slice), text or
--               fill. Setting any content replaces the previous one, whatever
--               its kind; clearContent removes it. Content survives transform,
--               size and structure changes.
--   Draw order  a node draws its content, then its children in child order;
--               the last child is on top. Top level nodes draw in their order.
--   Structure   createNode makes a detached node. attach inserts it under a
--               parent (nil for the top level) before nextSibling (nil to
--               append); an attached node is moved. detach removes a node from
--               its parent and keeps it with its subtree, properties and
--               content, so it can be attached again. destroyNode detaches and
--               releases the node and its whole subtree; destroyed nodes must
--               not be used again (hosts may raise).
--   Input       the host feeds input to a sink the framework registers with
--               setInputSink, in window pixels, with named keys. The host
--               never picks: hit testing is the framework's job.
--
-- Text: every string of text is UTF-8. Text the framework passes to a host
-- (setText, textWidth, wrapText) comes from the application, and a host may
-- raise on invalid UTF-8 or replace it. Text a host delivers (textInput,
-- getClipboard) has to be valid.
--
-- Frame protocol: the host feeds pending input to the sink, then calls the
-- framework's update (timers, effects, layout, then one flush of node
-- changes, optionally inside beginBatch/endBatch), then renders its retained
-- scene. Rendering is host internal and not part of this interface (the LOVE
-- host exposes host.render() for love.draw).
--

local floor = math.floor

local Interface = {}

Interface.version = 1

-- Every host function, grouped. Fields: name, required, params, returns, doc.
Interface.groups = {
    {
        name = "structure",
        functions = {
            { name = "createNode", required = true, params = "()", returns = "node",
              doc = "A detached node: position 0, 0, rotation 0, scale 1, origin 0, 0, "
                 .. "size 0 x 0, opacity 1, visible, not clipping, no content." },
            { name = "destroyNode", required = true, params = "(node)",
              doc = "Detaches the node and releases it and its whole subtree." },
            { name = "attach", required = true, params = "(node, parent, nextSibling)",
              doc = "Inserts node under parent (nil: top level) before nextSibling (nil: "
                 .. "append). nextSibling must be a child of parent other than node. An "
                 .. "attached node is moved. Attaching a node under itself or its own "
                 .. "subtree is an error." },
            { name = "detach", required = true, params = "(node)",
              doc = "Removes node from its parent or the top level; it keeps its subtree, "
                 .. "properties and content. Detaching a detached node does nothing." },
        },
    },
    {
        name = "properties",
        functions = {
            { name = "setTransform", required = true,
              params = "(node, x, y, rotation, scale, originX, originY)",
              doc = "Position in parent units, rotation in radians (default 0), uniform "
                 .. "scale (default 1), transform origin in local units (default 0, 0)." },
            { name = "setSize", required = true, params = "(node, width, height)",
              doc = "The node's box (0, 0, width, height) for content and clipping." },
            { name = "setOpacity", required = true, params = "(node, opacity)",
              doc = "0..1, multiplied down the tree." },
            { name = "setVisible", required = true, params = "(node, visible)",
              doc = "An invisible node draws neither its content nor its subtree." },
            { name = "setClip", required = true, params = "(node, clip)",
              doc = "Clips content and subtree to the node's transformed box." },
        },
    },
    {
        name = "content",
        functions = {
            { name = "setImage", required = true,
              params = "(node, texture, tint, flipX, flipY, grayscale)",
              doc = "Draws texture stretched over the box, multiplied by tint (default "
                 .. "0xFFFFFFFF), mirrored within the box by the flips. grayscale is "
                 .. "honoured with the grayscale capability, otherwise ignored." },
            { name = "setSlices", required = true,
              params = "(node, texture, left, top, right, bottom, tint, grayscale)",
              doc = "A nine-slice of one texture (or region) with insets in texture "
                 .. "pixels: corners keep their size, edges stretch along one axis, the "
                 .. "centre stretches both ways (see Interface.sliceRects)." },
            { name = "setText", required = true,
              params = "(node, font, text, color, align, wrap)",
              doc = "text is a string or a runs array { color, string, color, string, ... } "
                 .. "whose colours replace color (only color's alpha byte applies to runs). "
                 .. "Lines start at the top of the box, one lineHeight apart. align is "
                 .. "\"left\" (default), \"center\" or \"right\" within the box width. With "
                 .. "wrap, lines wrap at the box width as wrapText does; without, lines break "
                 .. "only at \"\\n\" and the block of lines is aligned within the width." },
            { name = "setFill", required = true, params = "(node, color, borderColor, borderWidth)",
              doc = "Fills the box with color (nil: no fill) and draws a border of "
                 .. "borderWidth (default 1 when borderColor is given) inside the box." },
            { name = "clearContent", required = true, params = "(node)",
              doc = "Removes the node's content, if any." },
        },
    },
    {
        name = "resources",
        functions = {
            { name = "loadTexture", required = true, params = "(path)",
              returns = "texture or nil, message",
              doc = "Loads an image; cached per path, so equal paths give the same handle." },
            { name = "createTexture", required = true, params = "(width, height, pixel)",
              returns = "texture",
              doc = "A generated texture; pixel(x, y) returns r, g, b, a in 0..255 (a "
                 .. "defaults to 255). Without pixel the texture is opaque white." },
            { name = "textureRegion", required = true, params = "(texture, x, y, width, height)",
              returns = "texture",
              doc = "A sub rectangle, in the texture's own pixels; regions of regions work." },
            { name = "textureSize", required = true, params = "(texture)", returns = "width, height" },
            { name = "loadFont", required = true, params = "(spec)", returns = "font",
              doc = "spec = { file = path or false, size = n, shadow = { dx, dy, color }, "
                 .. "outline = { color }, name = optional }. Equal specs give the same handle." },
            { name = "textWidth", required = true, params = "(font, text)", returns = "width",
              doc = "Width of a single line of text." },
            { name = "lineHeight", required = true, params = "(font)", returns = "height",
              doc = "Vertical advance between two lines." },
            { name = "wrapText", required = true, params = "(font, text, width)",
              returns = "widest, lines",
              doc = "Word wraps text at width; returns the widest line's width and the lines." },
            { name = "setTextureFilter", required = false, params = "(min, mag, texture)",
              capability = "textureFilter",
              doc = "\"linear\" or \"nearest\" for every texture, or for one texture (and "
                 .. "the regions that share its image) when given." },
        },
    },
    {
        name = "system",
        functions = {
            { name = "time", required = true, params = "()", returns = "milliseconds",
              doc = "Monotonic clock, the one the host passes to the framework's update." },
            { name = "screenSize", required = true, params = "()", returns = "width, height",
              doc = "Window size in pixels." },
            { name = "getClipboard", required = true, params = "()", returns = "text",
              doc = "The clipboard text as valid UTF-8 (the host replaces or drops "
                 .. "anything else), \"\" when there is none." },
            { name = "setClipboard", required = true, params = "(text)" },
            { name = "setCursor", required = true, params = "(name)",
              doc = "One of Interface.cursors; nil or an unknown name selects \"arrow\"." },
            { name = "readFile", required = true, params = "(path)",
              returns = "contents or nil, message" },
            { name = "capabilities", required = true, params = "()", returns = "table",
              doc = "Capability name -> true for what the host supports (see "
                 .. "Interface.capabilityList); missing names are false." },
            { name = "beginBatch", required = false, params = "()", capability = "batch",
              doc = "Brackets one flush of node changes; brackets do not nest." },
            { name = "endBatch", required = false, params = "()", capability = "batch" },
            { name = "pointerPosition", required = false, params = "()", returns = "x, y",
              capability = "pointerPosition", doc = "Current pointer position in window pixels." },
            { name = "isKeyDown", required = false, params = "(key)", returns = "boolean",
              capability = "keyState", doc = "Whether a named key is held." },
            { name = "inspect", required = false, params = "(node)", returns = "table",
              capability = "inspect",
              doc = "A snapshot of a node for tests and tools: parent (nil at the top "
                 .. "level or detached), topLevel, inScene, children (array), x, y, rotation, "
                 .. "scale, originX, originY, width, height, opacity, visible, clip, and "
                 .. "content (false, or a copy of the normalized content record)." },
            { name = "topLevel", required = false, params = "()", returns = "array",
              capability = "inspect", doc = "The top level nodes in draw order." },
        },
    },
    {
        name = "input",
        functions = {
            { name = "setInputSink", required = true, params = "(sink)",
              doc = "Registers the table whose feed functions (Interface.feed) the host "
                 .. "calls; missing functions are skipped. nil unregisters." },
        },
    },
}

--
-- The input feed: functions on the sink, called by the host. Positions are
-- window pixels; buttons are 1 left, 2 right, 3 middle; keys are LOVE
-- KeyConstant names ("a", "return", "escape", "left", "lshift", "f1",
-- "kp5", ...), which a non LOVE host maps its key codes onto. Hosts deliver
-- a pointerReleased for every pointerPressed they delivered, synthesizing
-- it when the release got lost. textInput carries printable text only, as
-- valid UTF-8 (the host replaces or drops anything else);
-- Return, Tab and Backspace arrive as key presses. Feed functions return true
-- when the framework handled the input, so a host can pass other input on.
--
Interface.feed = {
    { name = "pointerMoved",    params = "(x, y)" },
    { name = "pointerPressed",  params = "(x, y, button)" },
    { name = "pointerReleased", params = "(x, y, button)" },
    { name = "wheel",           params = "(dx, dy)",
      doc = "Notches at the current pointer position; positive dy scrolls up." },
    { name = "keyPressed",      params = "(key, isRepeat)" },
    { name = "keyReleased",     params = "(key)" },
    { name = "textInput",       params = "(text)" },
    { name = "pointerLeft",     params = "()",
      doc = "The pointer left the window; nothing is hovered until it moves again." },
}

-- Capabilities a host can report. Those with functions require them.
Interface.capabilityList = {
    { name = "rotatedClip",
      doc = "Clips follow rotation; otherwise clips use the transformed box's bounds." },
    { name = "rotatedSlices",
      doc = "Slices content draws correctly under rotation." },
    { name = "rotatedText",
      doc = "Text content draws correctly under rotation." },
    { name = "grayscale",
      doc = "The grayscale flag of setImage and setSlices is honoured." },
    { name = "batch", functions = { "beginBatch", "endBatch" } },
    { name = "textureFilter", functions = { "setTextureFilter" } },
    { name = "pointerPosition", functions = { "pointerPosition" } },
    { name = "keyState", functions = { "isKeyDown" } },
    { name = "inspect", functions = { "inspect", "topLevel" } },
}

Interface.cursors = {
    "arrow", "hand", "ibeam", "sizeall", "sizenwse", "sizenesw", "sizewe",
    "sizens", "wait", "waitarrow", "no", "crosshair",
}

Interface.alignments = { left = true, center = true, right = true }

-- name -> function description, and name -> group name
Interface.functions = {}
Interface.groupOf = {}
for _, group in ipairs(Interface.groups) do
    for _, fn in ipairs(group.functions) do
        Interface.functions[fn.name] = fn
        Interface.groupOf[fn.name] = group.name
    end
end

Interface.feedNames = {}
for _, fn in ipairs(Interface.feed) do
    Interface.feedNames[fn.name] = true
end

Interface.cursorNames = {}
for _, name in ipairs(Interface.cursors) do
    Interface.cursorNames[name] = true
end

--
-- Checks a host table against the interface. Returns true, or false and an
-- array of problems (missing required functions, a capabilities() that does
-- not return a table, claimed capabilities without their functions,
-- unknown capability names).
--
function Interface.check(host)
    local problems = {}
    if type(host) ~= "table" then
        return false, { "host is not a table" }
    end
    for _, group in ipairs(Interface.groups) do
        for _, fn in ipairs(group.functions) do
            if fn.required and type(host[fn.name]) ~= "function" then
                problems[#problems + 1] = "missing " .. group.name .. " function " .. fn.name
            end
        end
    end
    if type(host.capabilities) == "function" then
        local caps = host.capabilities()
        if type(caps) ~= "table" then
            problems[#problems + 1] = "capabilities() did not return a table"
        else
            local known = {}
            for _, cap in ipairs(Interface.capabilityList) do
                known[cap.name] = true
                if caps[cap.name] then
                    for _, name in ipairs(cap.functions or {}) do
                        if type(host[name]) ~= "function" then
                            problems[#problems + 1] = "capability " .. cap.name
                                .. " claimed without function " .. name
                        end
                    end
                end
            end
            for name in pairs(caps) do
                if not known[name] then
                    problems[#problems + 1] = "unknown capability " .. tostring(name)
                end
            end
        end
    end
    return #problems == 0, problems
end

-- Every known capability name mapped to a boolean.
function Interface.capabilities(host)
    local caps = host.capabilities and host.capabilities() or {}
    local result = {}
    for _, cap in ipairs(Interface.capabilityList) do
        result[cap.name] = caps[cap.name] and true or false
    end
    return result
end

--
-- Colours
--

-- A packed colour as a number in 0..0xFFFFFFFF; nil gives the default.
function Interface.color(color, default)
    if color == nil then color = default end
    if color == nil or color == false then return false end
    assert(type(color) == "number", "colour must be a packed 0xAARRGGBB number")
    return color % 4294967296
end

-- r, g, b, a in 0..1 of a normalized packed colour.
function Interface.unpackColor(color)
    return floor(color / 65536) % 256 / 255, floor(color / 256) % 256 / 255,
           color % 256 / 255, floor(color / 16777216) / 255
end

--
-- Content records. Hosts store what these return (and may add private
-- fields starting with an underscore); inspect copies the public fields.
--

local WHITE = 0xFFFFFFFF

local function checkNumber(value, name)
    assert(type(value) == "number", name .. " must be a number")
    return value
end

function Interface.imageContent(texture, tint, flipX, flipY, grayscale)
    assert(texture, "setImage: texture required")
    return {
        kind = "image", texture = texture, tint = Interface.color(tint, WHITE),
        flipX = flipX and true or false, flipY = flipY and true or false,
        grayscale = grayscale and true or false,
    }
end

function Interface.slicesContent(texture, left, top, right, bottom, tint, grayscale)
    assert(texture, "setSlices: texture required")
    return {
        kind = "slices", texture = texture,
        left = checkNumber(left, "left"), top = checkNumber(top, "top"),
        right = checkNumber(right, "right"), bottom = checkNumber(bottom, "bottom"),
        tint = Interface.color(tint, WHITE), grayscale = grayscale and true or false,
    }
end

function Interface.textContent(font, text, color, align, wrap)
    assert(font, "setText: font required")
    align = align or "left"
    assert(Interface.alignments[align], "setText: invalid alignment " .. tostring(align))
    if type(text) == "table" then
        assert(#text % 2 == 0, "setText: runs must be colour, string pairs")
        local runs = {}
        for i = 1, #text, 2 do
            runs[i] = Interface.color(text[i], WHITE)
            runs[i + 1] = tostring(text[i + 1])
        end
        text = runs
    else
        text = tostring(text or "")
    end
    return {
        kind = "text", font = font, text = text, color = Interface.color(color, WHITE),
        align = align, wrap = wrap and true or false,
    }
end

function Interface.fillContent(color, borderColor, borderWidth)
    borderColor = Interface.color(borderColor, false)
    if borderColor then
        borderWidth = borderWidth or 1
    else
        borderWidth = 0
    end
    return {
        kind = "fill", color = Interface.color(color, false),
        borderColor = borderColor, borderWidth = checkNumber(borderWidth, "borderWidth"),
    }
end

-- The plain string of text content (runs concatenated).
function Interface.plainText(text)
    if type(text) ~= "table" then return text end
    local parts = {}
    for i = 2, #text, 2 do
        parts[#parts + 1] = text[i]
    end
    return table.concat(parts)
end

-- A copy of a content record without private fields, for inspect.
function Interface.copyContent(content)
    if not content then return false end
    local copy = {}
    for k, v in pairs(content) do
        if type(k) ~= "string" or k:sub(1, 1) ~= "_" then
            if type(v) == "table" and k == "text" then
                local runs = {}
                for i = 1, #v do runs[i] = v[i] end
                v = runs
            end
            copy[k] = v
        end
    end
    return copy
end

--
-- Nine-slice geometry. One axis: the source spans (0, a), (a, total - b),
-- (total - b, total); the destination keeps a and b and stretches the middle
-- to size - a - b. When size < a + b the ends shrink proportionally and the
-- middle is empty.
--
local function sliceAxis(size, total, a, b)
    if size < 0 then size = 0 end
    local s1, s2, s3 = 0, a, total - b
    local w1, w2, w3 = a, total - a - b, b
    local d1, d2, d3, dw1, dw2, dw3
    if size >= a + b then
        d1, d2, d3 = 0, a, size - b
        dw1, dw2, dw3 = a, size - a - b, b
    else
        local k = size / (a + b)
        d1, d2, d3 = 0, a * k, a * k
        dw1, dw2, dw3 = a * k, 0, b * k
    end
    return s1, s2, s3, w1, w2, w3, d1, d2, d3, dw1, dw2, dw3
end

--
-- The nine source and destination rectangles of a slices node, in row major
-- order (1 top left, 5 centre, 9 bottom right). Each entry is
-- { sx, sy, sw, sh, dx, dy, dw, dh } with the source in texture pixels and
-- the destination in the node's local units. Parts with an empty source or
-- destination are still listed; hosts skip them when drawing.
--
function Interface.sliceRects(textureWidth, textureHeight, left, top, right, bottom, width, height)
    local sx = { select(1, sliceAxis(width, textureWidth, left, right)) }
    local sy = { select(1, sliceAxis(height, textureHeight, top, bottom)) }
    local rects = {}
    for row = 1, 3 do
        for col = 1, 3 do
            rects[(row - 1) * 3 + col] = {
                sx[col], sy[row], sx[col + 3], sy[row + 3],
                sx[col + 6], sy[row + 6], sx[col + 9], sy[row + 9],
            }
        end
    end
    return rects
end

return Interface
