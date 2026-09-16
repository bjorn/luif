--
-- core/textlayout.lua: colour runs, measurement through a host, wrapping,
-- scale, abbreviation and obfuscation. Runs with the recording host under
-- plain LuaJIT (`luajit tests/run_luajit.lua`); under LOVE it also checks
-- the LOVE host's metrics against the font.
--

return function(t)
    local TextLayout = require "luif.core.textlayout"
    local Recording = require "luif.host.recording"

    local function near(a, b)
        return type(a) == "number" and type(b) == "number" and math.abs(a - b) < 1e-6
    end

    local ELLIPSIS, BULLET = TextLayout.ELLIPSIS, TextLayout.BULLET

    -- Colour run parsing is pure string work.
    local plain, runs = TextLayout.parse("a{color:#ff0000}b{/color}c", 0x800000FF)
    t.eq(plain, "abc", "parse strips colour tags from the plain text")
    t.ok(runs and #runs == 6, "parse yields three runs")
    t.ok(runs and runs[1] == 0xFF0000FF and runs[2] == "a", "first run uses the base colour, opaque")
    t.ok(runs and runs[3] == 0xFFFF0000 and runs[4] == "b", "second run is red")
    t.ok(runs and runs[5] == 0xFF0000FF and runs[6] == "c", "colour is restored after /color")

    plain, runs = TextLayout.parse("x{scale:0.9}y{/scale}", 0xFF000000)
    t.eq(plain, "xy", "unknown tags are stripped")
    t.eq(runs, false, "no colour tags means no runs")
    t.eq((TextLayout.parse("no tags")), "no tags", "text without braces is returned as is")

    -- Measurement through the recording host: 10 per codepoint, 20 per line.
    local host = Recording.new { glyphWidth = 10, lineHeight = 20 }
    local font = host.loadFont { size = 14 }
    local function layout(text, options)
        return TextLayout.layout(host, font, text, options)
    end

    local l = layout("Hello")
    t.ok(l.width == 50 and l.height == 20, "single line size")
    t.ok(l.boxWidth == 50 and l.boxHeight == 20 and not l.wrap, "without a limit the box is the text")
    l = layout("Hello\nWorld!!")
    t.ok(l.width == 70 and l.height == 40, "two lines: widest line, two line heights")
    l = layout("")
    t.ok(l.width == 0 and l.height == 20, "empty text is one line high")
    l = layout("Hello", { scale = 2 })
    t.ok(l.width == 100 and l.height == 40 and l.boxWidth == 50, "scale multiplies the size, not the box")
    l = layout("Hello", { scale = 0, limit = 50 })
    t.ok(l.width == 0 and l.height == 0, "scale 0 measures as empty")

    -- Wrapping uses the host's wrapText at the limit.
    local long = "The quick brown fox jumps over the lazy dog"
    local widest, lines = host.wrapText(font, long, 100)
    l = layout(long, { limit = 100 })
    t.ok(#lines > 1 and l.wrap, "text wraps with a limit")
    t.ok(l.width == widest and l.height == #lines * 20, "wrapped size matches wrapText")
    t.eq(l.boxWidth, 100, "the box of wrapped text is the limit")
    widest, lines = host.wrapText(font, long, 200)
    l = layout(long, { limit = 100, scale = 0.5 })
    t.ok(near(l.width, widest * 0.5) and near(l.height, #lines * 10) and l.boxWidth == 200,
         "the limit is divided by the scale")

    -- Abbreviation: one line cut with an ellipsis that fits.
    l = layout(long, { limit = 100, abbreviate = true })
    t.ok(not l.wrap and l.height == 20 and l.width <= 100, "abbreviated text fits in one line")
    t.eq(l.display, "The quick" .. ELLIPSIS, "the longest prefix with an ellipsis that fits")
    t.eq(l.boxWidth, 100, "the box of abbreviated text is the limit")
    t.eq(layout(long, { limit = 1000, abbreviate = true }).display, long, "text that fits is kept")
    l = layout("{color:#00ff00}" .. long .. "{/color}", { limit = 100, abbreviate = true })
    t.ok(type(l.display) == "table" and l.display[#l.display] == ELLIPSIS,
         "abbreviated runs end in an ellipsis")
    t.ok(l.display[1] == 0xFF00FF00 and l.display[2] == "The quick", "abbreviated runs keep their colour")

    -- Obfuscation shows one bullet per codepoint.
    l = layout("p\195\164ss", { obfuscate = true })
    t.eq(l.display, BULLET:rep(4), "obfuscated text is bullets")
    t.eq(l.width, 40, "obfuscated width is the bullets' width")

    if not (love and love.graphics and love.graphics.isCreated()) then
        t.skip("measuring with the LOVE host needs love.graphics")
        return
    end

    -- The LOVE host measures with the font.
    local loveHost = require("luif.love").host
    local handle = loveHost.loadFont { size = 14 }
    t.eq(loveHost.loadFont { size = 14 }, handle, "the LOVE host caches fonts per specification")
    local loveFont = handle.font
    local lineHeight = loveFont:getHeight() * loveFont:getLineHeight()
    l = TextLayout.layout(loveHost, handle, "Hello\nWorld!!")
    t.ok(near(l.width, math.max(loveFont:getWidth("Hello"), loveFont:getWidth("World!!"))),
         "LOVE host: widest line")
    t.ok(near(l.height, 2 * lineHeight), "LOVE host: line height")
    local wrapWidth, wrapped = loveFont:getWrap(long, 60)
    l = TextLayout.layout(loveHost, handle, long, { limit = 60 })
    t.ok(near(l.width, wrapWidth) and near(l.height, #wrapped * lineHeight),
         "LOVE host: wrapping matches Font:getWrap")
    l = TextLayout.layout(loveHost, handle, long, { limit = 60, abbreviate = true })
    t.ok(l.width <= 60 and near(l.width, loveFont:getWidth(l.display)),
         "LOVE host: abbreviated width is the shown width")
end
