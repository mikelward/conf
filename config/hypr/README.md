# Hyprland Wayland desktop

A dynamic-tiling Wayland desktop for **Hyprland 0.56+**, configured in Lua
(`hyprland.lua`; Hyprland no longer reads `hyprland.conf`). Tiling comes from
the [tide](https://github.com/mikelward/tide) layout when it is
installed (tile, three-column, two columns + stack and monocle, per
workspace), and from Hyprland's master layout otherwise. The keys, look and
focus rules follow the tide spec (SPEC.md §6 and §14). Intended as a
KDE replacement that works across laptops and workstations; KDE Plasma stays
installed as the fallback.

Files (all live under this repo's `config/` and map to `~/.config/`):

| Path | Purpose |
|------|---------|
| `config/hypr/hyprland.lua` | Compositor: layout, input, keybinds, look, lid, window rules |
| `config/hypr/hyprland_test.lua` | Tests for `hyprland.lua` against a stub of Hyprland's Lua API |
| `config/hypr/hyprland.local.lua.template` | Per-machine override template (copy to `~/.config/hypr/hyprland.local.lua`) |
| `config/hypr/hypridle.conf` | Idle: dim → lock → DPMS off → suspend |
| `config/hypr/hyprlock.conf` | Lock screen |
| `config/hypr/scripts/apply-input.sh` | Auto-classify pointers (mice → right-handed) |
| `config/hypr/scripts/theme.sh` | Apply light/dark theme by time of day |
| `config/hypr/scripts/theme-daemon.sh` | Re-apply theme at each 07:00/19:00 boundary |
| `config/hypr/scripts/launch-fuzzel.sh` | Launch fuzzel with the current theme's colours |
| `config/waybar/config.jsonc` | Bar: workspaces, clocks, tray, battery, net, volume |
| `config/waybar/{style,style-light,common,colors-dark,colors-light}.css` | Bar theme (dark + light) |
| `config/fuzzel/fuzzel.ini` | Launcher (SUPER+Space) |
| `config/swaync/config.json` + `{style,style-light,common,colors-*}.css` | Notifications + control center (dark + light) |
| `config/uwsm/env` + `env-hyprland` | Environment for the optional uwsm session |
| `config/environment.d/env.conf` | Symlink to `env` so systemd user services see the shared PATH |

The launcher keybinds run their helper scripts (`browser1`, `home`, `irc`, ...)
through `runenv` from the scripts repo, which sources `~/.env` (the canonical
user PATH dirs, from this repo — including `~/scripts.local` for per-machine
scripts) and `~/.env.local` (other per-machine additions, e.g.
`PATH=$HOME/scripts.work:$PATH`) before exec'ing, so binds see the
login-shell PATH (a display-manager or uwsm session never runs
`.profile`/`.shrc` itself).

## Installing

The dotfiles here are installed by this repo's `make install`, and the
packages by `setup` (scripts repo). The tide layout is optional: its
repo's `make install` puts it in `~/.config/hypr/tide/`, and
`hyprland.lua` picks it up on the next reload.

The packages `setup` installs (names vary by distro; Hyprland is first-class on
Arch, `setup` auto-enables the `lionheartp/Hyprland` COPR on Fedora, and on
Debian/Ubuntu the hypr* tools may need a backport or manual build):

    hyprland (0.56+) hypridle hyprlock xdg-desktop-portal-hyprland
    waybar fuzzel swaync swww
    power-profiles-daemon
    pipewire wireplumber pavucontrol      # volume/sound
    brightnessctl                         # backlight keys + hypridle dimming
    grim slurp wl-clipboard jq            # screenshots (Print) → clipboard
    libnotify (libnotify-bin on Debian)   # notify-send: "Screenshot copied"
    playerctl                             # media play/pause/next/prev keys
    gnome-calculator                      # XF86Calculator key
    yazi                                  # terminal file manager (SUPER+E)
    network-manager-applet blueman        # network + bluetooth tray applets
    polkit-gnome                          # GUI privilege prompts
    xdg-desktop-portal-gtk glib2          # gsettings + colour-scheme portal
                                          #   (light/dark theming; kitty + GTK)
    a JetBrains Mono Nerd Font            # glyphs in waybar/fuzzel/lock

The screenshot tools are small local packages: no network, no cost, and no
work until Print is pressed. Without `notify-send` a shot still reaches the
clipboard, but its "Screenshot copied" and any error message go nowhere, so
Print looks like it did nothing; without `jq`, Alt+Print reports a failure
and takes no shot.

`yazi` isn't in every distro's default repos; if the package is missing,
`cargo install --locked yazi-fm yazi-cli` installs it.

## Starting the session

Pick "Hyprland" at your display manager, or from a TTY:

    exec Hyprland

### The tide session

`setup --tide` (scripts repo) installs the tide session, which
appears at the greeter as "tide". `hyprland.lua` recognizes it by
`XDG_CURRENT_DESKTOP=tide:Hyprland` and changes two things there:

- **Autostart is `uwsm finalize` alone.** tide's units run the rest:
  the bar and notifications (through the theme daemon), the wallpaper, the
  polkit agent, `apply-input.sh`, and hypridle. A plain Hyprland login keeps
  the autostart list in `hyprland.lua`.
- **App keys and the launcher go through `tide launch`**, so the app's
  first window takes focus past tide's focus guard, and the app runs
  outside the shell's unit. Keys bound to a `runenv` wrapper grant the
  first window of any app (`--app '*'`), since their window class isn't
  known here.
- **A command run from a terminal grants its first window focus too.**
  bash and zsh (`precommand`), fish (`fish_preexec`), nushell
  (`pre_execution`) and Elvish (`command-started`) hand each command line
  to tide's `tide-grant` with the shell's pid, so
  `nautilus .` from kitty opens focused. The grant names the shell's pid,
  so a window from any of the shell's descendants can use it (the
  command's own processes, or a background job it started earlier), and
  the app of the line's first command, so an app that was already running
  (`firefox URL`) can too. In a tide session it costs about 3 ms per
  command, plus a `hyprctl` round trip; elsewhere it's never called.

### Optional: uwsm (systemd-managed session)

[uwsm](https://github.com/Vladimir-csp/uwsm) can instead launch Hyprland as a
**systemd user session**, which propagates the environment to systemd user
services and D-Bus activation (better xdg-desktop-portal, tray, and a clean
logout). `setup` installs it, but enabling it is **opt-in** — it changes
nothing about how you currently log in until you select the uwsm session:

- **Display manager:** with uwsm installed, pick the "Hyprland (uwsm-managed)"
  session at the greeter. If your uwsm/Hyprland packages didn't add that entry,
  create `/usr/share/wayland-sessions/hyprland-uwsm.desktop` (needs root):

      [Desktop Entry]
      Name=Hyprland (uwsm-managed)
      Comment=Hyprland launched via uwsm (systemd user session)
      Exec=uwsm start hyprland.desktop
      Type=Application
      DesktopNames=Hyprland

- **TTY:** `uwsm start hyprland.desktop` (instead of `exec Hyprland`; the
  argument is the Hyprland desktop-entry ID, or use `uwsm start -- Hyprland`).

The Wayland/toolkit environment is provided for uwsm in **`config/uwsm/env`**
(general vars) and **`config/uwsm/env-hyprland`** (`HYPR*` vars). uwsm sources
these as shell, so they use `export KEY=VAL` with values quoted where needed
(e.g. `export QT_QPA_PLATFORM='wayland;xcb'`). They mirror the `hl.env` calls in
`hyprland.lua` — which still apply to a plain, non-uwsm session — so both
launch paths get the same environment (edit both if you change a var).

> **gdm3 / PAM note:** on some setups (e.g. a work laptop on gdm3) the
> session/PAM wiring is picky — verify login, keyring unlock, and `hyprlock`
> auth still work *before* making uwsm your default. Nothing changes until you
> choose the uwsm session, so it's safe to try and switch back.

## Keybindings

`SUPER` is the modifier. `SUPER+<letter>` launchers mirror your `xbindkeysrc`;
the tiling controls sit on symbol keys so they don't take the letters. The
table is the tide spec's (SPEC.md §6.6).

### Apps / session

| Keys | Action |
|------|--------|
| `SUPER + T` | Terminal (kitty) |
| `SUPER + W` | Terminal on workstation |
| `SUPER + G` / `SUPER + F` | Browser 1 / Browser 2 |
| `SUPER + Shift + G` | Browser 3 |
| `SUPER + E` | File manager (yazi in a terminal) |
| `SUPER + B` / `SUPER + Shift + B` | Bluetooth connect / audio profile |
| `SUPER + C` / `SUPER + Shift + C` | Calendar / Chat |
| `SUPER + H` | Home |
| `SUPER + I` | IRC |
| `SUPER + M` | Meet |
| `SUPER + N` | Notepad |
| `SUPER + R` | Remote desktop |
| `SUPER + Y` | YouTube Music |
| `SUPER + Space` | Launcher (tide's, or fuzzel without the tide shell) |
| `SUPER + Shift + N` | Notification center (swaync) |
| `SUPER + Backspace` | Close the current window |
| `SUPER + L` | Lock (hyprlock) |
| `SUPER + Shift + E` | Exit Hyprland (log out) |
| `Print` / `Alt + Print` / `Shift + Print`, `SUPER + Print` | Screenshot: screen / window / region → clipboard |
| `XF86AudioMicMute`, `SUPER + Shift + M` | Toggle microphone mute |
| `XF86Audio*` / `XF86MonBrightness*` | Volume, play/pause/next/prev, brightness |

> Launchers run the helper scripts of the same name from the scripts repo (on
> `$PATH`). `SUPER + D` (code) and `SUPER + S` (secureshell) are **left unbound**
> — those scripts aren't in this repo; add them in
> `~/.config/hypr/hyprland.local.lua`.

### Workspaces

| Keys | Action |
|------|--------|
| `SUPER + 1..9` / `SUPER + Shift + 1..9` | Go to / send window to workspace 1–9 |
| `SUPER + Left` / `SUPER + Right`, `SUPER + PgUp` / `SUPER + PgDn` | Previous / next workspace |
| `SUPER + Shift + Left` / `SUPER + Shift + Right` | Move the window to the previous / next workspace |
| `SUPER + Tab`, `SUPER + Home` | Focus the most recent urgent window, or the last one (both on trial) |

### Layouts and windows

| Keys | Action |
|------|--------|
| `SUPER + J` / `SUPER + K` | Focus next / previous in the stack |
| `SUPER + Shift + J` / `SUPER + Shift + K` | Move window down / up the stack |
| `SUPER + Return` | Swap the focused window with the master |
| `SUPER + \` / `SUPER + /` | Grow / shrink the master area (mfact ±0.025) |
| `SUPER + =` / `SUPER + -` | Add / remove a master |
| `SUPER + .` / `SUPER + ,` | Next / previous layout |
| `SUPER + \`` (backtick) | Toggle monocle |
| `SUPER + Up` / `SUPER + Shift + Up` / `SUPER + Down` | Maximize (bar stays) / fullscreen / restore |
| `SUPER + Shift + F` / `SUPER + Insert` | Toggle floating |
| `SUPER + Shift + R` | **Resize** mode (h/j/k/l or arrows; Esc/Enter to exit) |

Without the tide layout, the layout keys drive Hyprland's master layout
instead: `.` / `,` rotate the master orientation (center is the three-column
shape) and `` ` `` maximizes the window.

### Mouse

| Action | Result |
|--------|--------|
| `SUPER + drag left button` | Move window |
| `SUPER + drag right button` | Resize window |
| `SUPER + middle click` | Maximize the window; click again to put it back in its tile |

Focus follows the mouse when it crosses into a window, and never warps the
pointer. An app that asks for focus is marked urgent instead of taking it
(`SUPER + Tab` goes there).

## Behaviour notes

- **Keyboard: US Dvorak, Caps Lock as Compose, Menu as Super**
  (`kb_variant = dvorak`, `kb_options = compose:caps,altwin:menu_win`). Caps
  Lock matches `setup`'s `configure_keyboard`; Menu as a second Super is what
  `xmodmaprc` did under X11, on trial here. espanso's `keyboard_layout` names
  the same options, since it types through them.
- **The focus cue is the dim alone.** No gaps and no borders;
  `dim_inactive` with `dim_strength = 0.07`: Hyprland's dim looks stronger
  than KDE's "dim inactive" effect at the same number, so 0.15 was too much.
  A lone window, video and picture-in-picture never dim.
- **Dialogs float, centered**: modal windows, pavucontrol,
  nm-connection-editor, blueman-manager, portal file choosers, and "Open
  File" / "Save File" / "Save As" titles. Picture-in-picture floats pinned in
  the bottom-right corner.
- **Per-device handedness (auto).** Global default is right-handed so
  **trackpads keep the left button primary**. `apply-input.sh` (autostarted)
  enumerates the pointers at login, classifies each as touchpad or mouse by
  name, and flips **mice** to `left_handed` (right button primary) with a faster
  `scroll_factor` — no device names to hardcode, and the same config works on
  every machine. It configures each mouse with `hyprctl eval` and an
  `hl.device()` call, since the Lua config has no `hyprctl keyword`. A config
  reload resets devices, so `hyprland.lua` runs it again after each one.
  Re-run it after hotplugging a mouse; override the mouse wheel speed
  (default 3) with `HYPR_MOUSE_SCROLL_FACTOR` in `~/.env.local`: `hyprland.lua`
  runs it through `runenv`, which sources that file, and in the tide
  session `tide.service`'s run at login sees it once `~/.env.local` is
  linked into `environment.d` as `~/.env` describes. Since it runs after
  `hyprland.local.lua`, an `hl.device()` there can't change a mouse's
  handedness or wheel speed.
- **Laptop lid.** logind owns suspend with its defaults
  (`HandleLidSwitch=suspend`, `HandleLidSwitchDocked=ignore`), and hypridle
  locks first. `hyprland.lua` handles only the docked case: closing the lid
  with an external display attached disables the internal panel (Hyprland
  moves its workspaces over), and opening it re-enables the panel and moves
  those workspaces back, even across a config reload in between. The panel
  is auto-detected (first eDP/LVDS/DSI
  output; override with `HYPR_INTERNAL_OUTPUT`). If an old
  `HandleLidSwitch=ignore` logind drop-in from the retired `setup-hypr` is
  still installed, remove it, or an undocked lid close won't suspend.
- **Automatic light/dark by time of day.** `theme-daemon.sh` (autostarted)
  applies **light 07:00–19:00 and dark otherwise**, and re-applies at each
  boundary. `theme.sh` drives the whole desktop: it sets the freedesktop
  colour-scheme preference (so **kitty**, via its `*.auto.conf` themes, and
  **GTK** apps follow automatically), relaunches **waybar** and **swaync** with
  the matching stylesheet, and — if you drop
  `~/.config/hypr/wallpaper-light.jpg` / `wallpaper-dark.jpg` — swaps the
  wallpaper. **fuzzel** is themed per-launch by `launch-fuzzel.sh`. Because the
  daemon owns waybar/swaync, they are not started by their own autostart
  lines. Edit `LIGHT_START` / `DARK_START` in `theme.sh` to change the times.
- **Power management is identical on laptops and desktops** — one shared
  `hypridle.conf` (dim → lock → DPMS off → suspend). On a desktop with no
  backlight the dim step is simply a no-op.
- **Multi-machine.** The same configs run everywhere unchanged — input
  handedness and the laptop's internal panel are auto-detected, and Hyprland
  auto-places monitors. Nothing is machine-specific. When a machine *does*
  need something of its own (pinned monitor layout, the unbound `SUPER+D`/
  `SUPER+S` launchers, device tweaks), it goes in
  **`~/.config/hypr/hyprland.local.lua`** — the same name plus `.local`,
  like `.shrc.local` — which `hyprland.lua` loads last so it overrides the
  shared defaults. (Binds are the exception: Hyprland runs every bind on a
  key, so rebind an already-bound key with `hl.unbind` first — see the
  template.) Copy `hyprland.local.lua.template` to start one; it is
  machine-local and never committed. A missing file is fine. An error in
  it shows as a notification: a syntax error applies none of the file, and
  a runtime error stops it there, after the calls before it have applied.

## Placeholders

**None required.** Input devices and the internal panel are auto-detected, and
monitors are auto-placed, so the shipped config has no fill-in-the-blanks
anywhere. Two things are optional:

1. **Custom monitor arrangement (optional)** — the catch-all monitor rule
   auto-places every output left-to-right, and the lid binds handle
   clamshell, so single-monitor, docked, undocked, and dual-head all work
   with no config. For a *specific* layout (fixed positions/scale/order), add
   `hl.monitor({ output = ..., mode = ..., position = ..., scale = ... })`
   calls to `~/.config/hypr/hyprland.local.lua` — find names with
   `hyprctl monitors` / `wlr-randr`. (If you prefer a hotplug daemon with
   declarative profiles,
   kanshi still works; it was dropped from the defaults to keep zero
   placeholders.)

2. **Wallpaper image (optional)** — `config/hypr/hyprland.lua` (`swww img ...`) and
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
  autostart lines with `hl.exec_cmd("swaybg -i <file> -m fill")`.
- **Hyprland auto-placement over kanshi.** Custom monitor *positioning*
  inherently needs output names (no auto-detection for "which monitor goes
  left"), which meant fill-in placeholders. Since Hyprland's built-in
  catch-all rule auto-places outputs and the lid binds handle clamshell,
  dropping kanshi from the defaults gets the desktop to **zero placeholders**
  while still working everywhere. Add `hl.monitor` rules (or re-add kanshi) if you want
  a pinned layout.
