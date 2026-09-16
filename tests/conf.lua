function love.conf(t)
    t.identity = "luif_tests"
    t.version = "11.5"
    t.console = false
    t.window.title = "Luif tests"
    t.window.width = 640
    t.window.height = 480
    t.window.resizable = false
    t.window.vsync = 0
    t.modules.audio = false
    t.modules.joystick = false
    t.modules.physics = false
    t.modules.video = false
end
