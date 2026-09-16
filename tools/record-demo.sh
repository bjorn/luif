#!/bin/sh
# Records one loop of the example's demo screen and encodes it as
# doc/screenshots/demo.webm (VP9). Needs love, ffmpeg with libvpx-vp9, and
# xvfb-run when there is no display.
set -e

root=$(cd "$(dirname "$0")/.." && pwd)
fps=${FPS:-60}
save="${XDG_DATA_HOME:-$HOME/.local/share}/love/luif_example/record"
out="$root/doc/screenshots"

rm -rf "$save"
run=""
if [ -z "$DISPLAY" ] || [ -n "$HEADLESS" ]; then
    run="xvfb-run -a -s '-screen 0 1280x720x24'"
fi
eval "LUIF_SCENE=demo LUIF_RECORD=$fps $run love \"$root/example\""

ffmpeg -loglevel error -y -framerate "$fps" -i "$save/frame%04d.png" \
    -c:v libvpx-vp9 -pix_fmt yuv420p -crf 42 -b:v 0 -row-mt 1 -an \
    "$out/demo.webm"
ls -l "$out/demo.webm"
