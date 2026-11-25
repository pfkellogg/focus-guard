# Focus Guard

**Typing into nothing? Focus Guard tells you, and puts you back in Claude Code.**

You start typing a message to Claude Code, but Claude Code doesn't have the keyboard: the desktop, Finder, or some
app window does. Your words vanish, or worse, they press that app's shortcut keys. Focus Guard is a tiny Mac app
that notices, and:

1. **catches the keys** you typed, so they don't land in the wrong place;
2. **says out loud:** "Claude Code doesn't have focus. Click to stay here.";
3. **waits 4 seconds.** Click any mouse button to stay where you are ("Staying here.", and it stays quiet until you
   go back to VS Code yourself);
4. if you don't click, it **brings VS Code to the front, puts the cursor in Claude Code**, and **types what you typed**
   there, so nothing has to be retyped.

Made for people who can't always see where the keyboard focus is, and useful for everyone else.

It never touches:
- typing into a real text box in any app (Chrome, Mail, Notes, a web form...);
- shortcuts (anything with Cmd, Ctrl or Option);
- a Return pressed into nothing: it's dropped, so a half-typed message is never sent by surprise.

## Turn it off and on

Press **Control + Option + F**, or click **Focus: ON** in the menu bar (top right of the screen). Focus Guard says
"Focus Guard off." and the menu bar shows **Focus: OFF**; do it again to turn it back on ("Focus Guard on.").
Handy while you type somewhere it doesn't recognise as a text box. It starts on again after a restart. (Mac.)

## Claude Code in the terminal or the extension

Focus Guard looks each time:
- **Claude Code running in a VS Code terminal:** the cursor goes to the terminal.
- **Only the Claude Code extension:** the cursor goes to the extension's input.
- **Both:** the terminal.

With several VS Code windows open, it brings back the one you last typed into.

To always use one: `defaults write com.aikellogg.focusguard place extension` (or `terminal`).
Back to automatic: `defaults delete com.aikellogg.focusguard place`. Then restart Focus Guard.

## VS Code extension (macOS and Windows)

The easiest way: the **Focus Guard** extension starts Focus Guard whenever VS Code starts, and adds the two shortcuts
itself.
- **In VS Code:** Extensions view, search **Focus Guard**, Install. Or on the
  [VS Code Marketplace](https://marketplace.visualstudio.com/items?itemName=aikellogg.focus-guard).
- Or download `focus-guard-1.1.3.vsix` from [Releases](https://github.com/pfkellogg/focus-guard/releases/latest), then:
- In VS Code: Extensions view > `...` menu > **Install from VSIX...**, and pick the file. Or in a terminal:
  `code --install-extension focus-guard-1.1.3.vsix`
- **Mac:** the first time it builds Focus Guard on your Mac (needs Apple's free Command Line Tools; it offers to install
  them), then asks for the Accessibility switch, out loud and with an **Open Settings** button.
- **Windows:** nothing else to do. A small helper runs with Windows PowerShell, which every Windows 10 and 11 PC has.
  It is new: it builds and starts on Windows (checked on every change by GitHub Actions), but please report anything
  odd in Issues.
- Settings: **Focus Guard: Place** (auto / terminal / extension) and **Focus Guard: Enabled**.

## Install without the extension (Mac)

You need macOS 13 or later and VS Code. Paste this into Terminal:

```bash
curl -fsSL https://raw.githubusercontent.com/pfkellogg/focus-guard/main/install.sh | bash
```

The installer:
- builds Focus Guard on your Mac, for Apple chip and Intel. Built on your own Mac, macOS doesn't block it, so no
  paid Apple developer account is needed. If Apple's free Command Line Tools aren't installed yet, macOS offers to
  install them: click Install, then run the installer again;
- installs it in Applications and starts it at login;
- adds two shortcuts to VS Code's `keybindings.json` (a backup of the old file is kept). Focus Guard presses them to put
  the cursor in Claude Code. Nobody presses them by hand:
  ```jsonc
  { "key": "ctrl+alt+shift+f19", "command": "workbench.action.terminal.focus" },
  { "key": "ctrl+alt+shift+f18", "command": "claude-vscode.focus" }
  ```
- opens **System Settings > Privacy & Security > Accessibility**.

**One step only you can do:** turn on the switch next to **Focus Guard** (macOS asks for your password or Touch ID),
then run `open -a "Focus Guard"` once. That permission is what lets it see keys typed into nothing; macOS lets only
you grant it.

## Uninstall

```bash
curl -fsSL https://raw.githubusercontent.com/pfkellogg/focus-guard/main/uninstall.sh | bash
```

## How it works

Mac: one Swift file, [`FocusGuard.swift`](FocusGuard.swift). Windows: [`windows/FocusGuard.cs`](windows/FocusGuard.cs),
compiled at start by [`windows/FocusGuard.ps1`](windows/FocusGuard.ps1). The extension: [`vscode/`](vscode).
On the Mac:
- A keyboard event tap sees each key. If VS Code isn't in front and no text element has focus (checked through the
  Accessibility API), the key is held back.
- `NSSpeechSynthesizer` speaks; a mouse click within 4 seconds cancels the move.
- Otherwise it activates VS Code, presses the focus shortcut, and retypes the held keys as plain letters.
- Nothing is recorded, saved or sent anywhere. Keys are held in memory for at most a few seconds.

## License

MIT, see [LICENSE](LICENSE). By Patrick Kellogg, [aikellogg.com](https://aikellogg.com).

Support the Patrick Kellogg Foundation for the Performing Arts: [ko-fi.com/aikellogg](https://ko-fi.com/aikellogg)
