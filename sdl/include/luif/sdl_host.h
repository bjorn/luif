//
// Luif on SDL3: a retained host (luif/host/interface.lua) that keeps the scene
// in C++ and draws it with an SDL_Renderer.
//
// The application owns the Lua state, the window and the renderer, and keeps
// its own event loop:
//
//     luif::SdlHost ui(L, window, renderer, options);
//     // ... run the application's Lua code, which does require "luif" ...
//     while (running) {
//         SDL_Event event;
//         while (SDL_PollEvent(&event))
//             if (!ui.handleEvent(event))
//                 game.handleEvent(event);      // input the UI did not take
//         if (!ui.update(dt))
//             report(ui.error());
//         game.draw();                          // the UI draws over the game
//         ui.render();
//         SDL_RenderPresent(renderer);
//     }
//
// Constructing the host puts the host table in package.loaded["luif.sdl"];
// require "luif" finds it there and uses it. The application exposes its own
// Lua API next to it in the usual ways (sdl/app/app_api.cpp is an example).
//
// Rules:
//
//   * package.path has to find luif/init.lua.
//   * Construct the host before the first require "luif", and one host per
//     Lua state.
//   * Destroy it before lua_close, before the renderer and the window, and
//     not from inside a Lua callback that it is running. Host functions that
//     Lua still holds raise an error afterwards.
//   * Call everything from the thread that owns the renderer and the Lua
//     state.
//   * screenSize, input and drawing use the renderer's coordinates: the
//     logical presentation when one is set, otherwise the output size over
//     the render scale. update() and handleEvent() expect the target that
//     the UI is drawn to.
//
#pragma once

#include <cstddef>

struct lua_State;
struct SDL_Window;
struct SDL_Renderer;
struct SDL_Texture;
struct SDL_IOStream;
union SDL_Event;

namespace luif {

struct SdlHostOptions {
    // Relative texture, font and readFile paths resolve against this
    // directory; null means the current directory.
    const char *basePath = nullptr;

    // When set, every file is opened through this instead (a virtual file
    // system, an archive), with the path as Lua gave it. Returns null, with
    // SDL_SetError, when there is no such file. Images are PNG or BMP.
    SDL_IOStream *(*openFile)(const char *path, void *userdata) = nullptr;
    void *userdata = nullptr;

    // The font for specifications without a file: a TTF file, or TTF data in
    // memory that outlives the host. Without either, such fonts fail to load.
    const char *defaultFontFile = nullptr;
    const void *defaultFontData = nullptr;
    size_t defaultFontSize = 0;

    // The Lua module that update() drives: require(module).update(dt)
    const char *module = "luif";

    // The host starts text input on the window while a text field has the
    // focus (with its area, for on-screen keyboards and input methods) and
    // stops it afterwards. Turn this off when the application looks after it.
    bool textInput = true;

    // The inspect capability (host.inspect, host.topLevel) for tests and tools
    bool inspect = false;
};

// The strings of the options are copied; defaultFontData is only referenced.

class SdlHost {
public:
    SdlHost(lua_State *L, SDL_Window *window, SDL_Renderer *renderer,
            const SdlHostOptions &options = {});
    ~SdlHost();
    SdlHost(const SdlHost &) = delete;
    SdlHost &operator=(const SdlHost &) = delete;

    // Feeds an event to the UI. Returns true when the UI handled it, so the
    // application can keep it from the game. Pointer motion and window
    // events are never reported as handled.
    bool handleEvent(const SDL_Event &event);

    // Timers, effects, layout and the flush of node changes. Returns false
    // when Lua raised an error, which error() then describes.
    bool update(double seconds);

    // Draws the retained scene into the current render target. Leaves the
    // renderer's clip rectangle unset and its draw colour and blend mode
    // unspecified.
    void render();

    // Whether the pointer is over an item that takes mouse input, as of the
    // last motion event: the game can leave its world unhovered then.
    bool pointerOverUi() const;

    // A texture of the application for the UI to show: returns the handle
    // that Lua uses as a texture (luif.Image { texture = handle }). The
    // application keeps ownership. replaceTexture points the handle at
    // another texture, or at none (null) before the texture is destroyed.
    double addTexture(SDL_Texture *texture);
    void replaceTexture(double handle, SDL_Texture *texture);

    const char *error() const;

    struct Impl;

private:
    Impl *d;
};

} // namespace luif
