# Hyprland Wayland desktop

A dynamic-tiling Wayland desktop built around Hyprland's **master/stack**
layout, modelled on the Krohnkite KWin script's "Tile" layout. Intended as a
KDE replacement that works across laptops and workstations, matching the KDE +
Krohnkite setup in `setup-kde` (scripts repo).

Files (all live under this repo's `config/` and map to `~/.config/`):

| Path | Purpose |
|------|---------|
| `config/hypr/hyprland.conf` | Compositor: layout, input, keybinds, look |
| `config/hypr/hypridle.conf` | Idle: dim → lock → DPMS off → suspend |
| `config/hypr/hyprlock.conf` | Lock screen |
| `config/hypr/scripts/toggle-layout.sh` | Master ⇄ dwindle quick toggle |
| `config/hypr/scripts/layout-cycle.sh` | Cycle tile → threecolumn → columns |
| `config/hypr/scripts/lid.sh` | Laptop lid: disable internal panel, conditional suspend |
| `config/hypr/scripts/apply-input.sh` | Auto-classify pointers (mice → right-handed) |
| `config/hypr/scripts/theme.sh` | Apply light/dark theme by time of day |
| `config/hypr/scripts/theme-daemon.sh` | Re-apply theme at each 07:00/19:00 boundary |
| `config/hypr/scripts/launch-fuzzel.sh` | Launch fuzzel with the current theme's colours |
| `config/waybar/config.jsonc` | Bar: workspaces, clocks, tray, battery, net, volume |
| `config/waybar/{style,style-light,common,colors-dark,colors-light}.css` | Bar theme (dark + light) |
| `config/fuzzel/fuzzel.ini` | Launcher (SUPER+Space) |
| `config/swaync/config.json` + `{style,style-light,common,colors-*}.css` | Notifications + control center (dark + light) |

## Installing

Packages, the systemd-logind lid drop-in, and `power-profiles-daemon` are
handled by **`setup-hypr`** in the scripts repo:

    setup-hypr            # install packages + logind drop-in + services
    setup-hypr --no-install   # only (re)apply logind + services

Or as part of a full machine bootstrap, select the Hyprland desktop:

    setup --hypr

The dotfiles here are installed by this repo's `make install`. `setup-hypr`
installs (package names vary by distro; Hyprland is first-class on Arch and may
need a backport/COPR/manual build on Debian/Fedora):

    hyprland hypridle hyprlock xdg-desktop-portal-hyprland
    waybar fuzzel swaync swww
    power-profiles-daemon
    pipewire wireplumber pavucontrol      # volume/sound
    brightnessctl                         # backlight keys + hypridle dimming
    yazi                                  # terminal file manager (SUPER+E)
    network-manager-applet blueman        # network + bluetooth tray applets
    polkit-gnome                          # GUI privilege prompts
    xdg-desktop-portal-gtk glib2          # gsettings + colour-scheme portal
                                          #   (light/dark theming; kitty + GTK)
    a JetBrains Mono Nerd Font            # glyphs in waybar/fuzzel/lock

`yazi` isn't in every distro's default repos; if the package is missing,
`cargo install --locked yazi-fm yazi-cli` installs it.

## Starting the session

Pick "Hyprland" at your display manager, or from a TTY:

    exec Hyprland

## Keybindings

`SUPER` is the modifier (`$mainMod`). Keys match the KDE/Krohnkite setup so the
muscle memory carries over.

### Master/stack (Krohnkite equivalents)

| Keys | Action |
|------|--------|
| `SUPER + \` / `SUPER + /` | Grow / shrink the master area (mfact) |
| `SUPER + Return` | Set focused window as master (swap with master) |
| `SUPER + I` / `SUPER + D` | Add / remove a window from the master area |
| `SUPER + O` / `SUPER + Shift + O` | Cycle master orientation (rotate) |
| `SUPER + J` / `SUPER + K` | Focus next / previous in the stack |
| `SUPER + Shift + J` / `SUPER + Shift + K` | Move window down / up the stack |

### Layouts

Krohnkite cycled Tile / ThreeColumn / Columns / Monocle. Hyprland has no native
ThreeColumn/Columns, so `layout-cycle.sh` approximates them:

| Keys | Action |
|------|--------|
| `SUPER + .` / `SUPER + ,` | Next / previous layout (tile → threecolumn → columns) |
| `SUPER + \`` (backtick) | Monocle (fullscreen state 1 — keeps gaps + bar) |
| `SUPER + Shift + \` | Quick toggle master ⇄ dwindle |
| `SUPER + Shift + F` | True fullscreen (state 0 — covers the bar) |
| `SUPER + F` | Toggle floating |
| `SUPER + R` | Enter **resize** mode (h/j/k/l or arrows; Esc/Enter to exit) |

- `tile` = master, orientation left (master/stack)
- `threecolumn` = master, orientation center (master centred, stack both sides)
- `columns` = dwindle (BSP)

### Apps / session

| Keys | Action |
|------|--------|
| `SUPER + T` | Terminal (kitty) |
| `SUPER + W` | Terminal on workstation |
| `SUPER + G` / `SUPER + H` | Browser 1 / Browser 2 |
| `SUPER + Y` | Music |
| `SUPER + E` | File manager (yazi in a terminal) |
| `SUPER + Space` | Launcher (fuzzel) |
| `SUPER + Backspace` | Close the current window |
| `SUPER + Shift + L` | Lock now (hyprlock) |
| `SUPER + Shift + E` | Exit Hyprland (log out) |
| `SUPER + 1..0` | Switch to workspace 1–10 |
| `SUPER + Shift + 1..0` | Move window to workspace 1–10 |

> `browser1`, `browser2`, `terminal_on_workstation`, and `music` are the same
> helper scripts the KDE setup binds; they live in the scripts repo on `$PATH`.

### Mouse

| Action | Result |
|--------|--------|
| `SUPER + drag left button` | Move window |
| `SUPER + drag right button` | Resize window |

Focus follows the mouse (`follow_mouse = 1`) — no click needed to focus.

## Behaviour notes

- **Dim inactive windows.** `decoration:dim_inactive` with `dim_strength =
  0.15`, matching the KDE "dim inactive" effect (Strength 15).
- **Per-device handedness (auto).** Global default is right-handed so
  **trackpads keep the left button primary**. `apply-input.sh` (autostarted)
  enumerates the pointers at login, classifies each as touchpad or mouse by
  name, and flips **mice** to `left_handed` (right button primary) with a faster
  `scroll_factor` — no device names to hardcode, and the same config works on
  every machine. Re-run it after hotplugging a mouse; override the mouse wheel
  speed with `HYPR_MOUSE_SCROLL_FACTOR`.
- **Laptop lid.** `lid.sh` disables the internal panel on lid close and
  **suspends only when no external display is connected** — a docked laptop
  with the lid shut keeps running on its external screen. The internal panel is
  auto-detected (first eDP/LVDS/DSI output; override with
  `HYPR_INTERNAL_OUTPUT`). `setup-hypr` installs a logind drop-in
  (`HandleLidSwitch=ignore`) so Hyprland is the sole lid handler.
- **Automatic light/dark by time of day.** `theme-daemon.sh` (autostarted)
  applies **light 07:00–19:00 and dark otherwise**, and re-applies at each
  boundary. `theme.sh` drives the whole desktop: it sets the freedesktop
  colour-scheme preference (so **kitty**, via its `*.auto.conf` themes, and
  **GTK** apps follow automatically), relaunches **waybar** and **swaync** with
  the matching stylesheet, sets Hyprland's border colours, and — if you drop
  `~/.config/hypr/wallpaper-light.jpg` / `wallpaper-dark.jpg` — swaps the
  wallpaper. **fuzzel** is themed per-launch by `launch-fuzzel.sh`. Because the
  daemon owns waybar/swaync, they are not started by their own `exec-once`
  lines. Edit `LIGHT_START` / `DARK_START` in `theme.sh` to change the times.
- **Power management is identical on laptops and desktops** — one shared
  `hypridle.conf` (dim → lock → DPMS off → suspend). On a desktop with no
  backlight the dim step is simply a no-op.
- **Multi-machine.** The same configs run everywhere unchanged — input
  handedness and the laptop's internal panel are auto-detected, and Hyprland
  auto-places monitors. Nothing is machine-specific.

## Placeholders

**None required.** Input devices and the internal panel are auto-detected, and
monitors are auto-placed, so the shipped config has no fill-in-the-blanks
anywhere. Two things are optional:

1. **Custom monitor arrangement (optional)** — the catch-all `monitor = ,
   preferred, auto, auto` rule auto-places every output left-to-right, and
   `lid.sh` handles clamshell, so single-monitor, docked, undocked, and
   dual-head all work with no config. For a *specific* layout (fixed
   positions/scale/order), add per-output `monitor = <name>, <mode>, <pos>,
   <scale>` lines to `hyprland.conf` — find names with `hyprctl monitors` /
   `wlr-randr`. (If you prefer a hotplug daemon with declarative profiles,
   kanshi still works; it was dropped from the defaults to keep zero
   placeholders.)

2. **Wallpaper image (optional)** — `config/hypr/hyprland.conf` (`swww img ...`) and
   `config/hypr/hyprlock.conf` (`background { path = ... }`). Optionally add
   `~/.config/hypr/wallpaper-light.jpg` and `wallpaper-dark.jpg` for `theme.sh`
   to swap the wallpaper with the light/dark theme.

3. **Timezones (optional)** — the waybar clocks use `Europe/London` and
   `America/Los_Angeles` plus system local time; edit
   `config/waybar/config.jsonc` if you want different zones.

## Design choices

- **swaync over mako.** You asked for a control center; mako is a lighter
  notification daemon with no GUI. swaync gives the notification history +
  Do-Not-Disturb control center. mako is the simpler drop-in if you drop the
  center.
- **swww over swaybg.** swww runs a daemon so you can swap wallpapers/get
  transitions live. For a purely static wallpaper, replace the two `swww`
  `exec-once` lines with `exec-once = swaybg -i <file> -m fill`.
- **Hyprland auto-placement over kanshi.** Custom monitor *positioning*
  inherently needs output names (no auto-detection for "which monitor goes
  left"), which meant fill-in placeholders. Since Hyprland's built-in
  catch-all rule auto-places outputs and `lid.sh` handles clamshell, dropping
  kanshi from the defaults gets the desktop to **zero placeholders** while
  still working everywhere. Add `monitor=` rules (or re-add kanshi) if you want
  a pinned layout.
