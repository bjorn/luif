--
-- The luif entry module: classes by name, the screen root and, under LOVE,
-- the callbacks with their handled results and hook().
--
return function(t)
    local luif = require "luif"
    local Sync = require "luif.core.sync"
    local Update = require "luif.core.update"
    local Pointer = require "luif.core.pointer"

    t.eq(luif.Item, require "luif.core.item", "classes are reachable by name")
    t.eq(luif.skins.DefaultButtonSkin, require "luif.core.skins.defaultbuttonskin",
         "and skins through luif.skins")

    local root = luif.root
    t.ok(root == luif.root and Sync.isRoot(root), "luif.root is one registered root")
    t.ok(root.layout and root.layout:as(luif.AnchorLayout), "with an AnchorLayout")
    local width, height = root:size()
    t.ok(width == Update.virtualScreenWidth and height == Update.virtualScreenHeight,
         "covering the virtual screen")
    Update:setUiScale(2)
    width, height = root:size()
    t.ok(width == Update.virtualScreenWidth and height == Update.virtualScreenHeight,
         "and following the UI scale")
    Update:setUiScale(1)

    if not rawget(luif, "mousepressed") then
        t.skip("the LOVE callbacks need LOVE")
        return
    end

    local previousHost = Pointer.host()
    local item = luif.Item { x = 10, y = 10, width = 50, height = 30, mouseEnabled = true }
    local input = luif.TextInput { x = 10, y = 100, width = 100, height = 20 }
    root:addChild(item)
    root:addChild(input)
    luif.update(0)

    t.eq(luif.mousepressed(20, 20, 1, false, 1), true, "a press on an item is handled")
    t.eq(luif.mousereleased(20, 20, 1, false, 1), true, "and so is its release")
    t.eq(luif.mousepressed(300, 300, 1, false, 1), false, "a press on no item is not handled")
    t.eq(luif.mousereleased(20, 20, 1, false, 1), false, "nor its release, even over an item")
    luif.mousemoved(300, 300, 0, 0, false)
    t.eq(luif.wheelmoved(0, 1), false, "the wheel over no item is not handled")
    luif.mousemoved(20, 20, 0, 0, false)
    t.eq(luif.wheelmoved(0, 1), true, "the wheel over an item is handled")
    luif.mousemoved(300, 300, 0, 0, false)
    t.eq(luif.keypressed("x", "x", false), false, "a key without a focused item is not handled")
    input:setFocus()
    t.eq(luif.textinput("a"), true, "text a focused text input accepts is handled")
    t.eq(input.text, "a", "and reaches it")
    input:setFocus(false)

    -- hook() chains the game's callbacks
    local names = { "update", "draw", "mousemoved", "mousepressed", "mousereleased",
                    "wheelmoved", "keypressed", "keyreleased", "textinput", "mousefocus" }
    local saved = {}
    for _, name in ipairs(names) do saved[name] = love[name] end
    local game = {}
    love.update = function() game[#game + 1] = "update" end
    love.draw = function() game[#game + 1] = "draw" end
    love.mousepressed = function() game[#game + 1] = "press" end
    love.mousereleased = function() game[#game + 1] = "release" end
    love.mousemoved = function() game[#game + 1] = "move" end
    luif.hook()
    love.update(0)
    love.draw()
    love.mousemoved(20, 20, 0, 0, false)
    love.mousepressed(20, 20, 1, false, 1)
    love.mousereleased(20, 20, 1, false, 1)
    love.mousepressed(300, 300, 1, false, 1)
    love.mousereleased(300, 300, 1, false, 1)
    t.eq(table.concat(game, ","), "update,draw,move,press,release",
         "hook: the game updates and draws, gets moves, and misses input the UI handled")
    for _, name in ipairs(names) do love[name] = saved[name] end

    item:delete()
    input:delete()
    luif.update(0)
    Pointer.reset()
    Pointer.attach(previousHost)
end
