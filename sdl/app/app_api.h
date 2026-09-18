//
// The Lua API of the luif-sdl application, next to Luif's own: an example of
// how an SDL3 application that embeds Luif exposes more of itself to Lua.
//
// The pattern:
//
//   * What Lua can reach lives in one struct (App). The main loop owns it
//     and acts on it; the Lua functions only read and write it.
//   * Every function is a lua_CFunction in one luaL_Reg table, with the App
//     as its upvalue, so there are no globals on either side.
//   * The module is registered in package.preload, so scripts get it with
//     require "app" like any other module, and only when they ask for it.
//
// From Lua:
//
//   local app = require "app"
//   app.source                      the directory that is running
//   app.args                        the arguments after the directory
//   app.quit(code)                  leaves the main loop; code defaults to 0
//   app.setTitle(text)
//   app.setWindowSize(width, height)
//   app.windowSize()                width, height in pixels
//   app.setBackgroundColor(color)   packed 0xAARRGGBB, like Luif's colours
//   app.screenshot(path)            saves the next frame as a PNG
//   app.capture()                   draws a frame now and keeps its pixels
//   app.pixel(x, y)                 the packed colour of a captured pixel
//   app.setFrameTime(seconds)       a fixed dt for every update, to record
//                                   frames; nil returns to real time
//   app.update = function(dt) end   optional, called before the UI updates
//
#pragma once

#include <SDL3/SDL.h>

#include <string>
#include <vector>

struct lua_State;
namespace luif { class SdlHost; }

struct App {
    luif::SdlHost *ui = nullptr;
    SDL_Window *window = nullptr;
    SDL_Renderer *renderer = nullptr;
    std::string source;
    std::vector<std::string> args;

    bool running = true;
    int exitCode = 0;
    Uint32 background = 0xFF000000;
    double frameTime = 0;           // seconds; 0 for real time
    std::string screenshot;         // where the next frame goes, when set
    SDL_Surface *capture = nullptr; // the frame app.capture drew, for app.pixel
};

// Clears to the background colour and draws the UI
void appDraw(App &app);

// Makes require "app" work. The App must outlive the Lua state.
void appRegister(lua_State *L, App &app);

// Calls app.update(dt) when the script set one. Returns false when it raised
// an error (see appCall).
bool appUpdate(lua_State *L, App &app, double dt);

// Saves the frame that was just rendered when a screenshot is pending. Goes
// between the last drawing and SDL_RenderPresent.
void appSaveScreenshot(App &app);

// lua_pcall that prints the error with a traceback to stderr and returns false
bool appCall(lua_State *L, int arguments, int results);
