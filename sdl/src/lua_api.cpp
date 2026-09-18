//
// The host table of luif/host/interface.lua: plain functions with the host as
// their upvalue, stored in package.loaded["luif.sdl"]. Argument handling
// follows the Interface.*Content builders and the LOVE host.
//
// Lua errors are longjmps when Lua is built as C, so functions check their
// arguments before they create C++ objects that own memory.
//
#include "internal.h"

#include <cmath>

namespace luif {

namespace {

using Impl = SdlHost::Impl;

constexpr int MaxTextureSize = 16384;

const char *const alignNames[] = { "left", "center", "right", nullptr };       // Align
const char *const filterNames[] = { "nearest", "linear", nullptr };
const SDL_ScaleMode filterModes[] = { SDL_SCALEMODE_NEAREST, SDL_SCALEMODE_LINEAR };
const char *const kindNames[] = { "none", "image", "slices", "text", "fill" }; // ContentKind

const char *const capabilityNames[] = {
    "rotatedSlices", "rotatedText", "grayscale", "textureFilter", "pointerPosition", "keyState",
};

const struct { const char *name; float Node::*member; } nodeNumbers[] = {
    { "x", &Node::x }, { "y", &Node::y }, { "rotation", &Node::rotation },
    { "scale", &Node::scale }, { "originX", &Node::originX }, { "originY", &Node::originY },
    { "width", &Node::width }, { "height", &Node::height }, { "opacity", &Node::opacity },
};

//
// Lua 5.1 and LuaJIT to Lua 5.4
//

size_t rawLength(lua_State *L, int index)
{
#if LUA_VERSION_NUM >= 502
    return lua_rawlen(L, index);
#else
    return lua_objlen(L, index);
#endif
}

// Colours do not fit a 32 bit lua_Integer
void pushColor(lua_State *L, Color color)
{
    if constexpr (sizeof(lua_Integer) > 4)
        lua_pushinteger(L, lua_Integer(color));
    else
        lua_pushnumber(L, lua_Number(color));
}

//
// Arguments
//

// The upvalue is a box that the host empties when it goes, since Lua may
// hold on to these functions for longer
Impl &self(lua_State *L)
{
    Impl *host = *static_cast<Impl **>(lua_touserdata(L, lua_upvalueindex(1)));
    if (!host)
        luaL_error(L, "the host is gone");
    return *host;
}

// Whole sizes are integers, so that Lua 5.3 and later print them as such
void pushSize(lua_State *L, float size)
{
    if (size == std::floor(size))
        lua_pushinteger(L, lua_Integer(size));
    else
        lua_pushnumber(L, size);
}

Id checkNode(lua_State *L, int index)
{
    const Id node = lua_type(L, index) == LUA_TNUMBER
        ? self(L).scene.resolve(lua_tonumber(L, index)) : None;
    if (node == None)
        luaL_argerror(L, index, "invalid or destroyed node");
    return node;
}

Id optNode(lua_State *L, int index)
{
    return lua_isnoneornil(L, index) ? None : checkNode(L, index);
}

// A texture or font id: a whole number from 1 to count - 1
Id checkIndex(lua_State *L, int index, size_t count, const char *message)
{
    const lua_Number id = lua_type(L, index) == LUA_TNUMBER ? lua_tonumber(L, index) : 0;
    if (!(id >= 1 && id < lua_Number(count) && id == std::floor(id)))
        luaL_argerror(L, index, message);
    return Id(id);
}

Id checkTexture(lua_State *L, int index)
{
    return checkIndex(L, index, self(L).textures.items.size(), "invalid texture");
}

Id checkFont(lua_State *L, int index)
{
    return checkIndex(L, index, self(L).fonts.count(), "invalid font");
}

std::string_view checkView(lua_State *L, int index)
{
    size_t length = 0;
    const char *string = luaL_checklstring(L, index, &length);
    return { string, length };
}

// Wraps like Interface.color, so negative int32 values mean the same bits
Color toColor(lua_Number number)
{
    number = std::floor(std::fmod(number, 4294967296.0));
    return number == number ? Color(int64_t(number)) : 0;
}

Color optColor(lua_State *L, int index, Color fallback)
{
    return lua_isnoneornil(L, index) ? fallback : toColor(luaL_checknumber(L, index));
}

// Pushes tostring(value); with orEmpty "" for nil and false
const char *pushText(lua_State *L, int index, size_t *length, bool orEmpty)
{
    if (orEmpty && !lua_toboolean(L, index)) {
        lua_pushliteral(L, "");
    } else if (lua_type(L, index) == LUA_TSTRING) {
        lua_pushvalue(L, index);
    } else {
        lua_getglobal(L, "tostring");
        lua_pushvalue(L, index);
        lua_call(L, 1, 1);
        if (!lua_isstring(L, -1))
            luaL_error(L, "'tostring' must return a string");
    }
    return lua_tolstring(L, -1, length);
}

//
// Structure
//

int createNode(lua_State *L)
{
    Scene &scene = self(L).scene;
    const Id node = scene.create();
    if (node == None)
        return luaL_error(L, "createNode: too many nodes");
    lua_pushnumber(L, scene.handle(node));
    return 1;
}

int destroyNode(lua_State *L)
{
    self(L).scene.destroy(checkNode(L, 1));
    return 0;
}

int attach(lua_State *L)
{
    const Id node = checkNode(L, 1), parent = optNode(L, 2), before = optNode(L, 3);
    if (const char *message = self(L).scene.attach(node, parent, before))
        return luaL_error(L, "%s", message);
    return 0;
}

int detach(lua_State *L)
{
    self(L).scene.detach(checkNode(L, 1));
    return 0;
}

//
// Properties
//

int setTransform(lua_State *L)
{
    const Id id = checkNode(L, 1);
    const lua_Number x = luaL_checknumber(L, 2), y = luaL_checknumber(L, 3);
    const lua_Number rotation = luaL_optnumber(L, 4, 0), scale = luaL_optnumber(L, 5, 1);
    const lua_Number originX = luaL_optnumber(L, 6, 0), originY = luaL_optnumber(L, 7, 0);
    Node &node = self(L).scene.nodes[id];
    node.x = float(x);
    node.y = float(y);
    node.rotation = float(rotation);
    node.scale = float(scale);
    node.originX = float(originX);
    node.originY = float(originY);
    return 0;
}

int setSize(lua_State *L)
{
    const Id id = checkNode(L, 1);
    const lua_Number width = luaL_checknumber(L, 2), height = luaL_checknumber(L, 3);
    Node &node = self(L).scene.nodes[id];
    node.width = float(width);
    node.height = float(height);
    return 0;
}

int setOpacity(lua_State *L)
{
    const Id id = checkNode(L, 1);
    self(L).scene.nodes[id].opacity = float(luaL_checknumber(L, 2));
    return 0;
}

void setFlag(Node &node, uint16_t flag, bool on)
{
    node.flags = on ? node.flags | flag : node.flags & ~flag;
}

int setVisible(lua_State *L)
{
    setFlag(self(L).scene.nodes[checkNode(L, 1)], Visible, lua_toboolean(L, 2));
    return 0;
}

int setClip(lua_State *L)
{
    setFlag(self(L).scene.nodes[checkNode(L, 1)], Clip, lua_toboolean(L, 2));
    return 0;
}

//
// Content
//

uint16_t flagIf(lua_State *L, int index, NodeFlags flag)
{
    return lua_toboolean(L, index) ? flag : 0;
}

// Replaces the content of the node, once every argument is checked
Node &setContent(lua_State *L, Id id, ContentKind kind, uint16_t flags)
{
    Scene &scene = self(L).scene;
    scene.clearContent(id);             // clears the content flags too
    Node &node = scene.nodes[id];
    node.kind = kind;
    node.flags |= flags;
    return node;
}

int setImage(lua_State *L)
{
    const Id id = checkNode(L, 1);
    const ImageContent image = { checkTexture(L, 2), optColor(L, 3, White) };
    setContent(L, id, ContentKind::Image,
               flagIf(L, 4, FlipX) | flagIf(L, 5, FlipY) | flagIf(L, 6, Grayscale)).image = image;
    return 0;
}

int setSlices(lua_State *L)
{
    const Id id = checkNode(L, 1);
    const SlicesContent slices = {
        checkTexture(L, 2), optColor(L, 7, White), float(luaL_checknumber(L, 3)),
        float(luaL_checknumber(L, 4)), float(luaL_checknumber(L, 5)), float(luaL_checknumber(L, 6)),
    };
    setContent(L, id, ContentKind::Slices, flagIf(L, 8, Grayscale)).slices = slices;
    return 0;
}

int setText(lua_State *L)
{
    Scene &scene = self(L).scene;
    checkNode(L, 1);
    const Id font = checkFont(L, 2);
    const Color color = optColor(L, 4, White);
    const int align = lua_toboolean(L, 5) ? luaL_checkoption(L, 5, nullptr, alignNames) : 0;
    const bool wrap = lua_toboolean(L, 6);
    lua_settop(L, 6);

    // The text is normalized at index 7 first, since conversions can raise
    // and run Lua code: a string, or a fresh array of colour and string pairs.
    const bool isRuns = lua_istable(L, 3);
    const int count = isRuns ? int(rawLength(L, 3)) : 0;
    if (isRuns) {
        if (count % 2 != 0)
            return luaL_error(L, "setText: runs must be colour, string pairs");
        lua_createtable(L, count, 0);
        for (int i = 1; i <= count; i += 2) {
            lua_rawgeti(L, 3, i);
            if (!lua_isnil(L, -1) && lua_type(L, -1) != LUA_TNUMBER)
                return luaL_error(L, "setText: colour must be a packed 0xAARRGGBB number");
            lua_pushnumber(L, lua_isnil(L, -1) ? White : toColor(lua_tonumber(L, -1)));
            lua_rawseti(L, 7, i);
            lua_rawgeti(L, 3, i + 1);
            pushText(L, lua_gettop(L), nullptr, false);
            lua_rawseti(L, 7, i + 1);
            lua_pop(L, 2);
        }
    } else {
        pushText(L, 3, nullptr, true);
    }

    // A __tostring may have destroyed the node in the meantime
    TextContent &text = scene.makeText(checkNode(L, 1));
    text.font = font;
    text.color = color;
    text.align = Align(align);
    text.wrap = wrap;
    text.isRuns = isRuns;
    size_t length = 0;
    for (int i = 1; i <= count; i += 2) {
        lua_rawgeti(L, 7, i);
        lua_rawgeti(L, 7, i + 1);
        const char *string = lua_tolstring(L, -1, &length);
        text.runs.push_back({ Color(lua_tonumber(L, -2)), uint32_t(text.text.size()) });
        text.text.append(string, length);
        lua_pop(L, 2);
    }
    if (!isRuns) {
        const char *string = lua_tolstring(L, 7, &length);
        text.text.assign(string, length);
    }
    return 0;
}

int setFill(lua_State *L)
{
    const Id id = checkNode(L, 1);
    const uint16_t flags = flagIf(L, 2, HasFill) | flagIf(L, 3, HasBorder);
    FillContent fill = {};
    if (flags & HasFill)
        fill.color = toColor(luaL_checknumber(L, 2));
    if (flags & HasBorder) {
        fill.borderColor = toColor(luaL_checknumber(L, 3));
        fill.borderWidth = lua_toboolean(L, 4) ? float(luaL_checknumber(L, 4)) : 1;
    }
    setContent(L, id, ContentKind::Fill, flags).fill = fill;
    return 0;
}

int clearContent(lua_State *L)
{
    self(L).scene.clearContent(checkNode(L, 1));
    return 0;
}

//
// Resources
//

int loadTexture(lua_State *L)
{
    Impl &host = self(L);
    const Id id = host.textures.load(std::string(checkView(L, 1)));
    if (id == None) {
        lua_pushnil(L);
        lua_pushfstring(L, "cannot load texture: %s", SDL_GetError());
        return 2;
    }
    lua_pushinteger(L, id);
    return 1;
}

// Rounds like LOVE's ImageData:setPixel
uint32_t toByte(lua_Number value)
{
    return value >= 255 ? 255 : value > 0 ? uint32_t(value + 0.5) : 0;
}

// pixel(x, y) from 0, 0 returns r, g, b, a in 0..255, a defaults to 255, as
// in luif/love/texture.lua.
int createTexture(lua_State *L)
{
    const lua_Number width = luaL_checknumber(L, 1), height = luaL_checknumber(L, 2);
    if (!(width >= 1 && width <= MaxTextureSize && height >= 1 && height <= MaxTextureSize))
        return luaL_error(L, "createTexture: invalid size");
    const bool hasPixel = lua_toboolean(L, 3);
    if (hasPixel)
        luaL_checktype(L, 3, LUA_TFUNCTION);
    lua_settop(L, 3);

    // A userdata, so an error in pixel leaves the buffer to the collector
    const int w = int(width), h = int(height);
    auto *pixels = static_cast<uint32_t *>(lua_newuserdata(L, size_t(w) * h * sizeof(uint32_t)));
    for (int y = 0; y < h; ++y) {
        for (int x = 0; x < w; ++x) {
            uint32_t &argb = pixels[size_t(y) * w + x];
            argb = White;
            if (!hasPixel)
                continue;
            lua_pushvalue(L, 3);
            lua_pushinteger(L, x);
            lua_pushinteger(L, y);
            lua_call(L, 2, 4);
            if (!lua_isnumber(L, -4) || !lua_isnumber(L, -3) || !lua_isnumber(L, -2))
                return luaL_error(L, "createTexture: pixel must return r, g, b numbers");
            const uint32_t alpha = lua_toboolean(L, -1) ? toByte(lua_tonumber(L, -1)) : 255;
            argb = alpha << 24 | toByte(lua_tonumber(L, -4)) << 16
                | toByte(lua_tonumber(L, -3)) << 8 | toByte(lua_tonumber(L, -2));
            lua_pop(L, 4);
        }
    }

    const Id id = self(L).textures.create(w, h, pixels);
    if (id == None)
        return luaL_error(L, "createTexture: %s", SDL_GetError());
    lua_pushinteger(L, id);
    return 1;
}

int textureRegion(lua_State *L)
{
    const Id texture = checkTexture(L, 1);
    const lua_Number x = luaL_checknumber(L, 2), y = luaL_checknumber(L, 3);
    const lua_Number width = luaL_checknumber(L, 4), height = luaL_checknumber(L, 5);
    lua_pushinteger(L, self(L).textures.region(texture, float(x), float(y),
                                               float(width), float(height)));
    return 1;
}

int textureSize(lua_State *L)
{
    const Texture &texture = self(L).textures.items[checkTexture(L, 1)];
    pushSize(L, texture.width);
    pushSize(L, texture.height);
    return 2;
}

// Reads field[index] of the table on top as a colour or number
lua_Number optEntry(lua_State *L, int index, lua_Number fallback)
{
    lua_rawgeti(L, -1, index);
    if (lua_toboolean(L, -1) && lua_type(L, -1) != LUA_TNUMBER)
        luaL_error(L, "loadFont: shadow and outline take numbers");
    const lua_Number value = lua_toboolean(L, -1) ? lua_tonumber(L, -1) : fallback;
    lua_pop(L, 1);
    return value;
}

// Pushes spec[name] when it is a table; false when it is nil or false
bool pushStyle(lua_State *L, const char *name)
{
    lua_getfield(L, 1, name);
    if (!lua_toboolean(L, -1))
        return false;
    if (!lua_istable(L, -1))
        luaL_error(L, "loadFont: %s must be a table", name);
    return true;
}

// The defaults are those of luif/love/font.lua
int loadFont(lua_State *L)
{
    if (lua_isnoneornil(L, 1)) {
        lua_settop(L, 0);
        lua_newtable(L);
    }
    luaL_checktype(L, 1, LUA_TTABLE);
    lua_settop(L, 1);

    lua_getfield(L, 1, "file");     // stays on the stack while file is used
    const char *file = "";
    if (lua_toboolean(L, -1)) {
        if (lua_type(L, -1) != LUA_TSTRING)
            return luaL_error(L, "loadFont: file must be a path or false");
        file = lua_tostring(L, -1);
    }
    lua_getfield(L, 1, "size");
    if (lua_toboolean(L, -1) && lua_type(L, -1) != LUA_TNUMBER)
        return luaL_error(L, "loadFont: size must be a number");
    const lua_Number size = lua_toboolean(L, -1) ? lua_tonumber(L, -1) : 12;

    lua_Number shadowX = 1, shadowY = 1, shadowColor = 0xFF000000, outlineColor = 0xFF000000;
    const bool shadow = pushStyle(L, "shadow");
    if (shadow) {
        shadowX = optEntry(L, 1, shadowX);
        shadowY = optEntry(L, 2, shadowY);
        shadowColor = optEntry(L, 3, shadowColor);
    }
    const bool outline = pushStyle(L, "outline");
    if (outline)
        outlineColor = optEntry(L, 1, outlineColor);

    Id id = None;
    {
        Impl &host = self(L);
        FontSpec spec;
        spec.file = file;
        spec.size = float(size);
        spec.shadow = shadow;
        spec.outline = outline;
        spec.shadowX = float(shadowX);
        spec.shadowY = float(shadowY);
        spec.shadowColor = toColor(shadowColor);
        spec.outlineColor = toColor(outlineColor);
        id = host.fonts.load(spec);
    }
    if (id == None)
        return luaL_error(L, "loadFont: %s", SDL_GetError());
    lua_pushinteger(L, id);
    return 1;
}

int textWidth(lua_State *L)
{
    const Id font = checkFont(L, 1);
    lua_pushnumber(L, self(L).fonts.textWidth(font, checkView(L, 2)));
    return 1;
}

int lineHeight(lua_State *L)
{
    lua_pushnumber(L, self(L).fonts.lineHeight(checkFont(L, 1)));
    return 1;
}

int wrapText(lua_State *L)
{
    const Id font = checkFont(L, 1);
    const std::string_view text = checkView(L, 2);
    const lua_Number width = luaL_checknumber(L, 3);

    std::vector<std::string_view> lines;
    lua_pushnumber(L, self(L).fonts.wrap(font, text, float(width), lines));
    lua_createtable(L, int(lines.size()), 0);
    for (size_t i = 0; i < lines.size(); ++i) {
        lua_pushlstring(L, lines[i].data(), lines[i].size());
        lua_rawseti(L, -2, int(i + 1));
    }
    return 2;
}

// SDL has one scale mode per texture: mag wins, since a UI is rarely minified
int setTextureFilter(lua_State *L)
{
    const int mode = luaL_checkoption(L, lua_isnoneornil(L, 2) ? 1 : 2, nullptr, filterNames);
    luaL_checkoption(L, 1, nullptr, filterNames);
    self(L).textures.setFilter(filterModes[mode], lua_isnoneornil(L, 3) ? None : checkTexture(L, 3));
    return 0;
}

//
// System
//

int time(lua_State *L)
{
    lua_pushnumber(L, lua_Number(SDL_GetTicksNS()) / 1e6);
    return 1;
}

// In the coordinates that input and drawing use: the logical presentation
// when the application set one, otherwise the output over the render scale
int screenSize(lua_State *L)
{
    SDL_Renderer *renderer = self(L).renderer;
    int width = 0, height = 0;
    SDL_GetRenderLogicalPresentation(renderer, &width, &height, nullptr);
    float scaleX = 1, scaleY = 1;
    if (width <= 0 || height <= 0) {
        SDL_GetRenderOutputSize(renderer, &width, &height);
        SDL_GetRenderScale(renderer, &scaleX, &scaleY);
    }
    pushSize(L, scaleX > 0 ? width / scaleX : width);
    pushSize(L, scaleY > 0 ? height / scaleY : height);
    return 2;
}

// Invalid bytes become U+FFFD, since the framework expects valid UTF-8. The
// host's own decoder judges that: SDL_StepUTF8 lets some invalid sequences by.
int getClipboard(lua_State *L)
{
    char *text = SDL_GetClipboardText();
    const std::string_view view = text ? text : "";
    luaL_Buffer buffer;
    luaL_buffinit(L, &buffer);
    for (size_t at = 0; at < view.size();) {
        const size_t start = at;
        if (decode(view, at) == 0xFFFD)     // a real U+FFFD is replaced by itself
            luaL_addlstring(&buffer, "\xEF\xBF\xBD", 3);
        else
            luaL_addlstring(&buffer, view.data() + start, at - start);
    }
    luaL_pushresult(&buffer);
    SDL_free(text);
    return 1;
}

int setClipboard(lua_State *L)
{
    SDL_SetClipboardText(pushText(L, 1, nullptr, true));
    return 0;
}

int setCursorName(lua_State *L)
{
    setCursor(self(L), lua_type(L, 1) == LUA_TSTRING ? lua_tostring(L, 1) : nullptr);
    return 0;
}

int readFile(lua_State *L)
{
    size_t size = 0;
    SDL_IOStream *io = self(L).files.open(std::string(checkView(L, 1)));
    void *contents = io ? SDL_LoadFile_IO(io, &size, true) : nullptr;
    if (!contents) {
        lua_pushnil(L);
        lua_pushstring(L, SDL_GetError());
        return 2;
    }
    lua_pushlstring(L, static_cast<const char *>(contents), size);
    SDL_free(contents);
    return 1;
}

int capabilities(lua_State *L)
{
    lua_newtable(L);
    for (const char *name : capabilityNames) {
        lua_pushboolean(L, true);
        lua_setfield(L, -2, name);
    }
    if (self(L).inspect) {
        lua_pushboolean(L, true);
        lua_setfield(L, -2, "inspect");
    }
    return 1;
}

// In render output pixels, like the positions of the input feed
int pointerPosition(lua_State *L)
{
    float x = 0, y = 0;
    SDL_GetMouseState(&x, &y);
    SDL_RenderCoordinatesFromWindow(self(L).renderer, x, y, &x, &y);
    lua_pushnumber(L, x);
    lua_pushnumber(L, y);
    return 2;
}

int isKeyDownName(lua_State *L)
{
    lua_pushboolean(L, lua_type(L, 1) == LUA_TSTRING && isKeyDown(lua_tostring(L, 1)));
    return 1;
}

int setInputSink(lua_State *L)
{
    Impl &host = self(L);
    if (lua_toboolean(L, 1))
        luaL_checktype(L, 1, LUA_TTABLE);
    lua_settop(L, 1);
    luaL_unref(L, LUA_REGISTRYINDEX, host.sinkRef);
    host.sinkRef = lua_toboolean(L, 1) ? luaL_ref(L, LUA_REGISTRYINDEX) : LUA_NOREF;
    return 0;
}

//
// Inspect: the records Interface.*Content would build
//

void setColorField(lua_State *L, const char *name, Color color, bool present = true)
{
    if (present)
        pushColor(L, color);
    else
        lua_pushboolean(L, false);
    lua_setfield(L, -2, name);
}

void setBoolField(lua_State *L, const char *name, bool value)
{
    lua_pushboolean(L, value);
    lua_setfield(L, -2, name);
}

void setNumberField(lua_State *L, const char *name, lua_Number value)
{
    lua_pushnumber(L, value);
    lua_setfield(L, -2, name);
}

void setIdField(lua_State *L, const char *name, Id id)
{
    lua_pushinteger(L, id);
    lua_setfield(L, -2, name);
}

// The string, or the runs array { color, string, ... }
void pushTextValue(lua_State *L, const TextContent &text)
{
    if (!text.isRuns) {
        lua_pushlstring(L, text.text.data(), text.text.size());
        return;
    }
    const size_t count = text.runs.size();
    lua_createtable(L, int(count * 2), 0);
    for (size_t i = 0; i < count; ++i) {
        const size_t start = text.runs[i].start;
        const size_t end = i + 1 < count ? text.runs[i + 1].start : text.text.size();
        pushColor(L, text.runs[i].color);
        lua_rawseti(L, -2, int(i * 2 + 1));
        lua_pushlstring(L, text.text.data() + start, end - start);
        lua_rawseti(L, -2, int(i * 2 + 2));
    }
}

void pushContent(lua_State *L, const Scene &scene, const Node &node)
{
    if (node.kind == ContentKind::None) {
        lua_pushboolean(L, false);
        return;
    }
    lua_newtable(L);
    lua_pushstring(L, kindNames[int(node.kind)]);
    lua_setfield(L, -2, "kind");
    switch (node.kind) {
    case ContentKind::Image:
        setIdField(L, "texture", node.image.texture);
        setColorField(L, "tint", node.image.tint);
        setBoolField(L, "flipX", node.flags & FlipX);
        setBoolField(L, "flipY", node.flags & FlipY);
        setBoolField(L, "grayscale", node.flags & Grayscale);
        break;
    case ContentKind::Slices:
        setIdField(L, "texture", node.slices.texture);
        setNumberField(L, "left", node.slices.left);
        setNumberField(L, "top", node.slices.top);
        setNumberField(L, "right", node.slices.right);
        setNumberField(L, "bottom", node.slices.bottom);
        setColorField(L, "tint", node.slices.tint);
        setBoolField(L, "grayscale", node.flags & Grayscale);
        break;
    case ContentKind::Text: {
        const TextContent &text = scene.texts[node.text];
        setIdField(L, "font", text.font);
        pushTextValue(L, text);
        lua_setfield(L, -2, "text");
        setColorField(L, "color", text.color);
        lua_pushstring(L, alignNames[int(text.align)]);
        lua_setfield(L, -2, "align");
        setBoolField(L, "wrap", text.wrap);
        break;
    }
    case ContentKind::Fill:
        setColorField(L, "color", node.fill.color, node.flags & HasFill);
        setColorField(L, "borderColor", node.fill.borderColor, node.flags & HasBorder);
        setNumberField(L, "borderWidth", node.fill.borderWidth);
        break;
    case ContentKind::None:
        break;
    }
}

void pushChildren(lua_State *L, const Scene &scene, Id parent)
{
    lua_newtable(L);
    int count = 0;
    for (Id child = scene.nodes[parent].firstChild; child != None; child = scene.nodes[child].next) {
        lua_pushnumber(L, scene.handle(child));
        lua_rawseti(L, -2, ++count);
    }
}

int inspect(lua_State *L)
{
    const Scene &scene = self(L).scene;
    const Id id = checkNode(L, 1);
    const Node node = scene.nodes[id];  // a copy: a finalizer run by an allocation may grow the pool

    lua_createtable(L, 0, 16);
    if (node.parent != None && node.parent != Scene::Root)
        setNumberField(L, "parent", scene.handle(node.parent));
    setBoolField(L, "topLevel", node.parent == Scene::Root);
    setBoolField(L, "inScene", scene.inScene(id));
    pushChildren(L, scene, id);
    lua_setfield(L, -2, "children");
    for (const auto &number : nodeNumbers)
        setNumberField(L, number.name, node.*number.member);
    setBoolField(L, "visible", node.flags & Visible);
    setBoolField(L, "clip", node.flags & Clip);
    pushContent(L, scene, node);
    lua_setfield(L, -2, "content");
    return 1;
}

int topLevel(lua_State *L)
{
    pushChildren(L, self(L).scene, Scene::Root);
    return 1;
}

const luaL_Reg functions[] = {
    { "createNode", createNode }, { "destroyNode", destroyNode },
    { "attach", attach }, { "detach", detach },
    { "setTransform", setTransform }, { "setSize", setSize }, { "setOpacity", setOpacity },
    { "setVisible", setVisible }, { "setClip", setClip },
    { "setImage", setImage }, { "setSlices", setSlices }, { "setText", setText },
    { "setFill", setFill }, { "clearContent", clearContent },
    { "loadTexture", loadTexture }, { "createTexture", createTexture },
    { "textureRegion", textureRegion }, { "textureSize", textureSize },
    { "loadFont", loadFont }, { "textWidth", textWidth }, { "lineHeight", lineHeight },
    { "wrapText", wrapText }, { "setTextureFilter", setTextureFilter },
    { "time", time }, { "screenSize", screenSize },
    { "getClipboard", getClipboard }, { "setClipboard", setClipboard },
    { "setCursor", setCursorName }, { "readFile", readFile }, { "capabilities", capabilities },
    { "pointerPosition", pointerPosition }, { "isKeyDown", isKeyDownName },
    { "setInputSink", setInputSink },
    { nullptr, nullptr },
};

const luaL_Reg inspectFunctions[] = {
    { "inspect", inspect }, { "topLevel", topLevel },
    { nullptr, nullptr },
};

// luaL_setfuncs for every Lua version: into the table on top, with the value
// below it as the upvalue
void setFunctions(lua_State *L, const luaL_Reg *functions)
{
    for (; functions->name; ++functions) {
        lua_pushvalue(L, -2);
        lua_pushcclosure(L, functions->func, 1);
        lua_setfield(L, -2, functions->name);
    }
}

} // namespace

void registerLuaApi(SdlHost::Impl &host)
{
    lua_State *L = host.L;
    // The box with the host that self() reads; the registry keeps it for ~Impl
    *static_cast<Impl **>(lua_newuserdata(L, sizeof(Impl *))) = &host;
    lua_pushvalue(L, -1);
    host.boxRef = luaL_ref(L, LUA_REGISTRYINDEX);

    lua_newtable(L);
    setFunctions(L, functions);
    if (host.inspect)
        setFunctions(L, inspectFunctions);

    // package.loaded, under the name every Lua version gives it
    lua_getfield(L, LUA_REGISTRYINDEX, "_LOADED");
    if (lua_istable(L, -1)) {
        lua_pushvalue(L, -2);
        lua_setfield(L, -2, "luif.sdl");
    }
    lua_pop(L, 3);
}

} // namespace luif
