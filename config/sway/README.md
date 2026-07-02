# Sway Wayland desktop

A dynamic-tiling Wayland desktop built on **Sway** (i3-style), intended as a
KDE replacement across laptops and workstations. It is the traditional/flat
sibling of the Hyprland build in `config/hypr` and **shares** its launcher
(fuzzel), bar (waybar), notifications (swaync), colour scheme, keybinds, and
time-based light/dark theming — only the compositor config, dynamic-tiling
helper, and idle/lock stack are Sway-specific.

## Dynamic tiling: what you get (and don't)

Dynamic splits come from [`autotiling`](https://github.com/nwg-piotr/autotiling)
(autostarted from the Sway config): each new window splits the focused one
along its **longer** side, giving BSP/**dwindle-style** tiling like Hyprland's
`dwindle` layout. This is **NOT** Krohnkite-style master/stack — Sway cannot
do a true master/stack layout, so there are no mfact/add-master keybinds
here; the Hyprland build is the one that replicates Krohnkite's Tile layout.
Manual overrides (split direction, monocle, floating) are on keybinds below.

## Files

| Path | Purpose |
|------|---------|
| `config/sway/config` | Compositor: layout, input, keybinds, autostart (identical on every machine) |
| `config/sway/config.local.template` | Per-host override template (copy to `~/.config/sway/config.local`) |
| `config/sway/config.local.example-laptop` | Example per-host file: docking laptop |
| `config/sway/config.local.example-desktop` | Example per-host file: dual-head desktop (no suspend) |
| `config/sway/scripts/lid.sh` | Laptop lid: disable internal panel, conditional suspend |
| `config/sway/scripts/idle.sh` | Reload-safe swayidle launcher (dim → lock → screen off → suspend) |
| `config/swaylock/config` | Lock screen (flat, Nord dark) |
| *shared with Hyprland:* | |
| `config/waybar/*` | Bar: workspaces, 3 clocks, tray, battery, net, volume (carries both compositors' modules) |
| `config/fuzzel/*` | Launcher (SUPER+Space), themed per light/dark mode |
| `config/swaync/*` | Notifications + control centre (dark + light) |
| `config/hypr/scripts/theme.sh`, `theme-daemon.sh`, `launch-fuzzel.sh` | Light/dark theming engine (compositor-aware; lives under `hypr/` for historical reasons) |

## Installing

Dotfiles are installed by this repo's `make install`. **Packages** come from
`setup` (scripts repo); **`setup-sway`** applies the non-dotfile config (the
systemd-logind lid drop-in, enabling `power-profiles-daemon`, and seeding
`config.local` from the template):

    setup --sway              # full bootstrap: packages + Sway config
    setup-sway                # just the logind drop-in + services + config.local
    setup-sway --no-install   # skip the system-level changes

Packages (Debian/Ubuntu and Fedora names; everything is in the default
repos — no COPR/backport needed, unlike Hyprland):

    sway swaybg swayidle swaylock         # compositor, wallpaper, idle, lock
    autotiling                            # dynamic (dwindle-style) tiling
    xdg-desktop-portal-wlr xdg-desktop-portal-gtk
    waybar fuzzel swaync                  # bar, launcher, notifications (shared)
                                          #   (swaync is packaged as
                                          #   sway-notification-center on apt,
                                          #   SwayNotificationCenter on Fedora)
    power-profiles-daemon
    pipewire wireplumber pavucontrol      # volume/sound
    brightnessctl                         # backlight keys + idle dimming
    grim slurp wl-clipboard               # screenshots (Print) → clipboard
    playerctl                             # media play/pause/next/prev keys
    gnome-calculator                      # XF86Calculator key
    yazi                                  # terminal file manager (SUPER+E)
    network-manager-applet blueman        # network + bluetooth tray applets
    polkit-gnome                          # GUI privilege prompts
    a JetBrains Mono Nerd Font            # glyphs in waybar/fuzzel/swaylock

If your distro has no `autotiling` package: `pipx install autotiling`. If it
is missing entirely the desktop still works — you just fall back to manual
i3-style splits.

## Starting the session

Pick "Sway" at your display manager, or from a TTY:

    sway

(uwsm also works if you prefer a systemd-managed session — `uwsm start
sway.desktop`; `config/uwsm/env` provides the shared environment. Opt-in,
exactly as described in `config/hypr/README.md`.)

## Multi-machine / per-host setup

The base `config/sway/config` is **identical on every machine**. Machine
overrides live in `~/.config/sway/config.local` — the same file name plus a
`.local` suffix (like `.shrc.local`) — which the base config `include`s late,
so per-host lines win over the shared defaults. The file is machine-local
and never committed. If it's absent, Sway logs one warning and starts
normally: input handedness is type-matched, the lid panel is auto-detected,
and hotplugged outputs are auto-placed, so **an unconfigured machine works
out of the box**.

Adding a new machine:

1. `make install` (conf repo) and `setup-sway` (scripts repo). `setup-sway`
   copies `config.local.template` to `~/.config/sway/config.local` if it
   doesn't exist, and appends the machine's detected output names as
   comments when run inside a Sway session.
2. Edit `~/.config/sway/config.local`, keeping only what the machine needs —
   see `config.local.example-laptop` / `config.local.example-desktop`.
3. `swaymsg reload` (SUPER+Shift+C is *not* bound — reload from a terminal).

What belongs in `config.local` (everything optional):

- **Pinned output arrangement** — `output DP-1 pos 0 0` etc.
  (names: `swaymsg -t get_outputs`). Unlisted outputs are auto-placed.
- **Desktop: no suspend** — `set $idle_suspend_cmd true`.
- **Lid panel override** — only if auto-detection picks the wrong output:
  re-bind `bindswitch ... lid.sh close <name>`.
- **Per-device input tweaks** — e.g. `input "<identifier>" scroll_factor 1.5`.
  Scroll speed is deliberately not set globally.
- **Extra launchers** — SUPER+D / SUPER+S are left unbound (their helper
  scripts aren't in the repo), same as the Hyprland build.

## What setup-sway does

`setup-sway` (scripts repo) is idempotent and safe to re-run:

1. Installs the **systemd-logind lid drop-in** (`HandleLidSwitch=ignore`) so
   the compositor's lid handler is authoritative — **shared with the
   Hyprland build**: if setup-hypr's drop-in is already present it is reused
   and nothing is written. Needs sudo; reloads logind (no reboot).
2. Enables **power-profiles-daemon** (waybar's power-profile module).
3. Seeds `~/.config/sway/config.local` from the template (never overwrites),
   appending detected output names as comments when run inside Sway.
4. Sources `setup-sway.local` if present (machine-local extra steps).

Only things that genuinely can't live in static shared config go here;
everything else is in `config/sway/config`.

## Laptop lid / displays

- **Lid close/open** — Sway's native `bindswitch` runs
  `config/sway/scripts/lid.sh`: on close it disables the internal panel
  (auto-detected: first eDP/LVDS/DSI output) and **suspends only when no
  other output is active**, so a docked laptop keeps running on its external
  screen; on open it re-enables the panel. The bindings use `--locked
  --reload` so they work on the lock screen and re-sync on config reload.
- **systemd-logind** must ignore the lid for lid.sh to be the sole handler.
  `setup-sway` installs the drop-in (shared with setup-hypr) and reloads
  logind. To do it manually: create
  `/etc/systemd/logind.conf.d/10-sway-lid.conf` with
  `[Login]` / `HandleLidSwitch=ignore` /
  `HandleLidSwitchExternalPower=ignore` / `HandleLidSwitchDocked=ignore`,
  then `sudo systemctl kill -s HUP systemd-logind` (or restart logind).
  *TODO: consider flipping this policy to logind entirely
  (`HandleLidSwitch=suspend` + `HandleLidSwitchDocked=ignore`) and dropping
  the conditional suspend from both compositors' lid scripts — that's a
  shared system-level change, so do the Hyprland build at the same time.*
- **External display hotplug** — needs no config and no kanshi: Sway
  auto-enables a monitor when you attach it and drops it on detach.
  Positioning is automatic unless you pin it in `config.local`.

## Idle / power (Sway-specific)

`swayidle` + `swaylock` mirror the Hyprland build's hypridle/hyprlock flow:
dim the backlight at 2.5 min, lock at 5 min, screen off at 5.5 min, suspend
at 30 min; locking before sleep so you wake to a lock screen. All four
timeouts and the suspend command are `$idle_*` variables, overridable
per-host (desktops set `$idle_suspend_cmd true` and never sleep; the dim
step is a no-op without a backlight). swayidle is started through
`scripts/idle.sh` via `exec_always`, which replaces the previous instance —
so editing the `$idle_*` overrides in `config.local` takes effect on
`swaymsg reload`, no re-login needed. (`$wallpaper` is the one override that
still applies at the next login, since duplicating swaybg on every reload
would be worse.) `power-profiles-daemon` (shared) feeds the waybar
power-profile module.

## Bar / launcher / notifications / theming (shared)

All reused from the Hyprland build unchanged, except that
`config/waybar/config.jsonc` now lists both compositors' workspace/window
modules — waybar disables the pair for the compositor that isn't running
(one logged warning at startup, harmless):

- **waybar**: system tray (SNI), battery (auto-hides on battery-less hosts),
  network, volume, power profile, and **three labelled clocks** — local,
  London (`Europe/London`), San Francisco (`America/Los_Angeles`).
- **fuzzel** on SUPER+Space, via the shared `launch-fuzzel.sh` (themed to
  the current light/dark mode).
- **swaync** notifications + control centre.
- **Light/dark by time of day**: the shared `theme-daemon.sh` applies light
  07:00–19:00 and dark otherwise. `theme.sh` is compositor-aware: under Sway
  it sets `client.focused`/`client.unfocused` border colours via `swaymsg`
  and swaps the wallpaper via `swaybg` (per-mode images optional; see the
  Hyprland README). It also (re)launches waybar and swaync — which is why
  the Sway config doesn't start them itself.
- **Wallpaper**: plain static `swaybg`, reading the same
  `~/.config/hypr/wallpaper.jpg` placeholder the Hyprland build uses, so one
  image serves both desktops. Missing image = black desktop, nothing breaks.

## Keybindings

`SUPER` (`$mod`) is the modifier. All the launcher/media/screenshot binds
match the Hyprland build exactly (see `config/hypr/README.md` for the full
app-launcher table): SUPER+T terminal, SUPER+Space fuzzel,
SUPER+Backspace close, SUPER+L lock, SUPER+Shift+E exit, SUPER+1..0 /
SUPER+Shift+1..0 workspaces 1–10, Print screenshots, XF86 media keys.

Sway-specific tiling keys (manual overrides on top of autotiling):

| Keys | Action |
|------|--------|
| `SUPER + [` / `SUPER + ]` | Split the next window horizontally / vertically |
| `SUPER + O` | Toggle the split direction of the focused container |
| `SUPER + .` | Cycle layout: split → tabbed → stacking |
| `SUPER + ,` | Toggle split axis (splith ⇄ splitv) |
| `` SUPER + ` `` | Monocle (fullscreen toggle) |
| `SUPER + Shift + F` / `SUPER + Insert` | Toggle floating |
| `SUPER + J` / `SUPER + K` | Focus next / previous window |
| `SUPER + Shift + J` / `SUPER + Shift + K` | Move window down / up |
| `SUPER + arrows` / `SUPER + Shift + arrows` | Directional focus / move |
| `SUPER + Shift + R` | **Resize** mode (h/j/k/l or arrows; Esc/Enter exits) |
| `SUPER + drag` / `SUPER + right-drag` | Move / resize window (mouse) |

Hyprland binds with no Sway equivalent (master/stack: `SUPER+\`, `SUPER+/`,
`SUPER+Return`, `SUPER+=`, `SUPER+-`) are intentionally unbound.

## Behaviour notes / differences from Hyprland

- **No inactive-window dimming.** Sway has no equivalent of Hyprland's
  `dim_inactive`; the focused/unfocused border colours (thin 2px, shared
  scheme) are the visual cue. Don't look for a dimming option — there isn't
  one.
- **Flat by design.** No gaps, no rounded corners, no blur, no shadows, no
  animations — Sway draws none of these, which is exactly the traditional
  look; the Hyprland build keeps its subtle rounding/blur.
- **Handedness is static here.** Sway matches input devices by *type*, so
  the shared policy (mice → right button primary via `left_handed enabled`;
  touchpads → left button primary) is two static `input type:` blocks with
  the touchpad block last — no helper script, no per-machine config. On
  Hyprland the same policy needs the per-device `apply-input.sh` at login.
- **Keyboard**: US Dvorak, Caps Lock is Compose — same as everywhere else.

## Placeholders to fill in

**None are required to boot.** Optional, all per-host or shared:

1. **Wallpaper image** — drop `~/.config/hypr/wallpaper.jpg` (shared with
   the Hyprland build; optional `wallpaper-light.jpg`/`wallpaper-dark.jpg`
   for the day/night swap). Absent = black desktop.
2. **`config.local` values** — output names/positions, lid-panel override,
   desktop no-suspend, per-device scroll speed (see the template/examples;
   internal and external output names come from `swaymsg -t get_outputs`).
3. **Timezones** — the waybar clocks are local/London/San Francisco; edit
   `config/waybar/config.jsonc` (shared) to change them.
