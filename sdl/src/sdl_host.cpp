//
// The public class: construction, the update call into Lua, and path
// resolution.
//
#include "internal.h"

#include <cctype>

namespace luif {

namespace {

// debug.traceback through Lua, which every Lua version has
int traceback(lua_State *L)
{
    lua_getglobal(L, "debug");
    if (lua_istable(L, -1)) {
        lua_getfield(L, -1, "traceback");
        if (lua_isfunction(L, -1)) {
            lua_pushvalue(L, 1);
            lua_pushinteger(L, 2);
            lua_call(L, 2, 1);
            return 1;
        }
    }
    lua_settop(L, 1);
    return 1;
}

} // namespace

bool protectedCall(SdlHost::Impl &host, int nargs, int nresults)
{
    lua_State *L = host.L;
    const int handler = lua_gettop(L) - nargs;
    lua_pushcfunction(L, traceback);
    lua_insert(L, handler);
    const bool ok = lua_pcall(L, nargs, nresults, handler) == 0;
    if (!ok) {
        const char *message = lua_tostring(L, -1);
        if (!host.inputError)
            host.error = message ? message : "error object is not a string";
        lua_pop(L, 1);
    }
    lua_remove(L, handler);
    return ok;
}

SDL_IOStream *Files::open(const std::string &path) const
{
    if (openFile)
        return openFile(path.c_str(), userdata);
    const bool drive = path.size() > 1 && path[1] == ':' && std::isalpha((unsigned char)path[0]);
    const bool relative = !basePath.empty() && !drive && (path.empty() || path[0] != '/');
    return SDL_IOFromFile((relative ? basePath + "/" + path : path).c_str(), "rb");
}

SdlHost::Impl::Impl(lua_State *L, SDL_Window *window, SDL_Renderer *renderer,
                    const SdlHostOptions &options)
    : L(L)
    , window(window)
    , renderer(renderer)
    , files{ options.basePath ? options.basePath : "", options.openFile, options.userdata }
    , module(options.module ? options.module : "luif")
    , inspect(options.inspect)
    , manageTextInput(options.textInput)
    , fonts(renderer, options, files)
{
    textures.renderer = renderer;
    textures.files = &files;
    batch.renderer = renderer;
    registerLuaApi(*this);
}

// The Lua state has to be open still
SdlHost::Impl::~Impl()
{
    // Lua may keep the host functions; they find an empty box from now on
    lua_rawgeti(L, LUA_REGISTRYINDEX, boxRef);
    if (Impl **box = static_cast<Impl **>(lua_touserdata(L, -1)))
        *box = nullptr;
    lua_pop(L, 1);
    luaL_unref(L, LUA_REGISTRYINDEX, boxRef);
    luaL_unref(L, LUA_REGISTRYINDEX, sinkRef);
    luaL_unref(L, LUA_REGISTRYINDEX, updateRef);
    lua_getfield(L, LUA_REGISTRYINDEX, "_LOADED");
    if (lua_istable(L, -1)) {
        lua_pushnil(L);
        lua_setfield(L, -2, "luif.sdl");
    }
    lua_pop(L, 1);

    for (SDL_Cursor *cursor : cursors)
        SDL_DestroyCursor(cursor);      // null is fine
    if (textInput)
        SDL_StopTextInput(window);
}

SdlHost::SdlHost(lua_State *L, SDL_Window *window, SDL_Renderer *renderer,
                 const SdlHostOptions &options)
    : d(new Impl(L, window, renderer, options))
{
}

SdlHost::~SdlHost()
{
    delete d;
}

bool SdlHost::handleEvent(const SDL_Event &event)
{
    return feedEvent(*d, event);
}

bool SdlHost::update(double seconds)
{
    // An error raised while handling input is reported here, once
    if (d->inputError) {
        d->inputError = false;
        return false;
    }
    d->error.clear();

    lua_State *L = d->L;
    const int top = lua_gettop(L);
    if (d->updateRef == LUA_NOREF) {
        lua_getglobal(L, "require");
        lua_pushstring(L, d->module.c_str());
        if (!protectedCall(*d, 1, 1))
            return false;
        if (lua_istable(L, -1))
            lua_getfield(L, -1, "update");
        if (!lua_isfunction(L, -1)) {
            lua_settop(L, top);
            d->error = "module '" + d->module + "' has no update function";
            return false;
        }
        d->updateRef = luaL_ref(L, LUA_REGISTRYINDEX);
        lua_settop(L, top);
    }

    lua_rawgeti(L, LUA_REGISTRYINDEX, d->updateRef);
    lua_pushnumber(L, seconds);
    return protectedCall(*d, 1, 0);
}

void SdlHost::render()
{
    renderScene(*d);
}

bool SdlHost::pointerOverUi() const
{
    return d->pointerOverUi;
}

double SdlHost::addTexture(SDL_Texture *texture)
{
    return d->textures.addExternal(texture);
}

void SdlHost::replaceTexture(double handle, SDL_Texture *texture)
{
    const Id id = handle >= 1 && handle < double(d->textures.items.size()) ? Id(handle) : None;
    if (id != None && d->textures.items[id].external)
        d->textures.replaceExternal(id, texture);
}

const char *SdlHost::error() const
{
    return d->error.c_str();
}

} // namespace luif
