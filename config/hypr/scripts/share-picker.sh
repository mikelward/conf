#!/bin/sh
#
# xdg-desktop-portal-hyprland's share picker (xdph.conf): tide's
# tide-share-picker where tide is installed (tide SPEC.md §12), and xdph's
# own hyprland-share-picker otherwise, so a screen share works with or
# without tide. xdph passes its arguments (--allow-token) and its window
# list (XDPH_WINDOW_SHARING_LIST) through, and reads the answer from stdout.

if command -v tide-share-picker >/dev/null 2>&1; then
    exec tide-share-picker "$@"
fi
if command -v hyprland-share-picker >/dev/null 2>&1; then
    exec hyprland-share-picker "$@"
fi
echo "share-picker.sh: neither tide-share-picker nor hyprland-share-picker is installed, so nothing is shared" >&2
exit 1
