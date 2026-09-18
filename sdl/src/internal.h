//
// Shared declarations of the SDL host. One translation unit per concern:
//
//   scene.cpp     the node pool: structure, properties, content
//   texture.cpp   texture handles, regions, grayscale copies
//   text.cpp      fonts, the glyph atlas, measuring, wrapping, text layout
//   render.cpp    the draw traversal and the quad batch
//   input.cpp     SDL events to the input sink, key names, cursors
//   lua_api.cpp   the host table of luif/host/interface.lua
//   sdl_host.cpp  the public class
//
// Memory: a node is one plain struct in a pooled vector (no allocation per
// node, no Lua object per node), handles are plain numbers, text content lives
// in its own pool and keeps its buffers when its text changes, glyphs of a
// face are shared in atlas pages, and regions share the texture they were cut
// from.
//
// Arguments are checked once, in lua_api.cpp: the functions declared here
// take ids of live nodes and of existing textures and fonts.
//
#pragma once

#include "luif/sdl_host.h"

#include <SDL3/SDL.h>
#include <SDL3_ttf/SDL_ttf.h>
#include <lua.hpp>

#include <cstdint>
#include <string>
#include <string_view>
#include <unordered_map>
#include <vector>

namespace luif {

using Id = uint32_t;            // index into a pool; 0 is none
constexpr Id None = 0;

using Color = uint32_t;         // packed 0xAARRGGBB
constexpr Color White = 0xFFFFFFFF;

// r, g, b of color with its alpha multiplied by opacity
SDL_FColor toFColor(Color color, float opacity);

// x' = a x + c y + tx, y' = b x + d y + ty
struct Affine {
    float a = 1, b = 0, c = 0, d = 1, tx = 0, ty = 0;

    Affine operator*(const Affine &local) const;        // this is the parent
    SDL_FPoint apply(float x, float y) const;
    bool isTranslation() const { return a == 1 && b == 0 && c == 0 && d == 1; }
};

//
// Scene
//

enum class ContentKind : uint8_t { None, Image, Slices, Text, Fill };
enum class Align : uint8_t { Left, Center, Right };

enum NodeFlags : uint16_t {
    Visible = 1 << 0,
    Clip = 1 << 1,
    FlipX = 1 << 2,         // image
    FlipY = 1 << 3,         // image
    Grayscale = 1 << 4,     // image, slices
    HasFill = 1 << 5,       // fill: color is set
    HasBorder = 1 << 6,     // fill: borderColor is set
};

struct ImageContent { Id texture; Color tint; };
struct SlicesContent { Id texture; Color tint; float left, top, right, bottom; };
struct FillContent { Color color, borderColor; float borderWidth; };

struct Node {
    Id parent = None, firstChild = None, lastChild = None, prev = None, next = None;
    float x = 0, y = 0, rotation = 0, scale = 1, originX = 0, originY = 0;
    float width = 0, height = 0, opacity = 1;
    union {
        ImageContent image;
        SlicesContent slices;
        FillContent fill;
        Id text;                // index into Scene::texts
    };
    uint16_t generation = 0;    // bumped on destroy, so stale handles are caught
    uint16_t flags = Visible;
    ContentKind kind = ContentKind::None;
    bool alive = false;

    Node() : slices{} {}
    Affine local() const;       // T(x, y) T(origin) R(rotation) S(scale) T(-origin)
};

struct TextRun { Color color; uint32_t start; };        // from byte start of the text
struct PlacedGlyph { float x, y; uint32_t glyph; Color color; };   // glyph: index into its face

struct TextContent {
    Id font = None;
    Color color = White;
    Align align = Align::Left;
    bool wrap = false;
    bool isRuns = false;            // the text was given as runs, which may be none
    std::string text;               // the plain text (runs concatenated)
    std::vector<TextRun> runs;      // without isRuns: empty, one run in color
    // Layout cache (text.cpp): glyphs in the node's local units, laid out for
    // a box of layoutWidth; negative means not laid out.
    std::vector<PlacedGlyph> glyphs;
    float layoutWidth = -1;
    Id nextFree = None;
};

struct Scene {
    static constexpr Id Root = 1;   // parent of the top level nodes; never handed out

    std::vector<Node> nodes;        // [0] is none, [1] the root
    std::vector<TextContent> texts; // [0] is none
    Id freeNode = None, freeText = None;

    Scene();
    Id create();
    void destroy(Id node);          // detaches and releases the whole subtree
    // parent None attaches to the top level, before None appends. Returns an
    // error message, or null on success.
    const char *attach(Id node, Id parent, Id before);
    void detach(Id node);
    void clearContent(Id node);
    // Replaces the content with empty text content; content that is text
    // already keeps its buffers.
    TextContent &makeText(Id node);
    bool inScene(Id node) const;    // attached, directly or indirectly, to the root

    // Handles for Lua: index and generation in one number (a double, since
    // they do not fit a 32 bit lua_Integer)
    double handle(Id node) const;
    Id resolve(double handle) const;        // None for stale or invalid handles
};

//
// Textures. Handles are indices; nothing is released before the host is.
//

struct Texture {
    SDL_Texture *sdl = nullptr;     // shared by regions
    SDL_Texture *gray = nullptr;    // grayscale copy, made on first use (source entries only)
    Id source = None;               // for regions: the entry that owns sdl
    bool external = false;          // sdl belongs to the application (SdlHost::addTexture)
    float x = 0, y = 0, width = 0, height = 0;  // region within sdl, in pixels
};

// Where textures, fonts and readFile get their files: the application's
// openFile, or the file system with relative paths resolved against basePath.
struct Files {
    std::string basePath;
    SDL_IOStream *(*openFile)(const char *path, void *userdata) = nullptr;
    void *userdata = nullptr;

    SDL_IOStream *open(const std::string &path) const;     // null with SDL_GetError set
};

struct Textures {
    SDL_Renderer *renderer = nullptr;
    const Files *files = nullptr;
    SDL_ScaleMode filter = SDL_SCALEMODE_LINEAR;
    std::vector<Texture> items = std::vector<Texture>(1);   // [0] is none
    std::unordered_map<std::string, Id> byPath;

    // load and create return None on failure, and SDL_GetError() says why
    ~Textures();
    Id load(const std::string &path);                           // cached per path
    Id create(int width, int height, const uint32_t *argb);     // pixels as 0xAARRGGBB
    Id region(Id texture, float x, float y, float width, float height);
    Id addExternal(SDL_Texture *texture);
    void replaceExternal(Id texture, SDL_Texture *replacement);    // also in its regions; null draws nothing
    SDL_Texture *gray(Id texture);  // the grayscale copy, or the texture itself when that failed
    void setFilter(SDL_ScaleMode mode, Id texture = None);  // None: every texture, and new ones
    bool valid(Id texture) const { return texture > None && texture < items.size(); }
};

//
// Drawing
//

// Collects quads and submits them with SDL_RenderGeometry when the texture
// changes or flush is called (before clip changes and at the end).
struct Batch {
    SDL_Renderer *renderer = nullptr;
    SDL_Texture *texture = nullptr;
    std::vector<SDL_Vertex> vertices;
    std::vector<int> indices;

    // The local rectangle (x, y, w, h) under transform, textured with the
    // normalized coordinates (u0, v0)-(u1, v1); a null texture is solid colour.
    void quad(SDL_Texture *texture, const Affine &transform, float x, float y, float w, float h,
              float u0, float v0, float u1, float v1, SDL_FColor color);
    void flush();
};

//
// Text
//

// The codepoint at text[i], moving i past it. An invalid byte gives U+FFFD
// and moves one byte.
uint32_t decode(std::string_view text, size_t &i);

struct FontSpec {
    std::string file;               // resolved; empty: the default font
    float size = 12;
    bool shadow = false, outline = false;
    float shadowX = 1, shadowY = 1;
    Color shadowColor = 0xFF000000, outlineColor = 0xFF000000;
};

struct Fonts {
    struct Data;
    Data *d;

    Fonts(SDL_Renderer *renderer, const SdlHostOptions &options, const Files &files);
    ~Fonts();

    // Equal specs give the same id. None on failure, and SDL_GetError() says why.
    Id load(const FontSpec &spec);
    size_t count() const;           // ids are 1 to count() - 1
    float lineHeight(Id font) const;
    float textWidth(Id font, std::string_view text);    // one line
    // Word wraps at width; the lines are views into text. Returns the widest line.
    float wrap(Id font, std::string_view text, float width, std::vector<std::string_view> &lines);
    // Draws the text content in a box of the given width, laying it out when
    // the cached layout is for another width. Shadow and outline passes first.
    void draw(Batch &batch, const Affine &transform, TextContent &text, float boxWidth, float opacity);
};

//
// The host
//


struct SdlHost::Impl {
    lua_State *L;
    SDL_Window *window;
    SDL_Renderer *renderer;
    Files files;
    std::string module;
    bool inspect;
    bool manageTextInput;           // text input follows the focus of text fields

    Scene scene;
    Textures textures;
    Fonts fonts;
    Batch batch;

    int boxRef = LUA_NOREF;         // the userdata through which the host functions find the host
    int sinkRef = LUA_NOREF;        // the input sink table
    int updateRef = LUA_NOREF;      // require(module).update
    uint32_t pressedButtons = 0;    // bit per button a pointerPressed was delivered for
    std::string error;              // the last Lua error
    bool textInput = false;         // the host started text input on the window
    bool pointerOverUi = false;     // what the last pointerMoved returned
    bool inputError = false;        // error is from input and update() has yet to report it
    SDL_SystemCursor cursor = SDL_SYSTEM_CURSOR_DEFAULT;
    SDL_Cursor *cursors[SDL_SYSTEM_CURSOR_COUNT] = {};  // made on first use

    Impl(lua_State *L, SDL_Window *window, SDL_Renderer *renderer, const SdlHostOptions &options);
    ~Impl();
};

// Calls the function below its nargs arguments with a traceback. On an error
// the message goes to host.error (unless that holds an input error update()
// has yet to report) and nothing is left on the stack.
bool protectedCall(SdlHost::Impl &host, int nargs, int nresults);  // sdl_host.cpp
void registerLuaApi(SdlHost::Impl &host);                   // lua_api.cpp
bool feedEvent(SdlHost::Impl &host, const SDL_Event &event);    // input.cpp
void setCursor(SdlHost::Impl &host, const char *name);      // input.cpp
bool isKeyDown(const char *name);                           // input.cpp, LOVE key names
void renderScene(SdlHost::Impl &host);                      // render.cpp

} // namespace luif
