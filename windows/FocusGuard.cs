// Focus Guard for Windows: when you start typing and the keys would go nowhere (VS Code, where Claude Code runs,
// isn't in front and no text box has focus), it catches the keys, says "Claude Code doesn't have focus. Click to stay
// here.", and waits 4 seconds: a mouse click keeps you where you are; otherwise it brings VS Code forward, puts the
// cursor in Claude Code (ctrl+alt+shift+F19 terminal / F18 extension, contributed by the VS Code extension) and types
// the keys there. Typing into a real text box and shortcuts (Ctrl, Alt, Win) are never touched. Return is dropped.
// Compiled at start by FocusGuard.ps1 (PowerShell Add-Type); no install, no admin.
// SPDX-License-Identifier: MIT. Copyright (C) 2026 Patrick Kellogg (aikellogg.com)
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Management;
using System.Runtime.InteropServices;
using System.Speech.Synthesis;
using System.Text;
using System.Threading;
using System.Windows.Automation;
using System.Windows.Forms;

public static class FocusGuardWin
{
    const int WH_KEYBOARD_LL = 13, WH_MOUSE_LL = 14;
    const int WM_KEYDOWN = 0x100, WM_SYSKEYDOWN = 0x104;
    const int WM_LBUTTONDOWN = 0x201, WM_RBUTTONDOWN = 0x204, WM_MBUTTONDOWN = 0x207, WM_XBUTTONDOWN = 0x20B;
    const uint LLKHF_INJECTED = 0x10;
    const uint INPUT_KEYBOARD = 1, KEYEVENTF_KEYUP = 2, KEYEVENTF_UNICODE = 4;
    const string Message = "Claude Code doesn't have focus. Click to stay here.";
    const int GraceMs = 4000;

    delegate IntPtr HookProc(int n, IntPtr w, IntPtr l);

    [StructLayout(LayoutKind.Sequential)]
    struct KBDLLHOOKSTRUCT { public uint vkCode, scanCode, flags, time; public IntPtr extra; }
    [StructLayout(LayoutKind.Sequential)]
    struct MOUSEINPUT { public int dx, dy; public uint mouseData, dwFlags, time; public IntPtr extra; }
    [StructLayout(LayoutKind.Sequential)]
    struct KEYBDINPUT { public ushort wVk, wScan; public uint dwFlags, time; public IntPtr extra; }
    [StructLayout(LayoutKind.Explicit)]
    struct InputUnion { [FieldOffset(0)] public MOUSEINPUT mi; [FieldOffset(0)] public KEYBDINPUT ki; }
    [StructLayout(LayoutKind.Sequential)]
    struct INPUT { public uint type; public InputUnion u; }
    [StructLayout(LayoutKind.Sequential)]
    struct RECT { public int l, t, r, b; }
    [StructLayout(LayoutKind.Sequential)]
    struct GUITHREADINFO { public int cbSize, flags; public IntPtr hwndActive, hwndFocus, hwndCapture, hwndMenuOwner, hwndMoveSize, hwndCaret; public RECT rcCaret; }

    [DllImport("user32.dll", SetLastError = true)] static extern IntPtr SetWindowsHookEx(int id, HookProc p, IntPtr mod, uint tid);
    [DllImport("user32.dll")] static extern IntPtr CallNextHookEx(IntPtr h, int n, IntPtr w, IntPtr l);
    [DllImport("kernel32.dll")] static extern IntPtr GetModuleHandle(string name);
    [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
    [DllImport("user32.dll")] static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] static extern bool ShowWindow(IntPtr h, int cmd);
    [DllImport("user32.dll")] static extern bool IsIconic(IntPtr h);
    [DllImport("user32.dll")] static extern short GetAsyncKeyState(int vk);
    [DllImport("user32.dll")] static extern short GetKeyState(int vk);
    [DllImport("user32.dll")] static extern int ToUnicode(uint vk, uint scan, byte[] state, StringBuilder buf, int size, uint flags);
    [DllImport("user32.dll")] static extern uint SendInput(uint n, INPUT[] inputs, int size);
    [DllImport("user32.dll")] static extern bool GetGUIThreadInfo(uint tid, ref GUITHREADINFO info);

    static HookProc kbProc, mouseProc;              // kept alive (the hooks hold only a pointer)
    static IntPtr kbHook, mouseHook;
    static readonly SpeechSynthesizer synth = new SpeechSynthesizer();
    static DateTime lastSpoken = DateTime.MinValue;
    static readonly StringBuilder buffer = new StringBuilder();
    static bool moving, warning;
    static int pendingId;
    static readonly HashSet<string> stayApps = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
    static DateTime stayUntil = DateTime.MinValue;
    static string warnedApp;
    static string placeSetting = "auto";
    static volatile bool textFocusedCache;          // kept fresh by a background thread (UI Automation can be slow)
    static volatile string frontCache = "";
    static SynchronizationContext ui;

    // ---------- the front app and whether a text box has focus
    static string FrontProcess()
    {
        try
        {
            uint pid;
            GetWindowThreadProcessId(GetForegroundWindow(), out pid);
            return Process.GetProcessById((int)pid).ProcessName;
        }
        catch { return ""; }
    }

    static bool IsVSCode(string name) { return name.Equals("Code", StringComparison.OrdinalIgnoreCase); }

    static bool ComputeTextFocused()
    {
        try
        {
            IntPtr fg = GetForegroundWindow();
            uint pid;
            uint tid = GetWindowThreadProcessId(fg, out pid);
            var gi = new GUITHREADINFO();
            gi.cbSize = Marshal.SizeOf(gi);
            if (GetGUIThreadInfo(tid, ref gi) && gi.hwndCaret != IntPtr.Zero) return true;   // a blinking caret
            var el = AutomationElement.FocusedElement;
            if (el == null) return false;
            var ct = el.Current.ControlType;
            object vp;
            if (el.TryGetCurrentPattern(ValuePattern.Pattern, out vp))
                return !((ValuePattern)vp).Current.IsReadOnly;
            return ct == ControlType.Edit;
        }
        catch { return false; }
    }

    static void Watcher()
    {
        while (true)
        {
            frontCache = FrontProcess();
            textFocusedCache = IsVSCode(frontCache) || ComputeTextFocused();
            Thread.Sleep(120);
        }
    }

    // ---------- where Claude Code runs inside VS Code: a terminal (claude not under .vscode\extensions) or the extension
    static string CurrentPlace()
    {
        if (placeSetting == "terminal" || placeSetting == "extension") return placeSetting;
        try
        {
            var parent = new Dictionary<uint, uint>();
            var name = new Dictionary<uint, string>();
            var cmd = new Dictionary<uint, string>();
            using (var s = new ManagementObjectSearcher("SELECT ProcessId, ParentProcessId, Name, CommandLine FROM Win32_Process"))
                foreach (ManagementObject o in s.Get())
                {
                    uint id = (uint)o["ProcessId"];
                    parent[id] = (uint)o["ParentProcessId"];
                    name[id] = (o["Name"] as string) ?? "";
                    cmd[id] = (o["CommandLine"] as string) ?? "";
                }
            bool extension = false;
            foreach (var id in name.Keys)
            {
                string c = cmd[id].Replace('/', '\\');
                bool inExt = c.IndexOf(".vscode\\extensions\\anthropic.claude-code", StringComparison.OrdinalIgnoreCase) >= 0;
                if (inExt) { extension = true; continue; }
                bool isClaude = name[id].Equals("claude.exe", StringComparison.OrdinalIgnoreCase)
                    || c.IndexOf("@anthropic-ai\\claude-code", StringComparison.OrdinalIgnoreCase) >= 0;
                if (!isClaude) continue;
                uint p = id;
                for (int hops = 0; hops < 12 && parent.ContainsKey(p); hops++)
                {
                    p = parent[p];
                    string n;
                    if (name.TryGetValue(p, out n) && n.Equals("Code.exe", StringComparison.OrdinalIgnoreCase)) return "terminal";
                }
            }
            return extension ? "extension" : "terminal";
        }
        catch { return "terminal"; }
    }

    // ---------- sending keys
    static INPUT Key(ushort vk, ushort scan, uint flags)
    {
        var i = new INPUT { type = INPUT_KEYBOARD };
        i.u.ki = new KEYBDINPUT { wVk = vk, wScan = scan, dwFlags = flags };
        return i;
    }

    static void Send(params INPUT[] keys) { SendInput((uint)keys.Length, keys, Marshal.SizeOf(typeof(INPUT))); }

    static void TypeText(string s)
    {
        foreach (char ch in s)
            Send(Key(0, ch, KEYEVENTF_UNICODE), Key(0, ch, KEYEVENTF_UNICODE | KEYEVENTF_KEYUP));
    }

    static void FocusClaudeInside()
    {
        ushort fkey = (ushort)(CurrentPlace() == "extension" ? 0x81 : 0x82);   // F18 / F19
        const ushort CTRL = 0x11, ALT = 0x12, SHIFT = 0x10;
        Send(Key(CTRL, 0, 0), Key(ALT, 0, 0), Key(SHIFT, 0, 0), Key(fkey, 0, 0),
             Key(fkey, 0, KEYEVENTF_KEYUP), Key(SHIFT, 0, KEYEVENTF_KEYUP), Key(ALT, 0, KEYEVENTF_KEYUP), Key(CTRL, 0, KEYEVENTF_KEYUP));
    }

    static IntPtr VSCodeWindow()
    {
        foreach (var p in Process.GetProcessesByName("Code"))
            if (p.MainWindowHandle != IntPtr.Zero) return p.MainWindowHandle;
        return IntPtr.Zero;
    }

    static void After(int ms, Action a)
    {
        var t = new System.Windows.Forms.Timer { Interval = Math.Max(1, ms) };
        t.Tick += (s, e) => { t.Stop(); t.Dispose(); a(); };
        t.Start();
    }

    // ---------- warn, stay, move
    static void Speak(string s) { synth.SpeakAsyncCancelAll(); synth.SpeakAsync(s); }

    static void WarnThenMove()
    {
        if ((DateTime.Now - lastSpoken).TotalSeconds > 4) { lastSpoken = DateTime.Now; Speak(Message); }
        pendingId++;
        warning = true;
        warnedApp = frontCache;
        int id = pendingId;
        After(GraceMs, () => { if (moving && warning && id == pendingId) { warning = false; MoveFocus(); } });
    }

    static void StayHere()
    {
        pendingId++;
        warning = false;
        moving = false;
        buffer.Clear();
        stayApps.Clear();
        if (!string.IsNullOrEmpty(warnedApp)) stayApps.Add(warnedApp);
        After(400, () => stayApps.Add(FrontProcess()));   // the window the click landed on, too
        stayUntil = DateTime.Now.AddSeconds(60);
        Speak("Staying here.");
    }

    static void MoveFocus()
    {
        IntPtr h = VSCodeWindow();
        if (h == IntPtr.Zero) { moving = false; buffer.Clear(); Speak("VS Code isn't open."); return; }
        if (IsIconic(h)) ShowWindow(h, 9);
        Send(Key(0x12, 0, 0), Key(0x12, 0, KEYEVENTF_KEYUP));   // an Alt tap lets a background app take the front
        SetForegroundWindow(h);
        After(500, () => { if (IsVSCode(FrontProcess())) FocusClaudeInside(); });
        After(900, () =>
        {
            moving = false;
            string text = buffer.ToString();
            buffer.Clear();
            if (IsVSCode(FrontProcess()) && text.Length > 0) TypeText(text);
        });
    }

    // ---------- the hooks
    static string CharsOf(KBDLLHOOKSTRUCT k)
    {
        var state = new byte[256];
        if ((GetAsyncKeyState(0x10) & 0x8000) != 0) state[0x10] = 0x80;
        if ((GetKeyState(0x14) & 1) != 0) state[0x14] = 1;
        var sb = new StringBuilder(8);
        int n = ToUnicode(k.vkCode, k.scanCode, state, sb, sb.Capacity, 4);   // 4: don't disturb dead keys
        return n > 0 ? sb.ToString(0, n) : "";
    }

    static IntPtr KeyboardHook(int n, IntPtr w, IntPtr l)
    {
        if (n < 0) return CallNextHookEx(kbHook, n, w, l);
        int msg = w.ToInt32();
        if (msg != WM_KEYDOWN && msg != WM_SYSKEYDOWN) return CallNextHookEx(kbHook, n, w, l);
        var k = (KBDLLHOOKSTRUCT)Marshal.PtrToStructure(l, typeof(KBDLLHOOKSTRUCT));
        if ((k.flags & LLKHF_INJECTED) != 0) return CallNextHookEx(kbHook, n, w, l);           // ours (and other tools')
        if ((GetAsyncKeyState(0x11) & 0x8000) != 0 || (GetAsyncKeyState(0x12) & 0x8000) != 0
            || (GetAsyncKeyState(0x5B) & 0x8000) != 0 || (GetAsyncKeyState(0x5C) & 0x8000) != 0)
            return CallNextHookEx(kbHook, n, w, l);                                         // shortcuts: never
        if (k.vkCode == 0x10 || k.vkCode == 0xA0 || k.vkCode == 0xA1 || k.vkCode == 0x14)
            return CallNextHookEx(kbHook, n, w, l);                                         // Shift, Caps Lock alone
        if (moving) { buffer.Append(CharsOf(k)); return (IntPtr)1; }
        string front = frontCache;
        if (IsVSCode(front) || textFocusedCache) return CallNextHookEx(kbHook, n, w, l);
        if (stayApps.Contains(front) && DateTime.Now < stayUntil) return CallNextHookEx(kbHook, n, w, l);
        string s = CharsOf(k);
        if (k.vkCode != 0x0D && s.Length > 0 && !char.IsControl(s[0])) buffer.Append(s);       // Return dropped
        moving = true;
        ui.Post(_ => WarnThenMove(), null);
        return (IntPtr)1;
    }

    static IntPtr MouseHook(int n, IntPtr w, IntPtr l)
    {
        if (n >= 0)
        {
            int msg = w.ToInt32();
            if ((msg == WM_LBUTTONDOWN || msg == WM_RBUTTONDOWN || msg == WM_MBUTTONDOWN || msg == WM_XBUTTONDOWN) && moving && warning)
                ui.Post(_ => StayHere(), null);
        }
        return CallNextHookEx(mouseHook, n, w, l);                                          // the click goes through
    }

    // selfTest: compile + the detectors, then exit (for CI)
    public static int Run(string place, bool selfTest)
    {
        placeSetting = string.IsNullOrEmpty(place) ? "auto" : place.ToLowerInvariant();
        if (selfTest)
        {
            Console.WriteLine("front=" + FrontProcess() + " text=" + ComputeTextFocused() + " place=" + CurrentPlace());
            return 0;
        }
        bool created;
        using (var mutex = new Mutex(true, "Local\\FocusGuardWin", out created))
        {
            if (!created) { Console.WriteLine("Focus Guard is already running."); return 0; }
            Application.EnableVisualStyles();
            var ctx = new WindowsFormsSynchronizationContext();
            SynchronizationContext.SetSynchronizationContext(ctx);
            ui = ctx;
            new Thread(Watcher) { IsBackground = true }.Start();
            kbProc = KeyboardHook;
            mouseProc = MouseHook;
            IntPtr mod = GetModuleHandle(null);
            kbHook = SetWindowsHookEx(WH_KEYBOARD_LL, kbProc, mod, 0);
            mouseHook = SetWindowsHookEx(WH_MOUSE_LL, mouseProc, mod, 0);
            if (kbHook == IntPtr.Zero) { Console.WriteLine("Focus Guard: couldn't watch the keyboard."); return 1; }
            // quit when VS Code has been closed for a while (the extension starts it again)
            var idle = new System.Windows.Forms.Timer { Interval = 5000 };
            int noCode = 0;
            idle.Tick += (s, e) => { noCode = Process.GetProcessesByName("Code").Length == 0 ? noCode + 1 : 0; if (noCode >= 6) Application.Exit(); };
            idle.Start();
            Console.WriteLine("Focus Guard is on: typing into nothing moves you to Claude Code.");
            Application.Run();
            return 0;
        }
    }
}
