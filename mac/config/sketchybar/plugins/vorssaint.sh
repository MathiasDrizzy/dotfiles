#!/usr/bin/env bash
# Opens Vorssaint's menu bar panel by clicking its status item through System Events (needs the Accessibility
# permission), since the native menu bar that holds it is hidden.
exec osascript -e 'tell application "System Events" to tell process "Vorssaint" to click menu bar item 1 of menu bar 2'
