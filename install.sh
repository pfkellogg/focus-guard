#!/bin/bash
# Focus Guard installer: builds the app on this Mac (so macOS doesn't block it), installs it, adds the two VS Code
# shortcuts it uses, starts it at login, and opens the Accessibility settings for the one switch only you can turn on.
#   Install:  curl -fsSL https://raw.githubusercontent.com/pfkellogg/focus-guard/main/install.sh | bash
#   or, in a copy of this folder:  ./install.sh
set -euo pipefail
REPO="https://raw.githubusercontent.com/pfkellogg/focus-guard/main"
APP_NAME="Focus Guard.app"
SIGN="${FG_SIGN:--}"                      # "-" = signed on this Mac only (default); FG_SIGN="Apple Development" to use a certificate

say_step() { printf '\n==> %s\n' "$1"; }

[ "$(uname)" = "Darwin" ] || { echo "Focus Guard is for macOS."; exit 1; }

say_step "Checking for Apple's free developer tools (to build the app)"
if ! xcode-select -p >/dev/null 2>&1 || ! command -v swiftc >/dev/null 2>&1; then
  xcode-select --install 2>/dev/null || true
  echo "A window asks to install the Command Line Tools: click Install, wait for it to finish, then run this installer again."
  exit 1
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
HERE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || true)"
if [ -n "$HERE" ] && [ -f "$HERE/FocusGuard.swift" ]; then
  cp "$HERE/FocusGuard.swift" "$HERE/Info.plist" "$WORK/"
else
  say_step "Downloading the source"
  curl -fsSL "$REPO/FocusGuard.swift" -o "$WORK/FocusGuard.swift"
  curl -fsSL "$REPO/Info.plist" -o "$WORK/Info.plist"
fi

say_step "Building (Apple chip and Intel)"
APP="$WORK/$APP_NAME"
mkdir -p "$APP/Contents/MacOS"
cp "$WORK/Info.plist" "$APP/Contents/Info.plist"
swiftc -O -target arm64-apple-macos13.0 -o "$WORK/fg-arm64" "$WORK/FocusGuard.swift" 2>/dev/null
swiftc -O -target x86_64-apple-macos13.0 -o "$WORK/fg-x86_64" "$WORK/FocusGuard.swift" 2>/dev/null
lipo -create "$WORK/fg-arm64" "$WORK/fg-x86_64" -output "$APP/Contents/MacOS/FocusGuard"
codesign --force --deep -s "$SIGN" "$APP"

say_step "Installing"
DEST="/Applications"
[ -w "$DEST" ] || DEST="$HOME/Applications"
mkdir -p "$DEST"
pkill -x FocusGuard 2>/dev/null || true
rm -rf "$DEST/$APP_NAME"
cp -R "$APP" "$DEST/"
echo "Installed: $DEST/$APP_NAME"

say_step "Adding two VS Code shortcuts (Focus Guard presses them to put the cursor in Claude Code)"
KB="$HOME/Library/Application Support/Code/User/keybindings.json"
mkdir -p "$(dirname "$KB")"
/usr/bin/python3 - "$KB" <<'PY'
import sys, os, re
p = sys.argv[1]
ours = ('  { "key": "ctrl+alt+shift+f19", "command": "workbench.action.terminal.focus" },  // Focus Guard\n'
        '  { "key": "ctrl+alt+shift+f18", "command": "claude-vscode.focus" }  // Focus Guard\n')
t = open(p).read() if os.path.exists(p) else ""
if "ctrl+alt+shift+f19" in t:
    print("Already there."); sys.exit()
if not t.strip():
    open(p, "w").write("// Focus Guard presses these after bringing VS Code forward.\n[\n" + ours + "]\n"); print("Created."); sys.exit()
end = t.rstrip().rfind("]")
if end < 0:
    print("Couldn't read your keybindings.json: add the two lines from the README by hand."); sys.exit()
before = t[:end].rstrip()
body = re.sub(r"//[^\n]*", "", before)            # comments don't count
need_comma = body.rstrip()[-1:] not in ("[", ",")
open(p + ".before-focus-guard", "w").write(t)     # a backup
open(p, "w").write(before + ("\n  ," if need_comma else "") + "\n" + ours + t[end:])   # the comma on its own line: never inside a // comment
print("Added (backup: keybindings.json.before-focus-guard).")
PY

say_step "Starting at login"
LA="$HOME/Library/LaunchAgents/com.aikellogg.focusguard.plist"
mkdir -p "$(dirname "$LA")"
cat > "$LA" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Label</key><string>com.aikellogg.focusguard</string>
<key>ProgramArguments</key><array><string>/usr/bin/open</string><string>-a</string><string>$DEST/$APP_NAME</string></array>
<key>RunAtLoad</key><true/>
</dict></plist>
PL
launchctl bootout "gui/$(id -u)/com.aikellogg.focusguard" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$LA" 2>/dev/null || true

say_step "One step only you can do"
# a rebuild is a new app to macOS: clear any old switch so the new one is asked for fresh
tccutil reset Accessibility com.aikellogg.focusguard >/dev/null 2>&1 || true
open "$DEST/$APP_NAME"
sleep 2
open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
cat <<'MSG'
In System Settings > Privacy & Security > Accessibility, turn ON the switch next to "Focus Guard"
(your Mac asks for your password or Touch ID). Then start it once more:
    open -a "Focus Guard"
From then on it starts by itself when you log in.
MSG
