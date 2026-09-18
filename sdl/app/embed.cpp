//
// A minimal SDL3 "game" that embeds Luif: it owns the window, the renderer,
// the Lua state and the loop, has a Lua function and a texture of its own,
// and draws its world under the UI.
//
//     luif-embed <directory that holds the luif folder>
//
// It clicks its own button and checks the frame, so that it also serves as a
// test: exit status 0 when the click arrived and both layers are visible.
//
#include <luif/sdl_host.h>

#include <SDL3/SDL.h>
#include <lua.hpp>

#include <cstdio>
#include <string>

extern const unsigned char luif_default_font[];
extern const size_t luif_default_font_size;

static int clicks = 0;
static int gameClicked(lua_State *) { ++clicks; return 0; }

static const char *script = R"(
    local luif = require "luif"
    luif.root:addChild(luif.Button {
        x = 20, y = 20, width = 160, height = 40, text = "Click me",
        click = function() gameClicked() end,
    })
    luif.root:addChild(luif.Image { x = 200, y = 20, width = 40, height = 40, texture = gameIcon })
)";

static void pushClick(SDL_Window *window, bool down, float x, float y)
{
    SDL_Event event = {};
    event.type = down ? SDL_EVENT_MOUSE_BUTTON_DOWN : SDL_EVENT_MOUSE_BUTTON_UP;
    event.button.windowID = SDL_GetWindowID(window);
    event.button.button = SDL_BUTTON_LEFT;
    event.button.down = down;
    event.button.x = x;
    event.button.y = y;
    SDL_PushEvent(&event);
}

static bool pixelIs(SDL_Surface *frame, int x, int y, Uint8 red, Uint8 green, Uint8 blue)
{
    Uint8 r, g, b, a;
    return SDL_ReadSurfacePixel(frame, x, y, &r, &g, &b, &a) && r == red && g == green && b == blue;
}

int main(int argc, char **argv)
{
    SDL_Window *window = nullptr;
    SDL_Renderer *renderer = nullptr;
    if (argc < 2 || !SDL_Init(SDL_INIT_VIDEO)
        || !SDL_CreateWindowAndRenderer("game", 640, 480, 0, &window, &renderer))
        return 2;

    lua_State *L = luaL_newstate();
    luaL_openlibs(L);
    const std::string path = "package.path = '" + std::string(argv[1]) + "/?.lua;"
                           + argv[1] + "/?/init.lua;' .. package.path";
    bool ok = luaL_dostring(L, path.c_str()) == 0;
    lua_register(L, "gameClicked", gameClicked);        // the game's own Lua API

    SDL_Texture *icon = SDL_CreateTexture(renderer, SDL_PIXELFORMAT_ARGB8888,
                                          SDL_TEXTUREACCESS_STATIC, 1, 1);
    const Uint32 green = 0xFF00FF00;
    SDL_UpdateTexture(icon, nullptr, &green, 4);
    {
        luif::SdlHostOptions options;
        options.defaultFontData = luif_default_font;
        options.defaultFontSize = luif_default_font_size;
        luif::SdlHost ui(L, window, renderer, options);     // before the first require "luif"
        lua_pushnumber(L, ui.addTexture(icon));              // a texture of the game, for the UI
        lua_setglobal(L, "gameIcon");

        if (ok && !(ok = luaL_dostring(L, script) == 0))
            fprintf(stderr, "%s\n", lua_tostring(L, -1));
        for (int frame = 0; ok && frame < 3; ++frame) {
            if (frame == 1) {
                pushClick(window, true, 100, 40);
                pushClick(window, false, 100, 40);
            }
            SDL_Event event;
            while (SDL_PollEvent(&event))
                if (!ui.handleEvent(event) && event.type == SDL_EVENT_QUIT)  // not the UI's: the game's
                    ok = false;
            if (ok && !(ok = ui.update(1.0 / 60)))          // timers, effects, layout
                fprintf(stderr, "%s\n", ui.error());

            SDL_SetRenderDrawColor(renderer, 0, 0, 0, 255);
            SDL_RenderClear(renderer);
            SDL_SetRenderDrawColor(renderer, 255, 0, 0, 255);   // the game's world
            const SDL_FRect world = { 0, 0, 400, 300 };
            SDL_RenderFillRect(renderer, &world);
            ui.render();                                        // the UI over it

            if (SDL_Surface *shot = frame == 2 ? SDL_RenderReadPixels(renderer, nullptr) : nullptr) {
                ok = ok && clicks == 1 && pixelIs(shot, 300, 200, 255, 0, 0)
                    && !pixelIs(shot, 30, 40, 255, 0, 0) && pixelIs(shot, 220, 40, 0, 255, 0);
                printf("clicks: %d, world, button and icon visible: %s\n", clicks, ok ? "yes" : "no");
                SDL_DestroySurface(shot);
            }
            SDL_RenderPresent(renderer);
        }
    }   // the host goes first: before the Lua state, the renderer and the window
    lua_close(L);
    SDL_DestroyTexture(icon);
    SDL_DestroyRenderer(renderer);
    SDL_DestroyWindow(window);
    SDL_Quit();
    return ok ? 0 : 1;
}
