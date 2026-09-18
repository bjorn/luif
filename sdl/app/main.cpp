//
// luif-sdl runs a directory with a main.lua, like love does:
//
//     luif-sdl [--inspect] [--watch] <directory> [args...]
//
// F5 runs main.lua again with all Lua modules and images loaded afresh, and
// --watch does so whenever a file in the directory changes. With --watch a
// script error is shown in the window instead of ending the run.
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
#include <functional>
#include <string>
#include <vector>

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

// --watch: a signature of the watched files (Lua, images, fonts), polled a
// few times per second. A change reloads once the files have been quiet for
// a moment, so that a save in several steps or of several files counts once.
struct Watcher {
    static constexpr Uint64 POLL_NS = SDL_NS_PER_SECOND / 4;
    static constexpr Uint64 QUIET_NS = SDL_NS_PER_SECOND * 3 / 10;

    Uint64 loaded = 0, seen = 0;    // signatures: what runs, and the last look
    Uint64 polledAt = 0, changedAt = 0;

    static Uint64 signature(const std::vector<std::string> &directories)
    {
        namespace fs = std::filesystem;
        Uint64 result = 0;
        std::error_code error;
        for (const std::string &directory : directories) {
            fs::recursive_directory_iterator files(directory, fs::directory_options::skip_permission_denied, error);
            for (; !error && files != fs::recursive_directory_iterator(); files.increment(error)) {
                const std::string extension = files->path().extension().string();
                if (extension != ".lua" && extension != ".png" && extension != ".bmp"
                    && extension != ".ttf" && extension != ".otf")
                    continue;
                const auto time = files->last_write_time(error).time_since_epoch().count();
                // Order independent, and sensitive to names, times and sizes
                result += std::hash<std::string>()(files->path().string()) * 31 + Uint64(time)
                        + Uint64(files->file_size(error));
            }
        }
        return result;
    }

    // True when what is on disk differs from what runs and has settled
    bool changed(const App &app, Uint64 now)
    {
        if (now - polledAt < POLL_NS)
            return false;
        polledAt = now;
        const Uint64 current = signature(app.watched);
        if (current != seen) {
            seen = current;
            changedAt = now;
        }
        return seen != loaded && now - changedAt >= QUIET_NS;
    }
};

// What --watch shows instead of exiting when a script fails: the message, on
// a fresh UI, until a change or F5 reloads
const char *errorScreen = R"(
    local luif = require "luif"
    luif.root:addChild(luif.Rectangle { left = 0, right = 0, top = 0, bottom = 0, color = 0xFF30181C })
    luif.root:addChild(luif.Label { left = 24, right = 24, top = 24, color = 0xFFFFD0D0,
                                    text = (...):gsub("\t", "    ") })
)";

// Runs main.lua on a fresh UI. False when it failed; message has the error.
bool load(lua_State *L, App &app, std::string &message)
{
    appReset(L, app);
    app.ui->reload();
    std::string main = app.source + "/main.lua";
    if (luaL_loadfile(L, main.c_str()) != 0) {
        message = lua_tostring(L, -1);
        lua_pop(L, 1);
        fprintf(stderr, "%s\n", message.c_str());
        return false;
    }
    return appCall(L, 0, 0, &message);
}

// The host lives in here, so that it is gone before the Lua state closes
int run(lua_State *L, App &app, bool inspect, bool watch)
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
    app.watched.push_back(app.source);

    Watcher watcher;
    app.reload = true;          // the first load is a reload of nothing

    // Without --watch a script error ends the run. With it the message is
    // shown, on a fresh UI, until the next change or F5.
    std::string message;
    auto recover = [&]() {
        if (!watch)
            return false;
        appReset(L, app);
        ui.reload();
        if (luaL_loadstring(L, errorScreen) != 0)
            return false;
        lua_pushstring(L, message.c_str());
        return appCall(L, 1, 0);
    };

    // Frames are paced by vsync, or by sleeping when the renderer has none.
    // Headless and fixed frame time runs are not paced at all: SDL would
    // simulate vsync with a sleep, and they should finish fast.
    const char *driver = SDL_GetCurrentVideoDriver();
    bool headless = driver && SDL_strcmp(driver, "dummy") == 0;
    bool paced = false, vsync = false, shown = false;

    Uint64 last = SDL_GetTicksNS();
    while (app.running) {
        Uint64 now = SDL_GetTicksNS();
        double dt = app.frameTime > 0 ? app.frameTime : (now - last) / double(SDL_NS_PER_SECOND);
        last = now;

        if (app.reload || (watch && watcher.changed(app, now))) {
            if (shown)
                printf("reloading %s\n", app.source.c_str());
            bool loaded = load(L, app, message);
            // What runs now, including the directories main.lua asked to watch
            watcher.loaded = watcher.seen = Watcher::signature(app.watched);
            if (!loaded && !recover())
                return 1;
        }

        SDL_Event event;
        while (SDL_PollEvent(&event)) {
            // F5 reloads, whatever has the focus
            if (event.type == SDL_EVENT_KEY_DOWN && event.key.key == SDLK_F5 && !event.key.repeat)
                app.reload = true;
            else if (!ui.handleEvent(event))
                handleEvent(app, event);
        }

        bool ok = appUpdate(L, app, dt, &message);
        if (ok && !(ok = ui.update(dt))) {
            message = ui.error();
            fprintf(stderr, "%s\n", ui.error());
        }
        if (!ok && !(recover() && ui.update(0)))
            return 1;

        // Shown only now, sized and titled by main.lua, without an empty flash
        if (app.running && !shown) {
            SDL_ShowWindow(app.window);
            shown = true;
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
    bool inspect = false, watch = false;
    for (; first < argc && argv[first][0] == '-'; first++) {
        inspect = inspect || SDL_strcmp(argv[first], "--inspect") == 0;
        watch = watch || SDL_strcmp(argv[first], "--watch") == 0;
    }
    if (first >= argc) {
        fprintf(stderr, "usage: luif-sdl [--inspect] [--watch] <directory> [args...]\n");
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
        code = run(L, app, inspect, watch);
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
