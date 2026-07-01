# Hyprland Wayland desktop

A dynamic-tiling Wayland desktop built around Hyprland's **master/stack**
layout, modelled on the Krohnkite KWin script's "Tile" layout. Intended as a
KDE replacement that works across laptops and workstations.

Files (all live under this repo's `config/` and map to `~/.config/`):

| Path | Purpose |
|------|---------|
| `config/hypr/hyprland.conf` | Compositor: layout, input, keybinds, look |
| `config/hypr/hypridle.conf` | Idle: dim → lock → DPMS off → suspend |
| `config/hypr/hyprlock.conf` | Lock screen |
| `config/hypr/scripts/toggle-layout.sh` | Master ⇄ dwindle toggle |
| `config/waybar/config.jsonc` | Bar: workspaces, clocks, tray, battery |
| `config/waybar/style.css` | Bar theme |
| `config/fuzzel/fuzzel.ini` | Launcher (SUPER+Space) |
| `config/swaync/config.json` + `style.css` | Notifications + control center |
| `config/kanshi/config` | Display hotplug profiles |

## Packages to install

Core compositor + session:

    hyprland hypridle hyprlock xdg-desktop-portal-hyprland

Bar, launcher, notifications, wallpaper, display hotplug:

    waybar fuzzel swaync swww kanshi

Power, audio, backlight, and helpers used by the keybinds/modules:

    power-profiles-daemon
    wireplumber pavucontrol   # wpctl volume keys + audio module
    brightnessctl             # backlight keys + hypridle dimming
    network-manager           # nm-connection-editor for the network module

Fonts (the configs reference a Nerd Font for glyphs):

    ttf-jetbrains-mono-nerd   # or any "JetBrainsMono Nerd Font" package

> Package names above are Arch-style; translate to your distro. On Debian/
> Ubuntu several of these (hyprland, hypridle, hyprlock, swaync, swww) may
> need a backport, a PPA, or a manual build.

Enable the power-profiles daemon (it's a system service, not started by
Hyprland):

    systemctl enable --now power-profiles-daemon

## Starting the session

If you use a Wayland display manager (SDDM, greetd/tuigreet, ly), Hyprland
installs a `hyprland.desktop` session entry — just pick "Hyprland" at login.

To start from a TTY instead, add to your shell profile (or run manually):

    exec Hyprland

## Keybindings

`SUPER` is the modifier (`$mainMod`).

### Master/stack (Krohnkite equivalents)

| Keys | Action |
|------|--------|
| `SUPER + H` / `SUPER + L` | Shrink / grow the master area (mfact) |
| `SUPER + I` / `SUPER + D` | Add / remove a window from the master area |
| `SUPER + Shift + Return` | Swap focused window with master |
| `SUPER + O` / `SUPER + Shift + O` | Cycle master orientation (rotate) |
| `SUPER + J` / `SUPER + K` | Focus next / previous in the stack |
| `SUPER + Shift + J` / `SUPER + Shift + K` | Move window down / up the stack |

### Layout / window

| Keys | Action |
|------|--------|
| `SUPER + Backslash` | Toggle master ⇄ dwindle layout |
| `SUPER + M` | Monocle (fullscreen state 1 — keeps gaps + bar) |
| `SUPER + Shift + F` | True fullscreen (state 0 — covers the bar) |
| `SUPER + F` | Toggle floating |
| `SUPER + Q` | Close the current window |
| `SUPER + R` | Enter **resize** mode (h/j/k/l or arrows; Esc/Enter to exit) |

### Session / apps

| Keys | Action |
|------|--------|
| `SUPER + Return` | Terminal (kitty) |
| `SUPER + Space` | Launcher (fuzzel) |
| `SUPER + Shift + L` | Lock now (hyprlock) |
| `SUPER + Shift + E` | Exit Hyprland (log out) |
| `SUPER + 1..0` | Switch to workspace 1–10 |
| `SUPER + Shift + 1..0` | Move window to workspace 1–10 |

### Mouse

| Action | Result |
|--------|--------|
| `SUPER + drag left button` | Move window |
| `SUPER + drag right button` | Resize window |

Focus follows the mouse (`follow_mouse = 1`) — no click needed to focus.

## Placeholders you must fill in

Everything below is marked `REPLACE-ME` / `PLACEHOLDER` in the files.

1. **Pointer device names** — `config/hypr/hyprland.conf`, the two `device {}`
   blocks. Run `hyprctl devices` and copy each pointer's exact `name` (lower
   case, spaces → hyphens). Set `left_handed` and `scroll_factor` per device.

2. **Monitor / output names** — `config/kanshi/config`. Run
   `hyprctl monitors` (see the `Monitor <NAME>` lines) or `wlr-randr`. Replace
   the `REPLACE-ME-eDP-1` / `REPLACE-ME-DP-1` / `REPLACE-ME-DP-2` names, and
   adjust each output's `mode`, `position`, and `scale`. Delete profiles you
   don't need (e.g. `workstation` on a laptop-only setup). kanshi owns
   per-output layout; Hyprland's own `monitor=` line is left as a `preferred,
   auto` catch-all so the two don't conflict.

3. **Wallpaper image** — `config/hypr/hyprland.conf` (`swww img ...`) and
   `config/hypr/hyprlock.conf` (`background { path = ... }`). Point both at a
   real image file.

4. **Timezones (optional)** — the waybar clocks use `Europe/London` and
   `America/Los_Angeles` plus your system local time. Edit
   `config/waybar/config.jsonc` (`clock#london`, `clock#sf`) if you want
   different zones.

## Design choices

- **swaync over mako.** You asked for a control center; mako is a lighter
  notification daemon with no GUI. swaync gives the notification history +
  Do-Not-Disturb control center you wanted (toggleable, themable). If you ever
  decide you don't need the center, mako is the simpler drop-in.
- **swww over swaybg.** swww runs a daemon so you can swap wallpapers and get
  transitions live. For a purely static wallpaper `swaybg -i <file>` is
  simpler and one fewer moving part — replace the two `swww` `exec-once` lines
  with `exec-once = swaybg -i <file> -m fill` if you prefer.
- **kanshi for hotplug** rather than Hyprland's built-in `monitor=` rules, so
  docked/undocked/clamshell/workstation profiles apply automatically and
  identically on every machine.
