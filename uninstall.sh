#!/bin/bash
# Focus Guard uninstaller: stops it, removes the app and the login item. The two VS Code shortcuts are left (harmless);
# remove the two lines marked "Focus Guard" in VS Code's keybindings.json if you like.
launchctl bootout "gui/$(id -u)/com.aikellogg.focusguard" 2>/dev/null || true
rm -f "$HOME/Library/LaunchAgents/com.aikellogg.focusguard.plist"
pkill -x FocusGuard 2>/dev/null || true
rm -rf "/Applications/Focus Guard.app" "$HOME/Applications/Focus Guard.app"
tccutil reset Accessibility com.aikellogg.focusguard >/dev/null 2>&1 || true
echo "Focus Guard removed."
