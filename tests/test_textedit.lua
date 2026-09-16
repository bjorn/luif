--
-- Text editing: the pure Lua model in core.TextEdit with a fake
-- monospace measure, and core.TextInput driven by raw events.
--

local function len(s)
    local n = 0
    for _ in s:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
        n = n + 1
    end
    return n
end

-- 7 pixels per character, 12 pixels per line, greedy word wrap that drops
-- the space at each break (like LOVE's getWrap)
local measure = {
    getWidth = function(s) return 7 * len(s) end,
    getHeight = function() return 12 end,
    wrap = function(s, width)
        local lines, current = {}, ""
        for word, space in s:gmatch("(%S*)(%s*)") do
            if word == "" and space == "" then break end
            local candidate = current .. word
            if current ~= "" and 7 * len(candidate) > width then
                lines[#lines + 1] = current:gsub("%s+$", "")
                current = word .. space
            else
                current = candidate .. space
            end
        end
        lines[#lines + 1] = current
        return lines
    end,
}

local function rectString(rects)
    local parts = {}
    for i, r in ipairs(rects) do
        parts[i] = r.x .. "," .. r.y .. "," .. r.w .. "," .. r.h
    end
    return table.concat(parts, " ")
end

local function modelTests(t, TextEdit)
    local e = TextEdit { text = "hello world", measure = measure }
    t.eq(e:length(), 11, "length")
    t.eq(e.caret, 0, "caret starts at 0")

    e:moveCaret("Right")
    t.eq(e.caret, 1, "Right")
    e:moveCaret("Left")
    e:moveCaret("Left")
    t.eq(e.caret, 0, "Left clamps at 0")
    e:moveCaret("End")
    t.eq(e.caret, 11, "End")
    e:moveCaret("Right")
    t.eq(e.caret, 11, "Right clamps at end")
    e:moveCaret("Start")
    t.eq(e.caret, 0, "Start")

    -- Word operations
    e:moveCaret("WordRight")
    t.eq(e.caret, 6, "WordRight skips word and space")
    e:moveCaret("WordRight")
    t.eq(e.caret, 11, "WordRight to end")
    e:moveCaret("WordLeft")
    t.eq(e.caret, 6, "WordLeft to word start")
    e:moveCaret("WordLeft")
    t.eq(e.caret, 0, "WordLeft to start")
    e:setText("foo, bar")
    e:setCaretPos(0)
    e:moveCaret("WordRight")
    t.eq(e.caret, 3, "WordRight stops at punctuation")
    e:moveCaret("WordRight")
    t.eq(e.caret, 5, "WordRight over punctuation and space")
    local first, last = e:wordRangeAt(6)
    t.ok(first == 5 and last == 8, "wordRangeAt")
    e:selectWordAt(1)
    t.eq(e:selectedText(), "foo", "selectWordAt")
    e:extendWordSelection(1, 6)
    t.eq(e:selectedText(), "foo, bar", "extendWordSelection forward")
    e:extendWordSelection(6, 1)
    t.eq(e:selectedText(), "foo, bar", "extendWordSelection backward")
    t.ok(e.caret == 0 and e.anchor == 8, "backward word selection caret at start")

    -- Selection
    e:setText("hello world")
    e:setCaretPos(0)
    e:moveCaret("WordRight", true)
    t.ok(e:hasSelection(), "shift WordRight selects")
    t.eq(e:selectedText(), "hello ", "selected text")
    local s, f = e:selectionRange()
    t.ok(s == 0 and f == 6, "selection range")
    e:moveCaret("Left")
    t.ok(e.caret == 0 and not e:hasSelection(), "Left collapses to selection start")
    e:setCaretPos(8, false)
    e:setCaretPos(2, true)
    t.eq(e:selectedText(), "llo wo", "reversed selection")
    e:moveCaret("Right")
    t.ok(e.caret == 8 and not e:hasSelection(), "Right collapses to selection end")
    e:selectAll()
    t.eq(e:selectedText(), "hello world", "selectAll")

    -- Insert replaces the selection
    t.ok(e:insert("bye"), "insert returns true")
    t.eq(e.text, "bye", "insert replaced selection")
    t.eq(e.caret, 3, "caret after insert")
    e:setCaretPos(1)
    e:insert("éx")
    t.eq(e.text, "béxye", "insert multibyte in the middle")
    t.eq(e.caret, 3, "caret counts codepoints")

    -- maxLength
    local m = TextEdit { text = "abc", maxLength = 5, measure = measure }
    m:setCaretPos(3)
    m:insert("defgh")
    t.eq(m.text, "abcde", "maxLength truncates insert")
    t.eq(m:insert("x"), false, "insert at maxLength refused")
    m:setCaretPos(0)
    m:moveCaret("Right", true)
    m:insert("xyz")
    t.eq(m.text, "xbcde", "maxLength with selection replaced")
    t.eq(m:insertTest("q"), "xbcde", "insertTest respects maxLength")
    t.eq(m.text, "xbcde", "insertTest leaves text alone")

    -- Numeric filtering and newlines
    local n = TextEdit { numeric = true, measure = measure }
    n:insert("a1b2")
    t.eq(n.text, "12", "numeric drops non digits")
    t.eq(n:insert("x"), false, "numeric refuses letters")
    local single = TextEdit { measure = measure }
    single:insert("a\r\nb\nc")
    t.eq(single.text, "a b c", "single line turns newlines into spaces")
    local multi = TextEdit { multiline = true, measure = measure }
    multi:insert("a\r\nb")
    t.eq(multi.text, "a\nb", "multiline keeps newlines")

    -- Delete
    local d = TextEdit { text = "abc", measure = measure }
    d:setCaretPos(1)
    d:deleteForward()
    t.ok(d.text == "ac" and d.caret == 1, "deleteForward")
    d:deleteBackward()
    t.ok(d.text == "c" and d.caret == 0, "deleteBackward")
    t.eq(d:deleteBackward(), false, "deleteBackward at start")
    d:setCaretPos(1)
    t.eq(d:deleteForward(), false, "deleteForward at end")
    d:setText("one two")
    d:setCaretPos(7)
    d:moveCaret("WordLeft", true)
    d:deleteBackward()
    t.eq(d.text, "one ", "delete selection")

    -- caretPosAt and caretRect
    local c = TextEdit { text = "hello world", measure = measure }
    c:setCaretPos(3)
    local x, y, w, h = c:caretRect()
    t.ok(x == 21 and y == 0 and w == 1 and h == 12, "caretRect")
    t.eq(c:caretPosAt(24, 5), 3, "caretPosAt rounds down to nearest")
    t.eq(c:caretPosAt(25, 5), 4, "caretPosAt rounds up to nearest")
    t.eq(c:caretPosAt(-5, 0), 0, "caretPosAt left of text")
    t.eq(c:caretPosAt(1000, 40), 11, "caretPosAt right of text")
    local roundTrip = true
    for pos = 0, c:length() do
        c:setCaretPos(pos)
        local cx, cy = c:caretRect()
        if c:caretPosAt(cx, cy) ~= pos then
            roundTrip = false
        end
    end
    t.ok(roundTrip, "caretPosAt round trips caretRect")
    t.eq(#c:selectionRects(), 0, "no selection rects without selection")
    c:setCaretPos(2)
    c:setCaretPos(5, true)
    t.eq(rectString(c:selectionRects()), "14,0,21,12", "single line selection rect")

    -- Multiline with wrap: lines "aaaa", "bbbb", "cccc" (positions 0-4, 5-9, 10-14)
    local wrap = TextEdit { text = "aaaa bbbb cccc", multiline = true, wrapWidth = 35,
                            measure = measure }
    local lines = wrap:lines()
    t.eq(#lines, 3, "wrapped line count")
    t.ok(lines[2].text == "bbbb" and lines[2].first == 5 and lines[2].last == 9,
         "wrapped line range")
    t.eq(wrap:height(), 36, "wrapped height")
    wrap:setCaretPos(7)
    x, y = wrap:caretRect()
    t.ok(x == 14 and y == 12, "caretRect on wrapped line")
    t.eq(wrap:caretPosAt(14, 13), 7, "caretPosAt on wrapped line")
    wrap:moveCaret("StartOfLine")
    t.eq(wrap.caret, 5, "StartOfLine")
    wrap:moveCaret("EndOfLine")
    t.eq(wrap.caret, 9, "EndOfLine")
    wrap:setCaretPos(7)
    wrap:moveCaret("Up")
    t.eq(wrap.caret, 2, "Up")
    wrap:moveCaret("Down")
    t.eq(wrap.caret, 7, "Down")
    wrap:moveCaret("Down")
    t.eq(wrap.caret, 12, "Down to last line")
    wrap:moveCaret("Down")
    t.eq(wrap.caret, 14, "Down past last line goes to end")
    wrap:moveCaret("Up")
    t.eq(wrap.caret, 7, "Up keeps the preferred x")
    wrap:moveCaret("Up", true)
    t.eq(wrap:selectedText(), "aa bb", "shift Up selects")
    wrap:setCaretPos(2)
    wrap:setCaretPos(12, true)
    t.eq(rectString(wrap:selectionRects()), "14,0,21,12 0,12,35,12 0,24,14,12",
         "selection rects across wrapped lines")
    wrap:setWrapWidth(70)
    t.eq(#wrap:lines(), 2, "wrap width change invalidates layout")
    wrap:setMultiline(false)
    t.eq(#wrap:lines(), 1, "single line ignores wrap width")
    wrap:setMultiline(true)
    wrap:setCaretPos(14)
    wrap:insert(" dddd eeee")
    t.eq(#wrap:lines(), 3, "insert invalidates layout")

    -- Paragraphs: "ab", "cd", "", "ef"
    local p = TextEdit { text = "ab\ncd\n\nef", multiline = true, measure = measure }
    t.eq(#p:lines(), 4, "paragraph line count")
    p:moveCaret("ParagraphDown")
    t.eq(p.caret, 2, "ParagraphDown to paragraph end")
    p:moveCaret("ParagraphDown")
    t.eq(p.caret, 5, "ParagraphDown to next paragraph end")
    p:moveCaret("End")
    p:moveCaret("ParagraphUp")
    t.eq(p.caret, 7, "ParagraphUp to paragraph start")
    p:moveCaret("ParagraphUp")
    t.eq(p.caret, 6, "ParagraphUp to empty paragraph")
    p:setCaretPos(8)
    p:moveCaret("Up")
    t.eq(p.caret, 6, "Up onto empty line")
    p:setCaretPos(1)
    p:moveCaret("Down")
    t.eq(p.caret, 4, "Down across newline")
    p:setCaretPos(1)
    p:setCaretPos(4, true)
    t.eq(rectString(p:selectionRects()), "7,0,14,12 0,12,7,12", "selection rects across newline")
    t.raises(function() p:moveCaret("Sideways") end, "unknown operation")

    -- Clipboard helpers
    local stored = ""
    local clipboard = {
        get = function() return stored end,
        set = function(s) stored = s end,
    }
    local cb = TextEdit { text = "copy paste", measure = measure }
    t.eq(cb:copy(clipboard), false, "copy without selection")
    cb:selectWordAt(0)
    cb:copy(clipboard)
    t.eq(stored, "copy", "copy")
    cb:cut(clipboard)
    t.eq(cb.text, " paste", "cut removes selection")
    cb:moveCaret("End")
    cb:paste(clipboard)
    t.eq(cb.text, " pastecopy", "paste at caret")
    stored = ""
    t.eq(cb:paste(clipboard), false, "paste empty clipboard")
end

local function widgetTests(t)
    local module = require "luif.module"
    local core = module "luif.core"
    local Host = require "luif.core.host"
    local Sync = require "luif.core.sync"

    local function key(w, name, modifiers)
        modifiers = modifiers or ""
        w:handleEvent(core.Event { name = "keyPress", keyName = name,
                                   ctrl = modifiers:find("ctrl") ~= nil,
                                   shift = modifiers:find("shift") ~= nil })
    end
    local function type(w, text)
        for ch in text:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
            w:handleEvent(core.Event { name = "keyCharacter", typed = ch })
        end
    end
    local function mouse(w, name, x, y)
        w:handleEvent(core.Event { name = name, localX = x, localY = y, absX = x, absY = y,
                                   mouseButton = core.MouseButton.Left })
    end

    -- Clipboard stub on top of the application host
    local stored = ""
    local realHost = Host.get()
    Host.set(setmetatable({
        getClipboard = function() return stored end,
        setClipboard = function(text) stored = text end,
    }, { __index = realHost }))

    local root = core.Item { width = 400, height = 300 }
    Sync.addRoot(root)

    -- Metrics of the host the labels measure with
    local measure = Sync.host(root)

    local changes, returns = 0, 0
    local input = core.TextInput {
        width = 200, height = 20, multiline = false, paddingLeft = 4, paddingTop = 2,
        textChange = function() changes = changes + 1 end,
        returnPress = function() returns = returns + 1 end,
    }
    root:addChild(input)
    input:setFocus()
    t.eq(input.state, "focused", "focus state")
    t.ok(input.caret.visible, "caret visible when focused")

    type(input, "hello")
    t.eq(input.text, "hello", "typed text")
    t.eq(input.label.text, "hello", "label follows text")
    t.eq(changes, 5, "textChange per character")
    t.eq(input:caretPos(), 5, "caret after typing")
    local font = input.label.font
    t.near(input.caret.x, math.floor(4 + measure.textWidth(font, "hello")), 0, "caret x")
    t.eq(input.caret.y, 2, "caret y uses paddingTop")
    t.near(input.caret.height, measure.lineHeight(font), 1e-6, "caret height")

    key(input, "backspace")
    t.eq(input.text, "hell", "Backspace deletes")
    key(input, "left", "shift")
    key(input, "left", "shift")
    t.eq(input:selectedText(), "ll", "shift Left selects")
    local rects = input._selectionRects
    t.eq(#rects, 1, "one selection rect")
    t.ok(rects[1].visible and rects[1].alpha == 128, "selection rect shown half transparent")
    t.near(rects[1].x, 4 + measure.textWidth(font, "he"), 1e-6, "selection rect x")
    t.near(rects[1].width, measure.textWidth(font, "ll"), 1e-6, "selection rect width")
    local HostWorld = require "tests.hostworld"
    Sync.flush()
    local nodeHost = Sync.host(input)
    local inputNode = Sync.node(input)
    local rectIndex = HostWorld.childIndex(nodeHost, inputNode, Sync.node(rects[1]))
    local labelIndex = HostWorld.childIndex(nodeHost, inputNode, Sync.node(input.label))
    local caretIndex = HostWorld.childIndex(nodeHost, inputNode, Sync.node(input.caret))
    t.ok(rectIndex and labelIndex and caretIndex and rectIndex < labelIndex and
         labelIndex < caretIndex, "selection below label, caret on top")

    key(input, "c", "ctrl")
    t.eq(stored, "ll", "ctrl C copies")
    key(input, "x", "ctrl")
    t.eq(input.text, "he", "ctrl X cuts")
    t.ok(not rects[1].visible, "selection rect hidden without selection")
    key(input, "end")
    key(input, "v", "ctrl")
    t.eq(input.text, "hell", "ctrl V pastes")
    key(input, "a", "ctrl")
    t.eq(input:selectedText(), "hell", "ctrl A selects all")
    type(input, "one two")
    key(input, "backspace", "ctrl")
    t.eq(input.text, "one ", "ctrl Backspace deletes a word")
    key(input, "home")
    key(input, "delete", "ctrl")
    t.eq(input.text, "", "ctrl Delete deletes a word")

    type(input, "a\n")
    t.eq(input.text, "a", "newline ignored when single line")
    key(input, "return")
    t.eq(returns, 1, "returnPress")
    local special
    input.specialPress = function(code) special = code end
    key(input, "up")
    t.eq(special, "up", "specialPress for Up when single line")

    -- Mouse: press places the caret, drag selects, double click selects a word
    input:setText("alpha beta")
    local xBeta = 4 + measure.textWidth(font, "alpha b")
    mouse(input, "mousePress", xBeta, 5)
    t.eq(input:caretPos(), 7, "mouse press places caret")
    mouse(input, "mouseMove", 4 + measure.textWidth(font, "alpha beta"), 5)
    t.eq(input:selectedText(), "eta", "mouse drag selects")
    mouse(input, "mouseRelease", xBeta, 5)
    mouse(input, "mouseMove", 0, 5)
    t.eq(input:selectedText(), "eta", "move after release does not select")
    mouse(input, "mousePress", xBeta, 5)
    mouse(input, "mouseDoubleClick", xBeta, 5)
    t.eq(input:selectedText(), "beta", "double click selects word")
    mouse(input, "mouseMove", 5, 5)
    t.eq(input:selectedText(), "alpha beta", "double click drag extends by words")
    mouse(input, "mouseRelease", 5, 5)

    -- Numeric with maxValue, readonly
    input:setText("")
    input:setNumeric(true)
    input.maxValue = 99
    type(input, "4x2")
    t.eq(input.text, "42", "numeric filters characters")
    type(input, "7")
    t.eq(input.text, "42", "maxValue refuses larger numbers")
    input:setNumeric(false)
    input:setMaxLength(3)
    type(input, "abc")
    t.eq(input.text, "42a", "maxLength")
    input:setMaxLength(false)
    input:setReadonly(true)
    type(input, "z")
    key(input, "backspace")
    t.eq(input.text, "42a", "readonly refuses edits")
    t.ok(not input.caret.visible, "no caret when readonly")
    input:setReadonly(false)

    -- Obfuscation measures bullets
    input:setObfuscate(true)
    input:setText("pw")
    input:moveCaret("End")
    local bullets = "\226\128\162\226\128\162"
    t.near(input.caret.x, math.floor(4 + measure.textWidth(font, bullets)), 0, "obfuscated caret x")
    input:setObfuscate(false)

    -- Focus loss and disabling
    input:setFocus(false)
    t.eq(input.state, "normal", "state after focus loss")
    t.ok(not input.caret.visible, "caret hidden after focus loss")
    t.eq(input:caretPos(), 2, "caret at end after focus loss")
    input:setEnabled(false)
    t.eq(input.state, "disabled", "disabled state")
    type(input, "q")
    t.eq(input.text, "pw", "disabled refuses characters")
    input:setEnabled(true)
    t.eq(input.state, "normal", "state restored when enabled")

    -- Multiline with wrapping
    local area = core.TextInput { width = 100, height = 10 }
    root:addChild(area)
    area.label:setWidth(100)
    area:setText("the quick brown fox jumps over the lazy dog")
    local lineHeight = measure.lineHeight(area.label.font)
    local _, wrapped = measure.wrapText(area.label.font, area.text, 100)
    t.eq(#area.edit:lines(), #wrapped, "model lines follow font wrap")
    t.ok(#wrapped > 1, "text wraps")
    t.near(area.height, #wrapped * lineHeight, 1e-6, "multiline height follows text")
    local _, labelHeight = area.label:implicitSize()
    t.near(labelHeight, #wrapped * lineHeight, 1e-6, "model and label agree on height")
    area:setFocus()
    area:moveCaret("Start")
    key(area, "down")
    t.eq(area.edit:lineIndexAt(area:caretPos()), 2, "Down moves to next line")
    t.near(area.caret.y, lineHeight, 1e-6, "caret y on second line")
    key(area, "end", "ctrl shift")
    t.eq(#area._selectionRects, #wrapped - 1, "selection rects per line")
    type(area, "\n")
    t.ok(area.text:sub(-1) == "\n", "Return inserts newline when multiline")
    area:setFocus(false)

    -- LineEdit scrolls its label and TextArea wraps to its width. The default
    -- skins need textures, so these use minimal skins.
    local LineSkin = core.Skin:extend { textColor = 0xFF000000, width = 60, height = 20 }
    function LineSkin.new(class, self)
        self.layout = core.AnchorLayout {}
        self.children = {
            core.TextInput { id = "textInput", top = 2, bottom = 2, left = 3, right = 3,
                             paddingRight = 2 },
        }
        return core.Skin.new(class, self)
    end
    local AreaSkin = core.Skin:extend { width = 120, height = 60 }
    function AreaSkin.new(class, self)
        self.layout = core.AnchorLayout {}
        self.children = {
            core.TextInput { id = "textInput", top = 0, left = 0, right = 0 },
        }
        return core.Skin.new(class, self)
    end

    local lineEdit = core.LineEdit { skinClass = LineSkin, width = 60, height = 20 }
    root:addChild(lineEdit)
    lineEdit:setText(string.rep("wide ", 10))
    local textInput = lineEdit.textInput
    textInput:moveCaret("End")
    t.ok(textInput.label.x < 0, "LineEdit scrolls label left for a long text")
    t.ok(textInput.caret.x <= textInput:size() - textInput.paddingRight,
         "caret inside the line edit")
    textInput:moveCaret("Start")
    t.eq(textInput.label.x, textInput.paddingLeft, "LineEdit scrolls back at start")
    lineEdit:setText("x")
    t.eq(textInput.label.x, textInput.paddingLeft, "short text is not scrolled")
    t.ok(textInput.clip, "LineEdit clips its text input")

    local textArea = core.TextArea { skinClass = AreaSkin, width = 120, height = 60 }
    root:addChild(textArea)
    textArea:setText("some words that will need to wrap inside the area")
    t.ok(#textArea.textInput.edit:lines() > 1, "TextArea wraps")

    root:delete()
    Host.set(realHost)
end

return function(t)
    local TextEdit = require "luif.core.textedit"
    modelTests(t, TextEdit)
    widgetTests(t)
end
