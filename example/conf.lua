--
-- LOVE configuration of the example: a resizable 1280x720 window.
--

function love.conf(t)
    t.identity = "luif_example"
    t.version = "11.5"
    t.window.title = "Luif on LOVE"
    t.window.width = 1280
    t.window.height = 720
    t.window.resizable = true
    t.window.vsync = 1
end
