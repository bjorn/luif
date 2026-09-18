-- Localization, action bindings, sounds, text, events, labels, texture and
-- font databases, the clip flag and the top layer.
return function(t)
    local module = require "luif.module"
    local core = module "luif.core"
    local Host = require "luif.core.host"
    local textureSize = Host.textureSize

    -- Localization
    local Localization = require "luif.core.localization"
    t.eq(Localization.localize("Plain"), "Plain", "localize identity fallback")
    Localization.load { ok = "OK" }
    t.eq(Localization.localize("ok"), "OK", "localize loaded string")
    t.eq(Localization.pluralForm(1), 0, "plural form singular")
    t.eq(Localization.pluralForm(3), 1, "plural form plural")

    -- Text substitution on top of it
    t.eq(core.Text("Hello {1}", "world"):get(), "Hello world", "text substitution")
    t.eq(core.Text("{1} {p item items}", 2):get(), "2 items", "text plural")
    t.eq(core.Text("{1} {p item items}", 1):get(), "1 item", "text singular")
    t.eq(core.Text("ok"):get(), "OK", "text localized")
    t.eq(core.Label { text = "50% {braces}" }.text, "50% {braces}", "a label keeps its string by default")
    t.eq(core.Label { text = "ok", localize = true }.text:get(), "OK", "localize = true runs it through Text")

    -- Action bindings
    local ActionBindings = require "luif.core.actionbindings"
    t.eq(ActionBindings.mapKeyPress("space"), "Activate", "space activates")
    t.eq(ActionBindings.mapKeyPress("return"), "Activate", "return activates")
    t.eq(ActionBindings.mapKeyPress("kpenter"), "Activate", "keypad enter activates")
    t.eq(ActionBindings.mapKeyPress("a"), false, "letter unbound")
    ActionBindings.setBinding("a", "Test")
    t.eq(ActionBindings.mapKeyPress("a"), "Test", "custom binding")
    ActionBindings.setBinding("a", false)
    t.eq(ActionBindings.mapKeyPress("a"), false, "binding removed")

    -- Sounds
    local Sounds = require "luif.core.sounds"
    t.eq(Sounds.play(Sounds.UI.Click), nil, "play without handler")
    local played, params
    Sounds.handler = function(name, parameters) played, params = name, parameters; return 7 end
    t.eq(Sounds.play(Sounds.UI.Hover, { volume = 1 }), 7, "handler return value")
    t.eq(played, "ui/hover", "handler name")
    t.eq(params and params.volume, 1, "handler parameters")
    Sounds.handler = false

    -- Events are plain Event objects with key names
    local event = core.Event { name = "keyCharacter", typed = "é" }
    t.eq(event.name, "keyCharacter", "event name")
    t.eq(event:text(), "é", "event text")
    t.eq(event:key(), nil, "text input has no key")
    t.ok(event.accepted and not event:controlDown() and not event:mouseDown(), "event defaults")
    t.raises(function() return core.Event { typed = "x" } end,
             "a table without a name is not an event")
    event = core.Event { name = "keyPress", keyName = "return", ctrl = true, autoRepeat = true }
    t.eq(event:key(), "return", "Event:key")
    t.ok(event:isKey("kpenter", "return") and not event:isKey("space"), "Event:isKey")
    t.ok(event:controlDown() and event:modifierDown("ctrl") and event:modifierDown()
         and not event:shiftDown(), "modifiers")
    t.eq(event:isAutoRepeat(), true, "auto repeat")
    event = core.Event { name = "mousePress", localX = 1, localY = 2, absX = 3, absY = 4,
                         mouseButton = core.MouseButton.Right, buttons = { [2] = true } }
    t.ok(event:x() == 1 and event:y() == 2 and select(2, event:absolutePos()) == 4, "positions")
    t.ok(event:button() == 2 and event:mouseDown(2) and not event:mouseDown(1), "buttons")
    t.eq(core.Event.keyDisplayName("pageup"):get(), "Page Up", "readable key name")
    t.eq(core.Event.keyDisplayName("f5"):get(), "F5", "capitalized key name")
    Localization.load { ["Page Up"] = "Bild auf" }
    t.eq(core.Event.keyDisplayName("pageup"):get(), "Bild auf", "translated key name")

    -- Key helpers
    local Keys = require "luif.core.keys"
    t.eq(Keys.modifierOf.rctrl, "ctrl", "modifier of a key")
    t.ok(Keys.isReturn("kpenter") and not Keys.isReturn("space"), "isReturn")
    t.ok(Keys.isPrintable("a") and not Keys.isPrintable("\t") and not Keys.isPrintable("\127"),
         "isPrintable")

    -- Fonts
    local FontDb = require "luif.core.fontdb"
    t.ok(FontDb.Text ~= nil, "default font built")
    t.eq(FontDb.Text, FontDb.Text, "font cached")
    t.eq(FontDb.spec("TextShadowed").shadow[3], 0xFF000000, "shadow spec")
    t.ok(FontDb.TextShadowed ~= FontDb.Text, "a shadowed font is another font")
    -- Font handles are opaque, so sizes are compared through the host
    local lineHeight = require("luif.core.host").get().lineHeight
    FontDb.configure { Custom = { size = 21 } }
    t.ok(FontDb.Custom ~= FontDb.Text, "configured font")
    t.eq(lineHeight(FontDb.Unknown), lineHeight(FontDb.Text), "unknown font falls back to Text")

    -- Textures: generated ones and files from the example directory
    local TexDb = require "luif.core.texdb"
    t.eq(TexDb.try("does_not_exist"), false, "try missing texture")
    t.raises(function() return TexDb.does_not_exist end, "missing texture errors")
    local w, h = textureSize(TexDb.empty)
    t.ok(w == 1 and h == 1, "empty is 1x1")
    t.eq(TexDb.empty, TexDb.empty, "generated texture cached")
    t.eq(TexDb.nameOf[TexDb.white1x1], "white1x1", "nameOf generated")
    t.ok(select(2, textureSize(TexDb.gradient01)) > 1, "gradient has height")
    t.ok(TexDb.line and TexDb.arrowhead and TexDb.close_button, "other generated textures")

    local imageDirectories = TexDb.imageDirectories()
    TexDb.setImageDirectories { require("tests.root") .. "/example/images" }
    local button = TexDb.try("button")
    if button then
        t.eq(TexDb.nameOf[button], "button", "nameOf loaded")
        t.eq(TexDb.button, button, "loaded texture cached")
        local bw, bh = textureSize(button)
        t.ok(bw > 0 and bh > 0, "loaded texture has size")

        local fw, fh = textureSize(TexDb.simpleframe)
        TexDb.setSlices("simpleframe", 4, 3, 5, 2)
        local insets = TexDb.insets("simpleframe")
        t.ok(insets.left == 4 and insets.top == 3 and insets.right == 5 and insets.bottom == 2,
             "slices registered")

        -- One image plus insets
        local nine = core.Scale9 { source = "simpleframe" }
        t.ok(nine.implicitWidth == fw and nine.implicitHeight == fh, "Scale9 implicit size is the image size")
        t.ok(nine.minimumWidth == 9 and nine.minimumHeight == 5, "Scale9 minimum size holds the corners")
        -- The slices an item pushes as its content
        local function slicesOf(item)
            local content
            item:pushContent({ setSlices = function(_, texture, left, top, right, bottom)
                content = { kind = "slices", texture = texture, left = left, top = top,
                            right = right, bottom = bottom }
            end })
            return content
        end
        local content = slicesOf(nine)
        t.ok(content.kind == "slices" and content.texture == TexDb.simpleframe and content.left == 4
             and content.top == 3 and content.right == 5 and content.bottom == 2,
             "Scale9 slices the image by its insets")
        local three = core.ScaleH3 { source = "simpleframe" }
        content = slicesOf(three)
        t.ok(three.implicitWidth == fw and three.implicitHeight == fh and content.left == 4
             and content.right == 5 and content.top == 0 and content.bottom == 0,
             "ScaleH3 slices by the left and right insets")
        local column = core.ScaleV3 { texture = TexDb.simpleframe, insets = { top = 6, bottom = 7 } }
        content = slicesOf(column)
        t.ok(content.left == 0 and content.right == 0 and content.top == 6 and content.bottom == 7,
             "ScaleV3 slices an explicit texture by the top and bottom insets")
        t.raises(function() return core.Scale9 { source = "button" } end,
                 "Scale9 requires slices registered for its source")
        nine:delete()
        three:delete()
        column:delete()
    else
        t.skip("example images not reachable")
    end
    TexDb.setImageDirectories(imageDirectories)

    -- Clip flag on the item's host node, and the top layer
    local Sync = require "luif.core.sync"
    local clipped = core.Item { width = 10, height = 10, clip = true }
    Sync.addRoot(clipped)
    Sync.flush()
    local clipHost = Sync.host(clipped)
    t.eq(#clipped.children, 0, "clip adds no child")
    t.eq(clipHost.inspect(Sync.node(clipped)).clip, true, "clip flag on node")
    clipped:setClip(false)
    Sync.flush()
    t.eq(clipHost.inspect(Sync.node(clipped)).clip, false, "clip flag cleared")
    clipped:setClip(true)
    clipped:setSize(20, 20)
    Sync.flush()
    local snapshot = clipHost.inspect(Sync.node(clipped))
    t.ok(snapshot.clip == true and snapshot.width == 20, "clip survives resize")
    clipped:delete()
    Sync.flush()

    local TopLayer = require "luif.core.toplayer"
    local layer = TopLayer.instance()
    t.ok(layer:isAttached(), "top layer created")
    t.eq(TopLayer.instance(), layer, "top layer is a singleton")
    local root = core.Item { width = 100, height = 100 }
    Sync.addRoot(root)
    TopLayer.setRoot(root)
    t.eq(layer.parent, root, "top layer parented under root")
    local other = core.Item { width = 1, height = 1 }
    root:addChild(other)
    TopLayer.instance()
    t.eq(root.children[#root.children], layer, "top layer moved to top")
    TopLayer.setRoot(false)
    t.eq(layer.parent, false, "top layer back at root level")
    t.ok(layer:isAttached() and Sync.isRoot(layer), "top layer registered as a root again")
    root:delete()
    Sync.flush()
end
