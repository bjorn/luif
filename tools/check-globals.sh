#!/bin/sh
# Static checks for the framework under luif/core/ (and luif/module.lua, its loader):
#  1. core is portable: no love, io, os or luif.love references, no global
#     assignments, and no global reads beyond the Lua standard library
#     (checked on LuaJIT bytecode, GGET and GSET); luif/core/bit.lua alone may
#     read the bit library,
#  2. no host node use outside luif/core/sync.lua but content in pushContent,
#  3. Screen.scale read only by the screen, sync and pointer,
#  4. luif/host/ loads without LOVE.
# Run from anywhere; exits 1 when a check fails.

root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root" || exit 1
status=0

# Globals core may read: the Lua 5.1 standard library (without io, os,
# package, dofile, loadfile and module) as LuaJIT provides it.
standard='assert|collectgarbage|error|getfenv|getmetatable|ipairs|load|loadstring|next|pairs|pcall|print|rawequal|rawget|rawset|require|select|setfenv|setmetatable|tonumber|tostring|type|unpack|xpcall|_G|_VERSION|coroutine|debug|math|string|table'

for f in luif/module.lua luif/core/*.lua luif/core/skins/*.lua; do
    if ! bytecode=$(luajit -bl "$f" 2>&1); then
        echo "check-globals: syntax error in $f"
        status=1
        continue
    fi
    allowed="^($standard)\$"
    if [ "$f" = luif/core/bit.lua ]; then
        allowed="^($standard|bit)\$"
    fi
    globals=$(printf '%s\n' "$bytecode" \
        | sed -nE 's/^[0-9]+ +(GGET|GSET) .*; "([^"]*)"$/\1 \2/p' | sort -u)
    writes=$(printf '%s\n' "$globals" | sed -n 's/^GSET //p')
    reads=$(printf '%s\n' "$globals" | sed -n 's/^GGET //p' | grep -vE "$allowed")
    if [ -n "$writes" ]; then
        echo "check-globals: global assignment in $f:"
        printf '%s\n' "$writes" | sed 's/^/    /'
        status=1
    fi
    if [ -n "$reads" ]; then
        echo "check-globals: non-standard global read in $f:"
        printf '%s\n' "$reads" | sed 's/^/    /'
        status=1
    fi
done

# Also as text, so a love, io or os field reached some other way or a
# luif.love require stands out. Comment lines do not count.
if grep -rnE '\b(love|io|os)\.|require *\(? *["'"'"']luif\.love' luif/module.lua luif/core --include=*.lua \
        | grep -vE '^[^:]+:[0-9]+: *--'; then
    echo "check-globals: love, io, os or luif.love referenced from luif/core/"
    status=1
fi

# Only luif/core/sync.lua touches host nodes: no node handles, structure or
# property functions or host inspection anywhere else in luif/core/ or example/.
# Items set the content of the node they are handed in pushContent(host, node).
nodes='_node\b|Sync\.node\b|([hH]ost|\))\.(createNode|destroyNode|attach|detach|setTransform|setSize|setOpacity|setVisible|setClip|clearContent|inspect|topLevel)\('
if grep -rnE "$nodes" luif/core example --include=*.lua | grep -v '^luif/core/sync\.lua:'; then
    echo "check-globals: host nodes used outside core/sync.lua"
    status=1
fi
if grep -rnE '([hH]ost|\))\.(setImage|setSlices|setText|setFill)\(' example --include=*.lua; then
    echo "check-globals: host content set outside core"
    status=1
fi

# The UI scale is applied in one place: only luif/core/screen.lua,
# luif/core/sync.lua (root nodes) and luif/core/pointer.lua (input) read
# Screen.scale. Comment lines do not count.
if grep -rnE "Screen\.scale\b" luif/core example --include=*.lua \
        | grep -vE '^luif/core/(screen|sync|pointer)\.lua:' \
        | grep -vE '^[^:]+:[0-9]+: *--'; then
    echo "check-globals: Screen.scale read outside the screen, sync and pointer"
    status=1
fi

# The platform neutral host code (interface, recording host) must load
# without LOVE.
for f in luif/host/*.lua; do
    if ! luajit -bl "$f" >/dev/null 2>&1; then
        echo "check-globals: syntax error in $f"
        status=1
    elif luajit -bl "$f" | grep -qE 'GGET .*"(love|io|os)"'; then
        echo "check-globals: love, io or os used in $f"
        status=1
    fi
done

if [ $status -eq 0 ]; then
    echo "check-globals: ok"
fi
exit $status
