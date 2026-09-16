--
-- Some color helper functions
--

local core = require "luif.core"

local bit = core.Bit

local floor = math.floor
local rshift = bit.rshift
local lshift = bit.lshift
local band = bit.band
local bor = bit.bor

local Color = {}

function Color.rgba(r, g, b, a)
    return bor(lshift(r, 16), lshift(g, 8), b) + a * 0x01000000
end

function Color.rgb(r, g, b)
    return bor(lshift(r, 16), lshift(g, 8), b) + 0xFF000000
end

function Color.grayColor(value)
    return Color.rgb(value, value, value)
end

function Color.channels(color)
    local a = rshift(color, 24)
    local r = band(rshift(color, 16), 0xff)
    local g = band(rshift(color, 8), 0xff)
    local b = band(color, 0xff)

    return r, g, b, a
end

function Color.yuvChannels(color)
    local r, g, b = Color.channels(color)
    local y =  0.299   * r + 0.587   * g + 0.114   * b
    local u = -0.14713 * r - 0.28886 * g + 0.436   * b
    local v =  0.615   * r - 0.51499 * g - 0.10001 * b

    return y, u, v
end

function Color.yuvDistance(a, b)
    local yA, uA, vA = Color.yuvChannels(a)
    local yB, uB, vB = Color.yuvChannels(b)
    return math.sqrt((yA-yB)*(yA-yB) + (uA-uB)*(uA-uB) + (vA-vB)*(vA-vB))
end

function Color.blend(color1, color2, factor)
    local r1, g1, b1, a1 = Color.channels(color1)
    local r2, g2, b2, a2 = Color.channels(color2)

    local r = floor(r1 + factor * (r2 - r1))
    local g = floor(g1 + factor * (g2 - g1))
    local b = floor(b1 + factor * (b2 - b1))
    local a = floor(a1 + factor * (a2 - a1))

    return Color.rgba(r, g, b, a)
end

function Color.multiply(color1, color2)
    local r1, g1, b1, a1 = Color.channels(color1)
    local r2, g2, b2, a2 = Color.channels(color2)
    r2 = r2 / 255.0
    g2 = g2 / 255.0
    b2 = b2 / 255.0
    a2 = a2 / 255.0
    return Color.rgba(r1*r2, g1*g2, b1*b2, a1*a2)
end

-- color names according to W3C specifications

Color.aliceBlue       = 0xffF0F8ff
Color.antiqueWhite      = 0xfffaebd7
Color.aqua              = 0xff00ffff
Color.aquamarine        = 0xff7ffFd4
Color.azure           = 0xffF0ffff
Color.beige             = 0xffF5F5dc
Color.bisque            = 0xffffe4c4
Color.black             = 0xff000000
Color.blanchedAlmond    = 0xffffebcd
Color.blue              = 0xff0000ff
Color.blueViolet        = 0xff8a2be2
Color.brown             = 0xffa52a2a
Color.burlyWood         = 0xffdeb887
Color.cadetBlue         = 0xff5F9ea0
Color.chartreuse        = 0xff7ffF00
Color.chocolate         = 0xffd2691e
Color.coral             = 0xffff7f50
Color.cornflowerBlue    = 0xff6495ed
Color.cornsilk          = 0xffffF8dc
Color.crimson           = 0xffdc143c
Color.cyan              = 0xff00ffff
Color.darkOlivegreen    = 0xff556b2F
Color.darkBlue          = 0xff00008b
Color.darkCyan          = 0xff008b8b
Color.darkGoldenRod     = 0xffb8860b
Color.darkGray          = 0xffa9a9a9
Color.darkGreen         = 0xff006400
Color.darkKhaki         = 0xffbdb76b
Color.darkMagenta       = 0xff8b008b
Color.darkOrange        = 0xffff8c00
Color.darkOrchid        = 0xff9932cc
Color.darkRed           = 0xff8b0000
Color.darkSalmon        = 0xffe9967a
Color.darkSeaGreen      = 0xff8Fbc8F
Color.darkSlateBlue     = 0xff483d8b
Color.darkSlateGray     = 0xff2F4F4F
Color.darkTurquoise     = 0xff00ced1
Color.darkViolet        = 0xff9400d3
Color.deepPink          = 0xffff1493
Color.deepSkyBlue       = 0xff00bffF
Color.dimGray           = 0xff696969
Color.dodgerBlue        = 0xff1e90ff
Color.fireBrick         = 0xffb22222
Color.floralWhite       = 0xfffffaf0
Color.forestGreen       = 0xff228b22
Color.fuchsia           = 0xffff00ff
Color.gainsboro         = 0xffdcdcdc
Color.ghostWhite        = 0xffF8F8ff
Color.gold              = 0xffffd700
Color.goldenRod         = 0xffdaa520
Color.gray              = 0xff808080
Color.green             = 0xff008000
Color.greenYellow       = 0xffadff2F
Color.honeydew        = 0xffF0ffF0
Color.hotPink           = 0xffff69b4
Color.indianRed         = 0xffcd5c5c
Color.indigo            = 0xff4b0082
Color.ivory           = 0xffffffF0
Color.khaki             = 0xffF0e68c
Color.lavender          = 0xffe6e6Fa
Color.lavenderBlush   = 0xffffF0F5
Color.lawnGreen         = 0xff7cFc00
Color.lemonChiffon      = 0xffffFacd
Color.lightBlue         = 0xffadd8e6
Color.lightCoral        = 0xfff08080
Color.lightCyan       = 0xffe0ffff
Color.lightGoldenrodYellow = 0xffFaFad2
Color.lightGreen        = 0xff90ee90
Color.lightGray         = 0xffd3d3d3
Color.lightPink         = 0xffffb6c1
Color.lightSalmon       = 0xffffa07a
Color.lightSeaGreen     = 0xff20b2aa
Color.lightSkyBlue      = 0xff87ceFa
Color.lightSlateGray    = 0xff778899
Color.lightSteelBlue    = 0xffb0c4de
Color.lightYellow       = 0xffffffe0
Color.lime              = 0xff00ff00
Color.limeGreen         = 0xff32cd32
Color.linen             = 0xfffaf0e6
Color.magenta           = 0xffff00ff
Color.maroon            = 0xff800000
Color.mediumAquaMarine  = 0xff66cdaa
Color.mediumBlue        = 0xff0000cd
Color.mediumOrchid      = 0xffba55d3
Color.mediumPurple      = 0xff9370db
Color.mediumSeaGreen    = 0xff3cb371
Color.mediumSlateBlue   = 0xff7b68ee
Color.mediumSpringGreen = 0xff00Fa9a
Color.mediumTurquoise   = 0xff48d1cc
Color.mediumVioletRed   = 0xffc71585
Color.midnightBlue      = 0xff191970
Color.mintCream       = 0xffF5ffFa
Color.mistyRose         = 0xffffe4e1
Color.moccasin          = 0xffffe4b5
Color.navajoWhite       = 0xffffdead
Color.navy              = 0xff000080
Color.oldLace         = 0xfffdf5e6
Color.olive             = 0xff808000
Color.oliveDrab         = 0xff6b8e23
Color.orange            = 0xffffa500
Color.orangeRed         = 0xffff4500
Color.orchid            = 0xffda70d6
Color.paleGoldenRod     = 0xffeee8aa
Color.paleGreen         = 0xff98Fb98
Color.paleTurquoise     = 0xffaFeeee
Color.paleVioletRed     = 0xffdb7093
Color.papayaWhip        = 0xffffefd5
Color.peachPuff         = 0xffffdab9
Color.peru              = 0xffcd853f
Color.pink              = 0xffffc0cb
Color.plum              = 0xffdda0dd
Color.powderBlue        = 0xffb0e0e6
Color.purple            = 0xff800080
Color.red               = 0xffff0000
Color.rosyBrown         = 0xffbc8f8f
Color.royalBlue         = 0xff4169e1
Color.saddleBrown       = 0xff8b4513
Color.salmon            = 0xfffa8072
Color.sandyBrown        = 0xfff4a460
Color.sand              = 0xfff3dbb4
Color.seaGreen          = 0xff2e8b57
Color.seashell        = 0xfffff5ee
Color.sienna            = 0xffa0522d
Color.silver            = 0xffc0c0c0
Color.skyBlue           = 0xff87ceeb
Color.slateBlue         = 0xff6a5acd
Color.slateGray         = 0xff708090
Color.snow              = 0xfffffafa
Color.springGreen       = 0xff00ff7F
Color.steelBlue         = 0xff4682b4
Color.tan               = 0xffd2b48c
Color.teal              = 0xff008080
Color.thistle           = 0xffd8bFd8
Color.tomato            = 0xffff6347
Color.turquoise         = 0xff40e0d0
Color.violet            = 0xffee82ee
Color.wheat             = 0xfff5deb3
Color.white             = 0xffffffff
Color.whiteSmoke        = 0xfff5f5f5

Color.yellow            = 0xffffff00
Color.yellowGreen       = 0xff9acd32

return Color
