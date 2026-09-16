# Host contract

The framework talks to its platform through the retained host interface. A
host keeps a scene of nodes and renders it itself; the framework only changes
that scene when something changed.

Input and drawing go through the host interface. The host's input feed
drives core's pointer (`luif/core/pointer.lua`), which picks on the core item
tree, and `luif/core/sync.lua` gives every attached item one node in the host's
scene and flushes changes once per frame (see "Items and nodes" below).

Files:

| file | role |
|---|---|
| `luif/host/interface.lua` | the interface as data (groups, functions, feed, capabilities), `Interface.check(host)`, `Interface.capabilities(host)`, content normalizers, `Interface.sliceRects` |
| `luif/host/tree.lua` | structure bookkeeping shared by the Lua hosts |
| `luif/host/recording.lua` | recording host in plain Lua: full node state, a log of every call, test helpers |
| `luif/love/host.lua` | LOVE host: `require("luif.love.host").new()`, `host.render()` from `love.draw`, `host.loveHandlers` |
| `luif/love/transform.lua`, `texture.lua`, `font.lua` | transform and clip helpers, texture and font handles of the LOVE host |
| `luif/init.lua`, `luif/love/init.lua` | the `luif` entry module and the LOVE callbacks |
| `luif/core/host.lua` | the application's host, where core gets its platform services |
| `luif/core/sync.lua` | one host node per attached item; the only core module that touches nodes; flushes changes once per frame |
| `luif/core/textlayout.lua` | label text: colour runs, abbreviation, obfuscation, measuring through a host |
| `tests/host_conformance.lua` | interface tests run against both hosts |

`luif/host/` and `luif/core/` are platform neutral: they never use `love`, `io` or
`os` (`tools/check-globals.sh` checks this) and load under plain LuaJIT.
Platform specific hosts live with their platform code, like
`luif/love/host.lua`.
`luif/love/` requires core; core never requires `luif/love/`.

## Conventions

* A host is a table of plain functions: `host.createNode()`.
* Nodes, textures and fonts are opaque handles with stable identity.
* Positions and sizes are in the parent node's units. Top level nodes, input
  positions and `screenSize()` are in window pixels; a UI scale is a scale on
  a root node (`luif/core/sync.lua` puts `Update.uiScale` there).
* Origin top left, y down, rotations in radians, clockwise on screen.
* Colours are packed `0xAARRGGBB` numbers; negative int32 values mean the
  same bits; the alpha byte is honoured.
* Opacity is 0..1 and multiplies down the tree. A node with effective opacity
  0, or an invisible node, draws neither its content nor its subtree.
* Local transform: `T(x, y) * T(originX, originY) * R(rotation) * S(scale) *
  T(-originX, -originY)`; world transform: `parentWorld * local`.
* A node's box is `(0, 0, width, height)`. Content fills the box; a clipping
  node clips its content and subtree to the transformed box, nested clips
  intersect.
* One content per node: image, slices, text or fill. Any `set*` content call
  replaces the previous content of any kind; content survives transform, size
  and structure changes.
* Draw order: a node's content, then its children in child order (last on
  top). Top level nodes draw in their order.
* Frame protocol: the host feeds input to the sink, calls the framework's
  update (timers, effects, layout, then one flush of node changes), then
  renders. The host never picks.

## Functions

Required unless marked optional; optional functions belong to a capability.

| group | function | notes |
|---|---|---|
| structure | `createNode() -> node` | detached, identity transform, size 0, opacity 1, visible, no clip, no content |
| | `destroyNode(node)` | detaches and releases the whole subtree; destroyed nodes raise when used |
| | `attach(node, parent, nextSibling)` | `parent` nil is the top level; `nextSibling` nil appends; an attached node is moved; cycles raise |
| | `detach(node)` | keeps subtree, properties and content; no-op when detached |
| properties | `setTransform(node, x, y, rotation, scale, originX, originY)` | rotation 0, scale 1, origin 0 by default |
| | `setSize(node, width, height)` | |
| | `setOpacity(node, opacity)` | 0..1 |
| | `setVisible(node, visible)` | |
| | `setClip(node, clip)` | |
| content | `setImage(node, texture, tint, flipX, flipY, grayscale)` | stretched over the box; flips mirror within it |
| | `setSlices(node, texture, left, top, right, bottom, tint, grayscale)` | one nine-slice of one texture; insets in texture pixels; a box smaller than the insets shrinks the corners (`Interface.sliceRects`) |
| | `setText(node, font, text, color, align, wrap)` | `text` is a string or runs `{ color, string, ... }` (then only `color`'s alpha applies); `align` left, center, right within the width; `wrap` wraps at the width like `wrapText`, otherwise lines break at `\n` and the block is aligned |
| | `setFill(node, color, borderColor, borderWidth)` | `color` nil means no fill; border inside the box, width 1 by default |
| | `clearContent(node)` | |
| resources | `loadTexture(path) -> texture or nil, message` | cached per path |
| | `createTexture(width, height, pixel) -> texture` | `pixel(x, y) -> r, g, b, a` in 0..255; white without `pixel` |
| | `textureRegion(texture, x, y, w, h) -> texture` | regions of regions work |
| | `textureSize(texture) -> w, h` | |
| | `loadFont(spec) -> font` | `{ file, size, shadow = { dx, dy, color }, outline = { color }, name }`; equal specs give the same handle |
| | `textWidth(font, text)`, `lineHeight(font)` | single line width; line advance |
| | `wrapText(font, text, width) -> widest, lines` | |
| | `setTextureFilter(min, mag)` | optional, `textureFilter` |
| system | `time() -> ms`, `screenSize() -> w, h` | |
| | `getClipboard()`, `setClipboard(text)` | |
| | `setCursor(name)` | `arrow hand ibeam sizeall sizenwse sizenesw sizewe sizens wait waitarrow no crosshair`; unknown or nil is `arrow` |
| | `readFile(path) -> contents or nil, message` | |
| | `capabilities() -> table` | capability name to true |
| | `beginBatch()`, `endBatch()` | optional, `batch`; brackets around one flush, not nested |
| | `pointerPosition() -> x, y` | optional, `pointerPosition` |
| | `isKeyDown(key)` | optional, `keyState` |
| | `inspect(node) -> snapshot`, `topLevel() -> nodes` | optional, `inspect`; for tests and tools |
| input | `setInputSink(sink)` | the table the host feeds |

Input feed (functions on the sink, called by the host; missing ones are
skipped): `pointerMoved(x, y)`, `pointerPressed(x, y, button)`,
`pointerReleased(x, y, button)`, `wheel(dx, dy)`, `keyPressed(key,
isRepeat)`, `keyReleased(key)`, `textInput(text)`, `pointerLeft()`. Buttons
are 1 left, 2 right, 3 middle. Keys are LOVE KeyConstant names. Every
delivered press gets a release, synthesized when lost. `textInput` carries
printable text only.

Capabilities: `rotatedClip` (otherwise clips use the transformed box's
bounds), `rotatedSlices`, `rotatedText`, `grayscale`, and the optional
function groups `batch`, `textureFilter`, `pointerPosition`, `keyState`,
`inspect`. `Interface.check(host)` reports missing required functions,
claimed capabilities without their functions and unknown capability names.

## The hosts

LOVE host (`luif/love/host.lua`): node records with `x, y, rotation, scale, ox,
oy, width, height, opacity, visible, clip, content`. Images are one
`love.graphics.draw`, slices are nine quads of one image, text is `print` or
`printf` with the font's shadow and outline passes and colour runs as LOVE
coloured text, fills are up to five rectangles. Clips use the scissor when
axis aligned and a stencil otherwise. Textures and fonts are the
`luif/love/texture.lua` and `luif/love/font.lua` handles; clock, cursor and
clipboard use `love.timer`, `love.mouse` and `love.system`. Reports every
capability except `batch`. `host.loveHandlers` translates the love input
callbacks into feed calls and returns what the sink returns, and
`host.releaseLostButtons()` synthesizes lost releases.

Recording host (`luif/host/recording.lua`): `Recording.new(options)`. Stores the
same node state, logs every interface call except `inspect` and `topLevel`,
and reports every capability unless `options.capabilities` turns some off.
Resources are stubs: texture sizes come from `options.textureSizes` (by path
or base name) or `defaultTextureSize`, `strictTextures` makes unknown paths
fail, text is `glyphWidth` per codepoint and `lineHeight` high, wrapping is
greedy at spaces. Helpers: `log()`, `resetLog()`, `count(filter)`,
`logLines(filter)` (filter is a function or group name), `dump(node)`,
`feed(name, ...)`, `setTime(ms)`, `advance(ms)`, `setScreenSize(w, h)`,
`cursor()`.

With `pngSizes`, texture sizes come from the header of a PNG file that
`readFile` returns, so tests can use real images without LOVE.

Tests: `tests/test_host_love.lua` and `tests/test_host_recording.lua` run the
conformance tests; the LOVE file also captures drawing calls. The whole suite
runs without LOVE too: `luajit tests/run_luajit.lua` makes a recording host
core's host and reports LOVE only tests as skips.

# The framework on the host

The framework in `luif/core/` draws through the host interface and takes every
platform service from the application's host.

## The `luif` module and the LOVE callbacks

`require "luif"` (`luif/init.lua`) returns a table with every class and
module of `luif/core/` by name, loaded on first use (`luif.Button`,
`luif.Update`, `luif.skins.DefaultButtonSkin`), and:

| name | meaning |
|---|---|
| `luif.root` | an item covering the virtual screen with an `AnchorLayout`: a root created on first use and resized on `uiScaleChanged` |
| `luif.setHost(host)` | core's host and the pointer's input source |
| `luif.update(dt)` | `Update.onUpdate(host.time(), dt * 1000)`, then `Pointer.afterUpdate()` |

Under LOVE, `luif/init.lua` makes the LOVE host core's host and adds the
functions of `luif/love/init.lua`:

| name | meaning |
|---|---|
| `luif.update(dt)` | lost releases (`host.releaseLostButtons()`), then the update above |
| `luif.draw()` | `host.render()` |
| `luif.mousemoved`, `mousepressed`, `mousereleased`, `wheelmoved`, `keypressed`, `keyreleased`, `textinput`, `mousefocus` | the love callbacks with LOVE's arguments, returning true when the UI handled the input |
| `luif.hook()` | installs them all as the love callbacks and chains those already set: the game updates first, the UI draws over the game, and input the UI handled does not reach the game (moves and focus changes always do) |

The first callback makes the LOVE host the pointer's input source and
enables key repeat. Input counts as handled, as the sink of
`luif/core/pointer.lua` reports it, for a press on an item that takes mouse
input, the release of a press an item took, the wheel over such an item, and
keys and text the focused item accepted.

```lua
local luif = require "luif"
luif.root:addChild(luif.Button { text = "OK", horizontalCenter = 0, verticalCenter = 0 })
luif.hook()
```

A folder elsewhere, such as `lib/luif`, is required as `require "lib.luif"`,
which makes the `luif.*` modules requirable through that prefix. Debugging is
the application's choice: the example calls `luif.Debug.setEnabled(true)`
when `LUIF_DEBUG` is set.

Ground rules:

1. `luif/core/` requires nothing from `luif/love/`, calls no `love.*`, `io.*` or
   `os.*`, assigns no globals and reads no globals but the Lua standard
   library; `luif/core/bit.lua` alone reads the `bit` library when present
   (`tools/check-globals.sh` checks the LuaJIT bytecode for this).
2. Platform services come from `luif/core/host.lua`: `Host.set(host)` once, then
   core calls `Host.get()` for `time`, `screenSize`, `getClipboard`,
   `setClipboard`, `setCursor`, `loadTexture`, `createTexture`,
   `textureSize`, `setTextureFilter`, `loadFont` and `readFile`. Nodes go to `Sync.host(item)` (the application host unless
   `Sync.setHost` overrides it for new roots), and labels measure with that
   host. `luif/core/pointer.lua` is attached to the host that feeds input.
3. What were globals are modules: `luif/core/debug.lua` (`dbg`, `dbgprint`,
   `dbgtrace`; off unless the application enables it), `luif/core/bit.lua` (the `bit`
   library or a pure Lua fallback with the same signed 32 bit results),
   `luif/core/keys.lua` (key name helpers) and `luif/core/mousebutton.lua`
   (`Left = 1, Right = 2, Middle = 3`).
4. Loading: core files start with `local core = require "luif.core"`
   (`luif/core/init.lua`, a namespace made by `luif/module.lua`) and take
   classes and modules from it: `core.Item` loads `luif/core/item.lua` on
   first use. Without a usable `require`, `module.loader { readFile =
   host.readFile }` loads core by reading files (a package from its
   `init.lua`) and compiling them with
   `load`; the files get an environment whose `require` is the loader's, and
   `options.globals` can restrict what else they see
   (`tests/test_loader.lua` loads all of core that way with the standard
   library only).
5. Handles (nodes, textures, fonts) are plain Lua tables with stable
   identity. The framework uses them as table keys and compares them with `==`.
6. Units: items are laid out in virtual units, the window size divided by
   `Update.uiScale` (`Update.virtualScreenWidth/Height`). The scale is
   applied in one place per direction: `luif/core/sync.lua` composes it into the
   transform of every root node (a root's own `x, y` and `scale` stay
   virtual; child nodes never carry it), and `luif/core/pointer.lua` divides the
   window pixels of the input feed by it before picking. So event positions
   and deltas, `absolutePos` and `core.Pointer.position()` are virtual;
   `Pointer.toWindow` and `Pointer.toVirtual` convert. Only the host's
   `screenSize` and `pointerPosition` and the double click radius are in
   window pixels. `Update:setUiScale(s)` sets a fixed scale,
   `Update:setAdaptUiScale(true)` the adaptive one, which fits
   `Update.adaptiveWidth` by `adaptiveHeight` (1920 by 1080) into the
   window; only `luif/core/update.lua`,
   `luif/core/sync.lua` and `luif/core/pointer.lua` read `Update.uiScale`
   (`tools/check-globals.sh`), and `luif/core/update.lua` hands it to
   `luif/core/sync.lua` with `Sync.setScaleSource`.
7. Origin is top left, y grows downwards, rotations are in radians (items
   keep degrees and `luif/core/sync.lua` converts), clockwise on screen.
8. Text: `luif/core/text.lua` substitutes `{1}`, `{1:U}`, `{1:p}`, `{1:d.2}`,
   `{p one other}` and `{color:...}`; applications add their own rules to
   `Text.substitutionRules` and `Text.grammarRules`.

## Items and nodes (`luif/core/sync.lua`)

There is one item class, `core.Item` (`luif/core/item.lua`). Controls, the
classes with content (`Image`, `Label`, `Rectangle`, `Scale9`, `ScaleH3`,
`ScaleV3`, `SlicedImage`, `Line`) and layout items all derive from it, and
any item can have children, content and input.

Lifetime: `Sync.addRoot(item)` (`core.Sync`) registers a parentless item as
a root and attaches its tree; `Sync.removeRoot(item)` unregisters it and
detaches the tree. Applications register their top level items this way, as
`luif/core/toplayer.lua` and tooltips do; dialogs usually live in the
`TopLayer`. An item is attached (`isAttached()`) while it is a root or its
parent is attached, so `addChild`, `insertChild`, `removeChild`,
`setChildren`, `setParent` and `delete` attach and detach whole subtrees.
Subclasses act on that in `attached()` and `detached()`, which run once the
whole subtree joined or left, children first. Giving a root a parent
unregisters it (it stays attached when the parent is); `setParent(false)`
detaches, and `Sync.addRoot` makes the item a root again.

Every attached item gets one node in the host of its root: the host set with
`Sync.setHost(host)` when the root was registered, the application host of
`luif/core/host.lua` by default, so a test can render a whole tree into a
recording host. Items
describe their node with `describeNode(p)` (transform, size, opacity,
visibility, clip) and set its content with `pushContent(host, node)`, which
calls a host content function directly. Setters only
mark the item dirty (`Sync.propertiesChanged(item)`,
`Sync.contentChanged(item)`, and `Sync.childrenChanged(item)` for structure);
`Sync.flush()`, which `Update.onUpdate` calls once per frame after layout,
creates and attaches nodes for items that joined a root, moves nodes whose
place changed, pushes the properties that differ from what a node has and
the content of items marked with `contentChanged`, and destroys the nodes of items that left, last, so an item
moved out of a leaving subtree keeps its node. The flush is bracketed with
`beginBatch` and `endBatch` on hosts with the `batch` capability, and a frame
without changes makes no host calls. Label measuring stays eager (layouts
read implicit sizes when setters run); it goes through `Sync.host(item)`.
Nothing but `luif/core/sync.lua` holds node handles or calls node functions,
apart from the content functions in `pushContent` (`tools/check-globals.sh`
checks this); tests read nodes with
`Sync.node(item)` after a flush.

Node properties:

| item | properties |
|---|---|
| every item | `x, y`, `rotation` (degrees to radians), `scale`, `transformOriginX/Y` (fractions of `size()`, the centre by default), `size()`, opacity `alpha / 255`, visible unless hidden, `clip` (clips to the node box, which is the item's size) |
| `Label` | the same, with `textScale` multiplied into the scale and the box in unscaled font units; the position and origin are adjusted so the node covers the item's box |

Content per class:

| class | content |
|---|---|
| `Image` | `image`: texture, tint `color`, `flipX`, `flipY`, `grayscale`, stretched over the box. |
| `Rectangle` | `fill`: `color`, `borderColor` (unless false or 0) and `borderWidth`, the border inside the box. |
| `Label` | `text`: font, the text or colour runs, `color`, `align`, `wrap`. `luif/core/textlayout.lua` parses colour tags, abbreviates and obfuscates, and measures with the host's `textWidth`, `lineHeight` and `wrapText`. With a format rectangle (`wrap` or `abbreviate` and a width) the box width is `(wrappingWidth or width) / textScale`; without one the box is the text's own size, so `align` only aligns lines against each other. The implicit size is the measured size times `textScale`. |
| `Scale9` | `slices` of one texture with its insets: `source` names a `TexDb` image whose insets were registered with `TexDb.setSlices(name, left, top, right, bottom)`, or `texture` and `insets = { left, top, right, bottom }` are given (`setSource`, `setTexture(texture, insets)`). The implicit size is the texture size and the minimum size holds the corners. |
| `ScaleH3`, `ScaleV3` | `slices` of one texture with only its left and right (H3) or top and bottom (V3) insets, from a `source` or a `texture` with `insets`. |
| `SlicedImage` | no content: a child `Image` per texture of the grid, stretched with the grid when the item has an explicit size. |
| `Line` | `image`: the line texture on the body. The item's position, size and rotation follow the points: it starts at the start point, is `thickness` high, and is rotated towards the end around the middle of its start edge (transform origin 0, 0.5); the arrow head and the mirrored arrow tail are two child `Image` items centred on the ends. |

Structure and draw order: draw order is child order. An item's node holds
the nodes of its children in child order, with or without content
(`moveToTop` moves an item to the end). Roots
are top level nodes in registration order, and `moveToTop` on a root moves
it to the top. `Item:absolutePos()` sums `x, y` up the parents, ignoring
rotation and scale. The node tree has the item tree's shape: an item's node
parent is the node of its parent, the item that positions it.

Skins are ordinary children (`luif/core/skinnableitem.lua`). A
`SkinnableItem`'s skin is its first child. When the skin has an item with
id `contentArea` (`item.contentArea`), the item's content children are
children of that item, after the content area's own children; without one
they follow the skin as direct children. `addChild`, `insertChild`,
`removeChild`, `removeChildren`, `setChildren` and `setParent` onto the
item work on the content (indexes count content children), and
`moveToTop` moves an item within its real parent. `item.children` is the
real list; `item:contentChildren()` returns the content as a list and the
index of its first entry. Id lookups (`findChild`, `findChildren`), state
changes and the item's layout use `contentChildren()`, so skin parts stay
out of lookups on the item, and a content child's resize invalidates the
item's layout through the content area. A state set on the item is
applied to its content by the item's transition and to the skin by the
skin's own `setState`, whose walk stops at the content area, so every item
gets it once.

## Texture and font handles

```lua
tex  = { image = <love Image>, quad = <love Quad> or false, width = w, height = h, name = "button" }
font = { font = <love Font>, name = "Text", size = 13, shadow = false | { dx, dy, color }, outline = false | { color } }
```

These are the LOVE host's handles (`luif/love/texture.lua`, `luif/love/font.lua`);
core only passes them back to the host. `luif/core/texdb.lua` loads images with
`loadTexture` and generates its built in textures with `createTexture`,
and items lay out with `textureSize`; `luif/core/fontdb.lua` builds fonts with `loadFont`.

## Events (`luif/core/pointer.lua`, `luif/core/event.lua`)

The host feed is dispatched in core: `luif/core/pointer.lua` is the input sink.
It picks on the core item tree and calls `Item:handleEvent(event)` with an
Event (`luif/core/event.lua`), a plain table with the class's methods. `event.name`
is the handler name: `mouseEnter, mouseLeave, mousePress, mouseRelease,
mouseDoubleClick, mouseMove, mouseWheel, keyPress, keyRelease,
keyCharacter`. Handlers read it through methods:

| method | meaning |
|---|---|
| `x(), y(), pos()` | pointer position in the receiving item's local space (inverse of its world transform); updated while the event bubbles |
| `absolutePos()` | pointer position in virtual units |
| `dx(), dy()` | movement since the previous delivered position (0 unless `mouseMove`) |
| `button()` | `1` left, `2` right, `3` middle (`core.MouseButton.Left`, `Right`, `Middle`) |
| `value()` | wheel steps as the host reports them (notches, fractions on precise devices), positive scrolls up |
| `key()`, `isKey(name, ...)` | the feed's key name: `"a"`, `"space"`, `"return"`, `"kpenter"`, `"escape"`, `"left"`, `"lctrl"`, `"f2"`, `"kp5"`, ... |
| `text()` | `keyCharacter` only: the UTF-8 text of `textInput`, or `"\n"` synthesized for Return and keypad Enter |
| `isAutoRepeat()` | `true` for a repeated `keyPress` |
| `mouseDown(button)`, `modifierDown(name)` | buttons and modifiers (`"ctrl"`, `"shift"`, `"alt"`, `"gui"`) held when the event was made; without an argument, any |
| `controlDown()`, `shiftDown()`, `altDown()` | the modifiers, either side |
| `focusItem()` | the item that had the focus |
| `ignore()`, `accept()` | bubbling: an ignored event goes on to the parent |

The fields behind them are `localX, localY, absX, absY, deltaX, deltaY,
mouseButton, wheel, keyName, typed, autoRepeat, buttons, ctrl, shift, alt,
gui, focus`, so an event can be made directly, as tests do:
`core.Event { name = "keyPress", keyName = "c", ctrl = true }`.
`luif/core/keys.lua` has the helpers for names: `Keys.modifiers`,
`Keys.modifierOf`, `Keys.isReturn`, `Keys.isPrintable`,
and `Keys.displayName`, which gives readable English names
(`Event.keyDisplayName(key)` returns one as a Text to translate). Controls
compare names: `TextInput` edits on `"backspace"`, `"delete"`, the arrows,
`"home"`, `"end"`, `"a"`, `"c"`, `"x"`, `"v"` and `"insert"` with the
modifiers, `ActionBindings` maps `"space"`, `"return"` and `"kpenter"` to
`"Activate"` for `Button`, and `specialPress` gets the key name.

Picking: the topmost attached, mouse enabled item whose box `(0, 0,
size())` contains the point, walking the roots of `luif/core/sync.lua` last to
first and draw children last to first, on the item tree (no node is read).
Each item's transform is `x, y`, `rotation` (degrees), `scale` and
`transformOriginX/Y` (fractions of its size), relative to its parent, so the content children of a
`SkinnableItem` are offset by the skin and its `contentArea` like any
other children. An item that is invisible or
has alpha 0 is skipped with its subtree, and a `clip` item skips its subtree
outside its box.

Delivery rules:

* Mouse events go to the picked item. Bubbling is done by
  `Item:event`, which maps the local position into each parent's space
  with `Pointer.toLocal(parent, absX, absY)`.
* While a button is held, `mouseMove`, `mouseRelease` and `mouseDoubleClick`
  go to the item that received the `mousePress` (capture). `mouseEnter`
  and `mouseLeave` keep following the real hit. The wheel is not captured.
* Double clicks are counted in core with the host's `time()`: a press of
  the same button within `Pointer.doubleClickTime` (500 ms) and
  `Pointer.doubleClickRadius` (32 pixels) of the previous one adds to the
  count. An even count is delivered as `mouseDoubleClick` instead of
  `mousePress`; the framework's double click
  handlers forward to `mousePress`. If the item does not accept the
  `mouseDoubleClick`, the `mousePress` is delivered after all (the
  unaccepted `mouseDoubleClick` does not reach the fallback listener).
* A `mouseRelease` is only delivered for a button whose press was delivered.
  Lost releases are the host's job (`releaseLostButtons` on LOVE).
* `pointerLeft` gives the hovered item `mouseLeave`; nothing is hovered
  until the pointer moves again.
* Key events go to the focused item (`Pointer.focused()`) while it is
  attached. Focus is a reference to an item: a focused item that is detached
  keeps it and gets keys again once attached, unless the focus moved;
  `setFocus` before attachment applies once attached; deleting the focused
  item clears the focus. `Pointer.isKeyDown(name)` and
  `Pointer.modifierDown(name)` report held keys.
* Anything not accepted (the item returned false, is not mouse enabled,
  or there is none) goes to the function registered with
  `Pointer.setFallback` (`core.FallbackListeners`), as a fresh Event made
  from the values before the item ran.
* Detaching an item makes the pointer forget it as hover or capture,
  without a `mouseLeave`.
* Hover is re-picked after the update (`Pointer.afterUpdate`) only when the
  generation counter moved. Item setters bump it when position, size,
  rotation, scale, transform origin, visibility, alpha, `mouseEnabled`,
  `clip` or the parent changes value, when children are reordered, and when
  items are attached or detached.

Tooltips (`luif/core/tooltip.lua`) are roots placed and sized in virtual units:
next to the pointer (or `relX/relY` from the item's `absolutePos`) and
kept within `Update.virtualScreenWidth/Height`; they have no scale of their
own; `Item:createToolTip` registers them with `Sync.addRoot`.
`luif/core/toplayer.lua` is a root sized to the virtual screen on
`uiScaleChanged`.
