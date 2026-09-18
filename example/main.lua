--
-- Example application: Luif running on LOVE.
--
-- A title screen and a demo screen are two pages of one item whose state
-- ("title" or "demo") drives a full screen Transition. Dialogs are modal and
-- live in the TopLayer.
--
-- Keys: Return enters the demo, Escape goes back (or asks to quit on the
-- title screen), F2 toggles the adaptive UI scale.
--
-- Environment, for headless runs:
--   LUIF_SCENE=<list>       comma separated: "demo" starts on the demo
--                           screen, "dialog" opens a dialog, "transition"
--                           starts the page switch just before the capture,
--                           "scaled" resizes the window to 1000x600 and
--                           toggles the scale like F2 (scale 0.52),
--                           "tooltip" hovers Start so its tooltip shows
--   LUIF_SCREENSHOT=<name>  writes <name>.png to the LOVE save directory
--                           after 1.5 seconds and quits
--   LUIF_SMOKE=1            quits after two seconds with exit code 0
--   LUIF_SELFTEST=1         clicks through both screens and the dialogs
--                           with injected input, exits 0 when all checks pass
--   LUIF_RECORD=<fps>       renders one loop of the animations (LOOP_MS),
--                           after one loop to settle, with a fixed frame
--                           time, writes the frames to
--                           record/frame0001.png and so on in the LOVE save
--                           directory and quits; LUIF_RECORD_FRAMES overrides
--                           the number of frames (tools/record-demo.sh)
--

-- The framework lives one directory up from this LOVE source directory.
-- LOVE keeps Lua's standard package searchers, so an absolute package.path
-- entry makes the framework requirable from here.
local root = love.filesystem.getSource() .. "/.."
package.path = root .. "/?.lua;" .. root .. "/?/init.lua;" .. package.path

-- Required under LOVE, Luif sets up its LOVE host
local luif = require "luif"
local core = require "luif.core"
local flag = os.getenv("LUIF_DEBUG")
core.Debug.setEnabled(flag ~= nil and flag ~= "" and flag ~= "0")

-- Fonts must be configured before labels are created
local FontDb = core.FontDb
FontDb.configure {
    Text   = { size = 14 },
    Small  = { size = 12 },
    Medium = { size = 18 },
    Large  = { size = 24 },
}

local Screen            = core.Screen
local TexDb             = core.TexDb
local FallbackListeners = core.FallbackListeners
local TopLayer          = core.TopLayer
local Pointer           = core.Pointer
local Sync              = core.Sync

-- Textures are loaded through love.filesystem, relative to this directory
TexDb.setImageDirectories { "images" }
TexDb.setSlices("frame_with_title", 36, 30, 36, 15)

local skins  = require "skins"
local Dialog = require "dialog"

-- Pixel art that is scaled up keeps its hard edges
local function pixelated(name)
    local texture = TexDb[name]
    texture.image:setFilter("nearest", "nearest")
    return texture
end
pixelated("login_background")
pixelated("frame_with_title")
pixelated("icon_money")

local STAGE_WIDTH, STAGE_HEIGHT = 1280, 720

local COLOR = {
    page        = 0xFF292B35,
    panel       = 0xFF32343F,
    panelBorder = 0xFF474B5C,
    text        = 0xFFE8E8E8,
    dim         = 0xFF9EA3B5,
    accent      = 0xFFFFD890,
}

love.graphics.setBackgroundColor(0.16, 0.17, 0.21)

local function text(value, x, y, color, font, width, align)
    return core.Label {
        text = value,
        x = x, y = y,
        color = color or COLOR.text,
        font = font or FontDb.Text,
        width = width,
        wrap = width ~= nil,
        align = align or "left",
    }
end

-- A titled panel; children are placed in panel coordinates
local function panel(title, x, y, width, height, children)
    local items = {
        x = x, y = y, width = width, height = height,
        core.Rectangle {
            x = 0, y = 0, width = width, height = height,
            color = COLOR.panel, borderColor = COLOR.panelBorder,
        },
        core.Image { source = "header_ornamental", x = 16, y = 17 },
        text(title, 62, 15, COLOR.accent, FontDb.Medium),
    }
    for i = 1, #children do
        items[#items + 1] = children[i]
    end
    return core.Item(items)
end

local dialog        -- created once the item tree exists
local showScreen    -- defined with the pages below

---------------------------------------------------------------------------
-- Demo screen: counters and the top bar
---------------------------------------------------------------------------

local clicks, coins = 0, 0
local counter = text("Clicks: 0", 960, 26, COLOR.text, FontDb.Medium, 200, "right")
local money = text("0", 152, 238)

local function countClick()
    clicks = clicks + 1
    counter:setText("Clicks: " .. clicks)
end

local function resetCounters()
    clicks, coins = 0, 0
    counter:setText("Clicks: 0")
    money:setText("0")
end

local topBar = {
    core.Button {
        skinClass = skins.CompactButtonSkin, text = "Back", id = "backButton",
        x = 32, y = 20,
        click = function() showScreen("title") end,
    },
    text("Widgets, transitions and animations", 120, 20, COLOR.text, FontDb.Large),
    counter,
    core.Button {
        skinClass = skins.CompactButtonSkin, text = "Reset", id = "resetButton",
        x = 1181, y = 20,
        click = function()
            dialog:open {
                title = "Reset",
                message = "Reset the click and coin counters?",
                confirmText = "Reset", cancelText = "Cancel",
                confirmed = resetCounters,
            }
        end,
    },
}

---------------------------------------------------------------------------
-- Panel: buttons with state transitions
---------------------------------------------------------------------------

local status = text("Nothing clicked yet", 20, 284, COLOR.accent)

local function report(message)
    status:setText(message)
    countClick()
end

local function earn(amount)
    coins = coins + amount
    money:setText(tostring(coins))
    countClick()
end

local sleeper = core.Button {
    skinClass = skins.BigButtonSkin, text = "Disabled", enabled = false,
    x = 306, y = 140,
    click = function() report("The enabled button was clicked") end,
}

local buttonsPanel = panel("Buttons and state transitions", 32, 72, 600, 320, {
    core.Button {
        skinClass = skins.BigButtonSkin, text = "Start", id = "startButton",
        x = 20, y = 52,
        focusOnPress = true,
        toolTip = "Tool tips are placed next to the pointer",
        toolTipClass = skins.ToolTip,
        click = function() report("Start was clicked") end,
    },
    core.Button {
        skinClass = skins.BigButtonSkin, text = "Options",
        x = 306, y = 52,
        focusOnPress = true,
        click = function() report("Options was clicked") end,
    },
    core.ToggleButton {
        skinClass = skins.RoundToggleSkin,
        x = 20, y = 159,
        change = function(selected)
            sleeper:setEnabled(selected)
            sleeper:setText(selected and "Enabled" or "Disabled")
        end,
    },
    text("Enables the button on the right", 62, 166, COLOR.dim),
    sleeper,
    core.Button { skinClass = skins.SmallButtonSkin, iconSource = "icon_money",
                  x = 20, y = 236, click = function() earn(1) end },
    core.Button { skinClass = skins.SmallButtonSkin, iconSource = "icon_money",
                  x = 54, y = 236, click = function() earn(10) end },
    core.Button { skinClass = skins.SmallButtonSkin, iconSource = "icon_money",
                  x = 88, y = 236, enabled = false },
    core.Image { source = "icon_money", x = 130, y = 240 },
    money,
    text("Icon buttons: +1, +10 and disabled", 200, 240, COLOR.dim),
    status,
})

---------------------------------------------------------------------------
-- Panel: toggle buttons and text input
---------------------------------------------------------------------------

local tabNames = { "Character", "Inventory", "Quest log", "Trade" }
local tabIcons = { "tab_icon_character", "tab_icon_inventory", "tab_icon_questlog", "tab_icon_trade" }

local tabTitle = text(tabNames[1], 200, 56, COLOR.text, FontDb.Medium)

local tabButtons = {
    layout = core.HorizontalLayout { gap = 6 },
    x = 20, y = 52, width = 154, height = 63,
    selectedButtonChanged = function(button)
        tabTitle:setText(button and button.text or "None")
    end,
}
for i = 1, #tabNames do
    tabButtons[i] = core.Tab {
        skinClass = skins.TabSkin, text = tabNames[i],
        iconSource = tabIcons[i], selected = i == 1,
    }
end

local typed = text("You typed: nothing yet", 20, 206)

local inputPanel = panel("Toggle buttons and text input", 32, 408, 600, 288, {
    core.ButtonGroup(tabButtons),
    tabTitle,
    text("Tabs are sticky toggle buttons in an exclusive ButtonGroup.",
         200, 86, COLOR.dim, nil, 380),
    core.LineEdit {
        skinClass = skins.LineEditSkin,
        x = 20, y = 160, width = 360, height = 30,
        placeholderText = "Type something",
        textChange = function(value)
            typed:setText("You typed: " .. (value == "" and "nothing yet" or value))
        end,
    },
    typed,
    text("Click the field to type. The arrows, Home and End move the caret, "
         .. "with Shift to select. Ctrl+A, C, X and V work too.",
         20, 236, COLOR.dim, nil, 560),
})

---------------------------------------------------------------------------
-- Panel: looping animations
---------------------------------------------------------------------------

-- Every animation below repeats a whole number of times in LOOP_MS, so the
-- panel as a whole loops too
local LOOP_MS = 3000

-- Widget rotation: an item turns with its children around its centre
local star = core.Item {
    x = 110 - 56.5, y = 50, width = 113, height = 113,
    core.Image { source = "star" },
}
star:start("spin", core.Rotate { from = 0, to = 360, duration = 3000, loops = "infinite" })

-- Image rotation around its centre. The dots are black, so a light round
-- plate sits behind them.
local spinner = core.Image { source = "progress-indicator", scale = 0.8 }
local spinnerBox = core.Item {
    x = 300 - 16, y = 90, width = 32, height = 32,
    scale = 2,
    core.Image { source = "roundbutton" },
    spinner,
}
spinner:start("spin", core.Rotate { from = 0, to = 360, duration = 1000, loops = "infinite" })

-- Alpha pulse: a Sequence of two Fades
local coin = core.Image { source = "icon_money", x = 490 - 7.5, y = 98, scale = 3 }
coin:start("pulse", core.Sequence { loops = "infinite",
    core.Fade { from = 255, to = 40, duration = 750, ease = "inOutSine" },
    core.Fade { from = 40, to = 255, duration = 750, ease = "inOutSine" },
})

-- Move, Parallel(Scale, Rotate) and Pause in one looping Sequence. A
-- Sequence prepares all children up front, so every step states its 'from'
-- value explicitly.
local ball = core.Image { source = "roundbutton", x = 24, y = 248 }
ball:start("bounce", core.Sequence { loops = "infinite",
    core.Move { properties = { "x" }, from = 24, to = 544, duration = 1150, ease = "inOutQuad" },
    core.Parallel {
        core.Scale { from = 1, to = 1.5, duration = 200 },
        core.Rotate { from = 0, to = 180, duration = 200 },
    },
    core.Pause { duration = 300 },
    core.Parallel {
        core.Scale { from = 1.5, to = 1, duration = 200 },
        core.Rotate { from = 180, to = 360, duration = 200 },
    },
    core.Move { properties = { "x" }, from = 544, to = 24, duration = 1150, ease = "inOutQuad" },
})

-- Children draw in order: the captions and the track come first so the
-- spinning star and the bouncing ball pass over them
local animationPanel = panel("Looping animations", 648, 72, 600, 320, {
    text("Rotate on a widget", 20, 186, COLOR.dim, nil, 180, "center"),
    text("Rotate on an image", 210, 186, COLOR.dim, nil, 180, "center"),
    text("Sequence of two Fades", 400, 186, COLOR.dim, nil, 180, "center"),
    core.Rectangle { x = 24, y = 262, width = 552, height = 4, color = 0xFF22242C },
    text("Sequence of Move, Parallel(Scale, Rotate) and Pause", 24, 288, COLOR.dim),
    star,
    spinnerBox,
    coin,
    ball,
})

---------------------------------------------------------------------------
-- Panel: a clipped scroll area with clickable rows
---------------------------------------------------------------------------

local rowStatus = text("No row clicked", 320, 56, COLOR.text, FontDb.Medium)

local rows = {}
for i = 1, 16 do
    rows[i] = core.Button {
        skinClass = skins.RowSkin, text = "Row " .. i,
        width = 268,
        click = function()
            rowStatus:setText("Row " .. i .. " clicked")
            countClick()
        end,
    }
end

local scrollPanel = panel("Clipping and scrolling", 648, 408, 600, 288, {
    core.ScrollArea {
        skinClass = skins.ScrollAreaSkin,
        x = 20, y = 52, width = 280, height = 216,
        content = core.Column { gap = 2, (unpack or table.unpack)(rows) },
    },
    rowStatus,
    text("The list is clipped by the node clip flag, and rows scrolled out of "
         .. "view do not react to the mouse. Scroll with the wheel, or click "
         .. "and drag in the track.",
         320, 92, COLOR.dim, nil, 260),
})

---------------------------------------------------------------------------
-- Title screen
---------------------------------------------------------------------------

local function askQuit()
    dialog:open {
        title = "Quit",
        message = "Do you want to leave the example?",
        confirmText = "Quit", cancelText = "Stay",
        confirmed = function() love.event.quit() end,
    }
end

local function showAbout()
    dialog:open {
        title = "About",
        message = "Luif, a Lua UI framework, running on LOVE 11.5. The artwork "
               .. "comes from the Source of Tales client.",
        confirmText = "OK",
    }
end

local backdrop = core.Image { texture = TexDb.login_background }

local logo = core.Image { source = "sourceoftales", x = 320, y = 104, width = 640, height = 129 }
logo:start("float", core.Sequence { loops = "infinite",
    core.Move { properties = { "y" }, from = 104, to = 118, duration = 1800, ease = "inOutSine" },
    core.Move { properties = { "y" }, from = 118, to = 104, duration = 1800, ease = "inOutSine" },
})

local menu = core.Column { x = 505, y = 318, width = 270, gap = 14,
    core.Button {
        skinClass = skins.BigButtonSkin, text = "Enter the demo", id = "enterButton",
        click = function() showScreen("demo") end,
    },
    core.Button {
        skinClass = skins.BigButtonSkin, text = "About", id = "aboutButton",
        click = showAbout,
    },
    core.Button {
        skinClass = skins.BigButtonSkin, text = "Quit", id = "quitButton",
        click = askQuit,
    },
}

local titlePage = core.Item {
    layout = core.AnchorLayout {},
    states = { demo = { alpha = 0, scale = 1.15 } },

    backdrop,
    core.Rectangle { color = 0xFF000000, alpha = 80, left = 0, top = 0, right = 0, bottom = 0 },
    core.Item {
        width = STAGE_WIDTH, height = STAGE_HEIGHT,
        horizontalCenter = 0, verticalCenter = 0,
        logo,
        menu,
    },
    core.Rectangle { color = 0xFF000000, alpha = 140, left = 0, right = 0, bottom = 0, height = 44 },
    core.Label {
        text = "Return enters the demo, Escape goes back, F2 toggles UI scaling",
        align = "center", color = COLOR.text,
        left = 0, right = 0, bottom = 13,
    },
}

---------------------------------------------------------------------------
-- Pages and the full screen transition
---------------------------------------------------------------------------

local demoStage = {
    width = STAGE_WIDTH, height = STAGE_HEIGHT,
    horizontalCenter = 0, verticalCenter = 0,
    buttonsPanel, inputPanel, animationPanel, scrollPanel,
}
for i = 1, #topBar do
    demoStage[#demoStage + 1] = topBar[i]
end

-- The demo page waits off screen to the right, transparent (so it is neither
-- drawn nor picked), and slides in while the title page fades and zooms.
local demoPage = core.Item {
    layout = core.AnchorLayout {},
    alpha = 0,
    states = { demo = { x = 0, alpha = 255 } },

    core.Rectangle { color = COLOR.page, left = 0, top = 0, right = 0, bottom = 0 },
    core.Item(demoStage),
}

local app = core.Item {
    state = "title",
    titlePage,
    demoPage,
    transitions = {
        core.Transition {
            core.Move { duration = 700, ease = "inOutCubic" },
            core.Fade { duration = 500, ease = "outQuad" },
            core.Scale { duration = 700, ease = "inOutCubic" },
        },
    },
}

function showScreen(name)
    app:setState(name)
end

local uiRoot = core.Item { id = "root", app }

-- Sizes everything to the virtual screen and covers it with the backdrop.
-- The UI scale itself is applied to every root by core/sync.lua.
local function layoutScreens(width, height)
    uiRoot:setSize(width, height)
    app:setSize(width, height)
    titlePage:setSize(width, height)
    demoPage:setSize(width, height)
    if app.state == "title" then
        demoPage:setX(width)
    end

    local scale = math.max(width / 480, height / 320)
    local coverWidth, coverHeight = 480 * scale, 320 * scale
    backdrop:setSize(coverWidth, coverHeight)
    backdrop:setX((width - coverWidth) / 2)
    local travel = height - coverHeight
    backdrop:start("pan", core.Sequence { loops = "infinite",
        core.Move { properties = { "y" }, from = 0, to = travel, duration = 9000, ease = "inOutSine" },
        core.Move { properties = { "y" }, from = travel, to = 0, duration = 9000, ease = "inOutSine" },
    })

    if dialog then
        dialog:fitToParent()
    end
end

layoutScreens(Screen.width, Screen.height)

Sync.addRoot(uiRoot)

-- Popups, drag items and dialogs live in the TopLayer, a root above uiRoot
-- that follows the virtual screen size itself
dialog = Dialog {}
TopLayer.instance():addChild(dialog)

-- Registered after the layer exists, so the layer is resized before the
-- dialog fits itself to it
Screen:on("changed", function(_, virtualWidth, virtualHeight)
    layoutScreens(virtualWidth, virtualHeight)
end)

---------------------------------------------------------------------------
-- Global keys. Keys that no item accepted end up in the fallback
-- listeners; an open dialog is an active focus scope above this one.
---------------------------------------------------------------------------

local function toggleUiScale()
    if Screen.adaptive then
        Screen:setScale(1)
    else
        Screen:setAdaptive(true)
    end
end

FallbackListeners.pushBottom {
    event = function(_, event)
        if event.name ~= "keyPress" then
            return false
        end
        local key = event:key()
        if key == "escape" then
            if app.state == "demo" then
                showScreen("title")
            else
                askQuit()
            end
        elseif event:isKey("return", "kpenter") and app.state == "title" then
            showScreen("demo")
        elseif key == "f2" then
            toggleUiScale()
        else
            return false
        end
        return true
    end,
}

---------------------------------------------------------------------------
-- Headless runs
---------------------------------------------------------------------------

local scene = {}
for name in (os.getenv("LUIF_SCENE") or ""):gmatch("[%w_]+") do
    scene[name] = true
end

if scene.scaled then
    love.window.updateMode(1000, 600)
    toggleUiScale()
end
if scene.demo then
    app:setState("demo", false)
end
if scene.dialog then
    if app.state == "demo" then
        dialog:open { title = "Reset", message = "Reset the click and coin counters?",
                      confirmText = "Reset", cancelText = "Cancel" }
    else
        showAbout()
    end
end

local selftest = os.getenv("LUIF_SELFTEST") and require("selftest") {
    root = uiRoot, app = app, dialog = dialog,
    titlePage = titlePage, demoPage = demoPage, counter = counter,
    scaled = scene.scaled,
}

-- Hovers an item through the pointer feed, which takes window pixels
local function hover(item)
    local x, y = item:absolutePos()
    local width, height = item:size()
    Pointer.sink.pointerMoved(Pointer.toWindow(x + width / 2, y + height / 2))
end
local hovered = false

local screenshot = os.getenv("LUIF_SCREENSHOT")
local smoke = os.getenv("LUIF_SMOKE")
local elapsed = 0
local transitionStarted = false
local captureRequested = false
local quitRequested = false

function love.update(dt)
    elapsed = elapsed + dt

    if selftest then
        selftest(dt)
    end

    if scene.tooltip and not hovered and elapsed >= 0.8 then
        hovered = true
        hover(uiRoot:findChild("startButton"))
    end

    if scene.transition and not transitionStarted and elapsed >= 1.2 then
        transitionStarted = true
        showScreen(app.state == "title" and "demo" or "title")
    end

    if screenshot and not captureRequested and elapsed >= 1.5 then
        captureRequested = true
        local name = screenshot
        if name == "" or name == "1" then
            name = "example"
        end
        if not name:match("%.png$") then
            name = name .. ".png"
        end
        love.graphics.captureScreenshot(function(imageData)
            imageData:encode("png", name)
            print("screenshot written to " .. love.filesystem.getSaveDirectory() .. "/" .. name)
            quitRequested = true
        end)
    end

    if quitRequested or (smoke and elapsed >= 2) then
        love.event.quit(0)
    end
end

luif.hook()

local record = tonumber(os.getenv("LUIF_RECORD") or "")
if record then
    local loop = math.floor(LOOP_MS * record / 1000 + 0.5)
    local frames = tonumber(os.getenv("LUIF_RECORD_FRAMES") or "") or loop
    local frame = -loop     -- one loop lets startup transitions settle
    love.filesystem.createDirectory("record")
    local hookedUpdate, hookedDraw = love.update, love.draw

    -- A fixed frame time, so the frames show exact points in the loop: frame
    -- n is n / record seconds into it, and the last one closes the loop
    function love.update()
        hookedUpdate(1 / record)
    end

    function love.draw()
        hookedDraw()
        frame = frame + 1
        if frame > frames then
            love.event.quit(0)
            return
        elseif frame < 1 then
            return
        end
        local name = ("record/frame%04d.png"):format(frame)
        love.graphics.captureScreenshot(function(imageData)
            imageData:encode("png", name)
        end)
    end
end
