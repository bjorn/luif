--
-- Texture database. TexDb[name] loads "<dir>/<name>.png" from the configured
-- image directories through the application host (core/host.lua) and
-- caches the handle. A few small
-- textures used by the default skins are generated when no file exists.
--
--   core.TexDb.setImageDirectories { "images", "images/icons" }
--   core.TexDb.setSlices("frame", 4, 4, 4, 4)      -- insets for Scale9 { source = "frame" }
--   local tex = core.TexDb.button                  -- images/button.png
--

local core = require "luif.core"

local Host = core.Host

local TexDb = {}

local directories = { "images" }
local cache = {}        -- name -> texture
local slices = {}       -- name -> { left, top, right, bottom }

-- Insets of the generated textures; TexDb.setSlices overrides them
slices.tooltip_box = { left = 6, top = 6, right = 6, bottom = 6 }

-- Maps a texture handle back to its name
TexDb.nameOf = setmetatable({}, { __mode = "k" })

function TexDb.setImageDirectories(list)
    directories = {}
    for i, dir in ipairs(list) do
        directories[i] = dir
    end
end

function TexDb.imageDirectories()
    return directories
end

-- Sets the filter ("nearest" or "linear") of all loaded and generated images
-- (on hosts with the textureFilter capability)
function TexDb.setFilter(min, mag)
    local host = Host.get()
    if host.setTextureFilter then
        host.setTextureFilter(min, mag or min)
    end
end

local function tryLoad(path)
    local ok, tex = pcall(Host.get().loadTexture, path)
    if ok and tex then
        return tex
    end
    return nil
end

local function fromPixels(width, height, pixel)
    return Host.get().createTexture(width, height, pixel)
end

local function loadFromDisk(name)
    for _, dir in ipairs(directories) do
        local tex = tryLoad(dir .. "/" .. name .. ".png")
        if tex then
            return tex
        end
    end
    return nil
end

-- Generated textures. The pixel functions return r, g, b, a in 0..255 for
-- pixel coordinates counted from 0.
local generators = {}

function generators.empty()
    return fromPixels(1, 1, function() return 0, 0, 0, 0 end)
end

function generators.white1x1()
    return fromPixels(1, 1, function() return 255, 255, 255, 255 end)
end

-- Vertical shading from white at the top to gray at the bottom
function generators.gradient01()
    local height = 64
    return fromPixels(1, height, function(x, y)
        local v = 255 - math.floor(115 * y / (height - 1))
        return v, v, v, 255
    end)
end

-- Solid line with soft edges along its thickness
function generators.line()
    return fromPixels(4, 4, function(x, y)
        local a = (y == 0 or y == 3) and 128 or 255
        return 255, 255, 255, a
    end)
end

-- Triangle pointing to the right
function generators.arrowhead()
    local size = 16
    return fromPixels(size, size, function(x, y)
        local half = (size - 1) / 2
        local inside = math.abs(y - half) <= (x / (size - 1)) * half
        return 255, 255, 255, inside and 255 or 0
    end)
end

-- A diagonal cross
function generators.close_button()
    local size = 12
    return fromPixels(size, size, function(x, y)
        local onCross = math.abs(x - y) <= 1 or math.abs(x - (size - 1 - y)) <= 1
        return 255, 255, 255, onCross and 255 or 0
    end)
end

-- Dark rounded box with a one pixel light border, for DefaultToolTipSkin
local TOOLTIP_BOX_SIZE, TOOLTIP_BOX_RADIUS = 16, 5

function generators.tooltip_box()
    local size, radius = TOOLTIP_BOX_SIZE, TOOLTIP_BOX_RADIUS
    return fromPixels(size, size, function(x, y)
        -- Distance of the pixel centre outside the inner rectangle
        local dx = math.max(radius - (x + 0.5), (x + 0.5) - (size - radius), 0)
        local dy = math.max(radius - (y + 0.5), (y + 0.5) - (size - radius), 0)
        local d = math.sqrt(dx * dx + dy * dy)
        local coverage = math.min(math.max(radius + 0.5 - d, 0), 1)
        if d > radius - 1.5 then
            return 128, 128, 128, math.floor(255 * coverage)
        end
        return 32, 32, 36, math.floor(235 * coverage)
    end)
end

local function generate(name)
    local generator = generators[name]
    return generator and generator() or nil
end

local function register(name, tex)
    cache[name] = tex
    TexDb.nameOf[tex] = name
    return tex
end

-- Returns the texture, or false when no file and no generator exists
function TexDb.try(name)
    local tex = cache[name]
    if tex then
        return tex
    end
    tex = loadFromDisk(name) or generate(name)
    if tex then
        return register(name, tex)
    end
    return false
end

setmetatable(TexDb, {
    __index = function(_, name)
        local tex = TexDb.try(name)
        if not tex then
            error("Texture '" .. tostring(name) .. "' not found in " ..
                  table.concat(directories, ", "), 2)
        end
        return tex
    end,
})

-- Registers the insets that slice the image for Scale9, ScaleH3 and ScaleV3
function TexDb.setSlices(name, left, top, right, bottom)
    slices[name] = { left = left, top = top, right = right, bottom = bottom }
end

-- The insets registered with setSlices, or nil
function TexDb.insets(name)
    return slices[name]
end

-- Drops all cached textures so they are reloaded on next access
function TexDb.clear()
    cache = {}
end

return TexDb
