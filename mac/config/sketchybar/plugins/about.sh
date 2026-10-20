#!/usr/bin/env bash
# Opens the same "About This Mac" panel as the native Apple menu: its first item, clicked through System Events
# (needs the Accessibility permission).
exec osascript -e 'tell application "System Events" to tell (first process whose frontmost is true) to click menu item 1 of menu 1 of menu bar item 1 of menu bar 1'
