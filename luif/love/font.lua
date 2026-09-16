--
-- Font handles for the LOVE host. A handle is a plain table with stable
-- identity (the framework compares fonts with ==):
--
--   { font = <love Font>, name = "Text", size = 13,
--     shadow = false | { dx, dy, color }, outline = false | { color } }
--
-- Font.load(spec) takes { file = path or false, size = n, shadow = ...,
-- outline = ..., name = optional } and caches per specification. A false
-- file selects LOVE's built-in font. Colours are packed 0xAARRGGBB.
--

local Font = {}

local cache = {}

local function keyOf(file, size, shadow, outline)
    local key = tostring(file) .. "|" .. tostring(size)
    if shadow then
        key = key .. "|s" .. tostring(shadow[1]) .. "," .. tostring(shadow[2])
            .. "," .. tostring(shadow[3])
    end
    if outline then
        key = key .. "|o" .. tostring(outline[1])
    end
    return key
end

local function nameOf(file)
    if not file then return "default" end
    return file:match("([^/\\]+)%.[^.]+$") or file
end

function Font.load(spec)
    spec = spec or {}
    local file = spec.file or false
    local size = spec.size or 12
    local shadow = spec.shadow or false
    local outline = spec.outline or false
    local key = keyOf(file, size, shadow, outline)
    local handle = cache[key]
    if handle then return handle end

    local font
    if file and not love.filesystem.getInfo(file) and file:sub(1, 1) == "/" then
        -- Outside the LOVE filesystem: read through io.
        local f = assert(io.open(file, "rb"), "Cannot open font '" .. file .. "'")
        local data = love.filesystem.newFileData(f:read("*a"), nameOf(file) .. ".ttf")
        f:close()
        font = love.graphics.newFont(love.font.newTrueTypeRasterizer(data, size))
    elseif file then
        font = love.graphics.newFont(file, size)
    else
        font = love.graphics.newFont(size)
    end
    handle = {
        font = font,
        name = spec.name or nameOf(file),
        size = size,
        shadow = shadow and { shadow[1] or 1, shadow[2] or 1, shadow[3] or 0xFF000000 } or false,
        outline = outline and { outline[1] or 0xFF000000 } or false,
    }
    cache[key] = handle
    return handle
end

-- Vertical advance between two lines (what print and printf use).
function Font.lineHeight(handle)
    local font = handle.font
    return font:getHeight() * font:getLineHeight()
end

-- Word wraps text to width; returns the widest line width and the lines.
function Font.wrap(handle, text, width)
    return handle.font:getWrap(text, width)
end

return Font
