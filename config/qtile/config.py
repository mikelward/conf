# Copyright (c) 2010 Aldo Cortesi
# Copyright (c) 2010, 2014 dequis
# Copyright (c) 2012 Randall Ma
# Copyright (c) 2012-2014 Tycho Andersen
# Copyright (c) 2012 Craig Barnes
# Copyright (c) 2013 horsik
# Copyright (c) 2013 Tao Sauvage
# Copyright (c) 2020 Mikel Ward
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

import os

from typing import List  # noqa: F401

from libqtile import bar, hook, layout, qtile, widget
from libqtile.config import Click, Drag, Group, Key, Screen
from libqtile.lazy import lazy
from libqtile.log_utils import logger

import mydynamic
import mystack

screeninfo = None
try:
    import screeninfo
except:
    pass

mod = "mod4"
alt = "mod1"
# TODO(mikel): calculate width
quarter_width = 860
num_columns = 3
slice_role = "browser"
slice_wmclass = None
if os.environ.get("QTILE_XEPHYR"):
    quarter_width = 480
    mod = alt
    slice_role = None
    slice_wmclass = "xclock"

def window_to_previous_screen(qtile):
    curr = qtile.screens.index(qtile.current_screen)
    prev = (curr - 1) % len(qtile.screens)
    group = qtile.screens[prev].group.name
    qtile.current_window.togroup(group)

def window_to_next_screen(qtile):
    curr = qtile.screens.index(qtile.current_screen)
    next = (curr + 1) % len(qtile.screens)
    group = qtile.screens[next].group.name
    qtile.current_window.togroup(group)

keys = [
    # Switch between screens (a.k.a. monitors)
    Key([mod], "Page_Up", lazy.prev_screen(), desc="Move monitor focus to previous screen"),
    Key([mod], "Page_Down", lazy.next_screen(), desc="Move monitor focus to next screen"),
    # Switch between groups (a.k.a. workspaces)
    Key([mod], "Tab", lazy.screen.toggle_group(), desc="Switch to the previous group"),
    # Switch between windows
    Key([mod, alt], "Down", lazy.layout.down(), desc="Move focus down"),
    Key([mod, alt], "Up", lazy.layout.up(), desc="Move focus up"),
    Key([mod, alt], "Right", lazy.layout.right(), desc="Move focus right"),
    Key([mod, alt], "Left", lazy.layout.left(), desc="Move focus left"),
    Key([mod], "Right", lazy.layout.swap_stack_right()),
    Key([mod], "Left", lazy.layout.swap_stack_left()),
    Key([alt], "Tab", lazy.layout.next(), desc="Focus the next window"),
    Key([alt, "shift"], "Tab", lazy.layout.previous(), desc="Focus the previous window"),
    # Move windows
    Key([mod, "shift"], "Page_Up", lazy.function(window_to_previous_screen), desc="Move window to previous screen"),
    Key([mod, "shift"], "Page_Down", lazy.function(window_to_next_screen), desc="Move window to next screen"),
    Key([mod, "shift"], "Down", lazy.layout.shuffle_down(), desc="Move window down"),
    Key([mod, "shift"], "Up", lazy.layout.shuffle_up(), desc="Move window up"),
    Key([mod, "shift"], "Right", lazy.layout.shuffle_right(), desc="Move window right"),
    Key([mod, "shift"], "Left", lazy.layout.shuffle_left(), desc="Move window left"),
    # Toggle between different layouts
    Key([mod], "grave", lazy.to_layout_index(-1), desc="Switch to layout -1"),
    Key([mod], "apostrophe", lazy.to_layout_index(0), desc="Switch to layout 0"),
    Key([mod], "comma", lazy.to_layout_index(1), desc="Switch to layout 1"),
    Key([mod], "period", lazy.to_layout_index(2), desc="Switch to layout 2"),
    Key([mod], "Return", lazy.to_layout_index(-1), desc="Switch to layout -1"),
    Key([mod], "equal", lazy.to_layout_index(3), desc="Switch to layout 3"),
    Key([mod], "BackSpace", lazy.window.kill(), desc="Kill focused window"),
    Key([mod, "control"], "r", lazy.restart(), desc="Restart qtile"),
    Key([mod, "control"], "q", lazy.shutdown(), desc="Shutdown qtile"),
    Key([mod, "control"], "x", lazy.shutdown(), desc="Shutdown qtile"),
    Key([mod], "space", lazy.spawncmd(), desc="Spawn a command using a prompt widget"),
]

groups = [Group(i) for i in "1234567890"]

for i in groups:
    keys.extend(
        [
            # mod + letter of group = switch to group
            Key([mod], i.name, lazy.group[i.name].toscreen(toggle=True), desc="Switch to group {}".format(i.name)),
            # mod + shift + letter of group = move focused window to group
            Key([mod, "shift"], i.name, lazy.window.togroup(i.name, switch_group=False), desc="Move focused window to group {}".format(i.name)),
        ]
    )

layouts = [
    mystack.MyStack(name="3center", widths=[1.0 / 4, 1.0 / 2, 1.0 / 4]),
    mystack.MyStack(name="2equal", widths=[1.0 / 2, 1.0 / 2]),
    mydynamic.MyDynamic(name="21:9", left_fractions=[1.0 / 4], center_fractions=[1.0 / 2], right_fraction=[1.0 / 4]),
    mydynamic.MyDynamic(name="16:9", left_fractions=[], center_fractions=[2.0 / 3], right_fraction=[1.0 / 3]),
    layout.Max(),
]

widget_defaults = dict(
    font="sans",
    fontsize=12,
    padding=3,
)
extension_defaults = widget_defaults.copy()

def screen(main=True):
    top = bar.Bar(
        widgets=list(
            filter(
                None,
                [
                    widget.GroupBox(),
                    widget.Prompt(),
                    widget.Spacer(),
                    widget.CurrentLayout(),
                    widget.Sep(),
                    widget.WindowName(width=bar.CALCULATED, show_state=False),
                    widget.Spacer(),
                    widget.Clipboard(max_width=30),
                    widget.Clock(format="%b %-d %H:%M"),
                    (widget.PulseVolume() if main else None),
                    (widget.Systray() if main else None),
                ],
            )
        ),
        size=24,
    )

    def update_bar_background():
        if top.screen == top.qtile.current_screen:
            top.background = '#000000'
        else:
            top.background = '#666666'
        top.draw()
    hook.subscribe.current_screen_change(update_bar_background)

    return Screen(top=top)


screens = []
if screeninfo:
    monitors = screeninfo.get_monitors()
    logger.info('screeninfo detected %d monitors', len(monitors))
    main = monitors[0]
    if monitors[0].name.startswith('e') and len(monitors) > 1:
        main = monitors[1]
    for monitor in monitors:
        screens.append(screen(main==monitor))
else:
    logger.info('screeninfo not available, only configuring a single screen')
    screens.append(screen(True))

# Drag floating layouts.
mouse = [
    Drag([mod], "Button1", lazy.window.set_position_floating(), start=lazy.window.get_position()),
    Drag([mod], "Button3", lazy.window.set_size_floating(), start=lazy.window.get_size()),
    Click([mod], "Button2", lazy.window.bring_to_front()),
]

dgroups_key_binder = None
dgroups_app_rules = []  # type: List
main = None
follow_mouse_focus = True
bring_front_click = False
cursor_warp = True
floating_layout = layout.Floating(
    float_rules=[
        # Run the utility of `xprop` to see the wm class and name of an X client.
        {"wmclass": "confirm"},
        {"wmclass": "dialog"},
        {"wmclass": "download"},
        {"wmclass": "error"},
        {"wmclass": "file_progress"},
        {"wmclass": "notification"},
        {"wmclass": "splash"},
        {"wmclass": "toolbar"},
        {"wmclass": "confirmreset"},  # gitk
        {"wmclass": "makebranch"},  # gitk
        {"wmclass": "maketag"},  # gitk
        {"wname": "branchdialog"},  # gitk
        {"wname": "pinentry"},  # GPG key password entry
        {"wmclass": "ssh-askpass"},  # ssh-askpass
        {"wname": "meet.google.com is sharing your screen."},
        {"wname": "meet.google.com is sharing a window."},
    ]
)
auto_fullscreen = True
focus_on_window_activation = "smart"

# Pretend to be "LG3D" so that Java apps behave correctly.
wmname = "LG3D"

# Restart to handle a monitor appearing or disappearing.
# This seems to cause an infinite loop.
# @hook.subscribe.screen_change
# def restart_on_randr(ev):
#     logger.info('screen_change, restarting')
#     qtile.cmd_restart()
