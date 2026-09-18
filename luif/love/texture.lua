--
-- Texture handles for the LOVE host. A handle is a plain table with stable
-- identity (TexDb uses it as a table key):
--
--   { image = <love Image>, quad = <love Quad> or false,
--     width = w, height = h, name = "button" }
--
-- Texture.load caches per path. Paths are relative to the LOVE source
-- directory (love.filesystem); absolute paths are read through io as a
-- fallback. Texture.region returns a quad handle that shares the image of
-- its source.
--

local Texture = {}

local cache = {}        -- path -> handle
local owned = {}        -- handles with their own image, for setFilter
local filterMin, filterMag = "linear", "linear"

local function nameOf(path)
    return path:match("([^/\\]+)%.[^.]+$") or path
end

local function isAbsolute(path)
    return path:sub(1, 1) == "/" or path:match("^%a:[/\\]") ~= nil
end

local function newHandle(image, name)
    image:setFilter(filterMin, filterMag)
    local w, h = image:getDimensions()
    local handle = { image = image, quad = false, width = w, height = h, name = name }
    owned[#owned + 1] = handle
    return handle
end

-- Reads a file outside the LOVE filesystem into an Image.
local function loadAbsolute(path)
    local f, err = io.open(path, "rb")
    if not f then error("Cannot open texture '" .. path .. "': " .. tostring(err)) end
    local contents = f:read("*a")
    f:close()
    local fileData = love.filesystem.newFileData(contents, nameOf(path) .. ".png")
    return love.graphics.newImage(love.image.newImageData(fileData))
end

function Texture.load(path)
    local handle = cache[path]
    if handle then return handle end
    local image
    if love.filesystem.getInfo(path) then
        image = love.graphics.newImage(path)
    elseif isAbsolute(path) then
        image = loadAbsolute(path)
    else
        image = love.graphics.newImage(path)
    end
    handle = newHandle(image, nameOf(path))
    cache[path] = handle
    return handle
end

function Texture.exists(path)
    local info = love.filesystem.getInfo(path)
    if info then return info.type == "file" end
    if isAbsolute(path) then
        local f = io.open(path, "rb")
        if f then
            f:close()
            return true
        end
    end
    return false
end

-- A sub rectangle of a texture. Works on sub textures as well.
function Texture.region(tex, x, y, w, h)
    local ox, oy = 0, 0
    if tex.quad then
        ox, oy = tex.quad:getViewport()
    end
    local iw, ih = tex.image:getDimensions()
    local quad = love.graphics.newQuad(ox + x, oy + y, w, h, iw, ih)
    return { image = tex.image, quad = quad, width = w, height = h, name = tex.name }
end

-- Builds a texture from fn(x, y) -> r, g, b, a with x, y starting at 0 and
-- colour components in 0..255 (alpha defaults to 255).
function Texture.fromPixels(w, h, fn, name)
    local data = love.image.newImageData(w, h)
    for y = 0, h - 1 do
        for x = 0, w - 1 do
            local r, g, b, a = fn(x, y)
            data:setPixel(x, y, r / 255, g / 255, b / 255, (a or 255) / 255)
        end
    end
    return newHandle(love.graphics.newImage(data), name or "pixels")
end

function Texture.size(tex)
    return tex.width, tex.height
end

-- Filter for every loaded and generated image, or for the image of one
-- texture; "nearest" for pixel art.
function Texture.setFilter(min, mag, tex)
    if tex then
        tex.image:setFilter(min, mag or min)
        return
    end
    filterMin, filterMag = min, mag or min
    for i = 1, #owned do
        owned[i].image:setFilter(filterMin, filterMag)
    end
end

return Texture
