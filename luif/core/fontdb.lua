--
-- Font database. Fonts are created lazily through the application host
-- (core/host.lua, loadFont) and cached by name. The defaults use the host's
-- built in font; an application can override them before the first use
-- (shadow = { dx, dy, color }, outline = { color }):
--
--   core.FontDb.configure {
--       Text   = { file = "fonts/regular.ttf", size = 14 },
--       Medium = { file = "fonts/bold.ttf", size = 16 },
--   }
--
-- FontDb[name] for an unknown name falls back to the Text specification.
--

local core = require "luif.core"

local Host = core.Host

local FontDb = {}

local specs = {
    Text         = { size = 13 },
    Small        = { size = 11 },
    Medium       = { size = 15 },
    Large        = { size = 20 },
    TextShadowed = { size = 13, shadow = { 1, 1, 0xFF000000 } },
    TextOutlined = { size = 13, outline = { 0xFF000000 } },
}

local fonts = {}

local function build(name)
    local spec = specs[name] or specs.Text
    return Host.get().loadFont {
        name = name,
        file = spec.file or false,
        size = spec.size or 13,
        shadow = spec.shadow or false,
        outline = spec.outline or false,
    }
end

-- Replaces the specification of the given fonts; already built fonts are
-- rebuilt on next access.
function FontDb.configure(config)
    for name, spec in pairs(config) do
        specs[name] = spec
        fonts[name] = nil
    end
end

function FontDb.spec(name)
    return specs[name]
end

setmetatable(FontDb, {
    __index = function(_, name)
        local font = fonts[name]
        if not font then
            font = assert(build(name), "Failed to create font " .. tostring(name))
            fonts[name] = font
        end
        return font
    end,
})

return FontDb
