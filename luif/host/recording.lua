--
-- The recording host: the retained host interface (host/interface.lua) in
-- plain Lua, without LOVE. It keeps the full node state (tree, properties,
-- content), logs every interface call, and has helpers for tests.
--
--   local Recording = require "luif.host.recording"
--   local host = Recording.new {
--       textureSizes = { button = { 32, 16 } },  -- by path or base name
--       defaultTextureSize = { 16, 16 },
--       strictTextures = false,     -- true: unknown textures fail to load
--       glyphWidth = 8,             -- text width per codepoint
--       lineHeight = 16,
--       screenWidth = 1280, screenHeight = 720,
--       time = 0,                   -- initial clock in milliseconds
--       files = { ["a.txt"] = "contents" },
--       readFile = function(path) end,   -- fallback for files
--       pngSizes = false,           -- true: size textures from PNG files
--       capabilities = { rotatedClip = false },  -- overrides
--   }
--
-- Resources are deterministic stubs: textures take their size from the
-- size table, with pngSizes from the header of a PNG file that readFile
-- returns, or the default, text is glyphWidth wide per codepoint, and
-- wrapText wraps greedily at spaces without splitting words.
--
-- Test helpers (not logged): host.log(), host.resetLog(), host.count(filter),
-- host.logLines(filter), host.dump(node), host.feed(name, ...),
-- host.setTime(ms), host.advance(ms), host.setScreenSize(w, h),
-- host.cursor(). A filter is an interface function name or group name
-- ("structure", "properties", "content", "resources", "system", "input").
-- inspect and topLevel are not logged either.
--

local Interface = require "luif.host.interface"
local Tree = require "luif.host.tree"

local format, concat = string.format, table.concat
local floor, max = math.floor, math.max

local Recording = {}

local nodeMeta = {
    __tostring = function(node) return "node#" .. node.id end,
}

local function codepoints(s)
    local _, count = s:gsub("[^\128-\191]", "")
    return count
end

local function baseName(path)
    return path:match("([^/\\]+)%.[^./\\]*$") or path:match("([^/\\]+)$") or path
end

-- Width and height from the IHDR chunk of PNG file contents, or nil.
local function pngSize(contents)
    if type(contents) ~= "string" or #contents < 24
            or contents:sub(1, 8) ~= "\137PNG\r\n\26\n" or contents:sub(13, 16) ~= "IHDR" then
        return nil
    end
    local function u32(i)
        local a, b, c, d = contents:byte(i, i + 3)
        return ((a * 256 + b) * 256 + c) * 256 + d
    end
    return { u32(17), u32(21) }
end

local function num(value)
    return format("%.10g", value)
end

local function textureName(tex)
    if tex.region then
        return format("%s@%s,%s+%sx%s", tex.name, num(tex.x), num(tex.y),
                      num(tex.width), num(tex.height))
    end
    return tex.name
end

-- One log argument as text.
local function formatValue(value)
    local kind = type(value)
    if kind == "number" then
        return num(value)
    elseif kind == "string" then
        return format("%q", value)
    elseif kind == "table" then
        if getmetatable(value) == nodeMeta then
            return tostring(value)
        elseif value.kind == "texture" then
            return "tex:" .. textureName(value)
        elseif value.kind == "font" then
            return "font:" .. value.name .. ":" .. num(value.size)
        end
        return "table"
    end
    return tostring(value)
end

local function describeContent(content)
    local kind = content.kind
    if kind == "image" then
        return format("image=%s tint=%08X%s%s%s", textureName(content.texture), content.tint,
                      content.flipX and " flipX" or "", content.flipY and " flipY" or "",
                      content.grayscale and " grayscale" or "")
    elseif kind == "slices" then
        return format("slices=%s insets=%s,%s,%s,%s tint=%08X%s", textureName(content.texture),
                      num(content.left), num(content.top), num(content.right),
                      num(content.bottom), content.tint, content.grayscale and " grayscale" or "")
    elseif kind == "text" then
        local runs = type(content.text) == "table" and " runs" or ""
        return format("text=%q%s font=%s:%s color=%08X align=%s%s",
                      Interface.plainText(content.text), runs, content.font.name,
                      num(content.font.size), content.color, content.align,
                      content.wrap and " wrap" or "")
    end
    local fill = content.color and format("fill=%08X", content.color) or "fill=none"
    if content.borderColor then
        fill = fill .. format(" border=%08X/%s", content.borderColor, num(content.borderWidth))
    end
    return fill
end

local function describeNode(node)
    local parts = { tostring(node), "pos=" .. num(node.x) .. "," .. num(node.y),
                    "size=" .. num(node.width) .. "x" .. num(node.height) }
    if node.rotation ~= 0 then parts[#parts + 1] = "rotation=" .. num(node.rotation) end
    if node.scale ~= 1 then parts[#parts + 1] = "scale=" .. num(node.scale) end
    if node.ox ~= 0 or node.oy ~= 0 then
        parts[#parts + 1] = "origin=" .. num(node.ox) .. "," .. num(node.oy)
    end
    if node.opacity ~= 1 then parts[#parts + 1] = "opacity=" .. num(node.opacity) end
    if not node.visible then parts[#parts + 1] = "hidden" end
    if node.clip then parts[#parts + 1] = "clip" end
    if node.content then parts[#parts + 1] = describeContent(node.content) end
    return concat(parts, " ")
end

function Recording.new(options)
    options = options or {}

    local host = {}
    local impl = {}
    local root = Tree.newRoot()
    local check = Tree.check

    local log = {}
    local nextId = 0
    local sink = false
    local batchDepth = 0

    local glyphWidth = options.glyphWidth or 8
    local lineHeightValue = options.lineHeight or 16
    local textureSizes = options.textureSizes or {}
    local defaultTextureSize = options.defaultTextureSize or { 16, 16 }
    local files = options.files or {}
    local clock = options.time or 0
    local screenW, screenH = options.screenWidth or 1280, options.screenHeight or 720
    local clipboard = ""
    local cursor = "arrow"
    local pointerX, pointerY = 0, 0
    local keysDown = {}
    local textures = {}
    local fonts = {}

    local caps = {
        rotatedClip = true, rotatedSlices = true, rotatedText = true, grayscale = true,
        batch = true, textureFilter = true, pointerPosition = true, keyState = true,
        inspect = true,
    }
    for name, value in pairs(options.capabilities or {}) do
        caps[name] = value and true or false
    end

    --
    -- Structure
    --

    function impl.createNode()
        nextId = nextId + 1
        return setmetatable({
            id = nextId, parent = false, children = {}, destroyed = false,
            x = 0, y = 0, rotation = 0, scale = 1, ox = 0, oy = 0,
            width = 0, height = 0, opacity = 1, visible = true, clip = false,
            content = false,
        }, nodeMeta)
    end

    local function releaseNode(node)
        node.content = false
    end

    function impl.destroyNode(node)
        Tree.destroy(node, releaseNode)
    end

    function impl.attach(node, parent, nextSibling)
        Tree.attach(root, node, parent, nextSibling)
    end

    function impl.detach(node)
        Tree.detach(node)
    end

    --
    -- Properties
    --

    local function number(value, name)
        if type(value) ~= "number" then
            error(name .. " must be a number, got " .. tostring(value), 3)
        end
        return value
    end

    function impl.setTransform(node, x, y, rotation, scale, originX, originY)
        check(node)
        node.x, node.y = number(x, "x"), number(y, "y")
        node.rotation = number(rotation or 0, "rotation")
        node.scale = number(scale or 1, "scale")
        node.ox, node.oy = number(originX or 0, "originX"), number(originY or 0, "originY")
    end

    function impl.setSize(node, width, height)
        check(node)
        node.width, node.height = number(width, "width"), number(height, "height")
    end

    function impl.setOpacity(node, opacity)
        check(node)
        node.opacity = number(opacity, "opacity")
    end

    function impl.setVisible(node, visible)
        check(node)
        node.visible = visible and true or false
    end

    function impl.setClip(node, clip)
        check(node)
        node.clip = clip and true or false
    end

    --
    -- Content
    --

    function impl.setImage(node, texture, tint, flipX, flipY, grayscale)
        check(node)
        node.content = Interface.imageContent(texture, tint, flipX, flipY, grayscale)
    end

    function impl.setSlices(node, texture, left, top, right, bottom, tint, grayscale)
        check(node)
        node.content = Interface.slicesContent(texture, left, top, right, bottom, tint, grayscale)
    end

    function impl.setText(node, font, text, color, align, wrap)
        check(node)
        node.content = Interface.textContent(font, text, color, align, wrap)
    end

    function impl.setFill(node, color, borderColor, borderWidth)
        check(node)
        node.content = Interface.fillContent(color, borderColor, borderWidth)
    end

    function impl.clearContent(node)
        check(node)
        node.content = false
    end

    --
    -- Resources
    --

    local function newTexture(name, width, height)
        return { kind = "texture", name = name, width = width, height = height,
                 x = 0, y = 0, region = false }
    end

    function impl.loadTexture(path)
        local tex = textures[path]
        if tex then return tex end
        local size = textureSizes[path] or textureSizes[baseName(path)]
        if not size and options.pngSizes then
            size = pngSize(impl.readFile(path))
        end
        if not size then
            if options.strictTextures then
                return nil, "texture not found: " .. tostring(path)
            end
            size = defaultTextureSize
        end
        tex = newTexture(baseName(path), size[1], size[2])
        tex.path = path
        textures[path] = tex
        return tex
    end

    function impl.createTexture(width, height, pixel)
        return newTexture("generated", number(width, "width"), number(height, "height"))
    end

    function impl.textureRegion(tex, x, y, width, height)
        assert(type(tex) == "table" and tex.kind == "texture", "textureRegion: not a texture")
        local region = newTexture(tex.name, width, height)
        region.x, region.y = tex.x + x, tex.y + y
        region.region = true
        region.source = tex.source or tex
        return region
    end

    function impl.textureSize(tex)
        return tex.width, tex.height
    end

    function impl.loadFont(spec)
        spec = spec or {}
        local file = spec.file or false
        local size = spec.size or 12
        local shadow, outline = spec.shadow, spec.outline
        local key = concat({ tostring(file), num(size), tostring(spec.name),
                             shadow and concat(shadow, ",") or "",
                             outline and concat(outline, ",") or "" }, "|")
        local font = fonts[key]
        if not font then
            font = { kind = "font", name = spec.name or (file and baseName(file)) or "default",
                     size = size, file = file, shadow = shadow or false, outline = outline or false }
            fonts[key] = font
        end
        return font
    end

    local function measure(text)
        return codepoints(text) * glyphWidth
    end

    function impl.textWidth(font, text)
        return measure(tostring(text))
    end

    function impl.lineHeight(font)
        return lineHeightValue
    end

    function impl.wrapText(font, text, width)
        text = tostring(text)
        local lines = {}
        if text == "" then return 0, lines end
        for paragraph in (text .. "\n"):gmatch("(.-)\n") do
            local line = nil
            for word in paragraph:gmatch("%S+") do
                if not line then
                    line = word
                elseif measure(line .. " " .. word) <= width then
                    line = line .. " " .. word
                else
                    lines[#lines + 1] = line
                    line = word
                end
            end
            lines[#lines + 1] = line or ""
        end
        local widest = 0
        for i = 1, #lines do
            widest = max(widest, measure(lines[i]))
        end
        return widest, lines
    end

    function impl.setTextureFilter(min, mag)
    end

    --
    -- System
    --

    function impl.time()
        return clock
    end

    function impl.screenSize()
        return screenW, screenH
    end

    function impl.getClipboard()
        return clipboard
    end

    function impl.setClipboard(text)
        clipboard = tostring(text or "")
    end

    function impl.setCursor(name)
        cursor = Interface.cursorNames[name] and name or "arrow"
    end

    function impl.readFile(path)
        local contents = files[path]
        if contents == nil and options.readFile then
            contents = options.readFile(path)
        end
        if contents == nil then
            return nil, "file not found: " .. tostring(path)
        end
        return contents
    end

    function impl.capabilities()
        local copy = {}
        for name, value in pairs(caps) do copy[name] = value end
        return copy
    end

    function impl.beginBatch()
        assert(batchDepth == 0, "beginBatch: batches do not nest")
        batchDepth = 1
    end

    function impl.endBatch()
        assert(batchDepth == 1, "endBatch: no batch open")
        batchDepth = 0
    end

    function impl.pointerPosition()
        return pointerX, pointerY
    end

    function impl.isKeyDown(key)
        return keysDown[key] and true or false
    end

    --
    -- Input
    --

    function impl.setInputSink(newSink)
        sink = newSink or false
    end

    -- Every interface function logs its call, then runs.
    for name in pairs(Interface.functions) do
        local fn = impl[name]
        if fn and name ~= "inspect" and name ~= "topLevel" then
            local group = Interface.groupOf[name]
            host[name] = function(...)
                log[#log + 1] = { op = name, group = group, n = select("#", ...), ... }
                return fn(...)
            end
        end
    end

    -- Returns host functions only when the capability is on, so a host made
    -- without a capability looks like a host that lacks it.
    for _, cap in ipairs(Interface.capabilityList) do
        if not caps[cap.name] then
            for _, name in ipairs(cap.functions or {}) do
                host[name] = nil
            end
        end
    end

    --
    -- Inspection (interface, not logged)
    --

    if caps.inspect then
        function host.inspect(node)
            check(node)
            local snapshot = Tree.snapshot(node, Interface.copyContent)
            snapshot.id = node.id
            return snapshot
        end

        function host.topLevel()
            return Tree.topLevel(root)
        end
    end

    --
    -- Test helpers
    --

    -- The log entries: { op = name, group = group, n = argument count, args... }.
    function host.log()
        return log
    end

    function host.resetLog()
        log = {}
    end

    local function matches(entry, filter)
        return filter == nil or entry.op == filter or entry.group == filter
    end

    function host.count(filter)
        local count = 0
        for i = 1, #log do
            if matches(log[i], filter) then count = count + 1 end
        end
        return count
    end

    -- Entries as text, for example "attach node#2 node#1 nil".
    function host.logLines(filter)
        local lines = {}
        for i = 1, #log do
            local entry = log[i]
            if matches(entry, filter) then
                local parts = { entry.op }
                for j = 1, entry.n do
                    parts[#parts + 1] = formatValue(entry[j])
                end
                lines[#lines + 1] = concat(parts, " ")
            end
        end
        return lines
    end

    -- A node and its subtree, one line per node indented by depth; without a
    -- node, every top level subtree.
    function host.dump(node)
        local lines = {}
        local function walk(n, depth)
            lines[#lines + 1] = string.rep("  ", depth) .. describeNode(n)
            for i = 1, #n.children do
                walk(n.children[i], depth + 1)
            end
        end
        if node then
            check(node)
            walk(node, 0)
        else
            for i = 1, #root.children do
                walk(root.children[i], 0)
            end
        end
        return concat(lines, "\n")
    end

    -- Feeds input to the registered sink, as a host would. Tracks the
    -- pointer position and held keys for pointerPosition and isKeyDown.
    function host.feed(name, ...)
        assert(Interface.feedNames[name], "feed: unknown input function " .. tostring(name))
        if name == "pointerMoved" or name == "pointerPressed" or name == "pointerReleased" then
            pointerX, pointerY = ...
        elseif name == "keyPressed" then
            keysDown[(...)] = true
        elseif name == "keyReleased" then
            keysDown[(...)] = nil
        end
        local fn = sink and sink[name]
        if fn then return fn(...) end
    end

    function host.setTime(ms)
        clock = ms
    end

    function host.advance(ms)
        clock = clock + ms
    end

    function host.setScreenSize(width, height)
        screenW, screenH = width, height
    end

    function host.cursor()
        return cursor
    end

    return host
end

return Recording
