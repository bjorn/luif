#include "app_api.h"

#include "luif/sdl_host.h"

#include <lua.hpp>

#include <cstdio>

namespace {

App &self(lua_State *L)
{
    return *static_cast<App *>(lua_touserdata(L, lua_upvalueindex(1)));
}

int quit(lua_State *L)
{
    App &app = self(L);
    app.exitCode = static_cast<int>(luaL_optinteger(L, 1, 0));
    app.running = false;
    return 0;
}

int setTitle(lua_State *L)
{
    SDL_SetWindowTitle(self(L).window, luaL_checkstring(L, 1));
    return 0;
}

int setWindowSize(lua_State *L)
{
    App &app = self(L);
    int width = static_cast<int>(luaL_checknumber(L, 1));
    int height = static_cast<int>(luaL_checknumber(L, 2));
    SDL_SetWindowSize(app.window, width, height);
    // Window managers resize asynchronously; scripts expect the new size
    SDL_SyncWindow(app.window);
    return 0;
}

int windowSize(lua_State *L)
{
    int width = 0, height = 0;
    SDL_GetWindowSizeInPixels(self(L).window, &width, &height);
    lua_pushinteger(L, width);
    lua_pushinteger(L, height);
    return 2;
}

int setBackgroundColor(lua_State *L)
{
    // A number rather than an integer: 0xFF000000 and up do not fit the
    // integers of a 32 bit Lua 5.1
    self(L).background = static_cast<Uint32>(luaL_checknumber(L, 1));
    return 0;
}

int screenshot(lua_State *L)
{
    self(L).screenshot = luaL_checkstring(L, 1);
    return 0;
}

int reload(lua_State *L)
{
    self(L).reload = true;
    return 0;
}

int watch(lua_State *L)
{
    App &app = self(L);
    std::string directory = luaL_checkstring(L, 1);
    bool known = false;
    for (const std::string &watched : app.watched)
        known = known || watched == directory;
    if (!known)
        app.watched.push_back(directory);
    return 0;
}

int textInputActive(lua_State *L)
{
    lua_pushboolean(L, SDL_TextInputActive(self(L).window));
    return 1;
}

// Tests read back what the host draws with these two
int capture(lua_State *L)
{
    App &app = self(L);
    appDraw(app);
    SDL_DestroySurface(app.capture);
    app.capture = SDL_RenderReadPixels(app.renderer, nullptr);
    if (!app.capture)
        return luaL_error(L, "capture failed: %s", SDL_GetError());
    return 0;
}

int pixel(lua_State *L)
{
    App &app = self(L);
    Uint8 r, g, b, a;
    if (!app.capture || !SDL_ReadSurfacePixel(app.capture, int(luaL_checknumber(L, 1)),
                                              int(luaL_checknumber(L, 2)), &r, &g, &b, &a))
        return luaL_error(L, "no captured pixel there");
    lua_pushnumber(L, lua_Number(Uint32(a) << 24 | Uint32(r) << 16 | Uint32(g) << 8 | b));
    return 1;
}

int setFrameTime(lua_State *L)
{
    double seconds = luaL_optnumber(L, 1, 0);
    self(L).frameTime = seconds > 0 ? seconds : 0;
    return 0;
}

const luaL_Reg functions[] = {
    { "quit", quit },
    { "setTitle", setTitle },
    { "setWindowSize", setWindowSize },
    { "windowSize", windowSize },
    { "setBackgroundColor", setBackgroundColor },
    { "screenshot", screenshot },
    { "reload", reload },
    { "watch", watch },
    { "textInputActive", textInputActive },
    { "capture", capture },
    { "pixel", pixel },
    { "setFrameTime", setFrameTime },
    { nullptr, nullptr },
};

// The package.preload entry: builds the module table on the first require
int load(lua_State *L)
{
    App &app = self(L);
    lua_newtable(L);

    // luaL_setfuncs with an upvalue, which Lua 5.1 does not have
    for (const luaL_Reg *f = functions; f->name; f++) {
        lua_pushlightuserdata(L, &app);
        lua_pushcclosure(L, f->func, 1);
        lua_setfield(L, -2, f->name);
    }

    lua_pushstring(L, app.source.c_str());
    lua_setfield(L, -2, "source");

    lua_newtable(L);
    for (size_t i = 0; i < app.args.size(); i++) {
        lua_pushstring(L, app.args[i].c_str());
        lua_rawseti(L, -2, static_cast<int>(i) + 1);
    }
    lua_setfield(L, -2, "args");

    // The main loop finds the table (for app.update) in the registry
    lua_pushlightuserdata(L, &app);
    lua_pushvalue(L, -2);
    lua_rawset(L, LUA_REGISTRYINDEX);
    return 1;
}

int traceback(lua_State *L)
{
    // debug.traceback rather than luaL_traceback, which Lua 5.1 lacks
    lua_getglobal(L, "debug");
    lua_getfield(L, -1, "traceback");
    lua_pushvalue(L, 1);
    lua_pushinteger(L, 2);
    lua_call(L, 2, 1);
    return 1;
}

} // namespace

void appRegister(lua_State *L, App &app)
{
    lua_getglobal(L, "package");
    lua_getfield(L, -1, "preload");
    lua_pushlightuserdata(L, &app);
    lua_pushcclosure(L, load, 1);
    lua_setfield(L, -2, "app");
    lua_pop(L, 2);
}

bool appUpdate(lua_State *L, App &app, double dt, std::string *message)
{
    lua_pushlightuserdata(L, &app);
    lua_rawget(L, LUA_REGISTRYINDEX);
    if (!lua_istable(L, -1)) {      // the script never required the module
        lua_pop(L, 1);
        return true;
    }
    lua_getfield(L, -1, "update");
    lua_remove(L, -2);
    if (!lua_isfunction(L, -1)) {
        lua_pop(L, 1);
        return true;
    }
    lua_pushnumber(L, dt);
    return appCall(L, 1, 0, message);
}

void appDraw(App &app)
{
    Uint32 color = app.background;
    SDL_SetRenderDrawColor(app.renderer, color >> 16 & 0xFF, color >> 8 & 0xFF, color & 0xFF,
                           color >> 24);
    SDL_RenderClear(app.renderer);
    // A game draws its world here; the UI goes over it
    app.ui->render();
}

void appSaveScreenshot(App &app)
{
    if (app.screenshot.empty())
        return;
    std::string path;
    path.swap(app.screenshot);

    size_t slash = path.find_last_of('/');
    if (slash != std::string::npos && slash > 0)
        SDL_CreateDirectory(path.substr(0, slash).c_str());

    SDL_Surface *surface = SDL_RenderReadPixels(app.renderer, nullptr);
    if (surface && SDL_SavePNG(surface, path.c_str()))
        printf("screenshot written to %s\n", path.c_str());
    else
        fprintf(stderr, "screenshot %s failed: %s\n", path.c_str(), SDL_GetError());
    SDL_DestroySurface(surface);
}

void appReset(lua_State *L, App &app)
{
    lua_pushlightuserdata(L, &app);
    lua_pushnil(L);
    lua_rawset(L, LUA_REGISTRYINDEX);
    app.background = 0xFF000000;
    app.frameTime = 0;
    app.screenshot.clear();
    app.reload = false;
}

bool appCall(lua_State *L, int arguments, int results, std::string *message)
{
    int handler = lua_gettop(L) - arguments;
    lua_pushcfunction(L, traceback);
    lua_insert(L, handler);
    bool ok = lua_pcall(L, arguments, results, handler) == 0;
    if (!ok) {
        const char *text = lua_tostring(L, -1);
        text = text ? text : "(the error is not a string)";
        fprintf(stderr, "%s\n", text);
        if (message)
            *message = text;
        lua_pop(L, 1);
    }
    lua_remove(L, handler);
    return ok;
}
