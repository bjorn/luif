--
-- The LOVE host: the retained host interface (host/interface.lua) on LOVE
-- 11.5. Nodes are Lua records holding transform, size, opacity, visibility,
-- clip and at most one content; host.render() draws the retained scene and
-- is meant to be called from love.draw. Texture and font handles come from
-- luif/love/texture.lua and luif/love/font.lua, and are the tables core's TexDb
-- and FontDb hand out.
--
--   local host = require("luif.love.host").new()
--
-- Node record:
--
--   { parent = false, children = {}, destroyed = false,
--     x = 0, y = 0, rotation = 0, scale = 1, ox = 0, oy = 0,
--     width = 0, height = 0, opacity = 1, visible = true, clip = false,
--     content = false }  -- or a record from Interface.*Content
--
-- Content drawing: image is one love.graphics.draw scaled to the box,
-- slices are nine quads of one image, text is print or printf with the
-- font's shadow and outline passes, fill is up to five rectangles.
--
-- host.loveHandlers maps the love input callbacks onto the input sink and
-- returns what the sink returns; luif/love/init.lua calls them from the love
-- callbacks.
--

local Interface = require "luif.host.interface"
local Tree = require "luif.host.tree"
local Transform = require "luif.love.transform"
local Texture = require "luif.love.texture"
local Font = require "luif.love.font"

local bit = require "bit"
local band, rshift = bit.band, bit.rshift
local min = math.min

local localTransform, applyTransform = Transform.localTransform, Transform.apply
local pushClip, popClip = Transform.pushClip, Transform.popClip

-- System cursors by name, shared by every host
local cursors = {}
local currentCursor = false

local function setSystemCursor(name)
    if name == currentCursor then return end
    currentCursor = name
    if not love.mouse.isCursorSupported() then return end
    local cursor = cursors[name]
    if cursor == nil then
        local ok, result = pcall(love.mouse.getSystemCursor, name)
        cursor = ok and result or false
        cursors[name] = cursor
    end
    if cursor then
        love.mouse.setCursor(cursor)
    else
        love.mouse.setCursor()
    end
end

local Host = {}

local function unpackColor(color)
    return band(rshift(color, 16), 0xFF) / 255, band(rshift(color, 8), 0xFF) / 255,
           band(color, 0xFF) / 255, rshift(color, 24) / 255
end

-- Sets a packed colour with its alpha multiplied by eff; false when the
-- result is fully transparent.
local function setColor(lg, color, eff)
    local r, g, b, a = unpackColor(color)
    a = a * eff
    if a <= 0 then return false end
    lg.setColor(r, g, b, a)
    return true
end

local grayShader = false

local function getGrayShader()
    if not grayShader then
        grayShader = love.graphics.newShader [[
            vec4 effect(vec4 color, Image tex, vec2 uv, vec2 sc) {
                vec4 p = Texel(tex, uv);
                float l = dot(p.rgb, vec3(0.299, 0.587, 0.114));
                return vec4(l, l, l, p.a) * color;
            }
        ]]
    end
    return grayShader
end

--
-- Content drawing, in the node's local space. eff is the effective opacity.
--

local draw = {}

function draw.image(lg, c, w, h, eff)
    if w <= 0 or h <= 0 then return end
    local tex = c.texture
    local tw, th = tex.width, tex.height
    if tw <= 0 or th <= 0 or not setColor(lg, c.tint, eff) then return end
    if c.grayscale then lg.setShader(getGrayShader()) end
    local sx, sy, x, y = w / tw, h / th, 0, 0
    if c.flipX then sx, x = -sx, w end
    if c.flipY then sy, y = -sy, h end
    if tex.quad then
        lg.draw(tex.image, tex.quad, x, y, 0, sx, sy)
    else
        lg.draw(tex.image, x, y, 0, sx, sy)
    end
    if c.grayscale then lg.setShader() end
end

-- The nine quads depend only on the texture and insets, which never change
-- for one content record; the rectangles are recomputed when the size does.
local function sliceParts(lg, c, w, h)
    local tex = c.texture
    if not c._quads then
        local ox, oy = 0, 0
        if tex.quad then ox, oy = tex.quad:getViewport() end
        local iw, ih = tex.image:getDimensions()
        local rects = Interface.sliceRects(tex.width, tex.height,
                                           c.left, c.top, c.right, c.bottom, 0, 0)
        local quads = {}
        for i = 1, 9 do
            local r = rects[i]
            quads[i] = r[3] > 0 and r[4] > 0
                and lg.newQuad(ox + r[1], oy + r[2], r[3], r[4], iw, ih) or false
        end
        c._quads = quads
    end
    if c._w ~= w or c._h ~= h then
        c._rects = Interface.sliceRects(tex.width, tex.height,
                                        c.left, c.top, c.right, c.bottom, w, h)
        c._w, c._h = w, h
    end
    return c._quads, c._rects
end

function draw.slices(lg, c, w, h, eff)
    if w <= 0 or h <= 0 or not setColor(lg, c.tint, eff) then return end
    local quads, rects = sliceParts(lg, c, w, h)
    local image = c.texture.image
    if c.grayscale then lg.setShader(getGrayShader()) end
    for i = 1, 9 do
        local quad, r = quads[i], rects[i]
        if quad and r[7] > 0 and r[8] > 0 then
            lg.draw(image, quad, r[5], r[6], 0, r[7] / r[3], r[8] / r[4])
        end
    end
    if c.grayscale then lg.setShader() end
end

-- Display text (string or LOVE coloured text), plain text for the shadow
-- and outline passes, widest line and line count; computed on first draw.
local function prepareText(c)
    local text = c.text
    local plain = Interface.plainText(text)
    if type(text) == "table" and #text > 0 then
        local display = {}
        for i = 1, #text, 2 do
            local r, g, b, a = unpackColor(text[i])
            display[i], display[i + 1] = { r, g, b, a }, text[i + 1]
        end
        c._display = display
    else
        c._display = plain
    end
    c._plain = plain
    local font = c.font.font
    local widest, lines, start = 0, 0, 1
    while true do
        lines = lines + 1
        local nl = plain:find("\n", start, true)
        local width = font:getWidth(nl and plain:sub(start, nl - 1) or plain:sub(start))
        if width > widest then widest = width end
        if not nl then break end
        start = nl + 1
    end
    c._widest, c._lines = widest, lines
end

-- Prints text at (x, y) laid out in a box of width w.
local function printText(lg, c, text, x, y, w)
    local align = c.align
    if c.wrap then
        lg.printf(text, x, y, w > 0 and w or 0, align)
        return
    end
    local widest = c._widest
    if align == "center" then
        x = x + (w - widest) / 2
    elseif align == "right" then
        x = x + w - widest
    end
    if c._lines > 1 and align ~= "left" then
        -- The slack keeps printf from wrapping the widest line itself.
        lg.printf(text, x, y, widest + 0.01, align)
    else
        lg.print(text, x, y)
    end
end

function draw.text(lg, c, w, h, eff)
    local r, g, b, a = unpackColor(c.color)
    a = a * eff
    if a <= 0 then return end
    if c._display == nil then prepareText(c) end

    local fh = c.font
    lg.setFont(fh.font)
    if fh.shadow then
        local shadow = fh.shadow
        local sr, sg, sb, sa = unpackColor(shadow[3])
        lg.setColor(sr, sg, sb, sa * a)
        printText(lg, c, c._plain, shadow[1], shadow[2], w)
    end
    if fh.outline then
        local orr, og, ob, oa = unpackColor(fh.outline[1])
        lg.setColor(orr, og, ob, oa * a)
        for dy = -1, 1 do
            for dx = -1, 1 do
                if dx ~= 0 or dy ~= 0 then
                    printText(lg, c, c._plain, dx, dy, w)
                end
            end
        end
    end
    if type(c._display) == "table" then
        lg.setColor(1, 1, 1, a)
    else
        lg.setColor(r, g, b, a)
    end
    printText(lg, c, c._display, 0, 0, w)
end

function draw.fill(lg, c, w, h, eff)
    if w <= 0 or h <= 0 then return end
    if c.color and setColor(lg, c.color, eff) then
        lg.rectangle("fill", 0, 0, w, h)
    end
    local bw = c.borderWidth
    if c.borderColor and bw > 0 and setColor(lg, c.borderColor, eff) then
        local bx, by = min(bw, w / 2), min(bw, h / 2)
        lg.rectangle("fill", 0, 0, w, by)
        lg.rectangle("fill", 0, h - by, w, by)
        lg.rectangle("fill", 0, by, bx, h - 2 * by)
        lg.rectangle("fill", w - bx, by, bx, h - 2 * by)
    end
end

--
-- Scene walk. A and B are the rotation and scale part of the parent's
-- accumulated transform, for the scissor fast path of axis aligned clips.
--
local function drawNode(lg, node, A, B, eff)
    if not node.visible then return end
    eff = eff * node.opacity
    if eff <= 0 then return end

    local la, lb = localTransform(node)
    local a, b = A * la - B * lb, A * lb + B * la
    local w, h = node.width, node.height

    lg.push()
    applyTransform(lg, node)

    local mode, sx, sy, sw, sh
    if node.clip then
        mode, sx, sy, sw, sh = pushClip(lg, a, b, 0, 0, w, h)
    end

    local content = node.content
    if content then
        draw[content.kind](lg, content, w, h, eff)
    end

    local children = node.children
    for i = 1, #children do
        drawNode(lg, children[i], a, b, eff)
    end

    if mode then
        popClip(lg, mode, sx, sy, sw, sh, 0, 0, w, h)
    end
    lg.pop()
end

function Host.new()
    local host = {}
    local root = Tree.newRoot()
    local check = Tree.check
    local sink = false

    --
    -- Structure
    --

    function host.createNode()
        return {
            parent = false, children = {}, destroyed = false,
            x = 0, y = 0, rotation = 0, scale = 1, ox = 0, oy = 0,
            width = 0, height = 0, opacity = 1, visible = true, clip = false,
            content = false,
        }
    end

    local function releaseNode(node)
        node.content = false
    end

    function host.destroyNode(node)
        Tree.destroy(node, releaseNode)
    end

    function host.attach(node, parent, nextSibling)
        Tree.attach(root, node, parent, nextSibling)
    end

    function host.detach(node)
        Tree.detach(node)
    end

    --
    -- Properties
    --

    function host.setTransform(node, x, y, rotation, scale, originX, originY)
        check(node)
        node.x, node.y = x, y
        node.rotation, node.scale = rotation or 0, scale or 1
        node.ox, node.oy = originX or 0, originY or 0
    end

    function host.setSize(node, width, height)
        check(node)
        node.width, node.height = width, height
    end

    function host.setOpacity(node, opacity)
        check(node)
        node.opacity = opacity
    end

    function host.setVisible(node, visible)
        check(node)
        node.visible = visible and true or false
    end

    function host.setClip(node, clip)
        check(node)
        node.clip = clip and true or false
    end

    --
    -- Content
    --

    function host.setImage(node, texture, tint, flipX, flipY, grayscale)
        check(node)
        node.content = Interface.imageContent(texture, tint, flipX, flipY, grayscale)
    end

    function host.setSlices(node, texture, left, top, right, bottom, tint, grayscale)
        check(node)
        node.content = Interface.slicesContent(texture, left, top, right, bottom, tint, grayscale)
    end

    function host.setText(node, font, text, color, align, wrap)
        check(node)
        node.content = Interface.textContent(font, text, color, align, wrap)
    end

    function host.setFill(node, color, borderColor, borderWidth)
        check(node)
        node.content = Interface.fillContent(color, borderColor, borderWidth)
    end

    function host.clearContent(node)
        check(node)
        node.content = false
    end

    --
    -- Resources
    --

    function host.loadTexture(path)
        if not Texture.exists(path) then
            return nil, "texture not found: " .. tostring(path)
        end
        local ok, tex = pcall(Texture.load, path)
        if not ok then
            return nil, tostring(tex)
        end
        return tex
    end

    local function white()
        return 255, 255, 255, 255
    end

    function host.createTexture(width, height, pixel)
        return Texture.fromPixels(width, height, pixel or white, "generated")
    end

    host.textureRegion = Texture.region
    host.textureSize = Texture.size
    host.loadFont = Font.load

    function host.textWidth(font, text)
        return font.font:getWidth(text)
    end

    host.lineHeight = Font.lineHeight
    host.wrapText = Font.wrap
    host.setTextureFilter = Texture.setFilter

    --
    -- System
    --

    -- The clock the application feeds to Update.onUpdate
    function host.time()
        return love.timer.getTime() * 1000
    end

    function host.screenSize()
        if love.graphics and love.graphics.isCreated() then
            return love.graphics.getDimensions()
        end
        return 0, 0
    end

    function host.getClipboard()
        local ok, text = pcall(love.system.getClipboardText)
        return ok and text or ""
    end

    function host.setClipboard(text)
        pcall(love.system.setClipboardText, tostring(text or ""))
    end

    function host.setCursor(name)
        setSystemCursor(Interface.cursorNames[name] and name or "arrow")
    end

    -- Through love.filesystem, with io as a fallback for other paths.
    function host.setTextInput(active, x, y, width, height)
        if active and x then
            love.keyboard.setTextInput(true, x, y, width, height)
        else
            love.keyboard.setTextInput(active and true or false)
        end
    end

    function host.readFile(path)
        if love.filesystem.getInfo(path, "file") then
            local contents, err = love.filesystem.read(path)
            if contents then return contents end
            return nil, err
        end
        local f, err = io.open(path, "rb")
        if not f then
            return nil, err
        end
        local contents = f:read("*a")
        f:close()
        return contents
    end

    local caps = {
        rotatedClip = true, rotatedSlices = true, rotatedText = true, grayscale = true,
        textureFilter = true, pointerPosition = true, keyState = true, textInput = true,
        inspect = true,
    }

    function host.capabilities()
        local copy = {}
        for name, value in pairs(caps) do copy[name] = value end
        return copy
    end

    function host.pointerPosition()
        return love.mouse.getPosition()
    end

    function host.isKeyDown(key)
        local ok, down = pcall(love.keyboard.isDown, key)
        return ok and down or false
    end

    function host.inspect(node)
        check(node)
        return Tree.snapshot(node, Interface.copyContent)
    end

    function host.topLevel()
        return Tree.topLevel(root)
    end

    --
    -- Input feed
    --

    function host.setInputSink(newSink)
        sink = newSink or false
    end

    local held = {}
    local lastX, lastY = 0, 0

    local function emit(name, ...)
        local fn = sink and sink[name]
        if fn then return fn(...) end
        return false
    end

    local handlers = {}
    host.loveHandlers = handlers

    function handlers.mousemoved(x, y)
        lastX, lastY = x, y
        return emit("pointerMoved", x, y)
    end

    function handlers.mousepressed(x, y, button)
        lastX, lastY = x, y
        held[button] = true
        return emit("pointerPressed", x, y, button)
    end

    -- A release without a delivered press is dropped.
    function handlers.mousereleased(x, y, button)
        lastX, lastY = x, y
        if held[button] then
            held[button] = nil
            return emit("pointerReleased", x, y, button)
        end
        return false
    end

    function handlers.wheelmoved(dx, dy)
        return emit("wheel", dx, dy)
    end

    function handlers.keypressed(key, scancode, isrepeat)
        return emit("keyPressed", key, isrepeat and true or false)
    end

    function handlers.keyreleased(key)
        return emit("keyReleased", key)
    end

    function handlers.textinput(text)
        if text ~= "" then
            return emit("textInput", text)
        end
        return false
    end

    function handlers.mousefocus(focus)
        if not focus then
            return emit("pointerLeft")
        end
        return false
    end

    -- Releases buttons that are held according to the delivered presses but
    -- up according to isDown (default love.mouse.isDown). Call once all of a
    -- frame's callbacks ran.
    function host.releaseLostButtons(isDown)
        isDown = isDown or love.mouse.isDown
        for button in pairs(held) do
            if not isDown(button) then
                held[button] = nil
                emit("pointerReleased", lastX, lastY, button)
            end
        end
    end

    --
    -- Rendering
    --

    -- Draws the top level nodes in order under the current love.graphics
    -- transform. An empty scene makes no graphics calls.
    function host.render()
        local top = root.children
        if #top == 0 then return end
        local lg = love.graphics
        lg.setColor(1, 1, 1, 1)
        for i = 1, #top do
            drawNode(lg, top[i], 1, 0, 1)
        end
        lg.setColor(1, 1, 1, 1)
    end

    return host
end

return Host
