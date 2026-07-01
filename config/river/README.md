# river Wayland desktop

A traditional, KDE-like **dynamic-tiling** Wayland desktop built on the
[river](https://codeberg.org/river/river) compositor. It reproduces the
feel of the KDE + [Krohnkite](https://github.com/anametologin/Krohnkite)
setup configured by `scripts/setup-kde`: master/stack tiling, focus
follows mouse, tags as virtual desktops, and the same launch keybinds — so
muscle memory carries over.

It is structured as a **shared base plus per-host overrides** so the exact
same checkout runs on several machines with different displays and input
devices, degrading gracefully on a machine you haven't configured yet.

## What's here

Everything installs via `confinst` (symlinks `~/conf/config/*` into
`~/.config/*`):

| Path | Purpose |
|------|---------|
| `river/init` | Entry point. **Identical on every machine.** Sources `base`, then `hosts/<hostname>.sh` if present. |
| `river/base` | Shared config: keybinds, tags, theme, layout, autostart. Host-agnostic. |
| `river/hosts/<hostname>.sh` | Per-host input devices, handedness, scroll factor, lid watcher. |
| `waybar/` | Bar: tags, tray, network, volume, battery, **three clocks** (SF / London / local). |
| `fuzzel/fuzzel.ini` | Launcher (Super+Space). |
| `swaync/` | Notifications + control centre. |
| `swayidle/config` | Idle dim → lock → screen-off. |
| `swaylock/config` | Lock screen. |
| `kanshi/config` + `kanshi/hosts/<hostname>.conf` | Display hotplug / multi-monitor profiles. |

Helpers in the **scripts** repo:

- `scripts/setup-river` — installs packages and system config (run once per machine).
- `scripts/river-lid` — turns the internal panel off when the lid closes while docked.
- `scripts/river-theme` — time-of-day light/dark theming (see below).

## Packages

`setup-river` installs these (Debian/Ubuntu and Fedora names handled):

**Core:** `river-classic` (the monolithic river that bundles `rivertile`;
this config uses the `riverctl` + `rivertile` model, which upstream
`river` 0.4+ dropped — `setup-river` prefers `river-classic` and warns if
`rivertile` is missing), `waybar`, `sway-notification-center`/`swaync`,
`fuzzel`, `kanshi`, `swayidle`, `swaylock`, `swaybg`.

**Helpers used by keybinds / autostart:** `wlopm` (idle DPMS — may need
building from [sr.ht](https://git.sr.ht/~leon_plickat/wlopm)), `wlr-randr`,
`wl-clipboard`, `brightnessctl`, `playerctl`, `pavucontrol`,
`network-manager-gnome`/`nm-connection-editor`, `grim`, `slurp`.

**System:** `power-profiles-daemon`, a polkit agent (`polkit-kde-agent-1`),
`xdg-desktop-portal-wlr` + `xdg-desktop-portal-gtk`, `qt6-wayland`, and the
Ubuntu Mono font (also installed by `scripts/setup`).

Audio keybinds use `wpctl` from PipeWire/WirePlumber (already part of the
base `scripts/setup`).

## Starting a river session

1. Install packages + system config:  `setup-river`
2. Install dotfiles:  `confinst`
3. Log out and choose **River** at your display manager, **or** from a
   TTY run:  `river`

`river` reads `~/.config/river/init`, which sources `base` then your
per-host file.

## Per-host setup (adding a new machine)

The base config works immediately with sane defaults. To tailor a machine:

1. **Run once:**  `setup-river`  (installs packages, the logind lid
   drop-in, enables power-profiles-daemon, adds the session entry).

2. **Input devices** — in a river session, list device names:
   ```
   riverctl list-inputs
   ```
   Copy the template and fill in the names:
   ```
   cp ~/.config/river/hosts/examples/template.sh ~/.config/river/hosts/$(hostname -s).sh
   ```
   Handedness rule used here: **trackpads** keep the left button primary
   (`left-handed disabled`); **mice** use the right button primary
   (`left-handed enabled`). Set `scroll-factor` per device too.

3. **Displays** — list output names/modes:
   ```
   wlr-randr
   ```
   Copy the kanshi template and fill in the outputs:
   ```
   cp ~/.config/kanshi/hosts/examples/template.conf ~/.config/kanshi/hosts/$(hostname -s).conf
   ```
   External monitors are enabled automatically on hotplug (kanshi switches
   to the matching profile).

4. **Laptop lid** — in your host `.sh`, enable the watcher with the
   internal output name (from `wlr-randr`, usually `eDP-1`):
   ```
   run_once river-lid eDP-1
   ```
   This turns the internal panel off when the lid closes **and** an
   external is connected; `setup-river`'s logind drop-in stops the machine
   suspending in that case.

Reload after edits by restarting river (Super+Shift+E, then log back in),
or re-run `riverctl` commands ad hoc.

## Placeholders to fill in (per host)

| File | Placeholder | Get it from |
|------|-------------|-------------|
| `river/hosts/<host>.sh` | `pointer-...-TRACKPAD`, `pointer-...-MOUSE` device names | `riverctl list-inputs` |
| `river/hosts/<host>.sh` | internal output for `river-lid` (e.g. `eDP-1`) | `wlr-randr` |
| `kanshi/hosts/<host>.conf` | output names (`eDP-1`, `HDMI-A-1`, `DP-1`, …) and modes | `wlr-randr` |

The `template` and `example-laptop` / `example-desktop` files live in
`hosts/examples/` in both the river and kanshi trees. They are illustrative
only and are **never loaded**: river sources `hosts/<hostname>.sh` (an
example never matches a real hostname), and kanshi's `hosts/*.conf` glob
doesn't descend into `examples/`. Your real per-host files go directly in
`hosts/`.

## Keybindings

Super is the modifier. These mirror `setup-kde` where possible.

| Key | Action |
|-----|--------|
| Super+T / G / H / W / Y | terminal / browser1 / browser2 / terminal_on_workstation / music |
| Super+Space | launcher (fuzzel, themed) |
| Super+Shift+T | toggle light/dark theme |
| Super+Backspace | close window |
| Super+Return | zoom (swap with master) |
| Super+J / K | focus next / previous |
| Super+Shift+J / K | swap next / previous |
| Super+` or Super+F | monocle / fullscreen toggle |
| Super+= / − (or \ /) | grow / shrink master ratio |
| Super+] / [ | more / fewer master windows |
| Super+, / . | master on left / top |
| Super+O / Super+Shift+O | focus / send to next output |
| Super+1..9 | focus tag N |
| Super+Shift+1..9 | move window to tag N |
| Super+Ctrl+1..9 | toggle tag N in view |
| Super+Ctrl+L | lock screen (themed) |
| Print | screenshot whole output → file |
| Super+Shift+S | screenshot region → clipboard |
| Super+Print | screenshot region → file |
| Super+Shift+E | exit river |
| Super+drag / Super+right-drag | move / resize window |

Screenshots use `grim`/`slurp`/`wl-copy` and save to
`~/Pictures/Screenshots/`.

## Layouts

Default generator is **rivertile** (master/stack, like Krohnkite's *Tile*),
with **no gaps** and thin borders. Monocle is the fullscreen toggle.

rivertile doesn't do Krohnkite's *ThreeColumn* / *Columns* / *spiral*. If
you want those, `base` documents drop-in alternatives —
[stacktile](https://git.sr.ht/~novakane/stacktile) (closest),
[filtile](https://gitlab.com/gwund/filtile),
[river-luatile](https://github.com/MTeaHead/river-luatile) — and how to
wire one while keeping rivertile the default.

## Light/dark theme by time of day

`river-theme` switches the whole desktop between a **light** palette
(classic grey, blue accent) from **07:00–19:00** and a **dark** palette
(the repo's amber-on-charcoal) outside those hours. It themes river
borders, Waybar, swaync, fuzzel and swaylock together, so everything stays
consistent.

How it fits together:

- `base` runs `river-theme apply auto` synchronously at startup (before
  Waybar), then starts `river-theme watch`, which re-applies at each 07:00
  / 19:00 boundary.
- Waybar and swaync `@import "theme.css"`, a small palette file
  `river-theme` regenerates and live-reloads on each switch. If
  `river-theme` isn't installed, `base` writes a dark-mode `theme.css`
  fallback so the CSS still resolves.
- fuzzel (`river-theme menu`) and swaylock (`river-theme lock`) are
  launched through `river-theme`, which passes the current palette as
  colour flags — so a single static `fuzzel.ini` / `swaylock/config`
  serves both themes.
- **Super+Shift+T** toggles light/dark manually (until the next scheduled
  switch). `river-theme mode` prints the current mode.

Change the hours by editing `DAY_START` / `DAY_END` in `scripts/river-theme`;
change the palettes in its `set_palette` function.

## Known limitation: dimming inactive windows

river has **no compositor effects** — it can't round window corners, blur,
or dim inactive window *contents* (unlike KDE's Dim Inactive). The closest
substitute, used here, is a strong **border-colour contrast**: the focused
window gets a bright accent border, unfocused windows a dim grey one. UI
chrome (Waybar, fuzzel, swaync) is lightly rounded via CSS, which river
*can* honour because those apps draw their own surfaces.
