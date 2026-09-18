--
-- What the example needs from the application it runs in, which is LOVE
-- (love example) or the SDL3 runner (luif-sdl example, with its "app"
-- module: sdl/app/app_api.h). Both branches return the same table:
--
--   platform.name                     "love" or "sdl"
--   platform.description              for the About dialog
--   platform.source                   the example's directory
--   platform.quit(code)
--   platform.setBackgroundColor(color)    packed 0xAARRGGBB
--   platform.setWindowSize(width, height)
--   platform.windowSize()             width, height in pixels
--   platform.onUpdate(fn)             fn(dt) runs every frame, before the UI
--                                     updates
--   platform.setFrameTime(seconds)    a fixed dt for every update; nil
--                                     returns to real time
--   platform.screenshot(name, done)   writes the frame of this update to
--                                     <name> (in the LOVE save directory, or
--                                     the current directory on SDL), prints
--                                     the path and then calls done
--   platform.run()                    call last: hooks Luif into the LOVE
--                                     callbacks; the SDL runner drives Luif
--                                     from its own loop
--
-- Requiring this file also puts the framework, which lives one directory up
-- from the example, on package.path.
--

local platform = {}

local function addFramework(source)
    local root = source .. "/.."
    package.path = root .. "/?.lua;" .. root .. "/?/init.lua;" .. package.path
end

if love then
    platform.name = "love"
    platform.description = "LOVE 11.5"
    platform.source = love.filesystem.getSource()

    -- LOVE keeps Lua's standard package searchers, so an absolute
    -- package.path entry makes the framework requirable
    addFramework(platform.source)

    local frameTime = nil

    function platform.quit(code)
        love.event.quit(code or 0)
    end

    function platform.setBackgroundColor(color)
        love.graphics.setBackgroundColor(
            math.floor(color / 0x10000) % 256 / 255,
            math.floor(color / 0x100) % 256 / 255,
            color % 256 / 255)
    end

    function platform.setWindowSize(width, height)
        love.window.updateMode(width, height)
    end

    function platform.windowSize()
        return love.graphics.getDimensions()
    end

    function platform.onUpdate(fn)
        local previous = love.update
        function love.update(dt)
            if previous then previous(dt) end
            fn(dt)
        end
    end

    function platform.setFrameTime(seconds)
        frameTime = seconds
    end

    -- LOVE captures when the frame is presented, so this is the frame of
    -- the update that asked
    function platform.screenshot(name, done)
        local directory = name:match("^(.*)/[^/]*$")
        if directory then
            love.filesystem.createDirectory(directory)
        end
        love.graphics.captureScreenshot(function(imageData)
            imageData:encode("png", name)
            print("screenshot written to " .. love.filesystem.getSaveDirectory() .. "/" .. name)
            if done then done() end
        end)
    end

    function platform.run()
        require("luif").hook()

        -- Around the hooked update, so the UI gets the fixed frame time too
        local update = love.update
        function love.update(dt)
            update(frameTime or dt)
        end
    end
else
    local app = require "app"

    platform.name = "sdl"
    platform.description = "SDL3"
    platform.source = app.source
    addFramework(app.source)

    -- What conf.lua does under LOVE
    app.setTitle("Luif on SDL3")

    -- With luif-sdl --watch, changes to the framework reload the example too
    app.watch(app.source .. "/../luif")

    platform.quit = app.quit
    platform.setBackgroundColor = app.setBackgroundColor
    platform.setWindowSize = app.setWindowSize
    platform.windowSize = app.windowSize
    platform.setFrameTime = app.setFrameTime

    local updates = {}
    local saved = {}    -- the done callbacks of screenshots taken last frame

    function platform.onUpdate(fn)
        updates[#updates + 1] = fn
    end

    function app.update(dt)
        local callbacks = saved
        saved = {}
        for i = 1, #callbacks do
            callbacks[i]()
        end
        for i = 1, #updates do
            updates[i](dt)
        end
    end

    -- The runner saves the frame it renders after this update and prints
    -- the path
    function platform.screenshot(name, done)
        app.screenshot(name)
        saved[#saved + 1] = done
    end

    function platform.run() end
end

return platform
