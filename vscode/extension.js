// Focus Guard for VS Code: starts the Focus Guard helper (macOS: a small app built on this Mac from its source;
// Windows: a PowerShell-compiled helper) and contributes the two shortcuts it presses to put the cursor in Claude Code.
// SPDX-License-Identifier: MIT. Copyright (C) 2026 Patrick Kellogg (aikellogg.com)
const vscode = require("vscode");
const cp = require("child_process");
const fs = require("fs");
const os = require("os");
const path = require("path");

const BUNDLE = "com.aikellogg.focusguard";
let out;
let extPath;

const cfg = () => vscode.workspace.getConfiguration("focusGuard");
const log = (s) => out && out.appendLine(`[${new Date().toLocaleTimeString()}] ${s}`);
const run = (cmd, args, opts = {}) =>
  new Promise((resolve) => cp.execFile(cmd, args, { maxBuffer: 1 << 20, ...opts }, (err, stdout, stderr) =>
    resolve({ ok: !err, code: err ? err.code : 0, out: String(stdout || ""), err: String(stderr || "") })));
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// ---------- macOS
const MAC_STATUS = path.join(os.homedir(), "Library/Application Support/Focus Guard/status");

async function macAppVersion(app) {
  const r = await run("/usr/bin/defaults", ["read", path.join(app, "Contents/Info"), "CFBundleShortVersionString"]);
  return r.ok ? r.out.trim() : "";
}

async function macBundledVersion() {
  const r = await run("/usr/bin/defaults", ["read", path.join(extPath, "mac/Info"), "CFBundleShortVersionString"]);
  return r.ok ? r.out.trim() : "";
}

// An app installed with install.sh (in /Applications) is used as it is; otherwise build ours in ~/Applications
async function macApp() {
  const system = "/Applications/Focus Guard.app";
  if (fs.existsSync(path.join(system, "Contents/MacOS/FocusGuard"))) return system;
  const mine = path.join(os.homedir(), "Applications/Focus Guard.app");
  const want = await macBundledVersion();
  if (fs.existsSync(path.join(mine, "Contents/MacOS/FocusGuard")) && (await macAppVersion(mine)) === want) return mine;
  return await macBuild(mine);
}

async function macBuild(app) {
  const swiftc = await run("/usr/bin/xcrun", ["--find", "swiftc"]);
  if (!swiftc.ok) {
    const pick = await vscode.window.showWarningMessage(
      "Focus Guard is built on your Mac, so macOS doesn't block it. That needs Apple's free Command Line Tools.",
      "Install them");
    if (pick) cp.spawn("/usr/bin/xcode-select", ["--install"], { detached: true, stdio: "ignore" }).unref();
    log("swiftc not found: asked to install the Command Line Tools");
    return null;
  }
  return await vscode.window.withProgress(
    { location: vscode.ProgressLocation.Notification, title: "Focus Guard: building for this Mac (once, about 30 seconds)" },
    async () => {
      const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "focusguard-"));
      const bin = path.join(tmp, "FocusGuard");
      const b = await run("/usr/bin/xcrun", ["swiftc", "-O", "-o", bin, path.join(extPath, "mac/FocusGuard.swift")]);
      if (!b.ok) { log("build failed:\n" + b.err); vscode.window.showErrorMessage("Focus Guard couldn't be built. See Output > Focus Guard."); return null; }
      await run("/usr/bin/pkill", ["-x", "FocusGuard"]);
      fs.rmSync(app, { recursive: true, force: true });
      fs.mkdirSync(path.join(app, "Contents/MacOS"), { recursive: true });
      fs.copyFileSync(path.join(extPath, "mac/Info.plist"), path.join(app, "Contents/Info.plist"));
      fs.copyFileSync(bin, path.join(app, "Contents/MacOS/FocusGuard"));
      fs.chmodSync(path.join(app, "Contents/MacOS/FocusGuard"), 0o755);
      await run("/usr/bin/codesign", ["--force", "--deep", "-s", "-", app]);
      // a new build is a new app to macOS: clear any old switch so it is asked for fresh
      await run("/usr/bin/tccutil", ["reset", "Accessibility", BUNDLE]);
      fs.rmSync(tmp, { recursive: true, force: true });
      log("built " + app);
      return app;
    });
}

async function macStart(restart) {
  const place = cfg().get("place", "auto");
  if (place === "auto") await run("/usr/bin/defaults", ["delete", BUNDLE, "place"]);
  else await run("/usr/bin/defaults", ["write", BUNDLE, "place", place]);
  const app = await macApp();
  if (!app) return;
  const running = (await run("/usr/bin/pgrep", ["-x", "FocusGuard"])).ok;
  if (running && !restart) { log("already running"); return; }
  if (running) { await run("/usr/bin/pkill", ["-x", "FocusGuard"]); await sleep(500); }
  try { fs.rmSync(MAC_STATUS, { force: true }); } catch (e) { /* none */ }
  await run("/usr/bin/open", ["-a", app]);
  log("started " + app + " (place: " + place + ")");
  await sleep(3000);
  const status = fs.existsSync(MAC_STATUS) ? fs.readFileSync(MAC_STATUS, "utf8").trim() : "";
  if (status === "waiting-for-permission") {
    const pick = await vscode.window.showWarningMessage(
      "Focus Guard needs one switch: System Settings > Privacy & Security > Accessibility > Focus Guard. It starts working the moment you turn it on.",
      "Open Settings");
    if (pick) macOpenAccessibility();
  }
}

function macOpenAccessibility() {
  cp.spawn("/usr/bin/open", ["x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"],
    { detached: true, stdio: "ignore" }).unref();
}

// ---------- Windows
const WIN_PS = path.join(process.env.SystemRoot || "C:\\Windows", "System32\\WindowsPowerShell\\v1.0\\powershell.exe");

async function winStop() {
  await run(WIN_PS, ["-NoProfile", "-Command",
    "Get-CimInstance Win32_Process -Filter \"CommandLine like '%FocusGuard.ps1%'\" | Where-Object { $_.ProcessId -ne $PID } | Invoke-CimMethod -MethodName Terminate | Out-Null"]);
}

async function winStart(restart) {
  if (restart) await winStop();
  const script = path.join(extPath, "win", "FocusGuard.ps1");
  const p = cp.spawn(WIN_PS, ["-NoProfile", "-ExecutionPolicy", "Bypass", "-WindowStyle", "Hidden", "-File", script,
    "-Place", cfg().get("place", "auto")], { windowsHide: true, detached: true, stdio: ["ignore", "pipe", "pipe"] });
  p.stdout.on("data", (d) => log(String(d).trim()));
  p.stderr.on("data", (d) => log(String(d).trim()));
  p.on("exit", (code) => {
    log("helper exited (" + code + ")");
    if (code) vscode.window.showErrorMessage("Focus Guard stopped. See Output > Focus Guard.");
  });
  p.unref();
  log("started the Windows helper");
}

// ---------- both
async function start(restart) {
  try {
    if (process.platform === "darwin") await macStart(restart);
    else if (process.platform === "win32") await winStart(restart);
    else log("Focus Guard works on macOS and Windows.");
  } catch (e) { log("start failed: " + (e && e.stack || e)); }
}

async function stop() {
  if (process.platform === "darwin") await run("/usr/bin/pkill", ["-x", "FocusGuard"]);
  else if (process.platform === "win32") await winStop();
  log("stopped");
}

function activate(ctx) {
  extPath = ctx.extensionPath;
  out = vscode.window.createOutputChannel("Focus Guard");
  ctx.subscriptions.push(out,
    vscode.commands.registerCommand("focusGuard.start", () => start(true)),
    vscode.commands.registerCommand("focusGuard.stop", stop),
    vscode.commands.registerCommand("focusGuard.openAccessibility", macOpenAccessibility),
    vscode.workspace.onDidChangeConfiguration(async (e) => {
      if (!e.affectsConfiguration("focusGuard")) return;
      if (cfg().get("enabled", true)) await start(true); else await stop();
    }));
  if (cfg().get("enabled", true)) start(false);
}

function deactivate() { /* the helper keeps running: it guards the whole desktop, not one VS Code window */ }

module.exports = { activate, deactivate };
