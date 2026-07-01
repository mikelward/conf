# river per-host override -- TEMPLATE. Copy this to hosts/<hostname>.sh
# (use your machine's short hostname; `hostname -s` prints it) and fill
# in the PLACEHOLDERS. Sourced by init AFTER base, so anything here wins.
#
# This file is the ONLY place machine-specific values belong: input
# device names, handedness, scroll factor, per-machine wallpaper, and the
# optional lid-watcher. Output arrangement is handled by kanshi
# (~/.config/kanshi/hosts/<hostname>.conf), not here.
#
# Nothing here is required -- an unconfigured host still gets a working
# desktop from base alone.

### Input devices #############################################################
#
# Get exact device names with:   riverctl list-inputs
# (run it inside a river session). Names look like:
#   pointer-1267:12345:Some_Trackpad
#   pointer-0000:0000:Logitech_USB_Mouse
#
# HANDEDNESS RULE for this setup:
#   - Trackpads keep the LEFT button as primary  -> left-handed DISABLED
#   - Mice use the RIGHT button as primary        -> left-handed ENABLED
# left-handed swaps the primary/secondary buttons, so "enabled" makes the
# right button primary.

# --- Trackpad(s): left button primary (default), tap-to-click, natural scroll
# riverctl input "POINTER-NAME-TRACKPAD" left-handed disabled
# riverctl input "POINTER-NAME-TRACKPAD" tap enabled
# riverctl input "POINTER-NAME-TRACKPAD" natural-scroll enabled
# riverctl input "POINTER-NAME-TRACKPAD" scroll-factor 0.75

# --- Mouse/mice: right button primary, custom wheel speed
# riverctl input "POINTER-NAME-MOUSE" left-handed enabled
# riverctl input "POINTER-NAME-MOUSE" scroll-factor 1.0

### Wallpaper (optional) ######################################################
#
# base sets a plain solid colour. To use an image on this host, kill the
# solid swaybg and relaunch with a file:
# pkill -x swaybg; swaybg --mode fill --image "$HOME/Pictures/wallpaper.jpg" &

### Lid switch: turn the internal panel off while the lid is closed #########
#
# LAPTOPS ONLY. Turns the internal output off when the lid closes *and*
# an external monitor is connected (so closing the lid docked won't blank
# your only screen); turns it back on when the lid reopens. Needs the
# river-lid helper from the scripts repo and wlr-randr.
#
# Replace INTERNAL-OUTPUT with the internal panel's name from `wlr-randr`
# (commonly eDP-1). Desktops: leave this commented out.
# run_once river-lid "INTERNAL-OUTPUT"

### Anything else machine-specific goes here #################################
