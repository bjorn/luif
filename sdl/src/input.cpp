//
// SDL events to the input sink (Interface.feed), LOVE key names and system
// cursors.
//
#include "internal.h"

#include <cstring>

namespace luif {

namespace {

constexpr int MaxButton = 31;   // pressedButtons has a bit per button

//
// Key names (https://love2d.org/wiki/KeyConstant). Printable keys are named
// by their character and are not listed, except for space.
//
struct KeyName { SDL_Keycode key; const char *name; };

const KeyName keyNames[] = {
    { SDLK_SPACE, "space" }, { SDLK_RETURN, "return" }, { SDLK_ESCAPE, "escape" },
    { SDLK_BACKSPACE, "backspace" }, { SDLK_TAB, "tab" }, { SDLK_DELETE, "delete" },
    { SDLK_INSERT, "insert" }, { SDLK_CLEAR, "clear" },
    { SDLK_LEFT, "left" }, { SDLK_RIGHT, "right" }, { SDLK_UP, "up" }, { SDLK_DOWN, "down" },
    { SDLK_HOME, "home" }, { SDLK_END, "end" },
    { SDLK_PAGEUP, "pageup" }, { SDLK_PAGEDOWN, "pagedown" },
    { SDLK_F1, "f1" }, { SDLK_F2, "f2" }, { SDLK_F3, "f3" }, { SDLK_F4, "f4" },
    { SDLK_F5, "f5" }, { SDLK_F6, "f6" }, { SDLK_F7, "f7" }, { SDLK_F8, "f8" },
    { SDLK_F9, "f9" }, { SDLK_F10, "f10" }, { SDLK_F11, "f11" }, { SDLK_F12, "f12" },
    { SDLK_F13, "f13" }, { SDLK_F14, "f14" }, { SDLK_F15, "f15" }, { SDLK_F16, "f16" },
    { SDLK_F17, "f17" }, { SDLK_F18, "f18" }, { SDLK_F19, "f19" }, { SDLK_F20, "f20" },
    { SDLK_F21, "f21" }, { SDLK_F22, "f22" }, { SDLK_F23, "f23" }, { SDLK_F24, "f24" },
    { SDLK_LSHIFT, "lshift" }, { SDLK_RSHIFT, "rshift" },
    { SDLK_LCTRL, "lctrl" }, { SDLK_RCTRL, "rctrl" },
    { SDLK_LALT, "lalt" }, { SDLK_RALT, "ralt" },
    { SDLK_LGUI, "lgui" }, { SDLK_RGUI, "rgui" }, { SDLK_MODE, "mode" },
    { SDLK_CAPSLOCK, "capslock" }, { SDLK_NUMLOCKCLEAR, "numlock" },
    { SDLK_SCROLLLOCK, "scrolllock" },
    { SDLK_KP_0, "kp0" }, { SDLK_KP_1, "kp1" }, { SDLK_KP_2, "kp2" }, { SDLK_KP_3, "kp3" },
    { SDLK_KP_4, "kp4" }, { SDLK_KP_5, "kp5" }, { SDLK_KP_6, "kp6" }, { SDLK_KP_7, "kp7" },
    { SDLK_KP_8, "kp8" }, { SDLK_KP_9, "kp9" },
    { SDLK_KP_PERIOD, "kp." }, { SDLK_KP_COMMA, "kp," }, { SDLK_KP_DIVIDE, "kp/" },
    { SDLK_KP_MULTIPLY, "kp*" }, { SDLK_KP_MINUS, "kp-" }, { SDLK_KP_PLUS, "kp+" },
    { SDLK_KP_ENTER, "kpenter" }, { SDLK_KP_EQUALS, "kp=" },
    { SDLK_PRINTSCREEN, "printscreen" }, { SDLK_PAUSE, "pause" }, { SDLK_SYSREQ, "sysreq" },
    { SDLK_MENU, "menu" }, { SDLK_APPLICATION, "application" }, { SDLK_POWER, "power" },
    { SDLK_HELP, "help" }, { SDLK_CURRENCYUNIT, "currencyunit" },
    { SDLK_CURRENCYSUBUNIT, "currencysubunit" },
    { SDLK_EXECUTE, "execute" }, { SDLK_SELECT, "select" }, { SDLK_STOP, "stop" },
    { SDLK_AGAIN, "again" }, { SDLK_UNDO, "undo" }, { SDLK_CUT, "cut" }, { SDLK_COPY, "copy" },
    { SDLK_PASTE, "paste" }, { SDLK_FIND, "find" }, { SDLK_MUTE, "mute" },
    { SDLK_VOLUMEUP, "volumeup" }, { SDLK_VOLUMEDOWN, "volumedown" },
    { SDLK_ALTERASE, "alterase" }, { SDLK_CANCEL, "cancel" }, { SDLK_PRIOR, "prior" },
    { SDLK_RETURN2, "return2" }, { SDLK_SEPARATOR, "separator" }, { SDLK_OUT, "out" },
    { SDLK_OPER, "oper" }, { SDLK_CLEARAGAIN, "clearagain" },
    { SDLK_MEDIA_NEXT_TRACK, "audionext" }, { SDLK_MEDIA_PREVIOUS_TRACK, "audioprev" },
    { SDLK_MEDIA_STOP, "audiostop" }, { SDLK_MEDIA_PLAY, "audioplay" },
    { SDLK_MEDIA_SELECT, "mediaselect" }, { SDLK_MEDIA_EJECT, "eject" }, { SDLK_SLEEP, "sleep" },
    { SDLK_AC_SEARCH, "appsearch" }, { SDLK_AC_HOME, "apphome" }, { SDLK_AC_BACK, "appback" },
    { SDLK_AC_FORWARD, "appforward" }, { SDLK_AC_STOP, "appstop" },
    { SDLK_AC_REFRESH, "apprefresh" }, { SDLK_AC_BOOKMARKS, "appbookmarks" },
};

// Keycodes of printable keys are their code point
bool isCharacterKey(SDL_Keycode key)
{
    return key > ' ' && key != SDLK_DELETE && key < 0x110000;
}

const char *keyName(SDL_Keycode key, char buffer[8])
{
    for (const KeyName &entry : keyNames)
        if (entry.key == key)
            return entry.name;
    if (!isCharacterKey(key))
        return "unknown";
    *SDL_UCS4ToUTF8(key, buffer) = '\0';
    return buffer;
}

SDL_Keycode keyFromName(const char *name)
{
    for (const KeyName &entry : keyNames)
        if (std::strcmp(entry.name, name) == 0)
            return entry.key;
    const SDL_Keycode key = SDL_StepUTF8(&name, nullptr);
    return *name == '\0' && isCharacterKey(key) ? key : SDLK_UNKNOWN;
}

struct CursorName { const char *name; SDL_SystemCursor id; };

// Interface.cursors
const CursorName cursorNames[] = {
    { "arrow", SDL_SYSTEM_CURSOR_DEFAULT },
    { "hand", SDL_SYSTEM_CURSOR_POINTER },
    { "ibeam", SDL_SYSTEM_CURSOR_TEXT },
    { "sizeall", SDL_SYSTEM_CURSOR_MOVE },
    { "sizenwse", SDL_SYSTEM_CURSOR_NWSE_RESIZE },
    { "sizenesw", SDL_SYSTEM_CURSOR_NESW_RESIZE },
    { "sizewe", SDL_SYSTEM_CURSOR_EW_RESIZE },
    { "sizens", SDL_SYSTEM_CURSOR_NS_RESIZE },
    { "wait", SDL_SYSTEM_CURSOR_WAIT },
    { "waitarrow", SDL_SYSTEM_CURSOR_PROGRESS },
    { "no", SDL_SYSTEM_CURSOR_NOT_ALLOWED },
    { "crosshair", SDL_SYSTEM_CURSOR_CROSSHAIR },
};

void push(lua_State *L, float value) { lua_pushnumber(L, value); }
void push(lua_State *L, int value) { lua_pushinteger(L, value); }
void push(lua_State *L, bool value) { lua_pushboolean(L, value); }
void push(lua_State *L, const char *value) { lua_pushstring(L, value); }

// Calls the sink's feed function with the arguments, when there is a sink
// that has it; true when the framework handled the input.
template <typename... Args>
bool feed(SdlHost::Impl &host, const char *name, Args... args)
{
    if (host.sinkRef == LUA_NOREF)
        return false;
    lua_State *L = host.L;
    lua_rawgeti(L, LUA_REGISTRYINDEX, host.sinkRef);
    lua_getfield(L, -1, name);
    lua_remove(L, -2);
    if (!lua_isfunction(L, -1)) {
        lua_pop(L, 1);
        return false;
    }
    (push(L, args), ...);
    if (!protectedCall(host, sizeof...(args), 1)) {
        host.inputError = true;     // update() reports it
        return false;
    }
    const bool handled = lua_toboolean(L, -1);
    lua_pop(L, 1);
    return handled;
}

// Every delivered press gets exactly one release
bool feedRelease(SdlHost::Impl &host, float x, float y, int button)
{
    const uint32_t bit = 1u << button;
    if (!(host.pressedButtons & bit))
        return false;
    host.pressedButtons &= ~bit;
    return feed(host, "pointerReleased", x, y, button);
}

void releaseAll(SdlHost::Impl &host)
{
    float x, y;
    SDL_GetMouseState(&x, &y);      // the last known position
    SDL_RenderCoordinatesFromWindow(host.renderer, x, y, &x, &y);
    for (int button = 1; button <= MaxButton; ++button)
        feedRelease(host, x, y, button);
}

// SDL numbers the middle button 2 and the right button 3; 0 is none
int buttonOf(const SDL_MouseButtonEvent &event)
{
    static const int buttons[] = { 0, 1, 3, 2 };
    if (event.button > MaxButton)
        return 0;
    return event.button < SDL_arraysize(buttons) ? buttons[event.button] : event.button;
}

} // namespace

bool feedEvent(SdlHost::Impl &host, const SDL_Event &original)
{
    SDL_Window *window = SDL_GetWindowFromEvent(&original);
    if (window && window != host.window)
        return false;

    SDL_Event event = original;
    SDL_ConvertEventToRenderCoordinates(host.renderer, &event);

    switch (event.type) {
    case SDL_EVENT_MOUSE_MOTION:
        host.pointerOverUi = feed(host, "pointerMoved", event.motion.x, event.motion.y);
        return false;
    case SDL_EVENT_MOUSE_BUTTON_DOWN: {
        const int button = buttonOf(event.button);
        if (!button)
            return false;
        feedRelease(host, event.button.x, event.button.y, button);  // its release got lost
        host.pressedButtons |= 1u << button;
        return feed(host, "pointerPressed", event.button.x, event.button.y, button);
    }
    case SDL_EVENT_MOUSE_BUTTON_UP: {
        const int button = buttonOf(event.button);
        return button && feedRelease(host, event.button.x, event.button.y, button);
    }
    case SDL_EVENT_MOUSE_WHEEL:
        // As SDL reports them, which is what LOVE does: undoing a flipped
        // direction would cancel the natural scrolling setting
        return feed(host, "wheel", original.wheel.x, original.wheel.y);
    case SDL_EVENT_KEY_DOWN:
    case SDL_EVENT_KEY_UP: {
        char buffer[8];
        const char *name = keyName(event.key.key, buffer);
        return event.type == SDL_EVENT_KEY_DOWN ? feed(host, "keyPressed", name, bool(event.key.repeat))
                                                : feed(host, "keyReleased", name);
    }
    case SDL_EVENT_TEXT_INPUT:
        return event.text.text && *event.text.text && feed(host, "textInput", event.text.text);
    case SDL_EVENT_WINDOW_MOUSE_LEAVE:
        host.pointerOverUi = false;
        feed(host, "pointerLeft");
        return false;
    case SDL_EVENT_WINDOW_FOCUS_LOST:
        releaseAll(host);       // the releases go to whatever has the focus now
        return false;
    default:
        return false;
    }
}

void setCursor(SdlHost::Impl &host, const char *name)
{
    SDL_SystemCursor id = SDL_SYSTEM_CURSOR_DEFAULT;    // nil and unknown names: arrow
    for (const CursorName &entry : cursorNames)
        if (name && std::strcmp(entry.name, name) == 0)
            id = entry.id;
    if (id == host.cursor)
        return;
    host.cursor = id;
    if (!host.cursors[id])
        host.cursors[id] = SDL_CreateSystemCursor(id);
    SDL_SetCursor(host.cursors[id] ? host.cursors[id] : SDL_GetDefaultCursor());
}

bool isKeyDown(const char *name)
{
    const SDL_Keycode key = keyFromName(name);
    if (key == SDLK_UNKNOWN)
        return false;
    int count = 0;
    const bool *state = SDL_GetKeyboardState(&count);
    const SDL_Scancode scancode = SDL_GetScancodeFromKey(key, nullptr);
    return scancode != SDL_SCANCODE_UNKNOWN && int(scancode) < count && state[scancode];
}

} // namespace luif
