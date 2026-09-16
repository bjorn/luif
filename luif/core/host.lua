--
-- The application's host (host/interface.lua): where core gets its platform
-- services. The application sets it once, before creating items:
--
--   luif.setHost(host)
--
-- Core reads time, screen size, clipboard, cursor, textures, fonts and file
-- contents through it (Host.get()), and core/sync.lua puts new roots into
-- it unless Sync.setHost overrides that. core/pointer.lua is attached to a
-- host separately (Pointer.attach), because only a host with input feeds it.
--

local Host = {}

local current = false

function Host.set(host)
    current = host or false
end

-- The host, or an error when the application did not set one.
function Host.get()
    if not current then
        error("no host set: call luif.setHost(host) first", 2)
    end
    return current
end

-- The host, or nil.
function Host.current()
    return current or nil
end

-- Width and height of a texture handle of the host.
function Host.textureSize(texture)
    return Host.get().textureSize(texture)
end

-- The host's clock in milliseconds, 0 without a host.
function Host.time()
    return current and current.time() or 0
end

return Host
