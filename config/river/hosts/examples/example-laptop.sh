# river per-host override -- EXAMPLE LAPTOP. Illustrative only; it will
# never load on its own (no machine is named "example-laptop"). Copy to
# hosts/<your-hostname>.sh and replace the PLACEHOLDER device names.
#
# Get device names inside a river session with:  riverctl list-inputs
# Get output names with:                          wlr-randr

### Input ####################################################################

# Built-in trackpad: left button primary (default handedness), tap-to-
# click, natural scrolling, slightly slower wheel.
riverctl input "pointer-PLACEHOLDER-TRACKPAD" left-handed disabled
riverctl input "pointer-PLACEHOLDER-TRACKPAD" tap enabled
riverctl input "pointer-PLACEHOLDER-TRACKPAD" natural-scroll enabled
riverctl input "pointer-PLACEHOLDER-TRACKPAD" scroll-factor 0.75

# External USB mouse used when docked: RIGHT button primary (left-handed
# enabled swaps the buttons), default wheel speed.
riverctl input "pointer-PLACEHOLDER-MOUSE" left-handed enabled
riverctl input "pointer-PLACEHOLDER-MOUSE" scroll-factor 1.0

### Lid switch ###############################################################

# Turn the internal panel off while the lid is closed and an external
# monitor is attached; restore it on reopen. eDP-1 is the usual internal
# output name -- confirm with wlr-randr.
run_once river-lid "eDP-1"

### Wallpaper (optional) #####################################################
# pkill -x swaybg; swaybg --mode fill --image "$HOME/Pictures/wallpaper.jpg" &
