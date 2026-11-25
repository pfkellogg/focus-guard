# Focus Guard: Back to Claude Code

**Typing into nothing? Focus Guard tells you out loud, and puts you back in Claude Code, keys and all.**

You start typing a message to Claude Code, but Claude Code doesn't have the keyboard: the desktop, Finder or
Explorer, or some other window does. Your words vanish, or worse, they press that app's shortcut keys.

When the keys you type would go nowhere, Focus Guard:

1. **catches them**, so they don't land in the wrong place;
2. **says out loud:** "Claude Code doesn't have focus. Click to stay here.";
3. **waits 4 seconds.** Click any mouse button to stay where you are ("Staying here.", and it stays quiet until you go
   back to VS Code yourself);
4. if you don't click, it **brings VS Code to the front, puts the cursor in Claude Code**, and **types what you typed**
   there, so nothing has to be retyped.

Made for people who can't always see where the keyboard focus is, and useful for everyone else.

It never touches typing into a real text box in any app, or shortcuts (Cmd, Ctrl, Option/Alt, Win). A Return pressed
into nothing is dropped, so a half-typed message is never sent by surprise.

## Claude Code in the terminal or the extension

Setting **Focus Guard: Place**:
- **auto** (default): it looks each time. Claude Code running in a VS Code terminal wins; otherwise the Claude Code
  extension's input.
- **terminal** or **extension**: always that one.

With several VS Code windows open, Focus Guard brings back the one you last typed into.

The extension adds two shortcuts that Focus Guard presses for you; nobody presses them by hand:
`ctrl+alt+shift+F19` (focus the terminal) and `ctrl+alt+shift+F18` (focus the Claude Code extension's input).

## macOS

- The first time, Focus Guard is **built on your Mac** from its source (about 30 seconds), so macOS doesn't block it and
  no paid Apple developer account is needed. It needs Apple's free Command Line Tools; if they're missing, the
  extension offers to install them.
- **One switch only you can turn on:** System Settings > Privacy & Security > Accessibility > **Focus Guard**. Focus
  Guard says so out loud, the extension shows an **Open Settings** button, and it starts working the moment you turn it
  on. (Each new version is a new app to macOS, so the switch is asked for again after an update.)
- If you installed Focus Guard with the
  [one-line installer](https://github.com/pfkellogg/focus-guard#install), the extension uses that copy.

## Windows

- Nothing to install and no permission needed: the extension starts a small helper with Windows PowerShell, which every
  Windows 10 and 11 PC has.
- It can't see typing into apps run as administrator (Windows doesn't allow it).
- **New:** tested to build and start on Windows, but not yet used day to day. Please report anything odd in
  [Issues](https://github.com/pfkellogg/focus-guard/issues).

## Commands

- **Focus Guard: Start** / **Focus Guard: Stop**
- **Focus Guard: Open the Accessibility Settings (Mac)**

Setting **Focus Guard: Enabled** turns starting with VS Code on or off.

## Privacy

Nothing is recorded, saved or sent anywhere. Keys typed into nothing are held in memory for at most a few seconds.

## About

By Patrick Kellogg, [aikellogg.com](https://aikellogg.com). MIT license. Source:
[github.com/pfkellogg/focus-guard](https://github.com/pfkellogg/focus-guard). Not made by or affiliated with Anthropic;
Claude Code is Anthropic's.

Support the Patrick Kellogg Foundation for the Performing Arts: [ko-fi.com/aikellogg](https://ko-fi.com/aikellogg)
