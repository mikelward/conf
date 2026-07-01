# river per-host override -- EXAMPLE DESKTOP. Illustrative only; it will
# never load on its own (no machine is named "example-desktop"). Copy to
# hosts/<your-hostname>.sh and replace the PLACEHOLDER device names.
#
# Get device names inside a river session with:  riverctl list-inputs
# Get output names with:                          wlr-randr

### Input ####################################################################

# Desktop mouse: RIGHT button primary (left-handed enabled swaps the
# buttons). Faster wheel for a big monitor.
riverctl input "pointer-PLACEHOLDER-MOUSE" left-handed enabled
riverctl input "pointer-PLACEHOLDER-MOUSE" scroll-factor 1.25

# No trackpad and no lid on a desktop, so no handedness/lid handling here.
# Output arrangement lives in ~/.config/kanshi/hosts/<hostname>.conf.

### Wallpaper (optional) #####################################################
# pkill -x swaybg; swaybg --mode fill --image "$HOME/Pictures/wallpaper.jpg" &
