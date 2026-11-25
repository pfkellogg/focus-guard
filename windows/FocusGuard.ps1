# Focus Guard for Windows: compiles FocusGuard.cs (next to this file) and runs it. Started by the VS Code extension
# with Windows PowerShell 5.1 (powershell.exe), which every Windows 10/11 has. No install, no admin.
#   powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File FocusGuard.ps1 [-Place auto|terminal|extension] [-SelfTest]
# SPDX-License-Identifier: MIT. Copyright (C) 2026 Patrick Kellogg (aikellogg.com)
param([string]$Place = "auto", [switch]$SelfTest)
$ErrorActionPreference = "Stop"
$src = Get-Content -Raw -Path (Join-Path $PSScriptRoot "FocusGuard.cs")
Add-Type -TypeDefinition $src -Language CSharp -ReferencedAssemblies @(
  "System.Windows.Forms", "System.Speech", "System.Management", "UIAutomationClient", "UIAutomationTypes", "WindowsBase")
exit [FocusGuardWin]::Run($Place, [bool]$SelfTest)
