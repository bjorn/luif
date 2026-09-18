//
// luif-sdl runs a directory with a main.lua, like love does:
//
//     luif-sdl [--inspect] <directory> [args...]
//
// It is also the example of an SDL3 application that embeds Luif: it owns
// the window, the renderer, the Lua state and the main loop, hands the UI its
// events first, and has a Lua API of its own next to Luif's (app_api.h).
//

#include "app_api.h"

#include <luif/sdl_host.h>

#include <lua.hpp>

#include <cstdio>
#include <filesystem>

extern const unsigned char luif_default_font[];     // font/Vera.ttf
extern const size_t luif_default_font_size;

namespace {

const Uint64 FRAME_NS = SDL_NS_PER_SECOND / 60;

// The absolute directory without a trailing separator
std::filesystem::path sourceDirectory(const char *argument)
{
    std::error_code error;
    std::filesystem::path path = std::filesystem::absolute(argument, error);
    if (error)
        return argument;
    path = path.lexically_normal();
    return path.has_filename() ? path : path.parent_path();
}

// Lets main.lua require the files next to it
void prependPackagePath(lua_State *L, const std::string &directory)
{
    lua_getglobal(L, "package");
    lua_getfield(L, -1, "path");
    const char *path = lua_tostring(L, -1);
    lua_pushfstring(L, "%s/?.lua;%s/?/init.lua;%s", directory.c_str(), directory.c_str(),
                    path ? path : "");
    lua_setfield(L, -3, "path");
    lua_pop(L, 2);
}

// Input the UI did not handle is the application's. A game would steer its
// character here; this application toggles fullscreen with F11.
void handleEvent(App &app, const SDL_Event &event)
{
    if (event.type == SDL_EVENT_QUIT) {
        app.running = false;
    } else if (event.type == SDL_EVENT_KEY_DOWN && event.key.key == SDLK_F11 && !event.key.repeat) {
        bool fullscreen = SDL_GetWindowFlags(app.window) & SDL_WINDOW_FULLSCREEN;
        SDL_SetWindowFullscreen(app.window, !fullscreen);
    }
}

// The host lives in here, so that it is gone before the Lua state closes
int run(lua_State *L, App &app, bool inspect)
{
    prependPackagePath(L, app.source);
    appRegister(L, app);

    luif::SdlHostOptions options;
    options.basePath = app.source.c_str();
    options.defaultFontData = luif_default_font;
    options.defaultFontSize = luif_default_font_size;
    options.inspect = inspect;
    luif::SdlHost ui(L, app.window, app.renderer, options);
    app.ui = &ui;

    std::string main = app.source + "/main.lua";
    if (luaL_loadfile(L, main.c_str()) != 0) {
        fprintf(stderr, "%s\n", lua_tostring(L, -1));
        return 1;
    }
    if (!appCall(L, 0, 0))
        return 1;

    // Shown only now, sized and titled by main.lua, without an empty flash
    if (app.running)
        SDL_ShowWindow(app.window);

    // Frames are paced by vsync, or by sleeping when the renderer has none.
    // Headless and fixed frame time runs are not paced at all: SDL would
    // simulate vsync with a sleep, and they should finish fast.
    const char *driver = SDL_GetCurrentVideoDriver();
    bool headless = driver && SDL_strcmp(driver, "dummy") == 0;
    bool paced = false, vsync = false;

    Uint64 last = SDL_GetTicksNS();
    while (app.running) {
        Uint64 now = SDL_GetTicksNS();
        double dt = app.frameTime > 0 ? app.frameTime : (now - last) / double(SDL_NS_PER_SECOND);
        last = now;

        SDL_Event event;
        while (SDL_PollEvent(&event))
            if (!ui.handleEvent(event))
                handleEvent(app, event);

        if (!appUpdate(L, app, dt))
            return 1;
        if (!ui.update(dt)) {
            fprintf(stderr, "%s\n", ui.error());
            return 1;
        }

        if (paced != (!headless && app.frameTime == 0)) {
            paced = !paced;
            vsync = SDL_SetRenderVSync(app.renderer, paced ? 1 : SDL_RENDERER_VSYNC_DISABLED) && paced;
        }

        appDraw(app);
        appSaveScreenshot(app);
        SDL_RenderPresent(app.renderer);

        if (paced && !vsync) {
            Uint64 spent = SDL_GetTicksNS() - now;
            if (spent < FRAME_NS)
                SDL_DelayPrecise(FRAME_NS - spent);
        }
    }
    return app.exitCode;
}

} // namespace

int main(int argc, char **argv)
{
    int first = 1;
    bool inspect = first < argc && SDL_strcmp(argv[first], "--inspect") == 0;
    if (inspect)
        first++;
    if (first >= argc) {
        fprintf(stderr, "usage: luif-sdl [--inspect] <directory> [args...]\n");
        return 2;
    }

    std::filesystem::path directory = sourceDirectory(argv[first]);
    App app;
    app.source = directory.string();
    app.args.assign(argv + first + 1, argv + argc);

    if (!SDL_Init(SDL_INIT_VIDEO)) {
        fprintf(stderr, "SDL_Init failed: %s\n", SDL_GetError());
        return 1;
    }

    int code = 1;
    std::string title = directory.filename().string();
    if (SDL_CreateWindowAndRenderer(title.c_str(), 1280, 720, SDL_WINDOW_HIDDEN | SDL_WINDOW_RESIZABLE,
                                    &app.window, &app.renderer)) {
        lua_State *L = luaL_newstate();
        luaL_openlibs(L);
        code = run(L, app, inspect);
        lua_close(L);
    } else {
        fprintf(stderr, "no window: %s\n", SDL_GetError());
    }

    SDL_DestroySurface(app.capture);
    SDL_DestroyRenderer(app.renderer);
    SDL_DestroyWindow(app.window);
    SDL_Quit();
    return code;
}
