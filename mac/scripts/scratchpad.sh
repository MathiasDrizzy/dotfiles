#!/usr/bin/env bash
# ==============================================================================
# scratchpad.sh — shows or hides the scratchpad: Ghostty's floating quick terminal (see mac/config/ghostty/config).
# herdr runs it on prefix+t. It asks Ghostty through AppleScript, so macOS asks once to allow "Automation" (the app that
# runs this script controlling Ghostty).
# ==============================================================================
set -euo pipefail

exec /usr/bin/osascript <<'APPLESCRIPT'
tell application "Ghostty"
	if (count of windows) is 0 then
		new window
	end if
	perform action "toggle_quick_terminal" on (focused terminal of selected tab of front window)
end tell
APPLESCRIPT
