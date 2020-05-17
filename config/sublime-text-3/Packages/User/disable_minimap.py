# -*- encoding: utf-8 -*-

import sublime
import sublime_plugin

class DisableMinimap(sublime_plugin.EventListener):

    def on_activated(self, view):
        view.window().set_minimap_visible(False)