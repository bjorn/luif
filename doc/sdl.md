# Luif on SDL3

`sdl/` holds a host for SDL3 written in C++17: a static library (`luif::sdl`)
that implements the retained host interface (`luif/host/interface.lua`, see
`doc/architecture.md`), and `luif-sdl`, an application that runs a directory
with a `main.lua` the way `love` does. The host keeps the scene in C++ and
draws it with an `SDL_Renderer`, so a frame in which nothing changed runs no
Lua at all apart from timers.

| path | contents |
|---|---|
| `sdl/include/luif/sdl_host.h` | the public API: `luif::SdlHost` and its options |
| `sdl/src/` | the library; `internal.h` describes how it is divided |
| `sdl/app/` | `luif-sdl`, with its own Lua module as an example of an application API, and `luif-embed`, a minimal embedding example |
| `sdl/CMakeLists.txt` | the build |

## Building and running

Needed: CMake 3.20, a C++17 compiler, SDL3 3.4 or later (it loads PNG files
itself), SDL3_ttf, and LuaJIT or Lua 5.1 to 5.4.

```sh
cmake -S sdl -B build -G Ninja
cmake --build build
build/luif-sdl example
```

`-DLUIF_LUA=luajit` or `-DLUIF_LUA=lua` picks the Lua to build against; the
default prefers LuaJIT when pkg-config finds it. CMake prints which one it
uses.

`luif-sdl [--inspect] [--watch] <directory> [arguments]` puts the directory on
`package.path`, makes it the base of relative texture, font and file paths,
and runs its `main.lua`. `example/` runs unchanged under LOVE and `luif-sdl`;
`example/platform.lua` hides the differences between the two. The default
font is Bitstream Vera Sans, embedded in the application, which is also
LOVE's default, so both render alike.

F5 reloads: `main.lua` runs again with every Lua module and image loaded
afresh, in the same Lua state, so globals are a place to keep what should
survive. `--watch` does the same whenever a Lua, image or font file in the
directory changes (polled four times per second, once the files have been
quiet for 0.3 seconds; `app.watch(directory)` adds directories, which the
example uses for `luif/` itself). With `--watch` a script error is shown in
the window until the next change, instead of ending the run.

Headless runs need no display: with `SDL_VIDEODRIVER=dummy` and
`SDL_RENDER_DRIVER=software` the application renders into memory and does
not pace its frames.

```sh
export SDL_VIDEODRIVER=dummy SDL_RENDER_DRIVER=software
build/luif-sdl --inspect tests              # the whole test suite on this host
build/luif-sdl --inspect --watch tests/reload "$(mktemp -d)"   # live reload
LUIF_SELFTEST=1 build/luif-sdl example      # the example's self-test
LUIF_SCENE=demo LUIF_SCREENSHOT=demo build/luif-sdl example
```

`--inspect` turns on the `inspect` capability, which the tests use to read
nodes back. `tests/test_host_sdl.lua` runs the interface conformance tests
and checks drawing by reading pixels of rendered frames.

## The application's Lua API

An application that embeds Luif usually has more to offer its scripts than
the UI. `sdl/app/app_api.cpp` shows the pattern with the module that
`luif-sdl` itself provides: state in one struct that the main loop owns,
plain `lua_CFunction`s in one `luaL_Reg` table with that struct as their
upvalue, registered in `package.preload` so scripts get it with `require`.

```lua
local app = require "app"
app.source                      -- the directory that is running
app.args                        -- the arguments after the directory
app.quit(code)
app.setTitle(text)
app.setWindowSize(width, height)
app.windowSize()
app.setBackgroundColor(0xFF292B35)
app.screenshot(path)            -- saves the next frame as a PNG
app.capture()                   -- draws a frame now, for app.pixel
app.pixel(x, y)                 -- the packed colour of a captured pixel
app.setFrameTime(seconds)       -- a fixed dt, to record frames
app.reload()                    -- runs main.lua again after this frame, like F5
app.watch(directory)            -- with --watch: changes there reload too
app.update = function(dt) end   -- called before the UI updates
```

Input that the UI does not handle goes to the application: F11 toggles
fullscreen in `luif-sdl`.

## Embedding

The application owns the window, the renderer, the Lua state and the loop.
`sdl/app/embed.cpp` is a complete program of about 110 lines that checks
itself (`build/luif-embed .`); its core:

```cpp
luif::SdlHostOptions options;
options.defaultFontFile = "fonts/regular.ttf";
luif::SdlHost ui(L, window, renderer, options);    // before the first require "luif"

// ... run the game's Lua, which builds its UI with require "luif" ...

while (running) {
    SDL_Event event;
    while (SDL_PollEvent(&event))
        if (!ui.handleEvent(event))                 // true: the UI took it
            game.handleEvent(event);
    if (!ui.update(dt))                             // timers, effects, layout
        report(ui.error());
    game.draw();
    ui.render();                                    // the UI over the game
    SDL_RenderPresent(renderer);
}
```

In CMake, `add_subdirectory(luif/sdl)` (or `FetchContent` with
`SOURCE_SUBDIR sdl`) and link `luif::sdl`. An application that already has a
Lua target defines an interface target `luif_lua` that links it before adding
the directory, so both use the same Lua. SDL3 and SDL3_ttf targets that
already exist (a vendored SDL) are used as they are.

Rules:

* `package.path` has to find `luif/init.lua`; ship the `luif` folder with the
  game. `options.module` names it when it is required under another name
  (`lib.luif`).
* Construct the host before the first `require "luif"`: that is when Luif
  looks for the host table in `package.loaded["luif.sdl"]`. One host per Lua
  state.
* Destroy the host before `lua_close` and before the renderer and the
  window, and not from inside a Lua callback it is running. Host functions
  that Lua still holds raise an error once the host is gone.
* All calls come from the thread that owns the renderer and the Lua state.
* A Lua error during `handleEvent` is reported by the next `update()`, which
  returns false once with the traceback in `error()`.

Options and calls beyond the basics:

* **Files.** Relative texture, font and `readFile` paths resolve against
  `basePath`. With `openFile` set, the host opens every file through that
  callback instead (a virtual file system, an archive), with the path as
  given. PNG and BMP images load.
* **Textures of the application** (item icons, a minimap): `addTexture`
  returns a handle for Lua, used as `luif.Image { texture = handle }`. The
  application keeps ownership; `replaceTexture` points the handle at another
  texture, or at none before the texture is destroyed.
* **Text input.** The host starts SDL text input on the window while a text
  field has the focus, with the field's area for on-screen keyboards and
  input methods, and stops it afterwards, so game keys never go through an
  input method. `textInput = false` leaves text input to the application.
* **Live reload.** `reload()` forgets the scene, the textures and fonts (so
  images are read again) and every Lua module loaded since the host was
  constructed; the application then runs its UI scripts again, in the same
  Lua state. Modules the game loaded before constructing the host stay, and
  so do globals. Handles of `addTexture` have to be added again. When to
  reload (a key, a file watcher) is the application's choice;
  `sdl/app/main.cpp` does both.
* **The pointer.** `pointerOverUi()` tells whether the pointer is over an
  item that takes mouse input, to suppress hover effects in the world.
* **Sizes.** `screenSize`, input and drawing share the renderer's coordinates:
  the logical presentation size when one is set, otherwise the output size
  divided by the render scale. On a high density window, set the UI scale
  from the display: `luif.Screen:setScale(scale)`.
* **Renderer state.** `render()` draws into the current target, leaves the
  clip rectangle unset and the draw colour and blend mode unspecified. The
  first grayscale use of a texture switches the render target for a moment
  and restores it. `setCursor` sets the SDL cursor.

## How it keeps memory low

* A node is one 88 byte struct in a pooled vector, linked to its parent and
  siblings by index. There is no allocation and no Lua object per node: a
  handle is a number holding the index and a generation that catches stale
  handles.
* Image, slices and fill content live inside the node. Text content has its
  own pool, holding the string, the colour runs and the laid out glyphs (16
  bytes each), which are reused while the box width stays the same and keep
  their buffers when a label's text changes.
* Glyphs of a face (file and size) are shared by every font that differs
  only in shadow or outline, rasterized on first draw into atlas pages that
  all faces share. Measuring alone rasterizes nothing.
* Texture regions share the texture they were cut from. A grayscale copy is
  made on first use only. Pixel data is not kept after upload.
* Drawing walks the tree once, computes world transforms on the way and
  batches quads per texture into one reused vertex buffer. A frame without
  text changes allocates nothing.

A UI of 500 nodes and 100 labels takes about 150 KB of host memory, plus the
atlas (256 KB for the first page) and the textures themselves.

## Differences from the LOVE host and known gaps

* Clips use the axis aligned bounds of a rotated box (no `rotatedClip`
  capability); slices and text do rotate.
* Text is laid out one glyph per code point with kerning from the font's
  kern table: no ligatures, combining marks or right to left text. Lines
  break at spaces; a word wider than the box breaks per character.
* Glyphs are rasterized at the font's size, so a scaled UI scales their
  pixels, as on LOVE.
* Textures, regions and fonts live as long as the host. Core creates each
  once; an application should not create regions every frame.
* A renderer device reset (`SDL_EVENT_RENDER_DEVICE_RESET`) loses the
  textures and the glyph atlas; the host does not rebuild them.
* Text input has the area of the focused field but not the caret position
  within it.
* No per-node blend modes or masks, as on LOVE.
