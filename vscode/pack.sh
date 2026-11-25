#!/bin/bash
# Copies the helpers' sources into the extension and packages it: focus-guard-<version>.vsix
set -euo pipefail
cd "$(dirname "$0")"
rm -rf mac win && mkdir -p mac win
cp ../FocusGuard.swift ../Info.plist mac/
cp ../windows/FocusGuard.ps1 ../windows/FocusGuard.cs win/
npx --yes @vscode/vsce@latest package --allow-missing-repository 2>&1 | tail -3
