//
// Fonts, the glyph atlas, measuring, wrapping and text layout.
//
// A face is one TTF_Font for a (file, size) pair with its glyph table; a font
// (what an Id names) is a face plus shadow and outline parameters, so fonts
// that differ only in those share the face and its glyphs. Glyphs are measured
// on first use and rasterized into shared atlas pages when first laid out.
//
// Measuring, wrapping and layout all move the pen with advance(), so what is
// measured is what is drawn. Known gap: no complex shaping (no ligatures,
// combining marks, bidirectional or cursive scripts), one glyph per codepoint.
//
#include "internal.h"

#include <algorithm>
#include <cmath>

namespace luif {

namespace {

constexpr int PageSize = 512;
constexpr int FirstPageSize = 256;  // a typical UI fills a fraction of it
constexpr int TabSpaces = 4;        // as in LOVE
constexpr uint16_t NoPage = 0xFFFF;
constexpr uint32_t MissingGlyph = 0xFFFFFFFF;    // no codepoint: measures and draws as glyph 0

struct Glyph {
    uint16_t page = NoPage, x = 0, y = 0, w = 0, h = 0;     // NoPage: nothing to draw
    int16_t left = 0, top = 0;      // of the image, from the pen and the top of the line
    int16_t advance = 0;
    bool rasterized = false;
    bool colored = false;           // image with its own colours (emoji): not tinted
};

struct Page { SDL_Texture *texture; float invWidth, invHeight; };

struct Face {
    std::string file;               // resolved; empty: the default font from memory
    float size = 0;
    TTF_Font *ttf = nullptr;
    float lineSkip = 0;
    int ascent = 0;
    std::vector<Glyph> glyphs;
    std::unordered_map<uint32_t, uint32_t> byCodepoint;     // to index in glyphs
};

struct Font { FontSpec spec; uint32_t face; };

struct Line { uint32_t start, end; float width; };          // bytes [start, end) of the text

// The shadow and outline parameters only count when enabled
bool sameSpec(const FontSpec &a, const FontSpec &b)
{
    return a.file == b.file && a.size == b.size && a.shadow == b.shadow && a.outline == b.outline
        && (!a.shadow || (a.shadowX == b.shadowX && a.shadowY == b.shadowY
                          && a.shadowColor == b.shadowColor))
        && (!a.outline || a.outlineColor == b.outlineColor);
}

// Control characters take no space and draw nothing ("\n" is handled before,
// and a tab is spaces)
bool isControl(uint32_t cp)
{
    return (cp < 0x20 && cp != '\t') || (cp >= 0x7F && cp < 0xA0);
}

bool isSpace(uint32_t cp)
{
    return cp == ' ' || cp == '\t';
}

} // namespace

uint32_t decode(std::string_view text, size_t &i)
{
    static const uint32_t minimum[] = { 0, 0x80, 0x800, 0x10000 };
    const uint32_t lead = uint8_t(text[i++]);
    if (lead < 0x80)
        return lead;
    if (lead < 0xC2 || lead > 0xF4)
        return 0xFFFD;
    const int extra = lead >= 0xF0 ? 3 : lead >= 0xE0 ? 2 : 1;
    uint32_t cp = lead & (0x3F >> extra);
    for (int k = 0; k < extra; ++k) {
        const uint32_t next = i + k < text.size() ? uint8_t(text[i + k]) : 0;
        if ((next & 0xC0) != 0x80)
            return 0xFFFD;
        cp = cp << 6 | (next & 0x3F);
    }
    if (cp < minimum[extra] || cp > 0x10FFFF || (cp >= 0xD800 && cp < 0xE000))
        return 0xFFFD;
    i += extra;
    return cp;
}

namespace {

uint32_t findGlyph(Face &face, uint32_t cp)
{
    const auto found = face.byCodepoint.find(cp);
    if (found != face.byCodepoint.end())
        return found->second;

    // Characters the font lacks share its missing glyph
    if (cp != MissingGlyph && cp != '\t' && !TTF_FontHasGlyph(face.ttf, cp)) {
        const uint32_t missing = findGlyph(face, MissingGlyph);
        face.byCodepoint.emplace(cp, missing);
        return missing;
    }

    Glyph glyph;
    int minX = 0, maxX = 0, minY = 0, maxY = 0, advance = 0;
    if (cp == '\t') {
        glyph.advance = int16_t(TabSpaces * face.glyphs[findGlyph(face, ' ')].advance);
    } else if (TTF_GetGlyphMetrics(face.ttf, cp, &minX, &maxX, &minY, &maxY, &advance)) {
        glyph.left = int16_t(minX);
        glyph.top = int16_t(face.ascent - maxY);
        glyph.advance = int16_t(advance);
    }
    // Without a box (spaces, tabs, failures) there is nothing to rasterize
    glyph.rasterized = maxX <= minX || maxY <= minY;
    const uint32_t index = uint32_t(face.glyphs.size());
    face.glyphs.push_back(glyph);
    face.byCodepoint.emplace(cp, index);
    return index;
}

// How far the pen moves for cp after prev (0 at the start of a line),
// kerning included. A tab kerns as the spaces it stands for.
float advance(Face &face, uint32_t prev, uint32_t cp, uint32_t &index)
{
    index = findGlyph(face, cp);
    int kerning = 0;
    if (prev)
        TTF_GetGlyphKerning(face.ttf, prev == '\t' ? ' ' : prev, cp == '\t' ? ' ' : cp, &kerning);
    return float(face.glyphs[index].advance + kerning);
}

// Visits the drawn characters of one line: visit(cp, byte offset, pen x
// before the character, its advance, glyph index). Returns the line's width.
template <typename Visit>
float walkLine(Face &face, std::string_view line, Visit visit)
{
    float pen = 0;
    uint32_t prev = 0;
    for (size_t i = 0; i < line.size();) {
        const size_t at = i;
        const uint32_t cp = decode(line, i);
        if (isControl(cp))
            continue;
        uint32_t index;
        const float step = advance(face, prev, cp, index);
        visit(cp, at, pen, step, index);
        pen += step;
        prev = cp;
    }
    return pen;
}

//
// Splits text into lines at "\n" and, with wrap, where the next character
// would pass limit, as LOVE's Font:getWrap does:
//
//   - A line breaks after its last space (or tab); the spaces stay at the
//     end of the line they follow, and hang over the limit without causing a
//     break.
//   - A line without a space breaks before the character that does not fit
//     (so a long word is cut per character), but every line takes at least
//     one character (LOVE drops a character wider than the limit instead).
//   - "\n" ends a line and belongs to none, so the lines with the newlines
//     cover every byte of the text. Empty lines stay; empty text is one line.
//   - With wrap a line's width leaves out its trailing spaces.
//
void breakLines(Face &face, std::string_view text, float limit, bool wrap, std::vector<Line> &lines)
{
    size_t start = 0, i = 0;
    size_t afterSpace = 0;          // past the line's last space; 0: no space yet
    float width = 0, beforeSpaces = 0, trailing = 0;
    uint32_t prev = 0;
    bool empty = true;

    const auto push = [&](size_t end, float lineWidth, size_t next) {
        lines.push_back({ uint32_t(start), uint32_t(end), lineWidth });
        start = i = next;
        afterSpace = 0;
        width = beforeSpaces = trailing = 0;
        prev = 0;
        empty = true;
    };

    while (i < text.size()) {
        const size_t at = i;
        const uint32_t cp = decode(text, i);
        if (cp == '\n') {
            push(at, wrap ? width - trailing : width, i);
            continue;
        }
        if (isControl(cp))
            continue;
        uint32_t index;
        const float step = advance(face, prev, cp, index);
        if (wrap && !isSpace(cp) && !empty && width + step > limit) {
            // The character starts the next line, measured without kerning
            if (afterSpace)
                push(afterSpace, beforeSpaces, afterSpace);
            else
                push(at, width, at);
            continue;
        }
        if (isSpace(cp)) {
            if (!isSpace(prev))
                beforeSpaces = width;
            afterSpace = i;
            trailing += step;
        } else {
            trailing = 0;
        }
        width += step;
        prev = cp;
        empty = false;
    }
    push(text.size(), wrap ? width - trailing : width, text.size());
}

// Whole units, as LOVE's printf does, which keeps glyphs on the pixel grid
float alignOffset(Align align, float slack)
{
    switch (align) {
    case Align::Center: return std::floor(slack / 2);
    case Align::Right: return std::floor(slack);
    default: return 0;
    }
}

} // namespace

struct Fonts::Data {
    SDL_Renderer *renderer = nullptr;
    const Files *files = nullptr;
    std::string defaultFile;
    const void *defaultData = nullptr;
    size_t defaultSize = 0;
    bool ttfInit = false;

    std::vector<Face> faces;
    std::vector<Font> fonts;        // [0] is none
    std::vector<Line> lines;        // scratch for wrap and layout

    // The atlas: a shelf packer fills the open page, one pixel apart; pages
    // are shared by all faces. A glyph too large for a page gets its own.
    std::vector<Page> pages;
    int open = -1, pageSize = 0, shelfX = 0, shelfY = 0, shelfHeight = 0;

    int addPage(int width, int height);
    void rasterize(Face &face, Glyph &glyph, uint32_t cp);
    void layout(Face &face, TextContent &text, float boxWidth);
};

int Fonts::Data::addPage(int width, int height)
{
    if (pages.size() >= NoPage)
        return -1;
    SDL_Texture *texture = SDL_CreateTexture(renderer, SDL_PIXELFORMAT_ARGB8888,
                                             SDL_TEXTUREACCESS_STATIC, width, height);
    if (!texture)
        return -1;
    SDL_SetTextureBlendMode(texture, SDL_BLENDMODE_BLEND);
    SDL_SetTextureScaleMode(texture, SDL_SCALEMODE_LINEAR);
    // Transparent white, so filtering at glyph edges does not darken them
    const std::vector<uint32_t> clear(size_t(width) * height, 0x00FFFFFF);
    SDL_UpdateTexture(texture, nullptr, clear.data(), width * 4);
    pages.push_back({ texture, 1.0f / width, 1.0f / height });
    return int(pages.size()) - 1;
}

void Fonts::Data::rasterize(Face &face, Glyph &glyph, uint32_t cp)
{
    glyph.rasterized = true;
    TTF_ImageType type = TTF_IMAGE_INVALID;
    SDL_Surface *image = TTF_GetGlyphImage(face.ttf, cp, &type);
    if (!image)     // a character the font lacks: glyph 0, which is what was measured
        image = TTF_GetGlyphImageForIndex(face.ttf, 0, &type);
    if (image && image->format != SDL_PIXELFORMAT_ARGB8888) {
        SDL_Surface *converted = SDL_ConvertSurface(image, SDL_PIXELFORMAT_ARGB8888);
        SDL_DestroySurface(image);
        image = converted;
    }
    if (!image)
        return;

    // Alpha images are white with coverage in alpha, which the vertex colour tints
    const int w = image->w, h = image->h;
    int page = -1, x = 1, y = 1;
    if (w <= 0 || h <= 0 || w > 0xFFFF || h > 0xFFFF) {
        // nothing to draw
    } else if (w + 2 > PageSize || h + 2 > PageSize) {
        page = addPage(w + 2, h + 2);
    } else {
        if (shelfX + w + 1 > pageSize) {
            shelfX = 1;
            shelfY += shelfHeight + 1;
            shelfHeight = 0;
        }
        if (open < 0 || shelfY + h + 1 > pageSize || w + 2 > pageSize) {
            const bool first = open < 0 && w + 2 <= FirstPageSize && h + 2 <= FirstPageSize;
            pageSize = first ? FirstPageSize : PageSize;
            open = addPage(pageSize, pageSize);
            shelfX = shelfY = 1;
            shelfHeight = 0;
        }
        page = open;
        x = shelfX;
        y = shelfY;
        if (page >= 0) {
            shelfX += w + 1;
            shelfHeight = std::max(shelfHeight, h);
        }
    }
    if (page >= 0) {
        const SDL_Rect rect = { x, y, w, h };
        SDL_UpdateTexture(pages[page].texture, &rect, image->pixels, image->pitch);
        glyph.page = uint16_t(page);
        glyph.x = uint16_t(x);
        glyph.y = uint16_t(y);
        glyph.w = uint16_t(w);
        glyph.h = uint16_t(h);
        glyph.colored = type == TTF_IMAGE_COLOR;
    }
    SDL_DestroySurface(image);
}

// Fills text.glyphs for a box of boxWidth, in the node's local units
void Fonts::Data::layout(Face &face, TextContent &text, float boxWidth)
{
    const std::string_view all = text.text;
    text.glyphs.clear();
    lines.clear();
    breakLines(face, all, boxWidth, text.wrap, lines);

    // Wrapped lines align within the box. Unwrapped ones align within their
    // block (the widest line), and the block within the box.
    float block = boxWidth, left = 0;
    if (!text.wrap) {
        block = 0;
        for (const Line &line : lines)
            block = std::max(block, line.width);
        left = alignOffset(text.align, boxWidth - block);
    }

    const uint32_t alpha = text.color >> 24;
    size_t run = 0;
    float y = 0;
    for (const Line &line : lines) {
        const float x = left + alignOffset(text.align, block - line.width);
        walkLine(face, all.substr(line.start, line.end - line.start),
                 [&](uint32_t cp, size_t at, float pen, float step, uint32_t index) {
            Glyph &glyph = face.glyphs[index];
            if (!glyph.rasterized)
                rasterize(face, glyph, cp);
            if (glyph.page == NoPage)
                return;
            // Run colours replace the content colour, except for its alpha
            Color color = text.color;
            if (!text.runs.empty()) {
                while (run + 1 < text.runs.size() && text.runs[run + 1].start <= line.start + at)
                    ++run;
                color = text.runs[run].color;
                color = (color & 0xFFFFFF) | ((((color >> 24) * alpha + 127) / 255) << 24);
            }
            if (glyph.colored)
                color |= 0xFFFFFF;
            // Kerning moves the glyph itself, so it sits at the end of the step
            text.glyphs.push_back({ x + pen + step - glyph.advance + glyph.left, y + glyph.top,
                                    index, color });
        });
        y += face.lineSkip;
    }
    text.layoutWidth = boxWidth;
}

Fonts::Fonts(SDL_Renderer *renderer, const SdlHostOptions &options, const Files &files)
    : d(new Data)
{
    d->renderer = renderer;
    d->files = &files;
    if (options.defaultFontFile)
        d->defaultFile = options.defaultFontFile;
    if (options.defaultFontData && options.defaultFontSize > 0) {
        d->defaultData = options.defaultFontData;
        d->defaultSize = options.defaultFontSize;
    }
    // Counted by SDL_ttf, so this is safe next to an application using it too
    d->ttfInit = TTF_Init();
    d->fonts.emplace_back();
}

Fonts::~Fonts()
{
    for (Face &face : d->faces)
        TTF_CloseFont(face.ttf);
    for (Page &page : d->pages)
        SDL_DestroyTexture(page.texture);
    if (d->ttfInit)
        TTF_Quit();
    delete d;
}

Id Fonts::load(const FontSpec &spec)
{
    for (size_t id = 1; id < d->fonts.size(); ++id)
        if (sameSpec(d->fonts[id].spec, spec))
            return Id(id);

    const std::string &file = spec.file.empty() ? d->defaultFile : spec.file;
    const char *problem = !d->ttfInit ? "SDL_ttf failed to initialize"
        : !(spec.size > 0) ? "font size must be positive"
        : file.empty() && !d->defaultData
            ? "no default font: set defaultFontFile or defaultFontData in SdlHostOptions"
        : nullptr;
    if (problem) {
        SDL_SetError("%s", problem);
        return None;
    }

    size_t face = 0;
    while (face < d->faces.size() && (d->faces[face].file != file || d->faces[face].size != spec.size))
        ++face;
    if (face == d->faces.size()) {
        // The font keeps reading from the stream, and closes it with itself
        SDL_IOStream *io = file.empty() ? SDL_IOFromConstMem(d->defaultData, d->defaultSize)
                                        : d->files->open(file);
        TTF_Font *ttf = io ? TTF_OpenFontIO(io, true, spec.size) : nullptr;
        if (!ttf)
            return None;
        d->faces.emplace_back();
        Face &added = d->faces.back();
        added.file = file;
        added.size = spec.size;
        added.ttf = ttf;
        added.lineSkip = float(TTF_GetFontLineSkip(ttf));
        added.ascent = TTF_GetFontAscent(ttf);
    }
    d->fonts.push_back({ spec, uint32_t(face) });
    return Id(d->fonts.size() - 1);
}

size_t Fonts::count() const
{
    return d->fonts.size();
}

float Fonts::lineHeight(Id font) const
{
    return d->faces[d->fonts[font].face].lineSkip;
}

float Fonts::textWidth(Id font, std::string_view text)
{
    return walkLine(d->faces[d->fonts[font].face], text,
                    [](uint32_t, size_t, float, float, uint32_t) {});
}

float Fonts::wrap(Id font, std::string_view text, float width, std::vector<std::string_view> &lines)
{
    lines.clear();
    d->lines.clear();
    breakLines(d->faces[d->fonts[font].face], text, width, true, d->lines);
    float widest = 0;
    for (const Line &line : d->lines) {
        lines.push_back(text.substr(line.start, line.end - line.start));
        widest = std::max(widest, line.width);
    }
    return widest;
}

void Fonts::draw(Batch &batch, const Affine &transform, TextContent &text, float boxWidth, float opacity)
{
    const uint32_t alpha = text.color >> 24;
    if (text.text.empty() || opacity <= 0 || alpha == 0)
        return;
    const Font &font = d->fonts[text.font];
    Face &face = d->faces[font.face];
    boxWidth = std::max(boxWidth, 0.0f);
    if (text.layoutWidth != boxWidth)
        d->layout(face, text, boxWidth);

    // Unrotated and unscaled text lands on whole pixels, which keeps it crisp
    const bool snap = transform.isTranslation();
    const auto pass = [&](float dx, float dy, const SDL_FColor *color) {
        for (const PlacedGlyph &placed : text.glyphs) {
            const Glyph &glyph = face.glyphs[placed.glyph];
            const Page &page = d->pages[glyph.page];
            float x = placed.x + dx, y = placed.y + dy;
            if (snap) {
                x = std::floor(x + transform.tx + 0.5f) - transform.tx;
                y = std::floor(y + transform.ty + 0.5f) - transform.ty;
            }
            batch.quad(page.texture, transform, x, y, glyph.w, glyph.h,
                       glyph.x * page.invWidth, glyph.y * page.invHeight,
                       (glyph.x + glyph.w) * page.invWidth, (glyph.y + glyph.h) * page.invHeight,
                       color ? *color : toFColor(placed.color, opacity));
        }
    };

    const float contentOpacity = opacity * alpha / 255.0f;
    if (font.spec.shadow) {
        const SDL_FColor color = toFColor(font.spec.shadowColor, contentOpacity);
        if (color.a > 0)
            pass(font.spec.shadowX, font.spec.shadowY, &color);
    }
    if (font.spec.outline) {
        const SDL_FColor color = toFColor(font.spec.outlineColor, contentOpacity);
        for (int i = 0; i < 9 && color.a > 0; ++i)
            if (i != 4)
                pass(float(i % 3 - 1), float(i / 3 - 1), &color);
    }
    pass(0, 0, nullptr);
}

} // namespace luif
