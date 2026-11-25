// FocusGuard: when you start typing and the keys would go nowhere (no text box has focus, and VS Code, where
// Claude Code runs, isn't in front), it catches the keys, says so out loud, brings VS Code to the front and types
// them there, so nothing is lost. Typing into any real text box (Chrome, Gmail, Notes...) is never touched, nor are
// shortcuts (Cmd, Ctrl, Option).
// Needs Accessibility permission (System Settings > Privacy & Security > Accessibility > Focus Guard).
// SPDX-License-Identifier: MIT. Copyright (C) 2026 Patrick Kellogg (aikellogg.com)
import AppKit
import ApplicationServices

let targetBundle = "com.microsoft.VSCode"           // where Claude Code runs
// where in VS Code: "auto" (default: look each time), "terminal" or "extension".
// Force one with: defaults write com.aikellogg.focusguard place extension   (back to auto: defaults delete com.aikellogg.focusguard place)
let placeSetting = UserDefaults.standard.string(forKey: "place") ?? "auto"

// auto: Claude Code running in a VS Code terminal (a "claude" process with a terminal, started under VS Code) wins;
// else the Claude Code extension running; else the terminal
func currentPlace() -> String {
    if placeSetting == "terminal" || placeSetting == "extension" { return placeSetting }
    let ps = Process()
    ps.executableURL = URL(fileURLWithPath: "/bin/ps")
    ps.arguments = ["-axo", "pid=,ppid=,tty=,args="]
    let pipe = Pipe()
    ps.standardOutput = pipe
    guard (try? ps.run()) != nil else { return "terminal" }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    ps.waitUntilExit()
    var parent: [Int: Int] = [:], name: [Int: String] = [:]
    var terminalClaude: [Int] = []
    var extensionRunning = false
    for line in String(decoding: data, as: UTF8.self).split(separator: "\n") {
        let f = line.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true).map(String.init)
        guard f.count >= 4, let pid = Int(f[0]), let ppid = Int(f[1]) else { continue }
        let args = f[3]                              // the command line (paths may have spaces)
        parent[pid] = ppid
        name[pid] = args
        if args.contains(".vscode/extensions/anthropic.claude-code") { extensionRunning = true }
        let prog = args.split(separator: " ").first.map(String.init) ?? ""
        if (prog == "claude" || prog.hasSuffix("/claude")) && f[2] != "??" { terminalClaude.append(pid) }
    }
    for pid in terminalClaude {                      // is it inside VS Code?
        var p = pid, hops = 0
        while let pp = parent[p], pp > 1, hops < 12 {
            if name[pp]?.contains("Visual Studio Code.app") == true { return "terminal" }
            p = pp; hops += 1
        }
    }
    return extensionRunning ? "extension" : "terminal"
}

// press ctrl+alt+shift+F19 (terminal) or F18 (extension): VS Code keybindings.json maps them to the focus commands
func focusClaudeInside() {
    let key: CGKeyCode = currentPlace() == "extension" ? 79 : 80      // F18, F19
    let src = CGEventSource(stateID: .hidSystemState)
    for down in [true, false] {
        if let e = CGEvent(keyboardEventSource: src, virtualKey: key, keyDown: down) {
            e.flags = [.maskControl, .maskAlternate, .maskShift]
            e.setIntegerValueField(.eventSourceUserData, value: 0x46474644)
            e.post(tap: .cghidEventTap)
        }
    }
}
let message = "Claude Code doesn't have focus. Click to stay here."
let graceSeconds = 4.0                              // a click within this long: stay where you are
// After a click to stay: quiet everywhere until you go back to VS Code yourself (clicking into it, its terminal or
// Claude Code). Then it watches again.
var resting = false
var warnedApp: String? = nil
let synth = NSSpeechSynthesizer()
var lastSpoken = Date.distantPast
var buffer: [String] = []                           // keys caught while moving focus
var moving = false
var tap: CFMachPort?

func frontBundle() -> String? { NSWorkspace.shared.frontmostApplication?.bundleIdentifier }

// With several VS Code windows: the one you last typed into is where Claude Code is brought back (not just the one
// macOS used last). Its title, read when a key goes to VS Code.
var lastWindowTitle: String?

func vscodeApp() -> AXUIElement? {
    guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: targetBundle).first else { return nil }
    return AXUIElementCreateApplication(app.processIdentifier)
}

func focusedWindowTitle() -> String? {
    guard let app = vscodeApp() else { return nil }
    var w: AnyObject?
    guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &w) == .success, let win = w else { return nil }
    var title: AnyObject?
    AXUIElementCopyAttributeValue(win as! AXUIElement, kAXTitleAttribute as CFString, &title)
    return title as? String
}

func raiseWindow(titled title: String) {
    guard let app = vscodeApp() else { return }
    var ws: AnyObject?
    guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &ws) == .success,
          let wins = ws as? [AXUIElement] else { return }
    for w in wins {
        var t: AnyObject?
        AXUIElementCopyAttributeValue(w, kAXTitleAttribute as CFString, &t)
        if (t as? String) == title {
            AXUIElementSetAttributeValue(w, kAXMainAttribute as CFString, kCFBooleanTrue)
            AXUIElementPerformAction(w, kAXRaiseAction as CFString)
            return
        }
    }
}

// Is a text-entry element focused in the front app? (a field, a text area, an editable web field, a terminal)
func textFocused() -> Bool {
    let sys = AXUIElementCreateSystemWide()
    var focused: AnyObject?
    guard AXUIElementCopyAttributeValue(sys, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
          let el = focused else { return false }
    let e = el as! AXUIElement
    var role: AnyObject?
    AXUIElementCopyAttributeValue(e, kAXRoleAttribute as CFString, &role)
    let r = role as? String ?? ""
    if ["AXTextField", "AXTextArea", "AXComboBox", "AXSearchField", "AXSecureTextField"].contains(r) { return true }
    var settable: DarwinBoolean = false
    if AXUIElementIsAttributeSettable(e, kAXValueAttribute as CFString, &settable) == .success, settable.boolValue {
        return true                                  // (an editable web field, a custom text view)
    }
    var editable: AnyObject?                         // Chrome/Electron: contenteditable areas
    if AXUIElementCopyAttributeValue(e, "AXEditableAncestor" as CFString, &editable) == .success, editable != nil {
        return true
    }
    return false
}

func typeText(_ s: String) {
    let src = CGEventSource(stateID: .hidSystemState)
    for ch in s.utf16 {
        var c = ch
        if let down = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: true),
           let up = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: false) {
            for e in [down, up] {                    // plain letters: no modifier left over, marked as ours
                e.flags = []
                e.setIntegerValueField(.eventSourceUserData, value: 0x46474644)
            }
            down.keyboardSetUnicodeString(stringLength: 1, unicodeString: &c)
            up.keyboardSetUnicodeString(stringLength: 1, unicodeString: &c)
            down.post(tap: .cghidEventTap)
            up.post(tap: .cghidEventTap)
        }
    }
}

var pendingID = 0                                   // the current warning (a click cancels it)
var warning = false                                 // true only while it waits for a click

func warnThenMove() {
    if Date().timeIntervalSince(lastSpoken) > 4 {
        lastSpoken = Date()
        synth.startSpeaking(message)
    }
    pendingID += 1
    warning = true
    warnedApp = frontBundle()
    let id = pendingID
    DispatchQueue.main.asyncAfter(deadline: .now() + graceSeconds) {
        if moving && warning && id == pendingID { warning = false; moveFocus() }   // no click: move
    }
}

func stayHere() {                                    // a click while warned: stay, quiet until you go back to VS Code
    pendingID += 1
    warning = false
    moving = false
    buffer.removeAll()
    resting = true
    synth.stopSpeaking()
    synth.startSpeaking("Staying here.")
}

func moveFocus() {
    if let app = NSRunningApplication.runningApplications(withBundleIdentifier: targetBundle).first {
        app.activate()
        if let t = lastWindowTitle { raiseWindow(titled: t) }   // the window you were typing in
    } else {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: targetBundle) {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
        if frontBundle() == targetBundle { focusClaudeInside() }
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
        moving = false
        let text = buffer.joined()
        buffer.removeAll()
        if frontBundle() == targetBundle, !text.isEmpty { typeText(text) }
    }
}

let callback: CGEventTapCallBack = { _, type, event, _ in
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let t = tap { CGEvent.tapEnable(tap: t, enable: true) }
        return Unmanaged.passUnretained(event)
    }
    if type == .leftMouseDown || type == .rightMouseDown || type == .otherMouseDown {
        if moving && warning { DispatchQueue.main.async { stayHere() } }
        return Unmanaged.passUnretained(event)        // the click itself goes through, always
    }
    guard type == .keyDown else { return Unmanaged.passUnretained(event) }
    if event.getIntegerValueField(.eventSourceUserData) == 0x46474644 { return Unmanaged.passUnretained(event) }
    let flags = event.flags
    if flags.contains(.maskCommand) || flags.contains(.maskControl) || flags.contains(.maskAlternate) {
        return Unmanaged.passUnretained(event)        // shortcuts: never
    }
    if moving {                                      // still moving: keep collecting
        if let s = NSEvent(cgEvent: event)?.characters { buffer.append(s) }
        return nil
    }
    if frontBundle() == targetBundle {
        DispatchQueue.main.async { if let t = focusedWindowTitle() { lastWindowTitle = t } }
        return Unmanaged.passUnretained(event)
    }
    if textFocused() { return Unmanaged.passUnretained(event) }
    if resting { return Unmanaged.passUnretained(event) }   // you chose to stay: quiet until you go back to VS Code
    // typing into nothing: catch it, say so, move to Claude Code
    if let s = NSEvent(cgEvent: event)?.characters, !s.isEmpty,
       let u = s.unicodeScalars.first, !CharacterSet.controlCharacters.contains(u) || s == "\r" {
        buffer.append(s == "\r" ? "" : s)
    }
    moving = true
    DispatchQueue.main.async { warnThenMove() }
    return nil
}

// status for the VS Code extension: ~/Library/Application Support/Focus Guard/status ("waiting-for-permission" / "on")
let statusDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Focus Guard")
func writeStatus(_ s: String) {
    try? FileManager.default.createDirectory(at: statusDir, withIntermediateDirectories: true)
    try? s.write(to: statusDir.appendingPathComponent("status"), atomically: true, encoding: .utf8)
}

// no permission yet: ask once (out loud too), then wait for the switch instead of quitting
let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
if !AXIsProcessTrustedWithOptions(opts) {
    writeStatus("waiting-for-permission")
    print("Focus Guard needs Accessibility permission: System Settings > Privacy & Security > Accessibility")
    synth.startSpeaking("Focus Guard needs one switch turned on, in Privacy and Security, Accessibility.")
    while !AXIsProcessTrusted() {
        RunLoop.current.run(until: Date().addingTimeInterval(2))
    }
    synth.startSpeaking("Focus Guard is on.")
}
// You went back to VS Code yourself: watching again
NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil,
                                                  queue: .main) { n in
    let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
    if app?.bundleIdentifier == targetBundle { resting = false }
}
let mask = CGEventMask(1 << CGEventType.keyDown.rawValue) | CGEventMask(1 << CGEventType.leftMouseDown.rawValue)
    | CGEventMask(1 << CGEventType.rightMouseDown.rawValue) | CGEventMask(1 << CGEventType.otherMouseDown.rawValue)
tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                        eventsOfInterest: mask, callback: callback, userInfo: nil)
guard let t = tap else {
    writeStatus("waiting-for-permission")
    print("Focus Guard: couldn't watch the keyboard (permission). Turn the switch off and on, then start it again.")
    exit(1)
}
writeStatus("on")
let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, t, 0)
CFRunLoopAddSource(CFRunLoopGetCurrent(), src, .commonModes)
CGEvent.tapEnable(tap: t, enable: true)
print("Focus Guard is on: typing into nothing moves you to Claude Code.")
NSApplication.shared.setActivationPolicy(.accessory)
NSApplication.shared.run()
