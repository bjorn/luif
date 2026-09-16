--
-- Input dispatch on the core item tree. Registers as the input sink of a
-- host (host/interface.lua) and turns the feed into the events items
-- handle (Item:handleEvent, core/event.lua): picking, hover with enter and leave,
-- capture while a button is held, double clicks, the wheel, key routing to
-- the focused item and the fallback listener.
--
--   Pointer.attach(host)      register as the host's sink (nil detaches)
--   Pointer.afterUpdate()     re-pick under a still pointer when geometry changed
--   Pointer.pick(x, y)        topmost mouse enabled item, and the local position
--   Pointer.toLocal(w, x, y)  window position to the item's local space
--   Pointer.toWorld(w, x, y)  and back
--   Pointer.position()        last position the feed delivered, virtual units
--   Pointer.toWindow(x, y)    virtual units to window pixels
--   Pointer.toVirtual(x, y)   window pixels to virtual units
--   Pointer.isKeyDown(name)   whether a key is held (feed or host isKeyDown)
--   Pointer.modifierDown(m)   whether "ctrl", "shift", "alt" or "gui" is held
--
-- Units: the host feed is in window pixels. The pointer divides it by the UI
-- scale (Screen.scale, the scale core/sync.lua gives root nodes) before
-- picking, so picking, every event coordinate and delta, and position() are
-- in virtual units, the units items are laid out in. Only the double click
-- radius is measured in window pixels. A changed scale re-picks hover after
-- the update.
--
-- Picking walks the attached item tree from the roots of core/sync.lua and
-- follows each item's own transform: x, y, rotation in degrees, scale and
-- transformOriginX/Y (fractions of its size), relative to its parent.
-- Invisible and alpha 0 items are skipped with their subtree; a clipping
-- item rejects its subtree outside its box.
--
-- The sink functions return true when the UI handled the input: a press on
-- an item that takes mouse input, the release of a press an item took, the
-- wheel over such an item, and keys and text the focused item accepted
-- (pointerMoved: the pointer is over such an item). A host can pass other
-- input on.
--
-- Item geometry and structure changes call Pointer.changed(), which bumps a
-- generation counter; hover is re-picked after the update only when it
-- changed.
--

local core = require "luif.core"

local Event = core.Event
local Keys = core.Keys
local Sync = core.Sync

local rad, cos, sin, abs = math.rad, math.cos, math.sin, math.abs

local Pointer = {
    -- Two presses of one button within this time and radius make a double
    -- click, like SDL's defaults.
    doubleClickTime = 500,
    doubleClickRadius = 32,
}

local host = false
local sink = {}
Pointer.sink = sink

local wx, wy = 0, 0             -- last delivered position, window pixels
local outside = false           -- the pointer left the window
local held = {}                 -- buttons pressed through the feed
local keysDown = {}             -- keys pressed through the feed
local clicks = {}               -- button -> { time, x, y, count }
local hover = false             -- item that got mouseEnter
local capture = false           -- item that got the mousePress
local focus = false             -- item that has the focus
local fallback = false          -- function(event) for unaccepted events

local generation = 0
local pickedGeneration = nil    -- generation of the last hover pick
local pickedScale = nil         -- UI scale of the last hover pick
local picks = 0

local function uiScale()
    return core.Screen.scale
end

function Pointer.toVirtual(x, y)
    local scale = uiScale()
    return x / scale, y / scale
end

function Pointer.toWindow(x, y)
    local scale = uiScale()
    return x * scale, y * scale
end

-- One entry pick cache, valid while the generation stays the same.
local cacheX, cacheY, cacheGeneration = nil, nil, nil
local cacheHit, cacheLX, cacheLY = nil, nil, nil

-- Attached (rawget: a deleted item has no fields left).
local function alive(item)
    return item and rawget(item, "_root") and true or false
end

--
-- Geometry
--

local SNAP = 1e-12

-- The item's transform relative to its parent as a similarity
-- (a, b, tx, ty): world = (a * lx - b * ly + tx, b * lx + a * ly + ty).
local function localTransform(w)
    local s, r = w.scale, w.rotation
    local a, b
    if r == 0 then
        a, b = s, 0
    else
        r = rad(r)
        local c, n = cos(r), sin(r)
        if abs(c) < SNAP then c = 0 end
        if abs(n) < SNAP then n = 0 end
        a, b = s * c, s * n
    end
    local width, height = w:size()
    local ox, oy = w.transformOriginX * width, w.transformOriginY * height
    return a, b, w.x + ox - (a * ox - b * oy), w.y + oy - (b * ox + a * oy)
end

local function compose(A, B, TX, TY, a, b, tx, ty)
    return A * a - B * b, A * b + B * a, A * tx - B * ty + TX, B * tx + A * ty + TY
end

local function worldTransform(w)
    local a, b, tx, ty = localTransform(w)
    local parent = w.parent
    if parent then
        local A, B, TX, TY = worldTransform(parent)
        return compose(A, B, TX, TY, a, b, tx, ty)
    end
    return a, b, tx, ty
end

function Pointer.toLocal(w, x, y)
    local a, b, tx, ty = worldTransform(w)
    local det = a * a + b * b
    if det == 0 then return 0, 0 end
    local dx, dy = x - tx, y - ty
    return (a * dx + b * dy) / det, (a * dy - b * dx) / det
end

function Pointer.toWorld(w, x, y)
    local a, b, tx, ty = worldTransform(w)
    return a * x - b * y + tx, b * x + a * y + ty
end

--
-- Picking
--

local pickItem

-- Items of list, topmost (last) first.
local function pickList(list, a, b, tx, ty, x, y)
    for i = #list, 1, -1 do
        local child = list[i]
        if rawget(child, "_root") then
            local hit, lx, ly = pickItem(child, a, b, tx, ty, x, y)
            if hit then return hit, lx, ly end
        end
    end
    return nil
end

-- Children are picked topmost (last) first, before the item itself.
function pickItem(w, A, B, TX, TY, x, y)
    if not w._visible or w.alpha <= 0 then return nil end
    local children = w.children
    if not w.mouseEnabled and #children == 0 then
        return nil
    end
    local a, b, tx, ty = compose(A, B, TX, TY, localTransform(w))
    local det = a * a + b * b
    if det == 0 then return nil end
    local dx, dy = x - tx, y - ty
    local lx, ly = (a * dx + b * dy) / det, (a * dy - b * dx) / det
    local width, height = w:size()
    local inside = lx >= 0 and ly >= 0 and lx < width and ly < height
    if w.clip and not inside then return nil end

    local hit, hx, hy = pickList(children, a, b, tx, ty, x, y)
    if hit then return hit, hx, hy end

    if w.mouseEnabled and inside then
        return w, lx, ly
    end
    return nil
end

-- Topmost mouse enabled item under the position (virtual units), with the
-- position in its local space; nil when there is none.
function Pointer.pick(x, y)
    if cacheGeneration == generation and cacheX == x and cacheY == y then
        return cacheHit, cacheLX, cacheLY
    end
    picks = picks + 1
    local hit, lx, ly
    local roots = Sync.roots()
    for i = #roots, 1, -1 do
        local root = roots[i]
        if rawget(root, "_root") then
            hit, lx, ly = pickItem(root, 1, 0, 0, 0, x, y)
            if hit then break end
        end
    end
    cacheX, cacheY, cacheGeneration = x, y, generation
    cacheHit, cacheLX, cacheLY = hit, lx, ly
    return hit, lx, ly
end

-- Number of tree walks so far (cache hits excluded); for tests.
function Pointer.picks()
    return picks
end

--
-- Tree bookkeeping, called by Item
--

-- Geometry or structure that affects picking changed.
function Pointer.changed()
    generation = generation + 1
end

function Pointer.generation()
    return generation
end

-- The roots picking starts from, bottom to top (Sync.roots()).
function Pointer.roots()
    return Sync.roots()
end

-- Forgets an item that is detached, without delivering mouseLeave.
function Pointer.forget(w)
    if hover == w then hover = false end
    if capture == w then capture = false end
    generation = generation + 1
end

--
-- Focus
--

function Pointer.focused()
    return focus or nil
end

-- Sets the item that receives key events while attached (nil for none).
function Pointer.setFocused(w)
    focus = w or false
end

--
-- Delivery
--

function Pointer.setFallback(fn)
    fallback = fn or false
end

function Pointer.fallback()
    return fallback or nil
end

function Pointer.isKeyDown(name)
    if keysDown[name] then return true end
    local isKeyDown = host and host.isKeyDown
    return isKeyDown and isKeyDown(name) or false
end

local isKeyDown = Pointer.isKeyDown

function Pointer.modifierDown(modifier)
    local names = Keys.modifiers[modifier]
    if not names then return false end
    for i = 1, #names do
        if isKeyDown(names[i]) then return true end
    end
    return false
end

local modifierDown = Pointer.modifierDown
local noButtons = {}

-- Adds the held buttons, modifiers and focus to event fields.
local function addState(fields)
    if next(held) then
        local buttons = {}
        for button in pairs(held) do buttons[button] = true end
        fields.buttons = buttons
    else
        fields.buttons = noButtons
    end
    fields.ctrl = modifierDown("ctrl")
    fields.shift = modifierDown("shift")
    fields.alt = modifierDown("alt")
    fields.gui = modifierDown("gui")
    fields.focus = focus or nil
    return fields
end

-- Delivers an event made from fields to the item when it is attached and
-- mouse enabled; otherwise, or when it does not accept, to the fallback as
-- a fresh event with the fields from before the item ran. noFallback
-- suppresses the fallback.
local function deliver(item, fields, noFallback)
    addState(fields)
    local target = alive(item) and item.mouseEnabled and item or nil
    local fallbackFn = not noFallback and fallback
    if not target then
        if fallbackFn then
            fallbackFn(Event(fields))
        end
        return false
    end
    if not fallbackFn then
        return target:handleEvent(Event(fields))
    end
    local copy = {}
    for key, value in pairs(fields) do
        copy[key] = value
    end
    local accepted = target:handleEvent(Event(fields))
    if not accepted then
        fallbackFn(Event(copy))
    end
    return accepted
end

local function deliverMouse(name, item, x, y, button, wheel, dx, dy, noFallback)
    local lx, ly = x, y
    if alive(item) then
        lx, ly = Pointer.toLocal(item, x, y)
    end
    return deliver(item, {
        name = name,
        localX = lx, localY = ly, absX = x, absY = y,
        deltaX = dx or 0, deltaY = dy or 0,
        mouseButton = button, wheel = wheel,
    }, noFallback)
end

-- Re-picks under the pointer and delivers mouseLeave and mouseEnter when
-- the hovered item changed. Returns the hit.
local function updateHover(x, y)
    pickedGeneration = generation
    pickedScale = uiScale()
    if hover and not alive(hover) then
        hover = false
    end
    local hit = Pointer.pick(x, y)
    local owner = hit or false
    if owner ~= hover then
        local old = hover
        hover = owner
        if old then
            deliverMouse("mouseLeave", old, x, y)
        end
        if owner and hover == owner then
            deliverMouse("mouseEnter", owner, x, y)
        end
    end
    return hit
end

-- The item that receives moves and releases: the capture, else the hit.
local function target(x, y)
    if capture then
        if alive(capture) then
            return capture
        end
        capture = false
    end
    return (Pointer.pick(x, y))
end

-- Press count of the button like SDL counts clicks: a press within the
-- double click time and radius of the previous one adds to it.
local function clickCount(button, x, y)
    local now = host and host.time()
    if not now then return 1 end
    local click = clicks[button]
    if not click then
        click = { time = now, x = x, y = y, count = 0 }
        clicks[button] = click
    end
    if now - click.time >= Pointer.doubleClickTime
            or abs(x - click.x) > Pointer.doubleClickRadius
            or abs(y - click.y) > Pointer.doubleClickRadius then
        click.count = 0
    end
    click.time, click.x, click.y = now, x, y
    click.count = click.count + 1
    return click.count
end

--
-- The input feed
--

function sink.pointerMoved(windowX, windowY)
    local lastX, lastY = Pointer.position()
    wx, wy, outside = windowX, windowY, false
    local x, y = Pointer.position()
    local hit = updateHover(x, y)
    deliverMouse("mouseMove", target(x, y), x, y, nil, nil, x - lastX, y - lastY)
    return hit and true or false
end

-- The second press of a double click (an even press count) arrives as
-- mouseDoubleClick instead of mousePress. When the item does not accept
-- it, the press is delivered after all.
function sink.pointerPressed(windowX, windowY, button)
    wx, wy, outside = windowX, windowY, false
    local x, y = Pointer.position()
    updateHover(x, y)
    local item
    if alive(capture) then
        item = capture
    else
        capture = false
        item = Pointer.pick(x, y)
        if item and not next(held) then
            capture = item
        end
    end
    held[button] = true
    local handled = alive(item) and item.mouseEnabled and true or false
    local count = clickCount(button, windowX, windowY)
    if count >= 2 and count % 2 == 0 and handled then
        if deliverMouse("mouseDoubleClick", item, x, y, button, nil, nil, nil, true) then
            return handled
        end
    end
    deliverMouse("mousePress", item, x, y, button)
    return handled
end

-- A release without a delivered press is dropped.
function sink.pointerReleased(windowX, windowY, button)
    wx, wy, outside = windowX, windowY, false
    local x, y = Pointer.position()
    local handled = alive(capture)
    if held[button] then
        local item = target(x, y)
        held[button] = nil
        deliverMouse("mouseRelease", item, x, y, button)
    end
    if not next(held) then
        capture = false
    end
    updateHover(x, y)
    return handled
end

-- Not captured: the wheel goes to the item under the pointer.
function sink.wheel(dx, dy)
    local x, y = Pointer.position()
    local hit = nil
    if not outside then
        updateHover(x, y)
        hit = Pointer.pick(x, y)
    end
    deliverMouse("mouseWheel", hit, x, y, nil, dy)
    return hit and true or false
end

-- Nothing is hovered until the pointer moves again.
function sink.pointerLeft()
    local old = hover
    hover = false
    outside = true
    if alive(old) then
        local x, y = Pointer.position()
        deliverMouse("mouseLeave", old, x, y)
    end
end

function sink.keyPressed(key, isRepeat)
    keysDown[key] = true
    local handled = deliver(focus, { name = "keyPress", keyName = key, autoRepeat = isRepeat or false })
    -- The feed carries no text for Return, so synthesize the character.
    if Keys.isReturn(key) then
        deliver(focus, {
            name = "keyCharacter", keyName = key, typed = "\n", autoRepeat = isRepeat or false,
        })
    end
    return handled and true or false
end

function sink.keyReleased(key)
    keysDown[key] = nil
    return deliver(focus, { name = "keyRelease", keyName = key, autoRepeat = false }) and true or false
end

function sink.textInput(text)
    if text == "" then return false end
    return deliver(focus, { name = "keyCharacter", typed = text, autoRepeat = false }) and true or false
end

--
-- Frame and state
--

-- Registers as the host's input sink, replacing the previous host.
function Pointer.attach(newHost)
    if host and host ~= newHost then
        host.setInputSink(nil)
    end
    host = newHost or false
    if host then
        host.setInputSink(sink)
        if host.pointerPosition then
            wx, wy = host.pointerPosition()
        end
    end
end

function Pointer.host()
    return host or nil
end

-- Runs after the update: a layout or UI scale change under a still pointer
-- produces mouseEnter and mouseLeave, but only when the generation or the
-- scale moved.
function Pointer.afterUpdate()
    if outside or (pickedGeneration == generation and pickedScale == uiScale()) then
        return
    end
    updateHover(Pointer.position())
end

-- In virtual units.
function Pointer.position()
    local scale = uiScale()
    return wx / scale, wy / scale
end

function Pointer.hovered()
    return hover or nil
end

function Pointer.captured()
    return capture or nil
end

-- Drops hover, capture, held buttons and keys and click counts; keeps the
-- focus, the roots and the host.
function Pointer.reset()
    hover, capture, outside = false, false, false
    held, keysDown, clicks = {}, {}, {}
    pickedGeneration, pickedScale = nil, nil
    cacheGeneration = nil
end

return Pointer
