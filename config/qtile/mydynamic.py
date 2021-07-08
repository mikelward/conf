# Copyright (c) 2008, Aldo Cortesi. All rights reserved.
# Copyright (c) 2021, Mikel Ward. All rights reserved.
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

import traceback

from libqtile.layout.base import _SimpleLayoutBase
from libqtile.log_utils import logger

class MyDynamic(_SimpleLayoutBase):
    """A layout composed of stacks of stacks.

    The list of windows is maintained as a single stack. They are distributed
    across:

    a) optional left columns (oldest windows, one per column)
    b) optional center columns (newest windows, one per column)
    d) the right column (all remaining windows, in a vertical stack)
    """
    defaults = [
        ("name", "mydynamic", "Name of this layout."),
        ("border_focus", "#0000ff", "Border colour for the focused window."),
        ("border_normal", "#000000", "Border colour for un-focused windows."),
        ("border_width", 1, "Border width."),
        ("left_fractions", [1.0/4.0], "Width of left column(s)."),
        ("center_fractions", [1.0/2.0], "Width of center column(s)."),
        ("right_fraction", [1.0/4.0], "Width of right column."),
    ]

    def __init__(self, **config):
        _SimpleLayoutBase.__init__(self, **config)
        self.add_defaults(MyDynamic.defaults)

    def add(self, window):
        logger.info("Appending %s", window)
        # Newest clients always go at the end.
        self.clients.append(window)

    def remove(self, window):
        logger.info("Removing %s", window)
        self.clients.remove(window)

    def layout(self, windows, screen_rect):
        logger.info("Layout")
        logger.info("windows=%s", windows)
        logger.info("self.clients=%s", self.clients)
        # XXX why is windows different from self.clients? focus order?
        windows = self.clients[:]

        if len(windows) == 0:
            return

        widths = list(map(lambda fraction: int(fraction * screen_rect.width),
            self.left_fractions + self.center_fractions + self.right_fraction))
        x = screen_rect.x
        y = screen_rect.y
        width = screen_rect.width
        height = screen_rect.height

        center_windows = []
        try:
            for _ in range(len(self.center_fractions)):
                center_windows.append(windows.pop())
        except IndexError:
            pass

        left_windows = []
        try:
            for _ in range(len(self.left_fractions)):
                left_windows.append(windows.pop(0))
        except IndexError:
            pass

        right_windows = windows
        right_windows.reverse()

        column = 0

        # Put the oldest <num left columns> windows in the left columns, if any.
        for i, _ in enumerate(self.left_fractions):
            w = widths[column]

            try:
                window = left_windows[i]
                logger.info("Left: Placing %s in column %d", window, column)
                self._place(window, x, y, w, height)
            except IndexError:
                # More columns than windows.
                # Still need to increment `x` and `column`.
                pass

            x += w
            column += 1

        # Put the newest windows in the center columns, if any.
        for i, _ in enumerate(self.center_fractions):
            w = widths[column]

            try:
                window = center_windows[i]
                logger.info("Center: Placing %s in column %d", window, column)
                self._place(window, x, y, w, height)
            except IndexError:
                # More columns than windows.
                # Still need to increment `x` and `column`.
                pass

            x += w
            column += 1

        # Put any remaining windows in a stack in the right-most column.
        if len(right_windows):
            w = widths[column]
            h = height // len(right_windows)
            for window in right_windows:
                logger.info("Right: Placing %s in column %d", window, column)
                self._place(window, x, y, w, h)
                y += h

    def _place(self, window, x, y, w, h):
        border = (self.border_focus if window.has_focus else self.border_normal)
        return window.place(x, y, w, h, self.border_width, border)

    def cmd_next(self):
        pass

    def cmd_previous(self):
        pass

    def configure(self, window, screen_rect):
        pass
